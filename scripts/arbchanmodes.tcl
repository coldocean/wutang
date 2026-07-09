# arbchanmodes.tcl
# Provides additional Eggdrop Tcl functions to check for any valid user prefix
#
# 2010-2019 (c) Thomas "thommey" Sader
#
# Thanks for bugreports to: SpiKe^^, EliteGod
#
# ----------------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 42):
# <thommey@gmail.com> wrote this file. As long as you retain this notice you
# can do whatever you want with this stuff. If we meet some day, and you think
# this stuff is worth it, you can buy me a beer in return. Thomas Sader
# ----------------------------------------------------------------------------
#
# Adds the following Tcl functions:
#
# isowner <nick> [chan] - checks for prefix ~ (mode +q)
# isadmin <nick> [chan] - checks for prefix & (mode +a)
#
###############
# Settings
###############
# These are the modes that are going to be passed on to eggdrop.
# The other ones NOT sent to eggdrop itself, but still passed on to scripts (mode binds).
# You should not need to touch this, last updated for: Eggdrop v1.8.2
# This is similar to the format of RAW 005 (RPL_ISUPPORT), meaning:
# <prefix/user modes>,<list-type modes>,<key-type modes>,<limit-type modes>,<flag modes>
set eggmodeconfig "ohv,beI,k,l,ipsmcCRMrDuNTdtnaq"

###############
# If you touch the code below and then complain the script "suddenly stopped working" I'll touch you at night.
###############

package require Tcl 8.4
package require eggdrop

proc lchange {varname old new} {
	upvar 1 $varname list
	if {![info exists list]} { return }
	while {[set pos [lsearch -exact $list $old]] != -1} {
		set list [lreplace $list $pos $pos]
		lappend list $new
	}
	return $list
}

proc lremove {varname element} {
	upvar 1 $varname list
	if {![info exists list]} { return }
	while {[set pos [lsearch -exact $list $element]] != -1} {
		set list [lreplace $list $pos $pos]
	}
	return $list
}

proc mcin {modechar modelist} {
	expr {[string first $modechar $modelist] != -1}
}

bind raw - 005 parse005
proc parse005 {from key text} {
	if {[regexp {CHANMODES=(\S+)} $text -> modes]} {
		set ::modeconfig [split $modes ,]
	}
	if {[regexp {PREFIX=\((\S+)\)} $text -> umodes]} {
		set ::umodeconfig $umodes
	}
	return 0
}

proc getmodeconfig {} {
	if {![info exists ::umodeconfig]} {
		putlog "Arbchanmodes: Could not get usermodeconfig from raw 005!"
		set ::umodeconfig qaohv
	}
	if {![info exists ::modeconfig]} {
		putlog "Arbchanmodes: Could not get modeconfig from raw 005!"
		set ::modeconfig [split beI,kfL,lj,psmntirRcOAQKVCuzNSMTGZ ,]
	}
	concat [list $::umodeconfig] $::modeconfig
}

proc geteggmodeconfig {} {
	if {![info exists ::eggmodeconfig]} {
		putlog "Arbchanmodes: Eggmodeconfig not set, using default!"
		set ::eggmodeconfig "ohv,beI,k,l,ipsmcCRMrDuNTdtnaq"
	}
	split $::eggmodeconfig ","
}

proc modeparam {pre modechar modeconfig} {
	foreach {umodes ban key limit flag} $modeconfig { break }
	set pls [expr {$pre eq "+"}]
	if {[mcin $modechar $umodes] || [mcin $modechar $ban] || [mcin $modechar $key]} {
		return 1
	}
	if {[mcin $modechar $limit]} {
		return $pls
	}
	if {[mcin $modechar $flag]} {
		return 0
	}
	return -1
}

proc handleerr {msg} {
	if {[llength [info commands bgerror]]} {
		bgerror $msg
	} else {
		putlog $msg
	}
}

proc ircwordsplit {string} {
	set result ""
	foreach {- 1 2} [regexp -all -inline {(?::(.*$)|(\S+))} $string] { lappend result $1$2 }
	return $result
}

bind raw - MODE parsemode
# "thommey!thommey@tclhelp.net MODE #thommey -v+v TCL ^|^"
# "thommey!thommey@tclhelp.net MODE #thommey -v+v TCL :^|^" <- InspIRCd 3 being weird.
proc parsemode {from key text} {
	set text [ircwordsplit $text]
	set chan [string tolower [lindex $text 0]]
	if {![validchan $chan]} { return }
	foreach {parse eggparse} [parsemodestr [lindex $text 1] [lrange $text 2 end]] break
	foreach {mode victim} $parse {
		set victim [string tolower $victim]
		if {$mode eq "+q"} { lappend ::_owners($chan) $victim }
		if {$mode eq "-q"} { lremove ::_owners($chan) $victim }
		if {$mode eq "+a"} { lappend ::_admins($chan) $victim }
		if {$mode eq "-a"} { lremove ::_admins($chan) $victim }
	}
	set eggstr [buildmodestr $eggparse]
	if {$eggstr ne ""} {
		# server.mod/servmsg.c:gotmode()
		if {[catch {*raw:MODE $from $key "$chan $eggstr"} err]} {
			catch {handleerr "Tcl Background Error in server.mod:gotmmode(): $err"}
		}
		# irc.mod/mode.c:gotmode()
		if {[catch {*raw:irc:mode $from $key "$chan $eggstr"} err]} {
			catch {handleerr "Tcl Background Error in irc.mod:gotmode(): $err"}
		}
	}
	return 1
}

# removes first element from the list and returns it
proc pop {varname} {
	upvar 1 $varname list
	if {![info exists list]} { return "" }
	set elem [lindex $list 0]
	set list [lrange $list 1 end]
	return $elem
}

# parses a modestring "+v-v" and a list of victims {nick1 nick2} and returns a flat list in the form {modechange victim modechange victim ..}
# static modelist with parameters taken from unrealircd (better do it dynamically on raw 005 ;)
proc parsemodestr {modestr victims} {
	set result [list]
	set eggresult [list]
	set pre "+"
	foreach char [split $modestr ""] {
		if {$char eq "+" || $char eq "-"} {
			set pre $char
		} else {
			set useparam [modeparam $pre $char [getmodeconfig]]
			if {$useparam == -1} {
				error "Arbchanmodes: Unknown mode char '$char'!"
			}
			set egguseparam [modeparam $pre $char [geteggmodeconfig]]
			set param [expr {$useparam == 1 ? [pop victims] : ""}]
			lappend result $pre$char $param
			# Forward modes to eggdrop if they match IRCd config and are in the setting
			if {$egguseparam != -1 && $egguseparam == $useparam} {
				lappend eggresult $pre$char $param
			}
		}
	}
	return [list $result $eggresult]
}

# opposite of the above, re-assemble a mode string
proc buildmodestr {parse} {
	set pre ""
	set modestr ""
	set params ""
	foreach {mode arg} $parse {
		if {[string index $mode 0] ne $pre} {
			set pre [string index $mode 0]
			append modestr $pre
		}
		append modestr [string index $mode 1]
		if {$arg ne ""} {
			lappend params $arg
		}
	}
	join [concat [list $modestr] $params]
}

proc isowner {nick chan} {
	set nick [string tolower $nick]
	set chan [string tolower $chan]
	if {![info exists ::_owners($chan)]} { return 0 }
	if {[lsearch -exact $::_owners($chan) $nick] == -1} { return 0 }
	return 1
}

proc isadmin {nick chan} {
	set nick [string tolower $nick]
	set chan [string tolower $chan]
	if {![info exists ::_admins($chan)]} { return 0 }
	if {[lsearch -exact $::_admins($chan) $nick] == -1} { return 0 }
	return 1
}

proc resetlists {chan} {
	if {[validchan $chan]} {
		set channels [list $chan]
	} else {
		set channels [channels]
	}
	foreach chan [channels] {
		set chan [string tolower $chan]
		unset -nocomplain ::_owners($chan)
		unset -nocomplain ::_admins($chan)
	}
}

bind raw - 352 parsewho
proc parsewho {f k t} {
	foreach {mynick chan ident host server nick flags} [split $t] break
	set nick [string tolower $nick]
	set chan [string tolower $chan]
	if {![validchan $chan]} { return }
	if {[string first "~" $flags] != -1} { lappend ::_owners($chan) $nick }
	if {[string first "&" $flags] != -1} { lappend ::_admins($chan) $nick }
	return 0
}

bind nick - * checktheynick
bind part - * checktheyleft
bind sign - * checktheyleft
proc checktheynick {nick host hand chan newnick} {
	set chan [string tolower $chan]
	set nick [string tolower $nick]
	set newnick [string tolower $newnick]
	lchange ::_owners($chan) $nick $newnick
	lchange ::_admins($chan) $nick $newnick
}
proc checktheyleft {nick host hand chan reason} {
	set nick [string tolower $nick]
	set chan [string tolower $chan]
	lremove ::_owners($chan) $nick
	lremove ::_admins($chan) $nick
}

# Handle eggdrop leaving channels
bind part - * checkileft
bind sign - * checkileft
bind kick - * checkikicked
bind evnt - disconnect-server resetlists

proc checkileft {nick host hand chan {msg ""}} {
	if {![isbotnick $nick]} { return }
	resetlists $chan
}
proc checkikicked {nick host hand chan target reason} {
	if {![isbotnick $target]} { return }
	resetlists $chan
}
