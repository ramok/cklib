
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

::ck::require files   0.3
::ck::require colors  0.2
::ck::require eggdrop 0.3

namespace eval ::ck::config {
  variable version 0.3
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
  datafile register config -bot -net -backup
  load
  bind dcc - "set"  ::ck::config::cset
  bind dcc - "set?" ::ck::config::cset?

  config register -folder ".core" -id "encoding" -access "" -personal \
    -type encoding -default "" -desc "Codepage in patyline."
}
### interface for scripts

proc ::ck::config::config { args } {
  cmdargs \
    register ::ck::config::register \
    get      ::ck::config::get \
    exists   ::ck::config::exists \
    enable   ::ck::config::active \
    active   ::ck::config::active \
    disable  ::ck::config::disable \
    inactive ::ck::config::disable \
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
proc ::ck::config::active { args } {
  variable rconf
  foreach id $args {
    if { [info exists rconf($id)] } {
      array set {} $rconf($id)
      set (disable) 0
      set rconf($id) [array get {}]
      unset {}
    } {
      debug -warning "Bad id: <$id>"
    }
  }
}
proc ::ck::config::disable { args } {
  variable rconf
  foreach id $args {
    if { [info exists rconf($id)] } {
      array set {} $rconf($id)
      set (disable) 1
      set rconf($id) [array get {}]
    } {
      debug -warn "Bad id: <$id>"
    }
  }
}
# всегда возвращает необработанный дефолтный параметр параметр
proc ::ck::config::getdefault { id {handle ""} } {
  variable rconf
  if { ![exists $id] } {
    debug -err "Try access to not exists config param <%s>." $id
    return ""
  }
  array set {} $rconf($id)
  if { $(linkparam) != "" } {
    return [get "-$(linkparam)" $handle]
  }
  return $(default)
}
# ?<id> - дефолтовый ли параметр: 1 - дефолтовый/0 - custom
# -<id> - возвращает реально установленный параметр (для параметров типа time и encoding)
# +<id> - возвращает обработанный дефолтный параметр (для параметров типа time и encoding)
# %<id> - персональный ли параметр: 1 - персональный/0 - общий
proc ::ck::config::get { id {handle ""} } {
  variable rconf
  variable lconf

  switch -exact -- [string index $id 0] {
    "-" { set orig 1 }
    "?" { set orig 2 }
    "%" { set orig 3 }
    "+" { set orig 4 }
    default { set orig 0 }
  }
  if { $orig } { set id [string range $id 1 end] }

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
      if { $orig == 3 } { return 0 }
      return ""
    }
    debug -debug "Accessing to local param <%s> in namespace <%s>: %s" $id $ns $_
    set id $_
  } {
    if { ![info exists rconf($id)] } {
      debug -err "Try access to not exists config param <%s>." $id
      if { $orig == 2 } { return 1 }
      if { $orig == 3 } { return 0 }
      return ""
    }
    debug -debug "Accessing to param <%s>." $id
    array set {} $rconf($id)
  }

  if { $orig == 3 } { return $(personal) }
  if { $orig == 4 } { set (disable) 1 }

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

  if { [string index $id 0] != "." } {
    set ns [uplevel 1 {namespace current}]
    foreach_ [array names rconf] {
      array set {} $rconf($_)
      if { $(ns) eq $ns && $(lid) eq $id } break
      unset {}
    }
    if { ![array exists {}] } {
      debug -err "Can't find local config param <%s> for namespace <%s>." $id $ns
      return
    }
    debug -debug "Accessing to local param <%s> in namespace <%s>: %s" $id $ns $_
    set id $_
  } {
    if { ![info exists rconf($id)] } {
      debug -err "Try access to not exists config param <%s>." $id
      return
    }
    debug -debug "Accessing to param <%s>." $id
    array set {} $rconf($id)
  }

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

proc ::ck::config::access {h cid targhand} {
  variable rconf

  array set {} $rconf($cid)
  if { $(access) != "" } {
    if { $h == "*" } { return 0 }
    set test [chattr $h]
    if { $test == "-" || $test == "*" } { return 0 }
    foreach_ [split $(access) ""] {
      if { [string first $_ $test] == -1 } { return 0 }
    }
  }
  if { $(hook) != "" } {
    set sid $(id)
    if { $(personal) } { append $(id) "@" $targhand }
    debug -debug "Run hook proc for param <%s>..." $(id)
    if { [catch [list $(hook) access $sid [get $(id) $targhand] "" $h] errStr] } {
      debug -err "Error while exec hook proc <%s>: %s" $(hook) $errStr
      foreach_ [split $::errorInfo "\n"] { debug -err- "  $_" }
      return 0
    }
    if { [string equal -nocase "access" $errStr] } {
      return 1
    } elseif { [string equal -nocase "deny" $errStr] } {
      return 0
    }
  }
  if { $(personal) } {
    if { $h ne $targhand && [userlevel $targhand] >= [userlevel $h] } { return 0 }
  }
  return 1
}


proc ::ck::config::cset? { 1 2 3 } { cset $1 $2 $3 1 }
proc ::ck::config::cset {h idx mask {help 0}} {
  variable lconf
  variable rconf

  fixenc h mask

  set mask [split [string trim $mask] " "]
  if { [llength $mask] > 1 } {
    if { !$help } {
      if { [set setvalue [join [lrange $mask 1 end] " "]] eq "?" } {
        unset setvalue
        set help 1
      }
    }
    set mask [lindex $mask 0]
  } elseif { [llength $mask] } {
    set mask [lindex $mask 0]
  }

  if { [string first "@" $mask] != -1 } {
    set mask [split $mask @]
    set targhand [string trim [lindex $mask end]]
    set mask [join [lrange $mask 0 end-1] @]
    if { $targhand eq "" } {
      set targhand $h
    } elseif { ![validuser $targhand] } {
      putidx $idx [cformat [format [frm err.badhandle] $targhand]]
      return
    }
  } {
    set targhand $h
  }

  set match [list]
  set matchx [list]
  foreach id [array names rconf] {
    array init {} $rconf($id)

    if { [string index $(lid) 0] eq "_" } continue

    if { [llength $(disableon)] } {
      debug -debug "Param <%s> have field <disableon>, so check parent param\(%s\)..." \
	$id [lindex $(disableon) 0]
      set pval [get [lindex $(disableon) 0] $targhand]
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

    if { $targhand != $h && !$(personal) } continue

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
    array init {} $rconf([lindex $match 0])
    if { $(personal) } { set sid "$(id)@$targhand" } { set sid $(id) }
    if { [access $h [lindex $match 0] $targhand] < 1 } {
      putidx $idx [format [cformat [frm deny]] [lindex $match 0]]
    } elseif { $setvalue eq "-" } {
      if { $(hook) != "" } {
	debug -debug "Run hook proc for param <%s>..." $(id)
	if { [catch [list $(hook) setdefault $sid [get $(id) $targhand] [get "+$(id)" $targhand] $h] errStr] } {
	  debug -err "Error while exec hook proc <%s>: %s" $(hook) $errStr
	  foreach_ [split $::errorInfo "\n"] {
	    debug -err- "  $_"
	  }
	}
      }
      confsetdefault $(id) $targhand
      unset {}
    } else {
      if { [string length $setvalue] > 1 && [string index $setvalue 0] eq "\"" \
        && [string index $setvalue end] eq "\"" } {
          set setvalue [string range $setvalue 1 end-1]
      }
      array init {} $rconf([lindex $match 0])
      switch -- $(type) {
	bool {
	  set setvalue [string tolower $setvalue]
	  if { $setvalue eq "on" || $setvalue eq "true" || $setvalue == "1" || $setvalue eq "yes" } {
	    set setvalue 1
	  } elseif { $setvalue eq "off" || $setvalue eq "false" || $setvalue == "0" || $setvalue eq "no" } {
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
	  if { [catch [list $(hook) set $sid [get $(id) $targhand] $xsetvalue $h] errStr] } {
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
	  confset $(id) $setvalue $targhand
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

  set out  [list]
  set maxk 10

  foreach id $match {
    array init {} $rconf($id)

    if { $(folder) != "" && [info exists folders($(folder))] && [array size folders] > 3 } {
      if { $folders($(folder)) == -1 } continue
      if { $folders($(folder)) > 2 } {
	lappend out "1" [string trimleft $(folder) .] $folders($(folder))
	set maxk [max $maxk [expr { [string length $(folder)] + 5 }]]
	set folders($(folder)) -1
	unset {}
	continue
      }
    }

    if { $help } {
      set frm "desc"
      switch -- $(type) {
        int     { set val "integer" }
        str     { set val "string" }
        default { set val $(type) }
      }
      set xval [format [cformat [frm desc]] $(desc) $val]
    } {
      set val [get "-$id" $targhand]
      if { ($(hide) || [access $h $id $targhand] < 1) && ![get "?$id" $targhand] } {
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
    }

    if { ![info exists xval] } {
      set xval [format [cformat [frm $frm]] $val]
    }
    if { [get "%$id" $targhand] } { append id "@" $targhand }
    set maxk [max $maxk [string length $id]]
    lappend out "0" [string trimleft $id .] $xval
    unset xval {}
  }

  set maxk [min $maxk 50]
  putidx $idx [format [cformat [frm ban1]] $mask]
  foreach {isfolder k v} $out {
    if { $isfolder } {
      putidx $idx [format [cformat [frm folder]] $k $v]
    } {
      set k [format [frm maink] $maxk $k]
      set k [string map [list "@" [cformat "[frm mainat1]@[frm mainat2]"]] $k]
      putidx $idx [format [cformat [frm main]] $k $v]
    }
  }

  putidx $idx [format [cformat [frm ban2]] [llength $match]]
}

#  main   &G|&n %-20s&K : %s
::ck::msgreg -ns ::ck::config {
  ban1   &G.-&K[&nМаска: %s&K]&G---&g--&K-- -
  maink  %-*s
  main   &G|&n %s&K: %s
  mainat1 &B
  mainat2 &n
  folder &G|&n &L%s&L&P+ &K(&n%s&K)
  ban2   &G`---&K[&nВсего: %s&K]&G-----&g--&G--&g----&K-&g--&K-- - :: -
  novar  &G`-&K[&R Переменных не найдено. &K]&G--&g--&G-&g-&K-
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
  desc   &n%s &K(&B%s&K)
  deny   &rУ Вас нет прав на изменение переменной &B'&R%s&B'
  hide   &R<&rhidden&R>
  err.bool  &RОшибка установки переменной &K<&B%s&K>&R в значение &K<&B%s&K>&R, она логического типа &K(&non/off/true/false/yes/no/1/0&K)
  err.int   &RОшибка установки переменной &K<&B%s&K>&R в значение &K<&B%s&K>&R, она целочисленного типа.
  err.time  &RОшибка установки переменной &K<&B%s&K>&R в значение &K<&B%s&K>&R, она временного типа &K(&n<число>&K[&ns|m|h|d&K])
  err.float &RОшибка установки переменной &K<&B%s&K>&R в значение &K<&B%s&K>&R, она числового типа.
  err.enc   &RОшибка установки переменной &K<&B%s&K>&R в значение &K<&B%s&K>&R, неизвестная кодировка. &rИзвестны: &n%s
  err.setw  &RWarning&K: &n%s
  err.set   &RОшибка установки переменной &K<&B%s&K>: &n%s
  err.badhandle &RError! Пользователь&B %s&R не найден.
}
