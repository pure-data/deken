#!/usr/bin/env hy
; ./deken build svn://svn.code.sf.net/p/pure-data/svn/trunk/externals/freeverb~/

(import sys)
(import os)
(import argparse)
(import sh)

(def pd-repo "git://git.code.sf.net/p/pure-data/pure-data")

; invoke the git binary, ensuring it exists
(defn git [&rest args]
  (try (import [sh [git]])
    (except [ImportError] (print "Git binary not found. Please install git.") (sys.exit 1)))
  (try
    (git args)
    (catch [e sh.ErrorReturnCode]
           (print e.stderr)
           (sys.exit 1))))

; invoke the svn binary, ensuring it exists
(defn svn [&rest args]
  (try (import [sh [svn]])
    (catch [ImportError] (print "SVN binary not found. Please install subversion.") (sys.exit 1)))
  (try
    (svn args)
    (catch [e sh.ErrorReturnCode] 
            (print e.stderr)
            (sys.exit 1))))

; uses the 'make' command do do the actual building
(defn make [&rest args]
  (try (import [sh [make]])
    (catch [ImportError] (print "Make binary not found. Please install make.") (sys.exit 1)))
  (try
    (apply make args)
    (catch [sh.ErrorReturnCode e]
      (print e.stderr)
      (sys.exit 1))))

; execute a command inside a directory
(defn in-dir [destination f &rest args]
  (let [[last-dir (os.getcwd)]]
      (os.chdir destination)
      (apply f args)
      (os.chdir last-dir)))

; test if a repository is a git repository
(defn is-git? [repo-path]
  (or (repo-path.endswith ".git") (repo-path.startswith "git:")))

; uses git or svn to check out 
(defn checkout [repo-path destination]
  (if (is-git? repo-path)
    (git "clone" repo-path destination)
    (svn "checkout" repo-path destination)))

; uses git or svn to update the repository
(defn update [repo-path destination]
  (if (is-git? repo-path)
    (in-dir destination git "pull")
    (in-dir destination svn "update")))

; uses make to install an external
(defn install-one [location]
  (make "-C" location "STRIP=strip --strip-unneeded -R .note -R .comment" "DESTDIR='../../../pd-externals/'" "objectsdir=''" "install"))

; uses make to build an external
(defn build-one [location]
  (try (import [sh [make]])
    (catch [ImportError] (print "Make binary not found. Please install make."))
    (finally (make "-C" location "PD_PATH=../pd" "CFLAGS=-DPD -DHAVE_G_CANVAS_H -I../../pd/src -Wall -W"))))

; check for the existence of m_pd.h
(defn m-pd? []
  (os.path.exists (os.path.join "workspace" "pd" "src" "m_pd.h")))

; make sure there is a checkout of pd
(defn ensure-pd []
  (let [[destination (os.path.join "." "workspace" "pd")]]
    (if (not (m-pd?))
      (do
        (print "Checking out Pure Data")
        (checkout pd-repo destination)))
    destination))

; the executable portion of the different sub-commands that make up the deken tool
(def commands {
  ; download and build a particular external from a repository
  :build (fn [args]
    (let [
      [external-name (os.path.basename (.rstrip args.repository "/"))]
      [destination (os.path.join "." "workspace" "externals" external-name)]
      [pd-dir (ensure-pd)]]
        (if (os.path.isdir destination)
          (do
            (print "Updating" destination)
            (update args.repository destination))
          (do
            (print "Checking out" args.repository "into" destination)
            (checkout args.repository destination)))
        (print "Building" destination)
        (build-one destination)
        (print "Installing" destination)
        (install-one destination)
        (print (% "Installed into ./pd-externals/%s" external-name))))
  ; manipulate the version of Pd
  :pd (fn [args]
    (let [
      [destination (ensure-pd)]
      [deken-home (os.getcwd)]]
        (os.chdir destination)
        (if args.version
          (git "checkout" args.version))
        ; tell the user what version is currently checked out
        (print (% "Pd version %s checked out" (.rstrip (git "rev-parse" "--abbrev-ref" "HEAD"))))
        (os.chdir deken-home)))
  ; update pd binary and list of externals repositories
  :update (fn [])})

; kick things off by using argparse to check out the arguments supplied by the user
(if (= __name__ "__main__")
  (let [
    [version (.get os.environ "DEKEN_VERSION" "?")]
    [arg-parser (apply argparse.ArgumentParser [] {"prog" "deken" "description" "Deken is a build tool for Pure Data externals."})]
    [arg-subparsers (apply arg-parser.add_subparsers [] {"help" "-h for help." "dest" "command"})]
    [arg-build (apply arg-subparsers.add_parser ["build"])]
    [arg-pd (apply arg-subparsers.add_parser ["pd"])]]
      (apply arg-parser.add_argument ["--version"] {"action" "version" "version" version})
      (apply arg-build.add_argument ["repository"] {"help" "The SVN or git repository of the external to build."})
      (apply arg-pd.add_argument ["version"] {"help" "Fetch a particular version of Pd to build against." "nargs" "?"})
      (let [
        [arguments (.parse_args arg-parser)]
        [command (.get commands (keyword arguments.command))]]
          (print "Deken" version)
          (command arguments))))
