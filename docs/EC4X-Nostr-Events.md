# EC4X Nostr Event Schema

## Overview

EC4X uses custom Nostr event kinds (30000+ range) for game operations. Like a BBS door game, all game state flows through the relay, with encryption ensuring privacy and preventing cheating.

## Event Kinds

```nim
const
  EventKindOrderPacket* = 30001      # Player order submission
  EventKindGameState* = 30002        # Per-player filtered game state
  EventKindTurnComplete* = 30003     # Public turn resolution announcement
  EventKindGameMeta* = 30004         # Game lobby/configuration
  EventKindDiplomacy* = 30005        # Private diplomatic messages
  EventKindSpectate* = 30006         # Public spectator feed
```

### Why 30000+ Range?

Nostr reserves 30000-39999 for "parameterized replaceable events" - perfect for game state that updates over time. We use them as regular events but in the custom app range.

## Standard Tags

All EC4X events use these standard tags:

```nim
const
  TagGame* = "g"          # Game ID (UUID)
  TagHouse* = "h"         # Player's house name
  TagTurn* = "t"          # Turn number (integer string)
  TagPlayer* = "p"        # Target player pubkey (for encryption)
  TagPhase* = "phase"     # Game phase: setup|active|paused|completed
  TagRelay* = "relay"     # Recommended relay for this game
```

## Event Schemas

### 1. Order Packet (Kind 30001)

**Purpose**: Player submits encrypted orders to moderator

**Privacy**: Encrypted to moderator pubkey (NIP-44)

**Structure**:
```json
{
  "id": "event-id-hex",
  "pubkey": "player-pubkey-hex",
  "created_at": 1699564800,
  "kind": 30001,
  "tags": [
    ["g", "game-550e8400-e29b-41d4-a716-446655440000"],
    ["h", "House-Atreides"],
    ["t", "5"],
    ["p", "moderator-pubkey-hex"]
  ],
  "content": "<encrypted-order-json>",
  "sig": "signature-hex"
}
```

**Decrypted Content** (visible only to moderator):
```json
{
  "version": "1.0",
  "submitted_at": "2024-11-14T12:34:56Z",
  "orders": {
    "fleets": [
      {
        "fleet_id": "fleet-1",
        "order_type": "move",
        "from_system": "alpha",
        "to_system": "beta",
        "ships": ["ship-1", "ship-2"]
      },
      {
        "fleet_id": "fleet-2",
        "order_type": "attack",
        "target_system": "gamma",
        "ships": ["ship-3", "ship-4", "ship-5"]
      }
    ],
    "builds": [
      {
        "system": "alpha",
        "item_type": "ship",
        "ship_class": "destroyer",
        "quantity": 2
      }
    ],
    "research": {
      "tech_id": "advanced-shields",
      "investment": 500
    },
    "diplomacy": [
      {
        "target_house": "House-Harkonnen",
        "action": "propose_alliance",
        "terms": {...}
      }
    ]
  },
  "checksum": "sha256-of-orders"
}
```

**Validation Rules**:
- Must be received before turn deadline
- Must be signed by registered player
- Must decrypt successfully
- Must pass schema validation
- One order packet per player per turn (later ones override)

---

### 2. Game State (Kind 30002)

**Purpose**: Moderator sends encrypted game state to specific player

**Privacy**: Encrypted to player pubkey (NIP-44), implements fog of war

**Structure**:
```json
{
  "id": "event-id-hex",
  "pubkey": "moderator-pubkey-hex",
  "created_at": 1699651200,
  "kind": 30002,
  "tags": [
    ["g", "game-550e8400-e29b-41d4-a716-446655440000"],
    ["h", "House-Atreides"],
    ["t", "6"],
    ["p", "player-pubkey-hex"]
  ],
  "content": "<encrypted-state-json>",
  "sig": "moderator-signature-hex"
}
```

**Decrypted Content** (visible only to that player):
```json
{
  "version": "1.0",
  "game_id": "game-550e8400-e29b-41d4-a716-446655440000",
  "turn": 6,
  "phase": "active",
  "your_house": {
    "name": "House-Atreides",
    "prestige": 1250,
    "treasury": 5000,
    "tech_level": 3,
    "systems_controlled": 12,
    "total_military": 45,
    "total_spacelift": 8
  },
  "visible_systems": [
    {
      "id": "alpha",
      "name": "Alpha Centauri",
      "owner": "House-Atreides",
      "population": 5,
      "infrastructure": 3,
      "garrison": {
        "military": 5,
        "spacelift": 1
      },
      "production": {
        "income": 500,
        "available": 450
      }
    },
    {
      "id": "beta",
      "name": "Beta Hydri",
      "owner": "House-Harkonnen",
      "population": 3,
      "infrastructure": 2,
      "garrison": {
        "military": "unknown",
        "spacelift": "unknown"
      }
    }
  ],
  "visible_fleets": [
    {
      "fleet_id": "fleet-1",
      "owner": "House-Atreides",
      "location": "alpha",
      "ships": [
        {
          "id": "ship-1",
          "class": "destroyer",
          "health": 100,
          "crippled": false
        }
      ]
    },
    {
      "fleet_id": "enemy-fleet-x",
      "owner": "House-Harkonnen",
      "location": "beta",
      "ships": [
        {
          "class": "unknown",
          "count": 3
        }
      ]
    }
  ],
  "intel_reports": [
    "House Harkonnen fleet spotted in Beta Hydri",
    "Research breakthrough in advanced shields (50% complete)"
  ],
  "turn_deadline": "2024-11-15T00:00:00Z"
}
```

**Fog of War Rules**:
- Only systems within sensor range are visible
- Enemy fleet details are hidden (just count/class visible)
- Enemy resources and production hidden
- Intel reports based on espionage actions

---

### 3. Turn Complete (Kind 30003)

**Purpose**: Public announcement that a turn has been resolved

**Privacy**: Public (plaintext)

**Structure**:
```json
{
  "id": "event-id-hex",
  "pubkey": "moderator-pubkey-hex",
  "created_at": 1699651200,
  "kind": 30003,
  "tags": [
    ["g", "game-550e8400-e29b-41d4-a716-446655440000"],
    ["t", "6"],
    ["phase", "active"]
  ],
  "content": "{...summary...}",
  "sig": "moderator-signature-hex"
}
```

**Content** (public summary):
```json
{
  "game_id": "game-550e8400-e29b-41d4-a716-446655440000",
  "game_name": "Imperium Rising",
  "turn": 6,
  "resolved_at": "2024-11-15T00:01:23Z",
  "next_deadline": "2024-11-16T00:00:00Z",
  "game_year": 2006,
  "game_month": 6,
  "players_submitted": 6,
  "players_total": 8,
  "summary": {
    "battles": 2,
    "systems_changed_hands": 1,
    "ships_built": 12,
    "ships_destroyed": 5,
    "treaties_signed": 1
  },
  "leaderboard": [
    {
      "house": "House-Atreides",
      "prestige": 1250,
      "rank": 1
    },
    {
      "house": "House-Harkonnen",
      "prestige": 1100,
      "rank": 2
    },
    {
      "house": "House-Ordos",
      "prestige": 950,
      "rank": 3
    }
  ],
  "major_events": [
    "Battle of Beta Hydri: House Atreides defeats House Harkonnen",
    "House Corrino and House Ordos sign alliance",
    "First colony ship reaches outer rim"
  ]
}
```

**Use Cases**:
- Spectators can watch leaderboard updates
- Discord bot posts turn summaries
- Web dashboard shows game progress
- Historical game browser

---

### 4. Game Meta (Kind 30004)

**Purpose**: Game lobby info, configuration, registration

**Privacy**: Public (plaintext)

**Structure**:
```json
{
  "id": "event-id-hex",
  "pubkey": "moderator-pubkey-hex",
  "created_at": 1699478400,
  "kind": 30004,
  "tags": [
    ["g", "game-550e8400-e29b-41d4-a716-446655440000"],
    ["phase", "setup"],
    ["relay", "wss://relay.ec4x.game"]
  ],
  "content": "{...game-config...}",
  "sig": "moderator-signature-hex"
}
```

**Content** (game configuration):
```json
{
  "game_id": "game-550e8400-e29b-41d4-a716-446655440000",
  "name": "Imperium Rising",
  "description": "8-player competitive game, experienced players only",
  "phase": "setup",
  "created_at": "2024-11-10T00:00:00Z",
  "starts_at": "2024-11-14T00:00:00Z",
  "settings": {
    "max_players": 8,
    "turn_duration_hours": 24,
    "victory_prestige": 5000,
    "max_turns": 100,
    "map_size": "large",
    "fog_of_war": true,
    "allow_diplomacy": true,
    "allow_espionage": true
  },
  "players": [
    {
      "house": "House-Atreides",
      "pubkey": "player1-pubkey-hex",
      "status": "ready"
    },
    {
      "house": "House-Harkonnen",
      "pubkey": "player2-pubkey-hex",
      "status": "ready"
    },
    {
      "house": "House-Ordos",
      "pubkey": "player3-pubkey-hex",
      "status": "pending"
    }
  ],
  "rules_url": "https://ec4x.game/rules",
  "spectator_relay": "wss://relay.ec4x.game"
}
```

**Lifecycle**:
1. Moderator creates game (phase: `setup`)
2. Players join by publishing "join request" events
3. Moderator updates meta event with player list
4. Game starts (phase: `active`)
5. Game ends (phase: `completed`)

---

### 5. Diplomacy (Kind 30005)

**Purpose**: Private messages between players (treaties, threats, negotiations)

**Privacy**: Encrypted between two players (NIP-44)

**Structure**:
```json
{
  "id": "event-id-hex",
  "pubkey": "sender-pubkey-hex",
  "created_at": 1699564800,
  "kind": 30005,
  "tags": [
    ["g", "game-550e8400-e29b-41d4-a716-446655440000"],
    ["h", "House-Atreides"],
    ["p", "recipient-pubkey-hex"]
  ],
  "content": "<encrypted-message>",
  "sig": "sender-signature-hex"
}
```

**Decrypted Content**:
```json
{
  "from_house": "House-Atreides",
  "to_house": "House-Corrino",
  "message_type": "treaty_proposal",
  "message": "I propose a non-aggression pact for 10 turns. In exchange, I will support your claim to the imperial throne.",
  "treaty": {
    "type": "non_aggression",
    "duration_turns": 10,
    "terms": [
      "No military action against each other's systems",
      "Free passage through each other's territory",
      "House Atreides votes for House Corrino in imperial elections"
    ]
  },
  "requires_response": true,
  "expires_at": "2024-11-15T00:00:00Z"
}
```

**Message Types**:
- `treaty_proposal`: Formal alliance, NAP, trade agreement
- `treaty_acceptance`: Accept proposed treaty
- `treaty_rejection`: Decline proposed treaty
- `threat`: Ultimatum or warning
- `intel_share`: Share reconnaissance data
- `negotiation`: General diplomatic communication

---

### 6. Spectate (Kind 30006)

**Purpose**: Public feed for spectators (sanitized, no secrets)

**Privacy**: Public (plaintext)

**Structure**:
```json
{
  "id": "event-id-hex",
  "pubkey": "moderator-pubkey-hex",
  "created_at": 1699651200,
  "kind": 30006,
  "tags": [
    ["g", "game-550e8400-e29b-41d4-a716-446655440000"],
    ["t", "6"]
  ],
  "content": "{...spectator-view...}",
  "sig": "moderator-signature-hex"
}
```

**Content** (sanitized for public):
```json
{
  "game_id": "game-550e8400-e29b-41d4-a716-446655440000",
  "turn": 6,
  "leaderboard": [...],  // Same as turn complete
  "map_overview": {
    "systems": [
      {
        "id": "alpha",
        "name": "Alpha Centauri",
        "owner": "House-Atreides",
        "contested": false
      },
      {
        "id": "gamma",
        "name": "Gamma Draconis",
        "owner": "neutral",
        "contested": true
      }
    ],
    "territories": {
      "House-Atreides": 12,
      "House-Harkonnen": 10,
      "House-Ordos": 8
    }
  },
  "recent_events": [
    "House Atreides captured Beta Hydri",
    "Major battle in Gamma Draconis sector",
    "House Corrino completed research project"
  ]
}
```

**Use Cases**:
- Streamers cast games live
- Learning from top players
- Tournament spectating
- Community engagement

---

## Event Flow Examples

### Player Submits Orders

```
1. Player client creates order JSON
2. Encrypt to moderator pubkey (NIP-44)
3. Create event kind 30001 with tags [g, h, t, p]
4. Sign event with player's key
5. Publish to relay(s)
6. Moderator daemon receives via subscription
```

### Turn Resolution

```
1. Daemon checks for turn deadline
2. Query relay for all kind 30001 events (current game + turn)
3. Decrypt each order packet
4. Validate orders
5. Run game engine resolution
6. For each player:
   a. Generate filtered game state
   b. Encrypt to player pubkey
   c. Publish kind 30002 event
7. Generate public summary
8. Publish kind 30003 (turn complete)
9. Publish kind 30006 (spectator feed)
```

### Player Views State

```
1. Client subscribes to relay
2. Filter: kind 30002, game ID, player pubkey
3. Receive encrypted state event
4. Decrypt with player's private key
5. Parse JSON and render game view
6. Display turn deadline countdown
```

### Spectator Watches Game

```
1. Spectator client subscribes to relay
2. Filter: kind 30003 + 30006, game ID
3. Receive public events (no decryption needed)
4. Display leaderboard, map, recent events
5. Update in real-time as turns resolve
```

## Security Model

### Threat: Player Reads Other Players' Orders

**Prevention**: Orders encrypted to moderator pubkey only
- Only moderator can decrypt
- Relay operators can't read orders
- Other players can't read orders
- Even if relay is compromised, orders stay secret

### Threat: Moderator Cheats

**Detection**: All events are signed and timestamped
- Players can verify moderator didn't forge events
- Audit trail on relay
- Community can review game history
- Trusted moderators build reputation

### Threat: Replay Attack

**Prevention**: Event IDs are unique
- Relay rejects duplicate event IDs
- Timestamps prevent time-shifting
- Turn tags prevent cross-turn attacks

### Threat: Late Order Submission

**Prevention**: Daemon enforces deadlines
- Only process orders with `created_at` before deadline
- Publish deadline in turn complete event
- Clock sync required (NTP)

### Threat: Man-in-the-Middle

**Prevention**: Use WSS (WebSocket Secure)
- TLS encryption for transport
- Event signatures prevent tampering
- Verify relay certificates

## Event Retention

### Critical Events (Never Delete)

```
Kind 30001: Order packets - needed for dispute resolution
Kind 30002: Game states - full game history
Kind 30003: Turn complete - game timeline
Kind 30004: Game meta - configuration record
```

### Ephemeral Events (Can Prune)

```
Kind 30005: Diplomacy - delete after game ends
Kind 30006: Spectate feed - delete after 30 days
```

### Relay Configuration

```toml
[[retention.event_kinds]]
kinds = [30001, 30002, 30003, 30004]
time_limit = 0  # Permanent

[[retention.event_kinds]]
kinds = [30005]
time_limit = 7776000  # 90 days

[[retention.event_kinds]]
kinds = [30006]
time_limit = 2592000  # 30 days
```

## Querying Examples

### Get All Games

```json
["REQ", "sub-1", {
  "kinds": [30004],
  "#phase": ["active"]
}]
```

### Get Game History

```json
["REQ", "sub-2", {
  "kinds": [30003],
  "#g": ["game-550e8400-..."],
  "limit": 100
}]
```

### Get My Current Game State

```json
["REQ", "sub-3", {
  "kinds": [30002],
  "#g": ["game-550e8400-..."],
  "#p": ["my-pubkey-hex"],
  "limit": 1
}]
```

### Watch for Turn Updates

```json
["REQ", "sub-4", {
  "kinds": [30003],
  "#g": ["game-550e8400-..."],
  "since": 1699564800
}]
```

## Client Implementation Notes

### Order Submission

```nim
# Pseudocode
let orders = gatherPlayerOrders()
let orderJson = $(%orders)
let encrypted = encryptNIP44(orderJson, playerPrivKey, moderatorPubKey)

var event = newEvent(EventKindOrderPacket, encrypted, @[
  @[TagGame, gameId],
  @[TagHouse, playerHouse],
  @[TagTurn, $currentTurn],
  @[TagPlayer, moderatorPubKey]
])

event.pubkey = toHex(playerKeys.publicKey)
signEvent(event, playerKeys.privateKey)

await client.publish(event)
```

### State Retrieval

```nim
# Pseudocode
let filter = newFilter()
  .withKinds(@[EventKindGameState])
  .withTag(TagGame, @[gameId])
  .withTag(TagPlayer, @[myPubkey])
  .withLimit(1)

client.eventCallback = proc(event: NostrEvent) =
  let decrypted = decryptNIP44(event.content, myPrivKey, moderatorPubKey)
  let state = parseJson(decrypted)
  displayGameState(state)

await client.subscribe("game-state", @[filter])
```

## Future Enhancements

### NIP-42 Authentication

Require players to authenticate with relay before submitting orders:
- Prevents spam
- Allows player whitelisting
- Enables rate limiting per player

### NIP-57 Zaps

Lightning payments for:
- Game entry fees
- Prize pools
- Tips to moderator
- Spectator donations

### Parameterized Replaceable Events

Use proper NIP-33 replaceable events for game state:
- Single event per player per game
- Automatically replaces old state
- Reduces relay storage

---

*Last updated: November 2024*
