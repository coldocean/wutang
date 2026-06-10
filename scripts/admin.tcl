# admin.tcl — channel administration via simple "!" commands.
#
# Authorized users:
#   * the bot owners deemah & funt, auto-trusted once they are IDENTIFIED to
#     NickServ (no .hello bootstrap or userfile entry required), and
#   * anyone holding the +o (or +n/+m) flag in the bot's userfile.
#
# Trust model: we ask services (WHOIS / account-notify) whether the caller is
# logged in to a recognized NickServ account. We cache the verified account so
# repeated commands are instant, and re-verify on nick changes / quits.

namespace eval admin {
    # NickServ accounts that are always treated as bot owners.
    variable owners {deemah funt}

    # nick(lowercase) -> verified NickServ account name
    variable acct
    array set acct {}

    # pending command queue keyed by lowercase nick, run after WHOIS confirms
    variable pending
    array set pending {}
}

# ---------------------------------------------------------------------------
# Authorization helpers
# ---------------------------------------------------------------------------

# Is this nick an authorized admin *right now* (using cached account info)?
proc admin::is_authed {nick chan} {
    variable owners
    variable acct
    set ln [string tolower $nick]

    # 1) bot userfile flags (+n owner / +m master / +o op)
    set hand [nick2hand $nick $chan]
    if {$hand ne "" && $hand ne "*"} {
        if {[matchattr $hand n] || [matchattr $hand m] || [matchattr $hand o] || [matchattr $hand f]} {
            return 1
        }
    }

    # 2) verified NickServ account is in the owners list
    if {[info exists acct($ln)]} {
        set a [string tolower $acct($ln)]
        foreach o $owners { if {$a eq [string tolower $o]} { return 1 } }
    }
    return 0
}

# Run a verified action, or trigger a WHOIS first and queue it.
proc admin::guard {nick chan cmd} {
    if {[admin::is_authed $nick $chan]} {
        uplevel #0 $cmd
        return
    }
    # Not yet known — ask services who they are, then re-check.
    variable pending
    set ln [string tolower $nick]
    lappend pending($ln) [list $chan $cmd]
    putquick "WHOIS $nick"
    # give services ~3s, then either run or refuse
    utimer 3 [list admin::resolve $nick]
}

proc admin::resolve {nick} {
    variable pending
    set ln [string tolower $nick]
    if {![info exists pending($ln)]} { return }
    set jobs $pending($ln)
    unset pending($ln)
    foreach job $jobs {
        lassign $job chan cmd
        if {[admin::is_authed $nick $chan]} {
            uplevel #0 $cmd
        } else {
            putserv "NOTICE $nick :\0034\002\[Wunderbar\]\017 You must be an identified owner (deemah/funt) or hold a bot +o flag to use that."
        }
    }
}

# Capture the logged-in account from WHOIS numeric 330:
#   :server 330 mynick TARGET ACCOUNT :is logged in as
bind raw - 330 admin::raw330
proc admin::raw330 {from key text} {
    set parts [split $text]
    # text = "mynick TARGET ACCOUNT :is logged in as"
    if {[llength $parts] >= 3} {
        set target [lindex $parts 1]
        set account [lindex $parts 2]
        variable acct
        set acct([string tolower $target]) $account
    }
    return 0
}

# Account changes via IRCv3 account-notify (if the server sends it).
bind raw - ACCOUNT admin::rawaccount
proc admin::rawaccount {from key text} {
    # :nick!user@host ACCOUNT accountname
    set nick [lindex [split $from "!"] 0]
    set account [string trimleft $text ":"]
    variable acct
    if {$account eq "*"} {
        catch {unset acct([string tolower $nick])}
    } else {
        set acct([string tolower $nick]) $account
    }
    return 0
}

# Forget cached accounts when people leave / change nick.
bind nick - * admin::on_nick
proc admin::on_nick {nick uhost hand chan newnick} {
    variable acct
    catch {unset acct([string tolower $nick])}
}
bind sign - * admin::on_sign
proc admin::on_sign {nick uhost hand chan {reason ""}} {
    variable acct
    catch {unset acct([string tolower $nick])}
}

# ---------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------
proc admin::need_op {chan} {
    if {![botisop $chan]} {
        putquick "PRIVMSG ChanServ :OP $chan $::botnick"
        return 0
    }
    return 1
}

# default target = the command's own channel
proc admin::tgt {arg chan} {
    set arg [string trim $arg]
    if {$arg ne "" && [string index $arg 0] eq "#"} { return $arg }
    return $chan
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

# !op [nick ...]   — op the callers / named nicks
bind pub - "!op" admin::c_op
proc admin::c_op {nick uhost hand chan text} {
    admin::guard $nick $chan [list admin::do_op $nick $chan $text]
}
proc admin::do_op {nick chan text} {
    if {![admin::need_op $chan]} { return }
    set who [string trim $text]
    if {$who eq ""} { set who $nick }
    foreach n [split $who] { if {$n ne ""} { putquick "MODE $chan +o $n" } }
}

bind pub - "!deop" admin::c_deop
proc admin::c_deop {nick uhost hand chan text} {
    admin::guard $nick $chan [list admin::do_deop $nick $chan $text]
}
proc admin::do_deop {nick chan text} {
    if {![admin::need_op $chan]} { return }
    set who [string trim $text]
    if {$who eq ""} { set who $nick }
    foreach n [split $who] { if {$n ne ""} { putquick "MODE $chan -o $n" } }
}

bind pub - "!voice" admin::c_voice
proc admin::c_voice {nick uhost hand chan text} {
    admin::guard $nick $chan [list admin::do_voice $nick $chan $text +v]
}
bind pub - "!devoice" admin::c_devoice
proc admin::c_devoice {nick uhost hand chan text} {
    admin::guard $nick $chan [list admin::do_voice $nick $chan $text -v]
}
proc admin::do_voice {nick chan text mode} {
    if {![admin::need_op $chan]} { return }
    set who [string trim $text]
    if {$who eq ""} { set who $nick }
    foreach n [split $who] { if {$n ne ""} { putquick "MODE $chan $mode $n" } }
}

# !kick <nick> [reason]
bind pub - "!kick" admin::c_kick
proc admin::c_kick {nick uhost hand chan text} {
    admin::guard $nick $chan [list admin::do_kick $nick $chan $text]
}
proc admin::do_kick {nick chan text} {
    if {![admin::need_op $chan]} { return }
    set who [lindex [split $text] 0]
    if {$who eq ""} { putserv "NOTICE $nick :Usage: !kick <nick> \[reason\]"; return }
    set reason [string trim [join [lrange [split $text] 1 end]]]
    if {$reason eq ""} { set reason "requested by $nick" }
    putquick "KICK $chan $who :$reason"
}

# !ban <nick|mask> [reason]   (kick + channel ban, 1h)
bind pub - "!ban" admin::c_ban
proc admin::c_ban {nick uhost hand chan text} {
    admin::guard $nick $chan [list admin::do_ban $nick $chan $text]
}
proc admin::do_ban {nick chan text} {
    if {![admin::need_op $chan]} { return }
    set who [lindex [split $text] 0]
    if {$who eq ""} { putserv "NOTICE $nick :Usage: !ban <nick|mask> \[reason\]"; return }
    set reason [string trim [join [lrange [split $text] 1 end]]]
    if {$reason eq ""} { set reason "banned by $nick" }
    if {[string match "*!*@*" $who]} {
        set mask $who
    } elseif {[onchan $who $chan]} {
        set mask "*!*@[lindex [split [getchanhost $who $chan] @] 1]"
    } else {
        set mask "$who!*@*"
    }
    newchanban $chan $mask $nick $reason 60
    if {[onchan $who $chan]} { putquick "KICK $chan $who :$reason" }
    putserv "NOTICE $nick :Banned \002$mask\017 on $chan (1h)."
}

# !unban <mask>
bind pub - "!unban" admin::c_unban
proc admin::c_unban {nick uhost hand chan text} {
    admin::guard $nick $chan [list admin::do_unban $nick $chan $text]
}
proc admin::do_unban {nick chan text} {
    if {![admin::need_op $chan]} { return }
    set mask [string trim $text]
    if {$mask eq ""} { putserv "NOTICE $nick :Usage: !unban <mask>"; return }
    catch {killchanban $chan $mask}
    putquick "MODE $chan -b $mask"
    putserv "NOTICE $nick :Unbanned \002$mask\017 on $chan."
}

# !mute <nick>  /  !unmute <nick>   (uses +q quiet ban *!*@host)
bind pub - "!mute" admin::c_mute
proc admin::c_mute {nick uhost hand chan text} {
    admin::guard $nick $chan [list admin::do_mute $nick $chan $text q]
}
bind pub - "!unmute" admin::c_unmute
proc admin::c_unmute {nick uhost hand chan text} {
    admin::guard $nick $chan [list admin::do_mute $nick $chan $text -q]
}
proc admin::do_mute {nick chan text mode} {
    if {![admin::need_op $chan]} { return }
    set who [string trim [lindex [split $text] 0]]
    if {$who eq ""} { putserv "NOTICE $nick :Usage: !mute|!unmute <nick|mask>"; return }
    if {[string match "*!*@*" $who]} {
        set mask $who
    } elseif {[onchan $who $chan]} {
        set mask "*!*@[lindex [split [getchanhost $who $chan] @] 1]"
    } else {
        set mask "$who!*@*"
    }
    if {$mode eq "q"} {
        putquick "MODE $chan +q $mask"
        putserv "NOTICE $nick :Muted \002$mask\017 on $chan."
    } else {
        putquick "MODE $chan -q $mask"
        putserv "NOTICE $nick :Unmuted \002$mask\017 on $chan."
    }
}

# !topic <text>
bind pub - "!topic" admin::c_topic
proc admin::c_topic {nick uhost hand chan text} {
    admin::guard $nick $chan [list admin::do_topic $nick $chan $text]
}
proc admin::do_topic {nick chan text} {
    if {![admin::need_op $chan]} { return }
    set t [string trim $text]
    if {$t eq ""} { putserv "NOTICE $nick :Usage: !topic <new topic>"; return }
    putquick "TOPIC $chan :$t"
}

# !invite <nick> [#chan]
bind pub - "!invite" admin::c_invite
proc admin::c_invite {nick uhost hand chan text} {
    admin::guard $nick $chan [list admin::do_invite $nick $chan $text]
}
proc admin::do_invite {nick chan text} {
    set who [lindex [split $text] 0]
    if {$who eq ""} { putserv "NOTICE $nick :Usage: !invite <nick> \[#chan\]"; return }
    set ch [admin::tgt [lindex [split $text] 1] $chan]
    putquick "INVITE $who $ch"
    putserv "NOTICE $nick :Invited \002$who\017 to $ch."
}

# !say [#chan] <message>   — make the bot speak
bind pub - "!say" admin::c_say
proc admin::c_say {nick uhost hand chan text} {
    admin::guard $nick $chan [list admin::do_say $nick $chan $text]
}
proc admin::do_say {nick chan text} {
    set text [string trim $text]
    if {$text eq ""} { putserv "NOTICE $nick :Usage: !say \[#chan\] <message>"; return }
    set first [lindex [split $text] 0]
    if {[string index $first 0] eq "#"} {
        set ch $first
        set msg [string trim [join [lrange [split $text] 1 end]]]
    } else {
        set ch $chan
        set msg $text
    }
    if {$msg eq ""} { return }
    putserv "PRIVMSG $ch :$msg"
}

# !join <#chan>   /  !part [#chan]
bind pub - "!join" admin::c_join
proc admin::c_join {nick uhost hand chan text} {
    admin::guard $nick $chan [list admin::do_join $nick $chan $text]
}
proc admin::do_join {nick chan text} {
    set ch [string trim [lindex [split $text] 0]]
    if {$ch eq "" || [string index $ch 0] ne "#"} { putserv "NOTICE $nick :Usage: !join <#chan>"; return }
    if {![validchan $ch]} { channel add $ch }
    putquick "JOIN $ch"
    putserv "NOTICE $nick :Joining \002$ch\017."
}
bind pub - "!part" admin::c_part
proc admin::c_part {nick uhost hand chan text} {
    admin::guard $nick $chan [list admin::do_part $nick $chan $text]
}
proc admin::do_part {nick chan text} {
    set ch [admin::tgt $text $chan]
    putquick "PART $ch :requested by $nick"
    putserv "NOTICE $nick :Leaving \002$ch\017."
}

# !admin / !adminhelp — list the admin commands (only answers authed users)
bind pub - "!admin" admin::c_help
proc admin::c_help {nick uhost hand chan text} {
    admin::guard $nick $chan [list admin::do_help $nick]
}
proc admin::do_help {nick} {
    foreach l {
        "\0030,4 \002 ADMIN \002 \017 owner commands (deemah / funt / bot ops):"
        "\00310!op\017 \00310!deop\017 \00310!voice\017 \00310!devoice\017 \[nick...\]"
        "\00310!kick\017 <nick> \[reason\]   \00310!ban\017/\00310!unban\017 <nick|mask>"
        "\00310!mute\017/\00310!unmute\017 <nick>   \00310!topic\017 <text>   \00310!invite\017 <nick> \[#chan\]"
        "\00310!say\017 \[#chan\] <msg>   \00310!join\017 <#chan>   \00310!part\017 \[#chan\]"
    } {
        putserv "NOTICE $nick :$l"
    }
}

putlog "admin.tcl loaded — ! admin commands ready (owners: deemah, funt)."
