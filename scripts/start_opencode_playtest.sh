#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCENARIO="scenarios/standard-2-player.kdl"
CLEAN_MODE="full"

usage() {
  cat <<'EOF'
Usage:
  scripts/start_opencode_playtest.sh [options]

Starts a Human-vs-OpenCode playtest game and prints invite codes.

Options:
  --scenario PATH        Scenario path (default: scenarios/standard-2-player.kdl)
  --clean-mode MODE      full|none (default: full)
  --no-clean             Alias for --clean-mode none
  -h, --help             Show this help

Notes:
  - full mode runs: nim r tools/clean_dev.nim --clean --logs
  - none mode skips cleanup
EOF
}

while (($# > 0)); do
  case "$1" in
    --scenario)
      SCENARIO="$2"
      shift
      ;;
    --clean-mode)
      CLEAN_MODE="$2"
      shift
      ;;
    --no-clean)
      CLEAN_MODE="none"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ "$CLEAN_MODE" != "full" && "$CLEAN_MODE" != "none" ]]; then
  echo "Invalid --clean-mode: $CLEAN_MODE"
  echo "Allowed: full, none"
  exit 1
fi

if [[ "$CLEAN_MODE" == "full" ]]; then
  echo "[opencode-playtest] cleaning cache/data/logs"
  (cd "$ROOT_DIR" && nim r tools/clean_dev.nim --clean --logs)
else
  echo "[opencode-playtest] skipping cleanup"
fi

echo "[opencode-playtest] creating game from $SCENARIO"
CREATE_OUTPUT=$(cd "$ROOT_DIR" && ./bin/ec4x new --scenario="$SCENARIO")
printf "%s\n" "$CREATE_OUTPUT"

GAME_SLUG=""
while IFS= read -r line; do
  if [[ "$line" == Slug:* ]]; then
    GAME_SLUG=${line#Slug: }
    break
  fi
done <<< "$CREATE_OUTPUT"

if [[ -z "$GAME_SLUG" ]]; then
  echo "[opencode-playtest] failed to parse game slug"
  exit 1
fi

echo
echo "[opencode-playtest] invite codes for $GAME_SLUG"
(cd "$ROOT_DIR" && ./bin/ec4x invite "$GAME_SLUG")

echo
echo "[opencode-playtest] next steps"
echo "  1) Join one invite in ./bin/tui"
echo "  2) Tell OpenCode which house you took"
echo "  3) OpenCode will play the other house each turn"
