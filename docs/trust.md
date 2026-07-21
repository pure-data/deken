Trusting packages
=================

The `deken-plugin` will help you find and install Pd-libraries.
However, it does not verify whether a given package is downloaded from a trusted source or not.

As of now, the default package source is [http://puredata.info](http://puredata.info).
Anybody who has an account on that website (currently that's a few thousand people) can upload packages,
that the `deken-plugin` will happily find and install for you.

In order to make these packages more trustworthy, we ask people to sign their uploaded packages with the GPG-key.
Unfortunately the deken-plugin does not check these signatures yet.
If you are concerned about the authenticity of a given download, you can check the GPG-signature manually,
by following these steps:

- Navigate to `Help -> Find Packages` and search for an external
- Right-Click one of the search results
- Select "Copy package URL" to copy the link to the downloadable file to your clipboard
- Download the package from the copied link
- Back in the deken search results, select "Copy OpenGPG signature URL"
- Download the GPG-signature from the copied link to the same location as the package
- Run `gpg --verify` on the downloaded file

If the signature is correct, you can decide yourself whether you actually trust the person who signed:
- Do you trust the signature to be owned by the person?
- Do you know the person?
- Do you trust them enough to let them install arbitrary software on your machine?
