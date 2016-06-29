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


class ObjectSearch:
    def __init__(self):
        # db: "objectname" -> [library,]
        self.db=dict()
        pass

    def refresh(self, filename):
        """add/update contents in 'filename'; if filename is missing, its content gets deleted"""
        try:
            with open(filename, "r") as f:
                data=read(filename)
            for line in data.split("\n"):
                obj, _ = split_unescape(line, ' ', maxsplit=1)
        except FileNotFoundError:
            for key in self.db:
                self.db[key].discard(filename)

    def search(self, needles=[]):
        pass

if '__main__' ==  __name__:
    #run()
    data=None
    with open("data/libraryfile.txt", "r") as f:
        data=f.read()
    if data:
        ls=LibrarySearch(data)
        for s in ls.search(["z"]):
            print(s)
