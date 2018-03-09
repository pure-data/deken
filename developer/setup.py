#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys
import os
from setuptools import setup


def check_pyversions(versions):
    """checks if the python-version is within the list of versions

to check is we are running py2 or py3:
    check_pyversions(((2,), (3,)))

to check if we are running either py2 or py3.4.2 (but no other py3 version)
    check_pyversions(((2,), (3,4,2)))
"""
    for v in versions:
        if all([x == y for x, y in zip(v, sys.version_info)]):
            return True
    return False


# ModuleFinder can't handle runtime changes to __path__, but win32com uses them
try:
    # py2exe 0.6.4 introduced a replacement modulefinder.
    # This means we have to add package paths there, not to the built-in
    # one.  If this new modulefinder gets integrated into Python, then
    # we might be able to revert this some day.
    # if this doesn't work, try import modulefinder
    try:
        import py2exe.mf as modulefinder
    except ImportError:
        import modulefinder
    import win32com
    for p in win32com.__path__[1:]:
        modulefinder.AddPackagePath("win32com", p)
    for extra in ["win32com.shell"]:  # ,"win32com.mapi"
        __import__(extra)
        m = sys.modules[extra]
        for p in m.__path__[1:]:
            modulefinder.AddPackagePath(extra, p)
    import py2exe
except ImportError:
    # no build path setup, no worries.
    pass


# This is a list of files to install, and where
# (relative to the 'root' dir, where setup.py is)
# You could be more specific.
files = ["pydeken.py",]
data_files = ["deken.hy",]
setup_requires = []
dist_dir = ""
dist_file = None

options = {}
setupargs = {
    'name': "deken",
    'version': "0.2.4",
    'description': """Pure Data externals wrangler""",
    'author': "Chris McCormick, IOhannes m zmölnig et al.",
    'author_email': "pd-list@lists.puredata.info",
    'url': "https://git.iem.at/pure-data/deken",
    # Name the folder where your packages live:
    # (If you have other packages (dirs) or modules (py files) then
    # put them into the package directory - they will be found
    # recursively.)
    # 'packages': ['deken', ],
    # This dict maps the package name =to=> directories
    # It says, package *needs* these files.
    'package_data': {'deken': files},
    'data_files': data_files,

    'install_requires': [
        # 'PySide',
        ],
    'scripts': ["deken", "pydeken.py"],
    'long_description': """
a tool to create and upload dek packages to puredata.info,
so they can be installed by Pd's built-in package manager
""",
    #
    # https://pypi.python.org/pypi?%3Aaction=list_classifiers
    'classifiers': [
        "Development Status :: 3 - Alpha",
        "Environment :: Console",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: BSD 3 clause",
        "Natural Language :: English",
        #"Topic :: Internet :: WWW/HTTP :: Site Management",
        ],
    'options': options,
    'setup_requires': setup_requires,
    }

if 'py2exe' in sys.argv:
    dist_dir = "%s-%s" % (setupargs['name'], setupargs['version'])
    dist_file = "%s.exe-%s.zip" % (setupargs['name'], setupargs['version'])
    setup_requires += ['py2exe', ]

    def getMSVCfiles():
        # urgh, find the msvcrt redistributable DLLs
        # either it's in the MSVC90 application folder
        # or in some winsxs folder
        from glob import glob
        program_path = os.path.expandvars('%ProgramFiles%')
        winsxs_path = os.path.expandvars('%SystemRoot%\WinSXS')
        msvcrt_paths = [
            (r'%s\Microsoft Visual Studio 9.0\VC\redist\x86\Microsoft.VC90.CRT'
             % program_path)]

        if check_pyversions(((2, 7), )):
            # python2.7 seems to be built against VC90 (9.0.21022),
            # so let's try that
            msvcrt_paths += glob(
                r'%s\x86_microsoft.vc90.crt_*_9.0.21022.8_*_*' "\\" % winsxs_path
                )
            for p in msvcrt_paths:
                if os.path.exists(os.path.join(p, 'msvcp90.dll')):
                    sys.path.append(p)
                    f = glob(r'%s\*.*' % p)
                    if f:
                        return [("Microsoft.VC90.CRT", f)]
                    return None

        return None

    def getRequestsCerts():
        import requests.certs
        f = requests.certs.where()
        if f:
            return [(".", [f])]

    data_files += getMSVCfiles() or []
    data_files += getRequestsCerts() or []
    print(data_files)

    setupargs['windows'] = [{
        # 'icon_resources': [(1, "media\deken.ico")],
        'script': 'pydeken.py',
        }]
    setupargs['zipfile'] = None

    options['py2exe'] = {
        'includes': ['deken.hy',],
        'packages': ['requests', ],
        'bundle_files': 3,
        'dist_dir': os.path.join("dist", dist_dir),
        }

if 'py2app' in sys.argv:
    dist_dir = "%s.app" % (setupargs['name'], )
    dist_file = "%s.app-%s.zip" % (setupargs['name'], setupargs['version'])
    setup_requires += ['py2app', ]
    setupargs['app'] = ['pydeken.py', ]
    options['py2app'] = {
        'packages': ['requests', ],
        }

if dist_dir:
    try:
        os.makedirs(os.path.join("dist", dist_dir))
    except FileExistsError:
        pass

setup(**setupargs)

if dist_dir and dist_file:
    import zipfile
    def zipdir(path, ziph):
        # ziph is zipfile handle
        for root, dirs, files in os.walk(path):
            for f in files:
                fullname = os.path.join(root, f)
                archname = os.path.relpath(
                    fullname,
                    os.path.join(path, ".."))
                if ziph:
                    ziph.write(fullname, archname)
                else:
                    print("%s -> %s" % (fullname, archname))
    with zipfile.ZipFile(dist_file, 'w', compression=zipfile.ZIP_DEFLATED) as myzip:
        zipdir(os.path.join("dist", dist_dir), myzip)
