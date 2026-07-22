Packaging Best Practice
=======================

## Versioning

Every package should have a version.

This version is used to determine the latest release of a given library.
It is also used to sort multiple releases of a library.

To make this work, versions have to be sortable: newer versions must sort after older versions.

The algorithm used to sort version strings is as follows:

- the version string is split into numeric (integer) and non-numeric components.
  e.g. `1.23.3-beta` is split into a tuple `1 . 23 . 3 -beta`.
- two version tuples are compared element wise

    - existing components are always greater than non-existing components (e.g. `1 . 0` is greater than `1`)
    - numeric components are compared according to numeric value (e.g. `20` is greater than `3`)
    - non-numeric components are compared alphabetically (e.g. `two` is greater than `thirty`)
    - the `~` character sorts before the other non-numeric characters


#### Examples

| version1   | compares | version2   |
|------------|----------|------------|
| `1.0.0`    | `==`     | `1.0.0`    |
| `1.1.4`    | `<<`     | `1.2.3`    |
| `1.9.4`    | `<<`     | `1.10.1`   |
| `1.2`      | `<<`     | `1.2.0`    |
| `1.2`      | `<<`     | `1.2.3`    |
| `1.2`      | `<<`     | `1.2beta`  |
| `1.2.3`    | `<<`     | `1.2beta`  |
| `1.2`      | `<<`     | `1.2.beta` |
| `1.1`      | `<<`     | `1.2~beta` |
| `1.2~beta` | **`<<`!!** | `1.2`    |
| `1.2~`     | `<<`     | `1.2~beta` |
| `1.2~beta` | `<<`     | `1.2(beta)`|
| `1.2(beta)`| `<<`     | `1.2+beta` |
| `1.2+beta` | `<<`     | `1.2-beta` |
| `1.2-beta` | `<<`     | `1.2.beta` |
| `1.2.beta` | `<<`     | `1.2=beta` |
| `1.2~beta` | `<<`     | `1.2.0`    |
| `1.2.0`    | `<<`     | `1.2=beta` |
| `1.2.beta` | `<<`     | `1.2beta`  |
| `2.5.1`    | `<<`     | `20250813` |
| `20250813` | `<<`     | `a`        |

The special handling of `~` allows for easy pre-releases:
a library with version `2.1~rc1` is considered older than version `2.1~rc2`, which is considered older than `2.1`.

### Semantic versioning

A popular versioning scheme is [Semantic versioniong](https://semver.org).

It uses a three-part version number `<major>.<minor>.<patch>` (like `2.9.4`) with the following rules:

- whenever there is any breaking change, the `<major>` number is incremented by one, and the `<minor>` and `<patch>` numbers are set to zero.

    e.g. `2.9.4` → `3.0.0`

- new features (that leave the library otherwise compatible), increment the `<minor>` number and reset the `<patch>` number to zero.

    e.g. `2.9.4` → `2.10.0`

- any other non-breaking changes (like bugfixes, documentation updates,...) increment the `<patch>` number, leaving the others as is.

    e.g. `2.9.4` → `2.9.5`


### Using the date as version

People that do not want to think too much about semantic versioning often use a "timestamp version",
as the date in the form `YYYYMMDD` makes it both easy to calculate and sort.

However, keep in mind that if you ever want to switch to another versioning scheme (like semantic versioning),
these timestamps might always sort after any reasonable version number.
E.g. `20250813` is always considered newer than `0.54` and `1.7.3`.

Therefore it is recommended to use a prefix `0.` (or `0.0.`) with the timestamp, e.g. `0.0.20250813`.

If you ever decide to switch the versioning scheme, your upload of `1.0.0` or `0.1.0`
will have a higher priority than the old date-based version.


## Sourceful uploads

`deken` is very much about *sharing*.
To make sharing a more lasting experience, `deken` encourages the upload of
"source-packages" besides (pre-compiled) binary packages.

This is especially important if you are uploading a library that has been
released under a license that requires you to share sources along with binaries
(e.g. software licensed under the Gnu GPL), where it is *your obligation* to
provide the source code to the end users.
In other situations, having Source packages might be less important (e.g. it is
fine to use `deken` with closed source libraries), however we would like to
encourage sharing of sources.

The way `deken` implements all this is by using a special pseudo architecture
"Sources", which contains the sources of a library.

`deken package` tries to automatically detect whether a package contains Sources
by looking for common source code files (*.c, *.cpp, ...).

When uploading a package, `deken` will ensure that you are *also* uploading a
Source package of the library.
If a Source package is missing, `deken` will abort operation.
You can override this (e.g. because you have already uploaded a Source package;
or because you simply do not want to upload any sources) by using the
`--no-source-error` flag.

For uploading a Source package along with binary packages, you can either

- upload one package file with multiple archs (including a "Sources" arch)

``` console
$ deken upload "frobnozzel[v0.0.20250813](Windows-i386-32)(Sources).dek"
```

- or multiple package files (including one for the "Sources" arch) in one go

``` console
$ deken upload "foobar[v0.1](Linux-amd64-32).dek" "foobar[v0.1](Sources).dek"
```

- or upload the Source package *before* the binary packages:

``` console
$ deken upload "mylib[v3.14](Sources).dek"
$ deken upload "mylib[v3.14](Darwin-arm64-32).dek"
```



## Object Lists

Oftentimes users only have a patch with a broken object,
without knowing which library contains this package.

Provide an [object list](object-list.md) to make the content of your package searchable.


## Fat archives of thin packages?

Deken packages typically contain binaries, Pd patches and example media.
If you want to provide packages for "all" the platforms that Pd runs on (or at least the most popular ones),
you have to chose whether to provide a single fat package (that contains multiple binaries)
or multiple smaller packages (one for each architecture), or something in between.

There are two main factors:

- how much data is shared between different architectures?
- how many architectures can you support?

If your library only consists of binaries (which are necessarily different on each platform)
and help patches (which are practically small text files), then there is not much overlap between
multiple per-architecture packages.

However, if your package also contains media files (soundfiles, PDFs, html-documentation,...)
then you might easily end up with tens of megabytes shared between packages.
This might not seem much, but if you provide packages for all 3 major platforms (*Linux*, *macOS* and *Windows*),
the most common CPUs (*amd64*, *arm64*, *armv7*) and both single-precision and double-precision flavours of Pd,
then there are about a dozen different architectures. Packaging each architecture separately will easily get you a few hundred MB *per release*.
If you also release often, chances are that your package soon consumes Gigabytes of data.

Since there are many different libraries, this does not scale well (server-grade storage is a tad more expensive than what walmart offers...).


Luckily, a single deken package can contain multiple architectures.
Since the architectures contained in the package are encoded in the filename, this can give you rather long filenames like so:

```
mylib[v0.1.2](Darwin-amd64-32)(Darwin-amd64-64)(Darwin-arm64-32)(Darwin-arm64-64)(Linux-amd64-32)(Linux-amd64-64)(Windows-amd64-32)(Windows-amd64-64).dek
```

Most filesystems have a limit of 255 or so characters.
The above filename is 153 characters long.
If you add some more architectures (e.g. *i386* (32bit Intel) on both *Windows* and *Linux*, and *armv7* (32bit Arm) on *Linux*),
the filename is 281 characters long, which means that most users won't be able to save the package file after downloading it.
(And the server might also have problems with that filename).

Apart from that, multi-architecture packages take longer to download (as they are bigger)
and are a bit more complex to create (as you need to make sure that per-architecture files have different names;
you also need to first build your library for all supported architectures before you can start creating the package).

So you need to find a happy medium between providing many small per-architecture packages (that eat a lot of server disk space),
and few large multi-architecture packages (that are harder to create and might exceed the filename length limitation).

The best strategy depends on your actual package.

- Check how much space is wasted when creating per-architecture packages: create a big package file (or just a ZIP file)
  of all the different architectures you provide and compare the size of this file with the combined size of the separate packages.
  If they are about the same (or the per-architecture packages are less than 2 times the size of the multi-architecture package),
  then creating a big multi-architecture package is probably not worth the hassle.
- Check how many architectures you support. If there's a dozen different architectures, then the filename will become dangerously long,
  and you should split the package into smaller ones.
- **Provide separate `Source` packages.**
  [Source packages](#sourceful-uploads) are important for licensing and reproducibility reasons
  (and allow people to build your libraries on architectures that you do not have access to).
  But for most users, the source code in your package will only be dead weight that they have to download for no apparent gain.
- **Bundle single and double precision binaries in a single package**
  If you provide both single- and double-precision variants of your library, make sure to provide them in the same package.
  Switching between Pd32 and Pd64 on the same computer is much easier than switching between Operating Systems or CPUs.
  (Also, the package manager will default to removing a library before re-installing it.
  Which makes it hard to install a library from two different packages for both Pd32 and Pd64)
- **Group packages by Operating System**.
  It's not unheard of, that people run both `amd64` (aka `amd64`/64bit Intel) and `arm64` (aka `aarch64`/Apple Silicon)
  binaries on a single macOS installation.
  Or `i386` (aka 32bit Intel) and `amd64` on a single Windows installation.
  Or share their homedirectory (with all the externals) via NFS between multiple Linux computers (of different architecture).


## Snapshot releases

Some projects are under active development and want to provide nightly builds.

Since it is easy to reach the disk quota by repeatedly uploading new versions
(esp. if they contain a lot of documentation), its usually best to reuse the same version.

E.g. using `1.2.3~nightly` for nightly builds preceding the `1.2.3` release.
Or `0.88-snapshot` for snapshot builds following the `0.88` release.

This way, only the latest snapshot build will be available via the package manager
(but this is usually OK for snapshot builds).

Most users will only see the last release of a given library.
If you last proper release was `1.2.3` and you use use `~` as the delimiter (`1.2.3~nightly`),
then only users who disable the "only show latest version of package" in the preferences will see the snapshot release.
OTOH, if you use `-` or `+` as the delimiter (`1.2.3-nightly`), then all users will get the snapshot release *by default*.

Which is more appropriate depends on your project:

- if the nightly builds are alpha or beta releases that might break anytime, then it's probably better to use `~`.
- if the project is stable and virtually only sees bugfixes but you do not want to do a full release for every minor fix,
  then it is probably better to use `+`.

