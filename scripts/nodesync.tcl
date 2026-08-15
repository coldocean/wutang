# nodesync.tcl — Wunderbar
#
# Kill the eggdrop CORE "Abusing desync" kick/ban for good.
#
# Eggdrop's irc.mod (src/mod/irc.mod/mode.c) does this when a user who the bot
# does not consider an op performs a mode change (which happens all the time on
# a services network / after a netsplit / when ChanServ ops someone):
#
#     } else if (!chan_hasop(m) && !chan_hashalfop(m) && !channel_nodesynch(chan)) {
#         putlog(LOG_MODES, ch, CHAN_DESYNCMODE, ch);
#         dprintf(DP_MODE, "KICK %s %s :%s\n", ch, nick, CHAN_DESYNCMODE_KICK);   ;# "Abusing desync"
#
# That KICK is emitted straight from C via dprintf() — it never passes through
# putkick/putserv/puthelp, so scripts/protect.tcl cannot intercept it.
# The ONLY way to stop it is the channel flag +nodesynch.
#
# global-chanset in eggdrop.conf already sets +nodesynch, BUT a per-channel
# setting saved in the persisted .chan file on the Railway volume overrides the
# global default. This script force-applies +nodesynch on every channel, at
# startup, on connect, whenever a channel is added, and on a per-minute sweep —
# so a stale .chan file can never bring the desync kick back.
#
# It also neutralises the sibling core kick "Fake mode change" (CHAN_FAKEMODE_KICK,
# mode.c:1034) for the same reason: it fires on the same services-op desync and
# is not something a real user did wrong.

namespace eval nodesync {
    variable applied 0
}

# ---------------------------------------------------------------------------
# Force +nodesynch on one channel (and clear the flags that make the core
# punish people for mode changes it did not authorise).
# ---------------------------------------------------------------------------
proc nodesync::fix_chan {ch} {
    if {![validchan $ch]} { return 0 }
    set changed 0

    # +nodesynch  -> never kick "Abusing desync"
    if {![channel get $ch nodesynch]} {
        channel set $ch +nodesynch
        set changed 1
    }
    # +dontkickops -> core never kicks anyone the bot knows as an op
    if {![channel get $ch dontkickops]} {
        channel set $ch +dontkickops
        set changed 1
    }
    # -bitch -> do not deop/kick people who were opped by services
    if {[channel get $ch bitch]} {
        channel set $ch -bitch
        set changed 1
    }
    # stopnethack 0 -> do not deop/punish ops that appear after a netsplit
    if {[channel get $ch stopnethack-mode] != 0} {
        channel set $ch stopnethack-mode 0
        set changed 1
    }
    # revenge off -> no retaliation kicks/bans for mode changes
    if {[channel get $ch revenge]} {
        channel set $ch -revenge
        set changed 1
    }
    if {[channel get $ch revengebot]} {
        channel set $ch -revengebot
        set changed 1
    }

    if {$changed} {
        putlog "nodesync: enforced +nodesynch (no 'Abusing desync' kicks) on $ch"
    }
    return $changed
}

proc nodesync::fix_all {} {
    foreach ch [channels] {
        nodesync::fix_chan $ch
        nodesync::purge_bans $ch
    }
    nodesync::purge_global_bans
}

# ---------------------------------------------------------------------------
# Nobody stays banned for "desync" / "fake mode" — lift any such ban that a
# previous build (or an operator) left behind, on the bot's list and live.
# ---------------------------------------------------------------------------
proc nodesync::is_desync_reason {reason} {
    set r [string tolower $reason]
    foreach pat {desync "fake mode" "abusing desync"} {
        if {[string match "*$pat*" $r]} { return 1 }
    }
    return 0
}

proc nodesync::purge_bans {ch} {
    if {![validchan $ch]} { return }
    foreach entry [banlist $ch] {
        set mask   [lindex $entry 0]
        set reason [lindex $entry 1]
        if {[nodesync::is_desync_reason $reason]} {
            catch { killchanban $ch $mask }
            if {[botisop $ch]} { catch { pushmode $ch -b $mask } }
            putlog "nodesync: lifted stale desync ban $mask on $ch"
        }
    }
}

proc nodesync::purge_global_bans {} {
    foreach entry [banlist] {
        set mask   [lindex $entry 0]
        set reason [lindex $entry 1]
        if {[nodesync::is_desync_reason $reason]} {
            catch { killban $mask }
            putlog "nodesync: lifted stale global desync ban $mask"
        }
    }
}

# ---------------------------------------------------------------------------
# Wrap the `channel` command so that `channel add <chan>` and any later
# `channel set <chan> -nodesynch` can never leave a channel unprotected.
# ---------------------------------------------------------------------------
if {![llength [info commands ::nodesync::__real_channel]]} {
    rename ::channel ::nodesync::__real_channel

    proc ::channel {args} {
        set res [uplevel 1 [list ::nodesync::__real_channel {*}$args]]
        if {[llength $args] >= 2} {
            set sub [lindex $args 0]
            set ch  [lindex $args 1]
            if {$sub eq "add" || $sub eq "set"} {
                # re-assert on the next tick so we don't recurse inside the call
                catch { utimer 1 [list nodesync::fix_chan $ch] }
            }
        }
        return $res
    }
}

# ---------------------------------------------------------------------------
# Belt-and-braces: drop any OUTGOING KICK whose reason mentions desync / fake
# mode, no matter which script produced it. (The core kick bypasses this, which
# is why +nodesynch above is the real fix — this only covers Tcl-side callers.)
# ---------------------------------------------------------------------------
proc nodesync::blocked_line {text} {
    if {![string match -nocase "KICK *" $text]} { return 0 }
    set idx [string first ":" $text]
    if {$idx < 0} { return 0 }
    return [nodesync::is_desync_reason [string range $text [expr {$idx + 1}] end]]
}

foreach __ns_cmd {putserv puthelp putquick} {
    if {[llength [info commands ::$__ns_cmd]] &&
        ![llength [info commands ::nodesync::__real_$__ns_cmd]]} {
        rename ::$__ns_cmd ::nodesync::__real_$__ns_cmd
        proc ::$__ns_cmd {text args} "
            if {\[nodesync::blocked_line \$text]} {
                putlog \"nodesync: blocked desync kick -> \$text\"
                return
            }
            return \[uplevel 1 \[list ::nodesync::__real_$__ns_cmd \$text {*}\$args]]
        "
    }
}
unset -nocomplain __ns_cmd

if {[llength [info commands ::putkick]] &&
    ![llength [info commands ::nodesync::__real_putkick]]} {
    rename ::putkick ::nodesync::__real_putkick
    proc ::putkick {chan nicks {reason ""}} {
        if {[nodesync::is_desync_reason $reason]} {
            putlog "nodesync: blocked desync kick of $nicks on $chan"
            return
        }
        return [::nodesync::__real_putkick $chan $nicks $reason]
    }
}

# ---------------------------------------------------------------------------
# Apply now, on connect, and on a per-minute sweep.
# ---------------------------------------------------------------------------
catch { nodesync::fix_all }
catch { utimer 5  nodesync::fix_all }
catch { utimer 30 nodesync::fix_all }

bind evnt - init-server nodesync::on_connect
proc nodesync::on_connect {type} {
    catch { utimer 8  nodesync::fix_all }
    catch { utimer 25 nodesync::fix_all }
}

bind time - "* * * * *" nodesync::sweep
proc nodesync::sweep {min hour day month year} {
    catch { nodesync::fix_all }
}

putlog "nodesync.tcl loaded — core 'Abusing desync' kick/ban disabled on all channels."
