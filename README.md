## Get started ##

	$ curl https://raw.githubusercontent.com/pure-data/deken/master/deken > ~/bin/deken
	$ chmod 755 ~/bin/deken
	$ deken
	This is your first time running deken on this machine.
	I'm going to install myself and my dependencies into ~/.deken now.
	Feel free to ctrl-C now if you don't want to do this.
	...

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

## Upgrade ##

	$ deken upgrade
	... self upgrades the scripts ...

### How to make your externals compatible ###

<http://puredata.info/docs/developer/MakefileTemplate>

