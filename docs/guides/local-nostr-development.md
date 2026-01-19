# EC4X Local Nostr Development Guide

This guide walks you through setting up a complete local development
environment for EC4X with Nostr transport. By the end, you'll have a
working game you can use for UI development.

## Architecture Overview

```
+-------------------+     +------------------+     +-------------------+
|   nostr-rs-relay  |<--->|   ec4x-daemon    |<--->|     ec4x-tui      |
|   (ws://localhost |     | (game engine +   |     |  (player client)  |
|        :8080)     |     |  nostr client)   |     |                   |
+-------------------+     +------------------+     +-------------------+
         ^                        |
         |                        v
         |                +------------------+
         +--------------->|   SQLite DB      |
                          | (per-game state) |
                          +------------------+
```

**Components:**

- **nostr-rs-relay**: External Nostr relay server (Rust)
- **ec4x-daemon**: Game engine + Nostr subscriber/publisher
- **ec4x-tui**: Terminal UI player client
- **ec4x**: Moderator CLI (creates games, admin tasks)

**Wire Format:**

```
KDL string -> zippy compress -> NIP-44 encrypt -> base64 -> Nostr event
```

---

## Prerequisites

### System Requirements

- Linux (tested on Ubuntu 22.04+, Debian 12+)
- 4GB RAM minimum
- 2GB disk space

### Required Tools

```bash
# Nim (2.0+)
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
source ~/.bashrc

# Rust (for nostr-rs-relay)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Build essentials
sudo apt install -y build-essential git sqlite3 pkg-config libssl-dev
```

---

## Phase 1: Install nostr-rs-relay

### 1.1 Clone and Build

```bash
cd ~/dev
git clone https://github.com/scsibug/nostr-rs-relay.git
cd nostr-rs-relay
cargo build --release

# Binary at: ./target/release/nostr-rs-relay
```

### 1.2 Create Configuration

Create `~/dev/nostr-rs-relay/config.toml`:

```toml
[info]
relay_url = "ws://localhost:8080"
name = "EC4X Local Relay"
description = "Development relay for EC4X"

[database]
data_directory = "./data"
engine = "sqlite"

[network]
port = 8080
address = "127.0.0.1"

[limits]
max_event_bytes = 1048576      # 1MB for large game states
max_ws_message_bytes = 1048576
max_ws_frame_bytes = 1048576
messages_per_sec = 100         # High for local dev
subscriptions_per_connection = 50

[retention]
# Keep EC4X events forever (kinds 30400-30405)
[[retention.event_kinds]]
kinds = [30400, 30401, 30402, 30403, 30405]
time_limit = 0   # Permanent
count_limit = 0  # Unlimited
```

### 1.3 Start Relay

```bash
cd ~/dev/nostr-rs-relay
./target/release/nostr-rs-relay -c config.toml

# Should see: "listening on ws://127.0.0.1:8080"
```

### 1.4 Test Relay (Optional)

Install websocat for testing:

```bash
cargo install websocat

# Connect to relay
websocat ws://localhost:8080

# Type this to subscribe (should get EOSE response):
["REQ","test",{"kinds":[1]}]
```

---

## Phase 2: Build EC4X

### 2.1 Install Dependencies

```bash
cd ~/dev/ec4x
nimble install -y
```

This installs:
- `ws` - WebSocket client
- `zippy` - Compression
- `nimcrypto` - Cryptography for NIP-44
- `nimkdl` - KDL parsing (your library!)
- Other dependencies

### 2.2 Build All Binaries

```bash
nimble buildAll

# Creates:
#   bin/ec4x        - Moderator CLI
#   bin/ec4x-daemon - Game daemon
#   bin/ec4x-tui    - TUI player client
```

### 2.3 Verify Builds

```bash
./bin/ec4x --help
./bin/ec4x-daemon --help
./bin/ec4x-tui --help
```

---

## Phase 3: Create a Test Game

### 3.1 Create Game

```bash
./bin/ec4x new \
  --name "Dev Test Game" \
  --scenario scenarios/standard-4-player.kdl

# Output:
#   Game ID: 550e8400-e29b-41d4-a716-446655440000
#   Name: Dev Test Game
#   Systems: 61
#   Houses: 4
#   Database: data/games/550e8400-.../ec4x.db
```

Save the Game ID for later steps.

### 3.2 Verify Game Created

```bash
./bin/ec4x list

# Output:
#   Games in data/games:
#     550e8400-e29b-41d4-a716-446655440000
```

### 3.3 Assign Test Players

For development, manually assign npubs to houses:

```bash
# Replace <game-id> with your actual game ID
sqlite3 data/games/<game-id>/ec4x.db << 'EOF'
UPDATE houses SET nostr_pubkey = 'npub1testplayeralpha000000000000000000000000000000000000001' WHERE name LIKE '%Alpha%';
UPDATE houses SET nostr_pubkey = 'npub1testplayerbeta0000000000000000000000000000000000000002' WHERE name LIKE '%Beta%';
UPDATE houses SET nostr_pubkey = 'npub1testplayergamma000000000000000000000000000000000000003' WHERE name LIKE '%Gamma%';
UPDATE houses SET nostr_pubkey = 'npub1testplayerdelta000000000000000000000000000000000000004' WHERE name LIKE '%Delta%';

-- Verify
SELECT id, name, nostr_pubkey FROM houses;
EOF
```

---

## Phase 4: Start the Daemon

### 4.1 Start Daemon

In a new terminal:

```bash
cd ~/dev/ec4x
./bin/ec4x-daemon start --dataDir data

# Should see:
#   Daemon starting...
#   Data directory: data
#   Poll interval: 30 seconds
#   Discovered game: 550e8400-...
```

### 4.2 Verify Daemon Operation

The daemon:
- Scans `data/games/*/ec4x.db` for active games
- Subscribes to Nostr relay for command events (kind 30402)
- Publishes game state events (kinds 30403, 30405)

---

## Phase 5: Resolve a Turn

### 5.1 Manual Turn Resolution

Since we don't have player clients submitting commands yet, manually
trigger turn resolution:

```bash
./bin/ec4x-daemon resolve --gameId <game-id>

# Should see:
#   Resolving turn for game: <game-id>
#   Loading game state...
#   Turn 1 -> Turn 2
#   Publishing results to Nostr...
#   Resolution complete. Now at turn 2
```

### 5.2 Verify State in Database

```bash
sqlite3 data/games/<game-id>/ec4x.db "SELECT turn FROM games;"
# Output: 2
```

---

## Phase 6: Connect TUI Client

### 6.1 Start TUI

In a new terminal:

```bash
cd ~/dev/ec4x
./bin/ec4x-tui

# TUI will show:
#   - Identity management (import nsec)
#   - Game list
#   - Join game flow
```

### 6.2 Import Test Identity

When prompted, import a test nsec or generate one. The TUI stores
identity at `~/.local/share/ec4x/identity.kdl`.

### 6.3 View Game State

After connecting to a game, the TUI:
- Subscribes to game state events (kind 30405)
- Receives and applies delta events (kind 30403)
- Renders the game map and entity lists

---

## Development Workflow

### Typical Development Cycle

1. **Start relay** (Terminal 1):
   ```bash
   cd ~/dev/nostr-rs-relay
   ./target/release/nostr-rs-relay -c config.toml
   ```

2. **Start daemon** (Terminal 2):
   ```bash
   cd ~/dev/ec4x
   ./bin/ec4x-daemon start
   ```

3. **Run TUI** (Terminal 3):
   ```bash
   cd ~/dev/ec4x
   ./bin/ec4x-tui
   ```

4. **Make changes** - Edit source code

5. **Rebuild** - `nimble buildAll`

6. **Restart** - Kill and restart daemon/TUI

### Quick Reset

To start fresh:

```bash
# Remove all game data
rm -rf data/games/*

# Remove relay data
rm -rf ~/dev/nostr-rs-relay/data/*

# Create new game
./bin/ec4x new --name "Fresh Game"
```

### Debugging Tips

**View relay traffic:**
```bash
websocat ws://localhost:8080
# Then type:
["REQ","debug",{"kinds":[30400,30401,30402,30403,30405]}]
```

**Check game state:**
```bash
sqlite3 data/games/<game-id>/ec4x.db ".schema"
sqlite3 data/games/<game-id>/ec4x.db "SELECT * FROM houses;"
sqlite3 data/games/<game-id>/ec4x.db "SELECT * FROM game_events ORDER BY id DESC LIMIT 10;"
```

**View daemon logs:**
The daemon logs to stdout. Increase verbosity with:
```bash
./bin/ec4x-daemon start --dataDir data 2>&1 | tee daemon.log
```

---

## KDL Message Formats

### Command Packet (Player -> Daemon)

Nostr event kind: **30402**

```kdl
commands house=(HouseId)1 turn=5 {
  // Fleet commands
  fleet (FleetId)123 {
    move to=(SystemId)456 priority=1
  }
  fleet (FleetId)789 hold

  // Build commands
  build (ColonyId)1 {
    ship Destroyer quantity=2
    facility Shipyard
  }

  // Research allocation
  research {
    economic 100
    science 50
    tech {
      weapons 40
      shields 20
    }
  }

  // Diplomacy
  diplomacy {
    declare-hostile target=(HouseId)3
  }

  // Espionage
  espionage {
    invest ebp=200 cip=80
    tech-theft target=(HouseId)2
  }

  // Colony management
  colony (ColonyId)1 {
    tax-rate 60
    auto-repair true
  }
}
```

### Turn Delta (Daemon -> Player)

Nostr event kind: **30403**

```kdl
delta turn=5 game=(GameId)"550e8400-..." {
  // Fleet movements
  fleet-moved id=(FleetId)123 from=(SystemId)100 to=(SystemId)101
  fleet-moved id=(FleetId)456 from=(SystemId)200 to=(SystemId)201

  // Combat results
  combat at=(SystemId)101 {
    attacker house=(HouseId)1 fleet=(FleetId)123
    defender house=(HouseId)2 fleet=(FleetId)789
    result "attacker-victory"
    losses attacker=2 defender=5
  }

  // Colony updates
  colony-updated id=(ColonyId)1 {
    population 850
    industry 430
  }

  // Tech advancement
  tech-advance house=(HouseId)1 field="weapons" level=3

  // Diplomatic changes
  relation-changed from=(HouseId)1 to=(HouseId)3 status="war"

  // Events visible to this house
  events {
    event type="ShipCommissioned" {
      description "Destroyer commissioned at Alpha Prime"
      colony=(ColonyId)1
      ship-class "Destroyer"
    }
    event type="BattleOccurred" {
      description "Battle at Tau Ceti"
      system=(SystemId)101
    }
  }
}
```

### Full State (Daemon -> Player, Initial Sync)

Nostr event kind: **30405**

```kdl
state turn=5 game=(GameId)"550e8400-..." viewing-house=(HouseId)1 {
  // House info
  house id=(HouseId)1 name="House Alpha" {
    treasury 5000
    prestige 250
    eliminated false
  }

  // Owned colonies (full detail)
  colonies {
    colony id=(ColonyId)1 system=(SystemId)10 {
      population 840
      industry 420
      tax-rate 50
      facilities {
        spaceport 1
        shipyard 2
        drydock 1
      }
      ground-units {
        army 10
        marine 5
        ground-battery 3
      }
    }
  }

  // Owned fleets (full detail)
  fleets {
    fleet id=(FleetId)1 location=(SystemId)10 {
      ship id=(ShipId)100 class="Destroyer" hp=10 max-hp=10
      ship id=(ShipId)101 class="Cruiser" hp=15 max-hp=15
    }
  }

  // Visible systems (fog of war filtered)
  systems {
    system id=(SystemId)10 visibility="owned" coords=(q=0 r=0)
    system id=(SystemId)11 visibility="scouted" last-scouted=4 coords=(q=1 r=0)
    system id=(SystemId)12 visibility="adjacent" coords=(q=0 r=1)
  }

  // Enemy intel (what we've observed)
  intel {
    fleet id=(FleetId)999 owner=(HouseId)2 {
      location=(SystemId)20
      detected-turn=4
      estimated-ships=5
    }
    colony id=(ColonyId)99 owner=(HouseId)3 {
      system=(SystemId)30
      intel-turn=3
      estimated-population=500
    }
  }

  // Public information
  prestige-standings {
    house (HouseId)1 prestige=250 colonies=3
    house (HouseId)2 prestige=180 colonies=2
    house (HouseId)3 prestige=200 colonies=3
    house (HouseId)4 prestige=150 colonies=2
  }

  diplomatic-relations {
    relation (HouseId)1 (HouseId)2 status="peace"
    relation (HouseId)1 (HouseId)3 status="war"
  }
}
```

---

## Troubleshooting

### Relay Won't Start

**Port in use:**
```bash
lsof -i :8080
# Kill the process or use a different port
```

**Permission denied:**
```bash
# Ensure data directory exists and is writable
mkdir -p ~/dev/nostr-rs-relay/data
chmod 755 ~/dev/nostr-rs-relay/data
```

### Daemon Can't Connect to Relay

**Relay not running:**
```bash
# Check if relay is running
curl -s http://localhost:8080 || echo "Relay not responding"
```

**Wrong URL:**
Check daemon config for correct relay URL (`ws://localhost:8080`).

### TUI Shows No Games

**Game not created:**
```bash
./bin/ec4x list
# If empty, create a game first
```

**Player not assigned:**
```bash
sqlite3 data/games/<game-id>/ec4x.db "SELECT nostr_pubkey FROM houses;"
# If NULL, assign npubs (see Phase 3.3)
```

### Build Errors

**Missing dependencies:**
```bash
nimble install -y
```

**Nim version too old:**
```bash
choosenim update stable
```

---

## Next Steps

Once your local environment is working:

1. **Develop UI** - Use the TUI as a base, add features
2. **Test commands** - Submit commands via TUI, resolve turns
3. **Implement features** - Add missing Nostr integration pieces
4. **Test against public relay** - Try `wss://relay.damus.io`
5. **Remote Admin** - [Manage via Chat Bot](game-management-chatbot.md)

See also:
- [Nostr Implementation Roadmap](nostr-implementation-roadmap.md)
- [Nostr Protocol Specification](../architecture/nostr-protocol.md)
- [Transport Architecture](../architecture/transport.md)
