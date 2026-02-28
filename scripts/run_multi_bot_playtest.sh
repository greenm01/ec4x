#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE=${1:-"$ROOT_DIR/scripts/bot/multi_session.env"}

cleanup() {
  for pid in "${BOT_PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE"
  echo "Copy scripts/bot/multi_session.env.example to scripts/bot/multi_session.env"
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

: "${BOT_RELAYS:?BOT_RELAYS is required}"
: "${BOT_GAME_ID:?BOT_GAME_ID is required}"
: "${BOT_DAEMON_PUBHEX:?BOT_DAEMON_PUBHEX is required}"
: "${BOT_API_KEY:?BOT_API_KEY is required}"
: "${BOT_COUNT:?BOT_COUNT is required}"

BOT_LOG_ROOT=${BOT_LOG_ROOT:-"$ROOT_DIR/logs/bot/multi"}
BOT_BASE_URL=${BOT_BASE_URL:-"https://api.openai.com/v1"}
BOT_MODEL_DEFAULT=${BOT_MODEL_DEFAULT:-"gpt-4o-mini"}
BOT_MAX_RETRIES=${BOT_MAX_RETRIES:-2}
BOT_REQUEST_TIMEOUT_SEC=${BOT_REQUEST_TIMEOUT_SEC:-45}

mkdir -p "$BOT_LOG_ROOT"

echo "[multi-bot] building bot entrypoint"
nim c "$ROOT_DIR/src/bot/main.nim"

BOT_PIDS=()
for i in $(seq 1 "$BOT_COUNT"); do
  priv_var="BOT_${i}_PLAYER_PRIV_HEX"
  pub_var="BOT_${i}_PLAYER_PUB_HEX"
  model_var="BOT_${i}_MODEL"

  bot_priv=${!priv_var:-}
  bot_pub=${!pub_var:-}
  bot_model=${!model_var:-$BOT_MODEL_DEFAULT}

  if [[ -z "$bot_priv" || -z "$bot_pub" ]]; then
    echo "Missing keypair for bot $i ($priv_var / $pub_var)"
    exit 1
  fi

  bot_log_dir="$BOT_LOG_ROOT/bot$i"
  bot_stdout="$BOT_LOG_ROOT/bot$i.stdout.log"
  mkdir -p "$bot_log_dir"

  echo "[multi-bot] starting bot $i with model $bot_model"
  env \
    BOT_RELAYS="$BOT_RELAYS" \
    BOT_GAME_ID="$BOT_GAME_ID" \
    BOT_DAEMON_PUBHEX="$BOT_DAEMON_PUBHEX" \
    BOT_PLAYER_PRIV_HEX="$bot_priv" \
    BOT_PLAYER_PUB_HEX="$bot_pub" \
    BOT_MODEL="$bot_model" \
    BOT_BASE_URL="$BOT_BASE_URL" \
    BOT_API_KEY="$BOT_API_KEY" \
    BOT_MAX_RETRIES="$BOT_MAX_RETRIES" \
    BOT_REQUEST_TIMEOUT_SEC="$BOT_REQUEST_TIMEOUT_SEC" \
    BOT_LOG_DIR="$bot_log_dir" \
    "$ROOT_DIR/src/bot/main" >"$bot_stdout" 2>&1 &

  BOT_PIDS+=("$!")
done

echo "[multi-bot] started ${#BOT_PIDS[@]} bot process(es)"
echo "[multi-bot] press Ctrl-C to stop"
wait
