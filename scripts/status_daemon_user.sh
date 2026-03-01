#!/usr/bin/env bash
set -euo pipefail

DAEMON_SERVICE=${EC4X_DAEMON_SERVICE:-ec4x-daemon}
RESOLVE_TIMER=${EC4X_RESOLVE_TIMER:-ec4x-resolve.timer}
RESOLVE_SERVICE=${EC4X_RESOLVE_SERVICE:-ec4x-resolve.service}

usage() {
  cat <<'EOF'
Usage:
  scripts/status_daemon_user.sh

Shows user-level daemon status and scheduled resolve timer state.

Environment overrides:
  EC4X_DAEMON_SERVICE   daemon service name (default: ec4x-daemon)
  EC4X_RESOLVE_TIMER    timer name (default: ec4x-resolve.timer)
  EC4X_RESOLVE_SERVICE  timer service name (default: ec4x-resolve.service)
EOF
}

if (($# > 0)); then
  case "$1" in
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
fi

echo "[status] daemon service: $DAEMON_SERVICE"
if systemctl --user --quiet is-active "$DAEMON_SERVICE"; then
  echo "[status] daemon active: yes"
else
  echo "[status] daemon active: no"
fi
systemctl --user --no-pager --lines=0 status "$DAEMON_SERVICE" || true

echo
echo "[status] resolve timer: $RESOLVE_TIMER"
if systemctl --user --quiet is-enabled "$RESOLVE_TIMER"; then
  echo "[status] timer enabled: yes"
else
  echo "[status] timer enabled: no"
fi

if systemctl --user --quiet is-active "$RESOLVE_TIMER"; then
  echo "[status] timer active: yes"
else
  echo "[status] timer active: no"
fi

systemctl --user list-timers --all "$RESOLVE_TIMER" --no-pager

echo
echo "[status] last daemon logs"
journalctl --user -u "$DAEMON_SERVICE" -n 25 --no-pager || true

echo
echo "[status] last resolve service logs"
journalctl --user -u "$RESOLVE_SERVICE" -n 25 --no-pager || true
