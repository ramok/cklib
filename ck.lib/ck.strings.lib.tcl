
encoding system utf-8

###
# [string stripword <varName> ?<count>?]
#   - strip <count> (default - 1) word in <varName> and return it
# [string stripspace <string>]
#   - replace many space chars with one. Remove leading and trailing characters.
# [string randomstr ?<num>?]
#   - return random string with <num> characters
# [string stripcolor ?<flags...>? <string>]
#   - return <string> with ripped mirc's colors, if <flags> exists, strip only specified codes
#     flags: -color, -bold, -reverse, -underline, -clear
# [string exists <substring> <string>]
#   - return true if <substring> is in <string>
# [string nohighlight <string>]
#   - replace english chars with russian in <string>
# [string isnum ?-int? ?-unsig? <string>]
#   - return true if <string> in valid numerical format
#    -int   : add check for integer type
#    -unsig : add check for unsigned num
# [string trans2rus <string>]
#   - convert <string> form russian-translit to russian
# [string rus2trans <string>]
#   - convert <string> form russian to russian-translit
# [string strongspace <string>]
#   - return <string> with corrected many spaces as thay look in mirc much better %)
# [string hash <string>]
#   - return hash of <string>
# [string encode64 <string>]
#   - return <string> encoded in base64
# [string decode64 <string>]
#   - return <string> decoded from base64
# [string escape -regexp|-tcl <string>]
#   - return <string> with escaped special character for regexp/tcl
# [string 2size <number> ?-bin? ?postfixes list?]
#   - convert <number> to kb/mb/gb.
#     -bin - uses 1000 == 1k

namespace eval ::ck::strings {
  variable version 0.8
  variable author "Chpock <chpock@gmail.com>"

  variable const

  namespace export html
  namespace import -force ::ck::*
}
proc ::ck::strings::init {  } {
  variable const

  set const(lrus)   "ёйцукенгшщзхъфывапролджэячсмитьбю"
  set const(urus)   "ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ"
  set const(leng)   "qwertyuiopasdfghjklzxcvbnm"
  set const(ueng)   "QWERTYUIOPASDFGHJKLZXCVBNM"
  set const(dig)    "0123456789"
  set const(rus)    "$const(lrus)$const(urus)"
  set const(eng)    "$const(leng)$const(ueng)"
  set const(irus)   "ЕеТОоРрАаНКХхСсВМ"
  set const(ieng)   "EeTOoPpAaHKXxCcBM"
  set const(urlen)  [list]
  set const(urlde)  [list]
  set const(urldex) [list]
  set const(mapf)   [list]
  set const(r2t)    "
    й y ц c у u к k е e н n г g ш sh щ sh з z х h ъ ' ф f ы i в v а a п p р r о o л l д d ж zh э e я ya ч ch с s м m и i т t ь ' б b ю yu"

  set const(dehtml) {
        &nbsp; \x20 &quot; \x22 &amp; \x26 &apos; \x27 &ndash; \x2d
        &lt; \x3C &gt; \x3E &tilde; \x7E &euro; \x80 &iexcl; \xA1
        &cent; \xA2 &pound; \xA3 &curren; \xA4 &yen; \xA5 &brvbar; \xA6
        &sect; \xA7 &uml; \xA8 &copy; \xA9 &ordf; \xAA &laquo; \x60
        &not; \xAC &shy; \xAD &reg; \xAE &hibar; \xAF &deg; \xB0
        &plusmn; \xB1 &sup2; \xB2 &sup3; \xB3 &acute; \xB4 &micro; \xB5
        &para; \xB6 &middot; \xB7 &cedil; \xB8 &sup1; \xB9 &ordm; \xBA
        &raquo; \x60 &frac14; \xBC &frac12; \xBD &frac34; \xBE &iquest; \xBF
        &Agrave; \xC0 &Aacute; \xC1 &Acirc; \xC2 &Atilde; \xC3 &Auml; \xC4
        &Aring; \xC5 &AElig; \xC6 &Ccedil; \xC7 &Egrave; \xC8 &Eacute; \xC9
        &Ecirc; \xCA &Euml; \xCB &Igrave; \xCC &Iacute; \xCD &Icirc; \xCE
        &Iuml; \xCF &ETH; \xD0 &Ntilde; \xD1 &Ograve; \xD2 &Oacute; \xD3
        &Ocirc; \xD4 &Otilde; \xD5 &Ouml; \xD6 &times; \xD7 &Oslash; \xD8
        &Ugrave; \xD9 &Uacute; \xDA &Ucirc; \xDB &Uuml; \xDC &Yacute; \xDD
        &THORN; \xDE &szlig; \xDF &agrave; \xE0 &aacute; \xE1 &acirc; \xE2
        &atilde; \xE3 &auml; \xE4 &aring; \xE5 &aelig; \xE6 &ccedil; \xE7
        &egrave; \xE8 &eacute; \xE9 &ecirc; \xEA &euml; \xEB &igrave; \xEC
        &iacute; \xED &icirc; \xEE &iuml; \xEF &eth; \xF0 &ntilde; \xF1
        &ograve; \xF2 &oacute; \xF3 &ocirc; \xF4 &otilde; \xF5 &ouml; \xF6
        &divide; \xF7 &oslash; \xF8 &ugrave; \xF9 &uacute; \xFA &ucirc; \xFB
        &uuml; \xFC &yacute; \xFD &thorn; \xFE &yuml; \xFF &mdash; \x2d
        &bull; \x2a
  }

  if { [catch {rename ::string ::ck::strings::string} errStr] } { rename ::string "" }
  rename ::_string ::string

  set binstr ""
  for {set i 0} {$i < 256} {incr i} {
    set char [format %c $i]
    append binstr $char
    if { $char eq "\n" } {
      set x "%0d%0a"
      set X "%0D%0A"
    } elseif { $char eq " " } {
      set x "+"
    } elseif { [string match {[a-zA-Z0-9-._~]} $char] } {
      set x $char
    } else {
      set x "%[format %02x $i]"
      set X "%[format %02X $i]"
    }
    lappend const(urlen) $char $x
    lappend const(urlde) $x $char
    if { [info exists X] } {
      lappend const(urldex) $X $char
      unset X
    }
  }

  if { ![string equal -length 2 cp $::ck::ircencoding] && ![string equal -length 3 koi $::ck::ircencoding] } {
    set const(validchars) ""
  } {
    set const(validchars) [encoding convertfrom $::ck::ircencoding $binstr]
  }

  foreach x {rus lrus urus eng leng ueng dig} {
    lappend const(mapf) ":${x}:" $const($x)
  }

  return 1
}
proc ::ck::strings::escape { type string } {
  switch -glob -- $type {
    "-reg*" - "reg*" { return [regsub -all {[][${}^?+*()|.\\]} $string {\\\0}] }
    "-tcl" - "tcl"   { return [regsub -all {[][${}\\]} $string {\\\0}] }
    default {
      debug -err "unknown escape type <%s> for string: %s" $type $string
      return ""
    }
  }
}
proc ::ck::strings::2size { args } {
  set bin 0
  set lvl [list "" kb Mb Gb Tb Pb Eb]
  set num [lindex $args 0]
  if { ![isnum -int -unsig $num] } {
    debug -err "bad value <%s> for str2size" $num
    set num 0
  } {
    foreach _ [lrange $args 1 end] {
      if { $_ eq "-bin" } {
        set bin 1
      } {
        set lvl $_
      }
    }
  }
  set bin [expr { $bin ? 1000 : 1024 }]
  set i 0
  while { $num > 999 } {
    set num [expr { 1.0 * $num / $bin }]
    if { $i + 1 >= [llength $lvl] } break { incr i 1 }
  }
  if { [llength [set num [split $num .]]] == 1 } { return [lindex $num 0][lindex $lvl $i] }
  set _ [string trim [lindex $num 1] 0]
  if { [string length [set num [lindex $num 0]]] > 2 || $_ eq "" } { return $num[lindex $lvl $i] }
  append num .
  while { [string length $num] < 4 && $_ ne "" } {
    append num [string index $_ 0]
    set _ [string range $_ 1 end]
  }
  return $num[lindex $lvl $i]
}
proc ::ck::strings::removeinvalid { string } {
  variable const
  if { $const(validchars) == "" } { return $string }
  set _ ""
  foreach c [split $string ""] {
    if { [string first $c $const(validchars)] == -1 } continue
    switch -exact -- $c {
      "—" { append _ "-" }
      "«" { append _ "<" }
      "»" { append _ ">" }
      default { append _ $c }
    }
  }
  return $_
}
proc ::ck::strings::stripword {xstr} {
  if { [llength $xstr] > 1 } {
    set count [lindex $xstr 1]
    set xstr [lindex $xstr 0]
    incr count -1
  } {
    set count 0
    set xstr [lindex $xstr 0]
  }
  upvar 2 $xstr str
  set str [split $str]
  set ret [join [lrange $str 0 $count]]
  set str [string trimleft [join [lreplace $str 0 $count]]]
  return $ret
}
proc ::ck::strings::stripspace { str } {
  return [string trim [regsub -all {[\r\n\t\s]+} $str { }]]
}
proc ::ck::strings::randomstr { {nums 10} } {
  variable const
  if { [regexp {^0*(\d+)$} $nums - nums] } {
    while { [incr nums -1] > -1 } {
      append ret [binary format c [expr {int(26*rand()) + 65 + 32 * int(2*rand())}]]
    }
  } {
    foreach _ [split [lindex {31 56 01 032 542 076 02 32 56 01 89} [expr int(11*rand())]] {}] {
      set _ [lindex $const(randstr) $_]
      append ret [lindex $_ [expr {int([llength $_]*rand())}]]
    }
  }
  return [expr {[info exists ret]?$ret:{}}]
}
proc ::ck::strings::stripcolor { args } {
  if { ![llength $args] } { return "" }
  if { [llength $args] == 1 } {
    return [regsub -all "(\026|\002|\037|\017|\003\[0-9\]{1,2}(,\[0-9\]{1,2})?)" [lindex $args 0] {}]
  }
  set ex [list]
  foreach _ [lrange $args 0 end-1] {
    switch -glob -- $_ {
      -col* { lappend ex "\003\[0-9\]{1,2}(,\[0-9\]{1,2})?" }
      -bol* { lappend ex "\002" }
      -rev* { lappend ex "\026" }
      -und* { lappend ex "\037" }
      -cle* { lappend ex "\017" }
      default { debug -warn "Bad option to stripcolor: %s" $_ }
    }
  }
  if { ![llength $ex] } { return [lindex $args end] }
  return [regsub -all "([join $ex |])" [lindex $args end] {}]
}
proc ::ck::strings::exists {char str} {
  if { [string first $char $str] == -1 } { return 0 } { return 1 }
}
proc ::ck::strings::char_invert {char} {
  variable const
  if { [set pos [string first $char $const(ieng)]] != -1 } { return [string index $const(irus) $pos] }
  if { [set pos [string first $char $const(irus)]] != -1 } { return [string index $const(ieng) $pos] }
  return $char
}
proc ::ck::strings::nohighlight {str} {
  set tmp ""
  foreach char [split $str ""] { append tmp [char_invert $char] }
  return $tmp
}
proc ::ck::strings::rus2trans {str} {
  variable const
  array set map $const(r2t)
  set l [llength [set str [split $str [set ret ""]]]]
  for { set i 0 } { $i < $l } { incr i } {
    set o [string tolower [set _ [lindex $str $i]]]
    if { [info exists map($o)] } {
      if { $o eq $_ } {
	set _ $map($o)
      } elseif { [string length $map($o)] == 1 || ($i + 1 == $l) \
        || [string toupper [lindex $str [expr { $i + 1 }]]] eq [lindex $str [expr { $i + 1 }]] } {
	  set _ [string toupper $map($o)]
      } else {
	set _ [string totitle $map($o)]
      }
    }
    append ret $_
  }
  return $ret
}
proc ::ck::strings::trans2rus { args } {
  set str [lindex $args 0]
  return [string map \
    {sch щ sh' щ sh ш zh ж ya я ch ч ck к yu ю i и j й c ц y й u у k к e е n н g г w в z з x х h х ' ь f ф v в a а p п r р o о l л
       d д s с m м t т b б} $str]
}
proc ::ck::strings::isnum { args } {
  set str [lindex $args end]
  set args [lrange $args 0 end-1]
  getargs -type choice [list "-int" "-float"] -unsig flag
  set patt "^"
  if { !$(unsig) } {
    append patt "-?"
  }
  if { $(type) == 0 } {
    append patt {[0-9]+}
  } else {
    append patt {[0-9]*\.[0-9]+}
  }
  append patt {$}
  return [regexp -- $patt $str]
}
proc ::ck::strings::isrus { args } {
  variable const
  return [regexp "\[$const(lrus)$const(urus)\]" [lindex $args 0]]
}
proc ::ck::strings::untag {str} {
  regsub -all -- {<.*?>} $str {} str
  return $str
}
proc ::ck::strings::unspec {str} {
  variable const
  set ret ""
  while { [regexp {^(.*?)&#(\d{1,4});(.*)$} $str - p e str] } {
    append ret $p [format %c [string trimleft $e 0]]
  }
  set str [append ret $str]
  set str [string map -nocase $const(dehtml) $str]
  return $str
}
proc ::ck::strings::html {args} {
  set cmd [lindex $args 0]
  switch -- $cmd {
    untag   { return [uplevel 1 [list ::ck::strings::untag [lindex $args 1]]] }
    parse   { return [uplevel 1 [concat "::ck::strings::parse_html" [lrange $args 1 end]]] }
    unspec  { return [uplevel 1 [list ::ck::strings::unspec [lindex $args 1]]] }
    default {
      debug -err "Unknown cmd: $cmd"
    }
  }
}
proc ::ck::strings::parse_html { args } {
  getargs \
   -tag str "" -spec str "" -text str "" \
   -stripspace flag -stripbadchar flag
  uplevel 1 {set _parsed ""}
  set string [lindex $args 0]
  regsub -all {<!--.*?-->} $string {} string
  array set specs [list "quot" "'" "gt" ">" "lt" "<" "copy" "(c)" "amp" "&" "nbsp" " "]
  while { [regexp -indices -nocase {([^<]*?)(&(?:[a-z]{2,7}|#\d{1,4});|</?[^>]+>)} $string - pre aft] } {
    debug -debug "next! pre:%s: aft:%s:" [string range $string [lindex $pre 0] [lindex $pre 1]] [string range $string [lindex $aft 0] [lindex $aft 1]]
    if { [lindex $pre 1] != -1 } {
      if { $(text) ne "" } {
	uplevel 1 [list set _text [string range $string [lindex $pre 0] [lindex $pre 1]]]
	uplevel 1 $(text)
      } {
	uplevel 1 [list append _parsed [string range $string [lindex $pre 0] [lindex $pre 1]]]
      }
    }
    set spec [string range $string [lindex $aft 0] [lindex $aft 1]]
    if { [string index $spec 0] eq {&} } {
      set spec [string tolower [string range $spec 1 end-1]]
      if { [string index $spec 0] eq "#" } {
        set spec_r [format %c [string trimleft [string range $spec 1 end] 0]]
      } elseif { [info exists specs($spec)] } {
	set spec_r $specs($spec)
      } {
	set spec_r ""
      }
      if { $(spec) ne "" } {
	uplevel 1 [list set _spec $spec]
	uplevel 1 [list set _replace $spec_r]
	uplevel 1 $(spec)
      } elseif { $spec_r ne "" } {
	uplevel 1 [list append _parsed $spec_r]
      }
    } elseif { $(tag) ne "" } {
      regexp {^<(/?)([^>\s]+)\s*([^>]*)} $spec - tag_state tag tag_param
      uplevel 1 [list set _tag [string tolower $tag]]
      uplevel 1 [list set _tag_open [expr { $tag_state eq "" }]]
      uplevel 1 [list set _tag_param $tag_param]
      uplevel 1 $(tag)
    }
    set string [string range $string [expr { [lindex $aft 1] + 1 }] end]
  }
  if { $string ne "" } {
    if { $(text) ne "" } {
      uplevel 1 [list set _text $string]
      uplevel 1 $(text)
    } {
      uplevel 1 [append _parsed $string]
    }
  }
  if { $(stripbadchar) } {
    uplevel 1 { set _parsed [::ck::strings::removeinvalid $_parsed] }
  }
  if { $(stripspace) } {
    uplevel 1 { set _parsed [::ck::strings::stripspace $_parsed] }
  }
}
proc ::ck::strings::strongspace {str} {
  regsub -all "  " $str " \240" str
  return $str
}
proc ::ck::strings::hash {str} {
  return [md5 $str]
}
proc ::ck::strings::urlencode {str} {
  variable const
  return [string map $const(urlen) $str]
}
proc ::ck::strings::urldecode {str} {
  variable const
  return [string map $const(urldex) [string map $const(urlde) $str]]
}
### Ripped from wiki
proc ::ck::strings::encode64 { args } {
  getargs -encoding str "utf-8"
  set string [lindex $args 0]
  if { $(encoding) != "" } {
    set string [encoding convertto $(encoding) $string]
  }
  set i 0
  foreach char [ list A B C D E F G H I J K L M N O P Q R S \
                      T U V W X Y Z a b c d e f g h i j k l m n o \
                      p q r s t u v w x y z 0 1 2 3 4 5 6 7 8 9 + / ] {
    set tmp($char) $i
    lappend b64 $char
    incr i
  }
  set result {}
  set state  0
  set length 0
  binary scan $string c* X
  foreach { x y z } $X {
    append result [lindex $b64 [expr {($x >>2) & 0x3F}]]
    if { $y != {} } {
      append result [lindex $b64 [expr {(($x << 4) & 0x30) | (($y >> 4) & 0xF)}]]
      if { $z != {} } {
        append result [lindex $b64 [expr {(($y << 2) & 0x3C) | (($z >> 6) & 0x3)}]]
        append result [lindex $b64 [expr {($z & 0x3F)}]]
      } else {
        set state 2
        break
      }
    } else {
      set state 1
      break
    }
    incr length 4
  }
  if { $state == 1 } {
    append result [lindex $b64 [expr {(($x << 4) & 0x30)}]]==
  } elseif { $state == 2 } {
    append result [lindex $b64 [expr {(($y << 2) & 0x3C)}]]=
  }
  return $result
}
### Ripped from tcllib
proc ::ck::strings::decode64 { args } {
  getargs -encoding str "utf-8"
  set string [lindex $args 0]
  if {[string length $string] == 0} {return ""}

  set chars {A B C D E F G H I J K L M N O P Q R S T U V W X Y Z \
	     a b c d e f g h i j k l m n o p q r s t u v w x y z \
	     0 1 2 3 4 5 6 7 8 9 + /}
  set base64 [list]
  scan z %c len
  for {set i 0} {$i <= $len} {incr i} {
    set char [format %c $i]
    if { [set pos [lsearch -exact $chars $char]] == -1 } {
      set val {}
    } else {
      set val $pos
    }
    lappend base64 $val
  }
  scan = %c i
  set base64 [lreplace $base64 $i $i -1]

  set output ""

  binary scan $string c* X
  foreach x $X {
    set bits [lindex $base64 $x]
    if {$bits >= 0} {
      if {[llength [lappend nums $bits]] == 4} {
        foreach {v w z y} $nums break
	set a [expr {($v << 2) | ($w >> 4)}]
	set b [expr {(($w & 0xF) << 4) | ($z >> 2)}]
	set c [expr {(($z & 0x3) << 6) | $y}]
	append output [binary format ccc $a $b $c]
	set nums {}
      }
    } elseif {$bits == -1} {
      foreach {v w z} $nums break
      set a [expr {($v << 2) | (($w & 0x30) >> 4)}]

      if {$z == {}} {
	append output [binary format c $a ]
      } else {
	set b [expr {(($w & 0xF) << 4) | (($z & 0x3C) >> 2)}]
	append output [binary format cc $a $b]
      }
      break
    } else continue
  }
  if { $(encoding) != "" } {
    set output [encoding convertfrom $(encoding) $output]
  }
  return $output
}
proc _string {args} {
  set cmd  [lindex $args 0]
  switch -- $cmd {
    filter      -
    regfilter   -
    allow       -
    stripspec   -
    stripword   -
    stripspace  -
    stripcolor  -
    exists      -
    nohighlight -
    random      -
    isnum       -
    isrus       -
    rus2trans   -
    trans2rus   -
    strongspace -
    hash        -
    encode64    -
    decode64    -
    removeinvalid -
    randomstr   -
    urlencode   -
    2size       -
    escape      -
    urldecode  {
      return [uplevel 1 [concat "::ck::strings::$cmd" [lrange $args 1 end]]]
    }
    default {
      return [uplevel 1 [concat "::ck::strings::string" $args]]
    }
  }
}

namespace eval ::ck::strings {
  set const(randstr) [split {ambi ana ani alte ante anti arti arche astro audi auto bene beta bio casca caco chrono coma contra cosmo data dada de deci demo deo deve dia divi digi dino domi dyna eco ecto ego endo envi ephe epi exti exi exo expe ergo gene geo giga hare hero homo hype idio inde infra inte inno juno jupi kilo kimo leo levi loca lutho macro mani maxi medi mega meso meta micro moni mono multi nano nemo nitro origi optio octo oxy para pata pate peri phobo photo plexi poly porta pre pro proto pyro quadro rama retro scie solo stella synthe techno tele tetra theo uni uno uto venu vento visi vita xeno xero xylo zero zoo ratio ange visa casa cali empi aphe kine xepha agei analo helio huma esca xyle iso tide sibe nige muti gara via equa yuca auro wake luna cata love zodi mona karma asce gaya neuro kaba guru cano cine abra arie aspi teni tene
  llic phor dical soft logy graph phys tics nicle nom ster can tone biz naut tech thron tech dor tive zos pher gen pia span ther haust dus corp cope phon lus lex ware gyn cine cate cal tion mode cide tism lize pose rage nous mous scan noid lous tate gog ture gure tor nure log reux tome vert duce thes rior cede spect byte cept red cent bol dox tox flex morph sty duct dict chron size city blic ntial nct ges nce lyse lope scope scape ridge stence bulb tium polis sphan mim dies logue gon xote lio tres res chre field shell ngle cale que line lite tigue pad spec rian nsion late taur tame twine liga teau ria zed nos xas lum nation dew tigo lood son reth tinus phia rast bert gion bura ding soph tent xtra nite cles sim kreuz dom spect bis ward duce lypse kone type
  ph m n th ss le ne ct sh ck me nt ng ze re x t ge gue p ve nse pe ns pa val ca net de ros gh stre ble rth
  ba be bee bha bi bo by ca ce che co cy da de di do dre fe fi ga ge gi gy ha he hi ho la le li lo ly ma me mi mo my na ne ni no ny pa pe po pre pro qe ra re ru ri ro sa se si so su ta te the ti to tu va ve vi wa we wi wy wo xa xe za ze zo
  a a e e i i o y u u a a a e e i i o y u
  dolph nesp cans spew fram less flath nith prem spins touch beat nons conc camp gaul latr faust cribl nitr easth trad spec electr naut nimr cell consp misd pack sub atom art under over kitch sink evil subv tank genr past scam futur steel thorn bend plag fount nedt sweep gemin coax neon domin kawl junct super grac juxt velv spac saturn nucl plut atlant germ spast bisc synchr mond carib phot solid ether kant meltm rept quand prox emper arcad theat gnom cloud goth carp jerom caplet deler cryst trib esth epil proph saur dayl loung scorp meph dynam babyl orang viol cabal sulph magn dethr apoll maeson hermet mund mechan glyph plex gnost mercur uriz pyth spagyr cansel caduc tart conq sublim axiom ascend mater script oracul hasid phar proph gener cecil gang cath temp apostl goeth ocean virg unic spectr yeat zetz quant quint revel prot
  os us et ia ism or ace age ator ion alon ama es ong ola ex ax ice ic ox ute ima en im ant er on io ite ure ica eus et
  b c d f g h j k l m n p q r s t v w b b c c d d g g h k l m m n n p p r r s s t t v w
  ten sub art con lab nor pan pop nax top tel dig nap ban tip sep hot mud wet cat man pro pre win tub sun pet nil bed hit lan zen god
  ant tor tic ist set net cer can end let van tos gen sat gel star ster son dad site bat ter pix vet test line met mag land med tra tox biz tag fin rod ware soft run est} \n]
}
