# Turn Resolution Operations

Operator runbook for managing EC4X turn advancement.

This guide focuses on user-level daemon setups (`systemctl --user`).

## Quick Commands

```bash
# Manual: resolve one game
./bin/ec4x-daemon resolve --gameId=<game-id>

# Manual: resolve all active games
./bin/ec4x-daemon resolve-all

# Deploy daemon updates (~/.local/bin + restart service)
./scripts/deploy_daemon_user.sh

# Set schedule preset (examples)
./scripts/set_resolve_schedule_user.sh hourly
./scripts/set_resolve_schedule_user.sh 4h
./scripts/set_resolve_schedule_user.sh 12h
./scripts/set_resolve_schedule_user.sh daily --time 00:00

# Disable scheduled resolves (manual-only scheduling)
./scripts/set_resolve_schedule_user.sh off

# Status: daemon + timer + recent logs
./scripts/status_daemon_user.sh
```

## Operating Modes

### 1) Manual-only

No automatic advancement. Turns advance only when you run `resolve` or
`resolve-all` manually.

```kdl
# config/daemon.kdl
turn_deadline_minutes 0
auto_resolve_on_all_submitted #false
```

And disable timer:

```bash
./scripts/set_resolve_schedule_user.sh off
```

### 2) Scheduled-only

Turns resolve on your timer cadence, regardless of all-submitted trigger.

```kdl
# config/daemon.kdl
auto_resolve_on_all_submitted #false
```

Enable timer cadence via presets:

```bash
./scripts/set_resolve_schedule_user.sh hourly
```

### 3) Hybrid (submit-trigger + schedule)

Resolve early when all players submit, otherwise resolve at schedule.

```kdl
# config/daemon.kdl
auto_resolve_on_all_submitted #true
```

Then set schedule, for example:

```bash
./scripts/set_resolve_schedule_user.sh daily --time 00:00
```

## Cadence Presets

- `hourly`
- `4h`
- `12h`
- `daily --time HH:MM[:SS]`
- `custom --on-calendar "..."` for arbitrary systemd `OnCalendar`

The schedule script writes:

- `~/.config/systemd/user/ec4x-resolve.service`
- `~/.config/systemd/user/ec4x-resolve.timer`

## Update Workflow (Typical Dev Loop)

When daemon code changes:

1. Run `./scripts/deploy_daemon_user.sh`
2. Verify with `./scripts/status_daemon_user.sh`

You do **not** need to rerun `set_resolve_schedule_user.sh` unless you want
to change schedule settings.

## Important Behavior Notes

- `set_resolve_schedule_user.sh off` disables the resolve timer only.
- It does **not** restart `ec4x-daemon`.
- The deploy script restarts `ec4x-daemon` after installing the binary.

## Troubleshooting

```bash
# Confirm daemon executable path loaded by systemd user unit
systemctl --user show ec4x-daemon --property=ExecStart

# Verify daemon is healthy
systemctl --user is-active ec4x-daemon
journalctl --user -u ec4x-daemon -n 100 --no-pager

# Verify timer is enabled/active and next run time
systemctl --user is-enabled ec4x-resolve.timer
systemctl --user is-active ec4x-resolve.timer
systemctl --user list-timers ec4x-resolve.timer --all
```

## Related Guides

- `docs/guides/daemon-setup-user.md`
- `docs/guides/daemon-setup.md`
