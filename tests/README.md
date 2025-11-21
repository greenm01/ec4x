# EC4X Test Suite

Modular test organization for the EC4X game engine.

## Directory Structure

```
tests/
├── unit/              Unit tests for individual modules
│   ├── test_hex.nim          Hex coordinate system
│   ├── test_ship.nim         Ship types and capabilities
│   ├── test_fleet.nim        Fleet composition
│   ├── test_system.nim       Star systems
│   └── test_config.nim       Configuration loading
│
├── combat/            Combat system tests
│   ├── test_space_combat.nim    10 integrated scenarios
│   ├── test_ground_combat.nim   5 ground combat scenarios
│   ├── test_combat_compile.nim  Compilation check
│   ├── harness.nim              Bulk execution framework
│   ├── generator.nim            Random scenario generation
│   ├── reporter.nim             JSON export
│   └── run_stress_test.nim      10k battle stress test
│
├── integration/       Multi-system integration tests
│   ├── test_starmap_robust.nim       Starmap generation
│   ├── test_starmap_validation.nim   Starmap validation
│   └── test_offline_engine.nim       Offline engine
│
├── scenarios/         Hand-crafted test scenarios
│   ├── historical/    Known bugs and edge cases
│   ├── balance/       Game balance verification
│   └── regression/    Regression prevention
│
└── fixtures/          Shared test data
    ├── fleets.nim     Pre-built fleet configurations
    └── battles.nim    Known battle setups
```

## Quick Start

### Run All Unit Tests
```bash
for test in tests/unit/test_*.nim; do
  nim c -r "$test"
done
```

### Run Combat Scenarios
```bash
# Space combat scenarios
nim c -r tests/combat/test_space_combat.nim

# Ground combat scenarios
nim c -r tests/combat/test_ground_combat.nim

# 10,000 battle stress test
nim c -r tests/combat/run_stress_test.nim
```

### Run Integration Tests
```bash
nim c -r tests/integration/test_starmap_robust.nim
nim c -r tests/integration/test_starmap_validation.nim
```

## Test Philosophy

### Unit Tests
- Test single modules in isolation
- Fast execution (<100ms each)
- No external dependencies
- Pure function testing

### Combat Tests
- Integrated combat scenarios
- Stress testing with random generation
- Performance benchmarking
- Edge case discovery

### Integration Tests
- Multi-system interactions
- Full workflow testing
- System boundary verification
- Data flow validation

### Fixtures
- Reusable test data
- Consistent fleet setups
- Known battle configurations
- Regression test baselines

## Test Output

Combat tests generate three output files (gitignored):

1. **combat_test_results.json** - Full round-by-round logs (~145 MB)
2. **combat_summary.json** - Aggregate statistics
3. **combat_stats.csv** - Spreadsheet format

## Adding New Tests

### Unit Test
```bash
# Create new test file
cat > tests/unit/test_mymodule.nim << 'EOF'
import unittest
import ../../src/engine/mymodule

suite "MyModule Tests":
  test "basic functionality":
    check myFunction() == expectedResult
EOF

# Run it
nim c -r tests/unit/test_mymodule.nim
```

### Combat Scenario
```nim
# Add to tests/combat/test_space_combat.nim
proc scenario_MyNewTest*() =
  echo "\n=== Scenario: My Test ==="
  let attackers = createFleet(...)
  let result = resolveCombat(...)
  assert result.victor.isSome
```

### Integration Test
```bash
# Create new integration test
cat > tests/integration/test_myfeature.nim << 'EOF'
import unittest
import ../../src/engine/[module1, module2]

suite "MyFeature Integration":
  test "modules work together":
    let data = module1.getData()
    let result = module2.process(data)
    check result.isValid
EOF
```

## Continuous Testing

During development:
```bash
# Watch mode (requires entr or similar)
ls tests/**/*.nim | entr nim c -r /_

# Quick smoke test
nim c -r tests/unit/test_hex.nim && \
nim c -r tests/combat/test_combat_compile.nim
```

## Test Coverage Goals

- [x] Hex coordinate system
- [x] Ship types and capabilities
- [x] Fleet composition
- [x] Star systems
- [x] Starmap generation
- [x] Space combat (all phases)
- [x] Ground combat (bombardment, invasion, blitz)
- [x] Combat stress testing (10k+ battles)
- [ ] Fleet movement + pathfinding
- [ ] Turn resolution
- [ ] Economy and production
- [ ] Diplomacy integration
- [ ] Tech research
- [ ] Victory conditions

## Performance Benchmarks

From 10,000 battle stress test:
- **Combat Resolution**: 15,600 combats/second
- **Average Battle**: 2.37 rounds
- **Edge Case Rate**: 0.42% desperation rounds
- **Spec Violations**: 0

## Further Documentation

See README.md files in each subdirectory for module-specific details:
- `unit/README.md` - Unit testing guidelines
- `combat/README.md` - Combat test architecture
- `integration/README.md` - Integration test patterns
- `fixtures/README.md` - Using test fixtures
- `scenarios/README.md` - Scenario organization
