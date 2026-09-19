program MkBase;

{ Splice the constant part of the HX-DOS image into btpc.pas.

    mkbase <hxbase.bin> <btpc.pas>

  Every HX-DOS image this compiler emits is the same bytes up to the generated
  code: the DPMIST32 stub, the PE headers and the runtime blob. Only four header
  fields move (see AssembleAndLink), so the constant part is embedded in the
  compiler as a literal instead of being built at run time.

  hxbase.bin is what `mkhx --base` writes: the headers followed by the runtime
  blob. It goes into btpc.pas between two markers, as the OutputCodeString calls
  the compiler's own emit machinery expects, and its size replaces the HXBaseSize
  constant. Both markers and the constant are in the file; running this again
  after rebuilding the blob updates them in place.

  The literal is chunks of 255 characters because that is the width of
  OutputCodeString's parameter, so the last chunk is padded - with NOPs, which
  cost nothing because OutputCodeDataSize is set back to the real size before any
  generated code is appended over them.

  The file is read whole into memory and written back whole, because the part
  being replaced is in the middle of it and the replacement is not the same
  length; a source is 175 kilobytes and a blob 13, which is nothing for a
  program with a heap. }

{ The runtime library is RTLDOS.PAS, and the compiler reads it before the first
  line of this file: there is no include for it here. }

const Chunk=255;           { the width of OutputCodeString's parameter }
      NopCode=$90;         { what the last chunk is padded with }
      NameMax=250;         { what an argument is copied into, without its NUL }
      MaxFile=1048576;     { the largest file a tool here is handed }

type TBytes=array[0..MaxFile] of char;
     PBytes=^TBytes;

var Blob:PBytes;
    BlobBase,BlobLen:integer;
    Src:PBytes;
    SrcBase,SrcLen:integer;
    Out:PBytes;
    OutBase,OutCap,OutLen:integer;
    BlobName,PathName:array[1..NameMax] of char;
    MarkerBegin:array[1..14] of char;
    MarkerEnd:array[1..12] of char;
    FragKey:array[1..12] of char;
    FragOpen:array[1..20] of char;
    FragClose:array[1..3] of char;
    Key:array[1..11] of char;
    BeginPos,EndPos,SizeCount,Chunks:integer;
    i,j,b,n:integer;
    f:TFile;

{ ---------------------------------------------------------------------------
  The command line. The host's buffer holds one argument, so each name is copied
  into an array of its own - which is also the shape the file calls want. The
  copying is ArgCopy, in the runtime library: it answers how many characters it
  copied, and a name that does not fit would otherwise go on to be opened as a
  shorter one. }

procedure Arg(i:integer; Dest:PChar);
var n:integer;
begin
 n:=ArgCopy(i,Dest,NameMax);
 if n>=NameMax then begin
  WriteLn('an argument is too long');
  Halt
 end
end;

{ A whole file into a block from the heap, the address kept as an integer
  because that is what GetMem answers and what the file calls take.

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
  The text being built, a character at a time. The buffer is the size of the
  source plus what the literal can add to it, and the writes are counted so that
  a file longer than the room allowed for it fails loudly instead of quietly. }

procedure EmitChar(c:char);
begin
 if OutLen>=OutCap then begin
  WriteLn('the output does not fit');
  Halt
 end;
 Out^[OutLen]:=c;
 OutLen:=OutLen+1
end;

{ A run of characters ending at a NUL, which is the shape every string here
  has. }
procedure EmitText(S:PChar);
begin
 while S^<>#0 do begin
  EmitChar(S^);
  S:=S+4
 end
end;

procedure EmitInt(Value:integer);
var Digits:array[1..12] of integer;
    n:integer;
begin
 if Value<=0 then begin
  EmitChar('0')
 end else begin
  n:=0;
  while Value>0 do begin
   n:=n+1;
   Digits[n]:=Value mod 10;
   Value:=Value div 10
  end;
  while n>0 do begin
   EmitChar(chr(48+Digits[n]));
   n:=n-1
  end
 end
end;

{ Is the source, at i, the HXBaseSize constant? The answer is how long it is
  there, and zero when it is not: the name, then at least one digit, then the
  semicolon that ends the constant. Nothing else in the source looks like it -
  the name is the compiler's own and appears once - and the count of what was
  replaced is checked at the end, because a source with none is the wrong file
  and one with two would leave the second one saying the old size. }
function SizeAt(i,Last:integer):integer;
var j,n:integer;
    Same:boolean;
begin
 SizeAt:=0;
 if i+11<=Last then begin
  n:=0;
  Same:=true;
  while (n<11) and Same do begin
   if Src^[i+n]<>Key[n+1] then begin
    Same:=false
   end else begin
    n:=n+1
   end
  end;
  if Same then begin
   j:=i+11;
   n:=0;
   while (j<=Last) and (Src^[j]>='0') and (Src^[j]<='9') do begin
    j:=j+1;
    n:=n+1
   end;
   if n>0 then begin
    if j<=Last then begin
     if Src^[j]=';' then begin
      SizeAt:=(j+1)-i
     end
    end
   end
  end
 end
end;

{ The source from the first index to the last, into the output, with the size
  constant brought up to date as it goes past. }
procedure CopyPart(First,Last:integer);
var i,n:integer;
begin
 i:=First;
 while i<=Last do begin
  n:=SizeAt(i,Last);
  if n>0 then begin
   EmitText(Addr(FragKey[1]));
   EmitInt(BlobLen);
   EmitChar(';');
   SizeCount:=SizeCount+1;
   i:=i+n
  end else begin
   EmitChar(Src^[i]);
   i:=i+1
  end
 end
end;

{ Is the marker M, which is Len characters long, in the source at i? }
function MatchAt(i,Last,Len:integer; M:PChar):boolean;
var n:integer;
    Same:boolean;
begin
 Same:=true;
 n:=0;
 while (n<Len) and Same do begin
  if i+n>Last then begin
   Same:=false
  end else begin
   if Src^[i+n]<>M^ then begin
    Same:=false
   end else begin
    M:=M+4;
    n:=n+1
   end
  end
 end;
 MatchAt:=Same
end;

function FindMarker(From,Last,Len:integer; M:PChar):integer;
var i:integer;
    Found:boolean;
begin
 Found:=false;
 i:=From;
 while (i<=Last) and not Found do begin
  if MatchAt(i,Last,Len,M) then begin
   Found:=true
  end else begin
   i:=i+1
  end
 end;
 if Found then begin
  FindMarker:=i
 end else begin
  FindMarker:=-1
 end
end;

begin
 if ParamCount<>2 then begin
  WriteLn('usage: mkbase <hxbase.bin> <btpc.pas>');
  Halt
 end;

 MarkerBegin[1]:='{'; MarkerBegin[2]:='H'; MarkerBegin[3]:='X'; MarkerBegin[4]:='B';
 MarkerBegin[5]:='A'; MarkerBegin[6]:='S'; MarkerBegin[7]:='E'; MarkerBegin[8]:='-';
 MarkerBegin[9]:='B'; MarkerBegin[10]:='E'; MarkerBegin[11]:='G'; MarkerBegin[12]:='I';
 MarkerBegin[13]:='N'; MarkerBegin[14]:='}';

 MarkerEnd[1]:='{'; MarkerEnd[2]:='H'; MarkerEnd[3]:='X'; MarkerEnd[4]:='B';
 MarkerEnd[5]:='A'; MarkerEnd[6]:='S'; MarkerEnd[7]:='E'; MarkerEnd[8]:='-';
 MarkerEnd[9]:='E'; MarkerEnd[10]:='N'; MarkerEnd[11]:='D'; MarkerEnd[12]:='}';

 Key[1]:='H'; Key[2]:='X'; Key[3]:='B'; Key[4]:='a'; Key[5]:='s'; Key[6]:='e';
 Key[7]:='S'; Key[8]:='i'; Key[9]:='z'; Key[10]:='e'; Key[11]:='=';

 FragKey[1]:='H'; FragKey[2]:='X'; FragKey[3]:='B'; FragKey[4]:='a'; FragKey[5]:='s';
 FragKey[6]:='e'; FragKey[7]:='S'; FragKey[8]:='i'; FragKey[9]:='z'; FragKey[10]:='e';
 FragKey[11]:='=';

 FragOpen[1]:=' '; FragOpen[2]:=' '; FragOpen[3]:='O'; FragOpen[4]:='u'; FragOpen[5]:='t';
 FragOpen[6]:='p'; FragOpen[7]:='u'; FragOpen[8]:='t'; FragOpen[9]:='C'; FragOpen[10]:='o';
 FragOpen[11]:='d'; FragOpen[12]:='e'; FragOpen[13]:='S'; FragOpen[14]:='t'; FragOpen[15]:='r';
 FragOpen[16]:='i'; FragOpen[17]:='n'; FragOpen[18]:='g'; FragOpen[19]:='(';

 FragClose[1]:=')'; FragClose[2]:=';';

 { The three fragments are walked to a NUL, like every other string here, so
   each array is one longer than its text and ends it. }
 FragKey[12]:=#0;
 FragOpen[20]:=#0;
 FragClose[3]:=#0;

 Arg(1,Addr(BlobName[1]));
 Arg(2,Addr(PathName[1]));

 ReadWhole(Addr(BlobName[1]),BlobBase,Blob,BlobLen);
 ReadWhole(Addr(PathName[1]),SrcBase,Src,SrcLen);
 if SrcLen=0 then begin
  WriteLn('the source is empty');
  Halt
 end;

 BeginPos:=FindMarker(0,SrcLen-1,14,Addr(MarkerBegin[1]));
 if BeginPos<0 then begin
  WriteLn('the source has no begin marker');
  Halt
 end;
 BeginPos:=BeginPos+14;
 EndPos:=FindMarker(BeginPos,SrcLen-1,12,Addr(MarkerEnd[1]));
 if EndPos<0 then begin
  WriteLn('the source has no end marker');
  Halt
 end;

 OutCap:=SrcLen+BlobLen*5+64;
 OutBase:=GetMem(OutCap*4+16);
 if OutBase=0 then begin
  WriteLn('Not enough memory');
  Halt
 end;
 Out:=OutBase;
 OutLen:=0;
 SizeCount:=0;

 CopyPart(0,BeginPos-1);
 EmitChar(#13);
 EmitChar(#10);

 { The literal: 255 bytes a call, the last one padded, one call a line. }
 Chunks:=0;
 i:=0;
 while i<BlobLen do begin
  if i>0 then begin
   EmitChar(#13);
   EmitChar(#10)
  end;
  EmitText(Addr(FragOpen[1]));
  j:=0;
  while j<Chunk do begin
   if i+j<BlobLen then begin
    b:=ord(Blob^[i+j])
   end else begin
    b:=NopCode
   end;
   EmitChar('#');
   EmitInt(b);
   j:=j+1
  end;
  EmitText(Addr(FragClose[1]));
  Chunks:=Chunks+1;
  i:=i+Chunk
 end;

 EmitChar(#13);
 EmitChar(#10);
 EmitChar(' ');
 CopyPart(EndPos,SrcLen-1);

 if SizeCount<>1 then begin
  WriteLn('expected one HXBaseSize constant, found ',SizeCount:1);
  Halt
 end;

 ReWrite(f,Addr(PathName[1]));
 if IOError<>0 then begin
  Write('Cannot create '); WriteStrLn(Addr(PathName[1]));
  Halt
 end;
 BlockWrite(f,OutBase,OutLen,n);
 Close(f);

 WriteStr(Addr(BlobName[1]));
 Write(': blob ',BlobLen:1,' bytes into ');
 WriteStr(Addr(PathName[1]));
 Write(' (',Chunks:1,' chunks)');
 WriteLn
end.
