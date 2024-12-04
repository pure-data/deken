#!/usr/bin/env python3

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
    p.add_argument("--api", type=int, required=True, help="Output format version")

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


def getPackages2(pkgs, arch=None, floatsize=32):
    pd32deps = {"puredata-core", "puredata", "puredata-gui", "pd"}
    pd64deps = {"puredata64-core", "puredata64", "puredata-gui", "pd64"}
    if floatsize == 64:
        pddeps = pd64deps
    else:
        pddeps = pd32deps

    packages = {}
    for p in aptcache:
        # filter out known non-externals
        if p.shortname.startswith("puredata"):
            continue
        # filter out unwanted architectures
        if arch and p.architecture() != arch:
            continue
        for v in p.versions:
            # we only take packages that depend on Pd
            if not hasDependency(v, pddeps):
                continue
            names = [p.shortname] + v.provides
            for name in {*names}:
                for n in {name, stripSuffix(name, "pd-"), stripSuffix(name, "pd64-")}:
                    npkgs = packages.get(n) or set()
                    npkgs.add(v)
                    packages[n] = npkgs
    matches = {}
    for p in pkgs:
        matches.update({m: packages[m] for m in fnmatch.filter(packages, p)})
    matches = {m: matches[m] for m in sorted(matches)}
    result = {m: True for m in itertools.chain(*matches.values())}
    return result


def getPackages(pkgs, arch=None, floatsize=32):
    """get a list of available packages (apt.package.Version)
    that match <pkgs>, <arch> and <floatsize>"""

    pddeps = {"puredata-core", "puredata", "puredata-gui", "pd"}
    if floatsize == 64:
        pddeps = {"puredata64-core", "puredata64", "puredata-gui", "pd64"}

    # all packages known to apt
    allpackages = list({p.split(":")[0]: True for p in aptcache.keys()})

    # match the name
    packages = {}
    for p in pkgs:
        packages.update({m: True for m in fnmatch.filter(allpackages, p)})

    # get the actual packages
    emptyversion = EmptyVersion([])
    packages = [
        p
        for p in itertools.chain(
            *[
                aptcache.get(f"%s:%s" % (p, arch), emptyversion).versions
                for p in packages
            ]
        )
        if p and (arch is None or p.architecture == arch) and hasDependency(p, pddeps)
    ]

    return packages


def getOrigin(
    versioned_pkg,
    fallback_uploader="apt",
    fallback_date=None,
    trusted="",
    untrusted="?",
):
    """get the package origin as a tuple repository and archive,
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
        return (fallback_uploader, fallback_date)

    for o in origins:
        try:
            return (
                f"{o.label or o.origin or fallback_uploader}{trust}",
                f"{o.codename or o.archive}/{o.component}" or fallback_date,
            )
        except AttributeError:
            pass
    return (fallback_uploader, fallback_date)


def showPackages(pkgs):
    """create a parseseable representation for each package"""
    for p in pkgs:
        library = p.package.name
        version = p.version
        uploader, date = getOrigin(p)
        status = p.summary
        state = "Already installed" if p.is_installed else "Provided"
        comment = f"{state} by {uploader} ({date})"

        print(f"{library}\t{version}\t{uploader}\t{date}\t{status}\t{comment}")


def main():
    args = parseArgs()
    if args.api not in {1}:
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
