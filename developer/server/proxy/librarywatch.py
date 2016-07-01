#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# LibraryWatch - watch library backend data and update the LibrarySearch if needed
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


## LATER use inotify to watch the library file
class LibraryWatch:
    def __init__(self, searcher, config):
        # searcher: instance of LibrarySearch to be updated when something changes
        # config: where to look for configuration
        self.searcher = searcher
        for filename in [config['location']]:
            with open(filename, 'r') as f:
                searcher.refresh(f.read())

def getLibraryWatch(searcher, config):
    ## factory to get a LibraryWatch for the given 'config'
    return LibraryWatch(searcher, config)

if '__main__' ==  __name__:
    print("implement LibraryWatch tests")
