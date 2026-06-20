# oppact.tcl — mutual op-protection pact between the Wunderbar eggdrops.
#
#  * Every bot in the pact ops ITSELF whenever it has ops and notices it lacks +o.
#  * Whenever ANY pact-bot is deopped, the other pact-bots that hold ops will
#    instantly re-op it. So you can never strip a pact-bot of ops for long:
#    deop one, the others put it straight back.
#  * Pact bots also keep each other +o in the userfile (auto-op) and protect
#    each other from kick/ban (a kicked pact-bot is re-invited & the kicker’s
#    op is removed if a peer can do it).
#
# The pact member list comes from env PACT_BOTS (space/comma separated nicks).
# Falls back to the four known eggdrops if unset.

namespace eval oppact {
    variable members
    set env_members ""
    if {[info exists ::env(PACT_BOTS)]} { set env_members $::env(PACT_BOTS) }
    if {[string trim $env_members] eq ""} {
        set env_members "WUNDERkind WU-tang HellGatesElf demonEgg"
    }
    # normalise: split on comma/space, drop blanks
    set members {}
    foreach m [split [string map {, " "} $env_members]] {
        set m [string trim $m]
        if {$m ne ""} { lappend members $m }
    }
}

# Is the given nick one of our pact bots (case-insensitive)?
proc oppact::is_member {nick} {
    variable members
    foreach m $members {
        if {[string equal -nocase $m $nick]} { return 1 }
    }
    return 0
}

# -------------------------------------------------------------------------
# BOSS SUPREMACY: boss is the head guardian. When boss deops / bans someone,
# the pact must NOT undo it. We remember "chan:target" entries that boss has
# acted on, with an expiry, and skip re-opping those targets.
# -------------------------------------------------------------------------
namespace eval oppact { variable bossact ; array set bossact {} }

proc oppact::is_boss {nick} { return [string equal -nocase $nick "boss"] }

# mark chan:target as a boss action (lock re-op for 600s)
proc oppact::boss_lock {chan target} {
    variable bossact
    set bossact([string tolower $chan:$target]) [expr {[clock seconds] + 600}]
}

# is chan:target currently boss-locked (so pact must NOT re-op it)?
proc oppact::boss_locked {chan target} {
    variable bossact
    set k [string tolower $chan:$target]
    if {![info exists bossact($k)]} { return 0 }
    if {[clock seconds] > $bossact($k)} { unset bossact($k) ; return 0 }
    return 1
}

# Op a target on a channel if we currently hold ops there.
proc oppact::give_op {chan target} {
    # never re-op a target boss has acted on (boss supremacy)
    if {[oppact::boss_locked $chan $target]} { return }
    if {[isop $::botnick $chan] && [onchan $target $chan] && ![isop $target $chan]} {
        putquick "MODE $chan +o $target"
    }
}

# Op ourselves via ChanServ if we somehow lack ops.
proc oppact::selfop {chan} {
    if {[onchan $::botnick $chan] && ![isop $::botnick $chan]} {
        putquick "PRIVMSG ChanServ :OP $chan $::botnick"
    }
}

# When a mode change strips +o from someone:
#   - if it was a pact bot -> every other pact bot that has ops re-ops it
#   - if it was US        -> ask ChanServ, and peers will also re-op us
bind mode - "*-o*" oppact::on_deop
proc oppact::on_deop {nick uhost hand chan mode target} {
    # BOSS SUPREMACY: if boss deopped someone, obey it — lock & do not re-op.
    if {[oppact::is_boss $nick]} {
        oppact::boss_lock $chan $target
        putlog "oppact: boss deopped $target on $chan — pact will NOT re-op (boss supremacy)."
        return
    }
    # target is the nick that lost +o
    if {[oppact::is_member $target]} {
        # re-op the deopped pact bot (only if WE hold ops; harmless otherwise)
        utimer 1 [list oppact::give_op $chan $target]
        # if it was us, also poke ChanServ directly
        if {[string equal -nocase $target $::botnick]} {
            utimer 1 [list oppact::selfop $chan]
        }
    }
}

# When a pact bot joins, op it (if we have ops). Also self-op on our own join.
bind join - * oppact::on_join
proc oppact::on_join {nick uhost hand chan} {
    if {[string equal -nocase $nick $::botnick]} {
        # we just joined — make sure we get ops
        utimer 4 [list oppact::selfop $chan]
        return
    }
    if {[oppact::is_member $nick]} {
        utimer 2 [list oppact::give_op $chan $nick]
    }
}

# If a pact bot is kicked, re-invite it and self-recover.
bind kick - * oppact::on_kick
proc oppact::on_kick {nick uhost hand chan target reason} {
    if {[oppact::is_member $target] && ![string equal -nocase $target $::botnick]} {
        if {[isop $::botnick $chan]} {
            putquick "INVITE $target $chan"
        }
    }
}

# Periodic safety sweep: ensure every pact bot present is opped, and that we
# are opped ourselves. Runs every minute.
bind time - "* * * * *" oppact::sweep
proc oppact::sweep {min hour day month year} {
    variable members
    foreach chan [channels] {
        oppact::selfop $chan
        if {[isop $::botnick $chan]} {
            foreach m $members {
                if {[onchan $m $chan] && ![isop $m $chan] && ![string equal -nocase $m $::botnick]} {
                    if {[oppact::boss_locked $chan $m]} { continue }
                    putquick "MODE $chan +o $m"
                }
            }
        }
    }
}

# =========================================================================
# BOSS UNBAN = LAW.  When boss (or any oper acting as boss) lifts a ban,
# every bot records that mask as "boss-cleared" for a window. During that
# window NO bot may re-ban the mask — if one tries, we instantly lift it
# again. This makes a boss unban final across the whole pact.
# =========================================================================
namespace eval oppact { variable bossunban ; array set bossunban {} }

# how long (seconds) a boss unban stays "law" and blocks re-bans
proc oppact::unban_ttl {} { return 1800 }

# record that boss cleared this mask on this channel
proc oppact::lock_unban {chan mask} {
    variable bossunban
    set bossunban([string tolower $chan]\x00[string tolower $mask]) \
        [expr {[clock seconds] + [oppact::unban_ttl]}]
}

# is this exact mask currently boss-cleared on this channel?
proc oppact::unban_locked {chan mask} {
    variable bossunban
    set k [string tolower $chan]\x00[string tolower $mask]
    if {![info exists bossunban($k)]} { return 0 }
    if {[clock seconds] > $bossunban($k)} { unset bossunban($k) ; return 0 }
    return 1
}

# When ANY ban is REMOVED (-b) by boss -> it becomes law. Lock the mask.
bind mode - "*-b*" oppact::on_unban
proc oppact::on_unban {nick uhost hand chan mode target} {
    if {[oppact::is_boss $nick]} {
        oppact::lock_unban $chan $target
        putlog "oppact: boss unbanned $target on $chan — LAW. No bot may re-ban for [oppact::unban_ttl]s."
    }
}

# When ANY ban is ADDED (+b) -> if boss had cleared this mask, lift it again
# immediately. boss's word is final.
bind mode - "*+b*" oppact::on_ban_check
proc oppact::on_ban_check {nick uhost hand chan mode target} {
    # never undo boss's OWN ban
    if {[oppact::is_boss $nick]} { return }
    if {[oppact::unban_locked $chan $target]} {
        if {[isop $::botnick $chan]} {
            putquick "MODE $chan -b $target"
            putlog "oppact: $nick re-banned $target on $chan but boss had unbanned it — LIFTED (boss law)."
        }
    }
}

# Periodic sweep: enforce boss unban law — lift any banned mask boss cleared.
bind time - "* * * * *" oppact::sweep_unbanlaw
proc oppact::sweep_unbanlaw {min hour day month year} {
    variable bossunban
    set now [clock seconds]
    foreach chan [channels] {
        if {![isop $::botnick $chan]} { continue }
        foreach ban [chanbans $chan] {
            set mask [lindex $ban 0]
            if {[oppact::unban_locked $chan $mask]} {
                putquick "MODE $chan -b $mask"
                catch {killchanban $chan $mask}
                putlog "oppact: sweep lifted re-ban $mask on $chan (boss law)."
            }
        }
    }
    # prune expired locks
    foreach k [array names bossunban] {
        if {$now > $bossunban($k)} { unset bossunban($k) }
    }
}

putlog "oppact.tcl loaded — pact: $oppact::members (boss supremacy + boss-unban-law active)"
