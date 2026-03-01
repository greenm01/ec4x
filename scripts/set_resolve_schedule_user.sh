#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UNIT_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$UNIT_DIR/ec4x-resolve.service"
TIMER_FILE="$UNIT_DIR/ec4x-resolve.timer"

DAEMON_BIN=${EC4X_DAEMON_BIN:-"$HOME/.local/bin/ec4x-daemon"}
WORK_DIR=${EC4X_WORK_DIR:-"$ROOT_DIR"}
ON_CALENDAR=""
MODE=""
TIME_VALUE="00:00:00"

usage() {
  cat <<'EOF'
Usage:
  scripts/set_resolve_schedule_user.sh <mode> [options]

Modes:
  hourly            Resolve every hour
  4h                Resolve every 4 hours (clock aligned)
  12h               Resolve every 12 hours (clock aligned)
  daily             Resolve once per day (midnight default)
  custom            Resolve on custom OnCalendar expression
  off               Disable scheduled resolve timer

Options:
  --time HH:MM[:SS]       Time for daily mode (default: 00:00:00)
  --on-calendar EXPR      OnCalendar string for custom mode
  --daemon-bin PATH       Binary path (default: ~/.local/bin/ec4x-daemon)
  --work-dir PATH         Working directory (default: repo root)
  -h, --help              Show this help

Examples:
  scripts/set_resolve_schedule_user.sh hourly
  scripts/set_resolve_schedule_user.sh 4h
  scripts/set_resolve_schedule_user.sh 12h
  scripts/set_resolve_schedule_user.sh daily --time 23:30
  scripts/set_resolve_schedule_user.sh custom --on-calendar "Mon..Fri 18:00"
  scripts/set_resolve_schedule_user.sh off
EOF
}

if (($# == 0)); then
  usage
  exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

MODE="$1"
shift

while (($# > 0)); do
  case "$1" in
    --time)
      TIME_VALUE="$2"
      shift
      ;;
    --on-calendar)
      ON_CALENDAR="$2"
      shift
      ;;
    --daemon-bin)
      DAEMON_BIN="$2"
      shift
      ;;
    --work-dir)
      WORK_DIR="$2"
      shift
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

if [[ "$MODE" == "off" ]]; then
  echo "[schedule] disabling ec4x-resolve.timer"
  systemctl --user disable --now ec4x-resolve.timer
  exit 0
fi

if [[ ! -x "$DAEMON_BIN" ]]; then
  echo "[schedule] daemon binary not executable: $DAEMON_BIN"
  exit 1
fi

case "$MODE" in
  hourly)
    ON_CALENDAR="hourly"
    ;;
  4h)
    ON_CALENDAR="*-*-* 00/4:00:00"
    ;;
  12h)
    ON_CALENDAR="*-*-* 00/12:00:00"
    ;;
  daily)
    if [[ ! "$TIME_VALUE" =~ ^[0-9]{2}:[0-9]{2}(:[0-9]{2})?$ ]]; then
      echo "[schedule] invalid --time value: $TIME_VALUE"
      echo "[schedule] expected HH:MM or HH:MM:SS"
      exit 1
    fi
    ON_CALENDAR="*-*-* $TIME_VALUE"
    ;;
  custom)
    if [[ -z "$ON_CALENDAR" ]]; then
      echo "[schedule] custom mode requires --on-calendar"
      exit 1
    fi
    ;;
  *)
    echo "[schedule] invalid mode: $MODE"
    usage
    exit 1
    ;;
esac

mkdir -p "$UNIT_DIR"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=EC4X Resolve Active Turns

[Service]
Type=oneshot
WorkingDirectory=$WORK_DIR
ExecStart=$DAEMON_BIN resolve-all
EOF

cat > "$TIMER_FILE" <<EOF
[Unit]
Description=EC4X Scheduled Turn Resolution

[Timer]
OnCalendar=$ON_CALENDAR
Persistent=true

[Install]
WantedBy=timers.target
EOF

echo "[schedule] wrote $SERVICE_FILE"
echo "[schedule] wrote $TIMER_FILE"

systemctl --user daemon-reload
systemctl --user enable --now ec4x-resolve.timer

echo "[schedule] enabled ec4x-resolve.timer"
echo "[schedule] OnCalendar=$ON_CALENDAR"
systemctl --user list-timers ec4x-resolve.timer
