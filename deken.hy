#!/usr/bin/env hy
; ./deken build svn://svn.code.sf.net/p/pure-data/svn/trunk/externals/freeverb~/

(import sys)
(import os)
(import argparse)
(import sh)
(import shutil)
(import platform)
(import string)

(def pd-repo-uri "git://git.code.sf.net/p/pure-data/pure-data")

(def pd-path (os.path.abspath (os.path.join "workspace" "pd")))
(def pd-binary-path (os.path.join pd-path "bin" "pd"))
(def pd-source-path (os.path.join pd-path "src"))
(def externals-build-path (os.path.abspath (os.path.join "workspace" "externals")))

(def binary-names {:git "Git" :make "Make" :svn "Subversion"})

(def strip-flag {
  :Darwin "STRIP=strip -x"
  :Linux "STRIP=strip --strip-unneeded -R .note -R .comment"})

; get the externals' homedir install location for this platform - from s_path.c
(def externals-folder
  (let [[system-name (platform.system)]]
    (cond
      [(= system-name "Linux") (os.path.expandvars (os.path.join "$HOME" "pd-externals"))]
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
(defn is-git? [repo-uri]
  (or (repo-uri.endswith ".git") (repo-uri.startswith "git:")))

; uses git or svn to check out 
(defn checkout [repo-uri destination]
  (if (is-git? repo-uri)
    (git "clone" repo-uri destination)
    (svn "checkout" repo-uri destination)))

; uses git or svn to update the repository
(defn update [repo-uri destination]
  (if (is-git? repo-uri)
    (in-dir destination git "pull")
    (in-dir destination svn "update")))

; uses make to install an external
(defn install-one [location]
  (make "-C" location (get strip-flag (keyword (platform.system))) (% "DESTDIR='%s'" externals-folder) "objectsdir=''" "install"))

; uses make to build an external
(defn build-one [location]
  (try (import [sh [make]])
    (catch [ImportError] (print "Make binary not found. Please install make."))
    (finally (make "-C" location (% "PD_PATH=%s" pd-source-path) (% "CFLAGS=-DPD -DHAVE_G_CANVAS_H -I%s -Wall -W" pd-source-path)))))

; check for the existence of m_pd.h
(defn m-pd? []
  (os.path.exists (os.path.join pd-source-path "m_pd.h")))

; make sure there is a checkout of pd
(defn ensure-pd []
  (if (not (m-pd?))
    (do
      (print "Checking out Pure Data")
      (checkout pd-repo-uri pd-path)))
  pd-path)

; make sure we have an up-to-date checked out copy of a particular repository
(defn ensure-checked-out [repo-uri destination]
  (if (os.path.isdir destination)
    (do
      (print "Updating" destination)
      (update repo-uri destination))
    (do
      (print "Checking out" repo-uri "into" destination)
      (checkout repo-uri destination))))

; get the name of the external from the repository path
(defn get-external-name [repo-uri]
  (os.path.basename (.rstrip repo-uri "/")))

; get the destination the external should go into
(defn get-external-destination [external-name]
  (os.path.join externals-build-path external-name))

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
    (if (os.path.isdir "workspace")
      (do
        (print "Deleting all files in the workspace folder.")
        (shutil.rmtree "workspace"))))
  ; self-update deken
  :upgrade (fn [args]
    (print "The upgrade script isn't here, it's in the Bash wrapper."))
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
    [arg-upgrade (apply arg-subparsers.add_parser ["upgrade"])]
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
