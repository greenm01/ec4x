# EC4X Data Flow and Turn Resolution

## Overview

This document traces the complete data flow through an EC4X turn cycle, from command submission to result delivery, showing how data moves between components in both transport modes.

## Turn Cycle Overview

```
┌─────────────────────────────────────────────────────────────┐
│                   EC4X Turn Cycle                           │
│                                                             │
│  ┌────────────┐     ┌──────────┐     ┌──────────────┐     │
│  │  Command   │────▶│  Turn    │────▶│   Result     │     │
│  │ Submission │     │Resolution│     │ Distribution │     │
│  │  (Players) │     │ (Daemon) │     │  (Daemon)    │     │
│  └────────────┘     └──────────┘     └──────────────┘     │
│        │                   │                  │            │
│        ▼                   ▼                  ▼            │
│   Transport           Game Engine         Transport        │
│   (Localhost/          (4 Phases)       (Localhost/        │
│    Nostr)                                Nostr)            │
└─────────────────────────────────────────────────────────────┘
```

**Timing:**
- Turn length: 24-72 hours (configurable)
- Command deadline: Before turn resolution
- Resolution: Atomic (seconds to minutes)
- Distribution: Immediate after resolution

## Phase 1: Command Submission

### Player Perspective

**1. Player Reviews Game State**

Players use the GUI client (`bin/ec4x-client`) to view game state:
- Starmap visualization shows known systems
- Fleet and colony panels show owned assets
- Intel panel shows known enemy positions

Internally:
- Localhost: Reads ec4x.db, shows filtered view based on intel
- Nostr: Queries local cache from received EventKindStateDelta

**2. Player Plans Commands**

- Review available fleets
- Check movement options (pathfinding)
- Plan attacks, colonization, spy operations
- Consider diplomacy

**3. Player Writes Commands**

commands.kdl:
```kdl
commands turn=42 house=(HouseId)1 {
  fleet (FleetId)1 {
    move to=(SystemId)5 roe=7
  }
  fleet (FleetId)2 {
    bombard system=(SystemId)10
  }
}
```

**4. Player Submits Commands**

Players submit commands through the TUI client or by placing KDL files directly.

Localhost:
```bash
# TUI client writes to commands directory, or player drops file directly:
cp turn_42_house_1.kdl data/games/{game_id}/commands/
```

Nostr:
```bash
client submit game-123 turn_42_house_1.kdl
# Client encrypts to moderator, publishes EventKindCommandPacket to relay
```

**5. Zero-Turn Command Flow**

Zero-turn commands are administrative operations that execute during command submission, not during turn resolution. They allow players to reorganize fleets and manage cargo before committing operational commands.

### Execution Timeline

```
Command Submission Flow:
  ↓
Parse CommandPacket
  ↓
Extract zero-turn commands
  ↓
Execute zero-turn commands sequentially
  - Validate each command
  - Modify GameState immediately
  - Return ZeroTurnResult per command
  ↓
Queue operational commands for turn resolution
```

### Client/Server Interaction

**Client Workflow:**
1. Load `PlayerState` from SQLite (or receive from server)
2. Player builds zero-turn commands (UI preview optional)
3. Submit `CommandPacket` containing zero-turn commands + operational orders
4. Receive `ZeroTurnResult`s for immediate feedback
5. Updated `PlayerState` saved to SQLite after processing

**Server Workflow:**
1. Receive `CommandPacket` from client
2. Extract zero-turn commands
3. Execute via `submitZeroTurnCommand(state, cmd, events)`
4. Emit `GameEvent`s for telemetry
5. Queue remaining operational commands
6. Save updated `PlayerState` to SQLite for player retrieval

### PlayerState Persistence

After zero-turn command execution, the server generates `PlayerState` for each house:
- Full entity data for owned assets (colonies, fleets, ships)
- Fog-of-war filtered intel for visible enemy assets
- Saved to SQLite `player_states` table

**Claude Testing:** Claude reads `PlayerState` directly from SQLite to analyze game state and submit commands via KDL.

### Zero-turn command types (9):

**Fleet Organization (no colony required):**
- DetachShips - Split ships to create new fleet
- TransferShips - Move ships between fleets
- MergeFleets - Combine entire fleet into another

**Cargo Operations (requires colony):**
- LoadCargo - Load marines/colonists onto transports
- UnloadCargo - Unload cargo at colony

**Fighter Operations:**
- LoadFighters - Load fighters from colony onto carrier (requires colony)
- UnloadFighters - Unload fighters from carrier to colony (requires colony)
- TransferFighters - Transfer fighters between carriers (no colony required)

**Status Changes (requires colony):**
- Reactivate - Return Reserve/Mothballed fleet to Active

**Key characteristic:** Execute during command submission, not during turn resolution. State changes take effect immediately—operational commands submitted in same batch see the updated state.

**Example:** Player submits:
1. LoadCargo (marines onto fleet) — executes immediately
2. MergeFleets (combine two fleets) — executes immediately
3. Invade command — queued for turn resolution

When turn resolves, invasion fleet already has marines loaded and merged composition.

**See:** [docs/engine/zero_turn.md](../engine/zero_turn.md) for complete API reference and location requirements.

### Data Flow (Localhost)

```
Player's commands.kdl
  ↓
Client validates format
  ↓
Client writes KDL to:
  /var/ec4x/games/my_game/commands/turn_42_house_1.kdl

Format (per command-format.md):
commands turn=42 house=(HouseId)1 {
  fleet (FleetId)1 {
    move to=(SystemId)5 roe=7
  }
  fleet (FleetId)2 {
    bombard system=(SystemId)10
  }
}
```

### Data Flow (Nostr)

```
Player's commands.kdl
  ↓
Client validates format
  ↓
Client serializes KDL to string
  ↓
Client encrypts KDL with NIP-44:
  recipient = moderator_pubkey
  encrypted_content = nip44_encrypt(kdl_string, moderator_pubkey, player_privkey)
  ↓
Client creates Nostr event:
{
  "kind": 30001,  // EventKindCommandPacket
  "pubkey": "player_pubkey",
  "created_at": 1705416000,
  "content": "encrypted_kdl_here",
  "tags": [
    ["g", "game-123"],
    ["h", "house-alpha"],
    ["t", "42"],
    ["p", "moderator_pubkey"]
  ],
  "sig": "..."
}
  ↓
Client publishes to relay WebSocket:
  ["EVENT", event_json]
  ↓
Relay broadcasts to subscribers
```

## Phase 2: Command Collection (Daemon)

### Daemon Monitoring Loop

**Every poll_interval seconds (e.g., 30s):**

```
For each active game:
  Check transport mode
  If localhost:
    Scan for commands/*.kdl files
  If nostr:
    Process received Nostr events from subscription

  Insert valid commands into SQLite
  Check if turn is ready for resolution
```

### Localhost Command Collection

```
Daemon polls:
  /var/ec4x/games/my_game/houses/*/turn_{N}_house_{H}.kdl

If file exists:
  1. Read and parse JSON
  2. Validate command packet structure
  3. Validate orders against game rules:
     - Fleet exists and owned by house
     - Target systems valid
     - Order type allowed
  4. Insert into SQLite:
     INSERT INTO orders (game_id, house_id, turn, fleet_id, order_type, ...)
     VALUES (...);
  5. Delete turn_{N}_house_{H}.kdl (consumed)
  6. Log: "Orders received from House Alpha for turn 42"
```

### Nostr Command Collection

```
Daemon maintains WebSocket subscription:
  Filter: {
    "kinds": [30001],
    "since": last_seen_timestamp,
    "#g": ["game-123", "game-456", ...],  // All managed games
    "#p": ["moderator_pubkey"]
  }

On EVENT received:
  1. Verify signature (Nostr protocol)
  2. Check if already processed (check nostr_events cache)
  3. Decrypt content:
     decrypted_json = nip44_decrypt(event.content, moderator_privkey, player_pubkey)
  4. Parse and validate command packet
  5. Validate orders against game rules
  6. Insert into SQLite orders table
  7. Cache event in nostr_events table:
     INSERT INTO nostr_events (id, game_id, kind, pubkey, content, ...)
  8. Log: "Orders received from House Alpha (npub...) for turn 42"
```

## Phase 3: Turn Readiness Check

### Readiness Criteria

**Daemon checks every poll:**

```sql
-- Count expected vs received orders
SELECT
  (SELECT COUNT(*) FROM houses
   WHERE game_id = 'game-123' AND eliminated = 0) as expected_houses,
  (SELECT COUNT(DISTINCT house_id) FROM orders
   WHERE game_id = 'game-123' AND turn = 42 AND processed = 0) as received_orders,
  (SELECT turn_deadline FROM games WHERE id = 'game-123') as deadline;
```

**Resolution Triggers:**

1. **All orders received**: `received_orders == expected_houses`
2. **Deadline passed**: `current_time >= deadline`
3. **Manual trigger**: `moderator resolve game-123 --turn=42`

**Example Log:**
```
[INFO] Game game-123 turn 42: 4/5 orders received, deadline in 2 hours
[INFO] Game game-123 turn 42: 5/5 orders received, resolving now
```

## Phase 4: Turn Resolution

### Resolution Transaction

**Atomic SQLite Transaction:**

```sql
BEGIN TRANSACTION;

-- Step 1: Lock game
UPDATE games SET phase = 'Resolving' WHERE id = 'game-123';

-- Step 2: Load game state (queries)
-- Step 3: Run game engine (in memory)
-- Step 4: Save new state (updates/inserts)

-- Step 5: Increment turn
UPDATE games SET
  turn = turn + 1,
  phase = 'Active',
  turn_deadline = ?,
  updated_at = ?
WHERE id = 'game-123';

-- Step 6: Mark orders processed
UPDATE orders SET processed = 1
WHERE game_id = 'game-123' AND turn = 42;

COMMIT;
```

### Four-Phase Resolution

See [gameplay.md](../specs/gameplay.md) for complete rules.

#### Phase 1: Income

```
For each house:
  1. Calculate resource production from colonies:
     production = sum(colony.industry for colony in house.colonies)

  2. Calculate prestige income:
     prestige_gain = calculate_prestige_sources(house)

  3. Update house resources:
     UPDATE houses SET prestige = prestige + prestige_gain
     WHERE id = house_id;

  4. Log income event:
     INSERT INTO turn_log (game_id, turn, phase, event_type, data, visible_to_house_id)
     VALUES ('game-123', 42, 'Income', 'ResourceGain', json(...), house_id);
```

#### Phase 2: Command

```
For each order in orders (by priority):
  1. Validate order still valid (fleet exists, etc.)

  2. Execute order:
     - Move: Update fleet location, check for encounters
     - Colonize: Create new colony
     - Join Fleet: Merge fleets
     - Patrol: Set patrol route
     - Spy: Roll for intel success

  3. Update entities in SQLite:
     UPDATE fleets SET location_system_id = ? WHERE id = ?;
     INSERT INTO colonies (...) VALUES (...);

  4. Log movement events:
     INSERT INTO turn_log (game_id, turn, phase, event_type, data, visible_to_house_id)
     VALUES ('game-123', 42, 'Command', 'FleetMoved', json({
       "fleet_id": "fleet-1",
       "from": "system-3",
       "to": "system-5"
     }), house_id);
```

#### Phase 3: Conflict

```
For each system with multiple hostile fleets:
  1. Identify combatants
  2. Run combat resolution:
     result = resolve_combat(fleets_in_system)

  3. Apply damage:
     For each damaged ship:
       UPDATE ships SET hull_points = ? WHERE id = ?;

     For each destroyed ship:
       DELETE FROM ships WHERE id = ?;

     For each empty fleet:
       DELETE FROM fleets WHERE id = ? AND (SELECT COUNT(*) FROM ships WHERE fleet_id = id) = 0;

  4. Log combat events:
     INSERT INTO turn_log (game_id, turn, phase, event_type, data, visible_to_house_id)
     VALUES ('game-123', 42, 'Conflict', 'Combat', json({
       "system": "system-5",
       "attacker": "house-alpha",
       "defender": "house-beta",
       "losses": {...}
     }), NULL);  -- Visible to both combatants (query filters later)
```

#### Phase 4: Maintenance

```
For each colony:
  1. Process construction queue:
     If construction_complete:
       colony.starbase_level += 1
       UPDATE colonies SET starbase_level = ? WHERE id = ?;

  2. Process research:
     If research_complete:
       house.tech_level += 1
       UPDATE houses SET tech_level = ? WHERE id = ?;

  3. Apply upkeep costs:
     house.prestige -= calculate_upkeep(house)
     UPDATE houses SET prestige = ? WHERE id = ?;

  4. Check elimination:
     If house has no colonies and no fleets:
       UPDATE houses SET eliminated = 1 WHERE id = ?;
       Log elimination event
```

### Intel Update

**After resolution, before result distribution:**

```
For each house in game:
  1. Update system visibility:
     - Mark owned systems (has colony)
     - Mark occupied systems (has fleet)
     - Keep scouted systems (visited before)
     - Add adjacent systems (one jump away)

     INSERT OR REPLACE INTO intel_systems (...)

  2. Update fleet detection:
     - Detect enemy fleets in same systems as own fleets
     - Record ship counts and types

     INSERT OR REPLACE INTO intel_fleets (...)

  3. Update colony intel:
     - Apply spy operation results
     - Update captured colony intel

     INSERT OR REPLACE INTO intel_colonies (...)
```

### Delta Generation

**For each house:**

```
1. Query changes since last turn:
   - Fleets that moved
   - Ships damaged/destroyed
   - Colonies gained/lost
   - Combat results visible to house
   - Intel updates

2. Construct delta JSON:
   {
     "turn": 42,
     "deltas": [
       {
         "type": "fleet_moved",
         "fleet_id": "fleet-1",
         "from": "system-3",
         "to": "system-5",
         "ships": [...]  // Only if HP changed
       },
       {
         "type": "combat",
         "system": "system-5",
         "participants": ["house-alpha", "house-beta"],
         "result": "attacker_victory",
         "losses": {...}
       },
       {
         "type": "intel_update",
         "detected_fleets": [...],
         "scouted_systems": [...]
       }
     ]
   }

3. Store delta:
   INSERT INTO state_deltas (game_id, turn, house_id, delta_type, data)
   VALUES ('game-123', 42, 'house-alpha', 'turn_complete', json);
```

## Phase 5: Result Distribution

### Localhost Distribution

```
For each house in game:
  1. Query state_deltas for house_id
  2. Query intel tables for visibility filter
  3. Generate complete GameState view for house
  4. Serialize to JSON
  5. Write to file:
     /var/ec4x/games/my_game/houses/house_alpha/turn_results/turn_42.json

  6. Structured data ready for client-side formatting:
     - TurnResult contains events and combatReports
     - Client can generate formatted reports on-demand
     - No pre-formatted text files needed (saves storage)

Note: Previous versions generated text summaries server-side.
Current design: Clients format reports from structured TurnResult data
using src/client/reports/turn_report.nim. This approach:
  - Minimizes network traffic (structured data only)
  - Allows different clients to format differently
  - Enables hex coordinate display with proper formatting
  - Supports customization per client type (CLI, web, mobile)
```

### Nostr Distribution

```
For each house in game:
  1. Query state_deltas for house_id
  2. Generate delta JSON (see above)

  3. Check size:
     If delta JSON < 32 KB:
       Create single EventKindStateDelta
     Else:
       Split into chunks
       Create multiple EventKindDeltaChunk

  4. Encrypt:
     encrypted_content = nip44_encrypt(delta_json, house_pubkey, moderator_privkey)

  5. Create Nostr event:
     {
       "kind": 30007,  // EventKindStateDelta
       "pubkey": "moderator_pubkey",
       "created_at": current_timestamp,
       "content": encrypted_content,
       "tags": [
         ["g", "game-123"],
         ["h", "house-alpha"],
         ["t", "42"],
         ["p", "house_alpha_pubkey"]
       ]
     }

  6. Sign event with moderator's keypair

  7. Insert into outbox queue:
     INSERT INTO nostr_outbox (game_id, event_kind, recipient_pubkey, content, tags, sent)
     VALUES ('game-123', 30007, 'house_alpha_pubkey', event_json, tags_json, 0);

Public turn summary:
  1. Generate public summary (no fog of war)
  2. Create EventKindTurnComplete (unencrypted)
  3. Insert into outbox queue

Publishing loop (async):
  Poll nostr_outbox WHERE sent = 0
  For each event:
    Publish to relay: ["EVENT", event_json]
    Wait for OK/CLOSED response
    If OK: Mark sent = 1
    If CLOSED/error: Retry with exponential backoff
```

## Phase 6: Player Receives Results

### Localhost

```
Player opens GUI client (bin/ec4x-client):

Client automatically:
  1. Checks for new turn results in:
     data/games/{game_id}/houses/{house}/turn_results/

  2. Reads latest turn file (turn_43.json)

  3. Displays:
     - Updated starmap with new positions
     - Movement results in event log
     - Combat reports with animations
     - Intel updates highlighted

  4. Turn report panel shows summary
```

### Nostr

```
Client maintains subscription:
  Filter: {
    "kinds": [30007],  // StateDelta
    "#g": ["game-123"],
    "#p": ["own_pubkey"]
  }

On EVENT received:
  1. Verify signature
  2. Check if new turn (not already processed)
  3. Decrypt:
     delta_json = nip44_decrypt(event.content, own_privkey, moderator_pubkey)

  4. If delta_chunk:
     Store in received_chunks table
     Wait for all chunks
     Reassemble

  5. Apply delta to local cached state:
     apply_delta(local_gamestate, delta_json)

  6. Update local SQLite cache
  7. Notify player: "Turn 42 results received"

GUI client automatically refreshes to show updated state from local cache.
```

## Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Turn 42 Complete Flow                        │
└─────────────────────────────────────────────────────────────────┘

Player A                     Daemon                      Player B
   │                           │                            │
   │ 1. Submit orders          │                            │
   ├──────────────────────────▶│                            │
   │   (file/Nostr)            │                            │
   │                           │                            │
   │                           │ 2. Collect orders          │
   │                           │◀───────────────────────────┤
   │                           │                            │
   │                           │ 3. Wait for all orders     │
   │                           │    or deadline             │
   │                           │                            │
   │                           │ 4. BEGIN TRANSACTION       │
   │                           │ 5. Resolve Turn (4 phases) │
   │                           │ 6. Update game state       │
   │                           │ 7. Update intel tables     │
   │                           │ 8. Generate deltas         │
   │                           │ 9. COMMIT                  │
   │                           │                            │
   │ 10. Receive delta A       │                            │
   │◀──────────────────────────┤                            │
   │   (filtered view)         │                            │
   │                           │ 11. Send delta B           │
   │                           ├───────────────────────────▶│
   │                           │   (different view)         │
   │                           │                            │
   │ 12. View results          │                            │
   │    (GUI client)           │                            │
   │                           │                 13. View   │
   │                           │                    results │
   │                           │                            │
   │ 14. Plan turn 43 orders   │         14. Plan turn 43  │
   │                           │             orders         │
   │                           │                            │
   └───────────────────────────┴────────────────────────────┘
```

## Timing Analysis

### Typical Turn Timeline

**Turn Length: 48 hours**

```
Hour 0: Turn 42 resolves, results distributed
  - Daemon resolves in ~10 seconds
  - Results published immediately

Hour 0-24: Players receive results, plan orders
  - Localhost: instant file access
  - Nostr: delivered within 1-5 minutes (relay latency)

Hour 24-47: Players submit orders
  - Most players submit in first 24 hours
  - Some wait until deadline

Hour 46: Reminder (optional feature)
  - Daemon sends reminder to players without orders

Hour 48: Turn deadline
  - Daemon resolves with available orders
  - Missing orders default to "Hold"

Hour 48: Turn 43 resolves
  - Cycle repeats
```

### Performance Metrics

**Turn Resolution:**
- Small game (2-4 players, 20 systems): 1-5 seconds
- Medium game (6-8 players, 50 systems): 5-15 seconds
- Large game (10-12 players, 100+ systems): 15-60 seconds

**Result Distribution:**
- Localhost: Instant (file write)
- Nostr: 1-30 seconds (per player, encryption + publish)

**Command Collection Latency:**
- Localhost: Up to poll_interval (e.g., 30 seconds)
- Nostr: 1-10 seconds (relay propagation)

## Error Scenarios

### Missing Orders

```
Hour 48: Deadline reached, only 4/5 orders received

Daemon:
  1. Log warning: "House Beta did not submit orders for turn 42"
  2. Generate default "Hold" orders for all Beta fleets
  3. Resolve turn with available + default orders
  4. In turn log, mark Beta's orders as "defaulted"
```

### Resolution Failure

```
During turn resolution: Database error

Daemon:
  1. ROLLBACK transaction
  2. Log error with stack trace
  3. Leave game in 'Active' phase
  4. Retry resolution on next poll cycle
  5. If 3 consecutive failures: Set phase to 'Paused', alert moderator
```

### Nostr Relay Failure

```
During result distribution: Relay connection lost

Daemon:
  1. Mark events as unsent in nostr_outbox
  2. Attempt reconnect with exponential backoff
  3. On reconnect: Retry publishing unsent events
  4. If all relays fail: Log critical error, try fallback relays
  5. Events remain queued until successful delivery
```

## Related Documentation

- [Architecture Overview](./overview.md)
- [Daemon Design](./daemon.md)
- [Transport Layer](./transport.md)
- [Intel System](./intel.md)
- [Storage Schema](./storage.md)
- [Gameplay Rules](../specs/gameplay.md)
