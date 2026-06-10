# console.tcl — bot administration over private message (/msg) and auto owner
# enrollment for deemah & funt.
#
#  * Owners (deemah/funt) identified to NickServ are auto-enrolled into the bot
#    userfile with +n (owner) the moment they're verified — no .hello needed.
#  * A "." command console works in /msg, e.g.:
#        /msg WU-tang .status
#        /msg WU-tang .adduser someone
#        /msg WU-tang .chattr someone +o
#        /msg WU-tang .die
#    Mirrors the most useful DCC partyline commands for people who can't open
#    a raw DCC chat.
#
# Relies on admin.tcl for the NickServ-account verification (admin::acct,
# admin::is_authed, admin::owners).

namespace eval console {}

# ---- auto-enroll a verified owner into the userfile ----------------------
proc console::enroll {nick} {
    set ln [string tolower $nick]
    if {![info exists ::admin::acct($ln)]} { return }
    set account $::admin::acct($ln)
    # only enroll recognized owners
    set isowner 0
    foreach o $::admin::owners {
        if {[string equal -nocase $account $o]} { set isowner 1; set handle $o }
    }
    if {!$isowner} { return }

    if {![validuser $handle]} {
        adduser $handle
        chattr $handle +nmfo
        putlog "console: enrolled owner $handle (+nmfo) from NickServ account."
    }
    # bind their current hostmask so DCC/partyline recognizes them too
    set host [getchanhost $nick]
    if {$host ne ""} {
        set mask "*!*@[lindex [split $host @] 1]"
        if {[lsearch -exact [getuser $handle HOSTS] $mask] < 0} {
            catch {setuser $handle HOSTS $mask}
        }
    }
}

# When admin.tcl verifies an account (330), enroll if it's an owner.
# We piggyback on a periodic check + the raw 330 handler by re-scanning.
bind raw - 330 console::after330
proc console::after330 {from key text} {
    set parts [split $text]
    if {[llength $parts] >= 2} {
        set target [lindex $parts 1]
        # give admin::raw330 a tick to store the account first
        after 200 [list console::enroll $target]
    }
    return 0
}

# ---- /msg "." command console --------------------------------------------
# Allowed commands -> implementation. Kept tight & safe.
bind msgm - "*" console::dispatch
proc console::dispatch {nick uhost hand text} {
    set text [string trim $text]
    if {[string index $text 0] ne "."} { return }

    # authorize: identified owner OR existing +n/+m userfile flag
    if {![console::authed $nick]} {
        # maybe not WHOIS'd yet — verify then retry once
        putquick "WHOIS $nick"
        after 2500 [list console::retry $nick $uhost $text]
        return
    }
    console::run $nick $text
}

proc console::retry {nick uhost text} {
    if {[console::authed $nick]} {
        console::run $nick $text
    } else {
        putserv "NOTICE $nick :\0034\002\[Wunderbar\]\017 Console is for identified owners (deemah/funt) only. /msg NickServ IDENTIFY <pass> first."
    }
}

proc console::authed {nick} {
    set ln [string tolower $nick]
    if {[info exists ::admin::acct($ln)]} {
        foreach o $::admin::owners {
            if {[string equal -nocase $::admin::acct($ln) $o]} { return 1 }
        }
    }
    set h [nick2hand $nick]
    if {$h ne "" && $h ne "*" && ([matchattr $h n] || [matchattr $h m])} { return 1 }
    return 0
}

proc console::reply {nick msg} { putserv "NOTICE $nick :$msg" }

proc console::run {nick text} {
    # ensure the caller is enrolled so userfile-based cmds work
    console::enroll $nick
    set argv  [split $text]
    set cmd   [string tolower [string range [lindex $argv 0] 1 end]]
    set args  [lrange $argv 1 end]
    switch -- $cmd {
        help - "" {
            foreach l {
                "\0030,4 \002 CONSOLE \002 \017 /msg WU-tang .<cmd>:"
                ".status  .uptime  .channels  .whois <nick>"
                ".adduser <nick>  .deluser <hand>  .chattr <hand> <+/-flags>  .users"
                ".op|.deop|.voice <#chan> <nick>   .kick|.ban <#chan> <nick> \[reason\]"
                ".say <#chan> <msg>   .act <#chan> <action>   .join <#chan>   .part <#chan>"
                ".rehash   .restart   .die"
            } { console::reply $nick $l }
        }
        status {
            console::reply $nick "\0033WU-tang\017 uptime [console::uptime] — channels: [channels] — server: $::server"
        }
        uptime { console::reply $nick "uptime [console::uptime]" }
        channels { console::reply $nick "channels: [channels]" }
        whois {
            set t [lindex $args 0]
            if {$t eq ""} { console::reply $nick "usage: .whois <nick>"; return }
            putquick "WHOIS $t"
            console::reply $nick "WHOIS $t sent (check your client)."
        }
        users {
            console::reply $nick "users: [join [userlist] { }]"
        }
        adduser {
            set t [lindex $args 0]
            if {$t eq ""} { console::reply $nick "usage: .adduser <nick-on-channel>"; return }
            if {[validuser $t]} { console::reply $nick "$t already exists."; return }
            adduser $t
            console::reply $nick "added user \002$t\017. Set flags with .chattr $t +o"
        }
        deluser {
            set t [lindex $args 0]
            if {$t eq "" || ![validuser $t]} { console::reply $nick "usage: .deluser <existing handle>"; return }
            deluser $t
            console::reply $nick "deleted user \002$t\017."
        }
        chattr {
            set t [lindex $args 0]; set fl [lindex $args 1]
            if {$t eq "" || $fl eq "" || ![validuser $t]} { console::reply $nick "usage: .chattr <handle> <+/-flags>"; return }
            chattr $t $fl
            console::reply $nick "$t flags now: \002[chattr $t]\017"
        }
        op - deop - voice - devoice {
            set ch [lindex $args 0]; set who [lindex $args 1]
            if {$ch eq "" || $who eq ""} { console::reply $nick "usage: .$cmd <#chan> <nick>"; return }
            if {![botisop $ch]} { putquick "PRIVMSG ChanServ :OP $ch $::botnick" }
            set m [dict get {op +o deop -o voice +v devoice -v} $cmd]
            putquick "MODE $ch $m $who"
            console::reply $nick "MODE $ch $m $who"
        }
        kick {
            set ch [lindex $args 0]; set who [lindex $args 1]
            if {$ch eq "" || $who eq ""} { console::reply $nick "usage: .kick <#chan> <nick> \[reason\]"; return }
            set r [join [lrange $args 2 end]]; if {$r eq ""} { set r "by $nick" }
            putquick "KICK $ch $who :$r"
        }
        ban {
            set ch [lindex $args 0]; set who [lindex $args 1]
            if {$ch eq "" || $who eq ""} { console::reply $nick "usage: .ban <#chan> <nick|mask> \[reason\]"; return }
            set r [join [lrange $args 2 end]]; if {$r eq ""} { set r "by $nick" }
            if {[string match "*!*@*" $who]} { set mask $who } \
            elseif {[onchan $who $ch]} { set mask "*!*@[lindex [split [getchanhost $who $ch] @] 1]" } \
            else { set mask "$who!*@*" }
            newchanban $ch $mask $nick $r 60
            if {[onchan $who $ch]} { putquick "KICK $ch $who :$r" }
            console::reply $nick "banned \002$mask\017 on $ch."
        }
        say {
            set ch [lindex $args 0]; set msg [join [lrange $args 1 end]]
            if {$ch eq "" || $msg eq ""} { console::reply $nick "usage: .say <#chan> <msg>"; return }
            putserv "PRIVMSG $ch :$msg"
        }
        act {
            set ch [lindex $args 0]; set msg [join [lrange $args 1 end]]
            if {$ch eq "" || $msg eq ""} { console::reply $nick "usage: .act <#chan> <action>"; return }
            putserv "PRIVMSG $ch :\001ACTION $msg\001"
        }
        join {
            set ch [lindex $args 0]
            if {$ch eq ""} { console::reply $nick "usage: .join <#chan>"; return }
            if {![validchan $ch]} { channel add $ch }
            putquick "JOIN $ch"
            console::reply $nick "joining $ch."
        }
        part {
            set ch [lindex $args 0]
            if {$ch eq ""} { console::reply $nick "usage: .part <#chan>"; return }
            putquick "PART $ch :by $nick"
            console::reply $nick "leaving $ch."
        }
        rehash  { console::reply $nick "rehashing…"; after 300 rehash }
        restart { console::reply $nick "restarting…"; after 300 restart }
        die     { console::reply $nick "shutting down."; after 500 [list die "requested by $nick"] }
        default { console::reply $nick "unknown command \002.$cmd\017 — try \002.help\017" }
    }
}

proc console::uptime {} {
    if {![info exists ::server-online]} { return "?" }
    set s [expr {[clock seconds] - ${::server-online}}]
    set d [expr {$s/86400}]; set h [expr {($s%86400)/3600}]; set m [expr {($s%3600)/60}]
    return "${d}d ${h}h ${m}m"
}

putlog "console.tcl loaded — /msg . console + auto owner enrollment ready."
