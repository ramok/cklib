
encoding system utf-8
::ck::require botnet 0.3
::ck::require cache

namespace eval botnetstat {
  variable version 1.0
  variable author  "Chpock <chpock@gmail.com>"

  namespace import -force ::ck::*
  namespace import -force ::ck::botnet::botnet
  namespace import -force ::ck::config::config
  namespace import -force ::ck::cache::cache
}

proc ::botnetstat::init { } {
  config register -id update -default 999d -type time \
    -desc "Update interval." -access "n" -folder "bnstat" -hook chkconfig
  config register -id file.tree -default "botnet.tree.php" -type str \
    -desc "File where save bots tree." -access "n" -folder "bnstat"
  config register -id file.data -default "botnet.data.php" -type str \
    -desc "File where save additional data about bot." -access "n" -folder "bnstat"
  config register -id file.encoding -default utf-8 -type encoding \
    -desc "Encoding for output files." -access "n" -folder "bnstat"
  cache register -maxrec 1000 -ttl 0
  etimer -norestart -interval [config get .bnstat.update] ::botnetstat::update
}
proc ::botnetstat::parseversion { str } {
  if { ![regexp {(\d)(\d\d)(\d\d)(\d\d)} $str - 1 2 3 4] } { return $str }
  set ver [list $1]
  lappend ver [string trimleft $2 0]
  lappend ver [string trimleft $3 0]
  lappend ver [string trimleft $4 0]
  return [string trimright [join $ver .] .]
}
proc ::botnetstat::escape { str } {
  return [string map [list {'} {\'} {\\} {\\\\}] $str]
}
proc ::botnetstat::update { {sid ""} } {
  if { $sid eq "" } {
    session create -proc ::botnetstat::update
    session hook BotNetResponse ::botnetstat::checkresponse
    session hook !onDestroy ::botnetstat::rebuild
    session event StartUpdate
    return
  }
  session import

#nick
#|--nick
#|  |--nick
#|  |  `--nick
#|  |--nick
#|  |  |--nick
#|  |  `--nick
#|  `--nick
#`--nick
  debug -debug "Register all bots in cache..."
  array set online [list]
  foreach_ [botlist] {
    cache makeid "![lindex_ 0]"
    if { [cache get xdata] } {
      array set {} $xdata
    } {
      array set {} [list]
    }
    set (_status) "on"
    set (_uplink) "![lindex_ 1]"
    set (_version) [parseversion [lindex_ 2]]
    cache put [array get {}]
    unset {}
    debug -debug "Registered bot: %s" [lindex_ 0]
    set online(![lindex_ 0]) 1
  }
  array set childs [list]
  set info(!${::botnet-nick}) [list "on" [parseversion $::numversion]]
  debug -debug "Mark other knowns bot as offline..."
  foreachkv [cache getindex] {
    if { $k == "!-local" || ![cache get -uid $k xdata] } continue
    array set {} $xdata
    if { ![info exists online($k)] } {
      set (_status) "off"
      debug -debug "Mark offline: %s" [string range $k 1 end]
    }
    if { ![info exists childs($(_uplink))] } {
      set childs($(_uplink)) [list $k]
    } {
      lappend childs($(_uplink)) $k
    }
    if { ![info exists childs($k)] } {
      set childs($k) [list $(_uplink)]
    } {
      lappend childs($k) $(_uplink)
    }
    set info($k) [list $(_status) $(_version)]
    unset {}
  }
  set d [list {<?}]
  foreacharray childs {
    set x [list]
    foreach_ $v { lappend x [escape $_] }
    set x [join $x {', '}]
    lappend d "\$b\['[escape $k]'\] = array\( 0 => '${x}'\);"
    set_ $info($k)
    set_ "'_status' => '[lindex_ 0]', '_version' => '[escape [lindex_ 1]]'"
    lappend d "\$n\['[escape $k]'\] = array\(${_}\);"
  }
  lappend d "\$defbot = '![escape ${::botnet-nick}]';"
  lappend d {?>}
  set fn [config get file.tree]
  if { [catch {set fid [open $fn w]} m] } {
    debug -err "Error while save tree data to file <%s>." $fn
    return
  }
  fconfigure $fid -encoding [config get "file.encoding"]
  puts $fid [join $d "\n"]
  close $fid
  debug -debug "Tree data saved to file <%s>." $fn

  botnet request -bot "-local" -service "_ck_pubinfo_" -cmd fullinfo
  # TODO: поставить вменяемый timeout на запрос
  botnet request -timeout 60 -global -service "_ck_pubinfo_" -cmd info
  return
}
proc ::botnetstat::checkresponse { sid } {
  session import

  if { $BotNetStatus < 0 } return

  cache makeid "!$Bot"
  #TODO: $Response может быть не листом, поэтому нужно проверить что б не повиснуть
  array set res $Response
  debug -debug "rcvd info from bot <%s>:" $Bot
  foreacharray res {
    debug -raw- "%20s : %s" $k $v
  }
  if { ![info exists res(rt)] } { set res(rt) "i" }
  if { [cache get _] } {
    array set {} $_
  }
  # Тут будет проверка на то, как давно были получены "полные" данные от бота, если давно -> unset {}
  if { $res(rt) ne "f" } {
    if { ![array exists {}] || ![info exists (_timestampf)] } {
      if { $Mark eq "2try" } {
	debug -error "No full info after second try, ignore bots info."
      } {
	debug -debug "No saved info about bot and info is not full, retry full."
	botnet request -bot $Bot -service "_ck_pubinfo_" -cmd "fullinfo" -mark "2try"
      }
      return
    }
    debug -debug "Got partial info from bot <%s>, is ok." $Bot
  } {
    debug -debug "Got full info from bot <%s>, is ok." $Bot
  }
  # переносим всю фигню
  foreacharray res {
    if { [string match "_*" $k] } continue
    set ($k) $v
    if { $k eq "rt" } { set (_timestamp$v) [clock seconds] }
  }
  if { $res(rt) eq "f" } {
    foreacharray {} {
      if { [string match "_*" $k] } continue
      if { ![info exists res($k)] } { unset ($k) }
    }
  }
  cache put [array get {}]
}
proc ::botnetstat::rebuild { sid } {
  debug -debug "Rebuilding bots infos..."
# 4 раздела
#  инфа о владельце
#  инфа о боте (включает irc инфу и инфу о хосте)
#  инфа о траффике
  set d [list {<?}]
#  array set info [list]
  proc deltatime { num } {
    upvar {} {}
    if { ![info exists (sendtime)] } { return "" }
    if { [catch {expr { $(sendtime) - $num }} v] } { return "" }
    return [duration $v]
  }
  proc makesize { num } {
    if { $num < 2048 } { return $num }
    set num [expr { 1.0 * $num / 1024 }]
    if { $num < 2048 } { return "[format %.2f $num]Kb" }
    set num [expr { 1.0 * $num / 1024 }]
    return "[format %.2f $num]Mb"
  }
  foreachkv [cache getindex] {
    if { ![cache get -uid $k xdata] } continue
    array set {} $xdata
    if { $k eq "!-local" } { set k "!${::botnet-nick}" }
    set b [escape $k]
    set_ [list]
    array set arr2 [list "_owner" 0 "_traffic" 0 "_irc" 0 "_system" 0 "_addinfo" 0]
    foreacharray {} {
      switch -exact -- $k {
        "network" - "ircnick" -
	"owners" - "masters" - "users" { set arr2(_irc) 1; set arr2(_addinfo) 1 }
	"channels" {
	  set v [join $v {, }]
          set arr2(_irc) 1; set arr2(_addinfo) 1
	}
	"owner.email" - "owner.city" - "owner.realname" -
	"owner" { set arr2(_owner) 1; set arr2(_addinfo) 1 }
	"owner.url" {
	  if { ![string equal -nocase -length 7 {http://} $v] } {
	    set v "http://$v"
	  }
          set arr2(_owner) 1; set arr2(_addinfo) 1
	}
	"modules" {
	  if { [catch {
	      set x [list]
	      foreach mod $v {
		lappend x "[lindex $mod 0] v[lindex $mod 1]"
	      }
	    }] } {
	      debug -warn "Error while parsing <module> field from bot <%s>: %s" $b $v
	      continue
	  }
	  set v [join $x {, }]
          set arr2(_system) 1; set arr2(_addinfo) 1
	}
	"tclver" - "tclthd" - codepage -
	"handlen" - "os" { set arr2(_system) 1; set arr2(_addinfo) 1 }
	"eggver" {
	  if { [catch {lreplace [split $v " "] 1 1} x] } {
	    debug -warn "Error while parsing <eggver> field from bot <%s>: %s" $b $v
	    continue
	  }
	  set v [join $x "+"]
          set arr2(_system) 1; set arr2(_addinfo) 1
	}
	"serveronline" - "uptime" {
	   if { [set x [deltatime $v]] == "" } {
	     debug -warn "Error while parsing <%s> field from bot <%s>: %s" $k $b $v
	     continue
	   }
	   set v $x
	   set arr2(_system) 1; set arr2(_addinfo) 1
	}
	"traffic" {
	  catch { unset x }
	  array set x [list]
	  if { [catch {
	      foreach rec $v {
		if { ![lexists {irc botnet partyline transfer misc total} [lindex $rec 0]] } continue
		if { [llength [set 1 [lrange $rec 1 end]]] != 4 } continue
		set 2 [list]
		foreach 3 $1 { lappend 2 [makesize $3] }
		set x([lindex $rec 0]) [join $2 { }]
	      }
	    }] || [array size x] == 0 } {
	      unset x
	      debug -warn "Error while parsing <traffic> field from bot <%s>: %s" $b $v
	      continue
	  }
	  set v [list]
	  foreach {1 2} [array get x] {
	    lappend v "'$1' => '$2'"
	  }
	  lappend_ "'traffic' => array\([join $v {, }]\)"
	  set arr2(_traffic) 1; set arr2(_addinfo) 1
	  unset x
	  continue
	}
        "sendtime" {
	  if { [catch {clock format $v} x] } {
	    debug -warn "Error while parsing <sendtime> field from bot <%s>: %s" $b $v
	    continue
	  }
	  set v $x
	}
      }
      lappend_ "'[escape $k]' => '[escape $v]'"
    }
    foreacharray arr2 {
      lappend_ "'${k}' => $v"
    }
    set_ [join $_ {, }]
    lappend d "\$n\['${b}'\] = array\(${_}\);"
    unset {} arr2
  }
  rename deltatime ""
  rename makesize ""
  lappend d {?>}
  set fn [config get file.data]
  if { [catch {set fid [open $fn w]} m] } {
    debug -err "Error while save data data to file <%s>." $fn
    return
  }
  fconfigure $fid -encoding [config get "file.encoding"]
  puts $fid [join $d "\n"]
  close $fid
  debug -debug "Bots data saved to file <%s>." $fn
}
proc ::botnetstat::chkconfig { mode var oldv newv hand } {
  if { ![string equal -length 3 $mode "set"] } return
  etimer -interval $newv ::botnetstat::update
  return
}
