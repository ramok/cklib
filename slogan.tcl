
encoding system utf-8
::ck::require cmd   0.4
::ck::require http  0.2

namespace eval ::slogan {
  variable version 0.1
  variable author  "Chpock <chpock@gmail.com>"
  variable annonuce

  namespace import -force ::ck::cmd::*
  namespace import -force ::ck::strings::html
  namespace import -force ::ck::http::http
}

proc ::slogan::init {  } {
  cmd register slogan ::slogan::run \
    -bind "слоган" -doc "слоган" -autousage -flood 10:60

  cmd doc "слоган" {~*!слоган* [слово]~ - вывод рекламного слогана для <слова>.}

  msgreg {
    err.conn  &RОшибка связи.
    err.parse &RОшибка обработки результата.
    main      &p%s
    main0     &K'&B%s&K'&p
  }
}

proc ::slogan::run { sid } {
  session import
  if { $Event eq "CmdPass" } {
    set Text [join [lrange $StdArgs 1 end] { }]
    http run "http://slogen.ru/server.php" -query [list "slogan" $Text] -query-codepage utf-8 -return
  }

  if { $HttpStatus < 0 } { reply -err conn }

  if { ![regexp -nocase {<comment encoded="[\%a-fA-F0-9]*[^>]*?>(.*?)</comment>} $HttpData - Slogan] } {
    reply -err parse
  }

  set Slogan [string stripspace [html unspec [html untag $Slogan]]]
  set Slogan [cquote $Slogan]
  set_ ""
  while { [regexp {^(.*?)'([^']+)'(.*)$} $Slogan - pre w Slogan] } {
    append_ $pre [format [::ck::frm main0] $w]
  }
  set_ [cmark [append_ $Slogan]]

  reply -uniq main $_
}
