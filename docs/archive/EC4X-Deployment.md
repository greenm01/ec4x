# EC4X Deployment Guide

This guide covers deploying EC4X in production for multiplayer gameplay over SSH.

## Overview

EC4X uses a **daemon-based architecture** optimized for asynchronous turn-based gameplay:

- **Daemon**: Systemd service that watches game folders and processes turns on schedule
- **SSH Transport**: Players submit orders via SSH file-drop
- **Discord Bot** (optional): Social layer for game management and turn notifications
- **ANSI Client**: Lightweight terminal interface for order entry

## Prerequisites

- Ubuntu 22.04 LTS or Debian 12+ server (VPS or dedicated)
- Root or sudo access
- Public IP address with ports 22 (SSH) open
- (Optional) Discord bot token for bot integration
- Nix package manager or system Nim installation (>= 2.0.0)

---

## 1. Server Setup

### 1.1 Create EC4X System User

```bash
# Create dedicated system user (no login shell)
sudo useradd -r -m -d /home/ec4x -s /usr/sbin/nologin ec4x

# Create required directories
sudo mkdir -p /opt/ec4x/{bin,games,archives,config}
sudo mkdir -p /home/ec4x/.ssh
sudo chown -R ec4x:ec4x /opt/ec4x /home/ec4x
```

### 1.2 Install Dependencies

**Option A: Using Nix (recommended)**

```bash
# Install Nix
curl -L https://nixos.org/nix/install | sh

# Clone repository
cd /opt/ec4x
sudo -u ec4x git clone https://github.com/greenm01/ec4x.git src

# Enter dev shell and build
cd src
nix develop --command nimble build -d:release

# Copy binaries
sudo cp bin/moderator bin/client /opt/ec4x/bin/
```

**Option B: System Nim**

```bash
# Install Nim
sudo apt update
sudo apt install nim

# Build project
cd /opt/ec4x/src
nimble build -d:release
sudo cp bin/moderator bin/client /opt/ec4x/bin/
```

### 1.3 Configuration File

Create `/opt/ec4x/config/daemon.kdl`:

```kdl
daemon {
  games_dir "/opt/ec4x/games"
  archive_dir "/opt/ec4x/archives"
  turn_schedule "0 0 * * *"  // Midnight daily (cron format)
  http_port 8080
  bind_address "127.0.0.1"   // Local only
}

discord_bot {
  enabled #true
  webhook_url "http://localhost:8081/turn_done"
  token_file "/opt/ec4x/config/.discord_token"
}

ssh {
  authorized_keys "/home/ec4x/.ssh/authorized_keys"
  forced_command "/opt/ec4x/bin/client"
}

turn_processing {
  auto_process #true
  grace_period_hours 0
  max_concurrent_games 10
}
```

---

## 2. SSH Configuration

### 2.1 Configure SSHD

Edit `/etc/ssh/sshd_config` or create `/etc/ssh/sshd_config.d/ec4x.conf`:

```sshd_config
# EC4X forced command setup
Match User ec4x
    ForceCommand /opt/ec4x/bin/client --game-id=%d
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
    AllowAgentForwarding no
```

Reload SSH:

```bash
sudo systemctl reload sshd
```

### 2.2 Test SSH Setup

```bash
# Add a test SSH key
sudo -u ec4x ssh-keygen -t ed25519 -f /home/ec4x/.ssh/test_key -N ""
sudo -u ec4x cat /home/ec4x/.ssh/test_key.pub >> /home/ec4x/.ssh/authorized_keys

# Test connection (should show "not yet implemented" from stub client)
ssh -i /home/ec4x/.ssh/test_key ec4x@localhost
```

---

## 3. Systemd Services

### 3.1 Daemon Service

Create `/etc/systemd/system/ec4x-daemon.service`:

```ini
[Unit]
Description=EC4X Game Daemon
After=network.target

[Service]
Type=simple
User=ec4x
Group=ec4x
WorkingDirectory=/opt/ec4x
ExecStart=/opt/ec4x/bin/moderator daemon --config=/opt/ec4x/config/daemon.toml
Restart=always
RestartSec=10

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/ec4x/games /opt/ec4x/archives

[Install]
WantedBy=multi-user.target
```

### 3.2 Turn Scheduler Timer

Create `/etc/systemd/system/ec4x-turn.timer`:

```ini
[Unit]
Description=EC4X Nightly Turn Processing
Requires=ec4x-daemon.service

[Timer]
OnCalendar=daily
OnCalendar=00:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

Create `/etc/systemd/system/ec4x-turn.service`:

```ini
[Unit]
Description=EC4X Turn Processing
Requires=ec4x-daemon.service

[Service]
Type=oneshot
User=ec4x
Group=ec4x
ExecStart=/opt/ec4x/bin/moderator process-turns --config=/opt/ec4x/config/daemon.toml
```

### 3.3 Enable Services

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable and start daemon
sudo systemctl enable --now ec4x-daemon.service

# Enable turn timer
sudo systemctl enable --now ec4x-turn.timer

# Check status
sudo systemctl status ec4x-daemon.service
sudo systemctl list-timers | grep ec4x
```

---

## 4. Discord Bot Setup (Optional)

### 4.1 Create Discord Bot

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Create New Application → "EC4X Game Bot"
3. Bot tab → Add Bot
4. Enable:
   - MESSAGE CONTENT INTENT
   - SERVER MEMBERS INTENT
5. Copy bot token

### 4.2 Store Bot Token

```bash
sudo -u ec4x sh -c 'echo "YOUR_BOT_TOKEN_HERE" > /opt/ec4x/config/.discord_token'
sudo chmod 600 /opt/ec4x/config/.discord_token
```

### 4.3 Bot Service

Create `/etc/systemd/system/ec4x-bot.service`:

```ini
[Unit]
Description=EC4X Discord Bot
After=network.target ec4x-daemon.service
Requires=ec4x-daemon.service

[Service]
Type=simple
User=ec4x
Group=ec4x
WorkingDirectory=/opt/ec4x
ExecStart=/opt/ec4x/bin/moderator bot --config=/opt/ec4x/config/daemon.toml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable:

```bash
sudo systemctl enable --now ec4x-bot.service
sudo systemctl status ec4x-bot.service
```

### 4.4 Invite Bot to Server

Generate invite URL with permissions:
- `applications.commands` (slash commands)
- `bot`
- Permissions: `Send Messages`, `Embed Links`, `Attach Files`

Example: `https://discord.com/api/oauth2/authorize?client_id=YOUR_CLIENT_ID&permissions=51200&scope=bot%20applications.commands`

---

## 5. Game Management

### 5.1 Create New Game

**Via Discord** (if bot enabled):

```
/newgame name:"Imperium Wars" players:6 description:"First campaign"
```

**Via CLI**:

```bash
sudo -u ec4x /opt/ec4x/bin/moderator new /opt/ec4x/games/imperium_wars
```

### 5.2 Add Players

**Via Discord**:

```
/register
# Bot will prompt for SSH public key
```

**Via CLI**:

```bash
# Player provides their SSH public key
echo "ssh-ed25519 AAAA...player1_key player1@email.com" | \
  sudo -u ec4x tee -a /home/ec4x/.ssh/authorized_keys
```

### 5.3 Manual Turn Processing

```bash
# Process specific game
sudo -u ec4x /opt/ec4x/bin/moderator process-turn /opt/ec4x/games/imperium_wars

# Process all games
sudo -u ec4x /opt/ec4x/bin/moderator process-all-turns
```

---

## 6. Player Workflow

### 6.1 Player Connection

Players connect via SSH:

```bash
ssh ec4x@your-server.com
```

The forced command automatically launches the EC4X client.

### 6.2 Order Submission Workflow

1. **SSH in**: Client shows current game state (filtered view)
2. **Review**: Player sees their fleets, systems, intel reports
3. **Enter orders**: Via ANSI interface or command-line flags
4. **Submit**: Client writes `packets/<house>.json` and exits
5. **Wait**: Daemon processes turn at midnight (or manual trigger)
6. **Notification**: Discord bot posts turn results
7. **Repeat**: Player SSHs in next day to see results and submit new orders

---

## 7. Monitoring and Maintenance

### 7.1 Log Files

```bash
# Daemon logs
sudo journalctl -u ec4x-daemon.service -f

# Bot logs
sudo journalctl -u ec4x-bot.service -f

# Turn processing logs
sudo journalctl -u ec4x-turn.service
```

### 7.2 Game Status

```bash
# List active games
sudo -u ec4x ls -la /opt/ec4x/games/

# Check game status
sudo -u ec4x /opt/ec4x/bin/moderator stats /opt/ec4x/games/imperium_wars

# View pending packets
sudo -u ec4x ls -la /opt/ec4x/games/imperium_wars/packets/
```

### 7.3 Backups

```bash
# Automated backup script
cat > /opt/ec4x/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/ec4x/backups/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"
cp -r /opt/ec4x/games "$BACKUP_DIR/"
cp -r /opt/ec4x/archives "$BACKUP_DIR/"
find /opt/ec4x/backups -type d -mtime +30 -exec rm -rf {} +
EOF

sudo chmod +x /opt/ec4x/backup.sh

# Add to cron
sudo crontab -e -u ec4x
# Add: 0 2 * * * /opt/ec4x/backup.sh
```

---

## 8. Troubleshooting

### 8.1 SSH Connection Issues

```bash
# Check SSH config
sudo sshd -T | grep -i match -A 10

# Verify authorized_keys permissions
sudo ls -la /home/ec4x/.ssh/
# Should be: authorized_keys (600), .ssh/ (700)

# Test forced command
sudo -u ec4x /opt/ec4x/bin/client --game-id=test
```

### 8.2 Daemon Not Processing Turns

```bash
# Check daemon status
sudo systemctl status ec4x-daemon.service

# Check timer status
sudo systemctl list-timers --all | grep ec4x

# Manual trigger
sudo systemctl start ec4x-turn.service

# Check game directory permissions
sudo ls -la /opt/ec4x/games/
# Should be owned by ec4x:ec4x
```

### 8.3 Discord Bot Not Responding

```bash
# Check bot status
sudo systemctl status ec4x-bot.service

# Verify token
sudo -u ec4x cat /opt/ec4x/config/.discord_token
# Should contain valid token (no newlines)

# Check connectivity
sudo -u ec4x curl -H "Authorization: Bot $(cat /opt/ec4x/config/.discord_token)" \
  https://discord.com/api/v10/users/@me
```

---

## 9. Security Considerations

### 9.1 Firewall

```bash
# Only allow SSH
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw enable
```

### 9.2 SSH Hardening

In `/etc/ssh/sshd_config`:

```sshd_config
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
MaxSessions 5
```

### 9.3 Rate Limiting

Consider using `fail2ban` for SSH brute-force protection:

```bash
sudo apt install fail2ban
sudo systemctl enable --now fail2ban
```

---

## 10. Scaling Considerations

### 10.1 Multiple Games

The daemon automatically handles multiple games:

```
/opt/ec4x/games/
├── game_001_imperium_wars/
├── game_002_border_skirmish/
└── game_003_grand_campaign/
```

Each is processed independently during turn resolution.

### 10.2 Performance Tuning

In `daemon.toml`:

```toml
[turn_processing]
max_concurrent_games = 10  # Process this many games in parallel
worker_threads = 4         # Threads per game
```

### 10.3 Database Backend

For games with many players (12+), consider moving from file-based storage to SQLite:

```toml
[storage]
backend = "sqlite"
db_path = "/opt/ec4x/data/ec4x.db"
```

---

## 11. Upgrade Process

```bash
# Stop services
sudo systemctl stop ec4x-daemon.service ec4x-bot.service

# Backup
sudo -u ec4x cp -r /opt/ec4x/games /opt/ec4x/games.backup

# Update code
cd /opt/ec4x/src
sudo -u ec4x git pull origin main

# Rebuild
sudo -u ec4x nix develop --command nimble build -d:release
sudo cp bin/* /opt/ec4x/bin/

# Restart services
sudo systemctl start ec4x-daemon.service ec4x-bot.service

# Verify
sudo systemctl status ec4x-daemon.service
```

---

## 12. Quick Reference

### Common Commands

```bash
# Service management
sudo systemctl status ec4x-daemon
sudo systemctl restart ec4x-daemon
sudo systemctl stop ec4x-bot

# Game management
sudo -u ec4x /opt/ec4x/bin/moderator new <game-dir>
sudo -u ec4x /opt/ec4x/bin/moderator stats <game-dir>
sudo -u ec4x /opt/ec4x/bin/moderator process-turn <game-dir>

# Logs
sudo journalctl -u ec4x-daemon -f
sudo journalctl -u ec4x-turn --since today

# Player management
sudo -u ec4x cat /home/ec4x/.ssh/authorized_keys
```

### File Locations

| Path | Purpose |
|------|---------|
| `/opt/ec4x/bin/` | Binaries (client, moderator) |
| `/opt/ec4x/games/` | Active games |
| `/opt/ec4x/archives/` | Turn history |
| `/opt/ec4x/config/` | Configuration files |
| `/home/ec4x/.ssh/` | SSH authorized keys |
| `/var/log/ec4x/` | Optional log directory |

---

## Support

- **Documentation**: [GitHub Repo](https://github.com/greenm01/ec4x)
- **Issues**: [Issue Tracker](https://github.com/greenm01/ec4x/issues)
- **Game Specification**: `docs/ec4x_specs.md`
- **Architecture**: `docs/EC4X-Architecture.md`
