
encoding system cp1251

::ck::require http
::ck::require cache

namespace eval myscript {
  # ��������� ������ ������� � ������ (��� ����)
  variable version 1.0
  variable author  "Chpock <chpock@gmail.com>"

  # ��������� ���������� � ������� ����� ������ ������ �����������
  variable authinfo

  # ��������� ��� ������� �� ���������� ::ck::cmd
  namespace import -force ::ck::cmd::*
  namespace import -force ::ck::http::http
  namespace import -force ::ck::cache::cache
}

proc ::myscript::init {  } {
  # ���������� ������� !runmyscript
  cmd register runmyscript ::myscript::run \
    -bind "runmyscript"

  # ������������ ����� ��� � �������� ����� 1 ���� � ������������ ����������� ������� 10 ����
  cache register -nobotnet -nobotnick -ttl 1d -maxrec 10
}

# ���������, ����������� ��� ������� !runmyscript
proc ::myscript::run { sid } {
  variable authinfo
  # ����������� ��� ���������� ������
  session import
  # ��������� ������� �� �������� ���������, ���� CmdPass - ����� ������� ������ �������
  if { $Event eq "CmdPass" } {
    # ������ ���������(makesearch � ������ ������) ������� ����� ���������� �� ������� "MakeSearch"
    session hook MakeSearch makesearch
    # �������� ����� ��� ������ �� ������ � ������� ��� � ���������� ������ SearchText
    session set SearchText [join [lrange $StdArgs 1 end]]
    # ��������� ���������� �� ���������� � ������� ������������
    if { [catch {set authinfo}] } {
      # ���� �� ���������� - ��������� ������ �� ������������
      http run "http://my.host/login.php" -query [list "id" "���id" "password" "���������"]
      # ������� �� ��������� �.�. ��� ������ ��� �����
      return
    }
    # ��� �� ������� ���� ������ ������������ ����������
    # ������ ������� ��� ������ "MakeSearch" ��� ������ ������
    session event MakeSearch
    # ������� �� ���������
    return
  }
  # ���� �� ����� ���� ������� ����� �� ������ �� �����������
  # ��� ������ ������� ��������� http � ��������
  foreach {k v} $HttpMeta {
    debug -debug "k(%s) v(%s)" $k $v
  }
  # �������� ����� � ���������� authinfo
  set authinfo "userN1"
  # ������ ������� �� �����
  session event MakeSearch
}

# ��������� ������
proc ::myscript::makesearch { sid } {
  session import
  # ���� �� ������� �� ������� MakeSearch ������ ����� ���������������� �����
  if { $Event eq "MakeSearch" } {
    # ������ ���������� ������� HttpResponse �� ���� ��
    session hook HttpResponse makesearch
    # ������ ID ��� ���� �� ���������� $SearchText (� ��� � ������ ������ ������ ������� ������)
    cache makeid $SearchText
    # �������� �� ������� � ���� ����� ������
    if { ![cache get HttpData] } {
      # ���� � ���� �� �������, ����� ��������� �����
      http run "http://my.host/index.php" -query [list "do" "search" "text" $SearchText]
      # ����� �������, ����� ��������
      return
    }
  } elseif { $Event eq "HttpResponse" } {
    # ���� � ��� ����� �� http, ������ ��� ����� �� �����, ��������� ������� �� ��...
    if { $HttpStatus < 0 } {
      # ���� ��������� ����� � �������� ������
      debug -err "����� ���������� �������� � ������� http: %s" $HttpError
      # �������� ����� �� ������
      reply -err "������ ������� '%s'." $HttpError
      # �������
      return
    }
    # ����� � ��� ���� ��������� ���������
    cache put $HttpData
  }
  # ���� �� ������� ���� � ���� ������� ��������� ��� ���� http ���������� ������

  # ����� � �������� ���� ��������� �� �������
  foreach line [split $HttpData \n] {
    debug "search line: %s" $line
  }
  # ������� ����� ���������� � ������
  reply "�����! ����� ������!"
}
