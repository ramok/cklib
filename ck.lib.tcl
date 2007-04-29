
namespace eval ::ck {
  variable version       0.3
  variable datapath      "data"
  variable scriptpath    [list "scripts2" "scripts" "."]
  variable modulepath    [list [file join "scripts2" "ck.lib"] "scripts2" [file join "scripts" "ck.lib"] "ck.lib" "scripts" "."]
  variable modfilemask   "ck.%s.lib.tcl"
  variable debug         0

  variable ircnick       "unknown_nick"
  variable ircnet        "unknown_net"
  variable ircencoding   "cp1251"

  variable loaded
  variable etimers

  variable author  "Chpock <chpock@gmail.com>"

  namespace forget *
  namespace export -clear debug require procexists uid source etimer
  namespace export fixenc* backenc*
}

proc ::ck::init {} {
  variable frmpath
  variable datapath
  variable etimers

  variable ircnick
  variable ircnet
  variable ircencoding

  variable loaded
  variable version

  # TODO: нужно обнулить этот массив, потому как не обновляются автоматически
  #  те скрипты которые изменились, но загружаются автоматичеески
  if { [array exists loaded] } { unset loaded }
  # TODO: поэтому и удаляем ns всех модулей, что б они заново загрузились
  foreach ns [namespace children ::ck] {
    catch { unset "${ns}::version" }
  }
  foreach _ [binds] {
    if [string match ::ck::* [lindex $_ 4]] { unbind [lindex $_ 0] [lindex $_ 1] [lindex $_ 2] [lindex $_ 4] }
  }


  ### Init variables
  set frmpath       [list "scripts" "."]
  if { [array exists phrases] } { unset phrases }
  array set phrases ""
  if { ![array exists etimers] } {
    array set etimers [list]
  } {
    foreach id [array names etimers] {
      set etimers($id) [lreplace $etimers($id) 0 0 "0"]
    }
  }

  ### Init data-storage
  if { ![file isdirectory $datapath] } {
    if { [catch {file mkdir $datapath} errstr] } {
      ::error "Failed create data-storage dir <$datapath>: $errstr"
    }
  }

  if { [info exists ::irc_encoding] } {
    set ircencoding [string tolower $::irc_encoding]
  } {
    debug -warn "Please set IRC encoding variable \"irc_encoding\" in config-file."
  }

  if { [lsearch -exact [encoding names] $ircencoding] == -1 } {
    debug -err {IRC encoding '%s' not known by bot.} $ircencoding
    unset version
    return
  }

  if { [info exists "::botnet-nick"] && ${::botnet-nick} != "" } {
    set ircnick [fixencstr ${::botnet-nick}]
  } elseif { [info exists "::nick"] } {
    set ircnick [fixencstr $::nick]
  } else {
    debug -warn "Please set the variable \"botnet-nick\" in config-file."
  }

  if { [info exists ::network] } {
    set ircnet [fixencstr $::network]
  } {
    debug -warn "Please set the variable \"network\" in config-file."
  }


  ### Load code modules
  if { [catch {require core 0.3}] } { catch { unset version }; return }
  namespace import -force ::ck::core::*
  namespace export getargs cmdargs frm frmexists msgreg uidns min max
  ::ck::require strings
  ::ck::require lists
  ::ck::require files
  ::ck::require colors
  namespace import -force ::ck::colors::cformat
  namespace import -force ::ck::colors::stripformat
  ::ck::require eggdrop
  namespace import -force ::ck::eggdrop::*
  foreach _ $::ck::eggdrop::cmds { namespace export [namespace tail $_] }
  ::ck::require -debug
  ::ck::require config
  namespace import -force ::ck::config::config
  ::ck::require -botnet
  ::ck::require -ircservices

  if { [info exists ::sp_version] } { set _ " SuZi-patch v$::sp_version detected." } { set _ "" }
#  frmload
  debug "ck.lib v%s: initialization successfully.%s" $::ck::version $_
}
# levels:
#  -9 - debug
#  -3 - notice
#   0 - info
#   5 - warning
#   9 - error
proc ::ck::debug { args } {
  if { [info exists ::errorInfo] } { set _errinfo $::errorInfo }
  set quiet 0
  switch -glob -- [lindex $args 0] {
    -raw*   { set level -20 }
    -debug* { set level -9  }
    -not*   { set level -3  }
    -info*  { set level 0   }
    -warn*  { set level 5   }
    -err*   { set level 9   }
    default { set level ""  }
  }
  if { $level == "" } {
    set level 0
  } {
    if { [string index [lindex $args 0] end] == "-" } { set quiet 1 }
    set args [lrange $args 1 end]
  }
  if { [llength $args] > 1 } {
    if { [catch [concat format $args] errStr] } {
      debug -err "Error while formating error message \(%s\). Args: %s" $errStr $args
      if { [info exists _errinfo] } { set ::errorInfo $_errinfo }
      return
    }
    set txt $errStr
  } {
    set txt [lindex $args 0]
  }
  set ns [uplevel 1 [list namespace current]]
  if { [array exists ::ck::debug::d] && [info exists ::ck::debug::d($ns)] } {
    set req_level $::ck::debug::d($ns)
  } elseif { [info exists ${ns}::debug] } {
    set req_level [set ${ns}::debug]
  } else {
    set req_level 0
  }
  if { $level < $req_level  } {
    if { [info exists _errinfo] } { set ::errorInfo $_errinfo }
    return
  }
  set txt [string map [list {&} {&&}] $txt]
  if { !$quiet } {
    set ns [uplevel 1 {namespace current}]
    if { [set xns [namespace tail $ns]] == "ck" || $xns == "" } {
      set xns ""
    } elseif { [string match "::ck::*" $ns] } {
      set xns "&g$xns"
    } else {
      set xns "&G$xns"
    }
    if { [catch {uplevel 1 {set sid}} sid] } {
      if { $xns != "" } {
	set sid "&K\[${xns}&K\]"
      } {
	set sid ""
      }
    } {
      if { ![catch {set "::ck::sessions::S${sid}::_session_parent"} prt] && $prt != "" } {
	set txt "  $txt"
      }
      set sid [format "&K\[&n%s&K/%-6.6s&K\]" $sid $xns]
    }
    switch -- $level {
      -20 { set levels "&K:&yraw${sid}&K:&n"      }
      -9  { set levels ":&Kdbg${sid}&n:"          }
      -3  { set levels "&b:&Bntc${sid}&b:&n"      }
       0  { set levels "&g:&Ginf&g${sid}&g:&n"      }
       5  { set levels "&p:&Pwrn${sid}&p:&n"      }
       9  { set levels "&r:&Rerr${sid}&r:&n"      }
       default { set levels "&K:&nunk${sid}&K:&n" }
    }
    set txt "$levels $txt"
  }
  if { [catch {cformat _}] } {
    set txt [string map [list "&&" "\0"] $txt]
    regsub -all {&[a-zA-Z]} $txt {} txt
    set txt [string map [list "\0" "&"] $txt]
    putloglev d * $txt
  } {
    set rpl [list]
    # логим по dcc
    foreach _ [dcclist CHAT] {
      set flgs [console [lindex $_ 0]]
      if { [string first d [lindex $flgs 1]] == -1 } {
       	if { $level < 0 } continue
      } {
	lappend rpl [lindex $_ 0]
	::console [lindex $_ 0] -d
      }
      set xtxt [cformat $txt]
      if { ![procexists ::ck::eggdrop::putidx] } { append xtxt \r }
      putidx [lindex $_ 0] $xtxt
      unset xtxt
    }
    # логим в файл с флагом +d
    putloglev d ## [stripformat $txt]
    foreach _ $rpl { ::console $_ +d }
  }
  if { [info exists _errinfo] } { set ::errorInfo $_errinfo }
}
proc ::ck::uid {{pfix ""}} {
  if { $pfix != "" } { append pfix "#" }
  return "$pfix[rand 99999][rand 99999]"
}
proc ::ck::procexists { procname } {
  if { [info procs $procname] == "" } { return 0 } { return 1 }
}
proc ::ck::source { fn { apath - } } {
  if { ![info exists ::ck::version] } {
    debug -err "Can't load script <%s>, ck.lib is not initialized." $fn
    return
  }
  if { [string index $fn 0] eq "-" } {
    set fn [string range $fn 1 end]
    set lazy "-"
  } {
    set lazy ""
  }
  if { $apath == "-" } { set apath $::ck::scriptpath; set noquiet 1 }
  foreach path $apath {
    if { ![file isdirectory $path] } continue
    set xfn [file join $path $fn]
    if { ![file isfile $xfn] || ![file readable $xfn] } {
      append xfn {.tcl}
      if { ![file isfile $xfn] || ![file readable $xfn] } continue
    }
    if { [catch {array get ::ck::loaded} loadedx] } { set loadedx ""  }
    array set loaded $loadedx
    if { [info exists loaded($xfn)] } {
      if { $loaded($xfn) == [file mtime $xfn] } {
#	debug -notice "File %s not changed, so not reloaded." $xfn
        return
      }
      unset ::ck::loaded($xfn)
#      debug -notice "File %s changed, reloading." $xfn
    }
    set fenc  ""
    set fid   [open $xfn]
    set frmid ""
    while { [gets $fid line] != -1 } {
      if { [regexp {^\s*encoding\s+system\s+([^\s]+)\s*$} $line - aenc] } {
	set fenc $aenc
        break
      }
    }
    close $fid
    if { $fenc != "" } {
      set senc [encoding system]
      if { [catch [list encoding system $fenc] errStr] } {
	debug -error "Can't set encoding of script %s to %s" $xfn $fenc
	encoding system $senc
	unset $senc
      } {
#	debug -notice "Set encoding %s for script %s" $fenc $xfn
      }
    }
    if { [catch [list uplevel #0 [list source $xfn]] errStr] } {
      debug -error "Error while loading %s: %s" $xfn $errStr
      foreach _ [split $::errorInfo "\n"] { debug -err- "  $_" }
      if [info exists senc] { encoding system $senc }
      return "-"
    } {
      if { [info exists senc] } {
	set add "in encoding $fenc"
        encoding system $senc
      } {
	set add "in default encoding"
      }
      if { [info exists noquiet] } { debug -info "Script %s %s succsefuly loaded." $xfn $add }
      set ::ck::loaded($xfn) [file mtime $xfn]
    }
    set fn [file tail $fn]
    if { [string match -nocase "*.tcl" $fn] } { set fn [string range $fn 0 end-4] }
    set fn "::${fn}::init"
    if { [procexists $fn] } {
      debug -debug "Try exec init proc: %s ..." $fn
      if { [catch [list uplevel #0 [list $fn]] errStr] } {
	debug -error "Error while exec init proc %s : %s" $fn $errStr
	foreach _ [split $::errorInfo "\n"] { debug -err- "  $_" }
      } {
	debug -debug "Init proc is succsefuly end."
      }
    } {
      debug -debug "Init proc <%s> not exists." $fn
    }
    return $xfn
  }
  if { $lazy eq "" } {
    debug -error "Script %s not found." $fn
  }
  return "-"
}
proc ::ck::require { module {ver "0.1"} } {
  if { [string index $module 0] eq "-" } {
    set module [string range $module 1 end]
    set lazy "-"
  } {
    set lazy ""
  }
  set fn [format $::ck::modfilemask $module]
  set xfn [source "$lazy$fn" $::ck::modulepath]
  if { $xfn == "-" } {
    catch { unset "::ck::${module}::version" }
  }
  if { ![info exists "::ck::${module}::version"] } {
    if { $lazy eq "-" } {
      debug -debug "Module <%s> not found while lazy-load." $module
      return
    } {
      debug -err "While loading module %s." $module
      return -code error "while loading module ${module}."
    }
  }
  if { $xfn != "" } {
    set initproc [format "::ck::%s::init" $module]
    if { [procexists $initproc] } {
      if { [catch [list uplevel #0 $initproc] errStr] } {
	debug -err "Can't init module %s: %s" $module $errStr
	foreach _ [split $::errorInfo "\n"] { debug -err- "  $_" }
	return -code error $errStr
      }
    }
  }
  if { [set "::ck::${module}::version"] < $ver } {
    debug -err "Requested module %s version %s, but i have only %s." \
      $module $ver [set "::ck::${module}::version"]
    return -code error "Requested unknown module $module version ${ver}."
  }
  debug -debug "Module %s version %s loaded." $module [set "::ck::${module}::version"]
  return 0
}
proc ::ck::etimer { args } {
  variable etimers
  getargs \
   -norestart flag \
   -interval time 1

  if { [llength $args] > 1 } {
    set id [lindex $args 0]
    set script [lindex $args 1]
  } {
    set id [uplevel 1 {namespace current}]
    set script [lindex $args 0]
  }

  set (interval) [expr { $(interval) * 1000 }]

  if { [info exists etimers($id)] } {
    if { $(norestart) } {
      set afterid [lindex $etimers($id) 3]
    } {
      catch { after cancel [lindex $etimers($id) 3] }
    }
  }
  if { ![info exists afterid] } {
    set afterid [after $(interval) [list ::ck::etimer_run $id]]
  }
  debug -debug "Register new timer with ID <%s>, interval <%s>, norestart <%s>." $script $(interval) $(norestart)
  set etimers($id) [list "1" $(interval) $script $afterid]
}
proc ::ck::etimer_run { id } {
  variable etimers
  if { ![info exists etimers($id)] } return
  set_ $etimers($id)
  if { [lindex_ 0] == "0" } {
    unset etimers($id)
    return
  }
  if { [catch {uplevel #0 [lindex_ 2]} errStr] } {
    debug -err "while exec etimer-proc with id <%s>: %s" $id $errStr
    foreach x [split $::errorInfo "\n"] { debug -err- "  $x" }
  }
  set etimers($id) [lreplace $_ 3 3 [after [lindex_ 1] [list ::ck::etimer_run $id]]]
}
if [info exists sp_version] {
  proc ::ck::fixenc args {}
  proc ::ck::backenc args {}
  proc ::ck::fixencstr str return\ \$str
  proc ::ck::backencstr str return\ \$str
} {
  proc ::ck::fixenc { args } {
    foreach __xvar $args {
      upvar $__xvar mvar
      set mvar [encoding convertfrom $::ck::ircencoding $mvar]
    }
  }
  proc ::ck::backenc { args } {
    foreach __xvar $args {
      upvar $__xvar mvar
      set mvar [encoding convertto $::ck::ircencoding $mvar]
    }
  }
  proc ::ck::fixencstr { str } { return [encoding convertfrom $::ck::ircencoding $str] }
  proc ::ck::backencstr { str } { return [encoding convertto $::ck::ircencoding $str] }
}
proc ::ck::libinfo { {from "::ck"} } {
  set out [list]
  foreach ns [namespace children $from] {
    if { ![info exists "${ns}::version"] } continue
    lappend out [libinfo $ns]
  }
  if { $from eq "::ck" } { set _ "ck.lib" } { set _ [namespace tail $from] }
  return [list $_ [set [list "${from}::version"]] $out]
}
bind msg - ck.lib.ver ::ck::libinfopub
bind pub - ck.lib.ver ::ck::libinfopub
proc ::ck::libinfopub {n args} {
  if { [info exists ::ck::infopublock] && [expr { [clock seconds] - $::ck::infopublock }] < 90 } return
  set ::ck::infopublock [clock seconds]
  proc __format l {
    if { $l eq "" } { return "" }
    set x [list]
    foreach _ [lindex $l 2] { lappend x [__format $_]  }
    if { [llength $x] } { set x [format {[%s]} [join $x {; }]] }
    return [format {%s/v%s%s} [lindex $l 0] [lindex $l 1] $x]
  }
  putquick "NOTICE [fixencstr $n] :[__format [libinfo]]"
  rename __format {}
}

catch {
  proc bgerror {err} {
    global errorCode errorInfo
    putlog "!bgerror! $err"
    putlog "!bgerror! $errorCode"
    putlog "!bgerror! $errorInfo"
  }
}

::ck::debug "ck.Lib v$::ck::version by Chpock loaded."
::ck::init

