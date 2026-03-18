Architecture Specifiers
=======================

## architecture specifiers for binaries
External binaries need to be compatible with a given Pd binary.
In order to identify externals that are compatible, *architecture specifiers* are used.

Each architecture specifier consists of a triplet `Operating System`, `CPU` and `floatsize`,
joined by dash (`-`), for example `Linux-amd64-32`
(Operating System is *Linux*, the CPU is *amd64* and the floatsize is *32*)

The `Operating System` and `CPU` specifiers define, whether a binary is loadable in principle
(by the means provided by a given OS installation).
The `floatsize` specifier is used to distinguish between precision flavours of Pd
(whether a binary is for single precision or double precision).


### OS specifiers

#### common OS specifiers

| OS        | description |
|-----------|-------------|
| `Darwin`  | the OS produced by Apple (macOS, OSX,...);<br/>*Darwin* is the name of the kernel of these systems |
| `Linux`   | the popular Open Source OS |
| `Windows` | the OS produced by Microsoft |


#### other OS specifiers

| OS        | description |
|-----------|-------------|
| `NetBSD`  | BSD-variant
| `FreeBSD` | BSD-variant
| `OpenBSD` | BSD-variant
| `Hurd`    | the GNU Operating System |
| `Solaris` | a Unix system |
| `Irix`    | a Unix system for SGI workstations |

### CPU specifiers

The CPU specifiers follow the [Debian architecture naming scheme](https://wiki.debian.org/ArchitectureSpecificsMemo).
They are generally all-lowercase and consist only of alphanumeric characters.

| CPU     | description |
|---------|-------------|
| `amd64` | 64bit AMD/Intel processors (aka `x86_64`) |
| `arm64` | 64bit ARM processors |
| `i386`  | 32bit AMD/Intel processors (aka `x86`) |
| `arm`   | 32bit ARM processors |

#### compatible CPU specifiers

| CPU     | compatible with these CPUs |
|---------|----------------------------|
| `i686`  | `i586`
| `i586`  | `i386`
| `armv7` | `armv6`
| `armv6` | `armv5`
| `armv6` | `arm`

(e.g. a package for `Windows-i586-32` can only run on a Windows PC with a Pentium processor,
whereas a package for  `Windows-i386-32` can run on a Windows PC with either an i386 CPU or a Pentium processor)


#### obsolete CPU specifiers

|obsolete CPU | use this instead |
|-------------|------------------|
| `PowerPC`   | `ppc`            |
| `x86_64`    | `amd64`          |
| `aarch64`   | `arm64`          |



#### other CPU specifiers

These are somewhat modern but CPUs (but probably see very few uses of Pd):

| CPU        | word size | endianness | description |
|------------|-----------|------------|-------------|
| `loong64`  | 64        | little     | Loongson processors
| `ppc`      | 32        | BIG        | PowerPC (rather old Apple computers)
| `ppc64`    | 64        | BIG        | PowerPC (rather old Apple computers)
| `ppc64el`  | 64        | little     | IBM Power8 & Power9
| `mipsn32`  | 32        | BIG        | MIPS with n32 ABI (e.g. newer SGIs)
| `riscv`    | 32        | little     | RISC-V (`RV32*`)
| `riscv64`  | 32        | little     | RISC-V (`RV64*`)
| `s390x`    | 64        | BIG        | IBM S/390z (mainframes)



The following are probably only used on historic machines long out of use:

| CPU        | word size | endianness | description |
|------------|-----------|------------|-------------|
| `sparc`    | 32        | BIG        |
| `s390`     | 32        | BIG        | IBM S/390 (old mainframes)
| `hppa`     | 64        | BIG        |
| `sh4`      | 32        | ??         | SuperH (SH4)
| `blackfin` | 32        |            |
| `avr`      | ??        |            |
| `x32`      | 32        | little     |
| `ia64`     | 64        | BIG        |
| `ia64el`   | 64        | little     |
| `m68k`     | 32        | BIG        | very old Apple computers
| `sparc64`  | 64        | BIG        |
| `alpha`    | 64        | BIG        | DEC Alpha
| `mips`     | 32        | BIG        | MIPS (e.g. old SGIs)
| `mipsel`   | 32        | little     | MIPS (Little Endian)
| `mips64`   | 64        | BIG        | MIPS (e.g. new SGIs)
| `mipso64`  | 64        | BIG        | MIPS with o32 ABI (probably unused)
| `mips64el` | 64        | little     | MIPS (Little Endian)


### floatsize specifiers


| floatsize | description |
|-----------|-------------|
| `32`      | single precision Pd
| `64`      | double precision Pd
| `0`       | precision agnostic (binaries can be loaded by a Pd running any precision, including - but not limited to - single and double precision)



## special architecture `Sources`

Packages that contain source-code to compile a specific library
use the pseudo architecture specifier `Sources`.

A package that only contains this pseudo architecture (e.g. `my_library[v0.1](Sources).dek`)
is not usable directly by Pd.

However, it is useful to allow people to re-compile the library (e.g. for a new architecture).


## architecture specifier for non-binaries

Packages that do not include any compiled objects are said to be architecture independent
(as they can be used on any architecture where Pd runs on).

In this case the list architecture specifiers is left empty.



## merging architecture specifiers
Architectures are cumulative: If a library contains multiple architectures,
the architecture specifiers are appended to the list.

E.g. if a package contains both a `foo.dll` binary (Windows, i386, single precision)
and a file `foo.d_fat` (macOS, amd64 and arm64, single precision),
the architecture identifiers for the package are `Windows-i386-32`+`Darwin-amd64-32`+`Darwin-arm64-32`

If a package contains both architecture independent objects (e.g. abstractions)
*and* binary objects (e.g. a `Windows-i386-32` external)
the latter shadow the former, so the package will have
the architecture identifier(s) `Windows-i386-32`.

If a package contains both binaries (for a given OS/CPU) combination that are both
floatsize-specific (e.g. for double precision, e.g. `Linux-amd64-64`)
*and* floatsize-agnostic (e.g. `Linux-amd64-0`),
then the former shadows the latter, so the package will have
the architecture identifier(s) `Linux-amd64-64`.
