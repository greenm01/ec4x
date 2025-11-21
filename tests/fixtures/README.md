# Test Fixtures

Shared test data for consistent, reusable test setups.

## Fixture Modules

- **fleets.nim** - Pre-built fleet configurations
- **battles.nim** - Known battle scenarios for regression testing

## Using Fixtures

```nim
import fixtures/fleets

let scoutFleet = testFleet_SingleScout("house-alpha", systemId = 1)
let capitalFleet = testFleet_BalancedCapital("house-beta", systemId = 1)
```

## Available Fleet Fixtures

### Basic Fleets
- `testFleet_SingleScout()` - Lone scout
- `testFleet_BalancedCapital()` - 2 Battleships + 1 Cruiser
- `testFleet_FighterSwarm()` - 4 Fighter squadrons
- `testFleet_Dreadnought()` - Single dreadnought
- `testFleet_PlanetBreaker()` - Bombardment specialist

### Battle Fixtures
- `battle_TechMismatch()` - Tech 3 vs Tech 0
- `battle_FighterVsCapital()` - Tactical matchup
- `battle_ScoutAmbush()` - Cloaked scout attack

## Adding New Fixtures

Add to fleets.nim or battles.nim:

```nim
proc testFleet_YourConfiguration*(owner: HouseId, location: SystemId): seq[CombatSquadron] =
  # Create your fleet setup
  result = @[...]
```

## Benefits

- **Consistency** - Same setup across tests
- **Readability** - Clear fleet names
- **Maintenance** - Update once, fix everywhere
- **Regression** - Lock down known edge cases
