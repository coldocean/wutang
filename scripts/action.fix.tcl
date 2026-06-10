# action.fix.tcl — minimal helper providing a friendly "putact" command so
# the bot can emote (/me). Some distros ship this in eggdrop; we include a
# tiny version so the source line in eggdrop.conf never fails.

if {[info commands putact] eq ""} {
    proc putact {dest text} {
        putserv "PRIVMSG $dest :\001ACTION $text\001"
    }
}
putlog "action.fix.tcl loaded."
