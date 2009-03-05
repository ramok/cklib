
::ck::require config
::ck::require sessions 0.3

namespace eval ::ck::http {
  variable version 0.5
  variable author  "Chpock <chpock@gmail.com>"

  namespace import -force ::ck::*
  namespace import -force ::ck::config::config
  namespace import -force ::ck::sessions::session
  namespace export http charset2encoding
}

proc ::ck::http::init {  } {
  config register -id "proxyhost" -type str -default "" \
    -desc "Default proxy host for http connections" -folder "mod.http"
  config register -id "proxyport" -type str -default "" \
    -desc "Default proxy port for http connections" -folder "mod.http"
  config register -id "useragent" -type str \
    -default "Mozilla/4.75 (X11; U; Linux 2.2.17; i586; Nav)" \
    -desc "Default User-Agent header for http connections" -folder "mod.http"
}
proc ::ck::http::http { args } {
  set c [catch {cmdargs \
    run ::ck::http::run} m]
  return -code $c $m
}
proc ::ck::http::run { HttpUrl args } {
  set sid [uplevel 1 {set sid}]

  getargs \
    -mark str "" \
    -req choice [list "-get" "-post" "-head"] \
    -heads dlist [list] \
    -query dlist [list] \
    -query-codepage str "utf-8" \
    -cookie dlist [list] \
    -cookpack dlist [list] \
    -norecode flag \
    -charset str "cp1251" \
    -forcecharset flag \
    -return flag \
    -redirects int 2 \
    -readlimit int 0 \
    -useragent str [config get ".mod.http.useragent"] \
    -proxyhost str [config get ".mod.http.proxyhost"] \
    -proxyport str [config get ".mod.http.proxyport"]

  if { [llength $(query)] } {
    set query [list]
    foreachkv $(query) {
      lappend query "[string urlencode [encoding convertto $(query-codepage) $k]]=[string urlencode [encoding convertto $(query-codepage) $v]]"
    }
    set HttpQuery [join $query "&"]
  } {
    set HttpQuery ""
  }

#  if { $(req) == 0 && [llength $(query)] } {
#    set query [list]
#    foreachkv $(query) {
#      lappend query "[string urlencode [encoding convertto $(query-codepage) $k]]=[string urlencode [encoding convertto $(query-codepage) $v]]"
#    }
#    append HttpUrl "?" [join $query "&"]
#    set (query) [list]
#  }

  set HttpUserAgent  $(useragent)
  set HttpProxyHost  $(proxyhost)
  set HttpProxyPort  $(proxyport)
#  set HttpProxyHost  ""
#  set HttpProxyPort  ""
  set HttpCookie     $(cookie)
  set HttpCookPack   $(cookpack)
  set HttpHeads      $(heads)
  set HttpRequest    $(req)
#  set HttpQuery      $(query)
  set HttpRedirCount 0
  set HttpRedirAuto  $(redirects)
  set HttpNoRecode   $(norecode)
  set HttpDefaultCP  $(charset)
  set HttpDefaultForceCP $(forcecharset)
  set HttpReadLimit  $(readlimit)

  session create -child -proc ::ck::http::make_request \
    -parent-event HttpResponse -parent-mark $(mark)
  session export -grab Http*
  if { $(return) } { return -code return }
}
proc ::ck::http::make_request { sid } {
  session import -exact HttpUrl HttpRequest HttpQuery HttpProxyPort HttpProxyHost

  if { ![regexp -nocase {^([a-z]+://)?([^@/#?]+@)?([^:/#?]+)(:\d+)?(/[^#]+?)?} $HttpUrl - proto user host port path] } {
    debug -err "Error parse url: %s" $HttpUrl
    session return HttpStatus -900 HttpError "Error while parse url."
  }
  if { $proto ne "" && ![string equal -nocase $proto "http://"] } {
    debug -err "Protocol <%s> is not supported in url: %s" $proto $HttpUrl
    session return HttpStatus -900 HttpError "Protocol <${proto}> is not supported."
  }
  if { $path == "" } { set path "/" }

  if { $HttpRequest != 1 } {
    if { $HttpQuery ne "" } {
      append path "?" $HttpQuery
    }
  }
  if { $HttpQuery ne "" } {
    append HttpUrl "?" $HttpQuery
    session export -grab HttpUrl
  }

  session insert HttpUrlParse [list $user $host $port $path]

  if { $HttpProxyHost ne "" && $HttpProxyPort ne "" } {
    debug -debug "Setting proxy %s:%s for http request..." $HttpProxyHost $HttpProxyPort
    set host $HttpProxyHost
    set port $HttpProxyPort
  } elseif { $port == "" } {
    set port "80"
  } else {
    set port [string trimleft $port :]
  }

  session insert HttpIntStatus 1
  session insert HttpMeta [list] HttpData ""

  debug -debug "Trying connect to %s:%s" $host $port
  if { [catch {socket -async $host $port} HttpSocket] } {
    session return HttpStatus -100 HttpError $HttpSocket
  }

  session insert HttpSocket $HttpSocket HttpIntStatus 2
  debug -debug "Connection in async mode..."
  session lock

  fconfigure $HttpSocket -blocking 0 -buffering line -encoding utf-8
  fileevent $HttpSocket writable [list ::ck::http::connected $sid]
}
proc ::ck::http::connected { sid } {
  session unlock
  session import -exact HttpSocket

  catch { fileevent $HttpSocket writable {} }
  if { [catch {fconfigure $HttpSocket -peername} errStr] } {
    debug -debug "Connection failed: %s" $errStr
    catch { close $HttpSocket }
    session return HttpStatus -101 HttpError "Connection failed."
  }

  session insert HttpIntStatus 3
  session import -exact HttpUrlParse HttpUserAgent HttpCookie HttpHeads HttpRequest HttpQuery HttpCookPack HttpProxyPort HttpProxyHost HttpUrl

  set Head [list "Accept" "*/*" "Host" [lindex $HttpUrlParse 1] \
    "User-Agent" $HttpUserAgent "Connection" "close"]
#  set Head [list "Accept" "*/*" \
#    "User-Agent" $HttpUserAgent "Connection" "close"]
  array set {} $HttpCookPack
  if { [llength $HttpCookie] } {
    foreachkv $HttpCookie {
      set ([string urlencode $k]) [list [string urlencode $v]]
    }
  }
  if { [array size {}] } {
    set_ [list]
    foreacharray {} {
      lappend_ [join [list $k [lindex $v 0]] =]
    }
    lappend Head "Cookie" [join_ {; }]
  }
  unset {}

#  set _ [list "[lindex {GET POST HEAD} $HttpRequest] http://[join $HttpUrlParse {}] HTTP/1.0"]
  set _ [list "[lindex {GET POST HEAD} $HttpRequest] [expr {$HttpProxyHost ne "" && $HttpProxyPort ne ""?$HttpUrl:[lindex $HttpUrlParse 3]}] HTTP/1.0"]
  if { $HttpRequest == 1 } {
    lappend_ [join [list "Content-Type" "application/x-www-form-urlencoded"] ": "] \
      [join [list "Content-Length" [string length $HttpQuery]] ": "]
  }
  foreachkv [concat $Head $HttpHeads] {
    lappend_ [join [list $k $v] ": "]
  }

  debug -debug "Connected. Trying send headers."
  foreach l $_ { debug -raw "  > %s" $l  }

  lappend_ {}
  set_ [join_ "\n"]
  if { $HttpRequest == 1 } {
    debug -raw "  > (postdata) %s" $HttpQuery
    append_ "\n" $HttpQuery
  } {
    append_ "\n"
  }
  if { [catch {puts -nonewline $HttpSocket $_; flush $HttpSocket} errStr] } {
    debug -debug "Error while sending headers: %s" $errStr
    session return HttpStatus -102 HttpError "Error while make request."
  }

  debug -debug "Headers sended, waiting for data..."
  session lock

  session insert HttpIntStatus 4
  fileevent $HttpSocket readable [list ::ck::http::readable $sid]
}
proc ::ck::http::charset2encoding { enc } {
  set enc [string tolower $enc]
  if { [regexp {^(?:win(?:dows)?|cp)-?(\d+)$} $enc - _] } { set enc "cp$_"
  } elseif { [regexp {iso-?8859-(\d+)} $enc - _] } { set enc "iso8859-$_"
  } elseif { [regexp {iso-?2022-(jp|kr)} $enc - _] } { set enc "iso2022-$_"
  } elseif { [regexp {shift[-_]?js} $enc -] } { set enc "shiftjis"
  } elseif { $enc eq "us-ascii" } { set enc "ascii"
  } elseif { [regexp {(?:iso-?)?lat(?:in)?-?([1-5])} $enc - _] } { if { $_ == 5 } { set _ 9 }; set enc "iso8859-$_" }
  if { [lsearch -exact [string tolower [encoding names]] $enc] != -1 } { return $enc }
  return "binary"
}
proc ::ck::http::parse_headers { sid heads } {
  set HttpMetaType     ""
  set HttpMetaCharset  ""
  set HttpMetaLength   ""
#  set HttpMetaCode     ""
  set HttpMetaLocation ""
  set HttpMetaCookie   [list]
  set HttpMeta         [list]

  session insert HttpStatus -104 HttpError "Error while parse headers."
  
  session import -exact HttpUrl

  set_ [lindex $heads 0]
  debug -debug "Rcvd HTTP reply: %s" $_
  if { ![regexp {^\S+\s+(\d{3})(?:\s+(.+))?$} [lindex $heads 0] - HttpMetaCode HttpMetaMessage] } {
    debug -err "while parse headers: %s" [lindex $heads 0]
    return 0
  }
  debug -raw "Rcvd headers:"
  foreach_ [lrange $heads 1 end] {
    if { ![regexp {^([^:]+):\s+(.+)$} $_ - k v] } continue
    debug -raw "  < %-15s: %s" $k $v
    lappend HttpMeta $k $v
    switch -exact -- $k {
      "Content-Type" {
        set v [split $v {;}]
	set HttpMetaType [string trim [lindex $v 0]]
	foreach l [lrange $v 1 end] {
	  if { ![regexp -nocase {charset\s*=\s*(\S+)} $l - __] } continue
	  set HttpMetaCharset $__
	  break
	}
      }
      "Location" {
            if {[regexp -nocase -- {^https?://} $v]} {
                set HttpMetaLocation $v
            } else {
                regexp -nocase -- {^(https?://[^/\?]+)} $HttpUrl -> url
                set HttpMetaLocation "${url}/[string trimleft $v /]"
            }
      }
      "Set-Cookie" {
        set v [split $v {;}]
        set_ [split [lindex $v 0] =]
        lappend HttpMetaCookie [list [lindex_ 0] [join [lrange $_ 1 end] =]]
      }
      "Content-Length" {
	if { ![string isnum -int -unsig -- $v] } {
	  debug -warn "Bad <Content-Length> filed in headers."
	  continue
	}
	set HttpMetaLength $v
      }
    }
  }
  if { [llength $HttpMetaCookie] } {
    session import -exact HttpCookPack
    array set {} $HttpCookPack
    foreach_ $HttpMetaCookie {
      set ([lindex_ 0]) [list [lindex_ 1]]
    }
    set HttpCookPack [array get {}]
    unset {}
  }
  session export -grab Http*
  debug -debug " HttpMetaType    : %s" $HttpMetaType
  debug -debug " HttpMetaCharset : %s" $HttpMetaCharset
  debug -debug " HttpMetaLength  : %s" $HttpMetaLength
  debug -debug " HttpMetaCode    : %s" $HttpMetaCode
  debug -debug " HttpMetaLocation: %s" $HttpMetaLocation
  debug -debug " HttpMetaCookie  : %s" $HttpMetaCookie

  if { [session set HttpRequest] == 2 } {
    debug -debug "Only headers requested, close connection."
    session insert HttpStatus 0 HttpError ""
    return 0
  }
  if { [string index $HttpMetaCode 0] == "3" } {
    debug -debug "Detected <Redirect> code while parsing headers."
    session insert HttpStatus -1 HttpError "Redirect received."
    return 0
  }
  if { [string index $HttpMetaCode 0] != "2" } {
    debug -debug "Detected <Error\(%s\)> code while parsing headers: %s" $HttpMetaCode $HttpMetaMessage
    session insert HttpStatus -2 HttpError "Server error: $HttpMetaMessage"
    return 0
  }

  session insert HttpStatus 0 HttpError ""
  session import -exact HttpNoRecode HttpDefaultForceCP HttpDefaultCP HttpSocket

  if { $HttpDefaultForceCP } {
    set enc $HttpDefaultCP
  } {
    if { $HttpNoRecode || ![string match -nocase "text*" $HttpMetaType] } {
      set enc "binary"
    } {
      if { $HttpMetaCharset == "" } {
        set enc $HttpDefaultCP
      } {
        set enc $HttpMetaCharset
      }
    }
  }

  if { $enc eq "binary" || [set xenc [charset2encoding $enc]] eq "binary" } {
    debug -debug "Configure socket for rcvd binary data."
    fconfigure $HttpSocket -encoding binary -translation binary
  } {
    debug -debug "Configure socket for rcvd text data with encoding: %s (%s)" $enc $xenc
    fconfigure $HttpSocket -encoding $xenc -translation "auto"
  }

  return 1
}
proc ::ck::http::readable { sid } {
  debug -debug "Call-back for http is prossed..."
  session unlock
  session import -exact HttpSocket HttpData HttpMeta HttpIntStatus HttpReadLimit
  if { $HttpIntStatus == 4 } {
    while { [gets $HttpSocket line] != -1 } {
      if { $line == "" } {
	if { [parse_headers $sid $HttpMeta] } {
	  debug -debug "Headers parsed, downloading body..."
	  session set HttpIntStatus 5
	  break
	} {
	  debug -debug "Headers parsed and no body been download."
	  catch { fileevent $HttpSocket readable {} }
	  catch { close $HttpSocket }
	  handler $sid
	  return
	}
      } {
        lappend HttpMeta $line
      }
    }
  }
  if { $HttpIntStatus == 5 } {
    append HttpData [read $HttpSocket]
    session export -grab HttpData
    if { [eof $HttpSocket] || ($HttpReadLimit && [string length $HttpData] >= $HttpReadLimit) } {
      catch { fileevent $HttpSocket readable {} }
      catch { close $HttpSocket }
      session set HttpIntStatus 6
      handler $sid
      return
    }
  } {
    session insert HttpMeta $HttpMeta
    if { [eof $HttpSocket] } {
      debug -debug "Rcvd EOF while getting headers."
      catch { fileevent $HttpSocket readable {} }
      catch { close $HttpSocket }
      session return HttpStatus -103 HttpError "Connection reset while getting headers."
    }
  }
  debug -debug "Call-back for is done in status <%s>, wait for more data..." $HttpIntStatus
  session lock
}
proc ::ck::http::handler { sid } {
  session import -exact HttpUrl HttpRedirCount HttpRedirAuto HttpMetaLocation HttpMetaCode \
    HttpStatus HttpError HttpRequest
  if { $HttpStatus == -1 } {
    if { $HttpMetaLocation != "" } {
      debug -notice "Recivied redirect to url\(%s\)..." $HttpMetaLocation
      if { $HttpRequest == 1 } {
	set HttpRequest 0
      }
      session insert HttpUrl $HttpMetaLocation \
        HttpRequest 0 \
        HttpQuery "" \
	HttpRequest $HttpRequest \
        HttpRedirCount [expr { $HttpRedirCount + 1 }]
      make_request $sid
      return
    } {
      debug -warn "Recivied redirect header and -redirects option, but don't have location, so no redirect."
    }
  }
  if { $HttpStatus < 0 } {
    debug -warn "Error\(%s\) while requesting: %s" $HttpStatus $HttpError
  } {
    debug -debug "Request for url\(%s\) completed with code <%s>." $HttpUrl $HttpMetaCode
  }
  session return
}

#      set_ [list]
#      foreachkv $HttpMeta {
#	debug -debug "Meta sid\(%s\): %30s = %s" $sid $k $v
#	if { $k == "Set-Cookie" } {
#	  set v [split [lindex [split $v {;}] 0] =]
#          lappend_ [list [lindex $v 0] [join [lrange $v 1 end] =]]
#	} elseif { $k == "Location" } {
#	  session set HttpLocation $v
#	}
#      }
#      if { [llength_] } { session set HttpSetCookie $_ }
