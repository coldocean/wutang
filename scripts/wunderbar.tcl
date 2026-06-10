# wunderbar.tcl — core behaviour for WU-tang on the Wunderbar network.
#
#  * Auto-identifies to NickServ on connect (password from env via .conf).
#  * Joins & keeps the configured channels.
#  * Re-grabs ops, recovers its nick.
#
# The NickServ password is read from the file written by the entrypoint at
# /opt/eggdrop/data/nickserv.pass (kept out of the repo / config).

namespace eval wunderbar {
    variable channels {#lobby #help #wunderbar #Liepaja}
    variable nspassfile "/opt/eggdrop/data/nickserv.pass"
    # Email used if the bot has to self-register its nick with NickServ.
    variable regemail "wutang@wunderbar.lv"
}

# Read the NickServ password from the file the entrypoint wrote.
proc wunderbar::nspass {} {
    variable nspassfile
    if {![file exists $nspassfile]} { return "" }
    set fh [open $nspassfile r]
    set pass [string trim [read $fh]]
    close $fh
    return $pass
}

# --- identify to NickServ once we're connected ---
proc wunderbar::nickserv_identify {type} {
    set pass [wunderbar::nspass]
    if {$pass eq ""} {
        putlog "wunderbar: no NickServ password, skipping IDENTIFY."
        return
    }
    putquick "PRIVMSG NickServ :IDENTIFY $pass"
    putlog "wunderbar: sent NickServ IDENTIFY."
}

# If NickServ tells us the nick isn't registered, register it so future
# IDENTIFYs (and ChanServ ops) work. Atheme: REGISTER <password> <email>.
bind notc - "*not a registered*" wunderbar::ns_notice
bind notc - "*isn't registered*"  wunderbar::ns_notice
proc wunderbar::ns_notice {nick uhost hand text {dest ""}} {
    if {![string match -nocase "NickServ*" $nick]} { return }
    variable regemail
    set pass [wunderbar::nspass]
    if {$pass eq ""} { return }
    putlog "wunderbar: nick not registered — sending NickServ REGISTER."
    putquick "PRIVMSG NickServ :REGISTER $pass $regemail"
}

# When fully connected to the server (event 'init-server' fires after MOTD).
bind evnt - init-server wunderbar::on_connect
proc wunderbar::on_connect {type} {
    # tiny delay so the nick is settled, then identify and join.
    utimer 3 [list wunderbar::nickserv_identify connect]
    utimer 6 wunderbar::join_all
}

proc wunderbar::join_all {} {
    variable channels
    foreach ch $channels {
        if {![validchan $ch]} { channel add $ch }
        if {![onchan $::botnick $ch]} { putquick "JOIN $ch" }
    }
}

# Make sure all our channels are registered with the channels module.
proc wunderbar::ensure_chans {} {
    variable channels
    foreach ch $channels {
        if {![validchan $ch]} {
            channel add $ch
            putlog "wunderbar: added channel $ch"
        }
    }
}
wunderbar::ensure_chans

# Try to keep ops: if someone deops us, ask ChanServ for ops back.
bind mode - "*-o*" wunderbar::deopped
proc wunderbar::deopped {nick uhost hand chan mode target} {
    if {$target eq $::botnick && ![isop $::botnick $chan]} {
        putquick "PRIVMSG ChanServ :OP $chan $::botnick"
    }
}

# Recover our nick if we're on the altnick.
bind time - "* * * * *" wunderbar::nick_recover
proc wunderbar::nick_recover {min hour day month year} {
    if {$::botnick ne $::nick} {
        putquick "PRIVMSG NickServ :GHOST $::nick"
        utimer 2 [list putquick "NICK $::nick"]
    }
}

putlog "wunderbar.tcl loaded."
