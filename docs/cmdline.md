Deken Commandline Tool
======================

You can use the [`deken` command line
tool](https://raw.githubusercontent.com/pure-data/deken/main/developer/deken)
to create archives with proper names (that includes the target architecture(s) of the package),
e.g. example `freeverb~[v0.1](Linux-amd64-64).dek`,
and the accompanying files (object lists, checksums, signatures).

## Usage



### Show help

To get a basic overview, just call it with `-h` (or `--help`):

```sh
deken -h
```


`deken` uses a number of subcommands (like `deken package` or `deken upload`),
each of which accept a number of flags to tune the behaviour to your needs.

To get help for a specific subcommand, pass `-h` (or `--help`) to the subcommand:

```sh
deken package --help
```

### Upgrade

To run a self-upgrade (not supported on all platforms), simply do:
```sh
deken upgrade
```


### Searching and installing packages
While `deken` is primarily targeted at creating and uploading packages (see below),
you can also use it to install packages from the cmdline.

To search for available packages (for your current architecture) use:

```sh
deken find my_external
```

You can override the architecture by specifying it on the cmdline,
and search for multiple search terms at once:
```sh
deken find --architecture Linux-amd64-64 my_external superlib
```

The search results (if any), will include a download link.

You can download a package directly into a directory of your choice with:
```sh
deken download --output-dir ~/Downloads superlib
```

This will not only download the package, but also ensure that the
checksum and signature (if found on the server) are valid.

If you want to install (download and extract) a package:
```sh
deken install superlib
```


### Create and Upload a package

The main objective of the `deken` cmdline tool, however,
is to help in publishing packages.

Let's assume that you have a directory containing your compiled externals object files
called `my_external/`.


To create a package from this directory that can later be uploaded just run:
```sh
deken package --version 0.1 my_external/
```

This command will create the following files:
- `my_external[v0.1](Linux-amd64-64).dek` -- the main package file (contains an archive of the directory)
- `my_external[v0.1](Linux-amd64-64).dek.txt` -- contains a list of Pd objects found in the package
- `my_external[v0.1](Linux-amd64-64).dek.sha256` -- contains a checksum of the main package file
- `my_external[v0.1](Linux-amd64-64).dek.asc` -- a detached OpenPGP signature (optional)

As you can see, the base package filename encodes the library name (`my_external`),
the version (`v0.1` as passed with the `--version` flag) and
the architectures for which this package provides binaries (here `Linux-amd64-64`,
detected automatically from the files within the archive).


You can then upload the package to your account on <https://puredata.info/> where the search plugin
can find it:

```sh
deken package -v 0.1 my_external/
deken upload "my_external[v0.1](Linux-amd64-64).dek"
```

This will upload the package file itself (`*.dek`), but also the auxiliary files
(`*.dek.txt`, `*.dek.sha256`, `*.dek.asc`).


To simplify things, you can also just call `upload` directly on a directory,
and it will call the `package` command for you in a single step:

```sh
deken upload -v 0.1 my_external/
```


#### Creating/Uploading packages on a different machine
`deken` inspects the files in the directory to determine the target platform(s)
(rather than just checking on which system you are currently running).
Therefore, if it is not feasible to install `deken` on the machine used for
building your Pd library, you can run `deken` on another machine,

Example: You build the "my_external" library on OSX-10.5, but (due to OSX-10.5
not being supported by Apple anymore) you haven't installed `deken` there.
So you simply transfer the "my_external" directory to your Linux machine, where
you run `deken package --version 3.14 my_external` and it will magically create the
`my_external[v3.14](Darwin-i386-32)(Darwin-amd64-32)-externals.tgz` file for
you, ready to be uploaded.




### Usage with docker
To use a dockerized `deken`, you need to make the package directory available
within the container (the default working directory inside the container is `/deken`).
To get the permissions right, you will probably want to run the job inside
the container as your user (on the host).

This means, that you typically will prefix all calls to deken with the following

```sh
docker run --rm -ti --user $(id -u) --volume $(pwd):/deken registry.git.iem.at/pd/deken \
```

This will run the container as the current user,
and mount the current working directory as `/deken`.
It will also completely remove the container after it has finished.


#### Create a package

```sh
$ ls -d deken-test*
deken-test/

$ docker run --rm -ti                      \
    --user $(id -u) --volume $(pwd):/deken \
    registry.git.iem.at/pd/deken           \
    deken package --version 1.2.3 deken-test

$ ls -d deken-test*
deken-test/
'deken-test[v1.2.3].dek'
'deken-test[v1.2.3].dek.sha256'
$
```


#### Upload a package

```sh
docker run --rm -ti                        \
    --user $(id -u) --volume $(pwd):/deken \
    --env DEKEN_USERNAME=mydekuser         \
    registry.git.iem.at/pd/deken           \
    deken upload *.dek
```

#### GPG-signing with Docker


Within the container, `deken` will not attempt to GPG-sign your packages by default.
If your container has access to your GPG keys, you can enable signing by passing the `--sign-gpg` flag to `package` (resp. `upload`).


The following assumes that you have a properly configured GPG setup in your `~/.gnupg`, and `gpg-agent` is running on your host machine:

```sh
docker run --rm -ti                        \
    --user $(id -u) --volume $(pwd):/deken \
    --volume ${HOME}/.gnupg/:/.gnupg/:ro --volume /run/user/$(id -u)/:/run/user/$(id -u)/:ro \
    registry.git.iem.at/pd/deken           \
    deken package --sign-gpg --version 1.2.3 deken-test
```


## Installation

### Prebuilt Binaries

If you don't want to install Python3, bash (MSYS),... as described below, you can also download
self-contained binaries from our Continuous Integration setup:

- [Windows 64bit](https://git.iem.at/pd/deken/-/jobs/artifacts/main/download?job=windows)
- [macOS 64bit](https://git.iem.at/pd/deken/-/jobs/artifacts/main/download?job=osx)

If they don't work for you, you might want to check the [releases page](https://github.com/pure-data/deken/releases)
for downloads that have been tested by humans.

These builds are snapshots of the latest stable branch of `deken`.

On *Debian* and derivatives (like *Ubuntu*), `deken` is also readily available via `apt`:

```sh
apt-get install deken
```

### Docker containers

[docker](https://hub.docker.com/) is all the rage these days, so naturally there is a docker image for `deken` as well.

Get the latest and greatest release:

```sh
docker pull registry.git.iem.at/pd/deken
```




### Manual bootstrap

For manually installation of `deken` from the sources, just download the main script
and run it locally.
It will fetch and install all the dependencies (except for those listed under [Prerequisites](#prerequisites))

```command
$ mkdir -p ~/bin/
$ curl https://raw.githubusercontent.com/pure-data/deken/main/developer/deken > ~/bin/deken
$ chmod 755 ~/bin/deken
$ deken
This is your first time running deken on this machine.
I'm going to install myself and my dependencies into ~/.deken now.
Feel free to ctrl-C now if you don't want to do this.
...
```

If you get an error like

> -bash: deken: command not found

then make sure that [`~/bin` is in your `PATH`](https://apple.stackexchange.com/a/99838).


To update deken to the latest and greatest, run
```sh
deken update --self
```

#### Prerequisites

`deken` requires Python3 to be installed on your computer (and available from
the cmdline). You can test whether python3 is installed, by opening a terminal
and running `python3 --version`.

For installing (and updating) `deken`, you will also need `curl` (or `wget`)
for downloading from the cmdline.


##### macOS
On macOS, you can install missing dependencies with [brew](https://brew.sh/).
Once you have installed `brew`, run the following in your terminal:

```sh
brew install python3
```

##### Windows

On Windows you might need to install [MSYS2/MinGW64](https://www.msys2.org/),
which comes with `pacman` as a package manager to install missing dependencies.
Once you have installed `pacman`, run the following in your terminal:

```sh
pacman -Suy python3
```


### Development versions

If you are feeling a bot more adventurous,
you can also grab the latest development snapshot from the `develop` branch.


#### Prebuilt Testing Binaries

For the adventurous, you could also try the latest development snapshots:

- [Windows 64bit](https://git.iem.at/pd/deken/-/jobs/artifacts/devel/download?job=windows)
- [macOS 64bit](https://git.iem.at/pd/deken/-/jobs/artifacts/devel/download?job=osx)

#### Docker Testing Containers

```sh
docker pull registry.git.iem.at/pd/deken:devel
```

#### Manual bootstrap

You can cross-grade an existing manually bootstrapped `deken` to the current development version
by setting `DEKEN_GIT_BRANCH` to `devel` and then self-upgrade the script.
```sh
export DEKEN_GIT_BRANCH=devel
deken update --self
```
