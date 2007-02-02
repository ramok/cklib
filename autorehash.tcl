
# Скрипт для авторехаша при изменении каких либо файлов скриптов
# Warning! Не использовать если не знаете точно что нужен!

encoding system utf-8
::ck::require config

namespace eval autorehash {
  variable version 0.1
  variable author "Chpock <chpock@gmail.com>"
  variable detected

  namespace import -force ::ck::*
  namespace import -force ::ck::config::config
}

proc ::autorehash::init {  } {
  config register -id "delay" -type time -default 3m \
    -desc "Delay for rehash after change of files detected." -access "n" -folder "autorehash"
  config register -id "notify" -type str -default "n" \
    -desc "Global flags of users for notify about autorehash." -access "n" -folder "autorehash"
  etimer -interval 1m ::autorehash::run
  catch { unset ::autorehash::detected }
}

proc ::autorehash::run {  } {
  if { [catch {set ::autorehash::detected} t] } {
    foreacharray ::ck::loaded {
      if { ![file exists $k] || [file mtime $k] != $v } {
	debug -debug "Detected change file <%s> at <%s>, rehash delayed..." $k [clock seconds]
	set ::autorehash::detected [clock seconds]
	return
      }
    }
    debug -debug "No changes."
    return
  }
  if { [expr { [clock seconds] - $t }] < [config get "delay"] } {
    debug -debug "delay prossed..."
    return
  }
  set_ [list]
  foreacharray ::ck::loaded {
    if { ![file exists $k] || [file mtime $k] != $v } {
      lappend_ [file tail $k]
    }
  }
  set_ [join_ "\00314\002\002, \00304"]
  if { [config get "notify"] ne "" } {
    set n [list]
    foreach c [channels] {
      set n [concat $n [chanlist $c [config get "notify"]]]
    }
    if { [llength $n] } {
      foreach n [luniq $n] {
	putquick "NOTICE $n :\00310Auto-rehash due change of\00314:\0034 $_"
      }
    }
  }
  after idle rehash
}
