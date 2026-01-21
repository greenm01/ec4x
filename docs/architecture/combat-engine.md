## Combat Engine Implementation Status

## Overview

The EC4X combat engine is being implemented as pure game logic with typed data structures, following the architecture principle of transport-agnostic design. No JSON handling in the engine - that happens at boundaries (storage/transport layers).

## Completed Components

### 1. Core Combat Types (`src/engine/combat_types.nim`)

**Pure data structures for combat:**
- `CombatPhase`: Enum for combat phases (Ambush, Intercept, MainEngagement)
- `CombatSquadron`: Squadron wrapper with combat state tracking
- `TaskForce`: Collection of squadrons with ROE and modifiers
- `CombatResult`: Complete battle outcome with round-by-round results
- `BattleContext`: Input structure for combat resolution

**Key design decisions:**
- All types are pure data (no I/O, no side effects)
- State tracking for destruction protection rules
- Deterministic seed for reproducible combat

### 2. CER System (`src/engine/combat_cer.nim`)

**Combat Effectiveness Rating implementation:**
- Deterministic PRNG (Linear Congruential Generator)
- 1D10 dice rolling with seed-based reproducibility
- CER modifier calculation (scouts, morale, ambush, surprise)
- Critical hit detection (natural 9)
- CER table lookup (0.25x, 0.5x, 0.75x, 1.0x effectiveness)

**Features:**
- Seed from string or int64
- Round-up damage calculation
- Pretty-print formatting for logs
- Testing helpers for distribution verification

### 3. Target Priority System (`src/engine/combat_targeting.nim`)

**Target selection according to specs:**
- Diplomatic filtering (Enemy, NAP, Neutral status)
- Bucket classification (Raider=1, Capital=2, Destroyer=3, Fighter=4, Starbase=5)
- Special fighter targeting rules (fighters target fighters first)
- Weighted random selection (base weight × crippled modifier)
- Complete targeting pipeline

**Implements Section 7.3.2:**
- Hostile force identification
- Bucket-order traversal
- Weighted probability distribution

## Architecture Flow

```
Test Scenario (Typed)
    ↓
BattleContext
    ↓
Combat Engine (Pure Logic)
    ↓
CombatResult (Typed)
    ↓
Test Analysis / JSON Export (Boundary)
```

## Pending Implementation

### Phase 1: Core Combat Resolution

#### 4. Task Force Formation
**File:** `src/engine/combat_taskforce.nim`
- Merge fleets into Task Forces (Section 7.2)
- ROE adoption (highest of joining fleets)
- Cloaking status determination
- Fighter deployment from carriers
- Spacelift protection

#### 5. Combat Phase Resolution
**File:** `src/engine/combat_resolution.nim`
- Phase 1: Undetected Raiders (Ambush)
  - Pre-combat detection rolls
  - +4 CER modifier
  - Simultaneous attacks
- Phase 2: Fighter Squadrons (Intercept)
  - All fighters attack simultaneously
  - No CER (full AS as damage)
  - Binary state (undamaged → destroyed)
- Phase 3: Capital Ships (Main Engagement)
  - Attack order by flagship CR (highest first)
  - CER rolls per squadron
  - Simultaneous resolution within CR tiers

#### 6. Squadron Damage System
**File:** `src/engine/combat_damage.nim`
- Apply damage to squadrons
- State transitions: Nominal → Crippled → Destroyed
- Destruction protection (can't skip states in same round)
- Critical hit bypass
- AS reduction when crippled (÷2)
- State propagation to all ships in squadron

#### 7. Retreat & ROE System
**File:** `src/engine/combat_retreat.nim`
- ROE evaluation (0-10 scale with morale modifiers)
- Strength ratio calculation
- Homeworld defense exception (never retreat)
- Multi-faction retreat priority
- Retreat destination pathfinding
- Carrier fighter withdrawal

### Phase 2: Testing Infrastructure

#### 8. Random Fleet Generator
**File:** `tests/combat_generator.nim`
- Generate random squadrons with ship mix
- Configurable tech levels
- Balanced/unbalanced scenarios
- Edge case generators (all fighters, all Raiders, etc.)

#### 9. Test Harness
**File:** `tests/combat_test_harness.nim`
- Run typed combat scenarios
- Round-by-round logging
- Edge case detection
- Spec violation checks
- Performance metrics

#### 10. JSON Export Layer
**File:** `tests/combat_report_json.nim`
- Convert `CombatResult` to JSON
- Aggregate statistics across battles
- AI-friendly format (structured, consistent)
- Export formats: JSON, Markdown, CSV

## Usage Example (Proposed)

```nim
# tests/test_basic_combat.nim
import combat_types, combat_resolution

# Create test scenario with typed data
let attacker = newSquadron(
  newEnhancedShip(ShipClass.Battleship),
  id = "sq-att-1",
  owner = "house-alpha"
)

let defender = newSquadron(
  newEnhancedShip(ShipClass.Cruiser),
  id = "sq-def-1",
  owner = "house-beta"
)

let context = BattleContext(
  systemId: "system-test",
  taskForces: @[
    TaskForce(house: "house-alpha", squadrons: @[attacker], roe: 6),
    TaskForce(house: "house-beta", squadrons: @[defender], roe: 6)
  ],
  seed: 12345,
  maxRounds: 20
)

# Pure engine call - no JSON
let result = resolveCombat(context)

# Analyze result (typed)
echo "Victor: ", result.victor
echo "Rounds: ", result.totalRounds

# Export to JSON for AI analysis (boundary layer)
let jsonReport = exportToJson(result)
writeFile("test_results.json", jsonReport)
```

## Testing Strategy

### Unit Tests
- CER roll distribution (verify uniform 1-10)
- Target weight calculations
- Bucket classification
- State transitions

### Integration Tests
- Complete combat scenarios
- Multi-round battles
- Retreat conditions
- Critical hit effects

### Fuzz Testing
- 1000+ random battles
- Edge case discovery
- Spec violation detection
- Balance analysis

### AI-Friendly Reports

**JSON Structure:**
```json
{
  "test_run_id": "combat_test_20251120_001",
  "seed": 12345,
  "total_battles": 1000,
  "scenarios": [
    {
      "name": "balanced_cruiser_vs_cruiser",
      "iterations": 100,
      "attacker_wins": 52,
      "defender_wins": 48,
      "avg_rounds": 3.4,
      "edge_cases": []
    }
  ],
  "spec_violations": [],
  "anomalies": [
    {
      "type": "stalemate",
      "frequency": 2,
      "scenarios": ["battleship_vs_starbase"]
    }
  ],
  "balance_metrics": {
    "raider_ambush_success_rate": 0.73,
    "fighter_vs_capital_efficiency": 0.42,
    "critical_hit_frequency": 0.098
  }
}
```

## Design Principles Enforced

✅ **Transport-Agnostic**: Engine works with Nim types, not JSON
✅ **Deterministic**: Same seed = same outcome (reproducible tests)
✅ **Pure Functions**: No I/O, no side effects, just transformations
✅ **Type Safe**: Compiler enforces spec compliance
✅ **Testable**: Easy to create scenarios and verify outcomes
✅ **Documented**: Code references spec sections directly

## Next Steps

1. Implement combat resolution (phases 1-3)
2. Implement damage system with destruction protection
3. Implement retreat mechanics
4. Build random fleet generator
5. Create test harness
6. Add JSON export layer
7. Run 1000+ random battles
8. Analyze for edge cases and balance issues

## References

- [operations.md](../specs/operations.md) - Section 7.0 Combat
- [Architecture Overview](./overview.md) - Design principles
- [Data Flow](./dataflow.md) - Turn resolution pipeline
