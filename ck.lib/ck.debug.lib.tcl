
encoding system utf-8
::ck::require files   0.2
::ck::require colors  0.2
::ck::require eggdrop 0.3

namespace eval ::ck::debug {
  variable version 0.1
  variable author "Chpock <chpock@gmail.com>"
  variable d
  namespace import -force ::ck::*
  namespace import -force ::ck::colors::cformat
  namespace import -force ::ck::files::datafile
}

proc ::ck::debug::init {  } {
  variable d
  datafile register cklib_debug -bot -net
  if { ![array exists d] } { datafile getarray cklib_debug d }
  bind dcc - "debug" ::ck::debug::dcc
  msgreg {
    noaccess &RError: You don't have access to debug variables!
    badvalue &RError: Bad value for debug level! Value should be from &B-100&K..&B100&R.
    ban1   &P.-&K[&nMask: &r%s&K]&P---&p--&K-- -
    ban2   &P`---&K[&nTotal: %s&K]&P-----&p--&P--&p----&K-&p--&K-- - :: -
    novar  &P`-&K[&R No variables found. &K]&P--&p--&P-&p-&K-
    maink  %-*s
    main   &P|&n %s &K: %s
    maindv1 &B
    maindv2 &n
    val-1  &G%s
    val0   &B%s
    val+1  &R%s
  }
}

proc ::ck::debug::dcc { h idx mask } {
  variable d
  if { [userlevel $h] < 98 } { putidx $idx [cformat [frm noaccess]]; return }

  set mask [split [string trim $mask] " "]
  if { [string equal -nocase -length 4 "sess" [lindex $mask 0]] } {
    dumpsess $idx [lindex $mask 1]
    return
  }
  if { [llength $mask] > 1 } {
    if { ![regexp {^-?\d+$} [set setvalue [join [lrange $mask 1 end] " "]]] } {
      putidx $idx [cformat [frm badvalue]]; return
      unset setvalue
    }
    set mask [lindex $mask 0]
  } elseif { [llength $mask] } {
    set mask [lindex $mask 0]
  }
  if { ![string equal -length 2 $mask "::"] } { set mask "::$mask" }
  if { [string index $mask end] ne "*" } { append mask "*" }
  set out [list]
  set max 10
  set nslist [list]
  foreach_ [lsort -dictionary [collect ::]] {
    if { [string match "::tcl*" $_] } continue
    if { ![info exists "${_}::version"] } continue
    if { ![string match $mask $_] } continue
    if { [string equal $_ [string trimright $mask "*"]] } {
      set nslist [list $_]
      set mask [string trimright $mask "*"]
      break
    }
    lappend nslist $_
  }
  foreach_ $nslist {
    if { [info exists setvalue] } {
      if { $setvalue == 0 } {
	if { [info exists d($_)] } { unset d($_) }
      } {
        set d($_) $setvalue
      }
    }
    if { [info exists d($_)] } {
      lappend out $d($_)
    } {
      lappend out 0
    }
    lappend out [set_ [string trimleft $_ :]]
    set max [max $max [string length $_]]
  }
  putidx $idx [cformat [format [frm ban1] [string trimleft $mask :]]]
  if { ![llength $out] } {
    putidx $idx [cformat [frm novar]]
    return
  }
  set max [min $max 50]
  foreach {v k} $out {
    if { $v < 0 } {
      set v [format [frm val-1] $v]
    } elseif { $v == 0 } {
      set v [format [frm val0] $v]
    } else {
      set v [format [frm val+1] $v]
    }
    set k [format [frm maink] $max $k]
    set k [string map [list "::" [cformat "[frm maindv1]::[frm maindv2]"]] $k]
    putidx $idx [cformat [format [frm main] $k $v]]
  }
  putidx $idx [cformat [format [frm ban2] [expr { [llength $out] / 2 }]]]
  if { [info exists setvalue] } {
    datafile putarray cklib_debug d
  }
}
proc ::ck::debug::dumpsess { idx what } {
  if { ![array exists ::ck::sessions::ses_list] } {
    putidx $idx "No session module loaded."
    return
  }
  if { [string equal -nocase $what "all"] || $what eq ""} {
    set slist [array names ::ck::sessions::ses_list]
    if { ![llength $slist] } {
      putidx $idx "No sessions."
      return
    }
  } else {
    if { ![session exists $what] } {
      putidx $idx "Session $what not exists!"
      return
    }
    set slist [list $what]
  }
  foreach_ $slist {
    putidx $idx ".--\[Dump of session $_\]------------------------"
    foreach_ [lsort -dictionary [info vars "::ck::sessions::S${_}::*"]] {
      if { [catch {set $_} data] } {
        putidx $idx [format "| %20s == %s" [namespace tail $_] {(array)}]
      } {
        putidx $idx [format "| %20s == %s" [namespace tail $_] [set $_]]
      }
    }
    putidx $idx "`-----------"
  }
}
proc ::ck::debug::collect p {
  set ret [list]
  foreach _ [namespace children $p] { set ret [concat $ret [list $_] [collect $_]] }
  return $ret
}
