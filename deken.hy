#!/usr/bin/env hy
; ./deken build svn://svn.code.sf.net/p/pure-data/svn/trunk/externals/freeverb~/

(import sys)
(import os)
(import argparse)


(defn git [&rest args]
  (try (import [sh [git]])
    (catch [ImportError] (print "Git binary not found. Please install git.") (sys.exit 1))
    (finally (git args))))

(defn svn [&rest args]
  (try (import [sh [svn]])
    (catch [ImportError] (print "SVN binary not found. Please install Subversion.") (sys.exit 1))
    (finally (svn args))))

; uses the 'make' command do do the actual building
(defn make [&rest args]
  (try (import [sh [make]])
    (catch [ImportError] (print "Make binary not found. Please install make.") (sys.exit 1))
    (finally (apply make args))))

; uses git or svn to check out 
(defn checkout [repo-path destination]
  (if (or (repo-path.endswith ".git") (repo-path.startswith "git:"))
    (git "clone" repo-path destination)
    (svn "checkout" repo-path destination)))

; uses make to install an external
(defn install-one [location]
  (make "-C" location "STRIP=strip --strip-unneeded -R .note -R .comment" "DESTDIR='../../../pd-externals/'" "objectsdir=''" "install"))

; uses make to build an external
(defn build-one [location]
  (try (import [sh [make]])
    (catch [ImportError] (print "Make binary not found. Please install make."))
    (finally (make "-C" location "PD_PATH=../pd" "CFLAGS=-DPD -DHAVE_G_CANVAS_H -I../../pd/src -Wall -W"))))

; check for the existence of m_pd.h
(defn check-for-m-pd []
  (os.path.exists (os.path.join "workspace" "pd" "src" "m_pd.h")))

; the executable portion of the different sub-commands that make up the deken tool
(def commands {
  ; download and build a particular external from a repository
  :build (fn [args]
    (let [[destination (os.path.join "." "workspace" "externals" (os.path.basename (.rstrip args.repository "/")))]]
      (print "Checking out" args.repository "into" destination)
      (checkout args.repository destination)
      (print "Building" destination)
      (build-one destination)
      (print "Installing" destination)
      (install-one destination)))
  ; manipulate the version of Pd
  :pd (fn [])
  :update (fn [])})

; kick things off by using argparse to check out the arguments supplied by the user
(let [
  [version (.get os.environ "DEKEN_VERSION" "?")]
  [arg-parser (apply argparse.ArgumentParser [] {"prog" "deken" "description" "Deken is a build tool for Pure Data externals."})]
  [arg-subparsers (apply arg-parser.add_subparsers [] {"help" "-h for help." "dest" "command"})]
  [arg-build (apply arg-subparsers.add_parser ["build"])]
  [arg-fetch (apply arg-subparsers.add_parser ["pd"])]]
    (apply arg-parser.add_argument ["--version"] {"action" "version" "version" version})
    (apply arg-build.add_argument ["repository"] {"help" "The SVN or git repository of the external to build."})
    (apply arg-fetch.add_argument ["pd"] {"help" "Fetch a particular version of Pd to build against."})
    (let [
      [arguments (.parse_args arg-parser)]
      [command (.get commands (keyword arguments.command))]]
        (print "Deken" version)
        (command arguments)))
