# EC4X Nostr Protocol

This document specifies how EC4X uses the Nostr protocol for game
coordination, state synchronization, and player communication.

## Overview

EC4X uses a daemon + relay architecture where the daemon is the
authoritative game engine and Nostr is the transport layer for:

- Game discovery and invitations
- Player identity and authentication
- Turn order submission
- Game state synchronization

```
┌─────────────────────────────────────────────────────────────┐
│                      EC4X RELAY                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Nostr Relay │─>│ Game Engine │─>│ Database (SQLite)   │  │
│  │  (NIP-01)   │  │    (Nim)    │  │   Authoritative     │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                           ▲
                           │ wss://
           ┌───────────────┼───────────────┐
           │               │               │
       ┌───┴───┐       ┌───┴───┐       ┌───┴───┐
       │ Admin │       │ Admin │       │Player │
       └───────┘       └───────┘       └───────┘
```

The daemon database is the authoritative source of game state. Nostr
events are used for real-time updates and client-server communication,
not as the primary data store.

---

## Normative Constants and Invariants

The rules in this section are normative. Later sections and examples
must be interpreted to match these rules.

### Core Invariants

- The daemon is the authoritative source of game state.
- Nostr relays transport events but are not authoritative state.
- Clients MUST validate daemon-signed authoritative events
  (`30400`, `30403`, `30404`, `30405`).
- Clients MUST treat malformed `turn` tags as invalid for
  turn-scoped events.

### Canonical Event Kinds

| Kind | Name | Publisher | Encryption |
|------|------|-----------|------------|
| 30400 | Game Definition | Daemon/Admin | None |
| 30401 | Player Slot Claim | Player | None |
| 30402 | Turn Commands | Player | NIP-44 |
| 30403 | Turn Results | Daemon | NIP-44 |
| 30404 | Join Error | Daemon | NIP-44 |
| 30405 | Game State | Daemon | NIP-44 |
| 30406 | Player Message | Player/Daemon | NIP-44 |

### Required Tags by Event Kind

| Kind | Required tags |
|------|---------------|
| 30400 | `d`, `name`, `status` |
| 30401 | `d`, `code` |
| 30402 | `d`, `turn`, `p` (daemon pubkey) |
| 30403 | `d`, `turn`, `p` (player pubkey) |
| 30404 | `p` (player pubkey) |
| 30405 | `d`, `turn`, `p` (player pubkey) |
| 30406 | `d`, `p`, `from_house`, `to_house` |

### Canonical Wire Pipeline

All encrypted payloads (`30402`, `30403`, `30404`, `30405`, `30406`)
MUST use:

```
msgpack binary -> zstd compress -> NIP-44 encrypt -> base64 encode
```

### Security Boundary (Confidentiality vs Metadata)

NIP-44 protects payload contents, but relay-visible metadata remains:

- Event kind (`kind`)
- Tags (`d`, `turn`, `p`, etc.)
- Sender pubkey (`pubkey`)
- Event timestamp (`created_at`)
- Message size and timing patterns

Therefore, EC4X guarantees payload confidentiality, not metadata
confidentiality.

---

## Roles & Permissions

### Role Definitions

| Role | Title | Description |
|------|-------|-------------|
| Sysop | Relay Sysop | Runs the server, grants Admin privileges |
| Admin | Game Admin | Creates and manages games |
| Player | Player | Joins games, submits orders |

### Permission Matrix

| Action | Player | Admin | Sysop |
|--------|--------|-------|-------|
| Join game with invite code | Y | Y | Y |
| View/play own games | Y | Y | Y |
| Submit orders | Y | Y | Y |
| Create game | - | Y | Y |
| Reissue invite code | - | Own games | Any game |
| Start game | - | Own games | Any game |
| Delete/cancel game | - | Own games | Any game |
| Grant Admin role | - | - | Y |
| Revoke Admin role | - | - | Y |
| Server maintenance | - | - | Y |

### Notes

- An Admin can also be a Player in their own game
- Each game has a single Admin (the creator)
- Sysop grants Admin privileges via CLI

---

## Binaries

| Binary | Location | Role | Description |
|--------|----------|------|-------------|
| `ec4x-player` | User machine | Player/Admin | TUI client with role-based UI |
| `ec4x-daemon` | Server | - | Nostr relay + game engine + persistence |
| `ec4x` | Server | Sysop | CLI tool for sysop tasks |

The `ec4x-player` binary serves both Players and Admins. The UI adapts
based on the user's npub privileges:

- Players see: game list, invite code input
- Admins see: game list, invite code input, game management menu

---

## Identity

### Storage

Player identities are stored locally in a wallet at (max 10 identities):

```
~/.local/share/ec4x/wallet.kdl
```

Format:

```kdl
wallet active="0"
identity nsec="nsec1..." type="local" created="2026-01-17T12:00:00Z"
identity nsec="nsec1..." type="imported" created="2026-01-21T09:35:00Z"
```

Compatibility mirror:

```
~/.local/share/ec4x/identity.kdl
```

When wallet encryption is disabled, the active wallet identity is mirrored
to `identity.kdl` for older tools that still expect a single identity file.
When wallet encryption is enabled, `identity.kdl` is not written.

### Player Message (30406)

```kdl
message game="550e8400-e29b-41d4-a716-446655440000" {
  from-house 1
  to-house 2        # 0 = broadcast
  text "Meet at Tau Ceti."
  timestamp 1705500300
}
```

**Tags:**
- `d`: game id
- `p`: recipient pubkey (daemon on send, player on forward)
- `from_house`: sender house id
- `to_house`: recipient house id (0 for broadcast)

### Identity Types

| Type | Description |
|------|-------------|
| `local` | Auto-generated by client on first launch |
| `imported` | User imported their own Nostr secret key |

### Identity Input Rules

The TUI supports both modes:

- Create a new local keypair (`local`)
- Import an existing player key (`imported`)

Accepted import formats:

- Bech32 secret key (`nsec1...`)
- 64-char hex secret key

### First Launch Flow

```
┌─────────────────────────────────────────────────────────────┐
│ No wallet found.                                            │
│                                                             │
│ A new local identity has been created for you.              │
│ npub1abc...xyz                                              │
│                                                             │
│ Press [I] to import your key, [N] to create another key.    │
└─────────────────────────────────────────────────────────────┘
```

Players can import an existing key if they want to use their Nostr
identity across clients or other Nostr applications. Players can cycle
stored identities and choose which pubkey to use before joining/loading
games.

---

## Invite Codes

Games are invitation-only. Players join by entering an invite code
provided by the Game Admin.

### Format

Invite codes consist of two words from the Monero mnemonic wordlist,
hyphenated and lowercase. Codes may optionally include a relay URL:

**Basic format:** `code` or `code@host[:port]`

```
velvet-mountain                      # Bare code, uses default relay
velvet-mountain@play.ec4x.io         # Code with relay (wss port 443)
velvet-mountain@play.ec4x.io:8080    # Code with custom port
velvet-mountain@localhost:8080       # Local relay (ws port 8080)
```

**TLS detection (automatic):**
- Localhost, 127.0.0.1, 192.168.*, 10.*, 172.16-31.* -> `ws://`
- All other hosts -> `wss://`

When admin tooling generates invite codes, it includes the relay URL:

```bash
$ ec4x invite friday-night
House 1: velvet-mountain@play.ec4x.io
House 2: copper-sunrise@play.ec4x.io
```

**Implementation:** `src/common/invite_code.nim`

The wordlist contains 1626 words, giving ~2.6 million combinations.
This is sufficient entropy for private invite codes that are not
brute-forced.

### Invite Code Lifecycle

```
┌──────────────┐    player claims    ┌──────────────┐
│   PENDING    │ ──────────────────► │   CLAIMED    │
│  (no npub)   │    with npub        │ (bound npub) │
└──────────────┘                     └──────────────┘
       │                                    │
       │ admin                              │ admin
       │ deletes slot                       │ reissues
       ▼                                    ▼
┌──────────────┐                     ┌──────────────┐
│   DELETED    │                     │   PENDING    │
│              │                     │ (new code)   │
└──────────────┘                     └──────────────┘
```

### Security Model

- Invite codes are **bearer tokens**: whoever presents one first claims
  the slot
- Codes should be shared **privately** (DM, email) not publicly
- Once claimed, the code is bound to that npub permanently
- If a player loses their identity, the Admin reissues a new code

### Reissue Flow

When an Admin reissues a code:

1. The old code becomes invalid
2. A new code is generated for that slot
3. The slot's npub binding is cleared
4. The player can claim with their new npub

```bash
# Sysop CLI (or Admin via TUI)
$ ec4x game reissue friday-night --slot 2
Slot 2 reset. New invite code: amber-cascade
```

---

## Game Lifecycle

### States

```
SETUP ──────────► ACTIVE ──────────► FINISHED
        Admin            Game ends
        starts           (victory or
        game             concession)
```

| State | Description |
|-------|-------------|
| `SETUP` | Game created, waiting for players to claim slots |
| `ACTIVE` | Game in progress, turns being resolved |
| `FINISHED` | Game complete, winner determined |

### Creation Flow

1. Admin creates game (via TUI)
2. Daemon generates invite codes for each slot
3. Admin shares codes privately with players
4. Players claim slots by entering codes
5. Admin starts game when ready

### House Assignment

Houses are assigned randomly when a player claims their slot. There
are 12 possible house names (fixed list, no custom names to prevent
abuse).

---

## Nostr Event Kinds

EC4X uses the 304xx range for parameterized replaceable events.

| Kind | Name | Publisher | Description |
|------|------|-----------|-------------|
| 30400 | Game Definition | Daemon | Game metadata, slot status |
| 30401 | Player Slot Claim | Player | Player claims invite code |
| 30402 | Turn Orders | Player | Player's orders for a turn |
| 30403 | Turn Results | Daemon | Delta from turn resolution |
| 30404 | Join Error | Daemon | Slot-claim failure reason |
| 30405 | Game State | Daemon | Full current state |
| 30406 | Player Message | Player/Daemon | Player messaging |

Daemon pubkey is authoritative for `30400`, `30403`, `30404`,
and `30405`.

### 30400: Game Definition

Published by the daemon when creating or updating a game.

```json
{
  "kind": 30400,
  "pubkey": "<daemon-npub>",
  "created_at": 1705500000,
  "tags": [
    ["d", "<game-id>"],
    ["name", "Friday Night Game"],
    ["status", "setup"],
    ["slot", "1", "<invite-code-hash>", "", "pending"],
    ["slot", "2", "<invite-code-hash>", "", "pending"],
    ["slot", "3", "<invite-code-hash>", "<player-npub>", "claimed"],
    ["slot", "4", "<invite-code-hash>", "", "pending"]
  ],
  "content": "{\"name\": \"Friday Night Game\", \"slots\": 4, \"claimed\": 1}",
  "sig": "..."
}
```

**Tag definitions:**

- `d`: Unique game identifier
- `name`: Human-readable game name
- `status`: `setup`, `active`, or `finished`
- `slot`: `[index, invite-code-hash, npub-or-empty, status]`

Invite codes are normalized (lowercase, trimmed) before hashing with SHA-256.

Invite codes are stored as hashes to prevent leaking codes in public
events. The daemon validates the actual code on claim.

### 30401: Player Slot Claim

Published by Player when claiming an invite code.

```json
{
  "kind": 30401,
  "pubkey": "<player-npub>",
  "created_at": 1705500100,
  "tags": [
    ["d", "<game-id>"],
    ["code", "<invite-code>"]
  ],
  "content": "",
  "sig": "..."
}
```

The daemon validates:

1. Code exists and is pending
2. Code not already claimed
3. Binds player npub to slot
4. Assigns random house
5. Updates game definition (30400)

### 30402: Turn Commands

Published by Player when submitting commands for a turn.

```json
{
  "kind": 30402,
  "pubkey": "<player-npub>",
  "created_at": 1705500200,
  "tags": [
    ["d", "<game-id>"],
    ["turn", "5"],
    ["p", "<daemon-npub>"]
  ],
  "content": "<encrypted-compressed-msgpack>",
  "sig": "..."
}
```

The content field contains: `base64(NIP-44-encrypt(zstd-compress(msgpack)))`

Normative behavior:

- Player MUST set tags `d`, `turn`, and `p` (daemon pubkey).
- Daemon MUST verify event signature before processing.
- Daemon MUST reject packets with missing/non-numeric `turn`.
- Daemon MUST reject packets not matching the current game turn.
- Players MAY resubmit `30402` for the same game/turn to revise orders.
- Daemon MUST store the latest valid submission for
  `(game_id, house_id, turn)` as authoritative.

See [Payload Formats](#payload-formats) for the msgpack structure.

Implementation references:

- `src/daemon/daemon.nim` (`processIncomingCommand`)
- `src/daemon/persistence/writer.nim` (`saveCommandPacket`)
- `src/daemon/transport/nostr/events.nim` (`createTurnCommands`)

### 30403: Turn Results

Published by Daemon after resolving a turn. One event per player,
encrypted to that player's pubkey. Clients must ignore events with
missing or non-numeric turn tags and treat the newest turn as authoritative.

```json
{
  "kind": 30403,
  "pubkey": "<daemon-npub>",
  "created_at": 1705500300,
  "tags": [
    ["d", "<game-id>"],
    ["turn", "5"],
    ["p", "<player-npub>"]
  ],
  "content": "<encrypted-compressed-msgpack>",
  "sig": "..."
}
```

The content field contains: `base64(NIP-44-encrypt(zstd-compress(msgpack)))`

The delta contains only the changes from this turn, filtered by fog of
war for the target player. Clients apply deltas to their local state.

In the current implementation, the msgpack payload is a
`PlayerStateDeltaEnvelope`:

- `delta`: the `PlayerStateDelta`
- `configSchemaVersion`: authoritative rules schema version
- `configHash`: hash of the active `TuiRulesSnapshot`

Clients must reject deltas whose schema or hash do not match the active
rules snapshot from the most recent 30405 full-state payload.

See [Payload Formats](#payload-formats) for the msgpack structure.

Implementation references:

- `src/daemon/transport/nostr/events.nim` (`createTurnResults`)
- `src/daemon/transport/nostr/delta_msgpack.nim`

### 30404: Join Error

Published by Daemon when a slot-claim attempt fails validation.

```json
{
  "kind": 30404,
  "pubkey": "<daemon-npub>",
  "created_at": 1705500150,
  "tags": [
    ["p", "<player-npub>"]
  ],
  "content": "<encrypted-error-message>",
  "sig": "..."
}
```

Normative behavior:

- Content MUST be encrypted with the canonical pipeline.
- `p` MUST identify the intended recipient player pubkey.
- Clients MUST only accept join errors from the authoritative daemon pubkey.

Implementation references:

- `src/daemon/publisher.nim` (`publishJoinError`)
- `src/daemon/transport/nostr/events.nim` (`createJoinError`)

### 30405: Game State

Published by Daemon, contains full current game state for a player.
Encrypted to that player's pubkey with fog-of-war filtering. Clients must
ignore events with missing or non-numeric turn tags and treat the newest
turn as authoritative.

```json
{
  "kind": 30405,
  "pubkey": "<daemon-npub>",
  "created_at": 1705500300,
  "tags": [
    ["d", "<game-id>"],
    ["turn", "5"],
    ["p", "<player-npub>"]
  ],
  "content": "<encrypted-compressed-msgpack>",
  "sig": "..."
}
```

The content field contains: `base64(NIP-44-encrypt(zstd-compress(msgpack)))`

In the current implementation, the msgpack payload is a
`PlayerStateEnvelope`:

- `playerState`: fog-of-war filtered `PlayerState`
- `authoritativeConfig`: sectioned `TuiRulesSnapshot`
  (`schemaVersion`, `configHash`, section versions, capabilities,
  optional sections)

Clients request this when:

- First connecting to a game
- Local state is corrupted or missing
- Manual resync requested

See [Payload Formats](#payload-formats) for the msgpack structure.

Implementation references:

- `src/daemon/transport/nostr/events.nim` (`createGameState`)
- `src/daemon/transport/nostr/state_msgpack.nim`

### Authoritative TUI Rules Snapshot

The daemon is authoritative for gameplay config values used by player
clients. The player TUI does not load local gameplay KDL files.

`TuiRulesSnapshot` is delivered in 30405 full-state events and cached by
the TUI per game. It is intentionally sectioned and forward-compatible:

- `schemaVersion`: top-level snapshot schema
- `configHash`: integrity hash over snapshot contents
- `capabilities`: feature capability strings (`rd.v1`, `build.v1`, etc.)
- Section versions: `techVersion`, `shipsVersion`, `groundUnitsVersion`,
  `facilitiesVersion`, `constructionVersion`, `limitsVersion`,
  `economyVersion`
- Optional sections: `tech`, `ships`, `groundUnits`, `facilities`,
  `construction`, `limits`, `economy`

Client behavior:

- Apply full state only if `schemaVersion`, required capabilities, and
  hash validation pass.
- Reject 30403 deltas when envelope `configHash` or
  `configSchemaVersion` differs from active snapshot.
- Remain in lobby/loading state until a valid authoritative snapshot is
  available.

---

## Wire Format

All encrypted payloads use this format:

```
msgpack binary -> zstd compress -> NIP-44 encrypt -> base64 encode
```

**Encoding (sender):**
1. Serialize game data to msgpack binary
2. Compress with zstd
3. Encrypt with NIP-44 to recipient's pubkey
4. Base64 encode for Nostr content field

**Decoding (receiver):**
1. Base64 decode content field
2. Decrypt with NIP-44 using own private key
3. Decompress with zstd
4. Deserialize msgpack binary

**Implementation:** `src/daemon/transport/nostr/wire.nim`

Supporting modules:

- `src/daemon/transport/nostr/compression.nim`
- `src/daemon/transport/nostr/crypto.nim`

---

## Message Flows

### Player Joins Game

```
Player                              Daemon
   │                                   │
   │  EVENT 30401 (claim code)         │
   ├──────────────────────────────────►│
   │                                   │ Validate code
   │                                   │ Bind npub to slot
   │                                   │ Assign house
   │                                   │
   │  EVENT 30400 (updated game def)   │
   │◄──────────────────────────────────┤
   │                                   │
   │  REQ {"kinds":[30405],            │
   │       "#d":["<game-id>"]}         │
   ├──────────────────────────────────►│
   │                                   │
   │  EVENT 30405 (full state)         │
   │◄──────────────────────────────────┤
```

### Player Submits Orders

```
Player                              Daemon
   │                                   │
   │  EVENT 30402 (turn orders)        │
   ├──────────────────────────────────►│
   │                                   │ Validate orders
   │                                   │ Store in DB
   │  OK                               │
   │◄──────────────────────────────────┤
```

### Turn Resolution

```
Daemon                              All Players
   │                                   │
   │ (all orders received or timeout)  │
   │                                   │
   │ Run game engine                   │
   │ Calculate deltas                  │
   │                                   │
   │  EVENT 30403 (turn results)       │
   ├──────────────────────────────────►│
   │                                   │ Apply delta
   │                                   │ Update UI
```

### State Recovery

```
Player                              Daemon
   │                                   │
   │  REQ {"kinds":[30405],            │
   │       "#d":["<game-id>"]}         │
   ├──────────────────────────────────►│
   │                                   │
   │  EVENT 30405 (full state)         │
   │◄──────────────────────────────────┤
   │                                   │
   │  REQ {"kinds":[30403],            │
   │       "#d":["<game-id>"],         │
   │       "since":<last-event-time>}  │
   ├──────────────────────────────────►│
   │                                   │
   │  (subscribe to future deltas)     │
   │◄─────────────────────────────────►│
```

### Player Messages

```
Player A                              Daemon                           Player B
   │                                   │                                 │
   │  EVENT 30406 (message)            │                                 │
   │  encrypted to daemon              │                                 │
   ├──────────────────────────────────►│ Validate sender/recipient        │
   │                                   │ Persist message                 │
   │                                   │                                 │
   │                                   │  EVENT 30406 (forward)           │
   │                                   │  encrypted to player             │
   │                                   ├────────────────────────────────►│
   │                                   │                                 │
   │                                   │  EVENT 30406 (echo)              │
   │                                   │  encrypted to sender             │
   │◄──────────────────────────────────┤                                 │
```

30406 events are encrypted with NIP-44 and routed through the daemon. The daemon
validates that both houses are in the game, applies rate limits, stores the
message, and forwards it to the recipient. The sender receives an echoed copy
as delivery confirmation.

---

## Client Entry Screen

When a player opens the TUI client:

```
┌─────────────────────────────────────────────────────────────┐
│                         E C 4 X                             │
│                                                             │
│  IDENTITY ────────────────────────────────────────────────  │
│  npub1abc...xyz (local) [1/2]                               │
│                  [I] Import key  [N] New key [Tab] Cycle    │
│                                                             │
│  YOUR GAMES ──────────────────────────────────────────────  │
│  ► Friday Night          T5    House Valdez                 │
│    Saturday Showdown     T1    House Kirin                  │
│                                                             │
│  JOIN GAME ───────────────────────────────────────────────  │
│  Enter invite code: [____________]                          │
│                                                             │
│  [Up/Dn] Select [Enter] Play [I] Import [Tab] ID [N] New    │
└─────────────────────────────────────────────────────────────┘
```

If the player has Admin privileges, they also see:

```
│  ADMIN ───────────────────────────────────────────────────  │
│  ► Create New Game                                          │
│    Manage My Games (2)                                      │
```

---

## Security Considerations

### Invite Codes

- Codes are bearer tokens; treat them like passwords
- Share privately (DM, email), never in public channels
- Codes are hashed in public events to prevent leakage
- Rate-limit code claim attempts to prevent brute-force

### Identity

- Private keys (nsec) never leave the client
- All events are signed with the player's key
- Daemon verifies signatures on all events

### Daemon Authority

- The daemon is the authoritative source of game state
- Clients should validate daemon-signed events
- The daemon npub should be well-known and verifiable

### Metadata Visibility

NIP-44 encrypts payload content, but relays still observe:

- Event kind
- Tags (`d`, `turn`, `p`, etc.)
- Sender pubkey and timestamp
- Message size and timing

Design assumption: EC4X protects payload contents, not all metadata.

### Fog of War

- Turn results (30403) contain only information visible to each player
- Or: separate events per player with encrypted content
- Full state (30405) is player-specific (filtered by visibility)

---

## Future Considerations

### Multiple Relays

The current design assumes a single central relay. Future versions
could support:

- Relay redundancy (multiple relays, same data)
- Federated games (different games on different relays)
- Relay discovery via NIP-65

### Encrypted Events

For games requiring hidden information:

- Use NIP-44 for encrypted payloads
- Per-player encrypted turn results
- Encrypted order submission

### Spectator Mode

- Read-only access to game state
- Could use a separate "spectator" invite code type
- Delayed state (fog of war for spectators)

---

## Payload Formats

Event payloads are serialized to msgpack for wire transmission. This section
documents the logical structure of commands, deltas, and full state.

**Note:** Players write commands in KDL format locally. The client parses
KDL and serializes to msgpack before encryption and transmission.

### Command Packet (30402)

Player commands submitted each turn. Written in KDL, serialized to msgpack.

```kdl
commands house=(HouseId)1 turn=5 {
  // Fleet commands - movement, combat, colonization
  fleet (FleetId)123 {
    move to=(SystemId)456 priority=1 roe=3
  }
  fleet (FleetId)789 hold
  fleet (FleetId)101 {
    colonize at=(SystemId)200
  }
  fleet (FleetId)102 {
    patrol from=(SystemId)10 to=(SystemId)20
  }
  fleet (FleetId)103 {
    join-fleet target=(FleetId)123
  }

  // Build commands - ships, facilities, ground units
  build (ColonyId)1 {
    ship Destroyer quantity=2
    ship Cruiser quantity=1
    facility Shipyard
    ground Marine quantity=5
    industrial units=10
  }

  // Scrap commands - salvage entities for PP
  scrap (ColonyId)1 {
    ship (ShipId)99 acknowledge-queue-loss=false
    ground-unit (GroundUnitId)50
  }

  // Research allocation
  research {
    economic 100
    science 50
    tech {
      weapons 40
      shields 20
      construction 10
    }
  }

  // Diplomacy
  diplomacy {
    declare-hostile target=(HouseId)3
    propose-alliance target=(HouseId)2
    accept-proposal id=(ProposalId)5
  }

  // Espionage
  espionage {
    invest ebp=200 cip=80
    tech-theft target=(HouseId)2
    sabotage-high target=(HouseId)3 system=(SystemId)50
  }

  // Population transfers
  transfer from=(ColonyId)1 to=(ColonyId)2 ptu=50

  // Terraforming
  terraform colony=(ColonyId)3

  // Colony management
  colony (ColonyId)1 {
    tax-rate 60
    auto-repair true
    auto-load-fighters true
    auto-load-marines false
  }
}
```

### Turn Delta (30403)

State changes from turn resolution, filtered by fog of war.

```kdl
delta turn=5 game="550e8400-e29b-41d4-a716-446655440000" {
  // Fleet movements visible to this house
  fleet-moved id=(FleetId)123 from=(SystemId)100 to=(SystemId)101
  fleet-moved id=(FleetId)456 from=(SystemId)200 to=(SystemId)201

  // Fleet destroyed
  fleet-destroyed id=(FleetId)789 at=(SystemId)101 by=(HouseId)2

  // Combat results
  combat at=(SystemId)101 {
    attacker house=(HouseId)1 fleet=(FleetId)123
    defender house=(HouseId)2 fleet=(FleetId)789
    result "attacker-victory"
    losses attacker=2 defender=5
  }

  // Colony updates (own colonies get full detail)
  colony-updated id=(ColonyId)1 {
    population 850
    industry 430
    treasury-contribution 215
  }

  // Colony captured
  colony-captured id=(ColonyId)99 {
    system=(SystemId)50
    old-owner=(HouseId)3
    new-owner=(HouseId)1
  }

  // Tech advancement
  tech-advance house=(HouseId)1 field="weapons" level=3 breakthrough="minor"

  // Diplomatic changes
  relation-changed from=(HouseId)1 to=(HouseId)3 {
    old-status "hostile"
    new-status "war"
    reason "Declaration of war"
  }

  // Ship commissioned
  ship-commissioned colony=(ColonyId)1 {
    ship-class "Destroyer"
    fleet=(FleetId)500
  }

  // Intel gathered (what we learned about enemies)
  intel {
    fleet-detected id=(FleetId)999 owner=(HouseId)2 {
      location=(SystemId)30
      estimated-ships=5
    }
    colony-intel id=(ColonyId)88 owner=(HouseId)3 {
      system=(SystemId)40
      estimated-population=600
      estimated-industry=300
    }
  }

  // Events visible to this house
  events {
    event type="ShipCommissioned" {
      description "Destroyer commissioned at Alpha Prime"
      colony=(ColonyId)1
      ship-class "Destroyer"
    }
    event type="BattleOccurred" {
      description "Battle at Tau Ceti - House Alpha victorious"
      system=(SystemId)101
      outcome "attacker-victory"
    }
    event type="TechAdvance" {
      description "Weapons technology advanced to level 3"
      tech-field "weapons"
      new-level 3
    }
    event type="SpyMissionSucceeded" {
      description "Intelligence gathered on House Beta colony"
      target=(HouseId)2
    }
  }
}
```

### Full State (30405)

Complete game state for initial sync or resync.

```kdl
state turn=5 game="550e8400-e29b-41d4-a716-446655440000" {
  viewing-house id=(HouseId)1 name="House Alpha"

  // Own house info (full detail)
  house {
    treasury 5000
    prestige 250
    eliminated false
    tech {
      economic 2
      science 1
      weapons 3
      shields 2
      construction 2
      terraforming 1
      electronic-intelligence 1
      cloaking 1
      strategic-lift 1
      counter-intelligence 1
      flagship-command 1
      strategic-command 1
      fighter-doctrine 1
      advanced-carrier-operations 1
    }
  }

  // Owned colonies (full detail)
  colonies {
    colony id=(ColonyId)1 system=(SystemId)10 name="Alpha Prime" {
      population 840
      industry 420
      tax-rate 50
      auto-repair true
      under-siege false
      facilities {
        spaceport 1
        shipyard 2
        drydock 1
        starbase 1
      }
      ground-units {
        army 10
        marine 5
        ground-battery 3
        planetary-shield 1
      }
      construction-queue {
        project type="ship" class="Cruiser" progress=50 cost=100
        project type="facility" class="Shipyard" progress=0 cost=200
      }
    }
    colony id=(ColonyId)2 system=(SystemId)15 name="New Terra" {
      population 200
      industry 100
      tax-rate 50
    }
  }

  // Owned fleets (full detail)
  fleets {
    fleet id=(FleetId)1 location=(SystemId)10 name="Alpha Fleet" {
      command type="guard-colony"
      ship id=(ShipId)100 class="Destroyer" hp=10 max-hp=10 tech-level=2
      ship id=(ShipId)101 class="Cruiser" hp=15 max-hp=15 tech-level=2
      ship id=(ShipId)102 class="ETAC" hp=5 max-hp=5 {
        cargo ptu=3
      }
    }
    fleet id=(FleetId)2 location=(SystemId)20 name="Scout Wing" {
      command type="scout-system" target=(SystemId)25
      ship id=(ShipId)200 class="Destroyer" hp=10 max-hp=10
    }
  }

  // Visible systems (fog of war filtered)
  systems {
    system id=(SystemId)10 name="Alpha Centauri" {
      visibility "owned"
      coords q=0 r=0
      ring 0
      planet-class "Eden"
      resource-rating "Abundant"
      lanes (SystemId)11 (SystemId)12 (SystemId)15
    }
    system id=(SystemId)11 name="Tau Ceti" {
      visibility "scouted"
      last-scouted 4
      coords q=1 r=0
      ring 1
      lanes (SystemId)10 (SystemId)20
    }
    system id=(SystemId)20 name="Unknown System" {
      visibility "adjacent"
      coords q=2 r=0
      ring 2
    }
  }

  // Enemy intel (fog of war - what we've observed)
  intel {
    fleets {
      fleet id=(FleetId)999 owner=(HouseId)2 {
        location=(SystemId)30
        detected-turn 4
        estimated-ships 5
        quality "visual"
      }
    }
    colonies {
      colony id=(ColonyId)99 owner=(HouseId)3 {
        system=(SystemId)40
        intel-turn 3
        estimated-population 500
        estimated-industry 250
        quality "scan"
      }
    }
    systems {
      system id=(SystemId)30 {
        last-scouted 4
        owner=(HouseId)2
      }
    }
  }

  // Public information (all players see this)
  standings {
    house id=(HouseId)1 name="House Alpha" prestige=250 colonies=2
    house id=(HouseId)2 name="House Beta" prestige=180 colonies=2
    house id=(HouseId)3 name="House Gamma" prestige=200 colonies=3
    house id=(HouseId)4 name="House Delta" prestige=150 colonies=2 eliminated=true
  }

  diplomacy {
    relation (HouseId)1 (HouseId)2 status="peace" since-turn=1
    relation (HouseId)1 (HouseId)3 status="war" since-turn=3
    relation (HouseId)2 (HouseId)3 status="hostile" since-turn=2
  }

  // Pending diplomatic proposals
  proposals {
    proposal id=(ProposalId)1 {
      from=(HouseId)2
      to=(HouseId)1
      type "alliance"
      expires-turn 6
    }
  }
}
```

### KDL Type Annotations

EC4X uses KDL type annotations for entity IDs in command files:

| Type | Example | Description |
|------|---------|-------------|
| `(HouseId)` | `(HouseId)1` | House/faction identifier |
| `(FleetId)` | `(FleetId)123` | Fleet identifier |
| `(ShipId)` | `(ShipId)456` | Ship identifier |
| `(ColonyId)` | `(ColonyId)789` | Colony identifier |
| `(SystemId)` | `(SystemId)10` | Star system identifier |
| `(ProposalId)` | `(ProposalId)5` | Diplomatic proposal ID |

These are parsed by `nimkdl` and converted to msgpack as uint32 values.
