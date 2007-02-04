
::ck::require sessions 0.3
::ck::require config 0.2

namespace eval ::ck::botnet {
  variable version 0.3
  variable author "Chpock <chpock@gmail.com>"

  variable res_buf
  variable req_buf
  variable req_snt

  variable my_services

  namespace import -force ::ck::sessions::session
  namespace import -force ::ck::config::config
  namespace import -force ::ck::*
  namespace export botnet
}

proc ::ck::botnet::init {  } {
  variable res_buf
  variable req_buf
  variable my_services
  variable infolock

  if { ![array exists res_buf] } { array set res_buf [list] }
  if { ![array exists req_buf] } { array set req_buf [list] }
  if { ![array exists req_snt] } { array set req_snt [list] }
  array init my_services

  bind bot - ckbn_req  ::ck::botnet::bnd_req
  bind bot - ckbn_reqN ::ck::botnet::bnd_req
  bind bot - ckbn_res  ::ck::botnet::bnd_res
  bind bot - ckbn_resN ::ck::botnet::bnd_res

  if { [catch {rename ::putbot ::_ck_putbot} errStr] } { rename ::putbot "" }
  rename ::_putbot ::putbot
  regservice _ck_pubinfo_ ::ck::botnet::publicinfo
  config register -id "public" -default 0 -desc "Send bots info in public." \
    -folder ".core.botnet" -type bool -access "n"
  config register -id "owner" -default "Lamer" -desc "Owner of bot." \
    -folder ".core.botnet" -type str -access "n" -disableon [list "public" 0]
  config register -id "owner.email" -default "lamer@bobruysk.ru" -desc "Email of bots owner." \
    -folder ".core.botnet" -type str -access "n" -disableon [list "public" 0]
  config register -id "owner.realname" -default "Vasya Pupkin" -desc "Realname of bots owner." \
    -folder ".core.botnet" -type str -access "n" -disableon [list "public" 0]
  config register -id "owner.icq" -default "" -desc "ICQ num of bots owner." \
    -folder ".core.botnet" -type str -access "n" -disableon [list "public" 0]
  config register -id "owner.url" -default "" -desc "URL of bots owner." \
    -folder ".core.botnet" -type str -access "n" -disableon [list "public" 0]
  config register -id "owner.city" -default "Bobruysk" -desc "City of bots owner." \
    -folder ".core.botnet" -type str -access "n" -disableon [list "public" 0]
  config register -id "hosting" -default "" -desc "Public name of bots hosting." \
    -folder ".core.botnet" -type str -access "n" -disableon [list "public" 0]
  config register -id "hosting.url" -default "" -desc "URL of bots hosting." \
    -folder ".core.botnet" -type str -access "n" -disableon [list "public" 0]
}
proc ::ck::botnet::botnet { args } {
  cmdargs \
    regservice ::ck::botnet::regservice \
    response   ::ck::botnet::response \
    request    ::ck::botnet::request
}
proc ::ck::botnet::regservice { servid servproc } {
  variable my_services
  set my_services($servid) $servproc
  debug -debug "Register service <%s> with proc <%s>" $servid $servproc
}
proc ::ck::botnet::request { args } {
  upvar sid sid
  getargs \
    -bot str "" -bots str [list] \
    -service str "" -cmd str "" \
    -local flag -global flag \
    -mark str "" \
    -timeout time 60

  if { $(global) } {
    set (bots) [bots]
    set BotNetRequestType "global"
  } {
    if { $(bot) != "" } {
      if { ![lexists $(bots) $(bot)] } {
	lappend (bots) $(bot)
      }
    }
    set BotNetRequestType "custom"
  }
  if { ![llength $(bots)] } {
    debug -warn "No dest bots."
    return [list]
  }
  set BotsReply [list]
  session create -child -proc ::ck::botnet::make_request \
    -parent-event BotNetResponse -parent-mark $(mark)
  session export \
    -grab (service) as ServId \
    -grab (cmd) as ReqCmd \
    -grab args as ReqArgs \
    -grab (bots) as BotsList \
    -grab (timeout) as BotNetTimeout \
    -grablist [list BotsReply BotNetRequestType]
  session insert ReqId [uidns Req]
  session hook Timeout req_timeout
  session parent
  return $(bots)
}
proc ::ck::botnet::make_request { sid } {
  variable req_snt
  session import
  session insert ReqTime [clock seconds]
  set msg [string encode64 -encoding utf-8 -- [list $ReqId $ServId $ReqCmd $ReqArgs]]
  set BotNetTimeout [expr { $BotNetTimeout * 1000 }]
  set_ [after $BotNetTimeout [list session event -sid $sid Timeout]]
  set req_snt($ReqId) [list $sid $_]
  if { [string length $msg] <= 350 } {
    set msg [list "ckbn_req $msg"]
  } {
    set msgl [list]; set i 0
    while { $msg != "" } {
      lappend msgl "ckbn_reqN ${ReqId}_${i}_99 [string range $msg 0 299]"
      set msg [string range $msg 300 end]
      incr i
    }
    set msg $msgl; unset msgl
    lappend msg "ckbn_reqN ${ReqId}_${i}_99"
  }
  if { $BotNetRequestType eq "global" } {
    foreach_ $msg { putallbots $_ }
  } {
    foreach Bot $BotsList {
      if { [catch {foreach_ $msg {putbot $Bot $_}} m] } {
	debug -warn "Error while send request to <%s>." $Bot
	session return -nodestroy Bot $bot BotNetStatus -20 BotNetError "Error while send request."
	session import -exact BotsReply
	session insert BotsReply [lappend BotsReply $Bot]
      }
    }
  }
  if { [info exists req_snt($ReqId)] } {
    session import -exact BotsReply
    if { [llength $BotsList] == [llength $BotsReply] } {
      catch { after cancel [lindex $req_snt($ReqId) 1] }
      catch { unset req_snt($ReqId) }
    } {
      session lock
    }
  }
}
proc ::ck::botnet::response { text } {
  upvar sid sid
  session import -exact Bot ReqId
  set msg "[string encode64 -encoding utf-8 -- [list $ReqId $text]]"
  if { [string length $msg] <= 350 } {
    debug -debug "send one-part response."
    putbot $Bot "ckbn_res $msg"
  } {
    set msgl [list]
    while { $msg != "" } {
      lappend msgl [string range $msg 0 299]
      set msg [string range $msg 300 end]
    }
    set rid [uidns Res]
    for { set i 0 } { $i < [llength $msgl] } { incr i } {
      debug -debug "send response part $i of [llength $msgl]"
      putbot $Bot "ckbn_resN ${rid}_${i}_[llength $msgl] [lindex $msgl $i]"
    }
    debug -debug "send final response part $i of [llength $msgl]"
    putbot $Bot "ckbn_resN ${rid}_${i}_[llength $msgl]"
  }
}
proc ::ck::botnet::bnd_req { fb cmd txt } {
  variable req_buf
  variable my_services
  if { $cmd == "ckbn_reqN" } {
    set txt [split $txt " "]
    set arg [split [lindex $txt 0] "_"]
    set txt [lindex $txt 1]
    foreach_ $arg {
      if { ![string isnum -int -unsig $_] } {
	debug -err "bad multirequest format <%s> from bot %s." $_ $fb
	return
      }
    }
    lassign $arg id N M
    set id "$id@$fb"
    if { $N != 0 } {
      if { ![info exists req_buf($id)] } {
	debug -warn "rcvd bad part <%s> from bot %s" $N $fb
	return
      }
      if { [expr { [lindex $req_buf($id) 0] + 1 }] != $N } {
	debug -warn "rcvd bad part <%s> from bot %s, expected part <%s>" $N $fb [expr { [lindex $req_buf($id) 0] + 1 }]
	unset req_buf($id)
	return
      }
      set xtxt [lindex $req_buf($id) 2]
      append xtxt $txt
      set req_buf($id) [list $N [clock seconds] $xtxt]
      unset xtxt
    } {
      set req_buf($id) [list $N [clock seconds] $txt]
    }
    if { $txt != "" } { return }
    set txt [lindex $req_buf($id) 2]
    unset req_buf($id)
  }
  set txt [string decode64 -encoding utf-8 -- $txt]
  if { [catch {lindex $txt 4} errStr] || [llength $txt] != 4 } {
    debug -err "rcvd bad format for request: %s" $txt
    return
  }
  lassign $txt ReqId ServId ReqCmd ReqArgs
  debug -debug {rcvd ServId(%s) ReqCmd(%s) ReqId(%s) ReqArgs(%s)} $ServId $ReqCmd $ReqId $ReqArgs
  if { ![info exists my_services($ServId)] } {
    debug -err "rcvd message for service <%s>, but its not registered." $ServId
    return
  }
  session create -proc $my_services($ServId)
  session export -grablist [list ReqId ServId ReqCmd ReqArgs] -grab fb as Bot
  debug -debug "Got request, launch new session..."
  session event BotNetRequest
}
proc ::ck::botnet::bnd_res { fb cmd txt } {
  variable res_buf
  variable req_snt
  if { $cmd == "ckbn_resN" } {
    set txt [split $txt " "]
    set arg [split [lindex $txt 0] "_"]
    set txt [lindex $txt 1]
    foreach_ $arg {
      if { ![string isnum -int -unsig $_] } {
	debug -err "bad multiresuest format <%s> from bot %s." $_ $fb
	return
      }
    }
    lassign $arg id N M
    set id "$id@$fb"
    if { $N != 0 } {
      if { ![info exists res_buf($id)] } {
	debug -warn "rcvd bad part <%s> from bot %s" $N $fb
	return
      }
      if { [expr { [lindex $res_buf($id) 0] + 1 }] != $N } {
	debug -warn "rcvd bad part <%s> from bot %s, expected part <%s>" $N $fb [expr { [lindex $res_buf($id) 0] + 1 }]
	unset res_buf($id)
	return
      }
      set xtxt [lindex $res_buf($id) 2]
      append xtxt $txt
      set res_buf($id) [list $N [clock seconds] $xtxt]
      unset xtxt
    } {
      set res_buf($id) [list $N [clock seconds] $txt]
    }
    if { $txt != "" } { return }
    set txt [lindex $res_buf($id) 2]
    unset res_buf($id)
  }
  set txt [string decode64 -encoding utf-8 -- $txt]
  if { [catch {lindex $txt 4} errStr] || [llength $txt] != 2 } {
    debug -err "rcvd bad format for response: %s" $txt
    return
  }
  lassign $txt ReqId Response
  if { ![info exists req_snt($ReqId)] } {
    debug -warn "rcvs not expected response id <%s>, text: %s" $ReqId $Response
    return
  }
  set sid [lindex $req_snt($ReqId) 0]
  session import -exact BotsList BotsReply
  if { ![lexists $BotsList $fb] } {
    debug -warn "rcvs response from unexpected bot <%s>, ignoring..." $fb
    return
  }
  if { [lexists $BotsReply $fb] } {
    debug -warn "rcvs double response from bot <%s>, ignoring..." $fb
    return
  }
  session insert BotsReply [lappend BotsReply $fb]
  debug -debug "Got response, return to parent session."
  if { [llength $BotsList] == [llength $BotsReply] } {
    after cancel [lindex $req_snt($ReqId) 1]
    unset req_snt($ReqId)
    session unlock
    session return BotNetStatus 0 BotNetError "" Response $Response Bot $fb
  } {
    session return -nodestroy BotNetStatus 0 BotNetError "" Response $Response Bot $fb
  }
}
proc ::_putbot { tobot txt } {
  if { $tobot == "-local" } {
    set txt [split $txt " "]
    set cmd [lindex $txt 0]
    set txt [join [lrange $txt 1 end] " "]
    foreach_ [binds] {
      if { [lindex $_ 0] != "bot" || [lindex $_ 2] != $cmd } { continue }
      set prc [lindex $_ 4]
      ::ck::debug -info ":botnet: transfer message cmd\(%s\) to local proc <%s>..." $cmd $prc
      if { [catch [list $prc $tobot $cmd $txt] errStr] } {
	::ck::debug -err ":botnet: Error transfer message cmd\(%s\) to local proc <%s>: %s" $cmd $prc $errStr
	foreach_ [split $::errorInfo "\n"] {
	  ::ck::debug -err- "  $_"
	}
      }
      return
    }
    ::ck::debug -warn ":botnet: local recepient for cmd <%s> not found." $cmd
  } {
    uplevel 1 [list ::_ck_putbot $tobot $txt]
  }
}
proc ::ck::botnet::publicinfo { sid } {
  # original idea from rbninfo.tcl by Shrike <shrike@eggdrop.org.ru>
  variable infolock
  session import
  if { $ReqCmd ne "info" && $ReqCmd ne "fullinfo" } return
  if { [array exists infolock] && [info exists infolock($Bot)] } {
    array set oi $infolock($Bot)
    if { [info exists oi(sendtime$ReqCmd)] && [expr { [clock seconds] - $oi(sendtime$ReqCmd) }] < 180 } {
      debug -debug "Ignore request for bot info from bot <%s>." $Bot
      return
    }
  } {
    array set oi [list]
  }
  set (ckinfo)   [::ck::libinfo]
  set (sendtime) [clock seconds]
  if { [config get public] } {
    foreach_ {owner owner.email owner.realname owner.icq owner.url owner.city hosting hosting.url} {
      if { [set v [config get $_]] eq "" } continue
      set ($_) $v
    }

    set (channels) [list]
    foreach_ [channels] {
      if { [channel get $_ secret] || [channel get $_ inactive] || [string index $_ 0] eq "&" } continue
      lappend (channels) $_
    }

    set (modules) [list]
    foreach_ [modules] { lappend (modules) [lrange $_ 0 1] }

    set (users)    [countusers]
    set (os)       [unames]
    set (tclver)   [info patchlevel]
    set (handlen)  $::handlen
    set (owners)   [userlist n|]
    set (masters)  [userlist m|]
    set (codepage) $::ck::ircencoding
    set (network)  $::ck::ircnet
    set (tclthd)   [info exists ::tcl_platform(threaded)]
    set (traffic)  [traffic]
    set (uptime)   $::uptime
    set (serveronline) ${::server-online}
    set (eggver)   $::version
    set (ircnick)  $::botnick
  }
  if { $ReqCmd == "fullinfo" } {
    set (rt) "f"
    set send [array get {}]
  } {
    set send [list]
    set (rt) "i"
    foreacharray {} {
      if { $k eq "rt" || ![info exists oi($k)] || ($oi($k) ne $v)  } { lappend send $k $v }
    }
  }
  if { [info exists oi(sendtimeinfo)] } { set (sendtimeinfo) $oi(sendtimeinfo) }
  if { [info exists oi(sendtimefullinfo)] } { set (sendtimefullinfo) $oi(sendtimefullinfo) }
  set (sendtime$ReqCmd) [clock seconds]
  set infolock($Bot) [array get {}]
  debug -debug "Send my info to bot <%s> by request <%s> (info type \[%s\])..." $Bot $ReqCmd $(rt)
  unset {} oi
  foreachkv $send {
    debug -raw- "%15s : %s" $k $v
  }
  debug -raw "End of info."
  response $send
}
proc ::ck::botnet::req_timeout { sid } {
  session import -exact BotsList BotsReply ReqId
  debug -debug "Session timeouted, try to force it."
  set BotsList [lfilter -exact -- $BotsList $BotsReply]
  while { [llength $BotsList] } {
    lpop BotsList Bot
    debug -debug "Report about timeout while get response from <%s>..." $Bot
    if { [llength $BotsList] } {
      session return -nodestroy BotNetStatus -30 BotNetError "Request timeout." Bot $Bot
    } {
      unset ::ck::botnet::req_snt($ReqId)
      session unlock
      session return BotNetStatus -30 BotNetError "Request timeout." Bot $Bot
    }
  }
  debug -err "Can't find bots with no replay."
  unset ::ck::botnet::req_snt($ReqId)
  session unlock
  session destroy
}

# в ботнете мессаги
# ckbn_req [base64]
# ckbn_reqN id_N_M [base64]
#   req id, N part of M's
# ckbn_res [base64]
# ckbn_resN id_N_M [base64]
#   res id, N part od M's
# запрос:
#   {id запроса} {id сервиса для запроса} {id команды запроса} {другие данные}
# ответ
#   {id запроса} {ответ}
