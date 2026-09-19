@echo off
rem make.bat - rebuild the compiler kept here from the sources kept here.
rem
rem This directory is a snapshot: the compiler, the sources it was compiled
rem from, the tools those sources are built with, and the assembler. Nothing
rem outside it is read, so it keeps working when the rest of the tree has
rem moved on. Rebuilding it from those sources is what says the snapshot holds
rem together, and it is also the way back: a snapshot that cannot rebuild
rem itself is not a version to fall back to.
rem
rem The chain starts from a copy of the compiler that is already here, so the
rem two comparisons at the end are the strongest ones this build has. The
rem first says the code generation does not depend on which compiler ran; the
rem second says the source here and the compiler here are the same version. A
rem compiler that is newer than its source, or older, fails the second, and
rem that is the one thing to look at when it does. The compiler here is
rem replaced only after both have passed.
rem
rem The build is the same as the one in ..\src, written out in full rather
rem than called. Paths are relative and the shell features are DOS's; the
rem images are HX-DOS programs and need a running DOS or Windows.
rem
rem egasm is a Windows program: under DOS it stops with "This program must be
rem run under Win32" and writes nothing. The blob is a product of hxrtl.asm
rem and is kept here as well, so the build goes on with the blob already here
rem and says so. That one case has to be handled under Windows.
rem
rem FIX.TXT holds what the byte comparisons said. It is deleted when they both
rem passed, and left where it is when one did not, which is the one case it is
rem there to be read in.

if not exist btpc.pas goto nosource
if not exist mkhx.pas goto nosource
if not exist mkbase.pas goto nosource
if not exist BTCPC.EXE goto noseed
if not exist egasm.exe goto noseed
if not exist emptycode.bin copy nul emptycode.bin > nul
copy BTCPC.EXE seed.exe > nul
if not exist seed.exe goto noseed

echo === the blob ===
if exist hxrtl.bin ren hxrtl.bin hxrtl.old
egasm.exe hxrtl.asm hxrtl.bin +BIN > nul
if exist hxrtl.bin goto blob
if not exist hxrtl.old goto failed
ren hxrtl.old hxrtl.bin
echo NOTE: hxrtl.bin was not rebuilt and the one already here is used. Under
echo DOS this is expected: egasm is a Windows program. Anywhere else it means
echo the assembly of hxrtl.asm failed and has to be looked at.
:blob
if exist hxrtl.old del hxrtl.old

echo === the tools ===
if exist mkhx.EXE del mkhx.EXE
seed.exe mkhx.pas
if not exist mkhx.EXE goto failed
if exist mkbase.EXE del mkbase.EXE
seed.exe mkbase.pas
if not exist mkbase.EXE goto failed

echo === the image the compiler carries ===
if exist check.exe del check.exe
mkhx.EXE hxstub.bin hxrtl.bin emptycode.bin check.exe --base hxbase.bin
if not exist check.exe goto failed
if not exist hxbase.bin goto failed
mkbase.EXE hxbase.bin btpc.pas
if not exist btpc.pas goto failed

echo === the chain ===
del gen3.exe
seed.exe < btpc.pas > gen3.exe
if not exist gen3.exe goto failed
find "MZ" < gen3.exe > nul
if errorlevel 1 goto failed
if exist btpc.new del btpc.new
gen3.exe < btpc.pas > btpc.new
if not exist btpc.new goto failed
find "MZ" < btpc.new > nul
if errorlevel 1 goto failed

echo === the snapshot ===
del fix.txt
fc /b gen3.exe btpc.new > fix.txt
if errorlevel 1 goto notfixed
fc /b seed.exe btpc.new >> fix.txt
if errorlevel 1 goto notsame
del BTCPC.EXE
ren btpc.new BTCPC.EXE
if not exist BTCPC.EXE goto failed
if exist gen3.exe del gen3.exe
if exist seed.exe del seed.exe
if exist mkhx.EXE del mkhx.EXE
if exist mkbase.EXE del mkbase.EXE
if exist check.exe del check.exe
if exist fix.txt del fix.txt
echo SNAPSHOT OK - the compiler here rebuilt itself from the sources here
goto done

:notfixed
echo GEN3.EXE AND THE COMPILER BUILT FROM IT ARE NOT THE SAME BYTES
goto done

:notsame
echo THE COMPILER KEPT HERE WAS NOT BUILT FROM THE SOURCE KEPT HERE
goto done

:nosource
echo NO BTCPC.PAS, MKHX.PAS OR MKBASE.PAS IN THIS DIRECTORY
goto done

:noseed
echo NO BTCPC.EXE OR EGASM.EXE IN THIS DIRECTORY
goto done

:failed
echo BUILD FAILED
:done
exit
