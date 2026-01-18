# EC4X Daemon Setup (Arch/CachyOS, User Service)

This guide runs `ec4x-daemon` as a systemd user service for development.

## Assumptions

- Working directory: `/home/youruser/dev/ec4x`
- Data directory: `/home/youruser/dev/ec4x/data`
- Relay URL configured via systemd EnvironmentFile

## 1) Create Environment File

Create `~/.config/ec4x/ec4x-daemon.env`:

```bash
EC4X_DATA_DIR=/home/youruser/dev/ec4x/data
EC4X_RELAY_URLS=ws://localhost:8080
EC4X_LOG_LEVEL=info
EC4X_REGEN_IDENTITY=1
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
ExecStart=/home/youruser/dev/ec4x/bin/ec4x-daemon start
Restart=on-failure
RestartSec=3
TimeoutStopSec=20
KillSignal=SIGINT
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
```

## 3) Enable and Start

```bash
systemctl --user daemon-reload
systemctl --user enable --now ec4x-daemon
```

## 4) Verify

```bash
systemctl --user status ec4x-daemon
journalctl --user -u ec4x-daemon -f
```

## Notes

- Keep using `nimble buildDaemon` (or `nimble buildAll`) before restarting.
- `EC4X_REGEN_IDENTITY=1` is a dev-only escape hatch when the identity file is
  invalid; remove it once the daemon starts cleanly.
- If you want to install the binary into `/usr/local/bin`, run
  `sudo nimble installDaemon`.
