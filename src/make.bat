@echo off
rem make.bat - build BTCPC.EXE from the sources in this directory.
rem
rem Run it with this directory as the current one. Every path in it is
rem relative and it uses nothing that DOS and a Windows command prompt do not
rem both have, so the same file serves both shells.
rem
rem What is built, in the order it has to be built:
rem
rem   hxrtl.bin   the runtime blob, assembled by ..\boot\egasm.exe from
rem               hxrtl.asm. Every image this compiler writes carries that
rem               blob, so it has to be the one the sources expect.
rem   the tools   ..\tools\mkhx.pas and ..\tools\mkbase.pas, compiled by the
rem               compiler kept in ..\boot. mkhx puts an image's headers
rem               together with the blob and writes out the part of that image
rem               the compiler carries, hxbase.bin; mkbase writes that part
rem               into btpc.pas, between the markers it finds there, and sets
rem               HXBaseSize to its length. A change to a tool alone does not
rem               need the compiler rebuilt; a change to hxrtl.asm or to
rem               btpc.pas itself does.
rem   BTCPC.EXE   the compiler. It is built twice: once by the compiler kept
rem               in ..\boot, and once by what that first build produced. The
rem               two images are then compared, and the build is good only if
rem               they are the same bytes - the source is the same, so a
rem               difference means the code generation depended on which
rem               compiler ran and not on the source. The compiler left behind
rem               here is the verified one; it replaces the one in ..\boot once
rem               the samples have been run (see README).
rem
rem The compiler names its output after the source, so btpc.pas would be built
rem into btpc.EXE. Both images are therefore written through the redirect,
rem under names this batch gives them, and the new compiler is built beside
rem the old one and moved over it only once it has been compared. That also
rem keeps the names the same whatever case the source file is spelled in,
rem which matters where a name is looked up in the host's own filesystem.
rem
rem egasm is a Windows program: under DOS it stops with "This program must be
rem run under Win32" and writes nothing. The blob is a product of hxrtl.asm and
rem is kept here as well, so the build goes on with the blob already here and
rem says so. That one case has to be handled under Windows.
rem
rem CHECK.EXE is left behind: it is the image mkhx assembles before any program
rem is put in it, and it is the only way to see the layout. It is not a
rem program and is not to be run.
rem
rem FIX.TXT holds what the byte comparison said. It is deleted when the
rem comparison passed, and left where it is when it did not, which is the one
rem case it is there to be read in.

if not exist btpc.pas goto nosource
if not exist ..\boot\BTCPC.EXE goto noseed
if not exist ..\boot\egasm.exe goto noseed
if not exist ..\tools\mkhx.pas goto notools
if not exist ..\tools\mkbase.pas goto notools
if not exist emptycode.bin copy nul emptycode.bin > nul

echo === the blob ===
if exist hxrtl.bin ren hxrtl.bin hxrtl.old
..\boot\egasm.exe hxrtl.asm hxrtl.bin +BIN > nul
if exist hxrtl.bin goto blob
if not exist hxrtl.old goto failed
ren hxrtl.old hxrtl.bin
echo NOTE: hxrtl.bin was not rebuilt and the one already here is used. Under
echo DOS this is expected: egasm is a Windows program. Anywhere else it means
echo the assembly of hxrtl.asm failed and has to be looked at.
:blob
if exist hxrtl.old del hxrtl.old

echo === the tools ===
if exist ..\tools\mkhx.EXE del ..\tools\mkhx.EXE
..\boot\BTCPC.EXE ..\tools\mkhx.pas
if not exist ..\tools\mkhx.EXE goto failed
if exist ..\tools\mkbase.EXE del ..\tools\mkbase.EXE
..\boot\BTCPC.EXE ..\tools\mkbase.pas
if not exist ..\tools\mkbase.EXE goto failed

echo === the image the compiler carries ===
if exist check.exe del check.exe
..\tools\mkhx.EXE hxstub.bin hxrtl.bin emptycode.bin check.exe --base hxbase.bin
if not exist check.exe goto failed
if not exist hxbase.bin goto failed
..\tools\mkbase.EXE hxbase.bin btpc.pas
if not exist btpc.pas goto failed

echo === the chain ===
del gen3.exe
..\boot\BTCPC.EXE < btpc.pas > gen3.exe
if not exist gen3.exe goto failed
find "MZ" < gen3.exe > nul
if errorlevel 1 goto failed
if exist btpc.new del btpc.new
gen3.exe < btpc.pas > btpc.new
if not exist btpc.new goto failed
find "MZ" < btpc.new > nul
if errorlevel 1 goto failed

echo === the fixpoint ===
del fix.txt
fc /b gen3.exe btpc.new > fix.txt
if errorlevel 1 goto notfixed
del BTCPC.EXE
ren btpc.new BTCPC.EXE
if not exist BTCPC.EXE goto failed
echo BUILD OK - gen3.exe and BTCPC.EXE are the same bytes
if exist gen3.exe del gen3.exe
if exist fix.txt del fix.txt
goto done

:notfixed
echo GEN3.EXE AND THE COMPILER BUILT FROM IT ARE NOT THE SAME BYTES
goto done

:nosource
echo NO BTCPC.PAS IN THIS DIRECTORY
goto done

:noseed
echo NO COMPILER OR ASSEMBLER IN ..\BOOT
goto done

:notools
echo NO TOOLS IN ..\TOOLS
goto done

:failed
echo BUILD FAILED
:done
exit
