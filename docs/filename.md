Filename format
===============

The `deken` tool names a zipfile of externals binaries with a specific format to
be optimally searchable on [puredata.info](http://puredata.info/);

	LIBNAME[vVERSION]{(ARCH)}.dek

 * LIBNAME is the name of the externals package ("zexy", "cyclone", "freeverb~").
 * VERSION contains the version information for the end use
   (this information is optional though *strongly* encouraged)
 * ARCH is the architecture specifier, and can be given multiple times
   (once for each type of architecture the externals are compiled for within
   this archive).
   It is either "Sources" (see [Sourceful uploads](best-practice.md#sourceful-uploads) or `OS-MARCH-BIT`,
   with:
   - OS being the Operating System. Typical values are:
     - `Linux`
     - `Darwin`
     - `Windows`
   - MARCH is the machine architecture, e.g.:
     - `i386` (32bit Intel/AMD-compatible CPUs)
     - `amd64` (64bit Intel/AMD-compatible CPUs; synonymous for `x86_64`, though `amd64` is the preferred form)
     - `ppc` (the `PowerPC` architecture popular in old Apple computers)
     - `armv7l` (little-endian 32bit ARM CPUs as found in the *Raspberry Pi 3*)
   - BIT is the size of Pd's numbers in bits (usually `32`; for double-precision it will be `64`)
   
   A detailed explanation of the ARCH specifier can be found [here](arch-specifiers.md).

Note that the archive should contain a single directory at the top level with
NAME the same as the externals package itself. For example a freeverb~ externals
package would contain a directory "freeverb~" at the top level of the zipfile in
which the externals live.

The version string must be enclosed by square brackets (`[]`) and start with a `v`.
The version string itself must not contain any brackets or parentheses.
Strictly speaking, the version (with the enclosing brackets) is optional, however
it is highly suggested that you provide it.

The curly braces around the "(ARCH)" specifiers are only to indicate that this section
can occur multiple times (or not at all).
However, the round parentheses "()" enclosing the architectures string must be included to
separate the architectures visibly from each other.

In plain English this means:
> the library-name, followed by an optional version string (starting with `[v`
> and ending with `]`), followed by zero or more architecture specifications
> (each surrounded by `(`parentheses`)`), and terminated by `.dek`.


Here is the actual regular expression used:

    (.*/)?([^\[\]\(\)]+)(\[v[^\[\]\(\)]+\])?((\([^\[\]\(\)]+\))*)\.(dek)

with the following matching groups:

 - ~~`#0` anything before the path (always empty and *ignored*)~~
 - ~~`#1` = path to filename (*ignored*)~~
 -   `#2` = library name
 -   `#3` = options (including the version)
 -   `#4` = archs
 - ~~`#5` = last arch in archs (*ignored*)~~
 -   `#6` = extension ('dek')

Some examples:

    adaptive[v0.0.extended](Linux-i386-32)(Linux-amd64-32).dek
    adaptive[v0.0.extended](Sources).dek
    freeverb~(Darwin-i386-32)(Darwin-x86_64-32)(Sources).dek
    list-abs[v0.1].dek

