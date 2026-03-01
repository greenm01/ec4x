# EC4X Daemon Setup (Arch/CachyOS)

This guide describes running `ec4x-daemon` as a systemd service on Arch-based
systems with a dedicated service user.

## Assumptions

- Binary installed at `/usr/local/bin/ec4x-daemon`
- Working directory: `/home/youruser/dev/ec4x`
- Data directory: `/var/lib/ec4x`
- Identity file: `/var/lib/ec4x/daemon_identity.kdl`
- Relay URL configured via systemd EnvironmentFile

Adjust paths if you deploy elsewhere.

## 1) Create a Dedicated Service User

Create a system user with no login shell:

```bash
sudo useradd -r -m -d /var/lib/ec4x -s /usr/bin/nologin ec4x
```

## 2) Create Directories and Permissions

```bash
sudo mkdir -p /var/lib/ec4x /etc/ec4x
sudo chown -R ec4x:ec4x /var/lib/ec4x
sudo chmod 750 /var/lib/ec4x
sudo chmod 750 /etc/ec4x
```

## 3) Create Environment File

Create `/etc/ec4x/ec4x-daemon.env` with relay and data config:

```ini
EC4X_DATA_DIR=/var/lib/ec4x
EC4X_RELAY_URLS=ws://localhost:8080
EC4X_LOG_LEVEL=info
```

## 4) Install the Daemon Binary (Optional)

If you want to install the daemon systemwide, run:

```bash
sudo nimble installDaemon
```

## 5) Create systemd Unit

Create `/etc/systemd/system/ec4x-daemon.service`:

```ini
[Unit]
Description=EC4X Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ec4x
Group=ec4x
WorkingDirectory=/home/youruser/dev/ec4x
EnvironmentFile=/etc/ec4x/ec4x-daemon.env
ExecStart=/usr/local/bin/ec4x-daemon start
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
KillSignal=SIGINT
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

## 6) Initialize Daemon Identity

Generate the Nostr keypair once before the first start:

```bash
sudo -u ec4x /usr/local/bin/ec4x-daemon init
```

Output:
```
Daemon identity created at: /var/lib/ec4x/daemon_identity.kdl
Public key (npub): npub1...
Keep this file safe - back it up alongside your game databases.
```

The file is written with `600` permissions (owner read/write only).
Running `init` again is safe — it will never overwrite an existing identity.

## 7) Enable and Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now ec4x-daemon
```

## 8) Verify

```bash
systemctl status ec4x-daemon
journalctl -u ec4x-daemon -f
```

## Notes

- Relay URLs are managed in `/etc/ec4x/ec4x-daemon.env`.
- Back up `daemon_identity.kdl` alongside your game databases. If the identity
  is lost, existing GameDefinition events on the relay will be unverifiable.
- For local development, run `./bin/ec4x-daemon start` manually from your
  checkout.

## Manual Turn Advancement

Resolve one game manually:

```bash
sudo -u ec4x /usr/local/bin/ec4x-daemon resolve --gameId=<game-id>
```

Resolve all active games manually:

```bash
sudo -u ec4x /usr/local/bin/ec4x-daemon resolve-all
```

## Scheduled Turn Advancement (systemd timer)

Create `/etc/systemd/system/ec4x-resolve.service`:

```ini
[Unit]
Description=EC4X Resolve Active Turns

[Service]
Type=oneshot
User=ec4x
Group=ec4x
WorkingDirectory=/home/youruser/dev/ec4x
ExecStart=/usr/local/bin/ec4x-daemon resolve-all
```

Create `/etc/systemd/system/ec4x-resolve.timer`:

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
sudo systemctl daemon-reload
sudo systemctl enable --now ec4x-resolve.timer
```

Common schedule presets (`OnCalendar`):

- Hourly: `hourly`
- Every 4 hours: `*-*-* 00/4:00:00`
- Every 12 hours: `*-*-* 00/12:00:00`
- Daily at midnight (default): `*-*-* 00:00:00`

Disable scheduled advancement:

```bash
sudo systemctl disable --now ec4x-resolve.timer
```

## Manual-Only Mode

In `config/daemon.kdl`, set:

```kdl
turn_deadline_minutes 0
auto_resolve_on_all_submitted #false
```

With the timer disabled, turns only advance via explicit manual commands.
