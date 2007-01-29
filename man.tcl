
encoding system utf-8
::ck::require cmd  0.2

# mans array:
#  index : lowered, uncolored keyword
#  elem0 : lowered, uncolored keyword
#  elem1 : original keyword
#  elem2 : man body
#  elem3 : man author
#  elem4 : list of linked mans

namespace eval mans {
  variable version 1.1
  variable author  "Chpock <chpock@gmail.com>"

  variable mans

  namespace import -force ::ck::cmd::*
  namespace import -force ::ck::files::datafile
}

proc ::mans::init {  } {

  datafile register man

  etimer -interval 10 ::mans::dbcleanup

  cmd register mans ::mans::run \
    -bind "man|ual" -bind "ман|уал" -config "mans"
  config register -id "admflags" -type str -default "o|" \
    -desc "Flags for access to change mans db." -access "m" -folder "mans"

  cmd doc -alias [list man.search] -link [list man.add man.link man.clear man.seealso] "man" \
    {*!man* <word> - view man page&K; *!man* [num] <mask> - search man pages.}
  cmd doc -link [list man] "man.add" \
    {*!man* <word> = <description> - add new man page.}
  cmd doc -link [list man] "man.clear" \
    {*!man* <word> = - clear man page.}
  cmd doc -link [list man] "man.seealso" \
    {*!man* <original_man> =+ <other_man> - Add link for page <original_man> as "see also".}
  cmd doc -link [list man] "man.link" \
    {*!man* <word> = <original_man> - Add man page for <word> as synonym of <original_man>.}

  msgreg {
    err.title.mask &rMan title can't contains mask symbol like &K"&B*&K"&r and &K"&B?&K"&r.
    err.few.page   &rSeveral man pages match your request. Select one of them. &K(&n%s&K)
    err.few.page.j ", "
    err.no.page    &rNo such man page.
    del.page       &BMan page deleted.
    err.bad.key    &rOriginal keyword is wrong.
    err.key.nofnd  &rMan page for keyword &K"&R%s&K"&r not found.
    err.already.ln &BThese mans already linked.
    tnx.for.info   &Bthx for information.
    err.bad.req    &rNo mans match your request.
    err.nolocal    &rCan't delete this man page.
    main.count     "&K[&B%s&K/&b%s&K]&n "
    main.author    " &n[%s]"
    main.orig.page &K(&n%s&K)
    main.seealso   " &K(&nsee also:&g %s&K)"
    main.seealso.j "&n,&g "
    main           &R*&n %s%s%s&K =&n %s%s%s
  }
}

proc ::mans::regman { args } {
  variable mans
  getargs -link str [list] -author str ""
  set id [string stripcolor [string tolower [lindex $args 0]]]
  set_ [list $id [lindex $args 0] [lindex $args 1] $(author) $(link)]
  if { $id == "" } return
  if { ![array exists mans] } { datafile getarray man mans }
  set mans() [clock seconds]
  set mans($id) $_
  datafile putarray man mans
}
proc ::mans::dbsearch { args } {
  variable mans

  getargs -exact flag

  if { ![array exists mans] } { datafile getarray man mans }
  set mans() [clock seconds]
  set mid [string stripcolor [lindex $args 0]]
  if { $(exact) } {
    if { ![info exists mans($mid)] } {
      if { ![info exists ::ck::cmd::cmddoc($mid)] } {
	return ""
      }
      return $::ck::cmd::cmddoc($mid)
    }
    return $mans($mid)
  }
  set result [list]
  foreach_ [lsort -dictionary [concat [array names mans] [array names ::ck::cmd::cmddoc]]] {
    if { $_ == "" } continue
    if { [string match -nocase $mid $_] } {
      if { [info exists mans($_)] } {
	lappend result $mans($_)
      } {
	lappend result $::ck::cmd::cmddoc($_)
      }
    }
  }
  return $result
}
proc ::mans::dbcount { args } {
  variable mans
  if { ![array exists mans] } { datafile getarray man mans }
  set mans() [clock seconds]
  set cnt [llength [luniq [concat [array names mans] [array names ::ck::cmd::cmddoc]]]]
  # вычитаем 1 на "пустой ман" в котором время апдейта базы
  return [incr cnt -1]
}
proc ::mans::dbupdate {  } {
  variable mans
  if { ![array exists mans] } return
  set mans() [clock seconds]
  datafile putarray man mans
}
proc ::mans::dbcleanup {  } {
  variable mans
  if { ![array exists mans] } return
  if { ([clock seconds] - $mans()) < 300 } return
  unset mans
}
proc ::mans::list2titles { mlist } {
  set result ""
  foreach_ $mlist { lappend result [lindex_ 1] }
  return $result
}
proc ::mans::run { sid } {
  session export

  if { [regexp -- {^\S+\s+(.+?)\s*([\+\-]?=[\+\-]?)\s*(.*)$} [string trim $Text] - var isadd val] } {
    session insert CmdAccess [config get "admflags"]
    checkaccess -return
    # запрос на удаление
    if { $val == "" } {
      set mid [dbsearch -- $var]
      if { ![llength $mid] } { reply -err err.no.page }
      if { [llength $mid] > 1 } { reply -err err.few.page [cjoin [list2titles $mid] err.few.page.j]  }
      set mid [lindex [lindex $mid 0] 0]
      if { [info exists ::mans::mans($mid)] } {
	unset ::mans::mans($mid)
	dbupdate
	reply -return del.page
      } {
	reply -err nolocal
      }
    # запрос на добавление линка
    } elseif { [string exists "+" $isadd] } {
      set mid [dbsearch -- $var]
      if { ![llength $mid] } { reply -err err.bad.key }
      if { [llength $mid] > 1 } { reply -err err.few.page [cjoin [list2titles $mid] err.few.page.j]  }
      set mid [lindex $mid 0]
      set linkto [dbsearch -exact -- $val]
      if { ![llength $linkto] } { reply -err err.key.nofnd $val }
      if { [lexists [lindex $linkto 4] [lindex $mid 0]] } { reply -err err.already.ln }
      regman -author [lindex $linkto 3] -link [concat [lindex $linkto 4] [lindex $mid 0]] \
        [lindex $linkto 1] [lindex $linkto 2]
      reply -return tnx.for.info
    }
    # добавление нового мана
    if { [string first "*" $var] != -1 || [string first "?" $var] != -1 } {
      reply -err err.title.mask
    }
    regman -author $Nick $var $val
    reply -return tnx.for.info
  }
  # просмотр манов
  set text [join [lrange $StdArgs 1 end] { }]
  if { [regexp {^-?(\d+)(\s+|$)} $text - num] } {
    regsub {^-?\d+\s*} $text {} text
    if { $num < 1 } { set num 1 }
  } {
    if { [string trim $text *] eq "" } {
      set num [rand [dbcount]]
    } {
      set num 1
    }
  }
  if { $text == "" } { set text "*" }
  set mlist [dbsearch -- $text]
  if { ![llength $mlist] } { reply -err err.bad.req }
  if { $num > [llength $mlist] } { set num [llength $mlist] }
  set man [lindex $mlist [expr { $num - 1 }]]
  # сохраняем val оригинального мана
  set oval [lindex $man 1]
  # находим слинкованный ман
  set stoplist [list [lindex $man 0]]
  while { [llength [set_ [dbsearch -exact -- [lindex $man 2]]]] } {
    if { [lexists $stoplist [lindex_ 2]] } break
    set man $_
    lappend stoplist [lindex $man 2]
  }
  # man содержит последний ман в цепочке
  # если оригинальный ман и полученый не совпадают
  if { [lindex $man 1] != $oval } {
    set oval [cformat main.orig.page $oval]
  } {
    set oval ""
  }
  # если есть автор
  if { [lindex $man 3] != "" } {
    set ath [cformat main.author [string nohighlight [lindex $man 3]]]
  } {
    set ath ""
  }
  # если есть see also
  if { [llength [lindex $man 4]] } {
    set see [cformat main.seealso [cjoin [lindex $man 4] main.seealso.j]]
  } {
    set see ""
  }
  # если несколько манов совпало
  if { [llength $mlist] > 1 } {
    set num [cformat main.count $num [llength $mlist]]
  } {
    set num ""
  }
  reply -noperson main $num [lindex $man 1] $oval [lindex $man 2] $see $ath
}

::mans::init
