File format
===========

A Deken package is a ZIP file with the custom extension `.dek`, and the following filename convention:

	$LIBNAME[$VERSION]{$ARCH}.dek

 * `$LIBNAME` is the name of the externals package ("*zexy*", "*cyclone*", "*freeverb~*").
 * The optional `$VERSION` contains the version information for the end user.
   (This information is optional, but *strongly* encouraged.)
   If present it consists of the the actual version prefixed with `v` and enclosed in square brackets (e.g. "*[v1.2]*")
 * The optional version information is followed by zero or more architecture specifiers `$ARCH`
   (one for each type of architecture the externals are compiled for within this archive).
   Each architecture specifier must be enclosed in round parenthese,
   and can be either the literal "*(Sources)*" (see [Sourceful uploads](best-practice.md#sourceful-uploads))
   or a dash separated triplet `($OS-$MARCH-$BIT)` (e.g. "*(Windows-amd64-32)*"):
       - `$OS` is the Operating System. Typical values are:
         - `Linux`
         - `Darwin`
         - `Windows`
       - `$MARCH` is the machine architecture, e.g.:
         - `i386` (32bit Intel/AMD-compatible CPUs)
         - `amd64` (64bit Intel/AMD-compatible CPUs; synonymous for `x86_64`, though `amd64` is the preferred form)
         - `ppc` (the `PowerPC` architecture popular in old Apple computers)
         - `armv7l` (little-endian 32bit ARM CPUs as found in the *Raspberry Pi 3*)
       - `$BIT` is the size of Pd's numbers in bits (usually `32`; for double-precision it will be `64`;
          for externals that are truely independent of the number size, this can be `0`).

   A detailed explanation of the `$ARCH` specifier can be found [here](arch-specifiers.md).

!!! note
    The archive should contain a single directory at the top level
    that is named exactly like the `$NAME` of the externals package.
    For example a `freeverb~` externals package would contain
    a directory "`freeverb~/`" at the top level of the ZIP file in
    which the externals live.
    
The version string must be enclosed by square brackets (`[]`) and start with a `v`.
The version string itself must not contain any brackets or parentheses.
Strictly speaking, the version (with the enclosing brackets) is optional, however
it is highly suggested that you provide it.

The architecture specifiers must be enclosed by round parentheses (`()`)
and must not contain any brackets or parentheses.
The architecture specifiers can appear zero (for architecture indepented packages)
or multiple times (once for each supported architecture).
They must come after the (optional) version information,
and they must be grouped together. The order of architectures does not matter.

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

