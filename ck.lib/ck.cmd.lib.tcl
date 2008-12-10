
#TODO: фильры тоже по каналам матчат

::ck::require core 0.3
::ck::require eggdrop  0.2
::ck::require colors   0.4
::ck::require config   0.3
::ck::require auth     0.2
::ck::require sessions 0.3
::ck::require strings  0.6

namespace eval ::ck::cmd {
  variable version 0.9
  variable author  "Chpock <chpock@gmail.com>"

  variable MAGIC "\000:\000"
  variable MAGIClength [string length $MAGIC]

  namespace import -force ::ck::*
  foreach _ $::ck::eggdrop::cmds { namespace export [namespace tail $_] }
  namespace import -force ::ck::config::config
  namespace import -force ::ck::auth::authcheck
  namespace import -force ::ck::sessions::session
  namespace import -force ::ck::files::datafile
  namespace import -force ::ck::colors::color
  namespace export cmd cmdchans cmd_checkchan
  namespace export cformat cjoin cquote cmark rawformat
  namespace export reply replydoc checkaccess
  namespace export debug msgreg uidns getargs etimer fixenc* backenc* min max
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
  variable doc_handler

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
  config register -id "stripcolor" -type list -default [list] \
    -desc "Remove colors-codes from command replys. Format: \[<channel>|msg|dcc\] <color> <bold> <underline> <reverse> <all>" -access "m" \
    -folder "mod.cmd" -hook ::ck::cmd::cfg_stripcolor

  catch { unset doc_handler }
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
#  array set floodctl {}
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
    register       ::ck::cmd::register \
    doc            ::ck::cmd::regdoc \
    regfilter      ::ck::cmd::regfilter \
    regdoc_handler ::ck::cmd::regdoc_handler \
    unregister     ::ck::cmd::unregister \
    invoke         ::ck::cmd::invoke_cmd
}
proc ::ck::cmd::regdoc_handler { aproc } {
  variable doc_handler
  set doc_handler $aproc
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
  set text [string map "~~ \000" $text]
  while { [regexp {^(.*?)~(.+?)~(.*)$} $text - a1 a2 a3] } {
    set a2 [string map [list "&n" "&n&U"] $a2]
    append_ $a1 &U $a2 &U
    set text $a3
  }
  set text [string map "\000 ~" "$_$text"]
  set text [::ck::colors::cformat $text]
  set_ [list $id [lindex $args 0] $text $(author) $(link)]
  set cmddoc($id) $_
  foreach_ $(alias) { set cmddoc($_) [list $_ $_ $id $(author) $(link)] }
}
proc ::ck::cmd::regfilter { fid fproc args } {
  variable filters
  variable bindmask

  getargs \
    -cmd str "" \
    -event choice [list -all -msg -dcc -pub]

  set tflt(proc)  $fproc
  set tflt(id)    $fid
  set tflt(acmd)  $(cmd)
  set tflt(event) [lindex {all msg dcc pub} $(event)]

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
  set tcmd(nolog)       0
  set tcmd(pubbind) [list]
  set tcmd(msgbind) [list]
  set tcmd(dccbind) [list]
  set tcmd(pubmask) [list]
  set tcmd(msgmask) [list]
  set tcmd(dccmask) [list]
  set tcmd(namespace) [uplevel 1 [list namespace current]]

  set frc_pfix [set frc_regexp 0]

  while { [llength $args] > 0 } {
    lpop args cmd
    switch -- $cmd {
      -bind   {
	if { [lpop args mask] != "" } {
	  lappend tcmd(pubbind) $mask $frc_regexp $frc_pfix
	  lappend tcmd(dccbind) $mask $frc_regexp $frc_pfix
	  lappend tcmd(msgbind) $mask $frc_regexp $frc_pfix
	}
      }
      -bindpub - -pubbind { if { [lpop args mask] != "" } { lappend tcmd(pubbind) $mask $frc_regexp $frc_pfix } }
      -bindmsg - -msgbind { if { [lpop args mask] != "" } { lappend tcmd(msgbind) $mask $frc_regexp $frc_pfix } }
      -binddcc - -dccbind { if { [lpop args mask] != "" } { lappend tcmd(dccbind) $mask $frc_regexp $frc_pfix } }
      -mask   {
	if { [lpop args mask] != "" } {
	  lappend tcmd(pubmask) $mask $frc_pfix
	  lappend tcmd(dccmask) $mask $frc_pfix
	  lappend tcmd(msgmask) $mask $frc_pfix
        }
      }
      -maskpub - -pubmask { if { [lpop args mask] != "" } { lappend tcmd(pubmask) $mask $frc_pfix } }
      -maskmsg - -msgmask { if { [lpop args mask] != "" } { lappend tcmd(msgmask) $mask $frc_pfix } }
      -maskdcc - -dccmask { if { [lpop args mask] != "" } { lappend tcmd(dccmask) $mask $frc_pfix } }
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
      -force-regexp { set frc_regexp 1 }
      -force-prefix { set frc_pfix 1 }
      -nolog        { set tcmd(nolog) 1 }
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

  config register -id "stripcolor" -type list -default [list] \
    -desc "Remove colors-codes from command $id replys. Format: \[<channel>|msg|dcc\] <color> <bold> <underline> <reverse> <all>" -access "m" \
    -folder $tcmd(config) -ns $tcmd(namespace) -hook ::ck::cmd::cfg_stripcolor

  config register -id "chanallow" -type list -default "*" \
    -desc "List of channels were command $id is allowed." -access "m" -folder $tcmd(config) -ns $tcmd(namespace) \
    -hook ::ck::cmd::cfg_resetbinds
  config register -id "chandeny" -type list -default "" \
    -desc "List of channels were command $id is forbidden." -access "m" -folder $tcmd(config) -ns $tcmd(namespace) \
    -hook ::ck::cmd::cfg_resetbinds
  config register -id "notice" -type bool -default 0  \
   -desc "Reply command $id to user as notice." -access "m" -folder $tcmd(config) -ns $tcmd(namespace)
  config register -id "pub.noprefix" -type bool -default 1 -hook ::ck::cmd::cfg_resetbinds \
   -desc "Разрешено ли вызывать команду $id без указания префикса команды." -access "m" -folder $tcmd(config) -ns $tcmd(namespace) \
   -disableon [list .mod.cmd.pub.noprefix 0]

  config register -id "msgmode" -type str -default quick \
    -desc "Send-reply mode. Can be <fast>, <quick>, <serv> or <help>." -access "m" -folder $tcmd(config) \
    -ns $tcmd(namespace) -hook ::ck::cmd::cfg_msgmode

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
    array init tflt $larray
    debug $larray
    if { $tflt(event) != "all" && $tflt(event) != $type } continue
    if { $tflt(acmd) ne "" } {
      if { ![info exists cmds($tflt(acmd))] } { debug -debug "Filter ID(%s) is disabled due attached command not exists." $id; continue }
      if { $type eq "pub" && ![cmd_checkchan $tflt(acmd) $target] } {
        debug -debug "Filter ID(%s) is disabled on chan <%s> by attached command."
        continue
      }
    }
    debug -debug "Add filter <%s> for cmd <%s> on <%s@%s>" $id $tflt(acmd) $target $type
    lappend filtres $id $tflt(proc)
  }

  set pfixmask [string escape -regexp [config get "prefix.$type"]]

  debug -debug "Update cmds for <%s/%s>; Prefix: '%s'" $type $target $pfixmask

  foreach {id larray} [array get cmds] {
    array set tcmd $larray
    if { $type eq "pub" } {
      if { ![cmd_checkchan $id $target] } {
        debug -debug "Cmd <%s> is disabled on <%s> due config." $id $target
        continue
      }
      if { $pfixmask ne "" } {
        if { ![config get "pub.noprefix"] || [config get ".$tcmd(config).pub.noprefix"] ne "1" } {
          debug -debug "Pub prefix sticky due config."
        } {
          set opfx $pfixmask
          append pfixmask ?
        }
      }
    }
    foreach {bnd isre isfx} [set "tcmd(${type}bind)"] {
      if { $bnd == "" } continue
      if { [regexp {^(.+?)\|(.+)$} $bnd - a1 a2] } {
	set a3 ""
	set a4 ""
	foreach ch [split $a2 ""] {
          append a3 {(?:}
          if { !$isre && [string first $ch {[]{}()$^?+*|\.}] != -1 } { append a3 \\ }
	  append a3 $ch
	  append a4 {)?}
	}
        if { !$isre } { set a1 [string escape -regexp $a1] }
	set bnd "$a1$a3$a4"
	unset a1 a2 a3 a4
      } elseif { !$isre } {
        set bnd [string escape -regexp $bnd]
      }
      if { $pfixmask ne "" && [info exists opfx] && $isfx } {
        set bnd "^$opfx\(?:$bnd\)(:?\\s|\$)"
        debug -debug "Bind <%s> for cmd <%s> in <%s@%s> (force prefix by cmd init)" $bnd $id $target $type
      } {
        set bnd "^$pfixmask\(?:$bnd\)(:?\\s|\$)"
        debug -debug "Bind <%s> for cmd <%s> in <%s@%s>" $bnd $id $target $type
      }
      lappend bindres $bnd $id
    }
    foreach {mask isfx} [set "tcmd\(${type}mask\)"] {
      if { $mask == "" } continue
      if { $pfixmask ne "" && [info exists opfx] && $isfx } {
        set msk "^$opfx$mask"
        debug -debug "Mask <%s> for cmd <%s> in <%s@%s> (force prefix by cmd init)" $msk $id $target $type
      } {
        set msk "^$pfixmask$mask"
        debug -debug "Mask <%s> for cmd <%s> in <%s@%s>" $msk $id $target $type
      }
      lappend maskres $msk $id
    }
    if { [info exists opfx] } { set pfixmask $opfx; unset opfx }
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
proc ::ck::cmd::applyfilter { CmdEvent {Channel ""} } {
  variable bindmask
  if { ![info exists bindmask([list "filt $CmdEvent $Channel"])] } { updatebinds $CmdEvent $Channel }
  switch -- $CmdEvent {
    msg - pub {
      upvar t Text n Nick uh UserHost h Handle
      set CmdDCC ""
    }
    dcc {
      upvar t Text n Nick uh UserHost n Handle i CmdDCC
    }
  }
  foreach {FilterId fproc} [set bindmask([list "filt $CmdEvent $Channel"])] {
    debug -debug "Apply %s-filter\(%s\) <%s>..." $CmdEvent $Channel $FilterId
    if { [catch [list $fproc] errStr] } {
      debug -err "Error %s-filter\(%s\) with proc <%s>: %s" $CmdEvent $Channel $fproc $errStr
      foreach_ [split $::errorInfo "\n"] {
	debug -err- "  $_"
      }
    }
    debug -debug "Apply %s-filter\(%s\) <%s> finish." $CmdEvent $Channel $FilterId
    if { $Text == "" } {
      debug -debug "Filter nulled Text var. exiting."
      return 1
    }
  }
  return 0
}
proc ::ck::cmd::checkaccess { {ret ""} } {
  upvar sid sid
  session import -exact CmdAccess
  if { $CmdAccess == "-" } { return 1 }
  session import -exact Handle Nick
  if { $Handle == "*" || $Handle == "" } {
    if { $ret != "" } { return -code return }
    return 0
  }
  session import -exact CmdChannel
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
  return 1
}
proc ::ck::cmd::invoke_cmd { args } {
  variable cmds
  getargs \
    -event choice [list "-msg" "-dcc" "-pub" "-custom"] \
    -nick str "" \
    -userhost str "" \
    -handle str "" \
    -channel str "" \
    -text str "" \
    -cmdid str "" \
    -cmddcc str "" \
    -inline flag \
    -mark str ""

  array set tcmd $cmds($(cmdid))

  if { $(inline) } {
    session set CmdConfig $tcmd(config)
    session set CmdId $(cmdid)
    session set CmdNamespace $tcmd(namespace)
    session hook default $tcmd(bind)
    session event CmdPass
    return -code return
  }

  set CmdConfig   $tcmd(config)
  set CmdAccess   $tcmd(access)
  set CmdNeedAuth $tcmd(auth)
  set CmdChannel  $(channel)
  set StdArgs     [split [string stripspace [string stripcolor $(text)]] { }]
  set CmdReturn   [list]
  set CmdEvent    [lindex {msg dcc pub custom} $(event)]

  session create -proc $tcmd(bind)
  session export -grab tcmd(namespace) as CmdNamespace \
    -grab (text) as Text \
    -grab (handle) as Handle \
    -grab (cmdid) as CmdId \
    -grab (cmddcc) as CmdDCC \
    -grab (channel) as Channel \
    -grab (nick) as Nick \
    -grab (userhost) as UserHost \
    -grab (mark) as CmdEventMark \
    -grablist [list CmdEvent StdArgs CmdAccess CmdNeedAuth CmdChannel CmdReturn CmdConfig]
  # на доступ к команде и autousage проверки нет, предполагается что если делается invoke, тогда все проверки уже сделаны
  session event CmdPass
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
  set CmdEventMark ""

  session create -proc $tcmd(bind)
  session export -grab tcmd(namespace) as CmdNamespace \
    -grablist [list CmdEvent Text Handle CmdId StdArgs CmdDCC Channel CmdAccess CmdNeedAuth CmdChannel \
      Nick UserHost CmdReturn CmdConfig CmdEventMark]
  if { ![checkaccess] } {
    cmdlog "noaccess"
    session destroy
  } elseif { [llength $StdArgs] < 2 && $tcmd(autousage) } {
    cmdlog "autousage"
    catch { replydoc $tcmd(doc) }
    session destroy
  } else {
    if { !$tcmd(nolog) } cmdlog
    session event CmdPass
  }
}
proc ::ck::cmd::cmdlog { {status ""} } {
  foreach_ {Nick Channel CmdEvent StdArgs CmdId UserHost} { upvar $_ $_ }
  if { $status ne "" } { set status [format {(%s)} $status] }
  switch -- $CmdEvent {
    "pub" { set m [format {pub(%s/%s) :%s%s: %s} $Channel $Nick $CmdId $status [join $StdArgs { }]] }
    "msg" { set m [format {msg(%s!%s) :%s%s: %s} $Nick $UserHost $CmdId $status [join $StdArgs { }]] }
    "dcc" { set m [format {dcc(%s) :%s%s: %s} $Nick $CmdId $status [join $StdArgs { }]] }
    default { return }
  }
  set rpl [list]
  foreach_ [dcclist CHAT] {
    if { [string first c [lindex [console [set_ [lindex_ 0]]] 1]] == -1 } continue
    lappend rpl $_
    ::console $_ -c
    putidx $_ $m
  }
#  putloglev c ## [stripformat $txt]
  putloglev c ## $m
  foreach_ $rpl { ::console $_ +c }
}
proc ::ck::cmd::replydoc { args } {
  variable doc_handler
  variable cmddoc
  upvar sid sid

  set doc [lindex $args 0]
  if { [info exists doc_handler] } {
    session insert ReplyWithDoc $doc
    if { [catch [list $doc_handler $sid] errStr] } {
      debug -err "while exec doc-handler proc <%s>: %s" $doc_handler $errStr
      foreach_ [split $::errorInfo "\n"] { debug -err- "  $_" }
      debug -debug "Fall back to default doc-handle..."
    } {
      return -code return
    }
  }
  if { ![info exists cmddoc($doc)] } {
    debug -err "Requested doc <%s>, but I don't have this one."
    return -code return
  }
  set stoplist [list $doc]; set_ [lindex $cmddoc($doc) 2]
  while { [info exists cmddoc($_)] } {
    if { [lexists $stoplist [lindex $cmddoc($_) 2]] } break
    lappend stoplist $_
    set_ [lindex $cmddoc($_) 2]
  }
  reply "%s" [cmark [lindex $cmddoc([lindex $stoplist end]) 2]]
  return -code return
}
proc ::ck::cmd::makepfix { cmd isaction targlist } {
  set maxret [set max 510]
  foreach_ $targlist {
    set maxret [min $maxret [expr { $max - [string length [format ":%s %s %s :" $::botname $cmd $_]] }]]
  }
  set pfix [format "%s %s :" $cmd [join $targlist ,]]
  if { $isaction && $cmd eq "PRIVMSG" } {
    append pfix "\001ACTION "; set postfix "\001"
  } else { set postfix "" }
  return [list $pfix [min $maxret [expr { $max - [string length $pfix] }]] $postfix]
}
proc ::ck::cmd::colorstrip { cmdconf txt targtype {targ ""} } {
  upvar sid sid
  foreach cfgpfix [list ".${cmdconf}." ""] {
    array set striparr [stripcolor2array [::ck::config::config get "${cfgpfix}stripcolor"]]
    if { $targtype eq "pub" && [info exists striparr($targ)] } {
      set stripit $striparr($targ)
    } elseif { $targtype ne "pub" && [info exists striparr($targtype)] } {
      set stripit $striparr($targtype)
    } elseif { [info exists striparr()] } {
      set stripit $striparr()
    }
    if { [info exists stripit] } break
  }
  if { ![info exists stripit] } { return $txt }

  foreach_ $stripit {
    switch -glob -- $_ {
      u* { set txt [string stripcolor -und $txt]  }
      b* { set txt [string stripcolor -bol $txt] }
      r* { set txt [string stripcolor -rev $txt] }
      c* { set txt [string stripcolor -col $txt] }
      a* { set txt [string stripcolor $txt] }
    }
  }
  return $txt
}
proc ::ck::cmd::reply { args } {
  upvar sid sid
  session import CmdReplyParam*
  if { [info exists CmdReplyParam] } { set args [concat $CmdReplyParam $args] }
  getargs \
    -noperson flag \
    -return flag \
    -noreturn flag \
    -private flag \
    -err flag \
    -broadcast flag \
    -doc str "" \
    -uniq flag \
    -action flag \
    -bcast-targ list [list] \
    -multi flag \
    -multi-max int 2 \
    -multi-only int -1

  if { $(doc) ne "" } {
    catch { replydoc $(doc) }
    if { $(noreturn) } return { return -code return }
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
  if { $txt eq "" } {
    if { $(return) || (!$(noreturn) && $(err)) } { return -code return } return
  }
  session import -exact CmdEvent CmdConfig CmdId Nick Channel
  if { $CmdEvent == "pub" && !$(noperson) && !$(private) } {
    if { [set frm [getfrm "Reply"]] == "" } {
      set frm [::ck::frm default.reply]
    }
    set frm [stripMAGIC [cformat $frm $Nick]]
    set txt "$frm$txt"
  }
  set mode [::ck::config::config get ".${CmdConfig}.msgmode"]
  if { $mode eq "" } { debug -warn "Unknown put mode for cmd <%s>." $CmdId; set mode "serv" }
  switch -- $CmdEvent {
    "msg" {
      set txt [colorstrip $CmdConfig [::ck::colors::cformat -optcol $txt] msg]
      lassign [makepfix "PRIVMSG" $(action) [list $Nick]] pre width post
      if { $(multi) } {
	foreach txt [color splittext -line $(multi-only) -maxlines $(multi-max) -width $width $txt] {
	  put$mode "$pre$txt$post"
	}
      } {
        put$mode $pre[string range $txt 0 [incr width -1]]$post
      }
    }
    "pub" {
      set txt [::ck::colors::cformat -optcol $txt]
      if { $(private) || [::ck::config::config get ".${CmdConfig}.notice"] eq "1" } {
	lassign [makepfix "NOTICE" $(action) [list $Nick]] pre width post
        set txt [colorstrip $CmdConfig $txt msg]
	if { $(multi) } {
	  foreach txt [color splittext -line $(multi-only) -maxlines $(multi-max) -width $width $txt] {
	    put$mode "$pre$txt$post"
	  }
	} {
	  put$mode $pre[string range $txt 0 [incr width -1]]$post
	}
      } {
	if { $(broadcast) } {
	  if { ![llength $(bcast-targ)] } { set (bcast-targ) [cmdchans $CmdId] }
	  if { [::ck::config::config get "pub.multitarget"] } {
	    lassign [makepfix "PRIVMSG" $(action) $(bcast-targ)] pre width post
	    put$mode $pre[string range $txt 0 [incr width -1]]$post
	  } {
	    foreach_ $(bcast-targ) {
	      lassign [makepfix "PRIVMSG" $(action) [list $_]] pre width post
	      put$mode $pre[string range $txt 0 [incr width -1]]$post
	    }
	  }
	} {
	  lassign [makepfix "PRIVMSG" $(action) [list $Channel]] pre width post
          set txt [colorstrip $CmdConfig $txt pub $Channel]
	  if { $(multi) } {
	    foreach txt [color splittext -line $(multi-only) -maxlines $(multi-max) -width $width $txt] {
	      put$mode "$pre$txt$post"
	    }
	  } {
	    put$mode $pre[string range $txt 0 [incr width -1]]$post
	  }
	}
      }
    }
    "dcc" {
      set txt [colorstrip $CmdConfig [::ck::colors::cformat $txt] dcc]
      putidx [session set CmdDCC] [expr { $(action)?"-${::nick}-> ":"" }]$txt
    }
  }
  if { $(return) || (!$(noreturn) && $(err)) } { return -code return } return
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
  if { [applyfilter msg *] } { return }
  if { [set cmdid [searchcmd t msg]] == "" } return
  prossed_cmd msg $n $uh $h "*" $t $cmdid
  return 1
}
proc ::ck::cmd::filt { i t } {
  set enc [::getuser [::idx2hand $i] XTRA _ck.core.encoding]
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
  }
  set uh "-telnet@"
  foreach_ [dcclist] {
    if { [lindex $_ 0] == $i } {
      append uh [lindex [split [lindex $_ 2] "@"] end]
      set n [lindex $_ 1]
      break
    }
  }
  if { [applyfilter dcc [lindex [console $i] 0]] } { return "" }
  if { [set cmdid [searchcmd t dcc]] == "" } {
    if { [info exists ::sp_version] } { return $t }
    backenc t
    return [encoding convertfrom identity $t]
  }
  prossed_cmd dcc $n $uh $n [lindex [console $i] 0] $t $cmdid $i
  return ""
}
proc ::ck::cmd::getfrm { afrm {defs ""}} {
  upvar sid sid
  session import -exact CmdNamespace CmdId
  if { [info exists "${CmdNamespace}::__msgfrm\($CmdId.[list $afrm]\)"] } {
    return [set "${CmdNamespace}::__msgfrm\($CmdId.[list $afrm]\)"]
  } elseif { [info exists "${CmdNamespace}::__msgfrm\([list $afrm]\)"] } {
    return [set "${CmdNamespace}::__msgfrm\([list $afrm]\)"]
  } elseif { $defs == "-" } {
    return [stripMAGIC $afrm]
  }
  return $defs
}
proc ::ck::cmd::rawformat { frmid } {
  upvar sid sid
  return [getfrm $frmid -]
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
proc ::ck::cmd::stripcolor2array { data } {
  array set ret {}
  set curdest ""
  foreach_ $data {
    switch -glob -- $_  {
      msg - dcc - "#*" { set curdest $_ }
      default { set ret($curdest) $_ }
    }
  }
  return [array get ret]
}

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
proc ::ck::cmd::cfg_stripcolor { mode var oldv newv hand } {
  if { ![string equal -length 3 $mode "set"] } return
  if { $newv ne "" } {
    switch -glob -- [lindex $newv 0] {
      msg - dcc - "#*" { lnext newv dest }
      default { set dest "" }
    }
    set newvparsed [list]
    foreach_ $newv {
      switch -glob -- $_ {
        u* { lappend newvparsed "underline" }
        r* { lappend newvparsed "reverse"   }
        c* { lappend newvparsed "color"     }
        b* { lappend newvparsed "bold"      }
        a* { lappend newvparsed "all"       }
        default {
          return [list 2 "Unknown value \"$_\". Format: \[<channel>|msg|dcc\] <color> <bold> <underline> <reverse> <all>."]
        }
      }
    }
    if { [lexists [set newvparsed [luniq $newvparsed]] all] } { set newvparsed all }
  } {
    set dest ""
    set newvparsed [list]
  }
  array set curarr [stripcolor2array $oldv]
  set curarr($dest) $newvparsed
  set newv [list]
  foreach_ [lsort [array names curarr]] {
    if { $curarr($_) eq "" } continue
    if { $_ ne "" } { lappend newv $_ }
    eval [concat [list lappend newv] $curarr($_)]
  }
  return [list 1 "" $newv]
}
