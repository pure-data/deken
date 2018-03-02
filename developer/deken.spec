# -*- mode: python -*-

block_cipher = None
datas = [('deken.hy', '.')]

versionfile = "DEKEN_VERSION"
try:
    import os
    import tempfile
    import subprocess
    version = subprocess.check_output(["./deken", "--version"]).strip()
    tmpdir = tempfile.TemporaryDirectory()
    versionfile = os.path.join(tmpdir.name, versionfile)
    with open(versionfile, 'wb') as f:
        f.write(version)
        datas += [(versionfile, '.')]
except Exception as e:
    print("OOPS: %s" % (e,))
    versionfile = None

a = Analysis(['pydeken.py'],
             pathex=['.'],
             binaries=[],
             datas=datas,
             hiddenimports=[],
             hookspath=['installer/'],
             runtime_hooks=[],
             excludes=[],
             win_no_prefer_redirects=False,
             win_private_assemblies=False,
             cipher=block_cipher)
pyz = PYZ(a.pure, a.zipped_data,
             cipher=block_cipher)
exe = EXE(pyz,
          a.scripts,
          a.binaries,
          a.zipfiles,
          a.datas,
          name='deken',
          debug=False,
          strip=False,
          upx=True,
          runtime_tmpdir=None,
          console=True )
