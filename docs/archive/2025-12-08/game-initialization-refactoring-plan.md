# EC4X Game Setup and Configuration Refactoring Plan

## Overview

Refactor EC4X's game initialization system to eliminate hardcoded values, improve modularity, support flexible per-fleet configuration, and organize code following DRY/DoD best practices. Current `gamestate.nim` is bloated (1047 lines) with mixed responsibilities.

## Goals

1. **Extract initialization logic** from gamestate.nim into well-organized sub-modules
2. **Eliminate all hardcoded values** - move to TOML config files
3. **Support per-fleet configuration** in game setup (despite toml_serialization limitations)
4. **Organize capacity functions** to avoid circular dependencies
5. **Maintain clean API** for player clients and AI players
6. **Ensure zero breaking changes** - all 101+ integration tests must pass

## Architecture Design

### Module Structure

```
src/engine/
├── gamestate.nim              # REDUCED: Types + queries only (~600 lines)
├── initialization/            # NEW: Game setup sub-modules
│   ├── game.nim              # Public API: newGame, newGameState
│   ├── house.nim             # House initialization
│   ├── colony.nim            # Colony creation (homeworld + ETAC)
│   ├── fleet.nim             # Fleet composition and creation
│   ├── validation.nim        # Setup validation
│   └── config_resolver.nim   # Resolve config conflicts/defaults
└── config/
    └── game_setup_config.nim # Extended fleet configuration types
```

### Import Hierarchy (No Circular Dependencies)

```
initialization/game.nim (public API)
    ↓ imports
initialization/[house, colony, fleet, validation, config_resolver]
    ↓ import
gamestate.nim (types + queries only)
    ↓ NEVER imports initialization or capacity modules

economy/capacity/* modules
    ↓ import gamestate.nim
    (NO CYCLE - gamestate doesn't import them back)
```

**Key principle**: `gamestate.nim` NEVER imports initialization or capacity modules. Capacity modules can safely import gamestate without creating cycles.

### Public API Design

**initialization/game.nim** - Single entry point for game creation:

```nim
proc newGame*(gameId: string, playerCount: int, seed: int64 = 42,
              setupConfigPath: string = "game_setup/standard.toml"): GameState

proc newGameState*(gameId: string, playerCount: int, starMap: StarMap,
                  setupConfigPath: string = "game_setup/standard.toml"): GameState

proc validateSetup*(playerCount: int, mapRings: int, turnCount: int): seq[string]
```

**For backward compatibility**, gamestate.nim will re-export initialization/game during transition:
```nim
# In gamestate.nim (temporary, during transition)
import initialization/game
export game.newGame, game.newGameState
```

## Configuration Changes

### 1. Fleet Configuration (game_setup/standard.toml)

**Challenge**: toml_serialization doesn't handle deep nesting well.

**Solution**: Use flat indexed tables `[fleet1]`, `[fleet2]`, etc.

```toml
# game_setup/standard.toml

[starting_fleet]
# BACKWARD COMPATIBLE: Aggregated counts (fallback if no individual fleets)
etac = 2
light_cruiser = 2
destroyer = 2
scout = 0

# NEW: Individual fleet definitions
fleet_count = 4  # Number of starting fleets to create

[fleet1]
ships = ["ETAC", "LightCruiser"]
cargo_ptu = 50  # Optional: Override default ETAC cargo

[fleet2]
ships = ["ETAC", "LightCruiser"]
cargo_ptu = 50

[fleet3]
ships = ["Destroyer"]

[fleet4]
ships = ["Destroyer"]

[starting_resources]
treasury = 1200               # Currently hardcoded in gamestate.nim:483
starting_prestige = 100       # Already in config
default_tax_rate = 0.50       # Already configurable

[house_naming]
name_pattern = "House{index}"  # Currently hardcoded
use_theme_names = false        # If true, use house_themes.toml
```

**Nim types**:
```nim
type
  FleetConfig* = object
    ships*: seq[string]        # Ship class names
    cargoPtu*: Option[int]     # Optional PTU cargo override

  StartingFleetConfig* = object
    # Backward compatible aggregated counts
    etac*, lightCruiser*, destroyer*, scout*: int
    # New individual fleet configs
    fleetCount*: int
    fleets*: seq[FleetConfig]  # Loaded from [fleet1], [fleet2], etc.
```

**Loading strategy**: Parse `[fleet1]`, `[fleet2]`, ... dynamically up to `fleet_count`.

### 2. Economy Configuration (config/economy.toml)

```toml
# Add these sections to existing economy.toml

[industrial_growth]
# IU passive growth formula: max(min_growth, floor(PU / divisor))
passive_growth_divisor = 100.0     # RESOLVED: Use 100.0 (2x rate for 30-turn games)
passive_growth_minimum = 2.0       # Minimum 2 IU growth per turn
applies_modifiers = true            # Apply tax + starbase bonuses

[starbase_bonuses]
growth_bonus_per_starbase = 0.05   # 5% population growth per starbase
max_starbases_for_bonus = 3        # Max 3 starbases (15% max bonus)
eli_bonus_per_starbase = 2         # ELI+2 per operational starbase

[squadron_capacity]
# Capital squadron formula: max(minimum, floor(Total_IU / divisor) * multiplier)
capital_squadron_iu_divisor = 100   # Currently in capital_squadrons.nim:69
capital_squadron_multiplier = 2     # Currently in capital_squadrons.nim:69
capital_squadron_minimum = 8        # Currently in capital_squadrons.nim:72

[production_modifiers]
el_bonus_per_level = 0.05          # 5% per EL (currently in production.nim:92)
cst_bonus_per_level = 0.10         # 10% per CST (currently in production.nim:123)
blockade_penalty = 0.40            # 40% production when blockaded (production.nim:134)
prod_growth_numerator = 50.0       # (50 - taxRate) / 500 formula (production.nim:104)
prod_growth_denominator = 500.0
```

### 3. RBA Configuration (config/rba.toml)

```toml
# Add to existing rba.toml

[intelligence]
# RESOLVED: Use 10 turns (config is source of truth)
colony_intel_stale_threshold = 10   # Currently 5 in intelligence.nim:150, 10 in intelligence_distribution.nim:74
system_intel_stale_threshold = 5
starbase_intel_stale_threshold = 15

[eparch_industrial]
# RESOLVED: Match economy.toml (100.0)
iu_growth_divisor = 100.0           # Currently 200.0 in industrial_investment.nim:61
iu_payback_threshold_turns = 10     # Currently hardcoded:146
iu_affordability_multiplier = 3     # Currently hardcoded:134
iu_investment_fraction = 0.25       # 25% of deficit (hardcoded:130)
iu_minimum_investment = 10          # Minimum 10 IU (hardcoded:130)

[treasury_thresholds]
terraform_minimum = 800             # terraforming.nim:34
terraform_buffer = 200              # terraforming.nim:77
transfer_healthy = 500              # logistics.nim:439
salvage_critical = 100              # logistics.nim:548
reactivation_healthy = 1000         # logistics.nim:1066

[affordability_checks]
# Treasury multipliers for different build decisions
general_multiplier = 1.5            # build_requirements.nim:104
shield_multiplier = 2.0             # build_requirements.nim:1017, 1226
critical_multiplier = 3.0           # build_requirements.nim:1043
```

### 4. Facilities Configuration (config/facilities.toml)

```toml
# Add to existing facilities.toml

[planetary_shields]
# Shield block chance by tech level
sld1_block_chance = 0.30  # 30%
sld2_block_chance = 0.40  # 40%
sld3_block_chance = 0.50  # 50%
sld4_block_chance = 0.60  # 60%
sld5_block_chance = 0.70  # 70%
sld6_block_chance = 0.80  # 80%

shield_damage_reduction = 0.25     # 25% reduction from bombardment
shield_invasion_difficulty = 0.15  # +15% difficulty per SLD level

[ground_defense]
defense_per_battery = 10           # Currently hardcoded in commissioning.nim:76
```

## Critical Files and Changes

### Files to Create

1. **src/engine/initialization/game.nim** (new, ~150 lines)
   - Public API: `newGame`, `newGameState`, `validateSetup`
   - Re-exported from gamestate.nim for backward compatibility
   - Orchestrates house/colony/fleet initialization

2. **src/engine/initialization/house.nim** (new, ~80 lines)
   - Extract `initializeHouse` from gamestate.nim:473-515
   - Update to use config for treasury, prestige, house naming

3. **src/engine/initialization/colony.nim** (new, ~120 lines)
   - Extract `createHomeColony` from gamestate.nim:517-611
   - Extract `createETACColony` from gamestate.nim:721-763

4. **src/engine/initialization/fleet.nim** (new, ~100 lines)
   - Extract `createStartingFleet` from gamestate.nim:613-645
   - Add support for new FleetConfig format with per-fleet composition

5. **src/engine/initialization/validation.nim** (new, ~60 lines)
   - Extract `validateTechTree` from gamestate.nim:418-435
   - Consolidate setup validation logic

6. **src/engine/initialization/config_resolver.nim** (new, ~40 lines)
   - Handle defaults and fallbacks for fleet configurations
   - Resolve backward compatibility (aggregated vs individual fleets)

### Files to Modify

1. **src/engine/gamestate.nim** (reduce from 1047 to ~600 lines)
   - Keep: Type definitions, query functions, advanceTurn
   - Remove: All initialization functions (lines 367-763, ~393 lines)
   - Add: Re-export initialization/game for backward compatibility (temporary)

2. **src/engine/config/game_setup_config.nim** (extend ~50 lines)
   - Add FleetConfig type and fleet parsing logic
   - Extend StartingFleetConfig with fleet_count and fleets fields
   - Add parsing for indexed tables `[fleet1]`, `[fleet2]`, etc.

3. **src/engine/economy/income.nim** (2 changes)
   - Line 260: Replace `currentPU / 100.0` with `globalEconomyConfig.industrial_growth.passive_growth_divisor`
   - Add import for extended economy config

4. **src/ai/rba/eparch/industrial_investment.nim** (1 change)
   - Line 61: Replace `float(populationUnits) / 200.0` with `globalEconomyConfig.industrial_growth.passive_growth_divisor`
   - RESOLUTION: Change 200.0 → 100.0 to match engine behavior

5. **src/ai/rba/intelligence.nim** (1 change)
   - Line 150: Replace `age > 5` with `age > globalRBAConfig.intelligence.colony_intel_stale_threshold`

6. **src/ai/rba/drungarius/intelligence_distribution.nim** (1 change)
   - Line 74: Replace `> 10` with `> globalRBAConfig.intelligence.colony_intel_stale_threshold`
   - RESOLUTION: Both now use config (10 turns)

7. **config/economy.toml** (add 4 sections)
   - `[industrial_growth]`, `[starbase_bonuses]`, `[squadron_capacity]`, `[production_modifiers]`

8. **config/rba.toml** (add 3 sections)
   - `[intelligence]`, `[eparch_industrial]`, `[treasury_thresholds]`, `[affordability_checks]`

9. **config/facilities.toml** (add 2 sections)
   - `[planetary_shields]`, `[ground_defense]`

10. **game_setup/standard.toml** (add 2 sections)
    - `[starting_resources]` with treasury field, `[house_naming]`, individual `[fleet1-4]` sections

### Files with Minor Updates (re-exports, imports)

- **src/core.nim** - Update imports if needed (currently uses starmap directly)
- **src/ai/analysis/game_setup.nim** - Update to use initialization/game API
- **tests/test_core.nim** - Should work unchanged (backward compatible API)
- **tests/integration/test_*.nim** - Should work unchanged (backward compatible API)

## Implementation Sequence

### Phase 1: Configuration Extensions (No Breaking Changes)

1. **Add config sections** to economy.toml, rba.toml, facilities.toml, game_setup/standard.toml
   - All values match current hardcoded defaults
   - Tests: All tests pass unchanged

2. **Extend game_setup_config.nim** with FleetConfig types
   - Add backward-compatible parsing
   - Tests: Config loading tests pass

### Phase 2: Create Initialization Modules (Parallel to Existing)

3. **Create initialization/ directory** with empty stub modules
   - Document module responsibilities
   - No code moves yet

4. **Copy (don't move) initialization functions** to new modules
   - gamestate.nim keeps original functions
   - New modules have duplicates
   - Tests: All tests still use gamestate.nim versions

5. **Update new modules to use config accessors**
   - Replace hardcoded values with config lookups
   - Tests: Create new tests for initialization modules

### Phase 3: Switch to New Modules (Incremental)

6. **Add re-exports from gamestate.nim**
   ```nim
   import initialization/game
   export game.newGame, game.newGameState
   ```
   - Tests: All tests work unchanged

7. **Update calling code one module at a time**
   - Start with test files
   - Then AI analysis code
   - Then main simulation
   - Tests: Full test suite after each file

8. **Remove old functions from gamestate.nim**
   - After all callers updated
   - Tests: Full test suite passes

### Phase 4: Replace Hardcoded Values (One at a Time)

9. **Replace IU growth divisor** in income.nim and industrial_investment.nim
   - Tests: `nimble testBalanceQuick` - verify unchanged behavior

10. **Replace intel staleness** thresholds in RBA modules
    - Tests: RBA integration tests pass

11. **Replace squadron capacity** hardcoded values
    - Tests: Capacity enforcement tests pass

12. **Replace other hardcoded values** (starbase bonuses, shield chances, etc.)
    - Tests: Integration tests pass after each change

### Phase 5: Fleet Configuration Support

13. **Implement per-fleet configuration** parsing in game_setup_config.nim
    - Parse indexed tables [fleet1], [fleet2], etc.
    - Tests: Config parsing tests with new format

14. **Update fleet initialization** to use per-fleet configs
    - Maintain backward compatibility with aggregated format
    - Tests: Fleet creation tests with both formats

15. **Update standard.toml** with individual fleet definitions
    - Tests: Full game initialization with new format

### Phase 6: Cleanup and Documentation

16. **Remove deprecated code** and temporary re-exports
17. **Update CLAUDE.md** with new patterns and module structure
18. **Add architecture documentation** for initialization system
19. **Final validation**: Run full test suite + balance tests

## Config Conflict Resolutions

| Parameter | Locations | Resolution | Rationale |
|-----------|-----------|------------|-----------|
| IU passive growth divisor | income.nim:260 (100.0)<br>industrial_investment.nim:61 (200.0) | **100.0** in config | 2x rate for 30-turn games, engine behavior is correct |
| Intel staleness (colony) | intelligence.nim:150 (5 turns)<br>intelligence_distribution.nim:74 (10 turns) | **10 turns** in config | Config is source of truth, more realistic for gameplay |
| Squadron capacity | gamestate.nim:827-828 (hardcoded)<br>capital_squadrons.nim:69 (100, 2, 8) | Move to economy.toml | Already calculated correctly in capacity module |
| Starbase growth bonus | gamestate.nim:865 (0.05, 3 max)<br>production.nim (uses same) | **0.05** from config | Use accessor function |
| Tax penalties | income.nim + prestige/economic.nim<br>(DUPLICATED) | **Config only** | Remove source duplicates, single source of truth |

## Testing Strategy

After each phase:
1. **Unit tests**: `nimble test` - All pass
2. **Integration tests**: 101+ integration tests - All pass
3. **Balance tests**: `nimble testBalanceQuick` (20 games, 7 turns) - Unchanged win rates
4. **Full simulation**: Run 100-game batch, verify no anomalies

## Success Criteria

- ✅ gamestate.nim reduced to ~600 lines (type definitions + queries only)
- ✅ All initialization logic in dedicated initialization/ modules
- ✅ Zero hardcoded game values - all from TOML configs
- ✅ Per-fleet configuration supported in game_setup/standard.toml
- ✅ Clean import hierarchy with no circular dependencies
- ✅ All 101+ integration tests pass unchanged
- ✅ Balance tests show unchanged economic behavior
- ✅ RBA AI continues functioning correctly
- ✅ Clean API for player clients and AI players

## Risks and Mitigations

**Risk**: Breaking existing tests
- **Mitigation**: Incremental approach with backward-compatible re-exports

**Risk**: Circular import dependencies
- **Mitigation**: gamestate.nim NEVER imports initialization or capacity modules

**Risk**: Config value changes affecting game balance
- **Mitigation**: All config defaults match current hardcoded values exactly

**Risk**: toml_serialization limitations for fleet configs
- **Mitigation**: Use flat indexed tables [fleet1], [fleet2] instead of nested arrays

**Risk**: Forgetting to update a hardcoded value
- **Mitigation**: Grep for all TODO comments and numeric literals before completion

## End State

After refactoring:
- Clean separation of concerns (types, queries, initialization)
- All game parameters configurable via TOML
- Flexible per-fleet game setup
- Maintainable codebase following DRY/DoD principles
- No breaking changes to existing code
- Foundation for future scenario system
