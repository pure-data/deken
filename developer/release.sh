#!/bin/sh

## deken versioning scheme
# - we losely follow semver
# - releases should *always* have an even bugfix-number
# - during development, we use an odd bugfix-number

# files that contain the version number
# - ./developer/deken
# - ./deken-plugin.tcl
# - ./README.deken.pd
# - .git-ci/deken-test/README.deken.txt


version_script=".git-ci/git-version"

cd ${0%/*}/..

version=$1
version=${version#v}
if [ "x${version}" = "x" ]; then
 echo "usage: $0 <version>" 1>&2
 exit 1
fi

version_check() {
   local bugfix
   bugfix=$3
   if [ -n "${bugfix}" ]  && [ $((bugfix % 2)) -ne 0 ]; then
	return 1
   fi
   return 0
}

if git diff --name-only | sed -e 's|^|CHANGED: |' | tee /dev/stderr | grep . >/dev/null; then
  echo "the repository contains changes!" 1>&2
  echo "commit or stash them, before releasing." 1>&2
  exit 1
fi

if [ -x "${version_script}" ]; then
  echo "setting version to ${version}"
  ${version_script} "${version}"
else
  echo "version-script '${version_script}' missing"
  exit 1
fi


if version_check $(echo $version | sed -e 's|[.-]| |g'); then
echo "committing changes and tagging release" 1>&2
git commit \
	developer/deken deken-plugin.tcl \
	README.deken.pd .git-ci/deken-test/README.deken.txt \
	-m "Releasing v${version}" \
&& git tag -s -m "Released deken-v${version}" "v${version}"
else
echo "committing changes for development version" 1>&2
git commit \
	developer/deken deken-plugin.tcl \
	README.deken.pd .git-ci/deken-test/README.deken.txt \
	-m "Bump dev-version to v${version}"
fi
