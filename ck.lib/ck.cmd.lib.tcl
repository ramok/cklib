
#TODO: фильры тоже по каналам матчат

#скрипт может возвращать:
#  ERR_SYNTAX   - ошибка синтаксиса вызова команды
#  ERR_INTERNAL - ошибка скрипта
#    ?string?       - сообщение об ошибке
::ck::require eggdrop  0.2
::ck::require colors   0.2
::ck::require config   0.2
::ck::require auth     0.2
::ck::require sessions 0.2

namespace eval ::ck::cmd {
  variable version 0.2
  variable author  "Chpock <chpock@gmail.com>"

  variable debug -20
  variable MAGIC "\000:\000"
  variable MAGIClength [string length $MAGIC]

  namespace import -force ::ck::*
  foreach _ $::ck::eggdrop::cmds { namespace export [namespace tail $_] }
  namespace import -force ::ck::config::config
  namespace import -force ::ck::auth::authcheck
  namespace import -force ::ck::sessions::session
  namespace import -force ::ck::files::datafile
  namespace export cmd cmdchans cmd_checkchan
  namespace export cformat cjoin cquote cmark
  namespace export reply replydoc checkaccess
  namespace export debug msgreg uidns getargs etimer fixenc* backenc*
  namespace export session
  namespace export config
  namespace export datafile
}

proc ::ck::cmd::init {} {
  variable bindmask

  variable cmds
  variable filters
  variable cmds_flood
  variable floodctl
  variable floodctl_timer
  variable version
  variable cmddoc

  config register -id "prefix.pub" -type str -default "!" \
    -desc "Prefix for public cmds." -access "m" -folder "mod.cmd" -hook ::ck::cmd::cfg_resetbinds
  config register -id "prefix.msg" -type str -default "" \
    -desc "Prefix for private cmds." -access "m" -folder "mod.cmd" -hook ::ck::cmd::cfg_resetbinds
  config register -id "prefix.dcc" -type str -default "." \
    -desc "Prefix for partyline cmds." -access "m" -folder "mod.cmd" -hook ::ck::cmd::cfg_resetbinds
  config register -id "pub.noprefix" -type bool -default 1 \
    -desc "Allow public cmds without prefix." -access "m" -folder "mod.cmd" -hook ::ck::cmd::cfg_resetbinds
  config register -id "pub.multitarget" -type bool -default 0 \
    -desc "Allow multitarget public msgs." -folder "mod.cmd"

  array init cmds
  array init filters
  array init bindmask
  array init cmddoc
#  if { [array exist cmds_flood] } { unset cmds_flood }
#  array set cmds_flood ""
  bind pubm - * ::ck::cmd::pubm
  bind msgm - * ::ck::cmd::msgm
  bind filt - * ::ck::cmd::filt

#  if { [array exist floodctl] } { unset floodctl }
#  array set floodctl ""
#  foreach timer [after info] {
#    if { [string match "::ck::cmd::*" [after info $timer]] } { after cancel $timer }
#  }
#  set floodctl_timer [after 1000 ::ck::cmd::floodchecktimer]

  msgreg {
    default.usage Usage for cmd <%s> is not defined.
    default.reply &c%s&K: &n
    auth.nick You currently authenticated with nick &L%s&L.
    auth.need Authentication require for using my public commands.
  }

}

proc ::ck::cmd::floodchecktimer {} {
  variable floodctl_timer
  variable floodctl
  variable cmds_flood

  if { [array size floodctl] == 0 } {
    set floodctl_fimer [after 1000 ::ck::cmd::floodchecktimer]
    return
  }

  set now [clock seconds]
  foreach cmd [array names floodctl] {
    set needunset 0
    if { ![info exist cmds_flood($cmd)] } {
      set needunset 1
    } {
      set fld [split $cmds_flood($cmd) :]
      if { $now - [lindex $floodctl($cmd) 1] >= [lindex $fld 1] } { set needunset 1 }
    }
    if { $needunset } { unset floodctl($cmd) }
    unset needunset
  }
  unset now
  set floodctl_fimer [after 1000 ::ck::cmd::floodchecktimer]
}

proc ::ck::cmd::floodcheck {id} {
  variable floodctl
  variable cmds_flood

  if { ![info exist floodctl($id)] } {
    set floodctl($id) [list 1 [clock seconds]]
  } {
    set floodctl($id) [lreplace $floodctl($id) 0 0 [expr [lindex $floodctl($id) 0] + 1]]
  }
  if { [lindex $floodctl($id) 0] > [lindex [split $cmds_flood($id) :] 0] } {
    return 1
  } {
    return 0
  }
}
proc ::ck::cmd::cmd {args} {
  cmdargs \
    register      ::ck::cmd::register \
    doc           ::ck::cmd::regdoc \
    regfilter-pub ::ck::cmd::regfilter-pub \
    unregister ::ck::cmd::unregister
}

proc ::ck::cmd::regdoc { args } {
  variable cmddoc
  getargs \
    -link list [list] \
    -author str "" \
    -alias list [list]
  set id [string stripcolor [string tolower [lindex $args 0]]]
  if { $id == "" } return
  set text [lindex $args 1]
  regsub -all {\s*\\\n\s*} $text { } text
  regsub -all {\*(.+?)\*} $text {\&B\1\&n} text
  regsub -all {\[(.+?)\]} $text {\&K[\&R\1\&K]\&n} text
  regsub -all {<(.+?)>} $text   {\&K<\&R\1\&K>\&n} text
  set_ ""
  while { [regexp {^(.*?)~(.+?)~(.*)$} $text - a1 a2 a3] } {
    set a2 [string map [list "&n" "&n&U"] $a2]
    append_ $a1 &U $a2 &U
    set text $a3
  }
  set text "$_$text"
  set text [::ck::colors::cformat $text]
  set_ [list $id [lindex $args 0] $text $(author) $(link)]
  set cmddoc($id) $_
  foreach_ $(alias) { set cmddoc($_) [list $_ $_ $id $(author) $(link)] }
}
proc ::ck::cmd::regfilter-pub { fid fproc } {
  variable filters
  variable bindmask

  set tflt(type) "pub"
  set tflt(proc) $fproc
  set tflt(id)   $fid

  set filters($fid) [array get tflt]
  array init bindmask
}

# register command.id procedure \
#   -bind -bindpub -bindmsg -binddcc
#     биндит на слово
#   -flood
#     флуд-лимит на обычные сообщения
#   -floodusage
#     флуд-лимит на сообщения об использовании
#   -flooderr
#     флуд-лимит на сообщения об ошибках
#   -flooduniq
#     флуд-лимит на то, когда можно повторяться
#   -floodhost
#     флуд-лимит на 1хост
proc ::ck::cmd::register {id bindprc args} {
  variable cmds
  variable cmds_flood
  variable bindmask

  unregister $id
  set tcmd(flood)       "10:60"
  set tcmd(floodusage)  "1:90"
  set tcmd(flooderr)    "3:60"
  set tcmd(flooduniq)   "1:90"
  set tcmd(noprefix)    "[config get pub.noprefix] 1 0"
  set tcmd(bind)        $bindprc
  set tcmd(id)	        $id
  set tcmd(config)      $id
  set tcmd(autousage)   0
  set tcmd(access)      "-"
  set tcmd(auth)        "1"
  set tcmd(doc)         ""
  set tcmd(pubbind) [list]
  set tcmd(msgbind) [list]
  set tcmd(dccbind) [list]
  set tcmd(pubmask) [list]
  set tcmd(msgmask) [list]
  set tcmd(dccmask) [list]
  set tcmd(namespace) [uplevel 1 [list namespace current]]

  while { [llength $args] > 0 } {
    lpop args cmd
    switch -- $cmd {
      -bind   {
	if { [lpop args mask] != "" } {
	  lappend tcmd(pubbind) $mask
	  lappend tcmd(dccbind) $mask
	  lappend tcmd(msgbind) $mask
	}
      }
      -bindpub - -pubbind { if { [lpop args mask] != "" } { lappend tcmd(pubbind) $mask } }
      -bindmsg - -msgbind { if { [lpop args mask] != "" } { lappend tcmd(msgbind) $mask } }
      -binddcc - -dccbind { if { [lpop args mask] != "" } { lappend tcmd(dccbind) $mask } }
      -mask   {
	if { [lpop args mask] != "" } {
	  lappend tcmd(pubmask) $mask
	  lappend tcmd(dccmask) $mask
	  lappend tcmd(msgmask) $mask
        }
      }
      -maskpub - -pubmask { if { [lpop args mask] != "" } { lappend tcmd(pubmask) $mask } }
      -maskmsg - -msgmask { if { [lpop args mask] != "" } { lappend tcmd(msgmask) $mask } }
      -maskdcc - -dccmask { if { [lpop args mask] != "" } { lappend tcmd(dccmask) $mask } }
      -flood       { lpop args tcmd(flood)      }
      -floodusage  { lpop args tcmd(floodusage) }
      -flooderr    { lpop args tcmp(flooderr)   }
      -flooduniq   { lpop args tcmp(flooduniq)  }
      -config      { lpop args tcmd(config)     }
      -ns          { lpop args tcmd(namespace)  }
      -autousage   { set tcmd(autousage) 1      }
      -access      { lpop args tcmd(access)     }
      -noauth      { set tcmd(auth) 0           }
      -doc         { lpop args tcmd(doc)        }
      default {
	debug -warn "Unknown option: %s" $cmd
      }
    }
  }

  if { $tcmd(access) == "-|-" } {
    set tcmd(access) "-"
  }

  set cmds($id) [array get tcmd]
#  set cmds_flood($id) $tcmd(flood)

  if { $tcmd(pubmask) != "" || $tcmd(pubbind) != "" } {
    config register -id "chanallow" -type list -default "*" \
      -desc "List of channels were command $id is allowed." -access "m" -folder $tcmd(config) -ns $tcmd(namespace) \
      -hook ::ck::cmd::cfg_resetbinds
    config register -id "chandeny" -type list -default "" \
      -desc "List of channels were command $id is forbidden." -access "m" -folder $tcmd(config) -ns $tcmd(namespace) \
      -hook ::ck::cmd::cfg_resetbinds
    config register -id "notice" -type bool -default 0  \
     -desc "Reply command $id to user as notice." -access "m" -folder $tcmd(config) -ns $tcmd(namespace)
  }

  if { $tcmd(pubmask) != "" || $tcmd(msgmask) != "" || \
    $tcmd(msgbind) != "" || $tcmd(pubbind) != "" } {
      config register -id "msgmode" -type str -default quick \
        -desc "Send-reply mode. Can be <fast>, <quick>, <serv> or <help>." -access "m" -folder $tcmd(config) \
        -ns $tcmd(namespace) -hook ::ck::cmd::cfg_msgmode
  }

  config register -id "nocolors" -type bool -default 0  \
    -desc "Remove colors from command $id replys." -access "m" -folder $tcmd(config) -ns $tcmd(namespace)

  array init bindmask
}

proc ::ck::cmd::unregister {id} {
  variable cmds
  variable bindmask

  if { ![info exist cmds($id)] } return
  unset cmds($id)
  array init bindmask
}
proc ::ck::cmd::updatebinds { type { target "" } } {
  variable bindmask
  variable filters
  variable cmds

  set bindres [list]
  set maskres [list]
  set filtres [list]

  foreach {id larray} [array get filters] {
    array set tflt $larray
    if { $tflt(type) != $type } continue
    lappend filtres $id $tflt(proc)
  }
  foreach {id larray} [array get cmds] {
    array set tcmd $larray
    debug -debug "Binding cmd <%s>" $id
    switch -- $type {
      "pub" {
	if { ![cmd_checkchan $id $target] } {
	  debug -debug "Cmd <%s> is disabled on <%s> due config." $id $target
	  continue
	}
	set pfixmask {!?}
      }
      "msg" {
	set pfixmask {}
      }
      "dcc" {
	set pfixmask {\.}
      }
    }
    foreach bnd [set "tcmd(${type}bind)"] {
      if { $bnd == "" } continue
      if { [regexp {^(.+?)\|(.+)$} $bnd - a1 a2] } {
	set a3 ""
	set a4 ""
	foreach ch [split $a2 ""] {
	  append a3 "\($ch"
	  append a4 "\)?"
	}
	set bnd "$a1$a3$a4"
	unset a1 a2 a3 a4
      }
      set bnd "^$pfixmask\($bnd\)(\\s|\$)"
      debug -debug "Bind <%s> for cmd <%s> in <%s@%s>" $bnd $id $target $type
      lappend bindres $bnd $id
    }
    foreach mask [set "tcmd\(${type}mask\)"] {
      if { $mask == "" } continue
      set msk "^$pfixmask$mask"
      debug -debug "Mask <%s> for cmd <%s> in <%s@%s>" $msk $id $target $type
      lappend maskres $msk $id
    }
    unset tcmd
  }
  set bindmask([list "bind $type $target"]) $bindres
  set bindmask([list "mask $type $target"]) $maskres
  set bindmask([list "filt $type $target"]) $filtres
}
proc ::ck::cmd::searchcmd { vart type { tg "" } } {
  variable bindmask
  upvar $vart t
  if { ![info exists bindmask([list "mask $type $tg"])] } { updatebinds $type $tg }
  foreach {msk tid} [set bindmask([list "mask $type $tg"])] {
    if { [regexp -- $msk $t] } {
      return $tid
    }
  }
  set match [list]
  foreach {bnd tid} [set bindmask([list "bind $type $tg"])] {
    if { [set tmpm [regexp -inline -- $bnd $t]] != "" } {
      lappend match [list [string length [lindex $tmpm 1]] $tid]
    }
  }
  if { [llength $match] == 0 } return
  return [lindex [lindex [lsort -integer -index 0 $match] end] 1]
}
proc ::ck::cmd::applyfilter { type {tg ""} } {
  variable bindmask
  switch -- $type {
    pub {
      upvar t Text n Nick uh UserHost h Handle tg Channel
    }
  }
  if { ![info exists bindmask([list "mask $type $tg"])] } { updatebinds $type $tg }
  foreach {FilterId fproc} [set bindmask([list "filt $type $tg"])] {
    debug -debug "Apply %s-filter\(%s\) <%s>..." $type $tg $FilterId
    if { [catch [list $fproc $type] errStr] } {
      debug -err "Error %s-filter\(%s\) with proc <%s>: %s" $type $tg $fproc $errStr
      foreach_ [split $::errorInfo "\n"] {
	debug -err- "  $_"
      }
    }
    debug -debug "Apply %s-filter\(%s\) <%s> finish." $type $tg $FilterId
    if { $Text == "" } {
      debug -debug "Filter nulled Text var. exiting."
      return 1
    }
  }
  return 0
}
proc ::ck::cmd::checkaccess { {ret ""} } {
  upvar sid sid
  session export -exact CmdAccess
  if { $CmdAccess == "-" } { return 1 }
  session export -exact Handle Nick
  if { $Handle == "*" || $Handle == "" } {
    if { $ret != "" } { return -code return }
    return 0
  }
  session export -exact CmdChannel
  if { $CmdChannel == "*" || $CmdChannel == "" } {
    set_ [::matchattr $Handle $CmdAccess]
  } {
    set_ [::matchattr $Handle $CmdAccess $CmdChannel]
  }
  if { !$_ } {
    if { $ret != "" } { return -code return }
    return 0
  }
  if { [session set CmdEvent] == "dcc" || ![session set CmdNeedAuth] } { return 1 }
  if { ![authcheck -nick $Nick $Handle] } {
    if { $ret ne "" } { return -code return }
    return 0
  }
  # TODO: join in one string without temp-vars & with [string compare]
  session export -exact Nick
  if { [set_ [getuser $Handle XTRA AUTH_NICK]] != $Nick } {
    reply -private -- [::ck::frm auth.nick] $_
    if { $ret != "" } { return -code return }
    return 0
  }
  return 1
}
proc ::ck::cmd::prossed_cmd { CmdEvent Nick UserHost Handle Channel Text CmdId {CmdDCC ""} } {
  variable cmds
  array set tcmd $cmds($CmdId)

  set CmdAccess   $tcmd(access)
  set CmdNeedAuth $tcmd(auth)
  set CmdChannel  $Channel
  set StdArgs [split [string stripspace [string stripcolor $Text]] { }]
  set CmdReturn  [list]
  set CmdConfig   $tcmd(config)

  session create -proc $tcmd(bind)
  session import -grab tcmd(namespace) as CmdNamespace \
    -grablist [list CmdEvent Text Handle CmdId StdArgs CmdDCC Channel CmdAccess CmdNeedAuth CmdChannel \
      Nick UserHost CmdReturn CmdConfig]
#  session hook !onDestroy end_of_cmd
  if { ![checkaccess] } {
    session destroy
  } elseif { [llength $StdArgs] < 2 && $tcmd(autousage) } {
    catch { replydoc $tcmd(doc) }
    session destroy
  } else {
    session event CmdPass
  }
}
#proc ::ck::cmd::end_of_cmd { sid } {
#  session export -exact CmdReturn CmdId
#  debug -debug "Return value: %s" $CmdReturn
#  switch -- [lindex $CmdReturn 0] {
#    "ERR_SYNTAX" {
#      if { [llength $CmdReturn] == 1 } {
#	if { [set frm [list [getfrm "Usage"]]] == "" } {
#	  set frm [list [::ck::frm default.usage] $CmdId]
#	}
#      } {
#	set frm [lrange $CmdReturn 1 end]
#      }
#      eval [concat reply -- $frm]
#    }
#    "ERR_INTERNAL" {
#      if { [llength $CmdReturn] == 1 } {
#	debug -error "Error while executing bind-proc for <%s>."
#      } {
#        debug -error "Error while executing bind-proc for <%s>: %s" $CmdId [lindex $CmdReturn 1]
#	foreach _ [split [lindex $CmdReturn 2] "\n"] {
#	  debug -error- "  $_"
#	}
#      }
#    }
#  }
#}
proc ::ck::cmd::replydoc { args } {
  upvar sid sid

  set doc [lindex $args 0]
  debug "Reply with doc: $doc"
  return -code return
}
proc ::ck::cmd::reply { args } {
  upvar sid sid

  getargs \
    -noperson flag \
    -return flag \
    -private flag \
    -err flag \
    -broadcast flag \
    -doc str "" \
    -uniq flag \
    -multi int 1

  if { $(doc) ne "" } {
    catch { replydoc $(doc) }
    return -code return
  }
  if { $(err) } {
    if { [llength $args] } {
      set frm [lindex $args 0]
      if { [getfrm "err.$frm"] ne "" } {
	set args [concat [list "err.$frm"] [lrange $args 1 end]]
      }
    } {
      set args [list "err"]
    }
  }
  set txt  [eval [concat cformat $args]]
  set txt  [stripMAGIC $txt]
  session export -exact CmdEvent CmdConfig
  if { $CmdEvent == "pub" && !$(noperson) && !$(private) } {
    if { [set frm [getfrm "Reply"]] == "" } {
      set frm [::ck::frm default.reply]
    }
    set frm [stripMAGIC [cformat $frm [session set Nick]]]
    set txt "$frm$txt"
  }
  set mode [::ck::config::config get ".${CmdConfig}.msgmode"]
#  debug "xxx: $txt"
  switch -- $CmdEvent {
    "msg" {
      set txt [::ck::colors::cformat $txt]
#      set txt [string range $txt 0 300]
      put$mode "PRIVMSG [session set Nick] :$txt"
#      debug -debug "put$mode \"PRIVMSG [session set Nick] :$txt\""
    }
    "pub" {
      set txt [::ck::colors::cformat $txt]
#      set txt [string range $txt 0 300]
      if { $(private) } {
        put$mode "NOTICE [session set Nick] :$txt"
      } {
	if { $(broadcast) } {
	  set chans [cmdchans [session set CmdId]]
	  if { [::ck::config::config get "pub.multitarget"] } {
	    put$mode "PRIVMSG [join $chans {,}] :$txt"
	  } {
	    foreach_ $chans {
	      put$mode "PRIVMSG $_ :$txt"
	    }
	  }
	} {
#	  debug "yyy: PRIVMSG [session set Channel] :$txt"
#	  debug -debug "put$mode \"PRIVMSG [session set Channel] :$txt\""
	  put$mode "PRIVMSG [session set Channel] :$txt"
	}
      }
    }
    "dcc" {
      set txt [::ck::colors::cformat $txt]
      putidx [session set CmdDCC] $txt
    }
  }
  if { $(return) || $(err) } {
    return -code return
  }
}
proc ::ck::cmd::pubm { n uh h tg t } {
  fixenc n uh h tg t
  if { [applyfilter pub $tg] } { return }
  if { [set cmdid [searchcmd t pub $tg]] == "" } return
  prossed_cmd pub $n $uh $h $tg $t $cmdid
  return 1
}
proc ::ck::cmd::msgm { n uh h t } {
  fixenc n uh h t
  if { [set cmdid [searchcmd t msg]] == "" } return
  prossed_cmd msg $n $uh $h "*" $t $cmdid
  return 1
}
proc ::ck::cmd::filt { i t } {
#  set tt $t
#  debug "dcctext:%s:%s:" [string length $t] [string bytelength $t]
  set enc [::getuser [::idx2hand $i] XTRA _ck.self.cp.patyline]
  if { $enc eq "" || [string length $enc] == 1 } {
    fixenc t
  } {
    if { [info exists ::sp_version] } {
      set t [encoding convertto $t]
      set t [encoding convertfrom [string range $enc 1 end] $t]
    } {
      if { [string length $t] == [string bytelength $t] } {
	set t [encoding convertfrom [string range $enc 1 end] $t]
      }
    }
#    set t [encoding convertfrom identity $t]
#    putlog $t
#    debug "alen: %s %s" [string length $t] [string bytelength $t]
#    debug "alen: %s %s" [string length $t] [string bytelength $t]
#    debug "enc: [string range $enc 1 end] ! %s" $t
  }
  if { [set cmdid [searchcmd t dcc]] == "" } {
#    debug "len: %s %s" [string length $t] [string bytelength $t]
#    set t [encoding convertto cp1251 $t]
#    debug "len: %s %s" [string length $tt] [string bytelength $tt]
#    set tt [encoding convertfrom cp1251 $tt]
#    debug "len: %s %s" [string length $tt] [string bytelength $tt]
#    set tt [encoding convertto cp1251 $tt]
#    debug "len: %s %s" [string length $tt] [string bytelength $tt]
#    set tt [encoding convertfrom identity $tt]
#    debug "len: %s %s" [string length $tt] [string bytelength $tt]
#    return [encoding convertto cp1251 $t]
#    debug "len: %s %s" [string length $tt] [string bytelength $tt]
#    return [encoding convertto cp1251 [encoding convertfrom cp1251 $tt]]
#    return $t
#    return [encoding convertto cp1251 $t]
#    debug "len: %s %s" [string length $t] [string bytelength $t]
    if { [info exists ::sp_version] } { return $t }
    backenc t
#    set t [encoding convertto cp1251 $t]
#    debug "len: %s %s" [string length $t] [string bytelength $t]
    return [encoding convertfrom identity $t]
#    return $t
  }
  set uh "-telnet@"
  foreach_ [dcclist] {
    if { [lindex $_ 0] == $i } {
      append uh [lindex [split [lindex $_ 2] "@"] end]
      set n [lindex $_ 1]
      break
    }
  }
  prossed_cmd dcc $n $uh $n [lindex [console $i] 0] $t $cmdid $i
  return ""
}
proc ::ck::cmd::getfrm { afrm {defs ""}} {
  upvar sid sid
  session export -exact CmdNamespace CmdId
  if { [info exists "${CmdNamespace}::__msgfrm\($CmdId.[list $afrm]\)"] } {
    return [set "${CmdNamespace}::__msgfrm\($CmdId.[list $afrm]\)"]
  } elseif { [info exists "${CmdNamespace}::__msgfrm\([list $afrm]\)"] } {
    return [set "${CmdNamespace}::__msgfrm\([list $afrm]\)"]
  } elseif { $defs == "-" } {
    return [stripMAGIC $afrm]
  }
  return $defs
}
proc ::ck::cmd::cformat { args } {
  upvar sid sid
  set frm [getfrm [lindex $args 0] -]
  if { [llength $args] > 1 } {
    set xargs [list]
    foreach_ [lrange $args 1 end] {
      lappend xargs [stripMAGIC $_ 1]
    }
    if { [catch [concat [list format $frm] $xargs] errStr] } {
      debug -error "Format failed: %s" $errStr
      debug -error- "  format: %s" $frm
      debug -error- "  args  : %s" $xargs
      set frm "#error#"
    } {
      set frm $errStr
    }
  }
  return [MAGIC $frm]
}
proc ::ck::cmd::cjoin { list frm } {
  upvar sid sid
  set frm [getfrm $frm -]
  set xlist [list]
  foreach_ $list {
    lappend xlist [stripMAGIC $_ 1]
  }
  return [MAGIC [join $xlist $frm]]
}
proc ::ck::cmd::MAGIC { str } {
  variable MAGIC
  return "$MAGIC$str"
}
proc ::ck::cmd::cmark { str } {
  variable MAGIC
  return "$MAGIC$str"
}
proc ::ck::cmd::stripMAGIC { str {esc 0}} {
  variable MAGIC
  variable MAGIClength
  if { [string equal -length $MAGIClength $MAGIC $str] } {
    return [string range $str $MAGIClength end]
  } elseif { $esc != "0" } {
    return [string map [list {&} {&&}] $str]
  }
  return $str
}
proc ::ck::cmd::cquote { str } {
  return [string map [list {&} {&&}] $str]
}
proc ::ck::cmd::cmdchans { cmdid } {
  variable cmds

  array set tcmd $cmds($cmdid)
  set chans [channels]
  set deny [::ck::config::get ".$tcmd(config).chandeny"]
  set allow [::ck::config::get ".$tcmd(config).chanallow"]
  set chans [lfilter -nocase -- $chans $deny]
  set chans [lfilter -nocase -keep -- $chans $allow]
  return $chans
}
proc ::ck::cmd::cmd_checkchan { cmdid chan } {
  variable cmds
  array set tcmd $cmds($cmdid)
#  debug "check for chan %s" $chan
  foreach_ [::ck::config::get ".$tcmd(config).chandeny"] {
    if { [string match -nocase $_ $chan] } {
#      debug "matched by deny mask: %s" $_
      return 0
    }
  }
  foreach_ [::ck::config::get ".$tcmd(config).chanallow"] {
    if { [string match -nocase $_ $chan] } {
#      debug "matched by allow mask: %s" $_
      return 1
    }
  }
#  debug "default - disable."
  return 0
}

#proc ::ck::cmd::confvar {param id} {
#  set fld [cmdvar config $id]
#  return [::ck::config::get "${fld}.$param"]
#}
#
#proc ::ck::cmd::cmdvar {param id} {
#  variable cmds
#  array set tcmd $cmds($id)
#  return $tcmd($param)
#}
#
#proc ::ck::cmd::reply {args} {
#  variable cmds
#
#  upvar state state
#  if { ![info exists state] } {
#    moderror "Called from <[info level -1]> without <state>."
#    return
#  }
#  set repl [lindex $args 0]
#  if { [frmexists $repl] } {
#    set repl [eval "xformat $args"]
#  } {
#    set repl [cformat $repl]
#  }
#  rollstate
#
#  if { [confvar nocolors $cmd] } { set repl [string stripcolor $repl] }
#  set mmode [confvar msgmode $cmd]
#
#  if { $type == "pub" } {
#    if { [confvar notice $cmd] } {
#      put$mmode "NOTICE $n :$repl"
#    } {
#      put$mmode "PRIVMSG $tg :$repl"
#    }
#  } elseif { $type == "msg" } {
#    put$mmode "PRIVMSG $n :$repl"
#  } elseif { $type == "dcc" } {
#    putidx $tg $repl
#  }
#}
#
#proc ::ck::cmd::xformat {args} {
#  upvar state state
#  if { ![info exists state] } {
#    moderror "Called from <[info level -1]> without <state>."
#    return
#  }
#  set repl [cformat [frm [lindex $args 0]]]
#  if { [llength $args] > 1 } {
#    if { [catch {set end [eval "format \$repl [lrange $args 1 end]"]} errstr] } {
#      moderror "failed format reply."
#      moderror "reason: $errstr"
#      moderror "format: $repl"
#      moderror "args  : [lrange $args 1 end]"
#      moderror "end of error report."
#      set end "#error#"
#    }
#    set repl $end
#  }
#  return $repl
#}
#
#
#proc ::ck::cmd::log {state} {
#  rollstate
#  if { $type == "pub" } {
#    putlog "pub\(${chan}/${nick}\) :${cmd}: $t"
#  } elseif { $type == "msg" } {
#    putlog "msg\(${nick}!${uhost}\) :${cmd}: $t"
#  } elseif { $type == "dcc" } {
#    putlog "dcc\(${nick}\) :${cmd}: $t"
#  }
#}
#
#proc ::ck::cmd::frm {lid {gid ""}} {
#  upvar state state
#  if { $gid == "" } {
#    if { ![info exists state] } {
#      moderror "Phrase not found, state is not sets. \($lid\)"
#      return "#error#"
#    }
#    rollstate
#    set gid $cmd
#  }
#  return [::ck::frm $lid $gid]
#}
#
#proc ::ck::cmd::frmexists {lid {gid ""}} {
#  upvar state state
#  if { $gid == "" } {
#    if { ![info exists state] } {
#      moderror "Phrase not found, state is not sets. \($lid\)"
#      return "#error#"
#    }
#    rollstate
#    set gid $cmd
#  }
#  return [::ck::frmexists $lid $gid]
#}
#
#proc ::ck::cmd::checkaccess {needflag {ostate ""}} {
#
#  if { $needflag == "" } { return 1 }
#
#  if { $ostate == "" } {
#    upvar "state" state
#    rollstate
#  } {
#    rollstate ostate
#  }
#
#  if { $handle == "*" } { return 0 }
#
#  if { $type != "dcc" && ![authcheck $handle $nick] } {
#    return 0
#  }
#
#  if { [set pos [string first "|" $needflag]] != -1 } {
#    set needflag [split $needflag "|"]
#    set flocal   [lindex $needflag 1]
#    set fglobal  [lindex $needflag 0]
#  } {
#    set flocal  ""
#    set fglobal $needflag
#  }
#
#  if { $fglobal != "" } {
#    set test [chattr $handle]
#    if { $test == "-" || $test == "*" } { return 0 }
#    foreach xflag [split $fglobal ""] {
#      if { [string first $xflag $test] == -1 } { return 0 }
#    }
#    return 1
#  }
#
#  if { $flocal != "" } {
#    if { $chan == "" || $chan == "*" || $chan == "-" } { return 0 }
#    set test [lindex [split [chattr $handle $chan] "|"] 1]
#    if { $test == "" || $test == "-" || $test == "*" } { return 0 }
#    foreach xflag [split $flocal ""] {
#      if { [string first $xflag $test] == -1 } { return 0 }
#    }
#  }
#  return 1
#}

#### Config Checks

proc ::ck::cmd::cfg_resetbinds { args } {
  if { ![string equal -length 3 [lindex $args 0] "set"] } return
  array init ::ck::cmd::bindmask
  return
}

proc ::ck::cmd::cfg_msgmode { mode var oldv newv hand } {
  if { ![string equal -length 3 $mode "set"] || \
    [lexists "fast quick serv help" $newv] } return
  return [list 2 "MsgMode must be one of <fast>, <quick>, <serv> or <help>."]
}
