# funtban.tcl — kick + permanently ban 'funt' from all channels.
# Reason: "bullshitter". Shared across all Wunderbar guardian eggdrops.
#
# Matches funt by nick (funt / funtomas) OR by his registered vhost
# funtomas.wunderbar.lv, so a nick change won't dodge the ban.
# Never touches the op-pact bots or boss (guardian supremacy respected).

namespace eval funtban {
    variable reason "bullshitter"

    # Nicks we always treat as funt (case-insensitive, exact match).
    variable nicks {funt funtomas}

    # Host globs that identify funt regardless of nick.
    variable hostmasks {*!*@*funtomas.wunderbar.lv *!*funt@* *!*~funt@*}

    # Never ban these (pact bots / guardians / self).
    variable protect {WUNDERkind WU-tang HellGatesElf demonEgg boss}
}

proc funtban::is_protected {nick} {
    variable protect
    if {[string equal -nocase $nick [botnick]]} { return 1 }
    foreach b $protect {
        if {[string equal -nocase $nick $b]} { return 1 }
    }
    return 0
}

# Decide if a nick+userhost belongs to funt.
proc funtban::is_funt {nick uhost} {
    variable nicks
    variable hostmasks
    if {[funtban::is_protected $nick]} { return 0 }
    foreach n $nicks {
        if {[string equal -nocase $nick $n]} { return 1 }
    }
    set full "$nick!$uhost"
    foreach m $hostmasks {
        if {[string match -nocase $m $full]} { return 1 }
    }
    return 0
}

# Kick + permanent ban on a single channel.
proc funtban::nuke {nick uhost chan} {
    variable reason
    if {![botisop $chan]} { return }
    # Ban the host so reconnects/nick changes are caught.
    set host [lindex [split $uhost @] 1]
    if {$host eq ""} {
        set mask "$nick!*@*"
    } else {
        set mask "*!*@$host"
    }
    newchanban $chan $mask [botnick] $reason 0
    putserv "KICK $chan $nick :$reason"
}

# On join — nuke immediately.
proc funtban::on_join {nick uhost hand chan} {
    if {[funtban::is_funt $nick $uhost]} {
        utimer 1 [list funtban::nuke $nick $uhost $chan]
    }
}
bind join - * funtban::on_join

# Per-minute sweep — catch anyone already in channel / who slipped in.
proc funtban::sweep {min hour day month year} {
    foreach chan [channels] {
        if {![botonchan $chan] || ![botisop $chan]} { continue }
        foreach nick [chanlist $chan] {
            set uhost [getchanhost $nick $chan]
            if {$uhost ne "" && [funtban::is_funt $nick $uhost]} {
                funtban::nuke $nick $uhost $chan
            }
        }
    }
}
bind time - "* * * * *" funtban::sweep

putlog "funtban.tcl loaded — funt is banned (reason: bullshitter)"
