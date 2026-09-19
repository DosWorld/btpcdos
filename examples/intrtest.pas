program IntrTest;

{ Intr(i, r) - an interrupt with the registers the caller put in a record.

  The host runs the interrupt through the DPMI call that emulates one, 0300h,
  so what is exercised here is the whole of the pair: the compiler's builtin,
  the record's layout, and the runtime's translation of the record into the
  real mode register structure DPMI wants. Every call below is a DOS call
  whose arguments and answer are registers, which is what this interface
  carries; a call that moves bytes through memory wants a real mode buffer and
  is not what it is for.

  What it prints:

    version        AH=30h, the two bytes the version comes in
    major, minor   the same two bytes, apart
    date, time     AH=2Ah and AH=2Ch
    drive          AH=19h, one for A:
    key            AH=0Bh - nothing is waiting when the input is a file
    hand           the version again, written out by hand: AH=30h in the high
                   byte of EAX, the answer read back out of the record. The
                   library's DosVersion makes the same call, so the two lines
                   have to agree
    pspseg         AH=51h answers with the program's PSP in EBX. It is a real
                   mode segment, and a small number is the sign that the call
                   ran in real mode and not in protected mode with a selector
    flags          AH=3Eh on a handle that is not one fails, and the carry
                   is how a DOS call says so: it went out clear on the
                   record, so the set carry is the interrupt's own answer }

{ The runtime library is RTLDOS.PAS, and the compiler reads it before the
  first line of this file: there is no include for it here. }

var r:Registers;

begin
 WriteLn('version=',DosVersion:1);
 WriteLn('major=',DosMajor:1,' minor=',DosMinor:1);
 WriteLn('date=',DosDate:1,' time=',DosTime:1);
 WriteLn('drive=',DosDrive:1);
 if KeyPressed then begin
  WriteLn('key=yes')
 end else begin
  WriteLn('key=no')
 end;

 { The call DosVersion makes, written out. }
 r.EAX:=$3000;
 Intr($21,r);
 WriteLn('hand=',RtlByte(r.EAX,1):1,'.',RtlByte(r.EAX,0):1);

 { A call nothing in the library names, to show that the record is the whole
   of what carries it. }
 r.EAX:=$5100;
 Intr($21,r);
 WriteLn('pspseg=',RtlByte(r.EBX,0)+(RtlByte(r.EBX,1) shl 8):1);

 { AH=3Eh closes a file handle, and FFFFh is not one: the call fails, and it
   fails on every DOS there is, so the line does not depend on what the
   machine has. The carry went out clear and comes back set, which is the
   interrupt's own answer and not the caller's. }
 r.Flags:=0;
 r.EAX:=$3E00;
 r.EBX:=$FFFF;
 Intr($21,r);
 WriteLn('badhandle flags=',r.Flags:1,' expect=1')
end.
