#!/usr/bin/env bash
set -euo pipefail

RELAY_URL=${RELAY_URL:-"ws://localhost:8080"}
DATA_DIR=${DATA_DIR:-"data"}

cleanup() {
  if [[ -n "${DAEMON_PID:-}" ]]; then
    kill "$DAEMON_PID" 2>/dev/null || true
  fi
  if [[ -n "${RELAY_PID:-}" ]]; then
    kill "$RELAY_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ -z "${RELAY_URL}" ]]; then
  echo "Missing RELAY_URL"
  exit 1
fi

if [[ -d "$HOME/dev/nostr-rs-relay" ]]; then
  (cd "$HOME/dev/nostr-rs-relay" && ./target/release/nostr-rs-relay -c config.toml &) 
  RELAY_PID=$!
  sleep 2
fi

GAME_ID=$(./bin/ec4x new --name "E2E Test" | awk -F: '/Game ID/ { gsub(/ /, "", $2); print $2 }')
if [[ -z "$GAME_ID" ]]; then
  echo "Failed to create game"
  exit 1
fi

DB_PATH="$DATA_DIR/games/$GAME_ID/ec4x.db"
if [[ ! -f "$DB_PATH" ]]; then
  echo "Missing DB: $DB_PATH"
  exit 1
fi

./bin/ec4x-daemon start &
DAEMON_PID=$!
sleep 3

DAEMON_PUBKEY_HEX=$(python - <<'PY'
from pathlib import Path
import re
CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
CHARSET_MAP = {c: i for i, c in enumerate(CHARSET)}

def bech32_polymod(values):
    generator = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
    chk = 1
    for v in values:
        b = (chk >> 25)
        chk = ((chk & 0x1ffffff) << 5) ^ v
        for i in range(5):
            chk ^= generator[i] if ((b >> i) & 1) else 0
    return chk

def bech32_hrp_expand(hrp):
    return [ord(x) >> 5 for x in hrp] + [0] + [ord(x) & 31 for x in hrp]

def bech32_verify_checksum(hrp, data):
    return bech32_polymod(bech32_hrp_expand(hrp) + data) == 1

def bech32_decode(bech):
    if any(ord(x) < 33 or ord(x) > 126 for x in bech):
        return None, None
    bech = bech.lower()
    pos = bech.rfind('1')
    if pos < 1 or pos + 7 > len(bech):
        return None, None
    hrp = bech[:pos]
    data = []
    for c in bech[pos+1:]:
        if c not in CHARSET_MAP:
            return None, None
        data.append(CHARSET_MAP[c])
    if not bech32_verify_checksum(hrp, data):
        return None, None
    return hrp, data[:-6]

def convertbits(data, frombits, tobits, pad=True):
    acc = 0
    bits = 0
    ret = []
    maxv = (1 << tobits) - 1
    for value in data:
        if value < 0 or (value >> frombits):
            return None
        acc = (acc << frombits) | value
        bits += frombits
        while bits >= tobits:
            bits -= tobits
            ret.append((acc >> bits) & maxv)
    if pad:
        if bits:
            ret.append((acc << (tobits - bits)) & maxv)
    elif bits >= frombits or ((acc << (tobits - bits)) & maxv):
        return None
    return ret

path = Path.home() / '.local' / 'share' / 'ec4x' / 'daemon_identity.kdl'
text = path.read_text()
match = re.search(r'npub="(npub[0-9a-z]+)"', text)
if not match:
    raise SystemExit(1)
npub = match.group(1)
hrp, data = bech32_decode(npub)
if hrp != 'npub' or data is None:
    raise SystemExit(1)
raw = bytes(convertbits(data, 5, 8, False))
print(raw.hex())
PY
)

if [[ -z "$DAEMON_PUBKEY_HEX" ]]; then
  echo "FAILED: unable to decode daemon npub"
  exit 1
fi

sqlite3 "$DB_PATH" << EOF
UPDATE houses SET nostr_pubkey = '$DAEMON_PUBKEY_HEX';
EOF

./bin/ec4x-daemon resolve --gameId "$GAME_ID"

WEBSOCAT_BIN=${WEBSOCAT_BIN:-"$HOME/.cargo/bin/websocat"}
CHECK="[\"REQ\",\"test\",{\"kinds\":[30403,30405],\"#d\":[\"$GAME_ID\"]}]"
if ! command -v "$WEBSOCAT_BIN" >/dev/null 2>&1; then
  echo "FAILED: websocat not found at $WEBSOCAT_BIN"
  exit 1
fi

if echo "$CHECK" | timeout 5 "$WEBSOCAT_BIN" "$RELAY_URL" | grep -q "EVENT"; then
  echo "SUCCESS: Event published"
else
  echo "FAILED: No event found"
  exit 1
fi

exit 0
