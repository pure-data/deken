#!/usr/bin/env hy
;; deken upload --version 0.1 ./freeverb~/

;; This software is copyrighted by Chris McCormick, IOhannes m zmölnig and
;; others.
;; The following terms (the "Standard Improved BSD License") apply to all
;; files associated with the software unless explicitly disclaimed in
;; individual files:
;;
;; Redistribution and use in source and binary forms, with or without
;; modification, are permitted provided that the following conditions are
;; met:
;;
;; 1. Redistributions of source code must retain the above copyright
;;    notice, this list of conditions and the following disclaimer.
;; 2. Redistributions in binary form must reproduce the above
;;    copyright notice, this list of conditions and the following
;;    disclaimer in the documentation and/or other materials provided
;;    with the distribution.
;; 3. The name of the author may not be used to endorse or promote
;;    products derived from this software without specific prior
;;    written permission.
;;
;; THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY
;; EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
;; THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
;; PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR
;; BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
;; EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
;; TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
;; DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
;; ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
;; LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
;; IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
;; THE POSSIBILITY OF SUCH DAMAGE.


(import sys)
(import os)
(import re)
(import argparse)
(import datetime)

(import platform)
(import zipfile)
(import tarfile)
(import string)
(import struct)
(import copy)
(try (import [ConfigParser [SafeConfigParser]])
 (except [e ImportError] (import [configparser [SafeConfigParser]])))
(try (import [StringIO [StringIO]])
 (except [e ImportError] (import [io [StringIO]])))
(import hashlib)
(import [getpass [getpass]])
(try (import [urlparse [urlparse]])
 (except [e ImportError] (import [urllib.parse [urlparse]])))

(require hy.contrib.loop)

(def deken-home (os.path.expanduser (os.path.join "~" ".deken")))
(def config-file-path (os.path.abspath (os.path.join deken-home "config")))
(def version (try (.rstrip (.read (open (os.path.join deken-home "VERSION"))) "\r\n") (except [e Exception] (.get os.environ "DEKEN_VERSION" "0.1"))))
(def externals-host "puredata.info")

(def elf-arch-types {
  "EM_NONE" None
  "EM_386" "i386"
  "EM_68K" "m68k"
  "EM_IA_64" "x86_64"
  "EM_X86_64" "amd64"
  "EM_ARM" "arm"
  "EM_M32" "WE32100"
  "EM_SPARC" "Sparc"
  "EM_88K" "m88k"
  "EM_860" "Intel 80860"
  "EM_MIPS" "MIPS R3000"
  "EM_S370" "IBM System/370"
  "EM_MIPS_RS4_BE" "MIPS 4000 big-endian"
  "EM_AVR" "Atmel AVR 8-bit microcontroller"
  "EM_AARCH64" "AArch64"
  "EM_BLAFKIN" "Analog Devices Blackfin"
  "RESERVED" "RESERVED"})

;; values updated via https://sourceware.org/git/gitweb.cgi?p=binutils-gdb.git;a=blob;f=include/elf/arm.h;hb=HEAD#l93
(def arm-cpu-arch
  [
   "Pre-v4"
   "v4"
   "v4T"
   "v5T"
   "v5TE"
   "v5TEJ"
   "v6"
   "v6KZ"
   "v6T2"
   "v6K"
   "v7"
   "v6_M"
   "v6S_M"
   "v7E_M"
   "v8"
   "v8R"
   "v8M_BASE"
   "v8M_MAIN"
   ])

(def win-types {
  "0x014c" ["i386" 32]
  "0x0200" ["x86_64" 64]
  "0x8664" ["amd64" 64]})

;; algorithm to use to hash files
(def hasher hashlib.sha256)
(def hash-extension (.pop (hasher.__name__.split "_")))

;; nil? has been removed from hy-0.12
(try (nil? None) (except [e NameError] (defn nil? [x] (= x None))))

;; in hy-0.12 'slice' has been replaced with 'cut'
;; but we cannot replace 'cut' in hy>=0.12, because it is a built-in...
(defn cut-slice [x y z] (cut x y z))
(try (cut []) (except [e NameError] (defn cut-slice [x y z] (slice x y z))))

;; convert a string into bool, based on the string value
(defn str-to-bool [s] (and (not (nil? s)) (not (in (.lower s) ["false" "f" "no" "n" "0" "nil" "none"]))))

;; join non-empty elements
(defn join-nonempty [joiner elements] (.join joiner (list-comp (str x) [x elements] x)))

;; concatenate two dictionaries - hylang's assoc is broken
(defn dict-merge [d1 d2] (apply dict [d1] (or d2 {})))

;; apply attributes to objects in a functional way
(defn set-attr [obj attr value] (setattr obj attr value) obj)
;; get multiple attributes as list
(defn get-attrs [obj attributes &optional default] (list-comp (getattr obj _default) [_ attributes]))

;; replace multiple words (given as pairs in <repls>) in a string <s>
(defn replace-words [s repls] (reduce (fn [a kv] (apply a.replace kv)) repls s))

;; get multiple values from a dict (give keys as list, get values as list)
(defn get-values [coll keys] (list-comp (get coll _) [_ keys]))

;; get a value at an index/key or a default
(defn try-get [elements index &optional default]
  (try (get elements index)
       (except [e TypeError] default)
       (except [e KeyError] default)
       (except [e IndexError] default)))

;; read in the config file if present
(defn read-config [configstring &optional [config-file (SafeConfigParser)]]
  (config-file.readfp (StringIO configstring))
  (dict (config-file.items "default")))

(def config (read-config (+ "[default]\n" (try (.read (open config-file-path "r"))(except [e Exception] "")))))

;; takes the externals architectures and turns them into a string
(defn get-architecture-strings [folder]
   (defn _get_archs [archs sep-1 sep-2]
     (if archs (+ "(" (sep-1.join (set (list-comp (sep-2.join (list-comp (str a) [a arch])) [arch archs]))) ")") ""))
   (_get_archs (get-externals-architectures folder) ")(" "-"))

;; check if a particular file has an extension in a set
(defn test-extensions [filename extensions]
  (len (list-comp e [e extensions] (filename.endswith e))))

;; examine a folder for externals and return the architectures of those found
(defn get-externals-architectures [folder]
  (sum (list-comp (cond
      [(test-extensions f [".pd_linux" ".l_ia64" ".l_i386" ".l_arm" ".so"]) (get-elf-arch (os.path.join folder f) "Linux")]
      [(test-extensions f [".pd_freebsd" ".b_i386"]) (get-elf-arch (os.path.join folder f) "FreeBSD")]
      [(test-extensions f [".pd_darwin" ".d_fat" ".d_ppc"]) (get-mach-arch (os.path.join folder f))]
      [(test-extensions f [".m_i386" ".dll"]) (get-windows-arch (os.path.join folder f))]
      [(test-extensions f [".c" ".cpp" ".C" ".cxx" ".cc"]) [["Sources"]]]
      [True []])
    [f (os.listdir folder)]) []))

;; get architecture strings from a windows DLL
;; http://stackoverflow.com/questions/495244/how-can-i-test-a-windows-dll-to-determine-if-it-is-32bit-or-64bit
(defn get-windows-arch [filename] (try (do-get-windows-arch (open filename "rb")) (except [e Exception] [])))
(defn do-get-windows-arch [f]
  (setv [magic _ offset] (struct.unpack (str "<2s58sL") (f.read 64)))
  (if (= magic "MZ")  ; has correct magic bytes
    (do
     (f.seek offset)
     (setv [sig _ machine] (struct.unpack (str "<2s2sH") (f.read 6)))
     (if (= sig "PE")  ; has correct signature
       [(+ ["Windows"] (win-types.get (% "0x%04x" machine) ["unknown" "unknown"]))]
       (raise (Exception "Not a PE Executable."))))
    (raise (Exception "Not a valid Windows dll."))))

;; get architecture from an ELF (e.g. Linux)
(defn get-elf-arch [filename oshint]
  (import [elftools.elf.elffile [ELFFile]])
  (import [elftools.common [exceptions]])
  (try
   (do
    (setv elf (ELFFile (open filename :mode "rb")))
    ;; TODO: check section .ARM.attributes for v number
    ;; python ./virtualenv/bin/readelf.py -p .ARM.attributes ...
    [[oshint
      (+ (elf-arch-types.get (elf.header.get "e_machine") None)
         (or (parse-arm-elf-arch elf) ""))
      (int (cut-slice (.get (elf.header.get "e_ident") "EI_CLASS") -2 None))]])
   (except [e exceptions.ELFError] [])))

;; get architecture from a Darwin Mach-O file (OSX)
(defn get-mach-arch [filename]
  (import [macholib.MachO [MachO]])
  (import [macholib.mach_o [MH_MAGIC_64 CPU_TYPE_NAMES]])
  (try
   (list-comp ["Darwin" (CPU_TYPE_NAMES.get h.header.cputype h.header.cputype) (if (= h.MH_MAGIC MH_MAGIC_64) 64 32)] [h (. (MachO filename) headers)])
   (except [e ValueError] [])))



;; gets the specific flavour of arm by hacking the .ARM.attributes ELF section
(defn parse-arm-elf-arch [arm-elf]
  (setv arm-section (if arm-elf (try (arm-elf.get_section_by_name ".ARM.attributes"))))
  ;; we only support format 'A'
  (setv A (try (bytes "A") (except [e TypeError] (bytes "A" "ascii"))))
  ;; the arm cpu can be found in the 'aeabi' section
  (setv data (and arm-section (.startswith (arm-section.data) A) (.index (arm-section.data) "aeabi") (.pop (.split (arm-section.data) "aeabi"))))
  (if data
    (get arm-cpu-arch (ord (get (get (.split (cut-slice data 7 None) "\x00" 1) 1) 1)))))

;; try to obtain a value from environment, then config file, then prompt user
(defn get-config-value [name &rest default]
  (first (filter (fn [x] (not (nil? x)))
                 [
                  ;; try to get the value from an environment variable
                  (os.environ.get (+ "DEKEN_" (name.upper)))
                  ;; try to get the value from the config file
                  (config.get name)
                  ;; finally, try the default
                  (first default)])))

;; prompt for a particular config value for externals host upload
(defn prompt-for-value [name]
  (raw_input (% (+
    "Environment variable DEKEN_%s is not set and the config file %s does not contain a '%s = ...' entry.\n"
    "To avoid this prompt in future please add a setting to the config or environment.\n"
    "Please enter %s for http://%s/: ")
      (tuple [(name.upper) config-file-path name name externals-host]))))

;; calculate the sha256 hash of a file
(defn hash-file [filename &optional [blocksize 65535] [hashfn (hasher)]]
  (setv f (open filename :mode "rb"))
  (setv read-chunk (fn [] (.read f blocksize)))
  (while True
    (setv buf (read-chunk))
    (if-not buf (break))
    (hashfn.update buf))
   (hashfn.hexdigest))

(defn hash-sum-file [filename &optional [blocksize 65535]]
  (setv hashfilename (% "%s.%s" (tuple [filename hash-extension])))
  (.write (open hashfilename :mode "w") (hash-file filename blocksize))
  hashfilename)

;; handling GPG signatures
(try (import gnupg)
     ;; read a value from the gpg config
     (except [e ImportError] (defn gpg-sign-file [filename] (print (% "Unable to GPG sign '%s'\n" filename) "'gnupg' module not loaded")))
     (else
      (defn gpg-get-config [gpg id]
          (try
           (get
            (list-comp
             (get (.split (.strip x)) 1)
             [x
              (.readlines
               ( open
                 (os.path.expanduser
                  (os.path.join
                   (or gpg.gnupghome (os.path.join "~" ".gnupg"))
                   "gpg.conf"))
                 ))]
             (.startswith (.lstrip x) (.strip id) )) -1)
           (except [e [IOError IndexError]] None)))

      ;; get the GPG key for signing
      (defn gpg-get-key [gpg]
        (setv keyid (get-config-value "key_id" (gpg-get-config gpg "default-key")))
        (try
         (car (list-comp k
                         [k (gpg.list_keys True)]
                         (cond [keyid (.endswith (.upper (get k "keyid" )) (.upper keyid) )]
                               [True True])))
         (except [e IndexError] None)))

      ;; generate a GPG signature for a particular file
      (defn do-gpg-sign-file [filename signfile]
        (print (% "Attempting to GPG sign '%s'" filename))
        (setv gnupghome (get-config-value "gpg_home"))
        (setv use-agent (str-to-bool (get-config-value "gpg_agent")))
        (setv gpg (set-attr
                   (apply gnupg.GPG []
                          (dict-merge
                           (dict-merge {} (if gnupghome {"gnupghome" gnupghome}))
                           (if use-agent {"use_agent" True})))
                   "decode_errors" "replace"))
        (setv [keyid uid] (list-comp (try-get (gpg-get-key gpg) _ None) [_ ["keyid" "uids"]]))
        (setv uid (try-get uid 0 None))
        (setv passphrase
              (if (and (not use-agent) keyid)
                (do
                 (print (% "You need a passphrase to unlock the secret key for\nuser: %s ID: %s\nin order to sign %s"
                           (tuple [uid keyid filename])))
                 (getpass "Enter GPG passphrase: " ))))
        (setv signconfig (dict-merge (dict-merge {"detach" True}
                                                 (if keyid {"keyid" keyid}))
                                     (if passphrase {"passphrase" passphrase})))

        (if (and (not use-agent) passphrase)
          (print "No passphrase and not using gpg-agent...trying to sign anyhow"))
        (try
         (do
          (setv sig (if gpg (apply gpg.sign_file [(open filename "rb")] signconfig)))
          (if (hasattr sig "stderr")
            (print (try (str sig.stderr) (except [e UnicodeEncodeError] (.encode sig.stderr "utf-8")))))
          (if (not sig)
            (print "WARNING: Could not GPG sign the package.")
            (do
             (setv f (open signfile "w"))
             (.write f (str sig))
             (.close f)
             signfile)))
         (except [e OSError] (print (.join "\n"
                                           ["WARNING: GPG signing failed:"
                                            str(e)
                                            "Do you have 'gpg' (on OSX: 'GPG Suite') installed?"])))))

      ;; sign a file if it is not already signed
      (defn gpg-sign-file [filename]
        (setv signfile (+ filename ".asc"))
        (if (os.path.exists signfile)
          (do
           (print (% "NOTICE: not GPG-signing already signed file '%s'\nNOTICE: delete '%s' to re-sign" (, filename signfile)))
           signfile)
          (do-gpg-sign-file filename signfile)))))

;; execute a command inside a directory
(defn in-dir [destination f &rest args]
  (setv last-dir (os.getcwd))
  (os.chdir destination)
  (setv result (apply f args))
  (os.chdir last-dir)
  result)

;; zip up a single directory
;; http://stackoverflow.com/questions/1855095/how-to-create-a-zip-archive-of-a-directory
(defn zip-file [filename]
  (try (zipfile.ZipFile filename "w" :compression zipfile.ZIP_DEFLATED)
       (except [e RuntimeError] (zipfile.ZipFile filename "w"))))
(defn zip-dir [directory-to-zip archive-file]
  (setv zip-filename (+ archive-file ".zip"))
  (setv f (zip-file zip-filename))
  (for [[root dirs files] (os.walk directory-to-zip)]
    (for [file files]
      (setv file-path (os.path.join root file))
      (f.write file-path (os.path.relpath file-path (os.path.join directory-to-zip "..")))))
  (.close f)
  zip-filename)

;; tar up the directory
(defn tar-dir [directory-to-tar archive-file]
  (setv tar-file (+ archive-file ".tar.gz"))
  (setv f (tarfile.open tar-file "w:gz"))
  (.add f directory-to-tar)
  (.close f)
  tar-file)

;; do we use zip or tar on this archive?
(defn archive-extension [rootname]
  (if (or (in "(Windows" rootname) (not (in "(" rootname))) ".zip" ".tar.gz"))

;; automatically pick the correct archiver - windows or "no arch" = zip
(defn archive-dir [directory-to-archive rootname]
  ((if (= (archive-extension rootname) ".zip") zip-dir tar-dir) directory-to-archive rootname))

;; naive check, whether we have an archive: compare against known suffixes
(defn is-archive? [filename]
  (len (list-comp f [f [".zip" ".tar.gz" ".tgz"]] (.endswith (filename.lower) f))))

;; upload a zipped up package to puredata.info
(defn upload-file [filepath destination username password]
  ;; get username and password from the environment, config, or user input
  (import easywebdav)
  (if filepath
    (do
     (setv filename (os.path.basename filepath))
     (setv [pkg ver _ _] (parse-filename filename))
     (setv url (urlparse destination))
     (setv proto (or url.scheme "https"))
     (setv host (or url.netloc externals-host))
     (setv path
           (str
            (replace-words
             (or (.rstrip url.path "/") "/Members/%u/software/%p/%v")
             (, (, "%u" username) (, "%p" pkg) (, "%v" (or ver ""))))))
     (setv url (+ proto "://" host path))
     (setv dav (apply easywebdav.connect [host] {"username" username "password" password "protocol" proto}))
     (print (+ "Uploading " filename " to " url))
     (try
      (do
       ;; make sure all directories exist
       (dav.mkdirs path)
       ;; upload the package file
       (dav.upload filepath (+ path "/" filename)))
      (except [e easywebdav.client.OperationFailed]
        (sys.exit (+
                   (% "Couldn't upload to %s!\n" url)
                   (% "Are you sure you have the correct username and password set for '%s'?\n" host)
                   (% "Please ensure the folder '%s' exists on the server and is writeable." path))))))))

;; upload a list of archives (given the archive-filename it will also upload some extra-files (sha256, gpg,...))
(defn upload-package [pkg destination username password]
  (print "Uploading package" pkg)
  (upload-file (hash-sum-file pkg) destination username password)
  (upload-file pkg destination username password)
  (upload-file (gpg-sign-file pkg) destination username password))
(defn upload-packages [pkgs destination username password skip-source]
  (if (not skip-source) (check-sources (set (list-comp (filename-to-namever pkg) [pkg pkgs]))
                                       (set (list-comp (has-sources? pkg) [pkg pkgs]))
                                       (if (= "puredata.info"
                                              (.lower (or (getattr (urlparse destination) "netloc") externals-host)))
                                         username)))
  (for [pkg pkgs] (upload-package pkg destination username password)))

;; compute the zipfile name for a particular external on this platform
(defn make-archive-basename [folder version]
  (+ (.rstrip folder "/\\")
     (cond [(nil? version) (sys.exit
                            (+ (% "No version for '%s'!\n" folder)
                               " Please provide the version-number via the '--version' flag.\n"
                               (% " If '%s' doesn't have a proper version number,\n" folder)
                               (% " consider using a date-based fake version (like '0~%s')\n or an empty version ('')."
                                  (.strftime (datetime.date.today) "%Y%m%d"))))]
           [version (% "-v%s-" version)]
           [True ""])
     (get-architecture-strings folder) "-externals"))

;; create additional files besides archive: hash-file and gpg-signature
(defn archive-extra [zipfile]
   (print "Packaging" zipfile)
   (hash-sum-file zipfile)
   (gpg-sign-file zipfile)
   zipfile)

;; parses a filename into a (pkgname version archs extension) tuple
;; missing values are None
(defn parse-filename [filename]
  (list-comp (get
                ;; parse filename with a regex
                (re.split r"(.*/)?(.+?)(-v(.+)-)?((\([^\)]+\))+|-)*-externals\.([a-z.]*)" filename) x)
                ;; extract only the fields of interested
             [x [2 4 5 7]]))
(defn filename-to-namever [filename]
  (join-nonempty "/" (get-values (parse-filename filename) [0 1])))

;; check if the list of archs contains sources (or is arch-independent)
(defn is-source-arch? [arch] (or (not arch) (in "(Sources)" arch)))
;; check if a package contains sources (and returns name-version to be used in a SET of packages with sources)
(defn has-sources? [filename]
  (if (is-source-arch? (try-get (parse-filename filename) 2)) (filename-to-namever filename)))

;; check if the given package has a sources-arch on puredata.info
(defn check-sources@puredata-info [pkg username]
  (import requests)
  (print (% "Checking puredata.info for Source package for '%s'" pkg))
  (in pkg
      ;; list of package/version matching 'pkg' that have 'Source' archictecture
      (list-comp
       (has-sources? p)
       [p
        (list-comp
         (try-get (.split (try-get (.split x "\t") 1) "/") -1)  ; filename part of the download URL
         [x (.splitlines (getattr (requests.get (% "http://deken.puredata.info/search?name=%s" (get (.split pkg "/") 0))) "text"))]
         (= username (try-get (.split x "\t") 2)))])))

;; check if sources archs are present by comparing a SET of packagaes and a SET of packages-with-sources
(defn check-sources [pkgs sources &optional puredata-info-user]
  (for [pkg pkgs] (if (and
                       (not (in pkg sources))
                       (not (and puredata-info-user (check-sources@puredata-info pkg puredata-info-user))))
                    (sys.exit (+ (% "Missing sources for '%s'!\n" pkg)
                                 "(You can override this error with the '--no-source-error' flag,\n"
                                 " if you absolutely cannot provide the sources for this package)\n")))))

;; get the password, either from
;; - a password agent
;; - the config-file (no, not really?)
;; - user-input
;; if force-ask is set, skip the agent
;; store the password in the password agent (for later use)
(defn get-upload-password [username force-ask]
  (or (if (not force-ask)
          (or (try (do
                      (import keyring)
                      (keyring.get_password "deken" username)))
              (get-config-value "password")))
      (getpass (% "Please enter password for uploading as '%s': " username))))

;; the executable portion of the different sub-commands that make up the deken tool
(def commands
  {
   ;; zip up a set of built externals
   :package (fn [args]
              ;; are they asking to package a directory?
              (list-comp
               (if (os.path.isdir name)
                 ;; if asking for a directory just package it up
                 (archive-extra (archive-dir name (make-archive-basename (.rstrip name "/\\") args.version)))
                 (sys.exit (% "Not a directory '%s'!" name)))
               (name args.source)))
   ;; upload packaged external to pure-data.info
   :upload (fn [args]
             (setv username (or (get-config-value "username") (prompt-for-value "username")))
             (setv password (get-upload-password username args.ask-password))
             (upload-packages (list-comp (cond [(os.path.isfile x)
                                                (if (is-archive? x) x (sys.exit (% "'%s' is not an externals archive!" x)))]
                                               [(os.path.isdir x) (get ((:package commands) (set-attr (copy.deepcopy args) "source" [x])) 0)]
                                               [True (sys.exit (% "Unable to process '%s'!" x))])
                                         (x args.source))
                              (or (getattr args "destination") (get-config-value "destination" ""))
                              username password args.no-source-error)
             ;; if we reach this line, upload has succeeded; so let's try storing the (non-empty) password in the keyring
             (if password
               (try (do
                     (import keyring)
                     (keyring.set_password "deken" username password)))))
  ;; the rest should have been caught by the wrapper script
  :upgrade (fn [args] (sys.exit "'upgrade' not implemented for this platform!"))
  :update  (fn [args] (sys.exit "'upgrade' not implemented for this platform!"))
  :install (fn [args] (sys.exit "'install' not implemented for this platform!"))})

;; kick things off by using argparse to check out the arguments supplied by the user
(defn main []
  (print "Deken" version)

  (setv arg-parser
        (apply argparse.ArgumentParser [] {"prog" "deken" "description" "Deken is a build tool for Pure Data externals."}))
  (setv arg-subparsers (apply arg-parser.add_subparsers [] {"help" "-h for help." "dest" "command" "metavar" "{package,upload}"}))
  (setv arg-package (apply arg-subparsers.add_parser ["package"]))
  (setv arg-upload (apply arg-subparsers.add_parser ["upload"]))
  (setv arg-install (apply arg-subparsers.add_parser ["install"]))
  (setv arg-upgrade (apply arg-subparsers.add_parser ["upgrade"] {"aliases" ["update"]}))
  (apply arg-parser.add_argument ["--version"] {"action" "version" "version" version "help" "Outputs the version number of Deken."})
  (apply arg-package.add_argument ["source"]
         {"nargs" "+"
                  "metavar" "SOURCE"
                  "help" "The path to a directory of externals, abstractions, or GUI plugins to be packaged."})
  (apply arg-package.add_argument ["--version" "-v"] {"help" "An external version number to insert into the package name."
                                                             "default" None
                                                             "required" False})
  (apply arg-upload.add_argument ["source"] {"nargs" "+"
                                                     "metavar" "PACKAGE"
                                                     "help" "The path to an externals/abstractions/plugins zipfile to be uploaded, or a directory which will be packaged first automatically."})
  (apply arg-upload.add_argument ["--version" "-v"] {"help" "An external version number to insert into the package name. (in case a package is created)"
                                                            "default" None
                                                            "required" False})
  (apply arg-upload.add_argument ["--destination" "-d"] {"help" "The destination folder to upload the file into (defaults to /Members/USER/software/PKGNAME/VERSION/)." "default" "" "required" False})
  (apply arg-upload.add_argument ["--ask-password" "-P"] {"action" "store_true" "help" "Ask for upload password (rather than using password-manager." "default" "" "required" False})
  (apply arg-upload.add_argument ["--no-source-error"] {"action" "store_true" "help" "Force-allow uploading of packages without sources." "required" False})

  (setv arguments (.parse_args arg-parser))
  (setv command (.get commands (keyword arguments.command)))
  (if command (command arguments) (.print_help arg-parser)))

(if (= __name__ "__main__")
  (try
   (main)
   (except [e KeyboardInterrupt] (print "\n[interrupted by user]"))))
