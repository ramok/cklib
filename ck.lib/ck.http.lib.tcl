
::ck::require config
::ck::require sessions 0.3

namespace eval ::ck::http {
  variable version 0.6
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
  set HttpCommand  "socket"
  set HttpTlsPakage [catch {package require tls}]

  session create -child -proc ::ck::http::make_request \
    -parent-event HttpResponse -parent-mark $(mark)
  session export -grab Http*
  if { $(return) } { return -code return }
}
proc ::ck::http::make_request { sid } {
  session import -exact HttpUrl HttpRequest HttpQuery HttpProxyPort HttpProxyHost HttpCommand HttpTlsPakage

  if { ![regexp -nocase {^([a-z]+://)?([^@/#?]+@)?([^:/#?]+)(:\d+)?(/[^#]+?)?} $HttpUrl - proto user host port path] } {
    debug -err "Error parse url: %s" $HttpUrl
    session return HttpStatus -900 HttpError "Error while parse url."
  }
  if { $proto ne "" && ([set proto [string tolower $proto]] ne "http://" && !($HttpTlsPakage == 0 && $proto eq "https://")) } {
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

  if { $proto eq "https://"} {
  	set HttpCommand "::tls::socket"
    session export -grab HttpCommand
  } elseif {[string is space $proto]} {
  	set proto "http://"
  	set HttpUrl "http://$HttpUrl"
  	session export -grab HttpUrl
  }

  if {[regexp -- {[^\x01-\x7f]} $host]} {set host [domain_toascii $host]}

  session insert HttpUrlParse [list $user $host $port $path]

  if { $HttpProxyHost ne "" && $HttpProxyPort ne "" } {
    debug -debug "Setting proxy %s:%s for http request..." $HttpProxyHost $HttpProxyPort
    set host $HttpProxyHost
    set port $HttpProxyPort
  } elseif { $port == "" } {
    set port [expr {[string equal -nocase $proto "https://"]? "443" : "80"}]
  } else {
    set port [string trimleft $port :]
  }

  session insert HttpIntStatus 1
  session insert HttpMeta [list] HttpData ""

  debug -debug "Trying connect to %s:%s" $host $port
  if { [catch {$HttpCommand -async $host $port} HttpSocket] } {
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
  } elseif { [regexp {shift[-_]?ji?s} $enc -] } { set enc "shiftjis"
  } elseif { $enc eq "us-ascii" } { set enc "ascii"
  } elseif { $enc eq "utf8" } { set enc "utf-8"
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
    switch -exact -- [string tolower $k] {
      "content-type" {
        set v [split $v {;}]
	set HttpMetaType [string trim [lindex $v 0]]
	foreach l [lrange $v 1 end] {
	  if { ![regexp -nocase {charset\s*=\s*(\S+)} $l - __] } continue
	  set HttpMetaCharset $__
	  break
	}
      }
      "location" {
            if {[regexp -nocase -- {^https?://} $v]} {
                set HttpMetaLocation $v
            } elseif {[string index $v 0] eq "/"} {
                regexp -nocase -- {^(https?://[^/\?]+)} $HttpUrl -> url
                set HttpMetaLocation "${url}${v}"
            } else {
                set url2 [lindex [split $HttpUrl {?}] 0]
                if {[regexp -nocase -- {^(https?://.+/)} $url2 -> url]} {
                    set HttpMetaLocation "${url}${v}"
                } else {
                    set HttpMetaLocation "${url2}/${v}"
                }
            }
      }
      "set-cookie" {
        set v [split $v {;}]
        set_ [split [lindex $v 0] =]
        lappend HttpMetaCookie [list [lindex_ 0] [join [lrange $_ 1 end] =]]
      }
      "content-length" {
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
	  set line [string trim $line]
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
      if { $HttpRedirCount < $HttpRedirAuto } {
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
        debug -warn "Reached the limit\(%s\) of redirections." $HttpRedirAuto
      }
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

# IDNA implementation by Alexey Shchepin
# http://svn.xmpp.ru/repos/tkabber/trunk/tkabber/idna.tcl
proc ::ck::http::domain_toascii {domain} {
        set domain [string tolower $domain]
        set parts [split $domain "\u002E\u3002\uFF0E\uFF61"]
        set res {}
        foreach p $parts {
                set r [toascii $p]
                lappend res $r
        }
        return [join $res .]
}


proc ::ck::http::toascii {name} {
        # TODO: Steps 2, 3 and 5 from RFC3490


        if {![string is ascii $name]} {
                set name [punycode_encode $name]
                set name "xn--$name"
        }
        return $name
}


proc ::ck::http::punycode_encode {input} {
        set base 36
        set tmin 1
        set tmax 26
        set skew 38
        set damp 700
        set initial_bias 72
        set initial_n 0x80

        set n $initial_n
        set delta 0
        set out 0
        set bias $initial_bias
        set output ""
        set input_length [string length $input]
        set nonbasic {}

        for {set j 0} {$j < $input_length} {incr j} {
                set c [string index $input $j]
                if {[string is ascii $c]} {
                        append output $c
                } else {
                        lappend nonbasic $c
                }
        }


        set nonbasic [lsort -unique $nonbasic]

        set h [set b [string length $output]];

        if {$b > 0} {
                append output -
        }

        while {$h < $input_length} {
                set m [scan [string index $nonbasic 0] %c]
                set nonbasic [lrange $nonbasic 1 end]

                incr delta [expr {($m - $n) * ($h + 1)}]
                set n $m

                for {set j 0} {$j < $input_length} {incr j} {
                        set c [scan [string index $input $j] %c]

                        if {$c < $n} {
                                incr delta
                        } elseif {$c == $n} {
                                for {set q $delta; set k $base} {1} {incr k $base} {
                                        set t [expr {$k <= $bias ? $tmin :
                                                 $k >= $bias + $tmax ? $tmax : $k - $bias}]
                                        if {$q < $t} break;
                                        append output \
                                        [punycode_encode_digit \
                                                [expr {$t + ($q - $t) % ($base - $t)}]]
                                        set q [expr {($q - $t) / ($base - $t)}]
                                }

                                append output [punycode_encode_digit $q]
                                set bias [punycode_adapt \
                                                  $delta [expr {$h + 1}] [expr {$h == $b}]]
                                set delta 0
                                incr h
                        }
                }

                incr delta
                incr n
        }


        return $output;
}


proc ::ck::http::punycode_adapt {delta numpoints firsttime} {
        set base 36
        set tmin 1
        set tmax 26
        set skew 38
        set damp 700

        set delta [expr {$firsttime ? $delta / $damp : $delta >> 1}]
        incr delta [expr {$delta / $numpoints}]

        for {set k 0} {$delta > (($base - $tmin) * $tmax) / 2}  {incr k $base} {
                set delta [expr {$delta / ($base - $tmin)}];
        }

        return [expr {$k + ($base - $tmin + 1) * $delta / ($delta + $skew)}]
}


proc ::ck::http::punycode_encode_digit {d} {
        return [format %c [expr {$d + 22 + 75 * ($d < 26)}]]
}


## end of IDNA procs

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