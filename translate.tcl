
# rewrite from translate.tcl by Twin@RusNet
encoding system utf-8
::ck::require cmd   0.4
::ck::require http  0.2
::ck::require cache 0.2

namespace eval translate {
  variable version 1.0
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
  foreacharray ::translate::dictionary {
    set_ [list]
    set i 0
    foreach {v1 v2} [lrange $v 1 end] {
      lappend_ "*[incr i]*:$v2"
    }
    cmd doc -link "translate" "translate.$k" "[lindex $v 0]; Варианты - [join_ {, }]"
    lappend x "*${k}*"
  }
  cmd doc -link {translate.*} "translate" "~*!translate* \[вариант словаря\] \[словарь\] <текст>~ - перевод текста. Словари - [join $x {, }]"

  config register -id "dict.lat" -type str -default "er" \
    -desc "Словарь по умолчанию для текста с латинскими буквами." -access "m" -folder "translateru"
  config register -id "dict.rus" -type str -default "re" \
    -desc "Словарь по умолчанию для текста с русскими буквами." -access "m" -folder "translateru"
  config register -id "show.dict" -type bool -default 0 \
    -desc "Показывать ли в результате перевода используемый словарь." -access "m" -folder "translateru"
  config register -id "show.dict.var" -type bool -default 1 \
    -desc "Показывать ли в результате перевода вариант словаря." -access "m" -folder "translateru"

  cache register -nobotnick -nobotnet -ttl 1d -maxrec 5

  msgreg {
    err.conn    &rОшибка связи с &Btranslate.ru&r.
    err.parse   &rОшибка обработки результата перевода.
    main        %s%s%s
    main.dict   "%s перевод&K: "
    main.dictv  &K(&n%s&K) &n
  }

}

proc ::translate::run { sid } {
  variable dictionary
  session import

  if { $Event eq "CmdPass" } {
    set StdArgs [lrange $StdArgs 1 end]

    if { [string isnum -int [lindex $StdArgs 0]] } {
      set dictnum [string trim [lpop StdArgs] -]
      if { [set dictnum [string trimleft $dictnum 0]] eq "" } {
	set dictnum 1
      }
    }
    if { [info exists dictionary([string tolower [lindex $StdArgs 0]])] } {
      set dict [string tolower [lpop StdArgs]]
    }
    if { ![info exists dictnum] } {
      if { [string isnum -int [lindex $StdArgs 0]] } {
	set dictnum [string trim [lpop StdArgs] -]
      } {
	set dictnum 1
      }
    }
    set Text [join $StdArgs { }]
    if { $Text eq "" } {
      replydoc "translate"
    }
    if { ![info exists dict] } {
      if { [string isrus $Text] } {
	set dict [config get "dict.rus"]
      } {
	set dict [config get "dict.lat"]
      }
    }

    set availdict $dictionary($dict)
    set dictnum [expr { $dictnum * 2 - 1 }]

    if { $dictnum >= [llength $availdict] } {
      set dictnum [expr { [llength $availdict] - 2 }]
    }
    debug -debug "Try to get :%s:%s: -> <%s>" [lindex $availdict 0] [lindex $availdict $dictnum] $Text

    cache makeid $dict $dictnum $Text

    if { ![cache get TransText] } {
      session export -grablist [list "dict" "dictnum" "availdict"]
      http run "http://www.translate.ru/text.asp" -post -query-codepage cp1251 -return \
        -query [list "lang" "ru" "status" "translate" "transliterate" "1" "direction" $dict "template" [lindex $availdict $dictnum] \
	  "source" $Text]
    }
  } elseif { $Event eq "HttpResponse" } {
    if { $HttpStatus < 0 } {
      reply -err conn
    }
    if { ![regexp {<span id="r_text" name="r_text">\s*(.*?)\s*</span>} $HttpData - TransText] } {
      reply -err parse
    }
    cache put $TransText
  }

  set TransText [string stripspace [html unspec [html untag $TransText]]]

  if { [config get "show.dict"] } { set o1 [cformat main.dict [lindex $availdict 0]] } { set o1 "" }
  if { [config get "show.dict.var"] } { set o2 [cformat main.dictv [lindex $availdict [incr dictnum]]] } { set o2 "" }

  reply -uniq main $o1 $o2 $TransText
}


namespace eval translate {
  variable dictionary
  array init dictionary {
    er {
      {Англо-Русский}
	{Software}   {Программное обеспечение}
	{Internet}   {Интернет}
	{General}    {Общая лексика}
	{Automotive} {Автомобили}
	{Banking}    {Банковское дело}
	{Business}   {Деловая корреспонденция}
	{Games}      {Компьютерные игры}
	{Logistics}  {Логистика}
	{Sport}      {Спорт}
	{Travels}    {Путешествия}
    }
    re {
      {Русско-Английский}
	{Software}   {Програмное обеспечение}
	{Internet}   {Интернет}
	{General}    {Общая лексика}
	{Phrasebook} {Разговорник}
	{Automotive} {Автомобили}
	{Business}   {Деловая корреспонденция}
	{Logistics}  {Логистика}
	{Travels}    {Путешествия}
    }
    gr {
      {Немецко-Русский}
	{General}    {Общая лексика}
	{Software}   {Програмное обеспечение}
	{Internet}   {Интернет}
	{Automotive} {Автомобили}
	{Business}   {Деловая корреспонденция}
	{Football}   {Футбол}
    }
    rg {
      {Русско-Немецкий}
	{General}    {Общая лексика}
	{Internet}   {Интернет}
	{Business}   {Деловая корреспонденция}
	{Football}   {Футбол}
    }
    fr {
      {Французско-Русский}
	{General}    {Общая лексика}
	{Internet}   {Интернет}
	{Business}   {Деловая корреспонденция}
	{Perfumery}  {Парфюмерия}
	{Football}   {Футбол}
    }
    rf {
      {Русско-Французский}
	{General}    {Общая лексика}
	{Internet}   {Интернет}
	{Business}   {Деловая корреспонденция}
    }
    sr {
      {Испанско-Русский}
	{General}    {Общая лексика}
    }
    rs {
      {Русско-Испанский}
	{General}    {Общая лексика}
    }
    ir {
      {Итальянско-Русский}
	{General}    {Общая лексика}
    }
    eg {
      {Англо-Немецкий}
	{General}    {Общая лексика}
	{Software}   {Программное обеспечение}
	{Business}   {Деловая корреспонденция}
	{Football}   {Футбол}
    }
    ge {
      {Немецко-Английский}
	{General}    {Общая лексика}
	{Software}   {Программное обеспечение}
	{Business}   {Деловая корреспонденция}
	{Football}   {Футбол}
    }
  }
#    es {
#      {Англо-Испанский}
#	{General}    {Общая лексика}
#    }
#    se {
#      {Испанско-Английский}
#	{General}    {Общая лексика}
#    }
#    ef {
#      {Англо-Французский}
#	{General}    {Общая лексика}
#    }
#    fe {
#      {Французско-Английский}
#	{General}    {Общая лексика}
#    }
#    ep {
#      {Англо-Португальский}
#	{General}    {Общая лексика}
#    }
#    pe {
#      {Португальско-Английский}
#	{General}    {Общая лексика}
#    }
#    fg {
#      {Французско-Немецкий}
#	{General}    {Общая лексика}
#	{Football}   {Футбол}
#    }
#    gf {
#      {Немецко-Французский}
#	{General}    {Общая лексика}
#	{Football}   {Футбол}
#    }
#    fs {
#      {Французско-Испанский}
#	{General}    {Общая лексика}
#    }
#    sf {
#      {Испанско-Французский}
#	{General}    {Общая лексика}
#    }
#    gs {
#      {Немецко-Испанский}
#	{General}    {Общая лексика}
#	{Football}   {Футбол}
#    }
#    sg {
#      {Испанско-Немецкий}
#	{General}    {Общая лексика}
#	{Football}   {Футбол}
#    }
#    ie {
#      {Итальянско-Английский}
#	{General}    {Общая лексика}
#    }
}
