#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is copyrighted by Chris McCormick and others.  The following
# terms (the "Standard Improved BSD License") apply to all files associated
# with the software unless explicitly disclaimed in individual files:
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above
#    copyright notice, this list of conditions and the following
#    disclaimer in the documentation and/or other materials provided
#    with the distribution.
# 3. The name of the author may not be used to endorse or promote
#    products derived from this software without specific prior
#    written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR
# BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
# THE POSSIBILITY OF SUCH DAMAGE.

# this is a thin wrapper around deken.hy, to launch it without a
# HY executable (or file associations)

try:
    import argparse
    import copy
    import getpass
    import os
    import re
    import sys
    import tarfile
    import zipfile

    import datetime

    import elftools
    import macholib
    import pefile

    import gnupg
    import hashlib

    import requests

    import subprocess

except ImportError:
    pass

# 'keyring' is disabled here as it makes problems with pyinstaller
try:
    import keyring.backends.Windows
    import keyring

    pass
except ImportError:
    pass

try:
    import webbrowser
except ImportError:
    pass

try:
    import easywebdav2
except ImportError:
    try:
        import easywebdav
    except ImportError:
        pass

try:
    import ConfigParser
    import StringIO
    import urlparse
except ImportError:
    import configparser
    import io
    import urllib.parse


import hy
import deken

## on macOS, pyinstaller requires more help...
try:
    import runpy
    import hy.core.bootstrap
    import hy.contrib.loop
except ImportError:
    pass


def askpass(prompt="Password: ", fallback=None):
    try:
        subprocess.call(["stty", "-echo"])
    except:
        if fallback:
            return fallback(prompt)
        return None
    sys.stdout.write(prompt)
    sys.stdout.flush()
    password = None
    try:
        try:
            password = raw_input()
        except NameError:
            password = input()
    except:
        pass
    sys.stdout.write("\n")
    sys.stdout.flush()
    subprocess.call(["stty", "echo"])
    return password


def resource_path(relative_path):
    """Get absolute path to resource, works for dev and for PyInstaller"""
    try:
        # PyInstaller creates a temp folder and stores path in _MEIPASS
        base_path = sys._MEIPASS
    except Exception:
        base_path = os.path.abspath(".")
    return os.path.join(base_path, relative_path)


if __name__ == "__main__":
    try:
        with open(resource_path("DEKEN_VERSION"), "r") as f:
            version = f.read().strip()
        deken.version = version
    except OSError:
        pass
    except IOError:
        pass
    deken_askpass = deken.askpass
    deken.askpass = lambda prompt: askpass(prompt, deken_askpass)
    deken.main()
