
encoding system utf-8
::ck::require cmd
::ck::require cache
::ck::require http

namespace eval ::weather {
  variable version 1.0
  variable author "Chpock <chpock@gmail.com>"

  namespace import -force ::ck::cmd::*
  namespace import -force ::ck::http::http
  namespace import -force ::ck::cache::cache
}

proc ::weather::init {  } {

  datafile register weather.alias
  datafile register weather.citys

  cache register -ttl 3h -maxrec 30

  cmd doc "weather" {~*!weather* [-день] <город>~ - подробная погода на <день> относительно текущего дня.}

  cmd register weatherupdate ::weather::update \
    -bind "weather\.update" -access "n" -config "weather"
  cmd register weather ::weather::run -autousage -doc "weather" \
    -bind "weather" -bind "погода"

  config register -id "admflags" -type str -default "m|" \
    -desc "Flags for access to change weather aliases." -access "n" -folder "weather"

  msgreg {
    nocity        &RГород по Вашему запросу не найден.
    manymatch     &RУточните запрос. По Вашему запросу найдены города&K: &B%s
    manymatchj    "&K, &B"
    day0          &K[&R%s &r%s&K(&R%s&K)] %s
    day           &r(&R%3$s&r) %4$s
    temp          &p%s&K..&p%s°C&K(&n%s&K)
    wind          &bВтр:&B%s..%sм/с&n(%s)
    press         &bДвл:&B%sмм
    relw          &bВлж:&B%s%%
    day.join      " "
    join          " &K// "
    main          &g%s %s

    err.parse     &RОшибка получения данных о погоде в &Bг.%s
    err.nodata    &cНет данных о погоде в &Bг.%s&c на запрашиваемый период.

    upd.try       &BПытаюсь обновить базу данных городов для погоды...
    err.upd.http  &RОшибка связи с сервером.
    err.upd.pars  &RОшибка разбора данных полученных от сервера.
    upd.done      &BОбновление успешно завершено. В базе &R%s&B городов.
  }
}

proc ::weather::run { sid } {
  session export

  if { $Event eq "CmdPass" } {
    set Request [join [lrange $StdArgs 1 end] { }]
    if { [regexp {[+-](\d)} $Request - WeatherOffset] } {
      regfilter {[+-]\d} Request
      set Request [string trim $Request]
    } {
      set WeatherOffset 0
    }
    session insert WeatherOffset $WeatherOffset
    array set {} [searchcity $Request]
    if { ![llength $(city)] } {
      reply -err nocity
    } elseif { [llength $(city)] > 1 } {
      reply -err manymatch [cjoin $(city) manymatchj]
    }
    debug -debug "Try to get weather for city <%s\(%s\)>" [lindex $(city) 0] [lindex $(num) 0]
    session insert CityName [lindex $(city) 0]
    weather [lindex $(num) 0]
    return
  }

  if { $WeatherStatus < 0 } { reply -err parse $CityName }
  set WeatherData [filt $WeatherOffset $WeatherData]
  if { ![llength $WeatherData] } { reply -err nodata $CityName }

  set data [list]
  foreach_ $WeatherData {
    array set {} $_

    set_ [list [lindex {ясно малооблачно облачно пасмурно} $(Cloud)]]
    switch -- $(Precip) {
      4 { lappend_ "дождь" }
      5 { lappend_ "ливень" }
      6 - 7 { lappend_ "снег" }
      8 { lappend_ "гроза" }
    }
    set x [join_ {,}]
    if { $(Hour) > 0 && $(Hour) < 6 } { set_ "ночь"
    } elseif { $(Hour) > 6 && $(Hour) < 12 } { set_ "утро"
    } elseif { $(Hour) > 12 && $(Hour) < 18 } { set_ "день"
    } else { set_ "вечер" }
    set frm day; if { ![llength $data] } { append frm 0 }
    set out [list [cformat $frm [0 $(Day)] [lindex \
      {Янв Фев Мар Апр Мая Июн Июл Авг Сен Окт Ноя Дек} [incr (Month) -1]] \
        $_ [cformat temp $(MinT) $(MaxT) $x]]]
    lappend out [cformat wind $(MinW) $(MaxW) [lindex \
      {Сев ССВ СВ СВС Вст ВЮВ ЮВ ЮЮВ Южн ЮЮЗ ЮЗ ЗЮЗ Зап ЗСЗ СЗ ССЗ} $(RumbW)]]
    lappend out [cformat press [~ $(MinP) $(MaxP)]]
    lappend out [cformat relw [~ $(MinRW) $(MaxRW)]]
    lappend data [cjoin $out "day.join"]
  }
  reply -noperson -uniq main $CityName [cjoin $data join]
}
proc ::weather::searchcity { str } {
  set (city) [list]
  set (num)  [list]
  set str [string tolower $str]
  foreach_ [datafile getlist weather.alias] {
    if { [lindex_ 0] == $str } { set str [lindex_ 1]; break }
  }
  set lstr [list $str]
  foreach_ [datafile getlist weather.citys] {
    foreach str $lstr {
      if { [string match -nocase $str [lindex_ 0]] } {
	lappend (city) [lindex_ 0]
	lappend (num) [lindex_ 1]
      }
    }
    if { [llength $(city)] > 20 } break
  }
  return [array get {}]
}
proc ::weather::update { sid } {
  session export
  if { $Event eq "CmdPass" } {
    reply upd.try
    http run "http://gen.gismeteo.ru/frcdb/cityinfr.txt" -return -charset "cp866"
  }
  if { $HttpStatus < 0 } {
    reply -err upd.http
  }
  set datalist [list]
  foreach_ [split $HttpData "\n"] {
    set_ [string trim $_]
    if { $_ eq "" } continue
    if { ![regexp {^[0-9-]+\s+(\d{5})\s+[0-9-]+\s+[0-9-]+\s+(.+)$} $_ - n g] } {
      reply -err upd.pars
    }
    lappend datalist [list $g $n]
  }
  reply upd.done [llength $datalist]
  datafile putlist weather.citys $datalist
}
proc ::weather::weather { citynum } {
  upvar sid sid
  session create -child -proc ::weather::weather_request \
    -parent-event WeatherResponse
  session import \
    -grab citynum as RequestCityNum
  session parent
  return
}
proc ::weather::weather_request { sid } {
  session export

  if { $Event eq "SessionInit" } {
    cache makeid $RequestCityNum
    if { ![cache get HttpData] } {
      http run "http://gen.gismeteo.ru/plnt/T${RequestCityNum}.TXT" -return
    }
  } elseif { $Event eq "HttpResponse" } {
    if { $HttpStatus < 0 } {
      debug -err "while http request."
      session return WeatherStatus -99 WeatherError "while http request."
    }
    cache put $HttpData
  }

  array set result [list]
  foreach_ [split $HttpData \n] {
    if { [llength [set_ [split_ ,]]] != 17 } continue
    array set {} [list]
    foreach_ $_ {
      if { [llength [set_ [split_ =]]] != 2 } { unset {}; break }
      set ([lindex_ 0]) [lindex_ 1]
    }
    if { ![array exists {}] } continue
    set id "$(Year)[0 $(Month)][0 $(Day)][0 $(Hour)]"
    set result($id) [array get {}]
    unset {}
  }

  if { ![array size result] } {
    debug -err "while parsing data:"
    foreach_ [split $HttpData \n] {
      if { ![string length $_] } coninue
      debug -err- "  > %s" $_
    }
    session return WeatherStatus -50 WeatherError "while parsing data."
  }

  session return WeatherStatus 0 WeatherError "" WeatherData [array get result]
}
proc ::weather::filt { offset data } {
  set result [list]
  set last 0
  array set {} $data
  foreach_ [lsort -integer [array names {}]] {
    if { !$last } { set last $_ }
    if { $offset } {
      if { [string equal -length 8 $_ $last] } continue
      set last $_
      if { [incr offset -1] } continue
    }
    if { ![string equal -length 8 $_ $last] } break
    lappend result $($_)
  }
  return $result
}
proc ::weather::0 a { if { [string length $a] == 1 } { return "0$a" } { return $a } }
proc ::weather::~ {1 2} { return [expr { int(.5 * ($1 + $2)) }] }
