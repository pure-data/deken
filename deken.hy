#!/usr/bin/env hy
; ./deken build svn://svn.code.sf.net/p/pure-data/svn/trunk/externals/freeverb~/

(import sys)
(import os)
(import argparse)
(import sh)
(import shutil)
(import platform)
(import string)

(def pd-repo "git://git.code.sf.net/p/pure-data/pure-data")
(def binary-names {:git "Git" :make "Make" :svn "Subversion"})

(def pd-binary-path (os.path.join "workspace" "pd" "bin" "pd"))
(def pd-m-pd-h-path (os.path.join "workspace" "pd" "src" "m_pd.h"))

; get the externals' homedir install location for this platform - from s_path.c
(def externals-folder
  (let [[system-name (platform.system)]]
    (cond [(= system-name "Linux") (os.path.expandvars (os.path.join "$HOME" "pd-externals"))]
    [(= system-name "Darwin") (os.path.expandvars (os.path.join "$HOME" "Library" "Pd"))]
    [(= system-name "Windows") (os.path.expandvars (os.path.join "%AppData%" "Pd"))])))

; create an architecture string
(defn arch-string [&rest args]
  (let [[arch (list-comp a [a (apply platform.architecture args)] a)]]
    (.join "-" arch)))

; get a string we can use to specify/determine the build architecture of externals on this platform
(defn get-architecture-prefix []
  (.join "-" [
     (platform.system)
     (platform.machine)
     (if (os.path.isfile pd-binary-path)
       (arch-string pd-binary-path)
       (arch-string))]))

; get access to a command line binary in a way that checks for it's existence and reacts to errors correctly
(defn get-binary [binary-name]
  (try
    (let [[binary-fn (getattr sh binary-name)]]
      (fn [&rest args]
        (try
          (apply binary-fn args)
          (catch [e sh.ErrorReturnCode]
            (print e.stderr)
            (sys.exit 1)))))
    (catch [e sh.CommandNotFound]
      (print binary-name (% "binary not found. Please install %s." (get binary-names (keyword binary-name))))
      (sys.exit 1))))

; error-handling wrappers for the command line binaries
(def git (get-binary "git"))
(def svn (get-binary "svn"))
(def make (get-binary "make"))

; execute a command inside a directory
(defn in-dir [destination f &rest args]
  (let [
    [last-dir (os.getcwd)]
    [new-dir (os.chdir destination)]
    [result (apply f args)]]
      (os.chdir last-dir)
      result))

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
  (make "-C" location "STRIP=strip --strip-unneeded -R .note -R .comment" (% "DESTDIR='%s'" externals-folder) "objectsdir=''" "install"))

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

; make sure we have an up-to-date checked out copy of a particular repository
(defn ensure-checked-out [repo-path destination]
  (if (os.path.isdir destination)
    (do
      (print "Updating" destination)
      (update repo-path destination))
    (do
      (print "Checking out" repo-path "into" destination)
      (checkout repo-path destination))))

; get the name of the external from the repository path
(defn get-external-name [repo-path]
  (os.path.basename (.rstrip repo-path "/")))

; get the destination the external should go into
(defn get-external-destination [external-name]
  (os.path.join "." "workspace" "externals" external-name))

; the executable portion of the different sub-commands that make up the deken tool
(def commands {
  ; download and build a particular external from a repository
  :build (fn [args]
    (let [
      [external-name (get-external-name args.repository)]
      [destination (get-external-destination external-name)]
      [pd-dir (ensure-pd)]]
        (ensure-checked-out args.repository destination)
        (print "Building" destination)
        (build-one destination)))
  ; install a particular external into the user's pd-externals directory
  :install (fn [args]
    (let [
      [external-name (get-external-name args.repository)]
      [destination (get-external-destination external-name)]]
        ; make sure the repository is built
        ((:build commands) args)
        ; then install it
        (print (% "Installing %s into %s" (tuple [destination (os.path.join externals-folder external-name)])))
        (install-one destination)))
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
  ; deletes the workspace directory
  :clean (fn [args]
    (shutil.rmtree "workspace")
    (print "Deleted all files in the workspace folder."))
  ; update pd binary and list of externals repositories
  :update (fn [])})

; kick things off by using argparse to check out the arguments supplied by the user
(if (= __name__ "__main__")
  (let [
    [version (.get os.environ "DEKEN_VERSION" "?")]
    [arg-parser (apply argparse.ArgumentParser [] {"prog" "deken" "description" "Deken is a build tool for Pure Data externals."})]
    [arg-subparsers (apply arg-parser.add_subparsers [] {"help" "-h for help." "dest" "command"})]
    [arg-build (apply arg-subparsers.add_parser ["build"])]
    [arg-install (apply arg-subparsers.add_parser ["install"])]
    [arg-clean (apply arg-subparsers.add_parser ["clean"] {"help" "Deletes all files from the workspace folder."})]
    [arg-pd (apply arg-subparsers.add_parser ["pd"])]]
      (apply arg-parser.add_argument ["--version"] {"action" "version" "version" version "help" "Outputs the version number of Deken."})
      (apply arg-parser.add_argument ["--platform"] {"action" "version" "version" (get-architecture-prefix) "help" "Outputs the current build platform identifier string."})
      (apply arg-build.add_argument ["repository"] {"help" "The SVN or git repository of the external to build."})
      (apply arg-install.add_argument ["repository"] {"help" "The SVN or git repository of the external to install."})
      (apply arg-pd.add_argument ["version"] {"help" "Fetch a particular version of Pd to build against." "nargs" "?"})
      (let [
        [arguments (.parse_args arg-parser)]
        [command (.get commands (keyword arguments.command))]]
          (print "Deken" version)
          (command arguments))))
