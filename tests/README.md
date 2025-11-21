# EC4X Combat Testing Framework

Comprehensive combat simulation and testing infrastructure for EC4X game engine.

## Overview

This framework generates random combat scenarios with varying fleet compositions, tech levels, and player counts to systematically test the combat engine for edge cases, balance issues, and spec violations.

## Test Scenario Types

### 2-Faction Battles
- **Balanced**: Equal strength fleets with similar compositions
- **Asymmetric**: Unbalanced forces (strong vs weak)
- **Fighter vs Capital**: Tactical matchup testing
- **Raider Ambush**: Cloaked raider scenarios with ambush bonuses
- **Tech Mismatch**: Advanced tech (level 3) vs primitive (level 0)
- **Home Defense**: Defender never retreats (homeworld rules)

### Multi-Faction Battles
- **3-way**: Three empires converging simultaneously
- **4-way**: Four empires with mixed tech levels
- **6-way**: Six-player free-for-all
- **12-way**: Maximum player count stress test

Each multi-faction battle randomizes:
- Tech levels (0-3) per faction
- Fleet sizes (1-4 squadrons)
- Prestige/morale (30-70)

## Running Tests

```bash
# Compile and run default test suite (30 scenarios)
nim c -r tests/run_combat_tests.nim

# Or run directly
./tests/run_combat_tests
```

## Output Formats

### JSON (Full Details)
`combat_test_results.json` - Complete round-by-round combat logs including:
- All attack rolls and CER calculations
- State transitions (undamaged → crippled → destroyed)
- Critical hits
- Phase-by-phase resolution

### JSON (Summary)
`combat_summary.json` - Aggregate statistics only:
- Test run metadata
- Win rates by house
- Edge case counts
- Spec violation summary
- Average combat duration

### CSV (Spreadsheet)
`combat_stats.csv` - One row per test:
```
test_name,victor,rounds,duration,edge_cases,violations,num_factions,total_squadrons
multi_faction_12_8,none,3,0.0004,1,0,12,25
```

## Edge Cases Detected

- **Instant Victory**: Combat resolved in 1 round
- **Mutual Destruction**: All forces destroyed (common in 12-player battles)
- **Stalemate**: No progress after 20 rounds
- **Long Combat**: Exceeds 15 rounds
- **No Damage Loop**: 5+ consecutive rounds without state changes
- **Immediate Retreat**: Retreat after first eligible round

## Spec Violations Checked

- **No Retreat First Round**: Section 7.3.5 violation
- **Stalemate at 20 Rounds**: Combat duration limit (Section 7.3.4)
- **Invalid Victor**: Victor must be in survivors list

## Test Results Summary

Sample run (30 tests, 12 max players):
- **Average Rounds**: 2.37
- **Critical Hit Rate**: 10.3% per round
- **Edge Cases**: 13 detected (6 instant victories, 7 mutual destructions)
- **Spec Violations**: 0

Notable findings:
- 12-player battles consistently result in mutual destruction
- Tech level 3 vs 0 creates instant victories despite numerical superiority
- Homeworld defense dramatically extends combat duration

## Architecture

### Pure Nim Types
Combat engine uses pure Nim types throughout - no JSON in core logic. JSON export happens only at the boundary layer (`combat_report_json.nim`).

### Deterministic PRNG
Linear Congruential Generator ensures same seed = same battle result, enabling:
- Reproducible test failures
- Regression testing
- Balance verification

### Modular Design
```
combat_generator.nim      → Random scenario generation
combat_test_harness.nim   → Bulk execution & analysis
combat_report_json.nim    → Export layer (AI-friendly)
run_combat_tests.nim      → Test runner
```

## Customization

### Create Custom Test Suites

```nim
import combat_generator, combat_test_harness, combat_report_json

# Generate specific scenarios
let scenarios = @[
  generateMultiFactionBattle("epic_battle", 12345, numFactions = 8),
  generateTechMismatchBattle("tech_war", 54321),
  generateHomeDefenseBattle("last_stand", 99999)
]

# Run and export
let results = runTestSuite(scenarios, verbose = true)
exportToJsonFile(results, "custom_results.json")
```

### Adjust Fleet Configurations

```nim
var config = defaultConfig()
config.techLevel = 2
config.maxSquadrons = 10
config.minShipsPerSquadron = 3
config.allowedShipClasses = @[ShipClass.Dreadnought, ShipClass.Carrier]

let fleet = generateRandomFleet(config, "house-titans", seed)
```

## Future Enhancements

- [ ] Starbase defense scenarios
- [ ] Coalition/alliance battles (diplomatic status variations)
- [ ] Reinforcement arrival mid-combat
- [ ] Retreat path testing (fallback systems)
- [ ] Balance analysis reports (which ship classes dominate?)
- [ ] Performance profiling for large-scale battles
