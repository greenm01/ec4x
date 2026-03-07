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
- 8 custom event kinds (30400-30407)
- Encrypted private messages (orders, state)
- Public announcements (game metadata)
- Relay infrastructure (no custom relay protocol needed)

### Event Kinds

| Kind  | Name             | Direction        | Encryption |
|-------|------------------|------------------|------------|
| 30400 | GameDefinition   | Daemon → Public  | None       |
| 30401 | PlayerSlotClaim  | Player → Daemon  | None       |
| 30402 | TurnCommands     | Player → Daemon  | NIP-44     |
| 30403 | TurnResults      | Daemon → Player  | NIP-44     |
| 30404 | JoinError        | Daemon → Player  | NIP-44     |
| 30405 | GameState        | Daemon → Player  | NIP-44     |
| 30406 | PlayerMessage    | Player ↔ Daemon  | NIP-44     |
| 30407 | StateSyncRequest | Player → Daemon  | None       |

**Defined in:** `src/daemon/transport/nostr/types.nim`

### Required Tags by Kind

| Kind | Required tags |
|------|---------------|
| 30400 | `d`, `name`, `status` |
| 30401 | `d`, `code` |
| 30402 | `d`, `turn`, `p` (daemon pubkey) |
| 30403 | `d`, `turn`, `p` (player pubkey) |
| 30404 | `p` (player pubkey) |
| 30405 | `d`, `turn`, `p` (player pubkey) |
| 30406 | `d`, `p`, `from_house`, `to_house` |
| 30407 | `d`, `turn`, `p` (daemon pubkey) |

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
1. Player selects identity (existing wallet key or new local key, max 10)
2. Client connects to relay WebSocket
3. Subscribe to EventKindGameDefinition with game_id filter
4. Fetch game metadata (players, rules, status)
5. Subscribe to `30403` turn results and `30405` full state for the
   selected pubkey
6. Cache state locally in SQLite
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

Normative behavior:

- Clients MAY resubmit `30402` commands for the same turn to revise orders.
- Daemon treats the latest valid packet for `(game_id, house_id, turn)`
  as authoritative.

#### Fetch Game State
```
1. Load the latest cached `PlayerState` snapshot if present
2. Subscribe to `30403` turn results and `30405` full state:
   - `d`: game_id
   - `p`: own_pubkey
3. Receive daemon-signed events from the relay
4. Decrypt using NIP-44, decompress with zstd
5. Parse msgpack to:
   - `PlayerStateDeltaEnvelope` for `30403`
   - `PlayerStateEnvelope` for `30405`
6. Validate config schema/hash against active `TuiRulesSnapshot`
7. Validate `stateHash` integrity:
   - `30405`: recompute hash over full `PlayerState`
   - `30403`: apply delta to a copy and compare post-apply hash
8. Apply deltas or replace local state only if integrity checks pass
```

#### Manual Recovery / Resync
```
1. Player enters `:resync` in expert mode
2. Client re-subscribes the game feed
3. Client publishes `30407` StateSyncRequest to the daemon
4. Daemon validates sender and house membership
5. Daemon republishes `30405` authoritative full state
6. Client replaces same-turn local state with the authoritative snapshot

The TUI also performs this automatically:
- once after loading cached state on startup
- once on integrity mismatch during delta application
```

#### Authoritative Config Flow
```
1. Receive EventKindGameState (30405)
2. Parse PlayerStateEnvelope:
   - playerState
   - authoritativeConfig (TuiRulesSnapshot)
   - stateHash
3. Validate snapshot schema/capabilities/hash
4. Cache snapshot in local SQLite (per game)
5. Materialize runtime rules used by TUI screens/validators
6. Reject future deltas whose config hash/schema do not match snapshot
7. Reject snapshots or deltas whose recomputed `stateHash` does not match
```

#### Draft Restore Gate (Player TUI)
```
1. Load cached CommandPacket draft from order_drafts
2. Require draft.turn == current PlayerState.turn
3. Require draft.config_hash == active TuiRulesSnapshot.configHash
4. Restore staged orders/research only when both checks pass
5. Otherwise discard stale draft
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
1. Subscribe to player events with filters:
   - `30402` TurnCommands
   - `30407` StateSyncRequest
   - `30401` PlayerSlotClaim
   - `30406` PlayerMessage
2. Filter by:
   - `d`: game_id
   - `p`: daemon_pubkey where applicable
3. Receive events from relay stream
4. For `30402`:
   - Verify signature
   - Validate required tags (`d`, `turn`, `p`)
   - Reject if `turn` does not match current game turn
   - Decrypt and decompress content
   - Parse msgpack to `CommandPacket`
   - Upsert packet in commands table by `(game_id, turn, house_id)`
5. For `30407`:
   - Verify signature
   - Resolve sender pubkey to house in that game
   - Republish `30405` full state for that house
6. Check if all commands received or deadline passed
```

Implementation references:

- `src/daemon/daemon.nim` (`processIncomingCommand`)
- `src/daemon/persistence/writer.nim` (`saveCommandPacket`)
- `src/daemon/transport/nostr/client.nim` (`subscribeDaemon`)

#### Publish Results
```
1. For each house:
   - build and publish `30403` turn delta
   - build and publish `30405` authoritative full state
2. Sign both with daemon's keypair
3. Publish both to the relay
```

### State Deltas

Turn refresh uses deltas for efficiency, but each resolved turn now also
publishes a fresh full-state baseline for recovery and resync.

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

type PlayerStateDeltaEnvelope* = object
  delta*: PlayerStateDelta
  configSchemaVersion*: int32
  configHash*: string
  stateHash*: string
```

**Bandwidth Reduction**: 20-40x smaller than full state.

30405 full state uses a `PlayerStateEnvelope` containing:
- `playerState`
- authoritative `TuiRulesSnapshot`
- `stateHash`

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
- Fog-of-war filtering happens before encryption
- Each player receives different content

**Implementation:** `src/daemon/transport/nostr/crypto.nim`

#### Metadata Visibility

Encrypted payloads still expose metadata to relays and observers:

- Event kind
- Tags (`d`, `turn`, `p`, etc.)
- Sender pubkey and timestamp
- Message size and timing

Security guarantee: payload confidentiality, not full metadata secrecy.

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
- Command validation on daemon

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

- **Relay-flexible**: Works with existing Nostr relay infrastructure
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
| `events.nim` | Event builders for 30400-30407 |
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
