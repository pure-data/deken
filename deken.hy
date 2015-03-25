#!/usr/bin/env hy

(import sys)
(import os)

(try (import [sh [svn]])
  (catch [ImportError] (print "SVN binary not found. Please install Subversion.")))

(try (import [sh [git]])
  (catch [ImportError] (print "Git binary not found. Please install git.")))

; list of commands available to the user
(def commands {
  "build" {"args" ["REPOSITORY-PATH"] "help" "Downloads the code from the repository listed and builds it."}})

(def version (get os.environ "DEKEN_VERSION"))

(print "Deken" version (slice sys.argv 1))
