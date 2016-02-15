#!/usr/bin/env hy
; deken upload --version 0.1 ./freeverb~/

(import sys)
(import os)
(import re)
(import argparse)

(import platform)
(import zipfile)
(import tarfile)
(import string)
(import struct)
(import copy)
(import ConfigParser)
(import StringIO)
(import hashlib)
(import [getpass [getpass]])
(import [urlparse [urlparse]])
(import requests)
(import easywebdav)

(require hy.contrib.loop)

(def deken-home (os.path.expanduser (os.path.join "~" ".deken")))
(def config-file-path (os.path.abspath (os.path.join deken-home "config")))
(def version (try (.rstrip (.read (file (os.path.join deken-home "VERSION"))) "\r\n") (catch [e Exception] (.get os.environ "DEKEN_VERSION" "0.1"))))
(def externals-host "puredata.info")

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

; convert a string into bool, based on the string value
(defn str-to-bool [s] (and (not (nil? s)) (not (in (.lower s) ["false" "f" "no" "n" "0" "nil" "none"]))))

;; join non-empty elements
(defn join-nonempty [joiner elements] (.join joiner (list-comp (str x) [x elements] x)))

; concatenate two dictionaries - hylang's assoc is broken
(defn dict-merge [d1 d2] (apply dict [d1] (or d2 {})))

; apply attributes to objects in a functional way
(defn set-attr [obj attr value] (do (setattr obj attr value) obj))

; replace multiple words (given as pairs in <repls>) in a string <s>
(defn replace-words [s repls] (reduce (fn [a kv] (apply a.replace kv)) repls s))

;; get a value at an index or a default
(defn try-get [elements index &optional default] (try (get elements index) (catch [e IndexError] default)))

; read in the config file if present
(def config
  (let [
    [config-file (ConfigParser.SafeConfigParser)]
    [file-buffer (StringIO.StringIO (+ "[default]\n" (try (.read (open config-file-path "r")) (catch [e Exception] ""))))]]
      (config-file.readfp file-buffer)
      (dict (config-file.items "default"))))

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
      [(test-extensions f [".c" ".cpp" ".C" ".cxx" ".cc"]) [["Sources"]]]
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
   (first (filter (fn [x] (not (nil? x))) [
     ; try to get the value from an environment variable
     (os.environ.get (+ "DEKEN_" (name.upper)))
     ; try to get the value from the config file
     (config.get name)
     ; finally, try the default
     (first default)])))

; prompt for a particular config value for externals host upload
(defn prompt-for-value [name]
  (raw_input (% (+
    "Environment variable DEKEN_%s is not set and the config file %s does not contain a '%s = ...' entry.\n"
    "To avoid this prompt in future please add a setting to the config or environment.\n"
    "Please enter %s for http://%s/: ")
      (tuple [(name.upper) config-file-path name name externals-host]))))

; calculate the sha256 hash of a file
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
  (let [[configdir (cond [gpg.gnupghome gpg.gnupghome] [True (os.path.join "~" ".gnupg")])]
        [configfile (os.path.expanduser (os.path.join configdir "gpg.conf"))]]
    (try
     (get (list-comp (get (.split (.strip x)) 1) [x (.readlines ( open configfile))] (.startswith (.lstrip x) (.strip id) )) -1)
     (catch [e IOError] None)
     (catch [e IndexError] None))))

; get the GPG key for signing
(defn gpg-get-key [gpg]
  (let [[keyid (get-config-value "key_id" (gpg-get-config gpg "default-key"))]]
    (try
     (car (list-comp k [k (gpg.list_keys true)] (cond [keyid (.endswith (.upper (get k "keyid" )) (.upper keyid) )] [True True])))
     (catch [e IndexError] None))))

; generate a GPG signature for a particular file
(defn do-gpg-sign-file [filename signfile]
  (print (% "Attempting to GPG sign '%s'" filename))
  (let [[gnupghome (get-config-value "gpg_home")]
        [use-agent (str-to-bool (get-config-value "gpg_agent"))]
        [gpgconfig {}]
        [gpgconfig (dict-merge gpgconfig (if gnupghome {"gnupghome" gnupghome}))]
        [gpgconfig (dict-merge gpgconfig (if use-agent {"use_agent" true}))]
        [gpg (try (do
                   (import gnupg)
                   (set-attr (apply gnupg.GPG [] gpgconfig) "decode_errors" "replace")))]
        [sec-key (gpg-get-key gpg)]
        [keyid (try (get sec-key "keyid") (catch [e KeyError] None) (catch [e TypeError] None))]
        [uid (try (get (get sec-key "uids") 0) (catch [e KeyError] None) (catch [e TypeError] None))]
        [signconfig {"detach" true}]
        [signconfig (dict-merge signconfig (if keyid {"keyid" keyid}))]
        [passphrase (if (and (not use-agent) keyid)
                      (do
                       (print (% "You need a passphrase to unlock the secret key for\nuser: %s ID: %s\nin order to sign %s" (tuple [uid keyid filename])))
                       (getpass "Enter GPG passphrase: " )))]
        [signconfig (dict-merge signconfig (if passphrase {"passphrase" passphrase}))]]
    (if (and (not use-agent) passphrase)
      (print "No valid GPG key found (continue without signing)"))
    (let [[sig (if gpg (apply gpg.sign_file [(file filename "rb")] signconfig))]
          [signfile (+ filename ".asc")]]
      (if (hasattr sig "stderr")
        (print (try (str sig.stderr) (catch [e UnicodeEncodeError] (.encode sig.stderr "utf-8")))))
      (if (not sig)
        (do
         (print "WARNING: Could not GPG sign the package.")
         None)
        (do
         (.write (file signfile "wb") (str sig))
         signfile)))))

; sign a file if it is not already signed
(defn gpg-sign-file [filename]
  (let [[signfile (+ filename ".asc")]]
    (if (os.path.exists signfile)
      (do
       (print (% "NOTICE: not GPG-signing already signed file '%s'\nNOTICE: delete '%s' to re-sign" (, filename signfile)))
       signfile)
      (do-gpg-sign-file filename signfile))))

; execute a command inside a directory
(defn in-dir [destination f &rest args]
  (let [
    [last-dir (os.getcwd)]
    [new-dir (os.chdir destination)]
    [result (apply f args)]]
      (os.chdir last-dir)
      result))

; zip up a single directory
; http://stackoverflow.com/questions/1855095/how-to-create-a-zip-archive-of-a-directory
(defn zip-dir [directory-to-zip archive-file]
  (let [[zip-file (+ archive-file ".zip")]
        [zipf (try (zipfile.ZipFile zip-file "w" :compression zipfile.ZIP_DEFLATED)
                   (catch [e RuntimeError] (zipfile.ZipFile zip-file "w")))]
        [root-basename (os.path.basename directory-to-zip)]
        [root-path (os.path.join directory-to-zip "..")]]
    (for [[root dirs files] (os.walk directory-to-zip)]
      (for [file files]
        (let [[file-path (os.path.join root file)]]
          (zipf.write file-path (os.path.relpath file-path root-path)))))
    (zipf.close)
    zip-file))

; tar up the directory
(defn tar-dir [directory-to-tar archive-file]
  (let [[tar-file (+ archive-file ".tar.gz")]
        [tarf (tarfile.open tar-file "w:gz")]]
    (do
     (.add tarf directory-to-tar)
     (.close tarf)
     tar-file)))

; do we use zip or tar on this archive?
(defn archive-extension [rootname]
  (if (or (in "(Windows" rootname) (not (in "(" rootname))) ".zip" ".tar.gz"))

; automatically pick the correct archiver - windows or "no arch" = zip
(defn archive-dir [directory-to-archive rootname]
  (let [[ext (archive-extension rootname)]]
    ((if (= ext ".zip") zip-dir tar-dir) directory-to-archive rootname)))

; naive check, whether we have an archive: compare against known suffixes
(defn is-archive? [filename]
  (len (list-comp f [f [".zip" ".tar.gz" ".tgz"]] (.endswith (filename.lower) f))))

; upload a zipped up package to puredata.info
(defn upload-file [filepath destination username password]
  (if filepath
   (let [
    ;; get username and password from the environment, config, or user input
    [filename (os.path.basename filepath)]
    [[pkg ver arch ext] (parse-filename filename)]
    [url (urlparse destination)]
    [proto (or url.scheme "https")]
    [host (or url.netloc externals-host)]
    [path (str (replace-words (or (.rstrip url.path "/") "/Members/%u/software/%p/%v") (,
                         (, "%u" username) (, "%p" pkg) (, "%v" (or ver "")))))]
    [remotepath (+ path "/" filename)]
    [url (+ proto "://" host path)]
    [dav (apply easywebdav.connect [host] {"username" username "password" password "protocol" proto})]]
      (print (+ "Uploading " filename " to " url))
      (try
        (do
          ; make sure all directories exist
          (dav.mkdirs path)
          ; upload the package file
          (dav.upload filepath remotepath))
        (catch [e easywebdav.client.OperationFailed]
          (sys.exit (+
                     (% "Couldn't upload to %s!\n" url)
                     (% "Are you sure you have the correct username and password set for '%s'?\n" host)
                     (% "Please ensure the folder '%s' exists on the server and is writeable." path))))))))
;; upload a list of archives (given the archive-filename it will also upload some extra-files (sha256, gpg,...))
(defn upload-package [pkg destination username password]
  (do
   (print "Uploading package" pkg)
   (upload-file (hash-sum-file pkg) destination username password)
   (upload-file pkg destination username password)
   (upload-file (gpg-sign-file pkg) destination username password)))
(defn upload-packages [pkgs destination username password skip-source]
  (do (if (not skip-source) (check-sources (set (list-comp (filename-to-namever pkg) [pkg pkgs]))
                                           (set (list-comp (has-sources? pkg) [pkg pkgs]))
                                           (if (= "puredata.info"
                                                  (.lower (or (getattr (urlparse destination) "netloc") externals-host)))
                                             username)))
      (for [pkg pkgs] (upload-package pkg destination username password))))

; compute the zipfile name for a particular external on this platform
(defn make-archive-basename [folder version]
  (+ (.rstrip folder "/\\") (if version (% "-v%s-" version) "") (get-architecture-strings folder) "-externals"))

; create additional files besides archive: hash-file and gpg-signature
(defn archive-extra [zipfile]
  (do
   (print "Packaging" zipfile)
   (hash-sum-file zipfile)
   (gpg-sign-file zipfile)
   zipfile))

; parses a filename into a (pkgname version archs extension) tuple
; missing values are nil
(defn parse-filename [filename]
  (list-comp (get
                ; parse filename with a regex
                (re.split r"(.*/)?(.+?)(-v(.+)-)?((\([^\)]+\))+|-)*-externals\.([a-z.]*)" filename) x)
                ; extract only the fields of interested
             [x [2 4 5 7]]))
(defn filename-to-namever [filename]
  (let [[[pkg ver arch ext] (parse-filename filename)]] (join-nonempty "/" [pkg ver])))

;; check if the list of archs contains sources (or is arch-independent)
(defn is-source-arch? [arch] (or (not arch) (in "(Sources)" arch)))
;; check if a package contains sources (and returns name-version to be used in a SET of packages with sources)
(defn has-sources? [filename] (let [[[pkg ver arch ext] (parse-filename filename)]]
                                (if (is-source-arch? arch) (filename-to-namever filename))))

;; check if the given package has a sources-arch on puredata.info
(defn check-sources@puredata-info [pkg username]
  (do (print (% "Checking puredata.info for Source package for '%s'" pkg))
      (in pkg
          ;; list of package/version matching 'pkg' that have 'Source' archictecture
          (list-comp
           (has-sources? p)
           [p
            (list-comp
             (try-get (.split (try-get (.split x "\t") 1) "/") -1) ;; filename part of the download URL
             [x (.splitlines (getattr (requests.get (% "http://deken.puredata.info/search?name=%s" (get (.split pkg "/") 0))) "text"))]
             (= username (try-get (.split x "\t") 2)))]))))

;; check if sources archs are present by comparing a SET of packagaes and a SET of packages-with-sources
(defn check-sources [pkgs sources &optional puredata-info-user]
  (for [pkg pkgs] (if (and
                       (not (in pkg sources))
                       (not (and puredata-info-user (check-sources@puredata-info pkg puredata-info-user))))
                    (sys.exit (% "Missing sources for '%s'!" pkg)))))

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

; the executable portion of the different sub-commands that make up the deken tool
(def commands {
  ; zip up a set of built externals
  :package (fn [args]
    ;; are they asking to package a directory?
    (list-comp
      (if (os.path.isdir name)
      ; if asking for a directory just package it up
        (archive-extra (archive-dir name (make-archive-basename name args.version)))
        (sys.exit (% "Not a directory '%s'!" name)))
      (name args.source)))
  ; upload packaged external to pure-data.info
  :upload (fn [args]
            (let [[username (or (get-config-value "username") (prompt-for-value "username"))]
                  [password (get-upload-password username args.ask-password)]]
              (do
               (upload-packages (list-comp (cond [(os.path.isfile x)
                                                  (if (is-archive? x) x (sys.exit (% "'%s' is not an externals archive!" x)))]
                                                 [(os.path.isdir x) (get ((:package commands) (set-attr (copy.deepcopy args) "source" [x])) 0)]
                                                 [True (sys.exit (% "Unable to process '%s'!" x))])
                                           (x args.source))
                                (or (getattr args "destination") (get-config-value "destination" ""))
                                username password args.no-source-error))
              ;; if we reach this line, upload has succeeded; so let's try storing the (non-empty) password in the keyring
              (if password
                (try (do
                      (import keyring)
                      (keyring.set_password "deken" username password))))))
  ; self-update deken
  :upgrade (fn [args]
    (sys.exit "The upgrade script isn't here, it's in the Bash wrapper!"))})

; kick things off by using argparse to check out the arguments supplied by the user
(defn main []
  (let [
    [arg-parser (apply argparse.ArgumentParser [] {"prog" "deken" "description" "Deken is a build tool for Pure Data externals."})]
    [arg-subparsers (apply arg-parser.add_subparsers [] {"help" "-h for help." "dest" "command"})]
    [arg-package (apply arg-subparsers.add_parser ["package"])]
    [arg-upload (apply arg-subparsers.add_parser ["upload"])]
    [arg-upgrade (apply arg-subparsers.add_parser ["upgrade"])]]
      (apply arg-parser.add_argument ["--version"] {"action" "version" "version" version "help" "Outputs the version number of Deken."})
      (apply arg-package.add_argument ["source"] {"nargs" "*"
                                                  "help" "The path to a directory of externals, abstractions, or GUI plugins to be packaged."})
      (apply arg-package.add_argument ["--version" "-v"] {"help" "An external version number to insert into the package name." "default" "" "required" false})
      (apply arg-upload.add_argument ["source"] {"nargs" "*"
                                                 "help" "The path to an externals/abstractions/plugins zipfile to be uploaded, or a directory which will be packaged first automatically."})
      (apply arg-upload.add_argument ["--version" "-v"] {"help" "An external version number to insert into the package name." "default" "" "required" false})
      (apply arg-upload.add_argument ["--destination" "-d"] {"help" "The destination folder to upload the file into (defaults to /Members/USER/software/PKGNAME/VERSION/)." "default" "" "required" false})
      (apply arg-upload.add_argument ["--ask-password" "-P"] {"action" "store_true" "help" "Ask for upload password (rather than using password-manager." "default" "" "required" false})
      (apply arg-upload.add_argument ["--no-source-error"] {"action" "store_true" "help" "Force-allow uploading of packages without sources." "required" false})
      (let [
        [arguments (.parse_args arg-parser)]
        [command (.get commands (keyword arguments.command))]]
          (print "Deken" version)
          (command arguments))))

(if (= __name__ "__main__")
  (try
   (main)
   (catch [e KeyboardInterrupt] (print "\n[interrupted by user]"))))
