# ec4x-play - Dev Player CLI/TUI

**Binary:** `bin/ec4x-play`
**Source:** `src/player/`
**Status:** Design Document

---

## Overview

`ec4x-play` is a lightweight dev tool for playtesting EC4X without the full GUI client. It provides:

- **TUI Mode** - Menu-driven terminal interface for human playtesting
- **CLI Mode** - Order validation for Claude/LLM and scripted workflows

### When to Use

| Scenario | Tool |
|----------|------|
| Human dev testing against AI | `ec4x-play <game-id> --house=1` (TUI) |
| Claude/LLM playing | Direct SQLite queries + `ec4x-play validate` |
| Automated testing | `ec4x-play validate` in scripts |
| Full player experience | `bin/ec4x-client` (GUI) |

---

## TUI Mode (Human Playtesting)

### Launch

```bash
ec4x-play <game-id> --house=1
# or explicitly:
ec4x-play tui <game-id> --house=1
```

### Menu Structure

```
Main Menu
├── [F] Fleet Orders        → Fleet list → Order selection
├── [C] Colony Management   → Colony list → Tax/settings
├── [B] Build Orders        → Colony list → Build queue
├── [R] Research            → ERP/SRP/TRP allocation
├── [E] Espionage           → EBP investment, operations
├── [D] Diplomacy           → Relations, proposals
├── [V] View Reports        → Turn results, intel
├── [S] Submit Turn         → Preview KDL → Confirm
└── [Q] Quit
```

### Order Entry Flow

1. Navigate menus to enter orders (fleet moves, builds, research, etc.)
2. Orders accumulate in memory as you navigate
3. `[S] Submit Turn` shows KDL preview of all pending orders
4. Confirm writes KDL to `data/games/{id}/orders/` directory
5. Daemon picks up and processes on next turn resolution

### Example: Fleet Orders Screen

```
┌─ Fleet Orders ─────────────────────────────────────┐
│                                                    │
│  Select fleet:                                     │
│                                                    │
│  [1] Alpha Fleet @ Arrakis (3 ships)              │
│      CV, DD, DD - Status: Active                  │
│  [2] Beta Fleet @ Caladan (5 ships)               │
│      BB, CA, CA, DD, DD - Status: Active          │
│  [3] Scout Group @ Giedi Prime (1 scout)          │
│      SC - Status: Active                          │
│                                                    │
│  [B] Back to Main Menu                            │
│                                                    │
└────────────────────────────────────────────────────┘
```

### TUI Library

Uses **illwill** - pure Nim terminal UI library. Simple, no C dependencies,
sufficient for menu-driven interfaces.

---

## CLI Mode (Order Validation)

### Usage

```bash
ec4x-play validate <game-id> orders.kdl --house=1
```

### Purpose

Validates a KDL order file against game state without submitting. Returns:
- **Success:** Exit code 0, "Orders valid" message
- **Failure:** Exit code 1, list of errors with line numbers

### What Gets Validated

- **Entity existence:** Fleet/colony/system IDs exist
- **Ownership:** Entities belong to the specified house
- **Resource limits:** Treasury covers build costs, EBP covers operations
- **Tech requirements:** Ship classes unlocked, terraform tech available
- **Fleet constraints:** Ships per fleet, command capacity
- **Order conflicts:** No duplicate fleet orders, valid targets

### Error Format

```
Validation failed for house 1, turn 5:

  Line 12: Fleet 99 does not exist
  Line 18: Colony 5 is not owned by house 1
  Line 25: Insufficient treasury: need 500 PP, have 300 PP
  Line 31: Invalid ship class: battlewagon
  Line 45: Fleet 3 already has an order this turn
```

### Integration

- **Claude/LLM:** Validate before file drop, fix errors, retry
- **CI/Scripts:** Automated order validation in test pipelines
- **TUI:** Same validation runs before submit confirmation

---

## Claude/LLM Workflow

Claude plays EC4X by reading game state from SQLite and generating KDL orders.

### Step 1: Read Fog-of-War State

Query the game database directly:

```bash
sqlite3 data/games/{game-id}/ec4x.db
```

**Key tables for fog-of-war filtered view:**

```sql
-- Own colonies (full details)
SELECT * FROM colonies WHERE owner_house_id = ?;

-- Own fleets and ships
SELECT * FROM fleets WHERE owner_house_id = ?;
SELECT s.* FROM ships s
JOIN fleets f ON s.fleet_id = f.id
WHERE f.owner_house_id = ?;

-- Intel on enemy systems
SELECT * FROM intel_systems WHERE house_id = ?;

-- Intel on enemy fleets (detected)
SELECT * FROM intel_fleets WHERE house_id = ?;

-- Intel on enemy colonies (scouted/spied)
SELECT * FROM intel_colonies WHERE house_id = ?;

-- Diplomatic relations
SELECT * FROM diplomacy WHERE house_a_id = ? OR house_b_id = ?;

-- Current turn and game phase
SELECT turn, phase FROM games;
```

See `docs/architecture/storage.md` for complete schema documentation.

### Step 2: Generate KDL Orders

Write orders following the format in `docs/engine/kdl-commands.md`:

```kdl
orders turn=5 house=(HouseId)1 {
  fleet (FleetId)1 {
    move to=(SystemId)15 roe=6
  }
  fleet (FleetId)2 patrol
  
  build (ColonyId)1 {
    ship destroyer quantity=2
  }
  
  research {
    economic 100
    science 50
  }
}
```

### Step 3: Validate Orders

```bash
ec4x-play validate {game-id} orders.kdl --house=1
```

If errors, fix and re-validate.

### Step 4: Submit Orders

Drop the validated KDL file to the orders directory:

```bash
cp orders.kdl data/games/{game-id}/orders/house_1_turn_5.kdl
```

Daemon will pick up orders on next turn resolution.

### Step 5: Force Turn Resolution (Optional)

For dev testing, force immediate turn resolution:

```bash
ec4x resolve {game-id}
```

### Example Claude Session

```
Human: Here's the game state for House 1, Turn 5:
       [pastes SQLite query results]

Claude: [analyzes state, generates KDL order file]
```

---

## Architecture

### Module Structure

```
src/player/
├── player.nim              # Entry point, mode dispatch
├── cli/
│   └── validate.nim        # Order validation command
├── tui/
│   ├── app.nim             # TUI main loop (illwill)
│   ├── screens/
│   │   ├── main_menu.nim
│   │   ├── fleet_orders.nim
│   │   ├── colony_mgmt.nim
│   │   ├── build_orders.nim
│   │   ├── research.nim
│   │   ├── espionage.nim
│   │   ├── diplomacy.nim
│   │   ├── reports.nim
│   │   └── submit.nim
│   └── widgets/
│       └── menu.nim        # Reusable menu component
└── state/
    └── game_view.nim       # Load PlayerState from DB
```

### Dependencies

- **Engine validation**: Reuses `src/engine/` order validation logic
- **SQLite**: Reads game state via `src/daemon/persistence/`
- **KDL generation**: Outputs orders per `docs/engine/kdl-commands.md`
- **illwill**: TUI library (pure Nim, no C deps)

### Build

```bash
nimble buildPlayer
```

---

## Related Documentation

- [KDL Commands Spec](../engine/kdl-commands.md) - Order format specification
- [Storage Architecture](../architecture/storage.md) - SQLite schema and queries
- [Architecture Overview](../architecture/overview.md) - System components
- [Dataflow](../architecture/dataflow.md) - Turn cycle and order submission