; hxrtl.asm - the HX-DOS runtime for programs compiled by BeRoTinyPascal.
;
; Copyright (C) 2026, DosWorld    The Unlicense (public domain)
;
; Assembled as a flat binary blob (egasm +BIN) and placed at RVA 1000h of the
; output image, so the blob's first byte is the image's entry point. The
; generated program code is appended right after the blob.
;
; Everything here is position independent. The blob holds no absolute address
; of its own: the boot code takes its address off the stack, builds the
; function table from a table of offsets, and every later access to the blob's
; data goes through ESI, which generated code keeps pointing at the function
; table for the whole run (see the XChgEDXESI pairs in AssembleAndLink). The
; image therefore needs no relocation table and stays correct wherever the
; loader maps it.
;
; Calling convention: the compiler pushes the arguments in source order, so the
; last one is on top of the stack when the callee is entered; a callee removes
; them with RET 4*n. Generated code holds values on the machine stack, but ESI
; and EBP are live in it, so every function here preserves ESI, EBP, EBX and
; EDI.

.CPU PENTIUM4
.BITS 32

; Function table offsets. The compiler emits CALL DWORD PTR [ESI+ofs], so these
; numbers are a contract with btpc.pas and have to match it exactly.
RTLFUNCTIONCOUNT     EQU 22

; The room FileOpen copies a name into, so that a caller can pass a counted
; string (Pascal has no terminators) to a DOS call that wants ASCIZ. A name
; longer than this is cut rather than overrunning anything, and DOS's own limit
; on a path is 260 including the terminator.
RTLNAMESIZE          EQU 260

; The room one command-line parameter is copied into, in chars. DOS's tail is
; 127 bytes at the most, so a parameter can never be longer than this,
; terminator and all; a file name is what the copy is usually for. The copy is
; held in the compiler's own representation - one 32-bit cell per char, like
; every other string a program can see - so the buffer is four times this.
RTLPARAMSIZE         EQU 128

; AX=0500h, int 31h, is how much memory is left: the host fills a 48-byte
; record whose first dword is the largest block it can still give. That is the
; figure to ask 0501h for. A module is mapped out of that same free memory, and
; one loaded while the program already runs is mapped while it runs, so a
; program that takes every last byte has taken away its own ability to load
; anything. What is held back stays contiguous, because taking a block never
; splits the free memory.
RTLRESERVE           EQU 400000H
RTLMINSIZE           EQU 100000H

; What SysAllocMax will take for a pool. The boot's minimum is a megabyte
; because a program that cannot be given that has no business running; a pool
; only has to be big enough to be worth splitting, and the library's allocator
; asks for another one when this one is full, so what is left over on a small
; machine is still memory a program can use.
RTLHEAPMIN           EQU 10000H

; The field WriteInteger builds in before writing it out: at most eleven digits
; and a sign, and this much room in all, so the widest field it can produce is
; RTLDECIMALSIZE characters. A program that asks for more than that gets the
; widest field that fits rather than a write that runs off the buffer.
RTLDECIMALSIZE       EQU 64

; A char in a Pascal array is one 32-bit cell and not one byte: the compiler
; gives every simple type Size 4 (Types[TypeCHAR].Size in btpc.pas), so the
; stride of array[1..n] of char is RTLCHARSIZE. Everything here that moves a
; program's buffer stages it through RTLBuffer, packing one byte per cell on
; the way out and unpacking a zero-extended byte per cell on the way in - zero
; extended because that is the shape a char has when the generated code loads
; one, and a program compares a char it read with a char it wrote.
;
; A count is in chars, which is what a program has: the length of the array it
; passes. On the file side one char is one byte.
RTLCHARSIZE          EQU 4
RTLBUFFERSIZE        EQU 4096

; The entry point can only be the first byte of the section, so it is a jump to
; the boot code, which sits last and falls through into the program.
JMP RTLBoot

; ---------------------------------------------------------------------------
; Halt - int 21h AH=4Ch. The DPMI block is deliberately not released: the host
; frees every block a client owns when the client terminates, and 0502h on a
; block that borders the image faults (see API.ob07 FreeHeap in the Oberon
; tree).
; ---------------------------------------------------------------------------
RTLHalt:
 MOV AH,4CH
 INT 21H
 HLT

; ---------------------------------------------------------------------------
; DPMICall - the one place this runtime enters the DPMI host.
;
; AX holds the function number and every other register the function wants is
; already loaded, exactly as appendix A of the plan lists the calls. The carry
; comes back saying whether the host refused, and it is still there after the
; RET: a return moves no flags.
;
; Nothing else in this file may say int 31h. The interrupts a program asks for
; with Intr are run by the host through 0300h - simulate real mode interrupt -
; and every DPMI call the runtime makes for itself is one of these. The
; distinction is the one the two have in DPMI: what the host offers as a
; function is called here, and what a program asks for as an interrupt is
; emulated there.
; ---------------------------------------------------------------------------
DPMICall:
 INT 31H
 RET

; ---------------------------------------------------------------------------
; WriteChar(c) - one byte to handle 1 with AH=40h. AH=02h would be shorter, but
; its output is not reliably redirected, and a program that is compiled and run
; from a batch file has to be able to log to a file. One byte at a time through
; the handle costs nothing that matters here.
; ---------------------------------------------------------------------------
RTLWriteChar:
 PUSH EBX
 PUSH ECX
 PUSH EDX
 PUSH ESI
 PUSH EDI
 MOV EBX,ESP                        ; [EBX+24] c
 MOV EAX,DWORD PTR [EBX+24]
 MOV EDX,ESI
 SUB EDX,RTLFunctionTable-RTLCharBuffer
 MOV BYTE PTR [EDX],AL
 MOV ECX,1
 MOV EBX,1                          ; stdout
 MOV AH,40H
 INT 21H
 POP EDI
 POP ESI
 POP EDX
 POP ECX
 POP EBX
 RET 4

; ---------------------------------------------------------------------------
; WriteInteger(value, width) - decimal, negative values signed, right aligned in
; `width` with spaces, the way Turbo Pascal's Write(v:w) does it.
;
; The Win32 runtime this replaces wrote the sign first and then the padding, so
; Write(-42:6) came out as "-   42" there and comes out as "   -42" here. The
; width is the same either way; only the sign's place in a padded field differs,
; and it differs by being right this time.
; ---------------------------------------------------------------------------
RTLWriteInteger:
 PUSH EBX
 PUSH ECX
 PUSH EDX
 PUSH ESI
 PUSH EDI
 PUSH EBP
 MOV EBX,ESP                        ; [EBX+28] width, [EBX+32] value
 MOV EAX,DWORD PTR [EBX+32]
 MOV EDI,ESI
 SUB EDI,RTLFunctionTable-RTLDecimalBuffer-RTLDECIMALSIZE
 XOR ECX,ECX
 XOR EBP,EBP                        ; EBP = the sign, noted for later
 TEST EAX,EAX
 JNS RTLWriteIntegerDigits
 NEG EAX                            ; -2147483648 negates to itself, which
 MOV EBP,1                          ; still divides out as unsigned
RTLWriteIntegerDigits:
 MOV ESI,10
RTLWriteIntegerLoop:
 XOR EDX,EDX
 DIV ESI
 ADD DL,'0'
 DEC EDI                            ; the buffer fills backwards, so the last
 MOV BYTE PTR [EDI],DL              ; digit written ends up first
 INC ECX
 TEST EAX,EAX
 JNZ RTLWriteIntegerLoop
 TEST EBP,EBP
 JZ RTLWriteIntegerPad
 DEC EDI                            ; the sign goes in front of the digits,
 MOV BYTE PTR [EDI],'-'             ; which is below them in the buffer
 INC ECX
RTLWriteIntegerPad:
 MOV EDX,DWORD PTR [EBX+28]         ; width
 SUB EDX,ECX
 JLE RTLWriteIntegerWrite
 MOV ESI,RTLDECIMALSIZE             ; what is left of the buffer is all the
 SUB ESI,ECX                        ; padding there is room for
 CMP EDX,ESI
 JBE RTLWriteIntegerPadLoop
 MOV EDX,ESI
RTLWriteIntegerPadLoop:
 DEC EDI
 MOV BYTE PTR [EDI],' '
 INC ECX
 DEC EDX
 JNZ RTLWriteIntegerPadLoop
RTLWriteIntegerWrite:
 MOV EDX,EDI                        ; the field starts at EDI and is ECX long
 MOV EBX,1                          ; stdout
 MOV AH,40H
 INT 21H
 POP EBP
 POP EDI
 POP ESI
 POP EDX
 POP ECX
 POP EBX
 RET 8

; ---------------------------------------------------------------------------
; WriteLn - CR LF.
; ---------------------------------------------------------------------------
RTLWriteLn:
 PUSH EDX
 PUSH EBX
 PUSH ESI
 PUSH EDI
 MOV EDX,ESI
 SUB EDX,RTLFunctionTable-RTLNewLine
 MOV ECX,2
 MOV EBX,1
 MOV AH,40H
 INT 21H
 POP EDI
 POP ESI
 POP EBX
 POP EDX
 RET
RTLNewLine: DB 13,10

; ---------------------------------------------------------------------------
; Input. The shape is the one the Win32 runtime had, because the compiler's
; source is written against it: the stream is read through a one-byte
; lookahead, EOF is sticky once a read comes back empty, and ReadLn stops *on*
; the line feed rather than past it.
;
; The bytes behind the lookahead come from a block buffer, refilled with
; AH=3Fh on handle 0. That is a handle read and not AH=0Ah, so redirected
; input works and a program can be run from a file.
;
; The three helpers below are internal, and RTLInPeek/RTLInSkip keep the
; convention that only EAX is clobbered - the callers hold values in EBX, ECX
; and EDI across them.
; ---------------------------------------------------------------------------

; RTLInFill: refill the buffer from handle 0. Sets RTLInEOF when the read
; comes back empty. Preserves every register.
RTLInFill:
 PUSHAD
 MOV EDX,ESI
 SUB EDX,RTLFunctionTable-RTLInBuffer
 PUSH ESI                           ; the DOS call is free to clobber it
 MOV ECX,4096
 XOR EBX,EBX                        ; handle 0 = standard input
 MOV AH,3FH
 INT 21H
 POP ESI
 JC RTLInFillFailed
 TEST EAX,EAX
 JNZ RTLInFillGot
RTLInFillFailed:
 MOV EDI,ESI
 SUB EDI,RTLFunctionTable-RTLInEOF
 MOV BYTE PTR [EDI],1
 XOR EAX,EAX
RTLInFillGot:
 MOV EDI,ESI
 SUB EDI,RTLFunctionTable-RTLInPos
 MOV DWORD PTR [EDI],0
 MOV EDI,ESI
 SUB EDI,RTLFunctionTable-RTLInCount
 MOV DWORD PTR [EDI],EAX
 POPAD
 RET

; RTLInNext: pull the next byte into the lookahead. At end of input the
; lookahead keeps its last byte and RTLInEOF is set. Preserves every register.
RTLInNext:
 PUSHAD
 MOV EDI,ESI
 SUB EDI,RTLFunctionTable-RTLInPos
 MOV ECX,DWORD PTR [EDI]
 MOV EDX,ESI
 SUB EDX,RTLFunctionTable-RTLInCount
 CMP ECX,DWORD PTR [EDX]
 JB RTLInNextTake
 CALL RTLInFill
 MOV EDI,ESI
 SUB EDI,RTLFunctionTable-RTLInPos
 MOV ECX,DWORD PTR [EDI]
 MOV EDX,ESI
 SUB EDX,RTLFunctionTable-RTLInCount
 CMP ECX,DWORD PTR [EDX]
 JAE RTLInNextDone
RTLInNextTake:
 MOV EDX,ESI
 SUB EDX,RTLFunctionTable-RTLInBuffer
 ADD EDX,ECX
 MOV AL,BYTE PTR [EDX]
 INC ECX
 MOV DWORD PTR [EDI],ECX
 MOV EDX,ESI
 SUB EDX,RTLFunctionTable-RTLInChar
 MOV BYTE PTR [EDX],AL
RTLInNextDone:
 POPAD
 RET

; RTLInInit: prime the lookahead, once. Preserves every register.
RTLInInit:
 PUSHAD
 MOV EDI,ESI
 SUB EDI,RTLFunctionTable-RTLInInited
 CMP BYTE PTR [EDI],0
 JNE RTLInInitDone
 MOV BYTE PTR [EDI],1
 CALL RTLInNext
RTLInInitDone:
 POPAD
 RET

; RTLInAtEof: AL = 1 when the input has run out. At that point the lookahead
; stops moving, so every loop that consumes bytes has to ask this as well as
; look at the byte, or it spins forever on the last one. Only EAX is changed.
RTLInAtEof:
 PUSH EDX
 MOV EDX,ESI
 SUB EDX,RTLFunctionTable-RTLInEOF
 MOVZX EAX,BYTE PTR [EDX]
 POP EDX
 RET

; RTLInPeek: AL = the lookahead byte. Only EAX is changed.
RTLInPeek:
 PUSH EDX
 MOV EDX,ESI
 SUB EDX,RTLFunctionTable-RTLInChar
 MOV AL,BYTE PTR [EDX]
 POP EDX
 RET

; RTLInSkip: consume the lookahead byte. Only EAX is changed.
RTLInSkip:
 CALL RTLInNext
 RET

; ---------------------------------------------------------------------------
; ReadChar - the lookahead byte, then advance.
; ---------------------------------------------------------------------------
RTLReadChar:
 PUSHAD
 CALL RTLInInit
 CALL RTLInPeek
 MOV DWORD PTR [ESP+28],EAX         ; PUSHAD pushed EAX last, so it is here
 CALL RTLInSkip
 POPAD
 RET

; ---------------------------------------------------------------------------
; ReadInteger - whitespace, an optional minus, then digits.
; ---------------------------------------------------------------------------
RTLReadInteger:
 PUSHAD
 CALL RTLInInit
RTLReadIntegerSpace:
 CALL RTLInPeek
 MOVZX ECX,AL
 TEST ECX,ECX
 JZ RTLReadIntegerZero              ; a NUL byte: nothing was read
 CMP ECX,32
 JA RTLReadIntegerSign
 CALL RTLInAtEof
 TEST AL,AL
 JNZ RTLReadIntegerZero             ; end of input: nothing was read
 CALL RTLInSkip
 JMP RTLReadIntegerSpace
RTLReadIntegerZero:
 XOR EAX,EAX                        ; nothing was read: the result is zero,
 JMP RTLReadIntegerStore            ; and the store below takes it from EAX
RTLReadIntegerSign:
 XOR EDI,EDI
 CMP AL,'-'
 JNE RTLReadIntegerDigits
 MOV EDI,1
 CALL RTLInSkip
RTLReadIntegerDigits:
 XOR EBX,EBX
RTLReadIntegerLoop:
 CALL RTLInPeek
 CMP AL,'0'
 JB RTLReadIntegerDone
 CMP AL,'9'
 JA RTLReadIntegerDone
 MOVZX ECX,AL
 SUB ECX,'0'
 IMUL EBX,EBX,10
 ADD EBX,ECX
 CALL RTLInSkip
 JMP RTLReadIntegerLoop
RTLReadIntegerDone:
 MOV EAX,EBX
 TEST EDI,EDI
 JZ RTLReadIntegerStore
 NEG EAX
RTLReadIntegerStore:
 MOV DWORD PTR [ESP+28],EAX
 POPAD
 RET

; ---------------------------------------------------------------------------
; ReadLn - discard up to and including the end of the line, stopping on the
; line feed itself, which stays in the lookahead.
; ---------------------------------------------------------------------------
RTLReadLn:
 PUSHAD
 CALL RTLInInit
RTLReadLnLoop:
 CALL RTLInPeek
 MOVZX ECX,AL
 TEST ECX,ECX
 JZ RTLReadLnDone
 CMP ECX,10
 JE RTLReadLnDone
 CALL RTLInAtEof
 TEST AL,AL
 JNZ RTLReadLnDone
 CALL RTLInSkip
 JMP RTLReadLnLoop
RTLReadLnDone:
 POPAD
 RET

; ---------------------------------------------------------------------------
; EOF and EOLN. Both answer in EAX, which is what the generated code pushes.
; ---------------------------------------------------------------------------
RTLEOF:
 PUSH EDX
 MOV EDX,ESI
 SUB EDX,RTLFunctionTable-RTLInEOF
 MOVZX EAX,BYTE PTR [EDX]
 POP EDX
 RET
RTLEOLN:
 PUSH EDX
 MOV EDX,ESI
 SUB EDX,RTLFunctionTable-RTLInChar
 MOVZX EAX,BYTE PTR [EDX]
 CMP EAX,10
 SETE AL
 MOVZX EAX,AL
 POP EDX
 RET

; ---------------------------------------------------------------------------
; Files. Everything here takes and returns linear addresses, which is all an HX
; client needs: it is flat, so DS is its own segment and a buffer address from
; Pascal is already what DOS wants in EDX. A failure is -1, the DOS convention.
;
; What the addresses point at is the compiler's own representation: a name and
; a buffer are char arrays, one 32-bit cell per char, so this section packs
; them into RTLBuffer on the way to DOS and unpacks what comes back. A caller
; writes the code it would write in Turbo Pascal - a name in an array[1..n] of
; char and a count of chars - and never sees the difference.
;
; Open asks for the long-name entry, AH=716Ch, first, and falls back to the old
; 8.3 entry - AH=3Dh for a file that is there, AH=3Ch for one that is to be
; created - when the long-name call comes back with the carry set. The carry is
; set before that call and read after it, and that is not decoration: it is the
; only way to tell the two answers apart. A DOS that has no long-name functions
; leaves the carry as it found it, and a handler that does not touch the flags
; at all is the case the fallback exists for. There is no way to ask whether
; long names are there - the carry after the call is the answer.
;
; Which entry answered is not recorded, because it does not have to be: what
; this buys is that a DOS without long names is a DOS where 8.3 names still
; work, instead of the DOS where nothing opens at all that an open with no
; fallback makes of it. A long name needs a DOS with long names; a program that
; has to run under both writes 8.3 names.
;
; The other file calls take a handle and not a name, so none of them is
; affected: read, write, seek and close are 3Fh, 40h, 42h and 3Eh on every DOS.
;
; AH=3Fh and AH=40h take a 16-bit count in CX, so one call moves at most
; 0FF00h bytes; a caller that wants more calls again. The count is clamped here
; rather than refused, because a short transfer is easy to notice (the caller
; compares the result with what it asked for) and a wrong one is not.
;
; DOS may clobber any register it likes, so every entry saves the whole set
; around its calls and puts the result in EAX afterwards.
; ---------------------------------------------------------------------------

; FileOpen(nameAdr, nameLen, mode) -> handle, or -1.
;   0 = open an existing file for reading
;   1 = create or truncate it and open it for writing
;   2 = open an existing file for reading and writing
;   3 = create or truncate it and open it for reading and writing
;
; A negative nameLen says that the name at nameAdr is NUL-terminated and that
; its length is not known to the caller. That is the shape the command line
; hands out, so ParamStr's answer can go straight in here.
RTLFileOpen:
 PUSH EBX
 PUSH ECX
 PUSH EDX
 PUSH ESI
 PUSH EDI
 PUSH EBP
 MOV EBX,ESP                        ; [EBX+28] mode, [EBX+32] nameLen,
                                    ; [EBX+36] nameAdr
 MOV EDX,DWORD PTR [EBX+28]
 MOV ECX,DWORD PTR [EBX+32]
 MOV EAX,DWORD PTR [EBX+36]
 TEST ECX,ECX
 JS RTLFileOpenZName                ; a negative length: the caller has no
                                    ; length to give, only a NUL-terminated
                                    ; name - which is what ParamStr answers
                                    ; with, and what a command line is
 CMP ECX,RTLNAMESIZE-1
 JBE RTLFileOpenCopy
 MOV ECX,RTLNAMESIZE-1
RTLFileOpenCopy:
 MOV EDI,ESI
 SUB EDI,RTLFunctionTable-RTLNameBuffer
 MOV EBP,EDI                        ; EBP = where the name goes
 TEST ECX,ECX
 JZ RTLFileOpenTerminate
RTLFileOpenCopyLoop:
 MOV BL,BYTE PTR [EAX]              ; EBX has done its job as the frame pointer
 MOV BYTE PTR [EDI],BL
 ADD EAX,RTLCHARSIZE                ; one cell per char in the caller's array
 INC EDI                            ; one byte per char in the name DOS reads
 DEC ECX
 JNZ RTLFileOpenCopyLoop
 JMP RTLFileOpenTerminate
RTLFileOpenZName:
 MOV ECX,RTLNAMESIZE-1              ; as much of the name as will fit, the
 MOV EDI,ESI                        ; terminator included
 SUB EDI,RTLFunctionTable-RTLNameBuffer
 MOV EBP,EDI
RTLFileOpenZNameLoop:
 TEST ECX,ECX
 JZ RTLFileOpenTerminate            ; a name that never ends is cut here
 MOV BL,BYTE PTR [EAX]
 TEST BL,BL
 JZ RTLFileOpenTerminate
 MOV BYTE PTR [EDI],BL
 ADD EAX,RTLCHARSIZE
 INC EDI
 DEC ECX
 JMP RTLFileOpenZNameLoop
RTLFileOpenTerminate:
 MOV BYTE PTR [EDI],0
 AND EDX,3                          ; the mode, which indexes all three tables
 MOV EDI,EDX                        ; kept: the short entry below needs it too
 MOV EBX,ESI
 SUB EBX,RTLFunctionTable-RTLFileAccessTable
 MOV EBX,DWORD PTR [EBX+EDX*4]      ; the access mode
 MOV ECX,ESI
 SUB ECX,RTLFunctionTable-RTLFileActionTable
 MOV ECX,DWORD PTR [ECX+EDX*4]      ; what to do with the file
 MOV EDX,ECX                        ; DX = the action
 MOV ECX,0                          ; attributes
 PUSH ESI                           ; the table base, the mode and the name,
 PUSH EDI                           ; which DOS is free to clobber across the
 PUSH EBP                           ; call and the fallback needs all three
 MOV EDI,0                          ; no alias hint
 MOV ESI,EBP                        ; DS:SI is where 716Ch takes the name
 MOV EAX,716CH
 STC                                ; and the carry is set first, so that it
                                    ; says something after the call: the
                                    ; long-name entry answered if and only if
                                    ; it came back clear. A handler that does
                                    ; not know the function leaves it set, and
                                    ; so does one that knows it and refused the
                                    ; file - a name that is not there is the
                                    ; case that reaches this every time a
                                    ; program is compiled from another
                                    ; directory and the library is not in the
                                    ; one the program is in
 INT 21H
 POP EBP                            ; the name, which the short entry below
                                    ; wants in DX rather than SI
 POP EDI                            ; the mode, which indexes both tables
 POP ESI                            ; the table base, which indexes them
 JNC RTLFileOpenGot
 MOV EDX,EBP                        ; DS:DX, which is where the short entry
                                    ; takes the name
 MOV EBX,ESI
 SUB EBX,RTLFunctionTable-RTLFileFallbackTable
 MOV EAX,DWORD PTR [EBX+EDI*4]      ; 3D00h/3D02h, or 3C00h to create
 MOV ECX,0                          ; the attributes 3Ch reads. AX and DS:DX
                                    ; are the rest of what the two entries
                                    ; look at, and neither is stale from the
                                    ; rejected 716Ch call: both were written
                                    ; here, after it
 INT 21H
 JC RTLFileOpenFailed
RTLFileOpenGot:
 AND EAX,0FFFFH                     ; the handle arrives in the low half
 JMP RTLFileOpenDone
RTLFileOpenFailed:
 MOV EAX,-1
RTLFileOpenDone:
 POP EBP
 POP EDI
 POP ESI
 POP EDX
 POP ECX
 POP EBX
 RET 12

; FileRead(h, bufAdr, count) -> chars read, 0 at the end of the file, or -1.
;
; The bytes come back into RTLBuffer and are then spread out, one zero-extended
; byte per cell, over the caller's array - whose cells are RTLCHARSIZE apart.
; The transfer runs in chunks so that a caller asking for more than RTLBuffer
; holds is served in full rather than silently cut short, and the loop stops on
; a read of nothing: that is the end of the file.
;
; The loop's state lives in the four dwords below EBP and not in registers,
; because DOS is free to clobber them.
;
; [EBP+0] chars still to read, [EBP+4] the next cell to fill, [EBP+8] chars
; read so far, [EBP+12] the chunk in hand; the arguments are above them, at
; [EBP+44] count, [EBP+48] bufAdr and [EBP+52] h.
RTLFileRead:
 PUSH EBX
 PUSH ECX
 PUSH EDX
 PUSH ESI
 PUSH EDI
 PUSH EBP
 SUB ESP,16
 MOV EBP,ESP
 MOV EAX,DWORD PTR [EBP+44]
 MOV DWORD PTR [EBP+0],EAX
 MOV EAX,DWORD PTR [EBP+48]
 MOV DWORD PTR [EBP+4],EAX
 MOV DWORD PTR [EBP+8],0
RTLFileReadLoop:
 MOV EAX,DWORD PTR [EBP+0]
 TEST EAX,EAX
 JZ RTLFileReadDone                 ; nothing left to ask for
 CMP EAX,RTLBUFFERSIZE
 JBE RTLFileReadChunk
 MOV EAX,RTLBUFFERSIZE
RTLFileReadChunk:
 MOV DWORD PTR [EBP+12],EAX
 MOV ECX,EAX                        ; the count is in bytes for DOS
 MOV EDX,ESI
 SUB EDX,RTLFunctionTable-RTLBuffer
 MOV EBX,DWORD PTR [EBP+52]
 MOV EAX,3F00H
 INT 21H
 JC RTLFileReadFailed
 AND EAX,0FFFFH                     ; what actually arrived
 TEST EAX,EAX
 JZ RTLFileReadDone                 ; the end of the file
 MOV DWORD PTR [EBP+12],EAX         ; a short read leaves less to spread out
 MOV ECX,EAX
 MOV EDI,ESI
 SUB EDI,RTLFunctionTable-RTLBuffer
 MOV EDX,DWORD PTR [EBP+4]
RTLFileReadExpand:
 MOVZX EBX,BYTE PTR [EDI]
 MOV DWORD PTR [EDX],EBX
 ADD EDI,1
 ADD EDX,RTLCHARSIZE
 DEC ECX
 JNZ RTLFileReadExpand
 MOV DWORD PTR [EBP+4],EDX          ; EDX is already the next cell
 MOV EDX,DWORD PTR [EBP+0]
 SUB EDX,EAX
 MOV DWORD PTR [EBP+0],EDX
 MOV EDX,DWORD PTR [EBP+8]
 ADD EDX,EAX
 MOV DWORD PTR [EBP+8],EDX
 JMP RTLFileReadLoop
RTLFileReadFailed:
 MOV EAX,-1
 JMP RTLFileReadExit
RTLFileReadDone:
 MOV EAX,DWORD PTR [EBP+8]
RTLFileReadExit:
 LEA ESP,[EBP+16]
 POP EBP
 POP EDI
 POP ESI
 POP EDX
 POP ECX
 POP EBX
 RET 12

; FileWrite(h, bufAdr, count) -> chars written, or -1. The mirror image of
; FileRead: one byte per cell goes into RTLBuffer, and the buffer goes to DOS
; in chunks. A chunk DOS takes none of - a full disk - ends the loop, so a
; write that cannot make progress is reported rather than retried forever.
RTLFileWrite:
 PUSH EBX
 PUSH ECX
 PUSH EDX
 PUSH ESI
 PUSH EDI
 PUSH EBP
 SUB ESP,16
 MOV EBP,ESP
 MOV EAX,DWORD PTR [EBP+44]
 MOV DWORD PTR [EBP+0],EAX
 MOV EAX,DWORD PTR [EBP+48]
 MOV DWORD PTR [EBP+4],EAX
 MOV DWORD PTR [EBP+8],0
RTLFileWriteLoop:
 MOV EAX,DWORD PTR [EBP+0]
 TEST EAX,EAX
 JZ RTLFileWriteDone                ; nothing left to write
 CMP EAX,RTLBUFFERSIZE
 JBE RTLFileWriteChunk
 MOV EAX,RTLBUFFERSIZE
RTLFileWriteChunk:
 MOV DWORD PTR [EBP+12],EAX
 MOV ECX,EAX
 MOV EDI,ESI
 SUB EDI,RTLFunctionTable-RTLBuffer
 MOV EDX,DWORD PTR [EBP+4]
RTLFileWritePack:
 MOV BL,BYTE PTR [EDX]
 MOV BYTE PTR [EDI],BL
 ADD EDX,RTLCHARSIZE
 ADD EDI,1
 DEC ECX
 JNZ RTLFileWritePack
 MOV ECX,DWORD PTR [EBP+12]         ; the packed length
 MOV EDX,ESI
 SUB EDX,RTLFunctionTable-RTLBuffer
 MOV EBX,DWORD PTR [EBP+52]
 MOV EAX,4000H
 INT 21H
 JC RTLFileWriteFailed
 AND EAX,0FFFFH
 TEST EAX,EAX
 JZ RTLFileWriteDone                ; no room left on the disk
 MOV EDX,DWORD PTR [EBP+4]
 LEA EDX,[EDX+EAX*RTLCHARSIZE]
 MOV DWORD PTR [EBP+4],EDX
 MOV EDX,DWORD PTR [EBP+0]
 SUB EDX,EAX
 MOV DWORD PTR [EBP+0],EDX
 MOV EDX,DWORD PTR [EBP+8]
 ADD EDX,EAX
 MOV DWORD PTR [EBP+8],EDX
 JMP RTLFileWriteLoop
RTLFileWriteFailed:
 MOV EAX,-1
 JMP RTLFileWriteExit
RTLFileWriteDone:
 MOV EAX,DWORD PTR [EBP+8]
RTLFileWriteExit:
 LEA ESP,[EBP+16]
 POP EBP
 POP EDI
 POP ESI
 POP EDX
 POP ECX
 POP EBX
 RET 12

; FileSeek(h, offset, whence) -> the new position, or -1. Whence 0 is the
; start of the file, 1 the current position and 2 the end.
RTLFileSeek:
 PUSH EBX
 PUSH ECX
 PUSH EDX
 PUSH ESI
 PUSH EDI
 PUSH EBP
 MOV EBX,ESP                        ; [EBX+28] whence, [EBX+32] offset,
                                    ; [EBX+36] h
 MOV EAX,DWORD PTR [EBX+28]
 MOV EDX,DWORD PTR [EBX+32]
 MOV ECX,EDX
 SHR ECX,16                         ; CX:DX is the offset, high half first
 AND EDX,0FFFFH
 AND EAX,0FFH
 OR EAX,4200H
 MOV EBX,DWORD PTR [EBX+36]
 INT 21H
 JC RTLFileSeekFailed
 SHL EDX,16                         ; the position comes back in DX:AX
 AND EAX,0FFFFH
 OR EAX,EDX
 JMP RTLFileSeekDone
RTLFileSeekFailed:
 MOV EAX,-1
RTLFileSeekDone:
 POP EBP
 POP EDI
 POP ESI
 POP EDX
 POP ECX
 POP EBX
 RET 12

; FileClose(h) -> 0, or -1.
RTLFileClose:
 PUSH EBX
 MOV EBX,ESP
 MOV EBX,DWORD PTR [EBX+8]
 MOV EAX,3E00H
 INT 21H
 JC RTLFileCloseFailed
 XOR EAX,EAX
 JMP RTLFileCloseDone
RTLFileCloseFailed:
 MOV EAX,-1
RTLFileCloseDone:
 POP EBX
 RET 4

; FileSize(h) -> the size, or -1. The position is left at the end of the file,
; because finding the size is a seek to the end; a caller that cares where it
; was saves the position with FileSeek(h,0,1) and puts it back afterwards.
RTLFileSize:
 PUSH EBX
 PUSH ECX
 PUSH EDX
 PUSH ESI
 PUSH EDI
 PUSH EBP
 MOV EBX,ESP
 MOV EBX,DWORD PTR [EBX+28]         ; the handle is the only argument
 MOV EAX,4202H                      ; whence 2, offset 0
 XOR ECX,ECX
 XOR EDX,EDX
 INT 21H
 JC RTLFileSizeFailed
 SHL EDX,16
 AND EAX,0FFFFH
 OR EAX,EDX
 JMP RTLFileSizeDone
RTLFileSizeFailed:
 MOV EAX,-1
RTLFileSizeDone:
 POP EBP
 POP EDI
 POP ESI
 POP EDX
 POP ECX
 POP EBX
 RET 4

; ---------------------------------------------------------------------------
; Params(index) - the command line. A negative index asks how many arguments
; there are; an index of zero or more asks for one of them, and the answer is
; the address of a NUL-terminated copy of it in RTLParamBuffer, or of an empty
; string when there is no such argument. The copy stands until the next call.
;
; The copy is in the compiler's representation - one 32-bit cell per char, the
; terminator a cell of its own - so its address can be passed to FileOpen or
; to Write as it stands, and a caller that has an array of its own can be
; given the text by the library.
;
; The arguments are the DOS command tail, which is a length byte at PSP:80h
; followed by the text at PSP:81h. An index of 1 is the first word of the tail
; and index 0 is empty, because DOS does not keep the name the program was
; run by: the tail begins where that name ended. Turbo Pascal's ParamStr(0)
; answers with the program's path, which a DOS program can only recover from
; the loader or from the environment block; a caller that wants the path asks
; the loader, and one that wants its arguments asks here.
;
; The tail is neither ours to write to nor terminated, so a parameter is
; copied out of it. Words are separated by blanks and tabs; quotes come
; through as ordinary characters, since a DOS tail is taken as typed.
;
; EBP is the anchor here, as it is in the boot: it holds the function table
; while the PSP is being asked for, and the two int 21h/31h calls that does
; are free to clobber everything else. It then becomes the answer, which is
; why the table is put back from the stack at the end.
; ---------------------------------------------------------------------------
RTLSysParams:
 PUSH EBX
 PUSH ECX
 PUSH EDX
 PUSH ESI
 PUSH EDI
 PUSH EBP
 MOV EBP,ESI                        ; EBP = the function table
 ; Where the parameters come from.
 MOV AH,51H
 INT 21H                            ; BX = the PSP's selector
 MOV AX,0006H
 CALL DPMICall                      ; CX:DX = where that selector starts
 MOVZX ESI,DX
 MOVZX EAX,CX
 SHL EAX,16
 OR ESI,EAX                         ; ESI = the PSP
 MOVZX ECX,BYTE PTR [ESI+80H]       ; the tail's length
 ADD ESI,81H                        ; ESI = the tail itself
 ; Where the answer goes, prepared now: a parameter that is not there has to
 ; come back as an empty string and not as the last call's text.
 MOV EDI,EBP
 SUB EDI,RTLFunctionTable-RTLParamBuffer
 MOV DWORD PTR [EDI],0              ; an empty string, as one cell holding a
 MOV EBP,EDI                        ; NUL: EBP = the buffer, and the answer
 ; The index, read here and again below: index 0 is a different kind of
 ; question - the program itself and not its arguments - and it is asked
 ; before the calls that follow have had their way with the registers.
 MOV EBX,ESP
 MOV EAX,DWORD PTR [EBX+28]
 TEST EAX,EAX
 JZ RTLSysParamsProgram
 ; The index, and the frame it is read from - EBX is the frame only from here,
 ; because the calls above were free to clobber it.
 MOV EBX,ESP
 MOV EAX,DWORD PTR [EBX+28]
 TEST EAX,EAX
 JS RTLSysParamsCount
 XOR EDX,EDX                        ; EDX = the words found so far
RTLSysParamsScan:
 TEST ECX,ECX
 JZ RTLSysParamsExit                ; the tail ran out: the empty string
 MOV BL,BYTE PTR [ESI]
 CMP BL,' '
 JE RTLSysParamsStep
 CMP BL,9
 JE RTLSysParamsStep
 INC EDX                            ; a word starts here
 CMP EDX,EAX
 JE RTLSysParamsCopy
RTLSysParamsSkipWord:
 TEST ECX,ECX
 JZ RTLSysParamsExit
 MOV BL,BYTE PTR [ESI]
 CMP BL,' '
 JE RTLSysParamsStep
 CMP BL,9
 JE RTLSysParamsStep
 INC ESI
 DEC ECX
 JMP RTLSysParamsSkipWord
RTLSysParamsStep:
 INC ESI
 DEC ECX
 JMP RTLSysParamsScan
RTLSysParamsCopy:
 TEST ECX,ECX
 JZ RTLSysParamsCopied
 MOVZX EAX,BYTE PTR [ESI]           ; the tail is packed, one byte a char
 CMP EAX,' '
 JE RTLSysParamsCopied
 CMP EAX,9
 JE RTLSysParamsCopied
 MOV DWORD PTR [EDI],EAX            ; the copy is not: it is what a program's
 ADD EDI,RTLCHARSIZE                ; own char array looks like, so that the
 INC ESI                            ; address can be handed to FileOpen or
 DEC ECX                            ; written out as it stands
 JMP RTLSysParamsCopy
RTLSysParamsCopied:
 MOV DWORD PTR [EDI],0
RTLSysParamsExit:
 MOV EAX,EBP                        ; the buffer
 JMP RTLSysParamsDone
; Index 0: the program's own path, the way Turbo Pascal answers ParamStr(0).
;
; Not from the PSP. DOS keeps the path in the environment block and keeps that
; block's segment at PSP:2Ch, which is the route every DOS program takes - but
; an HX client's PSP names a segment whose memory reads back as zeros, so
; there is no block there and no name after it. (Measured, and recorded in
; doc/hxdos.txt: the field is not zero, it just leads nowhere.) The loader is
; asked instead: AX=4B82h with EDX=0 answers the main module's handle in EAX,
; and AX=4B86h with that handle in EDX answers a flat pointer to the module's
; own path, NUL terminated. It is the sequence DKRNL32 uses on this host, both
; answers come back in the 32-bit registers, and it is what the Oberon library
; beside this one does for the same reason.
;
; The path is copied into the same buffer a parameter is, a cell to a
; character, so that it can be handed to FileOpen or written out as it stands.
RTLSysParamsProgram:
 PUSH ES                            ; ES is put aside and cleared for the two
 XOR EBX,EBX                        ; calls, and EBX with it: the loader reads
 MOV ES,BX                          ; the registers it is asked with, and a
 XOR EDX,EDX                        ; segment left over from the caller is a
 MOV AX,4B82H                       ; request it cannot answer. DKRNL32 clears
 INT 21H                            ; them in front of the same call.
 JC RTLSysParamsNoProgram           ; EAX = the main module's handle
 TEST EAX,EAX
 JZ RTLSysParamsNoProgram
 MOV EDX,EAX
 MOV AX,4B86H
 INT 21H                            ; EAX = a flat pointer to its path
 JC RTLSysParamsNoProgram
 TEST EAX,EAX
 JZ RTLSysParamsNoProgram
 POP ES
 MOV ESI,EAX                        ; ESI = the path, one byte a character
 MOV EDX,EBP                        ; EDX = the buffer, and the answer
 MOV ECX,RTLPARAMSIZE-1
RTLSysParamsProgramCopy:
 MOV AL,BYTE PTR [ESI]
 TEST AL,AL
 JZ RTLSysParamsProgramDone
 MOVZX EAX,AL
 MOV DWORD PTR [EDX],EAX
 ADD EDX,RTLCHARSIZE
 INC ESI
 DEC ECX
 JNZ RTLSysParamsProgramCopy
RTLSysParamsProgramDone:
 MOV DWORD PTR [EDX],0
 MOV EAX,EBP                        ; the answer is the buffer, not the
 JMP RTLSysParamsDone               ; last character the copy loop loaded
RTLSysParamsNoProgram:
 POP ES
 XOR EAX,EAX                        ; no name to give: the caller gets an
 JMP RTLSysParamsDone               ; empty string, which is what it had
                                   ; before it asked
RTLSysParamsCount:
 XOR EDX,EDX
RTLSysParamsCountScan:
 TEST ECX,ECX
 JZ RTLSysParamsCountDone
 MOV BL,BYTE PTR [ESI]
 CMP BL,' '
 JE RTLSysParamsCountStep
 CMP BL,9
 JE RTLSysParamsCountStep
 INC EDX
RTLSysParamsCountSkipWord:
 TEST ECX,ECX
 JZ RTLSysParamsCountDone
 MOV BL,BYTE PTR [ESI]
 CMP BL,' '
 JE RTLSysParamsCountStep
 CMP BL,9
 JE RTLSysParamsCountStep
 INC ESI
 DEC ECX
 JMP RTLSysParamsCountSkipWord
RTLSysParamsCountStep:
 INC ESI
 DEC ECX
 JMP RTLSysParamsCountScan
RTLSysParamsCountDone:
 MOV EAX,EDX
RTLSysParamsDone:
 POP EBP
 POP EDI
 POP ESI
 POP EDX
 POP ECX
 POP EBX
 RET 4

; ---------------------------------------------------------------------------
; Intr(number, VAR regs) - run an interrupt with the registers the caller put
; in the record, and leave its answer in the same record.
;
; The record is the library's Registers type, fifteen integers laid out as
; declared: EAX, EBX, ECX, EDX, ESI, EDI, EBP, ESP, Flags, ES, DS, FS, GS, CS,
; SS - byte offsets 0 to 56. Six of them are applied to the call: EAX, EBX,
; ECX, EDX, ESI and EDI, and those six come back with the interrupt's answers
; in them. EBP holds the record itself and ESP is the stack, so neither can
; be. Flags comes back holding the interrupt's carry in its low bit, which is
; the shape a caller tests.
;
; The interrupt is run by the host, through DPMI 0300h - simulate real mode
; interrupt - and not by an int instruction here. A protected mode int 21h
; does work under a host that reflects it, but the reflection is the host's
; own arrangement; 0300h is the call DPMI documents for having an interrupt
; run on a program's behalf, and the host does the translating. It takes BL =
; the interrupt number - with BH clear, and CX = the number of words to copy
; from the protected mode stack to the real mode one, which is none, because
; an interrupt's arguments are its registers - and ES:EDI = a real mode
; register structure, whose layout is nothing like the record's: EDI, ESI, EBP,
; one unused dword, EBX, EDX, ECX, EAX, then the flags and the six segment
; registers as words, then IP and SP. The structure is filled from the record,
; the call is made, and the record is filled back from the structure. The host
; reports success in its own carry, and an interrupt that could not be run
; comes back as a set carry with the structure untouched.
;
; The record's segment registers are the real mode segments to run the
; interrupt with, so a caller that wants a buffer in the first megabyte can
; name one. Zero means anywhere will do, and becomes the segment of the real
; mode stack below - the one paragraph of DOS memory this program is known to
; own. IP and CS are ignored, because the address comes from the interrupt
; vector, and the segment registers are not written back: what the host leaves
; in the structure is real mode segments and what is in the record is not.
;
; The flags are imposed rather than passed. A handler must not inherit the
; direction flag set or interrupts off, and the library's records are not
; cleared before use, so the bits that decide how the handler runs are set
; here and the rest of the caller's word is left as it is.
;
; SS:SP is the one field with nothing in the record to come from, and it has
; to be a real mode stack, because the interrupt pushes. The first call asks
; the host for a kilobyte of DOS memory (0100h) and every later call runs on
; that block, with SP at its top. The host frees it at exit with everything
; else a client owns. 0100h answers with the segment in AX - the address the
; real mode side knows the block by - and with a selector in DX, which is not
; an address at all and is of no use here: the host turns the structure's SS
; back into a linear address by shifting it left four.
;
; The structure's address comes from the instruction pointer and not from ESI,
; because a DPMI call is free to clobber ESI and 0300h is about to be one; the
; record's address stays in EBP, which no DPMI call touches.
; ---------------------------------------------------------------------------
RTLSysIntr:
 PUSH EBX
 PUSH ECX
 PUSH EDX
 PUSH ESI
 PUSH EDI
 PUSH EBP
 MOV EBP,DWORD PTR [ESP+28]         ; the record
 CALL RTLSysIntrPlace
RTLSysIntrPlace:
 POP EDI
 SUB EDI,RTLSysIntrPlace-RTLIntrRMCS
 CMP DWORD PTR [EDI+RTLIntrStackSeg-RTLIntrRMCS],0
 JNE RTLSysIntrStack
 MOV AX,5800H                       ; the loader leaves the arena to be handed
 INT 21H                            ; out last fit, high, and the top of the
 CALL RTLSysIntrPlace               ; arena is the ROM window: a block given
 POP EDI                            ; from there takes no writes, and the
 SUB EDI,RTLSysIntrPlace-RTLIntrRMCS; interrupt then runs on a stack that is
 MOVZX EBX,AL                       ; not there. Ask for the kilobyte low
 MOV DWORD PTR [EDI+RTLIntrStrategy-RTLIntrRMCS],EBX
 MOV AX,5801H
 XOR EBX,EBX
 INT 21H                            ; first fit, low memory
 XOR EBX,EBX                        ; the count is sixteen bits wide and the
 MOV BX,64                          ; kilobyte is what goes in it: paragraphs
 MOV AX,0100H
 CALL DPMICall                      ; DOS memory: AX = its real mode segment,
 JC RTLSysIntrRefused               ; the one the structure needs for SS, and
 CALL RTLSysIntrPlace               ; DX = a selector, which is not an address
 POP EDI                            ; a real mode stack can be given
 SUB EDI,RTLSysIntrPlace-RTLIntrRMCS
 MOVZX EDX,AX
 MOV DWORD PTR [EDI+RTLIntrStackSeg-RTLIntrRMCS],EDX
 MOV EBX,DWORD PTR [EDI+RTLIntrStrategy-RTLIntrRMCS]
 MOV AX,5801H
 INT 21H                            ; the strategy that was in force, back
RTLSysIntrStack:
 MOV EAX,DWORD PTR [EBP+20]         ; EDI
 MOV DWORD PTR [EDI+0],EAX
 MOV EAX,DWORD PTR [EBP+16]         ; ESI
 MOV DWORD PTR [EDI+4],EAX
 MOV EAX,DWORD PTR [EBP+24]         ; EBP
 MOV DWORD PTR [EDI+8],EAX
 MOV DWORD PTR [EDI+12],0           ; the dword the layout leaves unused
 MOV EAX,DWORD PTR [EBP+4]          ; EBX
 MOV DWORD PTR [EDI+16],EAX
 MOV EAX,DWORD PTR [EBP+12]         ; EDX
 MOV DWORD PTR [EDI+20],EAX
 MOV EAX,DWORD PTR [EBP+8]          ; ECX
 MOV DWORD PTR [EDI+24],EAX
 MOV EAX,DWORD PTR [EBP+0]          ; EAX
 MOV DWORD PTR [EDI+28],EAX
 MOV AX,WORD PTR [EBP+32]           ; the caller's flags, less the three bits a
 AND AX,0FAFFH                      ; handler must not inherit wrong: no trap
 OR AX,202H                         ; flag, no direction flag, interrupts on,
 MOV WORD PTR [EDI+32],AX           ; and bit 1, which real mode always has set
 MOV EDX,DWORD PTR [EDI+RTLIntrStackSeg-RTLIntrRMCS]
 MOV EAX,DWORD PTR [EBP+36]         ; ES
 AND EAX,0FFFFH
 JNZ RTLSysIntrES
 MOV EAX,EDX
RTLSysIntrES:
 MOV WORD PTR [EDI+34],AX
 MOV EAX,DWORD PTR [EBP+40]         ; DS
 AND EAX,0FFFFH
 JNZ RTLSysIntrDS
 MOV EAX,EDX
RTLSysIntrDS:
 MOV WORD PTR [EDI+36],AX
 MOV EAX,DWORD PTR [EBP+44]         ; FS
 AND EAX,0FFFFH
 JNZ RTLSysIntrFS
 MOV EAX,EDX
RTLSysIntrFS:
 MOV WORD PTR [EDI+38],AX
 MOV EAX,DWORD PTR [EBP+48]         ; GS
 AND EAX,0FFFFH
 JNZ RTLSysIntrGS
 MOV EAX,EDX
RTLSysIntrGS:
 MOV WORD PTR [EDI+40],AX
 MOV WORD PTR [EDI+42],0            ; IP and CS: the address of what runs is
 MOV WORD PTR [EDI+44],0            ; the one in the interrupt's vector
 MOV WORD PTR [EDI+46],1024         ; SP = the top of the kilobyte
 MOV WORD PTR [EDI+48],DX           ; SS = the block's segment
 MOV EBX,DWORD PTR [ESP+32]         ; the interrupt number: BL is the number
 XOR ECX,ECX                        ; and BH has to be clear, and no words are
 PUSH EDI                           ; to be copied to the real mode stack
 MOV AX,0300H
 PUSH DS
 POP ES
 CALL DPMICall
 POP EDI
 JC RTLSysIntrRefused
 MOV EAX,DWORD PTR [EDI+28]         ; EAX
 MOV DWORD PTR [EBP+0],EAX
 MOV EAX,DWORD PTR [EDI+16]         ; EBX
 MOV DWORD PTR [EBP+4],EAX
 MOV EAX,DWORD PTR [EDI+24]         ; ECX
 MOV DWORD PTR [EBP+8],EAX
 MOV EAX,DWORD PTR [EDI+20]         ; EDX
 MOV DWORD PTR [EBP+12],EAX
 MOV EAX,DWORD PTR [EDI+4]          ; ESI
 MOV DWORD PTR [EBP+16],EAX
 MOV EAX,DWORD PTR [EDI+0]          ; EDI
 MOV DWORD PTR [EBP+20],EAX
 MOVZX EAX,WORD PTR [EDI+32]        ; the carry alone, the rest of Flags gone
 AND EAX,1
 MOV DWORD PTR [EBP+32],EAX
 JMP RTLSysIntrDone
RTLSysIntrRefused:
 MOV DWORD PTR [EBP+32],1           ; the interrupt did not run
RTLSysIntrDone:
 POP EBP
 POP EDI
 POP ESI
 POP EDX
 POP ECX
 POP EBX
 RET 8

; ---------------------------------------------------------------------------
; SysAlloc(size) -> the address of a block of that many bytes, or 0 when the
; host will not give one. SysFree gives the block back.
;
; Every block is a DPMI block of its own, asked for with 0501h and given back
; with 0502h. This is the primitive a program reaches for when it wants one
; block and wants it now: one interrupt, no bookkeeping anywhere, and the
; memory back in the machine's hands the moment it is given back. What it
; costs is an interrupt per block, which is why it is not what the library's
; GetMem is made of: a heap that allocates and frees in a loop would spend its
; time in the host, and one that allocates a record at a time would pay that
; price per record. The library's heap takes one large block from SysAllocMax
; below and splits it in Pascal instead. Both are here, and neither is written
; in terms of the other: a block of the one is not a block of the other, so a
; block from SysAlloc is not something the library's FreeMem can be handed.
;
; One integer of bookkeeping is unavoidable: 0502h frees by handle, and SysFree
; is given nothing but the address of the payload. The handle is therefore kept
; in the sixteen bytes in front of the payload and the payload starts at
; base+16 - aligned as well as the block is, since DPMI blocks are paragraph
; aligned, and every payload stays word aligned because the size asked for is
; rounded up to 16 first.
;
; Nothing is held back for the loader's sake, the way the boot block holds back
; RTLRESERVE: that reservation is about a program that loads modules while it
; runs, and a program whose allocations come from here need not. A request the
; host cannot meet answers 0, which the library reports as out of memory, and
; memory no program asks for is not taken from anyone.
;
; The DPMI returns come back in registers the generated code keeps live - the
; base in BX:CX and the handle in SI:DI, with ESI holding the function table -
; so the pushes at the top are what puts them back.
; ---------------------------------------------------------------------------
RTLSysAlloc:
 PUSH EBX
 PUSH ESI
 PUSH EDI
 MOV EAX,DWORD PTR [ESP+16]         ; the size asked for
 CMP EAX,0
 JLE RTLSysAllocFailed              ; nothing to hand out
 ADD EAX,15
 JC RTLSysAllocFailed               ; too large to round
 AND EAX,0FFFFFFF0H
 JZ RTLSysAllocFailed
 ADD EAX,16                         ; and room for the handle
 JC RTLSysAllocFailed
 MOV EBX,EAX
 SHR EBX,16                         ; BX:CX = the size, high:low
 MOV ECX,EAX
 AND ECX,0FFFFH
 MOV EAX,0501H
 CALL DPMICall                      ; the base comes back in BX:CX
 JC RTLSysAllocFailed
 MOV EDX,ESI                        ; the handle's high half
 MOV EAX,EBX
 SHL EAX,16
 MOV AX,CX                          ; EAX = the block's base
 MOV DWORD PTR [EAX],EDI            ; the handle, in the sixteen bytes SysFree
 MOV DWORD PTR [EAX+4],EDX          ; steps back over when it is given the block
 ADD EAX,16                         ; the payload is what a caller is given
 POP EDI
 POP ESI
 POP EBX
 RET 4
RTLSysAllocFailed:
 XOR EAX,EAX
 POP EDI
 POP ESI
 POP EBX
 RET 4

; SysFree(p) -> 0, or -1 when the host would not take the block back. A zero
; address is a pointer a program is not holding anything in - after a Dispose,
; or in a field it has not filled yet - so it is nothing to free and not a
; mistake.
RTLSysFree:
 PUSH EBX
 PUSH ESI
 PUSH EDI
 MOV EAX,DWORD PTR [ESP+16]
 TEST EAX,EAX
 JZ RTLSysFreeNothing
 MOV EDI,DWORD PTR [EAX-16]         ; the handle saved below the payload, which
 MOV ESI,DWORD PTR [EAX-12]         ; is what SysAlloc handed the caller
 MOV EAX,0502H
 CALL DPMICall                      ; SI:DI is the whole of what it wants
 JC RTLSysFreeFailed
 XOR EAX,EAX
 JMP RTLSysFreeDone
RTLSysFreeFailed:
 MOV EAX,-1
 JMP RTLSysFreeDone
RTLSysFreeNothing:
 XOR EAX,EAX
RTLSysFreeDone:
 POP EDI
 POP ESI
 POP EBX
 RET 4

; ---------------------------------------------------------------------------
; SysAllocMax(VAR Size) -> the address of the largest block the host will give,
; and the number of bytes in it written back over the caller's Size, or 0 with
; Size left as it was.
;
; This is where the library's heap comes from. One block, as large as the host
; will make it, taken once and never given back: what a heap needs is room to
; cut up, and a heap built out of a block that is itself out of the host's
; free list is a heap whose growth is a host call. The handle 0501h answers
; with is dropped rather than kept - a pool is not given back, so 0502h is
; never called on it, and there is nowhere a handle could be put that would
; not be a header in front of a block that has none. What the caller is given
; is the block's first byte.
;
; How much of the free memory is taken is the boot's question asked a second
; time, and it is answered the same way: everything, except that RTLRESERVE is
; left free when there is more than twice that much to take. The difference is
; the minimum: the boot will not run a program in less than RTLMINSIZE, and
; the library will cut up anything down to RTLHEAPMIN, because a small pool is
; a small heap and not a failure.
;
; The 0501h retry is the boot's too. 0500h answers with the largest block the
; host can find, and the host's own bookkeeping for the block it is about to
; create lives in that same memory, so asking for the whole of it can be a few
; paragraphs too many; asking for half of it, again and again, is what the
; boot does and what a heap got the first time round should do.
;
; The DPMI answers come back in registers the generated code keeps live - the
; function table is in ESI, and 0501h answers the handle in SI:DI - so ESI is
; kept in EBP across the calls and put back at the end.
; ---------------------------------------------------------------------------
RTLSysAllocMax:
 PUSH EBX
 PUSH ECX
 PUSH EDX
 PUSH ESI
 PUSH EDI
 PUSH EBP
 MOV EBP,ESI                        ; the function table, safe from the calls
 MOV EDI,EBP
 ADD EDI,RTLMemInfo-RTLBoot
 PUSH DS
 POP ES
 MOV EAX,0500H
 CALL DPMICall                      ; the host fills in the 48-byte record
 MOV EDI,EBP
 ADD EDI,RTLMemInfo-RTLBoot
 MOV ECX,DWORD PTR [EDI]            ; the largest block there is
 CMP ECX,RTLRESERVE*2
 JBE RTLSysAllocMaxNoReserve
 SUB ECX,RTLRESERVE
RTLSysAllocMaxNoReserve:
RTLSysAllocMaxAsk:
 CMP ECX,RTLHEAPMIN
 JB RTLSysAllocMaxFailed
 MOV DWORD PTR [EBP+RTLHeapAsk-RTLBoot],ECX
 MOV EBX,ECX
 SHR EBX,16                         ; BX:CX = the size, high:low
 MOV EAX,0501H
 CALL DPMICall                      ; the base comes back in BX:CX
 JNC RTLSysAllocMaxGot
 MOV ECX,DWORD PTR [EBP+RTLHeapAsk-RTLBoot]
 SHR ECX,1                          ; the host's bookkeeping moved: ask for half
 JNZ RTLSysAllocMaxAsk
 JMP RTLSysAllocMaxFailed
RTLSysAllocMaxGot:
 AND ECX,0FFFFH
 MOV EAX,EBX
 AND EAX,0FFFFH
 SHL EAX,16
 OR EAX,ECX                         ; EAX = the block's first byte
 MOV EDI,DWORD PTR [ESP+28]         ; the caller's Size, where the answer goes
 MOV EDX,DWORD PTR [EBP+RTLHeapAsk-RTLBoot]
 MOV DWORD PTR [EDI],EDX
 MOV ESI,EBP                        ; the function table, back in its register
 POP EBP
 POP EDI
 POP ESI
 POP EDX
 POP ECX
 POP EBX
 RET 4
RTLSysAllocMaxFailed:
 XOR EAX,EAX
 MOV ESI,EBP
 POP EBP
 POP EDI
 POP ESI
 POP EDX
 POP ECX
 POP EBX
 RET 4

; ---------------------------------------------------------------------------
; Fill(address, count, value) -> nothing: count bytes at address are set to
; the low byte of value.
;
; The write side of what a program does with memory that is not character
; data - a buffer about to be read into, a table about to be written over, a
; picture being built. It is here rather than in the library because the loop
; is one instruction: REP STOSB is what a byte fill is on this processor, and
; the same fill written as a Pascal loop around a store is slower by the
; factor a byte at a time is slower than a block at a time - which is the
; whole of what the library's own ZeroMem cost.
;
; A char is a four-byte cell here, so the value is taken as the byte the low
; cell of a char holds, which is what a byte of a string in memory is. A count
; of zero or less is nothing to do rather than a mistake.
;
; EDI is the register REP STOSB counts down and the one the generated code
; keeps its frame pointer in, so it is pushed and put back.
; ---------------------------------------------------------------------------
RTLSysFill:
 PUSH EDI
 MOV ECX,DWORD PTR [ESP+12]         ; the count
 TEST ECX,ECX
 JLE RTLSysFillDone
 MOV EDI,DWORD PTR [ESP+16]         ; the address
 MOV EAX,DWORD PTR [ESP+8]          ; the value
 CLD                                ; upwards, whatever the caller left set
 REP STOSB
RTLSysFillDone:
 POP EDI
 RET 12

; ---------------------------------------------------------------------------
; Move(source, dest, count) -> nothing: count bytes are copied from source to
; dest.
;
; Turbo Pascal's Move, and the same count in the same unit: bytes, not cells,
; because a copy is about memory rather than about the characters in it. The
; two may overlap, which is what makes it usable for shifting a buffer along
; itself: MOVSB copies upwards, so a destination above the source has to be
; copied from its end, and the pair of them is what the comparison below
; chooses between.
;
; ESI and EDI are the two registers MOVSB walks and are both live in the
; generated code, so both are pushed and put back.
; ---------------------------------------------------------------------------
RTLSysMove:
 PUSH ESI
 PUSH EDI
 MOV ECX,DWORD PTR [ESP+12]         ; the count
 TEST ECX,ECX
 JLE RTLSysMoveDone
 MOV ESI,DWORD PTR [ESP+20]         ; the source
 MOV EDI,DWORD PTR [ESP+16]         ; the destination
 CLD
 CMP EDI,ESI
 JBE RTLSysMoveUp                   ; below the source: upwards cannot spoil it
 MOV EAX,ESI
 ADD EAX,ECX                        ; inside the source and above it: the
 CMP EDI,EAX                        ; copy has to start at the far end
 JAE RTLSysMoveUp
 STD                                ; downwards, from the last byte of both
 LEA ESI,DWORD PTR [ESI+ECX-1]
 LEA EDI,DWORD PTR [EDI+ECX-1]
 REP MOVSB
 CLD
 JMP RTLSysMoveDone
RTLSysMoveUp:
 REP MOVSB
RTLSysMoveDone:
 POP EDI
 POP ESI
 RET 12

; ---------------------------------------------------------------------------
; Data. It shares the section with the code, which is why the section is mapped
; read/write/execute: the loader moves the section as one piece, so the blob's
; own addresses stay fixed relative to its start.
; ---------------------------------------------------------------------------
RTLCharBuffer:    TIMES 1 DB 0
RTLDecimalBuffer: TIMES RTLDECIMALSIZE DB 0
RTLNameBuffer:    TIMES RTLNAMESIZE DB 0
RTLBuffer:        TIMES RTLBUFFERSIZE DB 0
RTLParamBuffer:   TIMES RTLPARAMSIZE*RTLCHARSIZE DB 0

; FileOpen turns a mode into the two numbers AH=716Ch wants. Bit 0-1 of the
; mode is the access, and the action says whether the file has to be there:
; 1 opens an existing one, 12h creates it and truncates whatever was there.
RTLFileAccessTable:
 DD 0                               ; 0 read
 DD 1                               ; 1 write
 DD 2                               ; 2 read and write
 DD 2                               ; 3 read and write
RTLFileActionTable:
 DD 1                               ; 0 open an existing file
 DD 12H                             ; 1 create or truncate
 DD 1                               ; 2 open an existing file
 DD 12H                             ; 3 create or truncate

; And the same mode turned into the old 8.3 entry, AH=3Dh or AH=3Ch in the high
; half of the word. 3Dh takes its access in the low half of AL - 0 read, 2 read
; and write - and 3Ch has no access of its own: it always makes the file and
; always opens it for reading and writing, which is why the two modes that
; create share an entry.
RTLFileFallbackTable:
 DD 3D00H                           ; 0 open an existing file for reading
 DD 3C00H                           ; 1 create or truncate
 DD 3D02H                           ; 2 open an existing file for reading and
                                    ;   writing
 DD 3C00H                           ; 3 create or truncate
RTLInBuffer:      TIMES 4096 DB 0
RTLInPos:         DD 0
RTLInCount:       DD 0
RTLInChar:        DB 0
RTLInEOF:         DB 0
RTLInInited:      DB 0
RTLMemInfo:       TIMES 48 DB 0
RTLMemBase:       DD 0
RTLMemSize:       DD 0

; What SysAllocMax is asking 0501h for at the moment. The DPMI call is free to
; clobber every register, so the size has to survive it somewhere, and the
; retry at half of it is what reads it back.
RTLHeapAsk:       DD 0

; The real mode register structure Intr fills in for 0300h, and the segment of
; the DOS memory it runs the interrupt on. Both are zero until the first Intr
; call, which is what asks for the stack; the structure is rewritten from
; scratch on every call and never read before it is written.
RTLIntrRMCS:      TIMES 50 DB 0
RTLIntrStackSeg:  DD 0
RTLIntrStrategy:  DD 0

; The functions' offsets relative to the blob. The boot code adds its own
; address to each, which is what keeps the blob free of absolute addresses.
RTLRelTable:
 DD RTLHalt-RTLBoot
 DD RTLWriteChar-RTLBoot
 DD RTLWriteInteger-RTLBoot
 DD RTLWriteLn-RTLBoot
 DD RTLReadChar-RTLBoot
 DD RTLReadInteger-RTLBoot
 DD RTLReadLn-RTLBoot
 DD RTLEOF-RTLBoot
 DD RTLEOLN-RTLBoot
 DD RTLFileOpen-RTLBoot
 DD RTLFileRead-RTLBoot
 DD RTLFileWrite-RTLBoot
 DD RTLFileSeek-RTLBoot
 DD RTLFileClose-RTLBoot
 DD RTLFileSize-RTLBoot
 DD RTLSysParams-RTLBoot
 DD RTLSysIntr-RTLBoot
 DD RTLSysAlloc-RTLBoot
 DD RTLSysFree-RTLBoot
 DD RTLSysAllocMax-RTLBoot
 DD RTLSysFill-RTLBoot
 DD RTLSysMove-RTLBoot
RTLFunctionTable: TIMES RTLFUNCTIONCOUNT*4 DB 0

; ---------------------------------------------------------------------------
; Boot. Entered through the jump at offset 0. It runs on the loader's stack and
; falls through into the generated program code.
;
; EBP carries the blob's address for the whole of the boot and becomes the
; frame pointer only at the very end, so a DPMI call - which is free to clobber
; EAX, EBX, ECX, EDX, ESI and EDI - cannot cost us the anchor.
; ---------------------------------------------------------------------------
RTLBoot:
 CALL RTLBootHere
RTLBootHere:
 POP EBP
 SUB EBP,RTLBootHere-RTLBoot        ; EBP = address of the blob
 ; Build the function table from the relative offsets.
 MOV ESI,EBP
 ADD ESI,RTLFunctionTable-RTLBoot
 MOV EDI,EBP
 ADD EDI,RTLRelTable-RTLBoot
 MOV ECX,RTLFUNCTIONCOUNT
RTLBootBuildTable:
 MOV EAX,DWORD PTR [EDI]
 ADD EAX,EBP
 MOV DWORD PTR [ESI],EAX
 ADD EDI,4
 ADD ESI,4
 DEC ECX
 JNZ RTLBootBuildTable
 ; Ask the host for the memory the frame and the expression stack live in.
 MOV EDI,EBP
 ADD EDI,RTLMemInfo-RTLBoot
 PUSH DS
 POP ES
 MOV EAX,0500H
 CALL DPMICall
 MOV EDI,EBP
 ADD EDI,RTLMemInfo-RTLBoot
 MOV ECX,DWORD PTR [EDI]
 CMP ECX,RTLRESERVE*2
 JBE RTLBootNoReserve
 SUB ECX,RTLRESERVE
RTLBootNoReserve:
 CMP ECX,RTLMINSIZE
 JB RTLBootNoMemory
 MOV DWORD PTR [EBP+RTLMemSize-RTLBoot],ECX
 MOV EBX,ECX
 SHR EBX,16                         ; BX:CX = size, high:low
 MOV EAX,0501H
 CALL DPMICall                      ; base comes back in BX:CX
 JNC RTLBootAllocated
 MOV ECX,DWORD PTR [EBP+RTLMemSize-RTLBoot]
 SHR ECX,1                          ; the host's bookkeeping moved: ask for half
 JNZ RTLBootNoReserve
 JMP RTLBootNoMemory
RTLBootAllocated:
 AND ECX,0FFFFH
 MOV EAX,EBX
 AND EAX,0FFFFH
 SHL EAX,16
 OR EAX,ECX                         ; EAX = linear base of the block
 MOV DWORD PTR [EBP+RTLMemBase-RTLBoot],EAX
 MOV EDX,DWORD PTR [EBP+RTLMemSize-RTLBoot]
 ADD EDX,EAX
 SUB EDX,4                          ; EDX = the frame's top, see below
 MOV ESI,EBP
 ADD ESI,RTLFunctionTable-RTLBoot
 ; EBP is the frame's top and the whole frame grows down from it: globals at
 ; EBP-4, EBP-8 and so on, the expression stack below those. It is four bytes
 ; short of the block's end because the generated code's first instruction at
 ; the outer level is ADD ESP,4 - the outer block counts a return address it
 ; was never given - so ESP is at EBP+4 before the first push, and that push
 ; lands on EBP itself. Pointing EBP at the very end of the block, as the
 ; Win32 stub did, only worked because the memory above a Windows heap block
 ; happens to be mapped; here it is a page fault on the first push.
 MOV ESP,EDX
 MOV EBP,EDX
 JMP RTLProgramEntry

; Reached only when the host will not give us a block worth running in, so this
; cannot rely on ESI: the failed 0501h left it holding the memory handle. EBP
; still holds the blob's address.
RTLBootNoMemory:
 MOV EDX,EBP
 ADD EDX,RTLMessageNoMemory-RTLBoot
 MOV ECX,RTLMessageNoMemoryEnd-RTLMessageNoMemory
 MOV EBX,2                          ; stderr
 MOV AH,40H
 INT 21H
 MOV AX,4C01H
 INT 21H

RTLMessageNoMemory: DB 13,10,78,111,116,32,101,110,111,117,103,104,32,109,101,109,111,114,121,32,116,111,32,114,117,110,32,116,104,105,115,32,112,114,111,103,114,97,109,46,13,10
RTLMessageNoMemoryEnd:

; The last label of the blob: the generated program code is appended here, and
; the jump above is the only way into it, so the boot cannot fall through into
; the message by accident.
RTLProgramEntry:
