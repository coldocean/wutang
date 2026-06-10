# WU-tang — Eggdrop bot for the Wunderbar IRC network

An [Eggdrop](https://www.eggheads.org/) 1.9.5 IRC bot that guards and runs the
**Wunderbar** network (`irc.wunderbar.lv`). It connects *outbound* to the IRC
server, so it needs no public port.

## Features
- **Keeps channels open & protects ops** (`#lobby`, `#help`, `#wunderbar`)
- **Greets** new joiners with colorful per-channel welcomes
- **!seen \<nick\>** — last-seen tracking (join/part/quit/nick/talk)
- **!stats** — channel line counts + top talkers
- **Anti-flood / anti-spam** — enforces the Wunderbar rules (repeat-line flood,
  advertising/other-network links, excessive caps) with a warning then
  kick+tempban. Ops/voiced/owners are exempt.
- **URL title fetcher** — announces the `<title>` of links posted in channel
- **Auto-identifies** the bot's nick to NickServ on connect
- **Owners:** `deemah` + `funt` (full partyline control)

## Deploy (Railway)
Built from the `Dockerfile` (compiles Eggdrop from source with TLS).

Set these **service variables** on Railway:

| Variable | Purpose | Example |
|---|---|---|
| `IRC_SERVER` | uplink host | `yamanote.proxy.rlwy.net` |
| `IRC_PORT` | uplink port | `52947` |
| `NICKSERV_PASS` | password to register/identify the bot's nick | *(secret)* |
| `OWNER_PASS` | optional partyline seed password | *(secret)* |

Add a **persistent volume** mounted at `/opt/eggdrop/data` so the userfile,
channel file, stats and seen data survive redeploys.

## First-run bootstrap
On the very first boot there is no userfile, so the bot starts with `-m`
(make-userfile). Claim ownership from IRC:

```
/msg WU-tang hello
```

The first person to do this becomes the bot owner. Then set a password:

```
/msg WU-tang pass <yourpassword>
```

Add the second owner (`funt`) from the partyline (`.dcc`/telnet or in-channel):

```
.+user funt
.chattr funt +no
```

After that, register the bot's own nick once so NickServ protects it:

```
/msg WU-tang msg NickServ REGISTER <NICKSERV_PASS> bot@wunderbar.lv
```

(or set `NICKSERV_PASS` and let it IDENTIFY automatically next boot).

## Channels
`#lobby`, `#help`, `#wunderbar`. Add more from the partyline with `.+chan #x`.

## Local layout
```
Dockerfile            compiles Eggdrop 1.9.5, builds runtime image
docker-entrypoint.sh  fills config from env, first-run bootstrap
config/eggdrop.conf   main bot config (secrets via env placeholders)
config/telnet-banner.txt
scripts/              custom TCL: wunderbar, greet, antispam, stats, urltitle
railway.json          Railway build/deploy config
```
