program LIBTEST;

{ rtldos.pas, exercised: every part of the library, once, in the order
  the library is written in - the DOS calls, the strings, the command line,
  and the files.

  It is the check that the library is a library and not a sketch: what it
  prints is what the code should be, and a value that is wrong is visible
  without a debugger.

  The command line matters here, so it is run with three arguments:

    LIBTEST.EXE -ALPHA BETA RTL.TXT

  Argument 3 names the file the file calls build, so the long-name path is
  walked with a name the program did not write itself. }

{ The runtime library is RTLDOS.PAS, and the compiler reads it before the
  first line of this file: there is no include for it here. }

var f,g:TFile;
    Name:array[1..40] of char;
    Txt:array[1..40] of char;
    Buf:array[1..256] of char;
    i,n,x,Code:integer;

begin
 WriteLn('--- dos ---');
 WriteLn('version=',DosVersion:1,' major=',DosMajor:1,' minor=',DosMinor:1);
 WriteLn('date=',DosDate:1,' time=',DosTime:1,' drive=',DosDrive:1);
 if KeyPressed then begin
  WriteLn('keypressed=1')
 end else begin
  WriteLn('keypressed=0')
 end;

 WriteLn('--- strings ---');
 SetStr(Addr(Txt[1]),'Hello           ');
 Write('setstr="'); WriteStr(Addr(Txt[1])); WriteLn('" len=',StrLen(Addr(Txt[1])):1);

 Str(0,Addr(Txt[1]));
 Write('str(0)="'); WriteStr(Addr(Txt[1])); WriteLn('"');
 Str(-1234,Addr(Txt[1]));
 Write('str(-1234)="'); WriteStr(Addr(Txt[1])); WriteLn('"');
 Str(1000000,Addr(Txt[1]));
 Write('str(1000000)="'); WriteStr(Addr(Txt[1])); WriteLn('"');
 x:=-2147483647;
 x:=x-1;
 Str(x,Addr(Txt[1]));
 Write('str(minint)="'); WriteStr(Addr(Txt[1])); WriteLn('"');

 Hex(255,2,Addr(Txt[1]));
 Write('hex(255,2)="'); WriteStr(Addr(Txt[1])); WriteLn('"');
 Hex(48879,4,Addr(Txt[1]));
 Write('hex(48879,4)="'); WriteStr(Addr(Txt[1])); WriteLn('"');
 Hex(0,8,Addr(Txt[1]));
 Write('hex(0,8)="'); WriteStr(Addr(Txt[1])); WriteLn('"');
 Hex(-1,8,Addr(Txt[1]));
 Write('hex(-1,8)="'); WriteStr(Addr(Txt[1])); WriteLn('"');

 SetStr(Addr(Txt[1]),'12345           ');
 x:=Val(Addr(Txt[1]),Code);
 WriteLn('val("12345")=',x:1,' code=',Code:1);
 SetStr(Addr(Txt[1]),'-42             ');
 x:=Val(Addr(Txt[1]),Code);
 WriteLn('val("-42")=',x:1,' code=',Code:1);
 SetStr(Addr(Txt[1]),'12ab            ');
 x:=Val(Addr(Txt[1]),Code);
 WriteLn('val("12ab")=',x:1,' code=',Code:1);
 SetStr(Addr(Txt[1]),'abc             ');
 x:=Val(Addr(Txt[1]),Code);
 WriteLn('val("abc")=',x:1,' code=',Code:1);

 SetStr(Addr(Txt[1]),'mixed           ');
 UpStr(Addr(Txt[1]));
 Write('upstr="'); WriteStr(Addr(Txt[1])); WriteLn('"');
 SetStr(Addr(Name[1]),'MIXED           ');
 if StrEq(Addr(Txt[1]),Addr(Name[1])) then begin
  WriteLn('streq: yes')
 end else begin
  WriteLn('streq: no')
 end;
 SetStr(Addr(Txt[1]),'ABC             ');
 SetStr(Addr(Name[1]),'ABD             ');
 if StrLess(Addr(Txt[1]),Addr(Name[1])) then begin
  WriteLn('strless ABC<ABD: yes')
 end else begin
  WriteLn('strless ABC<ABD: no')
 end;
 if StrLess(Addr(Name[1]),Addr(Txt[1])) then begin
  WriteLn('strless ABD<ABC: yes')
 end else begin
  WriteLn('strless ABD<ABC: no')
 end;
 StrCopy(Addr(Txt[1]),Addr(Name[1]));
 Write('strcopy="'); WriteStr(Addr(Txt[1])); WriteLn('"');

 WriteLn('--- command line ---');
 WriteLn('argcount=',ArgCount:1);
 i:=0;
 while i<=ArgCount do begin
  Write(' ',i:1,' "');
  ArgWrite(i);
  WriteLn('" len=',ArgLen(i):1);
  i:=i+1
 end;
 if ArgIs(1,'-ALPHA          ') then begin
  WriteLn('arg 1 is -ALPHA')
 end else begin
  WriteLn('arg 1 is not -ALPHA')
 end;
 if ArgIs(2,'BETA            ') then begin
  WriteLn('arg 2 is BETA')
 end else begin
  WriteLn('arg 2 is not BETA')
 end;
 if ArgCount>=2 then begin
  n:=ArgText(2);
  Write('argtext(2)="'); WriteStr(Addr(RtlArg[1])); WriteLn('" len=',n:1);
  WriteLn('argchar(2,1)=',ArgChar(2,1),' argchar(2,4)=',ArgChar(2,4))
 end;

 WriteLn('--- files ---');
 SetStr(Addr(Name[1]),'LIBOUT.TXT      ');
 Write('name="'); WriteStr(Addr(Name[1])); WriteLn('"');
 ReWrite(f,Addr(Name[1]));
 if IOError=0 then begin
  i:=1;
  while i<=100 do begin
   Buf[i]:=chr(64+((i-1) mod 26)+1);
   i:=i+1
  end;
  BlockWrite(f,Addr(Buf[1]),100,n);
  WriteLn('wrote=',n:1,' pos=',FilePos(f):1,' err=',IOError:1);
  Close(f)
 end else begin
  WriteLn('rewrite failed err=',IOError:1)
 end;

 Reset(f,Addr(Name[1]));
 if IOError=0 then begin
  WriteLn('size=',FileSize(f):1,' pos=',FilePos(f):1);
  BlockRead(f,Addr(Buf[1]),10,n);
  Write('read10=',n:1,' "',Buf[1],Buf[2],Buf[3],'" pos=',FilePos(f):1,' err=',IOError:1);
  WriteLn;
  Seek(f,50);
  WriteLn('seek(50) pos=',FilePos(f):1,' err=',IOError:1);
  BlockRead(f,Addr(Buf[1]),4,n);
  Write('read4=',n:1,' "',Buf[1],Buf[2],Buf[3],Buf[4],'"');
  WriteLn;
  Seek(f,1000);
  WriteLn('seek(1000) pos=',FilePos(f):1,' err=',IOError:1);
  BlockRead(f,Addr(Buf[1]),4,n);
  WriteLn('read at end=',n:1,' err=',IOError:1);
  Close(f);
  BlockRead(f,Addr(Buf[1]),4,n);
  WriteLn('read closed=',n:1,' err=',IOError:1);
  WriteLn('pos after close=',FilePos(f):1)
 end else begin
  WriteLn('reset failed err=',IOError:1)
 end;

 SetStr(Addr(Txt[1]),'NOSUCH          ');
 Reset(g,Addr(Txt[1]));
 if IOError=0 then begin
  WriteLn('open missing: unexpected success')
 end else begin
  WriteLn('open missing err=',IOError:1)
 end;

 if ArgCount>=3 then begin
  ReWriteArg(g,3);
  if IOError=0 then begin
   Buf[1]:='x';
   Buf[2]:='y';
   Buf[3]:='z';
   BlockWrite(g,Addr(Buf[1]),3,n);
   Close(g);
   ResetArg(g,3);
   if IOError=0 then begin
    Buf[1]:='.';
    Buf[2]:='.';
    Buf[3]:='.';
    BlockRead(g,Addr(Buf[1]),3,n);
    Write('argfile read=',n:1,' "',Buf[1],Buf[2],Buf[3],'"');
    WriteLn;
    Close(g)
   end else begin
    WriteLn('resetarg failed err=',IOError:1)
   end
  end else begin
   WriteLn('rewritearg failed err=',IOError:1)
  end
 end;

 WriteLn('--- done ---');
end.
