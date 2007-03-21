
encoding system utf-8
::ck::require cmd   0.7
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

  cmd doc -link "wiki.page" "wiki" {~*!wiki* [-номер] [язык] <статья>~ - запрос в Википедию. <номер> - вариант поиска, <язык> - двухбуквенное \
    обозначение языка &K(&nнапример&K: &Ben&n - английский, &Bfr&n - французкий&K).}
  cmd doc -link "wiki" "wiki.page" {~*!wiki* <запрос>~~<номер>~ - вывод части ответа по номеру. Формат запроса - см. команду <wiki>.}

  config register -id "num.search" -type bool -default 0 \
    -desc "Добавлять ли номер результата поиска." -access "m" -folder "wikipedia"
  config register -id "multi.count" -type int -default 1 \
    -desc "Сколько строк выдавать при выводе страницы вики." -access "m" -folder "wikipedia"
  config register -id "extmark" -type bool -default 0 \
    -desc "Помечать ли цветом ссылки на статьи." -access "m" -folder "wikipedia"

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
    mark.page    &B
    mark.new     ""
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
    if { [regexp {^(.*?)~(\d+)$} $req - req WikiPage] } {
      if { [set WikiPage [string trimleft $WikiPage 0]] eq "" } { set WikiPage -1 }
    } {
      set WikiPage -1
    }
    regsub -all -- {\s} $req {_} req

    session export -grablist [list "lang" "req" "sindex" "WikiPage"]

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

  if { [set_ [config get "multi.count"]] < 1 } { set_ 1 }
  session set CmdReplyParam [list "-multi" "-multi-max" $_]

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
  if { [regexp {^\s*<ul>(.*?)</ul>\s*<p>(.*)$} $HttpData - _ HttpData] } {
    # Для некоторых типов статей ("Гандикап")
    set HttpData "$_$HttpData"
  } {
    regfilter -- {.*?<p>} HttpData
  }
  # проверяем существует ли статья
  if { [string first "=\"noarticletext" $HttpData] != -1 } {
    if { $Mark ne "Search" } {
      if { [regexp {<a href="(/wiki/[^/]+:Search/[^"]+)} $HttpData - newurl] } {
        http run "http://${lang}.wikipedia.org$newurl" -redirects 5 -return -mark "Search"
      }
    }
    reply -err noarticle
  }
  # вырезаем трешевые div'ы
  regfilter -all {<div class="notice noprint".*?</div>} HttpData
  regfilter -all {<div class="floatleft".*?</div>} HttpData
  regfilter -all {<div class="notice metadata".*?</div>} HttpData
  regsub -all -- {&#160;} $HttpData { } HttpData
  set extmark [config get "extmark"]
  set nowM [set nowB [set nowU 0]]
  set mark_page [rawformat mark.page]
  set mark_new  [rawformat mark.new]
  html parse -stripspace -stripbadchar \
    -tag {
      if { $_tag eq "b" } {
        append _parsed {&L}
        set nowB $_tag_open
      } elseif { $_tag eq "i" } {
        append _parsed {&U}
        set nowU $_tag_open
      } elseif { $_tag eq "li" && $_tag_open } {
        append _parsed {* }
      } elseif { $extmark && $_tag eq "a" } {
        if { $nowM && !$_tag_open } {
          set nowM 0
          append _parsed {&n}
          if { $nowB } { append _parsed {&L} }
          if { $nowU } { append _parsed {&U} }
        } elseif { !$nowM && $_tag_open } {
          if { $mark_new ne "" && [lsearch -exact [split $_tag_param { }] {class="new"}] != -1 } {
            set nowM 1
            append _parsed $mark_new
          } elseif { $mark_page ne "" && [regexp {href="/wiki/[^:"]+""?} $_tag_param] } {
            set nowM 1
            append _parsed $mark_page
          }
        }
      }
    } \
    -text {
      append _parsed [cquote $_text]
    } \
    -spec {
      append _parsed [cquote $_replace]
    } $HttpData

  if { $WikiPage != -1 } {
    session set CmdReplyParam [list "-multi" "-multi-only" [incr WikiPage -1]]
  }

  reply -uniq -noperson [cmark $_parsed]
}
