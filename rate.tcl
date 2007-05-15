
encoding system utf-8
::ck::require cmd   0.4
::ck::require http  0.2

namespace eval ::rate {
  variable version 1.0
  variable author  "Chpock <chpock@gmail.com>"
  variable currency

  namespace import -force ::ck::cmd::*
  namespace import -force ::ck::http::http
}
proc ::rate::init { } {
  cmd register rate ::rate::run -doc "rate" -autousage \
    -bind "rate" -bind "курс" -flood 10:60

  cmd doc "rate" "~*!rate* \[сумма\] <валюта> \[= <валюта>\]~. \
    Валюта: &g[join [array names ::rate::currency] {&n, &g}]"

  config register -id "def.currency" -type "str" -default "UAH" \
    -desc "Валюта по умолчанию." -access "n" -folder "rate" -hook chkconfig

  msgreg {
    main     &r%s&B%s &K(&b%s&K)&n == &R%s&B%s &K(&b%s&K) (&nкурс: &c%s&K)
    err.from &RНе могу определить исходную валюту.
    err.to   &RНе могу определить валюту в которую следует конвертировать.
    err.parse  &RОшибка конвертации.
    err.http   &RОшибка связи с сайтом.
    err.nodata &RОшибка конвертации:&B %s
  }
}
proc ::rate::chkconfig { mode var oldv newv hand } {
  variable currency
  if { $mode != "set" } return
  set newv [string toupper $newv]
  if { ![info exists currency($newv)] } {
    return [list 2 "Известные валюты: [join [array names currency] {, }]"]
  }
  return [list 1 "" $newv]
}
proc ::rate::ai { str } {
  variable currency
  set str [string tolower $str]
  foreach_ [array names currency] {
    if { [string match -nocase "*${_}*" $str] } {
      return $_
    }
  }
  switch -glob -- $str {
    {*$*}    -
    "*дол*"  { return "USD" }
    "*рус*"  -
    "*rur*"  -
    "*rub*"  -
    "*руб*"  { return "RUR" }
    "*укр*"  -
    "*грив*" -
    "*грн*"  { return "UAH" }
    "*бакс*" { return "USD" }
    "*евр*"  { return "EUR" }
    "*р"     { return "RUR" }
    "*г"     { return "UAH" }
    "*е"     -
    "*e"     { return "EUR" }
  }
  return ""
}
proc ::rate::run { sid } {
  session import

  if { $Event == "CmdPass" } {
    set Text [join [lrange $StdArgs 1 end] " "]
    if { $Text == "" } {
      replydoc rate
    }
    if { ![regexp {^([^=]+?)=([^=]+)$} $Text - from to] && ![regexp {^([^=]+?) в ([^=]+)$} $Text - from to] } {
      set from $Text
      set to [config get "def.currency"]
    }
    if { [regexp {(\d+(?:\.\d+)?)} $Text - RateValue] } {
      regfilter {\d+\.?\d*} Text
      set RateValue [string trimleft $RateValue 0]
      if { $RateValue == 0 } { set RateValue 1 }
    } {
      set RateValue 1
    }
    if { [set from [ai $from]] == "" } { reply -err from }
    if { [set to [ai $to]] == "" } { reply -err to }
    session insert from $from
    session insert to $to
    if { $from == "RUR" } { set from "BASE" }
    if { $to == "RUR" } { set to "BASE" }
    http run "http://conv.rbc.ru/convert.shtml" \
      -query [list "mode" "calc" "source" "cb.0" commission 1 \
	"tid_from" $from "tid_to" $to summa $RateValue] -return
  }
  if { $HttpStatus < 0 } {
    debug -err "While requesting page."
    reply -err http
  }

  if { $from == "BASE" } { set from "RUR" }
  if { $to == "BASE" } { set to "RUR" }

  regfilter -nocase -- {.+<td\s+class=head_gr} HttpData
  regfilter -nocase -- {</table>.+$} HttpData

  if { [regexp {<font color=red>([^<]+)</font>} $HttpData - errMsg] } {
    reply -err nodata $errMsg
  }

  if { ![regexp -nocase {<td.*?>(.+?)\s*</td>\s*<td><b>(.+?)</b>} $HttpData - pubfrom pubfromcnt] } {
    debug -err "error while parsing page."
    reply -err parse
  }
  regfilter -nocase -- {<tr>.+?</tr>} HttpData
  if { ![regexp -nocase {<td.*?>.+?</td>\s*<td><b>(.+?)</b>} $HttpData - pubrate] } {
    debug -err "error while parsing page."
    reply -err parse
  }
  regfilter -nocase -- {<tr>.+?</tr>} HttpData
  if { ![regexp -nocase {<td.*?>(.+?)\s*</td>\s*<td><b>(.+?)</b>} $HttpData - pubto pubtocnt] } {
    debug -err "error while parsing page."
    reply -err parse
  }
  reply -uniq main $pubfromcnt $from $pubfrom $pubtocnt $to $pubto $pubrate
}

namespace eval ::rate {
  array set currency {
    "AUD" {Австралийский доллар} "ATS" {Австрийский шиллинг} "GBP" {Английский фунт стерлингов}
    "BYR" {Белорусский рубль} "BEF" {Бельгийский франк} "NLG" {Голландский гульден}
    "GRD" {Греческая драхма} "DKK" {Датская крона} "USD" {Доллар США}
    "EUR" {ЕВРО} "EGP" {Египетский фунт} "IEP" {Ирландский фунт}
    "ISK" {Исландская крона} "ESP" {Испанская песета} "ITL" {Итальянская лира}
    "KZT" {Казахский тенге} "CAD" {Канадский доллар} "KGS" {Киргизский сом}
    "CNY" {Китайский юань} "KWD" {Кувейтский динар} "LTL" {Литовский лит}
    "DEM" {Немецкая марка} "NOK" {Норвежская крона} "PTE" {Португальский эскудо}
    "RUR" {Российский рубль} "SDR" {СДР} "XDR" {СДР(спец. права заимствования)}
    "SGD" {Сингапурский доллар} "TRL" {Турецкая лира} "TRY" {Турецкая лира}
    "UAH" {Украинская гривна} "FIM" {Финляндская марка} "FRF" {Французский франк}
    "SEK" {Шведская крона} "CHF" {Швейцарский франк} "EEK" {Эстонская крона}
    "YUN" {Югославский динар} "JPY" {Японская иена}
  }
}
