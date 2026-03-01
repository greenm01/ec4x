# EC4X Daemon Setup (Arch/CachyOS, User Service)

This guide runs `ec4x-daemon` as a systemd user service for development.

## Assumptions

- Working directory: `/home/youruser/dev/ec4x`
- Data directory: `/home/youruser/dev/ec4x/data`
- Relay URL configured via systemd EnvironmentFile

## 1) Create Environment File

Create `~/.config/ec4x/ec4x-daemon.env`:

```ini
EC4X_DATA_DIR=/home/youruser/dev/ec4x/data
EC4X_RELAY_URLS=ws://localhost:8080
EC4X_LOG_LEVEL=info
```

## 2) Create systemd User Unit

Create `~/.config/systemd/user/ec4x-daemon.service`:

```ini
[Unit]
Description=EC4X Daemon (Dev)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/home/youruser/dev/ec4x
EnvironmentFile=%h/.config/ec4x/ec4x-daemon.env
ExecStart=/home/youruser/.local/bin/ec4x-daemon start
Restart=on-failure
RestartSec=3
TimeoutStopSec=20
KillSignal=SIGINT
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
```

## 3) Initialize Daemon Identity

Generate the Nostr keypair once before the first start:

```bash
./bin/ec4x-daemon init
```

Output:
```
Daemon identity created at: /home/youruser/.local/share/ec4x/daemon_identity.kdl
Public key (npub): npub1...
Keep this file safe - back it up alongside your game databases.
```

Running `init` again is safe — it will never overwrite an existing identity.

## 4) Enable and Start

```bash
systemctl --user daemon-reload
systemctl --user enable --now ec4x-daemon
```

## 5) Verify

```bash
systemctl --user status ec4x-daemon
journalctl --user -u ec4x-daemon -f
```

## Notes

- Keep using `nimble buildDaemon` (or `nimble buildAll`) before restarting.
- If you want to install the binary into `/usr/local/bin`, run
  `sudo nimble installDaemon`.

## Manual Turn Advancement

Resolve one game manually:

```bash
./bin/ec4x-daemon resolve --gameId=<game-id>
```

Resolve all active games manually:

```bash
./bin/ec4x-daemon resolve-all
```

Workflow helper scripts:

```bash
# Build -> install to ~/.local/bin -> restart user service
./scripts/deploy_daemon_user.sh

# Set schedule presets for resolve-all timer
./scripts/set_resolve_schedule_user.sh hourly
./scripts/set_resolve_schedule_user.sh 4h
./scripts/set_resolve_schedule_user.sh 12h
./scripts/set_resolve_schedule_user.sh daily --time 00:00
./scripts/set_resolve_schedule_user.sh off

# Show daemon + timer status and recent logs
./scripts/status_daemon_user.sh
```

## Scheduled Turn Advancement (systemd timer)

Create `~/.config/systemd/user/ec4x-resolve.service`:

```ini
[Unit]
Description=EC4X Resolve Active Turns

[Service]
Type=oneshot
WorkingDirectory=/home/youruser/dev/ec4x
ExecStart=/home/youruser/dev/ec4x/bin/ec4x-daemon resolve-all
```

Create `~/.config/systemd/user/ec4x-resolve.timer`:

```ini
[Unit]
Description=EC4X Scheduled Turn Resolution

[Timer]
OnCalendar=*-*-* 00:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable midnight schedule:

```bash
systemctl --user daemon-reload
systemctl --user enable --now ec4x-resolve.timer
```

Common schedule presets (`OnCalendar`):

- Hourly: `hourly`
- Every 4 hours: `*-*-* 00/4:00:00`
- Every 12 hours: `*-*-* 00/12:00:00`
- Daily at midnight (default): `*-*-* 00:00:00`

Disable scheduled advancement:

```bash
systemctl --user disable --now ec4x-resolve.timer
```

## Manual-Only Mode

In `config/daemon.kdl`, set:

```kdl
turn_deadline_minutes 0
auto_resolve_on_all_submitted #false
```

With the timer disabled, turns only advance via explicit manual commands.
