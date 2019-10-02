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
(import logging)

(try (import [configparser [ConfigParser :as SafeConfigParser]])
     (except [e ImportError] (import [ConfigParser [SafeConfigParser]])))
(try (import [io [StringIO]])
     (except [e ImportError] (import [StringIO [StringIO]])))
(try (import [urllib.parse [urlparse]])
     (except [e ImportError] (import [urlparse [urlparse]])))

(require hy.contrib.loop)

;; setup logging
(setv log (logging.getLogger "deken"))
(log.addHandler (logging.StreamHandler))

;; do nothing
(defn nop [&rest args] "does nothing; returns None" None)

;; simple debugging helper: prints an object and returns it
(defn debug [x] "print the argument and return it" (log.debug x) x)

;; print a fatal error and exit with an error code
(defn fatal [x]
  "print argument as an error message and exit"
  (log.fatal x)
  (sys.exit 1))

(setv deken-home (os.path.expanduser (os.path.join "~" ".deken")))
(setv config-file-path (os.path.abspath (os.path.join deken-home "config")))
(setv version (or
                (.get os.environ "DEKEN_VERSION" None)
                (if (os.path.exists
                      (os.path.join
                        (os.path.dirname (os.path.dirname
                                           (os.path.abspath __file__))) ".git"))
                    (try (do
                           (import subprocess)
                           (.strip (.decode (subprocess.check_output ["git" "describe" "--always"]))))
                         (except [e Exception] None)))
                "<unknown.version>"))
(setv default-destination (urlparse "https://puredata.info/Members/%u/software/%p/%v"))
(setv default-searchurl "https://deken.puredata.info/search")
(setv default-installpath
      (os.path.expandvars (os.path.expanduser
                            (cond
                              [(= sys.platform "darwin") "~/Library/Pd"]
                              [(= sys.platform "win32") "%AppData%/Pd"]
                              [True "~/.local/lib/pd/extra/"]))))

(setv architecture-substitutes
      {
       "x86_64" ["amd64"]
       "amd64" ["x86_64"]
       "i686" ["i586" "i386"]
       "i586" ["i386"]
       "armv6l" [ "armv6" "arm"]
       "armv7l" [ "armv7" "armv6l" "armv6" "arm"]
       "PowerPC" [ "ppc"]
       "ppc" [ "PowerPC"]
       })

(setv default-floatsize None)

;; check whether a form executes or not
(eval-when-compile
  (defmacro runs? [exp]
    `(try (do ~exp True) (except [] False))))

(defn binary-file? [filename]
  "checks if <filename> contains binary data"
  ;; files that contain '\0' are considered binary
  ;; UTF-16 can contain '\0'; but for our purposes, its a binary format :-)
  (defn contains? [f &optional [needle "\0"]]
    (setv data (f.read 1024))
    (cond
      [(not data) False]
      [(in needle data) True]
      [True (contains? f needle)]))
  (try
    (with [f (open filename "rb")]
      (contains? f (str-to-bytes "\0")))
    (except [e Exception]
      (log.debug e))))

(defn stringify-tuple [t]
  (if t
      (tuple (lfor x t (if (is x None) "" (.lower (str x)))))
      (tuple)))

(defn str-to-bytes [s]
  "convert a string into bytes"
  (try (bytes s) (except [e TypeError] (bytes s "utf-8"))))

(defn str-to-bool [s]
  "convert a string into a bool, based on its value"
  (and (not (is s None)) (not (in (.lower s) ["false" "f" "no" "n" "0" "nil" "none"]))))

(defn byte-to-int [b]
  "convert a single byte (e.g. an element of bytes()) into an integer"
  (try (ord b) (except [e TypeError] (int b))))

(defn join-nonempty [joiner elements]
  "join all non-empty (non-false) elements"
  (.join joiner (lfor x elements :if x (str x))))

;; concatenate dictionaries - hylang's assoc is broken
(defn dict-merge [dict0 &rest dicts]
  "merge several dictionaries; if a key exists in more than one dict, the latet takes precedence"
  (defn dict-merge-aux [dict0 dicts]
    (for [d dicts] (if d (dict0.update d)))
    dict0)
  ;; we need the aux just to prevent side-effects on dict0
  (dict-merge-aux (.copy dict0) dicts))

;; apply attributes to objects in a functional way
(defn set-attr [obj attr value]
  "sets an attribute of an obj in a functional way (returns the obj)"
  (setattr obj attr value) obj)

;; get multiple attributes as list
(defn get-attrs [obj attributes &optional default]
  "returns a list of values, one for each attr in <attributes>"
  (lfor _ attributes (getattr obj _default)))

;; get multiple values from a dict (give keys as list, get values as list)
(defn get-values [coll keys]
  "returns a list of values from a dictionary, pass the keys as list"
  (lfor _ keys (get coll _)))

;; get a value at an index/key or a default
(defn try-get [elements index &optional default]
  "get a value at an index/key, falling back to a default"
  (try (get elements index)
       (except [e TypeError] default)
       (except [e KeyError] default)
       (except [e IndexError] default)))

;; replace multiple words (given as pairs in <repls>) in a string <s>
(defn replace-words [s repls]
  "replace multiple words (given as pairs in <repls>) in a string <s>"
  (reduce (fn [a kv] (a.replace #* kv)) repls s))

;; execute a command inside a directory
(defn in-dir [destination f &rest args]
  "execute a command f(args) inside a directory"
  (setv last-dir (os.getcwd))
  (os.chdir destination)
  (setv result (f #* args))
  (os.chdir last-dir)
  result)

;; TODO: refactor 'listdir' and 'get-files-from-dir' into a single function

(defn fix-easywebdav2 [pkg &optional
                       [broken "            for dir_ in dirs:\n                try:\n                    self.mkdir(dir, safe=True, **kwargs)"]
                       [fixed "            for dir_ in dirs:\n                try:\n                    self.mkdir(dir_, safe=True, **kwargs)"]]
  "try to patch easywebdav2, it's broken as of 1.3.0"
  (try
    (do
      (setv filename (os.path.join (os.path.dirname pkg.__file__) "client.py"))
      (with [f (open filename "r")]
        (setv data (f.read)))
      (if (in broken data)
          (try
            (do
              (with [f (open filename "w")]
                (f.write (.replace data broken fixed)))
              ;; TODO: stop execution and require the user to re-start
              (fatal (.join "\n"
                            ["Fixing a problem with the 'easywebdav' module succeeded."
                             "Please re-run your command!"]))
              )
            (except [e OSError]
              (do
                (log.error "The 'easywebdav2' module is broken, and trying to fix the problem failed,")
                (log.error "so I will not be able to create directories on the remote server.")
                (log.error "As a workaround, please manually create any required directory on the remote server.")
                (log.error "For more information see https://github.com/zabuldon/easywebdav/pull/1")))
            )))
    (except [e Exception] (log.debug (% "Unable to patch 'easywebdav2'\n%s" e)))))


;; read in the config file if present
(defn read-config [configstring &optional [config-file (SafeConfigParser)]]
  "reads the configuration into a dictionary"
  (try (config-file.read_file (StringIO configstring))
       (except [e AttributeError] (config-file.readfp (StringIO configstring))))
  (dict (config-file.items "default")))

(setv config (read-config (+ "[default]\n" (try (.read (open config-file-path "r"))(except [e Exception] "")))))
;; try to obtain a value from environment, then config file, then prompt user

(defn get-config-value [name &rest default]
  "tries to get a value first from the envvars, then from the config-file and finally falls back to a default"
  (first (filter (fn [x] (not (is x None)))
                 [
                  ;; try to get the value from an environment variable
                  (os.environ.get (+ "DEKEN_" (name.upper)))
                  ;; try to get the value from the config file
                  (config.get name)
                  ;; finally, try the default
                  (first default)])))

;; prompt for a particular config value for externals host upload
(defn prompt-for-value [name &optional [forstring ""]]
  "prompt the user for a particular config value (with an explanatory text)"
  ((try raw_input (except [e NameError] input))
    (% (+
         "Environment variable DEKEN_%s is not set and the config file %s does not contain a '%s = ...' entry.\n"
         "To avoid this prompt in future please add a setting to the config or environment.\n"
         "Please enter %s %s:: ")
       (, (name.upper) config-file-path name name forstring))))

(defn askpass [&optional [prompt "Password: "]]
  """prompt the user for a password"""
  (import getpass)
  (getpass.getpass prompt))

(defn print-system-info [args]
  """print information about the environment we are running in"""
  (print "============= DEKEN =============")
  (print "Version     :" version)
  (print "Config      :" config-file-path)
  (print "Install-path:" default-installpath)
  (print "Platform    :" (.join "-" (native-arch)))
  (print)
  (print "============= SYSTEM ============")
  (print "Script      :" __file__)
  (print "Executable  :" sys.executable)
  (print "Hy          :" (do (import hy) hy.__version__))
  (print "Python      :" (.join "; " (.splitlines sys.version)))
  (print "PyPrefix    :" sys.prefix)
  (print "PyBasePrefix:" (try sys.base_prefix (except [e Exception] None)))
  (print "System      :" sys.platform)
  (try (print "Windows     :" (sys.getwindowsversion)) (except [e Exception]))
  (print "PATH        :" (.get os.environ "PATH"))
  )


(defn package-uri? [URI]
  "naive check whether the given URI seems to be a deken-package"
  (or
    (.endswith URI ".dek")
    (.endswith URI "-externals.zip")
    (.endswith URI "-externals.tgz")
    (.endswith URI "-externals.tar.gz")))


(defn --packages-from-args-- [packages requirement-files]
  """return a set of packages specified either directly (<packages>) or indirectly (<requirement-files>)"""
  (defn req2pkg [req]
    (try
      (with [f (open req "r")]
        (lfor line (.readlines f) (.strip line)))
      (except [e OSError] (fatal (% "Unable to open requirements-file '%s'" (, req))))))
  (defn reqs2pkgs [reqs]
    (chain.from-iterable (lfor f reqs (req2pkg f))))
  (.union (set packages) (reqs2pkgs requirement-files)))

(defn native-arch []
  "guesstimate on the native architecture"
  (defn amd64? [cpu] (if (= cpu "x86_64") "amd64" cpu))
  (import platform)
  (, (platform.system) (amd64? (platform.machine)) "32"))

(defn compatible-arch? [need-arch have-archs]
  "check whether <have-archs> contains an architecture that is compatible with <need-arch>"
  (defn simple-compat [need have]
    (or
      (= need have)
      (= need "*")))
  (defn cpu-compat [need have]
    ;; is <a> a subset of <b>?
    (or
      (simple-compat need have)
      (in have (or (try-get architecture-substitutes need) []))))
  (defn compat? [need-arch have-arch]
    (try
      (or
        (= have-arch need-arch)
        (and
          ;; OS = OS
          (simple-compat (get need-arch 0) (get have-arch 0))
          ;; CPU = CPU
          (cpu-compat (get need-arch 1) (get have-arch 1))
          ;; floatsize = floatsize
          (simple-compat (get need-arch 2) (get have-arch 2))))
      (except [e Exception] (log.error (% "%s != %s" (, need-arch have-arch))))))
  (defn compat-generator [need-arch have-archs]
    (setv na (stringify-tuple need-arch))
    (for [ha have-archs] (yield (compat? na (stringify-tuple ha)))))
  (cond
    [(not have-archs) True] ; archs is 'all' which matches any architecture
    [(= need-arch "*") True] ; we don't care
    [True (any (compat-generator need-arch have-archs))]))

(defn compatible-archs? [need-archs have-archs]
  "checks whether <have-archs> contains *any* of the architectures listed in <need-archs>"
  (defn compat-generator [need-archs have-archs]
    (for [na need-archs] (yield (compatible-arch? na have-archs))))
  (any (compat-generator need-archs have-archs)))

(defn sort-archs [archs]
  "alphabetically sort list of archs with 'Sources' always at the end"
  (+
    (sorted (.difference (set archs) (set ["Sources"])))
    (if (in "Sources" archs)
        ["Sources"]
        [])))

(defn split-archstring [archstring &optional [fixdek0 False]]
  "splits an archstring like '(Linux-amd64-32)(Windows-i686-32)' into a list of arch-tuples"
                                ; if fixdek0 is True, this forces the floatsize to "32"
  (defn split-arch [arch fixdek0]
    (setv t (.split arch "-"))
    (if (and fixdek0 (> (len t) 2))
        (assoc t 2 "32"))
    (tuple t))
  (if archstring
      (lfor x (re.findall r"\(([^()]*)\)" archstring) (split-arch x fixdek0))
      []))
(defn arch-to-string [arch]
  "convert an architecture-tuple into a string"
  (.join "-" (stringify-tuple arch)))

(defn --archs-default-floatsize-- [&optional [filename None]]
  (defn doit [floatsize filename]
    (log.warning
      (if filename
          (% "'%s' has no relevant symbols!...assuming floatsize=%s"
             (, filename floatsize))
          (% "No relevant symbols found!...assuming floatsize=%s"
             (, filename))))
    floatsize)
  (if default-floatsize
      (doit default-floatsize filename)
      None))

;; takes the externals architectures and turns them into a string)
(defn get-architecture-string [folder &optional [recurse-subdirs False] [extra-files []]]
  "get architecture-string for all Pd-binaries in the folder"
  (defn _get_archs [archs]
    (if archs
        (+
          "("
          (.join ")(" (list (sort-archs archs)))
          ")")
        ""))
  (_get_archs (lfor arch (get-externals-architectures
                           folder
                           :extra-files extra-files
                           :recurse-subdirs recurse-subdirs)
                    (.join "-" (lfor parts arch (str parts))))))

;; check if a particular file has an extension in a set
(defn test-extensions [filename extensions]
  "check if filename has one of the extensions in the set"
  (any (lfor e extensions :if (.endswith (.lower filename) e) e)))

;; check for a particular file in a directory, recursively
(defn test-filename-under-dir [pred dir]
  (any (map (fn [w] (any (map pred (get w 2))))
            (os.walk dir))))

;; check if a particular file has an extension in a directory, recursively
(defn test-extensions-under-dir [dir extensions]
  (test-filename-under-dir
    (fn [filename] (test-extensions filename extensions)) dir))

;; examine a folder for externals and return the architectures of those found
(defn get-externals-architectures [folder
                                   &optional
                                   [extra-files []]
                                   [recurse-subdirs False]]
  "examine a folder for external binaries (and sources) and return the architectures of those found"
  (defn listdir [folder &optional [recurse-subdirs True]]
    (if recurse-subdirs
        (lfor (, dirname subdirs filenames) (os.walk folder) f filenames (os.path.join dirname f))
        (lfor f (os.listdir folder) (os.path.join folder f))))
  (sum (+
         (if (test-extensions-under-dir folder [".c" ".cpp" ".cxx" ".cc"])
             [[["Sources"]]] [])
         (lfor
           f (+ (listdir folder recurse-subdirs) extra-files)
           :if (os.path.exists f)
           (cond
             [(re.search "\.(pd_linux|so|l_[^.]*)$" f) (get-elf-archs f "Linux")]
             [(re.search "\.(pd_freebsd|b_[^.]*)$" f) (get-elf-archs f "FreeBSD")]
             [(re.search "\.(pd_darwin|d_[^.]*)$" f) (get-mach-archs f)]
             [(re.search "\.(dll|m_[^.]*)$" f) (get-windows-archs f)]
             [True []])))
       []))

;; class_new -> t_float=float; class_new64 -> t_float=double
(defn --classnew-to-floatsize-- [function-names]
  "detect Pd-floatsize based on the list of <function-names> used in the binary"
  (cond
    [(in function-names ["_class_new" "class_new"]) 32]
    [(in function-names ["_class_new64" "class_new64"]) 64]
    [True None]))


;; Linux ELF file
(defn get-elf-archs [filename &optional [oshint "Linux"]]
  "guess OS/CPU/floatsize for ELF binaries"
  (setv elf-osabi {
                   "ELFOSABI_SYSV" None
                   "ELFOSABI_HPUX" "HPUX"
                   "ELFOSABI_NETBSD" "NetBSD"
                   "ELFOSABI_LINUX" "Linux"
                   "ELFOSABI_HURD" "Hurd"
                   "ELFOSABI_SOLARIS" "Solaris"
                   "ELFOSABI_AIX" "AIX"
                   "ELFOSABI_IRIX" "Irix"
                   "ELFOSABI_FREEBSD" "FreeBSD"
                   "ELFOSABI_TRU64" "Tru64"
                   "ELFOSABI_MODESTO" None
                   "ELFOSABI_OPENBSD" "OpenBSD"
                   "ELFOSABI_OPENVMS" "OpenVMS"
                   "ELFOSABI_NSK" None
                   "ELFOSABI_AROS" None
                   "ELFOSABI_ARM_AEABI" None
                   "ELFOSABI_ARM" None
                   "ELFOSABI_STANDALONE" None})
  (setv elf-cpu {
                 ;; format: (, CPU elfsize littlendian) "id"
                 (, "EM_386" 32 True) "i386"
                 (, "EM_X86_64" 64 True) "amd64"
                 (, "EM_X86_64" 32 True) "x32"
                 (, "EM_ARM" 32 True) "arm" ;; needs more
                 (, "EM_AARCH64" 64 True) "arm64"
                 ;; more or less exotic archs
                 (, "EM_IA_64" 64 False) "ia64"
                 (, "EM_IA_64" 64 True) "ia64el"
                 (, "EM_68K" 32 False) "m68k"
                 (, "EM_PARISC" 32 False) "hppa"
                 (, "EM_PPC" 32 False) "ppc"
                 (, "EM_PPC64" 64 False) "ppc64"
                 (, "EM_PPC64" 64 True) "ppc64el"
                 (, "EM_S390" 32 False) "s390" ;; 31bit!?
                 (, "EM_S390" 64 False) "s390x"
                 (, "EM_SH" 32 True) "sh4"
                 (, "EM_SPARC" 32 False) "sparc"
                 (, "EM_SPARCV9" 64 False) "sparc64"
                 (, "EM_ALPHA" 64 True) "alpha" ;; can also be big-endian
                 (, 36902 64 True) "alpha"
                 (, "EM_MIPS" 32 False) "mips"
                 (, "EM_MIPS" 32 True) "mipsel"
                 (, "EM_MIPS" 64 False) "mips64"
                 (, "EM_MIPS" 64 True) "mips64el"
                 ;; microcontrollers
                 (, "EM_BLAFKIN" 32 True) "blackfin" ;; "Analog Devices Blackfin"
                 (, "EM_BLACKFIN" 32 True) "blackfin" ;; "Analog Devices Blackfin"
                 (, "EM_AVR" 32 True) "avr" ;; "Atmel AVR 8-bit microcontroller" e.g. arduino
                 ;; dead archs
                 ;;  (, "EM_88K" 32 None) "m88k" ;; predecessor of PowerPC
                 ;;  (, "EM_M32" ) "WE32100" ;; Belmac32 the world's first 32bit processor!
                 ;;  (, "EM_S370" ) "s370" ;; terminated 1990
                 ;;  (, "EM_MIPS_RS4_BE" ) "r4000" ;; "MIPS 4000 big-endian" ;; direct concurrent to the i486
                 ;;  (, "EM_860" ) "i860" ;; terminated mid-90s
                 ;;  (, "EM_NONE", None, None) None
                 ;;  (, "RESERVED", None, None) "RESERVED"
                 })
  ;; values updated via https://sourceware.org/git/gitweb.cgi?p=binutils-gdb.git;a=blob;f=include/elf/arm.h;hb=HEAD#l93
  (setv elf-armcpu [
                    "armPre4"
                    "armv4"
                    "armv4T"
                    "armv5T"
                    "armv5TE"
                    "armv5TEJ"
                    "armv6"
                    "armv6KZ"
                    "armv6T2"
                    "armv6K"
                    "armv7"
                    "armv6_M"
                    "armv6S_M"
                    "armv7E_M"
                    "armv8"
                    "armv8R"
                    "armv8M_BASE"
                    "armv8M_MAIN"
                    ])
  (defn do-get-elf-archs [elffile oshint]
                                ; get the size of t_float in the elffile
    (defn get-elf-floatsizes [elffile]
      (lfor _ (.iter_symbols (elffile.get_section_by_name ".dynsym"))
            :if (in "class_new" _.name)
            (--classnew-to-floatsize-- _.name)))
    (defn get-elf-armcpu [cpu]
      (defn armcpu-from-aeabi [arm aeabi]
        (defn armcpu-from-aeabi-helper [data]
          (if data
              (get elf-armcpu (byte-to-int (get (get (.split
                                                       (cut data 7)
                                                       (str-to-bytes "\x00") 1) 1) 1)))))
        (armcpu-from-aeabi-helper (and (arm.startswith (str-to-bytes "A")) (arm.index aeabi) (.pop (arm.split aeabi)))))
      (or
        (if (= cpu "arm") (armcpu-from-aeabi
                            (.data (elffile.get_section_by_name ".ARM.attributes"))
                            (str-to-bytes "aeabi")))
        cpu))
    (lfor floatsize (or (get-elf-floatsizes elffile) [(--archs-default-floatsize-- filename)])
          :if floatsize
          (,
           (or (elf-osabi.get elffile.header.e_ident.EI_OSABI) oshint "Linux")
             (get-elf-armcpu (elf-cpu.get (, elffile.header.e_machine elffile.elfclass elffile.little_endian)))
             floatsize)))
  (try (do
         (import [elftools.elf.elffile [ELFFile]])
         (do-get-elf-archs (ELFFile (open filename :mode "rb")) oshint))
       (except [e Exception] (or (log.debug e) (list)))))


;; macOS MachO file
(defn get-mach-archs [filename]
  "guess OS/CPU/floatsize for MachO binaries"
  (setv macho-cpu {
                   1 "vac"
                   6 "m68k"
                   7 "i386"
                   16777223 "amd64"
                   8 "mips"
                   10 "m98k"
                   11 "hppa"
                   12 "arm"
                   16777228 "arm64"
                   13 "m88k"
                   14 "spark"
                   15 "i860"
                   16 "alpha"
                   18 "ppc"
                   16777234 "ppc64"
                   })
  (defn get-macho-arch [macho]
    (defn get-macho-floatsizes [header]
      (import [macholib.SymbolTable [SymbolTable]])
      (lfor (, _ name) (getattr (SymbolTable macho header) "undefsyms")
            :if (in (str-to-bytes "class_new") name)
            (--classnew-to-floatsize-- (.decode name))))
    (defn get-macho-headerarchs [header]
      (lfor
        floatsize (or (get-macho-floatsizes header)  [(--archs-default-floatsize-- filename)])
        (, "Darwin" (macho-cpu.get header.header.cputype) floatsize)))
    (list (chain.from_iterable (lfor hdr macho.headers (get-macho-headerarchs hdr)))))
  (try (do
         (import [macholib.MachO [MachO]])
         (get-macho-arch (MachO filename)))
       (except [e Exception] (or (log.debug e) (list)))))

;; Windows PE file
(defn get-windows-archs [filename]
  "guess OS/CPU/floatsize for PE (Windows) binaries"
  (defn get-pe-sectionarchs [cpu symbols]
    (if symbols
        (lfor fun symbols (, "Windows" cpu (--classnew-to-floatsize-- fun)))
        [(, "Windows" cpu (or (--archs-default-floatsize-- filename) (raise (Exception))))]))
  (defn get-pe-archs [pef cpudict]
    (pef.parse_data_directories)
    (get-pe-sectionarchs
      (.lower (.pop (.split (cpudict.get pef.FILE_HEADER.Machine "") "_")))
      (flatten
        (lfor entry pef.DIRECTORY_ENTRY_IMPORT
              (lfor imp entry.imports
                    :if (in (str-to-bytes "class_new") imp.name)
                    (.decode imp.name))))))
  (try (do
         (import pefile)
         (get-pe-archs (pefile.PE filename :fast_load True) pefile.MACHINE_TYPE))
       (except [e Exception] (list))))


(defn make-objects-file [dekfilename objfile &optional [warn-exists True]]
  "generate object-list for <filename> from <objfile>"
  ;; dekfilename exists: issue a warning, and don't overwrite it
  ;; objfile=='' don't create an objects-file
  ;; objfile==None generate from <objfile2>
  ;; objfile==zip-file extract from zip-file
  ;; objfile==TSV-file use directly (actually, we only check whether the file seems to not be binary)
  (defn get-files-from-zip [archive]
    (import zipfile)
    (try (.namelist (zipfile.ZipFile archive "r"))
         (except [e Exception] (log.debug e))))
  (defn get-files-from-dir [directory &optional [recursive False]]
    (if recursive
        (list (chain.from_iterable (lfor (, root dirs files) (os.walk directory) files)))
        (try
          (lfor x (os.listdir directory)
                :if (os.path.isfile (os.path.join directory x))
                x)
          (except [e OSError] []))))
  (defn genobjs [input]
    (lfor f input
          :if (f.endswith "-help.pd")
          (% "%s\tDEKEN GENERATED\n" (cut (os.path.basename f) 0 -8))))
  (defn readobjs [input]
    (try
      (with [f (open input)] (.readlines f))
      (except [e Exception] (log.debug e))))
  (defn writeobjs [output data]
    (if data
        (try (do
               (with [f (open output :mode "w")] (.write f (.join "" data)))
               output)
             (except [e Exception] (log.debug e)))))
  (defn  do-make-objects-file [dekfilename objfilename]
    (cond
      [(not dekfilename) None]
      [(not objfilename) None]
      [(= dekfilename objfilename) dekfilename]
      [True
       (writeobjs
         dekfilename
         (or
           (genobjs (or
                      (get-files-from-zip objfilename)
                      (get-files-from-dir objfilename)))
           (if (binary-file? objfilename)
               []
               (readobjs objfilename))))]))
  (setv dekfilename (% "%s.txt" dekfilename))
  (if (os.path.exists dekfilename)
      (do ;; already exists
        (log.info (% "objects file '%s' already exists" dekfilename))
        (if warn-exists
            (log.warning (% "WARNING: delete '%s' to re-generate objects file" dekfilename)))
        dekfilename)
      (do-make-objects-file dekfilename objfile)))

;; calculate the sha256 hash of a file
(defn hash-file [file hashfn &optional [blocksize 65535]]
  "calculate the hash of a file"
  (setv read-chunk (fn [] (.read file blocksize)))
  (while True
    (setv buf (read-chunk))
    (if-not buf (break))
    (hashfn.update buf))
  (hashfn.hexdigest))

(defn hash-sum-file [filename &optional [algorithm "sha256"] [blocksize 65535]]
  "calculates the (sha256) hash of a file and stores it into a separate file"
  (import hashlib)
  (defn do-hash-file [filename hashfilename hasher blocksize]
    (.write (open hashfilename :mode "w")
            (hash-file (open filename :mode "rb")
                       (hasher)
                       blocksize))
    hashfilename)
  (do-hash-file filename
                (% "%s.%s" (, filename algorithm))
                (.get hashlib.__dict__ algorithm)
                blocksize))

(defn hash-verify-file [filename &optional hashfilename [blocksize 65535]]
  "verify that the hash if the <filename> file is the same as stored in the <hashfilename>"
  (import hashlib)
  (defn filename2algo [filename]
    (cut (get (os.path.splitext filename) 1) 1))
  (setv hashfilename (or hashfilename (+ filename ".sha256")))
  (try
    (= (hash-file (open filename :mode "rb")
                  ((.get hashlib.__dict__ (filename2algo hashfilename)))
                  blocksize)
       (.strip (get (.split (.read (open hashfilename "r"))) 0)))
    (except [e OSError] None)
    (except [e TypeError] None)))

;; handling GPG signatures
(try (import gnupg)
     ;; read a value from the gpg config
     (except [e ImportError]
       (do
         (defn gpg-sign-file [filename]
           "sign a file with GPG (if the gnupg module is installed)"
           (log.warning (+
                          (% "Unable to GPG sign '%s'\n" filename)
                          "'gnupg' module not loaded")))
         (defn gpg-verify-file [signedfile signaturefile]
           "verify a file with a detached GPG signature"
           (log.warning (.join "\n" (list
                                      (% "Unable to GPG verify '%s'" (, signedfile))
                                      "'gnupg' module not loaded")))
           )))
     (else
       (do
         (defn --gpg-unavail-error-- [state &optional ex]
           (log.warning (% "GPG %s failed:" state))
           (if ex (log.warning ex))
           (log.warning "Do you have 'gpg' installed?")
           (log.warning "- If you've received numerous errors during the initial installation,")
           (log.warning "  you probably should install 'python-dev', 'libffi-dev' and 'libssl-dev'")
           (log.warning "  and re-run `deken install`")
           (log.warning "- On OSX you might want to install the 'GPG Suite'")
           (log.warning "Signing your package with GPG is optional.")
           (log.warning " You can safely ignore this warning if you don't want to sign your package"))

         ;; generate a GPG signature for a particular file
         (defn gpg-verify-file [signedfile signaturefile]
           "verify a file with a detached GPG signature"
           (defn get-gpg []
             (setv gnupghome (get-config-value "gpg_home"))
             (setv gpg
                   (try
                     (set-attr
                       (gnupg.GPG #** (if gnupghome {"gnupghome" gnupghome} {}))
                       "decode_errors" "replace")
                     (except [e OSError] (--gpg-unavail-error-- "init" e))))
             (if gpg (setv gpg.encoding "utf-8"))
             gpg)
           (defn do-verify [data sigfile]
             (setv result (gpg.verify_data signaturefile data))
             (if (not result) (log.debug result.stderr))
             (bool result))
           (setv gpg (get-gpg))
           (if gpg (do
                     (setv data (try (with [f (open signedfile "rb")] (f.read)) (except [e OSError] None)))
                     (if (and
                           data
                           (os.path.exists signaturefile))
                         (do-verify data signaturefile)))))
         (defn gpg-sign-file [filename]
           "sign a file with GPG (if the gnupg module is installed)"
           (defn gpg-get-config [gpg id]
             (try
               (get
                 (lfor x (.readlines
                           (open
                             (os.path.expanduser
                               (os.path.join
                                 (or gpg.gnupghome (os.path.join "~" ".gnupg"))
                                 "gpg.conf"))))
                       :if (.startswith (.lstrip x) (.strip id) )
                       (get (.split (.strip x)) 1)) -1)
               (except [e [IOError IndexError]] None)))
           ;; get the GPG key for signing
           (defn gpg-get-key [gpg]
             (setv keyid (get-config-value "key_id" (gpg-get-config gpg "default-key")))
             (try
               (first (lfor k (gpg.list_keys True)
                            :if (cond [keyid (.endswith (.upper (get k "keyid" )) (.upper keyid) )] [True True])
                            k))
               (except [e IndexError] None)))

           (defn do-gpg-sign-file [filename signfile gnupghome use-agent]
             (log.info (% "Attempting to GPG sign '%s'" filename))
             (setv gpg
                   (try
                     (set-attr
                       (gnupg.GPG #** (dict-merge
                                        (if gnupghome {"gnupghome" gnupghome} {})
                                        (if use-agent {"use_agent" True} {})))
                       "decode_errors" "replace")
                     (except [e OSError] (--gpg-unavail-error-- "init" e))))
             (if gpg (do
                       (setv gpg.encoding "utf-8")
                       (setv [keyid uid] (lfor _ ["keyid" "uids"] (try-get (gpg-get-key gpg) _ None)))
                       (setv uid (try-get uid 0 None))
                       (setv passphrase
                             (if (and (not use-agent) keyid)
                                 (do
                                   (print (% "You need a passphrase to unlock the secret key for\nuser: %s ID: %s\nin order to sign %s"
                                             (, uid keyid filename)))
                                   (askpass "Enter GPG passphrase: " ))))
                       (setv signconfig (dict-merge
                                          {"detach" True}
                                          (if keyid {"keyid" keyid} {})
                                          (if passphrase {"passphrase" passphrase} {})))
                       (if (and (not use-agent) (not passphrase))
                           (log.info "No passphrase and not using gpg-agent...trying to sign anyhow"))
                       (try
                         (do
                           (setv sig (if gpg (gpg.sign_file (open filename "rb") #** signconfig)))
                           (if (hasattr sig "stderr")
                               (log.debug (try (str sig.stderr) (except [e UnicodeEncodeError] (.encode sig.stderr "utf-8")))))
                           (if (not sig)
                               (log.warning "Could not GPG sign the package.")
                               (do
                                 (with [f (open signfile "w")] (f.write (str sig)))
                                 signfile)))
                         (except [e OSError] (--gpg-unavail-error-- "signing" e))))))

           ;; sign a file if it is not already signed
           (setv signfile (+ filename ".asc"))
           (setv gpghome (get-config-value "gpg_home"))
           (setv gpgagent (str-to-bool (get-config-value "gpg_agent")))
           (if (os.path.exists signfile)
               (do
                 (log.info (% "not GPG-signing already signed file '%s'" filename))
                 (log.info (% "delete '%s' to re-sign" signfile))
                 signfile)
               (do-gpg-sign-file filename signfile gpghome gpgagent))))))


(defn parse-requirement [spec]
  "parse a requirement-string "
  ;; spec can be a library, or a library with version, e.g. "library==0.2.1" or "library>=1.2.3"
  ;; currently the only valid compatrators are ">=" and "=="
  ;; returns a tuple (library, version, comparator)
  (setv result (try (get-values (re.split "(.+)([>=]=)(.+)" spec) [1 3 2])
                    (except [e IndexError] [spec None None])))
  (assoc result 2 (try-get {"==" str.startswith ">=" >=} (get result 2) (fn [a b] True)))
  (tuple result))

(defn make-requirement-matcher [parsedspec]
  "create a boolean function to check whether a given package-dict matches a requirement"
  ;; <parsedspec> is the output of (parse-requirement): a (library, version, comparator) tuple
  ;; currently the only valid compatrators are ">=" and "=="
  ;; returns a tuple (library, version, comparator)
                                ;(setv parsedspec (parse-requirement spec))
  (setv package (get parsedspec 0))
  (setv version (get parsedspec 1))
  (setv compare (get parsedspec 2))
  (fn [libdict]
    (try
      (and
        (= (get libdict "package") package)
        (compare (get libdict "version") version))
      (except [e TypeError] None)
      (except [e KeyError] None))))

(defn make-requirements-matcher [specs]
  "creates a boolean function to check whether a given package-dict matches any of the given requirements"
  (if specs
      (fn [libdict] (any
                      (lfor match (lfor spec specs
                                        :if spec
                                        (make-requirement-matcher spec))
                            (match libdict))))
      (fn [libdict] True)))


(defn sort-searchresults [libdicts &optional [reverse False]]
  "sort <libdicts> (list of dictionaries)"
  (sorted libdicts
          :reverse reverse
          :key (fn [d] (,
                        (.lower (or (get d "package") ""))
                          (.lower (or (get d "version") ""))
                          (.lower (or (get d "timestamp") ""))))))

(defn filter-older-versions [libdicts &optional [depth 1]]
  "for each library (with a unique 'package' key) in <libdicts> leave only the latest <depth> versions"
  (defn doit [libdicts depth]
    ;; create a dict with <package> keys, and the values being <libdict> lists
    (setv pkgdict {})
    (for [lib libdicts]
      (do
        (setv pkgname (get lib "package"))
        (if (not (in pkgname pkgdict))
            (assoc pkgdict pkgname []))
        (setv l (get pkgdict pkgname))
        (l.append lib)))
    ;; sort and truncate each dictvalue
    (setv result [])
    (for [key pkgdict]
      (setv result
            (+ result (cut (sorted (get pkgdict key)
                                   :reverse True
                                   :key (fn [d] (, (or (get d "version")) (or (get d "timestamp")))))
                           0 depth))))
    result)
  (if depth
      (doit libdicts depth)
      libdicts))

;; zip up a single directory
;; http://stackoverflow.com/questions/1855095/how-to-create-a-zip-archive-of-a-directory
(defn zip-file [filename]
  "create a ZIP-file with a default compression"
  (import zipfile)
  (try (zipfile.ZipFile filename "w" :compression zipfile.ZIP_DEFLATED)
       (except [e RuntimeError] (zipfile.ZipFile filename "w"))))
(defn zip-dir [directory-to-zip archive-file &optional [extension ".zip"]]
  "create a ZIP-archive of a directory"
  (setv zip-filename (+ archive-file extension))
  (with [f (zip-file zip-filename)]
    (for [[root dirs files] (os.walk directory-to-zip)]
      (for [file-path (lfor file files (os.path.join root file))]
        (if (os.path.exists file-path)
            (f.write file-path (os.path.relpath file-path (os.path.join directory-to-zip "..")))))))
  zip-filename)
(defn unzip-file [archive-file &optional [targetdir "."]]
  "extract all members of the zip archive into targetdir"
  (print archive-file)
  (try (do
         (import zipfile)
         (with [f (zipfile.ZipFile archive-file)]
           (f.extractall :path targetdir))
         True)
       (except [e Exception] (or (log.debug (% "unzipping '%s' failed" (, archive-file))) False))))

;; tar up the directory
(defn tar-dir [directory-to-tar archive-file &optional [extension ".tar.gz"]]
  "create a (gzipped) TAR archive of a directory"
  (import tarfile)
  (setv tar-file (+ archive-file extension))
  (defn tarfilter [tarinfo]
    (setv tarinfo.name (os.path.relpath tarinfo.name (os.path.join directory-to-tar "..")))
    tarinfo)
  (with [f (tarfile.open tar-file "w:gz")]
    (f.add directory-to-tar :filter tarfilter))
  tar-file)

(defn untar-file [archive-file &optional [targetdir "."]]
  "extract all members of the tar archive into targetdir"
  (try (do
         (import tarfile)
         (with [f (tarfile.open archive-file "r")]
           (f.extractall :path targetdir))
         True)
       (except [e Exception] (or (log.debug (% "untaring '%s' failed" (, archive-file))) False))))

;; do we use zip or tar on this archive?
(defn archive-extension [rootname]
  "default extension for dekformat.v0: if the architecture is Windows are any, w euse 'zip', else 'tar.gz'"
  (if (or (in "(Windows" rootname) (not (in "(" rootname))) ".zip" ".tar.gz"))

;; v1: all archives are ZIP-files with .dek extension
;; v0: automatically pick the correct archiver - windows or "no arch" = zip
(defn archive-dir [directory-to-archive rootname]
  "create an archive of a directory,using a method based on the extension"
  ((cond
     [(.endswith rootname ".dek") zip-dir]
     [(.endswith rootname ".zip") zip-dir]
     [True tar-dir])
    directory-to-archive rootname ""))

;; naive check, whether we have an archive: compare against known suffixes
(defn archive? [filename]
  "(naive) check if the given filename is a (known) archive: just check the file extension"
  (test-extensions filename [".dek" ".zip" ".tar.gz" ".tgz"]))

;; download a file
(defn download-file [url &optional filename]
  "downloads a file from <url>, saves it as <filename> (or a sane default); returns the filename or None; makes sure that no file gets overwritten"
  (defn unique-filename [filename]
    (defn unique-filename-number [filename number]
      (setv filename0 (% "%s.%s" (, filename number)))
      (if (not (os.path.exists filename0))
          filename0
          (unique-filename-number filename (+ number 1))))
    (if (os.path.exists filename)
        (unique-filename-number filename 1)
        filename))
  (defn save-data [outfile content]
    (try
      (do
        (with [f (open outfile "wb")] (.write f content))
        outfile)
      (except [e OSError] (log.warning (% "Unable to download file: %s" (, e))))))
  (import requests)
  (setv r (requests.get url))
  (if (= 200 r.status_code)
      (save-data
        (unique-filename
          (or
            filename
            (try
              (.strip (first (re.findall "filename=(.+)" (try-get r.headers "content-disposition" ""))) "\"")
              (except [e AttributeError] None))
            (os.path.basename url)
            "downloaded_file"))
        r.content)
      (log.warning (% "Downloading '%s' failed with '%s'" (, url r.status_code)))))

;; upload a zipped up package to puredata.info
(defn upload-file [filepath destination username password]
  "upload a file to a destination via webdav, using username/password"
  ;; get username and password from the environment, config, or user input
  (try (do
         (import easywebdav2)
         (fix-easywebdav2 easywebdav2)
         (setv easywebdav easywebdav2))
       (except [e ImportError] (import easywebdav)))
  (defn do-upload-file [dav path filename url host]
    (log.info (% "Uploading '%s' to %s" (, filename url)))
    (try
      (do
        ;; make sure all directories exist
        (dav.mkdirs path)
        ;; upload the package file
        (dav.upload filepath (+ path "/" filename)))
      (except [e easywebdav.client.OperationFailed]
        (fatal (+
                 (str e)
                 "\n"
                 (% "Couldn't upload to %s!\n" url)
                 (% "Are you sure you have the correct username and password set for '%s'?\n" host)
                 (% "Please ensure the folder '%s' exists on the server and is writable." path))))))
  (if filepath
      (do
        (setv filename (os.path.basename filepath))
        (setv [pkg ver _ _] (parse-filename filename))
        (setv pkg (or pkg (fatal (% "'%s' is not a valid deken file(name)" filename))))
        (setv ver (.strip (or ver "") "[]"))
        (setv proto (or destination.scheme default-destination.scheme))
        (setv host (or destination.hostname default-destination.hostname))
        (setv path
              (str
                (replace-words
                  (or (.rstrip destination.path "/") default-destination.path)
                  (, (, "%u" username) (, "%p" pkg) (, "%v" (or ver ""))))))
        (do-upload-file
          (easywebdav.connect host #** {"username" username
                                        "password" password
                                        "protocol" proto})
          path
          filename
          (+ proto "://" host path)
          (+ proto "://" host)))))

;; upload an archive (given the archive-filename it will also upload some extra-files (sha256, gpg,...))
;; returns a (username, password) tuple in case of success
;; in case of failure, this exits
(defn upload-package [pkg destination username password]
  "upload a package (with sha256-file and gpg-signature if possible)"
  (log.info (% "Uploading package '%s'" pkg))
  (upload-file (hash-sum-file pkg) destination username password)
  (upload-file pkg destination username password)
  (upload-file (make-objects-file pkg None False) destination username password)
  (upload-file (gpg-sign-file pkg) destination username password)
  (, username password))
;; upload a list of archives (with aux files)
;; returns a (username, password) tuple in case of success
;; in case of failure, this exits
(defn upload-packages [pkgs destination username password skip-source]
  "upload multiple packages at once"
  (if (not skip-source) (check-sources (sfor pkg pkgs (filename-to-namever pkg))
                                       (sfor pkg pkgs (has-sources? pkg))
                                       (if (= "puredata.info"
                                              (.lower (or destination.hostname default-destination.hostname)))
                                           username)))
  (for [pkg pkgs]
    (if (get (parse-filename pkg) 0)
        (upload-package pkg destination username password)
        (log.warning (% "Skipping '%s', it is not a valid deken package" pkg))))
  (log.warning "Your upload was successful.")
  (log.warning "Please note that it can take up to 24 hours before the package will appear")
  (log.warning "in deken-searches that allow others to download your package from the")
  (log.warning "Pd package repository.")
  (, username password))

;; compute the archive filename for a particular external on this platform
;; v1: "<pkgname>[v<version>](<arch1>)(<arch2>).dek"
;; v0: "<pkgname>-v<version>-(<arch1>)(<arch2>)-externals.tar.gz" (resp. ".zip")
(defn make-archive-name [folder version
                         &optional
                         [filenameversion 1]
                         [recurse-subdirs False]
                         [extra-arch-files []]]
  "calculates the dekenfilename for a given folder (embedding version and architectures in the filename)"
  (defn do-make-name [pkgname version archs filenameversion]
    (cond
      [(= filenameversion 1) (+ pkgname
                                (if version (% "[v%s]" version) "")
                                archs
                                ".dek")]
      [(= filenameversion 0) (+ pkgname
                                (if version (% "-v%s-" version) "")
                                archs
                                "-externals"
                                (archive-extension archs))]
      [True (fatal (% "Unknown dekformat '%s'" filenameversion))]))
  (do-make-name
    (os.path.basename folder)
    (cond [(is version None)
           (fatal
             (+ (% "No version for '%s'!\n" folder)
                " Please provide the version-number via the '--version' flag.\n"
                (% " If '%s' doesn't have a proper version number,\n" folder)
                (% " consider using a date-based fake version (like '0~%s')\n or an empty version ('')."
                   (.strftime (datetime.date.today) "%Y%m%d"))))]
          [version version])
    (get-architecture-string folder :recurse-subdirs recurse-subdirs :extra-files extra-arch-files)
    filenameversion))


;; create additional files besides archive: hash-file and gpg-signature
(defn archive-extra [dekfile &optional [objects None]]
  "create additional files besides archive: hash-file and GPG-signature"
  (log.info (% "Packaging %s" dekfile))
  (hash-sum-file dekfile)
  (if objects
      (if (dekfile.endswith ".dek")
          (make-objects-file dekfile objects)
          (log.warning "object-file generation is only enabled for dekformat>=1...skipping!")))
  (gpg-sign-file dekfile)
  dekfile)

;; parses a filename into a (pkgname version archs extension) tuple
;; missing values are None
(defn parse-filename0 [filename]
  "parses a dekenformat.v0 filename into a (pkgname version archs extension) tuple"
  (try
    (get-values
      ;; parse filename with a regex
      (re.split r"(.*/)?(.+?)(-v(.+)-)?((\([^\)]+\))+|-)*-externals\.([a-z.]*)" filename)
      ;; extract only the fields of interested
      [2 4 5 7])
    (except [e IndexError] [])))
(defn parse-filename1 [filename]
  "parses a dekenformat.v1 filename into a (pkgname version archs extension) tuple"
  (try
    (get-values
      (re.split r"(.*/)?([^\[\]\(\)]+)(\[v([^\[\]\(\)]+)\])?((\([^\[\]\(\)]+\))*)\.(dek(\.[a-z0-9_.-]*)?)" filename)
      [2 4 5 7])
    (except [e IndexError] [])))
(defn parse-filename [filename]
  "parses a dekenformat filename (any version) into a (pkgname version archs extension) tuple"
  (lfor x (or
            (parse-filename1 filename)
            (parse-filename0 filename)
            [None None None None])
        (or x None)))
(defn filename-to-namever [filename]
  "extracts a <name>/<version> string from a filename"
  (join-nonempty "/" (get-values (parse-filename filename) [0 1])))

;; check if the list of archs contains sources (or is arch-independent)
(defn source-arch? [arch]
  "check if the arch string contains sources (or doesn't need them because its arch-independent)"
  (or (not arch) (in "(Sources)" arch)))
;; check if a package contains sources (and returns name-version to be used in a SET of packages with sources)
(defn has-sources? [filename]
  "returns name/version if the filename contains sources (so we check whether we still need to upload sources)"
  (if (source-arch? (try-get (parse-filename filename) 2)) (filename-to-namever filename)))

;; check if the given package has a sources-arch on puredata.info
(defn check-sources@puredata-info [pkg username]
  "check if there has been a sourceful upload for a given package"
  (import requests)
  (log.info (% "Checking puredata.info for Source package for '%s'" pkg))
  (in pkg
      ;; list of package/version matching 'pkg' that have 'Source' architecture
      (lfor p (lfor x (.splitlines (getattr (requests.get (% "http://deken.puredata.info/search?name=%s" (get (.split pkg "/") 0))) "text"))
                    :if (= username (try-get (.split x "\t") 2))
                    (try-get (.split (try-get (.split x "\t") 1) "/") -1))  ; filename part of the download URL
            (has-sources? p))))

;; check if sources archs are present by comparing a SET of packagaes and a SET of packages-with-sources
(defn check-sources [pkgs sources &optional puredata-info-user]
  "bail out if there are no sources on puredata.info yet and we don't currently upload sources"
  (for [pkg pkgs] (if (and
                        (not (in pkg sources))
                        (not (and puredata-info-user (check-sources@puredata-info pkg puredata-info-user))))
                      (fatal (+ (% "Missing sources for '%s'!\n" pkg)
                                "(You can override this error with the '--no-source-error' flag,\n"
                                " if you absolutely cannot provide the sources for this package)\n")))))

;; get the password, either from
;; - a password agent
;; - the config-file (no, not really?)
;; - user-input
;; if force-ask is set, skip the agent
;; store the password in the password agent (for later use)
(defn get-upload-password [username force-ask]
  "get password from keyring agent, config-file (ouch), or user-input"
  (or (if (not force-ask)
          (or (try (do
                     (import keyring)
                     (keyring.get_password "deken" username))
                   (except [e RuntimeError] (log.debug e))
                   (except [e Exception] (log.warning e)))
              (get-config-value "password")))
      (askpass (% "Please enter password for uploading as '%s': " username))))

(defn user-agent []
  "get the user-agent string of this application"
                                ; "Deken/${::deken::version} ([::deken::platform2string]) ${pdversion} Tcl/[info patchlevel]"
  (% "Deken/%s (%s) Python/%s"
     (, version
        "<unknown>"
        (get (.split sys.version) 0))))

(defn categorize-search-terms [terms &optional [libraries True] [objects True]]
  "splits the <terms> into objects, libraries and versioned-libraries; returns a dict"
  ;; versioned requirements (e.g. 'foo>=3.14') are always libraries, and go into 'libraries' (without the version) and 'versioned-libraries' (as tuples)
  ;; unversioned terms will show up in 'libraries' and/or 'objects', depending on which flag is True
  ;; a term that looks like an URL, will appear (only) in 'urls'
  (setv libs (set))
  (setv objs (set))
  (setv vlibs (set))
  (setv urls (set))
  (for [t terms]
    (do
      (setv vlib (parse-requirement t))
      (if (getattr (urlparse t) "scheme")
          (urls.add t)
          (do
            (if libraries
                (if (get vlib 1)
                    (do
                      (vlibs.add vlib)
                      (libs.add (get vlib 0)))
                    (libs.add t)))
            (if objects
                (if (get vlib 1)
                    None
                    (objs.add t)))))))
  {"libraries" (sorted libs)
   "objects" (sorted objs)
   "versioned-libraries" (sorted vlibs)
   "urls" (sorted urls)}
  )

(defn search [searchurl libraries objects]
  "searches needles in libraries (if True) and objects (if True)"
  (defn parse-tab-separated-values [data]
    (defn parse-tsv [description &optional
                     [URL None]
                     [uploader None]
                     [date None]
                     &rest args]
      (setv result
            (dict-merge
              {"description" description
               "URL" URL
               "uploader" uploader
               "timestamp" date}
              (dict (zip ["package" "version" "architectures" "extension"] (parse-filename (or URL ""))))))
      (assoc result
             "architectures"
             (split-archstring
               (get result "architectures")
               (not (.endswith URL ".dek"))))
      result)
    (lfor line (.splitlines (getattr r "text"))
          :if line
          (parse-tsv #* (.split line "\t"))))
  (defn parse-data [data content-type]
    (cond
      [(in "text/tab-separated-values" content-type) (parse-tab-separated-values data)]
      [True []]))
  (import requests)
  (setv r (requests.get searchurl
                        :headers {"user-agent" (user-agent)
                                  "accept" "tab-separated-values"}
                        :params {"libraries" libraries
                                 "objects" objects}))
  (if (= 200 r.status_code)
      (parse-data r.text (get r.headers "content-type"))))

(defn find-packages [searchterms ;; as returned by categorize-search-terms
                     &optional
                     [architectures []] ;; defaults to 'native'; use '*' for any architecture
                     [versioncount 0]   ;; how many versions of a given library should be returned
                     [searchurl default-searchurl] ;; where to search
                     ]
  "finds packages and filters them according to architecture, requirements and versioncount"
  (setv version-match? (make-requirements-matcher (try-get searchterms "versioned-libraries")))
  (filter-older-versions
    (lfor x (search (or searchurl default-searchurl)
                    (try-get searchterms "libraries" [])
                    (try-get searchterms "objects" []))
          :if (and
                (version-match? x)
                (compatible-archs? (or architectures [(native-arch)]) (get x "architectures")))
          x)
    versioncount))

(defn find [&optional args]
  "searches the server for deken-packages and prints the results"
  (defn print-result [result &optional index]
    (setv url (get result "URL"))
    (setv description (get result "description"))
    (print (% "%s/%s uploaded by %s on %s for %s"
              (,
               (get result "package")
                 (get result "version")
                 (get result "uploader")
                 (get result "timestamp")
                 (or
                   (.join "/" (lfor x (get result "architectures") (.join "-" x)))
                   "all architectures"))))
    (if (.endswith url description)
        None
        (print "\t" description))
    (print "\t URL:" url)
    (print "\t" (* "-" 65))
    (print ""))

  (setv both (= args.libraries args.objects))
  (setv searchterms (categorize-search-terms args.search (or both args.libraries) (or both args.objects)))
  (setv version-match? (make-requirements-matcher (try-get searchterms "versioned-libraries")))
  (for [result
        (sort-searchresults
          (find-packages searchterms
                         :architectures (if args.architecture
                                            (if (in "*" args.architecture)
                                                ["*"]
                                                (split-archstring (.join "" (lfor a args.architecture (% "(%s)" a)))))
                                            [(native-arch)])
                         :versioncount (if (is args.depth None) (if (in "*" args.architecture) 0 1) args.depth)
                         :searchurl (or args.search_url default-searchurl))
          args.reverse)]
    (print-result result)))

;; instruct the user how to manually upgrade 'deken'
(defn upgrade [&optional args]
  "print a big fat notice about manually upgrading via the webpage"
  (defn open-webpage [page]
    (log.warning
      (% "Please manually check for updates on: %s" page))
    (try (do
           (import webbrowser)
           (log.debug "Trying to open the page for you...")
           (webbrowser.open_new(page)))
         (except [e Exception])))
  (open-webpage "https://github.com/pure-data/deken/tree/master/developer")
  (sys.exit "'update' not implemented for this platform!"))

;; verifies a dekfile by checking it's GPG-signature (if possible) the SHA256
;; this require more thought: the verify function should never exit the program
;; (e.g. we want to remove downloaded files first)
;; return: True verification succeeded
;;         None verification failed non-fatally (e.g. GPG-signature missing)
;;         False verification failed (e.g. GPG-signature mismatch)
;; the 'gpg/hash' arg can modify the result: False: always return True
;;                                           None: return True if None
(defn verify [dekfile &optional gpgfile hashfile [gpg True] [hash True]]
  "verifies a dekfile by checking it's GPG-signature (if possible) the SHA256; if gpg/hash is False, verification failure is ignored, if its None the reference file is allowed to miss"
  (defn verify-result [result fail errstring missstring]
    ;; result==True: OK
    ;; result==False: KO
    ;; result==None: verification failed (no signature file,...)
    ;; fail==True: fail on any error
    ;; fail==False: never fail
    ;; fail==None: only fail on verification errors
    (cond
      [(is result None)(log.fatal missstring)]
      [(not result)(log.fatal errstring)])
    (cond
      [(= fail False) True]
      [(and (is fail None) (is result None)) True]
      [True result]))
  (defn do-verify [verifun
                   dekfile
                   reffile
                   extension
                   fail
                   &optional
                   [errstring "verification of '%s' failed"]
                   [missstring "verification file of '%s' missing"]]
    (verify-result (verifun dekfile
                            (or reffile (+ dekfile extension)))
                   fail
                   (% errstring (, dekfile))
                   (% missstring (, dekfile))))
  (setv vgpg  (do-verify gpg-verify-file  dekfile gpgfile
                         ".asc"    gpg
                         "GPG-verification failed for '%s'"
                         "GPG-signature missing for '%s'"))
  (setv vhash (do-verify hash-verify-file dekfile hashfile
                         ".sha256" hash
                         "hashsum mismatch for '%s'"
                         "hash file missing for '%s'"))
  (log.debug (% "GPG-verification : %s" (, vgpg)))
  (log.debug (% "hash-verification: %s" (, vhash)))
  (and vgpg vhash))

(defn download-verified [searchterms
                         &optional
                         [architecture None]
                         [verify-gpg True]
                         [verify-hash True]
                         [verify-none False]
                         [search-url None]]
  "search for files using the <searchterms>, download any results and verify them. returns a list of verified files; unverified files are removed (pendig the verify-... flags)"
  (defn try-remove [filename]
    (if filename
        (try
          (os.remove filename)
          (except [e Exception] (log.debug e))))
    None)
  (defn try-download [url]
    (setv pkg (download-file url))
    (setv gpg (download-file (+ url ".asc")))
    (setv hsh (download-file (+ url ".sha256")))
    (if (and
          (not (verify
                 pkg gpg hsh
                 :gpg verify-gpg
                 :hash verify-hash))
          (not verify-none))
        (do
          (try-remove pkg)
          (try-remove gpg)
          (try-remove hsh)
          None)
        (do
          (log.info (% "Downloaded: %s" (, pkg)))
          pkg)))
  (setv foundurls
        (lfor x (find-packages searchterms
                               :architectures architecture
                               :versioncount 1
                               :searchurl search-url)
              :if (package-uri? (try-get x "URL" ""))
              (get x "URL")))
  (setv urls
        (lfor x (+ foundurls (try-get searchterms "urls" []))
              :if (or
                    (package-uri? x)
                    (log.info (+ "Skipping non-package URL" x)))
              x))
  ;; return a list of successfully downloaded (and verified) files
  (lfor x (lfor url urls (try-download url))
        :if x
        x))

(defn install-package [pkgfile installdir]
  "unpack a <pkgfile> into <installdir>"
  (or
    (unzip-file pkgfile installdir)
    (untar-file pkgfile installdir)))


;; the executable portion of the different sub-commands that make up the deken tool
(setv commands
      {
       ;; zip up a set of built externals
       :package (fn [args]
                  ;; are they asking to package a directory?
                  (defn int-dekformat [value]
                    (try (int value)
                         (except [e ValueError]
                           (fatal (% "Illegal dekformat '%s'" value)))))
                  (defn set-default-floatsize [value &optional [valid [None 0 32 64]]]
                    (if (in value valid)
                        (do
                          (global default-floatsize)
                          (setv default-floatsize args.default-floatsize))
                        (fatal (% "Illegal default-floatsize %s. Must be one of: %s"
                                  (, value (join-nonempty ", " valid))))))
                  (set-default-floatsize args.default-floatsize)
                  (lfor name args.source
                        (if (os.path.isdir name)
                            ;; if asking for a directory just package it up
                            (archive-extra
                              (archive-dir
                                name
                                (make-archive-name
                                  (os.path.normpath name)
                                  args.version
                                  (int-dekformat args.dekformat)
                                  :recurse-subdirs args.search-subdirs
                                  :extra-arch-files args.extra-arch-files))
                              (if (is args.objects None) name args.objects))
                            (fatal (% "Not a directory '%s'!" name)))
                        ))
       ;; upload packaged external to pure-data.info
       :upload (fn [args]
                 (defn set-nonempty-password [username password]
                   (if password
                       (try (do
                              (import keyring)
                              (keyring.set_password "deken" username password))
                            (except [e Exception] (log.warning e)))))
                 (defn mk-pkg-ifneeded [x]
                   (cond [(os.path.isfile x)
                          (if (archive? x) x (fatal (% "'%s' is not an externals archive!" x)))]
                         [(os.path.isdir x)
                          (do
                            (import copy)
                            (get ((:package commands)
                                   (set-attr (copy.deepcopy args) "source" [x])) 0))]
                         [True (fatal (% "Unable to process '%s'!" x))]))
                 (defn do-upload-username [packages destination username check-sources?]
                   (upload-packages packages
                                    destination
                                    username
                                    (or destination.password
                                        (get-upload-password username args.ask-password))
                                    check-sources?))
                 (defn do-upload [packages destination check-sources?]
                   (do-upload-username packages
                                       destination
                                       (or destination.username
                                           (get-config-value "username")
                                           (prompt-for-value "username"
                                                             (% "for %s://%s"
                                                                (, (or destination.scheme default-destination.scheme)
                                                                   (or destination.hostname default-destination.hostname)))))
                                       check-sources?))
                 ;; do-upload returns the username (on success)...
                 ;; so let's try storing the (non-empty) password in the keyring
                 (set-nonempty-password #*
                                        (do-upload (lfor x args.source (mk-pkg-ifneeded x))
                                                   (urlparse
                                                     (or (getattr args "destination")
                                                         (get-config-value "destination" "")))
                                                   args.no-source-error)))
       ;; search for externals
       :find find
       :search find
       ;; verify downloaded files
       :verify (fn [args]
                 (for [p args.dekfile]
                   (if (os.path.isfile p)
                       (if (not
                             (verify
                               p
                               :gpg (and (not args.ignore-gpg) (if (or args.ignore-missing args.ignore-missing-gpg) None True))
                               :hash (and (not args.ignore-hash) (if (or args.ignore-missing args.ignore-missing-hash) None True))))
                           (fatal (% "verification of '%s' failed" (, p)))))))
       ;; download a package (but don't install it)
       :download
       (fn [args]
         (download-verified
           ;; parse package specifiers
           (categorize-search-terms args.package True False)
           :architecture (or args.architecture None)
           :verify-gpg (and (not args.ignore-gpg) (if (or args.ignore-missing args.ignore-missing-gpg) None True))
           :verify-hash (and (not args.ignore-hash) (if (or args.ignore-missing args.ignore-missing-hash) None True))
           :verify-none args.no-verify
           :search-url  args.search-url))
       :uninstall (fn [args] None
                    (if args.self
                        (fatal "self-'uninstall' not implemented for this platform!"))
                    (defn uninstall-pkgs [pkgs installdir]
                      (import shutil)
                      (for [pkg pkgs :if pkg]
                        (setv pkgdir (os.path.join installdir pkg))
                        (if (os.path.isdir pkgdir)
                            (do
                              (log.info (% "removing package directory '%s'" (, pkgdir)))
                              (shutil.rmtree pkgdir True))
                            (log.warning (% "skipping non-existent directory '%s'" (, pkgdir))))))
                    (setv pkgs (--packages-from-args-- args.package args.requirement))
                    (uninstall-pkgs pkgs args.installdir))
       :install (fn [args] None
                  (if (and (not args.package) (not args.requirement))
                      (fatal "self-'install' not implemented for this platform!"))
                  (defn install-pkgs [pkgs installdir]
                    (if pkgs
                        (do
                          (try
                            (os.makedirs installdir)
                            (except [e Exception]
                              (if (not (os.path.isdir installdir)) (raise e))))
                          (lfor pkg pkgs
                                :if (or
                                      (os.path.isfile pkg)
                                      (log.warning (% "skipping non-existing file '%s'" (, pkg))))
                                (install-package pkg installdir)))))
                  (setv pkgs (--packages-from-args-- args.package args.requirement))

                  ;; those search-terms that refer to local files
                  (setv file-pkgs (sfor x pkgs
                                        :if (and
                                              (package-uri? x)
                                              (os.path.exists x))
                                        x))
                  ;; search/download/verify the rest
                  (setv pkgs (.difference pkgs (set file-pkgs)))
                  (setv downloaded-pkgs
                        (if pkgs
                            (set (download-verified
                                   (categorize-search-terms (.difference pkgs (set file-pkgs)) True False)
                                   :architecture (or args.architecture None)
                                   :verify-gpg (and (not args.ignore-gpg) (if (or args.ignore-missing args.ignore-missing-gpg) None True))
                                   :verify-hash (and (not args.ignore-hash) (if (or args.ignore-missing args.ignore-missing-hash) None True))
                                   :verify-none args.no-verify
                                   :search-url args.search-url))
                            (set [])))
                  (install-pkgs (.union file-pkgs downloaded-pkgs) args.installdir)
                  )
       :systeminfo print-system-info
       ;; the rest should have been caught by the wrapper script
       :update upgrade
       :upgrade upgrade})

;; kick things off by using argparse to check out the arguments supplied by the user
(defn main []
  "run deken"
  (defn add-package-flags [parser]
    (parser.add_argument
      "--version" "-v"
      :help "A library version number to insert into the package name (in case the package is created)."
      :default None
      :required False)
    (parser.add_argument
      "--objects"
      :help "Specify a tsv-file that lists all the objects of the library (DEFAULT: generate it)."
      :default None
      :required False)
    (parser.add_argument
      "--search-subdirs"
      :help "EXPERT: Search subdirectories for externals to determine architecture string (DEFAULT: only search one level)."
      :action "store_true"
      :required False)
    (parser.add_argument
      "--extra-arch-files"
      :help "EXPERT: Additionally take the given files into account for determining the package architecture (DEFAULT: use externals found in the package directory)."
      :default []
      :nargs "*"
      :required False)
    (parser.add_argument
      "--default-floatsize"
      :help "EXPERT: Use the given float-size if it cannot be determined automatically. Use with care! (DEFAULT: None)."
      :default None
      :type int
      :required False)
    (parser.add_argument
      "--dekformat"
      :help "Override the deken packaging format, in case the package is created (DEFAULT: 1)."
      :default 1
      :required False))
  (defn add-noverify-flags [parser]
    (parser.add_argument
      "--ignore-missing"
      :action "store_true"
      :help "Don't fail if detached verification files are missing"
      :required False)
    (parser.add_argument
      "--ignore-missing-gpg"
      :action "store_true"
      :help "Don't fail if there is no GPG-signature"
      :required False)
    (parser.add_argument
      "--ignore-gpg"
      :action "store_true"
      :help "Ignore an unverifiable (or no) GPG-signature"
      :required False)
    (parser.add_argument
      "--ignore-missing-hash"
      :action "store_true"
      :help "Don't fail if there is no hashsum file"
      :required False)
    (parser.add_argument
      "--ignore-hash"
      :action "store_true"
      :help "Ignore an unverifiable hashsum"
      :required False))
  (defn add-search-flags [parser]
    (parser.add_argument
      "--search-url"
      :help "URL to query for deken-packages"
      :default ""
      :required False)
    (parser.add_argument
      "--architecture" "--arch"
      :help (% "Filter architectures; use '*' for all architectures (DEFAULT: %s)"
               (, (.join "-" (native-arch))))
      :action "append"
      :default []
      :required False))
  (defn add-find-flags [parser]
    (add-search-flags parser)
    (parser.add_argument
      "--depth"
      :help "Limit search result to the N last versions (0 is unlimited; DEFAULT: 1)"
      :default None
      :type int
      :required False)
    (parser.add_argument
      "--reverse"
      :action "store_true"
      :help "Reverse search result sorting"
      :required False)
    (parser.add_argument
      "--libraries"
      :action "store_true"
      :help "Find libraries (DEFAULT: True)"
      :required False)
    (parser.add_argument
      "--objects"
      :action "store_true"
      :help "Find objects (DEFAULT: True)"
      :required False)
    (parser.add_argument
      "search"
      :nargs "*"
      :metavar "TERM"
      :help "libraries/objects to search for")
    )

  (defn parse-args [parser]
    (setv args (.parse_args parser))
    (log.setLevel (max 1 (+ logging.WARN (* 10 (- args.quiet args.verbose)))))
    (del args.verbose)
    (del args.quiet)
    args)

  (setv arg-parser
        (argparse.ArgumentParser
          :prog "deken"
          :description "Deken is a packaging tool for Pure Data externals."))
  (setv arg-subparsers (arg-parser.add_subparsers
                         :dest "command"
                         :metavar "{package,upload,find,download,verify,install,uninstall,systeminfo}"
                         ))
  (setv arg-package (arg-subparsers.add_parser
                      "package"
                      :description "create (and sign) a DEK-package from a directory with externals/abstractions/... guessing the architecture(s)"
                      ))
  (setv arg-upload (arg-subparsers.add_parser
                     "upload"
                      :description "upload a DEK-package to the deken repository (eventually creating the package from a directory)"
                     ))
  (setv arg-find (arg-subparsers.add_parser
                   "find"
                   :description "find packages (and/or libraries containing objects) in the repository"
                   ))
  (setv arg-search (arg-subparsers.add_parser
                     "search"
                     :description "find packages (and/or libraries containing objects) in the repository"
                     ))

  ;; verify a downloaded package (both SHA256 and (if available GPG))
  (setv arg-verify (arg-subparsers.add_parser
                     "verify"
                     :description "verify a downloaded package (using SHA256 checksums and - if available - GPG)"))

  ;; download a package from the internet
  (setv arg-download (arg-subparsers.add_parser
                       "download"
                       :description "search for a package, download it and verify the download"))

  ;; install a package from the internet
  ;; - package can be either an URL, a local file or a search string
  ;; - packages are verified (SHA256/GPG)
  ;; - search is similar to "find", but requires an "exact match"
  ;;   and installs only the first match (with the highest version number)
  (setv arg-install (arg-subparsers.add_parser
                      "install"
                      :description "search for a package, download and verify it and install it to be used by Pd"))

  (setv arg-uninstall (arg-subparsers.add_parser
                        "uninstall"
                        :description "attempt to uninstall (delete) an installed package"))

  (setv arg-upgrade (arg-subparsers.add_parser "upgrade" :description "self-'update' deken."))
  (setv arg-update (arg-subparsers.add_parser "update" :description "self-'update' deken."))
  (arg-subparsers.add_parser "systeminfo" :description "print information about your deken installation.")

  (arg-parser.add_argument
    "-v" "--verbose"
    :help "Raise verbosity"
    :action "count"
    :default 0)
  (arg-parser.add_argument
    "-q" "--quiet"
    :help "Lower verbosity"
    :action "count"
    :default 0)
  (arg-parser.add_argument
    "--version"
    :action "version"
    :version version
    :help "Outputs the version number of Deken.")
  (arg-parser.add_argument
    "--platform"
    :action "version"
    :version (.join "-" (native-arch))
    :help "Outputs a guess of the current architecture.")

  (arg-package.add_argument
    "source"
    :nargs "+"
    :metavar "SOURCE"
    :help "The path to a directory of externals, abstractions, or GUI plugins to be packaged.")
  (add-package-flags arg-package)
  (arg-upload.add_argument
    "source"
    :nargs "+"
    :metavar "PACKAGE"
    :help "The path to a package file to be uploaded, or a directory which will be packaged first automatically.")
  (add-package-flags arg-upload)
  (arg-upload.add_argument
    "--destination" "-d"
    :help "The destination folder to upload the package to (DEFAULT: /Members/USER/software/PKGNAME/VERSION/)."
    :default ""
    :required False)
  (arg-upload.add_argument
    "--ask-password" "-P"
    :action "store_true"
    :help "Ask for upload password (rather than using password-manager."
    :default ""
    :required False)
  (arg-upload.add_argument
    "--no-source-error"
    :action "store_true"
    :help "Force-allow uploading of packages without sources."
    :required False)

  (add-find-flags arg-find)
  (add-find-flags arg-search)

  (add-noverify-flags arg-verify)

  (arg-verify.add_argument
    "dekfile"
    :nargs "*"
    :help "deken package to verify")
  (add-search-flags arg-download)
  (arg-download.add_argument
    "--no-verify"
    :action "store_true"
    :help "Don't abort download on verification errors")
  (add-noverify-flags arg-download)
  (arg-download.add_argument
    "package"
    :nargs "+"
    :help "package specifier or URL to download")

  (add-search-flags arg-install)
  (arg-install.add_argument
    "--no-verify"
    :action "store_true"
    :help "Don't abort download on verification errors")
  (add-noverify-flags arg-install)
  (arg-install.add_argument
    "--requirement" "-r"
    :action "append"
    :default []
    :help "Install from the given requirements file. This option can be used multiple times.")
  (arg-install.add_argument
    "--installdir"
    :default default-installpath
    :help (% "Target directory to install packages to (DEFAULT: %s)" (, default-installpath)))
  (arg-install.add_argument
    "--self"
    :action "store_true"
    :help "(Re)install the 'deken' cmdline-utility (and dependencies) itself")
  (arg-install.add_argument
    "package"
    :nargs "*"
    :help "package specifier or URL to install")

  (arg-update.add_argument
    "--self"
    :action "store_true"
    :required True
    :help "Update the 'deken' cmdline-utility (and dependencies) itself")
  (arg-upgrade.add_argument
    "--self"
    :action "store_true"
    :required True
    :help "Update the 'deken' cmdline-utility (and dependencies) itself")


  (arg-uninstall.add_argument
    "--requirement" "-r"
    :action "append"
    :default []
    :help "Uninstall packages specified in the given requirements file. This option can be used multiple times.")
  (arg-uninstall.add_argument
    "--installdir"
    :default default-installpath
    :help (% "Directory to find installed packages (DEFAULT: %s)" (, default-installpath)))
  (arg-uninstall.add_argument
    "--self"
    :action "store_true"
    :help "Remove the 'deken' cmdline-utility (and dependencies) itself")
  (arg-uninstall.add_argument
    "package"
    :nargs "*"
    :help "package to uninstall")

  (setv arguments (parse-args arg-parser))
  (setv command (.get commands (keyword arguments.command)))
  ;;(print "Deken" version)
  (log.debug (.join " " sys.argv))
  (if command (command arguments) (.print_help arg-parser)))

(if (= __name__ "__main__")
    (try
      (main)
      (except [e KeyboardInterrupt] (log.warning "\n[interrupted by user]"))))
