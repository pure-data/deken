#!/usr/bin/env hy
; ./deken build svn://svn.code.sf.net/p/pure-data/svn/trunk/externals/freeverb~/

(import sys)
(import os)
(import argparse)
(import sh)
(import shutil)
(import platform)
(import zipfile)
(import string)
(import ConfigParser)
(import StringIO)

(def pd-repo-uri "git://git.code.sf.net/p/pure-data/pure-data")

(def pd-path (os.path.abspath (os.path.join "workspace" "pd")))
(def pd-binary-path (os.path.join pd-path "bin" "pd"))
(def pd-source-path (os.path.join pd-path "src"))
(def externals-build-path (os.path.abspath (os.path.join "workspace" "externals")))
(def externals-packaging-path (os.path.abspath (os.path.join "workspace" "pd-externals")))

; get the externals' homedir install location for this platform - from s_path.c
(def externals-folder
  (let [[system-name (platform.system)]]
    (cond
      [(= system-name "Linux") (os.path.expandvars (os.path.join "$HOME" "pd-externals"))]
      [(= system-name "Darwin") (os.path.expandvars (os.path.join "$HOME" "Library" "Pd"))]
      [(= system-name "Windows") (os.path.expandvars (os.path.join "%AppData%" "Pd"))])))

(def binary-names {:git "Git" :make "Make" :svn "Subversion"})

(def strip-flag {
  :Darwin "STRIP=strip -x"
  :Linux "STRIP=strip --strip-unneeded -R .note -R .comment"})

; read in the config file if present
(def config
  (let [
    [config-file (ConfigParser.SafeConfigParser)]
    [file-buffer (StringIO.StringIO (+ "[default]\n" (try (.read (open "config" "r")) (catch [e Exception] ""))))]]
      (config-file.readfp file-buffer)
      (dict (config-file.items "default"))))

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

; try to obtain a value from environment, then config file, then prompt user
(defn get-config-value [name]
  (or
    (os.environ.get (+ "DEKEN_" (name.upper)))
    (config.get name)
    (raw_input (% (+
      "Environment variable DEKEN_%s is not set and the config file %s does not contain a '%s = ...' entry.\n"
      "To avoid this prompt in future please add a setting to the config or environment.\n"
      "Please enter %s for pure-data.info upload: ")
        (tuple [(name.upper) (os.path.abspath (os.path.join "config")) name name])))))

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
(defn install-one [build-folder destination-folder]
  (make "-C" build-folder (get strip-flag (keyword (platform.system))) (% "DESTDIR='%s'" destination-folder) "objectsdir=''" "install"))

; uses make to build an external
(defn build-one [build-folder]
  (try (import [sh [make]])
    (catch [ImportError] (print "Make binary not found. Please install make."))
    (finally (make "-C" build-folder (% "PD_PATH=%s" pd-source-path) (% "CFLAGS=-DPD -DHAVE_G_CANVAS_H -I%s -Wall -W" pd-source-path)))))

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

; zip up a single directory
; http://stackoverflow.com/questions/1855095/how-to-create-a-zip-archive-of-a-directory
(defn zip-dir [directory-to-zip zip-file]
  (let [
    [zipf (zipfile.ZipFile zip-file "w")]
    [root-basename (os.path.basename directory-to-zip)]
    [root-path (os.path.join directory-to-zip "..")]]
      (for [[root dirs files] (os.walk directory-to-zip)]
        (for [file files]
             (let [[file-path (os.path.join root file)]]
               (zipf.write file-path (os.path.relpath file-path root-path)))))
      (zipf.close)))

; get the name of the external from the repository path
(defn get-external-name [repo-uri]
  (os.path.basename (.rstrip repo-uri "/")))

; get the destination the external should go into
(defn get-external-build-folder [external-name]
  (os.path.join externals-build-path external-name))

; compute the zipfile name for a particular external on this platform
(defn make-zipfile-name [folder]
  (+ folder "-xtrnl-" (get-architecture-prefix) ".zip"))

; the executable portion of the different sub-commands that make up the deken tool
(def commands {
  ; download and build a particular external from a repository
  :build (fn [args]
    (let [
      [external-name (get-external-name args.repository)]
      [build-folder (get-external-build-folder external-name)]
      [pd-dir (ensure-pd)]]
        (ensure-checked-out args.repository build-folder)
        (print "Building" build-folder)
        (build-one build-folder)))
  ; install a particular external into the user's pd-externals directory
  :install (fn [args]
    (let [
      [external-name (get-external-name args.repository)]
      [build-folder (get-external-build-folder external-name)]]
        ; make sure the repository is built
        ((:build commands) args)
        ; then install it
        (print (% "Installing %s into %s" (tuple [external-name externals-folder])))
        (install-one build-folder externals-folder)))
  ; zip up a set of built externals
  :package (fn [args]
    ; are they asking the package a directory or an existing repository?
    (if (os.path.isdir args.repository)
      ; if asking for a directory just package it up
      (let [[package-filename (make-zipfile-name args.repository)]]
        (zip-dir args.repository package-filename)
        package-filename)
      ; otherwise build and then package
      (let [
        [external-name (get-external-name args.repository)]
        [build-folder (get-external-build-folder external-name)]
        [package-folder (os.path.join externals-packaging-path external-name)]
        [package-filename (make-zipfile-name package-folder)]]
          ((:build commands) args)
          (install-one build-folder package-folder)
          (print "Packaging into" package-filename)
          (zip-dir package-folder package-filename)
          package-filename)))
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
    [arg-package (apply arg-subparsers.add_parser ["package"])]
    [arg-upgrade (apply arg-subparsers.add_parser ["upgrade"])]
    [arg-clean (apply arg-subparsers.add_parser ["clean"] {"help" "Deletes all files from the workspace folder."})]
    [arg-pd (apply arg-subparsers.add_parser ["pd"])]]
      (apply arg-parser.add_argument ["--version"] {"action" "version" "version" version "help" "Outputs the version number of Deken."})
      (apply arg-parser.add_argument ["--platform"] {"action" "version" "version" (get-architecture-prefix) "help" "Outputs the current build platform identifier string."})
      (apply arg-build.add_argument ["repository"] {"help" "The SVN or git repository of the external to build."})
      (apply arg-install.add_argument ["repository"] {"help" "The SVN or git repository of the external to install."})
      (apply arg-package.add_argument ["repository"] {"help" "Either the path to a directory of externals to be packaged, or the SVN or git repository of an external to package."})
      (apply arg-pd.add_argument ["version"] {"help" "Fetch a particular version of Pd to build against." "nargs" "?"})
      (let [
        [arguments (.parse_args arg-parser)]
        [command (.get commands (keyword arguments.command))]]
          (print "Deken" version)
          (command arguments))))
