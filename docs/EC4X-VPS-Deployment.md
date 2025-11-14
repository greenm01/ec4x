# EC4X VPS Deployment Guide

## Overview

This guide covers deploying EC4X on a VPS, including the Nostr relay and game daemon. Like hosting a BBS system, you'll run both the relay (the "board") and the game door on the same server.

## VPS Requirements

### Recommended Specifications

**Starter Setup (5-10 concurrent games):**
- **Provider**: Hetzner, DigitalOcean, Vultr, or Linode
- **CPU**: 2 cores (x86_64)
- **RAM**: 2GB
- **Storage**: 40GB SSD
- **Bandwidth**: 2TB/month
- **Cost**: ~$10/month

**Production Setup (20-50 games):**
- **CPU**: 4 cores
- **RAM**: 4GB
- **Storage**: 80GB SSD
- **Bandwidth**: 4TB/month
- **Cost**: ~$20/month

### OS Choice

**Ubuntu 24.04 LTS** (recommended)
- Long-term support
- Large community
- Easy package management

**Debian 12** (alternative)
- More stable
- Lighter weight

## Initial Server Setup

### 1. Secure Your VPS

```bash
# SSH in as root
ssh root@your-server-ip

# Update system
apt update && apt upgrade -y

# Create non-root user
adduser ec4x
usermod -aG sudo ec4x

# Setup SSH key auth
mkdir -p /home/ec4x/.ssh
cp /root/.ssh/authorized_keys /home/ec4x/.ssh/
chown -R ec4x:ec4x /home/ec4x/.ssh
chmod 700 /home/ec4x/.ssh
chmod 600 /home/ec4x/.ssh/authorized_keys

# Disable password auth
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd

# Setup firewall
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```

### 2. Install System Dependencies

```bash
# Switch to ec4x user
su - ec4x

# Install build tools
sudo apt install -y build-essential git curl wget \
  libssl-dev pkg-config sqlite3

# Install Nim (if building on VPS)
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
echo 'export PATH=$HOME/.nimble/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

## Nostr Relay Setup

### 1. Install nostr-rs-relay

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Clone and build nostr-rs-relay
cd /opt
sudo mkdir -p nostr-relay
sudo chown ec4x:ec4x nostr-relay
cd nostr-relay

git clone https://github.com/scsibug/nostr-rs-relay.git .
cargo build --release

# Binary will be at: ./target/release/nostr-rs-relay
```

### 2. Configure Relay

Create `/opt/nostr-relay/config.toml`:

```toml
[info]
relay_url = "wss://relay.ec4x.game"
name = "EC4X Game Relay"
description = "Official relay for EC4X turn-based strategy games - A Nostr BBS door game"
pubkey = ""  # Optional relay operator pubkey
contact = "admin@ec4x.game"

[database]
data_directory = "/var/lib/nostr-relay"
engine = "sqlite"

[network]
port = 8080
address = "127.0.0.1"  # Bind to localhost, Caddy will proxy

[limits]
# Message size limits
max_event_bytes = 1048576  # 1MB (for large game states)
max_ws_message_bytes = 1048576
max_ws_frame_bytes = 1048576

# Connection limits
messages_per_sec = 10
subscriptions_per_connection = 20

# Storage limits
event_age_limit = 0  # Never prune events (archive everything)
event_max_storage_bytes = 10737418240  # 10GB total storage

[retention]
# Keep EC4X events forever
[[retention.event_kinds]]
kinds = [30001, 30002, 30003, 30004, 30005]  # EC4X custom kinds
time_limit = 0  # Permanent
count_limit = 0  # Unlimited

# Keep standard Nostr events for 90 days
[[retention.event_kinds]]
kinds = [0, 1, 3, 5, 7]  # Metadata, notes, contacts, etc.
time_limit = 7776000  # 90 days in seconds

[authorization]
# Optional: Require NIP-42 auth for writes
pubkey_whitelist = []  # Empty = allow all

[logging]
folder_path = "/var/log/nostr-relay"
file_prefix = "relay"
level = "info"

[grpc]
# Disable gRPC (not needed)
enabled = false
```

### 3. Create Data Directory

```bash
sudo mkdir -p /var/lib/nostr-relay
sudo chown ec4x:ec4x /var/lib/nostr-relay

sudo mkdir -p /var/log/nostr-relay
sudo chown ec4x:ec4x /var/log/nostr-relay
```

### 4. Create Systemd Service

Create `/etc/systemd/system/nostr-relay.service`:

```ini
[Unit]
Description=Nostr Relay for EC4X
After=network.target

[Service]
Type=simple
User=ec4x
Group=ec4x
WorkingDirectory=/opt/nostr-relay
ExecStart=/opt/nostr-relay/target/release/nostr-rs-relay -c /opt/nostr-relay/config.toml
Restart=always
RestartSec=10

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/nostr-relay /var/log/nostr-relay

# Resource limits
LimitNOFILE=65536
MemoryMax=1G
CPUQuota=200%

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable nostr-relay
sudo systemctl start nostr-relay
sudo systemctl status nostr-relay
```

## EC4X Daemon Setup

### 1. Build EC4X Binaries

**Option A: Build on Development Machine**
```bash
# On your dev machine
cd ~/dev/ec4x
nimble build -d:release

# Binaries are in bin/
# Transfer to VPS:
scp bin/daemon ec4x@your-server:/opt/ec4x/bin/
scp bin/moderator ec4x@your-server:/opt/ec4x/bin/
```

**Option B: Build on VPS**
```bash
# On VPS
cd /opt
sudo mkdir ec4x
sudo chown ec4x:ec4x ec4x
cd ec4x

git clone https://github.com/yourusername/ec4x.git .
nimble build -d:release
```

### 2. Create Directory Structure

```bash
sudo mkdir -p /opt/ec4x/{bin,data,logs}
sudo chown -R ec4x:ec4x /opt/ec4x

# Create game data directories
mkdir -p /opt/ec4x/data/{games,archive,templates}

# Copy game config template
cp data/templates/game_config.toml.template /opt/ec4x/data/templates/
```

### 3. Configure Daemon

Create `/opt/ec4x/daemon_config.toml`:

```toml
[relay]
urls = [
  "ws://localhost:8080",  # Local relay (fast)
  "wss://relay.damus.io",  # Fallback public relay
  "wss://nos.lol"          # Fallback public relay
]
reconnect_delay_seconds = 5

[moderator]
private_key_file = "/opt/ec4x/keys/moderator.key"  # Keep secure!
public_key = "your-moderator-npub-here"

[games]
data_directory = "/opt/ec4x/data/games"
archive_directory = "/opt/ec4x/data/archive"
template_directory = "/opt/ec4x/data/templates"

[turn_schedule]
# Run turns at midnight UTC
hour = 0
minute = 0
timezone = "UTC"

# Or run every N hours
# interval_hours = 24

[logging]
level = "info"
log_directory = "/opt/ec4x/logs"
```

### 4. Generate Moderator Keys

```bash
# Using Nim client or standalone tool
cd /opt/ec4x
./bin/moderator keygen --output keys/moderator.key

# This generates:
# - keys/moderator.key (private, keep secret!)
# - Prints npub... (public, share this)

# Secure the key
chmod 600 keys/moderator.key
```

### 5. Create Systemd Service

Create `/etc/systemd/system/ec4x-daemon.service`:

```ini
[Unit]
Description=EC4X Game Daemon
After=network.target nostr-relay.service
Requires=nostr-relay.service

[Service]
Type=simple
User=ec4x
Group=ec4x
WorkingDirectory=/opt/ec4x
ExecStart=/opt/ec4x/bin/daemon --config /opt/ec4x/daemon_config.toml
Restart=always
RestartSec=10

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/opt/ec4x/data /opt/ec4x/logs

# Resource limits
MemoryMax=2G
CPUQuota=150%

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable ec4x-daemon
sudo systemctl start ec4x-daemon
sudo systemctl status ec4x-daemon
```

## Reverse Proxy with Caddy

Caddy provides automatic HTTPS (Let's Encrypt) with zero config.

### 1. Install Caddy

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy
```

### 2. Configure Caddy

Edit `/etc/caddy/Caddyfile`:

```
relay.ec4x.game {
    reverse_proxy localhost:8080

    # Websocket support
    header {
        Upgrade websocket
        Connection Upgrade
    }

    # Logs
    log {
        output file /var/log/caddy/relay.log
        format json
    }
}

# Optional: Status page
status.ec4x.game {
    root * /var/www/ec4x-status
    file_server

    # API endpoint for game stats
    reverse_proxy /api/* localhost:8081
}
```

```bash
sudo systemctl reload caddy
```

### 3. DNS Configuration

Point your domains to your VPS IP:

```
A    relay.ec4x.game   -> your.vps.ip.address
A    status.ec4x.game  -> your.vps.ip.address
```

Caddy will automatically obtain Let's Encrypt certificates.

## Monitoring & Maintenance

### 1. Check Service Status

```bash
# Relay status
sudo systemctl status nostr-relay
sudo journalctl -u nostr-relay -f

# Daemon status
sudo systemctl status ec4x-daemon
sudo journalctl -u ec4x-daemon -f

# Caddy status
sudo systemctl status caddy
```

### 2. View Logs

```bash
# Relay logs
tail -f /var/log/nostr-relay/relay.log

# Daemon logs
tail -f /opt/ec4x/logs/daemon.log

# Caddy logs
tail -f /var/log/caddy/relay.log
```

### 3. Monitor Resources

```bash
# Install monitoring tools
sudo apt install -y htop iotop nethogs

# Check resource usage
htop

# Check disk usage
df -h
du -sh /var/lib/nostr-relay
du -sh /opt/ec4x/data

# Check network
ss -tunlp | grep -E '8080|443'
```

### 4. Database Maintenance

```bash
# Vacuum SQLite database (monthly)
sqlite3 /var/lib/nostr-relay/nostr.db "VACUUM;"

# Check database size
du -h /var/lib/nostr-relay/nostr.db

# Backup database
sqlite3 /var/lib/nostr-relay/nostr.db ".backup /opt/ec4x/backups/relay-$(date +%Y%m%d).db"
```

## Backup Strategy

### 1. Automated Backups

Create `/opt/ec4x/scripts/backup.sh`:

```bash
#!/bin/bash
BACKUP_DIR="/opt/ec4x/backups"
DATE=$(date +%Y%m%d-%H%M%S)

mkdir -p $BACKUP_DIR

# Backup relay database
sqlite3 /var/lib/nostr-relay/nostr.db ".backup $BACKUP_DIR/relay-$DATE.db"

# Backup game data
tar -czf $BACKUP_DIR/games-$DATE.tar.gz /opt/ec4x/data/games

# Backup configs
tar -czf $BACKUP_DIR/config-$DATE.tar.gz \
  /opt/ec4x/*.toml \
  /opt/nostr-relay/config.toml \
  /etc/caddy/Caddyfile

# Keep only last 30 days
find $BACKUP_DIR -name "*.db" -mtime +30 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +30 -delete

echo "Backup completed: $DATE"
```

```bash
chmod +x /opt/ec4x/scripts/backup.sh

# Add to crontab (daily at 3 AM)
crontab -e
0 3 * * * /opt/ec4x/scripts/backup.sh >> /opt/ec4x/logs/backup.log 2>&1
```

### 2. Off-site Backups

```bash
# Install rclone for cloud backups
curl https://rclone.org/install.sh | sudo bash

# Configure rclone (e.g., for BackBlaze B2, AWS S3)
rclone config

# Sync backups to cloud (daily at 4 AM)
crontab -e
0 4 * * * rclone sync /opt/ec4x/backups remote:ec4x-backups --log-file=/opt/ec4x/logs/rclone.log
```

## Security Hardening

### 1. Fail2ban

```bash
# Protect SSH
sudo apt install -y fail2ban

# Create jail config
sudo cat > /etc/fail2ban/jail.local << EOF
[sshd]
enabled = true
port = 22
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

### 2. Automatic Updates

```bash
# Install unattended-upgrades
sudo apt install -y unattended-upgrades

# Enable automatic security updates
sudo dpkg-reconfigure -plow unattended-upgrades
```

### 3. Rate Limiting

Caddy handles basic rate limiting, but you can add more:

```
relay.ec4x.game {
    # Rate limit WebSocket connections
    rate_limit {
        zone nostr_connections {
            key {remote_host}
            events 100
            window 1m
        }
    }

    reverse_proxy localhost:8080
}
```

## Troubleshooting

### Relay Not Accessible

```bash
# Check if relay is running
sudo systemctl status nostr-relay

# Check if listening on port
ss -tunlp | grep 8080

# Check Caddy config
sudo caddy validate --config /etc/caddy/Caddyfile

# Check firewall
sudo ufw status

# Test WebSocket locally
wscat -c ws://localhost:8080
```

### Daemon Not Processing Turns

```bash
# Check daemon logs
sudo journalctl -u ec4x-daemon -n 100

# Check connection to relay
sudo journalctl -u ec4x-daemon | grep -i "connected"

# Manually trigger turn
/opt/ec4x/bin/moderator resolve-turn --game game-id

# Check game data
ls -la /opt/ec4x/data/games/
```

### High Resource Usage

```bash
# Check memory usage
free -h
ps aux --sort=-%mem | head

# Check disk I/O
iotop

# Check database size
du -sh /var/lib/nostr-relay/nostr.db

# Optimize database
sqlite3 /var/lib/nostr-relay/nostr.db "VACUUM; ANALYZE;"
```

### SSL Certificate Issues

```bash
# Check Caddy logs
sudo journalctl -u caddy -n 50

# Verify DNS propagation
dig relay.ec4x.game

# Force certificate renewal
sudo caddy reload --config /etc/caddy/Caddyfile
```

## Performance Tuning

### 1. Increase File Descriptors

Edit `/etc/security/limits.conf`:

```
ec4x soft nofile 65536
ec4x hard nofile 65536
```

### 2. Tune SQLite

Add to relay config:

```toml
[database]
# ... existing config ...
pragma = [
    "journal_mode=WAL",     # Write-ahead logging
    "synchronous=NORMAL",    # Balance safety/speed
    "cache_size=-64000",     # 64MB cache
    "temp_store=MEMORY"      # Temp tables in RAM
]
```

### 3. System Tuning

```bash
# Increase network buffer sizes
sudo sysctl -w net.core.rmem_max=16777216
sudo sysctl -w net.core.wmem_max=16777216
sudo sysctl -w net.ipv4.tcp_rmem='4096 87380 16777216'
sudo sysctl -w net.ipv4.tcp_wmem='4096 65536 16777216'

# Make permanent
echo "net.core.rmem_max=16777216" | sudo tee -a /etc/sysctl.conf
echo "net.core.wmem_max=16777216" | sudo tee -a /etc/sysctl.conf
```

## Scaling Considerations

### When to Upgrade

**Signs you need more resources:**
- CPU usage consistently >70%
- Memory usage >80%
- Disk I/O wait time increasing
- WebSocket connections timing out
- Turn resolution taking >30 seconds

### Vertical Scaling

```bash
# On most VPS providers, you can upgrade RAM/CPU without downtime:
# 1. Power off gracefully
sudo systemctl stop ec4x-daemon
sudo systemctl stop nostr-relay
sudo shutdown -h now

# 2. Upgrade via provider dashboard
# 3. Boot up, services auto-start
```

### Horizontal Scaling (Future)

For very high load:
- **Multiple relay instances**: Distribute read load
- **Separate daemon server**: Dedicated compute for game logic
- **PostgreSQL**: Replace SQLite for multi-writer support
- **Redis cache**: Cache game states

## Quick Reference

```bash
# Service management
sudo systemctl {start|stop|restart|status} nostr-relay
sudo systemctl {start|stop|restart|status} ec4x-daemon
sudo systemctl {start|stop|restart|status} caddy

# Logs
sudo journalctl -u nostr-relay -f
sudo journalctl -u ec4x-daemon -f
tail -f /opt/ec4x/logs/daemon.log

# Manual operations
/opt/ec4x/bin/moderator new-game --config game.toml
/opt/ec4x/bin/moderator resolve-turn --game <game-id>
/opt/ec4x/bin/moderator list-games

# Database
sqlite3 /var/lib/nostr-relay/nostr.db
> SELECT count(*) FROM event WHERE kind IN (30001, 30002, 30003);

# Backups
/opt/ec4x/scripts/backup.sh
rclone sync /opt/ec4x/backups remote:ec4x-backups
```

## Support & Resources

- **EC4X Docs**: https://github.com/yourusername/ec4x/tree/main/docs
- **nostr-rs-relay**: https://github.com/scsibug/nostr-rs-relay
- **Caddy**: https://caddyserver.com/docs/
- **Nostr Protocol**: https://github.com/nostr-protocol/nips

---

*Last updated: November 2024*
