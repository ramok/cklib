
encoding system utf-8

namespace eval ::ck::ircservices {
  variable version 0.2
  variable author "Chpock <chpock@gmail.com>"
  variable cache

  namespace import -force ::ck::*
  namespace import -force ::ck::config::config
  namespace export nickserv chanserv
}

proc ::ck::ircservices::init {  } {
  variable presets
  variable cache
  foreacharray presets {
    if { [string match -nocase $k $::ck::ircnet] } {
      array set {} $v
      break
    }
  }
  if { ![array exists {}] } { array set {} $presets(default) }
  unset presets

  config register -id "default" -default 1 -desc "Default commands for services." \
    -folder ".mod.ircsv" -type bool -access "n"
  config register -id "chan.aop" -default [list] -desc "List of channels with aop status for bot." \
    -folder ".mod.ircsv" -type list -access "n" -hook updatecache
  config register -id "chan.hop" -default [list] -desc "List of channels with hop status for bot." \
    -folder ".mod.ircsv" -type list -access "n" -hook updatecache
  config register -id "ns.pass" -default "" -desc "Password for NickServ." \
    -folder ".mod.ircsv" -type str -access "n" -hide -hook updatecache

  config register -id "ns.mask" -default $(ns.mask) -desc {Mask (nick!ident@host) of NickServ.} \
    -folder ".mod.ircsv" -type str -access "n" -disableon [list "default" 1] -hook updatecache
  config register -id "cmd.op" -default $(cmd.op) -desc "Command for give OP." \
    -folder ".mod.ircsv" -type str -access "n" -disableon [list "default" 1] -hook updatecache
  config register -id "cmd.ident" -default $(cmd.ident) -desc "Command for identify to NickServ." \
    -folder ".mod.ircsv" -type str -access "n" -disableon [list "default" 1] -hook updatecache
  config register -id "cmd.inviteme" -default $(cmd.inviteme) -desc "Command for invite bot to channel." \
    -folder ".mod.ircsv" -type str -access "n" -disableon [list "default" 1] -hook updatecache
  config register -id "cmd.unbanme" -default $(cmd.unbanme) -desc "Command for unban bot on channel." \
    -folder ".mod.ircsv" -type str -access "n" -disableon [list "default" 1] -hook updatecache
  config register -id "srv.mask" -default $(srv.mask) -desc "Command for unban bot on channel." \
    -folder ".mod.ircsv" -type str -access "n" -disableon [list "default" 1] -hook updatecache

  if { ![array exists cache] } {
    foreach _ {ns.pass chan.hop chan.aop ns.mask cmd.op cmd.ident cmd.inviteme cmd.unbanme srv.mask} {
      set cache($_) [config get $_]
    }
  }

  bind msgm - * ::ck::ircservices::filter
  bind notc - * ::ck::ircservices::filter
  bind evnt - userfile-loaded ::ck::ircservices::checkuserfile

  etimer -interval 3m ::ck::ircservices::checkuserfile
}

proc ::ck::ircservices::nickserv { args } {
  set c [catch {cmdargs \
    ident ::ck::ircservices::ns_ident} m]
  return -code $c $m
}
proc ::ck::ircservices::chanserv { args } {
  set c [catch {cmdargs \
    unbanme  ::ck::ircservices::cs_unbanme \
    inviteme ::ck::ircservices::cs_inviteme \
    opme     ::ck::ircservices::cs_opme \
    op       ::ck::ircservices::cs_op} m]
  return -code $c $m
}
proc ::ck::ircservices::ns_ident {  } {
  variable cache
  if { $cache(ns.pass) eq "" } {
    debug -err "Requested nickserv identify by script, but I don't have password."
  } {
    putquick [string map [list %pass% $cache(ns.pass)] $cache(cmd.ident)] -next
  }
}
proc ::ck::ircservices::cs_unbanme { chan } {
  variable cache
  putquick [string map [list %chan% $chan] $cache(cmd.unbanme)] -next
}
proc ::ck::ircservices::cs_inviteme { chan } {
  variable cache
  putquick [string map [list %chan% $chan] $cache(cmd.inviteme)] -next
}
proc ::ck::ircservices::cs_opme { chan } {
  variable cache
  putquick [string map [list %chan% $chan] $cache(cmd.opme)] -next
}
proc ::ck::ircservices::cs_op { chan nick } {
  variable cache
  putquick [string map [list %chan% $chan %nick% $nick] $cache(cmd.op)] -next
}
proc ::ck::ircservices::filter { n uh h t {d ""} } {
  if { $d ne "" && $d ne $::botnick } return
  variable cache
  if { ![string match -nocase $cache(ns.mask) [fixencstr "${n}!$uh"]] } return
  fixenc t
  if { [string match -nocase {*/msg*nickserv*identify*} $t] } {
    if { $cache(ns.pass) eq "" } {
      debug -err "NickServ request identify by /msg, but I don't have any passwords."
    } {
      debug -info "Try to autoidentify with msg..."
      putquick "PRIVMSG NICKSERV :IDENTIFY $cache(ns.pass)" -next
    }
  } elseif { [string match -nocase {*/nickserv*identify*} $t] } {
    if { $cache(ns.pass) eq "" } {
      debug -err "NickServ request identify by /nickserv, but I don't have any passwords."
    } {
      debug -info "Try to autoidentify with /nickserv..."
      putquick "NICKSERV IDENTIFY $cache(ns.pass)" -next
    }
  } {
    debug -info "NickServ: %s" $t
  }
  return 1
}
proc ::ck::ircservices::updatecache_ { } {
  variable cache
  foreach _ [array names cache] {
    set cache($_) [config get $_]
  }
}
proc ::ck::ircservices::updatecache { args } {
  if { ![string equal -length 3 [lindex $args 0] "set"] } return
  after 1000 ::ck::ircservices::updatecache_
}
proc ::ck::ircservices::checkuserfile { args } {
  if { [llength [userlist n]] } {
    catch { deluser -Services }
    catch {
      adduser -Services $::ck::ircservices::cache(srv.mask)
      chattr -Services "+ef-[chattr -Services]"
    }
  }
}
namespace eval ::ck::ircservices {
  variable presets
  array set presets {
    "default" {
      ns.mask      "NickServ!service@RusNet"
      cmd.op       "CHANSERV OP %chan% %nick%"
      cmd.ident    "NICKSERV IDENTIFY %pass%"
      cmd.inviteme "CHANSERV INVITE %chan%"
      cmd.unbanme  "CHANSERV UNBAN %chan%"
      srv.mask     "*!service@RusNet"
    }
    "uanet*" {
      ns.mask      "NickServ!service@UAnet"
      cmd.op       "CHANSERV OP %chan% %nick%"
      cmd.ident    "NICKSERV IDENTIFY %pass%"
      cmd.inviteme "CHANSERV INVITE %chan%"
      cmd.unbanme  "CHANSERV UNBAN %chan%"
      srv.mask     "*!service@UAnet"
    }
  }
}
