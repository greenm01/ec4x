# Engine Telemetry System

**Location:** `src/engine/telemetry/`

## Overview

The telemetry system collects comprehensive diagnostic metrics from `GameState` every turn for every house. This data drives:

- **AI decision-making** - Strategic and tactical choices based on current state
- **Balance testing** - Automated game simulations for balance analysis
- **Genetic algorithms** - AI personality weight evolution over thousands of games
- **Debugging** - Comprehensive state tracking for issue diagnosis

**Performance Critical:** Telemetry runs **every turn, every house, every simulation**. With genetic algorithms running thousands of games, efficiency is paramount.

## Architecture

### Core Components

```
src/engine/telemetry/
├── orchestrator.nim              # Public API: collectDiagnostics()
├── collectors/                   # 13 domain-specific collectors
│   ├── combat.nim               # Combat performance metrics
│   ├── military.nim             # Military assets (ships, squadrons, units)
│   ├── fleet.nim                # Fleet operations (ETACs, movement)
│   ├── facilities.nim           # Starbases, spaceports, shipyards, drydocks
│   ├── colony.nim               # Colony counts, gained/lost
│   ├── production.nim           # Construction, repair, commissioning
│   ├── capacity.nim             # Squadron/fighter capacity limits
│   ├── population.nim           # Population, transfers, blockades
│   ├── income.nim               # Treasury, tax, maintenance
│   ├── tech.nim                 # Technology levels
│   ├── espionage.nim            # Intelligence operations
│   ├── diplomacy.nim            # Diplomatic relations
│   └── house.nim                # House status, prestige, victory
└── export/
    └── csv_writer.nim           # CSV export format
```

### Data Flow

```
GameState + lastTurnEvents
    ↓
orchestrator.collectDiagnostics(state, houseId)
    ↓
Call 13 collectors in sequence
    ↓
Each collector:
  1. Process events from state.lastTurnEvents
  2. Query GameState via efficient iterators
  3. Update DiagnosticMetrics
    ↓
Return DiagnosticMetrics (319 fields)
    ↓
Persistence layer writes to SQLite database
```

## Key Design Principles

### 1. Data-Oriented Design (DoD)

**O(1) Lookups via Secondary Indexes:**
- Squadrons: `byHouse: Table[HouseId, seq[SquadronId]]`
- Ships: `byHouse: Table[HouseId, seq[ShipId]]`
- Colonies: `byOwner: Table[HouseId, seq[ColonyId]]`
- Facilities: `byColony: Table[ColonyId, seq[FacilityId]]`

**Efficient Iterators:**
```nim
# ❌ BAD - O(n) scan of ALL squadrons
for squadron in state.squadrons.entities.data:
  if squadron.houseId == houseId:
    ...

# ✅ GOOD - O(1) lookup + O(k owned squadrons)
for squadron in state.squadronsOwned(houseId):
  ...
```

### 2. Event-Driven Architecture

**Primary Source:** `state.lastTurnEvents`
- Events provide "what changed" information
- More efficient than snapshot diffing
- Captures turn-by-turn deltas

**Secondary Source:** GameState queries for totals/ratios
- Use iterators for efficient aggregation
- Calculate derived metrics (capacity ratios, etc.)

### 3. Domain-Specific Collectors

**Aligned with engine entities/types** (not Byzantine advisor names):
- Each collector focuses on one domain
- Clear separation of concerns
- Easy to understand and maintain

## Performance

### Before: O(n) Linear Scans

```nim
# Scan ALL colonies to find owned colonies
for colony in state.colonies.entities.data:
  if colony.owner == houseId:  # O(n) filter
    totalProduction += colony.production
```

**Cost:** O(all_entities) for every metric collection

### After: O(1) + O(k) with Indexes

```nim
# O(1) lookup, iterate only owned colonies
for colony in state.coloniesOwned(houseId):  # O(1) + O(k)
  totalProduction += colony.production
```

**Cost:** O(1) lookup + O(owned_entities)

### Speedup Analysis

Typical game state:
- 100 total colonies, 10 owned → **10x speedup**
- 500 total squadrons, 20 owned → **25x speedup**
- 2000 total ships, 50 owned → **40x speedup**

**Aggregate across all collectors:** **10-100x speedup** for full telemetry collection

**Impact:** Critical for genetic algorithms running thousands of simulations

## Usage

### Collecting Diagnostics

```nim
import engine/telemetry/orchestrator

# Collect metrics for a house
let metrics = collectDiagnostics(
  state = gameState,
  houseId = houseId,
  strategy = "Balanced",  # AI strategy name
  gameId = gameId,
  prevMetrics = lastTurnMetrics  # For delta calculations
)

# Access metrics
echo "Treasury: ", metrics.treasuryBalance
echo "Total Ships: ", metrics.totalShips
echo "Prestige: ", metrics.prestigeCurrent
```

### Available Iterators

**Ownership Queries (O(1) lookup):**
- `state.coloniesOwned(houseId)` - Owned colonies
- `state.squadronsOwned(houseId)` - Owned squadrons
- `state.shipsOwned(houseId)` - Owned ships
- `state.starbasesOwned(houseId)` - Owned starbases
- `state.spaceportsOwned(houseId)` - Owned spaceports
- `state.shipyardsOwned(houseId)` - Owned shipyards
- `state.drydocksOwned(houseId)` - Owned drydocks

**House Queries:**
- `state.activeHouses()` - Non-eliminated houses
- `state.eliminatedHouses()` - Eliminated houses

**Location Queries (O(1) lookup):**
- `state.fleetsAtSystem(systemId)` - Fleets at location
- `state.fleetsAtSystemForHouse(systemId, houseId)` - House fleets at location

## Diagnostic Metrics

**DiagnosticMetrics** contains **319 fields** across 13 domains:

### Core Domains

1. **Military Assets** (40+ fields)
   - Ship counts by class (Destroyer, Cruiser, Battleship, etc.)
   - Squadron counts (combat, intel, expansion, etc.)
   - Ground units (armies, marines, batteries, shields)
   - Special weapons (planet breakers)

2. **Economic** (30+ fields)
   - Treasury, production, maintenance
   - Tax income, deficits, shortfalls
   - Infrastructure, industrial units

3. **Combat Performance** (50+ fields)
   - Space combat wins/losses
   - Orbital bombardment rounds
   - Ground invasions (attempted, successful, repelled)
   - CER averages, detection rates, retreats

4. **Production** (25+ fields)
   - Build queue depth
   - Ships under construction / commissioned
   - Buildings under construction / completed
   - Repair projects

5. **Capacity Limits** (15+ fields)
   - Squadron limits (max, used, violations)
   - Fighter capacity (max, used, violations)
   - Grace period tracking

6. **Colonies** (20+ fields)
   - Total colonies, gained, lost
   - Colonization methods (ETACs, conquest, diplomacy)
   - Undefended colonies

7. **Population** (10+ fields)
   - Total PU, PTU
   - Population transfers
   - Blockades

8. **Technology** (20+ fields)
   - All tech levels (CST, WEP, EL, SL, TER, ELI, CLK, SLD, CIC, FD, ACO)
   - Research points allocated

9. **Espionage** (25+ fields)
   - Intelligence operations (success/failure rates)
   - CLK research without raiders (warning)

10. **Diplomacy** (20+ fields)
    - Diplomatic status counts (neutral, hostile, enemy)
    - Pact formations/breaks
    - War declarations
    - Violation history

11. **Fleet Operations** (15+ fields)
    - Fleets with/without orders
    - ETACs (total, in transit, without orders)
    - Fleet movements

12. **House Status** (15+ fields)
    - Prestige (current, change, victory progress)
    - House status (autopilot, defensive collapse)
    - Elimination countdown

13. **Facilities** (10+ fields)
    - Starbases, spaceports, shipyards, drydocks

**Reference:** `scripts/analysis/diagnostic_columns.json` (auto-generated)

## Adding New Metrics

### 1. Add Field to DiagnosticMetrics

**File:** `src/engine/types/telemetry.nim`

```nim
type
  DiagnosticMetrics* = object
    # ... existing fields ...
    myNewMetric*: int32  # Add your field
```

### 2. Update Appropriate Collector

**File:** `src/engine/telemetry/collectors/{domain}.nim`

```nim
proc collect{Domain}Metrics*(
  state: GameState,
  houseId: HouseId,
  prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  result = prevMetrics

  # Add your metric collection logic
  result.myNewMetric = calculateMyMetric(state, houseId)
```

### 3. Update CSV Writer (if exporting)

**File:** `src/engine/telemetry/export/csv_writer.nim`

Add column header and value to CSV output.

### 4. Regenerate Column Reference

```bash
python3.11 scripts/update_diagnostic_columns.py
```

## Files

- [architecture.md](./architecture.md) - Detailed architecture and design decisions
- [iterators.md](./iterators.md) - Iterator patterns and O(1) lookup implementation
- [index-maintenance.md](./index-maintenance.md) - How to maintain byHouse indexes
- [collectors.md](./collectors.md) - Collector implementation guide

## Related Documentation

- [Engine State Iterators](../../architecture/iterators.md) - General iterator patterns
- [Data-Oriented Design](../../architecture/dod.md) - DoD principles in EC4X
- [Persistence Layer](../persistence/README.md) - Database schema and writes

---

**Last Updated:** 2025-12-21
**Status:** Implemented with O(1) lookups (indexes defined, maintenance pending)
