# help.tcl — public !help / !commands menu so channel users can discover
# what WU-tang offers. Sent as notices to keep channels tidy.

namespace eval help {
    variable lines {
        "\0030,4 \002 WU-tang \002 \017 — your Wunderbar guardian bot \0033\002bzzt\017"
        "\00310\002!help\017 / \00310\002!commands\017  — this menu"
        "\00310\002!seen <nick>\017      — when someone was last active"
        "\00310\002!stats\017            — channel line counts & top talkers"
        "\00310\002!admin\017            — owner commands (op/kick/ban/topic/say…)"
        "\0033Automatic:\017 greets joiners, posts \002link titles\017, keeps ops, anti-flood/anti-spam."
        "\0033Support:\017 ask in \00310#help\017 — join IRC server for support and questions: \002irc.wunderbar.lv port:52947\017"
    }
}

proc help::show {nick uhost hand chan text} {
    variable lines
    foreach l $lines {
        putserv "NOTICE $nick :$l"
    }
    putserv "PRIVMSG $chan :\0033$nick\017 — sent you the command list via notice. \00310\002bee excellent\017 \0033to each other!"
}

bind pub - "!help"     help::show
bind pub - "!commands" help::show
bind pub - "!menu"     help::show

# Also answer in private (/msg WU-tang help).
proc help::show_priv {nick uhost hand text} {
    variable lines
    foreach l $lines { putserv "NOTICE $nick :$l" }
}
bind msg - "help"     help::show_priv
bind msg - "commands" help::show_priv

putlog "help.tcl loaded — !help / !commands ready."
