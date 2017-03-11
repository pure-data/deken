#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# utilities - helper functions for DekenProxy
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


# http://stackoverflow.com/questions/18092354
def split_unescape(s, delim, escape='\\', unescape=True, maxsplit=-1):
    """
    >>> split_unescape('foo,bar', ',')
    ['foo', 'bar']
    >>> split_unescape('foo$,bar', ',', '$')
    ['foo,bar']
    >>> split_unescape('foo$$,bar', ',', '$', unescape=True)
    ['foo$', 'bar']
    >>> split_unescape('foo$$,bar', ',', '$', unescape=False)
    ['foo$$', 'bar']
    >>> split_unescape('foo$', ',', '$', unescape=True)
    ['foo$']
    """
    ret = []
    current = []
    count = 0
    itr = iter(s)
    if not maxsplit:
        return [s]
    for ch in itr:
        if ch == escape:
            try:
                # skip the next character; it has been escaped!
                if not unescape:
                    current.append(escape)
                current.append(next(itr))
            except StopIteration:
                if unescape:
                    current.append(escape)
        elif ch == delim:
            # split! (add current to the list and reset it)
            ret.append(''.join(current))
            current = []
            count = count + 1
            if maxsplit>0 and count>=maxsplit:
                ret.append(''.join(itr))
                return ret
        else:
            current.append(ch)
    ret.append(''.join(current))
    return ret


def getNameVersion(filename, suffix="-externals"):
    filename = filename.split(suffix, 1)[0] .split('(')[0]
    pkgver = filename.split('-v')
    if len(pkgver) > 1:
        pkg = '-v'.join(pkgver[:-1])
        ver = pkgver[-1].strip('-').strip()
    else:
        pkg = pkgver[0]
        ver = ""
    return (pkg.strip('-').strip(), ver)


if '__main__' ==  __name__:
    print("expected %s, got %s" % (["foo", "bar", "baz"], split_unescape("foo bar baz", ' ')))
    print("expected %s, got %s" % (["foo", "bar baz"], split_unescape("foo bar baz", ' ', maxsplit=1)))
    print("expected %s, got %s" % (["foo bar", "baz"], split_unescape("foo\ bar baz", ' ', maxsplit=1)))

    def test_namever(expect, name, suffix=None):
        if suffix is None:
            x=getNameVersion(name)
        else:
            x=getNameVersion(name, suffix)
        print("expected %s, got %s [%s]" % (expect, x, name))
    test_namever(["patch2svg-plugin", "0.1"], "patch2svg-plugin-v0.1--externals.zip")
    test_namever(["zexy", "2.2.5-2"], "zexy-v2.2.5-2-(Linux-amd64-64)-externals.tgz")
    test_namever(["helloworld"], "helloworld(Linux-amd64-64)-externals.zip")
