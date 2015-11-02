A minimal package management system for Pure Data externals.

![Animated GIF demonstration of the Deken plugin user interface](https://raw.githubusercontent.com/pure-data/deken/master/deken.gif)

Packages are stored on <http://puredata.info/> and can be installed using the `Help -> Find Packages` menu after installing the [TCL plugin](https://raw.githubusercontent.com/pure-data/deken/master/deken-plugin.tcl).

## Download ##

Click to download [deken-plugin.tcl](https://raw.githubusercontent.com/pure-data/deken/master/deken-plugin.tcl) and save it to your Pd folder:

 * Linux = `~/pd-externals/deken-plugin/`
 * OSX = `~/Library/Pd/deken-plugin/`
 * Windows = `%AppData%\Pd\deken-plugin\`

Then select `Help -> Find Packages` and type the name of the external you would like to search for.

## Trusting packages

The `deken-plugin` will help you find and install Pd-libraries.
However, it does not verify whether a given package is downloaded from a trusted source or not.

As of now, the default package source is http://puredata.info.
Anybody who has an account on that website (currently that's a few thousand people) can upload packages,
that the `deken-plugin` will happily find and install for you.

In order to make these packages more trustworthy, we ask people to sign their uploaded packages with the GPG-key.
Unfortunately the deken-plugin does not check these signatures yet.
If you are concerned about the authenticity of a given download, you can check the GPG-signature manually,
by following these steps:

- Navigate to `Help -> Find Packages` and search for an external
- Hover your mouse over one of the search results
- At the bottom of the search window, a download link will appear
- Remember this link! (e.g. http://puredata.info/Members/the-bfg/software/frobscottle-1.10-externals.zip)
- Append `.asc` to the link (e.g. http://puredata.info/Members/the-bfg/software/frobscottle-1.10-externals.zip.asc)
- Download the GPG-signature from the link (besides the downloaded archive)
- Run `gpg --verify` on the downloaded file

If the signature is correct, you can decide yourself whether you actually trust the person who signed:
- Do you trust the signature to be owned by the person?
- Do you know the person?
- Do you trust them enough to let them install arbitrary software on your machine?


# Developers #

`deken` comes with a tool to package and  upload your own library builds.
See [developer/README.md](./developer/README.md) for more information.
