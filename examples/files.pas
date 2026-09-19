program Files;

{ Files, and the name they are opened under.

  Reset and ReWrite take a file name as the address of a run of characters
  ending at a NUL, and the name here is longer than eight plus three: the
  library opens it with the long-file-name call, because the 8.3 open is not
  translated for an HX client - a name DOS would shorten is a name this has to
  ask for by its full spelling.

  The name is built one cell at a time, because SetStr takes sixteen
  characters and is for keys, not for paths.

  What it prints:

    name        the name, read back out of the array it was built in
    wrote       the bytes written and the position afterwards
    size        the file's size on disk, from FileSize
    readback    the bytes read back and how many of them match
    argcount    the command line, and its first argument
    missing     opening a name that is not there: an error, not a crash }

{ The runtime library is RTLDOS.PAS, and the compiler reads it before the
  first line of this file: there is no include for it here. }

const Expect=64;

var f:TFile;
    Name:array[1..32] of char;
    Buf:array[1..Expect] of char;
    i,n,Same:integer;

function Pattern(i:integer):char;
begin
 Pattern:=chr(64+((i-1) mod 26)+1)
end;

begin
 { The name, cell by cell, ending in the NUL that ends it. }
 Name[1]:='H';  Name[2]:='X';  Name[3]:='D';  Name[4]:='O';  Name[5]:='S';
 Name[6]:='-';  Name[7]:='L';  Name[8]:='o';  Name[9]:='n';  Name[10]:='g';
 Name[11]:='-'; Name[12]:='N'; Name[13]:='a'; Name[14]:='m'; Name[15]:='e';
 Name[16]:='.'; Name[17]:='T'; Name[18]:='X'; Name[19]:='T'; Name[20]:=#0;
 Write('name="'); WriteStr(Addr(Name[1])); WriteLn('"');

 for i:=1 to Expect do begin
  Buf[i]:=Pattern(i)
 end;

 ReWrite(f,Addr(Name[1]));
 if IOError=0 then begin
  BlockWrite(f,Addr(Buf[1]),Expect,n);
  WriteLn('wrote=',n:1,' pos=',FilePos(f):1);
  Close(f)
 end else begin
  WriteLn('rewrite err=',IOError:1)
 end;

 Reset(f,Addr(Name[1]));
 if IOError=0 then begin
  WriteLn('size=',FileSize(f):1);
  for i:=1 to Expect do begin
   Buf[i]:=#0
  end;
  BlockRead(f,Addr(Buf[1]),Expect,n);
  Same:=0;
  for i:=1 to n do begin
   if Buf[i]=Pattern(i) then begin
    Same:=Same+1
   end
  end;
  WriteLn('readback=',n:1,' same=',Same:1);
  Close(f)
 end else begin
  WriteLn('reset err=',IOError:1)
 end;

 WriteLn('argcount=',ArgCount:1);
 if ArgCount>=1 then begin
  Write('arg1="'); ArgWrite(1); WriteLn('"')
 end;

 SetStr(Addr(Name[1]),'NOSUCH.TXT      ');
 Reset(f,Addr(Name[1]));
 if IOError=0 then begin
  WriteLn('missing=opened')
 end else begin
  WriteLn('missing err=',IOError:1)
 end
end.
