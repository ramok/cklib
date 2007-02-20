
encoding system utf-8
::ck::require cmd 0.4

namespace eval ::locate {
  variable version "1.2"
  variable author  "Chpock <chpock@gmail.com> with comments from Smollett@RusNet"

  variable countryidx
  variable reserved

  namespace import -force ::ck::cmd::*
}

proc ::locate::init { } {

  cmd register locator ::locate::run -autousage -doc "locate" \
    -bind "loc|ate" -bind "лок|атор" -flood 8:60

  cmd doc "locate" {~*!loc* <ip/domain/nick>~ - попытка выяснить географическое местонахождение.}

  msgreg {
    spec.block   &bInfo &R%s&K:&c Special Block &K[&p%s&K]&c %s
    no.info      No information.
    join         "&K;&c "
    main.ip      &R%s&K:&c %s%s
    main.host    &B%s&K(&R%s&K):&c %s%s
    main.net     " &K[&nNet: &p%s&K/&P%s&K]"
    main.range   " &K[&nNet: &p%s&K-&P%s&K]"
    err.resolve &BUnable to resolve hostname&r %s &Bto IP address.
    err.runwhois &RError while getting whois info.
    err.prswhois &BError while parse whois info for IP&r %s&B.
  }
}
proc ::locate::maskip {numip mask} {
  set mask [expr 32 - $mask]
  return [expr ($numip >> $mask) << $mask]
}
proc ::locate::checkloc { dest } {
  variable reserved
  upvar sid sid
  set nip [ip2num $dest]
  foreach {mask desc}  $reserved {
    if { [num2ip [maskip $nip [lindex [split $mask /] 1]]] == [lindex [split $mask /] 0] } {
      reply -uniq spec.block $dest $mask $desc
      return -code return
    }
  }
}
# LocIP - ip к хуизу
# LocHost - dns ip к хуизу
# WhoisData - ответ от хуиза
# WhoisServer - сервер к которому направлять запрос
# WhoisNick - ник который хуизится, если пустой - значит хост
# WhoisUserhost - ident@host ника который хуизится
# WhoisFake     - оригинальная запись(fake) ip, если пустое - значит ip был не fake
# DNSDest       - на чем делать dns
proc ::locate::run { sid } {
  session import
  if { $Event == "CmdPass" } {
    session hook MakeDNS     make_dns
    session hook GotDNS      got_dns
    session hook MakeWhois   make_whois
    session hook GotWhois    got_whois
    session insert WhoisServer ""
    set dest [lindex $StdArgs 1]
    if { [string first @ $dest] != -1 } { set dest [lindex [split $dest @] 1] }
    # если нужно искать по faked IP....
    if { [regexp {^[\^~%]([0-9a-f]{8}|[0-9A-F]{8})$} $dest - dest] } {
      set_ [list]
      for {set i 0} {$i < 4} {incr i} {
	set tmp [string range $dest [expr $i * 2] [expr $i * 2 + 1]]
	lappend_ [format %i 0x$tmp]
      }
      set dest [join_ .]
    } elseif { [string first . $dest] == -1 } {
    # если нет ".", значит нужно искать по нику
      # если ника нет на канале, запустить /who
      if { [set_ [getchanhost $dest]] == "" } {
	reply -err resolve $dest
      }
      set dest [lindex [split_ @] 1]
    }
    # проверка на принадлежность IP локальным сетям
    if { [regexp {^([0-9]{1,3}\.){3}[0-9]{1,3}$} $dest] } { checkloc $dest }
    session event -return MakeDNS DNSDest $dest
  }
}
proc ::locate::make_dns { sid } {
  session import -exact DNSDest
  session lock
  dnslookup $DNSDest ::locate::_dnsreply $sid
}
proc ::locate::_dnsreply { aip ahost astatus sid } {
  session unlock
  session event GotDNS "LocIP" $aip "LocHost" $ahost
}
proc ::locate::got_dns { sid } {
  session import
  if { $LocIP == "0.0.0.0" } {
    reply -err resolve $LocHost
  }
  checkloc $LocIP
  session event MakeWhois
}
proc ::locate::make_whois { sid } {
  session import
  set execstr "exec whois"
  if { $WhoisServer ne "" } { append execstr " -h $WhoisServer" }
  append execstr " " $LocIP
  if { [catch $execstr WhoisData] } {
    debug -err "while exec whois <%s>: %s" $execstr $WhoisData
    reply -err runwhois
  }
  session event GotWhois "WhoisData" $WhoisData
}
proc ::locate::got_whois { sid } {
  variable countryidx
  session import
  set dbtype ""
  set objects [list]
  set obj     [list]
  set whoisdata [split $WhoisData \n]
  for { set i 0 } { $i < [llength $whoisdata] } { incr i } {
    set line [lindex $whoisdata $i]
    switch -- $dbtype {
      "ARIN" {
	if { [set idx [string first "#" $line]] != -1 } {
	  set line [string trim [string range $line 0 [incr idx -1]]]
	}
	# если пустая строчка или камент - начало нового блока
	if { $line == "" } {
	  if { [llength $obj] } { lappend objects $obj; set obj [list] }
	  continue
	}
	# обычные пара ключ-значение
	if { [regexp {^([A-Za-z\-]+):\s+(.+)$} $line - k v] } {
	  lappend obj $k $v
	  continue
	}
	debug -warn "Unknown string <%s> while parse ARIN database for IP <%s>." $line $LocIP
      }
      "RIPE" {
	if { [set idx [string first "#" $line]] != -1 } {
	  set line [string trim [string range $line 0 [incr idx -1]]]
	}
	# если пустая строчка или камент - начало нового блока
	if { $line == "" || [string index $line 0] == "%" } {
	  if { [llength $obj] } { lappend objects $obj; set obj [list] }
	  continue
	}
	# если в начале пробелы - строчка продолжается
	if { [string index $line 0] == " " || [string index $line 0] == "\t"} {
	  if { [llength $obj] } {
	    set_ [string trimright [lindex $obj end] {, }]
	    append_ ", " [string trim $line]
	    set obj [lreplace $obj end end $_]
	  }
	  continue
	}
	# обычные пара ключ-значение
	if { [regexp {^([a-z\-]+):(\s+(?:.+))?$} $line - k v] } {
	  set v [string trim $v]
	  if { $WhoisServer eq "" } {
	    if { [string match -nocase "*These IP addresses are assigned in the AFRINIC region.*" $v] } {
	      session event -return MakeWhois WhoisServer "whois.afrinic.net"
	    }
	  }
	  lappend obj $k $v
	  continue
	}
	debug -warn "Unknown string <%s> while parse RIPE database for IP <%s>." $line $LocIP
      }
      default {
	if { [string first "inetnum:" $line] == 0 } {
	  set dbtype "RIPE"
	} elseif { [string first "OrgName:" $line] == 0 } {
	  set dbtype "ARIN"
	} elseif { [regexp {\s+\(NET-\d+-\d+-\d+-\d+-\d+\)\s*$} $line] } {
	  if { $WhoisServer eq "" } {
	    session event -return MakeWhois WhoisServer "whois.lacnic.net"
	  }
	  debug -warn "rcvd redirect while whois <%s>, but already at alcnic..." $LocIP
	} else {
	  debug -debug "pre str:%s:" $line
	  continue
	}
	incr i -1
	if { $WhoisServer eq "" } {
	  if { [string match -nocase "*RIPE Network Coordination Centre*" $line] } {
	    session event -return MakeWhois WhoisServer "whois.ripe.net"
	  } elseif { [string match -nocase "*Latin American and Caribbean IP address Regional Registry*" $line] } {
	    session event -return MakeWhois WhoisServer "whois.lacnic.net"
	  } elseif { [string match -nocase "*Asia Pacific Network Information Centre*" $line] } {
	    session event -return MakeWhois WhoisServer "whois.apnic.net"
	  }
	}
      }
    }
  }
  if { [llength $obj] } { lappend objects $obj }
  if { $dbtype == "" } {
    debug -warn "Unknown database while parse IP <%s>." $LocIP
    reply -err prswhois $LocIP
  }
  set state   ""
  set country ""
  set city    ""
  set address [list]
  set description [list]
  set netblock    ""
  foreach obj $objects {
    switch -- "${dbtype}@[lindex $obj 0]" {
      "RIPE@inetnum" {
	foreachkv $obj {
	  switch -- $k {
	    "inetnum" { set v [split $v { }]; set netblock [list [lindex $v 0] [lindex $v 2]] }
	    "country" { set country $v }
	    "city"    { set city $v }
	    "owner" -
	    "descr"   {
	      foreach v [split $v {,}] {
		if { [set v [string trim $v]] eq "" } continue
		if { [lexists $description $v] } continue
		lappend description $v
	      }
	    }
	  }
	}
      }
      "RIPE@role" -
      "RIPE@person" -
      "RIPE@organisation" {
	foreachkv $obj {
	  switch -- $k {
	    "address" {
	      foreach v [split $v {,}] {
		if { [set v [string trim $v]] eq "" } continue
		if { [lexists $description $v] } continue
		if { [lexists $address $v] } continue
		lappend address $v
	      }
	    }
	  }
	}
	break
      }
      "ARIN@OrgName" {
	foreachkv $obj {
	  switch -- $k {
	    "OrgName" { set description [list $v] }
	    "City"    { set city $v }
	    "Address" { lappend address [string trimright $v {, }] }
	    "Country" { set country $v }
	    "StateProv" { set state $v }
	  }
	}
      }
      "ARIN@NetRange" {
	set v [split [lindex $obj 1] { }]
	set netblock [list [lindex $v 0] [lindex $v 2]]
	break
      }
    }
  }
  if { [set idx [lsearch -exact $countryidx(domains) [string toupper $country]]] != -1 } {
    set country [string totitle [lindex $countryidx(names) $idx]]
  }
  if { $state ne "" } {
    if { [set idx [lsearch -exact $countryidx(shortstatenames) [string toupper $state]]] != -1 } {
      set state [string totitle [lindex $countryidx(statenames) $idx]]
    }
    append country {(} $state {)}
  }
  if { $city != "" } {
    set address [concat [list $city] $address]
  }
  set_ [list]
  if { $country ne "" } { lappend_ $country }
  if { $address ne "" } { lappend_ [join $address {, }] }
  if { $description ne "" } { lappend_ [join $description {, }] }
  if { $netblock != "" } {
    if { [regexp {^([\d\.]+)/(\d+)$} [lindex $netblock 0] - a1 a2] } {
      set a1 [split $a1 .]
      while { [llength $a1] < 4 } { lappend a1 {0} }
      set netblock [cformat main.net [join $a1 .] $a2]
    } {
      set fip [ip2num [lindex $netblock 0]]
      set sip [ip2num [lindex $netblock 1]]
      for { set netbits 32 } { $netbits > 0 } { incr netbits -1 } {
	if { [maskip $sip $netbits] == $fip } break
      }
      if { $netbits == 0 } {
	set netblock [cformat main.range [lindex $netblock 0] [lindex $netblock 1]]
      } {
	set netblock [cformat main.net [lindex $netblock 0] $netbits]
      }
    }
  }
  set_ [cjoin $_ join]
  if { $LocHost == "" || $LocHost == $LocIP } {
    reply -uniq main.ip $LocIP $_ $netblock
  } {
    reply -uniq main.host $LocHost $LocIP $_ $netblock
  }
}

namespace eval ::locate {
  set countryidx(names) {
	"AFGHANISTAN" "ALBANIA" "ALGERIA" "AMERICAN SAMOA"
	"ANDORRA" "ANGOLA" "ANGUILLA" "ANTARCTICA"
	"ANTIGUA AND BARBUDA" "ARGENTINA" "ARMENIA" "ARUBA"
	"AUSTRALIA" "AUSTRIA" "AZERBAIJAN" "BAHAMAS"
	"BAHRAIN" "BANGLADESH" "BARBADOS" "BELARUS"
	"BELGIUM" "BELIZE" "BENIN" "BERMUDA"
	"BHUTAN" "BOLIVIA" "BOSNIA" "BOTSWANA"
	"BOUVET ISLAND" "BRAZIL" "BRITISH INDIAN OCEAN TERRITORY" "BRUNEI DARUSSALAM"
	"BULGARIA" "BURKINA FASO" "BURUNDI" "BYELORUSSIA"
	"CAMBODIA" "CAMEROON" "CANADA" "CAP VERDE"
	"CAYMAN ISLANDS" "CENTRAL AFRICAN REPUBLIC" "CHAD" "CHILE"
	"CHINA" "CHRISTMAS ISLAND" "COCOS (KEELING) ISLANDS" "COLOMBIA"
	"COMOROS" "CONGO" "COOK ISLANDS" "COSTA RICA"
	"COTE D'IVOIRE" "CROATIA" "HRVATSKA" "CUBA"
	"CYPRUS" "CZECHOSLOVAKIA" "DENMARK" "DJIBOUTI"
	"DOMINICA" "DOMINICAN REPUBLIC" "EAST TIMOR" "ECUADOR"
	"EGYPT" "EL SALVADOR" "EQUATORIAL GUINEA" "ESTONIA"
	"ETHIOPIA" "FALKLAND ISLANDS" "MALVINAS" "FAROE ISLANDS"
	"FIJI" "FINLAND" "FRANCE" "FRENCH GUIANA"
	"FRENCH POLYNESIA" "FRENCH SOUTHERN TERRITORIES" "GABON" "GAMBIA"
	"GEORGIA" "GERMANY" "DEUTSCHLAND" "GHANA"
	"GIBRALTAR" "GREECE" "GREENLAND" "GRENADA"
	"GUADELOUPE" "GUAM" "GUATEMALA" "GUINEA"
	"GUINEA BISSAU" "GYANA" "HAITI" "HEARD AND MC DONALD ISLANDS"
	"HONDURAS" "HONG KONG" "HUNGARY" "ICELAND"
	"INDIA" "INDONESIA" "IRAN" "IRAQ"
	"IRELAND" "ISRAEL" "ITALY" "JAMAICA"
	"JAPAN" "JORDAN" "KAZAKHSTAN" "KENYA"
	"KIRIBATI" "NORTH KOREA" "SOUTH KOREA" "KUWAIT"
	"KYRGYZSTAN" "LAOS" "LATVIA" "LEBANON"
	"LESOTHO" "LIBERIA" "LIBYAN ARAB JAMAHIRIYA" "LIECHTENSTEIN"
	"LITHUANIA" "LUXEMBOURG" "MACAU" "MACEDONIA"
	"MADAGASCAR" "MALAWI" "MALAYSIA" "MALDIVES"
	"MALI" "MALTA" "MARSHALL ISLANDS" "MARTINIQUE"
	"MAURITANIA" "MAURITIUS" "MEXICO" "MICRONESIA"
	"MOLDOVA" "MONACO" "MONGOLIA" "MONTSERRAT"
	"MOROCCO" "MOZAMBIQUE" "MYANMAR" "NAMIBIA"
	"NAURU" "NEPAL" "NETHERLANDS" "NETHERLANDS ANTILLES"
	"NEUTRAL ZONE" "NEW CALEDONIA" "NEW ZEALAND" "NICARAGUA"
	"NIGER" "NIGERIA" "NIUE" "NORFOLK ISLAND"
	"NORTHERN MARIANA ISLANDS" "NORWAY" "OMAN" "PAKISTAN"
	"PALAU" "PANAMA" "PAPUA NEW GUINEA" "PARAGUAY"
	"PERU" "PHILIPPINES" "PITCAIRN" "POLAND"
	"PORTUGAL" "PUERTO RICO" "QATAR" "REUNION"
	"ROMANIA" "RUSSIAN FEDERATION" "RWANDA" "SAINT KITTS AND NEVIS"
	"SAINT LUCIA" "SAINT VINCENT AND THE GRENADINES" "SAMOA" "SAN MARINO"
	"SAO TOME AND PRINCIPE" "SAUDI ARABIA" "SENEGAL" "SEYCHELLES"
	"SIERRA LEONE" "SINGAPORE" "SLOVENIA" "SOLOMON ISLANDS"
	"SOMALIA" "SOUTH AFRICA" "SPAIN" "SRI LANKA"
	"ST. HELENA" "ST. PIERRE AND MIQUELON" "SUDAN" "SURINAME"
	"SVALBARD AND JAN MAYEN ISLANDS" "SWAZILAND" "SWEDEN" "SWITZERLAND"
	"CANTONS OF HELVETIA" "SYRIAN ARAB REPUBLIC" "TAIWAN" "TAJIKISTAN"
	"TANZANIA" "THAILAND" "TOGO" "TOKELAU"
	"TONGA" "TRINIDAD AND TOBAGO" "TUNISIA" "TURKEY"
	"TURKMENISTAN" "TURKS AND CAICOS ISLANDS" "TUVALU" "UGANDA"
	"UKRAINE" "UNITED ARAB EMIRATES" "UNITED KINGDOM" "GREAT BRITAIN"
	"UNITED STATES OF AMERICA" "UNITED STATES MINOR OUTLYING ISLANDS" "URUGUAY"
	"SOVIET UNION" "UZBEKISTAN" "VANUATU" "VATICAN CITY STATE" "VENEZUELA"
	"VIET NAM" "VIRGIN ISLANDS (US)" "VIRGIN ISLANDS (UK)" "WALLIS AND FUTUNA ISLANDS"
	"WESTERN SAHARA" "YEMEN" "YUGOSLAVIA" "ZAIRE"
	"ZAMBIA" "ZIMBABWE" "COMMERCIAL ORGANIZATION (US)" "EDUCATIONAL INSTITUTION (US)"
	"NETWORKING ORGANIZATION (US)" "MILITARY (US)" "NON-PROFIT ORGANIZATION (US)"
	"GOVERNMENT (US)" "KOREA - DEMOCRATIC PEOPLE'S REPUBLIC OF" "KOREA - REPUBLIC OF"
	"LAO PEOPLES' DEMOCRATIC REPUBLIC" "RUSSIA" "SLOVAKIA" "CZECH"
  }
  set countryidx(domains) {
	AF AL DZ AS AD AO AI AQ AG AR AM AW AU AT AZ BS BH BD BB BY BE
	BZ BJ BM BT BO BA BW BV BR IO BN BG BF BI BY KH CM CA CV KY CF
	TD CL CN CX CC CO KM CG CK CR CI HR HR CU CY CS DK DJ DM DO TP
	EC EG SV GQ EE ET FK FK FO FJ FI FR GF PF TF GA GM GE DE DE GH
	GI GR GL GD GP GU GT GN GW GY HT HM HN HK HU IS IN ID IR IQ IE
	IL IT JM JP JO KZ KE KI KP KR KW KG LA LV LB LS LR LY LI LT LU
	MO MK MG MW MY MV ML MT MH MQ MR MU MX FM MD MC MN MS MA MZ MM
	NA NR NP NL AN NT NC NZ NI NE NG NU NF MP NO OM PK PW PA PG PY
	PE PH PN PL PT PR QA RE RO RU RW KN LC VC WS SM ST SA SN SC SL
	SG SI SB SO ZA ES LK SH PM SD SR SJ SZ SE CH CH SY TW TJ TZ TH
	TG TK TO TT TN TR TM TC TV UG UA AE UK GB US UM UY SU UZ VU VA
	VE VN VI VG WF EH YE YU ZR ZM ZW COM EDU NET MIL ORG GOV KP KR
	LA SU SK CZ
  }
  set countryidx(statenames) {
         "ALABAMA" "ALASKA" "AMERICAN SAMOA" "ARIZONA" "ARKANSAS" "CALIFORNIA" "COLORADO"
         "CONNECTICUT" "DELAWARE" "DISTRICT OF COLUMBIA" "FEDERATED STATES OF MICRONESIA"
         "FLORIDA" "GEORGIA" "GUAM" "HAWAII" "IDAHO" "ILLINOIS" "INDIANA" "IOWA" "KANSAS"
         "KENTUCKY" "LOUISIANA" "MAINE" "MARSHALL ISLANDS" "MARYLAND" "MASSACHUSETTS" "MICHIGAN"
         "MINNESOTA" "MISSISSIPPI" "MISSOURI" "MONTANA" "NEBRASKA" "NEVADA" "NEW HAMPSHIRE"
         "NEW JERSEY" "NEW MEXICO" "NEW YORK" "NORTH CAROLINA" "NORTH DAKOTA"
         "NORTHERN MARIANA ISLANDS" "OHIO" "OKLAHOMA" "OREGON" "PALAU" "PENNSYLVANIA"
         "PUERTO RICO" "RHODE ISLAND" "SOUTH CAROLINA" "SOUTH DAKOTA" "TENNESSEE" "TEXAS"
         "UTAH" "VERMONT" "VIRGIN ISLANDS" "VIRGINIA" "WASHINGTON" "WEST VIRGINIA" "WISCONSIN" "WYOMING"
         "NOVA SCOTIA"
  }
  set countryidx(shortstatenames) {
         AL AK AS AZ AR CA CO CT DE DC FM FL GA GU HI ID IL IN IA KS KY
         LA ME MH MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND MP OH OK
         OR PW PA PR RI SC SD TN TX UT VT VI VA WA WV WI WY NS
  }

  set reserved {
    0.0.0.0/8
    "Addresses in this block refer to source hosts on \"this\" network."
    10.0.0.0/8
    "This block is set aside for use in private networks. Its intended use is documented in \[RFC1918\]."
    127.0.0.0/8
    "This block is assigned for use as the Internet host loopback address."
    128.0.0.0/16
    "This block, corresponding to the numerically lowest of the former Class B addresses, was initially and is still reserved by the IANA."
    169.254.0.0/16
    "This is the \"link local\" block.  It is allocated for communication between hosts on a single link."
    172.16.0.0/12
    "This block is set aside for use in private networks. Its intended use is documented in \[RFC1918\]."
    191.255.0.0/16
    "This block, corresponding to the numerically highest to the former Class B addresses, was initially and is still reserved by the IANA."
    192.0.0.0/24
    "This block, corresponding to the numerically lowest of the former Class C addresses, was initially and is still reserved by the IANA."
    192.0.2.0/24
    "This block is assigned as \"TEST-NET\" for use in documentation and example code."
    192.168.0.0/16
    "This block is set aside for use in private networks. Its intended use is documented in \[RFC1918\]."
    198.18.0.0/15
    "This block has been allocated for use in benchmark tests of network interconnect devices.  Its use is documented in \[RFC2544\]."
    223.255.255.0/24
    "This block, corresponding to the numerically highest of the former Class C addresses, was initially and is still reserved by the IANA."
    224.0.0.0/4
    "This block, formerly known as the Class D address space, is allocated for use in IPv4 multicast address assignments. The IANA guidelines for assignments from this space are described in \[RFC3171\]."
    240.0.0.0/4
    "This block, formerly known as the Class E address space, is reserved.  The \"limited broadcast\" destination address 255.255.255.255 should never be forwarded outside the (sub-)net of the source."
  }
}
