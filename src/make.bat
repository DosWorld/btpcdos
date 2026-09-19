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
rem   BTCPC.EXE   the compiler. It is built again and again, each image by the
rem               one before it, until two of those images are the same bytes.
rem               The source is the same for all of them, so a difference
rem               between two of them means the code generation depended on
rem               which compiler ran and not on the source. The last image is
rem               the verified one; it replaces the one in ..\boot once the
rem               samples have been run (see README).
rem
rem Why two images are not always enough, and the third is built only when
rem they are not. A compiler does not read the base out of its source - it
rem writes the base it carries, the one it was built with, from its own
rem EmitStubCode. So the first image a seed with an older base produces
rem carries that older base and nothing in the source can change that. It is
rem a compiler in every other way: it runs, and what it writes carries the
rem base from the source, because its own EmitStubCode is the one the source
rem has. So a change to hxrtl.bin makes exactly the first pair of images
rem differ, and the image after that pair is the settled one. Without such a
rem change the first two images are already equal and the third is not built.
rem
rem The compiler names its image after the source, so compiling btpc.pas would
rem write btpc.EXE and the generation after it would write over it. Each image
rem is therefore named on the command line with -o, which is also what leaves
rem the two compilations differing in nothing but which compiler ran them: the
rem source is the same file under the same name both times. The verified image
rem is moved over the old compiler only once it has been compared, so a build
rem that fails leaves the compiler that was there.
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
if exist btpc.new del btpc.new
if exist gen1.exe del gen1.exe
..\boot\BTCPC.EXE -o gen1.exe btpc.pas
if not exist gen1.exe goto failed
if exist gen2.exe del gen2.exe
gen1.exe -o gen2.exe btpc.pas
if not exist gen2.exe goto failed

echo === the fixpoint ===
if exist fix.txt del fix.txt
fc /b gen1.exe gen2.exe > fix.txt
if not errorlevel 1 goto settled2

echo THE FIRST TWO IMAGES ARE NOT THE SAME BYTES - the seed carries an older
echo base than the source does, which is what a change to hxrtl.asm does. The
echo next image is built by a compiler whose own base is the current one.
if exist gen3.exe del gen3.exe
gen2.exe -o gen3.exe btpc.pas
if not exist gen3.exe goto failed
if exist fix.txt del fix.txt
fc /b gen2.exe gen3.exe > fix.txt
if errorlevel 1 goto notfixed
if exist gen1.exe del gen1.exe
if exist gen2.exe del gen2.exe
ren gen3.exe btpc.new
goto promote

:settled2
if exist gen1.exe del gen1.exe
ren gen2.exe btpc.new

:promote
del BTCPC.EXE
ren btpc.new BTCPC.EXE
if not exist BTCPC.EXE goto failed
echo BUILD OK - the last two images built are the same bytes
if exist gen1.exe del gen1.exe
if exist gen2.exe del gen2.exe
if exist gen3.exe del gen3.exe
if exist fix.txt del fix.txt
goto done

:notfixed
echo THE LAST TWO IMAGES BUILT ARE NOT THE SAME BYTES, AND A BASE THAT MOVED
echo DOES NOT EXPLAIN IT. FIX.TXT HOLDS WHAT DIFFERS.
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
