
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

  cache register -nobotnet -nobotnick -ttl 10d -maxrec 30

  msgreg {
    err.http &BОшибка связи с Википедией&K:&R %s
    err.noarticle &BСтатья в Википедии не найдена.
    search    &BWiki поиск%s:&n &U%s
    search.j  "&n, &U"
    search.num1 &K[&R%s-%s&K/&r%s&K]
    search.num0 &K[&R%s-%s&K]
  }
}
proc ::wikipedia::run { sid } {
  session import

  if { $Event == "CmdPass" } {
    set req [join [lrange $StdArgs 1 end] " "]
    set lang "ru"
    if { [regexp {^-?(\w\w)\s+} $req - lang] } { regsub {^-?\w\w\s+} $req {} req }
    regsub -all -- {\s} $req {_} req

    session export -grablist [list "lang" "req"]

    cache makeid $lang $req ""

    if { ![cache get HttpData] } {
      http run "http://${lang}.wikipedia.org/wiki/[string urlencode [encoding convertto utf-8 $req]]" -redirects 5 -return
    }
    set Mark ""
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
      set resultnum [list "?" "?" "?"]
    } {
      set resultnum [list $r1 $r2 $r3]
    }
    if { [lindex $resultnum 1] == [lindex $resultnum 2] } {
      set resultnum [cformat search.num0 [lindex $resultnum 0] [lindex $resultnum 1]]
    } {
      set resultnum [cformat search.num1 [lindex $resultnum 0] [lindex $resultnum 1] [lindex $resultnum 2]]
    }
    # вырезаем сами рерультаты поиска
    regfilter {^.+?<ul>} HttpData
    regfilter {</ul>.+$} HttpData
    set result [list]
    while { [regexp {<li\s+[^>]+>\s*<a\s+[^>]+>([^<]+)</a>(.*)$} $HttpData - _ HttpData] } {
      lappend result $_
    }
    reply -noperson -return -uniq search $resultnum [cjoin $result search.j]
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
