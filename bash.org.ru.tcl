
encoding system utf-8
::ck::require cmd   0.4
::ck::require http  0.2
::ck::require cache 0.2

namespace eval ::bashorgru {
  variable version 1.2
  variable author  "Chpock <chpock@gmail.com>"
  variable annonuce
  variable lastQuote

  namespace import -force ::ck::cmd::*
  namespace import -force ::ck::cache::cache
  namespace import -force ::ck::strings::html
  namespace import -force ::ck::http::http
}
proc ::bashorgru::init {} {
  cmd register bashorgru ::bashorgru::run \
    -bind "bash" -bind "баш" -bind "bash+" -bind "баш+" -flood 10:60

  cmd doc -link [list "bash.search" "bash.last" "bash.chasm" "bash.vote"] "bash" \
    {~*!bash* [номер]~ - вывод цитаты из bash.org.ru по номеру или случайная цитата.}
  cmd doc -link "bash" "bash.search" {~*!bash* [номер] <фраза>~ - поиск цитаты на bash.org.ru и показать совпадение по номеру.}
  cmd doc -link "bash" "bash.last" {~*!bash* [номер] last~ - просмотр последних цитат.}
  cmd doc -link "bash" "bash.chasm" {~*!bash+* [фраза]~ - поиск по бездне. Если <фраза> не задана, выводится случайная цитата из бездны.}
  cmd doc -link "bash" "bash.vote" {~*!bash* [номер]+-~ - голосование за цитату <номер>. Если номер не задан, голосование идет за последнюю цитату.}

  cache register -nobotnet -nobotnick -ttl 12h -maxrec 40

  config register -id "access.vote" -type str -default "o|-" \
    -desc "Флаги необходимые для доступа к голосованию." -access "n" -folder "bashorgru"
  config register -id "num.to.private" -type int -default 5 \
    -desc "При каком количестве строк в цитате отправлять цитату в приват." -access "n" -folder "bashorgru"
  config register -id "num.max" -type int -default 10 \
    -desc "Максимальное количество строк на фразу." -access "n" -folder "bashorgru"
  config register -id "random.rate" -type bool -default 1 \
    -desc "Отбирать для рандома самые рейтинговые цитаты." -access "n" -folder "bashorgru"
  config register -id "annon.enable" -type bool -default 0 \
    -desc "Разрешить анонс новых цитат на каналы." -access "n" -folder "bashorgru" -hook chkconfig
  config register -id "annon.update" -type time -default 2h \
    -desc "Интервал времени автоматического апдейта последних изменений." -access "n" -folder "bashorgru" -hook chkconfig \
    -disableon [list "annon.enable" 0]
  config register -id "annon.interval" -type time -default 10m \
    -desc "Интервал анонса новых цитат на каналах." -access "n" -folder "bashorgru" -hook chkconfig \
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
  config register -id "annon.time" -type str -default "00:00-24:00" \
    -disableon [list "annon.enable" 0] -hook chkconfig -access "n" -folder "bashorgru" \
    -desc "Интервал времени когда разрешено анонсирование новых цитат. Формат - ЧЧ1:ММ1-ЧЧ2:ММ2. Анонс будет разрешен начиная со времени ЧЧ1:ММ1 до ЧЧ2:ММ2."

  msgreg {
    err.parse   &rОшибка обработки &Bbash.org.ru
    err.conn    &rОшибка связи с &Bbash.org.ru
    err.nofound &rПо запросу &K<&B%s&K>&r ничего не найдено.
    err.badnum  &rК сожалению цитата &bN&B%s&r не найдена.
    chanadd  &K/&R%s
    header.chasm  &g.-&G-&K[&n Бездна N&B%s%s &K]&G------&g-&G--&g--&K-&g-&K-- -
    vote          &cУ цитаты &BN&r%s&c рейтинг&K:&R %s
    header.chasm+ &g.-&G-&K[&n Поиск по бездне&K(&p%s&K)&n N&B%s%s &K]&G------&g-&G--&g--&K-&g-&K-- -
    header.search &g.-&G-&K[&n Поиск&K(&p%s&K):&R%s&K/&r%s&n N&B%s%s &K]&G------&g-&G--&g--&K-&g-&K-- -
    header        &g.-&G-&K[&n Цитата N&B%s%s &K]&G------&g-&G--&g--&K-&g-&K-- -
    header.new    &g.-&G-&K[&n Новая цитата N&B%s%s &K]&G------&g-&G--&g--&K-&g-&K-- -
    header.last   &g.-&G-&K[&n Последние цитаты&K:&R%s&K/&r%s&n N&B%s%s &K]&G------&g-&G--&g--&K-&g-&K-- -
    prequote1     &g|&n %s
    prequote2     &G|&n %s
    tail          &g`-&G-&K[&n Рейтинг: &r%s&K;&n Дата: &r%s &K]&G---&g-&G--&g--&K-&g-&K----
    tailx         &g`-&G-&K[&n Рейтинг: &r%s&K;&n Дата: &r%s&K; &cОстальные &B%s&c строк можно прочитать на &B&Uhttp://bash.org.ru/quote/%s&U&K ]&G---&g-&G--&g--&K-&g-&K----
    tailxchasm    &g`-&G-&K[&n Рейтинг: &r%s&K;&n Дата: &r%s&K; &cНе показанно &B%s&c строк&K ]&G---&g-&G--&g--&K-&g-&K----
    to.private &cЦитата &BN&R%s&c слишком большая &K(&B%s&c строк&K)&c будет отправлена к Вам в приват.
    anon.big &cНовая цитата &BN&R%s&c слишком большая &K(&B%s&c строк&K)&c, посмотреть ее можно по адресу &B&Uhttp://bash.org.ru/quote/%s&U&c .
    err.badtime Неверно задан интервал времени. Формат - ЧЧ1:ММ1-ЧЧ2:ММ2.
  }

  etimer -norestart -interval [config get "annon.update"] "bashorgru.update" ::bashorgru::checkupdate
  etimer -norestart -interval [config get "annon.interval"] "bashorgru.annonuce" ::bashorgru::checkannonuce
}
proc ::bashorgru::run { sid } {
  variable annonuce
  variable lastQuote
  session import
  if { $Event == "CmdPass" } {
    session set QuoteVote ""
    if { $CmdEventMark eq "Annonuce" } {
      if { ![llength annonuce] } { debug -err "No quotes for annonuce."; return }
      lassign [lindex $annonuce end] QuoteNum QuoteData QuoteRate QuoteDate
      set annonuce [lreplace $annonuce end end]
      config set "annon.last" $QuoteNum
    } {
      set QuoteNum [join [lrange $StdArgs 1 end] { }]
      session set QuoteChasm [expr { [string index [lindex $StdArgs 0] end] eq "+" }]
      if { $QuoteChasm } {
        session set SearchPhrase $QuoteNum
        http run "http://bash.org.ru/abyss" -return -query [list "text" $SearchPhrase] -query-codepage cp1251
      }
      set_ 0
      if { $QuoteNum eq "" || [set_ [string match {[-+]} $QuoteNum]] || [regexp {^([+-])1$} $QuoteNum - 4] || \
        [regexp {^([-+]?)[nN№]?\s*(\d+)\s*([-+]?)$} $QuoteNum - 1 QuoteNum 3] } {
          if { [info exists 4] } {
            set_ $4
            set QuoteNum ""
          } elseif { $_ } {
            set_ $QuoteNum
            set QuoteNum ""
          } elseif { [info exists 1] } {
            if { $1 ne "" } { set_ $1 } elseif { $3 ne "" } { set_ $3 } else { set_ "" }
          } { set_ "" }
          session set QuoteNum [string trimleft $QuoteNum "0"]
          if { $_ ne "" } {
            session set QuoteVote $_
            if { $QuoteNum eq "" } {
              if { ![info exists lastQuote] } {
                debug -notc "Try to vote on unknown quote."
                return
              }
              session set QuoteNum $lastQuote
            }
            set_ [expr {$QuoteVote eq {+}?{/rulez}:{/sux}}]
            session set CmdAccess [config get access.vote]
            checkaccess -return
          }
          if { $QuoteNum eq "" } {
            http run "http://bash.org.ru/random" -return
          } {
            http run "http://bash.org.ru/quote/$QuoteNum$_" -return
          }
      } {
	if { ![regexp {^-?(\d*)\s*(.+)$} $QuoteNum - SearchNum SearchPhrase] } { replydoc "bash.search" }
	if { $SearchNum < 1 } { set SearchNum 1 }
	if { [string equal -nocase "last" $SearchPhrase] } {
	  set SearchPhrase ""
	}
	session export -grablist [list SearchNum SearchPhrase]
	cache makeid -tolower all -- $SearchPhrase
	if { ![cache get SearchResult] } {
	  if { $SearchPhrase eq "" } {
	    http run "http://bash.org.ru/" -return
	  } {
	    http run "http://bash.org.ru/search" -query [list "text" $SearchPhrase] -return -query-codepage cp1251
	  }
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
      if { !$QuoteChasm } { cache put $HttpData }
    } {
      if { ![llength $HttpData] } {
	debug -err "Error while parse page."
	reply -err parse
      }
      if { $QuoteNum ne "" } {
        lassign [lindex $HttpData 0] RealQuoteNum QuoteData QuoteRate QuoteDate
        if { $QuoteNum != $RealQuoteNum } { reply -err badnum $QuoteNum }
        set QuoteNum $RealQuoteNum
      } elseif { ![config get "random.rate"] } {
        lassign [lindex $HttpData 0] QuoteNum QuoteData QuoteRate QuoteDate
      } {
        set max 0
        foreach_ $HttpData {
          if { [lindex_ 2] > $max || ![info exists QuoteData] } {
            lassign $_ QuoteNum QuoteData QuoteRate QuoteDate
            set max $QuoteRate
          }
        }
      }
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
  } elseif { $QuoteChasm } {
    lassign [lindex $SearchResult 0] QuoteNum QuoteData QuoteRate QuoteDate
  } elseif { [info exists SearchResult] } {
    set TotalCount [llength $SearchResult]
    if { $SearchNum > $TotalCount } {
      set SearchNum $TotalCount
    }
    lassign [set SearchResult [lindex $SearchResult [expr { $SearchNum - 1 }]]] \
      QuoteNum QuoteData QuoteRate QuoteDate
  }
  regsub -all -nocase {<br />} $QuoteData {<br>} QuoteData
  # если первым указан канал
  if { [regexp {^\s*(#\S+)<br>(.*)$} $QuoteData - cadd QuoteData] } {
    set cadd [cformat chanadd $cadd]
  } {
    set cadd ""
  }
  # удаляем мешающий тэг <index>
  regfilter -all -nocase {\s*</?index>\s*} QuoteData
  #удаляем пустые строки
  regsub -all -nocase {<br>(\s*<br>)+} $QuoteData {<br>} QuoteData
  regfilter -nocase {^(\s*(<br>)?\s*)+} QuoteData
  regfilter -nocase {(\s*(<br>)?\s*)+$} QuoteData
  # автоматом переделываем логи аськи
  regsub -all -nocase {(((<br>)|^)\s*[^\s<]+\s+\([^\)]+\))<br>([^<]+)} $QuoteData {\1 \4} QuoteData
  # если только 1 слово в строке - джойнить, например если только 'ник:' в строке
  regsub -all -nocase {(((<br>)|^)\s*[^\s<]+\s*)<br>([^<]+)} $QuoteData {\1 \4} QuoteData
  # логи с 'ник :' в одной строке
  regsub -all -nocase {(((<br>)|^)\s*[^\s<]+\s+:\s*)<br>([^<]+)} $QuoteData {\1 \4} QuoteData

  set QuoteData [wsplit $QuoteData "<br>"]

  if { [llength $QuoteData] >= [config get "num.to.private"] && $CmdEvent eq "pub" } {
    if { $CmdEventMark eq "Annonuce" } {
      reply -return anon.big $QuoteNum [llength $QuoteData] $QuoteNum
    }
    reply to.private $QuoteNum [llength $QuoteData]
    session set CmdEvent "msg"
  }

  set lastQuote $QuoteNum
  if { $QuoteVote ne "" } {
    reply -return vote $QuoteNum $QuoteRate
  } elseif { $CmdEventMark eq "Annonuce" } {
    reply -noperson header.new $QuoteNum $cadd
  } elseif { $QuoteChasm && [string length $SearchPhrase] } {
    reply -noperson header.chasm+ $SearchPhrase $QuoteNum $cadd
  } elseif { $QuoteChasm } {
    reply -noperson header.chasm $QuoteNum $cadd
  } elseif { [info exists SearchResult] } {
    if { [string length $SearchPhrase] } {
      reply -noperson header.search $SearchPhrase $SearchNum $TotalCount $QuoteNum $cadd
    } {
      reply -noperson header.last $SearchNum $TotalCount $QuoteNum $cadd
    }
  } else {
    reply -noperson header $QuoteNum $cadd
  }

  set linenum 0
  foreach_ $QuoteData {
    set_ [html untag $_]
    set_ [html unspec $_]
    set_ [string stripspace $_]
    if { $_ == "" } continue
    if { [info exists SearchResult] && [string length $SearchPhrase] } {
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
    if { [incr linenum] >= [config get num.max] && [set_ [expr { [llength $QuoteData] } - $linenum]] } {
      if { [info exists QuoteChasm] && $QuoteChasm } { reply -noperson -return tailxchasm $QuoteRate $QuoteDate $_ }
      reply -noperson -return tailx $QuoteRate $QuoteDate $_ $QuoteNum
    }
  }
  reply -noperson tail $QuoteRate $QuoteDate
}
proc ::bashorgru::parse { HttpData } {
  set_ [list]
  while { [regexp {<div class="q">\s*<div class="vote">\s*(.*?)</div>\s*<div>(.*?)</div>\s*(.*)$} $HttpData - 1 a2 HttpData] } {
    if { [string first {</form>} $a2] != -1 } continue
    if { ![regexp {^(?:<a href=./quote/[^>]+>)?(\d+)} $1 - a1] } set\ a1\ ?
    if { ![regexp {<span.*?>(.*?)</span>.*?\s+(\S+ \S+ \S+)\s*$} $1 - a3 a4] } { set a3 [set a4 ?] }
    lappend_ [list $a1 $a2 $a3 [set a4 [string trim $a4]]]
    debug -debug "qnum: %s" $a1
    debug -debug "qtxt: %s" $a2
    debug -debug "qscr: %s" $a3
    debug -debug "qdat: %s" $a4
  }
  return $_
}
proc ::bashorgru::checkannonuce { } {
  variable annonuce
  if { ![config get "annon.enable"] } return
  set t1 [string trimleft [join [split [lindex [set_ [split [config get "annon.time"] -]] 0] :] .] 0]
  set t2 [string trimleft [join [split [lindex_ 1] :] .] 0]
  set tc [string trimleft [clock format [clock seconds] -format %H.%M] 0]
  if { ($t1 < $t2 && ($tc < $t1 || $tc > $t2)) || ($tc > $t2 && $tc < $t1) } {
    debug -debug "annonuce disabled this time due config."
    return
  }
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
  session import

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
  if { $mode eq "set" && [string match "*.time" $var] } {
    set check [list]
    if { [llength [set_ [split $newv -]]] == 2 } {
      foreach_ $_ {
        if { [regexp {^([0-1]?\d|2[0-4])$} [lindex [set_ [split_ :]] 0]] } {
          lappend check [expr {[set x [string trimleft [lindex_ 0] 0]] eq ""?0:$x}]
          if { [lindex_ 0] eq "24" || [llength_] == 1 } {
            lappend check 0
          } elseif { ![regexp {^[0-5]?\d$} [lindex_ 1]] } continue {
            lappend check [expr {[set_ [string trimleft [lindex_ 1] 0]] eq ""?0:$_}]
          }
        }
      }
    }
    if { [llength $check] != 4 } { return [list 2 [::ck::frm err.badtime]] }
    return [list 1 "" [eval [concat format {%02u:%02u-%02u:%02u} $check]]]
  }
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
