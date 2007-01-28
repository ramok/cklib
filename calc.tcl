
encoding system utf-8
::ck::require cmd 0.2

namespace eval calc {
  variable version 1.1
  variable author  "Chpock <chpock@gmail.com>"

  namespace import -force ::ck::cmd::*
}

proc ::calc::init {} {
  cmd register calc ::calc::run -autousage -doc "calc" \
    -bind "cal|culate" -bind "math" -bind "кальк|улятор"

  cmd doc -link [list "calc.ip"] "calc" {~*!calc* <expression>~ - calculate expression.}
  cmd doc -link [list "calc"] "calc.ip" {~*!calc* ip <ip>/<mask>~ - calculate ip network/broadcast/host range.}

  config register -id "show.bin" -type bool -default 0 \
    -desc "Показывать ли двоичное представление результата." -access "m" -folder "calc"
  config register -id "show.hex" -type bool -default 1 \
    -desc "Показывать ли шестнадцатеричное представление результата." -access "m" -folder "calc"
  config register -id "show.oct" -type bool -default 1 \
    -desc "Показывать ли восьмеричное представление результата." -access "m" -folder "calc"


  msgreg {
    main %s&K =&n&L %s%s
    main.hex   &nHex: &p0x%s
    main.oct   &nOct: &p0%s
    main.bin   &nBin: &p%s
    main.join  "&K; "
    main.add   " &K(%s&K)"
    ip   %s&K =&n %s
    ip.minhost &cMinHost&K(&p%s&K)
    ip.maxhost &cMaxHost&K(&p%s&K)
    ip.bcast   &cBcast&K(&p%s&K)
    ip.hosts   &cHostCount&K(&p%s&K)
    err.expr     Error in expression.
    err.bad.mask Invalid netmask.
    err.bad.ip   Invalid IP address.
  }
}

proc ::calc::run { sid } {
  session export
  regsub -all -- {[{}\[\]\$\\"']} [join [lrange $StdArgs 1 end] " "] "" ex
  if { [regexp -nocase {^ip\s+(.+)$} $ex - ex] } {
    if { ![regexp {^(\d+\.\d+\.\d+\.\d+)/(\d+)$} $ex - ip mask] } {
      replydoc calc.ip
    }
    foreach_ [split $ip .] { if { $_ > 255 } { reply -err bad.ip } }
    if { $mask > 31 } { reply -err bad.mask }
    set numip [ip2num $ip]
    set mask  [expr { 32 - $mask }]
    set minhost [expr { ($numip >> $mask) << $mask }]
    for { set maxhost $minhost; set i 0 } { $i < [expr { $mask - 1}] } { incr i } {
      set maxhost [expr { $maxhost | (2 << $i) }]
    }
    set bcast   [expr { $maxhost + 1 }]
    incr minhost
    if { $mask == 1 } {
      set hosts 2
    } {
      set hosts   [expr { (2 << ($mask - 1)) - 2 } ]
    }
    set out [list]
    lappend out [cformat ip.minhost [num2ip $minhost]]
    lappend out [cformat ip.maxhost [num2ip $maxhost]]
    lappend out [cformat ip.bcast   [num2ip $bcast]]
    lappend out [cformat ip.hosts    $hosts]
    reply -uniq -return ip $ex [cjoin $out { }]
  }
  if { [catch {expr 1.0 * $ex} val] } {
    reply -err expr
  }
  if { [lindex [split $val .] 1] == 0 } { set val [lindex [split $val .] 0] }
  set_ [list]
  if { [config get show.hex] } { lappend_ [cformat main.hex [format %x [expr { int($val) }]]] }
  if { [config get show.oct] } { lappend_ [cformat main.oct [format %o [expr { int($val) }]]] }
  if { [config get show.bin] } {
    set x [expr { int($val) }]
    binary scan [binary format I1 [expr { int($val) }]] B* x
    lappend_ [cformat main.bin [string trimleft $x 0]]
  }
  if { [llength_] } { set_ [cformat main.add [cjoin $_ main.join]] }
  reply -uniq main $ex $val $_
}
