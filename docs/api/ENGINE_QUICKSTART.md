# EC4X Engine API Quick-Start Guide

This guide covers the essential patterns for working with the EC4X engine after the Phase 1-2 audit improvements.

## Table of Contents
1. [Core Concepts](#core-concepts)
2. [GameState Management](#gamestate-management)
3. [Turn Resolution](#turn-resolution)
4. [Combat System](#combat-system)
5. [Economy System](#economy-system)
6. [Common Patterns](#common-patterns)

## Core Concepts

### GameState Structure
The `GameState` type is the central data structure representing the complete game state:

```nim
type GameState* = object
  turn*: int
  phase*: GamePhase
  houses*: Table[HouseId, House]
  colonies*: Table[SystemId, Colony]
  fleets*: Table[FleetId, Fleet]
  # ... more tables
```

**CRITICAL**: All tables use value semantics - see [Table Copy Pattern](#table-copy-pattern) below.

### Module Organization
```
src/engine/
├── gamestate.nim          # Core game state types
├── resolve.nim            # Turn resolution orchestrator
├── combat/                # Combat resolution system
│   ├── engine.nim        # Main combat engine
│   ├── cer.nim           # Combat Effectiveness Rating (dice)
│   ├── damage.nim        # Damage application
│   └── ground.nim        # Ground combat & bombardment
├── economy/              # Economy system
│   ├── engine.nim        # Income/maintenance orchestrator
│   ├── income.nim        # Income calculations
│   └── construction.nim  # Construction system
└── resolution/           # Phase resolution implementations
    ├── combat_resolution.nim
    └── economy_resolution.nim
```

## GameState Management

### Table Copy Pattern

**Problem**: Nim Tables return copies, not references:
```nim
// BROKEN - changes are lost!
state.houses[houseId].treasury = 1000
state.fleets[fleetId].status = FleetStatus.Reserve
```

**Solution**: Get-Modify-Write pattern:
```nim
// CORRECT - changes persist
var house = state.houses[houseId]
house.treasury = 1000
state.houses[houseId] = house

var fleet = state.fleets[fleetId]
fleet.status = FleetStatus.Reserve
state.fleets[fleetId] = fleet
```

### Batch Modifications
When modifying multiple fields, batch them:
```nim
var house = state.houses[houseId]
house.treasury += income
house.prestige += prestigeBonus
house.techTree.levels.weaponsTech += 1
state.houses[houseId] = house  // Single write-back
```

### Table-to-Seq Patterns
When passing to functions that need `seq`, use copy-modify-writeback:
```nim
// Create seq copy
var coloniesSeq: seq[Colony] = @[]
for systemId, colony in state.colonies:
  coloniesSeq.add(colony)

// Pass to function that modifies via mpairs
let report = econ_engine.resolveIncomePhase(coloniesSeq, ...)

// CRITICAL: Write back modifications
for colony in coloniesSeq:
  state.colonies[colony.systemId] = colony
```

## Turn Resolution

### Resolution Flow
```nim
proc resolveTurn*(state: GameState, orders: Table[HouseId, OrderPacket]): TurnResult =
  // 1. Initialize turn RNG (deterministic)
  var rng = initRand(state.turn)
  logRNG("RNG initialized", "seed=", $state.turn)

  // 2. Resolve phases in order
  resolveConflictPhase(result.newState, orders, events, rng)
  resolveIncomePhase(result.newState, orders)
  resolveCommandPhase(result.newState, orders, events, rng)
  resolveMaintenancePhase(result.newState, events, orders)

  // 3. Advance turn counter
  result.newState.turn += 1
```

### RNG Integration
**Always use turn-seeded RNG for deterministic replay**:

```nim
// In turn resolution (resolve.nim)
var rng = initRand(state.turn)  // Turn-seeded
logRNG("RNG initialized", "turn=", $state.turn, " seed=", $state.turn)

// Pass rng through resolution chain
resolveConflictPhase(state, orders, events, rng)
resolveBattle(state, systemId, orders, events, rng)

// In combat resolution
let roll = rng.roll1d20()        // Use provided RNG
let cerRoll = rng.roll1d10()     // Don't create new RNG!
```

## Combat System

### Combat Resolution Pattern
```nim
proc resolveBattle*(
  state: var GameState,
  systemId: SystemId,
  orders: Table[HouseId, OrderPacket],
  combatReports: var seq[CombatReport],
  events: var seq[GameEvent],
  rng: var Rand  // Turn RNG passed through
) =
  logCombat("Resolving battle", "system=", $systemId)

  // 1. Build task forces from fleets
  var taskForces: Table[HouseId, TaskForce] = ...

  // 2. Execute combat
  let outcome = combat_engine.resolveCombat(battleContext)

  // 3. Apply results back to state
  for (fleetId, fleet) in fleetsAtSystem:
    var updatedSquadrons: seq[Squadron] = @[]
    for squadron in fleet.squadrons:
      if squadron.id in survivingSquadronIds:
        // Update crippled status
        var updatedSquadron = squadron
        updatedSquadron.flagship.isCrippled = (...)
        updatedSquadrons.add(updatedSquadron)
      else:
        // Mark destroyed before removal
        var destroyedSquadron = squadron
        destroyedSquadron.destroyed = true
        logCombat("Squadron destroyed", "id=", destroyedSquadron.id)

    // Write back
    if updatedSquadrons.len > 0:
      state.fleets[fleetId] = Fleet(...)
    else:
      state.fleets.del(fleetId)
```

### Config Integration
Load stats from config with tech modifiers:
```nim
// Ships with WEP tech
let ownerWepLevel = state.houses[houseId].techTree.levels.weaponsTech
let starbaseShip = EnhancedShip(
  shipClass: ShipClass.Starbase,
  stats: getShipStats(ShipClass.Starbase, ownerWepLevel),
  isCrippled: false
)

// Ground units with CST tech
let ownerCSTLevel = state.houses[colony.owner].techTree.levels.constructionTech
let battery = createGroundBattery(id, owner, techLevel = ownerCSTLevel)
```

## Economy System

### Income Phase Pattern
```nim
proc resolveIncomePhase*(state: var GameState, orders: Table[HouseId, OrderPacket]) =
  // 1. Apply blockades
  blockade_engine.applyBlockades(state)

  // 2. Copy colonies for processing
  var coloniesSeq: seq[Colony] = @[]
  for systemId, colony in state.colonies:
    coloniesSeq.add(colony)

  // 3. Calculate income
  let incomeReport = econ_engine.resolveIncomePhase(
    coloniesSeq, houseTaxPolicies, houseTechLevels, houseTreasuries
  )

  // 4. CRITICAL: Write back population growth
  for colony in coloniesSeq:
    state.colonies[colony.systemId] = colony

  // 5. Apply results to houses
  for houseId, houseReport in incomeReport.houseReports:
    var house = state.houses[houseId]
    house.treasury = houseTreasuries[houseId]
    house.prestige += prestigeBonus
    state.houses[houseId] = house
```

## Common Patterns

### Logging
Use structured logging for debugging:
```nim
import common/logger

logCombat("Resolving battle", "system=", $systemId)
logInfo("Resolve", "Turn resolution starting", "turn=", $state.turn)
logDebug("Table", "Colony modified", "id=", $colonyId)
logRNG("RNG initialized", "seed=", $seed)
```

### Destruction Tracking
Mark entities as destroyed before removal:
```nim
// Squadrons
if squadron.id notin survivingSquadronIds:
  var destroyedSquadron = squadron
  destroyedSquadron.destroyed = true
  logCombat("Squadron destroyed", "id=", destroyedSquadron.id)
  // Don't add to updatedSquadrons (removed)

// Batteries
updatedColony.groundBatteries -= result.batteriesDestroyed
if updatedColony.groundBatteries < 0:
  updatedColony.groundBatteries = 0
```

### Error Handling
Use Option types for optional results:
```nim
proc getFleet*(state: GameState, fleetId: FleetId): Option[Fleet] =
  if fleetId in state.fleets:
    return some(state.fleets[fleetId])
  else:
    return none(Fleet)

// Usage
let fleetOpt = state.getFleet(order.fleetId)
if fleetOpt.isNone:
  echo "Fleet not found"
  return
let fleet = fleetOpt.get()
```

## Best Practices

1. **Always use get-modify-write** for table modifications
2. **Pass RNG through resolution chain** - don't create new RNGs
3. **Write back seq modifications** after economy engine calls
4. **Log important state changes** for debugging
5. **Mark entities as destroyed** before removing from state
6. **Load stats from config** with tech level modifiers
7. **Batch table modifications** for efficiency
8. **Use structured logging** with module-specific helpers

## Further Reading

- [Full API Documentation](./engine/index.html) - Auto-generated from code
- [CLAUDE_CONTEXT.md](../CLAUDE_CONTEXT.md) - Development patterns
- [Architecture Docs](../architecture/) - System design
- [Specs](../specs/) - Game mechanics specifications
