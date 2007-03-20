
encoding system cp1251

::ck::require http
::ck::require cache

namespace eval myscript {
  # Объявляем версию скрипта и автора (для виду)
  variable version 1.0
  variable author  "Chpock <chpock@gmail.com>"

  # Объявляем переменную в которую будем ложить данные авторизации
  variable authinfo

  # Переносим все команды из неймспейса ::ck::cmd
  namespace import -force ::ck::cmd::*
  namespace import -force ::ck::http::http
  namespace import -force ::ck::cache::cache
}

proc ::myscript::init {  } {
  # Объявление команды !runmyscript
  cmd register runmyscript ::myscript::run \
    -bind "runmyscript"

  # регистрируем общий кэш с временем жизни 1 день и максимальным количеством записей 10 штук
  cache register -nobotnet -nobotnick -ttl 1d -maxrec 10
}

# Процедура, исполняется при команде !runmyscript
proc ::myscript::run { sid } {
  variable authinfo
  # Импортируем все переменные сессии
  session import
  # проверяем событие по которому вызвались, если CmdPass - тогда команда только вызвана
  if { $Event eq "CmdPass" } {
    # ставим процедуру(makesearch в данном случае) которая будет выполнятся по событию "MakeSearch"
    session hook MakeSearch makesearch
    # выбираем текст для поиска из строки и заносим его в переменную сессии SearchText
    session set SearchText [join [lrange $StdArgs 1 end]]
    # проверяем существует ли переменная с данными аунтификации
    if { [catch {set authinfo}] } {
      # если не существует - запускаем запрос на аунтификацию
      http run "http://my.host/login.php" -query [list "id" "нашid" "password" "нашпароль"]
      # выходим из процедуры т.к. наш запрос уже пошел
      return
    }
    # тут мы доходим если данные аунтификации существуют
    # делаем событие для сессии "MakeSearch" для самого поиска
    session event MakeSearch
    # выходим из процедуры
    return
  }
  # сюда мы дошли если получен ответ на запрос об авторизации
  # для дебага выводим заголовки http в патилайн
  foreach {k v} $HttpMeta {
    debug -debug "k(%s) v(%s)" $k $v
  }
  # забиваем фигню в переменную authinfo
  set authinfo "userN1"
  # делаем событие на поиск
  session event MakeSearch
}

# Процедура поиска
proc ::myscript::makesearch { sid } {
  session import
  # если мы вызваны по событию MakeSearch значит нужно инициализировать поиск
  if { $Event eq "MakeSearch" } {
    # ставим обработчик события HttpResponse на себя же
    session hook HttpResponse makesearch
    # делаем ID для кэша из переменной $SearchText (в нее с самого начала забиты условия поиска)
    cache makeid $SearchText
    # проверка на наличие в кэше этого поиска
    if { ![cache get HttpData] } {
      # если в кэше не найдено, тогда запустить поиск
      http run "http://my.host/index.php" -query [list "do" "search" "text" $SearchText]
      # поиск запущен, можно выходить
      return
    }
  } elseif { $Event eq "HttpResponse" } {
    # если у нас ответ на http, значит это ответ на поиск, проверяем удачный ли он...
    if { $HttpStatus < 0 } {
      # если неудачный пишем в патилайн ошибку
      debug -err "поиск завершился неудачей с ошибкой http: %s" $HttpError
      # отвечаем юзеру об ошибке
      reply -err "Ошибка запроса '%s'." $HttpError
      # выходим
      return
    }
    # ложим в кэш нашу скачанную страничку
    cache put $HttpData
  }
  # сюда мы доходим если в кэше нашлась страничка или если http завершился удачно

  # пишем в патилайн нашу страничку по строкам
  foreach line [split $HttpData \n] {
    debug "search line: %s" $line
  }
  # выводим юзеру информацию о поиске
  reply "Круто! поиск прошел!"
}
