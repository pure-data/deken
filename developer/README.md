# Developers #

You can use the [`deken` command line tool](https://raw.githubusercontent.com/pure-data/deken/master/developer/deken) to create packaged zipfiles with the correct searchable architectures in the filename, for example `freeverb~-v0.1-(Linux-amd64-64)-externals.zip`.

If you don't want to use the `deken` packaging tool you can zip and upload the files yourself. See the "Filename format" section below.

## Get started ##

	$ curl https://raw.githubusercontent.com/pure-data/deken/master/developer/deken > ~/bin/deken
	$ chmod 755 ~/bin/deken
	$ deken
	This is your first time running deken on this machine.
	I'm going to install myself and my dependencies into ~/.deken now.
	Feel free to ctrl-C now if you don't want to do this.
	...

See [config.md](./config.md) for deken's configuration file format.

## Create and Upload a package ##

You have a directory containing your compiled externals object files called `my_external`.

This command will create a file like `my_external-v0.1-(Linux-amd64-64)-externals.zip` and upload it to your account on <http://puredata.info/> where the search plugin can find it:

	$ deken package -v 0.1 my_external
	$ deken upload my_external

You can also just call the 'upload' directly and it will call the package command for you in one step:

	$ deken upload -v 0.1 my_external

The upload step will also generate a .sha256 checksum file and upload it along with the zip file.

## Filename format ##

The `deken` tool names a zipfile of externals binaries with a specific format to be optimally searchable on [puredata.info](http://puredata.info/):

	NAME[-VERSION-](ARCH1)(ARCH2)(ARCHX...)-externals.zip

 * NAME is the name of the externals package ("zexy", "cyclone", "freeverb~").
 * -VERSION- is an optional section which can contain version information for the end user.
 * (ARCH1)(ARCH2) etc. are architecture specifiers for each type of architecture the externals are compiled for within this zipfile.

Note that the zipfile should contain a single directory at the top level with NAME the same as the externals package itself. For example a freeverb~ externals package would contain a directory "freeverb~" at the top level of the zipfile in which the externals live.

The square brackets around the "-VERSION-" section are to indicate it is optional, don't include them. The round braces "(" around architectures are included to separate the architectures visibly from eachother.

Some examples:

	freeverb~(Windows-i386-32)-externals.zip
	freeverb~(Linux-armv6-32)-externals.zip
	cyclone-0.1_alpha57(Linux-x86_64-64)-externals.zip
	freeverb~(Darwin-i386-32)(Darwin-x86_64-32)(Linux-armv6-32)-externals.zip


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

    deken upload frobnozzel(Windows-i386-32)(Sources)-externals.zip
    deken upload foobar-v0.1-(Linux-x86_64-64)-externals.tgz foobar-v0.1-(Sources)-externals.tgz

## Upgrade ##

	$ deken upgrade
	... self upgrades the scripts ...

## Show help ##

	$ deken -h

## Platform ##

OSX Example

	$ deken --platform
	Darwin-i386-64bit

Linux example

	$ deken --platform
	Linux-x86_64-64bit-ELF

Raspbian

	$ deken --platform
	Linux-armv6l-32bit-ELF
