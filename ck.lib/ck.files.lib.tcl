
::ck::require lists

namespace eval ::ck::files {
  variable version 0.2
  variable author  "Chpock <chpock@gmail.com>"

  variable datareg

  namespace import -force ::ck::*
  namespace export buildtree
  namespace export datafile
  namespace export make_temp_directory
}

proc ::ck::files::init {} {
  variable datareg
  variable version

  if { [array exists datareg] } { unset datareg }
  array set datareg ""

  ### Init data-storage
  if { ![file isdirectory $::ck::datapath] } {
    if { [catch [list file mkdir "$::ck::datapath"] errstr] } {
      ::error "Failed create data-storage dir <${::ck::datapath}>: $errstr"
    }
  }

  return 1
}

proc ::ck::files::buildtree {tree} {
  variable separator
  set tree [file split $tree]
  set now  ""
  foreach dir $tree {
    set now [file join $now $dir]
    if { ![file isdirectory $now] } {
      if { [catch [list file mkdir $now] errstr] } {
	debug -error "While creating requested tree on $now"
        debug -error "Error comment: $errstr"
        return 0
      }
    }
  }
  return 1
}

#############################################

proc ::ck::files::datafile {args} {
  cmdargs \
    register ::ck::files::register \
    name     ::ck::files::filename \
    open     ::ck::files::open \
    get      ::ck::files::get \
    getlist  ::ck::files::get \
    putlist  ::ck::files::putlist \
    getarray ::ck::files::getarray \
    putarray ::ck::files::putarray \
    exists   ::ck::files::exists
}

proc ::ck::files::make_temp_directory { {id ""} } {

  if { $id == "" } { set id "temp" }
  append id "."

  set path [file join $::ck::datapath $id]
  while 1 {
    set add [string random 8]
    if { ![file exists "$path$add"] } break
  }
  append path $add
  buildtree $path
  return $path
}

proc ::ck::files::register {id args} {
  variable datareg

  getargs -bot flag -net flag -id flag
  set fn [file join $::ck::datapath $id]
  if { $(net) } { append fn ".$::ck::ircnet"  }
  if { $(bot) } { append fn ".$::ck::ircnick" }
  set datareg($id) [list $fn $(id) $(bot) $(net)]
  return 1
}
proc ::ck::files::filename {id {scid ""}} {
  variable datareg
  if { ![info exists datareg($id)] } {
    debug -warning "Requested name for unregistred id \(%s\)" $id
    return 0
  }
  set fn [lindex $datareg($id) 0]
  if { [lindex $datareg($id) 1] } { append fn ".$scid" }
  return $fn
}
proc ::ck::files::open {id {scid ""} {mode ""}} {
  if { $mode == "" } {
    set mode $scid
    set scid ""
  }
  if { $mode == "" } {
    set mode "r"
  }
  return [::open [filename $id $scid] $mode]
}
proc ::ck::files::exists {id {scid ""}} {
  return [file exists [filename $id $scid]]
}
proc ::ck::files::get {id {scid ""}} {
  if { ![exists $id $scid] } { return [list] }
  set fid [::open [filename $id $scid] r]
  fconfigure $fid -encoding utf-8
  set ret [read -nonewline $fid]
  close $fid
  return $ret
}
proc ::ck::files::putlist {id list {scid ""}} {
  set fid [::open [filename $id $scid] w]
  fconfigure $fid -encoding utf-8
  puts -nonewline $fid $list
  close $fid
  return 1
}
proc ::ck::files::getarray {id arrname {scid ""}} {
  set data [get $id $scid]
  upvar $arrname ret
  catch { unset ret }
  array set ret [get $id $scid]
  return 1
}
proc ::ck::files::putarray {id arrname {scid ""}} {
  upvar $arrname arr
  set fid [::open [filename $id $scid] w]
  fconfigure $fid -encoding utf-8
  puts -nonewline $fid [array get arr]
  close $fid
  return 1
}
