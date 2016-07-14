# Import a standard function, and get the HTML request and response objects.
from Products.PythonScripts.standard import url_unquote

def getNameVersion(filename):
  filename = filename.split('-externals', 1)[0] .split('(')[0]
  pkgver = filename.split('-v')
  if len(pkgver) > 1:
    pkg = '-v'.join(pkgver[:-1])
    ver = pkgver[-1].strip('-').strip()
  else:
    pkg = pkgver[0]
    ver = ""
  return (pkg.strip('-').strip(), ver)


def showPackage(obj, url, filename):
  (name, version) = getNameVersion(filename)
  title = obj.Title().replace('\t', ' ')
  if (name not in title) or (version not in title):
    if version:
      title = "%s/%s (%s)" % (name, version, title)
    else:
      title = "%s (%s)" % (name, title)
  date = obj.Date().replace('\t', ' ').strip()
  owner = obj.owner_info()['id'].replace('\t', ' ')
  return ("%s\t%s\t%s\t%s" % (url, title, owner, date))

mytypes = ('IAEMFile', 'PSCFile')
suffixes = ['zip', 'tgz', 'tar.gz']

for t in mytypes:
  results = context.portal_catalog(portal_type=t)
  for i in results:
    url = url_unquote(i.getURL())
    FileName = url.split('/')[-1]
    filename=FileName.lower()
    match = False
    for suffix in suffixes:
      if filename.endswith("-externals.%s" % (suffix,)):
        match = True
        break
    if not (match or filename.endswith("-objects.txt")):
      continue
    print("%s" % showPackage(i.getObject(), url, FileName))

# make sure there is *some* content in the page
if not printed:
  print("")

return printed
