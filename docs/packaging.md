Creating Deken Packages
=======================

In order to provide your own external libraries via this service,
you must upload a deken package to https://puredata.info/.
For this you will first need an account on that portal.

The simplest way to create and upload packages is via the `deken` commandline tool.
See [the tool page](cmdline.md) on how to install it (there are prebuilt binaries for Windows and macOS, a docker image, and an installer script for other systems.)

## Prepare your package

Put all your library files (Pd patches, binaries,...) into a directory that has the same name as your library.
Abstractions and externals are typically in the root of this directory,
so users will be able to use your library with something like:
``` pd
[declare -path library -lib library]
```

You can include binaries for multiple systems (Linux, macOS, Windows,...),
CPUs (amd64, arm64, i386, PDP-11,...) and floatsizes (Pd32, Pd64).
However, keep in mind that the actual package file will encode all architectures into the filename,
and most filesystems will not allow more than 255 characters for a filename.
For a detailed explanation of how the filename encodes the architecture, see [Filename format](file-format.md).

Feel free to put supporting files (like examples, tutorials,...) into subfolders.


## Create the package

``` console
$ deken package --version "0.0.1" mylibrary/
```

the deken command line tool, will create a ZIP file from the package directory,
that encodes library name, version and included architectures in the filename.

``` console
$ ls -l *.dek
mylibrary[v0.0.1](Linux-amd64-32)(Windows-amd64-32)(Darwin-arm64-32).dek
```

It will also create a list of objects included in your library,
based on the help-patches that are found in the top-level directory.
If your help patches contain a `[pd META]` subpatch that contains a comment starting with DESCRIPTION,
this descriptive string will be included in the list of objects (and displayed on the [deken webpage](https://deken.puredata.info)):

``` console
$ head "mylibrary[v0.0.1](Linux-amd64-32)(Windows-amd64-32)(Darwin-arm64-32).dek.txt"
frobnozzel	calculate the mean bamboozle value of a list
frobnozzel~	calculate the mean bamboozle value of a signal
```

It will also create a SHA256 checksum file (so it's easy to verify if the download was correct):

``` console
$ cat "mylibrary[v0.0.1](Linux-amd64-32)(Windows-amd64-32)(Darwin-arm64-32).dek.sha256"
0e21dabaae872bd49c55385ff1417551fe81fd4406c6798f2864680ced7796a7
```

Finally, if you have setup GPG, it will also attempt to sign the package file with your default PGP key.

``` console
$ gpg --verify "mylibrary[v0.0.1](Linux-amd64-32)(Windows-amd64-32)(Darwin-arm64-32).dek.asc" "mylibrary[v0.0.1](Linux-amd64-32)(Windows-amd64-32)(Darwin-arm64-32).dek"
gpg: Signature made Sat Apr 01 23:22:05 2000 CET
gpg:                using RSA key 1234567890ABCDEF1234567890ABCDEF12345678
gpg: Good signature from "Practical Joker "
```

See `deken --help` for more information on how to use the tool.


!!! note

    Before you upload a package, please make sure that the detected architectures in the generated package match your expectations
    (esp. if you are building for a non-mainstream architecture).


## Upload the package

Once you have verified that the package has been correctly created, it is time to upload:

``` console
$ deken upload "mylibrary[v0.0.1](Linux-amd64-32)(Windows-amd64-32)(Darwin-arm64-32).dek"
```

This will ask you for your [puredata.info](https://puredata.info) username and password,
and upload the package, object list, checksum file and the signature to the deken repository.

Depending on the server load, it might take a while until the package is available for download,
but it shouldn't take longer than 24 hours (and usually it is available within a few minutes).
