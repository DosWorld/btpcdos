(******************************************************************************
 *                                 BeRoTinyPascal                             *
 ******************************************************************************
 *   A self-hosting capable tiny pascal compiler for the Win32 x86 platform   *
 ******************************************************************************
 *                        Version 2016-06-22-18-07-0000                       *
 ******************************************************************************
 *                                zlib license                                *
 *============================================================================*
 *                                                                            *
 * Copyright (C) 2026,      DosWorld                                          *
 * Copyright (C) 2006-2016, Benjamin Rosseaux (benjamin@rosseaux.com)         *
 *                                                                            *
 * This software is provided 'as-is', without any express or implied          *
 * warranty. In no event will the authors be held liable for any damages      *
 * arising from the use of this software.                                     *
 *                                                                            *
 * Permission is granted to anyone to use this software for any purpose,      *
 * including commercial applications, and to alter it and redistribute it     *
 * freely, subject to the following restrictions:                             *
 *                                                                            *
 * 1. The origin of this software must not be misrepresented; you must not    *
 *    claim that you wrote the original software. If you use this software    *
 *    in a product, an acknowledgement in the product documentation would be  *
 *    appreciated but is not required.                                        *
 * 2. Altered source versions must be plainly marked as such, and must not be *
 *    misrepresented as being the original software.                          *
 * 3. This notice may not be removed or altered from any source distribution. *
 *                                                                            *
 ******************************************************************************)
program BTPC; { BeRoTinyPascalCompiler }
{$ifdef fpc}
 {$mode delphi}
{$endif}
{$ifdef Win32}
 {$define Windows}
{$endif}
{$ifdef Win64}
 {$define Windows}
{$endif}
{$ifdef WinCE}
 {$define Windows}
{$endif}
{$ifdef Windows}
 {$apptype console}
{$endif}

{ The library: everything the compiler gives a program it builds, spliced in
  at the top of this one, which is a program.

  The compiler reads it in itself, before the program's first line, so this
  line is not what puts it in the image. An up-to-date compiler reads the
  name, finds that it is the library it has already read, and reads nothing;
  what the line is for is the build that cannot start on its own, by a
  compiler older than the rule and with no reading of its own to do. Then the
  text has to be in this source as well as in the file, and it is spliced in
  here, where the reading of an up-to-date compiler puts it: the two
  placements have to agree, or two compilers built from one source would
  differ in the code they emit for it.

  It stands first because a name it declares may be used anywhere below, and
  what is below uses ParamStr in the reader, long before the tables.

  The file that older compiler is given is the older library, swapped in for
  the length of one build: a library that calls SysFill is no use to a
  compiler old enough not to have SysFill. }
{$I rtldos.pas}

{ The three tables the compiler keeps the program it is reading in: the code
  it emits, the identifiers it has met and the types it has built. None of
  them is carried in the image any more - PrepareTables asks the host for
  each one when the compiler starts - so what they cost is memory on the
  machine that is compiling, and only while it compiles. That is what pays
  for the limits below: the tables can be sized for the programs people write
  instead of for the memory every image spent whether it was used or not.

  Two of the three are asked for; the type table is a few kilobytes, so it
  stays in the frame and is only cleared there. What the heap has and the
  frame has not is room: the frame is the largest block the host has, tens of
  megabytes, while the memory free above it - which is where a block of a
  megabyte comes from - is a few megabytes the boot kept back. Two megabytes
  of identifiers and one of code are what that pays for. The jump table the
  assembler fills is a megabyte itself and stays in the frame, where there is
  room, for the same reason. }
const MaximalCodeSize=262144;
      MaximalIdentifiers=16384;
      MaximalTypes=512;
      MaximalList=10;
      MaximalAlfa=20;
      MaximalStringLength=255;
      MaximalCases=256;
      { One inline block holds at most this many bytes. The limit is the
        compiler's, not the machine's: it keeps the block's bytes in a local
        array while the list is parsed. }
      MaximalInline=256;

      { The source stack. Level 0 is the main source - the input stream, or
        the file named on the command line - and every level above it is an
        open include. Each level owns one SourceBufferSize slice of
        SourceBuffer, and the numbers are written out rather than derived
        from each other, because a constant in this compiler is one number, a
        name or a sign, and not an expression. }
      MaximalSourceLevel=8;
      SourceBufferSize=1024;
      MaximalSourceBuffer=9216;        { (MaximalSourceLevel+1)*SourceBufferSize }
      MaximalSourceName=128;

      (* The image this compiler emits is [512-byte DPMIST32 stub][PE headers]
         [.text], and .text is the runtime blob followed by the generated code.
         Only the four header fields below depend on how much code was
         generated; everything else is the constant HXBaseSize bytes that
         EmitStubCode writes. These are file offsets - OutputCodeData is
         1-based, which is why they are the offsets plus one. *)
      HXBaseSize=13377;
      HXSizeOfCode=541;
      HXSizeOfImage=593;
      HXSectionVirtualSize=769;
      HXSectionRawSize=777;
      HXFileAlignment=512;
      HXSectionAlignment=4096;
      HXSizeOfHeaders=1024;

      OPNone=-1;
      OPAdd=0;
      OPNeg=1;
      OPMul=2;
      OPDivD=3;
      OPRemD=4;
      OPDiv2=5;
      OPRem2=6;
      OPEqlI=7;
      OPNEqI=8;
      OPLssI=9;
      OPLeqI=10;
      OPGtrI=11;
      OPGEqI=12;
      OPDupl=13;
      OPSwap=14;
      OPAndB=15;
      OPOrB=16;
      { The shifts are binary like the four above them: two values off the
        expression stack, one back on. }
      OPShl=17;
      OPShr=18;
      OPLoad=19;
      OPStore=20;
      OPHalt=21;
      OPWrI=22;
      OPWrC=23;
      OPWrL=24;
      OPRdI=25;
      OPRdC=26;
      OPRdL=27;
      OPEOF=28;
      OPEOL=29;
      OPLdC=30;
      OPLdA=31;
      OPLdLA=32;
      OPLdL=33;
      OPLdG=34;
      OPStL=35;
      OPStG=36;
      OPMove=37;
      OPCopy=38;
      OPAddC=39;
      OPMulC=40;
      OPJmp=41;
      OPJZ=42;
      OPCall=43;
      OPAdjS=44;
      OPExit=45;
      OPCallRTL=46;
      OPCallRTLValue=47;
      { A block of literal bytes, written straight into the instruction stream.
        Not pairable with anything: it is a hole the peephole never sees into. }
      OPInline=48;

      TokIdent=0;
      TokNumber=1;
      TokStrC=2;
      TokPlus=3;
      TokMinus=4;
      TokMul=5;
      TokLBracket=6;
      TokRBracket=7;
      TokColon=8;
      TokEql=9;
      TokNEq=10;
      TokLss=11;
      TokLEq=12;
      TokGtr=13;
      TokGEq=14;
      TokLParent=15;
      TokRParent=16;
      TokComma=17;
      TokSemi=18;
      TokPeriod=19;
      TokAssign=20;
      SymBEGIN=21;
      SymEND=22;
      SymIF=23;
      SymTHEN=24;
      SymELSE=25;
      SymWHILE=26;
      SymDO=27;
      SymCASE=28;
      SymREPEAT=29;
      SymUNTIL=30;
      SymFOR=31;
      SymTO=32;
      SymDOWNTO=33;
      SymNOT=34;
      SymDIV=35;
      SymMOD=36;
      SymAND=37;
      SymOR=38;
      SymCONST=39;
      SymVAR=40;
      SymTYPE=41;
      SymARRAY=42;
      SymOF=43;
      SymPACKED=44;
      SymRECORD=45;
      SymPROGRAM=46;
      SymFORWARD=47;
      SymHALT=48;
      SymFUNC=49;
      SymPROC=50;
      SymINLINE=51;

      { The caret. It stands after a variable, P^, and inside a type, ^T; the
        two are told apart by where the parser meets them, not by the token. }
      TokPoint=52;

      { The shifts. Turbo Pascal ranks them with the multiplications rather
        than with the additions, and so does the parser: they are read in
        Term, and what they take is two integers, like DIV. }
      SymSHL=53;
      SymSHR=54;

      IdCONST=0;
      IdVAR=1;
      IdFIELD=2;
      IdTYPE=3;
      IdFUNC=4;

      KindSIMPLE=0;
      KindARRAY=1;
      KindRECORD=2;
      { A pointer. Its value is an address, which in this compiler is an
        integer like any other, so nothing about the machine code changes: what
        the kind buys is the double meaning of the name. A pointer variable
        read as a value is its value - an address - where an array or a record
        read as a value is where it lives. SubType is the type pointed at, and
        it is what P^ reads and writes. }
      KindPOINTER=3;

      TypeINT=1;
      TypeBOOL=2;
      TypeCHAR=3;
      TypeSTR=4;

      FunCHR=0;
      FunORD=1;
      FunWRITE=2;
      FunWRITELN=3;
      FunREAD=4;
      FunREADLN=5;
      FunEOF=6;
      FunEOFLN=7;
      FunSYSOPEN=8;
      FunSYSREAD=9;
      FunSYSWRITE=10;
      FunSYSSEEK=11;
      FunSYSCLOSE=12;
      FunSYSSIZE=13;
      FunADDR=14;
      { The command line as the host offers it, which is one call and not the
        two names a Pascal programmer writes: Params(i) answers the address of
        a copy of argument i, and a negative i asks how many there are.
        ParamStr and ParamCount are those two questions, and they are in the
        library rather than here, because a builtin is what cannot be written
        in the language and they can. }
      FunPARAMS=15;
      FunINTR=17;
      FunSYSALLOC=18;
      FunSYSFREE=19;
      FunNEW=20;
      FunDISPOSE=21;
      { The largest block the host will give, which is where the library's
        heap comes from. Index 0 is the program itself, which the host reads
        out of the environment block. }
      FunSYSALLOCMAX=22;
      { Fill(address, count, value) and Move(source, dest, count): the two
        operations every program does to memory it is not reading as
        characters, and the two the host does better than a loop written here
        can - a repeated string instruction against a byte at a time. Both
        counts are bytes, and both are in the runtime rather than in the
        library, which is where the library's FillChar and Move are written
        over them. }
      FunSYSFILL=23;
      FunSYSMOVE=24;

      { The runtime's function table. The host builds it at startup and the
        generated code calls through it as CALL DWORD PTR [ESI+ofs], so these
        byte offsets are a contract with hxrtl.asm: the entry a builtin emits
        has to be the entry the host put there. }
      RTLCallHalt=0;
      RTLCallWriteChar=4;
      RTLCallWriteInteger=8;
      RTLCallWriteLn=12;
      RTLCallReadChar=16;
      RTLCallReadInteger=20;
      RTLCallReadLn=24;
      RTLCallEOF=28;
      RTLCallEOLn=32;
      RTLCallSysOpen=36;
      RTLCallSysRead=40;
      RTLCallSysWrite=44;
      RTLCallSysSeek=48;
      RTLCallSysClose=52;
      RTLCallSysSize=56;
      { Params(index): the number of command-line arguments for a negative
        index, and the address of a NUL-terminated copy of one of them
        otherwise. One entry serves both ParamCount and ParamStr, which is
        why the count is asked for with an index rather than by its own call.
        Index 1 is the first argument; index 0 is the program itself, the path
        DOS ran it from, which is what a program that has to find a file
        beside its own image asks for. }
      RTLCallParams=60;
      { Intr(number, VAR regs): the record is the library's Registers type,
        fifteen integers in the order hxrtl.asm expects. }
      RTLCallIntr=64;
      { Alloc(size) and Free(address): one DPMI block, and the end of one.
        These are primitives a program may call and not what GetMem is made
        of - the heap takes one large block from the entry below and cuts it
        up - so a block from one pair is not a block for the other. }
      RTLCallSysAlloc=68;
      RTLCallSysFree=72;
      { AllocMax(VAR size): the largest block the host will give, with how
        large that is written back over the caller's variable. This is the
        library's heap, and the only entry here the compiler never emits: the
        library calls it, in the language, which is where a heap belongs. }
      RTLCallSysAllocMax=76;
      { Fill(address, count, value) and Move(source, dest, count): the two
        block operations, one byte at a time as far as a caller is concerned,
        which is what the runtime's repeated string instructions do them in. }
      RTLCallSysFill=80;
      RTLCallSysMove=84;

type { A string this file reads out of memory - the command line, and the name
       the compiler was run under - is the library's PChar, one character per
       cell with a NUL at the end, and it is stepped through four bytes at a
       time. The type is the library's because the library is spliced in above
       this point: the compiler's own reading puts it there, and the line that
       names the file puts it there for a compiler too old to read it in. }
     TAlfa=array[1..MaximalAlfa] of char;

     TIdent=record
      Name:TAlfa;
      Link:integer;
      TypeDefinition:integer;
      Kind:integer;
      Value:integer;
      VariableLevel:integer;
      VariableAddress:integer;
      ReferencedParameter:boolean;
      Offset:integer;
      FunctionLevel:integer;
      FunctionAddress:integer;
      LastParameter:integer;
      ReturnAddress:integer;
      Inside:boolean;
     end;

     TType=record
      Size:integer;
      Kind:integer;
      StartIndex:integer;
      EndIndex:integer;
      SubType:integer;
      Fields:integer;
     end;

     { The two tables that are asked for, as types, so that the compiler can
       hold a pointer to one. What it holds is the pointer: PrepareTables
       asks the host for the table itself when the compiler starts, and every
       access to an element goes through it. }
     TCodeArray=array[0..MaximalCodeSize] of integer;
     PCodeArray=^TCodeArray;

     TIdentArray=array[0..MaximalIdentifiers] of TIdent;
     PIdentArray=^TIdentArray;

     { The shapes the compiler writes more than once, named so that it writes
       them once. Every array or pointer written out where it is used costs an
       entry in the type table, every time it is written, and this source has
       to fit in the type table of the compiler that builds it, which is this
       compiler: 512 entries. A shape written six times is five entries that
       need not be spent, and a shape written out inline where a named one
       would do is an entry that has to be paid for by leaving another one out:
       if Error 134 (too many types) appears while this file is compiled, that
       is what has happened, and the answer is to name a shape that repeats.
       The names below were spent one at a time when the chain started from a
       compiler with 32 entries and this source used all 32 of them, and they
       are kept because a shape that repeats reads better named than written
       out. }
     TSourceLevelValues=array[0..MaximalSourceLevel] of integer;
     TSourceFileName=array[1..MaximalSourceName] of char;
     TString255=array[1..255] of char;

var CurrentChar:char;
    CurrentColumn:integer;
    CurrentLine:integer;
    CurrentSymbol:integer;
    CurrentIdentifer:TAlfa;
    CurrentNumber:integer;
    CurrentString:TString255;
    CurrentStringLength:integer;
    SourceLevel:integer;
    SourceHandle:TSourceLevelValues;
    SourceBuffer:array[1..MaximalSourceBuffer] of char;
    SourceBufferPos:TSourceLevelValues;
    SourceBufferLen:TSourceLevelValues;
    SourceLine:TSourceLevelValues;
    SourceColumn:TSourceLevelValues;
    SourceName:array[0..MaximalSourceLevel] of TSourceFileName;
    SourceNameLength:TSourceLevelValues;
    SourceNewName:TSourceFileName;
    SourceNewNameLength:integer;
    SourceIncludeName:TSourceFileName;
    SourceIncludeNameLength:integer;
    { The file at the top of the source stack was read in by the compiler
      itself, before the program's first line, rather than named by a
      directive. Where the program carries on when it ends is not the same for
      the two: a directive leaves its closing brace behind for the reader to
      get past, and this leaves a character the parser has not looked at yet,
      which has to be the character the reader answers with. }
    SourceSilent:boolean;
    { The base name of that file - the library - so that a directive naming it
      again can be told to do nothing. It is compared by base name because the
      program may name it from anywhere: beside itself, over a path, or in
      whatever case it likes. }
    SourceLibraryName:TSourceFileName;
    SourceLibraryNameLength:integer;
    { Where the compiler itself is, which is the last place the library is
      looked for and the place a program in another directory finds it. }
    SourceCompilerDir:TSourceFileName;
    SourceCompilerDirLength:integer;
    FunctionDeclarationIndex:integer;
    Keywords:array[SymBEGIN..SymSHR] of TAlfa;
    LastOpcode:integer;
    CurrentLevel:integer;
    IsLabeled:boolean;
    SymbolNameList:array[-1..MaximalList] of integer;
    IdentifierPosition:integer;
    TypePosition:integer;
    Identifiers:PIdentArray;
    Types:array[1..MaximalTypes] of TType;
    Code:PCodeArray;
    { One cell of each table, twice over. The language has no SizeOf, and what
      the host has to be asked for is a number of bytes - for a table that is
      asked for, the size of its block; for the type table, which stays in the
      frame, how far its clearing runs - so the size of a cell is measured
      instead: two cells of a kind laid end to end are one cell apart,
      whatever the kind is made of. }
    CodeCell:array[0..1] of integer;
    IdentCell:array[0..1] of TIdent;
    TypeCell:array[0..1] of TType;
    CodePosition:integer;
    StackPosition:integer;

function StringCompare(var s1,s2:TAlfa):boolean;
var f:boolean;
    i:integer;
begin
 f:=true;
 i:=1;
 while f and (i<=MaximalAlfa) do begin
  f:=(s1[i]=s2[i]);
  i:=i+1;
 end;
 StringCompare:=f;
end;

procedure StringCopy(var Dest:TAlfa;Src:TAlfa);
begin
 Dest:=Src;
end;

procedure Error(n:integer);
var i:integer;
begin
 Write('Error ',n:1,': ');
 case n of
  TokIdent:begin
   Write('Identifier expected');
  end;
  TokNumber:begin
   Write('Number expected');
  end;
  TokStrC:begin
   Write('String expected');
  end;
  TokPlus:begin
   Write('"+" expected');
  end;
  TokMinus:begin
   Write('"-" expected');
  end;
  TokMul:begin
   Write('"*" expected');
  end;
  TokLBracket:begin
   Write('"[" expected');
  end;
  TokRBracket:begin
   Write('"]" expected');
  end;
  TokColon:begin
   Write('":" expected');
  end;
  TokEql:begin
   Write('"=" expected');
  end;
  TokNEq:begin
   Write('"<>" expected');
  end;
  TokLss:begin
   Write('"<" expected');
  end;
  TokLEq:begin
   Write('"<=" expected');
  end;
  TokGtr:begin
   Write('">" expected');
  end;
  TokGEq:begin
   Write('">=" expected');
  end;
  TokLParent:begin
   Write('"(" expected');
  end;
  TokRParent:begin
   Write('")" expected');
  end;
  TokComma:begin
   Write('"," expected');
  end;
  TokSemi:begin
   Write('";" expected');
  end;
  TokPeriod:begin
   Write('"." expected');
  end;
  TokAssign:begin
   Write('":=" expected');
  end;
  SymBEGIN:begin
   Write('"begin" expected');
  end;
  SymEND:begin
   Write('"end" expected');
  end;
  SymIF:begin
   Write('"if" expected');
  end;
  SymTHEN:begin
   Write('"then" expected');
  end;
  SymELSE:begin
   Write('"else" expected');
  end;
  SymWHILE:begin
   Write('"else" expected');
  end;
  SymDO:begin
   Write('"do" expected');
  end;
  SymCASE:begin
   Write('"case" expected');
  end;
  SymREPEAT:begin
   Write('"repeat" expected');
  end;
  SymUNTIL:begin
   Write('"until" expected');
  end;
  SymFOR:begin
   Write('"for" expected');
  end;
  SymTO:begin
   Write('"to" expected');
  end;
  SymDOWNTO:begin
   Write('"downto" expected');
  end;
  SymNOT:begin
   Write('"not" expected');
  end;
  SymDIV:begin
   Write('"div" expected');
  end;
  SymMOD:begin
   Write('"mod" expected');
  end;
  SymAND:begin
   Write('"and" expected');
  end;
  SymOR:begin
   Write('"or" expected');
  end;
  SymCONST:begin
   Write('"const" expected');
  end;
  SymVAR:begin
   Write('"var" expected');
  end;
  SymTYPE:begin
   Write('"type" expected');
  end;
  SymARRAY:begin
   Write('"array" expected');
  end;
  SymOF:begin
   Write('"of" expected');
  end;
  SymPACKED:begin
   Write('"packed" expected');
  end;
  SymRECORD:begin
   Write('"record" expected');
  end;
  SymPROGRAM:begin
   Write('"program" expected');
  end;
  SymFORWARD:begin
   Write('"forward" expected');
  end;
  SymHALT:begin
   Write('"halt" expected');
  end;
  SymFUNC:begin
   Write('"function" expected');
  end;
  SymPROC:begin
   Write('"procedure" expected');
  end;
  100:begin
   Write('String literal must be closed');
  end;
  101:begin
   Write('String is empty');
  end;
  102:begin
   Write('Bad char');
  end;
  103:begin
   Write('Too many identifiers');
  end;
  104:begin
   Write('Duplicate identifier');
  end;
  105:begin
   Write('Duplicate procedure/function');
  end;
  106:begin
   Write('Unknown identifiers');
  end;
  107:begin
   Write('Invalid type');
  end;
  108:begin
   Write('Record type expected');
  end;
  109:begin
   Write('Unknown field');
  end;
  110:begin
   Write('Array type expected');
  end;
  111:begin
   Write('Non-writeable type');
  end;
  112:begin
   Write('Non-readable type');
  end;
  113:begin
   Write('Too many argumnts');
  end;
  114:begin
   Write('Passing string to var argument isn''t allowed');
  end;
  115:begin
   Write('Passing string to non-array argument isn''t allowed');
  end;
  116:begin
   Write('Passing string to non-char-array argument isn''t allowed');
  end;
  117:begin
   Write('Passing string to wrong sized char-array argument isn''t allowed');
  end;
  118:begin
   Write('Too few argumnts');
  end;
  119:begin
   Write('Procedure calls inside a expression aren''t allowed');
  end;
  120:begin
   Write('Type inside a expression isn''t allowed');
  end;
  121:begin
   Write('Expression expected');
  end;
  122:begin
   Write('Illegal assigning to function');
  end;
  123:begin
   Write('Illegal assigning to constant or type');
  end;
  124:begin
   Write('Case expression must be constant');
  end;
  125:begin
   Write('Case expression expected');
  end;
  126:begin
   Write('":" expected');
  end;
  127:begin
   Write('Variable after "FOR" expected');
  end;
  128:begin
   Write('Incorrect iterator type');
  end;
  129:begin
   Write('"TO" or "DOWNTO" expected');
  end;
  130:begin
   Write('Constant expected');
  end;
  131:begin
   Write('Identifier or number literal expected');
  end;
  132:begin
   Write('First index of array must be less or equal then last');
  end;
  133:begin
   Write('Type expected');
  end;
  134:begin
   Write('Too many types');
  end;
  135:begin
   Write('Too many nested records');
  end;
  136:begin
   Write('Too many nested procedures');
  end;
  137:begin
   Write('Invalid function return type');
  end;
  138:begin
   Write('Too many arguments then at forward declaration');
  end;
  139:begin
   Write('Argument name doesn''t match forward declaration');
  end;
  140:begin
   Write('Argument type doesn''t match forward declaration');
  end;
  141:begin
   Write('Argument var doesn''t match forward declaration');
  end;
  142:begin
   Write('Too less arguments then at forward declaration');
  end;
  143:begin
   Write('Already forward declared');
  end;
  144:begin
   Write('No definition for forward declared');
  end;
  145:begin
   Write('Internal negative retn');
  end;
  146:begin
   Write('Binary is too big');
  end;
  147:begin
   Write('String is too long');
  end;
  148:begin
   Write('Too many cases');
  end;
  149:begin
   Write('Too large code');
  end;
  150:begin
   Write('Incompatible types');
  end;
  151:begin
   Write('Too many open files');
  end;
  152:begin
   Write('File already open');
  end;
  153:begin
   Write('Inline byte out of range');
  end;
  154:begin
   Write('Inline block too long');
  end;
  155:begin
   Write('Cannot open include file');
  end;
  156:begin
   Write('Include file name expected');
  end;
  157:begin
   Write('Pointer type expected');
  end;
  158:begin
   Write('Cannot find rtldos.pas');
  end;
  159:begin
   Write('Routine the library must declare is missing');
  end;
 end;
 { Which file the line and the column belong to: an include has a name and
   the input stream has none. }
 Write(' in ');
 if SourceNameLength[SourceLevel]=0 then begin
  Write('<input>');
 end else begin
  i:=1;
  while i<=SourceNameLength[SourceLevel] do begin
   Write(SourceName[SourceLevel,i]);
   i:=i+1;
  end;
 end;
 WriteLn(' at line ',CurrentLine:1,' at column ',CurrentColumn:1);
 Halt;
end;

{ Read the next buffer of the file at the top of the source stack. Nothing is
  read from the input stream this way: it is read a character at a time, the
  way it always was. }
procedure SourceFill;
var n:integer;
begin
 n:=SysRead(SourceHandle[SourceLevel],Addr(SourceBuffer[SourceLevel*SourceBufferSize+1]),SourceBufferSize);
 if n<0 then begin
  n:=0;
 end;
 SourceBufferLen[SourceLevel]:=n;
 SourceBufferPos[SourceLevel]:=1;
end;

{ The one character that follows an include directive is its closing brace.
  The brace is read to get past it and thrown away: it is not program text,
  and it is still in the file when the include it belongs to ends. }
procedure SourceDiscard;
begin
 if SourceBufferPos[SourceLevel]>SourceBufferLen[SourceLevel] then begin
  SourceFill;
 end;
 if SourceBufferLen[SourceLevel]>0 then begin
  SourceBufferPos[SourceLevel]:=SourceBufferPos[SourceLevel]+1;
 end;
end;

{ The file at the top of the source stack has nothing left to give. An include
  is closed and the file that named it carries on where the directive was -
  one character on, which is where SourceDiscard has just put it. The main
  source has simply ended, and answers with #0 from here on, as it always
  did.

  A file the compiler read in itself leaves no brace to get past: the
  character in CurrentChar is one of the file underneath, read but not yet
  looked at, and it is left alone - both here and in the reader, which is
  what SourceSilent is for. }
procedure SourceEmpty;
begin
 if SourceLevel=0 then begin
  SourceBufferLen[0]:=0;
 end else begin
  SysClose(SourceHandle[SourceLevel]);
  SourceLevel:=SourceLevel-1;
  CurrentLine:=SourceLine[SourceLevel];
  CurrentColumn:=SourceColumn[SourceLevel];
  if SourceSilent then begin
   { No brace to get past, but the character the reader comes back to has to
     be there to be read: the buffer the file underneath was being read out of
     may have run out at exactly this one. }
   if SourceBufferPos[SourceLevel]>SourceBufferLen[SourceLevel] then begin
    SourceFill;
   end;
  end else begin
   { The line and the column that were saved are where the name in the
     directive ended, and the brace that ends the directive is one character
     on - the character SourceDiscard throws away. It is not program text, but
     it is a character of the line the reader has come back to, so the column
     has to count it: without this, every diagnostic on the line of an include
     points one character to the left of what it is about. }
   SourceDiscard;
   CurrentColumn:=CurrentColumn+1;
  end;
 end;
end;

procedure ReadChar;
var Done:boolean;
begin
 Done:=false;
 while not Done do begin
  if SourceBufferPos[SourceLevel]>SourceBufferLen[SourceLevel] then begin
   SourceFill;
   if SourceBufferLen[SourceLevel]=0 then begin
    SourceEmpty;
    if SourceSilent then begin
     { The file that has just been closed is the one the compiler read in
       itself, so the character to answer with is the one already standing in
       CurrentChar: it came from the file underneath and the parser has not
       looked at it. Nothing is read here and the position stays one past
       that character, so the file underneath carries on from exactly where
       the include found it. }
     SourceSilent:=false;
     Done:=true;
    end;
   end;
  end;
  if not Done then begin
   if SourceBufferLen[SourceLevel]>0 then begin
    CurrentChar:=SourceBuffer[SourceLevel*SourceBufferSize+SourceBufferPos[SourceLevel]];
    SourceBufferPos[SourceLevel]:=SourceBufferPos[SourceLevel]+1;
    Done:=true;
   end else if SourceLevel=0 then begin
    { The main source has nothing left to give, and it answers with #0 from
      here on, which is what the parser ends on. An include that ends here was
      closed by SourceEmpty and what is left is the file that named it; only
      the main source can be at the end with nothing under it. }
    CurrentChar:=#0;
    Done:=true;
   end;
  end;
 end;
 CurrentColumn:=CurrentColumn+1;
 if CurrentChar=#10 then begin
  CurrentLine:=CurrentLine+1;
  CurrentColumn:=0;
 end;
end;

function ReadNumber:integer;
var Num:integer;
begin
 Num:=0;
 if ('0'<=CurrentChar) and (CurrentChar<='9') then begin
  while ('0'<=CurrentChar) and (CurrentChar<='9') do begin
   Num:=(Num*10)+(ord(CurrentChar)-ord('0'));
   ReadChar;
  end;
 end else if CurrentChar='$' then begin
  ReadChar;
  while (('0'<=CurrentChar) and (CurrentChar<='9')) or
        (('a'<=CurrentChar) and (CurrentChar<='f')) or
        (('A'<=CurrentChar) and (CurrentChar<='F')) do begin
   if ('0'<=CurrentChar) and (CurrentChar<='9') then begin
    Num:=(Num shl 4)+(ord(CurrentChar)-ord('0'));
   end else if ('a'<=CurrentChar) and (CurrentChar<='f') then begin
    Num:=(Num shl 4)+(ord(CurrentChar)-ord('a')+10);
   end else if ('A'<=CurrentChar) and (CurrentChar<='F') then begin
    Num:=(Num shl 4)+(ord(CurrentChar)-ord('A')+10);
   end;
   ReadChar;
  end;
 end;
 ReadNumber:=Num;
end;

{ Upper case, for comparing file names: DOS does not care about their case,
  and neither does this. }
function SourceUpper(c:char):char;
begin
 if ('a'<=c) and (c<='z') then begin
  SourceUpper:=chr(ord(c)-32);
 end else begin
  SourceUpper:=c;
 end;
end;

{ Is this the character a directory ends with? Both of the separators DOS
  takes, and the colon that ends a drive. }
function SourceSep(c:char):boolean;
begin
 SourceSep:=(c='\') or (c='/') or (c=':')
end;

{ Where the base name of a name begins - its directory dropped. }
function SourceBase(var Name:TSourceFileName;NameLength:integer):integer;
var i,Start:integer;
begin
 Start:=1;
 for i:=1 to NameLength do begin
  if SourceSep(Name[i]) then begin
   Start:=i+1;
  end;
 end;
 SourceBase:=Start
end;

{ Is the name the directive has just read the library the compiler read in
  itself? Base names are compared, without regard to case, which is what makes
  a program that still names the library - from beside itself, over a path, in
  whatever case - name the file that has already been read, and so read
  nothing. }
function SourceIsLibrary:boolean;
var i,Start,Len:integer;
    Same:boolean;
begin
 SourceIsLibrary:=false;
 if SourceLibraryNameLength>0 then begin
  Start:=SourceBase(SourceIncludeName,SourceIncludeNameLength);
  Len:=SourceIncludeNameLength-Start+1;
  Same:=Len=SourceLibraryNameLength;
  i:=1;
  while Same and (i<=Len) do begin
   if SourceUpper(SourceIncludeName[Start+i-1])<>SourceUpper(SourceLibraryName[i]) then begin
    Same:=false;
   end;
   i:=i+1;
  end;
  SourceIsLibrary:=Same;
 end;
end;

{ Is the file the directive names already open? Its name is in SourceNewName,
  resolved the way the name of every open file was, so two names of the same
  shape are being compared - and the input stream, which has no name, matches
  nothing. A file that includes itself, or a cycle of two files, is an error
  rather than a hang. }
function SourceOnStack:boolean;
var i,j:integer;
    Same:boolean;
begin
 SourceOnStack:=false;
 for i:=0 to SourceLevel do begin
  if (SourceNameLength[i]>0) and (SourceNameLength[i]=SourceNewNameLength) then begin
   Same:=true;
   for j:=1 to SourceNewNameLength do begin
    if SourceUpper(SourceName[i,j])<>SourceUpper(SourceNewName[j]) then begin
     Same:=false;
    end;
   end;
   if Same then begin
    SourceOnStack:=true;
   end;
  end;
 end;
end;

{ The long spelling of the include directive, $INCLUDE name where $I name
  also does. The I has been read and the character after it is in
  CurrentChar; this eats the rest of the word when it is that spelling. When
  it is not, the reader is left somewhere inside the directive, which is all
  the caller needs: anything else that begins with I - $IFDEF is the one that
  matters - is skipped to the closing brace either way, and only the two
  spellings above name a file. }
function SourceIncludeWord:boolean;
begin
 SourceIncludeWord:=false;
 if (CurrentChar='N') or (CurrentChar='n') then begin
  ReadChar;
  if (CurrentChar='C') or (CurrentChar='c') then begin
   ReadChar;
   if (CurrentChar='L') or (CurrentChar='l') then begin
    ReadChar;
    if (CurrentChar='U') or (CurrentChar='u') then begin
     ReadChar;
     if (CurrentChar='D') or (CurrentChar='d') then begin
      ReadChar;
      if (CurrentChar='E') or (CurrentChar='e') then begin
       ReadChar;
       SourceIncludeWord:=true;
      end;
     end;
    end;
   end;
  end;
 end;
end;

{ Open the file SourceIncludeName and enter it: from here until it ends, the
  text being read is its text, and then the file that named it carries on
  where the directive was.

  The name is looked for beside the file that names it first, which is how a
  program in a subdirectory includes a file that sits beside it, and then as
  written, which is how a name relative to the current directory is spelled.
  The library is looked for in a third place, beside the compiler: it is the
  one file that belongs to the compiler rather than to the program, and the
  program may be anywhere. }
procedure SourceOpenInclude(Library:boolean);
var i,j,Depth:integer;
begin
 { the directory the naming file is in, if it has one }
 j:=0;
 for i:=1 to SourceNameLength[SourceLevel] do begin
  if (SourceName[SourceLevel,i]='\') or (SourceName[SourceLevel,i]='/') or (SourceName[SourceLevel,i]=':') then begin
   j:=i;
  end;
 end;
 SourceNewNameLength:=0;
 for i:=1 to j do begin
  if SourceNewNameLength<MaximalSourceName then begin
   SourceNewNameLength:=SourceNewNameLength+1;
   SourceNewName[SourceNewNameLength]:=SourceName[SourceLevel,i];
  end;
 end;
 for i:=1 to SourceIncludeNameLength do begin
  if SourceNewNameLength<MaximalSourceName then begin
   SourceNewNameLength:=SourceNewNameLength+1;
   SourceNewName[SourceNewNameLength]:=SourceIncludeName[i];
  end;
 end;
 Depth:=SourceLevel+1;
 if Depth>MaximalSourceLevel then begin
  Error(151);
 end;
 if SourceOnStack then begin
  Error(152);
 end;
 SourceHandle[Depth]:=SysOpen(Addr(SourceNewName[1]),SourceNewNameLength,0);
 if SourceHandle[Depth]<0 then begin
  SourceHandle[Depth]:=SysOpen(Addr(SourceIncludeName[1]),SourceIncludeNameLength,0);
 end;
 if (SourceHandle[Depth]<0) and Library then begin
  { Beside the compiler, which is where the library lives when the program
    being compiled is somewhere else. The name beside the program is not
    looked at again: this is another place entirely, so the name is built
    from scratch. An empty compiler directory leaves the name as written,
    which is looked for where the current directory says. }
  SourceNewNameLength:=0;
  for i:=1 to SourceCompilerDirLength do begin
   if SourceNewNameLength<MaximalSourceName then begin
    SourceNewNameLength:=SourceNewNameLength+1;
    SourceNewName[SourceNewNameLength]:=SourceCompilerDir[i];
   end;
  end;
  for i:=1 to SourceIncludeNameLength do begin
   if SourceNewNameLength<MaximalSourceName then begin
    SourceNewNameLength:=SourceNewNameLength+1;
    SourceNewName[SourceNewNameLength]:=SourceIncludeName[i];
   end;
  end;
  SourceHandle[Depth]:=SysOpen(Addr(SourceNewName[1]),SourceNewNameLength,0);
 end;
 if SourceHandle[Depth]<0 then begin
  if Library then begin
   Error(158);
  end else begin
   Error(155);
  end;
 end;
 { the line to come back to, and the numbering of the file that is entered }
 SourceLine[SourceLevel]:=CurrentLine;
 SourceColumn[SourceLevel]:=CurrentColumn;
 SourceLevel:=Depth;
 SourceNameLength[SourceLevel]:=SourceNewNameLength;
 for i:=1 to SourceNewNameLength do begin
  SourceName[SourceLevel,i]:=SourceNewName[i];
 end;
 SourceBufferPos[SourceLevel]:=1;
 SourceBufferLen[SourceLevel]:=0;
 CurrentLine:=1;
 CurrentColumn:=0;
 ReadChar;
end;

{ The include directive, $I name: the text of another file, spliced in where
  it stands.

  The name runs to the closing brace, so a quoted name may contain blanks; a
  name with no extension gets .pas. The closing brace is left in the file: it
  is read when the include ends and the file that named it carries on.

  One name does nothing at all, and that name is the library's. The compiler
  reads the library in itself, before the program's first line, and a program
  that names it anyway is naming a file that has already been read: the
  directive is got past, and what it named is not opened a second time. What
  is left of the directive is got past exactly as the end of an include is, so
  that a program which names the library reads on from the same character as
  one that does not. }
procedure IncludeFile;
var i,j:integer;
begin
 SourceIncludeNameLength:=0;
 while (CurrentChar<>'}') and (CurrentChar<>#0) do begin
  if SourceIncludeNameLength<MaximalSourceName then begin
   SourceIncludeNameLength:=SourceIncludeNameLength+1;
   SourceIncludeName[SourceIncludeNameLength]:=CurrentChar;
  end;
  ReadChar;
 end;
 { the blank padding and the quotes around the name are not part of it }
 while (SourceIncludeNameLength>0) and ((SourceIncludeName[1]=' ') or (SourceIncludeName[1]=#9)) do begin
  for i:=1 to SourceIncludeNameLength-1 do begin
   SourceIncludeName[i]:=SourceIncludeName[i+1];
  end;
  SourceIncludeNameLength:=SourceIncludeNameLength-1;
 end;
 while (SourceIncludeNameLength>0) and ((SourceIncludeName[SourceIncludeNameLength]=' ') or (SourceIncludeName[SourceIncludeNameLength]=#9)) do begin
  SourceIncludeNameLength:=SourceIncludeNameLength-1;
 end;
 if (SourceIncludeNameLength>=2) and (SourceIncludeName[1]='''') and (SourceIncludeName[SourceIncludeNameLength]='''') then begin
  for i:=1 to SourceIncludeNameLength-2 do begin
   SourceIncludeName[i]:=SourceIncludeName[i+1];
  end;
  SourceIncludeNameLength:=SourceIncludeNameLength-2;
 end;
 if SourceIncludeNameLength=0 then begin
  Error(156);
 end;
 { .pas is what a name with no extension means; a dot anywhere after the last
   separator is an extension, whether this compiler knows it or not }
 j:=0;
 for i:=1 to SourceIncludeNameLength do begin
  if SourceSep(SourceIncludeName[i]) then begin
   j:=0;
  end else if SourceIncludeName[i]='.' then begin
   j:=i;
  end;
 end;
 if j=0 then begin
  if SourceIncludeNameLength+4<=MaximalSourceName then begin
   SourceIncludeName[SourceIncludeNameLength+1]:='.';
   SourceIncludeName[SourceIncludeNameLength+2]:='p';
   SourceIncludeName[SourceIncludeNameLength+3]:='a';
   SourceIncludeName[SourceIncludeNameLength+4]:='s';
   SourceIncludeNameLength:=SourceIncludeNameLength+4;
  end;
 end;
 if SourceIsLibrary then begin
  { the brace is the character standing in CurrentChar, and what the parser
    wants next is the one after it: the directive is left behind as an include
    that has just ended leaves it }
  SourceDiscard;
  CurrentColumn:=CurrentColumn+1;
  ReadChar;
 end else begin
  SourceOpenInclude(false);
 end;
end;

{ The library, read in before the program's first line.

  It is the file that holds what every program needs and that no program
  should have to write out: the strings, the DOS calls, the files, the heap.
  Reading it in here rather than leaving it to a directive is what makes it
  part of the language instead of part of the program, and it is read in the
  same way a directive reads a file - the same search, the same level on the
  source stack - so that a program which names it as well is naming this file
  and not another.

  It is looked for beside the program first, so that a program may keep a copy
  of its own, and beside the compiler last, which is where it lives when the
  program is elsewhere. The compiler's own directory comes from the name it
  was run under, which is the only place a DOS program can learn it. }
procedure IncludeLibrary;
var i,Len:integer;
    src:PChar;
begin
 SourceCompilerDirLength:=0;
 src:=ParamStr(0);
 if src<>0 then begin
  Len:=0;
  while src^<>#0 do begin
   if Len<MaximalSourceName then begin
    Len:=Len+1;
    SourceCompilerDir[Len]:=src^;
   end;
   src:=src+4;
  end;
  { everything up to and including the last separator: what a name appended
    to it wants. A name with no separator in it - the compiler run as BTCPC
    from its own directory - leaves nothing, and then the library is looked
    for where the current directory says. }
  for i:=1 to Len do begin
   if SourceSep(SourceCompilerDir[i]) then begin
    SourceCompilerDirLength:=i;
   end;
  end;
 end;
 SourceIncludeName[1]:='r';
 SourceIncludeName[2]:='t';
 SourceIncludeName[3]:='l';
 SourceIncludeName[4]:='d';
 SourceIncludeName[5]:='o';
 SourceIncludeName[6]:='s';
 SourceIncludeName[7]:='.';
 SourceIncludeName[8]:='p';
 SourceIncludeName[9]:='a';
 SourceIncludeName[10]:='s';
 SourceIncludeNameLength:=10;
 SourceLibraryNameLength:=SourceIncludeNameLength;
 for i:=1 to SourceIncludeNameLength do begin
  SourceLibraryName[i]:=SourceUpper(SourceIncludeName[i]);
 end;
 { and the reader is told that what comes back when this file ends is the
   character the program was about to be read at, not the brace of a
   directive }
 SourceSilent:=true;
 SourceOpenInclude(true);
end;

procedure GetSymbol;
var k,s:integer;
    StrEnd,InStr:boolean;
    LastChar:char;
begin
 while (CurrentChar>#0) and (CurrentChar<=' ') do begin
  ReadChar;
 end;
 if (('a'<=CurrentChar) and (CurrentChar<='z')) or (('A'<=CurrentChar) and (CurrentChar<='Z')) then begin
  k:=0;
  while ((('a'<=CurrentChar) and (CurrentChar<='z')) or (('A'<=CurrentChar) and (CurrentChar<='Z')) or (('0'<=CurrentChar) and (CurrentChar<='9'))) or (CurrentChar='_') do begin
   if k<>MaximalAlfa then begin
    k:=k+1;
    if ('a'<=CurrentChar) and (CurrentChar<='z') then begin
     CurrentChar:=chr(ord(CurrentChar)-32);
    end;
    CurrentIdentifer[k]:=CurrentChar;
   end;
   ReadChar;
  end;
  while k<>MaximalAlfa do begin
   k:=k+1;
   CurrentIdentifer[k]:=' ';
  end;
  CurrentSymbol:=TokIdent;
  s:=SymBEGIN;
  { The bound is the last keyword, so a new keyword is one line in the
    declaration and one line of text here. }
  while s<=SymSHR do begin
   if StringCompare(Keywords[s],CurrentIdentifer) then begin
    CurrentSymbol:=s;
   end;
   s:=s+1;
  end;
 end else if (('0'<=CurrentChar) and (CurrentChar<='9')) or (CurrentChar='$') then begin
  CurrentSymbol:=TokNumber;
  CurrentNumber:=ReadNumber;
 end else if CurrentChar=':' then begin
  ReadChar;
  if CurrentChar='=' then begin
   ReadChar;
   CurrentSymbol:=TokAssign;
  end else begin
   CurrentSymbol:=TokColon;
  end;
 end else if CurrentChar='>' then begin
  ReadChar;
  if CurrentChar='=' then begin
   ReadChar;
   CurrentSymbol:=TokGEq;
  end else begin
   CurrentSymbol:=TokGtr;
  end;
 end else if CurrentChar='<' then begin
  ReadChar;
  if CurrentChar='=' then begin
   ReadChar;
   CurrentSymbol:=TokLEq;
  end else if CurrentChar='>' then begin
   ReadChar;
   CurrentSymbol:=TokNEq;
  end else begin
   CurrentSymbol:=TokLss;
  end;
 end else if CurrentChar='.' then begin
  ReadChar;
  if CurrentChar='.' then begin
   ReadChar;
   CurrentSymbol:=TokColon;
  end else begin
   CurrentSymbol:=TokPeriod
  end;
 end else if (CurrentChar='''') or (CurrentChar='#') then begin
  CurrentStringLength:=0;
  StrEnd:=false;
  InStr:=false;
  CurrentSymbol:=TokStrC;
  while not StrEnd do begin
   if InStr then begin
    if CurrentChar='''' then begin
     ReadChar;
     if CurrentChar='''' then begin
      if CurrentStringLength=MaximalStringLength then begin
       Error(147);
      end;
      CurrentStringLength:=CurrentStringLength+1;
      CurrentString[CurrentStringLength]:=CurrentChar;
      ReadChar;
     end else begin
      InStr:=false;
     end;
    end else if (CurrentChar=#13) or (CurrentChar=#10) then begin
     Error(100);
     StrEnd:=true;
    end else begin
      if CurrentStringLength=MaximalStringLength then begin
       Error(147);
      end;
     CurrentStringLength:=CurrentStringLength+1;
     CurrentString[CurrentStringLength]:=CurrentChar;
     ReadChar;
    end;
   end else begin
    if CurrentChar='''' then begin
     InStr:=true;
     ReadChar;
    end else if CurrentChar='#' then begin
     ReadChar;
     if CurrentStringLength=MaximalStringLength then begin
      Error(147);
     end;
     CurrentStringLength:=CurrentStringLength+1;
     CurrentString[CurrentStringLength]:=chr(ReadNumber);
    end else begin
     StrEnd:=true;
    end;
   end;
  end;
  if CurrentStringLength=0 then begin
   Error(101);
  end;
 end else if CurrentChar='^' then begin
  ReadChar;
  CurrentSymbol:=TokPoint;
 end else if CurrentChar='+' then begin
  ReadChar;
  CurrentSymbol:=TokPlus;
 end else if CurrentChar='-' then begin
  ReadChar;
  CurrentSymbol:=TokMinus;
 end else if CurrentChar='*' then begin
  ReadChar;
  CurrentSymbol:=TokMul;
 end else if CurrentChar='(' then begin
  ReadChar;
  if CurrentChar='*' then begin
   ReadChar;
   LastChar:='-';
   while (CurrentChar<>#0) and not ((CurrentChar=')') and (LastChar='*')) do begin
    LastChar:=CurrentChar;
    ReadChar;
   end;
   ReadChar;
   GetSymbol;
  end else begin
   CurrentSymbol:=TokLParent;
  end;
 end else if CurrentChar=')' then begin
  ReadChar;
  CurrentSymbol:=TokRParent;
 end else if CurrentChar='[' then begin
  ReadChar;
  CurrentSymbol:=TokLBracket;
 end else if CurrentChar=']' then begin
  ReadChar;
  CurrentSymbol:=TokRBracket;
 end else if CurrentChar='=' then begin
  ReadChar;
  CurrentSymbol:=TokEql;
 end else if CurrentChar=',' then begin
  ReadChar;
  CurrentSymbol:=TokComma;
 end else if CurrentChar=';' then begin
  ReadChar;
  CurrentSymbol:=TokSemi;
 end else if CurrentChar='{' then begin
  ReadChar;
  if CurrentChar='$' then begin
   ReadChar;
   { A directive. Only the two spellings of the include directive name a
     file; every other one is skipped to its closing brace, exactly as it was
     when a directive was nothing but a comment. }
   if (CurrentChar='I') or (CurrentChar='i') then begin
    ReadChar;
    if (CurrentChar='+') or (CurrentChar='-') then begin
     { $I+ and $I- switch I/O checking on and off: a switch, not a name }
     while (CurrentChar<>'}') and (CurrentChar<>#0) do begin
      ReadChar;
     end;
     ReadChar;
     GetSymbol;
    end else if (CurrentChar=' ') or (CurrentChar=#9) or (CurrentChar='''') then begin
     IncludeFile;
     GetSymbol;
    end else if SourceIncludeWord then begin
     IncludeFile;
     GetSymbol;
    end else begin
     while (CurrentChar<>'}') and (CurrentChar<>#0) do begin
      ReadChar;
     end;
     ReadChar;
     GetSymbol;
    end;
   end else begin
    while (CurrentChar<>'}') and (CurrentChar<>#0) do begin
     ReadChar;
    end;
    ReadChar;
    GetSymbol;
   end;
  end else begin
   while (CurrentChar<>'}') and (CurrentChar<>#0) do begin
    ReadChar;
   end;
   ReadChar;
   GetSymbol;
  end;
 end else if CurrentChar='/' then begin
  ReadChar;
  if CurrentChar='/' then begin
   repeat
    ReadChar;
   until (CurrentChar=#10) or (CurrentChar=#0);
   GetSymbol;
  end else begin
   Error(102);
  end;
 end else begin
  Error(102);
 end;
end;

procedure Check(s:integer);
begin
 if CurrentSymbol<>s then begin
  Error(s);
 end;
end;

procedure Expect(s:integer);
begin
 Check(s);
 GetSymbol;
end;

procedure EnterSymbol(CurrentIdentifer:TAlfa;k,t:integer);
var j:integer;
begin
 if IdentifierPosition=MaximalIdentifiers then begin
  Error(103);
 end;
 IdentifierPosition:=IdentifierPosition+1;
 Identifiers^[0].Name:=CurrentIdentifer;
 j:=SymbolNameList[CurrentLevel];
 while not StringCompare(Identifiers^[j].Name,CurrentIdentifer) do begin
  j:=Identifiers^[j].Link;
 end;
 if j<>0 then begin
  if Identifiers^[j].Kind<>IdFUNC then begin
   Error(104);
  end;
  if (Code^[Identifiers^[j].FunctionAddress]<>OPJmp) or (Code^[Identifiers^[j].FunctionAddress+1]>0) then begin
   Error(105);
  end;
  Identifiers^[j].Name[1]:='$';
  Code^[Identifiers^[j].FunctionAddress+1]:=CodePosition;
  FunctionDeclarationIndex:=j;
 end;
 Identifiers^[IdentifierPosition].Name:=CurrentIdentifer;
 Identifiers^[IdentifierPosition].Link:=SymbolNameList[CurrentLevel];
 Identifiers^[IdentifierPosition].TypeDefinition:=t;
 Identifiers^[IdentifierPosition].Kind:=k;
 SymbolNameList[CurrentLevel]:=IdentifierPosition;
end;

function Position:integer;
var i,j:integer;
begin
 Identifiers^[0].Name:=CurrentIdentifer;
 i:=CurrentLevel;
 repeat
  j:=SymbolNameList[i];
  while not StringCompare(Identifiers^[j].Name,CurrentIdentifer) do begin
   j:=Identifiers^[j].Link;
  end;
  i:=i-1;
 until (i<-1) or (j<>0);
 if j=0 then begin
  Error(106);
 end;
 Position:=j;
end;

procedure EmitCode(Value:integer);
begin
 if CodePosition>MaximalCodeSize then begin
  Error(149);
 end;
 Code^[CodePosition]:=Value;
 CodePosition:=CodePosition+1;
end;

procedure EmitOpcode(Opcode,a:integer);
begin
 case Opcode of
  OPDupl,OPEOF,OPEOL,OPLdC,OPLdA,OPLdLA,OPLdL,OPLdG:begin
   StackPosition:=StackPosition-4;
  end;
  OPNeg,OPDiv2,OPRem2,OPSwap,OPLoad,OPHalt,OPWrL,OPRdL,OpAddC,OPMulC,
  OPJmp,OPCall,OPExit:begin
  end;
  OPAdd,OPMul,OPDivD,OPRemD,OPEqlI,OPNEqI,OPLssI,OPLeqI,OPGtrI,OPGEqI,OPAndB,
  OPOrB,OPShl,OPShr,OPWrC,OPRdI,OPRdC,OPStL,OPStG,OPJZ:begin
   StackPosition:=StackPosition+4;
  end;
  OPStore,OPWrI,OPMove:begin
   StackPosition:=StackPosition+8;
  end;
  OPCopy:begin
   StackPosition:=StackPosition-(a-4);
  end;
  OPAdjS:begin
   StackPosition:=StackPosition+a;
  end;
 end;
 if not ((((Opcode=OPAddC) or (Opcode=OPAdjS)) and (a=0)) or ((Opcode=OPMulC) and (a=1))) then begin
  if IsLabeled then begin
   Code^[CodePosition]:=Opcode;
   CodePosition:=CodePosition+1;
   if Opcode>=OPLdC then begin
    Code^[CodePosition]:=a;
    CodePosition:=CodePosition+1;
   end;
   IsLabeled:=false;
  end else if (LastOpcode=OPLdC) and (Opcode=OPAdd) then begin
   Code^[CodePosition-2]:=OPAddC;
  end else if (LastOpcode=OPLdC) and (Opcode=OPMul) then begin
   Code^[CodePosition-2]:=OPMulC;
  end else if (LastOpcode=OPLdC) and (Opcode=OPNeg) then begin
   Code^[CodePosition-1]:=-Code^[CodePosition-1];
   Opcode:=LastOpcode;
  end else if (LastOpcode=OPLdC) and (Code^[CodePosition-1]=2) and (Opcode=OPDivD) then begin
   Code^[CodePosition-2]:=OPDiv2;
   CodePosition:=CodePosition-1;
  end else if (LastOpcode=OPLdC) and (Code^[CodePosition-1]=2) and (Opcode=OPRemD) then begin
   Code^[CodePosition-2]:=OPRem2;
   CodePosition:=CodePosition-1;
  end else if (LastOpcode=OPLdA) and (Opcode=OPStore) then begin
   Code^[CodePosition-2]:=OPStG;
  end else if (LastOpcode=OPLdA) and (Opcode=OPLoad) then begin
   Code^[CodePosition-2]:=OPLdG;
  end else if (LastOpcode=OPLdLA) and (Opcode=OPStore) then begin
   Code^[CodePosition-2]:=OPStL;
  end else if (LastOpcode=OPLdLA) and (Opcode=OPLoad) then begin
   Code^[CodePosition-2]:=OPLdL;
  end else begin
   EmitCode(Opcode);
   if Opcode>=OPLdC then begin
    EmitCode(a);
   end;
  end;
  LastOpcode:=Opcode;
 end;
end;

procedure EmitOpcode2(Opcode:integer);
begin
 EmitOpcode(Opcode,0);
end;

{ A call into the runtime's function table. The arguments are already on the
  stack, in source order, so the last one is on top - which is what the host
  code expects, because it reads them at fixed offsets above its return
  address. The host removes them itself (its RET carries the count), so nothing
  is emitted for the cleanup; what has to be fixed up here is the compiler's
  own idea of the stack, whose net change is the arguments gone and, for a
  function, the result left behind.

  The host hands its result back in EAX - that is what a DOS call and a Win32
  call both do, and it is what keeps the host free of the language's frame
  conventions - while everything else in the generated code expects a value to
  be on the stack. The PUSH EAX below is that translation, and it is why the
  host's own asm test can read the result straight out of EAX. }
procedure EmitRTL(Ofs,ArgumentBytes,ResultBytes:integer);
begin
 if ResultBytes<>0 then begin
  EmitOpcode(OPCallRTLValue,Ofs);
 end else begin
  EmitOpcode(OPCallRTL,Ofs);
 end;
 StackPosition:=StackPosition+ArgumentBytes-ResultBytes;
end;

function CodeLabel:integer;
begin
 CodeLabel:=CodePosition;
 IsLabeled:=true;
end;

procedure EmitAddress(Level,Address:integer);
begin
 if Level=0 then begin
  EmitOpcode(OPLdA,Address);
 end else if Level=CurrentLevel then begin
  EmitOpcode(OPLdLA,Address-StackPosition);
 end else begin
  EmitOpcode(OPLdL,-StackPosition);
  while Level+1<>CurrentLevel do begin
   EmitOpcode2(OPLoad);
   Level:=Level+1;
  end;
  EmitOpcode(OPAddC,Address);
 end;
end;

procedure EmitAddressVar(IdentifierIndex:integer);
begin
 EmitAddress(Identifiers^[IdentifierIndex].VariableLevel,Identifiers^[IdentifierIndex].VariableAddress);
 if Identifiers^[IdentifierIndex].ReferencedParameter then begin
  EmitOpcode2(OPLoad);
 end;
end;

procedure MustBe(x,y:integer);
begin
 if x<>y then begin
  if (Types[x].Kind=KindARRAY) and (Types[y].Kind=KindARRAY) and (Types[x].StartIndex=Types[y].StartIndex) and (Types[x].EndIndex=Types[y].EndIndex) then begin
   MustBe(Types[x].SubType,Types[y].SubType);
  end else if (Types[x].Kind=KindPOINTER) and (Types[y].Kind<>KindARRAY) and (Types[y].Kind<>KindRECORD) then begin
   { An address on one side and a pointer on the other. The language has no
     casts, so this is the only way to write p:=Addr(x) or p:=ParamStr(1) -
     and, since a pointer is an address and an integer is too, it costs
     nothing to allow. Two pointers of different types are compatible for the
     same reason: what is assigned is an address either way. }
  end else if (Types[y].Kind=KindPOINTER) and (Types[x].Kind<>KindARRAY) and (Types[x].Kind<>KindRECORD) then begin
  end else begin
   Error(107);
  end;
 end;
end;

procedure Expression(var x:integer); forward;

procedure Selector(var t,IdentifierIndex:integer);
var j,x:integer;
begin
 t:=Identifiers^[IdentifierIndex].TypeDefinition;
 GetSymbol;
 if (CurrentSymbol=TokPeriod) or (CurrentSymbol=TokLBracket) or (CurrentSymbol=TokPoint) then begin
  EmitAddressVar(IdentifierIndex);
  IdentifierIndex:=0;
  while (CurrentSymbol=TokPeriod) or (CurrentSymbol=TokLBracket) or (CurrentSymbol=TokPoint) do begin
   case CurrentSymbol of
    TokPeriod:begin
     if Types[t].Kind<>KindRECORD then begin
      Error(108);
     end;
     GetSymbol;
     Check(TokIdent);
     j:=Types[t].Fields;
     Identifiers^[0].Name:=CurrentIdentifer;
     while not StringCompare(Identifiers^[j].Name,CurrentIdentifer) do begin
      j:=Identifiers^[j].Link;
     end;
     if j=0 then begin
      Error(109);
     end;
     EmitOpcode(OPAddC,Identifiers^[j].Offset);
     t:=Identifiers^[j].TypeDefinition;
     GetSymbol;
    end;
    TokPoint:begin
     { P^: what P holds is where the value is. The address of P is on the
       stack by now, so loading it leaves the pointee's address - which is the
       same thing every other selector leaves, and the reason the statement
       and expression code above and below needs no case for pointers at all.
       A further selector may follow, and it will be taken against the
       pointee's type. }
     if Types[t].Kind<>KindPOINTER then begin
      Error(157);
     end;
     t:=Types[t].SubType;
     GetSymbol;
     EmitOpcode2(OPLoad);
    end;
    TokLBracket:begin
     repeat
      if Types[t].Kind<>KindARRAY then begin
       Error(110);
      end;
      GetSymbol;
      Expression(x);
      MustBe(TypeINT,x);
      EmitOpcode(OPAddC,-Types[t].StartIndex);
      t:=Types[t].SubType;
      EmitOpcode(OPMulC,Types[t].Size);
      EmitOpcode2(OPAdd);
     until CurrentSymbol<>TokComma;
     Expect(TokRBracket)
    end;
   end;
  end;
 end;
end;

procedure VarPar(var t:integer);
var j:integer;
begin
 Check(TokIdent);
 j:=Position;
 Selector(t,j);
 if j<>0 then begin
  EmitAddressVar(j);
 end;
end;

{ One integer argument of a runtime builtin, pushed the way any other operand
  is. The host's entries take and return plain integers, so there is nothing
  else a builtin's argument can be. }
procedure RTLArgument;
var x:integer;
begin
 Expression(x);
 MustBe(TypeINT,x);
end;

{ A routine the library declares, found by name. The library is read in
  before the program's first line, so by the time anything the program says is
  compiled its routines have been declared and a builtin that has to call one
  can find it here. New and Dispose are the two that do: what they add to a
  call to GetMem is the size, which only the type table knows, and GetMem
  itself is a routine in the library because a heap can be written in the
  language.

  The search is the parser's own - the level the compiler is at, downwards -
  so a program that declares its own GetMem gets it, and New and Dispose
  allocate through the program's allocator rather than behind its back. The
  name is compared in the sentinel cell 0, which is what makes the walk end. }
function LibraryRoutine(Name:TAlfa):integer;
var i,j:integer;
begin
 Identifiers^[0].Name:=Name;
 i:=CurrentLevel;
 repeat
  j:=SymbolNameList[i];
  while not StringCompare(Identifiers^[j].Name,Name) do begin
   j:=Identifiers^[j].Link;
  end;
  i:=i-1;
 until (i<-1) or (j<>0);
 if (j=0) or (Identifiers^[j].Kind<>IdFUNC) then begin
  Error(159);
 end;
 LibraryRoutine:=j;
end;

procedure InternalFunction(n:integer);
var x,j,k,OldStackPosition:integer;
begin
 case n of
  FunCHR:begin
   Expect(TokLParent);
   Expression(x);
   MustBe(TypeINT,x);
   Expect(TokRParent)
  end;
  FunORD:begin
   Expect(TokLParent);
   Expression(x);
   if x<>TypeBOOL then begin
    MustBe(TypeCHAR,x);
   end;
   Expect(TokRParent);
  end;
  FunWRITE,FunWRITELN:begin
   if n=FunWRITE then begin
    Check(TokLParent);
   end;
   if CurrentSymbol=TokLParent then begin
    repeat
     GetSymbol;
     if CurrentSymbol=TokStrC then begin
      x:=1;
      while x<=CurrentStringLength do begin
       EmitOpcode(OPLdC,ord(CurrentString[x]));
       EmitOpcode2(OPWrC);
       x:=x+1;
      end;
      GetSymbol;
     end else begin
      Expression(x);
      if CurrentSymbol=TokColon then begin
       MustBe(TypeINT,x);
       GetSymbol;
       Expression(x);
       MustBe(TypeINT,x);
       EmitOpcode2(OPWrI);
      end else if (x=TypeINT) or (Types[x].Kind=KindPOINTER) then begin
       { A pointer prints as the address it is, which is what makes one
         visible while a program is being written. }
       EmitOpcode(OPLdC,1);
       EmitOpcode2(OPWrI);
      end else if x=TypeCHAR then begin
       EmitOpcode2(OPWrC);
      end else begin
       Error(111);
      end;
     end;
    until CurrentSymbol<>TokComma;
    Expect(TokRParent)
   end;
   if n=FunWRITELN then begin
    EmitOpcode2(OPWrL);
   end; 
  end;
  FunREAD,FunREADLN:begin
   if n=FunREAD then begin
    Check(TokLParent);
   end;
   if CurrentSymbol=TokLParent then begin
    repeat
     GetSymbol;
     VarPar(x);
     if x=TypeINT then begin
      EmitOpcode2(OPRdI);
     end else if x=TypeCHAR then begin
      EmitOpcode2(OPRdC);
     end else begin
      Error(112);
     end;
    until CurrentSymbol<>TokComma;
    Expect(TokRParent);
   end;
   if n=FunREADLN then begin
    EmitOpcode2(OPRdL);
   end;
  end;
  FunEOF:begin
   EmitOpcode2(OPEOF);
  end;
  FunEOFLN:begin
   EmitOpcode2(OPEOL);
  end;
  { The file primitives. Their signatures are fixed, so the arguments are
    parsed here rather than through the identifier table's parameter list: a
    builtin has no parameters of its own. Everything is an integer - an
    address is an integer in this language, which is what lets a buffer or a
    name be passed without any kind of pointer type. }
  FunSYSOPEN:begin
   Expect(TokLParent);
   RTLArgument;
   Expect(TokComma);
   RTLArgument;
   Expect(TokComma);
   RTLArgument;
   Expect(TokRParent);
   EmitRTL(RTLCallSysOpen,12,4);
  end;
  FunSYSREAD:begin
   Expect(TokLParent);
   RTLArgument;
   Expect(TokComma);
   RTLArgument;
   Expect(TokComma);
   RTLArgument;
   Expect(TokRParent);
   EmitRTL(RTLCallSysRead,12,4);
  end;
  FunSYSWRITE:begin
   Expect(TokLParent);
   RTLArgument;
   Expect(TokComma);
   RTLArgument;
   Expect(TokComma);
   RTLArgument;
   Expect(TokRParent);
   EmitRTL(RTLCallSysWrite,12,4);
  end;
  FunSYSSEEK:begin
   Expect(TokLParent);
   RTLArgument;
   Expect(TokComma);
   RTLArgument;
   Expect(TokComma);
   RTLArgument;
   Expect(TokRParent);
   EmitRTL(RTLCallSysSeek,12,4);
  end;
  FunSYSCLOSE:begin
   Expect(TokLParent);
   RTLArgument;
   Expect(TokRParent);
   EmitRTL(RTLCallSysClose,4,4);
  end;
  FunSYSSIZE:begin
   Expect(TokLParent);
   RTLArgument;
   Expect(TokRParent);
   EmitRTL(RTLCallSysSize,4,4);
  end;
  { The command line, as one call: the address of a copy of argument i, or
    the number of arguments for a negative i. ParamStr and ParamCount are the
    two questions a Pascal program asks and the two the library declares; this
    is the one the host answers, and it is a builtin because an argument is
    read out of the environment block, which is not something the language
    reaches. }
  FunPARAMS:begin
   Expect(TokLParent);
   RTLArgument;
   Expect(TokRParent);
   EmitRTL(RTLCallParams,4,4);
  end;
  { Fill(address, count, value) and Move(source, dest, count): the block
    operations, which the host does with the repeated string instructions.
    The counts are bytes and the addresses are integers, as every address in
    this compiler is; the value of a fill is a char or an integer, because a
    char is four bytes here and either can be what a caller means by the byte
    it writes. The library's FillChar and Move are written over these two. }
  FunSYSFILL:begin
   Expect(TokLParent);
   RTLArgument;
   Expect(TokComma);
   RTLArgument;
   Expect(TokComma);
   Expression(x);
   if (x<>TypeCHAR) and (x<>TypeINT) then begin
    Error(107);
   end;
   Expect(TokRParent);
   EmitRTL(RTLCallSysFill,12,0);
  end;
  FunSYSMOVE:begin
   Expect(TokLParent);
   RTLArgument;
   Expect(TokComma);
   RTLArgument;
   Expect(TokComma);
   RTLArgument;
   Expect(TokRParent);
   EmitRTL(RTLCallSysMove,12,0);
  end;
  { Intr(i, r) - run an interrupt. The second argument is not a typed
    parameter of anything: the builtin only needs its address, and taking any
    variable is what keeps Registers a type the library declares rather than
    one the compiler has to know. Both arguments go on the stack in source
    order, the number first and the record's address on top, which is the
    order the host reads them in. }
  FunINTR:begin
   Expect(TokLParent);
   RTLArgument;
   Expect(TokComma);
   VarPar(x);
   Expect(TokRParent);
   EmitRTL(RTLCallIntr,8,0);
  end;
  { Addr(v) - the address of a variable, an array element or a record field.
    VarPar leaves exactly that on the stack: for a plain variable it emits the
    address, and for anything with a selector the address is what the selector
    code computes. The result is an integer, because an address is one. }
  FunADDR:begin
   Expect(TokLParent);
   VarPar(x);
   Expect(TokRParent);
  end;
  { The memory primitives, which are to New and Dispose what the file
    primitives are to the library's file calls: Alloc answers with the address
    of a block of at least the size asked for - 0 when the host will not give
    one - and Free takes a block back, answering 0 or -1 to say whether it
    could. A size of zero, or one too large to round, is nothing to hand out,
    so Alloc answers 0 rather than a block, and a caller that does not test the
    answer is writing into address zero, which is a fault rather than a
    silently wrong answer. }
  FunSYSALLOC:begin
   Expect(TokLParent);
   RTLArgument;
   Expect(TokRParent);
   EmitRTL(RTLCallSysAlloc,4,4);
  end;
  FunSYSFREE:begin
   Expect(TokLParent);
   RTLArgument;
   Expect(TokRParent);
   EmitRTL(RTLCallSysFree,4,4);
  end;
  { AllocMax(size) - the largest block the host will give, with how large it
    turned out written back over the caller's variable, and the answer 0 when
    the host will not give one at all. The variable is taken by reference
    because that is where the size has to come to rest: only the host knows
    what the largest free block is, and it is not a number the compiler could
    push, so there is nothing for a value parameter to be. }
  FunSYSALLOCMAX:begin
   Expect(TokLParent);
   VarPar(x);
   Expect(TokRParent);
   EmitRTL(RTLCallSysAllocMax,4,4);
  end;
  { New(p) and Dispose(p) - Turbo Pascal's two, in terms of the library's
    GetMem and FreeMem. The compiler is what knows the size: the type table
    has it, so a program never writes it down and cannot write it down wrong.
    Everything else about the two is the library's, which is what makes a
    program's own GetMem the allocator New uses - the call is written here the
    way FunctionCall writes one, so it is an ordinary call to an ordinary
    Pascal routine by the time the compiler is done with it.

    Dispose clears p, so that a second Dispose, or anything read through a
    pointer that outlived its block, meets a zero address instead of memory
    that is someone else's now. It is FreeMem that does the clearing, because
    FreeMem takes the pointer by reference and the compiler is what has the
    reference; a pointer that is a record field or an array element is the one
    case where there is none - the address the selector computed is spent by
    the time the block is given back, and asking the source for it again is
    not something this compiler can do - so the block goes back through the
    library's own free and the field keeps an address that is no longer
    anyone's, which is what the same program would do in Turbo Pascal, where
    Dispose takes the variable and not a copy of it. }
  FunNEW:begin
   Expect(TokLParent);
   Check(TokIdent);
   j:=Position;
   Selector(x,j);
   Expect(TokRParent);
   if Types[x].Kind<>KindPOINTER then begin
    Error(157);
   end;
   k:=LibraryRoutine('GETMEM              ');
   { The result slot first, then the argument, then the call: what the callee
     writes its answer into is under its argument, and its RET 4 leaves the
     answer where the slot was. }
   EmitOpcode(OPLdC,0);
   OldStackPosition:=StackPosition;
   EmitOpcode(OPLdC,Types[Types[x].SubType].Size);
   EmitOpcode(OPCall,Identifiers^[k].FunctionAddress);
   StackPosition:=OldStackPosition;
   { The address the result is stored through goes on last, which is the order
     every other store in this compiler is in - the value under the address -
     because that is the order the store instruction pops them in. }
   if j=0 then begin
    EmitOpcode2(OPSwap)
   end else begin
    EmitAddressVar(j)
   end;
   EmitOpcode2(OPStore);
  end;
  FunDISPOSE:begin
   Expect(TokLParent);
   Check(TokIdent);
   j:=Position;
   Selector(x,j);
   Expect(TokRParent);
   if Types[x].Kind<>KindPOINTER then begin
    Error(157);
   end;
   if j<>0 then begin
    { FreeMem(p): the variable itself, which it clears. A plain variable is
      the case where its address can be written down, and the selector has
      left nothing on the stack for one. }
    k:=LibraryRoutine('FREEMEM             ');
    OldStackPosition:=StackPosition;
    EmitAddressVar(j);
    EmitOpcode(OPCall,Identifiers^[k].FunctionAddress);
    StackPosition:=OldStackPosition;
   end else begin
    { RtlFreeBlock(p): the block and not the variable, which is all that can
      be named of a field or an element. It is the same free, without the
      clearing. }
    k:=LibraryRoutine('RTLFREEBLOCK        ');
    OldStackPosition:=StackPosition;
    EmitOpcode2(OPLoad);
    EmitOpcode(OPCall,Identifiers^[k].FunctionAddress);
    StackPosition:=OldStackPosition;
   end;
  end;
 end;
end;

procedure FunctionCall(i:integer);
var OldStackPosition,p,x:integer;
begin
 GetSymbol;
 if Identifiers^[i].FunctionLevel<0 then begin
  InternalFunction(Identifiers^[i].FunctionAddress);
 end else begin
  if Identifiers^[i].TypeDefinition<>0 then begin
   EmitOpcode(OPLdC,0);
  end;
  p:=i;
  OldStackPosition:=StackPosition;
  if CurrentSymbol=TokLParent then begin
   repeat
    GetSymbol;
    if p=Identifiers^[i].LastParameter then begin
     Error(113);
    end;
    p:=p+1;
    if Identifiers^[p].ReferencedParameter then begin
     VarPar(x);
    end else begin
     Expression(x);
     if (Types[x].Kind<>KindSIMPLE) and (Types[x].Kind<>KindPOINTER) then begin
      EmitOpcode(OPCopy,Types[x].Size);
     end;
    end;
    if x=TypeSTR then begin
     if Identifiers^[p].ReferencedParameter then begin
      Error(114);
     end;
     if Types[Identifiers^[p].TypeDefinition].Kind<>KindARRAY then begin
      Error(115);
     end;
     if Types[Identifiers^[p].TypeDefinition].SubType<>TypeCHAR then begin
      Error(116);
     end;
     if ((Types[Identifiers^[p].TypeDefinition].EndIndex-Types[Identifiers^[p].TypeDefinition].StartIndex)+1)<>CurrentStringLength then begin
      Error(117);
     end;
    end else begin
     MustBe(Identifiers^[p].TypeDefinition,x);
    end;
   until CurrentSymbol<>TokComma;
   Expect(TokRParent);
  end;
  if p<>Identifiers^[i].LastParameter then begin
   Error(118);
  end;
  if Identifiers^[i].FunctionLevel<>0 then begin
   EmitAddress(Identifiers^[i].FunctionLevel,0);
  end;
  EmitOpcode(OPCall,Identifiers^[i].FunctionAddress);
  StackPosition:=OldStackPosition;
 end;
end;

procedure Factor(var t:integer);
var i:integer;
begin
 if CurrentSymbol=TokIdent then begin
  i:=Position;
  t:=Identifiers^[i].TypeDefinition;
  case Identifiers^[i].Kind of
   IdCONST:begin
    GetSymbol;
    EmitOpcode(OPLdC,Identifiers^[i].Value);
   end;
   IdVAR:begin
    Selector(t,i);
    if i<>0 then begin
     EmitAddressVar(i);
    end;
    if (Types[t].Kind=KindSIMPLE) or (Types[t].Kind=KindPOINTER) then begin
     EmitOpcode2(OPLoad);
    end;
   end;
   IdFUNC:begin
    if t=0 then begin
     Error(119);
    end else begin
     FunctionCall(i);
    end;
   end;
   IdTYPE:begin
    Error(120);
   end;
  end;
 end else if CurrentSymbol=TokNumber then begin
  EmitOpcode(OPLdC,CurrentNumber);
  t:=TypeINT;
  GetSymbol;
 end  else if CurrentSymbol=TokStrC then begin
  i:=CurrentStringLength;
  while i>=1 do begin
   EmitOpcode(OPLdC,ord(CurrentString[i]));
   i:=i-1;
  end;
  t:=TypeCHAR;
  if CurrentStringLength<>1 then begin
   t:=TypeSTR;
  end;
  GetSymbol;
 end else if CurrentSymbol=TokLParent then begin
  GetSymbol;
  Expression(t);
  Expect(TokRParent);
 end else if CurrentSymbol=SymNOT then begin
  GetSymbol;
  Factor(t);
  MustBe(TypeBOOL,t);
  EmitOpcode2(OPNeg);
  EmitOpcode(OPAddC,1);
 end else begin
  Error(121);
 end;
end;

procedure Term(var x:integer);
var y:integer;
begin
 Factor(x);
 while (CurrentSymbol=SymAND) or (CurrentSymbol=TokMul) or (CurrentSymbol=SymDIV) or (CurrentSymbol=SymMOD) or (CurrentSymbol=SymSHL) or (CurrentSymbol=SymSHR) do begin
  if CurrentSymbol=SymAND then begin
   MustBe(TypeBOOL,x);
  end else begin
   MustBe(TypeINT,x);
  end;
  case CurrentSymbol of
   TokMul:begin
    GetSymbol;
    Factor(y);
    EmitOpcode2(OPMul);
   end;
   SymDIV:begin
    GetSymbol;
    Factor(y);
    EmitOpcode2(OPDivD);
   end;
   SymMOD:begin
    GetSymbol;
    Factor(y);
    EmitOpcode2(OPRemD);
   end;
   SymAND:begin
    GetSymbol;
    Factor(y);
    EmitOpcode2(OPAndB);
   end;
   SymSHL:begin
    GetSymbol;
    Factor(y);
    EmitOpcode2(OPShl);
   end;
   SymSHR:begin
    GetSymbol;
    Factor(y);
    EmitOpcode2(OPShr);
   end;
  end;
  MustBe(x,y);
 end;
end;

procedure SimpleExpression(var x:integer);
var y:integer;
begin
 if CurrentSymbol=TokPlus then begin
  GetSymbol;
  Term(x);
  MustBe(TypeINT,x);
 end else if CurrentSymbol=TokMinus then begin
  GetSymbol;
  Term(x);
  MustBe(TypeINT,x);
  EmitOpcode2(OPNeg);
 end else begin
  Term(x);
 end;
 while (CurrentSymbol=SymOR) or (CurrentSymbol=TokPlus) or (CurrentSymbol=TokMinus) do begin
  if CurrentSymbol=SymOR then begin
   MustBe(TypeBOOL,x);
  end else begin
   MustBe(TypeINT,x);
  end;
  case CurrentSymbol of
   TokPlus:begin
    GetSymbol;
    Term(y);
    EmitOpcode2(OPAdd);
   end;
   TokMinus:begin
    GetSymbol;
    Term(y);
    EmitOpcode2(OPNeg);
    EmitOpcode2(OPAdd);
   end;
   SymOR:begin
    GetSymbol;
    Term(y);
    EmitOpcode2(OPOrB);
   end;
  end;
  MustBe(x,y);
 end;
end;

procedure Expression(var x:integer);
var o,y:integer;
begin
 SimpleExpression(x);
 if (CurrentSymbol=TokEql) or (CurrentSymbol=TokNEq) or (CurrentSymbol=TokLss) or (CurrentSymbol=TokLEq) or (CurrentSymbol=TokGtr) or (CurrentSymbol=TokGEq) then begin
  if (x=TypeSTR) or ((Types[x].Kind<>KindSIMPLE) and (Types[x].Kind<>KindPOINTER)) then begin
   Error(150);
  end;
  o:=CurrentSymbol;
  GetSymbol;
  SimpleExpression(y);
  MustBe(x,y);
  case o of
   TokEql:begin
    EmitOpcode2(OPEqlI);
   end;
   TokNEq:begin
    EmitOpcode2(OPNEqI);
   end;
   TokLss:begin
    EmitOpcode2(OPLssI);
   end;
   TokLEq:begin
    EmitOpcode2(OPLeqI);
   end;
   TokGtr:begin
    EmitOpcode2(OPGtrI);
   end;
   TokGEq:begin
    EmitOpcode2(OPGEqI);
   end;
  end;
  x:=TypeBOOL;
 end;
end;

procedure InlineStatement;
var Bytes:array[1..MaximalInline] of integer;
    n,v:integer;
begin
 GetSymbol;
 Expect(TokLParent);
 n:=0;
 repeat
  if n<>0 then begin
   GetSymbol;
  end;
  if CurrentSymbol=TokNumber then begin
   v:=CurrentNumber;
  end else if CurrentSymbol=TokIdent then begin
   { A named constant is as constant as a number, and $1F is a number here
      already: ReadNumber reads the hex form, so both spellings arrive the
      same way. }
   v:=Identifiers^[Position].Value;
   if Identifiers^[Position].Kind<>IdCONST then begin
    Error(130);
   end;
  end else begin
   Error(131);
   v:=0;
  end;
  if (v<0) or (v>255) then begin
   Error(153);
   v:=0;
  end;
  if n=MaximalInline then begin
   Error(154);
  end else begin
   n:=n+1;
   Bytes[n]:=v;
  end;
  GetSymbol;
 until CurrentSymbol<>TokComma;
 Expect(TokRParent);
 { No semicolon is taken here: a statement ends where every other one does,
   on the semicolon the enclosing statement list is about to see. }
 { The block goes into the code array as it stands, and the assembler writes
   the bytes out where they land. Nothing may be fused across it: a byte the
   programmer wrote is not part of any pattern the peephole is looking for,
   and the stack the block leaves behind is the programmer's business - the
   contract is that it leaves the machine stack as it found it, which is the
   same one Turbo Pascal's inline has. }
 EmitCode(OPInline);
 EmitCode(n);
 v:=1;
 while v<=n do begin
  EmitCode(Bytes[v]);
  v:=v+1;
 end;
 LastOpcode:=-1;
 IsLabeled:=true;
end;

procedure Statement;
var L:array[1..MaximalCases] of integer;
    m,n,i,j,t,x,r,OldStackPosition:integer;
begin
 if CurrentSymbol=TokIdent then begin
  i:=Position;
  case Identifiers^[i].Kind of
   IdVAR:begin
    Selector(t,i);
    Expect(TokAssign);
    Expression(x);
    MustBe(t,x);
    if i=0 then begin
     EmitOpcode2(OPSwap);
    end else begin
     EmitAddressVar(i);
    end;
    if (Types[t].Kind=KindSIMPLE) or (Types[t].Kind=KindPOINTER) then begin
     EmitOpcode2(OPStore);
    end else begin
     EmitOpcode(OPMove,Types[t].Size);
    end;
   end;
   IdFUNC:begin
    if Identifiers^[i].FunctionLevel<0 then begin
     { A runtime builtin used as a statement: the call happens for its effect,
        and a result, if the builtin has one, is dropped. Turbo Pascal allows
        a function call as a statement, and a program closes a file that way.
        FunctionCall does the whole call - it is the one that steps over the
        name before the builtin's own handler looks at the tokens - and only
        the drop is left to do here. }
     FunctionCall(i);
     if Identifiers^[i].TypeDefinition<>0 then begin
      EmitOpcode(OPAdjS,4);
     end;
    end else if Identifiers^[i].TypeDefinition=0 then begin
     FunctionCall(i);
    end else begin
     if not Identifiers^[i].Inside then begin
      Error(122);
     end;
     GetSymbol;
     Expect(TokAssign);
     Expression(x);
     MustBe(Identifiers^[i].TypeDefinition,x);
     EmitAddress(Identifiers^[i].FunctionLevel+1,Identifiers^[i].ReturnAddress);
     EmitOpcode2(OPStore);
    end;
   end;
   IdCONST,IdFIELD,IdTYPE:Error(123);
  end;
 end else if CurrentSymbol=SymIF then begin
  GetSymbol;
  Expression(t);
  MustBe(TypeBOOL,t);
  Expect(SymTHEN);
  i:=CodeLabel;
  EmitOpcode(OPJZ,0);
  Statement;
  if CurrentSymbol=SymELSE then begin
   GetSymbol;
   j:=CodeLabel;
   EmitOpcode(OPJmp,0);
   Code^[i+1]:=CodeLabel;
   i:=j;
   Statement;
  end;
  Code^[i+1]:=CodeLabel;
 end else if CurrentSymbol=SymCASE then begin
  GetSymbol;
  Expression(t);
  MustBe(TypeINT,t);
  Expect(SymOF);
  j:=0;
  m:=0;
  repeat
   if j<>0 then begin
    Code^[j+1]:=CodeLabel;
   end;
   n:=m;
   repeat
    if n<>m then begin
     GetSymbol;
    end;
    EmitOpcode2(OPDupl);
    if CurrentSymbol=TokIdent then begin
     i:=Position;
     if Identifiers^[i].Kind<>IdCONST then begin
      Error(124);
     end;
     EmitOpcode(OPLdC,Identifiers^[i].Value);
    end else if CurrentSymbol=TokNumber then begin
     EmitOpcode(OPLdC,CurrentNumber);
    end else if (CurrentSymbol=TokStrC) and (CurrentStringLength=1) then begin
     EmitOpcode(OPLdC,ord(CurrentString[1]));
    end else begin
     Error(125);
    end;
    EmitOpcode2(OPNEqI);
    if n=MaximalCases then begin
     Error(148);
    end;
    n:=n+1;
    L[n]:=CodeLabel;
    EmitOpcode(OPJZ,0);
    GetSymbol;
   until CurrentSymbol<>TokComma;
   if CurrentSymbol<>TokColon then begin
    Error(126);
   end;
   j:=CodeLabel;
   EmitOpcode(OPJmp,0);
   repeat
    Code^[L[n]+1]:=CodeLabel;
    n:=n-1;
   until n=m;
   GetSymbol;
   Statement;
   m:=m+1;
   L[m]:=CodeLabel;
   EmitOpcode(OPJmp,0);
   if CurrentSymbol=TokSemi then begin
    GetSymbol;
   end;
  until CurrentSymbol=SymEND;
  Code^[j+1]:=CodeLabel;
  repeat
   Code^[L[m]+1]:=CodeLabel;
   m:=m-1;
  until m=0;
  EmitOpcode(OPAdjS,4);
  GetSymbol;
 end else if CurrentSymbol=SymFOR then begin
  GetSymbol;
  if CurrentSymbol=TokIdent then begin
   OldStackPosition:=StackPosition;

   i:=Position;
   if Identifiers^[i].Kind<>IdVAR then begin
    Error(127);
   end;
   Selector(t,i);
   Expect(TokAssign);
   Expression(x);
   MustBe(t,x);
   if i=0 then begin
    EmitOpcode2(OPSwap);
   end else begin
    EmitAddressVar(i);
   end;
   if Types[t].Kind<>KindSIMPLE then begin
    Error(128);
   end;
   EmitOpcode2(OPStore);

   r:=1;
   if CurrentSymbol=SymTO then begin
    Expect(SymTO);
   end else if CurrentSymbol=SymDOWNTO then begin
    Expect(SymDOWNTO);
    r:=-1;
   end else begin
    Error(129);
   end;

   j:=CodeLabel;
   if i=0 then begin
    EmitOpcode2(OPSwap);
   end else begin
    EmitAddressVar(i);
   end;
   EmitOpcode2(OPLoad);
   Expression(x);
   MustBe(t,x);
   if r>0 then begin
    EmitOpcode2(OPLeqI);
   end else begin
    EmitOpcode2(OPGeqI);
   end;
   n:=CodeLabel;
   EmitOpcode(OPJZ,0);

   Expect(SymDO);

   Statement;

   if i=0 then begin
    EmitOpcode2(OPSwap);
   end else begin
    EmitAddressVar(i);
   end;
   EmitOpcode2(OPLoad);

   EmitOpcode(OPAddC,r);

   if i=0 then begin
    EmitOpcode2(OPSwap);
   end else begin
    EmitAddressVar(i);
   end;
   EmitOpcode2(OPStore);

   EmitOpcode(OPJmp,j);
   Code^[n+1]:=CodeLabel;

   EmitOpcode(OPAdjS,OldStackPosition-StackPosition);

  end else begin
   Expect(TokIdent);
  end;
 end else if CurrentSymbol=SymWHILE then begin
  GetSymbol;
  i:=CodeLabel;
  Expression(t);
  MustBe(TypeBOOL,t);
  Expect(SymDO);
  j:=CodeLabel;
  EmitOpcode(OPJZ,0);
  Statement;
  EmitOpcode(OPJmp,i);
  Code^[j+1]:=CodeLabel;
 end else if CurrentSymbol=SymREPEAT then begin
  i:=CodeLabel;
  repeat
   GetSymbol;
   Statement;
  until CurrentSymbol<>TokSemi;
  Expect(SymUNTIL);
  Expression(t);
  MustBe(TypeBOOL,t);
  EmitOpcode(OPJZ,i);
 end else if CurrentSymbol=SymBEGIN then begin
  repeat
   GetSymbol;
   Statement;
  until CurrentSymbol<>TokSemi;
  Expect(SymEND);
 end else if CurrentSymbol=SymHALT then begin
  EmitOpcode2(OPHalt);
  GetSymbol;
 end else if CurrentSymbol=SymINLINE then begin
  InlineStatement;
 end;
end;

procedure Block(L:integer); forward;

procedure Constant(var c,t:integer);
var i,s:integer;
begin
 if (CurrentSymbol=TokStrC) and (CurrentStringLength=1) then begin
  c:=ord(CurrentString[1]);
  t:=TypeCHAR;
 end else begin
  if CurrentSymbol=TokPlus then begin
   GetSymbol;
   s:=1;
  end  else if CurrentSymbol=TokMinus then begin
   GetSymbol;
   s:=-1;
  end else begin
   s:=0;
  end;
  if CurrentSymbol=TokIdent then begin
   i:=Position;
   if Identifiers^[i].Kind<>IdCONST then begin
    Error(130);
   end;
   c:=Identifiers^[i].Value;
   t:=Identifiers^[i].TypeDefinition;
  end else if CurrentSymbol=TokNumber then begin
   c:=CurrentNumber;
   t:=TypeINT;
  end else begin
   Error(131);
  end;
  if s<>0 then begin
   MustBe(t,TypeINT);
   c:=c*s;
  end;
 end;
 GetSymbol;
end;

procedure ConstDeclaration;
var a:TAlfa;
    t,c:integer;
begin
 a:=CurrentIdentifer;
 GetSymbol;
 Expect(TokEql);
 Constant(c,t);
 Expect(TokSemi);
 EnterSymbol(A,IdCONST,t);
 Identifiers^[IdentifierPosition].Value:=c;
end;

procedure TypeDefinition(var t:integer); forward;

procedure ArrayType(var t:integer);
var x:integer;
begin
 Types[t].Kind:=KindARRAY;
 GetSymbol;
 Constant(Types[t].StartIndex,x);
 MustBe(TypeINT,x);
 Expect(TokColon);
 Constant(Types[t].EndIndex,x);
 MustBe(TypeINT,x);
 if Types[t].StartIndex>Types[t].EndIndex then begin
  Error(132);
 end;
 if CurrentSymbol=TokComma then begin
  ArrayType(Types[t].SubType);
 end else begin
  Expect(TokRBracket);
  Expect(SymOF);
  TypeDefinition(Types[t].SubType);
 end;
 Types[t].Size:=(Types[t].EndIndex-Types[t].StartIndex+1)*Types[Types[t].SubType].Size;
end;

procedure TypeDefinition(var t:integer);
var i,j,Size,FieldType,Pointee:integer;
begin
 if CurrentSymbol=SymPACKED then begin
  GetSymbol;
 end; 
 if CurrentSymbol=TokIdent then begin
  i:=Position;
  if Identifiers^[i].Kind<>IdTYPE then begin
   Error(133);
  end;
  t:=Identifiers^[i].TypeDefinition;
  GetSymbol;
 end else begin
  if TypePosition=MaximalTypes then begin
   Error(134);
  end;
  TypePosition:=TypePosition+1;
  t:=TypePosition;
  if CurrentSymbol=SymARRAY then begin
   GetSymbol;
   Check(TokLBracket);
   ArrayType(t);
  end else if CurrentSymbol=TokPoint then begin
   { ^T. The pointee is read first, so a pointer to an unnamed record, to an
     array or to another pointer is written the way it reads. }
   GetSymbol;
   TypeDefinition(Pointee);
   Types[t].Kind:=KindPOINTER;
   Types[t].SubType:=Pointee;
   Types[t].Size:=4;
  end else begin
   Expect(SymRECORD);
   if CurrentLevel=MaximalList then begin
    Error(135);
   end;
   CurrentLevel:=CurrentLevel+1;
   SymbolNameList[CurrentLevel]:=0;
   Check(TokIdent);
   Size:=0;
   repeat
    EnterSymbol(CurrentIdentifer,IdFIELD,0);
    i:=IdentifierPosition;
    GetSymbol;
    while CurrentSymbol=TokComma do begin
     GetSymbol;
     Check(TokIdent);
     EnterSymbol(CurrentIdentifer,IdFIELD,0);
     GetSymbol;
    end;
    j:=IdentifierPosition;
    Expect(TokColon);
    TypeDefinition(FieldType);
    repeat
     Identifiers^[i].TypeDefinition:=FieldType;
     Identifiers^[i].Offset:=Size;
     Size:=Size+Types[FieldType].Size;
     i:=i+1;
    until i>j;
    if CurrentSymbol=TokSemi then begin
     GetSymbol;
    end else begin
     Check(SymEND);
    end;
   until CurrentSymbol<>TokIdent;
   Types[t].Size:=Size;
   Types[t].Kind:=KindRECORD;
   Types[t].Fields:=SymbolNameList[CurrentLevel];
   CurrentLevel:=CurrentLevel-1;
   Expect(SymEND);
  end;
 end;
end;

procedure TypeDeclaration;
var a:TAlfa;
    t:integer;
begin
 a:=CurrentIdentifer;
 GetSymbol;
 Expect(TokEql);
 TypeDefinition(t);
 Expect(TokSemi);
 EnterSymbol(a,IdTYPE,t);
end;

procedure VarDeclaration;
var p,q,t:integer;
begin
 EnterSymbol(CurrentIdentifer,IdVAR,0);
 p:=IdentifierPosition;
 GetSymbol;
 while CurrentSymbol=TokComma do begin
  GetSymbol;
  Check(TokIdent);
  EnterSymbol(CurrentIdentifer,IdVAR,0);
  GetSymbol;
 end;
 q:=IdentifierPosition;
 Expect(TokColon);
 TypeDefinition(t);
 Expect(TokSemi);
 repeat
  Identifiers^[p].VariableLevel:=CurrentLevel;
  StackPosition:=StackPosition-Types[t].Size;
  Identifiers^[p].TypeDefinition:=t;
  Identifiers^[p].VariableAddress:=StackPosition;
  Identifiers^[p].ReferencedParameter:=false;
  p:=p+1;
 until p>q;
end;

procedure NewParameter(var p,LocalStackPosition:integer);
var r:boolean;
    t:integer;
begin
 if CurrentSymbol=SymVAR then begin
  r:=true;
  GetSymbol;
 end else begin
  r:=false;
 end;
 Check(TokIdent);
 p:=IdentifierPosition;
 EnterSymbol(CurrentIdentifer,IdVAR,0);
 GetSymbol;
 while CurrentSymbol=TokComma do begin
  GetSymbol;
  Check(TokIdent);
  EnterSymbol(CurrentIdentifer,IdVAR,0);
  GetSymbol;
 end;
 Expect(TokColon);
 Check(TokIdent);
 TypeDefinition(t);
 while p<IdentifierPosition do begin
  p:=p+1;
  Identifiers^[p].TypeDefinition:=t;
  Identifiers^[p].ReferencedParameter:=r;
  if r then begin
   LocalStackPosition:=LocalStackPosition+4;
  end else begin
   LocalStackPosition:=LocalStackPosition+Types[t].Size;
  end;
 end;
end;

procedure FunctionDeclaration(IsFunction:boolean);
var f,p,LocalStackPosition,P1,P2,OldStackPosition:integer;
begin
 GetSymbol;
 Check(TokIdent);
 FunctionDeclarationIndex:=-1;
 EnterSymbol(CurrentIdentifer,IdFUNC,0);
 GetSymbol;
 f:=IdentifierPosition;
 Identifiers^[f].FunctionLevel:=CurrentLevel;
 Identifiers^[f].FunctionAddress:=CodeLabel;
 EmitOpcode(OPJmp,0);
 if CurrentLevel=MaximalList then begin
  Error(136);
 end;
 CurrentLevel:=CurrentLevel+1;
 SymbolNameList[CurrentLevel]:=0;
 LocalStackPosition:=4;
 OldStackPosition:=StackPosition;
 if CurrentSymbol=TokLParent then begin
  repeat
   GetSymbol;
   NewParameter(p,LocalStackPosition);
  until CurrentSymbol<>TokSemi;
  Expect(TokRParent);
 end;
 if CurrentLevel>1 then begin
  StackPosition:=-4;
 end else begin
  StackPosition:=0;
 end;
 Identifiers^[f].ReturnAddress:=LocalStackPosition;
 p:=f;
 while p<IdentifierPosition do begin
  p:=p+1;
  if Identifiers^[p].ReferencedParameter then begin
   LocalStackPosition:=LocalStackPosition-4;
  end else begin
   LocalStackPosition:=LocalStackPosition-Types[Identifiers^[p].TypeDefinition].Size;
  end;
  Identifiers^[p].VariableLevel:=CurrentLevel;
  Identifiers^[p].VariableAddress:=LocalStackPosition;
 end;
 if IsFunction then begin
  Expect(TokColon);
  Check(TokIdent);
  TypeDefinition(Identifiers^[f].TypeDefinition);
  if (Types[Identifiers^[f].TypeDefinition].Kind<>KindSIMPLE) and (Types[Identifiers^[f].TypeDefinition].Kind<>KindPOINTER) then begin
   Error(137);
  end;
 end;
 Expect(TokSemi);
 Identifiers^[f].LastParameter:=IdentifierPosition;
 if CurrentSymbol<>SymFORWARD then begin
  if FunctionDeclarationIndex>=0 then begin
   P1:=FunctionDeclarationIndex+1;
   P2:=f+1;
   while P1<=Identifiers^[FunctionDeclarationIndex].LastParameter do begin
    if P2>Identifiers^[f].LastParameter then begin
     Error(138);
    end;
    if not StringCompare(Identifiers^[P1].Name,Identifiers^[P2].Name) then begin
     Error(139);
    end;
    if Identifiers^[P1].TypeDefinition<>Identifiers^[P2].TypeDefinition then begin
     Error(140);
    end;
    if Identifiers^[P1].ReferencedParameter<>Identifiers^[P2].ReferencedParameter then begin
     Error(141);
    end;
    P1:=P1+1;
    P2:=P2+1;
   end;
   if P2<=Identifiers^[f].LastParameter then begin
    Error(142);
   end;
  end;
  Identifiers^[f].Inside:=true;
  Block(Identifiers^[f].FunctionAddress);
  Identifiers^[f].Inside:=false;
  EmitOpcode(OPExit,Identifiers^[f].ReturnAddress-StackPosition);
 end else begin
  if FunctionDeclarationIndex>=0 then begin
   Error(143);
  end;
  GetSymbol;
 end;
 CurrentLevel:=CurrentLevel-1;
 StackPosition:=OldStackPosition;
 Expect(TokSemi);
end;

procedure Block(L:integer);
var i,d,OldStackPosition,OldIdentPos,GlobalBase:integer;
begin
 OldStackPosition:=StackPosition;
 OldIdentPos:=IdentifierPosition;
 while (CurrentSymbol=SymCONST) or (CurrentSymbol=SymTYPE) or (CurrentSymbol=SymVAR) or (CurrentSymbol=SymFUNC) or (CurrentSymbol=SymPROC) do begin
  if CurrentSymbol=SymCONST then begin
   GetSymbol;
   Check(TokIdent);
   while CurrentSymbol=TokIdent do begin
    ConstDeclaration;
   end;
  end else if CurrentSymbol=SymTYPE then begin
   GetSymbol;
   Check(TokIdent);
   while CurrentSymbol=TokIdent do begin
    TypeDeclaration;
   end;
  end else if CurrentSymbol=SymVAR then begin
   GetSymbol;
   Check(TokIdent);
   while CurrentSymbol=TokIdent do begin
    VarDeclaration;
   end;
  end else if (CurrentSymbol=SymFUNC) or (CurrentSymbol=SymPROC) then begin
   FunctionDeclaration(CurrentSymbol=SymFUNC);
  end;
 end;
 if L+1=CodeLabel then begin
  CodePosition:=CodePosition-1;
 end else begin
  Code^[L+1]:=CodeLabel;
 end;
 if CurrentLevel=0 then begin
  { The area's offset is taken before the adjustment below is emitted, and not
    after it: EmitOpcode folds an OPAdjS into StackPosition as it writes the
    instruction, so once that line has run the model holds twice the offset and
    an area read from it starts twice as far down as it does. Nothing else in
    an outer block reads the model after this point - a global is addressed
    absolutely, and every adjustment below is a difference - which is why the
    doubling has never shown, and this is the one place that has to know. }
  GlobalBase:=StackPosition;
  EmitOpcode(OPAdjS,StackPosition);
  { The variables of the outer block are the program's globals, and they have
    to start at zero, which is what they do wherever a loader puts an image
    together: the .bss of a Win32 image and the data of a Turbo Pascal program
    are both cleared before the first statement runs, and this source is
    written against that - the library's heap reads RtlHeapFree to find its
    first free block, and reads it before anything has put one there. An
    HX-DOS program is given a frame that is memory the machine has already run
    something else in, and the host promises nothing about what is in it, so
    the promise has to be kept here or not at all.

    The area is the whole of what the declarations reserved: it starts at
    EBP+GlobalBase, because that is the last variable declared and the
    addresses run upwards from it, and it is 4-GlobalBase bytes long, because
    the offset began at 4 - the return address an outer block counts and was
    never given - and every variable has taken its size from it since. The
    fill itself is the host's, one instruction, and it is emitted as the
    arguments of the same call the language's own Fill is: the area's first
    byte, its length, and the zero. Nothing is emitted for a
    program that declares no globals, which is the only case where there is
    nothing to clear. }
  if GlobalBase<4 then begin
   EmitAddress(0,GlobalBase);
   EmitOpcode(OPLdC,4-GlobalBase);
   EmitOpcode(OPLdC,0);
   EmitRTL(RTLCallSysFill,12,0)
  end
 end else begin
  d:=StackPosition-OldStackPosition;
  StackPosition:=OldStackPosition;
  EmitOpcode(OPAdjS,d);
 end;
 Statement;
 if CurrentLevel<>0 then begin
  EmitOpcode(OPAdjS,OldStackPosition-StackPosition);
 end;
 i:=OldIdentPos+1;
 while i<=IdentifierPosition do begin
  if Identifiers^[i].Kind=IdFUNC then begin
   if (Code^[Identifiers^[i].FunctionAddress]=OPJmp) and (Code^[Identifiers^[i].FunctionAddress+1]=0) then begin
    Error(144);
   end;
  end;
  i:=i+1;
 end;
 IdentifierPosition:=OldIdentPos;
end;

const OutputCodeDataMaximalSize=262144;

var OutputCodeData:array[1..OutputCodeDataMaximalSize] of char;
    OutputCodeDataSize:integer;

    { Where the image goes. The assembler assembles it and leaves it here; the
      caller writes it. ImageTailSize is the padding that makes the image as
      long as its own header says it is, and the caller has to write that too,
      so it is counted here and read there. }
    ImageTailSize:integer;

procedure EmitChar(c:char);
begin
 OutputCodeDataSize:=OutputCodeDataSize+1;
 if OutputCodeDataSize>OutputCodeDataMaximalSize then begin
  Error(146);
 end;
 OutputCodeData[OutputCodeDataSize]:=c;
end;

procedure EmitByte(B:integer);
begin
 EmitChar(chr(B));
end;

procedure EmitInt16(i:integer);
begin
 if i>=0 then begin
  EmitByte(i mod 256);
  EmitByte((i shr 8) mod 256);
 end else begin
  i:=-(i+1);
  EmitByte(255-(i mod 256));
  EmitByte(255-((i shr 8) mod 256));
 end;
end;

procedure EmitInt32(i:integer);
begin
 if i>=0 then begin
  EmitByte(i mod 256);
  EmitByte((i shr 8) mod 256);
  EmitByte((i shr 16) mod 256);
  EmitByte(i shr 24);
 end else begin
  i:=-(i+1);
  EmitByte(255-(i mod 256));
  EmitByte(255-((i shr 8) mod 256));
  EmitByte(255-((i shr 16) mod 256));
  EmitByte(255-(i shr 24));
 end;
end;

function OutputCodeGetInt32(o:integer):integer;
begin
 if ord(OutputCodeData[o+3])<$80 then begin
  OutputCodeGetInt32:=ord(OutputCodeData[o])+(ord(OutputCodeData[o+1]) shl 8)+(ord(OutputCodeData[o+2]) shl 16)+(ord(OutputCodeData[o+3]) shl 24);
 end else begin
  OutputCodeGetInt32:=-(((255-ord(OutputCodeData[o]))+((255-ord(OutputCodeData[o+1])) shl 8)+((255-ord(OutputCodeData[o+2])) shl 16)+((255-ord(OutputCodeData[o+3])) shl 24))+1);
 end;
end;

procedure OutputCodePutInt32(o,i:integer);
begin
 if i>=0 then begin
  OutputCodeData[o]:=chr(i mod 256);
  OutputCodeData[o+1]:=chr((i shr 8) mod 256);
  OutputCodeData[o+2]:=chr((i shr 16) mod 256);
  OutputCodeData[o+3]:=chr(i shr 24);
 end else begin
  i:=-(i+1);
  OutputCodeData[o]:=chr(255-(i mod 256));
  OutputCodeData[o+1]:=chr(255-((i shr 8) mod 256));
  OutputCodeData[o+2]:=chr(255-((i shr 16) mod 256));
  OutputCodeData[o+3]:=chr(255-(i shr 24));
 end;
end;

procedure WriteOutputCode;
var i:integer;
begin
 for i:=1 to OutputCodeDataSize do begin
  write(OutputCodeData[i]);
 end;
end;

procedure OutputCodeString(s:TString255);
var i:integer;
begin
 for i:=1 to 255 do begin
  EmitChar(s[i]);
 end;
end;

(* The constant part of every image: the DPMIST32 stub, the PE headers, the
   null import descriptor and the runtime blob. The linker appends the
   generated code to it and patches the four header fields listed above.
   tools/mkbase.pas writes the literal between the markers. *)
procedure EmitStubCode;
begin
 OutputCodeDataSize:=0;
 {HXBASE-BEGIN}
  OutputCodeString(#77#90#0#0#1#0#0#0#4#0#20#6#255#255#48#6#0#0#0#0#213#0#0#0#64#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#2#0#0#51#210#177#32#180#63#205#33#114#120#51#246#173#61#77#90#117#107#131#198#4#173#139#248#35#192#116#29#80#51#201#139#84#16#184#0#66#205#33#89#193#225#2#43#225#139#212#30#22#31#180#63#205#33#31#114#68#173#193#224#4#139#208#51#201#184#0#66#205#33#51#210#180#63#185#0#96#205#33#114#49#59#193#115#40#180#62#205#33#139#207#227#23#139#252#140#216#54#139#93#2#193#227#4#54#3#29#1#7#131#199#4#226#239#139#231#139#220#30#82#139#213#22#31#203#186#195#0#235#3#186#182#0#14#31#232#11#0#186#154#0#232#5#0#184#240#76#205#33#180#9#205#33#195#13#10#112#114#111#103#114#97#109#32#108#111#97#100#105#110#103#32#97#98#111#114#116#101#100#13#10#36#13#10#114#101#97#100#32#101#114);
  OutputCodeString(#114#111#114#36#13#10#98#97#100#32#108#111#97#100#101#114#32#102#105#108#101#36#252#161#2#0#131#232#48#142#208#188#176#2#139#236#131#236#80#139#244#6#38#142#6#44#0#232#35#0#14#31#232#57#0#139#247#22#31#232#76#0#186#149#1#114#131#185#213#0#22#7#51#255#51#246#46#243#164#7#30#81#14#31#203#43#255#176#0#185#255#255#242#174#174#117#251#71#71#38#138#5#54#136#4#70#71#34#192#117#244#195#43#255#190#144#1#185#5#0#243#166#116#13#176#0#181#127#242#174#38#58#5#117#235#43#255#195#141#126#0#139#215#86#190#170#1#185#12#0#46#172#136#5#71#226#249#136#13#184#32#61#205#33#94#115#40#35#246#249#116#36#139#250#185#68#0#38#138#4#136#5#70#71#60#59#116#6#60#0#224#241#51#246#79#128#125#255#92#116#198#198#5#92#71#235#192#147#195#80#65#84#72#61#13#10#99#97#110#110#111#116#32#102#105#110#100#32#108#111#97#100#101#114#32#68#80#77#73#76#68#51#50#46#69#88#69#36#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#80#69#0#0#76#1#1#0#0#0#0#0#0#0#0#0#0#0#0#0#224#0#14#1#11#1#0#0#0#50#0#0#0#0#0#0#0#0#0#0#0#16#0#0#0#16#0#0#0#0#0#0#0#0#64#0#0#16#0#0#0#2#0#0#4#0#0#0#0#0#0#0#4#0#0#0#0#0#0#0#0#68#0#0#0#4#0#0#0#0#0#0#3#0#0#0#0#0#16#0#0#16#0#0#0#0#16#0#0#16#0#0#0#0#0#0#16#0#0#0#0#0#0#0#0#0#0#0#32#3#0#0#20#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#46#116#101#120#116);
  OutputCodeString(#0#0#0#0#50#0#0#0#16#0#0#0#50#0#0#0#4#0#0#0#0#0#0#0#0#0#0#0#0#0#0#32#0#0#224#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#233#36#47#0#0#180#76#205#33#244#205#49#195#83#81#82#86#87#139#220#139#67#24#139#214#129#234#78#36#0#0#136#2#185#1#0#0#0#187#1#0#0#0#180#64#205#33#95#94#90#89#91#194#4#0#83#81#82#86#87#85#139#220#139#67#32#139#254#129#239#13#36#0#0#51#201#51#237#133#192#15#137#7#0#0#0#247#216#189#1#0#0#0#190#10#0#0#0#51#210#247#246#128#194#48#79#136#23#65#133#192#15#133#237#255#255#255#133#237#15#132#5#0#0#0#79#198#7#45#65#139#83#28#43#209#15#142#29#0#0#0#190#64#0#0#0#43#241#59#214#15#134#2#0#0#0#139#214#79#198#7#32#65#74#15#133#244#255#255#255#139#215#187#1#0#0#0#180#64#205#33#93#95#94#90#89#91#194#8#0#82#83#86#87#139#214#129#234#244#45#0#0#185#2#0#0#0#187#1#0#0#0#180#64#205#33#95#94#91#90#195#13#10#96#139#214#129#234#217#16#0#0#86#185#0#16#0#0#51#219#180#63#205#33#94#15#130#8#0#0#0);
  OutputCodeString(#133#192#15#133#13#0#0#0#139#254#129#239#208#0#0#0#198#7#1#51#192#139#254#129#239#217#0#0#0#199#7#0#0#0#0#139#254#129#239#213#0#0#0#137#7#97#195#96#139#254#129#239#217#0#0#0#139#15#139#214#129#234#213#0#0#0#59#10#15#130#31#0#0#0#232#149#255#255#255#139#254#129#239#217#0#0#0#139#15#139#214#129#234#213#0#0#0#59#10#15#131#25#0#0#0#139#214#129#234#217#16#0#0#3#209#138#2#65#137#15#139#214#129#234#209#0#0#0#136#2#97#195#96#139#254#129#239#207#0#0#0#128#63#0#15#133#8#0#0#0#198#7#1#232#145#255#255#255#97#195#82#139#214#129#234#208#0#0#0#15#182#2#90#195#82#139#214#129#234#209#0#0#0#138#2#90#195#232#111#255#255#255#195#96#232#189#255#255#255#232#226#255#255#255#137#68#36#28#232#230#255#255#255#97#195#96#232#167#255#255#255#232#204#255#255#255#15#182#200#133#201#15#132#32#0#0#0#131#249#32#15#135#30#0#0#0#232#165#255#255#255#132#192#15#133);
  OutputCodeString(#10#0#0#0#232#179#255#255#255#233#208#255#255#255#51#192#233#76#0#0#0#51#255#60#45#15#133#10#0#0#0#191#1#0#0#0#232#147#255#255#255#51#219#232#127#255#255#255#60#48#15#130#29#0#0#0#60#57#15#135#21#0#0#0#15#182#200#131#233#48#107#219#10#3#217#232#108#255#255#255#233#214#255#255#255#139#195#133#255#15#132#2#0#0#0#247#216#137#68#36#28#97#195#96#232#24#255#255#255#232#61#255#255#255#15#182#200#133#201#15#132#32#0#0#0#131#249#10#15#132#23#0#0#0#232#22#255#255#255#132#192#15#133#10#0#0#0#232#36#255#255#255#233#208#255#255#255#97#195#82#139#214#129#234#208#0#0#0#15#182#2#90#195#82#139#214#129#234#209#0#0#0#15#182#2#131#248#10#15#148#208#15#182#192#90#195#83#81#82#86#87#85#139#220#139#83#28#139#75#32#139#67#36#133#201#15#136#55#0#0#0#129#249#3#1#0#0#15#134#5#0#0#0#185#3#1#0#0#139#254#129#239#13#36#0#0#139#239#133#201#15#132#65#0#0);
  OutputCodeString(#0#138#24#136#31#131#192#4#71#73#15#133#241#255#255#255#233#45#0#0#0#185#3#1#0#0#139#254#129#239#13#36#0#0#139#239#133#201#15#132#22#0#0#0#138#24#132#219#15#132#12#0#0#0#136#31#131#192#4#71#73#233#226#255#255#255#198#7#0#131#226#3#139#250#139#222#129#235#9#17#0#0#139#28#147#139#206#129#233#249#16#0#0#139#12#145#139#209#185#0#0#0#0#86#87#85#191#0#0#0#0#139#245#184#108#113#0#0#249#205#33#93#95#94#15#131#26#0#0#0#139#213#139#222#129#235#233#16#0#0#139#4#187#185#0#0#0#0#205#33#15#130#10#0#0#0#37#255#255#0#0#233#5#0#0#0#184#255#255#255#255#93#95#94#90#89#91#194#12#0#83#81#82#86#87#85#131#236#16#139#236#139#69#44#137#69#0#139#69#48#137#69#4#199#69#8#0#0#0#0#139#69#0#133#192#15#132#126#0#0#0#61#0#16#0#0#15#134#5#0#0#0#184#0#16#0#0#137#69#12#139#200#139#214#129#234#9#35#0#0#139#93#52#184#0);
  OutputCodeString(#63#0#0#205#33#15#130#71#0#0#0#37#255#255#0#0#133#192#15#132#68#0#0#0#137#69#12#139#200#139#254#129#239#9#35#0#0#139#85#4#15#182#31#137#26#131#199#1#131#194#4#73#15#133#238#255#255#255#137#85#4#139#85#0#43#208#137#85#0#139#85#8#3#208#137#85#8#233#129#255#255#255#184#255#255#255#255#233#3#0#0#0#139#69#8#141#101#16#93#95#94#90#89#91#194#12#0#83#81#82#86#87#85#131#236#16#139#236#139#69#44#137#69#0#139#69#48#137#69#4#199#69#8#0#0#0#0#139#69#0#133#192#15#132#129#0#0#0#61#0#16#0#0#15#134#5#0#0#0#184#0#16#0#0#137#69#12#139#200#139#254#129#239#9#35#0#0#139#85#4#138#26#136#31#131#194#4#131#199#1#73#15#133#239#255#255#255#139#77#12#139#214#129#234#9#35#0#0#139#93#52#184#0#64#0#0#205#33#15#130#43#0#0#0#37#255#255#0#0#133#192#15#132#40#0#0#0#139#85#4#141#20#130#137#85#4#139#85#0#43#208#137#85#0#139);
  OutputCodeString(#85#8#3#208#137#85#8#233#126#255#255#255#184#255#255#255#255#233#3#0#0#0#139#69#8#141#101#16#93#95#94#90#89#91#194#12#0#83#81#82#86#87#85#139#220#139#67#28#139#83#32#139#202#193#233#16#129#226#255#255#0#0#37#255#0#0#0#13#0#66#0#0#139#91#36#205#33#15#130#15#0#0#0#193#226#16#37#255#255#0#0#11#194#233#5#0#0#0#184#255#255#255#255#93#95#94#90#89#91#194#12#0#83#139#220#139#91#8#184#0#62#0#0#205#33#15#130#7#0#0#0#51#192#233#5#0#0#0#184#255#255#255#255#91#194#4#0#83#81#82#86#87#85#139#220#139#91#28#184#2#66#0#0#51#201#51#210#205#33#15#130#15#0#0#0#193#226#16#37#255#255#0#0#11#194#233#5#0#0#0#184#255#255#255#255#93#95#94#90#89#91#194#4#0#83#81#82#86#87#85#139#238#180#81#205#33#102#184#6#0#232#50#250#255#255#15#183#242#15#183#193#193#224#16#11#240#15#182#142#128#0#0#0#129#198#129#0#0#0#139#253#129#239#9#19);
  OutputCodeString(#0#0#199#7#0#0#0#0#139#239#139#220#139#67#28#133#192#15#132#148#0#0#0#139#220#139#67#28#133#192#15#136#242#0#0#0#51#210#133#201#15#132#118#0#0#0#138#30#128#251#32#15#132#53#0#0#0#128#251#9#15#132#44#0#0#0#66#59#208#15#132#42#0#0#0#133#201#15#132#81#0#0#0#138#30#128#251#32#15#132#16#0#0#0#128#251#9#15#132#7#0#0#0#70#73#233#221#255#255#255#70#73#233#177#255#255#255#133#201#15#132#33#0#0#0#15#182#6#131#248#32#15#132#21#0#0#0#131#248#9#15#132#12#0#0#0#137#7#131#199#4#70#73#233#215#255#255#255#199#7#0#0#0#0#139#197#233#182#0#0#0#6#51#219#102#142#195#51#210#102#184#130#75#205#33#15#130#79#0#0#0#133#192#15#132#71#0#0#0#139#208#102#184#134#75#205#33#15#130#57#0#0#0#133#192#15#132#49#0#0#0#7#139#240#139#213#185#127#0#0#0#138#6#132#192#15#132#16#0#0#0#15#182#192#137#2#131#194#4#70#73#15#133#230#255);
  OutputCodeString(#255#255#199#2#0#0#0#0#139#197#233#83#0#0#0#7#51#192#233#75#0#0#0#51#210#133#201#15#132#63#0#0#0#138#30#128#251#32#15#132#45#0#0#0#128#251#9#15#132#36#0#0#0#66#133#201#15#132#34#0#0#0#138#30#128#251#32#15#132#16#0#0#0#128#251#9#15#132#7#0#0#0#70#73#233#221#255#255#255#70#73#233#185#255#255#255#139#194#93#95#94#90#89#91#194#4#0#83#81#82#86#87#85#139#108#36#28#232#0#0#0#0#95#129#239#48#217#255#255#131#127#50#0#15#133#80#0#0#0#102#184#0#88#205#33#232#228#255#255#255#95#129#239#48#217#255#255#15#182#216#137#95#54#102#184#1#88#51#219#205#33#51#219#102#187#64#0#102#184#0#1#232#91#248#255#255#15#130#15#1#0#0#232#181#255#255#255#95#129#239#48#217#255#255#15#183#208#137#87#50#139#95#54#102#184#1#88#205#33#139#69#20#137#7#139#69#16#137#71#4#139#69#24#137#71#8#199#71#12#0#0#0#0#139#69#4#137#71#16#139#69#12#137#71#20);
  OutputCodeString(#139#69#8#137#71#24#139#69#0#137#71#28#102#139#69#32#102#37#255#250#102#13#2#2#102#137#71#32#139#87#50#139#69#36#37#255#255#0#0#15#133#2#0#0#0#139#194#102#137#71#34#139#69#40#37#255#255#0#0#15#133#2#0#0#0#139#194#102#137#71#36#139#69#44#37#255#255#0#0#15#133#2#0#0#0#139#194#102#137#71#38#139#69#48#37#255#255#0#0#15#133#2#0#0#0#139#194#102#137#71#40#102#199#71#42#0#0#102#199#71#44#0#0#102#199#71#46#0#4#102#137#87#48#139#92#36#32#51#201#87#102#184#0#3#30#7#232#127#247#255#255#95#15#130#50#0#0#0#139#71#28#137#69#0#139#71#16#137#69#4#139#71#24#137#69#8#139#71#20#137#69#12#139#71#4#137#69#16#139#7#137#69#20#15#183#71#32#131#224#1#137#69#32#233#7#0#0#0#199#69#32#1#0#0#0#93#95#94#90#89#91#194#8#0#83#86#87#139#68#36#16#131#248#0#15#142#82#0#0#0#131#192#15#15#130#73#0#0#0#37#240#255#255#255#15);
  OutputCodeString(#132#62#0#0#0#131#192#16#15#130#53#0#0#0#139#216#193#235#16#139#200#129#225#255#255#0#0#184#1#5#0#0#232#242#246#255#255#15#130#24#0#0#0#139#214#139#195#193#224#16#102#139#193#137#56#137#80#4#131#192#16#95#94#91#194#4#0#51#192#95#94#91#194#4#0#83#86#87#139#68#36#16#133#192#15#132#39#0#0#0#139#120#240#139#112#244#184#2#5#0#0#232#173#246#255#255#15#130#7#0#0#0#51#192#233#12#0#0#0#184#255#255#255#255#233#2#0#0#0#51#192#95#94#91#194#4#0#83#81#82#86#87#85#139#238#139#253#129#199#218#254#255#255#30#7#184#0#5#0#0#232#114#246#255#255#139#253#129#199#218#254#255#255#139#15#129#249#0#0#128#0#15#134#6#0#0#0#129#233#0#0#64#0#129#249#0#0#1#0#15#130#87#0#0#0#137#141#18#255#255#255#139#217#193#235#16#184#1#5#0#0#232#53#246#255#255#15#131#19#0#0#0#139#141#18#255#255#255#209#233#15#133#203#255#255#255#233#41#0#0#0#129#225#255#255);
  OutputCodeString(#0#0#139#195#37#255#255#0#0#193#224#16#11#193#139#124#36#28#139#149#18#255#255#255#137#23#139#245#93#95#94#90#89#91#194#4#0#51#192#139#245#93#95#94#90#89#91#194#4#0#87#139#76#36#12#133#201#15#142#11#0#0#0#139#124#36#16#139#68#36#8#252#243#170#95#194#12#0#86#87#139#76#36#12#133#201#15#142#48#0#0#0#139#116#36#20#139#124#36#16#252#59#254#15#134#29#0#0#0#139#198#3#193#59#248#15#131#17#0#0#0#253#141#116#14#255#141#124#15#255#243#164#252#233#2#0#0#0#243#164#95#94#194#12#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#1#0#0#0#2#0#0#0#2#0#0#0#1#0#0#0#18#0);
  OutputCodeString(#0#0#1#0#0#0#18#0#0#0#0#61#0#0#0#60#0#0#2#61#0#0#0#60#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0);
  OutputCodeString(#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#220#208#255#255#228#208#255#255#14#209#255#255#149#209#255#255#147#210#255#255#169#210#255#255#56#211#255#255#112#211#255#255#126#211#255#255#149#211#255#255#132#212#255#255#58#213#255#255#243#213#255#255#62#214#255#255#97#214#255#255#154#214#255#255#55#216#255#255#171#217#255#255#21#218#255#255#83#218#255#255#251#218#255#255);
  OutputCodeString(#23#219#255#255#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#0#232#0#0#0#0#93#129#237#5#0#0#0#139#245#129#198#168#255#255#255#139#253#129#199#80#255#255#255#185#22#0#0#0#139#7#3#197#137#6#131#199#4#131#198#4#73#15#133#237#255#255#255#139#253#129#199#218#254#255#255#30#7#184#0#5#0#0#232#153#208#255#255#139#253#129#199#218#254#255#255#139#15#129#249#0#0#128#0#15#134#6#0#0#0#129#233#0#0#64#0#129#249#0#0#16#0#15#130#98#0#0#0#137#141#14#255#255#255#139#217#193#235#16#184#1#5#0#0#232#92#208#255#255#15#131#19#0#0#0#139#141#14#255#255#255#209#233#15#133#203#255#255#255#233#52#0#0#0#129#225#255#255#0);
  OutputCodeString(#0#139#195#37#255#255#0#0#193#224#16#11#193#137#133#10#255#255#255#139#149#14#255#255#255#3#208#131#234#4#139#245#129#198#168#255#255#255#139#226#139#234#233#70#0#0#0#139#213#129#194#238#0#0#0#185#42#0#0#0#187#2#0#0#0#180#64#205#33#102#184#1#76#205#33#13#10#78#111#116#32#101#110#111#117#103#104#32#109#101#109#111#114#121#32#116#111#32#114#117#110#32#116#104#105#115#32#112#114#111#103#114#97#109#46#13#10#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144#144);
 {HXBASE-END}
 OutputCodeDataSize:=HXBaseSize;
end;

const locNone=0;
      locPushEAX=1;
      locPopEAX=2;
      locPopEBX=3;
      locIMulEBX=4;
      locXorEDXEDX=5;
      locIDivEBX=6;
      locPushEDX=7;
      locCmpEAXEBX=8;
      locMovzxEAXAL=9;
      locMovDWordPtrESPEAX=10;
      locJNZJNE0x03=11;
      locMovDWordPtrEBXEAX=12;
      locJmpDWordPtrESIOfs=13;
      locCallDWordPtrESIOfs=14;
      locXChgEDXESI=15;
      locPopESI=16;
      locMovECXImm=17;
      locCLD=18;
      locREPMOVSB=19;
      locTestEAXEAX=20;
      locNegDWordPtrESP=21;
      locMovEAXDWordPtrESP=22;
      locMovEBXDWordPtrFORStateCurrentValue=23;
      locCmpDWordPtrEBXEAX=24;
      locMovEAXDWordPtrFORStateDestValue=25;

var LastOutputCodeValue,PC:integer;

procedure OCPushEAX;
begin
 if LastOutputCodeValue=locPopEAX then begin
  if Code^[PC]=OutputCodeDataSize then begin
   Code^[PC]:=Code^[PC]-1;
  end;
  if OutputCodeDataSize>0 then begin
   OutputCodeDataSize:=OutputCodeDataSize-1;
  end;
  LastOutputCodeValue:=locNone;
 end else begin
  EmitByte($50);
  LastOutputCodeValue:=locPushEAX;
 end;
end;

procedure OCPopEAX;
begin
 if LastOutputCodeValue=locPushEAX then begin
  if Code^[PC]=OutputCodeDataSize then begin
   Code^[PC]:=Code^[PC]-1;
  end;
  if OutputCodeDataSize>0 then begin
   OutputCodeDataSize:=OutputCodeDataSize-1;
  end;
  LastOutputCodeValue:=locNone;
 end else begin
  EmitByte($58);
  LastOutputCodeValue:=locPopEAX;
 end;
end;

procedure OCPopEBX;
begin
 EmitByte($5b);
 LastOutputCodeValue:=locPopEBX;
end;

procedure OCIMulEBX;
begin
 EmitByte($f7);
 EmitByte($eb);
 LastOutputCodeValue:=locIMulEBX;
end;

procedure OCXorEDXEDX;
begin
 EmitByte($33); EmitByte($d2);
 LastOutputCodeValue:=locXorEDXEDX;
end;

procedure OCIDIVEBX;
begin
 EmitByte($f7); EmitByte($fb);
 LastOutputCodeValue:=locIDivEBX;
end;

procedure OCPushEDX;
begin
 EmitByte($52);
 LastOutputCodeValue:=locPushEDX;
end;

procedure OCCmpEAXEBX;
begin
 EmitByte($3b); EmitByte($c3);
 LastOutputCodeValue:=locCmpEAXEBX;
end;

procedure OCMovzxEAXAL;
begin
 EmitByte($0f); EmitByte($b6); EmitByte($c0);
 LastOutputCodeValue:=locMovzxEAXAL;
end;

procedure OCJNZJNE0x03;
begin
 EmitByte($75); EmitByte($03);
 LastOutputCodeValue:=locJNZJNE0x03;
end;

procedure OCMovDWordPtrESPEAX;
begin
 EmitByte($89); EmitByte($04); EmitByte($24);
 LastOutputCodeValue:=locMovDWordPtrESPEAX;
end;

procedure OCMovDWordPtrEBXEAX;
begin
 EmitByte($89); EmitByte($03);
 LastOutputCodeValue:=locMovDWordPtrEBXEAX;
end;

procedure OCJmpDWordPtrESIOfs(Ofs:integer);
begin
 EmitByte($ff); EmitByte($66); EmitByte(Ofs);
 LastOutputCodeValue:=locJmpDWordPtrESIOfs;
end;

procedure OCCallDWordPtrESIOfs(Ofs:integer);
begin
 EmitByte($ff); EmitByte($56); EmitByte(Ofs);
 LastOutputCodeValue:=locCallDWordPtrESIOfs;
end;

procedure OCXChgEDXESI;
begin
 EmitByte($87); EmitByte($d6);
 LastOutputCodeValue:=locXChgEDXESI;
end;

procedure OCPopESI;
begin
 EmitByte($5e);
 LastOutputCodeValue:=locPopESI;
end;

procedure OCMovECXImm(Value:integer);
begin
 EmitByte($b9); EmitInt32(Value);
 LastOutputCodeValue:=locMovECXImm;
end;

procedure OCCLD;
begin
 EmitByte($fc);
 LastOutputCodeValue:=locCLD;
end;

procedure OCREPMOVSB;
begin
 EmitByte($f3); EmitByte($a4);
 LastOutputCodeValue:=locREPMOVSB;
end;

procedure OCTestEAXEAX;
begin
 EmitByte($85); EmitByte($c0); { TEST EAX,EAX }
 LastOutputCodeValue:=locTestEAXEAX;
end;

procedure OCNegDWordPtrESP;
begin
 EmitByte($f7); EmitByte($1c); EmitByte($24); { NEG DWORD PTR [ESP] }
 LastOutputCodeValue:=locNegDWordPtrESP;
end;

procedure OCMovEAXDWordPtrESP;
begin
 EmitByte($8b); EmitByte($04); EmitByte($24); { MOV EAX,DWORD PTR [ESP] }
 LastOutputCodeValue:=locMovEAXDWordPtrESP;
end;

procedure OCMovEBXDWordPtrFORStateCurrentValue;
begin
 EmitByte($8b); EmitByte($5d); EmitByte($04);
 LastOutputCodeValue:=locMovEBXDWordPtrFORStateCurrentValue;
end;

procedure OCCmpDWordPtrEBXEAX;
begin
 EmitByte($39); EmitByte($03);
 LastOutputCodeValue:=locCmpDWordPtrEBXEAX;
end;

procedure OCMovEAXDWordPtrFORStateDestValue;
begin
 EmitByte($8b); EmitByte($45); EmitByte($08);
 LastOutputCodeValue:=locMovEAXDWordPtrFORStateDestValue;
end;

var JumpTable:array[1..MaximalCodeSize] of integer;

procedure AssembleAndLink;
var CountJumps,Opcode,Value,Index,PEEXECodeSize,PEEXESectionRawSize,PEEXESectionVirtualSize,PEEXECodeStart:integer;
begin
 EmitStubCode;
 PEEXECodeStart:=OutputCodeDataSize;
 LastOutputCodeValue:=locNone;
 PC:=0;
 CountJumps:=0;
 while PC<CodePosition do begin
  Opcode:=Code^[PC];
  Value:=Code^[PC+1];
  Code^[PC]:=OutputCodeDataSize;
  case Opcode of
   OPAdd:begin
    OCPopEAX;
    EmitByte($01); EmitByte($04); EmitByte($24); { ADD DWORD PTR [ESP],EAX }
    LastOutputCodeValue:=locNone;
   end;
   OPNeg:begin
    OCNegDWordPtrESP;
   end;
   OPMul:begin
    OCPopEBX;
    OCPopEAX;
    OCIMulEBX;
    OCPushEAX;
   end;
   OPDivD:begin
    OCPopEBX;
    OCPopEAX;
    OCXorEDXEDX;
    OCIDIVEBX;
    OCPushEAX;
   end;
   OPRemD:begin
    OCPopEBX;
    OCPopEAX;
    OCXorEDXEDX;
    OCIDIVEBX;
    OCPushEDX;
   end;
   OPDiv2:begin
    EmitByte($d1); EmitByte($3c); EmitByte($24); { SAR DWORD PTR [ESP],1 }
    LastOutputCodeValue:=locNone;
   end;
   OPRem2:begin
    OCPopEAX;  
    EmitByte($8b); EmitByte($d8); { MOV EBX,EAX }
    EmitByte($25); EmitByte($01); EmitByte($00); EmitByte($00); EmitByte($80); { AND EAX,$80000001 }
    EmitByte($79); EmitByte($05); { JNS +$05 }
    EmitByte($48); { DEC EAX }
    EmitByte($83); EmitByte($c8); EmitByte($fe); { OR EAX,BYTE -$02 }
    EmitByte($40); { INC EAX }
    LastOutputCodeValue:=locNone;
    OCIMulEBX;
    OCPushEAX;
   end;
   OPEqlI:begin
    OCPopEBX;
    OCPopEAX;
    OCCmpEAXEBX;
    EmitByte($0f); EmitByte($94); EmitByte($d0); { SETE AL }
    LastOutputCodeValue:=locNone;
    OCMovzxEAXAL;
    OCPushEAX;
   end;
   OPNEqI:begin
    OCPopEBX;
    OCPopEAX;
    OCCmpEAXEBX;
    EmitByte($0f); EmitByte($95); EmitByte($d0); { SETNE AL }
    LastOutputCodeValue:=locNone;
    OCMovzxEAXAL;
    OCPushEAX;
   end;
   OPLssI:begin
    OCPopEBX;
    OCPopEAX;
    OCCmpEAXEBX;
    EmitByte($0f); EmitByte($9c); EmitByte($d0); { SETL AL }
    LastOutputCodeValue:=locNone;
    OCMovzxEAXAL;
    OCPushEAX;
   end;
   OPLeqI:begin
    OCPopEBX;
    OCPopEAX;
    OCCmpEAXEBX;
    EmitByte($0f); EmitByte($9e); EmitByte($d0); { SETLE AL }
    LastOutputCodeValue:=locNone;
    OCMovzxEAXAL;
    OCPushEAX;
   end;
   OPGtrI:begin
    OCPopEBX;
    OCPopEAX;
    OCCmpEAXEBX;
    EmitByte($0f); EmitByte($9f); EmitByte($d0); { SETG AL }
    LastOutputCodeValue:=locNone;
    OCMovzxEAXAL;
    OCPushEAX;
   end;
   OPGEqi:begin
    OCPopEBX;
    OCPopEAX;
    OCCmpEAXEBX;
    EmitByte($0f); EmitByte($9d); EmitByte($d0); { SETGE AL }
    LastOutputCodeValue:=locNone;
    OCMovzxEAXAL;
    OCPushEAX;
   end;
   OPDupl:begin
    EmitByte($ff); EmitByte($34); EmitByte($24); { PUSH DWORD PTR [ESP] }
    LastOutputCodeValue:=locNone;
   end;
   OPSwap:begin
    OCPopEBX;
    OCPopEAX;
    EmitByte($53); { PUSH EBX }
    LastOutputCodeValue:=locNone;
    OCPushEAX;
   end;
   OPAndB:begin
    OCPopEAX;
    OCTestEAXEAX;
    OCJNZJNE0x03;
    OCMovDWordPtrESPEAX;
    LastOutputCodeValue:=locNone;
   end;
   OPOrB:begin
    OCPopEAX;
    EmitByte($83); EmitByte($f8); EmitByte($01);  { CMP EAX,1 }
    LastOutputCodeValue:=locNone;
    OCJNZJNE0x03;
    OCMovDWordPtrESPEAX;
    LastOutputCodeValue:=locNone;
   end;
   { The count is the value on top, so it is the one popped first; the
     machine takes it in CL, which is why one of the two moves through a
     register instead of the shift being given a memory operand. The count
     is taken modulo 32, which is what the hardware does with CL and what
     Turbo Pascal leaves the result to be for a count above it. }
   OPShl:begin
    OCPopEBX;
    OCPopEAX;
    EmitByte($89); EmitByte($d9); { MOV ECX,EBX }
    EmitByte($d3); EmitByte($e0); { SHL EAX,CL }
    LastOutputCodeValue:=locNone;
    OCPushEAX;
   end;
   OPShr:begin
    OCPopEBX;
    OCPopEAX;
    EmitByte($89); EmitByte($d9); { MOV ECX,EBX }
    EmitByte($d3); EmitByte($e8); { SHR EAX,CL: a logical shift, as in Turbo
                                    Pascal, where the sign is not carried in }
    LastOutputCodeValue:=locNone;
    OCPushEAX;
   end;
   OPLoad:begin
    OCPopEAX;
    EmitByte($ff); EmitByte($30); { PUSH DWORD PTR [EAX] }
    LastOutputCodeValue:=locNone;
   end;
   OPStore:begin
    OCPopEBX;
    OCPopEAX;
    OCMovDWordPtrEBXEAX;
   end;
   OPHalt:begin
    OCJmpDWordPtrESIOfs(RTLCallHalt);
   end;
   OPWrI:begin
    OCCallDWordPtrESIOfs(RTLCallWriteInteger);
   end;
   OPWrC:begin
    OCCallDWordPtrESIOfs(RTLCallWriteChar);
   end;
   OPWrL:begin
    OCCallDWordPtrESIOfs(RTLCallWriteLn);
   end;
   OPRdI:begin
    OCPopEBX;
    OCCallDWordPtrESIOfs(RTLCallReadInteger);
    OCMovDWordPtrEBXEAX;
   end;
   OPRdC:begin
    OCPopEBX;
    OCCallDWordPtrESIOfs(RTLCallReadChar);
    OCMovzxEAXAL;
    OCMovDWordPtrEBXEAX;
   end;
   OPRdL:begin
    OCCallDWordPtrESIOfs(RTLCallReadLn);
   end;
   OPEOF:begin
    OCCallDWordPtrESIOfs(RTLCallEOF);
    OCPushEAX;
   end;
   OPEOL:begin
    OCCallDWordPtrESIOfs(RTLCallEOLn);
    OCPushEAX;
   end;
   { The bytes, one slot each, exactly as the parser stored them. }
   OPInline:begin
    for Index:=0 to Value-1 do begin
     EmitByte(Code^[PC+2+Index]);
    end;
    LastOutputCodeValue:=locNone;
    PC:=PC+Value+1;
   end;
   OPCallRTL:begin
    OCCallDWordPtrESIOfs(Value);
    LastOutputCodeValue:=locNone;
    PC:=PC+1;
   end;
   { The same call where the host's result is wanted: the host leaves it in
     EAX, and generated code expects a value on the stack. }
   OPCallRTLValue:begin
    OCCallDWordPtrESIOfs(Value);
    LastOutputCodeValue:=locNone;
    OCPushEAX;
    PC:=PC+1;
   end;
   OPLdC:begin
    if (Value>=-128) and (Value<=127) then begin
     EmitByte($6a); EmitByte(Value); { PUSH BYTE Value }
    end else begin
     EmitByte($68); EmitInt32(Value); { PUSH DWORD Value }
    end;
    LastOutputCodeValue:=locNone;
    PC:=PC+1;
   end;
   OPLdA:begin
    if Value=0 then begin
     EmitByte($8b); EmitByte($c5); { MOV EAX,EBP }
    end else if (Value>=-128) and (Value<=127) then begin
     EmitByte($8d); EmitByte($45); EmitByte(Value); { LEA EAX,[EBP+BYTE Value] }
    end else begin
     EmitByte($8d); EmitByte($85); EmitInt32(Value); { LEA EAX,[EBP+DWORD Value] }
    end;
    LastOutputCodeValue:=locNone;
    OCPushEAX;
    PC:=PC+1;
   end;
   OPLdLA:begin
    if Value=0 then begin
     EmitByte($8b); EmitByte($c4); { MOV EAX,ESP }
    end else if (Value>=-128) and (Value<=127) then begin
     EmitByte($8d); EmitByte($44); EmitByte($24); EmitByte(Value); { LEA EAX,[ESP+BYTE Value] }
    end else begin
     EmitByte($8d); EmitByte($84); EmitByte($24); EmitInt32(Value); { LEA EAX,[ESP+DWORD Value] }
    end;
    LastOutputCodeValue:=locNone;
    OCPushEAX;
    PC:=PC+1;
   end;
   OPLdL:begin
    if Value=0 then begin
     OCMovEAXDWordPtrESP;
    end else if (Value>=-128) and (Value<=127) then begin
     EmitByte($8b); EmitByte($44); EmitByte($24); EmitByte(Value); { MOV EAX,DWORD PTR [ESP+BYTE Value] }
    end else begin
     EmitByte($8b); EmitByte($84); EmitByte($24); EmitInt32(Value); { MOV EAX,DWORD PTR [ESP+DWORD Value] }
    end;
    OCPushEAX;
    PC:=PC+1;
   end;
   OPLdG:begin
    if (Value>=-128) and (Value<=127) then begin
     EmitByte($8b); EmitByte($45); EmitByte(Value); { MOV EAX,DWORD PTR [EBP+BYTE Value] }
    end else begin
     EmitByte($8b); EmitByte($85); EmitInt32(Value); { MOV EAX,DWORD PTR [EBP+DWORD Value] }
    end;
    LastOutputCodeValue:=locNone;
    OCPushEAX;
    PC:=PC+1;
   end;
   OPStL:begin
    OCPopEAX;
    Value:=Value-4;
    if Value=0 then begin
     EmitByte($89); EmitByte($04); EmitByte($24); { MOV DWORD PTR [ESP],EAX }
    end else if (Value>=-128) and (Value<=127) then begin
     EmitByte($89); EmitByte($44); EmitByte($24); EmitByte(Value); { MOV DWORD PTR [ESP+BYTE Value],EAX }
    end else begin
     EmitByte($89); EmitByte($84); EmitByte($24); EmitInt32(Value); { MOV EAX,DWORD PTR [ESP+DWORD Value] }
    end;
    LastOutputCodeValue:=locNone;
    PC:=PC+1;
   end;
   OPStG:begin
    OCPopEAX;
    if (Value>=-128) and (Value<=127) then begin
     EmitByte($89); EmitByte($45); EmitByte(Value); { MOV DWORD PTR [EBP+BYTE Value],EAX }
    end else begin
     EmitByte($89); EmitByte($85); EmitInt32(Value); { MOV EAX,DWORD PTR [EBP+DWORD Value] }
    end;
    LastOutputCodeValue:=locNone;
    PC:=PC+1;
   end;
   OPMove:begin
    OCXChgEDXESI;
    EmitByte($5f); { POP EDI }
    LastOutputCodeValue:=locNone;
    OCPopESI;
    OCMovECXImm(Value);
    OCCLD;
    OCREPMOVSB;
    OCXChgEDXESI;
    PC:=PC+1;
   end;
   OPCopy:begin
    OCXChgEDXESI;
    OCPopESI;
    OCMovECXImm(Value);
    EmitByte($2b); EmitByte($e1); { SUB ESP,ECX }
    EmitByte($8b); EmitByte($fc); { MOV EDI,ESP }
    LastOutputCodeValue:=locNone;
    OCCLD;
    OCREPMOVSB;
    OCXChgEDXESI;
    PC:=PC+1;
   end;
   OPAddC:begin
    if (Value>=-128) and (Value<=127) then begin
     EmitByte($83); EmitByte($04); EmitByte($24); EmitByte(Value); { ADD DWORD PTR [ESP],BYTE Value }
    end else begin
     EmitByte($81); EmitByte($04); EmitByte($24); EmitInt32(Value); { ADD DWORD PTR [ESP],DWORD Value }
    end;
    LastOutputCodeValue:=locNone;
    PC:=PC+1;
   end;
   OPMulC:begin
    if Value=(-1) then begin
     OCNegDWordPtrESP;
    end else if (Value>=-128) and (Value<=127) then begin
     OCPopEAX;
     EmitByte($6b); EmitByte($c0); EmitByte(Value); { IMUL EAX,BYTE s }
     LastOutputCodeValue:=locNone;
     OCPushEAX;
    end else begin
     OCPopEAX;
     EmitByte($69); EmitByte($c0); EmitInt32(Value); { IMUL EAX,DWORD s }
     LastOutputCodeValue:=locNone;
     OCPushEAX;
    end;
    PC:=PC+1;
   end;
   OPJmp:begin
    if Value<>(PC+2) then begin
     CountJumps:=CountJumps+1;
     EmitByte($e9); { JMP Value }
     JumpTable[CountJumps]:=OutputCodeDataSize+1;
     EmitInt32(Value);
    end;
    PC:=PC+1;
    LastOutputCodeValue:=locNone;
   end;
   OPJZ:begin
    CountJumps:=CountJumps+1;
    OCPopEAX;
    OCTestEAXEAX;
    EmitByte($0f); EmitByte($84); { JZ Value }
    JumpTable[CountJumps]:=OutputCodeDataSize+1;
    EmitInt32(Value);
    LastOutputCodeValue:=locNone;
    PC:=PC+1;
   end;
   OPCall:begin
    CountJumps:=CountJumps+1;
    EmitByte($e8); { CALL Value }
    JumpTable[CountJumps]:=OutputCodeDataSize+1;
    EmitInt32(Value);
    LastOutputCodeValue:=locNone;
    PC:=PC+1;
   end;
   OPAdjS:begin
    if Value>0 then begin
     if (Value>=-128) and (Value<=127) then begin
      EmitByte($83); EmitByte($c4); EmitByte(Value); { ADD ESP,BYTE Value }
     end else begin
      EmitByte($81); EmitByte($c4); EmitInt32(Value); { ADD ESP,DWORD Value }
     end;
    end else if Value<0 then begin
     Value:=-Value;
     if (Value>=-128) and (Value<=127) then begin
      EmitByte($83); EmitByte($ec); EmitByte(Value); { SUB ESP,BYTE Value }
     end else begin
      EmitByte($81); EmitByte($ec); EmitInt32(Value); { SUB ESP,DWORD Value }
     end;
    end;
    LastOutputCodeValue:=locNone;
    PC:=PC+1;
   end;
   OPExit:begin
    Value:=Value-4;
    if Value>0 then begin
     EmitByte($c2); EmitInt16(Value); { RET Value }
    end else if Value=0 then begin
     EmitByte($c3); { RET }
    end else begin
     Error(145);
    end;
    LastOutputCodeValue:=locNone;
    PC:=PC+1;
   end;
  end;
  PC:=PC+1;
 end;

 { Patch jumps + calls }
 for Index:=1 to CountJumps do begin
  Value:=JumpTable[Index];
  OutputCodePutInt32(Value,((Code^[OutputCodeGetInt32(Value)]-Value)-3));
 end;

 { .text is the runtime blob plus everything the linker appended to it - the
  headers are not part of it - rounded up to the file alignment, and SizeOfCode,
  the section's virtual size and its raw size are all that one figure. The image
  is that size rounded up to the section alignment, plus the headers. Computed
  rather than patched into what the base image says, so an empty program and a
  large one take the same path. }
 PEEXECodeSize:=OutputCodeDataSize-HXSizeOfHeaders;
 Value:=PEEXECodeSize mod HXFileAlignment;
 if Value<>0 then begin
  PEEXESectionRawSize:=PEEXECodeSize+(HXFileAlignment-Value);
 end else begin
  PEEXESectionRawSize:=PEEXECodeSize;
 end;
 OutputCodePutInt32(HXSizeOfCode,PEEXESectionRawSize);
 OutputCodePutInt32(HXSectionVirtualSize,PEEXESectionRawSize);
 OutputCodePutInt32(HXSectionRawSize,PEEXESectionRawSize);
 PEEXESectionVirtualSize:=PEEXESectionRawSize;
 Value:=PEEXESectionVirtualSize mod HXSectionAlignment;
 if Value<>0 then begin
  PEEXESectionVirtualSize:=PEEXESectionVirtualSize+(HXSectionAlignment-Value);
 end;
 OutputCodePutInt32(HXSizeOfImage,PEEXESectionVirtualSize+HXSizeOfHeaders);

 ImageTailSize:=PEEXESectionRawSize-PEEXECodeSize;
end;

{ Read the program and assemble the image of it.

  This is the whole of what the compiler does with a source, once the source
  is open and where the image should go is known. It is a procedure rather
  than the compiler's own body so that the command line can call it as well,
  and it is declared last because that is where it was when it was the body:
  a procedure's code is emitted where it is declared, so keeping it here
  keeps the image of this compiler the same shape it was.

  The program being compiled is at level zero, as it was when these
  statements were the compiler's own body: its variables are the ones the
  frame block holds, and the address of one of them is its offset from EBP.
  This procedure is not that program, so it says so. }
procedure ParseAndEmit;
begin
 { The program is read at the level it is: everything it declares is global,
   and it is global even though the parser is now inside a procedure. }
 CurrentLevel:=0;
 SymbolNameList[0]:=0;
 ReadChar;
 GetSymbol;
 IsLabeled:=true;
 CodePosition:=0;
 LastOpcode:=-1;
 StackPosition:=4;
 Expect(SymPROGRAM);
 Expect(TokIdent);
 { The semicolon is checked and not stepped over, because what stands after
   it is not the program: the library is read in there, and the reader has to
   be at the character the directive's line ends on, not at a token that has
   already been taken out of the program's text. }
 Check(TokSemi);
 { The jump over the library, which is the first thing in the code and the
   thing the block below patches to where the program's statements begin: an
   image whose first instruction is a call into a routine of the library would
   be a program that never reaches its own first line. }
 EmitOpcode(OPJmp,0);
 IncludeLibrary;
 GetSymbol;
 Block(0);
 EmitOpcode2(OPHalt);
 Check(TokPeriod);
 AssembleAndLink;
end;

{ The compiler's memory is the library's memory. GetMem asks the host for a
  block and answers its address, GetMemZeroed asks for one and empties it,
  FreeMem gives one back; they are the calls a program makes and the file a
  program is given, so a compiler that is short of memory fails the way a
  program does. The compiler never gives its tables back - it is about to
  halt whenever it stops - but there is nothing about a table that says it
  should be asked for any other way than a program's.

  The library is read in at the top of the file, where a compiler that reads
  it in itself puts it, and this is what that reading replaces. }
{ Prepare the three tables, before the program is read.

  What is in the frame is in every running copy of the compiler and is there
  from the moment it starts, which is the wrong place for the largest things
  it owns: a compiler should cost what the program it is compiling needs, not
  what the largest program it could ever be given would need. So the code
  table and the identifier table are heap blocks, asked for at the top of the
  main body and given back by nothing, and what is in the frame is two
  pointers and one cell of each table to measure by. The type table is small
  enough to stay where it is, and is cleared there.

  They are zeroed, and that is not a convenience. The compiler reads a type or
  an identifier entry before it has written one there - the kind of a variable
  it has not reached the declaration of is read as KindSIMPLE - and under
  Windows, where this compiler comes from, the loader had already made every
  global zero, so leaving an entry alone was the same as writing zero in it.
  The host here promises nothing about what a block holds: the tables a
  program has just been compiled into are still in the memory the next one is
  handed, and a compiler that read those would be compiling something that is
  not its source - one compile in a fresh session would work and the next
  would not. Zeroing is what asking rather than carrying costs, and it is paid
  once, at the size of the tables and no more. The type table is in the frame
  and not in a block, so nothing has zeroed it either, and it is cleared here
  the same way.

  The measurement is what the language offers: no SizeOf, and the host is
  asked for a number of bytes, so two cells of a kind laid end to end are
  taken to be one cell apart and the difference is the size of a cell. It is
  the same number the type table holds for the cell's type, arrived at from
  the other end.

  The host rounds a block up to sixteen bytes and answers zero when it will
  not give one. A host that will not find three megabytes for a compiler is a
  host that cannot run it, so the message names the table and halts; there is
  no compilation after that to write a diagnostic into. }
procedure PrepareTables;
var Cell,TableSize,TableAddress:integer;
begin
 Cell:=Addr(CodeCell[1])-Addr(CodeCell[0]);
 if Cell<0 then begin
  Cell:=-Cell
 end;
 TableSize:=Cell*(MaximalCodeSize+1);
 TableAddress:=GetMemZeroed(TableSize);
 if TableAddress=0 then begin
  WriteLn('Not enough memory for the code table');
  Halt
 end;
 Code:=TableAddress;

 Cell:=Addr(IdentCell[1])-Addr(IdentCell[0]);
 if Cell<0 then begin
  Cell:=-Cell
 end;
 TableSize:=Cell*(MaximalIdentifiers+1);
 TableAddress:=GetMemZeroed(TableSize);
 if TableAddress=0 then begin
  WriteLn('Not enough memory for the identifier table');
  Halt
 end;
 Identifiers:=TableAddress;

 Cell:=Addr(TypeCell[1])-Addr(TypeCell[0]);
 if Cell<0 then begin
  Cell:=-Cell
 end;
 FillChar(Addr(Types[1]),Cell*MaximalTypes,0)
end;

{ The command line.

  It is written in what the compiler declares above it - the source tables it
  fills in and the ParseAndEmit it hands them to - so it stands at the end of
  the declarations, and the main body is where it is called from.

  Called with a file name, the compiler reads that file and writes the image
  beside it under the same name with .EXE for an extension: BTCPC FOO.PAS
  writes FOO.EXE. -o names the image instead, and then it is written where
  that name says and nowhere else: BTCPC -o BAR.EXE FOO.PAS writes BAR.EXE
  and leaves FOO.EXE alone. Called with no source name at all it says how it
  is called and stops.

  A source is a file and there is no other way in. A compiler that read its
  source from the input stream would stop and wait on that stream when the
  file it was asked for was not the one it found, and waiting is not a thing
  a build can tell from working: it looks like a build that takes forever.
  The build reads a file for the same reason.

  The program is read and assembled by one procedure, ParseAndEmit, and what
  is here is what happens before that call and what happens after it.
  Every path out of here ends in Halt - a compilation that fails stops in
  Error, which writes the diagnostic and halts - so the failure paths never
  reach the code that opens the output file, and a half-written image is not
  something that can be left behind.

  An argument is what ParamStr answers with: the address of a NUL-terminated
  string whose characters are cells as wide as this compiler's CHAR, four
  bytes, which is why walking it steps by four. It is copied into an ordinary
  array and never looked at again, so nothing further down can tell a name
  that came from the command line from one that came from an include.

  An argument that is exactly -o is the flag and every other argument is a
  name, which is why nothing needs escaping here: a file called -o is asked
  for by writing it twice, once as the flag's name and once as the source. }

const CliNameMax=132;     { MaximalSourceName plus the room for a NUL }
      CliOutMax=140;      { ... and for the .EXE the output name is given }
      CliTailMax=511;     { the image padding: less than one file alignment }

var CliName:array[1..CliNameMax] of char;
    CliNameLength:integer;
    CliOutName:array[1..CliOutMax] of char;
    CliOutNameLength:integer;
    CliTail:array[1..CliTailMax] of char;

{ Copy argument i of the command line into Dest and answer how many
  characters it has. Max is what the destination holds without the NUL, and
  the NUL is written after the characters so that the array can also be
  handed to anything that wants a C string. An argument that is not there is
  a zero address, and then the copy is empty. }
function CliArg(i:integer;Dest:PChar;Max:integer):integer;
var src:PChar;
    n:integer;
    More:boolean;
begin
 n:=0;
 src:=ParamStr(i);
 if src<>0 then begin
  More:=true;
  while (n<Max) and More do begin
   if src^=#0 then begin
    More:=false
   end else begin
    Dest^:=src^;
    Dest:=Dest+4;
    src:=src+4;
    n:=n+1
   end
  end
 end;
 Dest^:=#0;
 CliArg:=n
end;

{ Is argument i exactly this flag? The flag is the two characters -o, so the
  first is matched where the argument starts and the second one cell along -
  the pointer is stepped and read, rather than read at an offset, because the
  language writes ^ against a name and not against an expression. Reading one
  cell past a one-character argument is the NUL that ends it, which is no
  character, so a bare - is not the flag; and an argument that is not there is
  a zero address, which is not the flag either. }
function CliArgIsFlag(i:integer;c:char):boolean;
var src:PChar;
    Yes:boolean;
begin
 Yes:=false;
 src:=ParamStr(i);
 if src<>0 then begin
  if src^='-' then begin
   src:=src+4;
   if src^=c then begin
    Yes:=true
   end
  end
 end;
 CliArgIsFlag:=Yes
end;

{ Print a name that is in an ordinary array. }
procedure CliWriteName(Src:PChar;Len:integer);
var i:integer;
begin
 i:=1;
 while i<=Len do begin
  Write(Src^);
  Src:=Src+4;
  i:=i+1
 end
end;

{ The name of the image, from the name of the source: the extension becomes
  EXE, and a name that has none has .EXE added.

  What counts as an extension is what the include directive counts as one - a
  dot after the last \ / or :, so that a directory called MY.DIR does not
  lose its dot - and there has to be something in front of the dot, so that a
  file called .PAS is not renamed to .EXE. The name is built into its own
  array rather than changed where it stands, because an extension is allowed
  to be longer than the one it replaces, and because a short one must leave
  nothing of the old name behind it. The directory, if there is one, is part
  of the name: the image is written beside the source, not in the current
  directory. }
procedure CliMakeOutName;
var i,Dot,Sep:integer;
begin
 Dot:=0;
 Sep:=0;
 i:=1;
 while i<=CliNameLength do begin
  if (CliName[i]='\') or (CliName[i]='/') or (CliName[i]=':') then begin
   Sep:=i;
   Dot:=0
  end else if CliName[i]='.' then begin
   Dot:=i
  end;
  i:=i+1
 end;
 if Dot>Sep+1 then begin
  CliOutNameLength:=Dot-1
 end else begin
  CliOutNameLength:=CliNameLength
 end;
 if CliOutNameLength+4>CliOutMax-1 then begin
  WriteLn('Output file name too long');
  Halt
 end;
 i:=1;
 while i<=CliOutNameLength do begin
  CliOutName[i]:=CliName[i];
  i:=i+1
 end;
 CliOutNameLength:=CliOutNameLength+1;
 CliOutName[CliOutNameLength]:='.';
 CliOutNameLength:=CliOutNameLength+1;
 CliOutName[CliOutNameLength]:='E';
 CliOutNameLength:=CliOutNameLength+1;
 CliOutName[CliOutNameLength]:='X';
 CliOutNameLength:=CliOutNameLength+1;
 CliOutName[CliOutNameLength]:='E'
end;

{ What BTCPC [-o image.exe] file.pas does, from the arguments to the file
  that is written. }
procedure CliMain;
var i,n,h:integer;
    Bad:boolean;
begin
 { The padding that makes the image as long as its header says it is is
   zeros, and a variable here starts as whatever the memory held before this
   program ran, so it is set rather than trusted. }
 i:=1;
 while i<=CliTailMax do begin
  CliTail[i]:=#0;
  i:=i+1
 end;

 { The arguments: one source name, and -o with the image name after it.
   Either may come first. A second source name, a -o with nothing after it, or
   a -o with an empty name is a command line that would compile something
   other than what was asked for, so it is refused rather than guessed at:
   every argument is read and the answer to any of them is one usage line. }
 n:=ParamCount;
 CliNameLength:=0;
 CliOutNameLength:=0;
 Bad:=false;
 i:=1;
 while i<=n do begin
  if CliArgIsFlag(i,'o') then begin
   i:=i+1;
   if i<=n then begin
    CliOutNameLength:=CliArg(i,Addr(CliOutName[1]),CliOutMax-1)
   end;
   if CliOutNameLength=0 then begin
    Bad:=true
   end
  end else begin
   if CliNameLength=0 then begin
    CliNameLength:=CliArg(i,Addr(CliName[1]),MaximalSourceName);
    if CliNameLength=0 then begin
     Bad:=true
    end
   end else begin
    Bad:=true
   end
  end;
  i:=i+1
 end;
 if (CliNameLength=0) or Bad then begin
  WriteLn('Usage: BTCPC [-o image.exe] file.pas');
  Halt
 end;

 { With no -o the image is named after the source, which is what CliMakeOutName
   builds; with one, the name is the one that was given, already in the array
   the write below reaches for. }
 if CliOutNameLength=0 then begin
  CliMakeOutName
 end;

 h:=SysOpen(Addr(CliName[1]),CliNameLength,0);
 if h<0 then begin
  Write('Cannot open ');
  CliWriteName(Addr(CliName[1]),CliNameLength);
  WriteLn;
  Halt
 end;

 { The source is a file, and every diagnostic names it: the name is the one
   the file was opened under, so it is the one the reader wrote, with its
   directory, as an include's name already is. }
 SourceLevel:=0;
 SourceHandle[0]:=h;
 SourceNameLength[0]:=CliNameLength;
 i:=1;
 while i<=CliNameLength do begin
  SourceName[0,i]:=CliName[i];
  i:=i+1
 end;
 SourceBufferPos[0]:=1;
 SourceBufferLen[0]:=0;

 { Where in the source the reader is. The counters are set here rather than
   left to the variables' initial value, which is whatever the memory held
   before the compiler ran - and a diagnostic that names the wrong line is
   worse than one that names none. }
 CurrentLine:=1;
 CurrentColumn:=0;

 ParseAndEmit;

 h:=SysOpen(Addr(CliOutName[1]),CliOutNameLength,1);
 if h<0 then begin
  WriteLn('Cannot create the output file');
  Halt
 end;
 SysWrite(h,Addr(OutputCodeData[1]),OutputCodeDataSize);
 if ImageTailSize>0 then begin
  SysWrite(h,Addr(CliTail[1]),ImageTailSize)
 end;
 SysClose(h);

 Write('Wrote ');
 CliWriteName(Addr(CliOutName[1]),CliOutNameLength);
 WriteLn(' (',OutputCodeDataSize+ImageTailSize:1,' bytes)');
 Halt
end;

begin
 PrepareTables;

 StringCopy(Keywords[SymBEGIN],'BEGIN               ');
 StringCopy(Keywords[SymEND],'END                 ');
 StringCopy(Keywords[SymIF],'IF                  ');
 StringCopy(Keywords[SymTHEN],'THEN                ');
 StringCopy(Keywords[SymELSE],'ELSE                ');
 StringCopy(Keywords[SymWHILE],'WHILE               ');
 StringCopy(Keywords[SymDO],'DO                  ');
 StringCopy(Keywords[SymCASE],'CASE                ');
 StringCopy(Keywords[SymREPEAT],'REPEAT              ');
 StringCopy(Keywords[SymUNTIL],'UNTIL               ');
 StringCopy(Keywords[SymFOR],'FOR                 ');
 StringCopy(Keywords[SymTO],'TO                  ');
 StringCopy(Keywords[SymDOWNTO],'DOWNTO              ');
 StringCopy(Keywords[SymNOT],'NOT                 ');
 StringCopy(Keywords[SymDIV],'DIV                 ');
 StringCopy(Keywords[SymMOD],'MOD                 ');
 StringCopy(Keywords[SymAND],'AND                 ');
 StringCopy(Keywords[SymOR],'OR                  ');
 StringCopy(Keywords[SymCONST],'CONST               ');
 StringCopy(Keywords[SymVAR],'VAR                 ');
 StringCopy(Keywords[SymTYPE],'TYPE                ');
 StringCopy(Keywords[SymARRAY],'ARRAY               ');
 StringCopy(Keywords[SymOF],'OF                  ');
 StringCopy(Keywords[SymPACKED],'PACKED              ');
 StringCopy(Keywords[SymRECORD],'RECORD              ');
 StringCopy(Keywords[SymPROGRAM],'PROGRAM             ');
 StringCopy(Keywords[SymFORWARD],'FORWARD             ');
 StringCopy(Keywords[SymHALT],'HALT                ');
 StringCopy(Keywords[SymFUNC],'FUNCTION            ');
 StringCopy(Keywords[SymPROC],'PROCEDURE           ');
 StringCopy(Keywords[SymINLINE],'INLINE              ');
 StringCopy(Keywords[SymSHL],'SHL                 ');
 StringCopy(Keywords[SymSHR],'SHR                 ');

 Types[TypeINT].Size:=4;
 Types[TypeINT].Kind:=KindSIMPLE;
 Types[TypeCHAR].Size:=4;
 Types[TypeCHAR].Kind:=KindSIMPLE;
 Types[TypeBOOL].Size:=4;
 Types[TypeBOOL].Kind:=KindSIMPLE;
 Types[TypeSTR].Size:=0;
 Types[TypeSTR].Kind:=KindSIMPLE;
 TypePosition:=4;

 SymbolNameList[-1]:=0;
 CurrentLevel:=-1;
 IdentifierPosition:=0;

 EnterSymbol('FALSE               ',IdCONST,TypeBOOL);
 Identifiers^[IdentifierPosition].Value:=ord(false);

 EnterSymbol('TRUE                ',IdCONST,TypeBOOL);
 Identifiers^[IdentifierPosition].Value:=ord(true);

 EnterSymbol('MAXINT              ',IdCONST,TypeINT);
 Identifiers^[IdentifierPosition].Value:=2147483647;

 EnterSymbol('INTEGER             ',IdTYPE,TypeINT);
 EnterSymbol('CHAR                ',IdTYPE,TypeCHAR);
 EnterSymbol('BOOLEAN             ',IdTYPE,TypeBOOL);

 EnterSymbol('CHR                 ',IdFUNC,TypeCHAR);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunCHR;
 Identifiers^[IdentifierPosition].Inside:=false;

 EnterSymbol('ORD                 ',IdFUNC,TypeINT);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunORD;
 Identifiers^[IdentifierPosition].Inside:=false;

 EnterSymbol('WRITE               ',IdFUNC,0);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunWRITE;

 EnterSymbol('WRITELN             ',IdFUNC,0);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunWRITELN;

 EnterSymbol('READ                ',IdFUNC,0);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunREAD;

 EnterSymbol('READLN              ',IdFUNC,0);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunREADLN;

 EnterSymbol('EOF                 ',IdFUNC,TypeBOOL);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunEOF;
 Identifiers^[IdentifierPosition].Inside:=false;

 EnterSymbol('EOLN                ',IdFUNC,TypeBOOL);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunEOFLN;
 Identifiers^[IdentifierPosition].Inside:=false;

 { The host file primitives. Addresses are integers here, so a caller passes
    the address of a name or of a buffer directly; the library in lib/ wraps
    them so that ordinary Pascal never has to. }
 EnterSymbol('SYSOPEN             ',IdFUNC,TypeINT);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunSYSOPEN;
 Identifiers^[IdentifierPosition].Inside:=false;

 EnterSymbol('SYSREAD             ',IdFUNC,TypeINT);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunSYSREAD;
 Identifiers^[IdentifierPosition].Inside:=false;

 EnterSymbol('SYSWRITE            ',IdFUNC,TypeINT);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunSYSWRITE;
 Identifiers^[IdentifierPosition].Inside:=false;

 EnterSymbol('SYSSEEK             ',IdFUNC,TypeINT);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunSYSSEEK;
 Identifiers^[IdentifierPosition].Inside:=false;

 EnterSymbol('SYSCLOSE            ',IdFUNC,TypeINT);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunSYSCLOSE;
 Identifiers^[IdentifierPosition].Inside:=false;

 EnterSymbol('SYSSIZE             ',IdFUNC,TypeINT);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunSYSSIZE;
 Identifiers^[IdentifierPosition].Inside:=false;

 EnterSymbol('ADDR                ',IdFUNC,TypeINT);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunADDR;
 Identifiers^[IdentifierPosition].Inside:=false;

 { The command line, which is one question with two answers: the address of
    an argument, which is what ParamStr answers with, and how many there are,
    which is what ParamCount answers with. The library declares both over
    this, so a program writes the Turbo Pascal names and gets ordinary Pascal
    strings; what the compiler adds is the index. }
 EnterSymbol('PARAMS              ',IdFUNC,TypeINT);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunPARAMS;
 Identifiers^[IdentifierPosition].Inside:=false;

 { Intr is a procedure, and the one whose second argument the compiler does
    not type-check: any variable will do, because all the runtime wants is
    where it is. It has no result, so a call to it is a statement. }
 EnterSymbol('INTR                ',IdFUNC,0);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunINTR;
 Identifiers^[IdentifierPosition].Inside:=false;

 { The memory primitives, and the two names a program normally writes instead
    of them. Alloc and Free are one DPMI block each and are what a program
    asks the host for directly; the heap a program's GetMem cuts up is a block
    of AllocMax's, which is a builtin the library calls and the compiler
    never emits.
    New and Dispose are compiler builtins rather than library routines because
    the size of what a pointer points at is in the type table and nowhere a
    library can reach it; they call the library's GetMem and FreeMem, so a
    program that uses both is using one allocator with two names. }
 EnterSymbol('SYSALLOC            ',IdFUNC,TypeINT);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunSYSALLOC;
 Identifiers^[IdentifierPosition].Inside:=false;

 EnterSymbol('SYSFREE             ',IdFUNC,TypeINT);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunSYSFREE;
 Identifiers^[IdentifierPosition].Inside:=false;

 EnterSymbol('SYSALLOCMAX         ',IdFUNC,TypeINT);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunSYSALLOCMAX;
 Identifiers^[IdentifierPosition].Inside:=false;

 EnterSymbol('SYSFILL             ',IdFUNC,0);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunSYSFILL;
 Identifiers^[IdentifierPosition].Inside:=false;

 EnterSymbol('SYSMOVE             ',IdFUNC,0);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunSYSMOVE;
 Identifiers^[IdentifierPosition].Inside:=false;

 EnterSymbol('NEW                 ',IdFUNC,0);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunNEW;
 Identifiers^[IdentifierPosition].Inside:=false;

 EnterSymbol('DISPOSE             ',IdFUNC,0);
 Identifiers^[IdentifierPosition].FunctionLevel:=-1;
 Identifiers^[IdentifierPosition].FunctionAddress:=FunDISPOSE;
 Identifiers^[IdentifierPosition].Inside:=false;

 SymbolNameList[0]:=0;
 CurrentLevel:=0;

{ The command line is the whole of what says what is compiled, and CliMain
  ends in Halt on every path out of it, so this is the last thing here. A
  command line with no source name in it is answered with the usage line
  rather than by waiting on the input stream: there is no input stream, and a
  compiler that stopped for one would look like a compiler that had hung. }
 CliMain
end.
