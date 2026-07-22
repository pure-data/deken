Object lists
============

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
