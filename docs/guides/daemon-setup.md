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

```bash
EC4X_DATA_DIR=/var/lib/ec4x
EC4X_RELAY_URLS=ws://localhost:8080
EC4X_LOG_LEVEL=info
# Optional dev-only override:
# EC4X_REGEN_IDENTITY=1
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

## 6) Enable and Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now ec4x-daemon
```

## 7) Verify

```bash
systemctl status ec4x-daemon
journalctl -u ec4x-daemon -f
```

## Notes

- Relay URLs are managed in `/etc/ec4x/ec4x-daemon.env`.
- Identity will be created at `/var/lib/ec4x/daemon_identity.kdl` on first run.
- For local development, you can still run `./bin/ec4x-daemon start` manually from your checkout.
