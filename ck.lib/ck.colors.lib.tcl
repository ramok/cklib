
namespace eval ::ck::colors {
  variable version 0.3
  variable ansi
  variable mirc
  variable form
  variable a2m [list]
  variable m2a [list]
  variable f2m [list "&&" "&"]
  variable f2a [list "&&" "&"]
  variable f2e [list "&&" "&"]

  set ansi(cl) "\033\[0m"
  set ansi(ul1) "\033\[4m"
  set ansi(ul0) "\033\[24m"
  set ansi(bl1) "\033\[1m"
  set ansi(bl0) "\033\[22m"
  set ansi(blk) "\033\[0;30m"
  set ansi(blu) "\033\[0;34m"
  set ansi(grn) "\033\[0;32m"
  set ansi(cyn) "\033\[0;36m"
  set ansi(red) "\033\[0;31m"
  set ansi(mag) "\033\[0;35m"
  set ansi(yel) "\033\[0;33m"
  set ansi(wht) "\033\[0;37m"
  set ansi(hblk) "\033\[1;30m"
  set ansi(hblu) "\033\[1;34m"
  set ansi(hgrn) "\033\[1;32m"
  set ansi(hcyn) "\033\[1;36m"
  set ansi(hred) "\033\[1;31m"
  set ansi(hmag) "\033\[1;35m"
  set ansi(hyel) "\033\[1;33m"
  set ansi(hwht) "\033\[1;37m"
# TODO: quick hack
  set ansi(ul) "\033\[4m"
  set ansi(bl) "\033\[1m"

  set mirc(cl) "\017"
  set mirc(ul) "\037"
  set mirc(bl) "\002"
  set mirc(blk) "\00301"
  set mirc(blu) "\00302"
  set mirc(grn) "\00303"
  set mirc(cyn) "\00310"
  set mirc(red) "\00305"
  set mirc(mag) "\00306"
  set mirc(yel) "\00307"
  set mirc(wht) "\00315"
  set mirc(hblk) "\00314"
  set mirc(hblu) "\00312"
  set mirc(hgrn) "\00309"
  set mirc(hcyn) "\00311"
  set mirc(hred) "\00304"
  set mirc(hmag) "\00313"
  set mirc(hyel) "\00308"
  set mirc(hwht) "\00300"

  set form(cl) "&n"
  set form(ul) "&U"
  set form(bl) "&L"
  set form(blk) "&k"
  set form(blu) "&b"
  set form(grn) "&g"
  set form(cyn) "&c"
  set form(red) "&r"
  set form(mag) "&p"
  set form(yel) "&y"
  set form(wht) "&w"
  set form(hblk) "&K"
  set form(hblu) "&B"
  set form(hgrn) "&G"
  set form(hcyn) "&C"
  set form(hred) "&R"
  set form(hmag) "&P"
  set form(hyel) "&Y"
  set form(hwht) "&W"

  foreach id [array names mirc] {
    if { [info exist form($id)] } {
      lappend f2m $form($id) $mirc($id)
      lappend f2a $form($id) $ansi($id)
      lappend f2e $form($id) ""
    }
    if { [info exist ansi($id)] } {
      lappend m2a $mirc($id) $ansi($id)
      lappend a2m $ansi($id) $mirc($id)
    }
  }

  namespace import -force ::ck::*
  namespace export color
  namespace export cformat stripformat
}
proc ::ck::colors::mirc2ansi {str} {
  variable m2a
  variable ansi
  variable mirc

  regsub -all -- "$mirc(ul)(.*?)$mirc(ul)" $str "$ansi(ul1)\\1$ansi(ul0)" str
  regsub -all -- "$mirc(ul)(.*?)$mirc(cl)" $str "$ansi(ul1)\\1$mirc(cl)"  str
  set str [string map [list $mirc(ul) $ansi(ul1)] $str]

  regsub -all -- "$mirc(bl)(.*?)$mirc(bl)" $str "$ansi(bl1)\\1$ansi(bl0)" str
  regsub -all -- "$mirc(bl)(.*?)$mirc(cl)" $str "$ansi(bl1)\\1$mirc(cl)"  str
  set str [string map [list $mirc(bl) $ansi(bl1)] $str]

  set str [string map $m2a $str]
  append str $ansi(cl)
  return $str
}
proc ::ck::colors::color {args} {
  set cmd [lindex $args 0]
  switch -- $cmd {
    mirc2ansi { return [mirc2ansi [lindex $args 1]] }
    splittext  { return [eval [concat splittext [lrange $args 1 end]]] }
    default {
      debug -warn "Unknown cmd: $cmd"
    }
  }
}
proc ::ck::colors::cformat { args } {
  variable f2m
  set txt [string map $f2m [lindex $args end]]
  if { [llength $args] > 1 } {
    if { [string match "-optcol*" [lindex $args 0]] } {
      regsub -all "(\003)0(\\d\\D)" $txt {\1\2} txt
    }
  }
  return $txt
}
proc ::ck::colors::stripformat { text } {
  variable f2e
  return [string map $f2e $text]
}
proc ::ck::colors::splittext { args } {
  set txt [split [lindex $args end] {}]
  set args [lrange $args 0 end-1]
  getargs -width int 80 -minwords int 3 -maxlines int 0

  if { $(maxlines) > 0 } {
    set txt [lrange $txt 0 [expr { $(width) * $(maxlines) }]]
  }

  set result [list]
  set current ""
  array set cr {c "" b 0 u 0 r 0}
  array set sv {c "" b 0 u 0 r 0}
  set lastwstart 0
  set iswordnow  0
  set wcount     0
  set len [llength $txt]
  set chw [set chn ""]
  set curwidth 0
  for { set i 0 } { $i < $len } { incr i } {
    set slen 1
    if { [regexp {\w} [set _ [lindex $txt $i]]] } {
      set type w
    } elseif { $_ eq "\003" } {
      if { [string match {[0-9]} [lindex $txt [incr i]]] } {
	append _ [lindex $txt $i]
	if { [string match {[0-9]} [lindex $txt [incr i]]] } {
	  append _ [lindex $txt $i]
	  if { [lindex $txt [incr i]] eq "," } {
	    append _ [lindex $txt $i]
	    if { [string match {[0-9]} [lindex $txt [incr i]]] } {
	      append _ [lindex $txt $i]
	      if { [string match {[0-9]} [lindex $txt [incr i]]] } {
		append _ [lindex $txt $i]
	      } { incr i -1 }
	    } { incr i -1 }
	  } { incr i -1 }
	} { incr i -1 }
	set type c
	set slen [string length $_]
      } {
        incr i -1
	set type n
      }
    } elseif { [string first $_ "\002\017\037\026"] != -1 } {
      set type c
    } else {
      set type n
    }
    if { $curwidth + $slen > $(width) } {
      if { [string match "\[ \t\r\n\]" $_] } {
	set iswordnow 0
	continue
      }
      if { ($type eq "w" && !$iswordnow) || $(minwords) >= $wcount } {
        set x $current
	set current ""
	array set sv [array get cr]
      } {
        set x [string range $current 0 [expr { $lastwstart - 1 }]]
	set current [string range $current $lastwstart end]
      }
      lappend result [regsub -all "\\s*(\026|\002|\037|\017|\003\[0-9\]{1,2}(,\[0-9\]{1,2})?)*\\s*\$" $x {}]
      if { $(maxlines) > 0 && [llength $result] == $(maxlines) } { return $result }
      set x $sv(c)
      if { $sv(b) } { append x "\002" }
      if { $sv(u) } { append x "\037" }
      if { $sv(r) } { append x "\026" }
      set lastwstart [string length $x]
      set curwidth [string length [set current [append x $current]]]
      unset x
      set wcount 1
    }
    if { $type eq "c" } {
      switch -glob -- $_ {
	"\002"  { set cr(b) [expr { !$cr(b) }] }
	"\017"  { array set cr {c "" b 0 u 0 r 0} }
	"\037"  { set cr(u) [expr { !$cr(u) }] }
	"\003*" { set cr(c) $_ }
	"\026"  { set cr(r) [expr { !$cr(r) }] }
      }
    } elseif { $type eq "n" } {
      set iswordnow 0
    } elseif { !$iswordnow } {
      set iswordnow 1
      array set sv [array get cr]
      set lastwstart [string length $current]
      incr wcount
    }
    incr curwidth $slen
    append current $_
  }
  if { $current ne "" } { lappend result $current }
  return $result
}

#proc w { args } {
#  putlog "s:[join $args]"
#  putlog "w:123456789012345678901234567890:"
#  foreach _ [::ck::colors::splittxt -width 30 [join $args]] {
#    putlog "w:${_}\017:"
#  }
#}
