
encoding system utf-8
::ck::require cmd   0.4
::ck::require http  0.2
::ck::require strings 0.4

namespace eval ::cyborg {
  variable version 0.2
  variable author  "Chpock <chpock@gmail.com>"

  namespace import -force ::ck::cmd::*
  namespace import -force ::ck::strings::html
  namespace import -force ::ck::http::http
}

proc ::cyborg::init {  } {
  cmd register cyborg ::cyborg::run \
    -bind "cyb|org" -bind "киб|орг" -doc "cyborg" -flood 10:60

  cmd doc "cyborg" {~*!cyborg* [слово]~ - расшифровка аббревиатуры киборга. Если <слово> не задано - генерируется случайное.}

  msgreg {
    err.conn  &RОшибка связи.
    err.parse &RОшибка обработки результата.
    word      &r%s&b.
    acronym   &P%s&p
    main      %s&K:&p %s
  }
}

proc ::cyborg::run { sid } {
  session import
  if { $Event eq "CmdPass" } {
    set TextR ""
    set TextE ""
    foreach_ [split [lindex $StdArgs 1] {}] {
      if { [string match {[A-Z]} [set_ [string toupper $_]]] } {
	append TextE $_
      } elseif { [string isrus $_] } {
	append TextR $_
      }
    }
    if { [string length $TextR] > 0 && [string length $TextE] > 0 } { replydoc cyborg }
    if { "$TextR$TextE" eq "" } { set TextE [string randomstr -] }
    if { [string length $TextR] } {
      http run "http://www.korova.ru/humor/cyborg.php" -query [list "acronym" $TextR] -query-codepage koi8-r -mark "Rus" -return
    } {
      set TextE [string range $TextE 0 9]
      http run "http://cyborg.namedecoder.com/index.php" -query [list "acronym" $TextE "design" "edox"] \
	-mark "Eng" -return
    }
  }

  if { $HttpStatus < 0 } { reply -err conn }

  if { $Mark eq "Rus" } {
    if { ![regexp {<p>(\w+):\s+([^>]+)</p>} $HttpData - word acronym] } {
      reply -err parse
    }
    set word [split $word {}]
  } {
    if { ![regexp {<p class="mediumheader">([^:]+):\s+([^>]+)</p>} $HttpData - word acronym] } {
      reply -err parse
    }
    set word [split [string trim $word .] .]
  }

  set_ [list]
  foreach char $word {
    lappend_ [cformat word $char]
  }
  set word [cjoin $_ {}]

  set_ [list]
  foreach char [split $acronym {}] {
    if { [regexp {\w} $char] && [string toupper $char] eq $char } {
      lappend_ [cformat acronym $char]
    } {
      lappend_ $char
    }
  }
  set acronym [cjoin $_ {}]

  reply -uniq main $word $acronym
}
