#!/usr/bin/env bash
# Entrypoint for the WU-tang Eggdrop bot on Railway.
#
# Fills runtime values into eggdrop.conf from environment variables and writes
# the NickServ password to a file the TCL reads (kept out of the image/repo).
#
# Expected env vars (set as Railway service variables):
#   IRC_SERVER          uplink host   (default: yamanote.proxy.rlwy.net)
#   IRC_PORT            uplink port   (default: 52947)
#   NICKSERV_PASS       password to IDENTIFY the bot's nick to NickServ
#   OWNER_PASS          partyline password seeded for deemah & funt (optional)
#   PORT                Railway-provided port for the DCC/telnet partyline
set -e

EGG=/opt/eggdrop
CONF="$EGG/eggdrop.conf"
DATA="$EGG/data"

mkdir -p "$DATA" "$EGG/logs"

# Railway mounts the persistent volume at $DATA owned by root. Eggdrop refuses
# to run as root, so fix ownership of the writable dirs then step down to the
# unprivileged 'eggdrop' user via gosu (re-exec).
if [ "$(id -u)" = "0" ]; then
    echo ">> Running as root — fixing perms and stepping down to 'eggdrop' user."
    chown -R eggdrop:eggdrop "$EGG" 2>/dev/null || true
    exec gosu eggdrop "$0" "$@"
fi
echo ">> Running as uid $(id -u) ($(id -un))."

IRC_SERVER="${IRC_SERVER:-yamanote.proxy.rlwy.net}"
IRC_PORT="${IRC_PORT:-52947}"
# Fixed DCC/telnet partyline port (matches the Railway TCP proxy target).
DCC_PORT="${DCC_PORT:-3333}"

echo ">> WU-tang starting: uplink ${IRC_SERVER}:${IRC_PORT}, DCC port ${DCC_PORT}"

# Resolve the public DCC proxy host to an IP for nat-ip (DCC handshakes need
# the dotted IP, not a hostname). Falls back to empty if unset/unresolvable.
NAT_IP=""
if [ -n "${DCC_HOST:-}" ]; then
    NAT_IP="$(getent hosts "$DCC_HOST" | awk '{print $1; exit}')"
    echo ">> DCC proxy ${DCC_HOST} -> nat-ip ${NAT_IP:-<unresolved>}"
fi

# Substitute the placeholders in the config.
sed -i \
    -e "s/__IRC_SERVER__/${IRC_SERVER}/g" \
    -e "s/__IRC_PORT__/${IRC_PORT}/g" \
    -e "s/__DCC_PORT__/${DCC_PORT}/g" \
    -e "s/__NAT_IP__/${NAT_IP}/g" \
    "$CONF"

# Write the NickServ password out for wunderbar.tcl (if provided).
if [ -n "${NICKSERV_PASS:-}" ]; then
    printf '%s' "$NICKSERV_PASS" > "$DATA/nickserv.pass"
    chmod 600 "$DATA/nickserv.pass"
    echo ">> NickServ password installed."
fi

cd "$EGG"

# First boot: there is no userfile yet. Create the bot with -m so it makes a
# fresh userfile; owners then claim ownership with `/msg WU-tang hello`.
# On later boots the userfile in the persisted volume is reused.
if [ ! -f "$DATA/WU-tang.user" ]; then
    echo ">> No userfile found — creating one (-m). Claim ownership in-channel:"
    echo "   /msg WU-tang hello   (first owner)  then  .help"
    exec "$EGG/eggdrop" -mn "$CONF"
else
    echo ">> Userfile present — normal start."
    exec "$EGG/eggdrop" -n "$CONF"
fi
