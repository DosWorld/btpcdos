program Shifts;

{ shl and shr - a shift by a bit count, as Turbo Pascal has them.

  There are four things to know about them and every one is a line below.
  They have the precedence of *, so they bind tighter than +. The count is
  taken modulo 32, which is what the machine does with it. shr is logical,
  so the bit shifted in is a zero and the sign is gone after the first shift.
  And a sign written before a term belongs to the whole term, the way it does
  before *, which is why the negative values below are put in a variable
  first: -1 shr 1 is -(1 shr 1), and it is 0.

  What it prints:

    shl, shr       a power of two times a value, and the same value back
    precedence     shl tighter than +, shown from both sides
    32             the count taken modulo 32
    31             the bit that leaves the top is not kept, so the sign can
                   change: 1 shl 31 is the smallest integer there is
    logical        a negative value shifted as the unsigned 32-bit value it
                   stands for, and the zeros that come in
    sign           the sign binding the whole term, on a count and on a
                   negative value
    variable       the count as a value and not a constant }

{ The runtime library is RTLDOS.PAS, and the compiler reads it before the
  first line of this file: there is no include for it here. }

var n,k:integer;

begin
 WriteLn('shl 3 shl 8=',3 shl 8:1,' expect=768');
 WriteLn('shr 256 shr 4=',256 shr 4:1,' expect=16');

 { The same two from the other side: what is on the left of the operator is
   the whole term, so neither of these is (1+1) shl 3 and neither is 4 shl 2. }
 WriteLn('1+1 shl 3=',1+1 shl 3:1,' expect=9');
 WriteLn('4 shl 1+1=',4 shl 1+1:1,' expect=9');

 { Within 32 there is nothing to mask, so a count of 32 is a count of 0 and
   a count of 33 is a count of 1. }
 WriteLn('32 1 shl 32=',1 shl 32:1,' expect=1');
 WriteLn('32 1 shl 33=',1 shl 33:1,' expect=2');
 WriteLn('31 1 shl 31=',1 shl 31:1);

 { -1 is four bytes of ones, and shr moves zeros in at the top, so what comes
   out is the positive value those 32 bits stand for. }
 n:=-1;
 WriteLn('logical -1 shr 1=',n shr 1:1,' expect=2147483647');
 n:=-256;
 WriteLn('logical -256 shr 4=',n shr 4:1,' expect=268435440');
 WriteLn('logical -256 shr 31=',n shr 31:1,' expect=1');

 { The sign is read before the operation, not after it. }
 WriteLn('sign -256 shr 4=',-256 shr 4:1,' expect=-16');

 { A count may be a value: five shifted left by two is twenty, and five
   shifted right by two is one, with the bit that falls off the bottom gone. }
 n:=5;
 k:=2;
 WriteLn('variable 5 shl 2=',n shl k:1,' expect=20');
 WriteLn('variable 5 shr 2=',n shr k:1,' expect=1');
 WriteLn('variable 5 shl 5=',n shl n:1,' expect=160')
end.
