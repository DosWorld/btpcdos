program MemList;

{ A linked list built with New and taken apart with Dispose.

  New(p) hands back a block exactly as large as what p points at - the size
  is in the compiler's type table, which is nowhere a library routine can
  reach it, and that is why New and Dispose are builtins - and Dispose(p)
  gives the block back and sets p to zero. Both go through the same host
  allocator as the library's GetMem and FreeMem, so the two are one allocator
  under two names.

  What the program checks, in the order it prints it:

    count, sum    the list is whole: ten nodes, and the payloads are the ones
                  that were put in them
    freed, last   every node is given back, and the address of the last one
                  is written down before it goes
    reused, again the block asked for next is the block just given back. That
                  is what reusing the space means here: it went back to the
                  program rather than staying with the program
    zeroed        Dispose left the pointer it was given holding zero

  The link field is an integer, not a pointer, because a record cannot name a
  pointer type that is declared after it and this language has no forward type
  declarations: ^T needs T to be there already. An address is an integer here,
  and a pointer and an integer can be assigned to one another, so the field
  holds the address of the next node and that address is turned back into a
  pointer when the list is walked. }

type TNode=record
      Value:integer;
      Next:integer        { the address of the next node, zero at the end }
     end;
     PNode=^TNode;

var Head,Cur:PNode;
    Following:integer;
    i,Count,Sum,Last,Again:integer;

begin
 Head:=0;
 Count:=0;
 Sum:=0;
 for i:=1 to 10 do begin
  New(Cur);
  Cur^.Value:=i*7;
  Cur^.Next:=Head;
  Head:=Cur
 end;

 Cur:=Head;
 while Cur<>0 do begin
  Count:=Count+1;
  Sum:=Sum+Cur^.Value;
  Cur:=Cur^.Next
 end;
 WriteLn('count=',Count:1);
 WriteLn('sum=',Sum:1);

 Last:=0;
 Cur:=Head;
 Head:=0;
 while Cur<>0 do begin
  Last:=Cur;
  Following:=Cur^.Next;
  Dispose(Cur);
  Cur:=Following
 end;
 WriteLn('freed last=',Last:1);

 New(Cur);
 Again:=Cur;
 Dispose(Cur);
 WriteLn('reused again=',Again:1);
 if Again=Last then begin
  WriteLn('reused=yes')
 end else begin
  WriteLn('reused=no')
 end;
 if Cur=0 then begin
  WriteLn('zeroed=yes')
 end else begin
  WriteLn('zeroed=no')
 end
end.
