# -*- mode: python -*-

#-----------------------------------------------------------------------------
# Copyright (c) 2017, PyInstaller Development Team.
#
# Distributed under the terms of the GNU General Public License with exception
# for distributing bootloader.
#
# The full license is in the file COPYING.txt, distributed with this software.
#-----------------------------------------------------------------------------

# Hook for the elftools module: https://github.com/eliben/pyelftools

hiddenimports = ['elftools.elf', 'elftools.elf.elffile']
