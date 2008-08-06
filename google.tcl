
encoding system utf-8
::ck::require cmd   0.6
::ck::require http  0.2
::ck::require cache 0.2

namespace eval ::google {
  variable version 1.1
  variable author "Chpock <chpock@gmail.com>"
  variable lastreq

  namespace import -force ::ck::cmd::*
  namespace import -force ::ck::cache::cache
  namespace import -force ::ck::http::http
  namespace import -force ::ck::strings::html
}

proc ::google::init {  } {
  cmd register google ::google::run -doc "google" -autousage \
    -bind "google" -force-regexp -bind "гуго?ль?"

  cmd doc "google" {~*!google* [номер] [запрос]~ - поиск в www.google.com. Если строка запроса не задана - подразумевается последний заданный.}

  cache register -nobotnet -nobotnick -ttl 1d -maxrec 10

  config register -id "filter" -type bool -default 1 \
    -desc "Позволять ли гуглу фильтровать свои результаты." -access "n" -folder "google"
  config register -id "maxnum" -type int -default 99 \
    -desc "Максимальный номер результата." -access "n" -folder "google"

  msgreg {
    err.http    &BОшибка связи с google.com&K:&R %s
    err.parse   &BОшибка обработки результатов поиска.
    err.nofound &RПо Вашему запросу ничего не найдено.
    err.maxquery &RВы выбрали слишком большой номер ответа.
    maybe        &BВозможно, вы имели в виду:&r %s
    main         %s. &B&U%s&U &K- &R"&r%s&R"&K;&n %s %s
    count        &K(&nВсего: &B%s&K)
  }
}
proc ::google::clear { string } {
  upvar sid sid
  html parse -stripspace -stripbadchar \
    -tag {
      if { $_tag eq "b" } {
	append _parsed {&L}
      } elseif { $_tag eq "i" } {
	append _parsed {&U}
      }
    } \
    -text {
      append _parsed [cquote $_text]
    } \
    -spec {
      append _parsed [cquote $_replace]
    } $string
  return [cmark $_parsed]
}
proc ::google::run { sid } {
  variable lastreq
  session import
  if { $Event eq "CmdPass" } {
    set Text [join [lrange $StdArgs 1 end] { }]
    if { [regexp {^-?(\d+)\s*(.*)$} $Text - QueryNum QueryText] } {
      if { $QueryText eq "" } {
	if { [catch {set lastreq}] } {
	  replydoc google
	} {
	  set QueryText $lastreq
	}
      }
      set QueryNum [string trimleft $QueryNum 0]
      if { $QueryNum eq ""  } { set QueryNum 1 }
    } {
      set QueryNum 1
      set QueryText $Text
    }
    set lastreq $QueryText
    if { $QueryNum > [config get maxnum] } { set QueryNum [config get maxnum] }
    set QueryNumX [expr { $QueryNum - ($QueryNum - 1) % 10 - 1 }]
    cache makeid $QueryText $QueryNumX
    if { ![cache get ParsedData] } {
      session export -grab Query*
      http run "http://www.google.ru/search" -return -charset utf-8 \
        -useragent {Mozilla/4.75 (X11; U; Linux 2.2.17; i586; Nav)} \
        -query [list "q" $QueryText "rls" "ru" "ie" "utf-8" \
	  "oe" "utf-8" start $QueryNumX "filter" [config get filter]]
    }
  } elseif { $Event eq "HttpResponse" } {
    if { $HttpStatus < 0 } {
      reply -err http $HttpError
    }
    cache put [set ParsedData [parse $HttpData]]
  }
  set snum [lindex $ParsedData 0]
  set lnum [lindex $ParsedData 1]
  set onum [lindex $ParsedData 2]
  set mb   [lindex $ParsedData 3]
  set ParsedData [lrange $ParsedData 4 end]
  if { $QueryNum == 1 && $mb ne "" } {
    reply -uniq maybe [clear $mb]
  }
  if { ![llength $ParsedData] } {
    reply -err nofound
  }
  if { $QueryNum > $lnum } {
    reply -err maxquery
  }
  set_ [lindex $ParsedData [expr { $QueryNum - $snum }]]
  if { ![llength_] } {
    reply -err nofound
  }
  debug -debug {Url[%s] Title[%s] Body[%s]} [lindex_ 0] [lindex_ 1] [lindex_ 2]
  reply -uniq -noperson main $QueryNum [lindex_ 0] [clear [lindex_ 1]] [clear [lindex_ 2]] [cformat count $onum]
}
proc ::google::parse { data } {
  regfilter {^.*?</form>} data
  set data [html unspec $data]
  if { ![regexp {<td nowrap align[^>]+?><font[^>]+?>.*?<b>(\d+)</b>.*?<b>(\d+)</b>.*?<b>(.*?)</b>} $data - snum mnum onum] } {
    set mnum [set snum [set onum 0]]
  } {
    regfilter -all {[^0-9,]} onum
  }
  if { ![regexp {<br><font color="#cc0000">[^<]+?</font>\s*<a[^>]+?>(.+?)</a>} $data - mb] } {
    set mb ""
  }
  set_ [list $snum $mnum $onum $mb]
  while { [regexp {<p><a\s[^>]*?href="(http.+?)"[^>]*?>(.+)$} $data - a1 a2] } {
    regexp {^(.+?)</a>(.+?)<br><font(.+)$} $a2 - a2 a3 data
    regfilter {.*?<font[^>]+>} a3
    lappend_ [list $a1 $a2 $a3]
  }
  return $_
}
