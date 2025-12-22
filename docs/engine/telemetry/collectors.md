# Telemetry Collectors

## Overview

The telemetry system uses **13 domain-specific collectors** to gather comprehensive game state metrics. Each collector focuses on one domain and is aligned with engine entities/types.

## Collector Architecture

### Design Principles

1. **Domain-Specific** - Each collector owns metrics for one game domain
2. **Event-Driven** - Process `state.lastTurnEvents` for delta metrics
3. **State-Querying** - Use efficient iterators for aggregation metrics
4. **Pure Functions** - No side effects, just read state and return metrics
5. **DoD-Compliant** - Use O(1) iterators, not O(n) scans

### Collector Signature

```nim
proc collect{Domain}Metrics*(
  state: GameState,
  houseId: HouseId,
  prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  result = prevMetrics  # Carry forward previous metrics

  # 1. Process events for delta metrics
  for event in state.lastTurnEvents:
    if event.houseId != some(houseId): continue
    case event.eventType:
      of EventType1: ...
      of EventType2: ...

  # 2. Query GameState for totals/aggregations
  for entity in state.entitiesOwned(houseId):
    result.totalCount += 1

  # 3. Calculate derived metrics
  result.ratio = float32(result.used) / float32(result.max)

  return result
```

## The 13 Collectors

### 1. Combat Collector (`combat.nim`)

**Domain:** Combat performance metrics

**Metrics:**
- Space combat (wins, losses, CER averages)
- Orbital bombardment (rounds, hits, misses)
- Ground invasions (attempted, successful, repelled)
- Detection events (raiders, scouts, surveillance)
- Fleet retreats and critical hits

**Data Sources:**
- Primary: `state.lastTurnEvents` (Battle, Bombardment, InvasionBegan, etc.)
- Secondary: None (pure event-driven)

**Example:**
```nim
for event in state.lastTurnEvents:
  if event.houseId != some(houseId): continue

  case event.eventType:
  of CombatResult:
    if event.outcome == some("Victory"):
      result.spaceCombatWins += 1
    elif event.outcome == some("Defeat"):
      result.spaceCombatLosses += 1
  of Bombardment:
    result.bombardmentRoundsTotal += 1
  of InvasionBegan:
    result.invasionAttemptsTotal += 1
```

### 2. Military Collector (`military.nim`)

**Domain:** Military asset counts

**Metrics:**
- Ships by class (Destroyer, Cruiser, Battleship, Carrier, etc.)
- Squadrons by type (Combat, Intel, Expansion, Fighter)
- Ground units (armies, marines, batteries, shields)
- Special weapons (planet breakers)

**Data Sources:**
- Primary: `state.squadronsOwned(houseId)` - O(1) iterator
- Secondary: `state.coloniesOwned(houseId)` - for ground units/fighters
- Tertiary: `house.planetBreakerCount` - from House object

**Example:**
```nim
# Count squadrons and ships by type
for squadron in state.squadronsOwned(houseId):
  if not squadron.destroyed:
    case squadron.squadronType:
    of SquadronType.Combat:
      result.combatSquadrons += 1
    of SquadronType.Intel:
      result.intelSquadrons += 1

    # Count flagship
    case squadron.flagship.shipClass:
    of ShipClass.Destroyer:
      result.destroyerShips += 1
    of ShipClass.Cruiser:
      result.cruiserShips += 1
```

### 3. Fleet Collector (`fleet.nim`)

**Domain:** Fleet operations and activity

**Metrics:**
- Fleets with/without orders
- Fleet movements
- ETACs (total, in transit, without orders)
- Colonization attempts

**Data Sources:**
- Primary: `state.fleetsOwned(houseId)` - O(n) iterator (small n)
- Secondary: `state.squadronsOwned(houseId)` - for ETAC counts
- Events: `FleetArrived`, `ColonyEstablished`

**Example:**
```nim
# Count ETACs and their status
for squadron in state.squadronsOwned(houseId):
  if squadron.flagship.shipClass == ShipClass.ETAC:
    result.totalETACs += 1
    if squadron.orders.isNone:
      result.etacsWithoutOrders += 1
```

### 4. Facilities Collector (`facilities.nim`)

**Domain:** Facility counts (starbases, spaceports, shipyards, drydocks)

**Metrics:**
- Total counts by facility type
- Crippled vs operational

**Data Sources:**
- Primary: Facility iterators via `coloniesOwned`
  - `state.starbasesOwned(houseId)`
  - `state.spaceportsOwned(houseId)`
  - `state.shipyardsOwned(houseId)`
  - `state.drydocksOwned(houseId)`

**Example:**
```nim
# Count facilities
for starbase in state.starbasesOwned(houseId):
  result.totalStarbases += 1
  if starbase.isCrippled:
    result.crippledStarbases += 1
```

### 5. Colony Collector (`colony.nim`)

**Domain:** Colony counts and changes

**Metrics:**
- Total colonies
- Colonies gained/lost
- Colonies gained by method (colonization, conquest, diplomacy)
- Undefended colonies

**Data Sources:**
- Primary: `state.lastTurnEvents` - for deltas
- Secondary: `state.coloniesOwned(houseId)` - for totals
- Events: `ColonyEstablished`, `ColonyCaptured`

**Example:**
```nim
# Track colony changes
for event in state.lastTurnEvents:
  case event.eventType:
  of ColonyEstablished:
    if event.houseId == some(houseId):
      result.coloniesGained += 1
      result.coloniesGainedViaColonization += 1
  of ColonyCaptured:
    if event.newOwner == some(houseId):
      result.coloniesGained += 1
      result.coloniesGainedViaConquest += 1
```

### 6. Production Collector (`production.nim`)

**Domain:** Construction and manufacturing

**Metrics:**
- Build queue depth
- Ships under construction / commissioned
- Buildings under construction / completed
- ETACs in construction
- Repair projects

**Data Sources:**
- Primary: `state.lastTurnEvents` - for commissioning events
- Secondary: `state.coloniesOwned(houseId)` - for build queues
- Queries: `state.constructionProjects.entities.getEntity(id)`
- Events: `ShipCommissioned`, `BuildingCompleted`

**Example:**
```nim
# Count construction projects
for colony in state.coloniesOwned(houseId):
  if colony.underConstruction.isSome:
    let projectOpt = state.constructionProjects.entities.getEntity(
      colony.underConstruction.get()
    )
    if projectOpt.isSome:
      let project = projectOpt.get()
      if project.projectType == BuildType.Ship:
        result.shipsUnderConstruction += 1
```

### 7. Capacity Collector (`capacity.nim`)

**Domain:** Capacity limits and violations

**Metrics:**
- Squadron limits (max, used, violations)
- Fighter capacity (max, used, violations)
- Grace period tracking

**Data Sources:**
- Primary: `state.coloniesOwned(houseId)` - for fighter capacity
- Secondary: `state.squadronsOwned(houseId)` - for squadron counts
- Config: `globalMilitaryConfig` - for limit calculations
- House: `house.techTree.levels.fighterDoctrine` - for FD multiplier

**Example:**
```nim
# Calculate fighter capacity
let fdMultiplier: float32 = case house.techTree.levels.fighterDoctrine
  of 1: 1.0
  of 2: 1.5
  of 3: 2.0
  else: 1.0

for colony in state.coloniesOwned(houseId):
  let capacity = int32(
    float32(colony.industrial.units / fighterIUDivisor) * fdMultiplier
  )
  result.fighterCapacityMax += capacity
  result.fighterCapacityUsed += colony.fighterSquadronIds.len
```

### 8. Population Collector (`population.nim`)

**Domain:** Population and transfers

**Metrics:**
- Total PU (Population Units)
- Total PTU (Population Transfer Units)
- Population transfers active
- Blockaded colonies

**Data Sources:**
- Primary: `state.coloniesOwned(houseId)` - for population totals
- Events: `PopulationTransfer`

**Example:**
```nim
for colony in state.coloniesOwned(houseId):
  result.totalPopulationUnits += colony.populationUnits
  result.totalPopulationPTU += colony.populationTransferUnits

  if colony.blockaded:
    result.coloniesBlockadedCount += 1
    result.blockadeTurns += colony.blockadeTurns
```

### 9. Income Collector (`income.nim`)

**Domain:** Economic income and expenses

**Metrics:**
- Treasury balance
- Production income
- Tax income
- Maintenance costs
- Treasury deficits

**Data Sources:**
- Primary: `house.treasury` - current balance
- Secondary: `state.coloniesOwned(houseId)` - for production/infrastructure
- House: `house.taxPolicy.currentRate` - for tax calculations

**Example:**
```nim
result.treasuryBalance = house.treasury

var totalProduction = 0
for colony in state.coloniesOwned(houseId):
  totalProduction += colony.production

result.totalProduction = totalProduction
```

### 10. Tech Collector (`tech.nim`)

**Domain:** Technology levels and research

**Metrics:**
- All 11 tech levels (CST, WEP, EL, SL, TER, ELI, CLK, SLD, CIC, FD, ACO)
- Research points allocated

**Data Sources:**
- Primary: `house.techTree.levels` - all tech levels
- Events: `TechAdvance` - for research breakthroughs

**Example:**
```nim
result.techCST = house.techTree.levels.constructionTech
result.techWEP = house.techTree.levels.weaponsTech
result.techEL = house.techTree.levels.economicLevel
result.techSL = house.techTree.levels.scienceLevel
# ... all 11 tech levels
```

### 11. Espionage Collector (`espionage.nim`)

**Domain:** Intelligence operations

**Metrics:**
- Espionage operations (success/failure)
- CLK research without raiders (warning metric)

**Data Sources:**
- Primary: `state.lastTurnEvents` - for espionage results
- Secondary: `state.squadronsOwned(houseId)` - to check for raiders
- House: `house.techTree.levels.cloakingTech` - for CLK check
- Events: `SpyMissionSucceeded`, `SpyMissionDetected`, etc.

**Example:**
```nim
# Check for CLK research without raiders
let hasCLK = house.techTree.levels.cloakingTech > 1
var hasRaiders = false

for squadron in state.squadronsOwned(houseId):
  if squadron.flagship.shipClass == ShipClass.Raider:
    hasRaiders = true
    break

result.clkResearchedNoRaiders = hasCLK and not hasRaiders
```

### 12. Diplomacy Collector (`diplomacy.nim`)

**Domain:** Diplomatic relations and events

**Metrics:**
- Diplomatic status counts (neutral, hostile, enemy)
- Pact formations/breaks
- War declarations
- Bilateral relations string
- Violation history

**Data Sources:**
- Primary: `state.diplomaticRelation` - centralized relations
- Secondary: `state.diplomaticViolation` - violation history
- Events: `TreatyAccepted`, `TreatyBroken`, `WarDeclared`

**Example:**
```nim
# Count diplomatic relations
for otherHouseId, otherHouse in state.houses.entities.data:
  if otherHouseId == houseId or otherHouse.isEliminated:
    continue

  let key = (houseId, otherHouseId)
  if state.diplomaticRelation.hasKey(key):
    case state.diplomaticRelation[key].state:
    of DiplomaticState.Neutral:
      result.neutralStatusCount += 1
    of DiplomaticState.Hostile:
      result.hostileStatusCount += 1
    of DiplomaticState.Enemy:
      result.enemyStatusCount += 1
```

### 13. House Collector (`house.nim`)

**Domain:** House status and victory conditions

**Metrics:**
- Prestige (current, change, victory progress)
- House status (autopilot, defensive collapse)
- Elimination countdown
- Maintenance shortfalls

**Data Sources:**
- Primary: `house` - prestige, status fields
- Secondary: `prevMetrics` - for delta calculations
- Events: `PrestigeGained`, `PrestigeLost`

**Example:**
```nim
result.prestigeCurrent = house.prestige
result.prestigeChange = result.prestigeCurrent - prevMetrics.prestigeCurrent

# Victory progress (3 consecutive turns at >= 1500)
if result.prestigeCurrent >= 1500:
  result.prestigeVictoryProgress = prevMetrics.prestigeVictoryProgress + 1
else:
  result.prestigeVictoryProgress = 0

result.autopilotActive = house.status == HouseStatus.Autopilot
```

## Collector Orchestration

### Orchestrator (`orchestrator.nim`)

**Responsibility:** Call all 13 collectors in sequence

```nim
proc collectDiagnostics*(
  state: GameState,
  houseId: HouseId,
  strategy: string,
  gameId: int32,
  prevMetrics: Option[DiagnosticMetrics] = none(DiagnosticMetrics)
): DiagnosticMetrics =

  # Initialize with turn metadata
  var metrics = initDiagnosticMetrics(state.turn, houseId, strategy, gameId)

  # Carry forward previous metrics if available
  if prevMetrics.isSome:
    metrics = prevMetrics.get()
    metrics.turn = state.turn

  # Call all 13 collectors in sequence
  metrics = collectCombatMetrics(state, houseId, metrics)
  metrics = collectMilitaryMetrics(state, houseId, metrics)
  metrics = collectFleetMetrics(state, houseId, metrics)
  metrics = collectFacilitiesMetrics(state, houseId, metrics)
  metrics = collectColonyMetrics(state, houseId, metrics)
  metrics = collectProductionMetrics(state, houseId, metrics)
  metrics = collectCapacityMetrics(state, houseId, metrics)
  metrics = collectPopulationMetrics(state, houseId, metrics)
  metrics = collectIncomeMetrics(state, houseId, metrics)
  metrics = collectTechMetrics(state, houseId, metrics)
  metrics = collectEspionageMetrics(state, houseId, metrics)
  metrics = collectDiplomacyMetrics(state, houseId, metrics)
  metrics = collectHouseMetrics(state, houseId, metrics)

  return metrics
```

**Order matters:**
- Independent collectors can be called in any order
- Dependent collectors must come after their dependencies
- Currently all collectors are independent (operate on prevMetrics)

## Adding a New Collector

### Step 1: Identify Domain

Choose a clear domain boundary:
- **Good:** "Technology Research", "Victory Conditions", "Espionage Operations"
- **Bad:** "Miscellaneous", "Other Metrics", "Extra Stuff"

### Step 2: Define Metrics

Add fields to `DiagnosticMetrics` in `types/telemetry.nim`:

```nim
type
  DiagnosticMetrics* = object
    # ... existing fields ...

    # My new domain
    myMetric1*: int32
    myMetric2*: float32
    myMetricRatio*: float32
```

### Step 3: Create Collector

**File:** `src/engine/telemetry/collectors/mydomain.nim`

```nim
import ../../types/[telemetry, core, game_state, event, ...]
import ../../state/interators

proc collectMyDomainMetrics*(
  state: GameState,
  houseId: HouseId,
  prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  result = prevMetrics

  # Process events
  for event in state.lastTurnEvents:
    if event.houseId != some(houseId): continue
    case event.eventType:
    of MyEventType:
      result.myMetric1 += 1
    else:
      discard

  # Query state
  for entity in state.myEntitiesOwned(houseId):
    result.myMetric2 += entity.value

  # Calculate derived metrics
  if result.myMetric2 > 0:
    result.myMetricRatio = float32(result.myMetric1) / result.myMetric2
```

### Step 4: Add to Orchestrator

**File:** `src/engine/telemetry/orchestrator.nim`

```nim
import ./collectors/[
  ..., mydomain  # Add import
]

proc collectDiagnostics*(...): DiagnosticMetrics =
  # ... existing collectors ...
  metrics = collectMyDomainMetrics(state, houseId, metrics)  # Add call
  return metrics
```

### Step 5: Update CSV Writer (if exporting)

**File:** `src/engine/telemetry/export/csv_writer.nim`

Add columns to CSV header and data rows.

### Step 6: Regenerate Column Reference

```bash
python3.11 scripts/update_diagnostic_columns.py
```

## Best Practices

### DO:
- ✅ Use efficient iterators (`coloniesOwned`, `squadronsOwned`, etc.)
- ✅ Process events for delta metrics
- ✅ Query state for aggregation metrics
- ✅ Keep collectors pure (no side effects)
- ✅ Use prevMetrics for delta calculations
- ✅ Handle missing entities gracefully (`Option`, `isSome`, `getOrDefault`)

### DON'T:
- ❌ Iterate `entities.data` manually (use iterators)
- ❌ Mutate GameState (collectors are read-only)
- ❌ Hardcode values (use configs)
- ❌ Duplicate logic between collectors
- ❌ Access omniscient state (respect fog-of-war if applicable)

## Related Documentation

- [README.md](./README.md) - Telemetry system overview
- [iterators.md](./iterators.md) - Efficient iterator patterns

---

**Last Updated:** 2025-12-21
**Collector Count:** 13 domain-specific collectors
