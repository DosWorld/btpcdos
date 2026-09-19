program InlineDemo;

{ inline($xx,...): bytes the programmer writes, put where the statement is.

  A block is written out as it stands and nothing is fused across it, and it
  has to leave the machine stack as it found it. That is the whole contract;
  what the bytes do is the programmer's business. The blocks below are each
  one part of it, and each one does something the program can then check.

  The bytes are for the machine the compiler is generating for, and here that
  is a 32 bit flat program: the registers are EAX, EDI and the like, and a
  segment register holds a selector and not a paragraph, so a segment
  register cannot be pointed at the screen - a linear address can. That is
  the one thing about writing a block for this target that is easy to get
  wrong, and the first block below is written both ways round: the wrong
  version, kept as a comment, is the one an assembler for real mode would
  have taken.

  What it prints:

    wrote     a character and its attribute written straight into the text
              screen by a block, and the same cell read back through a
              pointer: had the bytes not run, the cell would hold what it
              held before
    branch    the line after a block that branches over two bytes that are
              data and not code - reached only if the branch went where it
              was written to go
    stack     the sum a loop added up, with a block that pushes and pops
              inside the loop: unchanged, so the stack is where it was found
    hex       the same bytes as the first block, spelled $xx }

{ The runtime library is RTLDOS.PAS, and the compiler reads it before the
  first line of this file: there is no include for it here. }

type PInt=^integer;

var Cell:PInt;
    i,Sum:integer;

begin
 { PUSH EAX / PUSH EDI / MOV EDI,0B8000h / MOV AX,0748h / MOV [EDI],AX /
   POP EDI / POP EAX

   - the first cell of the text screen: 'H' in the low half of AX, which is
   the character, and 7, light grey on black, in the high half, which is the
   attribute. EDI holds the address the flat data segment starts at, which is
   the address itself.

   Real mode would say mov ax,0B800h / mov es,ax / mov [es:di],ax, which in
   this program loads a selector and faults. }
 inline($50, $57,
        $BF,$00,$80,$0B,$00,
        $66,$B8,$48,$07,
        $66,$89,$07,
        $5F, $58);

 { Read back: a screen cell is two bytes, the character and its attribute, and
   a variable of type char here is a four byte cell, so the pair is read as
   one integer and taken apart a byte at a time. Reading it as a PChar would
   step four bytes at a time - the next character is four bytes on, which is
   the trap the library's pointer comment names. }
 Cell:=$B8000;
 Write('wrote=',chr(RtlByte(Cell^,0)));
 if RtlByte(Cell^,1)=7 then begin
  WriteLn(' attr=7')
 end else begin
  WriteLn(' attr=not-7')
 end;

 { JMP +2 over two bytes that are data, then a NOP: the jump lands on the NOP
   and the data is left as data. }
 inline($EB,$02,$11,$22,$90);
 WriteLn('branch=reached');

 Sum:=0;
 for i:=1 to 10 do begin
  inline($50,$58);                  { PUSH EAX; POP EAX }
  Sum:=Sum+i
 end;
 WriteLn('stack=',Sum:1,' expect=55');

 { The first block's bytes again, with 'X' this time. }
 inline($50, $57,
        $BF,$00,$80,$0B,$00,
        $66,$B8,$58,$07,
        $66,$89,$07,
        $5F, $58);
 if chr(RtlByte(Cell^,0))='X' then begin
  WriteLn('hex=X')
 end else begin
  WriteLn('hex=not-X')
 end
end.
