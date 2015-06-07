A minimal package management system for Pure Data externals.

![Animated GIF demonstration of the Deken plugin user interface](https://raw.githubusercontent.com/pure-data/deken/master/deken.gif)

Packages are stored on <http://puredata.info/> and can be installed using the `Help -> Find Packages` menu after installing the [TCL plugin](https://raw.githubusercontent.com/pure-data/deken/master/deken-plugin.tcl).

## Download ##

Click to download [deken-plugin.tcl](https://raw.githubusercontent.com/pure-data/deken/master/deken-plugin.tcl) and save it to your Pd folder:

 * Linux = `~/pd-externals/`
 * OSX = `~/Library/Pd/`
 * Windows = `%AppData%\Pd`

 Then select `Help -> Find Packages` and type the name of the external you would like to search for.

# Developers #

You can use the command line tool to create packaged zipfiles with the correct searchable architectures in the filename, for example `freeverb~(Linux-amd64-64)-externals.zip`.

If you don't want to use the `deken` packaging tool you can zip and upload the files yourself. See the "Filename format" section below.

## Get started ##

	$ curl https://raw.githubusercontent.com/pure-data/deken/master/deken > ~/bin/deken
	$ chmod 755 ~/bin/deken
	$ deken
	This is your first time running deken on this machine.
	I'm going to install myself and my dependencies into ~/.deken now.
	Feel free to ctrl-C now if you don't want to do this.
	...

## Create and Upload a package ##

You have a directory containing your compiled externals object files called `my-external`.

This command will create a file like `my-external-v0.1-(Linux-amd64-64)-externals.zip` and upload it to your account on <http://puredata.info/> where the search plugin can find it:

	$ deken package -v 0.1 my-external
	$ deken upload my-external

You can also just call the 'upload' directly and it will call the package command for you in one step:

	$ deken upload -v 0.1 my-external

## Filename format ##

The `deken` tool names a zipfile of externals binaries with a specific format to be optimally searchable:

	NAME[-VERSION-](ARCH1)(ARCH2)(ARCHX...)-externals.zip

 * NAME is the name of the externals package ("zexy", "cyclone", "freeverb~").
 * -VERSION- is an optimal section which can contain version information for the end user.
 * (ARCH1)(ARCH2) etc. are architecture specifiers for each type of architecture the externals are compiled for within this zipfile.

Note that the zipfile should contain a single directory at the top level with NAME the same as the externals package itself. For example a freeverb~ externals package would contain a directory "freeverb~" at the top level of the zipfile in which the externals live.

The square brackets around the "-VERSION-" section are to indicate it is optional, don't include them. The round braces "(" around architectures are included to separate the architectures visibly from eachother.

Some examples:

	freeverb~(Windows-i386-32)-externals.zip
	freeverb~(Linux-armv6-32)-externals.zip
	cyclone-0.1_alpha57(Linux-x86_64-64)-externals.zip
	freeverb~(Darwin-i386-32)(Darwin-x86_64-32)(Linux-armv6-32)-externals.zip

## Upgrade ##

	$ deken upgrade
	... self upgrades the scripts ...

## Show help ##

	$ deken -h

	$ deken pd -h

	$ deken build -h

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

## Build an external from a repository ##

	$ deken build svn://svn.code.sf.net/p/pure-data/svn/trunk/externals/freeverb~/
	Deken 0.1
	Checking out svn://svn.code.sf.net/p/pure-data/svn/trunk/externals/freeverb~/ into ./workspace/externals/freeverb~
	Building ./workspace/externals/freeverb~

## Build and install an external from a repository ##

	$ deken install svn://svn.code.sf.net/p/pure-data/svn/trunk/externals/freeverb~/
	Deken 0.1
	Updating ./workspace/externals/freeverb~
	Building ./workspace/externals/freeverb~
	Installing ./workspace/externals/freeverb~ into ./pd-externals/freeverb~

## Manage Pd version ##

Show Pd version:

	$ deken pd
	Deken 0.1
	Pd version 0.43 checked out

Change Pd version:

	$ deken pd master
	Deken 0.1
	Pd version master checked out

### How to make your externals compatible ###

<http://puredata.info/docs/developer/MakefileTemplate>

