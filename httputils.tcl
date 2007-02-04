
encoding system utf-8
::ck::require cmd   0.4
::ck::require http  0.2

namespace eval httputils {
  variable version 1.0
  variable author  "Chpock <chpock@gmail.com>"

  namespace import -force ::ck::cmd::*
  namespace import -force ::ck::http::http
}
proc ::httputils::init {} {

  cmd register httphead ::httputils::httphead \
    -bind "http" -autousage -doc "http"
  cmd register httpheadadv ::httputils::httphead \
    -bind "http\\+" -autousage -doc "http" -config httphead

  cmd doc "http" {~*!http* <url>~ - получить информацию об URL.}

  msgreg {
    err  &nError&K(&R%s&K)&n while request url&K(&B%s&K):&r %s&n.
    err.adv &nError&K(&R%s&K)&n while request advanced info on url&K(&B%s&K):&r %s&n.
    hh.main &K[&nHTTP &B%s&n %s&K]&n %s
    hh.size &nSize&K:&c %s&n bytes
    hh.file &nFile&K:&c %s
    hh.loc  &nLocation&K:&B %s
    hh.serv &nServer&K:&B %s
    hh.join "&K; "
    hh.noinfo &nNo usefull information on url &B%s
    total   &pTotal&K:&n%s
    html    &phtml&K:&n%s&K(&c%s&K)
    html1   &phtml&K:&n%s
    html.fr  &pframe&K:&c%s
    html.ifr &piframe&K:&c%s
    html.j   &K;
    img      &pimg&K:&n%s&K(%s&K)
    img.main &phtml&K:&c%s&K/&c%s
    img.css &pcss&K:&c%s&K/&c%s
    img.j   &K;
    js      &pjs&K:&n%s&K(&n%s&K)
    css     &pcss&K:&n%s&K(&n%s&K)
    mm      &pmm&K:&n%s
    other   &pother&K:&n%s
    title   &ptitle&K:<&B%s&K>
    url     &purl&K:&U&B%s&U
    gzip.on  &pgzip&K:&Gon
    gzip.off &pgzip&K:&boff
    err.adv.big &rОбщий объем страницы &B&U%s&U&r слишком велик. &K(&R%s&K)
    err.adv.prs &rОшибка разбора дополнительной информации об url &B&U%s&U&r.
  }
}
proc ::httputils::httphead { sid } {
  session import

  if { $Event == "CmdPass" } {
    session set ReqUrl [join [lrange $StdArgs 1 end] " "]
    http run $ReqUrl -head -mark "Head"
    return
  }

  if { $Mark eq "Head" } {
    if { $HttpStatus < 0 } {
      reply -err err $HttpStatus $HttpUrl $HttpError
    }
    set file ""
    set serv ""
    set xpow [list]
    set istext 0
    foreachkv $HttpMeta {
      switch -- $k {
	"Content-Type" {
	  if { [string match -nocase "text/html*" $v] } {
	    set istext 1
	  }
	}
	"Content-Disposition" {
	  foreach_ [split $v {;}] {
	    set_ [split [string trim $_] =]
	    if { [lindex $_ 0] != "filename" } continue
	    set file [string trim [join [lrange $_ 1 end] =] "\""]
	  }
	}
	"Server" {
	  append serv $v " "
	}
	"X-Powered-By" {
	  lappend xpow $v
	}
      }
    }
    if { $istext && [string index $HttpMetaCode 0] == "2" && $CmdId eq "httpheadadv" } {
      http run "http://www.websiteoptimization.com/services/analyze/wso.php?url=$ReqUrl" -mark "AdvInfo" -return
    }
    set_ [list [cformat hh.main $HttpMetaCode $HttpMetaMessage $HttpMetaType]]
    if { $HttpMetaLength != "" } { lappend_ [cformat hh.size $HttpMetaLength] }
    if { $file != "" } { lappend_ [cformat hh.file $file] }
    if { $HttpMetaLocation != "" } { lappend_ [cformat hh.loc $HttpMetaLocation] }
    foreach x $xpow {
      if { [string first $x $serv] != -1 } continue
      append serv $x " "
    }
    set serv [string trim $serv]
    if { $serv != "" } { lappend_ [cformat hh.serv $serv] }

    if { [llength_] } {
      reply -uniq [cjoin $_ hh.join]
    } {
      reply -uniq hh.noinfo $HttpUrl
    }
  } elseif { $Mark eq "AdvInfo" } {
    if { $HttpStatus < 0 } {
      reply -err adv $HttpStatus $ReqUrl $HttpError
    }
    regfilter {^.*</form>} HttpData
    regfilter -nocase {^.*?</script>} HttpData
    regfilter {<h2>Analysis and Recommendations</h2>.*$} HttpData
    if { ![regexp {<table\s.*?<th>URL:.*?<td>(.*?)</td>.*<th>Title:.*?<td>(.*?)</td>.*?</table>\s*(.*)$} $HttpData - url title HttpData] } {
      reply -err adv.prs $ReqUrl
    }
    if { [regexp {The size of this web page \((\d+) bytes\) has exceeded the maximum size of 1000000 bytes.} $title - szTotal] } {
      reply -err adv.big $ReqUrl [msz $szTotal]
    }
    regexp {<table\s.*?<tr\s.*?<tr\s.*?<td>(\d+)\s.*?</table>(.*)$} $HttpData - szTotal HttpData

    regexp -nocase {<!--\sstart object size[^>]+?>\s*(.*?)\s*<!--\sendof object size[^>]+?>(.*)$} $HttpData - DataSize HttpData
    regexp -nocase {<!--\sstart ext[^>]+?>\s*(.*?)\s*<!--\sendof ext[^>]+?>(.*)$} $HttpData - DataExt HttpData

    regexp {<td>HTML:.*?<td>(\d+)<} $DataSize - szHtml
    regexp {<td>HTML Im.*?<td>(\d+)<} $DataSize - szImgHtml
    regexp {<td>CSS Im.*?<td>(\d+)<} $DataSize - szImgCSS
    regexp {<td>Total Im.*?<td>(\d+)<} $DataSize - szImg
    regexp {<td>Java.*?<td>(\d+)<} $DataSize - szJS
    regexp {<td>CSS:.*?<td>(\d+)<} $DataSize - szCSS
    regexp {<td>Multi.*?<td>(\d+)<} $DataSize - szMM
    regexp {<td>Other.*?<td>(\d+)<} $DataSize - szOther

    regexp {<td>Total HTML:.*?<td>(\d+)<} $DataExt - cnHtml
    regexp {<td>Total HTML Imag.*?<td>(\d+)<} $DataExt - cnImgHtml
    regexp {<td>Total CSS Imag.*?<td>(\d+)<} $DataExt - cnImgCSS
    regexp {<td>Total Ima.*?<td>(\d+)<} $DataExt - cnImg
    regexp {<td>Total Scr.*?<td>(\d+)<} $DataExt - cnJS
    regexp {<td>Total CSS imp.*?<td>(\d+)<} $DataExt - cnCSS
    regexp {<td>Total Fra.*?<td>(\d+)<} $DataExt - cnFrm
    regexp {<td>Total Ifra.*?<td>(\d+)<}  $DataExt - cnIfrm

    set out [list]
    set_ [cformat total [msz $szTotal]]
    lappend out $_

    set_ [list $cnHtml]
    if {$cnFrm} { lappend_ [cformat html.fr $cnFrm] }
    if {$cnIfrm} { lappend_ [cformat html.ifr $cnIfrm] }
    if { [llength $_] == 1 && $cnHtml == "1" } {
      lappend out [cformat html1 [msz $szHtml]]
    } {
      lappend out [cformat html [msz $szHtml] [cjoin $_ html.j]]
    }

    if { $szImg } {
      set_ [list]
      lappend_ [cformat img.main [msz $szImgHtml] $cnImgHtml]
      if { $cnImgCSS } { lappend_ [cformat img.css [msz $szImgCSS] $cnImgCSS] }
      lappend out [cformat img [msz $szImg] [cjoin $_ img.j]]
    }

    if { $szCSS } { lappend out [cformat css [msz $szCSS] $cnCSS] }
    if { $szJS } { lappend out [cformat js [msz $szJS] $cnJS] }
    if { $szMM } { lappend out [cformat mm [msz $szMM]] }
    if { $szOther } { lappend out [cformat other [msz $szOther]] }

    if { [regexp -nocase "<p># Congratulations. This site is using HTTP compression" $HttpData] } {
      lappend out [cformat gzip.on]
    } {
      lappend out [cformat gzip.off]
    }

    lappend out [cformat title $title]
    lappend out [cformat url $url]

    reply -uniq %s [cjoin $out { }]
  }
}

proc ::httputils::msz { num } {
  if { $num < 2048 } { return $num }
  set num [expr { 1.0 * $num / 1024 }]
  if { $num < 2048 } { return "[format %.2f $num]k" }
  set num [expr { 1.0 * $num / 1024 }]
  return "[format %.2f $num]M"
}

::httputils::init
