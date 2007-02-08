
encoding system utf-8
::ck::require cmd   0.4

namespace eval ::ping {
  variable version 1.0
  variable author  "Chpock <chpock@gmail.com>"
  variable lags

  namespace import -force ::ck::cmd::*

proc init {  } {
  cmd register ping ::ping::run \
    -bind "ping" -flood 2:4:90
  cmd register pingme ::ping::run \
    -bind "pingme" -flood 2:4:90 -config "ping"
  cmd register lag ::ping::lag \
    -bind "lag" -flood 1:60 -access "o|o" -config "ping"

  array set ::ping::lags [list]
  array set ::ping::ping [list]

  bind raw  - 421  ::ping::checklag
  bind ctcr - PING ::ping::checkping
  msgreg {
    lag.main &BМой лаг&K:&R %.3f&rс&B.
    err.nochan &RКаналы пинговать запрещено!
    err.nouser &RНик &K<&B%s&K>&R не найден!
    err.timeout &rОтвета на пинг &B%s&r так и не получено.
    ping.self  &cВремя получения от Вас ответа&K:&r %.3f&Rс&c.
    ping.ping  &cВремя ответа от&B %s&K:&r %.3f&Rс&c.
  }
}

proc run { sid } {
  variable ping
  set c [clock clicks -milliseconds]
  session import
  if { $Event eq "CmdPass" } {
    if { $CmdId eq "pingme" || [llength $StdArgs] == 1 } {
      set PingRec $Nick
    } {
      set PingRec [lindex $StdArgs 1]
      if { $PingRec eq "" } {
	replydoc "ping"
      } elseif { [string first [string index $PingRec 0] {#&!+}] != -1 } {
	reply -err nochan
      } elseif { ![onchan $PingRec] } {
	reply -err nouser $PingRec
      }
    }
    if { [info exists ping([string tolower $PingRec])] } {
      debug -debug "Already pinging nick <%s>..." $PingRec
      return
    }
    if { [string equal -nocase $PingRec $::botnick] } {
      session hook default ::ping::lag
      lag $sid
      return
    }
    session set PingNick $PingRec
    session set PingRec [string tolower $PingRec]
    set ping($PingRec) [list $sid [after [min2ms 2] [list session event -sid $sid Timeout]] \
      [set c [clock clicks -milliseconds]]]
    putquick "PRIVMSG $PingNick :\001PING $c\001" -next
    debug -debug "Send request to <%s> at %s ..." $PingNick $c
    session lock
    return
  }
  session unlock
  if { $Event eq "Timeout" } {
    reply -err timeout $PingNick
  } {
    after cancel [lindex $ping($PingRec) 1]
    debug -debug "Got response from <%s> at %s ." $PingNick $c
    set c [expr { 0.001 * ($c - [lindex $ping($PingRec) 2]) }]
    if { [string equal -nocase $Nick $PingRec] } {
      reply ping.self $c
    } {
      reply ping.ping $PingNick $c
    }
  }
  unset ping($PingRec)
}
proc min2ms { num } {
  return [expr { $num * 60 * 1000 }]
}
proc lag { sid } {
  variable lags
  session import
  if { $Event eq "CmdPass" } {
    set clock [clock clicks -milliseconds]
    set lags($clock) [list $sid [after [min2ms 2] [list session event -sid $sid Timeout LagID $clock]]]
    putquick $clock -next
    session lock
    return
  }
  session unlock
  if { $Event eq "Timeout" } {
    debug -err "Time out for lag reply."
  } {
    reply lag.main [expr { 0.001 * ([clock clicks -milliseconds] - $LagID) }]
    after cancel [lindex $lags($LagID) 1]
  }
  unset lags($LagID)
}
proc checklag { f k t } {
  variable lags
  if { ![info exists lags([set c [lindex [split $t] 1]])] } return
  session event -sid [lindex $lags($c) 0] LagReply LagID $c
}
proc checkping { n uh h d k t } {
  variable ping
  fixenc n uh h d k t
  if { $d != $::botnick } return
  if { ![info exists ping([string tolower $n])] } {
    debug -notice "Got unknown ping reply from <%s>: %s" "$n!$uh" $t
  } {
    session event -sid [lindex $ping([string tolower $n]) 0] PingReply PingNick $n
  }
}

}
