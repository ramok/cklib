
::ck::require colors 0.2

namespace eval ::ck::eggdrop {
  variable version 0.2
  variable cmds [list]
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
  if { [catch {set enc [::getuser [::idx2hand $idx] XTRA _ck.self.cp.patyline]}] || $enc eq "" || [string length $enc] == 1 } {
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
namespace eval ::ck::eggdrop {
  makeproc getuser setuser channels channel onchan passwdok chattr \
    userlist getchanhost chanlist \
    putserv puthelp \
    dcclist console matchattr \
    unames modules traffic \
    idx2hand \
    bots botlist
  lappend cmds putidx putfast putquick idx2flags idx2host \
    putserv puthelp
  namespace export idx2* putidx putfast putquick putserv puthelp
  namespace import -force ::ck::*
  namespace import -force ::ck::colors::color
}
