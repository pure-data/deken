# META NAME PdExternalsSearch
# META DESCRIPTION Search for externals zipfiles on puredata.info
# META AUTHOR <Chris McCormick> chris@mccormick.cx
# META AUTHOR <IOhannes m zmölnig> zmoelnig@iem.at
# ex: set setl sw=2 sts=2 et

# Search URL:
# http://deken.puredata.info/search?name=foobar

# TODOs
## open embedded README
## open README on homepage
## remove library before unzipping

# The minimum version of TCL that allows the plugin to run
package require Tcl 8.4
# If Tk or Ttk is needed
#package require Ttk
# Any elements of the Pd GUI that are required
# + require everything and all your script needs.
#   If a requirement is missing,
#   Pd will load, but the script will not.
package require http 2
# try enabling https if possible
if { [catch {package require tls} ] } {} {
    ::tls::init -ssl2 false -ssl3 false -tls1 true
    ::http::register https 443 ::tls::socket
}

package require pdwindow 0.1
package require pd_menucommands 0.1
package require pd_guiprefs

namespace eval ::deken:: {
    variable version

    variable installpath
    variable userplatform
    variable hideforeignarch
}

namespace eval ::deken::preferences {
    variable installpath
    variable userinstallpath
    variable platform
    variable userplatform
    variable hideforeignarch
}
namespace eval ::deken::utilities { }


## only register this plugin if there isn't any newer version already registered
## (if ::deken::version is defined and is higher than our own version)
proc ::deken::versioncheck {version} {
    if { [info exists ::deken::version ] } {
        set v0 [split $::deken::version "."]
        set v1 [split $version "."]
        foreach x $v0 y $v1 {
            if { $x > $y } {
                ::pdwindow::debug [format [_ "\[deken\]: installed version \[%1\$s\] > %2\$s...skipping!" ] $::deken::version $version ]
                ::pdwindow::debug "\n"
                return 0
            }
            if { $x < $y } {
                ::pdwindow::debug [format [_ "\[deken\]: installed version \[%1\$s] < %2\$s...overwriting!" ] $::deken::version $version ]
                ::pdwindow::debug "\n"
                set ::deken::version $version
                return 1
            }
        }
        ::pdwindow::debug [format [_ "\[deken\]: installed version \[%1\$s\] == %2\$s...skipping!" ] $::deken::version $version ]
        ::pdwindow::debug "\n"
        return 0
    }
    set ::deken::version $version
    return 1
}

## put the current version of this package here:
if { [::deken::versioncheck 0.2.4] } {
set ::deken::installpath {}
set ::deken::userplatform {}
set ::deken::hideforeignarch {}
set ::deken::preferences::installpath {}
set ::deken::preferences::userinstallpath {}
set ::deken::preferences::platform {}
set ::deken::preferences::userplatform {}
set ::deken::preferences::hideforeignarch {}

namespace eval ::deken:: {
    namespace export open_searchui
    variable mytoplevelref
    variable platform
    variable architecture_substitutes
    variable installpath
    variable statustext
    variable statustimer
    variable backends
    variable progressvar
    namespace export register
}
namespace eval ::deken::search:: { }

set ::deken::installpath ""
set ::deken::statustimer ""
set ::deken::userplaform ""
set ::deken::hideforeignarch false

proc ::deken::utilities::bool {value {fallback 0}} {
    catch {set fallback [expr bool($value) ] } stdout
    return $fallback
}

proc ::deken::utilities::is_writable_dir {path} {
    set fs [file separator]
    set access [list RDWR CREAT EXCL TRUNC]
    set tmpfile [::deken::get_tmpfilename $path]
    # try creating tmpfile
    if {![catch {open $tmpfile $access} channel]} {
        close $channel
        file delete $tmpfile
        return true
    }
    return false
}

proc ::deken::utilities::newwidget {basename} {
    # calculate a widget name that has not yet been taken
    set i 0
    while {[winfo exists ${basename}${i}]} {incr i}
    return ${basename}${i}
}

if { [ catch { set ::deken::installpath [::pd_guiprefs::read dekenpath] } stdout ] } {
    # this is a Pd without the new GUI-prefs
    proc ::deken::set_installpath {installdir} {
        set ::deken::installpath $installdir
    }
    proc ::deken::set_platform_options {platform hide} {
        set ::deken::userplatform $platform
        set ::deken::hideforeignarch [::deken::utilities::bool $hide ]
    }
    proc ::deken::set_install_options {remove readme} {
        set ::deken::remove_on_install [::deken::utilities::bool $remove]
        set ::deken::show_readme [::deken::utilities::bool $readme]
    }
} {
    # Pd has a generic preferences system, that we can use
    proc ::deken::set_installpath {installdir} {
        set ::deken::installpath $installdir
        ::pd_guiprefs::write dekenpath $installdir
    }
    # user requested platform (empty = DEFAULT)
    set ::deken::userplatform [::pd_guiprefs::read deken_platform]
    set ::deken::hideforeignarch [::deken::utilities::bool [::pd_guiprefs::read deken_hide_foreign_archs] ]
    proc ::deken::set_platform_options {platform hide} {
        set ::deken::userplatform $platform
        set ::deken::hideforeignarch [::deken::utilities::bool $hide ]
        ::pd_guiprefs::write deken_platform "$platform"
        ::pd_guiprefs::write deken_hide_foreign_archs $::deken::hideforeignarch
    }
    set ::deken::remove_on_install [::deken::utilities::bool [::pd_guiprefs::read deken_remove_on_install] ]
    set ::deken::show_readme [::deken::utilities::bool [::pd_guiprefs::read deken_show_readme] 1]
    proc ::deken::set_install_options {remove readme} {
        set ::deken::remove_on_install [::deken::utilities::bool $remove]
        set ::deken::show_readme [::deken::utilities::bool $readme]
        ::pd_guiprefs::write deken_remove_on_install "$::deken::remove_on_install"
        ::pd_guiprefs::write deken_show_readme "$::deken::show_readme"
    }
}

set ::deken::backends [list]
proc ::deken::register {fun} {
    set ::deken::backends [linsert $::deken::backends 0 $fun]
}
proc ::deken::gettmpdir {} {
    proc _iswdir {d} { expr [file isdirectory $d] * [file writable $d] }
    set tmpdir ""
    catch {set tmpdir $::env(TRASH_FOLDER)} ;# very old Macintosh. Mac OS X doesn't have this.
    if {[_iswdir $tmpdir]} {return $tmpdir}
    catch {set tmpdir $::env(TMP)}
    if {[_iswdir $tmpdir]} {return $tmpdir}
    catch {set tmpdir $::env(TEMP)}
    if {[_iswdir $tmpdir]} {return $tmpdir}
    set tmpdir "/tmp"
    set tmpdir [pwd]
    if {[_iswdir $tmpdir]} {return $tmpdir}
}
proc ::deken::vbs_unzipper {zipfile {path .}} {
    ## this is w32 only
    if { "Windows" eq "$::deken::platform(os)" } { } { return 0 }
    if { "" eq $::deken::_vbsunzip } {
        set ::deken::_vbsunzip [ file join [::deken::gettmpdir] unzip.vbs ]
    }

    if {[file exists $::deken::_vbsunzip]} {} {
        ## no script yet, create one
        set script {
Set fso = CreateObject("Scripting.FileSystemObject")

'The location of the zip file.
ZipFile = fso.GetAbsolutePathName(WScript.Arguments.Item(0))
'The folder the contents should be extracted to.
ExtractTo = fso.GetAbsolutePathName(WScript.Arguments.Item(1))

'If the extraction location does not exist create it.
If NOT fso.FolderExists(ExtractTo) Then
   fso.CreateFolder(ExtractTo)
End If

'Extract the contants of the zip file.
set objShell = CreateObject("Shell.Application")
set FilesInZip=objShell.NameSpace(ZipFile).items
objShell.NameSpace(ExtractTo).CopyHere(FilesInZip)
Set fso = Nothing
Set objShell = Nothing
}
        if {![catch {set fileId [open $::deken::_vbsunzip "w"]}]} {
            puts $fileId $script
            close $fileId
        }
    }
    if {[file exists $::deken::_vbsunzip]} {} {
        ## still no script, give up
        return 0
    }
    ## try to call the script
    if { [ catch { exec cscript $::deken::_vbsunzip $zipfile .} stdout ] } {
        ::pdwindow::debug "\[deken\] VBS-unzip: $::deken::_vbsunzip\n$stdout\n"
        return 0
    }
    return 1
}
set ::deken::_vbsunzip ""

proc ::deken::get_tmpfilename {{path ""}} {
    for {set i 0} {true} {incr i} {
        set tmpfile [file join ${path} dekentmp.${i}]
        if {![file exists $tmpfile]} {
            return $tmpfile
        }
    }
}

proc ::deken::get_writable_dir {paths} {
    foreach p $paths {
        if { [ ::deken::utilities::is_writable_dir $p ] } { return $p }
    }
    return
}

# find an install path, either from prefs or on the system
# returns an empty string if nothing was found
proc ::deken::find_installpath {{ignoreprefs false}} {
    set installpath ""
    if { [ info exists ::deken::installpath ] && !$ignoreprefs } {
        ## any previous choice?
        set installpath [ ::deken::get_writable_dir [list $::deken::installpath ] ]
    }
    if { "$installpath" == "" } {
        ## search the default paths
        set installpath [ ::deken::get_writable_dir $::sys_staticpath ]
    }
    if { "$installpath" == "" } {
        # let's use the first of $::sys_staticpath, if it does not exist yet
        set userdir [lindex $::sys_staticpath 0]
        if { [file exists ${userdir} ] } {} {
            set installpath $userdir
        }
    }
    return $installpath
}

proc ::deken::platform2string {} {
    return $::deken::platform(os)-$::deken::platform(machine)-$::deken::platform(bits)
}

# list-reverter (compat for tcl<8.5)
if {[info command lreverse] == ""} {
    proc lreverse list {
        set res {}
        set i [llength $list]
        while {$i} {
            lappend res [lindex $list [incr i -1]]
        }
        set res
    } ;# RS
}

set ::deken::platform(os) $::tcl_platform(os)
set ::deken::platform(machine) $::tcl_platform(machine)
set ::deken::platform(bits) [ expr [ string length [ format %X -1 ] ] * 4 ]

# normalize W32 OSs
if { [ string match "Windows *" "$::deken::platform(os)" ] > 0 } {
    # we are not interested in the w32 flavour, so we just use 'Windows' for all of them
    set ::deken::platform(os) "Windows"
}
# normalize W32 CPUs
if { "Windows" eq "$::deken::platform(os)" } {
    # in redmond, intel only produces 32bit CPUs,...
    if { "intel" eq "$::deken::platform(machine)" } { set ::deken::platform(machine) "i686" }
    # ... and all 64bit CPUs are manufactured by amd
    #if { "amd64" eq "$::deken::platform(machine)" } { set ::deken::platform(machine) "x86_64" }
}

# console message to let them know we're loaded
## but only if we are being called as a plugin (not as built-in)
if { "" != "$::current_plugin_loadpath" } {
    ::pdwindow::post [format [_ "\[deken\] deken-plugin.tcl (Pd externals search) loaded from %s." ]  $::current_plugin_loadpath ]
    ::pdwindow::post "\n"
}
::pdwindow::verbose 0 [format [_ "\[deken\] Platform detected: %s" ] [::deken::platform2string] ]
::pdwindow::verbose 0 "\n"

# architectures that can be substituted for eachother
array set ::deken::architecture_substitutes {}
set ::deken::architecture_substitutes(x86_64) [list "amd64" "i386" "i586" "i686"]
set ::deken::architecture_substitutes(amd64) [list "x86_64" "i386" "i586" "i686"]
set ::deken::architecture_substitutes(i686) [list "i586" "i386"]
set ::deken::architecture_substitutes(i586) [list "i386"]
set ::deken::architecture_substitutes(armv6l) [list "armv6" "arm"]
set ::deken::architecture_substitutes(armv7l) [list "armv7" "armv6l" "armv6" "arm"]
set ::deken::architecture_substitutes(PowerPC) [list "ppc"]
set ::deken::architecture_substitutes(ppc) [list "PowerPC"]

# try to set install path when plugin is loaded
set ::deken::installpath [::deken::find_installpath]

# allow overriding deken platform from Pd-core
proc ::deken::set_platform {os machine bits} {
    if { $os != $::deken::platform(os) ||
         $machine != $::deken::platform(machine) ||
         $bits != $::deken::platform(bits)} {
        set ::deken::platform(os) ${os}
        set ::deken::platform(machine) ${machine}
        set ::deken::platform(bits) ${bits}

        ::pdwindow::verbose 0 [format [_ "\[deken\] Platform (re)detected: %s" ] [::deken::platform2string ] ]
        ::pdwindow::verbose 0 "\n"
    }
}

proc ::deken::status {msg} {
    #variable mytoplevelref
    #$mytoplevelref.results insert end "$msg\n"
    #$mytoplevelref.status.label -text "$msg"
    after cancel $::deken::statustimer
    if {"" ne $msg} {
        set ::deken::statustext "STATUS: $msg"
        set ::deken::statustimer [after 5000 [list set ::deken::statustext ""]]
    } {
        set ::deken::statustext ""
    }
}
proc ::deken::scrollup {} {
    variable mytoplevelref
    $mytoplevelref.results see 0.0
}
proc ::deken::post {msg {tag ""}} {
    variable mytoplevelref
    $mytoplevelref.results insert end "$msg\n" $tag
    $mytoplevelref.results see end
}
proc ::deken::clearpost {} {
    variable mytoplevelref
    $mytoplevelref.results delete 1.0 end
}
proc ::deken::bind_posttag {tag key cmd} {
    variable mytoplevelref
    $mytoplevelref.results tag bind $tag $key $cmd
}
proc ::deken::highlightable_posttag {tag} {
    variable mytoplevelref
    ::deken::bind_posttag $tag <Enter> \
        "$mytoplevelref.results tag add highlight [ $mytoplevelref.results tag ranges $tag ]"
    ::deken::bind_posttag $tag <Leave> \
        "$mytoplevelref.results tag remove highlight [ $mytoplevelref.results tag ranges $tag ]"
    # make sure that the 'highlight' tag is topmost
    $mytoplevelref.results tag raise highlight
}
proc ::deken::do_prompt_installdir {path} {
   return [tk_chooseDirectory -title [_ "Install externals to directory:"] \
               -initialdir ${path} -parent .externals_searchui]
}

proc ::deken::prompt_installdir {} {
    set installdir [::deken::do_prompt_installdir $::fileopendir]
    if { "$installdir" != "" } {
        ::deken::set_installpath $installdir
        return 1
    }
    return 0
}


proc ::deken::update_searchbutton {mytoplevel} {
    if { [$mytoplevel.searchbit.entry get] == "" } {
        $mytoplevel.searchbit.button configure -text [_ "Show all" ]
    } {
        $mytoplevel.searchbit.button configure -text [_ "Search" ]
    }
}

proc ::deken::progress {x} {
    ::deken::post "= ${x}%"
}

# this function gets called when the menu is clicked
proc ::deken::open_searchui {mytoplevel} {
    if {[winfo exists $mytoplevel]} {
        wm deiconify $mytoplevel
        raise $mytoplevel
    } else {
        ::deken::create_dialog $mytoplevel
        $mytoplevel.results tag configure error -foreground red
        $mytoplevel.results tag configure warn -foreground orange
        $mytoplevel.results tag configure info -foreground grey
        $mytoplevel.results tag configure highlight -foreground blue
        $mytoplevel.results tag configure archmatch
        $mytoplevel.results tag configure noarchmatch -foreground grey
    }
    ::deken::post [_ "To get a list of all available externals, try an empty search."] info
}

# build the externals search dialog window
proc ::deken::create_dialog {mytoplevel} {
    toplevel $mytoplevel -class DialogWindow
    variable mytoplevelref $mytoplevel
    wm title $mytoplevel [_ "Find externals"]
    wm geometry $mytoplevel 670x550
    wm minsize $mytoplevel 230 360
    wm transient $mytoplevel
    $mytoplevel configure -padx 10 -pady 5

    if {$::windowingsystem eq "aqua"} {
        $mytoplevel configure -menu $::dialog_menubar
    }

    frame $mytoplevel.searchbit
    pack $mytoplevel.searchbit -side top -fill x

    entry $mytoplevel.searchbit.entry -font 18 -relief sunken -highlightthickness 1 -highlightcolor blue
    pack $mytoplevel.searchbit.entry -side left -padx 6 -fill x -expand true
    bind $mytoplevel.searchbit.entry <Key-Return> "::deken::initiate_search $mytoplevel"
    bind $mytoplevel.searchbit.entry <KeyRelease> "::deken::update_searchbutton $mytoplevel"
    focus $mytoplevel.searchbit.entry
    button $mytoplevel.searchbit.button -text [_ "Show all"] -default active -command "::deken::initiate_search $mytoplevel"
    pack $mytoplevel.searchbit.button -side right -padx 6 -pady 3 -ipadx 10

    frame $mytoplevel.warning
    pack $mytoplevel.warning -side top -fill x
    label $mytoplevel.warning.label -text [_ "Only install externals uploaded by people you trust."]
    pack $mytoplevel.warning.label -side left -padx 6

    frame $mytoplevel.status
    pack $mytoplevel.status -side bottom -fill x
    label $mytoplevel.status.label -textvariable ::deken::statustext
    pack $mytoplevel.status.label -side left -padx 6
    button $mytoplevel.status.preferences -text [_ "Preferences" ] -command "::deken::preferences::show"
    pack $mytoplevel.status.preferences -side right

    text $mytoplevel.results -takefocus 0 -cursor hand2 -height 100 -yscrollcommand "$mytoplevel.results.ys set"
    scrollbar $mytoplevel.results.ys -orient vertical -command "$mytoplevel.results yview"
    pack $mytoplevel.results.ys -side right -fill y
    pack $mytoplevel.results -side top -padx 6 -pady 3 -fill both -expand true

    if { [ catch {
        ttk::progressbar $mytoplevel.progress -orient horizontal -length 640 -maximum 100 -mode determinate -variable ::deken::progressvar } stdout ] } {
    } {
        pack $mytoplevel.progress -side bottom
        proc ::deken::progress {x} {
            set ::deken::progressvar $x
        }
    }
}

proc ::deken::preferences::create_pad {toplevel {padx 2} {pady 2} } {
    set mypad [::deken::utilities::newwidget ${toplevel}.pad]

    frame $mypad
    pack $mypad -padx ${padx} -pady ${pady} -expand 1 -fill y

    return mypad
}

proc ::deken::preferences::userpath_doit { } {
    set installdir [::deken::do_prompt_installdir ${::deken::preferences::userinstallpath}]
    if { "${installdir}" != "" } {
        set ::deken::preferences::userinstallpath "${installdir}"
    }
}
proc ::deken::preferences::path_doit {origin path {mkdir true}} {
    ${origin}.doit configure -state normal
    ${origin}.path configure -state disabled

    if { [file exists ${path}] } { } {
        ${origin}.doit configure -text "Create"
        if { $mkdir } {
            catch { file mkdir $path }
        }
    }

    if { [file exists ${path}] } {
        ${origin}.doit configure -text "Check"
    }

    if { [::deken::utilities::is_writable_dir ${path} ] } {
        ${origin}.doit configure -state disabled
        ${origin}.path configure -state normal
    }
}

proc ::deken::preferences::create_pathentries {toplevel var paths} {
    set i 0

    foreach path $paths {
        set w [::deken::utilities::newwidget ${toplevel}.frame]

        frame $w
        pack $w -anchor w -fill x

        radiobutton ${w}.path -value ${path} -text "${path}" -variable $var
        pack ${w}.path -side left
        frame ${w}.fill
        pack ${w}.fill -side left -padx 12 -fill x -expand 1
        button ${w}.doit -text "..." -command "::deken::preferences::path_doit ${w} ${path}"
        ::deken::preferences::path_doit ${w} ${path} false
        pack ${w}.doit -side right -fill y -anchor e -padx 5 -pady 0
        if { [::deken::utilities::is_writable_dir ${path} ] } {
            ${w}.doit configure -state disabled
            ${w}.path configure -state normal
        } else {
            ${w}.doit configure -state normal
            ${w}.path configure -state disabled
        }
    }
}

proc ::deken::preferences::create {mytoplevel} {
    set ::deken::preferences::installpath $::deken::installpath
    set ::deken::preferences::hideforeignarch $::deken::hideforeignarch
    if { $::deken::userplatform == "" } {
        set ::deken::preferences::platform DEFAULT
        set ::deken::preferences::userplatform [ ::deken::platform2string ]
    } {
        set ::deken::preferences::platform USER
        set ::deken::preferences::userplatform $::deken::userplatform
    }

    set ::deken::preferences::installpath USER
    set ::deken::preferences::userinstallpath $::deken::installpath

    set ::deken::preferences::show_readme $::deken::show_readme
    set ::deken::preferences::remove_on_install $::deken::remove_on_install

    # this dialog allows us to select:
    #  - which directory to extract to
    #    - including all (writable) elements from $::sys_staticpath
    #      and option to create each of them
    #    - a directory chooser
    #  - whether to delete directories before re-extracting
    #  - whether to filter-out non-matching architectures
    labelframe $mytoplevel.installdir -text [_ "Install externals to directory:" ] -padx 5 -pady 5 -borderwidth 1
    pack $mytoplevel.installdir -side top -fill x

    ### dekenpath: directory-chooser
    # FIXME: should we ask user to add chosen directory to PATH?
    set f ${mytoplevel}.installdir.user
    labelframe ${f} -borderwidth 1
    pack ${f} -anchor w -fill x

    radiobutton ${f}.path \
        -value "USER" \
        -textvariable ::deken::preferences::userinstallpath \
        -variable ::deken::preferences::installpath
    pack ${f}.path -side left
    frame ${f}.fill
    pack ${f}.fill -side left -padx 12 -fill x -expand 1
    button ${f}.doit -text "..." -command "::deken::preferences::userpath_doit"
    pack ${f}.doit -side right -fill y -anchor e -padx 5 -pady 0
    ::deken::preferences::create_pad $mytoplevel.installdir

    ### dekenpath: default directories
    if {[namespace exists ::pd_docsdir] && [::pd_docsdir::externals_path_is_valid]} {
        ::deken::preferences::create_pathentries $mytoplevel.installdir ::deken::preferences::installpath {[::pd_docsdir::get_externals_path]}
        ::deken::preferences::create_pad $mytoplevel.installdir
    }
    ::deken::preferences::create_pathentries $mytoplevel.installdir ::deken::preferences::installpath $::sys_staticpath

    ::deken::preferences::create_pad $mytoplevel.installdir
    ::deken::preferences::create_pathentries $mytoplevel.installdir ::deken::preferences::installpath $::sys_searchpath

    ## installation options
    labelframe $mytoplevel.install -text [_ "Installation options:" ] -padx 5 -pady 5 -borderwidth 1
    pack $mytoplevel.install -side top -fill x -anchor w

    checkbutton $mytoplevel.install.remove -text [_ "Try to remove libraries before (re)installing them?"] \
        -variable ::deken::preferences::remove_on_install
    pack $mytoplevel.install.remove -anchor w

    checkbutton $mytoplevel.install.readme -text [_ "Show README of newly installed libraries?"] \
        -variable ::deken::preferences::show_readme
    pack $mytoplevel.install.readme -anchor w


    ## platform filter settings
    labelframe $mytoplevel.platform -text [_ "Platform settings:" ] -padx 5 -pady 5 -borderwidth 1
    pack $mytoplevel.platform -side top -fill x -anchor w

    # default architecture vs user-defined arch
    radiobutton $mytoplevel.platform.default -value "DEFAULT" \
        -text [format [_ "Default platform: %s" ] [::deken::platform2string ] ] \
        -variable ::deken::preferences::platform \
        -command "$mytoplevel.platform.userarch.entry configure -state disabled"
    pack $mytoplevel.platform.default -anchor w

    frame $mytoplevel.platform.userarch
    radiobutton $mytoplevel.platform.userarch.radio -value "USER" \
        -text [_ "User-defined platform:" ] \
        -variable ::deken::preferences::platform \
        -command "$mytoplevel.platform.userarch.entry configure -state normal"
    entry $mytoplevel.platform.userarch.entry -textvariable ::deken::preferences::userplatform
    if { "$::deken::preferences::platform" == "DEFAULT" } {
        $mytoplevel.platform.userarch.entry configure -state disabled
    }

    pack $mytoplevel.platform.userarch -anchor w
    pack $mytoplevel.platform.userarch.radio -side left
    pack $mytoplevel.platform.userarch.entry -side right -fill x

    # hide non-matching architecture?
    ::deken::preferences::create_pad $mytoplevel.platform 2 10

    checkbutton $mytoplevel.platform.hide_foreign -text [_ "Hide foreign architectures?"] \
        -variable ::deken::preferences::hideforeignarch
    pack $mytoplevel.platform.hide_foreign -anchor w


    # Use two frames for the buttons, since we want them both bottom and right
    frame $mytoplevel.nb
    pack $mytoplevel.nb -side bottom -fill x -pady 2m

    # buttons
    frame $mytoplevel.nb.buttonframe
    pack $mytoplevel.nb.buttonframe -side right -fill x -padx 2m

    button $mytoplevel.nb.buttonframe.cancel -text [_ "Cancel"] \
        -command "::deken::preferences::cancel $mytoplevel"
    pack $mytoplevel.nb.buttonframe.cancel -side left -expand 1 -fill x -padx 15 -ipadx 10
    if {$::windowingsystem ne "aqua"} {
        button $mytoplevel.nb.buttonframe.apply -text [_ "Apply"] \
            -command "::deken::preferences::apply $mytoplevel"
        pack $mytoplevel.nb.buttonframe.apply -side left -expand 1 -fill x -padx 15 -ipadx 10
    }
    button $mytoplevel.nb.buttonframe.ok -text [_ "OK"] \
        -command "::deken::preferences::ok $mytoplevel"
    pack $mytoplevel.nb.buttonframe.ok -side left -expand 1 -fill x -padx 15 -ipadx 10
}

proc ::deken::preferences::show {{mytoplevel .deken_preferences}} {
    if {[winfo exists $mytoplevel]} {
        wm deiconify $mytoplevel
        raise $mytoplevel
    } else {
        toplevel $mytoplevel -class DialogWindow
        wm title $mytoplevel [format [_ "Deken %s Preferences"] $::deken::version]

        frame $mytoplevel.frame
        pack $mytoplevel.frame -side top -padx 6 -pady 3 -fill both -expand true

        ::deken::preferences::create $mytoplevel.frame
    }
}

proc ::deken::preferences::apply {mytoplevel} {
    set installpath "${::deken::preferences::installpath}"
    if { "$installpath" == "USER" } {
        set installpath "${::deken::preferences::userinstallpath}"
    }

    ::deken::set_installpath "$installpath"
    set plat ""
    if { "${::deken::preferences::platform}" == "USER" } {
        set plat "${::deken::preferences::userplatform}"
    }
    ::deken::set_platform_options "${plat}" "${::deken::preferences::hideforeignarch}"
    ::deken::set_install_options "${::deken::preferences::remove_on_install}" "${::deken::preferences::show_readme}"
}
proc ::deken::preferences::cancel {mytoplevel} {
    ## FIXXME properly close the window/frame (for re-use in a tabbed pane)
    if {[winfo exists .deken_preferences]} {destroy .deken_preferences}
    destroy $mytoplevel
}
proc ::deken::preferences::ok {mytoplevel} {
    ::deken::preferences::apply $mytoplevel
    ::deken::preferences::cancel $mytoplevel
}



proc ::deken::initiate_search {mytoplevel} {
    # let the user know what we're doing
    ::deken::clearpost
    ::deken::post [_ "Searching for externals..."]
    set ::deken::progressvar 0
    if { [ catch {
        set results [::deken::search_for [$mytoplevel.searchbit.entry get]]
    } stdout ] } {
        ::pdwindow::debug [format [_ "\[deken\]: online? %s" ] $stdout ]
        ::pdwindow::debug "\n"
        ::deken::status [_ "Unable to perform search. Are you online?" ]
    } else {
    # delete all text in the results
    ::deken::clearpost
    if {[llength $results] != 0} {
        set counter 0
        # build the list UI of results
        foreach r $results {
            ::deken::show_result $mytoplevel $counter $r 1
            incr counter
        }
        if { "$::deken::hideforeignarch" } {
            # skip display of non-matching archs
        } {
            foreach r $results {
                ::deken::show_result $mytoplevel $counter $r 0
                incr counter
            }
        }
	::deken::scrollup
    } else {
        ::deken::post [_ "No matching externals found. Try using the full name e.g. 'freeverb'." ]
    }
}}

# display a single found entry
proc ::deken::show_result {mytoplevel counter result showmatches} {
    foreach {title cmd match comment status} $result {break}

    set tag ch$counter
    #if { [ ($match) ] } { set matchtag archmatch } { set matchtag noarchmatch }
    set matchtag [expr $match?"archmatch":"noarchmatch" ]
    if {($match == $showmatches)} {
        set comment [string map {"\n" "\n\t"} $comment]
        ::deken::post "$title\n\t$comment\n" [list $tag $matchtag]
        ::deken::highlightable_posttag $tag
        ::deken::bind_posttag $tag <Enter> "+::deken::status $status"
        ::deken::bind_posttag $tag <1> "$cmd"
    }
}

# handle a clicked link
proc ::deken::clicked_link {URL filename} {
    ## make sure that the destination path exists
    ### if ::deken::installpath is set, use the first writable item
    ### if not, get a writable item from one of the searchpaths
    ### if this still doesn't help, ask the user
    set installdir [::deken::find_installpath]
    set extname [lindex [split $filename "-"] 0]
    if { "$installdir" == "" } {
        if {[namespace exists ::pd_docsdir] && [::pd_docsdir::externals_path_is_valid]} {
            # if the docspath is set, try the externals subdir
            set installdir [::pd_docsdir::get_externals_path]
        } else {
            # ask the user (and remember the decision)
            ::deken::prompt_installdir
            set installdir [ ::deken::get_writable_dir [list $::deken::installpath ] ]
        }
    }
    while {1} {
        if { "$installdir" == "" } {
            set msg  [_ "Please select a (writable) installation directory!"]
            set _args "-message $msg -type retrycancel -default retry -icon warning -parent .externals_searchui"
            switch -- [eval tk_messageBox ${_args}] {
                cancel {return}
                retry {
                    if {[::deken::prompt_installdir]} {
                        set installdir $::deken::installpath
                    } else {
                        continue
                    }
                }
            }
        } else {
            set msg [_ "Install %s to %s?" ]
            set _args "-message \"[format $msg $extname $installdir]\" -type yesnocancel -default yes -icon question -parent .externals_searchui"
            switch -- [eval tk_messageBox ${_args}] {
                cancel {return}
                yes { }
                no {
                    set prevpath $::deken::installpath
                    if {[::deken::prompt_installdir]} {
                        set keepprevpath 1
                        set installdir $::deken::installpath
                        # if docsdir is set & the install path is valid,
                        # saying "no" is temporary to ensure the docsdir
                        # hierarchy remains, use the Path dialog to override
                        if {[namespace exists ::pd_docsdir] && [::pd_docsdir::path_is_valid] &&
                            [file writable [file normalize $prevpath]] } {
                            set keepprevpath 0
                        }
                        if {$keepprevpath} {
                            set ::deken::installpath $prevpath
                        }
                    } else {
                        continue
                    }
                }
            }
        }

        if { "$installdir" != "" } {
            # try creating the installdir...just in case
            if { [ catch { file mkdir $installdir } ] } {}
        }
        # check whether this is a writable directory
        set installdir [ ::deken::get_writable_dir [list $installdir ] ]
        if { "$installdir" != "" } {
            # stop looping if we've found our dir
            break
        }
    }

    set fullpkgfile "$installdir/$filename"
    ::deken::clearpost
    ::deken::post [format [_ "Commencing downloading of:\n%1\$s\nInto %2\$s..."] $URL $installdir] ]
    set fullpkgfile [::deken::download_file $URL $fullpkgfile]
    if { "$fullpkgfile" eq "" } {
        ::deken::post [_ "aborting."] info
        return
    }

    set PWD [ pwd ]
    cd $installdir
    set success 1
    if { [ string match *.zip $fullpkgfile ] } then {
        if { [ ::deken::vbs_unzipper $fullpkgfile  $installdir ] } { } {
            if { [ catch { exec unzip -uo $fullpkgfile } stdout ] } {
                ::pdwindow::debug "$stdout\n"
                set success 0
            }
        }
    } elseif  { [ string match *.tar.* $fullpkgfile ]
                || [ string match *.tgz $fullpkgfile ]
              } then {
        if { [ catch { exec tar xf $fullpkgfile } stdout ] } {
            ::pdwindow::debug "$stdout\n"
            set success 0
        }
    }
    cd $PWD
    if { $success > 0 } {
        ::deken::post [format [_ "Successfully unzipped %1\$s into %2\$s."] $filename $installdir ]
        ::deken::post ""
        catch { file delete $fullpkgfile }
    } else {
        # Open both the fullpkgfile folder and the zipfile itself
        # NOTE: in tcl 8.6 it should be possible to use the zlib interface to actually do the unzip
        ::deken::post [_ "Unable to extract package automatically." ] warn
        ::deken::post [_ "Please perform the following steps manually:" ]
        ::deken::post [format [_ "1. Unzip %s." ]  $fullpkgfile ]
        pd_menucommands::menu_openfile $fullpkgfile
        ::deken::post [format [_ "2. Copy the contents into %s." ] $installdir]
        ::deken::post ""
        pd_menucommands::menu_openfile $installdir
    }

## FIXXME: should we really suggest to add to search-paths?
## per library search-paths should be added via [declare]

    # add to the search paths? bail if the version of pd doesn't support it
    if {[uplevel 1 info procs add_to_searchpaths] eq ""} {return}
    set extpath [file join $installdir $extname]
    if {![file exists $extpath]} {
        ::deken::post [_ "Unable to add %s to search paths"] $extname
        return
    }
    set msg [_ "Add %s to the Pd search paths?" ]
    set _args "-message \"[format $msg $extname]\" -type yesno -default yes -icon question -parent .externals_searchui"
    switch -- [eval tk_messageBox ${_args}] {
        yes {
            add_to_searchpaths [file join $installdir $extname]
            ::deken::post [format [_ "Added %s to search paths"] $extname]
            # if this version of pd supports it, try refreshing the helpbrowser
            if {[uplevel 1 info procs ::helpbrowser::refresh] ne ""} {
                ::helpbrowser::refresh
            }
        }
        no {
            return
        }
    }
}

# download a file to a location
# http://wiki.tcl.tk/15303
proc ::deken::download_file {URL outputfilename} {
    set downloadfilename [::deken::get_tmpfilename [file dirname $outputfilename] ]
    set f [open $downloadfilename w]
    fconfigure $f -translation binary

    set httpresult [::http::geturl $URL -binary true -progress "::deken::download_progress" -channel $f]
    set ncode [::http::ncode $httpresult]
    if {[expr $ncode != 200 ]} {
        ## FIXXME: we probably should handle redirects correctly
        # tcl-format
        ::deken::post [format [_ "Unable to download from %1\$s \[%2\$s\]" ] $URL $ncode ] error
        set outputfilename ""
    }
    flush $f
    close $f
    ::http::cleanup $httpresult

    if { "$outputfilename" != "" } {
        catch { file delete $outputfilename }
        if {[file exists $outputfilename]} {
            ::deken::post [format [_ "Unable to remove stray file %s" ] $outputfilename ] error
            set outputfilename ""
        }
    }
    if { $outputfilename != "" && "$outputfilename" != "$downloadfilename" } {
        if {[catch { file rename $downloadfilename $outputfilename}]} {
            ::deken::post [format [_ "Unable to rename downloaded file to %s" ] $outputfilename ] error
            set outputfilename ""
        }
    }
    if { "$outputfilename" eq "" } {
        file delete $downloadfilename
    }

    return $outputfilename
}

# print the download progress to the results window
proc ::deken::download_progress {token total current} {
    if { $total > 0 } {
        ::deken::progress [expr {round(100 * (1.0 * $current / $total))}]
    }
}

# parse a deken-packagefilename into it's components: <pkgname>[-v<version>-]?{(<arch>)}-externals.zip
# return: list <pkgname> <version> [list <arch> ...]
proc ::deken::parse_filename {filename} {
    set pkgname $filename
    set archs [list]
    set version ""
    if { [ regexp {(.*)-externals\..*} $filename _ basename] } {
        set pkgname $basename
        # basename <pkgname>[-v<version>-]?{(<arch>)}
        ## strip off the archs
        set baselist [split $basename () ]

        # get pkgname + version
        set pkgver [lindex $baselist 0]
        if { ! [ regexp "(.*)-(.*)-" $pkgver _ pkgname version ] } {
            set pkgname $pkgver
            set $version ""
        }
        # get archs
        foreach {a _} [lreplace $baselist 0 0] { lappend archs $a }
    }
    return [list $pkgname $version $archs]
}

# test for platform match with our current platform
proc ::deken::architecture_match {archs} {
    # if there are no architecture sections this must be arch-independent
    if { ! [llength $archs] } { return 1}
    set OS "$::deken::platform(os)"
    set MACHINE "$::deken::platform(machine)"
    set BITS "$::deken::platform(bits)"
    if { "$::deken::userplatform" != "" } {
        ## FIXXME what if the user-supplied input isn't valid?
        regexp -- {(.*)-(.*)-(.*)} $::deken::userplatform _ OS MACHINE BITS
    }

    # check each architecture in our list against the current one
    foreach arch $archs {
        if { [ regexp -- {(.*)-(.*)-(.*)} $arch _ os machine bits ] } {
            if { "${os}" eq "$OS" &&
                 "${bits}" eq "$BITS"
             } {
                ## so OS and word size match
                ## check whether the CPU matches as well
                if { "${machine}" eq "${MACHINE}" } {return 1}
                ## not exactly; see whether it is in the list of compat CPUs
                if {[llength [array names ::deken::architecture_substitutes -exact "${MACHINE}"]]} {
                    foreach cpu $::deken::architecture_substitutes(${MACHINE}) {
                        if { "${machine}" eq "${cpu}" } {return 1}
                    }
                }
            }
        }
    }
    return 0
}

proc ::deken::search_for {term} {
    ::deken::status [format [_ "searching for '%s'" ] $term ]

    set result [list]
    foreach searcher $::deken::backends {
        set result [concat $result [ $searcher $term ] ]
    }
    return $result
}

# create an entry for our search in the "help" menu (or re-use an existing one)
set mymenu .menubar.help
if { [catch {
    $mymenu entryconfigure [_ "Find externals"] -command {::deken::open_searchui .externals_searchui}
} _ ] } {
    $mymenu add separator
    $mymenu add command -label [_ "Find externals"] -command {::deken::open_searchui .externals_searchui}
}
# bind all <$::modifier-Key-s> {::deken::open_helpbrowser .helpbrowser2}

# http://rosettacode.org/wiki/URL_decoding#Tcl
proc urldecode {str} {
    set specialMap {"[" "%5B" "]" "%5D"}
    set seqRE {%([0-9a-fA-F]{2})}
    set replacement {[format "%c" [scan "\1" "%2x"]]}
    set modStr [regsub -all $seqRE [string map $specialMap $str] $replacement]
    return [encoding convertfrom utf-8 [subst -nobackslash -novariable $modStr]]
}


# ####################################################################
# search backends
# ####################################################################

## API draft

# each backend is implemented via a single proc
## that takes a single argument "term", the term to search fo
## an empty term indicates "search for all"
# the backend then returns a list of results
## each result is a list of the following elements:
##   <title> <cmd> <match> <comment> <status>
## title: the primary name to display
##        (the user will select the element by this name)
##        e.g. "frobscottle-1.10 (Linux/amd64)"
## cmd  : a command that will install the selected library
##        e.g. "[list ::deken::clicked_link http://bfg.org/frobscottle-1.10.zip frobscottle-1.10.zip]"
## match: an integer indicating whether this entry is actually usable
##        on this host (1) or not (0)
## comment: secondary line to display
##        e.g. "uploaded by the BFG in 1982"
## status: line to display in the status-line
##        e.g. "http://bfg.org/frobscottle-1.10.zip"
# note on sorting:
## the results ought to be sorted with most up-to-date first
##  (filtering based on architecture-matches should be ignored when sorting!)
# note on helper-functions:
## you can put whatever you like into <cmd>, even your own proc


# registration
## to register a new search function, call `::deken::register $myfun`

# namespace
## you are welcome to use the ::deken::search:: namespace



## ####################################################################
## searching puredata.info
proc ::deken::search::puredata.info {term} {
    set searchresults [list]
    set dekenserver "http://deken.puredata.info/search"
    catch {set dekenserver $::env(DEKENSERVER)} stdout
    set term [ join $term "&name=" ]
    set httpaccept [::http::config -accept]
    ::http::config -accept text/tab-separated-values
    set token [::http::geturl "${dekenserver}?name=${term}"]
    ::http::config -accept $httpaccept
    set contents [::http::data $token]
    set splitCont [split $contents "\n"]
    # loop through the resulting tab-delimited table
    foreach ele $splitCont {
        set ele [ string trim $ele ]
        if { "" ne $ele } {
            set sele [ split $ele "\t" ]

            set name  [ string trim [ lindex $sele 0 ]]
            set URL   [ string trim [ lindex $sele 1 ]]
            set creator [ string trim [ lindex $sele 2 ]]
            set date    [regsub -all {[TZ]} [ string trim [ lindex $sele 3 ] ] { }]
            set decURL [urldecode $URL]
            set filename [ file tail $URL ]
            set cmd [list ::deken::clicked_link $decURL $filename]
            set pkgverarch [ ::deken::parse_filename $filename ]
            set archs [lindex $pkgverarch 2]

            set match [::deken::architecture_match "$archs" ]

            set comment [format [_ "Uploaded by %1\$s @ %2\$s" ] $creator $date ]
            set status $URL
            set sortname [lindex $pkgverarch 0]--[lindex $pkgverarch 1]--$date
            set res [list $name $cmd $match $comment $status $filename]
            lappend searchresults $res
        }
    }
    ::http::cleanup $token
    return [lsort -dictionary -decreasing -index 5 $searchresults ]
}

::deken::register ::deken::search::puredata.info
}
