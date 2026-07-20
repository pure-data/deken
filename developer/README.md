External Developers
===================

You can use the [`deken` command line
tool](https://raw.githubusercontent.com/pure-data/deken/main/developer/deken)
to create packaged zipfiles with the correct searchable architectures in the
filename, for example `freeverb~-v0.1-(Linux-amd64-64)-externals.zip`.

If you don't want to use the `deken` packaging tool you can zip and upload the
files yourself. See the "Filename format" section below.

See [config.md](./config.md) for deken's configuration file format.

## Get started ##

See https://deken.readthedocs.io/ or [docs/cmdline](../docs/cmdline.md).

## Filename format ##

The `deken` tool names a zipfile of externals binaries with a specific format to
be optimally searchable on [puredata.info](http://puredata.info/);

	LIBNAME[vVERSION]{(ARCH)}.dek

 * LIBNAME is the name of the externals package ("zexy", "cyclone", "freeverb~").
 * VERSION contains the version information for the end use
   (this information is optional though *strongly* encouraged)
 * ARCH is the architecture specifier, and can be given multiple times
   (once for each type of architecture the externals are compiled for within
   this archive).
   It is either "Sources" (see [below](#sourceful-uploads) or `OS-MARCH-BIT`,
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


## Sourceful uploads
`deken` is very much about *sharing*.
To make sharing a more lasting experience, `deken` encourages the upload of
"source-packages" besides (pre-compiled) binary packages.

This is especially important if you are uploading a library that has been
released under a license that requires you to share sources along with binaries
(e.g. software licensed under the Gnu GPL), where it is your obligation to
provide the source code to the end users.
In other situations, having Source packages might be less important (e.g. it is
fine to use `deken` with closed source libraries), however we would like to
encourage sharing of sources.

The way `deken` implements all this is by using a special pseudo architecture
"Sources", which contains the sources of a library.

`deken package` tries to automatically detect whether a package contains Sources
by looking for common source code files (*.c, *.cpp, ...).

When uploading a package, `deken` will ensure that you are *also* uploading a
Source package of any library.
If a Source package is missing, `deken` will abort operation.
You can override this (e.g. because you have already uploaded a Source package;
or because you simply do not want to upload any sources) by using the
`--no-source-error` flag.

For uploading a Source package along with binary packages, you can upload one
package file with multiple archs (including a "Sources" arch) or multiple package
files (one for the "Sources" arch).

~~~sh
$ deken upload frobnozzel(Windows-i386-32)(Sources).dek
$ deken upload foobar[v0.1](Linux-x86_64-32).dek foobar[v0.1](Sources).dek
~~~

## objectlists
Sometimes the user only knows the object they need, not the library.
Therefore, a search initiated via the `deken-plugin` (Pd's package manager) also
searches for *objects*.
For this to work, the infrastructure must know which objects are contained in a
library; this is done via an objectlist file.

The objectlist file consists of exactly one line per object, with the object-name at the beginning,
followed by a TAB (`\t`) and a short (single-line) description of the object.

~~~
frobnofy	frobfurcate a bugle of numbers
frobnofy~	signal frobfurcation
~~~

The objectlist file has the same name as the package with a `.txt` appended.
E.g. if your library is called `frobnozzel(Windows-i386-32)(Sources).dek`, the
objectlist file would have the name `frobnozzel(Windows-i386-32)(Sources).dek.txt`
This file must be uploaded to the same directory as the `.dek` file.

`deken` will try to automatically generate an objectlist file for a package.
It looks for all "*-help.pd" files in the library directory, and creates an
entry in the objectlists for each. The short description is taken from the
`DESCRIPTION` comment in the `[pd META]` subpatch within the help-patch.
If no DESCRIPTION comment can be found, a generic description is used.

You can provide your own (manually maintained) objectlist file via the
`--objects`  flag:

~~~sh
$ deken package --objects mylist.txt my_external
~~~

To prevent the creation/use of an objectlist file, pass an empty string

~~~sh
$ deken package --objects "" my_external
~~~

In general, it is preferable if the description of the object in the META
subpatch is included in the object's help file (and let deken generate the
objectlist from it), as this allows others (humans, Pd, plugins, ...) to
access the same information as well.

## Troubleshooting

see [DEVELOPMENT.md](DEVELOPMENT.md) for some troubleshooting advice.
