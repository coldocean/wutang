# radiopromo.tcl — the bot periodically drops a curated underground radio
# station + the Hell Gates Radio link in every channel it sits in.
#
# Enabled only when env RADIO_PROMO=1 (so WUNDERkind/WU-tang can keep it off
# while the dedicated promo bots HellGatesElf / demonEgg run it).
#
# Interval (minutes) from env RADIO_PROMO_MIN (default 15).
# Site: https://demon.digitalslayer.com  (Hell Gates Radio / CyberPlayer)

namespace eval radio {
    variable enabled 0
    if {[info exists ::env(RADIO_PROMO)] && $::env(RADIO_PROMO) eq "1"} { set enabled 1 }
    variable interval 15
    if {[info exists ::env(RADIO_PROMO_MIN)]} {
        set v [string trim $::env(RADIO_PROMO_MIN)]
        if {[string is integer -strict $v] && $v > 0} { set interval $v }
    }
    variable site "https://demon.digitalslayer.com"
    variable idx 0

    # curated underground stations grouped by genre, each as
    # {GENRE  STATION  BLURB}
    variable stations {
        {"Liquid DnB"        "Bassdrive"            "24/7 worldwide drum'n'bass — deep liquid rollers."}
        {"Liquid DnB"        "DataBeats DnB"        "liquid funk & soulful dnb selections."}
        {"Liquid DnB"        "Record Liquid Funk"   "smooth liquid funk all day long."}
        {"Nu-disco / House"  "54house.fm"           "nu-disco, italo & tech house grooves."}
        {"Nu-disco / House"  "Soho Radio London"    "underground house, 320k London selections."}
        {"Worldwide"         "Worldwide FM"         "Gilles Peterson's global jazz/soul/broken-beat."}
        {"Trip-hop / Downtempo" "Noods Radio Bristol" "rare & deep cuts, leftfield Bristol sounds."}
        {"Tech / Deep House" "TM Radio"             "tribal, progressive & deep house mixes."}
        {"Pirate / Underground" "NTS Radio 1 & 2"   "London's cult underground, eclectic as hell."}
        {"Pirate / Underground" "Rinse UK"          "East-London pirate — bass, garage, dnb."}
        {"Pirate / Underground" "Refuge Worldwide"  "Berlin community radio, deep & weird."}
        {"Electro / Disco"   "Intergalactic FM"     "The Hague's cult electro & cosmic disco."}
    }
}

# IRC color helper — wrap text in a mIRC color code
proc radio::c {code text} { return "\003${code}\002${text}\017" }

proc radio::announce {} {
    variable enabled
    variable stations
    variable site
    variable idx
    if {!$enabled} { return }
    set n [llength $stations]
    if {$n == 0} { return }
    set entry [lindex $stations [expr {$idx % $n}]]
    incr idx
    lassign $entry genre station blurb

    set tag   [radio::c "0,4" " HELL GATES RADIO "]
    set g     [radio::c "08" "\[$genre\]"]
    set s     [radio::c "11" $station]
    set b     [radio::c "03" $blurb]
    set link  "\00312\037${site}\017"
    set line  "$tag $g $s — $b  ▶ tune in: $link"

    foreach chan [channels] {
        if {[onchan $::botnick $chan]} {
            putserv "PRIVMSG $chan :$line"
        }
    }
}

# kick off the recurring timer once, after connect settles
proc radio::schedule {} {
    variable enabled
    variable interval
    if {!$enabled} {
        putlog "radiopromo.tcl loaded — DISABLED (set RADIO_PROMO=1 to enable)."
        return
    }
    # eggdrop 'timer' is in minutes; reschedule itself each fire
    timer $interval [list radio::tick]
    putlog "radiopromo.tcl loaded — every $interval min -> demon.digitalslayer.com"
}

proc radio::tick {} {
    variable interval
    radio::announce
    timer $interval [list radio::tick]
}

radio::schedule
