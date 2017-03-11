#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# ObjectSearch - search for packages containing an object
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
#
# lib2obj-file: lists all objects in a library
#               library-name and version are implicitly given via the filename
# <library>-v<version>-objects.txt
#
# $ cat tof-v0.2.0-objects.txt
# crossfade~ cross fade between two signals
# getdollarzero get $0 for parent patch
# path get path of running patch
# $
#

from utilities import split_unescape, getNameVersion

class ObjectSearch:
    def __init__(self):
        # db: "objectname" -> [library,]
        self.db=dict()
        pass

    def refresh(self, filename):
        """add/update contents in 'filename'; if filename is missing, its content gets deleted"""
        try:
            with open(filename, "r") as f:
                data=f.read()
            pkg,ver = getNameVersion(filename.split("/")[-1], "-objects")
            if ver:
                pkg="%s/%s" % (pkg,ver)
            for line in data.split("\n"):
                if not line: continue
                try:
                    obj = split_unescape(line, ' ', maxsplit=1)[0]
                    if obj not in self.db:
                        self.db[obj]=[]
                    self.db[obj]+=[pkg]
                except IndexError:
                    pass
        except FileNotFoundError:
            for key in self.db:
                self.db[key].discard(filename)

    def search(self, needles=[]):
        keys=set()
        for k in self.db:
            for n in needles:
                if n in k:
                    keys.add(k)
        res=[]
        for k in sorted(keys):
            res+=self.db[k]
        return res

if '__main__' ==  __name__:
    data=None
    os=ObjectSearch()
    def test_search(needles):
        if len(needles)>1:
            for needle in needles:
                print("search for %s::" % (needle))
                for res in os.search([needle]):
                    print("%s" % (res))
        print("search for %s::" % (needles))
        for res in os.search(needles):
            print("%s" % (res))

    os.refresh("data/iemnet-v0.2.1-objects.txt")
    test_search(["udpclient", "phasorshot~", "z~"])
    os.refresh("data/tof-v0.2.0-objects.txt")
    test_search(["udpclient", "phasorshot~", "z~"])
