
# [lfilter ?-nocase? ?-masklist? ?-single? list mask1 ?mask2?...]
#   return filtered <list> with elements which match <mask1>, <mask2>....
#   -masklist : define that mask1 (NOT mask2 and more) is list of masks
#   -single   : define that mask1 is not list
#   -nocase   : case insensitive matching

namespace eval ::ck::lists {
  variable version 0.2
}
proc ::lexists { list element } {
  return [expr {[lsearch -exact $list $element] != -1}]
}
proc ::lnext { listname {tovar ""} } {
  upvar $listname list
  if { $list == "" } { return "" }
  if { $tovar != "" } { upvar $tovar res }
  set tmp [lindex $list 0]
  set list [lrange $list 1 end]
  return [set res $tmp]
}
proc ::lpop { listname {tovar ""} } {
  upvar $listname list
  if { $tovar != "" } { upvar $tovar xtovar }
  if { [info exists list] } { return [lnext list xtovar] }
  ::error "lpop: Unknown variable \"$listname\""
}
proc ::lrandom { list {def ""} } {
  if { $list == "" } { return $def }
  return [lindex $list [rand [llength $list]]]
}
proc ::lpush { listname element } {
  upvar $listname list
  set list [linsert $list 0 $element]
}
proc ::luniq { list } {
  set ret [list]
  foreach item $list {
    if { [lsearch -exact $ret $item] == -1 } { lappend ret $item  }
  }
  return $ret
}
proc ::lfilter { args } {
  ::ck::getargs \
    -nocase flag \
    -exact flag \
    -keep flag \
    -value str ""
  lpop args alist
  if { ![info exists alist] } {
    ::ck::debug -err "lfilter: List is not specified."
    return
  }
  if { [llength $args] } {
    # нам передали список масок
    set masklist [lindex $args 0]
  } {
    set masklist [list $(value)]
  }
  set ret [list]
  foreach el $alist {
    set match 0
    foreach mask $masklist {
      if { $(exact) } {
	if { $(nocase) } {
	  set match [string equal -nocase $el $mask]
	} {
	  set match [string equal $el $mask]
	}
      } {
	if { $(nocase) } {
	  set match [string match -nocase $mask $el]
	} {
	  set match [string match $mask $el]
	}
      }
      if { $match } break
    }
    if { ($match && $(keep)) || (!$match && !$(keep)) } { lappend ret $el }
  }
  return $ret
}
proc ::lvalid { list } {
  return [expr { ![catch [list llength $list]] }]
}

proc ::lremove { list args } {
  foreach x $args {
    if { [set pos [lsearch -exact $list $x]] == -1 } continue
    set list [lreplace $list $pos $pos]
  }
  return $list
}
proc ::lassign { list args } {
  foreach_ $args {
    uplevel 1 [list set $_ [lindex $list 0]]
    set list [lrange $list 1 end]
  }
  return $list
}

