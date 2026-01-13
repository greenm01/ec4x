# Play-Testing with Claude as Opponent

**Status:** Design Document (Implementation Pending Engine Refactor)
**Last Updated:** 2025-12-25
**Priority:** Post-refactor, pre-AI development

---

## Overview

EC4X is fundamentally a **social game** focused on human interaction, diplomacy, and strategy. We can play-test immediately using Claude as an intelligent opponent.

This approach provides:
- ✅ **Zero AI coding** - No complex AI debugging or training needed yet
- ✅ **Intelligent opposition** - Claude understands strategy, not random behavior
- ✅ **Explained reasoning** - Every decision comes with strategic commentary
- ✅ **Fast iteration** - Test balance changes immediately
- ✅ **Fog-of-war enforcement** - Claude only sees what its house should see
- ✅ **Transparent debugging** - All orders in human-readable KDL format

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Turn N: Game Execution                        │
│  ./bin/run_simulation --game game_42.db \      │
│                       --pause-at-turn 5         │
└─────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│  SQLite Database: game_42.db                    │
│  ├─ diagnostics (per-turn economic/military)    │
│  ├─ fleet_tracking (fleet positions/composition)│
│  ├─ game_states (full state snapshots)          │
│  └─ intelligence (fog-of-war filtered)          │
└─────────────────────────────────────────────────┘
                      │
                      ▼ (export for House 1)
┌─────────────────────────────────────────────────┐
│  Fog-of-War State Export                        │
│  ./bin/ec4x export-state --house 1 \            │
│                          --turn 5 \              │
│                          --format text \         │
│                          > claude_state.txt      │
│                                                  │
│  Contains:                                       │
│  - My colonies (full details)                    │
│  - My fleets (full composition + orders)         │
│  - My tech levels and treasury                   │
│  - Visible enemy fleets (limited intel)          │
│  - Scouted systems (partial info)                │
│  - Intelligence reports (with quality levels)    │
└─────────────────────────────────────────────────┘
                      │
                      ▼ (Claude reads state)
┌─────────────────────────────────────────────────┐
│  Claude Strategy Session                        │
│  - Analyze strategic situation                   │
│  - Consider diplomatic options                   │
│  - Plan fleet movements                          │
│  - Prioritize research/construction              │
│  - Write orders with reasoning                   │
└─────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│  KDL Orders File: orders_house1_turn6.kdl       │
│  (Human-readable, version-controllable)         │
└─────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│  Turn N+1: Execute Orders                       │
│  ./bin/run_simulation --game game_42.db \       │
│                       --orders orders_house1.kdl \│
│                       --pause-at-turn 6          │
└─────────────────────────────────────────────────┘
```

---

## KDL Orders Format

### Example Orders File

```kdl
// EC4X Orders - House 1 (Atreides) - Turn 6
// Strategic Assessment: Enemy expanding aggressively to the south
// Defensive posture with economic focus

// ============================================================
// FLEET ORDERS
// ============================================================

fleet id=123 name="Strike Force Alpha" {
    order "move"
    destination "system_8"

    // Reasoning: Enemy colonization fleet spotted heading toward System 8.
    // Intercept before they establish foothold. Our 10 destroyers + 5 cruisers
    // should outmatch their escort (intel shows 6 frigates).
}

fleet id=456 name="Colony Group Beta" {
    order "colonize"
    destination "system_15"
    etacCount 2

    // Reasoning: System 15 is Lush class (1200 PU potential), adjacent to
    // our homeworld. Establishes secure buffer zone and economic growth.
    // Low risk - no enemy activity detected within 3 jumps.
}

fleet id=789 name="Scout Wing Gamma" {
    order "scout"
    destination "system_22"

    // Reasoning: System 22 is 2 jumps from enemy homeworld. Critical intel
    // needed on their fleet strength and tech levels before committing to
    // offensive operations.
}

fleet id=234 name="Home Defense" {
    order "patrol"
    system "system_1"

    // Reasoning: Our homeworld. Maintain defensive posture with our
    // 15 frigates + 3 starbases. Enemy attempted raid last turn.
}

// ============================================================
// COLONY ORDERS
// ============================================================

colony system="arrakis" {
    production {
        build "destroyer" quantity=2
        build "army" quantity=3
        build "ground_battery" quantity=1
    }
    taxRate 25

    // Reasoning: Arrakis is our primary industrial world (420 IU).
    // Building fleet assets for Strike Force Alpha reinforcement.
    // Armies + battery defend against invasion (avoiding undefended penalty).
    // Low tax rate (25%) maintains high population growth (30% natural).
}

colony system="caladan" {
    production {
        build "spaceport"
        build "fighter" quantity=5
    }
    taxRate 30

    // Reasoning: Caladan needs infrastructure. Spaceport enables
    // shipyard construction next turn. Fighters provide cheap defense.
}

colony system="giedi_prime" {
    production {
        build "troop_transport" quantity=1
        build "marine" quantity=6
    }
    taxRate 35

    // Reasoning: Preparing invasion capability. 6 marines loaded on
    // 1 transport creates rapid reaction force for opportunistic captures.
}

// ============================================================
// RESEARCH ALLOCATION
// ============================================================

research {
    erp 400  // Economic Level: 3 → 4 (costs 320 ERP, pushing hard)
    srp 150  // Science Level: maintain at 1 (12 SRP/turn needed)
    trp 100  // Construction Tech: slow advance toward CST2

    // Reasoning: Economic advantage is critical. EL4 gives +20% production
    // modifier (0.05/level). With 3 major colonies producing 600+ PP/turn,
    // that's +120 PP/turn permanent boost. Worth the investment.
    // Science/Tech on maintenance mode for now.
}

// ============================================================
// DIPLOMATIC ACTIONS
// ============================================================

diplomacy {
    propose house="house_2" pact="trade"

    // Reasoning: House 2 (Ordos) is neutral and geographically distant.
    // Trade pact gives +5 prestige and potential ally against House 3
    // (Harkonnen) who is the immediate threat. Low risk, high value.
}

// ============================================================
// STRATEGIC NOTES
// ============================================================

// Turn 6 Strategy Summary:
//
// THREAT ASSESSMENT:
// - House 3 (Harkonnen): Enemy status, 8 systems, aggressive expansion
// - House 2 (Ordos): Neutral, 5 systems, economically focused
// - House 4 (Corrino): Unknown (no scouts, last intel 3 turns old)
//
// OBJECTIVES THIS TURN:
// 1. Block Harkonnen colonization at System 8 (military)
// 2. Secure System 15 for economic growth (expansion)
// 3. Gather intel on Corrino capabilities (reconnaissance)
// 4. Boost EL to 4 for long-term economic advantage (research)
// 5. Establish trade relations with Ordos (diplomacy)
//
// RISKS:
// - Strike Force Alpha may face larger enemy fleet than intel suggests
//   (Visual quality only, no tech levels known)
// - Research investment (400 ERP) reduces immediate military capacity
// - Invasion force at Giedi Prime won't be ready for 2-3 turns
//
// CONTINGENCIES:
// - If System 8 is heavily defended, abort and fall back to System 5
// - If Ordos rejects trade, consider NAP instead
// - If Corrino scout reveals major buildup, divert Colony Group Beta to defense
```

---

## Implementation Requirements

### 1. Fog-of-War State Export

**Command:**
```bash
./bin/ec4x export-state --house <id> --turn <n> --format <text|json>
```

**Output Format (Text):**
```
==============================================================
EC4X GAME STATE - HOUSE 1 (ATREIDES) - TURN 6
==============================================================

STRATEGIC OVERVIEW
------------------
Treasury: 1,450 PP
Prestige: 275 points (Rank: 2nd of 4)
Colonies: 3 systems
Total Population: 2,060 PU
Industrial Capacity: 520 IU
Tech Levels: EL3, SL1, CST1, WEP2, TER1, ELI1, CIC1

DIPLOMATIC STATUS
-----------------
House 2 (Ordos):     Neutral
House 3 (Harkonnen): Enemy
House 4 (Corrino):   Neutral

MY COLONIES
-----------
System 1 (Arrakis) - Homeworld
  Class: Abundant Eden (2,500 PU max)
  Population: 840 PU (33% capacity)
  Industrial: 420 IU (50% efficiency)
  Tax Rate: 25%
  Facilities: Spaceport, Shipyard, Drydock, Starbase ×3
  Defense: 12 Armies, 3 Ground Batteries, Planetary Shield
  Production: +180 PP/turn
  Build Queue: 2× Destroyer (120 PP, 2 turns), 3× Army (30 PP, 1 turn)

System 5 (Caladan)
  Class: Rich Lush (1,800 PU max)
  Population: 620 PU (34% capacity)
  Industrial: 100 IU (16% efficiency - new colony)
  Tax Rate: 30%
  Facilities: None (building Spaceport)
  Defense: 2 Armies
  Production: +45 PP/turn
  Build Queue: Spaceport (40 PP, 1 turn), 5× Fighter (50 PP, 2 turns)

[... full colony details ...]

MY FLEETS
---------
Fleet 123 "Strike Force Alpha" - System 5
  Commander: Admiral Hassan
  Composition:
    - 10× Destroyer (AS=3, DS=4, WEP2)
    - 5× Cruiser (AS=6, DS=7, WEP2)
  Command Cost: 22 / Command Rating: 30
  Current Orders: Move to System 8 (ETA: Turn 7)
  Fuel: 3 turns remaining

[... full fleet details ...]

INTELLIGENCE REPORTS
--------------------
System 8 (Neutral Space)
  Last Scouted: Turn 5 (1 turn ago)
  Planet Class: Abundant Benign (800 PU)
  Ownership: Unclaimed
  Enemy Activity: DETECTED
    - House 3 fleet spotted (Visual Quality, Turn 5)
    - 6× Frigate, 2× Troop Transport
    - Orders: Unknown (moving toward system)
    - Tech Levels: Unknown (Visual intel only)

System 22 (Enemy Territory - House 4)
  Last Scouted: Turn 3 (3 turns old - STALE)
  Planet Class: Poor Harsh (300 PU)
  Ownership: House 4 (Corrino)
  Enemy Activity: [DATA OUTDATED]

[... intelligence reports ...]

VISIBLE ENEMY FORCES
--------------------
House 3 (Harkonnen) - Last Contact: Turn 5
  Known Colonies: 6 systems (confirmed)
  Estimated Fleet Strength: 40-50 capital ships
  Tech Levels: Unknown (no spy-quality intel)
  Recent Activity:
    - Colonization attempt toward System 8 (Turn 5)
    - Fleet buildup at System 12 (Turn 4, 12× Destroyer spotted)

[... enemy intel summary ...]

==============================================================
END STATE EXPORT
==============================================================
```

**SQLite Schema Changes Needed:**
- Add `intelligence` table storing fog-of-war filtered intel per house
- Add quality levels (Perfect, Spy, Visual, None) to fleet reports
- Add staleness indicators (turn last updated)
- Add `visible_systems` and `visible_fleets` views per house

### 2. KDL Orders Parser

**Module:** `src/engine/config/orders_config.nim`

```nim
type
  FleetOrderKind* = enum
    Move, Colonize, Scout, Patrol, Bombard, Invade, Blitz, Guard,
    Blockade, TransferShips, TransferCargo, Rebase, Repair

  FleetOrder* = object
    fleetId*: FleetId
    fleetName*: string
    orderKind*: FleetOrderKind
    destination*: SystemId
    etacCount*: int32  # For colonization
    reasoning*: string  # Optional commentary

  ColonyOrder* = object
    systemId*: SystemId
    builds*: seq[BuildItem]
    taxRate*: int32
    reasoning*: string

  ResearchOrder* = object
    erp*: int32
    srp*: int32
    trp*: int32
    reasoning*: string

  DiplomacyOrder* = object
    targetHouse*: HouseId
    action*: string  # "propose", "accept", "reject"
    pactType*: string  # "trade", "nap", "alliance"
    reasoning*: string

  HouseOrders* = object
    houseId*: HouseId
    turn*: int32
    fleetOrders*: seq[FleetOrder]
    colonyOrders*: seq[ColonyOrder]
    research*: ResearchOrder
    diplomacy*: seq[DiplomacyOrder]

proc parseOrdersKdl*(path: string): HouseOrders =
  ## Parse KDL orders file into structured orders
  let doc = loadKdlConfig(path)
  var ctx = newContext(path)

  # Parse fleet orders
  for node in doc:
    if node.name == "fleet":
      let order = parseFleetOrder(node, ctx)
      result.fleetOrders.add(order)
    elif node.name == "colony":
      let order = parseColonyOrder(node, ctx)
      result.colonyOrders.add(order)
    elif node.name == "research":
      result.research = parseResearchOrder(node, ctx)
    elif node.name == "diplomacy":
      let order = parseDiplomacyOrder(node, ctx)
      result.diplomacy.add(order)
```

### 3. Orders Executor

**Module:** `src/engine/systems/orders/executor.nim`

```nim
proc executeHouseOrders*(game: var GameState, orders: HouseOrders) =
  ## Apply parsed orders to game state
  ## This integrates with existing order queue system

  # Validate orders (fog-of-war checks, resource availability)
  let validation = validateOrders(game, orders)
  if not validation.valid:
    logError("Orders", "Invalid orders for house", "house=", orders.houseId,
             " errors=", validation.errors)
    return

  # Apply fleet orders
  for order in orders.fleetOrders:
    game.applyFleetOrder(order)

  # Apply colony orders
  for order in orders.colonyOrders:
    game.applyColonyOrder(order)

  # Apply research allocation
  game.applyResearchOrder(orders.research)

  # Apply diplomatic actions
  for action in orders.diplomacy:
    game.applyDiplomacyOrder(action)

  logInfo("Orders", "Applied orders for house", "house=", orders.houseId,
          " fleets=", orders.fleetOrders.len, " colonies=", orders.colonyOrders.len)
```

---

## Play-Testing Workflow

### Initial Setup (One Time)

1. **Start new game:**
   ```bash
   ./bin/ec4x new-game --players 2 --seed 42 --map-size medium
   ```

2. **Play Turn 1 as your house:**
   - Issue orders via CLI or config files
   - Set tax rates, research priorities, fleet movements

3. **Run turn 1:**
   ```bash
   ./bin/run_simulation --game game_42.db --pause-at-turn 2
   ```

### Iterative Play (Each Turn)

1. **Export Claude's game state:**
   ```bash
   ./bin/ec4x export-state --house 1 --turn 2 --format text > claude_turn2.txt
   ```

2. **Share state with Claude:**
   - Paste `claude_turn2.txt` into conversation
   - Claude analyzes strategic situation
   - Claude writes `orders_house1_turn3.kdl` with reasoning

3. **Review Claude's orders:**
   - Read the KDL file (human-readable!)
   - Check reasoning in comments
   - Optionally modify orders if testing specific scenarios

4. **Execute turn:**
   ```bash
   ./bin/run_simulation --game game_42.db \
                        --orders orders_house1_turn3.kdl \
                        --pause-at-turn 3
   ```

5. **Analyze results:**
   ```bash
   ./bin/ec4x show-results --game game_42.db --turn 3
   ```

6. **Repeat for next turn**

---

## Why This Approach?

### Advantages Over Immediate AI Development

Using Claude as an initial opponent allows for excellent intelligence quality, immediate balance feedback, and transparent reasoning during the early stages of development.

### Why Delay AI Development?

1. **Engine stability first** - AI can't test a broken engine
2. **Social game focus** - EC4X is designed for human players (see specs)
3. **Faster iteration** - Test balance changes without AI retraining
4. **Better AI requirements** - After playing, you'll know what AI needs to do
5. **Avoid premature optimization** - Don't build AI for broken mechanics

### When to Build AI?

**Build AI when:**
- ✅ Engine is stable and well-tested
- ✅ Core mechanics feel good (from Claude play-testing)
- ✅ Balance is reasonably tuned
- ✅ You have dozens of complete games under your belt
- ✅ You understand what "good play" looks like

## Integration with Existing Systems

### SQLite Diagnostics

Existing `diagnostics` table already captures per-turn state. Add fog-of-war filtering:

```sql
-- New view: House 1's visible game state
CREATE VIEW house1_visible_state AS
SELECT * FROM diagnostics
WHERE house_id = 1
   OR house_id IN (SELECT house FROM house1_intel WHERE quality >= 'Visual');
```

### Existing Test Infrastructure

101+ integration tests verify engine correctness. Claude play-testing verifies:
- ✅ **Balance** - Are mechanics fun?
- ✅ **Pacing** - Do games finish in reasonable turns?
- ✅ **Strategy depth** - Are there interesting decisions?
- ✅ **Edge cases** - Does weird stuff happen?

### Future: Multi-House Claude

Claude can play 2-3 opponent houses simultaneously:

```bash
# Export state for all AI houses
./bin/ec4x export-state --house 1 --turn 5 > claude_house1.txt
./bin/ec4x export-state --house 2 --turn 5 > claude_house2.txt
./bin/ec4x export-state --house 3 --turn 5 > claude_house3.txt

# Claude writes orders for each
# (separate conversations to maintain fog-of-war isolation)
```

---

## Next Steps

### Phase 1: Post-Refactor (Priority)

1. **Implement state export** (`export-state` command)
   - Query SQLite for fog-of-war filtered state
   - Format as human-readable text
   - Estimate: 1 day

2. **Implement orders parser** (`orders_config.nim`)
   - Parse KDL orders files
   - Validate against game rules
   - Estimate: 1 day

3. **Implement orders executor** (`executor.nim`)
   - Apply parsed orders to game state
   - Integrate with existing order queue
   - Estimate: 1 day

4. **Test end-to-end workflow**
   - Play 5-10 turns against Claude
   - Iterate on export format and orders schema
   - Document pain points
   - Estimate: 2-3 days

**Total Estimate: 1 week to playable prototype**

### Phase 2: Refinement (As Needed)

1. Improve state export formatting (based on play-testing feedback)
2. Add strategic summaries (automatic threat assessment)
3. Add order validation with helpful error messages
4. Add replay/review mode (view historical turns)
5. Add order templates (common patterns as starting points)

### Phase 3: AI Development (Future)

Only after 20-30 complete games via Claude play-testing:
1. Analyze common strategies from Claude's orders
2. Identify patterns worth automating
3. Consider future AI development (neural networks, etc.)

---

## Design Philosophy

**EC4X is a social game.**

From the game spec (01-gameplay.md):
> The server processes orders mechanically but doesn't handle diplomacy.
> You negotiate alliances, betray pacts, and coordinate strategies through
> your preferred communication method—Discord, Signal, email, or face-to-face
> trash talk at the table. The server doesn't care how you scheme; it only
> processes the orders you submit. **Diplomacy is between humans.**

AI opponents are a **nice-to-have**, not core functionality. The game is designed for:
- 2-12 human players
- Asynchronous turn-based play
- Diplomatic intrigue and betrayal
- Strategic empire building over weeks/months

Using Claude for play-testing aligns perfectly with this philosophy:
- Test the engine thoroughly
- Understand balance and pacing
- Experience gameplay flow
- Build AI only if/when it adds value

---

## References

- [Game Spec Index](../specs/index.md) - EC4X overview and structure
- [Gameplay Rules](../specs/01-gameplay.md) - Turn structure, prestige, victory
- [Operations](../specs/06-operations.md) - Fleet orders and movement
- [Intelligence](../specs/09-intelligence.md) - Fog-of-war mechanics
- [KDL Spec](https://kdl.dev/spec/) - KDL document format

---

**Document Status:** Ready for implementation post-refactor
**Approval Required:** No - design document for future reference
**Dependencies:** Engine refactor completion, SQLite diagnostics system
