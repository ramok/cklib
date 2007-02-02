
# [wsplit <string> <substring>]
#   - return list by splitting <string> with <substring>

namespace eval ::ck::core {
  variable version 0.3
  namespace export getargs cmdargs frm frmexists msgreg uidns min max
  namespace import -force ::ck::debug
}

proc ::ck::core::init {  } {
  if { [catch {rename ::array ::_ck_array} errStr] } { rename ::array "" }
  rename ::_array ::array
#  if { [catch {rename ::foreach ::_ck_foreach} errStr] } { rename ::foreach "" }
#  rename ::_foreach ::foreach
}
### Ripped from wiki.tcl.tk
proc ::wsplit { str sstr } {
  return [split [string map [list $sstr \0] $str] \0]
}
proc ::rsplit { args } {
  ::ck::core::getargs -nocase flag
  set cmd "regsub"
  if { $(nocase) } { lappend cmd {-nocase} }
  if { [set c [catch [lappend cmd {-all} {--} [lindex $args 1] [lindex $args 0] \0 str] errStr]] } {
    return -code $c $errStr
  }
  return [split $str \0]
}
proc ::ip2num { ip } {
  set ip [split $ip .]
  return [expr { ([lindex $ip 0] << 24) + ([lindex $ip 1] << 16) + ([lindex $ip 2] << 8) + [lindex $ip 3] } ]
}
proc ::num2ip { ip } {
  set a1 [expr { $ip >> 24 } ]
  set ip [expr { $ip - ($a1 << 24) } ]
  if { $a1 < 0 } { set a1 [expr { 256 + $a1 } ] }
  set a2 [expr { $ip >> 16 } ]
  set ip [expr { $ip - ($a2 << 16) } ]
  set a3 [expr { $ip >> 8 } ]
  set ip [expr { $ip - ($a3 << 8) } ]
  return [join [list $a1 $a2 $a3 $ip] "."]
}
proc ::expandtime { str } {
  if { ![regexp -nocase -- {^(\d+)(s|m|h|d)?$} $str all sec pfix] } { return "" }
  switch -- $pfix {
    m { set sec [expr { $sec * 60 } ] }
    h { set sec [expr { $sec * 60 * 60 } ] }
    d { set sec [expr { $sec * 60 * 60 * 24 } ] }
  }
  return $sec
}
proc ::ck::core::checkforflag { str } {
#  switch -exact -nocase -- $str { } - for tcl8.5
  switch -exact -- $str {
    yes - 1 - true { return 1 }
    no - 0 - false { return 0 }
    default { return -1 }
  }
}
proc ::ck::core::checkforchoice { arg chlist } {
  foreach {k v} $chlist {
    if { [set pos [lsearch -exact $v $arg]] != -1 } {
      return [list $k $pos]
    }
  }
  return ""
}
# getargs \
#  {argname} {type} {default}
#     type: flag
#           int
#           str
#           float
#           bool
#           choice - в default список флагов которые могут быть указаны, по дефолту нулевой
#     отличия flag от bool - флаг не может быть с аргументом, всегда 0 по дефолту и 1 если указан
proc ::ck::core::getargs { args } {
#  uplevel 1 [list catch [list unset {}] -]
#  upvar "" vars
  upvar "args" parse

#  catch { unset vars }
#  set vars(xxx) "yyy"
#  putlog "a1: [array get vars]"

  array set myargs   [list]
  array set mychoice [list]
  for { set i 0 } { $i < [llength $args] } { incr i } {
    set argname [lindex $args $i]
    set argtype [lindex $args [incr i]]
    switch -glob -- $argtype {
      flag   { set argdefault 0 }
      str*   { set argtype "str"    }
      int*   { set argtype "int"    }
      float  { set argtype "float"  }
      choice { set argtype "choice" }
      dlist  { set argtype "double-list"  }
      list   { set argtype "list"   }
      time   { set argtype "time"   }
      bool   {
        set argtype "bool"
	if { [set argdefault [checkforflag [lindex $args [incr i]]]] == -1 } {
	  error "Bad default boolean value for arg \"$argname\""
	}
      }
      default { error "Unknown arg type: $argtype" }
    }
    if { ![info exists argdefault] } {
      set argdefault [lindex $args [incr i]]
    }
    if { $argtype == "choice" } {
      set vars([string trimleft $argname "-"]) 0
      set mychoice($argname) $argdefault
    } {
      set vars([string trimleft $argname "-"]) $argdefault
    }
    set myargs($argname) $argtype
    unset argdefault
  }

  set chlist [array get mychoice]
  unset mychoice

  while { [llength $parse] > 0 } {
    lpop parse arg
    if { $arg == "--" } { break }
    if { [info exists myargs($arg)] } {
      switch -exact -- $myargs($arg) {
	flag {
	  set v 1
	}
	"list" {
	  if { [catch {llength [lpop parse v]}] } {
	    unset v
	  }
	}
	"double-list" {
	  if { [catch {llength [lpop parse v]}] || [expr { [llength $v]%2 }] } {
	    unset v
	  }
	}
	"time" {
	  if { [set v [expandtime [lpop parse]]] == "" } { unset v }
	}
	bool {
	  if { [set v [checkforflag [lpop parse]]] == -1 } { unset v }
	}
	int  {
	  lpop parse v
	  if { ![regexp {^-?\d+$} $v] } { unset v }
	}
	float {
	  lpop parse v
	  if { [regexp {^-?\d+$} $v] } {
	    append v ".0"
	  } elseif { ![regexp {^-?\d+\.\d+$} $v] } {
	    unset v
	  }
	}
	str {
	  lpop parse v
	}
      }
      if { ![info exists v] } {
	::ck::debug -err "Bad arg type <%s> for <%s>, leave in default state." $myargs($arg) $arg
      } {
        set vars([string trimleft $arg "-"]) $v
        unset v
      }
    } elseif { [set tmp [checkforchoice $arg $chlist]] != "" } {
      set vars([string trimleft [lindex $tmp 0] "-"]) [lindex $tmp 1]
    } elseif { [string index $arg 0] == "-" } {
      ::ck::debug -err "Unknown arg <%s>, stop parse args." $arg
      lpush parse $arg
      break
    } else {
      lpush parse $arg
      break
    }
  }
  uplevel 1 [list array set "" [array get vars]]
#  uplevel 1 { putlog "a2: [array get {}]" }
  return $parse
}
proc ::ck::core::cmdargs { args } {
  upvar args pargs
  array set func $args
  if { [info exists func([lindex $pargs 0])] } {
    set c [catch { uplevel 2 [concat [list "$func([lindex $pargs 0])"] [lrange $pargs 1 end]] } errStr]
# this code work only in tcl8.5 :(
#    return -code $c -level 2 $errStr
    return -code $c $errStr
  } {
    uplevel 2 [list ::ck::debug -error "Unknown function. funcs: %s; args: %s" \
      [array names func] $pargs]
  }
}
proc ::ck::core::frm { afrm } {
  set ns [uplevel 1 [list namespace current]]
  if { ![array exists "${ns}::__msgfrm"] || \
    ![info exists "${ns}::__msgfrm\($afrm\)"]} {
      debug -err "Format for message <%s> in namespace <%s> not found." $afrm $ns
      return "#error#"
  }
  return [set "${ns}::__msgfrm\($afrm\)"]
}
proc ::ck::core::frmexists { afrm } {
  set ns [uplevel 1 [list namespace current]]
  if { ![array exists "${ns}::__msgfrm"] || \
    ![info exists "${ns}::__msgfrm\($afrm\)"]} {
      return 0
  }
  return 1
}
proc ::ck::core::msgreg { args } {
  set ns [uplevel 1 [list namespace current]]
  getargs -ns str $ns
  set cnt 0
  foreach line [split [lindex $args 0] "\n"] {
    set line [string trim $line]
    if { $line == "" || [string index $line 0] == "#" } continue
    if { ![regexp {^(\S+?)\s+(.+)$} $line - k v] } continue
    if { [string index $v 0] == "\"" && [string index $v end] == "\"" } {
      set v [string range $v 1 end-1]
    } elseif { [string index $v 0] == "\{" && [string index $v end] == "\}" } {
      set v [string range $v 1 end-1]
    }
    set "$(ns)::__msgfrm\($k\)" $v
    incr cnt
  }
  debug -debug "Readed %s message formats." $cnt
}
proc ::ck::core::uidns { {pfix ""} } {
  set ns [uplevel 1 [list namespace current]]
  if { [info exists "${ns}::_ck_uid_$pfix"] } {
    return [incr "${ns}::_ck_uid_$pfix"]
  }
  return [set "${ns}::_ck_uid_$pfix" 0]
}
proc ::ck::core::max { args } {
  if { [llength $args] == 1 } { set args [lindex $args 0] }
  return [lindex [lsort -real $args] end]
}
proc ::ck::core::min { args } {
  if { [llength $args] == 1 } { set args [lindex $args 0] }
  return [lindex [lsort -real $args] 0]
}
proc _array { args } {
  if { [string equal -nocase "init" [lindex $args 0]] } {
    uplevel 1 [list catch [list unset [lindex $args 1]]]
    return [uplevel 1 [list ::_ck_array set [lindex $args 1] [lindex $args 2]]]
  }
  uplevel 1 [concat ::_ck_array $args]
}
proc _foreach { args } {
  if { [llength $args] == 2 } {
    set c [catch { uplevel 1 [concat _ck_foreach _ $args] } errStr]
  } {
    set c [catch { uplevel 1 [concat _ck_foreach $args] } errStr]
  }
  return -code $c $errStr
}
proc foreach_ { args } {
  set c [catch { uplevel 1 [concat ::foreach _ $args] } errStr]
  return -code $c $errStr
}
proc foreacharray { arrname args} {
  set names [uplevel 1 [list array get $arrname]]
  set c [catch { uplevel 1 [concat [list ::foreach {k v} $names] $args] } errStr]
  return -code $c $errStr
}
proc ::foreachkv { args } {
  set c [catch { uplevel 1 [concat foreach {{k v}} $args] } errStr]
  return -code $c $errStr
}
proc ::set_ { s } {
  uplevel 1 [list set _ $s]
}
proc ::lappend_ { args } {
  uplevel 1 [concat ::lappend _ $args]
}
proc ::join_ { args } {
  uplevel 1 [concat ::join {$_} $args]
}
proc ::split_ { args } {
  uplevel 1 [concat ::split {$_} $args]
}
proc ::llength_ {  } {
  uplevel 1 { ::llength $_ }
}
proc ::append_ { args } {
  uplevel 1 [concat ::append _ $args]
}
proc ::regfilter { args } {
  ::ck::getargs -all flag -nocase flag
  upvar [lindex $args 1] var
  set cmd [list regsub]
  if { $(nocase) } { lappend cmd "-nocase" }
  if { $(all) } { lappend cmd "-all" }
  lappend cmd "--" [lindex $args 0] $var {} [lindex $args 1]
#  uplevel 1 [list regsub -all -- $reg $var {} $varn]
  uplevel 1 $cmd
}
proc ::lindex_ { num } {
  uplevel 1 [join [list ::lindex {$_} $num]]
}
