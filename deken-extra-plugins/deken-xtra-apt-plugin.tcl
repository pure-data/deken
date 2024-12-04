# META NAME PdExternalsSearch
# META DESCRIPTION Search for externals Debian-packages via apt
# META AUTHOR IOhannes m zmölnig <zmoelnig@iem.at>
# ex: set setl sw=2 sts=2 et

# Search URL:
# http://puredata.info/search_rss?SearchableText=xtrnl-

# The minimum version of TCL that allows the plugin to run
package require Tcl 8.4

## ####################################################################
## searching apt (if available)
namespace eval ::deken::apt {
    namespace export search
    namespace export install
    variable distribution
    variable pluginpath $::current_plugin_loadpath
}

proc ::deken::apt::search {name} {
    if { [ info proc ${::deken::apt::searcher} ] } {
        return [::deken::apt::search_pyapt ${name}]
    }
    return
}
proc ::deken::apt::search_pyapt {name} {
    set result {}
    set cmd "${::deken::apt::search_pyaptscript} --api 1 --os $::deken::platform(os) --architecture $::deken::platform(machine) --floatsize $::deken::platform(floatsize) -- ${name}"
    set io [open "|${cmd}" ]
    while { [gets ${io} line ] >= 0 }  {
        foreach {pkgname version arch is_installed uploader date uri status comment} [ split "${line}" "\t" ] {break}
        set name ${pkgname}
        set cmd [list ::deken::apt::install ${pkgname}=${version}]
        set match 1
        set contextcmds {}
        if { ${uri} ne {} } {
            lappend contextcmds [list [_ "Open package webpage" ] "pd_menucommands::menu_openfile [file dirname ${uri}]"]
            lappend contextcmds [list [_ "Copy package URL" ] "clipboard clear; clipboard append ${uri}"]
            if { ${is_installed} } {
                lappend contextcmds {}
            }
        }
        if { ${is_installed} } {
            lappend contextcmds [::deken::apt::contextmenu::uninstall ${pkgname}]
        }

        set contextcmd [list ::deken::apt::contextmenu %W %x %y $contextcmds]
        set norm [::deken::normalize_result "${pkgname} - ${status}" ${cmd} ${match} ${comment} ${status} ${contextcmd} ${pkgname} ${version} ${uploader} ${date}]
        lappend result ${norm}
    }
    close ${io}
    return ${result}
}
proc ::deken::apt::search_madison {name} {
    set result []
    if { [info exists ::deken::apt::distribution] } { } {
        if { [ catch { exec lsb_release -si } ::deken::apt::distribution ] } {
            set ::deken::apt::distribution {}
        }
    }
    if { "${::deken::apt::distribution}" == "" } {
        return
    }

    set name [ string tolower ${name} ]
    array unset pkgs
    array set pkgs {}
    set _dpkg_query {dpkg-query -W -f ${db:Status-Abbrev}${Version}\n}

    # pd-externals must depend on Pd somehow
    # (this misses packages that provide pd-externals among *other* things,
    #  and therefore would only 'Recommend' Pd...)
    set pdpkgs {pd puredata puredata-core puredata-gui}
    if { $::deken::platform(floatsize) == 64 } {
        set pdpkgs {pd64 puredata64 puredata64-core puredata-gui}
    }
    set pdfilter [concat {-F Depends -w} [join $pdpkgs " --or -F Depends -w "]]

    set filter ${pdfilter}
    if { "${name}" == "" } { } {
        set filter "-F Package ${name} --and ( ${filter} )"
    }

    #set io [ open "|grep-aptavail -n -s Package,Version ${filter} | paste -sort -u | xargs apt-cache madison" r ]
    set io [ open "|grep-aptavail -n -s Package ${filter} | sort -u | xargs apt-cache madison" r ]
    while { [ gets ${io} line ] >= 0 } {
        set llin [ split "${line}" "|" ]
        set pkgname [ string trim [ lindex ${llin} 0 ] ]

        #if { ${pkgname} ne ${searchname} } { continue }
        set ver_  [ string trim [ lindex ${llin} 1 ] ]
        set info_ [ string trim [ lindex ${llin} 2 ] ]

        ## status: is the package installed?
        set state "Provided"
        set installed 0
        catch {
            set io2cmd "|${_dpkg_query} ${pkgname} | grep -w -F \"ii ${ver_}\""
            set io2 [ open "${io2cmd}" ]
	    if { [ gets ${io2} _ ] >= 0 } {
		set state "Already installed"
                set installed 1
	    } {
		while { [ gets ${io2} _ ] >= 0 } { }
	    }
	}
        if { "Packages" eq [ lindex ${info_} end ] } {
            set suite [ lindex ${info_} 1 ]
            set arch  [ lindex ${info_} 2 ]
            if { ! [ info exists pkgs(${pkgname}/${ver_}) ] } {
                set pkgs(${pkgname}/${ver_}) [ list ${pkgname} ${ver_} ${suite} ${arch} ${state} ${installed}]
            }
        }
    }
    foreach {name inf} [ array get pkgs ] {
        set pkgname [ lindex ${inf} 0 ]
        set v       [ lindex ${inf} 1 ]
        set suite   [ lindex ${inf} 2 ]
        set arch    [ lindex ${inf} 3 ]
        set state   [ lindex ${inf} 4 ]
        set cmd [list ::deken::apt::install ${pkgname}=${v}]
        set match 1
        set comment "${state} by ${::deken::apt::distribution} (${suite})"
        set status "${pkgname}_${v}_${arch}.deb"
        set contextcmd {}
        set contextcmds {}
        if { [ lindex ${inf} 5 ] } {
            lappend contextcmds [::deken::apt::contextmenu::uninstall ${pkgname}]
        }
        if { ${contextcmds} eq {} } {
            set contextcmd {}
        } else {
            set contextcmd [list ::deken::apt::contextmenu %W %x %y $contextcmds]
        }
        lappend result [list ${name} ${cmd} ${match} ${comment} ${status} ${pkgname} ${v} ${suite} ${contextcmd}]
    }

    # version-sort the results and normalize the result-string
    set sortedresult []
    if {[llength [info procs ::deken::normalize_result ]] > 0} {
        foreach r [lsort -dictionary -decreasing -index 1 ${result} ] {
            foreach {title cmd match comment status pkgname version suite cmd2} ${r} {break}
            lappend sortedresult [::deken::normalize_result ${title} ${cmd} ${match} ${comment} ${status} ${cmd2} ${pkgname} ${version} Debian ${suite}]
        }
    } {
        foreach r [lsort -dictionary -decreasing -index 1 ${result} ] {
            # [list ${title} ${cmd} ${match} ${comment} ${status}]
            foreach {title cmd match comment status} ${r} {break}
            lappend sortedresult [list ${title} ${cmd} ${match} ${comment} ${status}]
        }
    }
    return ${sortedresult}
}


proc ::deken::apt::contextmenu {widget theX theY commands} {
    set m .dekenresults_contextMenu
    destroy ${m}
    if { ${commands} eq {} } { return }

    menu ${m}
    foreach lblcmd ${commands} {
        if { ${lblcmd} eq {} } {
            ${m} add separator
        } else {
            foreach {lbl cmd} ${lblcmd} {break}
            ${m} add command -label ${lbl} -command ${cmd}
        }
    }
    tk_popup ${m} [expr {[winfo rootx ${widget}] + ${theX}}] [expr {[winfo rooty ${widget}] + ${theY}}]
}
namespace eval ::deken::apt::contextmenu:: {}
proc ::deken::apt::contextmenu::uninstall {pkgname} {
    return [list [format [_ "Uninstall '%s'" ] ${pkgname}] [list ::deken::apt::uninstall ${pkgname}]]
}

proc ::deken::apt::getsudo {} {
    # for whatever reasons, we cannot have 'deken' as the description
    # (it will always show ${prog} instead)
    set desc deken::apt
    if { [ catch { exec which pkexec } sudo ] } {
	if { [ catch { exec which gksudo } sudo ] } {
	    set sudo ""
	} {
            set sudo "${sudo} -D ${desc} --"
	}
    }
    if { ${sudo} == "" } {
	::deken::post "Please install 'policykit-1', if you want to install system packages via deken..." error
    }
    return ${sudo}
}

proc ::deken::apt::install {pkg {version {}}} {
    if { ${version} ne {} } {
        set pkg "${pkg}=${version}"
    }
    set prog "apt-get install -y --show-progress ${pkg}"
    set sudo [::deken::apt::getsudo]
    if { ${sudo} ne "" } {
        set cmdline "${sudo} ${prog}"
        #::deken::post "${cmdline}" error
        set io [ open "|${cmdline}" ]
        while { [ gets ${io} line ] >= 0 } {
            ::deken::post "apt: ${line}"
        }
        if { [ catch { close ${io} } ret ] } {
            ::deken::post "apt::install failed to install ${pkg}" error
            ::deken::post "\tDid you provide the correct password and/or" error
            ::deken::post "\tis the apt database locked by another process?" error
        }
    }
}

proc ::deken::apt::uninstall {pkg} {
    set prog "apt-get remove -y --show-progress ${pkg}"
    set sudo [::deken::apt::getsudo]
    if { ${sudo} ne "" } {
        set cmdline "${sudo} ${prog}"
        #::deken::post "${cmdline}" error
        set io [ open "|${cmdline}" ]
        while { [ gets ${io} line ] >= 0 } {
            ::deken::post "apt: ${line}"
        }
        if { [ catch { close ${io} } ret ] } {
            ::deken::post "apt::uninstall failed to remove ${pkg}" error
            ::deken::post "\tDid you provide the correct password and/or" error
            ::deken::post "\tis the apt database locked by another process?" error
        }
    }
}

proc ::deken::apt::register { } {
    set pyfile [file join ${::deken::apt::pluginpath} deken-xtra-apt-helper.py]
    if {[file executable ${pyfile}]} {
        ::deken::register ::deken::apt::search_pyapt
        set ::deken::apt::search_pyaptscript ${pyfile}
        return 1
    }
    if { [ catch { exec apt-cache madison       } _ ] } { } {
	if { [ catch { exec which grep-aptavail } _ ] } { } {
	    if { [ catch {
		::deken::register ::deken::apt::search_madison
	    } ] } {
		::pdwindow::debug "Not using APT-backend for unavailable deken\n"
	    } {
		return 1
	    }
	}}
    return 0
}

if { [::deken::apt::register] } {
    ::pdwindow::debug "Using APT as additional deken backend\n"
}
