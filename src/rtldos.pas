{ rtldos.pas - the runtime library for programs this compiler builds for
  HX-DOS.

 ******************************************************************************
 *                                                                            *
 * Copyright (C) 2026, DosWorld  The Unlicense (public domain)                *
 *                                                                            *
 ******************************************************************************

  It is not a unit and it is not compiled on its own. The compiler reads it
  into every program before that program's first line is parsed, and
  everything here becomes part of it: the same names, the same scope, one
  file, and code that is emitted before the program's own - which is why a
  name here can be called from anywhere in the program, and why the compiler
  itself, which is a program, can leave the heap and the command line to this
  file. The library is looked for beside the file being compiled and then
  beside the compiler: in a tree where both are in one directory it is found
  wherever the compiler is run from. An include directive that names it is
  still accepted and does nothing, because the compiler compares the name
  against the library it has already read - so a program written before the
  library was read in for it keeps compiling, with or without the line.

  That is the shape the language allows, and it is why every name added to the
  program is either a Turbo Pascal name (Reset, BlockRead, Str, ...) or a name
  that begins with Rtl, which is what a program may not use for anything else.

  What is here is what the host layer does not answer, and only that. The
  host layer opens files, moves bytes, seeks, hands out the command line,
  allocates blocks of memory and raises an interrupt. What it does not have is
  the shape a Pascal programmer expects - a file that remembers where it is,
  an error number instead of an exception, a heap that can cut one block into
  many, and the handful of string and DOS helpers every program ends up
  writing. Those are here, and anything the host offers that the compiler does
  not have to know about is here too: GetMem and FreeMem, New and Dispose, the
  command line, are all names this file gives to primitives the compiler only
  passes on.

  Two rules of the language shape what is here, and both of them cost a
  little. A function of a program's own cannot be called as a statement - the
  compiler raises Error 122 when a call's result is dropped - so anything
  called for its effect is a procedure, which is why StrCopy is one. And AND
  and OR exist for booleans and not for integers; what an integer has is the
  two shifts, so a byte is taken out of a register by shifting the register
  down to it, which is RtlByte below and the shape every DOS call here is
  written in.

  A word on interrupts, because it is the reason the file calls below are not
  written with them. Intr($21, r) carries any DOS call whose arguments and
  result are registers: the version, the date, the time, a key, the drive,
  the file calls that take a handle and a number. It cannot carry a call that
  moves bytes through memory. In this language a CHAR is a four-byte cell, so
  a buffer of characters is not a buffer of bytes, and DOS's read and write
  want a buffer of bytes; only machine code can look at a byte, which is why
  the host layer does the moving and why the long-name call lives there too.
  The library's part is the shape of the thing, not the transfer. }

const RtlArgMax=128;    { the longest command line argument copied here }
      RtlKeyMax=16;     { the longest keyword ArgIs compares }
      RtlNameMax=128;   { the longest name SetStr builds }

{ The type a padded literal is passed in: a string literal can only go to a
  char array parameter that is exactly as long as the literal is, so a keyword
  for ArgIs and a name for SetStr are written as RtlKeyMax characters with the
  blanks that are not part of them on the end.

  It is a named type and not array[1..RtlKeyMax] of char written out at each
  parameter, because a parameter's type has to begin with an identifier: the
  compiler's NewParameter reads the type with Check(TokIdent) in front of it,
  so `Keyword:array[1..16] of char` is an error. A variable may be declared
  with the array written out; a parameter may not. }
type TRtlKey=array[1..RtlKeyMax] of char;

{ A pointer to a character cell, which is the one pointer the library needs.
  A string here is an address: a run of char cells ending at a NUL, and every
  string below is walked a cell at a time. A cell is four bytes, so the next
  character is four bytes on and not one - which is the one thing about
  pointers here that is easy to get wrong. }
type PChar=^char;

{ ---------------------------------------------------------------------------
  Registers.

  What Intr(i, r) hands to the host and gets back. The host runs the
  interrupt on the program's behalf, through the DPMI call that emulates one,
  and the record is what it reads the registers from and writes them back
  into: EAX, EBX, ECX, EDX, ESI, EDI and then Flags, whose low bit is the
  interrupt's carry - which is how a DOS call reports failure. A record of
  nothing but 4-byte fields, so there is nothing to pad.

  The six general registers are written back; the segment registers are not.
  They are read as the real mode segments to run the interrupt with, which is
  what a caller wants them for - a buffer in the first megabyte is named by a
  segment - and zero in any of them means the host may choose. What an
  interrupt leaves in them is a real mode segment, which is not something a
  program here can be given back. }
type Registers=record
      EAX,EBX,ECX,EDX:integer;
      ESI,EDI,EBP,ESP:integer;
      Flags:integer;
      ES,DS,FS,GS,CS,SS:integer;
     end;

{ The DOS calls whose answer is registers and whose arguments are not, in the
  shape a program wants them in. Every answer is read out of its register a
  byte at a time, because DOS writes the half that carries the answer and
  leaves the rest of the register as it found it, which is the host's state
  and can be anything.

  The byte is taken with a shift, which is what an integer here has for this.
  shr is logical, so it moves the byte that is wanted down to the bottom -
  eight bits a byte, so n bytes is a shift of n shl 3 - and fills what it
  leaves with zeros. A negative value therefore reads as the unsigned 32-bit
  value it stands for: -1 has four bytes and every one of them is 255. The
  mod that cuts the byte out of what is left is exact, because the shift has
  already made the value positive. }
function RtlByte(x,n:integer):integer;
var b:integer;
begin
 b:=(x shr (n shl 3)) mod 256;
 if b<0 then begin
  b:=b+256
 end;
 RtlByte:=b
end;

function DosVersion:integer;
var r:Registers;
begin
 r.EAX:=$3000;
 Intr($21,r);
 DosVersion:=(RtlByte(r.EAX,1) shl 8)+RtlByte(r.EAX,0)
end;

function DosMajor:integer;
begin
 DosMajor:=DosVersion shr 8
end;

function DosMinor:integer;
begin
 DosMinor:=DosVersion mod 256
end;

{ The date as YYYYMMDD and the time as HHMMSS, which are the two shapes that
  need no packed record and sort as they are written. }
function DosDate:integer;
var r:Registers;
begin
 r.EAX:=$2A00;
 Intr($21,r);
 DosDate:=(RtlByte(r.ECX,0)+(RtlByte(r.ECX,1) shl 8))*10000+RtlByte(r.EDX,1)*100+RtlByte(r.EDX,0)
end;

function DosTime:integer;
var r:Registers;
begin
 r.EAX:=$2C00;
 Intr($21,r);
 DosTime:=RtlByte(r.ECX,1)*10000+RtlByte(r.ECX,0)*100+RtlByte(r.EDX,1)
end;

{ 1 for A:, 2 for B:, and so on. }
function DosDrive:integer;
var r:Registers;
begin
 r.EAX:=$1900;
 Intr($21,r);
 DosDrive:=RtlByte(r.EAX,0)+1
end;

function KeyPressed:boolean;
var r:Registers;
begin
 r.EAX:=$0B00;
 Intr($21,r);
 KeyPressed:=RtlByte(r.EAX,0)<>0
end;

{ One key, without echo and without waiting for the keyboard buffer to fill.
  A key with a scan code in front of it (an arrow, a function key) answers
  with its first byte, #0, and the caller has to read again for the code. }
function ReadKey:char;
var r:Registers;
begin
 r.EAX:=$0700;
 Intr($21,r);
 ReadKey:=chr(RtlByte(r.EAX,0))
end;

{ The direct console output call: one byte, straight to the screen, and it
  cannot be redirected - which is what makes it the way to put a character
  where the user is looking while the output goes somewhere else. }
procedure WriteRaw(c:char);
var r:Registers;
begin
 r.EAX:=$0200;
 r.EDX:=ord(c);
 Intr($21,r)
end;

{ ---------------------------------------------------------------------------
  The command line, as the host hands it over.

  Params(i) is the host call: it copies argument i into a buffer of its own,
  one character to a cell, NUL terminated, and answers where that copy is. A
  negative index asks the other question - how many arguments there are - and
  that is all one call does. Argument 0 is the program itself: the path DOS
  ran it from, which the host reads out of the environment block. An argument
  that is not there answers zero rather than an empty string, so a caller
  tests for it before it reads. The buffer is the host's and holds one
  argument; asking again overwrites it.

  ParamStr and ParamCount are the two names a Pascal programmer writes, and
  they are here and not in the compiler because they do not have to be in the
  compiler: one is the host call's own answer and the other is that call with
  -1. What the compiler keeps is the primitive, which is what the host
  actually offers, and the library is where the language's names for it live.
  ParamStr answers an address and not a string, because there are no strings
  here to answer with: what is at the address is a NUL-terminated run of char
  cells, which is the shape the file calls want and the shape ArgCopy below
  copies out of. }
function ParamStr(i:integer):integer;
begin
 ParamStr:=Params(i)
end;

function ParamCount:integer;
begin
 ParamCount:=Params(-1)
end;

{ ---------------------------------------------------------------------------
  Files.

  Turbo Pascal's file variable is a type this language does not have, so a
  record stands in for it: the handle the host gave and where the next byte
  goes. A file is opened by name, and the name is a string of char cells that
  ends at a NUL - the shape the command line hands out, so ParamStr's answer
  can be passed straight in, and the shape SetStr builds.

  The name goes to the host with no length, which means "read it until the
  NUL", and the host is what turns it into the long-name call. That is the
  whole of long name support here: it is not translated, it is never
  translated, and it does not need to be - the only open this program ever
  makes is 716Ch.

  Errors are numbers in IOError and not exceptions, because the language has
  no exceptions: 0 is the last call went well, and the constants below say
  what went wrong. A call that fails leaves its result as the smallest thing
  it could be - no bytes, no position - so a caller that ignores IOError sees
  a short read rather than a crash.

  These are procedures and not functions, which is both the shape Turbo Pascal
  has and the only shape this language allows: a function of a program's own
  cannot be called as a statement, and Reset(f, name) is a statement a Pascal
  programmer writes. What a function would have returned is in IOError, in
  FilePos and in the count a block call is handed - so a program checks
  IOError where Turbo Pascal checks IOResult, and there is no error state to
  clear afterwards. }
type TFile=record
      Handle:integer;    { the DOS handle, or -1 when the file is not open }
      Mode:integer;      { 0 reading, 1 writing }
      Pos:integer        { the byte offset of the next transfer }
     end;

{ A buffer is passed as its address, not as a VAR parameter, and the reason is
  a rule of the language this library is written for: a VAR parameter's type
  *is* checked at the call site, and two arrays are the same type only when
  their bounds are the same. A parameter declared over a one-element array
  therefore accepts one call and no other, which is no use at all to a caller
  whose buffer is 512 characters long. An address has no such trouble: Addr
  answers with an integer, every integer is the same type, and the count
  beside it says how much of the buffer to use. }

const RtlErrNone=0;
      RtlErrOpen=1;      { the name could not be opened }
      RtlErrCreate=2;    { the file could not be created or truncated }
      RtlErrRead=3;      { the read failed }
      RtlErrWrite=4;     { the write failed, or wrote less than it was given }
      RtlErrSeek=5;      { the seek failed }
      RtlErrClosed=6;    { the file is not open }

var IOError:integer;

procedure Reset(var f:TFile; Name:PChar);
var h:integer;
begin
 h:=SysOpen(Name,-1,0);
 f.Handle:=h;
 f.Mode:=0;
 f.Pos:=0;
 if h<0 then begin
  IOError:=RtlErrOpen
 end else begin
  IOError:=RtlErrNone
 end
end;

procedure ReWrite(var f:TFile; Name:PChar);
var h:integer;
begin
 h:=SysOpen(Name,-1,1);
 f.Handle:=h;
 f.Mode:=1;
 f.Pos:=0;
 if h<0 then begin
  IOError:=RtlErrCreate
 end else begin
  IOError:=RtlErrNone
 end
end;

{ Open argument i of the command line. The command line is the one place a
  program gets a name it did not write itself, and passing the argument
  straight to the host is the whole of it. }
procedure ResetArg(var f:TFile; i:integer);
begin
 Reset(f,ParamStr(i))
end;

procedure ReWriteArg(var f:TFile; i:integer);
begin
 ReWrite(f,ParamStr(i))
end;

{ Blocks of bytes, a character to a cell, which is the width the host moves
  them in. Count is characters and Done comes back as the characters that
  moved; Done below Count is the end of the file on a read, and on a write it
  is a disk that filled up, which IOError also says. This is Delphi's
  four-parameter shape of the call, which is what a program written for Turbo
  Pascal can be changed to with one variable - and the buffer is handed over
  as Addr(Buf[1]) for the reason the type above gives. }
procedure BlockRead(var f:TFile; Buf:PChar; Count:integer; var Done:integer);
var n:integer;
begin
 n:=0;
 if f.Handle<0 then begin
  IOError:=RtlErrClosed
 end else if Count>0 then begin
  n:=SysRead(f.Handle,Buf,Count);
  if n<0 then begin
   IOError:=RtlErrRead;
   n:=0
  end else begin
   IOError:=RtlErrNone;
   f.Pos:=f.Pos+n
  end
 end else begin
  IOError:=RtlErrNone
 end;
 Done:=n
end;

procedure BlockWrite(var f:TFile; Buf:PChar; Count:integer; var Done:integer);
var n:integer;
begin
 n:=0;
 if f.Handle<0 then begin
  IOError:=RtlErrClosed
 end else if Count>0 then begin
  n:=SysWrite(f.Handle,Buf,Count);
  if (n<0) or (n<Count) then begin
   IOError:=RtlErrWrite;
   if n<0 then begin
    n:=0
   end
  end else begin
   IOError:=RtlErrNone
  end;
  f.Pos:=f.Pos+n
 end else begin
  IOError:=RtlErrNone
 end;
 Done:=n
end;

{ Where the next transfer goes, from the start of the file, and FilePos is
  where it is now. A seek past the end is allowed: the file grows to the
  offset when something is written there, and reads before that are the end of
  the file. }
procedure Seek(var f:TFile; Offset:integer);
var n:integer;
begin
 if f.Handle<0 then begin
  IOError:=RtlErrClosed
 end else begin
  n:=SysSeek(f.Handle,Offset,0);
  if n<0 then begin
   IOError:=RtlErrSeek
  end else begin
   IOError:=RtlErrNone;
   f.Pos:=n
  end
 end
end;

function FilePos(var f:TFile):integer;
begin
 FilePos:=f.Pos
end;

{ The size of the file in bytes. The host answers this by seeking to the end
  of the file, and leaves the position there; that is what the primitive does
  and it is not going to be talked out of it, so the position the library
  keeps is put back here. Asking how long a file is has not read from it, and
  a program that asks in the middle of reading - which is exactly when a
  program asks - must find the next read where it left off. }
function FileSize(var f:TFile):integer;
var n,Here:integer;
begin
 if f.Handle<0 then begin
  IOError:=RtlErrClosed;
  FileSize:=-1
 end else begin
  Here:=f.Pos;
  n:=SysSize(f.Handle);
  if n<0 then begin
   FileSize:=-1
  end else begin
   SysSeek(f.Handle,Here,0);
   FileSize:=n
  end
 end
end;

procedure Close(var f:TFile);
begin
 if f.Handle>=0 then begin
  SysClose(f.Handle);
  f.Handle:=-1
 end
end;

{ ---------------------------------------------------------------------------
  The command line.

  ParamStr answers with an address - a NUL-terminated string of char cells
  lives there - and ParamCount with how many there are. Argument 0 is the
  program. What the library adds is the copying, because a program cannot
  read what is at an address without a pointer and cannot put it anywhere
  without one either. }
function ArgCount:integer;
begin
 ArgCount:=ParamCount
end;

function ArgLen(i:integer):integer;
var p:PChar;
    n:integer;
begin
 n:=0;
 p:=ParamStr(i);
 if p<>0 then begin
  while p^<>#0 do begin
   n:=n+1;
   p:=p+4
  end
 end;
 ArgLen:=n
end;

function ArgChar(i,j:integer):char;
var p:PChar;
    n:integer;
    c:char;
begin
 c:=#0;
 p:=ParamStr(i);
 n:=1;
 while (p<>0) and (n<=j) do begin
  if p^=#0 then begin
   p:=0
  end else begin
   c:=p^;
   p:=p+4;
   n:=n+1
  end
 end;
 ArgChar:=c
end;

{ Copy argument i into the caller's array, NUL terminated, and answer how
  many characters it has. Max is what the array holds without the NUL. }
function ArgCopy(i:integer; Dest:PChar; Max:integer):integer;
var p:PChar;
    n:integer;
    More:boolean;
begin
 n:=0;
 p:=ParamStr(i);
 if p<>0 then begin
  More:=true;
  while (n<Max) and More do begin
   if p^=#0 then begin
    More:=false
   end else begin
    Dest^:=p^;
    p:=p+4;
    Dest:=Dest+4;
    n:=n+1
   end
  end
 end;
 Dest^:=#0;
 ArgCopy:=n
end;

{ The argument of the last ArgText, for a program that would rather look at
  the characters than at an address. }
var RtlArg:array[1..RtlArgMax] of char;

function ArgText(i:integer):integer;
begin
 ArgText:=ArgCopy(i,Addr(RtlArg[1]),RtlArgMax-1)
end;

procedure WriteStr(S:PChar);
begin
 if S<>0 then begin
  while S^<>#0 do begin
   Write(S^);
   S:=S+4
  end
 end
end;

procedure WriteStrLn(S:PChar);
begin
 WriteStr(S);
 WriteLn
end;

procedure ArgWrite(i:integer);
begin
 WriteStr(ParamStr(i))
end;

procedure ArgWriteLn(i:integer);
begin
 ArgWrite(i);
 WriteLn
end;

{ Does argument i read exactly as this keyword?

  The keyword is an array and not a string for one reason: a string literal
  can only be passed to a char array parameter that is exactly as long as the
  literal is, so a keyword is written padded with blanks to RtlKeyMax
  characters and the padding is not part of the comparison. The argument has
  to have exactly the length of the keyword without its padding, so a
  shorter or longer argument does not match.

   if ArgIs(1, '-HELP           ') then ...
   if ArgIs(1, '/VERSION        ') then ... }
function ArgIs(i:integer; Keyword:TRtlKey):boolean;
var L,j:integer;
    p:PChar;
    Same:boolean;
begin
 L:=RtlKeyMax;
 while (L>0) and (Keyword[L]=' ') do begin
  L:=L-1
 end;
 Same:=false;
 if (L>0) and (ArgLen(i)=L) then begin
  p:=ParamStr(i);
  if p<>0 then begin
   Same:=true;
   j:=1;
   while j<=L do begin
    if p^<>Keyword[j] then begin
     Same:=false
    end;
    p:=p+4;
    j:=j+1
   end
  end
 end;
 ArgIs:=Same
end;

{ ---------------------------------------------------------------------------
  Strings.

  A string here is a char array that ends at a NUL, and its length is not
  kept anywhere, so every one of these walks it. }
function StrLen(S:PChar):integer;
var n:integer;
begin
 n:=0;
 if S<>0 then begin
  while S^<>#0 do begin
   n:=n+1;
   S:=S+4
  end
 end;
 StrLen:=n
end;

{ A procedure and not a function, though returning where the copy ended is
  what the C library's version of this does: a user function cannot be called
  as a statement here. The compiler raises Error 122 when a call to a function
  of the program's own is used for its effect, so a function whose result is
  dropped is an error and everything called for its effect has to be a
  procedure. }
procedure StrCopy(Dest,S:PChar);
begin
 while S^<>#0 do begin
  Dest^:=S^;
  Dest:=Dest+4;
  S:=S+4
 end;
 Dest^:=#0
end;

function StrEq(A,B:PChar):boolean;
var Same,Done:boolean;
begin
 Same:=true;
 Done:=false;
 while not Done do begin
  if A^<>B^ then begin
   Same:=false;
   Done:=true
  end else if A^=#0 then begin
   Done:=true
  end else begin
   A:=A+4;
   B:=B+4
  end
 end;
 StrEq:=Same
end;

function StrLess(A,B:PChar):boolean;
var Less:boolean;
    Done:boolean;
begin
 Less:=false;
 Done:=false;
 while not Done do begin
  if A^<>B^ then begin
   Less:=ord(A^)<ord(B^);
   Done:=true
  end else if A^=#0 then begin
   Done:=true
  end else begin
   A:=A+4;
   B:=B+4
  end
 end;
 StrLess:=Less
end;

{ Upper case for the letters a program cares about here: the ASCII ones. }
procedure UpStr(S:PChar);
var c:integer;
begin
 while S^<>#0 do begin
  c:=ord(S^);
  if (c>=97) and (c<=122) then begin
   S^:=chr(c-32)
  end;
  S:=S+4
 end
end;

{ Build a name, or any short string, out of a literal: the literal is passed
  the way a literal has to be passed, padded with blanks to RtlKeyMax
  characters, and the padding is where it ends. A name with a blank in it
  cannot be built this way - it is built a character at a time instead. }
procedure SetStr(Dest:PChar; Text:TRtlKey);
var i:integer;
begin
 i:=1;
 while (i<=RtlKeyMax) and (Text[i]<>' ') do begin
  Dest^:=Text[i];
  Dest:=Dest+4;
  i:=i+1
 end;
 Dest^:=#0
end;

{ An integer as decimal digits. A negative number gets its sign, and the
  smallest integer is handled by dividing the magnitude rather than the
  number - -2147483648 has no positive counterpart to negate. }
procedure Str(x:integer; Dest:PChar);
var Digits:array[1..12] of char;
    n,i,Negative:integer;
begin
 Negative:=0;
 n:=0;
 if x<0 then begin
  Negative:=1;
  if x=-2147483647-1 then begin
   { The one number with no positive counterpart: its last digit and the
      digits of the rest of it are taken separately, because negating it is
      not something that can be done. }
   Digits[1]:='8';
   n:=1;
   x:=214748364
  end else begin
   x:=-x
  end
 end;
 repeat
  n:=n+1;
  Digits[n]:=chr(48+(x mod 10));
  x:=x div 10
 until x=0;
 if Negative<>0 then begin
  Dest^:='-';
  Dest:=Dest+4
 end;
 i:=n;
 while i>=1 do begin
  Dest^:=Digits[i];
  Dest:=Dest+4;
  i:=i-1
 end;
 Dest^:=#0
end;

{ Decimal digits read back as an integer, stopping at the first character
  that is not one. Code is 0 when at least one digit was read and 1 when
  there was nothing to read, which is Turbo Pascal's convention. }
function Val(S:PChar; var Code:integer):integer;
var x,Digit,Sign:integer;
    Any:boolean;
begin
 x:=0;
 Sign:=1;
 Any:=false;
 if S^='-' then begin
  Sign:=-1;
  S:=S+4
 end else if S^='+' then begin
  S:=S+4
 end;
 while (S^>='0') and (S^<='9') do begin
  Digit:=ord(S^)-48;
  x:=x*10+Digit;
  Any:=true;
  S:=S+4
 end;
 if Any then begin
  Code:=0
 end else begin
  Code:=1
 end;
 Val:=x*Sign
end;

{ Hexadecimal, which is what an address is read in and what inline code is
  written with: Digits digits of the low end of the value, most significant
  first, so 8 is the whole of a 32-bit one and 4 is a 16-bit half of it.

  A digit is a nibble, so the digits are taken off the low end one at a time
  and written out backwards, with the shift moving the next one down. A
  negative value reads as the unsigned 32-bit value it stands for, so every
  digit written for it is a digit of that value. The digit itself is worked
  out rather than looked up in a string, because there are no string
  constants to look anything up in: the language has numbers, characters, and
  arrays of characters that a program fills in itself. }
procedure Hex(x,Digits:integer; Dest:PChar);
var Buf:array[1..8] of char;
    n,i,v:integer;
begin
 n:=0;
 i:=1;
 while i<=Digits do begin
  v:=x mod 16;
  if v<0 then begin
   v:=v+16
  end;
  n:=n+1;
  if v<10 then begin
   Buf[n]:=chr(48+v)
  end else begin
   Buf[n]:=chr(55+v)
  end;
  x:=x shr 4;
  i:=i+1
 end;
 while n>=1 do begin
  Dest^:=Buf[n];
  Dest:=Dest+4;
  n:=n-1
 end;
 Dest^:=#0
end;

{ ---------------------------------------------------------------------------
  Memory: GetMem and FreeMem, and New and Dispose above them.

  There are two ways to get memory here and it is worth knowing which is
  which. SysAlloc asks the host for one block and SysFree gives it back: one
  interrupt for a block, no bookkeeping at all, and the memory is the
  machine's again the moment it is freed. That is the right call for a program
  that wants one buffer and knows how big, and it is the wrong call to make in
  a loop, because every GetMem would be an interrupt and every FreeMem would
  be another.

  So the heap does what a heap does: it asks the host once for the largest
  block it will give - SysAllocMax answers how large that turned out to be -
  and then cuts that block up here, in this file, in the language. Almost
  every allocation after the first is a few comparisons and two stores. The
  pool is only asked for when a program actually calls GetMem, so a program
  that never allocates never takes memory from the machine, and when the pool
  has nothing left the host is asked for another one - the largest block that
  is left, which is what a growing heap costs and why a program that grows one
  forever still runs out.

  A block is given out with two cells of header in front of it that only this
  file knows about: how long the block is, header included, and - in a block
  that is free - where the next free block is. Free blocks are on one list,
  kept in address order, and that is what makes joining two of them back
  together possible: the next free block on the list either begins exactly
  where this one ends, and then they are one block again, or it does not, and
  then they are not. A block that comes back is put on that list in its place,
  so two blocks freed one after the other are one block the next time
  something large is asked for. A block is split only when the piece left over
  is worth splitting - a header and a cell - and otherwise handed over whole,
  because a heap that splits into pieces too small to use is a heap that
  fragments itself.

  What a block holds when it is handed over is whatever was there, which is
  the same promise Turbo Pascal's New makes - a record with a pointer in it is
  not ready to read until the program has filled the field in. When a block
  has to start empty there is GetMemZeroed: the same block with every byte of
  it written to zero before the address is answered, which is FillChar with a
  value of zero and no separate routine of its own, because a byte fill is
  what a machine has an instruction for. The host promises nothing about what
  a block holds - the memory a program has finished with is the memory the
  next one is given - so a program that keeps a table in a block, and reads an
  entry of it before it has written that entry, wants this and not GetMem; a
  program that fills every entry before it reads one is paying for nothing it
  needs.

  The heap rounds every block up to a multiple of eight, so a block it hands
  out is aligned for anything this language can put in one, and a count in
  bytes that is not a multiple of four is as ordinary here as one that is:
  FillChar and Move are about memory and not about the cells in it.

  GetMem and FreeMem are the two calls the compiler's own New and Dispose are
  made of - New takes the size from the type it is given and calls GetMem,
  Dispose calls FreeMem for a variable and RtlFreeBlock for anything else - so
  a program may use either pair, or both: it is one heap with four names. New
  is the one to write where the type is already known, because the size is the
  compiler's to work out and not the program's, and Dispose is the one that
  also clears its pointer to zero.

  What none of them does is check that an address ever came from here: FreeMem
  and Dispose are given an address and believe it, exactly as they do in Turbo
  Pascal. And an address that came from SysAlloc is not an address for FreeMem
  - the two allocators do not know about each other - which is the one way to
  get this wrong that a program can also get right. }

type { A cell of the language: four bytes, whether it is read as a char, as
       an integer or as an address. The bound is what the language lets a
       pointer to an array be declared with; the heap walks past the end of
       it, which is what a block of memory is for and is checked by nothing.

       Nothing here fills memory with it - that is the host's Fill, which
       works in bytes - but a block's two header cells are read and written
       through a pointer, and ^ is written against a name. }
     TRtlCell=array[0..0] of integer;
     PRtlCell=^TRtlCell;

var RtlHeap:integer;      { where the first pool is, and 0 until the host has
                            been asked for one: a heap that has grown past it
                            is more than one pool, and the free list, and not
                            this, is what knows where they are }
    RtlHeapFree:integer;  { the first free block, 0 when there is none }

{ The two cells in front of every block. Both are read and written through a
  pointer, because an address is an integer here and ^ is written against a
  name: a helper function answers with a pointer to the header and the caller
  writes through it. }
function RtlPieceSize(b:integer):integer;
var p:PRtlCell;
begin
 p:=b;
 RtlPieceSize:=p^[0]
end;

procedure RtlSetPieceSize(b,Size:integer);
var p:PRtlCell;
begin
 p:=b;
 p^[0]:=Size
end;

function RtlPieceNext(b:integer):integer;
var p:PRtlCell;
begin
 p:=b;
 RtlPieceNext:=p^[1]
end;

procedure RtlSetPieceNext(b,Next:integer);
var p:PRtlCell;
begin
 p:=b;
 p^[1]:=Next
end;

{ A free block, put on the list in address order and joined to a neighbour it
  touches, which is what FreeMem is and what a new pool is when it happens to
  land beside an old one. }
procedure RtlInsertFree(b,Size:integer);
var Prev,Next:integer;
begin
 Prev:=0;
 Next:=RtlHeapFree;
 while (Next<>0) and (Next<b) do begin
  Prev:=Next;
  Next:=RtlPieceNext(Next)
 end;
 if (Next<>0) and (b+Size=Next) then begin
  Size:=Size+RtlPieceSize(Next);
  RtlSetPieceNext(b,RtlPieceNext(Next))
 end else begin
  RtlSetPieceNext(b,Next)
 end;
 RtlSetPieceSize(b,Size);
 if (Prev<>0) and (Prev+RtlPieceSize(Prev)=b) then begin
  RtlSetPieceSize(Prev,RtlPieceSize(Prev)+Size);
  RtlSetPieceNext(Prev,RtlPieceNext(b))
 end else if Prev=0 then begin
  RtlHeapFree:=b
 end else begin
  RtlSetPieceNext(Prev,b)
 end
end;

{ One more pool, as large as the host will make it. The size is rounded down
  to a multiple of eight so that every block cut out of it keeps the alignment
  the first one had: the host's block is paragraph aligned and this is the only
  thing that could move what comes after it off it. }
procedure RtlHeapGrow;
var p,Size:integer;
begin
 Size:=0;
 p:=SysAllocMax(Size);
 if p<>0 then begin
  Size:=(Size shr 3) shl 3;
  if RtlHeap=0 then begin
   RtlHeap:=p
  end;
  RtlInsertFree(p,Size)
 end
end;

{ The first free block that is large enough, taken off the list: the front of
  it is what the caller is given and the rest stays free where it is, unless
  the rest is too small to be worth a header, and then the caller is given the
  whole of it and the list simply loses it. Answers 0 when the heap is new
  and has to be asked for, or when growing it is worth a try. }
function RtlTake(Need:integer):integer;
var Prev,Next,Size,Rest:integer;
begin
 Prev:=0;
 Next:=RtlHeapFree;
 while (Next<>0) and (RtlPieceSize(Next)<Need) do begin
  Prev:=Next;
  Next:=RtlPieceNext(Next)
 end;
 if Next=0 then begin
  RtlTake:=0
 end else begin
  Size:=RtlPieceSize(Next);
  if Size-Need>=16 then begin
   Rest:=Next+Need;
   RtlSetPieceSize(Rest,Size-Need);
   RtlSetPieceNext(Rest,RtlPieceNext(Next));
   RtlSetPieceSize(Next,Need);
   if Prev=0 then begin
    RtlHeapFree:=Rest
   end else begin
    RtlSetPieceNext(Prev,Rest)
   end
  end else begin
   if Prev=0 then begin
    RtlHeapFree:=RtlPieceNext(Next)
   end else begin
    RtlSetPieceNext(Prev,RtlPieceNext(Next))
   end
  end;
  RtlTake:=Next+8
 end
end;

function GetMem(Size:integer):integer;
var Need,p:integer;
    Grew:boolean;
begin
 GetMem:=0;
 { A request that is not positive is not a request, and one above a gigabyte
    is one no machine this runs on can meet: both would only overflow the
    arithmetic below, so both answer 0 without asking anyone. }
 if (Size>0) and (Size<1073741824) then begin
  Need:=(((Size+7) shr 3) shl 3)+8;
  p:=RtlTake(Need);
  if p=0 then begin
   { Nothing on the list fits. Ask the host for another pool - once, or a
     request that cannot be met would ask for one on every call - and look at
     the list again, which now has it on it. }
   RtlHeapGrow;
   p:=RtlTake(Need);
   Grew:=p<>0
  end else begin
   Grew:=true
  end;
  if Grew then begin
   GetMem:=p
  end
 end
end;

{ A block handed back without clearing the variable it came from. That is what
  Dispose of anything but a variable needs: p^.next is an address read out of
  the block, and there is no variable there to clear. A program writes FreeMem
  and not this. }
procedure RtlFreeBlock(p:integer);
begin
 if p<>0 then begin
  RtlInsertFree(p-8,RtlPieceSize(p-8))
 end
end;

procedure FreeMem(var p:integer);
begin
 if p<>0 then begin
  RtlFreeBlock(p);
  p:=0
 end
end;

{ The two block operations a Pascal program expects, over the host's machine
  code ones: SysFill is REP STOSB and SysMove is REP MOVSB, so a buffer is
  cleared or copied by the processor rather than a cell at a time by a loop,
  which is the whole reason they are here and the whole reason a memory that
  is to start empty is a FillChar and not a routine of its own.

  Both take an address as an integer and a count in bytes, like everything
  else here that is about memory rather than about characters, and both take
  the address of what they work on: a caller writes FillChar(Addr(B),n,0) and
  Move(Addr(A),Addr(B),n). The value of a fill is the low byte of whatever it
  is given, so a char and an integer both mean what a caller means by it. }
procedure FillChar(Address,Count,Value:integer);
begin
 SysFill(Address,Count,Value)
end;

procedure Move(Source,Dest,Count:integer);
begin
 SysMove(Source,Dest,Count)
end;

function GetMemZeroed(Size:integer):integer;
var p:integer;
begin
 p:=GetMem(Size);
 if p<>0 then begin
  FillChar(p,Size,0)
 end;
 GetMemZeroed:=p
end;
