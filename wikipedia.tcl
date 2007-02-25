
encoding system utf-8
::ck::require cmd   0.4
::ck::require http  0.2
::ck::require cache 0.2

namespace eval ::wikipedia {
  variable version 1.0
  variable author  "Chpock <chpock@gmail.com>"

  namespace import -force ::ck::cmd::*
  namespace import -force ::ck::cache::cache
  namespace import -force ::ck::strings::html
  namespace import -force ::ck::http::http
}
proc ::wikipedia::init {} {
  cmd register wikipedia ::wikipedia::run -doc "wiki" -autousage \
    -bind "wiki|pedia" -bind "wp" -bind "вики|педия" -flood 10:60

  cmd doc "wiki" {~*!wiki* [язык] <статья>~ - запрос в Википедию. <язык> - двухбуквенное \
    обозначение языка &K(&nнапример&K: &Ben&n - английский, &Bfr&n - французкий&K)}

  config register -id "num.search" -type bool -default 0 \
    -desc "Добавлять ли номер результата поиска." -access "m" -folder "wikipedia"

  cache register -nobotnet -nobotnick -ttl 10d -maxrec 30

  msgreg {
    err.http &BОшибка связи с Википедией&K:&R %s
    err.noarticle &BСтатья в Википедии не найдена.
    err.search    &BWiki поиск&K: &RК сожалению, по вашему запросу не было найдено точных соответствий.
    search    &BWiki поиск%s:&n %s
    search.j  "&n, "
    search.onum1 &K[&R%s-%s&K/&r%s&K]
    search.onum0 &K[&R%s-%s&K]
    search.num0  &U%2$s
    search.num1  %s.&U%s
  }
}
proc ::wikipedia::run { sid } {
  session import

  if { $Event == "CmdPass" } {
    set req [join [lrange $StdArgs 1 end] " "]
    if { [regexp -- {-(\d+)} $req - sindex] } {
      regfilter {\s*-\d+\s*} req
      set sindex [string trimleft $sindex 0]
    } {
      set sindex ""
    }
    if { [regexp {^-?(\w\w)\s+} $req - lang] } { regfilter {^-?\w\w\s+} req } { set lang "ru" }
    regsub -all -- {\s} $req {_} req

    session export -grablist [list "lang" "req" "sindex"]

    cache makeid $lang $req [set Mark "Search"]
    if { ![cache get HttpData] } {
      cache makeid $lang $req [set Mark ""]
      if { ![cache get HttpData] } {
	http run "http://${lang}.wikipedia.org/wiki/[string urlencode [encoding convertto utf-8 $req]]" -redirects 5 -return
      }
    }
  } elseif { $Event == "HttpResponse"}  {
    if { $HttpStatus < 0 } {
      debug -err "::wikipedia:: http return code\(%s\): %s" $HttpStatus $HttpError
      reply -err http $HttpError
    }
    cache makeid $lang $req $Mark
    cache put $HttpData
  }

  regfilter {^.+?<!-- start content -->[\s\r\n]*} HttpData
  regfilter {[\s\r\n]*<!-- end content -->.+$} HttpData
  # выдана ли нам страничка поиска
  if { $Mark eq "Search" && [regexp {<!--\squerying\s[^>]+\s-->(.+)$} $HttpData - HttpData] } {
    if { ![regexp {<strong>\s*\D+(\d+)\D+(\d+)\D+(\d+)\D*</strong>} $HttpData - r1 r2 r3] } {
      reply -err search
    }
    # вырезаем сами рерультаты поиска
    regfilter {^.+?<ul>} HttpData
    regfilter {</ul>.+$} HttpData
    set result [list]
    set resultraw [list]
    set i 0
    while { [regexp {<li\s+[^>]+>\s*<a\s+[^>]+>([^<]+)</a>(.*)$} $HttpData - _ HttpData] } {
      lappend resultraw $_
      lappend result [cformat search.num[config get num.search] [incr i] $_]
    }
    if { $sindex eq "" } {
      if { [set r4 $r2] > [llength $resultraw] } { set r4 [llength $resultraw] }
      if { $r2 == $r3 } {
	set resultnum [cformat search.onum0 $r1 $r4]
      } {
	set resultnum [cformat search.onum1 $r1 $r4 $r3]
      }
      reply -noperson -return -uniq search $resultnum [cjoin $result search.j]
    }
    if { $sindex > [llength $resultraw] } { set sindex [llength $resultraw] }
    set req [lindex $resultraw [incr sindex -1]]
    regsub -all -- {\s} $req {_} req
    session export -grab "req"
    cache makeid $lang $req [set Mark ""]
    if { ![cache get HttpData] } {
      http run "http://${lang}.wikipedia.org/wiki/[string urlencode [encoding convertto utf-8 $req]]" -redirects 5 -return
    }
    regfilter {^.+?<!-- start content -->[\s\r\n]*} HttpData
    regfilter {[\s\r\n]*<!-- end content -->.+$} HttpData
  }
  # удаляем html камменты
  regfilter -all {<!-- .*? -->} HttpData
  # вычищаем таблицы, там левое содержание
  regfilter -all {<table .+?</table>} HttpData
  # вычищаем заголовки
  regfilter -all {<h2>.+?</h2>} HttpData
  regfilter -all {<h3>.+?</h3>} HttpData
  # удаляем навигацию
  regfilter -all {<div [^>]+ class="NavFrame">.+$} HttpData
  # ссылки типа "править"
  regfilter -all {<sup>\[.+?\]</sup>} HttpData
  # ссылки типа сноски
  regfilter -all {<sup[^>]+><a[^>]+>\[\d+\]</a></sup>} HttpData
  # находим первый параграф
  regfilter -- {.*?<p>} HttpData
  # проверяем существует ли статья
  if { [string first "=\"noarticletext" $HttpData] != -1 } {
    if { $Mark ne "Search" } {
      if { [regexp {<a href="(/wiki/[^/]+:Search/[^"]+)} $HttpData - newurl] } {
	http run "http://${lang}.wikipedia.org$newurl" -redirects 5 -return -mark "Search"
      }
    }
    reply -err noarticle
  }
  regsub -all -- {&#160;} $HttpData { } HttpData
  set HttpData [html unspec $HttpData]
  # замена для цветов
  set HttpData [string map [list {&} {&&}] $HttpData]
  regsub -nocase -all -- {</?b>} $HttpData {\&L} HttpData
  regsub -nocase -all -- {</?i>} $HttpData {\&U} HttpData
  # окончательно херим таги
  set HttpData [html untag $HttpData]
  # убираем символы которые наше ircd не видит
  set HttpData [string removeinvalid $HttpData]
  regsub -all -- {[\s\n\r]+} $HttpData { } HttpData

  reply -uniq -noperson [string stripspace $HttpData]
}
