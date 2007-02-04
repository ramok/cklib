
::ck::require sessions 0.2

namespace eval ::ck::cache {
  variable version 0.2
  variable cachepath
  variable cache
  variable idxfile    "index"
  variable cachepath  [file join $::ck::datapath ".cache"]

  namespace import -force ::ck::*
  namespace import -force ::ck::files::buildtree
  namespace import -force ::ck::sessions::session

  namespace export cache
}

proc ::ck::cache::init {} {
  variable cache
  variable cachepath

  if { ![file isdirectory $cachepath] } {
    if { [catch {file mkdir $cachepath} errstr] } {
      debug -err "Failed create cache-dir \(%s\): " $cachepath $errstr
      return 0
    }
  }
  array init cache
}

proc ::ck::cache::cache { args } {
  cmdargs \
    register ::ck::cache::register \
    put      ::ck::cache::put \
    get      ::ck::cache::get \
    makeid   ::ck::cache::makeid \
    getindex ::ck::cache::getindex \
    check    ::ck::cache::check
}
proc ::ck::cache::register { args } {
  variable cache
  variable cachepath

  getargs \
    -nobotnick flag -nobotnet flag -disable flag \
    -ttl time "3600" \
    -maxrec int 20 \
    -ns str [uplevel 1 [list namespace current]] \
    -id str ""

  if { $(id) eq "" } {
    if { [llength $args] } {
      set (id) [lindex $args 0]
    } {
      set (id) [namespace tail $(ns)]
    }
  }

  set (idstart) 0

  if { $(nobotnet) && $(nobotnick) } {
    set add ""
  } elseif { $(nobotnet) && !$(nobotnick) } {
    set add "$::ck::ircnick"
  } else {
    if { $(nobotnick) } { set add "common" } { set add $::ck::ircnick }
    set add "${add}.$::ck::ircnet"
  }
  set (path) [file join $cachepath $add]

  if { ![buildtree $(path)] } {
    debug -err "Error while building directorys. Cache disabled."
    set (disable) 1
  }

  set cache($(id)) [array get {}]
}
proc ::ck::cache::makeid { args } {
  upvar sid sid
  getargs \
   -tolower list [list] \
   -nospace list [list] \
   -id str ""

  if { $(id) eq "" } {
    set (id) [ns2cid [set ns [uplevel 1 {namespace current}]]]
  }

  set_ [list]
  for { set i 0 } { $i < [llength $args] } { incr i } {
    set element [lindex $args $i]
    if { $(tolower) == "all" || [lexists $(tolower) $i] } { set element [string tolower $element] }
    if { $(nospace) == "all" || [lexists $(nospace) $i] } { regsub -all {[\n\s\r]} $element {} element }
    lappend_ $element
  }

  session insert CacheID  $(id)
  session insert CacheUID $_

  return 1
}
proc ::ck::cache::check { } {
  upvar sid sid
  session import Cache*

  if { [isdisabled $CacheID] } { return 0 }

  set ttl [getparam ttl $CacheID]

  foreach_ [readindex $CacheID] {
    if { [lindex_ 0] != $CacheUID } continue
    if { $ttl > 0 && [expr { [clock seconds] - [lindex_ 1] }] > $ttl } { return 0 }
    set fn [file join [getpath $CacheID] [lindex_ 2]]
    if { ![file exists $fn] || ![file readable $fn] } { return 0 }
    return 1
  }
  return 0
}
proc ::ck::cache::put { data } {
  upvar sid sid
  session import Cache*

  if { [isdisabled $CacheID] } { return 0 }

  set path [getpath $CacheID]

  set index [list]
  foreach_ [readindex $CacheID] {
    if { [lindex_ 0] == $CacheUID } {
      catch { file delete [file join $path [lindex_ 2]] }
      continue
    }
    lappend index $_
  }
  set maxrec [expr [getparam maxrec $CacheID] - 1]
  if { $maxrec != 0 } {
    while { [llength $index] > $maxrec } {
      catch { file delete [file join $path [lindex [lindex $index 0] 2]] }
      set index [lrange $index 1 end]
    }
  }

  set cnum [getparam idstart $CacheID]
  while { [file exists [set fn [file join $path [format "cache.%s.%s" $CacheID $cnum]]]] } {
    incr cnum
  }

  set fid [open $fn w]
  fconfigure $fid -encoding utf-8
  puts -nonewline $fid $data
  close $fid

  set fn [format "cache.%s.%s" $CacheID $cnum]
  lappend index [list $CacheUID [clock seconds] $fn]
  setparam idstart $CacheID [incr cnum]
  writeindex $CacheID $index
  return 1
}
proc ::ck::cache::get { args } {
  getargs \
   -id str "" \
   -uid str "" \
   -nosession flag \
   -ns str [uplevel 1 [list namespace current]]
  upvar [lindex $args 0] data

  if { $(nosession) } {
    if { $(id) eq "" } {
      set CacheID [ns2cid $(ns)]
    } {
      set CacheID $(id)
    }
    set CacheUID $(uid)
  } {
    upvar sid sid
    if { $(uid) eq "" } {
      session import -exact CacheUID
    } {
      set CacheUID $(uid)
    }
    session import -exact CacheID
  }

  if { [isdisabled $CacheID] } { return 0 }

  set ttl [getparam ttl $CacheID]

  foreach_ [readindex $CacheID] {
    if { [lindex_ 0] eq $CacheUID } {
      if { $ttl > 0 && [expr { [clock seconds] - [lindex_ 1] }] > $ttl } continue
      set fn [lindex_ 2]
      break
    }
  }

  if { ![info exists fn] } { return 0 }

  set fn [file join [getpath $CacheID] $fn]
  if { ![file exists $fn] || ![file readable $fn] } {
    debug -err "Can't read cached file <%s>" $fn
    return 0
  }
  set fid [open $fn r]
  fconfigure $fid -encoding utf-8
  set data [read -nonewline $fid]
  close $fid
  return 1
}
proc ::ck::cache::getindex { args } {
  getargs \
   -id str "" \
   -ns str [uplevel 1 [list namespace current]]
  if { $(id) eq "" } {
    if { [llength $args] } {
      set (id) [lindex $args 0]
    } {
      set (id) [ns2cid $(ns)]
    }
  }
  if { [isdisabled $(id)] } { return [list] }
  set_ [list]
  foreach rec [readindex $(id)] {
    lappend_ [lindex $rec 0] [lindex $rec 1]
  }
  return $_
}
proc ::ck::cache::readindex { cid } {
  variable idxfile

  set fn [file join [getpath $cid] "${idxfile}.$cid"]
  if { ![file readable $fn] } { return [list] }
  set fid [open $fn r]
  fconfigure $fid -encoding utf-8
  set index [read -nonewline $fid]
  close $fid
  return $index
}
proc ::ck::cache::writeindex { cid index } {
  variable idxfile
  set fn [file join [getpath $cid] "${idxfile}.$cid"]
  set fid [open $fn w]
  fconfigure $fid -encoding utf-8
  puts -nonewline $fid $index
  close $fid
}
proc ::ck::cache::getparam { param cid } {
  variable cache
  array set ctmp $cache($cid)
  return $ctmp($param)
}
proc ::ck::cache::setparam { param cid data } {
  variable cache
  array set ctmp $cache($cid)
  set ctmp($param) $data
  set cache($cid) [array get ctmp]
}
proc ::ck::cache::isdisabled { cid } {
  return [getparam disable $cid]
}
proc ::ck::cache::getpath { cid } {
  return [getparam path $cid]
}
proc ::ck::cache::cacheexists { cid } {
  variable cache
  return [info exists cache($cid)]
}
proc ::ck::cache::ns2cid { ns } {
  variable cache
  foreach cid [array names cache] {
    array set ctmp $cache($cid)
    if { $ctmp(ns) != "" && $ctmp(ns) == $ns } { return $cid }
  }
  return ""
}

