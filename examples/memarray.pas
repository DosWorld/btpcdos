program MemArray;

{ A table of two thousand records in one block, got with GetMem and given
  back with FreeMem from rtldos.pas. GetMem and FreeMem are New and
  Dispose by another name: same allocator, same blocks, so a program may mix
  them and a block got with one can be given back with the other.

  The table is walked twice through a pointer to the record type, advanced by
  the size of one record. A record takes the room its fields take and nothing
  more - the compiler lays the fields out one after another - so a record of
  six integers is twenty-four bytes. The second walk reads the table back and
  compares it with what was written: a stride that did not match the layout
  would leave every value after the first one wrong, which is the failure
  this is here to catch.

  What it prints:

    count      how many records were written
    sum        the sum of the second field, which the program also knows
    readback   how many records came back exactly as they went in
    base       the block's address after FreeMem, which zeroes it }

{ The runtime library is RTLDOS.PAS, and the compiler reads it before the
  first line of this file: there is no include for it here. }

type TRec=record
      Id:integer;
      Value:integer;
      A:integer;
      B:integer;
      C:integer
     end;
     PRec=^TRec;

const RecSize=20;         { five cells of four bytes: see the layout above }
      Count=2000;
      Expect=6003000;     { 3 * (1+2+...+2000) }

var Base:integer;
    P:PRec;
    i,Sum,ReadBack:integer;

begin
 Base:=GetMem(Count*RecSize);
 if Base=0 then begin
  WriteLn('no memory for the table');
  Halt
 end;

 P:=Base;
 for i:=1 to Count do begin
  P^.Id:=i;
  P^.Value:=i*3;
  P^.A:=1;
  P^.B:=2;
  P^.C:=3;
  P:=P+RecSize
 end;
 WriteLn('count=',Count:1);

 Sum:=0;
 ReadBack:=0;
 P:=Base;
 for i:=1 to Count do begin
  Sum:=Sum+P^.Value;
  if (P^.Id=i) and (P^.Value=i*3) and (P^.C=3) then begin
   ReadBack:=ReadBack+1
  end;
  P:=P+RecSize
 end;
 WriteLn('sum=',Sum:1,' expect=',Expect:1);
 WriteLn('readback=',ReadBack:1);

 FreeMem(Base);
 WriteLn('base=',Base:1)
end.
