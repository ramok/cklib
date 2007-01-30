
namespace eval ::ck::sessions {
  variable version 0.2
  variable author "Chpock <chpock@gmail.com>"

  variable ses_list

  namespace import -force ::ck::*
  namespace export session
}

proc ::ck::sessions::session { args } {
  set c [catch {cmdargs \
    create    ::ck::sessions::create \
    import    ::ck::sessions::import \
    set       ::ck::sessions::sset \
    insert    ::ck::sessions::insert \
    unset     ::ck::sessions::sunset \
    suspend   ::ck::sessions::suspend \
    varexists ::ck::sessions::varexists \
    destroy   ::ck::sessions::destroy \
    exists    ::ck::sessions::isexists \
    parent    ::ck::sessions::getparent \
    dump      ::ck::sessions::dump \
    lock      ::ck::sessions::lock \
    islock    ::ck::sessions::islocked \
    islocked  ::ck::sessions::islocked \
    havechild ::ck::sessions::havechild \
    unlock    ::ck::sessions::unlock \
    enter     ::ck::sessions::enter \
    hook      ::ck::sessions::hook \
    event     ::ck::sessions::event \
    return    ::ck::sessions::return_uplevel \
    export    ::ck::sessions::export} m]
  return -code $c $m
}
proc ::ck::sessions::dump { {what ""} } {
  variable ses_list
  if { $what == "all" } {
    set slist [array names ses_list]
  } elseif { $what == "" } {
    set slist [list [uplevel 1 {set sid}]]
  } else {
    set slist [list $what]
  }
  foreach_ $slist {
    debug -debug- ".--\[Dump of session %s\]------------------------" $_
    foreach_ [lsort -dictionary [info vars "::ck::sessions::S${_}::*"]] {
      if { [catch {set $_} data] } {
        debug -debug- "| %20s == %s" [namespace tail $_] {(array)}
      } {
        debug -debug- "| %20s == %s" [namespace tail $_] [set $_]
      }
    }
    debug -debug- "`-----------"
  }
}
proc ::ck::sessions::getparent {  } {
  upvar sid sid
  if { ![isexists] } {
    debug -debug "Requested getparent of destroed session, trying get parent from <parent_sid>..."
    if { [catch {uplevel 1 {set parent_sid}} sid] } {
      debug -err "Can't get parent of session. Return empty SID."
      return ""
    }
    return [uplevel 1 [list set sid $sid]]
  }
  set parent [sset _session_parent]
  if { $parent != "" } {
    uplevel 1 [list set sid [lindex $parent 0]]
  } {
    debug -debug "Requested getparent from session which not have parent, return actual SID."
    return $sid
  }
}
proc ::ck::sessions::isexists { args } {
  variable ses_list
  if { [llength $args] == 0 } {
    if { [catch {uplevel 1 {set sid}} sid] } {
      return 0
    }
  } {
    set sid [lindex $args 0]
  }
  return [info exists ses_list($sid)]
}
# -grab {mask} забирает по маске переменные, ложит к себе
# -create {var} {value} создает переменную со значением
# -grab {var} as {newname} создает переменную с именем {newname}
# -grablist {list} забирает все из листа
proc ::ck::sessions::import { args } {
  upvar sid sid
  while { [llength $args] != 0 } {
    lpop args cmd
    switch -- $cmd {
      "-grab" {
	if { [lindex $args 1] == "as" } {
	  lpop args varname
	  lpop args -
	  lpop args newname
	  if { [catch [list uplevel 1 [list set $varname]] errStr] } {
	    debug -error "Can't grab var <%s> as <%s>." $varname $newname
	    continue
	  }
	  set [list "::ck::sessions::S${sid}::$newname"] $errStr
#	  debug -debug "Grabed var <%s> as <%s>, ctx: %s" $varname $newname $errStr
	  continue
	}
	lpop args varmask
	set varnamel [uplevel 1 [list info locals $varmask]]
	if { $varnamel == "" } {
	  debug -warn "No vars found with mask <%s>." $varmask
	  continue
	}
	foreach varname $varnamel {
	  if { [catch [list uplevel 1 [list set $varname]] errStr] } { continue }
	  set [list "::ck::sessions::S${sid}::$varname"] $errStr
#	  debug -debug "Grabed var <%s>, ctx: %s" $varname $errStr
	}
      }
      "-grablist" {
	foreach varname [lpop args] {
	  if { [catch [list uplevel 1 [list set $varname]] errStr] } { continue }
	  set [list "::ck::sessions::S${sid}::$varname"] $errStr
#	  debug -debug "Grabed var <%s>, ctx: %s" $varname $errStr
	}
      }
      "-create" {
	lpop args varname
	lpop args varvalue
	set [list "::ck::sessions::S${sid}::$varname"] $errStr
#	debug -debug "Created new var <%s>, ctx: %s" $varname $varvalue
      }
    }
  }
}
proc ::ck::sessions::export { args } {
  upvar sid sid
  if { [lindex $args 0] == "-exact" } {
    foreach var [lrange $args 1 end] {
      if { ![info exists [list "::ck::sessions::S${sid}::$var"]] } {
	debug -err "Try to export non exists variable <%s>." $var
      } {
       uplevel 1 [list set $var [set [list "::ck::sessions::S${sid}::$var"]]]
     }
    }
  } elseif { [llength $args] == 0 } {
    foreach var [info vars "::ck::sessions::S${sid}::*"] {
      if { [string match "*::_session_*" $var] } continue
      uplevel 1 [list set [namespace tail $var] [set $var]]
#      debug -debug "Exporting variable %s, ctx: %s" $var [set $var]
    }
  } else {
    foreach mask $args {
      foreach var [info vars "::ck::sessions::S${sid}::$mask"] {
	if { [string match "*::_session_*" $var] } continue
	uplevel 1 [list set [namespace tail $var] [set $var]]
      }
    }
  }
}
proc ::ck::sessions::exportto { tosid } {
  upvar sid sid
  debug -debug "Export all variables from session to <%s>..." $tosid
  foreach_ [info vars "::ck::sessions::S${sid}::*"] {
    if { [string match "_session_*" [namespace tail $_]] } continue
    set [list "::ck::sessions::S${tosid}::[namespace tail $_]"] [set $_]
  }
}
proc ::ck::sessions::sset { args } {
  upvar sid sid
  if { [llength $args] == 1 } {
    return [set [list "::ck::sessions::S${sid}::[lindex $args 0]"]]
  } {
    if { [llength $args] == 2 } {
      uplevel 1 [list set [lindex $args 0] [lindex $args 1]]
    }
    return [set [list "::ck::sessions::S${sid}::[lindex $args 0]"] [lindex $args 1]]
  }
}
proc ::ck::sessions::insert { args } {
  upvar sid sid
  foreach {k v} $args {
    set [list "::ck::sessions::S${sid}::$k"] $v
  }
}
proc ::ck::sessions::sunset { args } {
  upvar sid sid
  foreach $args {
    catch { unset [list "::ck::sessions::S${sid}::$_"] }
  }
}
proc ::ck::sessions::varexists { varn } {
  upvar sid sid
  if { [catch {set [list "::ck::sessions::S${sid}::$varn"]} errStr] } {
    return 0
  } {
    return 1
  }
}

# -new interface-
proc ::ck::sessions::lock { {lockid "general"} } {
  upvar sid sid
  session export -exact _session_lock
  if { [lexists $_session_lock $lockid] } {
    debug -debug "Session already locked."
    return
  }
  debug -debug "Locking session by lockid <%s>..." $lockid
  session insert _session_lock [lappend _session_lock $lockid]
}
proc ::ck::sessions::unlock { {lockid "general"} } {
  upvar sid sid
  session export -exact _session_lock
  if { ![lexists $_session_lock $lockid] } {
    debug -debug "Session not locked with lockid <%s>." $lockid
    return
  }
  session insert _session_lock [lremove $_session_lock $lockid]
  debug -debug "Unlocking session with lockid <%s>." $lockid
}
proc ::ck::sessions::islocked { {lockid "*"} } {
  upvar sid sid
  return [llength [lsearch -glob -all [set "::ck::sessions::S${sid}::_session_lock"] $lockid]]
}
proc ::ck::sessions::hook { hook args } {
  upvar sid sid
  set prc [lindex $args 0]
  if { ![string equal -length 2 "::" $prc] } {
    set prc "[uplevel 1 [list namespace current]]::$prc"
  }
  set ::ck::sessions::S${sid}::_session_hook($hook) $prc
}
proc ::ck::sessions::event { args } {
  getargs -sid str "" -lazy flag -return flag
  if { $(sid) eq "" } {
    set sid [uplevel 1 {set sid}]
  } {
    set sid $(sid)
  }
  lpop args event
  if { ![info exists "::ck::sessions::S${sid}::_session_hook($event)"] } {
    if { $(lazy) } return
    if { [string index $event 0] eq "!" } {
      debug -err "Can't find hook for event <%s>. ignore event." $event
      if { $(return) } { return -code return }
      return
    }
    set_ [set "::ck::sessions::S${sid}::_session_hook(default)"]
  } {
    set_ [set "::ck::sessions::S${sid}::_session_hook(${event})"]
  }
  foreach {k v} [concat [list "_session_proc" $_ "Event" $event] $args] {
    set [list "::ck::sessions::S${sid}::$k"] $v
  }
  debug -debug "Run hook for event <%s>" $event
  session enter ${sid}
  if { $(return) } { return -code return }
}
proc ::ck::sessions::destroy { args } {
  variable ses_list
  getargs -sid str ""

  if { $(sid) == "" } {
    set sid [uplevel 1 {set sid}]
  } {
    set sid $(sid)
  }
  if { [islocked] } {
    debug -debug "Request for destroy locked session, ignored."
    return
  }
  session export -exact _session_childs _session_parent
  if { [llength $_session_childs] } {
    debug -debug "Request for destroy session with childs, ignored."
    return
  }
  session lock "half_destroy"
  event -lazy !onDestroy
  if { $_session_parent != "" } {
    set _session_parent [lindex $_session_parent 0]
    debug -debug "Remove myself from parent's\(%s\) child-list..." $_session_parent
    set prtch [set "::ck::sessions::S${_session_parent}::_session_childs"]
    set "::ck::sessions::S${_session_parent}::_session_childs" [lremove $prtch $sid]
  }
  namespace delete "::ck::sessions::S$sid"
  unset ses_list($sid)
  debug -debug "Session destroyed. Total: %s session\(s\)" [array size ses_list]
  if { $(sid) == "" } { uplevel 1 [list unset sid] }
}
proc ::ck::sessions::create { args } {
  variable ses_list

  getargs \
    -child flag \
    -proc str "" \
    -parent str "" \
    -parent-event str "" \
    -parent-mark str ""

  set sid [uidns]
  set ses_list($sid) [list [clock seconds] [list]]
  namespace eval "::ck::sessions::S$sid" {
    variable _session_parent [list]
    variable _session_lock   [list]
    variable _session_childs [list]
    variable _session_wait   [list]
    variable _session_hook
    variable _session_proc
  }
  set ::ck::sessions::S${sid}::_session_hook(default) $(proc)

  if { $(child) } {
    if { $(parent) == "" } { set (parent) [uplevel 1 {set sid}] }
    session insert _session_parent [list $(parent) $(parent-event) $(parent-mark)]
    lappend "::ck::sessions::S$(parent)::_session_childs" $sid
    lappend "::ck::sessions::S$(parent)::_session_wait" $sid
    debug -debug "Session, child of %s created. Total: %s session\(s\)." $(parent) [array size ses_list]
  } {
    debug -debug "Session created. Total: %s session\(s\)." [array size ses_list]
  }
  uplevel 1 [list set sid $sid]
  return $sid
}
proc ::ck::sessions::enter { sid } {
  session export -exact _session_proc
  debug -debug "Enter in session, with proc: %s" $_session_proc
  if { [catch [list $_session_proc $sid] errStr] } {
    debug -err "Error while exec session proc <%s>: %s" $_session_proc $errStr
    foreach_ [split $::errorInfo "\n"] {
      debug -err- "  $_"
    }
  }
  set waitlist "::ck::sessions::S${sid}::_session_wait"
  if { [info exists $waitlist] } {
    while { [set wait [lindex [set $waitlist] 0]] != "" } {
      debug -debug "Session enter in child %s ..." $wait
      set $waitlist [lrange [set $waitlist] 1 end]
      event -sid $wait SessionInit
      if { ![info exists $waitlist] } {
	debug -debug "Session is die, stop exec childs ..."
	return
      }
    }
    debug -debug "Session is out, trying destroy ..."
    destroy -sid $sid
  } {
    debug -debug "Session is already die, don't check for childs."
  }
}
proc ::ck::sessions::return_uplevel { args } {
  getargs -nodestroy flag
  set sid [uplevel 1 {set sid}]
  session export -exact _session_parent
  set psid [lindex $_session_parent 0]
  if { $(nodestroy) } {
    debug -debug "Child wakeup parent session\(%s\)..." $psid
  } {
    debug -debug "Child return. Resume parent session\(%s\)..." $psid
  }
  exportto $psid
  if { !$(nodestroy) } {
    destroy -sid $sid
  }
  eval [concat [list event -sid $psid [lindex $_session_parent 1] Mark [lindex $_session_parent 2]] $args]
  if { $(nodestroy) } {
    debug -debug "Return in child."
  } {
    return -code return
  }
}

namespace import -force ::ck::sessions::*
