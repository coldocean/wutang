# protect.tcl — MASTERS & OWNERS ARE UNTOUCHABLE.
#
# Any user whose eggdrop handle carries the owner (+n), master (+m) or op (+o)
# flag — globally or on the channel — can NEVER be kicked or banned by this bot,
# under any circumstance, by any script.
#
# This is enforced at the LOWEST level: the core Tcl commands that kick and ban
# are renamed and wrapped, so EVERY script (antispam, boss enforcement, admin
# commands, console, trivia, third-party scripts) is covered automatically —
# including any script added in the future. There is no code path around it.
#
# Sourced FIRST in eggdrop.conf, before every other script.

namespace eval protect {
    # Handle flags that grant immunity. n = owner, m = master, o = op.
    variable flags {n m o}
}

# --- is this handle immune? ------------------------------------------------
proc protect::hand_immune {hand {chan ""}} {
    variable flags
    if {$hand eq "" || $hand eq "*"} { return 0 }
    foreach f $flags {
        # global flag
        if {[matchattr $hand $f]} { return 1 }
        # channel-specific flag
        if {$chan ne "" && [matchattr $hand |$f $chan]} { return 1 }
    }
    return 0
}

# --- is this NICK immune? --------------------------------------------------
proc protect::immune {nick {chan ""}} {
    if {$nick eq ""} { return 0 }
    # the bot never kicks/bans itself
    if {[string equal -nocase $nick $::botnick]} { return 1 }

    # resolve nick -> handle. Try the channel first, then all channels.
    set hand ""
    if {$chan ne "" && [validchan $chan] && [onchan $nick $chan]} {
        set hand [nick2hand $nick $chan]
    }
    if {$hand eq "" || $hand eq "*"} { set hand [nick2hand $nick] }
    if {[protect::hand_immune $hand $chan]} { return 1 }

    # Fall back to hostmask lookup, in case nick2hand missed.
    if {$chan ne "" && [validchan $chan] && [onchan $nick $chan]} {
        set uh [getchanhost $nick $chan]
        if {$uh ne ""} {
            set h [finduser "$nick!$uh"]
            if {[protect::hand_immune $h $chan]} { return 1 }
        }
    }
    return 0
}

# --- would this ban MASK hit an immune user? -------------------------------
# Stops "ban the host, then kick" from landing on a master/owner.
proc protect::mask_immune {mask {chan ""}} {
    if {$mask eq ""} { return 0 }
    set chans [expr {$chan ne "" ? [list $chan] : [channels]}]
    foreach c $chans {
        if {![validchan $c] || ![botonchan $c]} { continue }
        foreach n [chanlist $c] {
            set uh [getchanhost $n $c]
            if {$uh eq ""} { continue }
            if {[string match -nocase $mask "$n!$uh"]} {
                if {[protect::immune $n $c]} { return 1 }
            }
        }
    }
    # Also catch masks aimed at a master/owner who is currently offline.
    foreach h [userlist] {
        if {![protect::hand_immune $h $chan]} { continue }
        foreach hm [getuser $h HOSTS] {
            if {[string match -nocase $mask $hm] || [string match -nocase $hm $mask]} { return 1 }
        }
    }
    return 0
}

# ===========================================================================
#  Wrap the core commands. Renamed once; guards are permanent.
# ===========================================================================

if {[info commands ::protect::_orig_putkick] eq ""} {
    rename ::putkick ::protect::_orig_putkick
    proc ::putkick {chan nicks {reason ""}} {
        set allow {}
        foreach n [split $nicks ,] {
            if {[protect::immune $n $chan]} {
                putlog "protect: REFUSED kick of master/owner $n on $chan"
                continue
            }
            lappend allow $n
        }
        if {![llength $allow]} { return }
        return [::protect::_orig_putkick $chan [join $allow ,] $reason]
    }
}

if {[info commands ::protect::_orig_newchanban] eq ""} {
    rename ::newchanban ::protect::_orig_newchanban
    proc ::newchanban {chan ban creator comment {lifetime ""} args} {
        if {[protect::mask_immune $ban $chan]} {
            putlog "protect: REFUSED ban $ban on $chan (matches a master/owner)"
            return
        }
        if {$lifetime eq ""} {
            return [::protect::_orig_newchanban $chan $ban $creator $comment]
        }
        return [eval [list ::protect::_orig_newchanban $chan $ban $creator $comment $lifetime] $args]
    }
}

if {[info commands ::protect::_orig_newban] eq ""} {
    rename ::newban ::protect::_orig_newban
    proc ::newban {ban creator comment {lifetime ""} args} {
        if {[protect::mask_immune $ban]} {
            putlog "protect: REFUSED global ban $ban (matches a master/owner)"
            return
        }
        if {$lifetime eq ""} {
            return [::protect::_orig_newban $ban $creator $comment]
        }
        return [eval [list ::protect::_orig_newban $ban $creator $comment $lifetime] $args]
    }
}

# --- raw server output: catch "KICK #chan nick" and "MODE #chan +b mask" ---
proc protect::filter_raw {text} {
    set parts [split $text " "]
    set cmd [string toupper [lindex $parts 0]]

    if {$cmd eq "KICK"} {
        set chan [lindex $parts 1]
        set victims [lindex $parts 2]
        set keep {}
        foreach v [split $victims ,] {
            if {[protect::immune $v $chan]} {
                putlog "protect: REFUSED raw KICK of master/owner $v on $chan"
                continue
            }
            lappend keep $v
        }
        if {![llength $keep]} { return "" }
        set parts [lreplace $parts 2 2 [join $keep ,]]
        return [join $parts " "]
    }

    if {$cmd eq "MODE"} {
        set chan [lindex $parts 1]
        set modes [lindex $parts 2]
        # only inspect simple "+b mask" / "+bb m1 m2" style ban additions
        if {[string match "*b*" $modes] && [string match "+*" $modes]} {
            set i 3
            foreach m [lrange $parts 3 end] {
                if {[protect::mask_immune $m $chan]} {
                    putlog "protect: REFUSED raw MODE +b $m on $chan (master/owner)"
                    return ""
                }
                incr i
            }
        }
        return $text
    }

    return $text
}

foreach _pcmd {putserv puthelp putquick} {
    if {[info commands ::protect::_orig_$_pcmd] eq ""} {
        rename ::$_pcmd ::protect::_orig_$_pcmd
        proc ::$_pcmd {text args} [string map [list @@CMD@@ $_pcmd] {
            set filtered [protect::filter_raw $text]
            if {$filtered eq ""} { return }
            return [eval [list ::protect::_orig_@@CMD@@ $filtered] $args]
        }]
    }
}
unset -nocomplain _pcmd

# --- pushmode: the queued mode setter used for +b -------------------------
if {[info commands ::protect::_orig_pushmode] eq ""} {
    rename ::pushmode ::protect::_orig_pushmode
    proc ::pushmode {chan mode {arg ""}} {
        if {[string match "+b*" $mode] && $arg ne ""} {
            if {[protect::mask_immune $arg $chan]} {
                putlog "protect: REFUSED pushmode +b $arg on $chan (master/owner)"
                return
            }
        }
        if {[string match "-o*" $mode] || [string match "+b*" $mode]} {
            # never deop a master/owner either
            if {[string match "-o*" $mode] && $arg ne "" && [protect::immune $arg $chan]} {
                putlog "protect: REFUSED deop of master/owner $arg on $chan"
                return
            }
        }
        if {$arg eq ""} { return [::protect::_orig_pushmode $chan $mode] }
        return [::protect::_orig_pushmode $chan $mode $arg]
    }
}

putlog "protect.tcl loaded — masters (+m) & owners (+n) can never be kicked or banned"

# ===========================================================================
#  SELF-HEAL: make sure configured owners really hold +n, and purge any
#  stale ban (channel or global, stored or live) that hits a master/owner.
# ===========================================================================

proc protect::ensure_owners {} {
    foreach o [split [string map {, " "} $::owner] " "] {
        set o [string trim $o]
        if {$o eq ""} { continue }
        if {![validuser $o]} { adduser $o }
        if {![matchattr $o n]} {
            chattr $o +nmfo
            putlog "protect: restored owner flags (+nmfo) on handle $o"
        }
    }
}

proc protect::purge_bans {} {
    # stored + live channel bans
    foreach c [channels] {
        if {![validchan $c]} { continue }
        foreach b [chanbans $c] {
            set mask [lindex $b 0]
            if {[protect::mask_immune $mask $c]} {
                catch {killchanban $c $mask}
                catch {::protect::_orig_pushmode $c -b $mask}
                putlog "protect: purged stale ban $mask on $c (master/owner)"
            }
        }
    }
    # global bans
    foreach b [banlist] {
        set mask [lindex $b 0]
        if {[protect::mask_immune $mask]} {
            catch {killban $mask}
            putlog "protect: purged stale global ban $mask (master/owner)"
        }
    }
}

proc protect::sweep {} {
    catch {protect::ensure_owners}
    catch {protect::purge_bans}
}

# run on connect and every minute thereafter
bind evnt - init-server protect::evnt_sweep
proc protect::evnt_sweep {type} {
    utimer 15 protect::sweep
    utimer 45 protect::sweep
}
bind time - "* * * * *" protect::time_sweep
proc protect::time_sweep {min hour day month year} { protect::sweep }

# also once at load, in case the bot is already connected (rehash)
catch {protect::ensure_owners}
utimer 20 protect::sweep

putlog "protect.tcl: owner self-heal + stale-ban purge active"
