
encoding system utf-8
::ck::require cmd   0.2
::ck::require http  0.2
::ck::require cache 0.2

namespace eval ::bashorgru {
  variable version 1.0
  variable author  "Chpock <chpock@gmail.com>"
  variable annonuce

  namespace import -force ::ck::cmd::*
  namespace import -force ::ck::cache::cache
  namespace import -force ::ck::strings::html
  namespace import -force ::ck::http::http
}
proc ::bashorgru::init {} {
  cmd register bashorgru ::bashorgru::run \
    -bind "bash" -bind "баш" -flood 10:60

  cmd doc -link "bash.search" "bash" {~*!bash* [номер]~ - вывод цитаты из bash.org.ru по номеру или случайная цитата.}
  cmd doc -link "bash" "bash.search" {~*!bash* [номер] <фраза>~ - поиск цитаты на bash.org.ru и показать совпадение по номеру.}

  cache register -nobotnet -nobotnick -ttl 1d -maxrec 40

  config register -id "num.to.private" -type int -default 5 \
    -desc "При каком количестве строк в цитате отправлять цитату в приват." -access "n" -folder "bashorgru"
  config register -id "num.max" -type int -default 10 \
    -desc "Максимальное количество строк на фразу." -access "n" -folder "bashorgru"
  config register -id "annon.enable" -type bool -default 0 \
    -desc "Разрешить анонс новых цитат на каналы." -access "n" -folder "bashorgru" -hook chkconfig
  config register -id "annon.update" -type time -default 2h \
    -desc "Интервал времени автоматического апдейта последних изменений." -access "n" -folder "bashorgru" -hook chkconfig \
    -disableon [list "annon.enable" 0]
  config register -id "annon.interval" -type time -default 10m \
    -desc "Интервал анонса новых цитат на каналах." -access "n" -folder "bashorgru" \
    -disableon [list "annon.enable" 0]
  config register -id "annon.chans" -type list -default [list] \
    -desc "Список каналов на которых разрешен анонс новых цитат." -access "n" -folder "bashorgru" \
    -disableon [list "annon.enable" 0]
  config register -id "annon.last" -type int -default 0 \
    -desc "Последняя анонсированая цитата." -access "n" -folder "bashorgru" \
    -disableon [list "annon.enable" 0]
  config register -id "annon.max" -type int -default 30 \
    -desc "Сколько одновременно хранить анонсируемых цитат." -access "n" -folder "bashorgru" \
    -disableon [list "annon.enable" 0]

  msgreg {
    err.parse   &rОшибка обработки &Bbash.org.ru
    err.conn    &rОшибка связи с &Bbash.org.ru
    err.nofound &rПо запросу &K<&B%s&K>&r ничего не найдено.
    err.badnum  &rК сожалению цитата &bN&B%s&r не найдена.
    chanadd  &K/&R%s
    header.search &g.-&G-&K[&n Поиск&K(&p%s&K):&R%s&K/&r%s&n N&B%s%s &K]&G------&g-&G--&g--&K-&g-&K-- -
    header        &g.-&G-&K[&n Цитата N&B%s%s &K]&G------&g-&G--&g--&K-&g-&K-- -
    header.new    &g.-&G-&K[&n Новая цитата N&B%s%s &K]&G------&g-&G--&g--&K-&g-&K-- -
    prequote1     &g|&n %s
    prequote2     &G|&n %s
    tail          &g`-&G----&g-&G--&g--&K-&g-&K----
    tailx         &g`-&G-&K[&cОстальные &B%s&c строк можно прочитать на &B&U%s&U&K ]&G---&g-&G--&g--&K-&g-&K----
    to.private &cЦитата &BN&R%s&c слишком большая &K(&B%s&c строк&K)&c будет отправлена к Вам в приват.
    anon.big &cНовая цитата &BN&R%s&c слишком большая &K(&B%s&c строк&K)&c, посмотреть ее можно по адресу &B&Uhttp://bash.org.ru/quote.php?num=%s&U&c .
  }

  etimer -norestart -interval [config get "annon.update"] "bashorgru.update" ::bashorgru::checkupdate
  etimer -norestart -interval [config get "annon.interval"] "bashorgru.annonuce" ::bashorgru::checkannonuce
}
proc ::bashorgru::run { sid } {
  variable annonuce
  session export
  if { $Event == "CmdPass" } {
    if { $CmdEventMark eq "Annonuce" } {
      if { ![llength annonuce] } { debug -err "No quotes for annonuce."; return }
      lassign [lindex $annonuce end] QuoteNum QuoteData
      set annonuce [lreplace $annonuce end end]
      config set "annon.last" $QuoteNum
    } {
      set QuoteNum [join [lrange $StdArgs 1 end] { }]
      if { $QuoteNum eq "" || [string isnum -int -unsig -- $QuoteNum] } {
	session set QuoteNum [string trimleft $QuoteNum "0"]
	if { $QuoteNum == "" } {
	  http run "http://bash.org.ru/quote.php" -return
	} {
	  http run "http://bash.org.ru/quote.php?num=$QuoteNum" -return
	}
      } {
	if { ![regexp {^-?(\d*)\s*(.+)$} $QuoteNum - SearchNum SearchPhrase] } { replydoc "bash.search" }
	if { $SearchNum < 1 } { set SearchNum 1 }
	session import -grablist [list SearchNum SearchPhrase]
	cache makeid -tolower all -- $SearchPhrase
	if { ![cache get SearchResult] } {
	  http run "http://bash.org.ru/searchresults.php" -query [list "text" $SearchPhrase] -return -query-codepage cp1251
	}
      }
    }
  }
  if { $Event == "HttpResponse" } {
    if { $HttpStatus < 0 } {
      debug -err "Error request page."
      reply -err conn
    }
    set HttpData [parse $HttpData]
    if { [info exists SearchPhrase] } {
      if { ![llength [set SearchResult $HttpData]] } { reply -err nofound $SearchPhrase }
      cache put $SearchResult
    } {
      if { ![llength $HttpData] } {
	debug -err "Error while parse page."
	reply -err parse
      }
      lassign [lindex $HttpData 0] RealQuoteNum QuoteData
      if { $QuoteNum != "" && $QuoteNum != $RealQuoteNum } { reply -err badnum $QuoteNum }
      set QuoteNum $RealQuoteNum
    }
  }
  if { $CmdEventMark eq "Annonuce" } {
    set_ [lfilter -nocase -keep -- [channels] [config get "annon.chans"]]
    if { ![llength_] } {
      debug -err "No channels for annonuce."
      return
    }
    debug -debug "Annonuce chans: %s" [join $_ {, }]
    session set CmdReplyParam [list "-noperson" "-broadcast" "-bcast-targ" $_]
    session set Event "pub"
  } elseif { [info exists SearchResult] } {
    set TotalCount [llength $SearchResult]
    if { $SearchNum > $TotalCount } {
      set SearchNum $TotalCount
    }
    set SearchResult [lindex $SearchResult [expr { $SearchNum - 1 }]]
    set QuoteNum [lindex $SearchResult 0]
    set QuoteData [lindex $SearchResult 1]
  }
  # если первым указан канал
  if { [regexp {(#\S+)<br>} $QuoteData - cadd] } {
    regsub {(#\S+)<br>} $QuoteData {} QuoteData
    set cadd [cformat chanadd $cadd]
  } {
    set cadd ""
  }
  # автоматом переделываем логи аськи
  regsub -all -nocase {(((<br>)|^)\s*\S+\s+\([^\)]+\))<br>([^<]+)} $QuoteData {\1 \4} QuoteData
  # если только 1 слово в строке - джойнить, например если только 'ник:' в строке
  regsub -all -nocase {(((<br>)|^)\s*\S+\s*)<br>([^<]+)} $QuoteData {\1 \4} QuoteData

  set QuoteData [wsplit $QuoteData "<br>"]

  if { [llength $QuoteData] >= [config get "num.to.private"] && $CmdEvent eq "pub" } {
    if { $CmdEventMark eq "Annonuce" } {
      reply -return anon.big $QuoteNum [llength $QuoteData] $QuoteNum
    }
    reply to.private $QuoteNum [llength $QuoteData]
    session set CmdEvent "msg"
  }

  if { $CmdEventMark eq "Annonuce" } {
    reply -noperson header.new $QuoteNum $cadd
  } elseif { [info exists SearchResult] } {
    reply -noperson header.search $SearchPhrase $SearchNum $TotalCount $QuoteNum $cadd
  } else {
    reply -noperson header $QuoteNum $cadd
  }

  set linenum 0
  foreach_ $QuoteData {
    set_ [html untag $_]
    set_ [html unspec $_]
    set_ [string stripspace $_]
    if { $_ == "" } continue
    if { [info exists SearchResult] } {
      set_ [cquote $_]
      set x ""
      set SearchPhrase [string tolower $SearchPhrase]
      while { [set pos [string first $SearchPhrase [string tolower $_]]] != -1 } {
	set endidx [expr { $pos + [string length $SearchPhrase] }]
	append x [string range $_ 0 [expr { ${pos}-1 }]] \
	  {&y&L} [string range $_ $pos [expr { ${endidx} - 1 }]] {&n}
	set_ [string range $_ ${endidx} end]
      }
      set_ [cmark [append x $_]]
    }
    if { [expr rand()] < 0.5 } { set frm "1" } { set frm "2" }
    reply -noperson "prequote$frm" $_
    if { [incr linenum] >= [config get num.max] } {
      reply -noperson -return tailx [expr { [llength $QuoteData] } - $linenum] "http://bash.org.ru/quote.php?num=$QuoteNum"
    }
  }
  reply -noperson tail
}
proc ::bashorgru::parse { HttpData } {
  set_ [list]
  while { [regexp {<a href="\./quote\.php\?num=(\d+)".+?class="dat">[\s\r\n]*(.+)$} $HttpData - a1 a2] } {
    regexp {^(.+?)\s*</td>\s*(.+)$} $a2 - a2 HttpData
    lappend_ [list $a1 $a2]
  }
  return $_
}
proc ::bashorgru::checkannonuce {  } {
  variable annonuce
  if { ![config get "annon.enable"] } return
  if { [info exists annonuce] && [llength $annonuce] } {
    if { ![llength [lfilter -nocase -keep -- [channels] [config get "annon.chans"]]] } {
      debug -err "No channels for annonuce."
    } {
      debug -debug "Invoke annonuce quote N%s" [lindex [lindex $annonuce end] 0]
      cmd invoke -pub -cmdid "bashorgru" -mark "Annonuce"
    }
  } {
    debug -debug "No quotes for annonuce."
  }
}
proc ::bashorgru::checkupdate { {sid ""} } {
  variable annonuce
  if { ![config get "annon.enable"] } return
  if { $sid eq "" } {
    session create -proc ::bashorgru::checkupdate
    debug -debug "Created session for annonuce update."
    session event -return StartUpdate
  }
  session export

  if { $Event eq "StartUpdate" } {
    http run "http://bash.org.ru/" -return
  }

  if { $HttpStatus < 0 } {
    debug -err "while getting last quotes."
    return
  }

  set HttpData [parse $HttpData]

  if { ![llength $HttpData] } {
    debug -err "while parse page with last quotes."
    return
  }

  debug -debug "Got %s last quotes." [llength $HttpData]

  set annonuce [list]

  if { [config get "annon.last"] == 0 } {
    debug -debug "Push last quote to annonuce."
    lappend annonuce [lindex $HttpData 0]
  } {
    set i 0
    foreach_ $HttpData {
      if { [lindex_ 0] > [config get "annon.last"] } {
	lappend annonuce $_
      }
      if { [incr i] >= [config get "annon.max"] } {
	break
	debug -debug "Limit for save annons."
      }
    }
    if { [llength $annonuce] } {
      debug -debug "Pushed %s quotes to annonuce." [llength $annonuce]
    } {
      debug -debug "No new quotes to annonuce."
    }
  }
}
proc ::bashorgru::chkconfig { mode var oldv newv hand } {
  if { ![string equal -length 3 $mode "set"] } return
  if { [string match "*.update" $var] } {
    etimer -interval $newv "bashorgru.update" ::bashorgru::checkupdate
  } elseif { [string match "*.interval" $var] } {
    etimer -interval $newv "bashorgru.annonuce" ::bashorgru::checkannonuce
  } elseif { [string match "*.enable" $var] } {
    config set "annon.last" 0
    if { $newv == 1 } {
      after idle ::bashorgru::checkupdate
    }
  }
  return
}
::bashorgru::init
