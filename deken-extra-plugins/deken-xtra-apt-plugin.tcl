# META NAME PdExternalsSearch
# META DESCRIPTION Search for externals zipfiles on puredata.info
# META AUTHOR <Chris McCormick> chris@mccormick.cx
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
}

proc ::deken::apt::search {name} {
    set result []
    if { [info exists ::deken::apt::distribution] } { } {
	if { [ catch { exec lsb_release -si } ::deken::apt::distribution ] } {
	    set ::deken::apt::distribution {}
	}
    }
    if { "$::deken::apt::distribution" == "" } {
	return
    }

    set name [ string tolower $name ]
    array unset pkgs
    array set pkgs {}
    set filter "-F Provides pd-externals --or -F Depends -w pd --or -F Depends -w puredata --or -F Depends -w puredata-core"
    if { "$name" == "" } { } {
	set filter " -F Package $name --and ( $filter )"
    }

    set io [ open "|grep-aptavail -n -s Package $filter | sort -u | xargs apt-cache madison" r ]
    while { [ gets $io line ] >= 0 } {
        #puts $line
        set llin [ split "$line" "|" ]
        set pkgname [ string trim [ lindex $llin 0 ] ]

        #if { $pkgname ne $searchname } { continue }
        set ver_  [ string trim [ lindex $llin 1 ] ]
        set info_ [ string trim [ lindex $llin 2 ] ]
        if { "Packages" eq [ lindex $info_ end ] } {
            set suite [ lindex $info_ 1 ]
            set arch  [ lindex $info_ 2 ]
            if { ! [ info exists pkgs($pkgname/$ver_) ] } {
                set pkgs($pkgname/$ver_) [ list $pkgname $ver_ $suite $arch ]
            }
        }
    }
    foreach {name inf} [ array get pkgs ] {
        set pkgname [ lindex $inf 0 ]
        set v       [ lindex $inf 1 ]
        set suite   [ lindex $inf 2 ]
        set arch    [ lindex $inf 3 ]
        set cmd "::deken::apt::install ${pkgname}=$v"
        set match 1
        set comment "Provided by ${::deken::apt::distribution} (${suite})"
        set status "${pkgname}_${v}_${arch}.deb"
        lappend result [list $name $cmd $match $comment $status]
    }
    return [lsort -dictionary -decreasing -index 1 $result ]
}

proc ::deken::apt::install {pkg} {
    set desc deken::apt
    set prog "apt-get install -y --show-progress ${pkg}"
    if { [ catch { exec which pkexec } sudo ] } {
	if { [ catch { exec which gksudo } sudo ] } {
	    set sudo ""
	} { set sudo "$sudo -D $desc --"
	}
    }
    if { $sudo == "" } {
	::deken::post "Please install 'policykit-1', if you want to install system packages via deken..." error
    } {
        # for whatever reasons, we cannot have 'deken' as the description
        # (it will always show $prog instead)
        set cmdline "$sudo $prog"
        #::deken::post "$cmdline" error
        set io [ open "|${cmdline}" ]
        while { [ gets $io line ] >= 0 } {
            ::deken::post "apt: $line"
        }
        if { [ catch { close $io } ret ] } {
            ::deken::post "apt::install failed to install $pkg" error
            ::deken::post "\tDid you provide the correct password and/or" error
            ::deken::post "\tis the apt database locked by another process?" error
        }
    }
}

proc ::deken::apt::register { } {
    if { [ catch { exec apt-cache madison       } _ ] } { } {
	if { [ catch { exec which grep-aptavail } _ ] } { } {
	    if { [ catch {
		## oye a hack to get the apt-backend at the beginning of the backends
		if { [ info exists ::deken::backends ] } {
		    set ::deken::backends [linsert $::deken::backends 0 ::deken::apt::search ]
		} {
		    ::deken::register ::deken::apt::search
		}
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
