
encoding system cp1251
::ck::require cmd

namespace eval myscript {
  # ��������� ������ ������� � ������ (��� ����)
  variable version 1.0
  variable author  "Chpock <chpock@gmail.com>"

  # ��������� ���������� � ������� ����� ������� ���������� �������
  variable lock

  # ��������� ��� ������� �� ���������� ::ck::cmd
  namespace import -force ::ck::cmd::*
}

proc ::myscript::init {  } {
  # ���������� ������� !runmyscript
  cmd register runmyscript ::myscript::run \
    -bind "runmyscript"
  # ���������� ������� !continue
  cmd register contmyscript ::myscript::rerun \
    -bind "continue"
}

# ���������, ����������� ��� ������� !runmyscript
proc ::myscript::run { sid } {
  variable lock
  # ����������� ��� ���������� ������
  session import
  # ��������� ������� �� �������� ���������, ���� CmdPass - ����� ������� ������ �������
  if { $Event eq "CmdPass" } {
    # �������� �� ���������� �������
    if { ![catch {set lock} lv] } {
      reply -err "� ��� �������."
    }
    reply "������� ����������."
    # ������ ������ �� ����������
    set timer 20
    # �� ������� <timer>*1000 ����������� (� ���� ������ ���������� 20 ������)
    #   �������� ������� 'Timeout' ��� ����� ������
    set timer [after [expr { $timer * 1000 }] [list session event -sid $sid Timeout]]
    # ������ ���������� �������
    set lock [list $sid $timer]
    # ��������� ������. ��� ���� ���������� ������ ��������� �����������.
    session lock
    # ����������� �� ���������
    return
  } elseif { $Event eq "Timeout" } {
    # ���� ����� ���� � ��� �������
    debug "timeout in command. unlock command."
    # ������� ���������� �� �������
    unset lock
    # ������������ �� ���������
    return
  } elseif { $Event eq "Continue" } {
    # ���� ����� ���� ��������� ������� "Continue"
    debug "�� ����������"
    # ������� ������
    after cancel [lindex $lock 1]
    # ������� ���������� � ������� � � ������
    unset lock
    session unlock
    reply "� ���������!"
    return
  }
  # ���� �� �� ������ �������� ������ ��� ������������� ���
  #   ��������� �������, ������� ������ ������� ���������� ���������
  #   �� ������ � ������� �� ���������
  debug -err "�������� �����-�� ������� � ������"
  return
}

proc ::myscript::rerun { sid } {
  variable lock
  session import
  # ��������� ������������ �� ������
  if { [catch {set lock} lv] } {
    debug "� ��� ��� ���������� �������, �������."
    return
  }
  # �������� ������� "Continue" � �������������� ������
  session event -sid [lindex $lock 0] Continue
  # ������ ������ �� ������, ������ �������
}
