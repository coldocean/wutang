# Maskhost-Fix (c) 2011 thommey, Tothwolf

# Lets maskhost (used by most scripts to select banmask/usermask)
# return *!*@HOST if the thing you set here matches the host
# Usable most likely on Quakenet and Undernet
# to handle *!*@*.users.network.org masks correctly

# Set here now the masks (ex: "*.users.undernet.org").
# One line per mask. It is matched against nick!ident@host.

set ::fakehostmasks {
	*.users.quakenet.org
	*.users.undernet.org
	*!~*
}

proc update_fakehostmasks {name1 name2 op} {
	global fakehostmasks
	global fakehostmasks_list

	set fakehostmasks_list ""

	foreach fmask $fakehostmasks {
		set fmask [string trim $fmask]

		if {$fmask == ""} { continue }

		regsub -all {\\} $fmask {\\\\} fmask
		regsub -all {\[} $fmask {\\\[} fmask
		regsub -all {\]} $fmask {\\\]} fmask

		lappend fakehostmasks_list $fmask
	}

	return
}

if {[info commands maskhost_r] != "maskhost_r"} {
	rename maskhost maskhost_r

	update_fakehostmasks fakehostmasks "" w
	trace variable fakehostmasks w update_fakehostmasks
}

proc maskhost {host} {
	global fakehostmasks_list

	foreach fmask $fakehostmasks_list {
		if {[string match $fmask $host]} {
			return *!*@[lindex [split $host @] end]
		}
	}

	return [maskhost_r $host]
}

putlog "Maskhost-Fix loaded"
