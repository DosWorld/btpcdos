program MemReuse;

{ One hundred thousand blocks asked for with New and given back with
  Dispose, and what that proves.

  A block that is given back has to be a block that can be handed out again.
  If it were not - if the allocator lost a block every time one was freed -
  the hundred thousand blocks of this program would add up to about eight
  megabytes and the host would run out of memory long before the loop ended:
  the first New that could not be served turns the pointer into zero, and the
  program says so instead of writing through it. So the loop finishing, with
  no block refused and every payload still readable, is the proof that the
  space is reused.

  What it prints:

    cycles       how many blocks went round
    refused      how many New calls came back with nothing
    bad          how many blocks did not hold what was written into them
    first, last  the first and the last address handed out
    same         yes when they are equal, which is what a block coming back
                 to the program looks like at the smallest scale
    live         the high-water mark of the second part, where two hundred
                 blocks are held at once before being given back
    sys          the host primitive on its own: SysAlloc hands back an
                 address, SysFree takes it and answers zero }

type TBlob=record
      Tag:integer;
      Pad:array[1..15] of integer
     end;
     PBlob=^TBlob;

const Cycles=100000;
      Live=200;

var P:PBlob;
    Held:array[1..Live] of integer;
    i,Refused,Bad,First,Last,LiveMax:integer;

begin
 Refused:=0;
 Bad:=0;
 First:=0;
 Last:=0;
 for i:=1 to Cycles do begin
  New(P);
  if P=0 then begin
   Refused:=Refused+1
  end else begin
   if First=0 then begin
    First:=P
   end;
   Last:=P;
   P^.Tag:=i;
   P^.Pad[1]:=i*2;
   P^.Pad[15]:=i*3;
   if (P^.Tag<>i) or (P^.Pad[1]<>i*2) or (P^.Pad[15]<>i*3) then begin
    Bad:=Bad+1
   end;
   Dispose(P)
  end
 end;
 WriteLn('cycles=',Cycles:1);
 WriteLn('refused=',Refused:1,' bad=',Bad:1);
 WriteLn('first=',First:1,' last=',Last:1);
 if First=Last then begin
  WriteLn('same=yes')
 end else begin
  WriteLn('same=no')
 end;

 { Two hundred blocks alive at once, every other one given back and then
   asked for again: the ones that come back are the ones that were freed. }
 LiveMax:=0;
 i:=1;
 while i<=Live do begin
  New(P);
  if P<>0 then begin
   Held[i]:=P;
   LiveMax:=LiveMax+1
  end else begin
   Held[i]:=0
  end;
  i:=i+1
 end;
 i:=1;
 while i<=Live do begin
  if Held[i]<>0 then begin
   P:=Held[i];
   Dispose(P);
   Held[i]:=0
  end;
  i:=i+2
 end;
 WriteLn('live=',LiveMax:1);

 { The two host primitives the two names are built on. }
 i:=SysAlloc(1024);
 P:=i;
 if P=0 then begin
  WriteLn('sys=no memory')
 end else begin
  P^.Tag:=99;
  WriteLn('sys tag=',P^.Tag:1);
  WriteLn('sys free=',SysFree(i):1)
 end
end.
