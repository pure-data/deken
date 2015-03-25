#!/usr/bin/env hy

(import [sys])

(try (import [sh [svn]])
  (catch [ImportError] (print "SVN binary not found. Please install Subversion.")))

(try (import [sh [git]])
  (catch [ImportError] (print "Git binary not found. Please install git.")))

(print "Deken:" (slice sys.argv 1))
