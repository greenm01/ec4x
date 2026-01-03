# EC4X Development Context for Claude

**Quick start:** `@CLAUDE.md` `@docs/TODO.md` `@docs/STYLE_GUIDE.md`

---

## Critical Rules

1. **All enums MUST be `{.pure.}`** (NEP-1 requirement)
2. **No hardcoded values** - use TOML configs from `config/`
3. **Follow DRY** - check existing patterns before duplicating
4. **Follow DoD** - data-oriented design (see below)
5. **Use `std/logging`** NOT echo (disappears in release builds)
6. **Engine respects fog-of-war** - use `house.intelligence`, not omniscient state
7. **80 character line limit, 2-space indentation** (NEP-1)
8. **Use UFCS** - `state.foo(bar)` not `foo(state, bar)`
9. **Follow entity patterns** from `src/engine/architecture.md`

**Reference:** `docs/api/api.json` contains src tree API for efficient context.

---

## Design Patterns

### DoD (Data-Oriented Design)

**Core principle:** Separate data from behavior. Use tables for entity management.

```nim
# ✅ GOOD - DoD pattern
type GameState = object
  houses: Table[HouseId, House]
  fleets: Table[FleetId, Fleet]
  colonies: Table[ColonyId, Colony]

proc processFleets(state: var GameState) =
  for fleet in state.allFleets():
    # Process fleet logic
```

```nim
# ❌ BAD - OOP pattern (don't do this)
type Fleet = object
  id: FleetId
  ships: seq[Ship]

method move(self: var Fleet) =
  # Don't use methods/inheritance
```

**Guidelines:**
- Use `Table[Id, Entity]` for all game entities
- Keep data flat and cache-friendly
- Separate data (types) from logic (procs)
- Pass `GameState` by reference, mutate in place
- Use value types (not ref objects)

### DRY (Don't Repeat Yourself)

**Before writing code:**
1. Search for similar functionality in existing modules
2. Extract common patterns into shared utilities
3. Reuse existing types and interfaces

**Common patterns:**
- Table iteration: `for id, entity in table.pairs`
- Fog-of-war: `createFogOfWarView(state, houseId)`
- Config: Use existing `gameConfig.*` patterns

---

## Architecture Patterns

### Entity Management (Three-Layer Architecture)

**Public API** (`state/engine.nim`, `state/iterators.nim`):
```nim
# Access entities
let colony = state.colony(colonyId).get()
let fleet = state.fleet(fleetId).get()

# Iterate entities
for colony in state.coloniesOwned(houseId):
  # Process colony

for fleet in state.fleetsInSystem(systemId):
  # Process fleet
```

**Entity Operations** (`entities/*_ops.nim`):
```nim
# Create/destroy entities
import ../../entities/fleet_ops
let newFleet = fleet_ops.createFleet(state, owner, location)
fleet_ops.destroyFleet(state, fleetId)
```

**Systems** (`systems/*/`):
- Business logic ONLY
- Use public API, never access `entity_manager` directly
- Use entity_ops for creation/destruction

### Configuration System

**All tunable values from TOML:**
```nim
# ❌ BAD - hardcoded
result.prestige = 2
let attackThreshold = 0.6

# ✅ GOOD - from config
result.prestige = gameConfig.prestige.economic.tech_advancement
let attackThreshold = gameConfig.rba.strategic.attack_threshold
```

**Key configs:**
- `config/rba.toml` - AI weights, budgets, thresholds
- `config/prestige.toml` - Prestige rewards
- `config/economy.toml` - Economic parameters
- `config/ships.toml` - Ship stats

---

## Fog-of-War System

**AI MUST use filtered views:**
```nim
let view = createFogOfWarView(state, houseId)

# Access only what the house knows
for colony in view.ownColonies:        # Full details
  ...
for system in view.visibleSystems:    # Limited intel
  ...
for fleet in view.visibleFleets:      # If detected
  ...
```

**Visibility levels:** Owned > Occupied > Scouted > Adjacent > None

---

## Logging (Critical!)

**Use `std/logging`, NOT echo:**
```nim
import std/logging

info "Turn ", state.turn, " resolved: ", result.events.len, " events"
debug "Fleet ", fleetId, " moved from ", oldLoc, " to ", newLoc
error "Invalid order from ", houseId, ": ", reason
```

**Why:** Echo disappears in release builds. Lost 4 hours debugging "Brain-Dead AI" bug in Nov 2025 because of echo statements. Don't repeat this mistake.

---

## Build & Test

```bash
# Development
nimble buildSimulation      # Primary build (C API, parallel)
nimble buildAll             # All binaries
nimble buildDebug           # With debug symbols

# Testing
nimble testBalanceQuick     # 20 games, ~10s
nimble testIntegration      # Integration tests

# Cleanup
nimble tidy                 # Remove artifacts
```

**Run simulation:**
```bash
./bin/run_simulation --seed 12345 --turns 100 --players 4
```

---

## File Organization

### /docs Root (MAX 7 FILES)

Current:
1. `TODO.md` - Living roadmap
2. `STYLE_GUIDE.md` - Coding standards
3. `README.md` - Docs overview
4. `KNOWN_ISSUES.md` - Current issues
5. `OPEN_ISSUES.md` - Tracked issues
6. `BALANCE_TESTING_METHODOLOGY.md` - Testing approach
7. (1 slot available)

**Subdirectories:**
- `/docs/architecture/` - System design
- `/docs/specs/` - Game rules
- `/docs/ai/` - AI development
- `/docs/guides/` - Implementation guides
- `/docs/archive/[date]/` - Obsolete docs

---

## Pre-Commit Checklist

- [ ] Enums are `{.pure.}`
- [ ] No hardcoded values (check configs)
- [ ] Followed DRY - reused existing patterns
- [ ] Followed DoD - used Tables, avoided OOP
- [ ] Used `std/logging`, not echo
- [ ] Line length ≤80 characters
- [ ] 2-space indentation, spaces around operators
- [ ] Tests pass if touching engine/AI
- [ ] TODO.md updated if milestone reached
- [ ] Engine code respects fog-of-war

**Note:** Git hooks enforce `nimble buildAll` before push

---

## Common Gotchas

- **Stale binaries:** Use `nimble buildSimulation` (full clean)
- **Config changes:** Edit TOML files, NOT source code
- **Seeds:** Use `--seed` for reproducible testing
- **Entity access:** Use public API (`state.colony()`), never `entity_manager` directly
- **Facility types:** Neoria (shipyards/spaceports/drydocks), Kastra (starbases)

---

**Last Updated:** 2026-01-03
**Location:** Project root (`CLAUDE.md`)
**Status:** See `docs/TODO.md` for current work and roadmap
