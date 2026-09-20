# BeRoTinyPascal for DOS

BeRoTinyPascal is Benjamin Rosseaux's small self-hosting Pascal compiler. This
directory is a port of it to **DOS/DPMI32**: 32-bit protected mode DOS, as the HX-DOS
extender and HDPMI32 present it. The compiler still compiles itself, and the
same source compiled twice comes out byte-identical.

Upstream emits Win32 PE images and reads its source from the input stream. Here
the image is an PE-DOS executable, the source is named on the command line and
nowhere else, and the language has the few additions the port needed. This file is how to
build it, how to run it, and what it costs to run: the compiler's tables are no
longer part of its image, and how large they may be is a decision the source
records.

The build is a bootstrap chain, not a makefile, and the samples are run under
DOSBox-X, so the whole of it is a batch file and the commands it runs.

## What is in the tree

| Path | What it is |
|---|---|
| `boot/BTCPC.EXE` | the verified compiler: the seed every build starts from |
| `boot/btpc.pas` | the source that compiler was built from |
| `boot/mkhx.pas`, `boot/mkbase.pas` | the tools, as that build used them |
| `boot/egasm.exe` | the assembler that turns `hxrtl.asm` into the blob |
| `boot/hxrtl.asm`, `hxrtl.bin`, `hxstub.bin`, `hxbase.bin`, `emptycode.bin` | the runtime, and the parts an image is put together from |
| `boot/rtldos.pas` | the library, so that the snapshot is a compiler that can be used as it stands |
| `boot/make.bat` | rebuilds that snapshot from those files, and checks it against itself |
| `src/btpc.pas` | the compiler source being worked on |
| `src/hxrtl.asm` | the HX-DOS runtime: the host primitives the compiler is built on, and the DOS and DPMI calls the library needs |
| `src/hxstub.bin`, `src/hxrtl.bin`, `src/emptycode.bin` | the 512-byte DPMIST32 stub that is prepended to every image, the blob as assembled, and the empty code file `mkhx` is given |
| `src/hxbase.bin` | the runtime blob in image form - 1024 bytes of headers and 12353 of blob - embedded in the compiler as the literal `HXBaseSize` counts |
| `src/rtldos.pas` | the Pascal runtime library: DOS, strings, the command line, files, memory. The compiler reads it itself, before the program's first line |
| `src/make.bat` | builds `src/BTCPC.EXE` from what is in `src` and `../tools` |
| `tools/mkhx.pas`, `tools/mkbase.pas` | image assembly, and splicing the blob into the source |
| `examples/` | one sample per feature, and one that walks the whole library |
| `B1.BAT`, `B2.BAT` | the DOS-side batches that build and run the samples |

`boot` is a snapshot and `src` is where the work is. While the tree is clean the
two hold the same sources file for file, and the compiler in `boot` is what they
build. `src` keeps no compiler of its own: the one it builds is that build's
product and is not the tree's, and `boot` is the directory a build falls back
to. The rule that keeps the two together is in **Building** below: a version
goes into `boot` only after the samples have passed, and what goes in is the
compiler together with every source it was built from, so that the directory can
rebuild itself and be fallen back to without the rest of the tree.

## Building

`src/make.bat` builds the compiler, and it is run with `src` as the current
directory. Every path in it is relative and it uses nothing that DOS and the
Windows command prompt do not both have, so the same file serves both shells.
The programs it starts are PE-DOS images, though, and those run under DOS -
under Windows the first one crashes - so DOS is where the build is done. There
is no compiler on the Windows side to start it with: the port's compiler is an
PE-DOS program.

What the batch does, in the order it has to be done:

**1. the blob.** `..\boot\egasm.exe` assembles `hxrtl.asm` into `hxrtl.bin` -
the runtime blob every image this compiler writes carries. `egasm` is a
Windows program and under DOS it stops with `This program must be run under
Win32` and writes nothing, so the batch keeps the blob that is already in the
tree, goes on with it and says so. That is the one step that has to be done
elsewhere, and only when `hxrtl.asm` has changed: the blob is kept in the tree
as well as the source it comes from.

**2. the tools.** `tools/mkhx.pas` and `tools/mkbase.pas` are compiled by the
compiler kept in `..\boot`. `mkhx` puts an image's headers together with the
blob and writes out the part of that image the compiler carries, `hxbase.bin`;
`mkbase` writes that part into `btpc.pas`, between the markers it finds there,
and sets `HXBaseSize` to its length. A change to a tool alone does not need the
compiler rebuilt; a change to `hxrtl.asm`, or to `btpc.pas` itself, does.
`mkhx` also writes `check.exe`, the whole image with no program in it - the
headers and the runtime blob, which is what every other image starts with, and
what the layout of the header fields can be inspected against. It is left
behind on purpose and is not a program: the blob's entry falls through into the
code that is not there, and the fault that follows takes the DOS session with
it.

**3. the chain.** The compiler is built from the seed, then from itself, and the
two images are compared:

```
..\boot\BTCPC.EXE -o gen1.exe btpc.pas
gen1.exe -o gen2.exe btpc.pas
fc /b gen1.exe gen2.exe
```

Both compilations read the same file under the same name and differ in nothing
but which compiler ran them, which is what makes the comparison mean what it
says. `-o` is there because a compiler names its image after its source:
without it `btpc.pas` would come out as `btpc.EXE` and the second generation
would write over the first, and only the last image of the chain is kept.

The two compile the same source with two compilers, so the images must be the
same bytes, **120832** of them: that is the fixpoint, and a difference means
the code generation depended on which compiler ran rather than on the source.
The new compiler is moved over `src\BTCPC.EXE` only once they agree, so a build
that fails leaves the compiler that was there. What the comparison said is
written to `fix.txt`, which is deleted when it passed: a `fix.txt` in the tree
is a build that stopped and a file that is there to be read.

When those two differ, one more image is built from `gen2.exe` and compared
with it, and **that** pair is the fixpoint. The case that needs it is a change
to `hxrtl.asm`, and the reason is worth knowing:

- **A compiler writes the base it carries, not the base in its source.** The
  base is written by `EmitStubCode`, which is code in the compiler, so the
  image a compiler writes carries the runtime blob that compiler was *built*
  with. The literal between the markers in `btpc.pas` decides what a compiler
  built from that source will carry - it does not reach the image any other
  way.
- So the first image a seed with an older blob produces carries that older
  blob, and no source change can prevent it. It is a compiler in every other
  way: it runs, and its `EmitStubCode` is the one the source has, so what *it*
  writes carries the blob the source has. The generation after it is the one
  that is both.
- That is why the chain is run until two images agree rather than exactly
  twice, and why the third image is built only when the first two differ.
  Without a change to `hxrtl.asm` they do not, and the build is the two
  compilations above.

**`boot` is updated only after the whole verification, and it is updated as a
set.** What goes in is the compiler that passed, `src\BTCPC.EXE`, and every
source it was built from: `btpc.pas`, `hxrtl.asm`, `hxrtl.bin`, `hxstub.bin`,
`hxbase.bin`, `emptycode.bin`, `rtldos.pas`, `mkhx.pas` and `mkbase.pas`. A
compiler newer than the source beside it, or older, is the one state that is
not allowed there, and `boot\make.bat` is what says so: it rebuilds the
snapshot from what the directory holds and compares the result with the
compiler already in it. `SNAPSHOT OK` is two comparisons, both `No differences`
- the compiler rebuilding itself from the source beside it, and the compiler
that came out being the one the directory holds.

A full self-host under DOSBox-X is minutes, not seconds, and there is no
shorter way round it.

## Running under DOSBox-X

The DOS side is driven by batches so that one launch does all of it. The tree
they expect is `C:\BTPC`, which is this directory copied into the DOS drive:
`SRC`, `BOOT`, `TOOLS` and `EXAMPLES`, with this directory's `examples` in the
last of them. The library `RTLDOS.PAS` stands beside the compiler, which is the
second place the compiler looks for it, and the samples are in `EXAMPLES\`.

```
cd C:\DOSBox-X
timeout 500 ./dosbox-x.exe -conf dosbox-x.conf -c "mount c C:\dos\c" -c "c:" -c "call C:\BTPC\SRC\MAKE.BAT"
```

| Batch | What it does |
|---|---|
| `SRC\MAKE.BAT` | builds `SRC\BTCPC.EXE`: the blob, the tools, then the chain of images and the comparison that ends it |
| `BOOT\MAKE.BAT` | rebuilds the snapshot in `BOOT` from the sources in `BOOT`, and checks it against the compiler kept there |
| `B1.BAT` | builds and runs `libtest`, then the three memory samples |
| `B2.BAT` | builds and runs `hello`, `files`, `inline` and `intrtest` |

Rules that are not obvious and that a batch has to obey:

- One `-c "CALL ..."` per launch. The batch ends in `exit`, and `exit` closes
  the emulator, so a second one never runs. The mount goes in `-c` as well, and
  `-c` runs before `[autoexec]`, so the `c:` has to be there before the `call`.
- The batch is named by its full path and starts with an explicit `cd`, because
  the batch runs in whatever directory the emulator starts in.
- **A name in `if exist` is matched the way the filesystem under it matches
  names, and the two cases do not behave the same.** On a mounted host
  directory, DOSBox-X resolves a name case-insensitively for the files DOS
  itself wrote there, but matches the host's own spelling for a file that was
  copied in from the host. `if not exist BTCPC.PAS` therefore fails for a host
  file named `btpc.pas`, while `if exist case.exe` finds a `CASE.EXE` that DOS
  wrote. Spell a name that came from the host the way the host spells it, or
  keep the build from having to test it - which is why every image in the chain
  is named by the batch with `-o` rather than derived by the compiler from the
  name of the source, and why the batches name their sources in lower case.
- A failed compile does not stop the lines after it, so every output is deleted
  before the compile that writes it and every program is only run if its file
  exists. Otherwise error text would be executed as a program, or a stale image
  from an earlier run would be taken for a success. For the same reason, when
  reading a result, read the `.lst` the compiler wrote - it says whether the
  compile happened at all.
- Programs to be run are named in 8.3 form. This is the loader's rule, not the
  compiler's: a compiled program asks DOS for its files by their long names
  first and falls back to the 8.3 entry when there is nothing there to answer
  (see **Long file names**), so the *files* may have long names even though the
  *program* may not.

Two lines in the DOSBox-X log are normal for every HX client, these samples and
the shipped Oberon ones alike: `ERROR EXEC:stack underflow` and
`ERROR CPU:Illegal Unhandled Interrupt Called 68`.

## Using the compiler

```
BTCPC PROG.PAS
```

One argument, the source file. The image is written beside the source under the
same name with `.EXE` for an extension - `BTCPC SUB\PROG.PAS` writes
`SUB\PROG.EXE` - and the compiler says what it wrote:

```
Wrote PROG.EXE (19456 bytes)
```

`-o` names the image instead, and then it is written where that name says and
nowhere else:

```
BTCPC -o BAR.EXE FOO.PAS
```

writes `BAR.EXE` and leaves `FOO.EXE` alone. The name is taken as written, so
`-o BAR.BIN` writes `BAR.BIN`. The flag may stand anywhere among the arguments,
before or after the source, and a second `-o` replaces the first. An argument that is exactly `-o`
is the flag and every other argument is a name, so nothing here needs escaping:
a name that begins with a dash is an ordinary name, because the whole argument
has to match. Two names, a `-o` with no name after it, or no source at all, are
not a compilation - the compiler writes `Usage: BTCPC [-o image.exe] file.pas`
and stops.

**The source is a file and there is no other way in.** A compiler that read its
source from the input stream would be waiting on that stream the moment the
name it was given was not the file it wanted - a name that is not there, a
directory it cannot search - and a build that waits looks exactly like a build
that is slow. Nothing in a build can tell the two apart, which is reason enough
for the compiler to have one input and for that input to be a file it opens
itself, with a name that is in the command line it was called with.

A compilation that fails writes its diagnostic and stops, so a half-written
image is not something that can be left behind. `read`, `readln` and `eof` are
still part of the language and still in the runtime; what the compiler does not
have is a mode that reads a program from them.

## What the compiler costs

The compiler keeps three tables - the code it emits, the identifiers it has
met, the types it has built - and none of them is carried in its image.
`PrepareTables` asks the host for the code and identifier tables when a
compilation starts, so a run costs what the program it is compiling needs
rather than what the largest program it could ever be given would need:

| Limit | Value | What it is |
|---|---|---|
| `MaximalCodeSize` | 262144 | a megabyte of code |
| `MaximalIdentifiers` | 16384 | two megabytes of identifiers |
| `MaximalTypes` | 512 | twelve kilobytes of types |

The type table is small enough to stay in the frame and is only cleared there.
What stays with it is the assembler's jump table, a megabyte itself, for a
reason that is easy to get backwards: the frame is the largest block the host
has and is tens of megabytes, while the memory free above it - which is where
a block of a megabyte comes from - is the few megabytes the boot kept back.
Three megabytes of tables is what that pays for, and there is no more room
there to spend.

Two things about this are not obvious, and both are load-bearing:

- **The tables are asked for zeroed.** The compiler reads a type or identifier
  entry before it has written one there - the kind of a variable it has not
  reached the declaration of is read as `KindSIMPLE` - and under Windows the
  loader had already made every global zero, so leaving an entry alone was the
  same as writing zero in it. HX-DOS promises nothing about what a block holds:
  the tables a program has just been compiled into are still in the memory the
  next compilation is handed. Without the zeroing, the same compiler on the
  same source fails or succeeds depending on what ran before it.

- **The compiler's own source must fit in its own type table.** A type is an
  entry in the table `MaximalTypes` counts, and a shape written out where it is
  used costs an entry every time it is written, so a source that names a shape
  it uses more than once pays for that shape once. The compiler has to fit its
  own source in its own table to be able to build itself, and 512 entries is
  that table with room to spare. The names the source gives to the shapes it
  repeats - `TSourceLevelValues`, `TSourceFileName`, `TString255` - date from
  when the seed had 32 entries and the source spent all 32 of them, and are kept
  as the convention they became; `Error 134: Too many types` is what a
  compilation that writes out one shape too many reports.

## What the language has

Beyond upstream BeRoTinyPascal:

- **`{$I filename}`** - an include, anywhere a comment may go. The name is
  everything up to the closing brace, so a note written after the name on the
  same line is read as part of it; `.pas` is appended when the name has no
  extension; and the file is looked for beside the file that names it before it
  is looked for where it was written. One name is not an include at all: the
  library's, which the compiler has already read (see below).
- **`inline($xx, ...)`** - the bytes, written where the statement is.
- **Hex literals** - `$1F`, in expressions and in `inline`.
- **`shl` and `shr`** - a shift by a bit count, as Turbo Pascal has them, which
  is where the port took them from. They have the precedence of `*`, `div`,
  `mod` and `/`, so they bind tighter than `+`: `1 + 1 shl 3` is 9. The count is
  taken modulo 32, which is what the machine does with it - `1 shl 32` is 1 -
  and `shr` is logical, so the bit shifted in is a zero: `-1 shr 1` is
  2147483647. Written after a sign, the sign belongs to the whole term, the way
  it does before `*`: `-1 shl 3` is -8 and `-256 shr 4` is -16.
- **`Registers` and `Intr(i, r)`** - an interrupt run with the registers in a
  record. The host runs it through DPMI's emulation of a real mode interrupt,
  `int 31h AX=0300h`, so the call goes to real mode and back; the record's
  `Flags` field carries the interrupt's carry in and out, which is how a DOS
  call reports failure. The real mode stack the call runs on is a kilobyte the
  runtime asks DOS for on the first `Intr` and keeps, and the arena is asked
  for it with the allocation strategy set to low memory and put back
  afterwards: the loader's last-fit-high hands out the top of the arena, which
  is the ROM window, where the write that fills the stack is dropped and the
  interrupt then runs on a stack that was never written.
- **`new`/`dispose`, `GetMem`/`FreeMem`, `GetMemZeroed`** - a heap over DPMI
  memory, in the library, on top of the `SysAlloc`/`SysFree` primitives:
  `New` and `Dispose` are compiled into calls to the library's `GetMem`,
  `FreeMem` and `RtlFreeBlock`, looked up in the image by name. `GetMemZeroed`
  is `GetMem` with zero written over the block before the address is answered,
  and `FillChar` and `Move` - the runtime's own, in assembler - are what
  writing over a block and copying one are written with.
- **The command line** - a source file, and `-o` when the image is to be
  written under another name, as above.

There are no DLLs (item 9 of the requirements, and no support is planned), no
units, no `string` type, no sets, no floating point, and no output target other
than PE-DOS.

## Writing an `inline` block

Two rules, and the first one is a crash if it is broken:

- **The block must leave the machine stack as it found it.** The code generator
  keeps its variables on the frame pointer, but the expression stack has to be
  where the compiler left it. Push and pop in pairs.
- **The target is 32-bit flat.** A segment register holds a selector, not a
  paragraph, so the real mode idiom for the text screen - `mov ax,0B800h`,
  `mov es,ax`, `mov [es:di],ax` - loads a selector and faults. The flat address
  is `0B8000h`, and it goes in a general register: `mov edi,0B8000h`,
  `mov [edi],ax`.

`examples/inline.pas` is both rules written out and checked.

## The runtime library

`src/rtldos.pas` is the library. It is not named by the program and not linked
by the compiler: the compiler reads it itself, before the first line of the
program, from the first of these that has it:

- beside the file being compiled;
- beside the compiler - the directory `btpc.exe` was started from, which the
  loader is asked for - which is where it is when the program is somewhere
  else. A library that is not found either place is
  `Error 158: Cannot find rtldos.pas`;
- where the name says, which is the current directory.

A program that writes `{$I rtldos.pas}` anyway is doing nothing: the name is
the library's, and a file that has already been read is not opened again. The
compiler's own source keeps the line, because a compiler older than this rule
does not read the library by itself, and for the length of that one build it is
given the older library to read there - a library that calls a runtime
primitive an older compiler has never heard of is no use to it.

What the library has to declare is what the compiler emits calls to and finds
by name in the image: `GetMem`, `FreeMem` and `RtlFreeBlock`, which are what
`new` and `dispose` are compiled into. A library that leaves one of them out is
`Error 159: Routine the library must declare is missing`. Everything else the
program calls, it has to find where the program says, which is what the table
below is.

The library is written in the language the compiler accepts, which is narrower
than Delphi's, and the conventions it uses follow from that:

| Group | What it gives |
|---|---|
| DOS | `DosVersion`, `DosMajor`, `DosMinor`, `DosDate`, `DosTime`, `DosDrive`, `KeyPressed`, `ReadKey`, `WriteRaw`, `Registers`, `Intr` |
| strings | `StrLen`, `StrCopy`, `StrEq`, `StrLess`, `UpStr`, `SetStr`, `Str`, `Val`, `Hex`, `WriteStr`, `WriteStrLn` |
| command line | `ArgCount`, `ArgLen`, `ArgChar`, `ArgCopy`, `ArgText`, `ArgWrite`, `ArgWriteLn`, `ArgIs` |
| files | `Reset`, `ReWrite`, `BlockRead`, `BlockWrite`, `Seek`, `FilePos`, `FileSize`, `Close`, `ResetArg`, `ReWriteArg`, and `IOError`, the number the last call left |
| memory | `GetMem`, `GetMemZeroed`, `FillChar`, `Move`, `FreeMem`, `New`, `Dispose` |

Three things about it are worth knowing before reading it:

- **A `char` is a four-byte cell** here, so a `PChar` steps four bytes at a time
  and a byte inside a word is extracted arithmetically - `RtlByte` is what every
  masked read of a `Registers` field goes through. A string in memory is one
  character per cell.
- **A buffer travels as `Addr(X[1])`.** A `var` parameter's array type is
  checked against the argument's bounds, and the way round that is a pointer.
- **`SetStr` takes sixteen characters** and is for keys, not paths: a file name
  is built as a NUL-terminated array of cells, which is what `Reset` and
  `ReWrite` want.

## Long file names

A file is opened by name, and the name is handed to DOS by the runtime. There
are two entries for that in DOS: the long-name one, `AH=716Ch`, and the original
8.3 one, `AH=3Dh` for a file that is there and `AH=3Ch` for one that is to be
created. The runtime asks for the long-name entry first and falls back to the
8.3 entry when it does not answer.

**There is no way to ask whether long names are there.** No call answers that,
and no flag or version number can be trusted for it. What there is, is the carry
flag: a DOS that has the long-name function clears the carry when it has done
what was asked, and a DOS that has never heard of it leaves the flags exactly as
it found them. So the runtime sets the carry before the call and reads it after
it, and that is the whole of the test:

- **carry clear** - the long-name call ran and succeeded. The handle is in `AX`;
- **carry set** - the long-name call either failed or was never there, and the
  two cases need the same answer. The registers are rewritten - the name into
  `DS:DX`, where the 8.3 entry wants it rather than `DS:SI` where `716Ch` takes
  it, the mode into `AX`, fresh attributes in `CX` - and the 8.3 entry is called.
  Rewriting them is not tidiness: the rejected call leaves the fields it did not
  read holding whatever the caller put there, and the entry that is called
  second reads more of them than the first did.

Which entry answered is not recorded anywhere, because nothing needs to know.
What the fallback buys is that a DOS without long names is a DOS where 8.3 names
still work, instead of the DOS where nothing opens at all. What it does not buy
is a long name on such a DOS: a name longer than eight plus three is a name only
the long-name entry can reach, so **a program that has to run under both writes
8.3 names**, and one that writes a long name runs where long names do.
`examples/files.pas` opens a name of seventeen characters, so it is a sample
for a DOS with long names - which the DOSBox-X configuration here is
(`lfn = true`).

Opening is the only one of the file calls with a name in it. Reading, writing,
seeking and closing take a handle the open answered with - `AH=3Fh`, `40h`,
`42h` and `3Eh` - and those are the same call on every DOS there is, long names
or none. The library has no delete, rename, mkdir or find-first, so there is no
other name to hand over.

## The samples

`examples/` holds one program per feature; each one is compiled by its batch and
its output is read from the `.out` file beside it.

| Sample | Built by | What it shows |
|---|---|---|
| `hello.pas` | `B2` | the smallest program there is: `hello, HX-DOS` |
| `files.pas` | `B2` | a long file name, the bytes written and read back, and the command line |
| `inline.pas` | `B2` | the two `inline` rules, checked: a screen cell written and read back, a branch, and the stack depth |
| `intrtest.pas` | `B2` | `Intr` with the registers in a record, including a failed call whose carry comes back set |
| `shifts.pas` | `B2` | `shl` and `shr`: precedence, the count taken modulo 32, `shr` being logical, and the sign binding the whole term |
| `libtest.pas` | `B1` | every part of the library once, in order - DOS, strings, the command line, files |
| `memlist.pas` | `B1` | a linked list on the heap: ten nodes, freed and allocated again |
| `memarray.pas` | `B1` | two thousand integers on the heap, read back and summed |
| `memreuse.pas` | `B1` | a hundred thousand allocate-and-free cycles: nothing refused, nothing corrupted |

`test.pas` and `maketest.bat` are upstream's own example and are kept as they came; neither batch
builds them.

## License

The compiler and the port are under the zlib license:

    ******************************************************************************
    *                                zlib license                                *
    *============================================================================*
    *                                                                            *
    * Copyright (C) 2026,      DosWorld                                          *
    * Copyright (C) 2006-2016, Benjamin Rosseaux (benjamin@rosseaux.com)         *
    *                                                                            *
    * This software is provided 'as-is', without any express or implied          *
    * warranty. In no event will the authors be held liable for any damages      *
    * arising from the use of this software.                                     *
    *                                                                            *
    * Permission is granted to anyone to use this software for any purpose,      *
    * including commercial applications, and to alter it and redistribute it     *
    * freely, subject to the following restrictions:                             *
    *                                                                            *
    * 1. The origin of this software must not be misrepresented; you must not    *
    *    claim that you wrote the original software. If you use this software    *
    *    in a product, an acknowledgement in the product documentation would be  *
    *    appreciated but is not required.                                        *
    * 2. Altered source versions must be plainly marked as such, and must not be *
    *    misrepresented as being the original software.                          *
    * 3. This notice may not be removed or altered from any source distribution. *
    *                                                                            *
    ******************************************************************************

The runtime library `src/rtldos.pas` is the port's own file and is public
domain, under the Unlicense its header names.
