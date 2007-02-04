
encoding system utf-8
::ck::require cmd 0.4

## quote (list)
# <quote> <date> <nick!ident@host> <qhashe> <chan> <gflags> <cflags>

namespace eval quotes {
  variable version 1.1
  variable author  "Chpock <chpock@gmail.com>"

  variable quote

  namespace import -force ::ck::cmd::*
}
proc ::quotes::init {} {
  variable quote

  datafile register quotes -net -bot

  cmd doc -link [list "addquote" "delquote"] "quote" {~*!quote [шаблон]~ - поиск в цитатах по шаблону. \
    Если шаблон не задан - вывести случайную цитату.}
  cmd doc -link [list "quote" "delquote"] "addquote" {~*!addquote~ <цитата>~ - добавить цитату.}
  cmd doc -link [list "quote" "addquote"] "delquote" {~*!delquote~ <шаблон>~ - удалить цитату по шаблону.}

  cmd register quote ::quotes::run \
    -bind "q|uote" -config "quotes"
  cmd register addquote ::quotes::addquote -autousage -doc "addquote" \
    -bind "addq|uote" -bind "quoteadd" -bind {\+quote} -config "quotes"
  cmd register delquote ::quotes::delquote -autousage -doc "delquote" \
    -bind "delq|uote" -bind "quotedel" -bind "-quote" -config "quotes"

  config register -id "remflags" -type str -default "o|" \
    -desc "Flags for removing quotes." -access "m" -folder "quotes"
  config register -id "addflags" -type str -default "o|o" \
    -desc "Flags for adding quotes." -access "m" -folder "quotes"

  set quote [datafile getlist quotes]

  msgreg {
    quote.num      "&K[&B%s&K/&b%s&K]&n "
    quote.aut      " &K[&n%s&K]"
    quote.main     %s%s%s
    del.done       &BЦитата с номером &r#&R%s&B удалена. &K(&n%s&K)
    add.done       &BЦитата добавлена с номером &r#&R%s
    add.reject     &rВы не можете добавить такую цитату.
    err.noquote    &RВ базе цитат пусто.
    err.nomatch    &RЦитат по Вашему запросу не найдено.
    err.badnum     &RЦитаты с номером &B%s&R не найдено.
    err.manymatch  &RПо вашему запросу на удаление найдено &r%s&R цитат. Пожалуйста, уточните запрос.
  }
}
proc ::quotes::run { sid } {
  variable quote
  session import

  if { [llength $quote] == 0 } {
    reply -err noquote
  }

  set mask [join [lrange $StdArgs 1 end] " "]

  if { $mask == "" || $mask == "*" } {
    set mnum [expr { [rand [llength $quote]] + 1 }]
    set qmatch $quote
  } {
    if { [regexp {^-?(\d+)(\s|$)} $mask - mnum] } {
      regsub {^-?\d+\s*} $mask {} mask
      set mnum [string trimleft $mnum "0"]
      if { $mnum eq "" } { set mnum 1 }
    } {
      set mnum 1
    }
    set qmatch [list]
    foreach q $quote {
      if { [string match -nocase "*${mask}*" [lindex $q 0]] } {
	lappend qmatch $q
      }
    }
    if { $mnum > [llength $qmatch] } { set mnum [llength $qmatch] }
  }
  if { [llength $qmatch] == 0 } { reply -err nomatch }
  if { [llength $qmatch] == 1 } {
    set rnum ""
  } {
    set rnum [cformat quote.num $mnum [llength $qmatch]]
  }
  set q [lindex $qmatch [incr mnum -1]]

  set auth [lindex $q 2]
  set auth [string nohighlight [lindex [split $auth !] 0]]

  reply quote.main $rnum [lindex $q 0] [cformat quote.aut $auth]
}
proc ::quotes::addquote { sid } {
  variable quote
  session import

  session set CmdAccess [config get addflags]
  checkaccess -return

  regexp {^\S+\s+(.+)$} $Text - q
  regsub {\W} $q {} hash

  if { $hash == "" } { reply -err add.reject }

  set hash [string hash $hash]
  foreach_ $quote {
    if { [lindex $_ 3] == $hash } {
      reply -err add.reject
    }
  }
  if { [catch {chattr $Handle $CmdChannel} errStr] } {
    set gflags [chattr $Handle]
    set cflags ""
  } {
    set gflags [lindex [split $errStr "|"] 0]
    set cflags [lindex [split $errStr "|"] 1]
  }
  lappend quote [list $q [clock seconds] "${Nick}!$UserHost" $hash $CmdChannel $gflags $cflags]
  reply add.done [llength $quote]
  datafile putlist quotes $quote
}
proc ::quotes::delquote { sid } {
  variable quote
  session import

  if { [llength $quote] == 0 } {
    reply -err noquote
  }

  set mask [join [lrange $StdArgs 1 end] " "]

#  if { $mask == "" } {
#    set mmi [llength $quote]
#    incr mmi -1
#  } {
    if { [string isnum -int -unsig $mask] } {
      if { $mask > [llength $quote] || $mask < 1 } {
	reply -err badnum $mask
      }
      set mmi [incr mask -1]
    } {
      set matchlist [list]
      set i 0
      foreach_ $quote {
        if { [string match -nocase "*${mask}*" [lindex $_ 0]] } {
	  lappend matchlist $i
	}
	incr i
      }
      if { ![llength $matchlist] } {
	reply -err nomatch
      } elseif { [llength $matchlist] > 1 } {
	reply -err manymatch [llength $matchlist]
      }
      set mmi [expr { [lindex $matchlist 0] - 1 }]
    }
#  }

  set q [lindex $quote $mmi]

  # тут проветка на доступ к удалению

  set quote [lreplace $quote $mmi $mmi]

  reply del.done [expr { $mmi + 1 }] [lindex $q 0]
  datafile putlist quotes $quote
}
