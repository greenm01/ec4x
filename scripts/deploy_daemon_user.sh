#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SERVICE_NAME=${EC4X_DAEMON_SERVICE:-ec4x-daemon}
BIN_DIR=${EC4X_USER_BIN_DIR:-"$HOME/.local/bin"}
BIN_SRC="$ROOT_DIR/bin/ec4x-daemon"
BIN_DEST="$BIN_DIR/ec4x-daemon"

NO_BUILD=0
NO_RESTART=0
SHOW_LOGS=0

usage() {
  cat <<'EOF'
Usage:
  scripts/deploy_daemon_user.sh [options]

Options:
  --no-build     Skip nimble buildDaemon
  --no-restart   Skip systemctl --user restart
  --logs         Show recent daemon logs
  -h, --help     Show this help

Environment overrides:
  EC4X_DAEMON_SERVICE   systemd user service name (default: ec4x-daemon)
  EC4X_USER_BIN_DIR     install dir (default: ~/.local/bin)
EOF
}

while (($# > 0)); do
  case "$1" in
    --no-build)
      NO_BUILD=1
      ;;
    --no-restart)
      NO_RESTART=1
      ;;
    --logs)
      SHOW_LOGS=1
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

if [[ "$NO_BUILD" == "0" ]]; then
  echo "[deploy] building daemon"
  (cd "$ROOT_DIR" && nimble buildDaemon)
fi

if [[ ! -x "$BIN_SRC" ]]; then
  echo "[deploy] missing daemon binary: $BIN_SRC"
  exit 1
fi

echo "[deploy] installing binary to $BIN_DEST"
mkdir -p "$BIN_DIR"
install -m 755 "$BIN_SRC" "$BIN_DEST"

if [[ "$NO_RESTART" == "0" ]]; then
  echo "[deploy] restarting user service: $SERVICE_NAME"
  systemctl --user restart "$SERVICE_NAME"
  if ! systemctl --user --quiet is-active "$SERVICE_NAME"; then
    echo "[deploy] service is not active: $SERVICE_NAME"
    echo "[deploy] check logs: journalctl --user -u $SERVICE_NAME -n 80"
    exit 1
  fi
fi

echo "[deploy] done"
echo "[deploy] binary: $BIN_DEST"

if [[ "$SHOW_LOGS" == "1" ]]; then
  journalctl --user -u "$SERVICE_NAME" -n 60 --no-pager
fi
