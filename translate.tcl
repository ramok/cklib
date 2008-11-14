
# rewrite from translate.tcl by Twin@RusNet
encoding system utf-8
::ck::require cmd   0.4
::ck::require http  0.2
::ck::require cache 0.2

namespace eval translate {
  variable version 1.1
  variable author "Chpock <chpock@gmail.com>"
  namespace import -force ::ck::cmd::*
  namespace import -force ::ck::cache::cache
  namespace import -force ::ck::http::http
  namespace import -force ::ck::strings::html
}

proc ::translate::init {  } {

  cmd register translateru ::translate::run -doc "translate" -autousage \
    -bind "tran|slate" -bind "tt"

  set x [list]
  set dictlist [list]
  foreacharray ::translate::dictionary {
    lappend x "*${k}*: $v"
    lappend dictlist "*${k}*"
  }
  cmd doc -link "translate" "translate.dict" "~Словари~: [join $x {; }]"
  cmd doc -link "translate.dict" "translate" "~*!translate* \[словарь\] <текст>~ - перевод текста. Словари - [join $dictlist {, }]"

  config register -id "dict.lat" -type str -default "er" \
    -desc "Словарь по умолчанию для текста с латинскими буквами." -access "m" -folder "translateru"
  config register -id "dict.rus" -type str -default "re" \
    -desc "Словарь по умолчанию для текста с русскими буквами." -access "m" -folder "translateru"
  config register -id "show.dict" -type bool -default 0 \
    -desc "Показывать ли в результате перевода используемый словарь." -access "m" -folder "translateru"

  cache register -nobotnick -nobotnet -ttl 1d -maxrec 5

  msgreg {
    err.conn    &rОшибка связи с &Btranslate.ru&r.
    err.parse   &rОшибка обработки результата перевода.
    main        %s&n%s
    main.dict   "%s перевод&K: "
  }

}

proc ::translate::run { sid } {
  variable dictionary
  session import

  if { $Event eq "CmdPass" } {
    set StdArgs [lrange $StdArgs 1 end]
    if { [info exists dictionary([string tolower [lindex $StdArgs 0]])] } {
      set dict [string tolower [lpop StdArgs]]
    }
    set Text [join $StdArgs { }]
    if { $Text eq "" } { replydoc "translate" }
    if { ![info exists dict] } {
      if { [string isrus $Text] } {
	set dict [config get "dict.rus"]
      } {
	set dict [config get "dict.lat"]
      }
    }

    debug -debug "Try to get -> <%s>" $Text
    cache makeid $dict $Text

    if { ![cache get TransText] } {
      session export -grablist [list "dict"]
      http run "http://m.translate.ru/translator/result/" -query-codepage utf-8 -return \
        -query [list text $Text dirCode $dict]
    }
  } elseif { $Event eq "HttpResponse" } {
    if { $HttpStatus < 0 } {
      reply -err conn
    }
    if { ![regexp {<div class="tres">\s*(.*?)\s*</div><div.*} $HttpData - TransText] } {
      reply -err parse
    }
    cache put $TransText
  }

  set TransText [string stripspace [html unspec [html untag $TransText]]]

  if { [config get "show.dict"] } { set o1 [cformat main.dict $dictionary($dict)] } { set o1 "" }

  reply -uniq main $o1 $TransText
}

namespace eval translate {
  variable dictionary
  catch { unset dictionary }
  array set dictionary {
    er {Англо-Русский}
    re {Русско-Английский}
    gr {Немецко-Русский}
    rg {Русско-Немецкий}
    fr {Французско-Русский}
    rf {Русско-Французский}
    sr {Испанско-Русский}
    rs {Русско-Испанский}
    ir {Итальянско-Русский}
  }
#    eg {Англо-Немецкий}
#    ge {Немецко-Английский}
#    es {Англо-Испанский}
#    se {Испанско-Английский}
#    ef {Англо-Французский}
#    fe {Французско-Английский}
#    ep {Англо-Португальский}
#    pe {Португальско-Английский}
#    fg {Французско-Немецкий}
#    gf {Немецко-Французский}
#    fs {Французско-Испанский}
#    sf {Испанско-Французский}
#    gs {Немецко-Испанский}
#    sg {Испанско-Немецкий}
#    ie {Итальянско-Английский}
}
