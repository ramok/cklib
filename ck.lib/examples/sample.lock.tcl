
encoding system cp1251
namespace eval myscript {
  # Объявляем версию скрипта и автора (для виду)
  variable version 1.0
  variable author  "Chpock <chpock@gmail.com>"

  # Объявляем переменную в которую будем ставить блокировку скрипта
  variable lock

  # Переносим все команды из неймспейса ::ck::cmd
  namespace import -force ::ck::cmd::*
}

proc ::myscript::init {  } {
  # Объявление команды !runmyscript
  cmd register runmyscript ::myscript::run \
    -bind "runmyscript"
  # Объявление команды !continue
  cmd register contmyscript ::myscript::rerun \
    -bind "continue"
}

# Процедура, исполняется при команде !runmyscript
proc ::myscript::run { sid } {
  variable lock
  # Экспортируем все переменные сессии
  session import
  # проверяем событие по которому вызвались, если CmdPass - тогда команда только вызвана
  if { $Event eq "CmdPass" } {
    # Проверка на блокировку скрипта
    if { ![catch {set lock} lv] } {
      reply -err "Я уже запущен."
    }
    reply "Команда стартовала."
    # ставим таймер на блокировку
    set timer 20
    # По таймеру <timer>*1000 миллисекунд (в этом случае получается 20 секунд)
    #   вызываем событие 'Timeout' для нашей сессии
    set timer [after [expr { $timer * 1000 }] [list session event -sid $sid Timeout]]
    # Ставим блокировку скрипту
    set lock [list $sid $timer]
    # блокируем сессию. Без этой блокировки сессия автоматом уничтожится.
    session lock
    # Возращаемся из процедуры
    return
  } elseif { $Event eq "Timeout" } {
    # Сюда дошли если у нас таймаут
    debug "timeout in command. unlock command."
    # Снимаем блокировку со скрипта
    unset lock
    # Возвращаемся из процедуры
    return
  } elseif { $Event eq "Continue" } {
    # Сюда тошли если поступило событие "Continue"
    debug "Мы продолжаем"
    # убираем таймер
    after cancel [lindex $lock 1]
    # снимает блокировку с команды и с сессии
    unset lock
    session unlock
    reply "Я продолжаю!"
    return
  }
  # Сюда мы не должны доходить потому как предусмотрели все
  #   возможные события, поэтому только выводим дебагерное сообщение
  #   об ошибке и выходим из процедуры
  debug -err "Хреновое какое-то событие у сессии"
  return
}

proc ::myscript::rerun { sid } {
  variable lock
  session import
  # Проверяем заблокирован ли скрипт
  if { [catch {set lock} lv] } {
    debug "У нас нет запущенной команды, выходим."
    return
  }
  # Вызываем событие "Continue" в заблокированую сессию
  session event -sid [lindex $lock 0] Continue
  # дальше ничего не делаем, просто выходим
}

# Запускаем инит для скрипта
::myscript::init
