#!/usr/bin/env python3

import fnmatch
import itertools

import apt


aptcache = apt.Cache()


class EmptyVersion:
    """helper class that provides an empty versions member"""

    def __init__(self, versions=[]):
        self.versions = versions


def parseArgs():
    import argparse

    parser = argparse.ArgumentParser()

    for p in ["dpkg", "apt", "bash"]:
        try:
            architecture = aptcache.get(f"{p}:native").architecture()
            break
        except AttributeError:
            pass

    p = parser.add_argument_group(
        title="filters",
    )

    p.add_argument(
        "--os",
        default="Linux",
        choices=["Linux"],
        help="target operating system [DEFAULT: %(default)r]",
    )
    p.add_argument(
        "--architecture",
        default=architecture,
        help="target CPU architecture [DEFAULT: %(default)r]",
    )
    p.add_argument(
        "--floatsize",
        type=int,
        default=32,
        help="target floatsize [DEFAULT: %(default)s}]",
    )

    parser.add_argument(
        "pkg",
        nargs="*",
        help="package(s) to search for",
    )

    args = parser.parse_args()

    return args


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
    """get a list of available packages (apt.package.Version)
    that match <pkgs>, <arch> and <floatsize>"""
    if not arch:
        arch = "native"
    allpackages = list({p.split(":")[0]: True for p in aptcache.keys()})

    pddeps = {"puredata-core", "puredata", "puredata-gui", "pd"}
    if floatsize == 64:
        pddeps = {"puredata64-core", "puredata64", "puredata-gui", "pd64"}

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
    packages = getPackages(args.pkg, arch=args.architecture, floatsize=args.floatsize)
    showPackages(packages)


if __name__ == "__main__":
    main()
