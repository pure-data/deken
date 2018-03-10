random notes on deken
=====================

# easywebdav (and easywebdav2)
To upload packages to puredata.info, we utilize the `easywebdav` python package.

## easywebdav (Py2; Debian packages)
Unfortunately this package seems to be somewhat unmaintained, and is currently
not ready for Python3 (although it works fine with Python2).

If you are running a Debian based Linux distribution and use the package
manager (apt) to satisfy the deken requirements, then easywebdav has already
been fixed for Python3.

If you are using `virtualenv` to provide the requirements (the deken-script
internally will setup a virtualenv environment), then you should either stay
with Python2 or switch to easywebdav2 (see below).

## easywebdav2 (Py2+Py3)

There is a fork named `easywebdav2` which runs on Py3 (and Py2), but (as of
version 1.3.0) unfortunately has another bug which breaks the `mkdirs` command on
the server.

The fix is simple (but requires patching of the package sources):

~~~diff
@@ -145,7 +145,7 @@ def mkdirs(self, path, **kwargs):
         try:
             for dir_ in dirs:
                 try:
-                    self.mkdir(dir, safe=True, **kwargs)
+                    self.mkdir(dir_, safe=True, **kwargs)
                 except Exception as e:
                     if e.actual_code == 409:
                         raise
~~~



# Windows Standalone Executable
you can build a standalone executable with the following steps:

~~~bash
$ cd deken/development/
$ pip install pyinstaller
$ pyinstaller deken.spec
~~~

This will give you something like `deken/development/dist/deken.exe`
(The standalone installer can be created on macOS and Linux as well)

When creating a standalone executable, an attempt is made to automatically fix
the 'easywebdav2' package.

# Recommended backend

You may see the error:

`No recommended backend was available. Install the keyrings.alt package if you want to use the non-recommended backends. See README.rst for details.`

This should be safe to ignore.
