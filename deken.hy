#!/usr/bin/env hy
; deken build svn://svn.code.sf.net/p/pure-data/svn/trunk/externals/freeverb~/

(import sys)
(import os)
(import argparse)
(import shutil)
(import platform)
(import zipfile)
(import string)
(import struct)
(import ConfigParser)
(import StringIO)
(import hashlib)
(import [getpass [getpass]])

(import easywebdav)
(require hy.contrib.loop)

(def deken-home (os.path.expanduser (os.path.join "~" ".deken")))
(def config-file-path (os.path.abspath (os.path.join deken-home "config")))
(def version (try (.rstrip (.read (file (os.path.join deken-home "VERSION"))) "\r\n") (catch [e Exception] (.get os.environ "DEKEN_VERSION" "0.1"))))
(def pd-repo-uri "git://git.code.sf.net/p/pure-data/pure-data")
(def externals-host "puredata.info")
(def workspace-path (os.path.abspath (os.path.join deken-home "workspace")))
(def pd-path (os.path.join workspace-path "pd"))
(def pd-binary-path (os.path.join pd-path "bin" "pd"))
(def pd-source-path (os.path.join pd-path "src"))
(def externals-build-path (os.path.join workspace-path "externals"))
(def externals-packaging-path (os.path.join workspace-path "pd-externals"))

(def elf-arch-types {
  "EM_NONE" nil
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

(def arm-cpu-arch ["Pre-v4" "v4" "v4T" "v5T" "v5TE" "v5TEJ" "v6" "v6KZ" "v6T2" "v6K" "v7"])

(def win-types {
  "0x014c" ["i386" 32]
  "0x0200" ["x86_64" 64]
  "0x8664" ["amd64" 64]})

; algorithm to use to hash files
(def hasher hashlib.sha256)
(def hash-extension (.pop (hasher.__name__.split "_")))

; get the externals' homedir install location for this platform - from s_path.c
(def externals-folder
  (let [[system-name (platform.system)]]
    (cond
      [(in system-name ["Linux" "FreeBSD"]) (os.path.expandvars (os.path.join "$HOME" "pd-externals"))]
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
    [file-buffer (StringIO.StringIO (+ "[default]\n" (try (.read (open config-file-path "r")) (catch [e Exception] ""))))]]
      (config-file.readfp file-buffer)
      (dict (config-file.items "default"))))

; create an architecture string - deprecated for get-architecture-strings
(defn arch-string [&rest args]
  (let [[arch (list-comp a [a (apply platform.architecture args)] a)]]
    (.join "-" arch)))

; obsolete: get a string we can use to specify/determine the build architecture of the current platform
; (we now inspect binaries directly)
(defn get-architecture-prefix []
  (.join "-" [
     (platform.system)
     (platform.machine)
     (if (os.path.isfile pd-binary-path)
       (arch-string pd-binary-path)
       (arch-string))]))

; takes the externals architectures and turns them into a string
(defn get-architecture-strings [folder]
  (let [[archs (get-externals-architectures folder)]
        [sep-1 ")("]
        [sep-2 "-"]]
    (if archs
      (+ "(" (sep-1.join (set (list-comp (sep-2.join (list-comp (str a) [a arch])) [arch archs]))) ")")
      "")))

; check if a particular file has an extension in a set
(defn test-extensions [filename extensions]
  (len (list-comp e [e extensions] (filename.endswith e))))

; examine a folder for externals and return the architectures of those found
(defn get-externals-architectures [folder]
  (sum (list-comp (cond
      [(test-extensions f [".pd_linux" ".l_ia64" ".l_i386" ".l_arm" ".so"]) (get-elf-arch (os.path.join folder f) "Linux")]
      [(test-extensions f [".pd_freebsd" ".b_i386"]) (get-elf-arch (os.path.join folder f) "FreeBSD")]
      [(test-extensions f [".pd_darwin" ".d_fat" ".d_ppc"]) (get-mach-arch (os.path.join folder f))]
      [(test-extensions f [".m_i386" ".dll"]) (get-windows-arch (os.path.join folder f))]
      [true []])
    [f (os.listdir folder)]) []))

; get architecture strings from a windows DLL
; http://stackoverflow.com/questions/495244/how-can-i-test-a-windows-dll-to-determine-if-it-is-32bit-or-64bit
(defn get-windows-arch [filename]
  (let [[f (file filename)]
        [[magic blah offset] (struct.unpack (str "<2s58sL") (f.read 64))]]
    ;(print magic offset)
    (if (= magic "MZ")
      ; has correct magic bytes
      (do
        (f.seek offset)
        (let [[[sig skip machine] (struct.unpack (str "<2s2sH") (f.read 6))]]
          ;(print sig (% "0x%04x" machine))
          (if (= sig "PE")
            ; has correct signature
            [(+ ["Windows"] (win-types.get (% "0x%04x" machine) ["unknown" "unknown"]))]
            (raise (Exception "Not a PE Executable.")))))
      (raise (Exception "Not a valid Windows dll.")))))

; get architecture from an ELF (e.g. Linux)
(defn get-elf-arch [filename oshint]
  (import [elftools.elf.elffile [ELFFile]])
  (let [[elf (ELFFile (file filename))]]
    ; TODO: check section .ARM.attributes for v number
    ; python ./virtualenv/bin/readelf.py -p .ARM.attributes ...
    [[oshint (+ (elf-arch-types.get (elf.header.get "e_machine") nil) (or (parse-arm-elf-arch elf) "")) (int (slice (.get (elf.header.get "e_ident") "EI_CLASS") -2))]]))

; get architecture from a Darwin Mach-O file (OSX)
(defn get-mach-arch [filename]
  (import [macholib.MachO [MachO]])
  (import [macholib.mach_o [MH_MAGIC_64 CPU_TYPE_NAMES]])
  (let [[macho (MachO filename)]]
    (list-comp ["Darwin" (CPU_TYPE_NAMES.get h.header.cputype h.header.cputype) (if (= h.MH_MAGIC MH_MAGIC_64) 64 32)] [h macho.headers])))

; gets the specific flavour of arm by hacking the .ARM.attributes ELF section
(defn parse-arm-elf-arch [arm-elf]
  (let [[arm-section (if arm-elf (try (arm-elf.get_section_by_name ".ARM.attributes")))]
        [data (and arm-section (.startswith (arm-section.data) "A") (.index (arm-section.data) "aeabi") (.pop (.split (arm-section.data) "aeabi")))]]
        (if data (do
            ; (print (struct.unpack (str "<s") (slice data 7)))
            (let [[[name bins] (.split (slice data 7) "\x00")]
                  [arch (get arm-cpu-arch (ord (slice bins 1 2)))]]
              arch)))))

; try to obtain a value from environment, then config file, then prompt user
(defn get-config-value [name &rest default]
  (or
    (os.environ.get (+ "DEKEN_" (name.upper)))
    (config.get name)
    (and default (get default 0))))

; prompt for a particular config value for externals host upload
(defn prompt-for-value [name]
  (raw_input (% (+
    "Environment variable DEKEN_%s is not set and the config file %s does not contain a '%s = ...' entry.\n"
    "To avoid this prompt in future please add a setting to the config or environment.\n"
    "Please enter %s for http://%s/: ")
      (tuple [(name.upper) config-file-path name name externals-host]))))

; caculate the sha256 hash of a file
(defn hash-sum-file [filename]
  (let [[hashfn (hasher)]
        [blocksize 65536]
        [f (file filename)]
        [read-chunk (fn [] (f.read blocksize))]]
    (loop [[buf (read-chunk)]]
          (if (len buf) (do
            (hashfn.update buf)
            (recur (read-chunk)))))
    (let [[digest (hashfn.hexdigest)]
          [hashfilename (% "%s.%s" (tuple [filename hash-extension]))]]
      (.write (file hashfilename "wb") digest)
      hashfilename)))

; read a value from the gpg config
(defn gpg-get-config [gpg id]
  (let [
        [configdir (cond [gpg.gnupghome gpg.gnupghome] [True (os.path.join "~" ".gnupg")])]
        [configfile (os.path.expanduser (os.path.join configdir "gpg.conf"))]
        ]
    (try
     (get (list-comp (get (.split (.strip x)) 1) [x (.readlines ( open configfile))] (.startswith (.lstrip x) (.strip id) )) -1)
     (catch [e IOError] None)
     (catch [e IndexError] None))))

; get the GPG key for signing
(defn gpg-get-key [gpg]
  (let [
        [keyid (get-config-value "key_id" (gpg-get-config gpg "default-key"))]
        ]
    (try
     (car (list-comp k [k (gpg.list_keys true)] (cond [keyid (.endswith (.upper (get k "keyid" )) (.upper keyid) )] [True True])))
     (catch [e IndexError] None))))

; generate a GPG signature for a particular file
(defn gpg-sign-file [filename]
  (print "Attempting to GPG sign" filename)
  (let [[gnupghome (get-config-value "gpg_home")]
        [gpg (try (do
                   (import gnupg)
                   (apply gnupg.GPG [] (if gnupghome {"gnupghome" gnupghome} {}))))]
        [sec-key (gpg-get-key gpg)]
        [keyid (try (get sec-key "keyid") (catch [e KeyError] None) (catch [e TypeError] None))]
        [uid (try (get (get sec-key "uids") 0) (catch [e KeyError] None) (catch [e TypeError] None))]

        [passphrase (if keyid
                      (do
                       (print (% "You need a passphrase to unlock the secret key for\nuser: %s ID: %s\nin order to sign %s" (tuple [uid keyid filename])))
                       (getpass "Enter GPG passphrase: " ))
                      (print "No valid GPG key found (continue without signing)"))]
        [sig (if gpg (apply gpg.sign_file [(file filename "rb")] (if keyid {"keyid" keyid "detach" true "passphrase" passphrase} {"detach" true "passphrase" passphrase})))]
        [signfile (+ filename ".asc")]]
    (do
     (if (hasattr sig "stderr")
       (print sig.stderr))
     (if (not sig)
       (do
        print "WARNING: Could not GPG sign the package."
        None)
       (do
        (.write (file signfile "wb") (str sig))
        signfile)))))

; get access to a command line binary in a way that checks for it's existence and reacts to errors correctly
(defn get-binary [binary-name]
  (import sh)
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
    ((get-binary "git") "clone" repo-uri destination)
    ((get-binary "svn") "checkout" repo-uri destination)))

; uses git or svn to update the repository
(defn update [repo-uri destination]
  (if (is-git? repo-uri)
    (in-dir destination (get-binary "git") "pull")
    (in-dir destination (get-binary "svn") "update")))

; uses make to install an external
(defn install-one [build-folder destination-folder]
  ((get-binary "make") "-C" build-folder (get strip-flag (keyword (platform.system))) (% "DESTDIR='%s'" destination-folder) "objectsdir=''" "install"))

; uses make to build an external
(defn build-one [build-folder]
  ((get-binary "make") "-C" build-folder (% "PD_PATH=%s" pd-source-path) (% "CFLAGS=-DPD -DHAVE_G_CANVAS_H -I%s -Wall -W" pd-source-path)))

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

; upload a zipped up package to pure-data.info
(defn upload-package [filepath username password]
  (let [
    ; get username and password from the environment, config, or user input
    [filename (os.path.basename filepath)]
    [destination (+ "/Members/" username "/" filename)]
    [dav (apply easywebdav.connect [externals-host] {"username" username "password" password})]]
      (print (+ "Uploading to http://" externals-host destination))
      (try
        ; upload the package file
        (dav.upload filepath destination)
        (catch [e easywebdav.client.OperationFailed]
          (print (+ "Couldn't upload to http://" externals-host destination))
          (print (% "Are you sure you have the correct username and password set for <http://%s/>?" externals-host))
          (sys.exit 1)))))

; get the name of the external from the repository path
(defn get-external-name [repo-uri]
  (if (os.path.isdir repo-uri)
    (os.path.basename (os.path.abspath repo-uri))
    (os.path.basename (.rstrip (.rstrip repo-uri "/") ".git"))))

; get the destination the external should go into
(defn get-external-build-folder [external-name]
  (os.path.join externals-build-path external-name))

; compute the zipfile name for a particular external on this platform
(defn make-zipfile-name [folder version]
  (+ (.rstrip folder "/\\") (if version (% "-v%s-" version) "") (get-architecture-strings folder) "-externals.zip"))

; the executable portion of the different sub-commands that make up the deken tool
(def commands {
  ; download and build a particular external from a repository
  :build (fn [args]
    (let [
      [external-name (get-external-name args.repository)]
      [build-folder (get-external-build-folder external-name)]
      [pd-dir (ensure-pd)]]
        (if (os.path.isdir args.repository)
          (do
            (print "Building" external-name)
            (build-one args.repository))
          (do
            (ensure-checked-out args.repository build-folder)
            (print "Building" build-folder)
            (build-one build-folder)))))
  ; install a particular external into the user's pd-externals directory
  :install (fn [args]
    (let [
      [external-name (get-external-name args.repository)]
      [build-folder (get-external-build-folder external-name)]]
        ; make sure the repository is built
        ((:build commands) args)
        ; go ahead and perform the install
        (print (% "Installing %s into %s" (tuple [external-name externals-folder])))
        ; if they asked for a specific directory to be installed, do that
        (if (os.path.isdir args.repository)
          (install-one args.repository externals-folder)
          (install-one build-folder externals-folder))))
  ; zip up a set of built externals
  :package (fn [args]
    ; are they asking the package a directory or an existing repository?
    (if (os.path.isdir args.repository)
      ; if asking for a directory just package it up
      (let [[package-filename (make-zipfile-name args.repository args.version)]]
        (print "Packaging into" package-filename)
        (zip-dir args.repository package-filename)
        package-filename)
      ; otherwise build and then package
      (let [
        [external-name (get-external-name args.repository)]
        [build-folder (get-external-build-folder external-name)]
        [package-folder (os.path.join externals-packaging-path external-name)]
        [package-filename (make-zipfile-name package-folder args.version)]]
          ((:build commands) args)
          (install-one build-folder externals-packaging-path)
          (print "Packaging into" package-filename)
          (zip-dir package-folder package-filename)
          package-filename)))
  ; upload packaged external to pure-data.info
  :upload (fn [args]
    (if (os.path.isfile args.repository)
      ; user has asked to upload a zipfile
      (if (args.repository.endswith ".zip")
        (do
         (print (+ "Uploading " args.repository))
         (let [
               [signedfile (gpg-sign-file args.repository)]
               [hashfile   (hash-sum-file args.repository)]
               [username (or (get-config-value "username") (prompt-for-value "username"))]
               [password (or (get-config-value "password") (getpass "Please enter password for uploading: "))]
               ]
           (do
            (upload-package hashfile username password)
            (upload-package args.repository username password)
            (if signedfile
              (upload-package signedfile username password)))))
        (do
          (print "Not an externals zipfile.")
          (sys.exit 1)))
      ; otherwise we need to make the zipfile first
      (let [[args.repository ((:package commands) args)]]
        ; recurse - call myself again now that we have a package file
        ((:upload commands) args))))
  ; manipulate the version of Pd
  :pd (fn [args]
    (let [
      [destination (ensure-pd)]
      [deken-home (os.getcwd)]]
        (os.chdir destination)
        (if args.version
          ((get-binary "git") "checkout" args.version))
        ; tell the user what version is currently checked out
        (print (% "Pd version %s checked out" (.rstrip ((get-binary "git") "rev-parse" "--abbrev-ref" "HEAD"))))
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
(defn main []
  (let [
    [arg-parser (apply argparse.ArgumentParser [] {"prog" "deken" "description" "Deken is a build tool for Pure Data externals."})]
    [arg-subparsers (apply arg-parser.add_subparsers [] {"help" "-h for help." "dest" "command"})]
    [arg-build (apply arg-subparsers.add_parser ["build"])]
    [arg-install (apply arg-subparsers.add_parser ["install"])]
    [arg-package (apply arg-subparsers.add_parser ["package"])]
    [arg-upload (apply arg-subparsers.add_parser ["upload"])]
    [arg-upgrade (apply arg-subparsers.add_parser ["upgrade"])]
    [arg-clean (apply arg-subparsers.add_parser ["clean"] {"help" "Deletes all files from the workspace folder."})]
    [arg-pd (apply arg-subparsers.add_parser ["pd"])]]
      (apply arg-parser.add_argument ["--version"] {"action" "version" "version" version "help" "Outputs the version number of Deken."})
      (apply arg-parser.add_argument ["--platform"] {"action" "version" "version" (get-architecture-prefix) "help" "Outputs the current build platform identifier string."})
      (apply arg-build.add_argument ["repository"] {"help" "The SVN or git repository of the external to build."})
      (apply arg-install.add_argument ["repository"] {"help" "The SVN or git repository of the external to install."})
      (apply arg-package.add_argument ["repository"] {"help" "Either the path to a directory of externals to be packaged, or the SVN or git repository of an external to package."})
      (apply arg-package.add_argument ["--version" "-v"] {"help" "An external version number to insert into the package name." "default" "" "required" false})
      (apply arg-upload.add_argument ["repository"] {"help" "Either the path to an external zipfile to be uploaded, or the SVN or git repository of an external to package."})
      (apply arg-upload.add_argument ["--version" "-v"] {"help" "An external version number to insert into the package name." "default" "" "required" false})
      (apply arg-pd.add_argument ["version"] {"help" "Fetch a particular version of Pd to build against." "nargs" "?"})
      (let [
        [arguments (.parse_args arg-parser)]
        [command (.get commands (keyword arguments.command))]]
          (print "Deken" version)
          (command arguments))))

(if (= __name__ "__main__")
  (try
   (main)
   (catch [e KeyboardInterrupt] (print "\n[interrupted by user]"))))
