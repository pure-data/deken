#!/bin/sh

cd ${0%/*}/..

version=$1
version=${version#v}
if [ "x${version}" = "x" ]; then
 echo "usage: $0 <version>"
fi

sed \
  -e "s|^export DEKEN_VERSION=.*|export DEKEN_VERSION=\"${version}\"|" \
  -i developer/deken

sed \
  -e "s|^\(if *{ *\[.*::deken::versioncheck\) \([^]]*\)]|\1 ${version}]|" \
  -i deken-plugin.tcl


git commit developer/deken deken-plugin.tcl -m "Releasing v${version}" \
&& git tag -s -m "Released deken-v${version}" "v${version}"
