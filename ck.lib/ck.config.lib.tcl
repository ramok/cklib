
encoding system utf-8

## register
#    -hook <procedure>
#    -flag <string>
#       <string> consist global flags which necessary user for set this setings
#       special flag "!" - setting is hidden
#    -desc <string>
#       <string> is description for setting.
#    -active/-inactive
#       set state of param (acrive or inactive)
# hook:
#  <hook> set <varname> <oldvalue> <newvalue> <handle>
#  return:
#    "", 0 : no change
#    [LIST <1> <message> ?<newvalue>?] : show warn <message>, if <newvalue> exists - use it as value
#    [LIST <2> <message> ?<newvalue>?] : show error <message>, if <newvalue> exists - use it as value, if not - no change setting

::ck::require files   0.2
::ck::require colors  0.2
::ck::require eggdrop 0.2

namespace eval ::ck::config {
  variable version 0.2
  variable author "Chpock <chpock@gmail.com>"

## Loaded config
  variable lconf
## Registred config
  variable rconf

  namespace import -force ::ck::*
  namespace import -force ::ck::colors::cformat
  namespace import -force ::ck::files::datafile
  namespace export config
}

proc ::ck::config::init {} {
  array init ::ck::config::rconf
  datafile register config -bot -net
  load
  bind dcc - "set" ::ck::config::cset

  config register -folder ".self" -id "cp.patyline" -access "" -personal \
    -type encoding -default "" -desc "Codepage in patyline."
}
### interface for scripts

proc ::ck::config::config { args } {
  cmdargs \
    register ::ck::config::register \
    get      ::ck::config::get \
    exists   ::ck::config::exists \
    active   ::ck::config::active \
    inactive ::ck::config::inactive \
    set      ::ck::config::confset
}
proc ::ck::config::register { args } {
  variable rconf

  set ns [uplevel 1 {namespace current}]

  getargs \
    -hook      str "" \
    -linkparam str "" \
    -disableon list [list] \
    -folder  str "." \
    -type    str "str" \
    -disable flag \
    -access  str "n" \
    -desc    str "No description." \
    -id      str [namespace tail $ns] \
    -personal flag \
    -default str "" \
    -hide    flag \
    -ns      str ""

  if { $(ns) eq "" } {
    set (ns) $ns
  }

  if { $(hook) ne "" && [string range $(hook) 0 1] ne "::" } {
    set (hook) "$(ns)::$(hook)"
  }

  if { [llength $args] } {
    debug -warn "Unknown params to register function: %s" $args
  }

  if { [string index $(folder) 0] != "." } {
    set (folder) ".$(folder)"
  }

  if { $(linkparam) != "" && [string index $(linkparam) 0] != "." } {
    set (linkparam) "$(folder).$(linkparam)"
  }

  if { [llength $(disableon)] != 0 } {
    if { [string index [lindex $(disableon) 0] 0] != "." } {
      set (disableon) [lreplace $(disableon) 0 0 "$(folder).[lindex $(disableon) 0]"]
    }
  }

  if { $(id) == "" } {
    debug -err "Trying to register empty ID: %s" [array get {}]
    return
  }

  set (lid) $(id)

  if { [string index $(id) 0] != "." } {
    set (id) "$(folder).$(id)"
  }

  debug -debug {Registered new param <%s> (local <%s>) in namespace <%s>.} $(id) $(lid) $(ns)
  set rconf($(id)) [array get {}]
}
proc ::ck::config::load { } {
  variable lconf
  datafile getarray config lconf
}
proc ::ck::config::save { } {
  variable lconf
  datafile putarray config lconf
}
proc ::ck::config::exists { id } {
  variable rconf
  return [info exists rconf($id)]
}
proc ::ck::config::active { id } {
  variable rconf
  if { [info exists rconf($id)] } {
    array set {} $rconf($id)
    set (disable) 0
    set rconf($id) [array get {}]
  } {
    debug -warning "Bad id: <$id>"
  }
}
proc ::ck::config::disable { id } {
  variable rconf
  if { [info exists rconf($id)] } {
    array set {} $rconf($id)
    set (disable) 0
    set rconf($id) [array get {}]
  }
  debug -warn "Bad id: <$id>"
}
proc ::ck::config::getdefault { id {handle ""} } {
  variable rconf
  if { ![exists $id] } {
    debug -err "Try access to not exists config param <%s>." $id
    return ""
  }
  array set {} $rconf($id)
  if { $(linkparam) != "" } {
    return [get $(linkparam)]
  }
  return $(default)
}
proc ::ck::config::get { id {handle ""} } {
  variable rconf
  variable lconf

  if { [string index $id 0] eq "-" } {
    set id [string range $id 1 end]
    set orig 1
  } elseif { [string index $id 0] eq "?" } {
    set id [string range $id 1 end]
    set orig 2
  } else {
    set orig 0
  }

  if { [string index $id 0] != "." } {
    set ns [uplevel 1 {namespace current}]
    foreach_ [array names rconf] {
      array set {} $rconf($_)
      if { $(ns) eq $ns && $(lid) eq $id } break
      unset {}
    }
    if { ![array exists {}] } {
      debug -err "Can't find local config param <%s> for namespace <%s>." $id $ns
      if { $orig == 2 } { return 1 }
      return ""
    }
    debug -debug "Accessing to local param <%s> in namespace <%s>: %s" $id $ns $_
    set id $_
  } {
    if { ![info exists rconf($id)] } {
      debug -err "Try access to not exists config param <%s>." $id
      if { $orig == 2 } { return 1 }
      return ""
    }
    debug -debug "Accessing to param <%s>." $id
    array set {} $rconf($id)
  }

  if { !$(disable) && [llength $(disableon)] } {
    debug -debug "Param <%s> have field <disableon>, so check parent param\(%s\)..." \
      $id [lindex $(disableon) 0]
    set pval [get [lindex $(disableon) 0] $handle]
    debug -debug "Parent Param\(%s\) == %s" [lindex $(disableon) 0] $pval
    if { [llength $(disableon)] == 2 } {
      if { $pval == [lindex $(disableon) 1] } {
	debug -debug "Parent param pass condition, do return default."
	set (disable) 1
      }
    } {
      if { $pval != [lindex $(disableon) 2] } {
	debug -debug "Parent param not pass condition, do return default."
	set (disable) 1
      }
    }
  }
  if { $(disable) } {
    debug -debug "Param <%s> have <disabled> state, return default value..." $id
    if { $orig == 2 } { return 1 }
    set value [getdefault $id $handle]
  } elseif { $(personal) } {
    debug -debug "Get personal param <%s> for handle <%s>..." $id $handle
    set value [getuser $handle XTRA "_ck$id"]
    if { $value == "" } {
      debug -debug "Param have 'default' state."
      if { $orig == 2 } { return 1 }
      set value [getdefault $id $handle]
    } {
      if { $orig == 2 } { return 0 }
      set value [string range $value 1 end]
    }
  } else {
    if { [info exists lconf($id)] } {
      debug -debug "Get value for <%s> from local values..." $id
      set value $lconf($id)
      if { [lindex $value 0] == "0" } {
	if { $orig == 2 } { return 1 }
	debug -debug "Value for param <%s> in default state..." $id
	set value [getdefault $id]
      } {
	if { $orig == 2 } { return 0 }
	set value [lindex $value 1]
      }
    } else {
      debug -debug "Get value for <%s> from defaults..." $id
      if { $orig == 2 } { return 1 }
      set value [getdefault $id $handle]
    }
  }

  if { $orig == 2 } {
    debug -err "Internal error while get <isdefault> state for param <%s>." $id
    return 1
  } elseif { $orig == 1 } {
    debug -debug "Query ends. Param <%s> have original value <%s>." $id $value
  } else {
    switch -- $(type) {
      "time" {
	set value [expandtime $value]
      }
      "encoding" {
	if { $value eq "" } {
	  set value $::ck::ircencoding
	} elseif { ![lexists [encoding names] $value] } {
	  debug -notice "Unsupported encoding <%s> for param <%s>." $value [string trimleft $(id) .]
	  set value $::ck::ircencoding
	}
      }
    }
    debug -debug "Query ends. Param <%s> have value <%s>." $id $value
  }
  return $value
}
proc ::ck::config::confsetdefault { id {handle ""} } {
  variable lconf
  variable rconf

  if { ![exists $id] } {
    debug -err "Trying set to default unknown variable \(%s\)." $id
    return
  }
  array set {} $rconf($id)

  debug -debug "Set new param <%s> to default" $id
  if { $(personal) } {
    setuser $handle XTRA "_ck$id" ""
  } {
    if { [info exists lconf($id)] } {
      unset lconf($id)
    }
    save
  }
}
proc ::ck::config::confset { id value {handle ""} } {
  variable lconf
  variable rconf

  if { ![exists $id] } {
    debug -err "Trying set unknown variable \(%s\) to \"%s\"." $id $value
    return
  }
  array set {} $rconf($id)

  debug -debug "Set new param <%s> to <%s>" $id $value
  if { $(personal) } {
    setuser $handle XTRA "_ck$id" ".$value"
  } {
    set lconf($id) [list 1 $value]
    save
  }

  return $value

}

### interface for user

proc ::ck::config::access {h cid} {
  variable rconf

  array set {} $rconf($cid)
  if { $(access) == "" } { return 1 }
  if { $h == "*" } { return 0 }
  set test [chattr $h]
  if { $test == "-" || $test == "*" } { return 0 }
  foreach_ [split $(access) ""] {
    if { [string first $_ $test] == -1 } { return 0 }
  }
  return 1
}

proc ::ck::config::cset {h idx mask} {
  variable lconf
  variable rconf

  fixenc h mask

  set mask [split [string trim $mask] " "]
  if { [llength $mask] > 1 } {
    set setvalue [join [lrange $mask 1 end] " "]
    set mask [lindex $mask 0]
  } elseif { [llength $mask] } {
    set mask [lindex $mask 0]
  }

  set match [list]
  set matchx [list]
  foreach id [array names rconf] {
    array init {} $rconf($id)

    if { [llength $(disableon)] } {
      debug -debug "Param <%s> have field <disableon>, so check parent param\(%s\)..." \
	$id [lindex $(disableon) 0]
      set pval [get [lindex $(disableon) 0] $h]
      debug -debug "Parent Param\(%s\) == %s" [lindex $(disableon) 0] $pval
      if { [llength $(disableon)] == 2 } {
	if { $pval == [lindex $(disableon) 1] } {
	  debug -debug "Parent param pass condition, do return default."
	  set (disable) 1
	}
      } {
	if { $pval != [lindex $(disableon) 2] } {
	  debug -debug "Parent param not pass condition, do return default."
	  set (disable) 1
	}
      }
    }
    if { $(disable) } continue

    if { [string match -nocase ".$mask" $id] } {
      lappend matchx $id
    } elseif { [string match -nocase ".${mask}*" $id] || \
      [string match -nocase ".${mask}*" [string range $id [string length $(folder)] end]] } {
      lappend match $id
    }
  }
  if { [llength $matchx] } {
    set match $matchx
  } {
    append mask "*"
  }
  if { ![llength $match] } {
    putidx $idx [format [cformat [frm ban1]] $mask]
    putidx $idx [cformat [frm novar]]
    return ""
  }

  if { [llength $match] == 1 && [info exists setvalue] } {
    if { [access $h [lindex $match 0]] < 1 } {
      putidx $idx [format [cformat [frm deny]] [lindex $match 0]]
    } elseif { $setvalue eq "-" } {
      array init {} $rconf([lindex $match 0])
      if { $(hook) != "" } {
	debug -debug "Run hook proc for param <%s>..." $(id)
	if { [catch [list $(hook) setdefault $(id) [get "-$(id)" $h] "" $h] errStr] } {
	  debug -err "Error while exec hook proc <%s>: %s" $(hook) $errStr
	  foreach_ [split $::errorInfo "\n"] {
	    debug -err- "  $_"
	  }
	}
      }
      confsetdefault $(id) $h
      unset {}
    } else {
      array init {} $rconf([lindex $match 0])
      switch -- $(type) {
	bool {
	  set setvalue [string tolower $setvalue]
	  if { $setvalue == "on" || $setvalue == "1" || $setvalue == "yes" } {
	    set setvalue 1
	  } elseif { $setvalue == "off" || $setvalue == "0" || $setvalue == "no"} {
	    set setvalue 0
	  } else {
	    set err "err.bool"
	  }
	}
	int {
	  if { ![string isnum -int -- $setvalue] } {
	    set err "err.int"
	  }
	}
	time {
	  if { [expandtime $setvalue] == "" } {
	    set err "err.time"
	  }
	}
	float {
	  if { ![string isnum -float -- $setvalue] } {
	    set err "err.float"
	  }
	}
	list {
	  set setvalue [split $setvalue " "]
	}
	encoding {
	  if { ![lexists [encoding names] [string tolower $setvalue]] } {
	    putidx $idx [format [cformat [frm err.enc]] [string trimleft $(id) .] $setvalue [join [encoding names] {, }]]
	    set err ""
	  } {
	    set setvalue [string tolower $setvalue]
	  }
	}
      }
      if { ![info exists err] } {
	if { $(hook) != "" } {
	  debug -debug "Run hook proc for param <%s>..." $(id)
	  if { $(type) eq "time" } {
	    set xsetvalue [expandtime $setvalue]
	  } {
	    set xsetvalue $setvalue
	  }
	  if { [catch [list $(hook) set $(id) [get "-$(id)" $h] $xsetvalue $h] errStr] } {
	    debug -err "Error while exec hook proc <%s>: %s" $(hook) $errStr
	    foreach_ [split $::errorInfo "\n"] {
	      debug -err- "  $_"
	    }
	    putidx $idx [format [cformat [frm err.set]] [string trimleft $(id) .] "Internal error."]
	    unset setvalue
	  } {
	    debug -debug "Hook proc return: %s" $errStr
	    if { $errStr ne "" && $errStr != "0" } {
	      switch -- [lindex $errStr 0] {
		1 {
		  if { [lindex $errStr 1] != "" } {
		    putidx $idx [format [cformat [frm err.setw]] [string trimleft $(id) .] [lindex $errStr 1]]
		  }
		  if { [llength $errStr] > 2 } { set setvalue [lindex $errStr 2] }
		}
		2 {
		  putidx $idx [format [cformat [frm err.set]] [string trimleft $(id) .] [lindex $errStr 1]]
		  if { [llength $errStr] > 2 } { set setvalue [lindex $errStr 2] } { unset setvalue }
		}
	      }
	    }
	  }
	}
	if { [info exists setvalue] } {
	  confset $(id) $setvalue $h
	}
      } elseif { $err ne "" } {
	putidx $idx [format [cformat [frm $err]] [string trimleft $(id) .] $setvalue]
      }
      unset {}
    }
  }

  set match [lsort -dictionary -increasing $match]
  array set folders {}

  foreach id $match {
    array init {} $rconf($id)
    if { $(folder) == "." } continue
    if { [string equal -length [string length $(folder)] $(folder) $mask] } continue
    if { [info exists folders($(folder))] } {
      incr folders($(folder))
    } {
      set folders($(folder)) 1
    }
  }

  putidx $idx [format [cformat [frm ban1]] $mask]

  foreach id $match {
    array init {} $rconf($id)

    if { $(folder) != "" && [info exists folders($(folder))] && [array size folders] > 3 } {
      if { $folders($(folder)) == -1 } continue
      if { $folders($(folder)) > 2 } {
	putidx $idx [format [cformat [frm folder]] [string trimleft $(folder) .] $folders($(folder))]
	set folders($(folder)) -1
	continue
      }
    }

    set val [get "-$id" $h]
    if { ($(hide) || [access $h $id] < 1) && ![get "?$id" $h] } {
      set frm "hide"
    } {
      switch -- $(type) {
	bool    { if { $val } { set frm "bool1" } { set frm "bool0" } }
	int     { set frm "int"   }
	float   { set frm "float" }
	time    {
	  regexp -nocase -- {^(\d+)(s|m|h|d)?$} $val - a1 a2
	  set xval [format [cformat [frm time]] $a1 $a2]
	}
	list    {
	  if { [llength $val] == 0 } {
	    set frm "list0"
	  } {
	    set xval [format [cformat [frm list]] [join $val [cformat [frm list.j]]]]
	  }
	}
	default { if { $val == "" } { set frm "str0" } { set frm "str1" } }
      }
    }

    if { ![info exists xval] } {
      set xval [format [cformat [frm $frm]] $val]
    }
    putidx $idx [format [cformat [frm main]] [string trimleft $id .] $xval]
    unset xval
  }

  putidx $idx [format [cformat [frm ban2]] [llength $match]]
}

::ck::msgreg -ns ::ck::config {
  ban1   &G.-&K[&nMask: %s&K]&G---&g--&K-- -
  main   &G|&n %-20s&K : %s
  folder &G|&n &L%s&L&P+ &K(&n%s&K)
  ban2   &G`---&K[&nTotal: %s&K]&G-----&g--&G--&g----&K-&g--&K-- - :: -
  novar  &G`-&K[&R No variables found. &K]&G--&g--&G-&g-&K-
  bool1  &Con
  bool0  &coff
  int    &G%s
  float  &p%s
  time   &R%s&r%s
  list   &K|&R%s&K|
  list.j &K|&R
  list0  &K|<empty list>|
  str0   &K<null>
  str1   &n%s
  deny   &rYou don't have access for change variable &B'&R%s&B'
  hide   &R<&rhidden&R>
  err.bool  &RCan't set variable &K<&B%s&K>&R to &K<&B%s&K>&R, it is boolean.
  err.int   &RCan't set variable &K<&B%s&K>&R to &K<&B%s&K>&R, it is integer.
  err.time  &RCan't set variable &K<&B%s&K>&R to &K<&B%s&K>&R, it is time interval \(<num>\[s|m|h|d\])."
  err.float &RCan't set variable &K<&B%s&K>&R to &K<&B%s&K>&R, it is float.
  err.enc   &RCan't set variable &K<&B%s&K>&R to &K<&B%s&K>&R, unknown encoding. &rSupport: &n%s
  err.setw  &RWarning&K: &n%s
  err.set   &RError while set &K<&B%s&K>: &n%s
}
