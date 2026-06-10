# stats.tcl — lightweight channel stats: line counts, top talkers, !stats.
# Stores per-channel/per-nick line counts in data/stats.dat (persisted).

namespace eval stats {
    variable file "/opt/eggdrop/data/stats.dat"
    variable count    ;# array chan|nick -> lines
    variable words    ;# array chan|nick -> words
    variable since    ;# array chan      -> epoch first seen
    variable seen     ;# array nick      -> "epoch chan action"
    array set count {}
    array set words {}
    array set since {}
    array set seen {}
}

proc stats::load {} {
    variable file
    variable count
    variable words
    variable since
    if {![file exists $file]} { return }
    set fh [open $file r]
    while {[gets $fh line] >= 0} {
        set p [split $line "\t"]
        if {[llength $p] != 4} { continue }
        lassign $p kind key a b
        switch -- $kind {
            C { set count($key) $a ; set words($key) $b }
            S { set since($key) $a }
            V { set seen($key) "$a\t$b" }
        }
    }
    close $fh
}

proc stats::save {} {
    variable file
    variable count
    variable words
    variable since
    set fh [open $file w]
    foreach k [array names count] {
        puts $fh "C\t$k\t$count($k)\t[expr {[info exists words($k)] ? $words($k) : 0}]"
    }
    foreach k [array names since] {
        puts $fh "S\t$k\t$since($k)\t0"
    }
    foreach k [array names seen] {
        puts $fh "V\t$k\t$seen($k)"
    }
    close $fh
}

stats::load

bind pubm - * stats::track
proc stats::track {nick uhost hand chan text} {
    variable count
    variable words
    variable since
    variable seen
    if {$nick eq $::botnick} { return }
    set ch [string tolower $chan]
    set key "$ch|[string tolower $nick]"
    incr count($key)
    if {![info exists words($key)]} { set words($key) 0 }
    incr words($key) [llength [split $text]]
    if {![info exists since($ch)]} { set since($ch) [clock seconds] }
    set seen([string tolower $nick]) "[clock seconds]\ttalking in $chan"
}

# Record last-seen on join/part/quit/nick too.
bind join - * stats::seen_join
proc stats::seen_join {nick uhost hand chan} {
    variable seen
    if {$nick eq $::botnick} { return }
    set seen([string tolower $nick]) "[clock seconds]\tjoining $chan"
}
bind part - * stats::seen_part
proc stats::seen_part {nick uhost hand chan {msg ""}} {
    variable seen
    set seen([string tolower $nick]) "[clock seconds]\tleaving $chan"
}
bind sign - * stats::seen_sign
proc stats::seen_sign {nick uhost hand chan {reason ""}} {
    variable seen
    set seen([string tolower $nick]) "[clock seconds]\tquitting ($reason)"
}
bind nick - * stats::seen_nick
proc stats::seen_nick {nick uhost hand chan newnick} {
    variable seen
    set seen([string tolower $nick]) "[clock seconds]\tchanging nick to $newnick"
    set seen([string tolower $newnick]) "[clock seconds]\tchanging nick from $nick"
}

# !stats  -> show channel summary + top talkers
bind pub - "!stats" stats::pub_stats
proc stats::pub_stats {nick uhost hand chan text} {
    variable count
    variable words
    variable since
    set ch [string tolower $chan]
    set total 0
    set people {}
    foreach k [array names count "$ch|*"] {
        incr total $count($k)
        lappend people [list [lindex [split $k "|"] 1] $count($k)]
    }
    set people [lsort -integer -index 1 -decreasing $people]
    set top {}
    foreach p [lrange $people 0 4] {
        lappend top "\0033[lindex $p 0]\017 (\00310[lindex $p 1]\017)"
    }
    set days "?"
    if {[info exists since($ch)]} {
        set days [expr {([clock seconds]-$since($ch))/86400}]
    }
    putserv "PRIVMSG $chan :\0030,2 \002STATS\002 \017 $chan — \00310$total\017 lines tracked over \00310${days}d\017. Top talkers: [join $top { }]"
}

# !seen <nick> — uses our own tracking (no external module needed).
proc stats::ago {epoch} {
    set s [expr {[clock seconds]-$epoch}]
    if {$s < 60}    { return "${s}s ago" }
    if {$s < 3600}  { return "[expr {$s/60}]m ago" }
    if {$s < 86400} { return "[expr {$s/3600}]h ago" }
    return "[expr {$s/86400}]d ago"
}
bind pub - "!seen" stats::pub_seen
proc stats::pub_seen {nick uhost hand chan text} {
    variable seen
    set who [string trim $text]
    if {$who eq ""} {
        putserv "PRIVMSG $chan :Usage: \002!seen <nick>\017"
        return
    }
    if {[onchan $who $chan]} {
        putserv "PRIVMSG $chan :\0033$who\017 is right here in $chan."
        return
    }
    set key [string tolower $who]
    if {[info exists seen($key)]} {
        lassign [split $seen($key) "\t"] when what
        putserv "PRIVMSG $chan :\0033$who\017 was last seen \00310[stats::ago $when]\017 — $what."
        return
    }
    putserv "PRIVMSG $chan :I haven't seen \0033$who\017 yet."
}

# Periodically flush stats to disk.
bind time - "*5 * * * *" stats::flush
proc stats::flush {min hour day month year} { stats::save }
bind evnt - prerehash stats::save
bind evnt - prerestart stats::save

putlog "stats.tcl loaded — !stats and !seen ready."
