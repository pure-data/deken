# Import a standard function, and get the HTML request and response objects.
from Products.PythonScripts.standard import html_quote
from Products.PythonScripts.standard import url_unquote
request = container.REQUEST
RESPONSE = request.RESPONSE

qs = request['QUERY_STRING']

args = {}
if qs:
  for arg in qs.split('&'):
    try:
      key, val = arg.split('=', 1)
    except ValueError:
      key = arg
      val = ''
    if key in args:
      args[key].append(val)
    else:
      args[key] = [val]


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
  date = obj.Date().replace('\t', ' ')
  owner = obj.owner_info()['id'].replace('\t', ' ')
  print("%s\t%s\t%s\t%s" % (title, url, owner, date))
  return printed

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
    if not match:
      continue
    if 'name' in args:
      match = False
      for name in args['name']:
        if name in filename:
          match = True
          break
      if not match:
        continue
    print("%s" % showPackage(i.getObject(), url, FileName))

return printed
