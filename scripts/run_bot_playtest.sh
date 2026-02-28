#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE=${1:-"$ROOT_DIR/scripts/bot/session.env"}

cleanup() {
  if [[ -n "${BOT_DAEMON_PID:-}" ]]; then
    kill "$BOT_DAEMON_PID" 2>/dev/null || true
  fi
  if [[ -n "${BOT_RELAY_PID:-}" ]]; then
    kill "$BOT_RELAY_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE"
  echo "Copy scripts/bot/session.env.example to scripts/bot/session.env"
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

: "${BOT_RELAYS:?BOT_RELAYS is required}"
: "${BOT_GAME_ID:?BOT_GAME_ID is required}"
: "${BOT_DAEMON_PUBHEX:?BOT_DAEMON_PUBHEX is required}"
: "${BOT_PLAYER_PRIV_HEX:?BOT_PLAYER_PRIV_HEX is required}"
: "${BOT_PLAYER_PUB_HEX:?BOT_PLAYER_PUB_HEX is required}"
: "${BOT_MODEL:?BOT_MODEL is required}"
: "${BOT_API_KEY:?BOT_API_KEY is required}"

BOT_START_RELAY=${BOT_START_RELAY:-0}
BOT_START_DAEMON=${BOT_START_DAEMON:-0}
BOT_RELAY_BIN=${BOT_RELAY_BIN:-}
BOT_RELAY_CONFIG=${BOT_RELAY_CONFIG:-}
BOT_DAEMON_BIN=${BOT_DAEMON_BIN:-"$ROOT_DIR/bin/ec4x-daemon"}

if [[ "$BOT_START_RELAY" == "1" ]]; then
  if [[ -z "$BOT_RELAY_BIN" ]]; then
    echo "BOT_RELAY_BIN is required when BOT_START_RELAY=1"
    exit 1
  fi
  if [[ ! -x "$BOT_RELAY_BIN" ]]; then
    echo "Relay binary is not executable: $BOT_RELAY_BIN"
    exit 1
  fi
  echo "[bot] starting relay"
  if [[ -n "$BOT_RELAY_CONFIG" ]]; then
    "$BOT_RELAY_BIN" -c "$BOT_RELAY_CONFIG" &
  else
    "$BOT_RELAY_BIN" &
  fi
  BOT_RELAY_PID=$!
  sleep 2
fi

if [[ "$BOT_START_DAEMON" == "1" ]]; then
  if [[ ! -x "$BOT_DAEMON_BIN" ]]; then
    echo "Daemon binary is not executable: $BOT_DAEMON_BIN"
    exit 1
  fi
  echo "[bot] starting daemon"
  "$BOT_DAEMON_BIN" start &
  BOT_DAEMON_PID=$!
  sleep 2
fi

export BOT_LOG_DIR=${BOT_LOG_DIR:-"$ROOT_DIR/logs/bot"}
mkdir -p "$BOT_LOG_DIR"

echo "[bot] building bot entrypoint"
nim c "$ROOT_DIR/src/bot/main.nim"

echo "[bot] starting bot for game: $BOT_GAME_ID"
"$ROOT_DIR/src/bot/main"
