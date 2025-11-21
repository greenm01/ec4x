# AI Continuation Guide for EC4X

This document helps AI assistants (like Claude Code) quickly resume work on EC4X after context loss or in new sessions.

---

## Quick Orientation (30 seconds)

**What is EC4X?**
- Turn-based 4X space strategy game (like Master of Orion)
- Asynchronous multiplayer over Nostr protocol
- Offline-first design (complete game engine, then add network layer)

**Current Status:**
- ✅ **Combat System**: 100% complete (space, ground, starbase)
- 🎯 **Next**: Economy & production system
- **Phase**: Milestone 5 of 13 (see `IMPLEMENTATION_ROADMAP.md`)

**Your First Actions:**
1. Read `docs/IMPLEMENTATION_PROGRESS.md` (current status)
2. Read `docs/IMPLEMENTATION_ROADMAP.md` (overall plan)
3. Check git status for uncommitted work
4. Run a quick test: `nim c -r tests/unit/test_hex.nim`

---

## Project Structure Overview

```
ec4x/
├── src/
│   ├── common/                    # Shared types
│   │   ├── types/                # Core type definitions
│   │   ├── hex.nim               # Hex coordinate system
│   │   └── system.nim            # Star system types
│   ├── engine/                    # Game logic (pure Nim, no network)
│   │   ├── combat/               # Combat system (9 modules, COMPLETE)
│   │   ├── starmap.nim           # Map generation, pathfinding (COMPLETE)
│   │   ├── squadron.nim          # Squadron management (COMPLETE)
│   │   ├── economy.nim           # Production, research (PARTIAL)
│   │   ├── orders.nim            # Order validation (COMPLETE)
│   │   ├── resolve.nim           # Turn resolution (FRAMEWORK EXISTS)
│   │   └── gamestate.nim         # State management (COMPLETE)
│   ├── transport/nostr/          # Network layer (NOT STARTED)
│   ├── daemon/                    # Turn processor (NOT STARTED)
│   └── main/                      # Entry points
├── tests/
│   ├── unit/                      # Unit tests
│   ├── combat/                    # Combat tests (10k+ passing)
│   ├── integration/               # Integration tests
│   ├── scenarios/                 # Hand-crafted scenarios
│   └── fixtures/                  # Reusable test data
├── docs/
│   ├── IMPLEMENTATION_PROGRESS.md # ← READ THIS FIRST
│   ├── IMPLEMENTATION_ROADMAP.md  # Overall plan
│   ├── AI_CONTINUATION_GUIDE.md   # This file
│   ├── specs/                     # Game rules (authoritative)
│   │   ├── operations.md          # Combat, fleet orders
│   │   ├── economy.md             # Production, research
│   │   ├── assets.md              # Ships, buildings
│   │   └── reference.md           # Stats, costs
│   └── archive/                   # Historical docs
└── .gitignore
```

---

## Critical Context

### Tech Stack
- **Language**: Nim (https://nim-lang.org/)
- **Build**: Nimble + Nix development environment
- **Testing**: Native Nim `unittest` framework
- **Target**: CLI/TUI application (no GUI yet)

### Design Principles

1. **Offline-First**: Complete game engine works without network
2. **Transport-Agnostic**: Game logic independent of Nostr
3. **Spec-Driven**: Every mechanic references `docs/specs/` section numbers
4. **Test-First**: Tests written as features implemented
5. **Deterministic**: Same inputs → same outputs (enables testing)

### Coding Style

**Good**:
```nim
# Clear procedure names
proc calculateDamage(attacker: CombatSquadron, defender: CombatSquadron): int

# Spec references in comments
# Per operations.md:7.3.3 - Combat Effectiveness Rating
let cerRoll = rng.rand(1..10)

# Explicit error handling
if fleet.squadrons.len == 0:
  raise newException(ValueError, "Cannot resolve combat with empty fleet")
```

**Avoid**:
```nim
# Clever one-liners
let x = if a > b: c else: if d < e: f else: g  # Hard to read

# Unexplained magic numbers
if roll > 7: applyBonus(3)  # What is 7? What is 3?

# Abbreviated names
proc prc(sq: Sq, t: TF): R  # Unclear intent
```

---

## Common Tasks

### Adding a New Combat Scenario

**Location**: `tests/scenarios/balance/` or `tests/combat/test_space_combat.nim`

**Template**:
```nim
proc scenario_YourScenarioName*() =
  echo "\n=== Scenario: Your Scenario Description ==="
  echo "Design: What you're testing"
  echo "Expected: What should happen\n"

  # Create fleets (use fixtures or build inline)
  let attackers = testFleet_BalancedCapital("house-alpha", systemId = 1)
  let defenders = testFleet_SingleScout("house-beta", systemId = 1)

  # Create task forces
  let attackerTF = TaskForce(
    house: "house-alpha",
    squadrons: attackers,
    roe: 6,
    isCloaked: false,
    moraleModifier: 0,
    scoutBonus: false,
    isDefendingHomeworld: false
  )
  # ... similar for defender

  # Run combat
  let battle = BattleContext(
    systemId: 1,
    taskForces: @[attackerTF, defenderTF],
    seed: 12345,
    maxRounds: 20
  )
  let result = resolveCombat(battle)

  # Display results
  let victor = if result.victor.isSome: result.victor.get else: "Draw"
  echo fmt"Result: {victor}"
  echo fmt"Rounds: {result.totalRounds}"
  echo "\nAnalysis: Why this matters for game balance"
```

**Key Points**:
- Use `testFleet_*` from `tests/fixtures/fleets.nim` for common setups
- Always set a seed for deterministic testing
- Explain WHY you're testing this scenario
- Reference spec sections if testing specific rules

### Implementing Economy Features

**Read First**: `docs/specs/economy.md` (full spec)

**Location**: `src/engine/economy.nim`

**Pattern**:
```nim
# Always include spec reference
proc calculateProduction*(colony: Colony, techLevel: int): ProductionOutput =
  ## Calculate production for a colony
  ## Per economy.md:3.2 - Base production calculation

  # Base production from population (per economy.md:3.2.1)
  let basePU = colony.population * colony.planetType.productionMultiplier

  # Infrastructure bonus (per economy.md:3.3)
  let infraBonus = (colony.infrastructure / 100.0) * basePU

  # Tech modifier (per economy.md:4.6 - +10% per WEP level)
  let techBonus = basePU * (techLevel * 0.10)

  result = ProductionOutput(
    totalPU: basePU + infraBonus + techBonus,
    breakdown: ... # For debugging/UI
  )
```

**Testing**:
```nim
# tests/unit/test_economy.nim
test "production calculation with tech bonus":
  let colony = Colony(
    population: 100,
    infrastructure: 50,
    planetType: Eden  # Production multiplier = 1.0
  )

  let output = calculateProduction(colony, techLevel = 2)

  # Base: 100 PU
  # Infrastructure: 50 PU
  # Tech: 20 PU (2 levels × 10%)
  check output.totalPU == 170
```

### Adding Fleet Orders

**Read First**: `docs/specs/operations.md` Section 6.2

**Location**: `src/engine/resolve.nim`

**Pattern**:
```nim
proc resolveMovementOrder*(state: var GameState, houseId: HouseId,
                          order: FleetOrder, events: var seq[GameEvent]) =
  ## Resolve a fleet movement order
  ## Per operations.md:6.2.2 - Move to System

  # Validate fleet exists
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    events.add(GameEvent(
      eventType: OrderFailed,
      message: fmt"Fleet {order.fleetId} not found"
    ))
    return

  let fleet = fleetOpt.get()

  # Find path (pathfinding already implemented in starmap.nim)
  let path = findPath(
    state.starMap,
    fleet.location,
    order.targetSystem.get(),
    fleet
  )

  if not path.found:
    events.add(GameEvent(
      eventType: OrderFailed,
      message: "No valid path to target system"
    ))
    return

  # Apply movement (1-2 lanes per turn per operations.md:6.2.2)
  let lanesToTravel = min(2, path.path.len - 1)
  let newLocation = path.path[lanesToTravel]

  # Update fleet location
  fleet.location = newLocation

  # Check for encounters (hostile fleets trigger combat)
  let encounter = checkForEncounters(state, fleet)
  if encounter.isSome:
    # Trigger combat if hostile per operations.md:7.2
    if encounter.get().isHostile:
      let combatResult = resolveCombat(...)
      events.add(GameEvent(eventType: Combat, data: combatResult))

  events.add(GameEvent(
    eventType: FleetMoved,
    fleetId: order.fleetId,
    fromSystem: fleet.location,
    toSystem: newLocation
  ))
```

---

## Understanding the Combat System

### Architecture

The combat system is **modular** with clear separation of concerns:

```
combat/engine.nim          ← Main entry point (resolveCombat)
  ↓
combat/resolution.nim      ← 3-phase resolution (Ambush, Intercept, Main)
  ↓
combat/targeting.nim       ← Target selection (priority, diplomacy)
combat/cer.nim             ← Combat Effectiveness Rating (1d10 + modifiers)
combat/damage.nim          ← Damage application (destruction protection)
combat/retreat.nim         ← Retreat evaluation (ROE + morale)
  ↓
combat/types.nim           ← Data structures (TaskForce, CombatSquadron, etc.)
```

### Flow Example

```nim
// 1. Create battle context
let battle = BattleContext(
  systemId: 1,
  taskForces: @[attackers, defenders],
  seed: 12345,
  maxRounds: 20
)

// 2. Resolve combat
let result = resolveCombat(battle)  // combat/engine.nim

// 3. Engine calls resolution for each round
for round in 1..maxRounds:
  let roundResult = resolveRound(context)  // combat/resolution.nim

  // 4. Resolution runs 3 phases
  //    Phase 1: Ambush (raiders vs all)
  //    Phase 2: Intercept (fighters vs all)
  //    Phase 3: Main Engagement (capitals vs all)

  // 5. Each phase:
  //    - Select targets (combat/targeting.nim)
  //    - Roll CER (combat/cer.nim)
  //    - Apply damage (combat/damage.nim)

  // 6. Check retreat (combat/retreat.nim)
  // 7. Check termination (all destroyed, stalemate, etc.)

// 8. Return result
return CombatResult(
  victor: some("house-alpha"),
  survivors: [...],
  eliminated: [...],
  totalRounds: 3
)
```

### Key Concepts

**Destruction Protection** (combat/damage.nim):
- Ships can't skip states: Undamaged → Crippled → Destroyed
- Prevents one-shot kills unrealistically
- Tracked via `damageThisTurn` and `crippleRound` fields

**CER (Combat Effectiveness Rating)** (combat/cer.nim):
- 1d10 roll determines effectiveness
- Modifiers: Scouts (+1), Morale (-1 to +2), Desperation (+2)
- Effectiveness multipliers: 0.25×, 0.50×, 0.75×, 1.0× (critical)
- Formula: `effectiveDamage = attackStrength × CER multiplier`

**Target Priority** (combat/targeting.nim):
- Diplomatic filtering: Only attack Enemy-status houses
- Bucket system: Raider < Capital < Destroyer < Fighter < Starbase
- Higher priority = attacked first
- Crippled ships de-prioritized (0.5× weight)

**Desperation Rounds** (combat/resolution.nim):
- Triggered after 5 rounds with no state changes
- Both sides get +2 CER bonus for one round
- Prevents infinite loops in balanced matchups
- If still no damage → tactical stalemate

---

## Spec Navigation

### Most Important Specs

1. **operations.md** - Combat (Section 7), Fleet Orders (Section 6)
2. **economy.md** - Production (Section 3), Research (Section 4)
3. **assets.md** - Ships, Buildings, Facilities
4. **reference.md** - Ship stats, costs, tech requirements
5. **gameplay.md** - Turn structure, victory conditions

### Quick Lookup

**Need ship stats?**
→ `docs/specs/reference.md` Section 9.1

**How does bombardment work?**
→ `docs/specs/operations.md` Section 7.5

**What's the production formula?**
→ `docs/specs/economy.md` Section 3.2

**How much does a Battleship cost?**
→ `docs/specs/reference.md` Section 9.1 (300 PP)

**What are the turn phases?**
→ `docs/specs/gameplay.md` Section 1.3

### Reading Specs

**Pattern**:
```
1. Find the section number (e.g., "7.3.3 Combat Effectiveness Rating")
2. Read the RULE (what happens)
3. Read the RATIONALE (why it matters)
4. Note any TABLES (values, modifiers)
5. Check for EXCEPTIONS (edge cases)
```

**Example**:
```
Section 7.3.3 - Combat Effectiveness Rating

RULE: Roll 1d10, compare to table for effectiveness
TABLE: 0-2 = 0.25×, 3-4 = 0.50×, 5-6 = 0.75×, 7-8 = 1.0×, 9+ = 1.0× (critical)
MODIFIERS: Scouts +1, Morale -1 to +2, Desperation +2
RATIONALE: Adds variance, prevents deterministic outcomes

CODE LOCATION: src/engine/combat/cer.nim lines 45-60
```

---

## Testing Strategy

### Test Pyramid

```
        ┌─────────────────┐
        │   Scenarios     │  ← Few (10-20), hand-crafted, validate design
        └─────────────────┘
       ┌───────────────────┐
       │   Integration     │  ← Some (50-100), test system interactions
       └───────────────────┘
      ┌─────────────────────┐
      │    Unit Tests       │  ← Many (100+), fast, focused
      └─────────────────────┘
```

**Unit Tests** (`tests/unit/`):
- Test single functions/modules
- Fast (<1ms each)
- No dependencies on other systems
- Example: `test_hex.nim` - hex coordinate math

**Integration Tests** (`tests/integration/`):
- Test multiple systems working together
- Moderate speed (10-100ms)
- Example: `test_starmap_robust.nim` - map generation + pathfinding

**Combat Tests** (`tests/combat/`):
- Specialized: 10,000+ random scenarios
- Tests combat engine thoroughly
- Stress testing for edge cases
- Example: `run_stress_test.nim` - 500 battles in 0.04s

**Scenarios** (`tests/scenarios/`):
- Hand-crafted, validates game design
- Tests asymmetric balance
- Documents expected behavior
- Example: `asymmetric_warfare.nim` - Fighter defense, raider ambush

### When to Write Tests

**Always**:
- New combat mechanics → add to `test_space_combat.nim`
- New economy features → create `test_economy.nim`
- Bug fixes → add regression test to `scenarios/regression/`

**Optional**:
- Internal helper functions (test via public API)
- Trivial getters/setters
- Pure data structures (unless complex validation)

### Running Tests

```bash
# Quick smoke test (compile + run)
nim c -r tests/unit/test_hex.nim

# Combat verification
nim c -r tests/combat/test_tech_balance.nim

# Stress test (500 battles)
nim c -r tests/combat/run_stress_test.nim

# All unit tests
for test in tests/unit/test_*.nim; do nim c -r "$test"; done

# Compile without running
nim c tests/combat/test_space_combat.nim

# Release mode (faster, but no debug info)
nim c -d:release tests/combat/run_stress_test.nim
```

---

## Common Pitfalls

### 1. Import Paths After Reorganization

**Problem**: Tests moved to subdirectories, imports need updating

**Before** (flat structure):
```nim
import ../src/engine/combat/types  # WRONG from tests/combat/
```

**After** (subdirectory):
```nim
import ../../src/engine/combat/types  # CORRECT from tests/combat/
```

### 2. TaskForce Fields

**Problem**: Field names changed, old code won't compile

**Wrong**:
```nim
let tf = TaskForce(
  houseId: "house-alpha",  # WRONG: field is 'house', not 'houseId'
  prestige: 50,            # WRONG: use 'moraleModifier' instead
  isCloaked: false
)
```

**Correct**:
```nim
let tf = TaskForce(
  house: "house-alpha",      # Correct field name
  squadrons: @[...],
  roe: 6,                    # Rules of engagement (0-10)
  isCloaked: false,
  moraleModifier: 0,         # Derived from prestige (-1 to +2)
  scoutBonus: false,         # Has scouts in fleet
  isDefendingHomeworld: false
)
```

### 3. No Tech Level 0

**Problem**: Tests used "Tech 0" but gameplay.md:1.2 says tech starts at 1

**Wrong**:
```nim
let ship = newEnhancedShip(ShipClass.Battleship, techLevel = 0)  # INVALID
```

**Correct**:
```nim
let ship = newEnhancedShip(ShipClass.Battleship, techLevel = 1)  # Starting tech
let ship = newEnhancedShip(ShipClass.Battleship, techLevel = 3)  # Advanced tech
```

### 4. String Formatting in Nim

**Problem**: Complex expressions in `fmt` strings fail

**Wrong**:
```nim
echo fmt"Result: {if result.victor.isSome: result.victor.get else: \"Draw\"}"
# ERROR: fmt doesn't parse complex expressions
```

**Correct**:
```nim
let victor = if result.victor.isSome: result.victor.get else: "Draw"
echo fmt"Result: {victor}"
```

### 5. Target Bucket for Scouts

**Problem**: No `TargetBucket.Scout` enum value

**Wrong**:
```nim
bucket: TargetBucket.Scout  # WRONG: doesn't exist
```

**Correct**:
```nim
bucket: TargetBucket.Raider  # Scouts use Raider bucket
```

---

## Git Workflow

### Before Starting Work

```bash
# Check status
git status

# See recent commits
git log --oneline -5

# Check for uncommitted changes
git diff

# Pull latest (if working with others)
git pull
```

### Committing Work

**Pattern**:
```bash
# Stage changes
git add -A

# Commit with descriptive message
git commit -m "Add production calculation for colonies

Implement calculateProduction() per economy.md:3.2
- Base production from population
- Infrastructure bonus
- Tech level modifiers

Tests: test_economy.nim (all passing)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"

# Push (if working with remote)
git push
```

**Commit Message Format**:
1. **Title**: Short summary (50 chars or less)
2. **Body**: What changed and why (wrap at 72 chars)
3. **Details**: Implementation notes, test coverage
4. **Footer**: Claude Code attribution

### Useful Git Commands

```bash
# See what's changed
git status --short
git diff src/engine/economy.nim

# Undo uncommitted changes
git restore src/engine/economy.nim

# See file history
git log --oneline -- src/engine/economy.nim

# Find when a line was added
git blame src/engine/combat/cer.nim
```

---

## When You Get Stuck

### Checklist

1. **Read the spec** - Is there a rule you missed?
   - Check `docs/specs/` for relevant section
   - Look for examples or edge cases

2. **Check existing code** - How do similar features work?
   - Combat system is complete - use as reference
   - Tests show expected patterns

3. **Run tests** - Does anything break?
   - `nim c -r tests/unit/test_hex.nim` for quick check
   - `nim c tests/your_new_test.nim` to find compile errors

4. **Search the codebase** - Has this been solved elsewhere?
   - `grep -r "pattern" src/`
   - `rg "calculateDamage" src/`

5. **Check documentation**:
   - `IMPLEMENTATION_PROGRESS.md` - current status
   - `IMPLEMENTATION_ROADMAP.md` - overall plan
   - `AI_CONTINUATION_GUIDE.md` - this file

### Asking for Help

If user returns and you're stuck, provide:

1. **What you're trying to do** - Feature or bug fix
2. **What you've tried** - Approaches attempted
3. **Where you're stuck** - Specific error or confusion
4. **Code snippet** - Minimal example of the problem
5. **Spec reference** - What section you're implementing

**Example**:
```
I'm implementing production calculation (economy.md:3.2) and stuck on
infrastructure bonus calculation.

Tried:
- Direct multiplication: infrastructure * basePU
- Percentage: (infrastructure / 100) * basePU

Error: Tests expect 50% infrastructure to add 50 PU, but I'm getting 5000 PU

Spec says: "Infrastructure level 0-100 provides proportional bonus"

Code:
```nim
let infraBonus = colony.infrastructure * basePU  # Too large?
```

Is infrastructure stored as 0-100 or 0.0-1.0?
```

---

## Quick Reference

### File Locations

| What | Where |
|------|-------|
| Combat implementation | `src/engine/combat/engine.nim` |
| Combat types | `src/engine/combat/types.nim` |
| Economy (WIP) | `src/engine/economy.nim` |
| Turn resolution | `src/engine/resolve.nim` |
| Pathfinding | `src/engine/starmap.nim` lines 305-372 |
| Combat tests | `tests/combat/test_space_combat.nim` |
| Test fixtures | `tests/fixtures/fleets.nim` |
| Combat spec | `docs/specs/operations.md` Section 7 |
| Economy spec | `docs/specs/economy.md` |
| Ship stats | `docs/specs/reference.md` Section 9.1 |

### Key Commands

```bash
# Build
nim c src/main/client.nim
nim c -d:release src/main/daemon.nim

# Test
nim c -r tests/unit/test_hex.nim
nim c -r tests/combat/run_stress_test.nim

# Clean
rm tests/**/*.exe tests/**/test_* src/**/*.exe

# Git
git status
git add -A
git commit -m "message"
git log --oneline -5
```

### Important Constants

- **Tech levels**: 1-10 (start at 1, no level 0)
- **WEP modifier**: +10% AS/DS per level (rounded down)
- **CER table**: 0-2 (0.25×), 3-4 (0.50×), 5-6 (0.75×), 7+ (1.0×), 9 (critical)
- **Max combat rounds**: 20 before stalemate
- **Desperation trigger**: 5 rounds with no state changes
- **Starting prestige**: 50 (per gameplay.md:1.2)
- **Lanes per turn**: 1-2 (per operations.md:6.2.2)

---

*This guide helps AI assistants quickly resume productive work on EC4X. Keep it updated as patterns emerge.*
