
namespace eval ::ck::colors {
  variable version 0.2
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
    default {
      moderror "Unknown cmd: $cmd"
    }
  }
}
proc ::ck::colors::cformat { text } {
  variable f2m
  return [string map $f2m $text]
}
proc ::ck::colors::stripformat { text } {
  variable f2e
  return [string map $f2e $text]
}

