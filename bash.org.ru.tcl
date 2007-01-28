
encoding system utf-8
::ck::require cmd   0.2
::ck::require http  0.2
::ck::require cache 0.2

namespace eval ::bashorgru {
  variable version 1.0
  variable author  "Chpock <chpock@gmail.com>"

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

  cache register -nobotnet -nobotnick -ttl 10d -maxrec 40

  config register -id "num.to.private" -type int -default 5 \
    -desc "При каком количестве строк в цитате отправлять цитату в приват." -access "n" -folder "bashorgru"
  config register -id "num.max" -type int -default 10 \
    -desc "Максимальное количество строк на фразу." -access "n" -folder "bashorgru"

  msgreg {
    err.parse   &rОшибка обработки &Bbash.org.ru
    err.conn    &rОшибка связи с &Bbash.org.ru
    err.nofound &rПо запросу &K<&B%s&K>&r ничего не найдено.
    err.badnum  &rК сожалению цитата &bN&B%s&r не найдена.
    chanadd  &K/&R%s
    header   &g.-&G-&K[&n Цитата N&B%s%s &K]&G------&g-&G--&g--&K-&g-&K-- -
    prequote1 &g|&n %s
    prequote2 &G|&n %s
    tail     &g`-&G----&g-&G--&g--&K-&g-&K----
    tailx    &g`-&G-&K[&cПродолжение можно прочитать на&B&U %s &U&K]&G---&g-&G--&g--&K-&g-&K----
    header.search &g.-&G-&K[&n Поиск&K(&p%s&K):&R%s&K/&r%s&n N&B%s%s &K]&G------&g-&G--&g--&K-&g-&K-- -
    to.private &cЦитата слишком большая &K(&B%s&c строк&K)&n будет отправлена к Вам в приват.
  }
}
proc ::bashorgru::run { sid } {
  session export

  if { $Event == "CmdPass" } {
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
  if { $Event == "HttpResponse" } {
    if { $HttpStatus < 0 } {
      debug -err "Error request page."
      reply -err conn
    }
    if { [info exists SearchPhrase] } {
      set SearchResult [list]
      while { [regexp {<a href="\./quote\.php\?num=(\d+)".+?class="dat">[\s\r\n]*(.+)$} $HttpData - a1 a2] } {
	regexp {^(.+?)\s*</td>\s*(.+)$} $a2 - a2 HttpData
	lappend SearchResult [list $a1 $a2]
      }
      if { ![llength $SearchResult] } { reply -err nofound $SearchPhrase }
      cache put $SearchResult
    } {
      if { ![regexp \
	{<a href="\./quote\.php\?num=(\d+)".+?class="dat">[\s\r\n]*(.+)$} $HttpData - \
	  RealQuoteNum QuoteData] } {
	    debug -err "Error while parse page."
	    reply -err parse
      }
      regfilter -all {[\s\r\t]*</td>.+$} QuoteData
      if { $QuoteNum != "" && $QuoteNum != $RealQuoteNum } { reply -err badnum $QuoteNum }
      set QuoteNum $RealQuoteNum
    }
  }
  if { [info exists SearchResult] } {
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

  set $QuoteData [wsplit $QuoteData "<br>"]

  if { [llength $QuoteData] >= [config "num.to.private"] && $CmdEvent eq "pub" } {
    reply to.private [llength $QuoteData]
    session set CmdEvent "msg"
  }

  if { [info exists SearchResult] } {
    reply -noperson header.search $SearchPhrase $SearchNum $TotalCount $QuoteNum $cadd
  } {
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
      reply -noperson -return tailx "http://bash.org.ru/quote.php?num=$QuoteNum"
    }
  }
  reply -noperson tail
}
::bashorgru::init
