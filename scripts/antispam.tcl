# antispam.tcl — enforce the Wunderbar rules: no flooding, no spam, no ads.
# Auto-warns once, then kick+ban on repeat. Ops/voiced/owners are exempt.
#
# Works alongside Eggdrop's built-in flood protection (set in eggdrop.conf).
# This adds: repeat-line detection, advertising/link-spam detection, and
# excessive-CAPS handling.

namespace eval antispam {
    variable lastline       ;# array: nick|chan -> last message
    variable repeatcount    ;# array: nick|chan -> repeat counter
    variable warned         ;# array: nick|chan -> warned?
    array set lastline {}
    array set repeatcount {}
    array set warned {}

    # Patterns considered advertising / spam (other networks, invites, etc.)
    variable adpatterns {
        {(?i)irc\.(?!wunderbar\.lv)[a-z0-9.-]+\s}
        {(?i)\bjoin\s+irc\.}
        {(?i)\b(free\s+nitro|crypto\s+giveaway|click\s+here\s+to\s+win)\b}
        {(?i)(https?://\S+\s+){3,}}
    }
}

proc antispam::exempt {nick chan} {
    if {[isop $nick $chan]} { return 1 }
    if {[isvoice $nick $chan]} { return 1 }
    set hand [nick2hand $nick $chan]
    if {$hand ne "" && $hand ne "*"} {
        if {[matchattr $hand n] || [matchattr $hand m] || [matchattr $hand o] || [matchattr $hand f]} {
            return 1
        }
    }
    if {$nick eq $::botnick} { return 1 }
    return 0
}

proc antispam::punish {nick uhost chan reason} {
    variable warned
    set key "[string tolower $nick]|[string tolower $chan]"
    if {![info exists warned($key)]} {
        set warned($key) 1
        putserv "NOTICE $nick :\0034\002\[Wunderbar\]\017 $reason — this is your only warning. Next time = ban."
        utimer 30 [list array unset antispam::warned $key]
        return
    }
    # second offence -> kick + temp ban
    set mask "*!*@[lindex [split $uhost @] 1]"
    newchanban $chan $mask WU-tang "Rule: $reason" 60
    putserv "KICK $chan $nick :\0034Wunderbar rule violation:\017 $reason"
}

bind pubm - * antispam::check
proc antispam::check {nick uhost hand chan text} {
    variable lastline
    variable repeatcount
    variable adpatterns
    if {[antispam::exempt $nick $chan]} { return }

    set key "[string tolower $nick]|[string tolower $chan]"
    set clean [string trim $text]

    # --- repeat / flood of identical lines ---
    if {[info exists lastline($key)] && $lastline($key) eq $clean && $clean ne ""} {
        incr repeatcount($key)
        if {$repeatcount($key) >= 3} {
            antispam::punish $nick $uhost $chan "no flooding (repeated lines)"
            set repeatcount($key) 0
        }
    } else {
        set repeatcount($key) 0
    }
    set lastline($key) $clean

    # --- advertising / link spam ---
    foreach pat $adpatterns {
        if {[regexp $pat "$clean "]} {
            antispam::punish $nick $uhost $chan "no spamming / advertising"
            return
        }
    }

    # --- excessive CAPS (long & mostly uppercase) ---
    if {[string length $clean] >= 20} {
        set caps [regsub -all {[^A-Z]} $clean ""]
        set letters [regsub -all {[^A-Za-z]} $clean ""]
        if {[string length $letters] > 0 &&
            [expr {double([string length $caps]) / [string length $letters]}] > 0.75} {
            antispam::punish $nick $uhost $chan "please don't SHOUT in all caps"
        }
    }
}

# Clear stale counters every few minutes.
bind time - "*0 * * * *" antispam::cleanup
proc antispam::cleanup {min hour day month year} {
    array unset antispam::lastline
    array unset antispam::repeatcount
}

putlog "antispam.tcl loaded — Wunderbar rule enforcement active."
