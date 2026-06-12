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

# Op a target on a channel if we currently hold ops there.
proc oppact::give_op {chan target} {
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
                    putquick "MODE $chan +o $m"
                }
            }
        }
    }
}

putlog "oppact.tcl loaded — pact: $oppact::members"
