#!/usr/bin/env python3

import re
import fnmatch
import itertools

aptcache = None


class EmptyVersion:
    """helper class that provides an empty versions member"""

    def __init__(self, versions=[]):
        self.versions = versions


def parseArgs():
    import argparse

    parser = argparse.ArgumentParser()

    p = parser.add_argument_group(
        title="constraints",
    )

    p.add_argument(
        "--os",
        default="Linux",
        choices=["Linux"],
        help="target operating system [DEFAULT: %(default)r]",
    )
    p.add_argument(
        "--architecture",
        default=None,
        help="target CPU architecture [DEFAULT: 'native']",
    )
    p.add_argument(
        "--floatsize",
        type=int,
        default=32,
        help="target floatsize [DEFAULT: %(default)s}]",
    )

    p = parser.add_argument_group(
        title="API",
    )
    p.add_argument(
        "--api",
        type=int,
        choices=[
            0,
            1,
        ],
        required=True,
        help="Output format version (0=test; 1=current)",
    )

    parser.add_argument(
        "pkg",
        nargs="*",
        help="package(s) to search for",
    )

    args = parser.parse_args()

    return args


def initializeAptCache():
    import apt

    global aptcache
    aptcache = apt.Cache()


def stripSuffix(s, suffix):
    if s.startswith(suffix):
        return s[len(suffix) :]
    return s


def hasDependency(versioned_pkg, dependencies: list) -> bool:
    """returns True iff <versioned_pkg> (apt.package.Version) depends
    on any package in <dependencies> (list[str]);
    otherwise returns False"""
    for d in versioned_pkg.dependencies:
        for bd in d:
            if bd.name in dependencies:
                return True
    return False


def getPackages(pkgs, arch=None, floatsize=32):
    pd32deps = {"puredata-core", "puredata", "puredata-gui", "pd"}
    pd64deps = {"puredata64-core", "puredata64", "puredata-gui", "pd64"}
    if floatsize == 64:
        pddeps = pd64deps
    else:
        pddeps = pd32deps

    if pkgs == ["*"]:
        pkgs = []

    pkgmatch = re.compile(
        "(pd-|pd64-)?(" + "|".join(fnmatch.translate(p) for p in pkgs) + ")"
    ).match

    packages = {}
    for p in aptcache:
        # filter out known non-externals
        if p.shortname.startswith("puredata"):
            continue
        # filter out unwanted architectures
        if arch and p.architecture() != arch:
            continue
        for v in p.versions:
            if pkgs:
                names = [p.shortname] + v.provides
                matches = [
                    matchedname
                    for name in {*names}
                    for matchedname in [pkgmatch(name)]
                    if matchedname
                ]
                if not matches:
                    continue
            else:
                # all externals
                matches = [p.shortname, None, None]
                if p.shortname.startswith("pd-"):
                    matches[2] = p.shortname[3:]
                elif p.shortname.startswith("pd64-"):
                    matches[2] = p.shortname[5:]
                matches = [matches]

            # we only take packages that depend on Pd
            if not hasDependency(v, pddeps):
                continue
            for m in matches:
                for n in {m[0], m[2]}:
                    npkgs = packages.get(n) or set()
                    npkgs.add(v)
                    packages[n] = npkgs
    return itertools.chain(*packages.values())


def getOrigin(
    versioned_pkg,
    fallback_origin="apt",
    fallback_date=None,
    trusted="",
    untrusted="?",
):
    """get the (one) package origin as a tuple of repository & archive,
    e.g. ("Debian", "bookworm/main")
    if the repository is trusted, the <trusted> string is appended, otherwise the <untrusted>.
    prefer trusted sources over untrusted.
    """
    origins = [o for o in versioned_pkg.origins if o.trusted]
    trust = trusted
    if not origins:
        origins = versioned_pkg.origins
        trust = untrusted

    if not origins:
        return (fallback_origin, fallback_date, None)

    origin = None
    codename = None
    component = None
    for o in origins:
        if all((origin, codename, component)):
            break
        try:
            origin = origin or o.label or o.origin or fallback_uploader
        except AttributeError:
            pass
        try:
            codename = codename or o.codename or o.archive
        except AttributeError:
            pass
        try:
            component = component or o.component
        except AttributeError:
            pass

    origin = origin or fallback_origin
    if codename or component:
        if not component:
            codename_component = codename
        else:
            codename_component = f"{codename or '???'}/{component}"
    else:
        codename_component = fallback_date

    return (origin, codename_component)


def showPackages(pkgs):
    """create a parseseable representation for each package"""
    for p in sorted(set(pkgs)):
        library = p.package.name
        version = p.version
        arch = p.architecture
        uploader, date = getOrigin(p)
        uri = p.uri
        status = p.summary
        installed = p.package.is_installed
        state = "Already installed" if installed else "Provided"
        comment = f"{state} by {uploader} ({date})"

        print(
            f"{library}\t{version}\t{arch}\t{int(installed)}\t{uploader}\t{date}\t{uri}\t{status}\t{comment}"
        )


def main():
    args = parseArgs()
    if args.api not in {0, 1}:
        return
    if not args.api:
        # quick sanity check if python-apt is available
        import apt

        return

    initializeAptCache()
    if not args.architecture:
        for p in ["dpkg", "apt", "bash"]:
            try:
                args.architecture = aptcache.get(f"{p}:native").architecture()
                break
            except AttributeError:
                pass

    packages = getPackages(args.pkg, arch=args.architecture, floatsize=args.floatsize)
    showPackages(packages)


if __name__ == "__main__":
    main()
