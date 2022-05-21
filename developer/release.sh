#!/bin/sh

# files that contain the version number
# - ./developer/deken
# - ./deken-plugin.tcl
# - ./README.deken.pd
# - .git-ci/deken-test/README.deken.txt

cd ${0%/*}/..

version=$1
version=${version#v}
if [ "x${version}" = "x" ]; then
 echo "usage: $0 <version>" 1>&2
 exit 1
fi

if git diff --name-only | sed -e 's|^|CHANGED: |' | tee /dev/stderr | grep . >/dev/null; then
  echo "the repository contains changes!" 1>&2
  echo "commit or stash them, before releasing." 1>&2
  exit 1
fi

echo "setting version in"
echo "- developer/deken"
sed \
  -e "s|^export DEKEN_VERSION=.*|export DEKEN_VERSION=\"${version}\"|" \
  -i developer/deken

echo "- deken-plugin.tcl"
sed \
  -e "s|^\(if *{ *\[.*::deken::versioncheck\) \([^]]*\)]|\1 ${version}]|" \
  -i deken-plugin.tcl

echo "- README.deken.pd"
sed \
  -e "s|\(#X text .* version: \)v[^ ]*;|\1v${version}|" \
  -i README.deken.pd

echo "- .git-ci/deken-test/README.deken.txt"
sed \
  -e "s|^\(version:\) [^ ]*$|\1 ${version}|" \
  -i .git-ci/deken-test/README.deken.txt


echo "committing changes and tagging release"
git commit \
	developer/deken deken-plugin.tcl \
	README.deken.pd .git-ci/deken-test/README.deken.txt \
	-m "Releasing v${version}" \
&& git tag -s -m "Released deken-v${version}" "v${version}"
