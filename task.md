# WU-tang Eggdrop bot — task notes

## Goal
Eggdrop bot for Wunderbar IRC. Repo coldocean/wutang, deploy on Railway (same
project pacific-expression, NEW service). Connects OUTBOUND to
yamanote.proxy.rlwy.net:52947 (irc.wunderbar.lv), NETWORK Wunderbar.

## Config decisions
- Bot nick: WU-tang (alt WUNDERk1nd)
- Channels: #lobby #help #wunderbar
- Owners: deemah + funt
- Features: keep-open+protect ops, greet, !seen, anti-spam(kick/ban), !stats, urltitle
- Eggdrop 1.9.5 compiled from source (apt only has 1.8.4). TLS via libssl.
- No "seen" module (doesn't exist) — !seen implemented in stats.tcl.
- Custom TCL copied to scripts/wunderbar/ to avoid clobbering stock scripts.

## Env vars needed on Railway
IRC_SERVER=yamanote.proxy.rlwy.net  IRC_PORT=52947
NICKSERV_PASS=<secret>  OWNER_PASS=<optional>
PORT auto -> DCC/telnet partyline port.
VOLUME mounted at /opt/eggdrop/data (userfile/chanfile/stats/seen persist).

## Railway project
project 01bed72f-1609-45c4-a41a-13c4c09337de (pacific-expression)
env 07e761e9-7d96-4058-9ed3-24b65a7920c0 (production)
token 43f7a723-96d0-4994-99ee-88d86354ba6f (Team)
existing ircserver service fdf29f4d-4507-4459-8cfb-a8e32f94f59d

## Status
- [x] Dockerfile, conf, entrypoint, 5 TCL scripts, README, railway.json
- [x] TCL parse-checked OK
- [ ] create GitHub repo coldocean/wutang + push
- [ ] create Railway service from repo
- [ ] set env vars + volume
- [ ] deploy + verify bot joins channels

## Bootstrap (after deploy)
/msg WU-tang hello  -> first owner (deemah)
/msg WU-tang pass <pw>
.+user funt ; .chattr funt +no   (add funt)
