# EC4X Transport Layer

## Overview

The transport layer abstracts how orders and game state are communicated between players and the game server. This design allows the same game engine to work with multiple transport modes without modification.

## Design Philosophy

**Key Principle**: Game engine is transport-agnostic.

The core game logic in `src/engine/` never directly interacts with networking or file I/O. Instead, it reads from and writes to SQLite, and the transport layer handles moving that data to/from players.

## Transport Interface

### Abstract Operations

All transport implementations must support these operations:

**For Players (Client):**
- `joinGame(gameId)` → GameInfo
- `submitOrders(orders)` → Confirmation
- `fetchGameState()` → FilteredGameState
- `fetchTurnHistory(startTurn, endTurn)` → TurnEvents[]

**For Server (Daemon):**
- `discoverGames()` → GameConfig[]
- `listenForOrders(gameId)` → OrderStream
- `publishResults(gameId, deltas)` → PublishStatus
- `publishTurnSummary(gameId, summary)` → PublishStatus

## Localhost Transport

### Design

File-based transport using direct filesystem access and SQLite queries.

### Directory Structure

```
/var/ec4x/games/
└── game-123/
    ├── ec4x.db                   # SQLite database
    ├── config.kdl               # Game configuration
    ├── houses/
    │   ├── house_alpha/
    │   │   ├── orders_pending.json
    │   │   └── turn_results/
    │   │       ├── turn_1.json
    │   │       ├── turn_2.json
    │   │       └── ...
    │   └── house_beta/
    │       └── ...
    └── public/
        ├── turn_summaries/
        │   ├── turn_1.txt
        │   └── turn_2.txt
        └── game_log.txt
```

### Client Operations

#### Join Game
```
1. Client receives game directory path
2. Read config.kdl for game metadata
3. Connect to ec4x.db (read-only)
4. Query for house assignment
5. Return GameInfo
```

#### Submit Orders
```
1. Client writes orders as JSON to houses/<house>/orders_pending.json
2. Optionally validate against schema
3. Return confirmation (file write success)
```

#### Fetch Game State
```
1. Client queries ec4x.db with house_id filter
2. Read intel tables for visibility
3. Construct filtered GameState
4. Return to player
```

### Daemon Operations

#### Discover Games
```
1. Scan configured game directories
2. For each directory with ec4x.db:
   - Read games table
   - Filter by phase = 'Active'
   - Load transport_config
3. Return list of GameConfig
```

#### Listen for Orders
```
1. Poll houses/*/orders_pending.json every N seconds
2. When file found:
   - Parse JSON
   - Validate against schema
   - Insert into orders table
   - Delete orders_pending.json
3. Check if all orders received or deadline passed
```

#### Publish Results
```
1. For each house:
   - Query state_deltas for house_id
   - Generate filtered GameState
   - Write to houses/<house>/turn_results/turn_N.json
2. Update updated_at timestamp
```

#### Publish Turn Summary
```
1. Generate public summary (no fog of war)
2. Write to public/turn_summaries/turn_N.txt
3. Append to public/game_log.txt
```

### Configuration

**config.kdl:**
```toml
[game]
id = "game-123"
name = "Test Game"
mode = "localhost"

[transport]
type = "localhost"
poll_interval = 30  # seconds

[houses]
[[houses.players]]
id = "house-alpha"
name = "House Alpha"
```

### Advantages

- **Simple**: No network complexity
- **Fast**: No latency
- **Debuggable**: Inspect files directly
- **Portable**: Copy directory = copy game
- **Offline**: No internet required

### Disadvantages

- **Manual sync**: Players must manually share directory
- **No remote play**: Requires shared filesystem
- **Limited security**: Players can access SQLite directly

### Use Cases

- Local testing and development
- Hotseat multiplayer
- Offline AI testing
- Rapid iteration

## Nostr Transport

### Design

Event-based transport using Nostr protocol for decentralized, encrypted communication.

### Nostr Primer

**Nostr Basics:**
- Events are signed JSON messages
- Relays store and forward events
- Clients subscribe to event streams via filters
- NIP-44 provides end-to-end encryption

**EC4X Uses:**
- 6 custom event kinds (30001-30006)
- Encrypted private messages (orders, state)
- Public announcements (turn summaries)
- Relay infrastructure (no custom server needed)

### Event Kinds

See [EC4X-Nostr-Events.md](../EC4X-Nostr-Events.md) for complete spec.

**Summary:**
- `30001` OrderPacket: Player → Moderator (encrypted)
- `30002` GameState: Moderator → Player (encrypted)
- `30003` TurnComplete: Moderator → Public
- `30004` GameMeta: Game lobby/config (public)
- `30005` Diplomacy: Player → Player (encrypted)
- `30006` Spectate: Public spectator feed

### Client Operations

#### Join Game
```
1. Client connects to relay WebSocket
2. Subscribe to EventKindGameMeta with game_id filter
3. Fetch game metadata (players, rules, status)
4. Subscribe to EventKindGameState/StateDelta for own pubkey
5. Cache state locally in SQLite
```

#### Submit Orders
```
1. Client serializes orders to JSON
2. Encrypt to moderator's pubkey using NIP-44
3. Create EventKindOrderPacket with tags:
   - g: game_id
   - h: house_name
   - t: turn
   - p: moderator_pubkey
4. Sign event with player's keypair
5. Publish to relay
6. Wait for OK/CLOSED response
```

#### Fetch Game State
```
1. Subscribe to EventKindStateDelta with filters:
   - game_id
   - turn range
   - p: own_pubkey (encrypted to me)
2. Receive delta events from relay
3. Decrypt using NIP-44
4. Apply deltas to local cached state
5. Return filtered GameState
```

### Daemon Operations

#### Discover Games
```
1. Daemon connects to configured relays
2. Query SQLite for games where transport_mode = 'nostr'
3. For each game:
   - Extract relay URL from transport_config
   - Validate moderator keypair exists
4. Return list of GameConfig
```

#### Listen for Orders
```
1. Subscribe to EventKindOrderPacket with filters:
   - kind: 30001
   - g: game_id (for all managed games)
   - p: moderator_pubkey
2. Receive events from relay stream
3. For each event:
   - Verify signature
   - Decrypt content with moderator's private key
   - Validate order packet
   - Insert into orders table
   - Cache event in nostr_events table
4. Check if all orders received or deadline passed
```

#### Publish Results
```
1. For each house:
   - Query state_deltas for house_id
   - Serialize to JSON
   - Encrypt to house's pubkey using NIP-44
   - Create EventKindStateDelta with tags:
     - g: game_id
     - h: house_name
     - t: turn
     - p: house_pubkey
   - Sign with moderator's keypair
   - Add to nostr_outbox queue
2. Batch publish to relay
3. Mark sent in nostr_outbox
```

#### Publish Turn Summary
```
1. Generate public turn summary (no secrets)
2. Create EventKindTurnComplete with tags:
   - g: game_id
   - t: turn
   - phase: turn_phase
3. Sign with moderator's keypair
4. Publish to relay (unencrypted)
```

### Configuration

**transport_config JSON in games table:**
```json
{
  "relay": "wss://relay.damus.io",
  "moderator_pubkey": "npub1abc...",
  "moderator_privkey_path": "/secure/keys/mod.key",
  "fallback_relays": [
    "wss://relay.nostr.band",
    "wss://nos.lol"
  ],
  "publish_retries": 3,
  "subscription_timeout": 30
}
```

### Bandwidth Optimization

#### State Deltas

Instead of sending full game state each turn, send only changes:

**Full State** (turn 1 or resync):
```json
{
  "type": "full_state",
  "turn": 1,
  "colonies": [...],  // All data
  "fleets": [...],
  "systems": [...]
}
```

**Delta** (normal turns):
```json
{
  "type": "delta",
  "turn": 42,
  "deltas": [
    {"type": "fleet_moved", "id": "fleet-1", "from": "sys-A", "to": "sys-B"},
    {"type": "ship_damaged", "id": "ship-5", "hp": 8},
    {"type": "colony_updated", "id": "col-3", "industry": 12}
  ]
}
```

**Bandwidth Reduction**: 20-40x smaller than full state.

#### Message Chunking

If delta exceeds 32 KB:

```json
{
  "type": "delta_chunk",
  "turn": 42,
  "chunk": 1,
  "total": 3,
  "hash": "sha256...",  // For verification
  "data": "..." // Partial delta
}
```

Client reassembles chunks before applying.

**Tags for chunking:**
- `chunk`: 1-based chunk number
- `total`: total chunks
- `hash`: SHA-256 of complete data

### Security

#### Encryption (NIP-44)

**Orders (Player → Moderator):**
- Encrypted to moderator's pubkey
- Only moderator can decrypt
- Prevents order snooping

**State (Moderator → Player):**
- Encrypted to each player's pubkey
- Implements fog of war via encryption
- Each player receives different content

#### Signing

**All events signed:**
- Prevents impersonation
- Verifiable authenticity
- Relay cannot forge events

#### Trust Model

**Players trust:**
- Moderator to enforce rules correctly
- Relay to deliver messages (not censor)

**Moderator trusts:**
- Players to submit valid orders
- Relay to deliver results

**Mitigation:**
- Open source daemon (verifiable)
- Multiple relay fallbacks
- Order validation on server

### Relay Selection

**Considerations:**
- Latency (geographic proximity)
- Reliability (uptime)
- Limits (message size, rate limits)
- Censorship resistance (multiple relays)

**Recommended Setup:**
- Primary relay: low latency
- 2-3 fallback relays
- Monitor relay health in daemon

### Advantages

- **Decentralized**: No central server
- **Encrypted**: End-to-end privacy
- **Censorship-resistant**: Multiple relays
- **Identity**: Use existing Nostr identity
- **Bandwidth-efficient**: Delta-based sync

### Disadvantages

- **Complexity**: Encryption, key management
- **Latency**: Relay network adds delays
- **Reliability**: Depends on relay uptime
- **Size limits**: Large games may need chunking

### Use Cases

- Online multiplayer
- Play-by-relay async gaming
- Privacy-focused play
- Distributed tournaments

## Transport Comparison

| Feature | Localhost | Nostr |
|---------|-----------|-------|
| **Setup Complexity** | Simple | Moderate |
| **Network Required** | No | Yes |
| **Latency** | Instant | 100-1000ms |
| **Bandwidth** | N/A | Low (deltas) |
| **Security** | Filesystem ACLs | NIP-44 encryption |
| **Privacy** | Local only | End-to-end encrypted |
| **Scalability** | Single machine | Global |
| **Debugging** | Easy (inspect files) | Moderate (event logs) |
| **Use Case** | Development, hotseat | Online multiplayer |

## Implementation Roadmap

### Phase 1: Localhost (Complete)
- [x] File-based order submission
- [x] SQLite state storage
- [x] Directory structure
- [ ] Daemon polling loop
- [ ] Result export

### Phase 2: Nostr Foundation
- [ ] NIP-44 encryption implementation
- [ ] WebSocket relay client
- [ ] Event parsing and signing
- [ ] Filter subscription management

### Phase 3: Nostr Integration
- [ ] Order receipt and decryption
- [ ] State delta generation
- [ ] Delta encryption and publishing
- [ ] Chunk handling

### Phase 4: Production Hardening
- [ ] Multi-relay support
- [ ] Connection resilience
- [ ] Rate limiting
- [ ] Error recovery
- [ ] Monitoring and metrics

## Future Transports

### WebSocket (Direct)
- Client connects directly to daemon
- Lower latency than Nostr
- Requires port forwarding/VPS

### Discord Bot
- Orders via Discord DM
- Results posted to channels
- Accessible to Discord users

### Email
- Ultra-slow async play
- Orders via email attachment
- Results via email reply

### Matrix Protocol
- Federated messaging
- Similar to Nostr approach
- Different encryption (Olm/Megolm)

## Related Documentation

- [Architecture Overview](./overview.md)
- [Storage Layer](./storage.md)
- [Nostr Events](../EC4X-Nostr-Events.md)
- [Nostr Implementation](../EC4X-Nostr-Implementation.md)
- [Daemon Design](./daemon.md)
