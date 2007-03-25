
encoding system utf-8
::ck::require files 0.3

namespace eval autobackup {
  variable version 0.1
  variable author "Chpock <chpock@gmail.com>"

  namespace import -force ::ck::*
  namespace import -force ::ck::config::config
  namespace import -force ::ck::files::datafile
}

proc ::autobackup::init {  } {
  config register -id "interval" -type time -default 1d -folder "backup" \
    -access n -desc "Интервал autobackup." -hook chkconfig
  config register -id "path" -type str -default "backup" -folder "backup" \
    -access n -desc "Путь для каталога с бэкапами."
  config register -id "keepold" -type time -default 5d -folder "backup" \
    -access n -desc "Сколько времени хранить старые бэкапы."
  config register -id "fn.ext" -type str -default ".tar.gz" -folder "backup" \
    -access n -desc "Расширение для файла бэкапа."
  config register -id "command" -type str -folder "backup" -access n \
    -default "/usr/bin/env tar c -z -T %filelist -f %backupname" \
    -desc "Комманда выполняющая архивирование. %filelist - файл со списком для бэкапа. %backupname - сам файл бэкапа."

  etimer -norestart -interval [config get "interval"] ::autobackup::backup
}

proc ::autobackup::backup {  } {
  set path [config get "path"]
  if { ![file isdirectory $path] && [catch {file mkdir $path} errMsg] } {
    debug -err "fail to create backup dir <%s>: %s" $path $errMsg
    return
  }
  if { ![file readable $path] } {
    debug -err "fail to access backup dir <%s>." $path
    return
  }
  foreach_ [glob -nocomplain -directory $path [format "backup.%s-%s.*" $::ck::ircnick $::ck::ircnet]] {
    if { ![file writable $_] || [file isdirectory $_] } {
      debug -notice "find file <%s> but its not writable or directory."
      continue
    }
    if { [set age [expr { [clock seconds] - [file mtime $_] }]] <= [config get "keepold"] } {
      debug -debug "found file <%s>, age %ss. keep it." $_ $age
    } elseif { [catch {file delete $_} errMsg] } {
      debug -notice "found backup file <%s>, age %ss. fail to remove: %s" $_ $age $errMsg
    } {
      debug -debug "found file <%s>, age %ss. remove it." $_ $age
    }
  }
  set backupfn [file join $path [format "backup.%s-%s.%s%s" \
    $::ck::ircnick $::ck::ircnet [clock format [clock seconds] -format "%Y%m%d-%H%M"] [config get "fn.ext"]]]
  if { [file exists $backupfn] } {
    debug -warn "destination file for backup exists, ignore creating."
    return
  }
  set flist [list]
  foreach_ [list $::config $::userfile $::chanfile] {
    if { ![file exists $_] || [file isdirectory $_] || ![file exists $_] } {
      debug -debug "error while add 'important file' <%s> to backup." $_
    } {
      debug -debug "add to debug file: %s" $_
      lappend flist $_
    }
  }
  foreachkv [array get ::ck::files::datareg] {
    set fn [lindex $v 0]
    if { ![lindex $v 4] } {
      debug -debug "data file id <%s> marked as not backup." $k
    } elseif { ![file exists $fn] } {
      debug -debug "data file id <%s> not exists, skip it." $k
    } elseif { [file isdirectory $fn] || ![file readable $fn] } {
      debug -debug "data file id <%s> is not readable or directory, skip it." $k
    } elseif { [file size $fn] == 0 } {
      debug -debug "data file id <%s> is empty, skip it." $k
    } {
      debug -debug "add to debug data file id <%s>." $k
      lappend flist $fn
    }
  }
  if { [catch {open _bkptmp w} fid] } {
    debug -err "fail to create tmp file for backup: %s" $fid
    return
  }
  # не юзается [join $flist] потому как юзается автоопределение тиклем типа конца строк
  foreach_ $flist { puts $fid $_ }
  close $fid
  set cmd [concat exec [split [string map [list %filelist _bkptmp %backupname $backupfn] [config get "command"]] { }]]
  debug -debug "backup cmd: %s" $cmd
  if { [catch $cmd errMsg] && ![string equal $::errorCode NONE] } {
    debug -err "backup failed: $errMsg"
  } {
    debug -debug "backup done."
  }
  catch {file delete _bkptmp}
}

proc ::autobackup::chkconfig { mode var oldv newv hand } {
  if { ![string equal -length 3 $mode "set"] } { return 0 }
  etimer -interval $newv ::autobackup::backup
  return 0
}
