# Combat System Tests

Comprehensive test suite for EC4X combat mechanics.

## Test Files

### Scenario Tests
- **test_space_combat.nim** - Integrated space combat scenarios (10 scenarios)
- **test_ground_combat.nim** - Planetary combat scenarios (5 scenarios)
- **test_combat_compile.nim** - Compilation check for combat system

### Test Infrastructure
- **harness.nim** - Bulk test execution and analysis
- **generator.nim** - Random scenario generation
- **reporter.nim** - JSON export for test results
- **run_stress_test.nim** - 10,000+ battle stress test runner

## Running Combat Tests

```bash
# Run integrated space combat scenarios
nim c -r tests/combat/test_space_combat.nim

# Run ground combat scenarios
nim c -r tests/combat/test_ground_combat.nim

# Run 10k stress test
nim c -r tests/combat/run_stress_test.nim

# Compilation check
nim c -r tests/combat/test_combat_compile.nim
```

## Test Output

Tests generate three output files:

1. **combat_test_results.json** - Full round-by-round logs (large)
2. **combat_summary.json** - Aggregate statistics
3. **combat_stats.csv** - Spreadsheet format

## Test Scenarios

### Space Combat (test_space_combat.nim)
1. Patrol vs Patrol - Basic engagement
2. Starbase Defense - Detection bonuses
3. Planetary Bombardment - Space to ground
4. Planetary Invasion - Multi-phase assault
5. Planetary Blitz - Fast capture
6. Planet-Breaker Attack - Shield bypass
7. Multi-House Convergence - 3 factions
8. System Transit Encounter - Fleet collision
9. Cloaked Raider Ambush - Stealth mechanics
10. Four-Way Free-For-All - Maximum chaos

### Ground Combat (test_ground_combat.nim)
1. Basic Bombardment
2. Bombardment with Shields
3. Planet-Breaker Shield Bypass
4. Planetary Invasion
5. Planetary Blitz

## Adding New Combat Tests

### Scenario Tests
Add new test procedures to test_space_combat.nim or test_ground_combat.nim:

```nim
proc scenario_YourNewTest*() =
  echo "\n=== Scenario: Your Test Name ==="

  # Set up forces
  let attackers = createFleet(...)
  let defenders = createFleet(...)

  # Run combat
  let result = resolveCombat(...)

  # Verify results
  assert result.victor.isSome
  echo $"Victor: {result.victor.get}"
```

### Stress Tests
Use the generator and harness modules:

```nim
import combat/generator, combat/harness

let scenarios = generateTestSuite(count = 100)
let results = runTestSuite(scenarios)
```

## Architecture

The combat test system has three layers:

1. **Scenario Layer** - Hand-crafted test cases
2. **Generation Layer** - Random scenario creation
3. **Harness Layer** - Bulk execution and analysis

This separation allows both targeted testing and broad coverage.
