program MkHx;

{ Build an HX-DOS PE32 image out of the DPMIST32 stub, the runtime blob and the
  generated program code.

    mkhx <stub.bin> <blob.bin> <code.bin> <out.exe> [--base <base.bin>]

  The image layout is fixed, and everything in it other than four size fields
  is a constant:

    0000  the 512-byte MZ stub (DPMIST32.BIN), e_lfanew patched to 0x200
    0200  PE signature, file header, optional header, one section header
    0320  a single null import descriptor, in the header padding
    0400  .text: the runtime blob, then the generated code

  .text is one section, mapped read/write/execute. The runtime blob's addresses
  are all relative to the blob (see hxrtl.asm), so nothing in the image needs a
  relocation table and the section can simply grow with the generated code
  without moving anything the blob refers to.

  --base writes everything up to, but not including, the generated code, which
  is what btpc.pas embeds as a literal: the compiler then only has to append the
  code and patch SizeOfCode, SizeOfImage and the section's VirtualSize and
  SizeOfRawData. Those four are computed here from the sizes, the same way the
  compiler computes them, so the image this tool writes and the image the
  compiler writes are the same bytes for the same program.

  This tool used to be a Python script. It is a Pascal program now, built by the
  compiler it helps to build, so that a tree of this project is rebuilt with
  nothing but what is in it - and so that the tools are written in the language
  they are tools for. }

{ The runtime library is RTLDOS.PAS, and the compiler reads it before the first
  line of this file: there is no include for it here. }

const StubSize=512;        { the stub is copied whole, and has to be that long }
      HeadersEnd=800;      { 512 + 4 + 20 + 224 + 40: sig, file, optional, section }
      SizeOfHeaders=$400;  { the headers, rounded up to the file alignment }
      DescRva=800;         { the null import descriptor, inside the header padding }
      DescSize=20;
      TextRva=$1000;
      ImageBase=$400000;
      SectionAlignment=$1000;
      FileAlignment=$200;
      TextRaw=SizeOfHeaders;
      TailMax=512;         { one file alignment of padding, which is all there is }
      NameMax=250;         { what an argument is copied into, without its NUL }
      MaxFile=1048576;     { the largest file a tool here is handed }

{ A block of bytes. A character is four bytes here and a file is measured in
  characters: the host moves each byte of the file into a cell of its own, and
  writes each cell back out as one byte. A block that is to hold a whole file
  therefore has to be four times the file - and it is asked for that much, in
  ReadWhole below. The index is the cell, so element i holds byte i of the file,
  which is what makes the sizes in the rest of this file the sizes of the
  files. }
type TBytes=array[0..MaxFile] of char;
     PBytes=^TBytes;

var Stub,Blob,Code:PBytes;
    StubBase,BlobBase,CodeBase:integer;
    StubLen,BlobLen,CodeLen:integer;
    Header:array[1..SizeOfHeaders] of char;
    HeaderPos:integer;
    Tail:array[1..TailMax] of char;
    StubName,BlobName,CodeName:array[1..NameMax] of char;
    OutName,BaseName:array[1..NameMax] of char;
    FlagBase:array[1..4] of char;
    HaveBase:boolean;
    OutPath,BasePath:PChar;
    RawSize,TextLen,SizeOfImage,Total:integer;

{ ---------------------------------------------------------------------------
  The command line.

  The host's buffer holds one argument: asking for the next one overwrites it.
  A tool that needs five names at once therefore copies each into an array of
  its own, which is also the shape the file calls want - a run of characters
  ending at a NUL. The copying is ArgCopy, in the runtime library: it answers
  how many characters it copied, and a name that does not fit would otherwise
  go on to be opened as a shorter one. }

procedure Arg(i:integer; Dest:PChar);
var n:integer;
begin
 n:=ArgCopy(i,Dest,NameMax);
 if n>=NameMax then begin
  WriteLn('an argument is too long');
  Halt
 end
end;

{ Is argument i this flag? A flag is written with two leading dashes, and the
  argument has to end where the flag does: --base is the flag and --based is
  not. An argument that is not there is a zero address, which is not the flag
  either. The flag is compared cell by cell against a run of characters of its
  own, because there are no strings here to compare a literal in. }
function ArgIsFlag(i:integer; Flag:PChar; Count:integer):boolean;
var src:PChar;
    n:integer;
    Same:boolean;
begin
 Same:=false;
 src:=ParamStr(i);
 if src<>0 then begin
  if src^='-' then begin
   src:=src+4;
   if src^='-' then begin
    src:=src+4;
    n:=0;
    Same:=true;
    while (n<Count) and Same do begin
     if src^<>Flag^ then begin
      Same:=false
     end else begin
      src:=src+4;
      Flag:=Flag+4;
      n:=n+1
     end
    end
   end
  end
 end;
 if Same then begin
  if src^<>#0 then begin
   Same:=false
  end
 end;
 ArgIsFlag:=Same
end;

{ ---------------------------------------------------------------------------
  Files.

   A whole file into a block from the heap. The address is kept as an integer,
  because that is what GetMem answers and what FreeMem asks for, and the same
  bytes are named by a pointer to a character, which is what an index can be
  written against. Len is what came back: a file that cannot be opened stops the
  tool, there being no image to build out of it.

  Four bytes a byte, because the host expands what it reads into cells: a block
  asked for Size bytes would be written Size*4 into, which is the heap the next
  GetMem hands out. }
procedure ReadWhole(Name:PChar; var Base:integer; var Buf:PBytes; var Len:integer);
var f:TFile;
    Size,n:integer;
begin
 Base:=0;
 Len:=0;
 Reset(f,Name);
 if IOError<>0 then begin
  Write('Cannot open '); WriteStr(Name); WriteLn;
  Halt
 end;
 Size:=FileSize(f);
 if Size<0 then begin
  Size:=0
 end;
 if Size>0 then begin
  Base:=GetMem(Size*4+16);
  if Base=0 then begin
   WriteLn('Not enough memory');
   Halt
  end;
  Buf:=Base;
  BlockRead(f,Base,Size,n);
  Len:=n
 end;
 Close(f)
end;

{ ---------------------------------------------------------------------------
  The headers.

  Written field by field in the order the format lists them, which is the shape
  this file can be read in and corrected in. The size fields are written from
  the numbers computed below, and nothing else here depends on what is being
  linked. }
procedure PutByte(Value:integer);
begin
 Header[HeaderPos]:=chr(Value mod 256);
 HeaderPos:=HeaderPos+1
end;

procedure PutWord(Value:integer);
begin
 PutByte(Value mod 256);
 PutByte((Value div 256) mod 256)
end;

procedure PutInt(Value:integer);
begin
 PutWord(Value mod 65536);
 PutWord((Value div 65536) mod 65536)
end;

procedure BuildHeaders(RawSize,SizeOfImage:integer);
var i:integer;
begin
 FillChar(Addr(Header[1]),SizeOfHeaders,0);
 HeaderPos:=1;

 { The stub, which is the DOS part of the image: what DOS runs, and what reads
   e_lfanew and loads the PE image behind it. e_lfanew is 0x200, which is where
   the PE signature is written below. }
 for i:=0 to StubSize-1 do begin
  Header[i+1]:=Stub^[i]
 end;
 Header[$3C+1]:=#0; Header[$3D+1]:=#2; Header[$3E+1]:=#0; Header[$3F+1]:=#0;
 HeaderPos:=StubSize+1;

 Header[HeaderPos]:='P'; HeaderPos:=HeaderPos+1;
 Header[HeaderPos]:='E'; HeaderPos:=HeaderPos+1;
 PutByte(0);
 PutByte(0);

 { IMAGE_FILE_HEADER: i386, one section, no timestamp - which is what keeps a
   build byte-reproducible - no symbols, a 224-byte optional header, an
   executable 32-bit image with line numbers and local symbols stripped. }
 PutWord($14C);
 PutWord(1);
 PutInt(0);
 PutInt(0);
 PutInt(0);
 PutWord(224);
 PutWord($010E);

 { IMAGE_OPTIONAL_HEADER32 }
 PutWord($10B);                       { PE32 }
 PutByte(0); PutByte(0);              { linker version }
 PutInt(RawSize);                     { SizeOfCode }
 PutInt(0);                           { SizeOfInitializedData }
 PutInt(0);                           { SizeOfUninitializedData }
 PutInt(TextRva);                     { AddressOfEntryPoint }
 PutInt(TextRva);                     { BaseOfCode }
 PutInt(0);                           { BaseOfData }
 PutInt(ImageBase);
 PutInt(SectionAlignment);
 PutInt(FileAlignment);
 PutWord(4); PutWord(0);              { operating system version }
 PutWord(0); PutWord(0);              { image version }
 PutWord(4); PutWord(0);              { subsystem version }
 PutInt(0);                           { Win32VersionValue }
 PutInt(SizeOfImage);
 PutInt(SizeOfHeaders);
 PutInt(0);                           { CheckSum }
 PutWord(3);                          { Subsystem: console }
 PutWord(0);                          { DllCharacteristics }
 PutInt($100000); PutInt($1000);      { stack reserve and commit }
 PutInt($100000); PutInt($1000);      { heap reserve and commit }
 PutInt(0);                           { LoaderFlags }
 PutInt(16);                          { NumberOfRvaAndSizes }

 { The data directories. Only the import table is used, and it is empty - one
   null descriptor, because the image imports nothing and a loader that walks
   the directory expects a valid one. The descriptor is the last thing in the
   header, and what follows it is padding, which the clearing above left zero. }
 i:=0;
 while i<16 do begin
  if i=1 then begin
   PutInt(DescRva);
   PutInt(DescSize)
  end else begin
   PutInt(0);
   PutInt(0)
  end;
  i:=i+1
 end;

 { The section header. VirtualSize is the raw size, because the section is read
   out of the file whole. }
 Header[HeaderPos]:='.'; HeaderPos:=HeaderPos+1;
 Header[HeaderPos]:='t'; HeaderPos:=HeaderPos+1;
 Header[HeaderPos]:='e'; HeaderPos:=HeaderPos+1;
 Header[HeaderPos]:='x'; HeaderPos:=HeaderPos+1;
 Header[HeaderPos]:='t'; HeaderPos:=HeaderPos+1;
 PutByte(0); PutByte(0); PutByte(0);
 PutInt(RawSize);                     { VirtualSize }
 PutInt(TextRva);                     { VirtualAddress }
 PutInt(RawSize);                     { SizeOfRawData }
 PutInt(TextRaw);                     { PointerToRawData }
 PutInt(0);                           { PointerToRelocations }
 PutInt(0);                           { PointerToLinenumbers }
 PutWord(0);                          { NumberOfRelocations }
 PutWord(0);                          { NumberOfLinenumbers }
 PutInt($E0000020);                   { code, initialized data, readable, writable, executable }

 if HeaderPos<>HeadersEnd+1 then begin
  WriteLn('the header layout is off: ',HeaderPos-1:1,', expected ',HeadersEnd:1);
  Halt
 end
end;

{ The next multiple of Alignment at or above Value. }
function AlignUp(Value,Alignment:integer):integer;
var r:integer;
begin
 r:=Value mod Alignment;
 if r<>0 then begin
  r:=Value+(Alignment-r)
 end else begin
  r:=Value
 end;
 AlignUp:=r
end;

{ The image: the headers, the blob, the code, and the padding that fills the
  last file alignment - the loader reads the last section's raw data out of the
  file, so the file has to have it. }
procedure WriteImage(Name:PChar);
var f:TFile;
    n:integer;
begin
 ReWrite(f,Name);
 if IOError<>0 then begin
  Write('Cannot create '); WriteStr(Name); WriteLn;
  Halt
 end;
 BlockWrite(f,Addr(Header[1]),SizeOfHeaders,n);
 if BlobLen>0 then begin
  BlockWrite(f,BlobBase,BlobLen,n)
 end;
 if CodeLen>0 then begin
  BlockWrite(f,CodeBase,CodeLen,n)
 end;
 if RawSize>TextLen then begin
  BlockWrite(f,Addr(Tail[1]),RawSize-TextLen,n)
 end;
 Close(f)
end;

{ Everything up to the code, in one write: the headers and the blob. }
procedure WriteBase(Name:PChar);
var f:TFile;
    n:integer;
begin
 ReWrite(f,Name);
 if IOError<>0 then begin
  Write('Cannot create '); WriteStr(Name); WriteLn;
  Halt
 end;
 BlockWrite(f,Addr(Header[1]),SizeOfHeaders,n);
 if BlobLen>0 then begin
  BlockWrite(f,BlobBase,BlobLen,n)
 end;
 Close(f)
end;

begin
 if ParamCount<4 then begin
  WriteLn('usage: mkhx <stub.bin> <blob.bin> <code.bin> <out.exe> [--base <base.bin>]');
  Halt
 end;

 FlagBase[1]:='b'; FlagBase[2]:='a'; FlagBase[3]:='s'; FlagBase[4]:='e';

 Arg(1,Addr(StubName[1]));
 Arg(2,Addr(BlobName[1]));
 Arg(3,Addr(CodeName[1]));
 Arg(4,Addr(OutName[1]));
 OutPath:=Addr(OutName[1]);

 HaveBase:=false;
 BaseName[1]:=#0;
 BasePath:=Addr(BaseName[1]);
 if ParamCount>=5 then begin
  if ArgIsFlag(5,Addr(FlagBase[1]),4) then begin
   if ParamCount>=6 then begin
    Arg(6,Addr(BaseName[1]));
    HaveBase:=true
   end
  end
 end;

 ReadWhole(Addr(StubName[1]),StubBase,Stub,StubLen);
 if StubLen<>StubSize then begin
  WriteLn('the stub must be exactly ',StubSize:1,' bytes, got ',StubLen:1);
  Halt
 end;
 ReadWhole(Addr(BlobName[1]),BlobBase,Blob,BlobLen);
 ReadWhole(Addr(CodeName[1]),CodeBase,Code,CodeLen);

 { .text is the blob and the code, rounded up to the file alignment; the image
   is that size rounded up to the section alignment, plus the headers. }
 TextLen:=BlobLen+CodeLen;
 RawSize:=AlignUp(TextLen,FileAlignment);
 SizeOfImage:=AlignUp(RawSize,SectionAlignment)+SizeOfHeaders;

 FillChar(Addr(Tail[1]),TailMax,0);
 BuildHeaders(RawSize,SizeOfImage);

 WriteImage(OutPath);
 if HaveBase then begin
  WriteBase(BasePath)
 end;

 Total:=SizeOfHeaders+RawSize;
 WriteStr(OutPath);
 Write(': blob ',BlobLen:1,' + code ',CodeLen:1,' -> ',Total:1,' bytes (');
 Write(SizeOfHeaders:1,' before the code)');
 WriteLn
end.
