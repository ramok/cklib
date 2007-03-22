
::ck::require colors 0.2

namespace eval ::ck::eggdrop {
  variable version 0.3
  variable cmds [list]
}

proc ::ck::eggdrop::init {  } {
  foreach _ [binds ctcp] {
    if { [lindex $_ 2] ne "CHAT" } continue
    eval [linsert [lreplace $_ 3 3] 0 unbind]
  }
  bind ctcp - CHAT ::ck::eggdrop::chat_env
  bind chon - *    ::ck::eggdrop::chat_check
}
proc ::ck::eggdrop::chat_env { 1 2 3 4 5 6 } {
  variable chat_stamp [clock seconds]
  *ctcp:CHAT $1 $2 $3 $4 $5 $6
}
proc ::ck::eggdrop::chat_check { 1 2 } {
  variable chat_stamp
  if { ![info exists chat_stamp] || [clock seconds] - $chat_stamp > 90 } return
  *dcc:fixcodes $1 $2 .
}
proc ::ck::eggdrop::idx2host {idx} {
  foreach rec [dcclist] {
    if { [lindex $rec 0] == $idx } { return [fixencstr [lindex $rec 2]] }
  }
  return ""
}
proc ::ck::eggdrop::idx2flags {idx} {
  foreach rec [dcclist CHAT] {
    if { [lindex $rec 0] == $idx } {
      return [lindex [lindex $rec 4] 2]
    }
  }
}
proc ::ck::eggdrop::putidx {idx txt} {
  if { [string exists "T" [idx2flags $idx]] } {
    set txt [string strongspace [color mirc2ansi $txt]]
  }
  if { [catch {set enc [::getuser [::idx2hand $idx] XTRA _ck.core.encoding]}] || $enc eq "" || [string length $enc] == 1 } {
    ::putidx $idx [backencstr $txt]
  } {
    ::putidx $idx [encoding convertto [string range $enc 1 end] $txt]
  }
}
proc ::ck::eggdrop::makeproc { args } {
  foreach _ $args {
    proc $_ args "
      return \[fixencstr \[eval \[concat ::$_ \[backencstr \$args\]\]\]\]
    "
    lappend ::ck::eggdrop::cmds $_
    namespace export $_
  }
}
proc ::ck::eggdrop::putfast { txt } {
  backenc txt
  append txt "\r\n"
  ::putdccraw 0 [string bytelength $txt] $txt
}
proc ::ck::eggdrop::putquick { txt args } {
#  debug "out:%s:%s:" [string length $txt] [string bytelength $txt]
  backenc txt args
#  debug "after:%s:%s:" [string length $txt] [string bytelength $txt]
  set txt [string range $txt 0 499]
  eval [concat [list ::putquick $txt] $args]
}
proc ::ck::eggdrop::putserv { txt args } {
#  debug "out:%s:%s:" [string length $txt] [string bytelength $txt]
  backenc txt args
#  debug "after:%s:%s:" [string length $txt] [string bytelength $txt]
  set txt [string range $txt 0 499]
  eval [concat [list ::putserv $txt] $args]
}
proc ::ck::eggdrop::puthelp { txt args } {
#  debug "out:%s:%s:" [string length $txt] [string bytelength $txt]
  backenc txt args
#  debug "after:%s:%s:" [string length $txt] [string bytelength $txt]
  set txt [string range $txt 0 499]
  eval [concat [list ::puthelp $txt] $args]
}
proc ::ck::eggdrop::userlevel { hand {chan ""} {chanonly ""} } {
  if { ![validuser $hand] } { return -1 }
  if { $chan eq "" } {
    set flags [chattr $hand]
  } elseif { ![validchan $chan] } {
    return -1
  } else {
    set flags [chattr $hand $chan]
    if { $chanonly ne "" } {
      set flags [lindex [split $flags |] end]
    }
  }
  if { [string first "n" $flags] != -1 } { return 98 }
  if { [string first "m" $flags] != -1 } { return 70 }
  if { [string first "o" $flags] != -1 } { return 50 }
  if { [string first "l" $flags] != -1 } { return 30 }
  if { [string first "f" $flags] != -1 } { return 20 }
  return 0
}
namespace eval ::ck::eggdrop {
  makeproc getuser setuser channels channel onchan passwdok chattr \
    userlist getchanhost chanlist validuser finduser chhandle botattr matchattr adduser \
    addbot deluser delhost addchanrec delchanrec haschanrec getchaninfo setchaninfo  \
    newchanban newban newchanexempt newexempt newchaninvite newinvite stick unstick stickexempt \
    unstickexempt stickinvite unstickinvite killchanban killban killchanexempt kill exempt \
    killchaninvite killinvite ischanjuped isban ispermban isexempt ispermexempt isinvite \
    isperminvite isbansticky isexemptsticky isinvitesticky matchban matchexempt matchinvite banlist \
    exemptlist invitelist newignore killignore ignorelist isignore \
    putserv puthelp \
    dcclist console matchattr \
    unames modules traffic \
    idx2hand \
    bots botlist \
    validchan
  lappend cmds putidx putfast putquick idx2flags idx2host \
    putserv puthelp userlevel
  namespace export idx2* putidx putfast putquick putserv puthelp userlevel
  namespace import -force ::ck::*
  namespace import -force ::ck::colors::color
}
