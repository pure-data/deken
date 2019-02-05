# Developers #

You can use the [`deken` command line
tool](https://raw.githubusercontent.com/pure-data/deken/master/developer/deken)
to create packaged zipfiles with the correct searchable architectures in the
filename, for example `freeverb~-v0.1-(Linux-amd64-64)-externals.zip`.

If you don't want to use the `deken` packaging tool you can zip and upload the
files yourself. See the "Filename format" section below.

## Get started ##

	$ mkdir -p ~/bin/
	$ curl https://raw.githubusercontent.com/pure-data/deken/master/developer/deken > ~/bin/deken
	$ chmod 755 ~/bin/deken
	$ deken
	This is your first time running deken on this machine.
	I'm going to install myself and my dependencies into ~/.deken now.
	Feel free to ctrl-C now if you don't want to do this.
	...


See [config.md](./config.md) for deken's configuration file format.


If you get an error like

> -bash: deken: command not found

then make sure that [`~/bin` is in your `PATH`](https://apple.stackexchange.com/a/99838).

### Pre-built binaries for Windows

If you don't want to install Python, bash (MSYS),... on your Windows machine, you can download
self-contained binaries from our Continuous Integration setup:

- [Windows 32bit](https://ci.appveyor.com/api/projects/umlaeute/deken/artifacts/developer/dist/deken.exe?job=Environment%3A%20PYTHON%3DC%3A%5CPython36%2C%20PYTHON_VERSION%3D3.6%2C%20PYTHON_ARCH%3D32&branch=master)
- [Windows 64bit](https://ci.appveyor.com/api/projects/umlaeute/deken/artifacts/developer/dist/deken.exe?job=Environment%3A%20PYTHON%3DC%3A%5CPython36-x64%2C%20PYTHON_VERSION%3D3.6%2C%20PYTHON_ARCH%3D64&branch=master)

These builds are snaphots of the latest development branch of `deken`.
If they don't work for you, you might want to check the [releases page](https://github.com/pure-data/deken/releases)
for downloads that have been tested by humans.

## Show help ##

~~~sh
$ deken -h
~~~

## Upgrade ##

To run a self-upgrade (not supported on all platforms), simply do:

~~~sh
$ deken upgrade
~~~

## Create and Upload a package ##

You have a directory containing your compiled externals object files called
`my_external`.

This command will create a file like `my_external[v0.1](Linux-amd64-64).dek`
and upload it to your account on <https://puredata.info/> where the search plugin
can find it:

~~~sh
$ deken package -v 0.1 my_external
$ deken upload "my_external[v0.1](Linux-amd64-64).dek"
~~~

You can also just call the 'upload' directly and it will call the package
command for you in one step:

~~~sh
$ deken upload -v 0.1 my_external
~~~

The upload step will also generate a .sha256 checksum file and upload it along
with the dek file.
If possible, also a GPG signature file (with the .asc extension) will be created
and uploaded (but you must have [GPG](https://www.gnupg.org/) installed and you
need to have a GPG key for signing. The GPG signature mostly makes sense, if
your GPG key is cross-signed by (many) other people).


### Creating/Uploading packages on a different machine
`deken` inspects the files in the directory to determine the target platform
(rather than just checking on which system you are currently running).
Therefore, if it is not feasible to install `deken` on the machine used for
building your Pd library, you can run `deken` on another machine,

Example: You build the "my_external" library on OSX-10.5, but (due to OSX-10.5
not being supported by Apple anymore) you haven't installed `deken` there.
So you simply transfer the "my_external" directory to your Linux machine, where
you run `deken package my_external` and it will magically create the
`my_external[v3.14](Darwin-i386-32)(Darwin-amd64-32)-externals.tgz` file for
you, ready to be uploaded.

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
library; which is done via an objectlist file.

The objectlist file has one line per object, with the object-name at the beginning,
followed by a TAB (`\t`) and a short (single-line) description of the object.

~~~
frobnofy	frobfurcate a bugle of numbers
frobnofy~	signal frobfurcation
~~~

The objectlist file has the same name as the package with a `.txt` appended.
E.g. if your library is called `frobnozzel(Windows-i386-32)(Sources).dek`, the
objectlist would have the name `frobnozzel(Windows-i386-32)(Sources).dek.txt`

`deken` will try to automatically generate an objectlist file for a package.
It looks for all "*-help.pd" files in the library directory, and creates an
entry in the objectlists for each. The short description is set to a generic one.

You can provide your own (manually maintained) objectlist file via the
`--objects`  flag:

~~~sh
$ deken package --objects mylist.txt my_external
~~~

To prevent the creation/use of an objectlist file, pass an empty string

~~~sh
$ deken package --objects "" my_external
~~~
