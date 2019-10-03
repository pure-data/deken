# -*- mode: python -*-
import os

block_cipher = None
datas = [('deken.hy', '.')]

versionfile = "DEKEN_VERSION"
try:
    import tempfile
    tmpdir = tempfile.mkdtemp()
    version = os.environ['DEKEN_VERSION']
    versionfile = os.path.join(tmpdir, versionfile)
    with open(versionfile, 'w') as f:
        f.write(version)
        datas += [(versionfile, '.')]
except Exception as e:
    print("OOPS: %s" % (e,))
    versionfile = None

def easywebdav2_patch1():
    try:
        import easywebdav2
        print("trying to fix 'easywebdav2'")
        A="""            for dir_ in dirs:\n                try:\n                    self.mkdir(dir, safe=True, **kwargs)"""
        B="""            for dir_ in dirs:\n                try:\n                    self.mkdir(dir_, safe=True, **kwargs)"""

        filename = os.path.join(os.path.dirname(easywebdav2.__file__), 'client.py')
        print(filename)
        with open(filename, "r") as f:
            data = f.read()
        data = data.replace(A, B)
        with open(filename, "w") as f:
            f.write(data)
    except Exception as e:
        print("FAILED to patch 'easywebdav2', continuing anyhow...\n %s" % (e))
easywebdav2_patch1()

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

try:
  import shutil
  shutil.rmtree(tmpdir)
except Exception as e:
  print("OOPS: %s" % (e,))
print("BYE.")
