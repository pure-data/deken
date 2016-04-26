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

if { [ catch { exec apt-cache -v } _ ] } { } {
if { [ catch { exec lsb_release -si } ::deken::apt::distribution ] } { unset ::deken::apt::distribution }
}
proc ::deken::apt::search {name} {
    set result []
    if { [ catch { exec apt-cache madison } _ ] } {
        ::deken::post "Unable to run 'apt-cache madison'" error
    } {
    set name [ string tolower $name ]
    array unset pkgs
    array set pkgs {}

    set io [ open "|grep-aptavail -n -s Package -F Package $name --and ( -F Depends -w pd --or -F Depends -w puredata --or -F Depends -w puredata-core ) | sort -u | xargs apt-cache madison" r ]
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
            if { ! [ info exists pkgs($ver_) ] } {
                set pkgs($ver_) [ list $pkgname $suite $arch ]
            }
        }
    }
    foreach {v inf} [ array get pkgs ] {
        set pkgname [ lindex $inf 0 ]
        set suite   [ lindex $inf 1 ]
        set arch    [ lindex $inf 2 ]
        set name $pkgname/$v
        set cmd "::deken::apt::install ${pkgname}=$v"
        set match 1
        set comment "Provided by ${::deken::apt::distribution} (${suite})"
        set status "${pkgname}_${v}_${arch}.deb"

        lappend result [list $name $cmd $match $comment $status]
    }
    }
    return [lsort -dictionary -decreasing -index 1 $result ]
}

proc ::deken::apt::install {pkg} {
    if { [ catch { exec which gksudo } gsudo ] } {
        ::deken::post "Please install 'gksudo', if you want to install system packages via deken..." error
    } {
        ::deken::clearpost
        set prog "apt-get install -y --show-progress ${pkg}"
        # for whatever reasons, we cannot have 'deken' as the description
        # (it will always show $prog instead)
        set desc deken::apt
        set cmdline "$gsudo -D $desc -- $prog"
        #puts $cmdline
        set io [ open "|${cmdline}" ]
        while { [ gets $io line ] >= 0 } {
            ::deken::post "apt: $line"
        }
        if { [ catch { close $io } ret ] } {
            ::deken::post "apt::install failed to install $pkg" error
            ::deken::post "\tDid you provide the correct password and/or" error
            ::deken::post "\tis the apt database locked by another process?" error
            #puts stderr "::deken::apt::install ${options}"
        }
    }
}

if { [ catch {::deken::register ::deken::apt::search} ] } {
    ::pdwindow::debug "Not using APT-backend for unavailable deken\n"
} {
    ::pdwindow::debug "Using APT as additional deken backend\n"
}
