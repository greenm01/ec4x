# EC4X Test Suite

Modular test organization for the EC4X game engine.

## Directory Structure

```
tests/
├── integration/           Integration tests
│   ├── test_game_initialization.nim   Complete game init validation
│   └── test_starmap_validation.nim    Starmap generation
│
├── stress/                Stress & long-duration tests
│   ├── stress_framework.nim           Core invariant checking
│   ├── test_simple_stress.nim         Basic 100-turn validation
│   ├── test_engine_stress.nim         Comprehensive engine stress
│   ├── test_state_corruption.nim      1000-turn corruption detection
│   ├── test_pathological_inputs.nim   Input fuzzing & edge cases
│   ├── test_performance_regression.nim Performance monitoring
│   ├── test_unknown_unknowns.nim      Statistical anomaly detection
│   └── test_quick_demo.nim            Concept demonstration
│
└── archive/               Archived tests for reference
    └── test_mock_game.nim             Old API patterns
```

## Quick Start

### Run Integration Tests
```bash
# Game initialization (validates complete setup)
nim c -r --passL:-lsqlite3 tests/integration/test_game_initialization.nim

# Starmap validation
nim c -r tests/integration/test_starmap_validation.nim
```

### Run Stress Tests
```bash
# Simple stress test (100 turns, ~30 seconds)
nim c -r --passL:-lsqlite3 tests/stress/test_simple_stress.nim

# Full engine stress (100 + 500 turn simulations)
nim c -r --passL:-lsqlite3 tests/stress/test_engine_stress.nim

# Long-duration corruption detection (1000 turns)
nim c -r --passL:-lsqlite3 tests/stress/test_state_corruption.nim

# Input fuzzing (pathological inputs)
nim c -r --passL:-lsqlite3 tests/stress/test_pathological_inputs.nim

# Performance regression detection
nim c -r --passL:-lsqlite3 tests/stress/test_performance_regression.nim

# Statistical anomaly detection (100+ games)
nim c -r --passL:-lsqlite3 tests/stress/test_unknown_unknowns.nim
```

## Test Categories

### Integration Tests (`tests/integration/`)
- Validate complete system initialization
- Multi-component interaction testing
- Full workflow validation

### Stress Tests (`tests/stress/`)

**stress_framework.nim** - Core invariant checking:
- Treasury bounds validation
- Fleet/colony location validity
- Ownership consistency
- Prestige/tech level bounds
- Population consistency

**test_simple_stress.nim** - Basic validation:
- 100-turn simulation
- State integrity checking
- Invalid input handling

**test_engine_stress.nim** - Comprehensive:
- Performance metrics (avg, stddev, outliers)
- Algorithmic scaling analysis
- 500-turn long-duration tests

**test_state_corruption.nim** - Corruption detection:
- 1000-turn simulations
- Repeated game initialization
- Zero-population edge cases
- Negative treasury recovery
- Maximum tech levels
- Extreme prestige values

**test_pathological_inputs.nim** - Fuzzing:
- Invalid system IDs
- Non-existent fleet/colony references
- Invalid research allocations
- Extreme order counts
- Cross-house command attempts

**test_performance_regression.nim** - Performance:
- Turn timing baseline
- O(n^2) algorithm detection
- Variance spike detection
- Memory pressure (state growth)

**test_unknown_unknowns.nim** - Statistical:
- 100-game anomaly detection
- 1000-game rare event hunting
- Prestige/treasury distribution
- Tech progression rates

## State Invariants Checked

The stress framework validates:

1. **Treasury** - Not extremely negative (<-10,000 PP)
2. **Fleet Locations** - All fleets at valid system IDs
3. **Colony Locations** - All colonies at valid system IDs
4. **Ownership** - All entities owned by valid houses
5. **Prestige Bounds** - Reasonable range (-1000 to +10,000)
6. **Tech Levels** - Valid range (0-20)
7. **Colony Population** - Non-negative PU
8. **Infrastructure** - Valid range (0-10)

## New Engine API

Tests use the current engine API:

```nim
# Game creation
import ../../src/engine/engine
var game = newGame()

# Turn resolution
import ../../src/engine/turn_cycle/engine
var rng = initRand(42)
let turnResult = game.resolveTurn(commands, rng)

# State access
import ../../src/engine/state/iterators
for (houseId, house) in game.activeHousesWithId():
  # Process house

for (fleetId, fleet) in game.allFleetsWithId():
  # Process fleet

# State modification
import ../../src/engine/state/engine
game.updateHouse(houseId, house)
game.updateColony(colonyId, colony)
```

## Command Packet Structure

```nim
import ../../src/engine/types/[command, tech, espionage]

let commands = CommandPacket(
  houseId: houseId,
  turn: turn.int32,
  treasury: house.treasury.int32,
  fleetCommands: @[],
  buildCommands: @[],
  repairCommands: @[],
  researchAllocation: ResearchAllocation(),
  diplomaticCommand: @[],
  populationTransfers: @[],
  terraformCommands: @[],
  colonyManagement: @[],
  espionageAction: none(EspionageAttempt),
  ebpInvestment: 0,
  cipInvestment: 0
)
```

## Writing New Tests

```nim
import std/[unittest, random, tables, options]
import ../../src/engine/engine
import ../../src/engine/types/[core, command, house, tech, espionage]
import ../../src/engine/state/iterators
import ../../src/engine/turn_cycle/engine

suite "My Test Suite":

  test "basic functionality":
    var game = newGame()
    var rng = initRand(42)
    
    # Create empty commands
    var commands = initTable[HouseId, CommandPacket]()
    for (houseId, house) in game.activeHousesWithId():
      commands[houseId] = CommandPacket(
        houseId: houseId,
        turn: 1.int32,
        # ... other fields
      )
    
    # Resolve turn
    let turnResult = game.resolveTurn(commands, rng)
    
    # Assertions
    check turnResult.turnAdvanced
```

## Performance Expectations

- **Turn resolution**: <100ms average for 4-house games
- **12-house games**: <500ms average
- **Scaling**: Linear (O(n) per turn, not O(n^2))
- **Memory**: Bounded growth over 500+ turns

## Archive

`tests/archive/` contains old tests preserved for reference.
These use the old API and will not compile against current code.

---

*Last updated: 2026-01*
