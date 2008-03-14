<html>
<head>
	<title>UAbotnet &laquo; dig.org.ua/botnet &laquo; <?=$QUERY_STRING;?></title>
	<meta http-equiv=content-type content="text/html; charset=windows-1251">
	<meta name=description content="">
	<meta name=keywords content="">
	<meta name=author content="dig / dig@dig.org.ua / icq: 561689 / jabber: dig@anarxi.st">
	<link href="main.css" rel="stylesheet" type="text/css">
</head>
<body>
<?
include('botnet.tree.php');
include('botnet.data.php');

$bot = '!' . $QUERY_STRING;

$generator = substr("$defbot", 1);

if ( !isset($b[$bot]) ){
  $bot = $defbot;
}

function buildtree ($bot, $prefix = '', $islast = 0, $parent = "") {
  global $b;
  global $n;
  print $prefix;
  if ( $parent != "" && $islast == 1 ) {
    print " `--";
    $prefix .= '   ';
  } elseif ( $parent != "" ) {
    print " |--";
    $prefix .= ' | ';
  }
  $pubm = htmlspecialchars((substr($bot,1)));
  if ($n[$bot][_status] == on) { $status="class=up"; } else { $status="class=down"; }
  if ($n[$bot][_addinfo] == 0) {
    echo "<span $status>$pubm</span> (".$n[$bot][_version].")";
  } else {
    print "<a href=?".$pubm." $status>".$pubm."</a> (".$n[$bot][_version].")";
  }
  print "\n";
  $i = 0;
  $cnt = count($b[$bot]);
  if ( $parent != "" ) $cnt--;
  foreach  ($b[$bot] as $idx => $cbot) {
    if ($cbot != $parent) {
      if (++$i == $cnt) { $islast = 1; } else { $islast = 0; }
      buildtree ($cbot, $prefix, $islast, $bot);
    }
  }
}

function buildinfos ($data) {
  foreach ($data as $k => $v) {
    print htmlspecialchars($k) . " : " . htmlspecialchars($v) . "\n";
  }
}

function checkempty ($str) {
  if ( $str == "" ) {
    return "<unknown>";
  }
  return $str;
}

function buildinfo_owner ($data) {
  print "<table border=0 cellspacing=0 cellpadding=20 width=700 align=center>";
  if ( $data['_owner'] == 1 ) {
    print "<tr><td>No info</td></tr>";
    return;
  }
  print "<tr><td>Owner: $data[_owner]</td><td>";
}

function builfinfo_traffic ($data) {
}

function buildinfo_system ($data) {
}

function buildinfo_irc ($data) {
}


?>
<table border=0 cellspacing=0 cellpadding=5 width=700 align=center>
<tr>
	<td colspan=2><h2>Сгенерировано ботом <?=$generator?>@UAnet</h2></td>
</tr>
<tr>
	<td width=250 valign=top align=center>
		<table border=0 cellspacing=1 cellpadding=2 width=100% bgcolor=#808080>
		<tr>
			<td bgcolor=#f5f5f5>
			<h1>Дерево ботнета</h1>
			<pre>
<?
  buildtree($defbot);
?>
			</pre>
			</td>
		</tr>
		<tr>
			<td><span style="color:#333;font-weight:bold;">
			Всего: <?=count($n[$bot])?></span>
			</td>
		</tr>
		</table>
	</td>
	<td width=450>
<?
$data = $n[$bot];
$traf = $data['traffic'];
$traf1 = explode(" ", $traf[total]);
$traf2 = explode(" ", $traf[misc]);
$traf3 = explode(" ", $traf[partyline]);
$traf4 = explode(" ", $traf[botnet]);
$traf5 = explode(" ", $traf[transfer]);
$traf6 = explode(" ", $traf[irc]);

echo "<table border=0 cellspacing=1 cellpadding=2 width=100% bgcolor=#808080>";
echo "<tr><td bgcolor=#f5f5f5 colspan=2><h1>Информация о боте $QUERY_STRING @ $data[network]</h1></td></tr>";
echo "<tr><td bgcolor=#ffffff align=right width=25%>Статус: </td><td bgcolor=#f5f5f5>";
if ($data['_status'] == on) { echo "<span class=up>прилинкован</span>"; } else { print " <span class=down>отлинкован</span>"; }
echo "</td></tr>";
echo "<tr><td bgcolor=#f5f5f5 align=right>Версия: </td><td bgcolor=#ffffff>";
if ($data[eggver]) { echo $data[eggver]; } else { echo $data[_version]; }
echo "</td></tr>";
echo "<tr><td bgcolor=#ffffff align=right>Версия TCL: </td><td bgcolor=#f5f5f5>";
if ($data[tclver]) { echo $data[tclver]; } else { echo "неизвестно"; }
echo "</td></tr>";
echo "<tr><td bgcolor=#f5f5f5 align=right>Handlen: </td><td bgcolor=#ffffff>";
if ($data[handlen]) { echo $data[handlen]; } else { echo "неизвестно"; }
echo "</td></tr>";
echo "<tr><td bgcolor=#ffffff align=right>Юзеров в базе: </td><td bgcolor=#f5f5f5>";
if ($data[users]) { echo $data[users]; } else { echo "неизвестно"; }
echo "</td></tr>";
echo "<tr><td bgcolor=#f5f5f5 align=right>Владельцы (n|): </td><td bgcolor=#ffffff>";
if ($data[owners]) { echo $data[owners]; } else { echo "неизвестно"; }
echo "</td></tr>";
echo "<tr><td bgcolor=#ffffff align=right>Сеть: </td><td bgcolor=#f5f5f5>";
if ($data[network]) { echo $data[network]; } else { echo "неизвестно"; }
echo "</td></tr>";
echo "<tr><td bgcolor=#f5f5f5 align=right>Ник: </td><td bgcolor=#ffffff>";
if ($data[ircnick]) { echo $data[ircnick]; } else { echo "неизвестно"; }
echo "</td></tr>";
echo "<tr><td bgcolor=#ffffff align=right>On-Line: </td><td bgcolor=#f5f5f5>";
if ($data[serveronline]) { echo $data[serveronline]; } else { echo "неизвестно"; }
echo "</td></tr>";
echo "<tr><td bgcolor=#f5f5f5 align=right>Каналы: </td><td bgcolor=#ffffff>";
if ($data[channels]) { echo $data[channels]; } else { echo "неизвестно"; }
echo "</td></tr>";
echo "<tr><td bgcolor=#ffffff align=right>О.С.: </td><td bgcolor=#f5f5f5>";
if ($data[os]) { echo $data[os]; } else { echo "неизвестно"; }
echo "</td></tr>";
echo "<tr><td bgcolor=#f5f5f5 align=right>Uptime: </td><td bgcolor=#ffffff>";
if ($data[uptime]) { echo $data[uptime]; } else { echo "неизвестно"; }
echo "</td></tr>";
echo "<tr><td bgcolor=#ffffff align=right>Кодировка: </td><td bgcolor=#f5f5f5>";
if ($data[codepage]) { echo $data[codepage]; } else { echo "неизвестно"; }
echo "</td></tr>";
echo "<tr><td bgcolor=#f5f5f5 align=right>Модули: </td><td bgcolor=#ffffff>";
if ($data[modules]) {
  $mod = explode(", ", $data[modules]);
  $countmod = count($mod);
  for ($i = 1; $i <= $countmod; $i++) {
    echo $mod[$i]."<br />";  
  }
} else { echo "неизвестно"; }
echo "</td></tr>";
echo "<tr><td bgcolor=#ffffff align=right>Обновлена: </td><td bgcolor=#f5f5f5>";
if ($data[sendtime]) { echo $data[sendtime]; } else { echo "неизвестно"; }
echo "</td></tr>";
echo "</table><br />";


echo "<table border=0 cellspacing=1 cellpadding=2 width=100% bgcolor=#808080>";
echo "<tr><td bgcolor=#f5f5f5 colspan=2><h1>Информация о владельце бота $QUERY_STRING @ $data[network]</h1></td></tr>";
echo "<tr><td bgcolor=#ffffff align=right width=25%>Ник: </td><td bgcolor=#f5f5f5>";
if ($data[owner]) { echo $data[owner]; } else { print "неизвестно"; }
echo "</td></tr>";
echo "<tr><td bgcolor=#f5f5f5 align=right>Настоящее имя: </td><td bgcolor=#ffffff>";
if ($data['owner.realname']) { echo $data['owner.realname']; } else { echo "неизвестно"; }
echo "</td></tr>";
echo "<tr><td bgcolor=#ffffff align=right width=25%>Город: </td><td bgcolor=#f5f5f5>";
if ($data['owner.city']) { echo $data['owner.city']; } else { print "неизвестно"; }
echo "</td></tr>";
echo "<tr><td bgcolor=#f5f5f5 align=right>E-Mail: </td><td bgcolor=#ffffff>";
if ($data['owner.email']) { echo $data['owner.email']; } else { echo "неизвестно"; }
echo "</td></tr>";
echo "<tr><td bgcolor=#ffffff align=right>ICQ: </td><td bgcolor=#f5f5f5>";
if ($data['owner.icq']) { echo $data['owner.icq']; } else { echo "неизвестно"; }
echo "</td></tr>";
echo "</table><br />";

echo "<table border=0 cellspacing=1 cellpadding=2 width=100% bgcolor=#808080>";
echo "<tr><td bgcolor=#f5f5f5 colspan=5><h1>Информация о трафике бота $QUERY_STRING @ $data[network]</h1></td></tr>";
echo "<tr><td class=traftr2></td><td class=traftr2><small><b>IN</b> (сегодня)</small></td><td class=traftr2><small><b>IN</b> (всего)</small></td><td class=traftr2><small><b>OUT</b> (сегодня)</small></td><td class=traftr2><small><b>OUT</b> (всего)</small></td></tr>";
echo "<tr><td class=traftr1><small><b>TOTAL</b></small></td><td class=traftr1>$traf1[0]</td><td class=traftr1>$traf1[1]</td><td class=traftr1>$traf1[2]</td><td class=traftr1>$traf1[3]</td></tr>";
echo "<tr><td class=traftr2><small><b>MISC</b></small></td><td class=traftr2>$traf2[0]</td><td class=traftr2>$traf2[1]</td><td class=traftr2>$traf2[2]</td><td class=traftr2>$traf2[3]</td></tr>";
echo "<tr><td class=traftr1><small><b>PARTYLINE</small></b></td><td class=traftr1>$traf3[0]</td><td class=traftr1>$traf3[1]</td><td class=traftr1>$traf3[2]</td><td class=traftr1>$traf3[3]</td></tr>";
echo "<tr><td class=traftr2><small><b>BOTNET</b></small></td><td class=traftr2>$traf4[0]</td><td class=traftr2>$traf4[1]</td><td class=traftr2>$traf4[2]</td><td class=traftr2>$traf4[3]</td></tr>";
echo "<tr><td class=traftr1><small><b>TRANSFER</b></small></td><td class=traftr1>$traf5[0]</td><td class=traftr1>$traf5[1]</td><td class=traftr1>$traf5[2]</td><td class=traftr1>$traf5[3]</td></tr>";
echo "<tr>
          <td class=traftr2><small><b>IRC</b></small></td>
          <td class=traftr2>$traf6[0]</td>
          <td class=traftr2>$traf6[1]</td>
          <td class=traftr2>$traf6[2]</td>
          <td class=traftr2>$traf6[3]</td>
";
echo "</tr>";
echo "</table><br />";
?>	
	</td>
</tr>
</table>

</body>
</html>
