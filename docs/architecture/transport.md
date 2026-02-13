# EC4X Transport Layer

## Overview

The transport layer handles communication between players and the game daemon
using the Nostr protocol for decentralized, encrypted messaging.

## Design Philosophy

**Key Principle**: Game engine is transport-agnostic.

The core game logic in `src/engine/` never directly interacts with networking.
Instead, it reads from and writes to SQLite, and the transport layer handles
moving data to/from players via Nostr relays.

## Transport Interface

### Abstract Operations

**For Players (Client):**
- `joinGame(gameId)` → GameInfo
- `submitCommands(commands)` → Confirmation
- `fetchGameState()` → PlayerState
- `fetchTurnHistory(startTurn, endTurn)` → TurnEvents[]

**For Server (Daemon):**
- `discoverGames()` → GameConfig[]
- `listenForCommands(gameId)` → CommandStream
- `publishResults(gameId, deltas)` → PublishStatus
- `publishTurnSummary(gameId, summary)` → PublishStatus

## Nostr Transport

### Design

Event-based transport using Nostr protocol for decentralized, encrypted
communication via WebSocket connections to relays.

### Nostr Primer

**Nostr Basics:**
- Events are signed JSON messages
- Relays store and forward events
- Clients subscribe to event streams via filters
- NIP-44 provides end-to-end encryption

**EC4X Uses:**
- 6 custom event kinds (30400-30405)
- Encrypted private messages (orders, state)
- Public announcements (game metadata)
- Relay infrastructure (no custom server needed)

### Event Kinds

| Kind  | Name             | Direction        | Encryption |
|-------|------------------|------------------|------------|
| 30400 | GameDefinition   | Admin → Public   | None       |
| 30401 | PlayerSlotClaim  | Player → Daemon  | None       |
| 30402 | TurnCommands     | Player → Daemon  | NIP-44     |
| 30403 | TurnResults      | Daemon → Player  | NIP-44     |
| 30404 | JoinError        | Daemon → Player  | None       |
| 30405 | GameState        | Daemon → Player  | NIP-44     |
| 30406 | PlayerMessage    | Player ↔ Daemon  | NIP-44     |

**Defined in:** `src/daemon/transport/nostr/types.nim:67-74`

### Wire Format

All encrypted payloads use a 4-stage encoding pipeline:

```
msgpack binary → zstd compress → NIP-44 encrypt → base64 string
```

**Encoding (sender):**
1. Serialize data to msgpack binary format
2. Compress with zstd for bandwidth efficiency
3. Encrypt with NIP-44 (secp256k1 ECDH + ChaCha20-Poly1305)
4. Encode as base64 string for Nostr event content

**Decoding (receiver):**
1. Decode base64 to encrypted bytes
2. Decrypt with NIP-44 using recipient's private key
3. Decompress with zstd
4. Deserialize msgpack to game structures

**Implementation:** `src/daemon/transport/nostr/wire.nim`

### NostrClient API

The `NostrClient` manages WebSocket connections to multiple relays.

```nim
type NostrClient* = ref object
  relays*: seq[string]
  connections*: Table[string, RelayConnection]
  subscriptions*: Table[string, seq[NostrFilter]]
  onEvent*: EventCallback
  onEose*: EoseCallback
  onOk*: OkCallback
  onNotice*: NoticeCallback
  running*: bool
```

**Core Methods:**

| Method | Description |
|--------|-------------|
| `newNostrClient(relays)` | Create client with relay URLs |
| `connect()` | Connect to all configured relays |
| `disconnect()` | Close all connections |
| `isConnected()` | Check if any relay connected |
| `subscribe(subId, filters)` | Subscribe to event stream |
| `unsubscribe(subId)` | Cancel subscription |
| `publish(event)` | Publish event to all relays |
| `listen()` | Start receiving messages |
| `reconnectWithBackoff(ms, maxMs)` | Reconnect with exponential backoff |

**Convenience Methods:**

| Method | Description |
|--------|-------------|
| `subscribeGame(gameId, playerPubkey)` | Subscribe to game events for player |
| `subscribeDaemon(gameId, daemonPubkey)` | Subscribe to commands for daemon |

**Implementation:** `src/daemon/transport/nostr/client.nim`

### Client Operations

#### Join Game
```
1. Client connects to relay WebSocket
2. Subscribe to EventKindGameDefinition with game_id filter
3. Fetch game metadata (players, rules, status)
4. Subscribe to EventKindGameState/TurnResults for own pubkey
5. Cache state locally in SQLite
```

#### Submit Commands
```
1. Client serializes commands to msgpack
2. Compress with zstd, encrypt to daemon's pubkey using NIP-44
3. Create EventKindTurnCommands (30402) with tags:
   - d: game_id
   - turn: turn_number
   - p: daemon_pubkey
4. Sign event with player's keypair
5. Publish to relay
6. Wait for OK/CLOSED response
```

#### Fetch Game State
```
1. Subscribe to EventKindTurnResults with filters:
   - d: game_id
   - turn: range
   - p: own_pubkey (encrypted to me)
2. Receive delta events from relay
3. Decrypt using NIP-44, decompress with zstd
4. Parse msgpack to PlayerStateDelta
5. Apply deltas to local cached state
```

### Daemon Operations

#### Discover Games
```
1. Daemon connects to configured relays
2. Query SQLite for games where transport_mode = 'nostr'
3. For each game:
   - Extract relay URL from transport_config
   - Validate daemon keypair exists
4. Return list of GameConfig
```

#### Listen for Commands
```
1. Subscribe to EventKindTurnCommands (30402) with filters:
   - d: game_id (for all managed games)
   - p: daemon_pubkey
2. Receive events from relay stream
  3. For each event:
    - Verify signature
    - Decrypt and decompress content
    - Parse msgpack to command structure
    - Validate command packet
    - Insert base64 msgpack packet into commands table
4. Check if all commands received or deadline passed
```

#### Publish Results
```
1. For each house:
   - Query state_deltas for house_id
   - Serialize to msgpack
   - Compress with zstd
   - Encrypt to house's pubkey using NIP-44
   - Create EventKindTurnResults (30403) with tags:
     - d: game_id
     - turn: turn_number
     - p: house_pubkey
   - Sign with daemon's keypair
2. Batch publish to relay
```

### State Deltas

Instead of sending full game state each turn, send only changes:

**Delta Structure (msgpack):**
```nim
type EntityDelta*[T] = object
  added*: seq[T]
  updated*: seq[T]
  removed*: seq[EntityId]

type PlayerStateDelta* = object
  turn*: int
  colonies*: EntityDelta[Colony]
  fleets*: EntityDelta[Fleet]
  ships*: EntityDelta[Ship]
  # ... other entity types
```

**Bandwidth Reduction**: 20-40x smaller than full state.

**Implementation:**
- `src/daemon/transport/nostr/delta_msgpack.nim`
- `src/daemon/transport/nostr/state_msgpack.nim`

### Message Chunking

If delta exceeds relay limits (typically 64 KB):

```nim
type ChunkedMessage = object
  turn: int
  chunk: int        # 1-based chunk number
  total: int        # total chunks
  hash: string      # SHA-256 of complete data
  data: string      # Partial msgpack data
```

Client reassembles chunks before applying.

### Security

#### Encryption (NIP-44)

**Commands (Player → Daemon):**
- Encrypted to daemon's pubkey
- Only daemon can decrypt
- Prevents order snooping

**State (Daemon → Player):**
- Encrypted to each player's pubkey
- Implements fog of war via encryption
- Each player receives different content

**Implementation:** `src/daemon/transport/nostr/crypto.nim`

#### Signing

**All events signed:**
- Prevents impersonation
- Verifiable authenticity
- Relay cannot forge events

#### Trust Model

**Players trust:**
- Daemon to enforce rules correctly
- Relay to deliver messages (not censor)

**Daemon trusts:**
- Players to submit valid commands
- Relay to deliver results

**Mitigation:**
- Open source daemon (verifiable)
- Multiple relay fallbacks
- Command validation on server

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

### Configuration

**transport_config JSON in games table:**
```json
{
  "relay": "wss://relay.damus.io",
  "daemon_pubkey": "npub1abc...",
  "daemon_privkey_path": "/secure/keys/daemon.key",
  "fallback_relays": [
    "wss://relay.nostr.band",
    "wss://nos.lol"
  ],
  "publish_retries": 3,
  "subscription_timeout": 30
}
```

### Advantages

- **Decentralized**: No central server needed
- **Encrypted**: End-to-end privacy via NIP-44
- **Censorship-resistant**: Multiple relays
- **Identity**: Use existing Nostr identity
- **Bandwidth-efficient**: msgpack + zstd + deltas

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

## Module Reference

All transport code lives in `src/daemon/transport/nostr/`:

| Module | Purpose |
|--------|---------|
| `types.nim` | Core types, event kinds, constants |
| `client.nim` | WebSocket client, relay management |
| `wire.nim` | Encoding pipeline (msgpack→zstd→NIP-44→base64) |
| `crypto.nim` | NIP-44 encryption, secp256k1 signing |
| `compression.nim` | zstd compression |
| `delta_msgpack.nim` | PlayerStateDelta serialization |
| `state_msgpack.nim` | Full PlayerState serialization |
| `events.nim` | Event builders for 30400-30405 |
| `nip01.nim` | Basic Nostr protocol (REQ, EVENT, CLOSE) |
| `filter.nim` | NostrFilter builder |

## Implementation Status

- [x] NIP-44 encryption implementation
- [x] WebSocket relay client
- [x] Event parsing and signing
- [x] Filter subscription management
- [x] Command receipt and decryption
- [x] State delta generation
- [x] Delta encryption and publishing
- [x] msgpack serialization
- [x] zstd compression
- [ ] Multi-relay failover
- [ ] Connection resilience / auto-reconnect
- [ ] Rate limiting
- [ ] Comprehensive error recovery
- [ ] Monitoring and metrics

## Future Transports

### WebSocket (Direct)
- Client connects directly to daemon
- Lower latency than Nostr
- Requires port forwarding/VPS

## Related Documentation

- [Architecture Overview](./overview.md)
- [Storage Layer](./storage.md)
- [Nostr Protocol Details](./nostr-protocol.md)
- [Daemon Design](./daemon.md)
