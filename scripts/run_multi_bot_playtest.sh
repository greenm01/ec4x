#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE=${1:-"$ROOT_DIR/scripts/bot/multi_session.env"}

cleanup() {
  if [[ -n "${BOT_DAEMON_PID:-}" ]]; then
    kill "$BOT_DAEMON_PID" 2>/dev/null || true
  fi
  if [[ -n "${BOT_RELAY_PID:-}" ]]; then
    kill "$BOT_RELAY_PID" 2>/dev/null || true
  fi
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
BOT_START_RELAY=${BOT_START_RELAY:-0}
BOT_START_DAEMON=${BOT_START_DAEMON:-0}
BOT_RELAY_BIN=${BOT_RELAY_BIN:-}
BOT_RELAY_CONFIG=${BOT_RELAY_CONFIG:-}
BOT_DAEMON_BIN=${BOT_DAEMON_BIN:-"$ROOT_DIR/bin/ec4x-daemon"}
BOT_SEED=${BOT_SEED:-}
BOT_CONFIG_HASH=${BOT_CONFIG_HASH:-}

mkdir -p "$BOT_LOG_ROOT"

if [[ "$BOT_START_RELAY" == "1" ]]; then
  if [[ -z "$BOT_RELAY_BIN" || ! -x "$BOT_RELAY_BIN" ]]; then
    echo "BOT_RELAY_BIN must be executable when BOT_START_RELAY=1"
    exit 1
  fi
  echo "[multi-bot] starting relay"
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
    echo "BOT_DAEMON_BIN must be executable when BOT_START_DAEMON=1"
    exit 1
  fi
  echo "[multi-bot] starting daemon"
  "$BOT_DAEMON_BIN" start &
  BOT_DAEMON_PID=$!
  sleep 2
fi

echo "[multi-bot] building bot entrypoint"
nim c "$ROOT_DIR/src/bot/main.nim"

BOT_PIDS=()
MODELS=()
for i in $(seq 1 "$BOT_COUNT"); do
  priv_var="BOT_${i}_PLAYER_PRIV_HEX"
  pub_var="BOT_${i}_PLAYER_PUB_HEX"
  model_var="BOT_${i}_MODEL"

  bot_priv=${!priv_var:-}
  bot_pub=${!pub_var:-}
  bot_model=${!model_var:-$BOT_MODEL_DEFAULT}
  MODELS+=("$bot_model")

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

RUN_METADATA="$BOT_LOG_ROOT/run_metadata.json"
{
  printf '{\n'
  printf '  "gameId": "%s",\n' "$BOT_GAME_ID"
  printf '  "relay": "%s",\n' "$BOT_RELAYS"
  printf '  "botCount": %s,\n' "$BOT_COUNT"
  printf '  "models": ['
  for idx in "${!MODELS[@]}"; do
    if [[ "$idx" -gt 0 ]]; then
      printf ', '
    fi
    printf '"%s"' "${MODELS[$idx]}"
  done
  printf '],\n'
  printf '  "maxRetries": %s,\n' "$BOT_MAX_RETRIES"
  printf '  "requestTimeoutSec": %s,\n' "$BOT_REQUEST_TIMEOUT_SEC"
  printf '  "seed": "%s",\n' "$BOT_SEED"
  printf '  "configHash": "%s"\n' "$BOT_CONFIG_HASH"
  printf '}\n'
} >"$RUN_METADATA"
echo "[multi-bot] wrote metadata to $RUN_METADATA"

echo "[multi-bot] started ${#BOT_PIDS[@]} bot process(es)"
echo "[multi-bot] press Ctrl-C to stop"
wait
