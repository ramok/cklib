
encoding system utf-8
::ck::require cmd   0.4

namespace eval ::recode {
  variable version 1.0
  variable author  "Chpock <chpock@gmail.com>"

  namespace import -force ::ck::cmd::*
}

proc ::recode::init { } {
  cmd register recode_w2k ::recode::run \
    -force-regexp -bind "w(in)?2k(oi)?" -bind "в(ин)?2к(ои)?" -config "recode" -autousage -doc w2k
  cmd register recode_k2w ::recode::run \
    -force-regexp -bind "k(oi)?2w(in)?" -bind "к(ои)?2в(ин)?" -config "recode" -autousage -doc k2w
  cmd register recode_en64 ::recode::run \
    -force-regexp -bind "en(code)?64" -config "recode" -autousage -doc en64
  cmd register recode_de64 ::recode::run \
    -force-regexp -bind "de(code)?64" -config "recode" -autousage -doc de64
  cmd register recode_enurl ::recode::run \
    -bind "urlen|code" -force-regexp -bind "en(code)?url" -config "recode" -autousage -doc urlen
  cmd register recode_deurl ::recode::run \
    -bind "urlde|code" -force-regexp -bind "de(code)?url" -config "recode" -autousage -doc urlde
  cmd register recode_tr ::recode::run \
    -bind "tr" -config "recode" -autousage -doc tr

  config register -id "defencoding" -type encoding -default utf-8 \
    -desc "Кодировка по умолчанию." -access "n" -folder "recode"

  cmd doc -alias urlen -link {w2k de64} urlde \
    {~*!urlde|!urlen* <текст>~ - кодировка/декодировка формата urlencode (%ef%f0%e8%ec%e5%f0)}
  cmd doc -alias en64 -link {urlde w2k} de64 \
    {~*!de64|!en64* <текст>~ - кодировка/декодировка формата base64 (7/Do7OXw)}
  cmd doc -alias k2w -link {urlde de64} w2k \
    {~*!w2k|!k2w* <текст>~ - перекодировка windows-cp1251<->koi8-r.}
  cmd doc tr {~*!tr* <текст>~ - перекодировка русского текста набранного в английской раскладке (rfr nj nfr)}

  msgreg {
    main   &K(&n%s&K)&n %s

    !w2k   win->koi
    !k2w   koi->win
    !en64  encode64
    !de64  decode64
    !enurl urlencode
    !deurl urldecode
    !tr    tr
  }
}
proc ::recode::run { sid } {
  session import
  set type [lindex [split $CmdId _] end]
  regexp {^\S+\s+(.*?)$} $Text - _

  switch -- $type {
    k2w   { set_ [encoding convertfrom koi8-r [encoding convertto cp1251 $_]] }
    w2k   { set_ [encoding convertfrom cp1251 [encoding convertto koi8-r $_]] }
    en64  { set_ [string encode64 -encoding [config get defencoding] $_] }
    de64  { set_ [string decode64 -encoding [config get defencoding] $_] }
    enurl { set_ [string urlencode [encoding convertto [config get defencoding] $_]]   }
    deurl { set_ [encoding convertfrom [config get defencoding] [string urldecode $_]] }
    tr    {
		set trans {q й w ц e у r к t е y н u г i ш o щ p з [ х ] ъ a ф s ы d в f а g п h р j о k л l д ; ж ' э z я x ч c с v м b и n т m ь , б . ю / . Q Й W Ц E У R К T Е Y Н U Г I Ш O Щ P З A Ф S Ы D В F А G П H Р J О K Л L Д : Ж \" Э | / Z Я X Ч C С V М B И N Т M Ь < Б > Ю ?  , & ? }
		lappend trans "{" X "}" Ъ

		set_ [string map  $trans $_]
    }
  }

  reply -uniq main [rawformat !$type] $_
}
