
::ck::require config 0.2

##todo
# + проверяние раз в 10 минут того что все auth-юзеры находятся в ирке


namespace eval ::ck::auth {
  variable version 0.2

  namespace import -force ::ck::*
  namespace import -force ::ck::config::config
  namespace export authcheck
}

proc ::ck::auth::init {} {

  config register -id "disable" -type bool -default 0 \
    -desc "Disable necessary authorization." -folder "mod.auth"

  foreach b [binds] {
    if { [string match "::ck::auth::*" [lindex $b end]] } {
      unbind [lindex $b 0] [lindex $b 1] [lindex $b 2] [lindex $b 4]
    }
  }

#  bind join - * ::ck::auth::pjoin
#  bind rejn - * ::ck::auth::pjoin
  bind part Q * ::ck::auth::ppart
  bind kick Q * ::ck::auth::pkick
  bind splt Q * ::ck::auth::psplt
  bind sign Q * ::ck::auth::psign
  bind msg  - auth   ::ck::auth::auth
  bind msg  Q deauth ::ck::auth::deauth
  bind nick Q * ::ck::auth::nick

  return 1
}
proc ::ck::auth::auth {nick uhost hand arg} {
  fixenc nick uhost hand arg
  if { $hand == "*" } { return 0 }
  if { [config get disable] } { return 0 }
  set found 0
  foreach n [channels] {
    if { [onchan $nick $n] } {
      set found 1
      break
    }
  }
  if { $found == 0 } { return 0 }
  if { $arg eq "" } {
    putserv "NOTICE $nick :Usage: /msg $::botnick auth <pass>"
    return 0
  }
  if { [getuser $hand XTRA AUTH] == "DEAD" } {
    putserv "NOTICE $nick :Sorry, but you have been disabled from using my commands."
    return 0
  }
  set pass [join [lindex [split $arg] 0]]
  if { [passwdok $hand $pass] } {
    setuser $hand XTRA "AUTH" "1"
    setuser $hand XTRA "AUTH_NICK" $nick
    putcmdlog "<<$nick>> ($uhost) !$hand! AUTH ..."
    chattr $hand +Q
    putserv "NOTICE $nick :Authorization successful."
  } else {
    putserv "NOTICE $nick :Access denied."
  }
  return 0
}
proc ::ck::auth::authcheck { args } {
  if { [config get disable] } { return 1 }
  getargs -nick str "" -nowarn flag
  set hand [lindex $args 0]
  if { $hand eq "*" || $hand eq "" } { return 0 }
  if { [set auth [getuser $hand XTRA "AUTH"]] eq "DEAD" } { return 0 }
  if { $auth eq "" || $auth eq "0" } {
    if { !$(nowarn) && $(nick) ne "" } {
      putquick "NOTICE $(nick) :Authentication require for using my public commands."
    }
    return 0
  }
  if { $(nick) != "" && [set n [getuser $hand XTRA "AUTH_NICK"]] ne $(nick) } {
    putquick "NOTICE $(nick) :You currently authenticated with nick \002$n\002."
    return 0
  }
  return 1
}
proc ::ck::auth::deauth {nick uhost hand arg} {
  fixenc nick uhost hand arg
  if { $hand == "*" } { return 0 }
  if { [config get disable] } { return 0 }
  if { [getuser $hand XTRA AUTH] == "DEAD" } {
    putserv "NOTICE $nick :Sorry, but you have been disabled from using my commands."
    return 0
  }
  setuser $hand XTRA "AUTH" "0"
  chattr $hand -Q
  putcmdlog "<<$nick>> ($uhost) !$hand! DEAUTH"
  putserv "NOTICE $nick :Authentication has been removed."
  return 0
}
proc ::ck::auth::xpart { h n {chan "-"} } {
  fixenc h n chan
  if { [config get disable] } { return 0 }
  if { ![authcheck -nick $n -nowarn $h] } { return 0 }
  if { $chan != "-" } {
    foreach ch [channels] {
      if { $ch != $chan && [onchan $n $ch] } { return 0 }
    }
  }
  putlog "Auto-deauth for \002$h\002."
  setuser $h XTRA "AUTH" "0"
  setuser $h XTRA "AUTH_NICK" ""
  chattr  $h -Q
}
proc ::ck::auth::nick { n uh h c nn } {
  if { [config get disable] } { return 0 }
  fixenc h c nn
  setuser $h XTRA AUTH_NICK $nn
  debug -debug "Authed handle <%s> change nickname from <%s> to <%s>." $h $n $nn
}

proc ::ck::auth::ppart {n uh h c {m ""}} { xpart $h $n $c }
proc ::ck::auth::pkick {n uh h c t r}    { xpart $h $n $c }
proc ::ck::auth::psplt {n uh h c}        { xpart $h $n }
proc ::ck::auth::psign {n uh h c r}      { xpart $h $n }
#proc auth:check { hand {rn ""} } { return [::ck::auth::authcheck $hand $rn] }
