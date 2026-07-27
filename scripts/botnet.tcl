# botnet.tcl — Wunderbar eggdrop botnet linking.
#
# Star topology:  boss is the HUB, every other eggdrop is a LEAF that links
# (and auto-relinks) to boss.  Linking gives the bots a shared partyline
# (.bots / .vbots / .chat), lets owners jump between them with .relay, and lets
# them coordinate — WITHOUT sharing userfiles (each bot keeps its own users).
#
# Reference: https://docs.eggheads.org/using/botnet.html  (Adding and linking
# bots).  On the hub you add each leaf as a +b bot record; on each leaf you add
# the hub as a +bh bot record (h = auto-link/relink) with its address + a shared
# link password.  Both sides store the SAME password for the pair, exactly like
# the random password the doc's `.link` would negotiate — we just pre-seed it.
#
# Everything is driven by env vars (with safe defaults) so the same file ships
# to all five repos unchanged:
#
#   BOTNET_HUB        hub bot's botnet-nick            (default: boss)
#   BOTNET_HUB_HOST   hub's public link host           (default: sakura.proxy.rlwy.net)
#   BOTNET_HUB_PORT   hub's public link port           (default: 40889)
#   BOTNET_PASS       shared link password             (default: WunderNet2026)
#   BOTNET_LEAVES     leaf botnet-nicks the hub expects (space/comma separated)
#                     (default: WUNDERkind WU-tang HellGatesElf demonEgg)
#
# The hub opens `listen <BOTNET_LISTEN> bots` in eggdrop.conf (Railway TCP proxy
# sakura.proxy.rlwy.net:40889 -> that port). Leaves need no listen port.

namespace eval wbnet {
    variable HUB
    variable HOST
    variable PORT
    variable PASS
    variable LEAVES

    proc env_or {name def} {
        if {[info exists ::env($name)]} {
            set v [string trim $::env($name)]
            if {$v ne ""} { return $v }
        }
        return $def
    }
}

set wbnet::HUB  [wbnet::env_or BOTNET_HUB      "boss"]
set wbnet::HOST [wbnet::env_or BOTNET_HUB_HOST "sakura.proxy.rlwy.net"]
set wbnet::PORT [wbnet::env_or BOTNET_HUB_PORT "40889"]
set wbnet::PASS [wbnet::env_or BOTNET_PASS     "WunderNet2026"]

set wbnet::LEAVES {}
foreach _m [split [string map {, " "} \
        [wbnet::env_or BOTNET_LEAVES "WUNDERkind WU-tang HellGatesElf demonEgg"]]] {
    set _m [string trim $_m]
    if {$_m ne ""} { lappend wbnet::LEAVES $_m }
}
unset -nocomplain _m

# Our own botnet handle (the var name contains a dash, so read it with braces).
proc wbnet::me {} { return [set ::botnet-nick] }

# ------------------------------------------------------------------ HUB (boss)
# Pre-seed a bot record for every leaf so boss accepts their inbound links.
proc wbnet::setup_hub {} {
    variable LEAVES
    variable HUB
    variable PASS
    foreach leaf $LEAVES {
        if {[string equal -nocase $leaf $HUB]} { continue }
        if {![validuser $leaf]} { adduser $leaf }
        chattr $leaf +b               ;# it's a bot
        chattr $leaf -h               ;# leaves must NOT be our hub
        setuser $leaf HOSTS *!*@*     ;# accept from any source (password gates it)
        setuser $leaf PASS $PASS           ;# shared link password (matches leaf side)
    }
    putlog "botnet: HUB ready — awaiting leaves \[$LEAVES\] on the bot listen port."
}

# ----------------------------------------------------------------- LEAF (rest)
# Add boss as a +bh hub bot and auto-link to it, retrying until connected.
proc wbnet::setup_leaf {} {
    variable HUB
    variable HOST
    variable PORT
    variable PASS
    if {![validuser $HUB]} { adduser $HUB }
    chattr  $HUB +bh              ;# bot + hub (auto-link / auto-relink)
    setuser $HUB HOSTS *!*@*
    setuser $HUB BOTADDR $HOST $PORT $PORT
    setuser $HUB PASS $PASS
    putlog "botnet: LEAF ready — hub $HUB @ $HOST:$PORT (+h auto-link)."
    utimer 15 [list wbnet::try_link]
}

proc wbnet::try_link {} {
    variable HUB
    if {[catch {islinked $HUB} linked]} { set linked 0 }
    if {!$linked} {
        putlog "botnet: linking to hub $HUB ..."
        catch { link $HUB }
    }
    # keep trying every 2 minutes until we're linked in
    if {[catch {islinked $HUB} linked]} { set linked 0 }
    if {!$linked} { utimer 120 [list wbnet::try_link] }
}

proc wbnet::setup {} {
    variable HUB
    if {[string equal -nocase [wbnet::me] $HUB]} {
        wbnet::setup_hub
    } else {
        wbnet::setup_leaf
    }
}

# Run once the userfile is loaded and the event loop is up. A short startup
# timer is the most reliable trigger across eggdrop 1.9.x (userfile is loaded
# by the time it fires). Re-runs are idempotent (validuser guards).
utimer 8 [list wbnet::setup]

# Re-assert the link on every (re)connect to the IRC server as a safety net.
bind evnt - init-server wbnet::on_evnt
proc wbnet::on_evnt {type} {
    variable HUB
    if {![string equal -nocase [wbnet::me] $HUB]} {
        utimer 10 [list wbnet::try_link]
    }
}

putlog "botnet.tcl loaded — [wbnet::me] role: [expr {[string equal -nocase [wbnet::me] $wbnet::HUB] ? {HUB} : {LEAF}}]."
