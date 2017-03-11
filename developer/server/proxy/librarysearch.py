#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# LibrarySearch - search for Pd libraries
#
# Copyright © 2016, IOhannes m zmölnig, forum::für::umläute
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU Affero General Public License as
#  published by the Free Software Foundation, either version 3 of the
#  License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Affero General Public License for more details.
#
#  You should have received a copy of the GNU Affero General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

##### input data
# libraryfile: lists all available libraries
#    this is a dump of what puredata.info currently reports
# format: <name/description>\t<url>\t<uploader>\t<date>
#
# $ cat libraryfile.txt
# Gem/0.93.3 (deken installable file for W32 32bit/i386))	http://puredata.info/downloads/gem/releases/0.93.3/Gem-v0.93.3-(Windows-i386-32)-externals.zip	zmoelnig	2016-05-20 22:10:28
# patch2svg-plugin-v0.1--externals.zip	http://puredata.info/downloads/patch2svg-plugin/releases/0.1/patch2svg-plugin-v0.1--externals.zip	zmoelnig	2016-03-22 16:29:25
#

from utilities import getNameVersion

class LibrarySearch:
    def __init__(self, data=None):
        # libs: 'package' -> [package/version,]
        # db: 'package/version' -> [responsestring,]
        self.libs=dict()
        self.db=dict()
        if data:
            self.refresh(data)
    def refresh(self, data):
        self.libs=dict()
        self.db=dict()
        for line in data.split("\n"):
            if not line:
                continue
            descr, url, _ = line.split("\t", 2)
            pkg, ver = getNameVersion(url.split("/")[-1])
            pkgver=pkg
            if ver:
                pkgver=("%s/%s" % (pkg, ver))
            if pkg not in self.libs:
                self.libs[pkg]=[]
            if pkgver not in self.db:
                self.db[pkgver]=[]
            self.libs[pkg]+=[pkgver]
            self.db[pkgver]+=[line]
    def search(self, needles=[]):
        keys=set()
        for k in self.libs:
            for n in needles:
                if n in k:
                    for l in self.libs[k]:
                        keys.add(l)
        res=[]
        for k in sorted(keys):
            res+=self.db[k]
        return res

if '__main__' ==  __name__:
    data=None
    with open("data/libraryfile.txt", "r") as f:
        data=f.read()
    if data:
        ls=LibrarySearch(data)
        needles=["zexy", "z", "maxlib"]
        for needle in needles:
            print("searching for %s" % (needle))
            for s in ls.search([needle]):
                print("> %s" % (s))
            print("---------------------------")
        print("searching for %s" % (needles))
        for s in ls.search(needles):
            print("> %s" % (s))
