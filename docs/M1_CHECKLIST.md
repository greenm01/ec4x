# Milestone 1 Implementation Checklist

## Goal
Playable 2-player game via moderator commands.

## What You're Building

```bash
# Create game
$ ./bin/moderator new game1 --players=2

# Submit orders (manually create TOML files)
$ cat > alpha_orders.toml
$ cat > beta_orders.toml

# Moderator loads and validates orders
$ ./bin/moderator orders game1 alpha_orders.toml --house=alpha
$ ./bin/moderator orders game1 beta_orders.toml --house=beta

# Resolve turn (calls engine)
$ ./bin/moderator resolve game1

# View results
$ ./bin/moderator view game1
$ ./bin/moderator results game1 --house=alpha
```

---

## Implementation Tasks

### Phase 1: Engine (Fill in TODOs)

#### src/engine/combat.nim ⚠️ HIGH PRIORITY

**Current status:** Stubs with TODOs

**Implement:**
- [ ] `calculateDamage()` - Ship-to-ship combat math
- [ ] `applyDamageToFleet()` - Distribute damage, remove destroyed ships
- [ ] `resolveBattle()` - Main combat function
- [ ] Skip for M1: `resolveBombardment()`, `resolveInvasion()`

**Tests:**
```bash
nimble test # Should pass combat tests when done
```

**Estimated complexity:** Medium
**Time investment:** This is the hardest part of M1

---

#### src/engine/economy.nim ⚠️ HIGH PRIORITY

**Current status:** Stubs with TODOs

**Implement:**
- [ ] `calculateProduction()` - Colony production per turn
- [ ] `calculateHouseIncome()` - Sum all colonies
- [ ] `startConstruction()` - Begin ship/building construction
- [ ] `advanceConstruction()` - Progress construction each turn
- [ ] `completeShipConstruction()` - Deploy finished ship
- [ ] Skip for M1: Advanced research, complex upkeep

**Minimal viable version:**
```nim
proc calculateProduction*(colony: Colony, techLevel: int): ProductionOutput =
  # Simple formula for M1
  result.production = colony.population * 10
  result.credits = colony.industry * 5
  result.research = 0  # Skip research in M1
```

---

#### src/engine/resolve.nim ⚠️ INTEGRATE

**Current status:** Framework exists, needs TODOs filled

**Review and complete:**
- [ ] Phase 1 (Income): Call `economy.calculateHouseIncome()`
- [ ] Phase 2 (Command): Process movement orders
- [ ] Phase 3 (Conflict): Call `combat.resolveBattle()`
- [ ] Phase 4 (Maintenance): Call `economy.advanceConstruction()`

**This ties everything together!**

---

### Phase 2: Moderator CLI (New Commands)

#### src/main/moderator.nim ⚠️ HIGH PRIORITY

**Current status:** Has `new`, `start`, `maint`, `stats` commands

**Add new commands for M1:**

**1. `moderator orders <dir> <file> --house=<name>`**
```nim
proc ordersCmd(dir: string, ordersFile: string, house: string): int =
  ## Load and validate order file for a house
  # 1. Parse TOML file
  # 2. Load game state from JSON
  # 3. Validate orders against gamestate
  # 4. Save to orders/<house>_turn<N>.json
  # 5. Echo "Orders submitted for <house>"
```

**2. `moderator resolve <dir>`**
```nim
proc resolveCmd(dir: string): int =
  ## Resolve current turn
  # 1. Load game state from JSON
  # 2. Load all orders from orders/
  # 3. Call engine.resolveTurn(state, orders)
  # 4. Save new state to JSON
  # 5. Write turn summary to results/
  # 6. Echo summary of what happened
```

**3. `moderator view <dir>`**
```nim
proc viewCmd(dir: string): int =
  ## Display current game state
  # 1. Load game state from JSON
  # 2. Pretty-print:
  #    - Turn number
  #    - Each house: fleets, colonies, prestige
  #    - Systems owned
```

**4. `moderator results <dir> --house=<name>`**
```nim
proc resultsCmd(dir: string, house: string): int =
  ## Show turn results for specific house
  # 1. Load turn log from results/turn_N.json
  # 2. Filter to events visible to house
  # 3. Pretty-print:
  #    - Movement summary
  #    - Combat results
  #    - Construction completed
  #    - Income/expenses
```

---

### Phase 3: Game State Storage (Simple)

#### Create: src/storage/json_storage.nim (NEW FILE)

**Why:** Need to save/load game state between commands

```nim
## Simple JSON storage for M1
## (Replace with SQLite in M2)

import std/json
import ../engine/gamestate

proc saveGameState*(path: string, state: GameState) =
  ## Save game state to JSON file
  let jsonNode = %* state  # Nim's JSON serialization
  writeFile(path / "game_state.json", $jsonNode)

proc loadGameState*(path: string): GameState =
  ## Load game state from JSON file
  let jsonStr = readFile(path / "game_state.json")
  let jsonNode = parseJson(jsonStr)
  result = to(jsonNode, GameState)

proc saveOrders*(path: string, house: HouseId, turn: int, orders: seq[Order]) =
  ## Save orders to JSON file
  let jsonNode = %* orders
  writeFile(path / "orders" / &"{house}_turn{turn}.json", $jsonNode)

proc loadAllOrders*(path: string, turn: int): Table[HouseId, seq[Order]] =
  ## Load all orders for a turn
  for file in walkFiles(path / "orders" / &"*_turn{turn}.json"):
    let house = extractHouseId(file)
    let jsonStr = readFile(file)
    let orders = to(parseJson(jsonStr), seq[Order])
    result[house] = orders
```

---

## Directory Structure for M1

```
game_data/
└── game1/
    ├── game_state.json       # Current state
    ├── config.toml           # Game config
    ├── orders/
    │   ├── alpha_turn1.json
    │   └── beta_turn1.json
    └── results/
        ├── turn1_summary.txt
        └── turn1_log.json
```

---

## Testing Strategy

### Unit Tests (As You Go)

```bash
# Test each function individually
nimble test

# Focus on:
# - Combat calculations
# - Production calculations
# - Order validation
```

### Manual Integration Test (When Done)

```bash
# Create game
./bin/moderator new test_game --players=2

# Create order files
cat > alpha_orders.toml <<EOF
[[order]]
fleet_id = "fleet-alpha-1"
order_type = "Move"
target_system = "delta"
EOF

cat > beta_orders.toml <<EOF
[[order]]
fleet_id = "fleet-beta-1"
order_type = "Hold"
EOF

# Submit orders
./bin/moderator orders test_game alpha_orders.toml --house=alpha
./bin/moderator orders test_game beta_orders.toml --house=beta

# Resolve turn
./bin/moderator resolve test_game

# View results
./bin/moderator view test_game
./bin/moderator results test_game --house=alpha

# Play multiple turns!
# Repeat: edit orders → submit → resolve → view
```

---

## What to Skip for M1

### Deferred Features

- ❌ Diplomacy (no alliances, treaties)
- ❌ Espionage (no spy operations)
- ❌ Advanced economy (skip complex research)
- ❌ Fog of war (both players see everything)
- ❌ All 16 order types (focus on: Move, Hold, Bombard, Colonize)
- ❌ SQLite (JSON files are fine)
- ❌ Daemon (manual resolution)
- ❌ Client tool (moderator is enough)
- ❌ Network play (localhost only)

### Keep It Simple

**Combat:** Basic ship-to-ship only
- Ships have HP
- Ships attack each other
- Damaged ships are removed
- Winner holds the field

**Economy:** Basic production only
- Colonies produce resources
- Resources build ships
- Ships take multiple turns to build
- Skip: complex trade, advanced buildings

**Movement:** Basic lane traversal
- Fleets move one lane per turn
- Use existing pathfinding
- Skip: advanced movement rules

---

## Success Criteria

M1 is **complete** when:

- [ ] Can create 2-player game
- [ ] Can submit orders for both players
- [ ] Can resolve turn (engine processes orders)
- [ ] Combat works (ships fight, take damage, die)
- [ ] Movement works (fleets change systems)
- [ ] Economy works (production, construction)
- [ ] Can view game state at any time
- [ ] Can play multiple consecutive turns
- [ ] All unit tests pass
- [ ] Manual playthrough works end-to-end

**Then invite a friend to play!**

---

## Development Order (Suggested)

**Week 1: Core Engine**
1. Day 1-2: `combat.nim` - Get battles working
2. Day 3-4: `economy.nim` - Get production working
3. Day 5: `resolve.nim` - Tie phases together
4. Day 6-7: Test and fix bugs

**Week 2: Moderator CLI**
1. Day 8: `json_storage.nim` - Save/load state
2. Day 9: `orders` command - Submit orders
3. Day 10: `resolve` command - Process turn
4. Day 11: `view` and `results` commands
5. Day 12-14: Integration testing, bug fixes, playthrough

**Flexibility:** Work at your own pace, skip days as needed!

---

## Getting Unstuck

### If combat is hard:
Start with minimal version:
```nim
# Each ship deals 1 damage per turn
# First side to lose all ships loses
```
Add complexity later.

### If economy is hard:
Use fixed values:
```nim
# Every colony produces 10 resources/turn
# Every ship costs 50 resources
# Ships take 5 turns to build
```
Add formulas later.

### If moderator CLI is confusing:
Focus on one command at a time:
1. Get `new` working (already done)
2. Get `view` working (just display JSON)
3. Get `resolve` working (call engine)
4. Add `orders` last

### If stuck for > 1 day:
- Skip the feature (mark TODO)
- Move to next task
- Come back later with fresh eyes

---

## Next Steps After M1

Once M1 works:
1. **Playtest!** Invite friend, play a game
2. **Get feedback** - Is it fun? What's broken?
3. **Fix critical bugs**
4. **Tag release:** `git tag milestone-1`
5. **Take a break!** You earned it
6. **Start M2** when ready (SQLite)

---

*Remember: Perfect is the enemy of done. Ship M1 even if it's rough!*
