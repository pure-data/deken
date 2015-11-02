Deken can also be used to build some externals directly from a repository.

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

