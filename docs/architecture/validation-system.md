# Validation System Architecture

**Status**: Implemented (2025-11-27)
**Files**: `src/engine/setup.nim`, `src/engine/config/validators.nim`, `src/engine/starmap.nim:validateMapRings()`

## Overview

The validation system provides comprehensive parameter and configuration validation across the EC4X engine. It follows a **layered architecture** with clear separation of concerns and a **single source of truth** for validation logic.

## Design Principles

1. **Single Source of Truth**: All entry points use the same validation
2. **Defense in Depth**: Multiple validation layers catch different classes of errors
3. **Domain Ownership**: Each module validates its own invariants
4. **Fail Fast**: Validate at parse/load time, not runtime
5. **Clear Errors**: Descriptive messages with actual vs expected values
6. **Future-Proof**: New entry points automatically get validation

## Architecture Layers

```
┌─────────────────────────────────────────┐
│  Entry Points (test, moderator, client) │  Layer 3: User-Facing
│  - Parse with error handling             │  - Entry-specific validation
│  - Call validateGameSetup()              │  - User-friendly messages
│  - Display errors                        │  - Fast fail with helpful output
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│  src/engine/setup.nim                    │  Layer 2: Orchestration
│  validateGameSetup(params) -> Result     │  - SINGLE SOURCE OF TRUTH
│  - Validates complete configuration      │  - All entry points use this
│  - Calls domain validators               │  - Returns structured errors
│  - Cross-parameter validation            │  - Coordinates all validation
└────────────────┬────────────────────────┘
                 │
         ┌───────┴────────┐
         │                │
┌────────▼─────────┐ ┌───▼──────────────────┐
│ Domain Validators │ │ Config Validators     │  Layer 1: Domain Logic
│ starmap.nim       │ │ validators.nim        │  - Each module owns its
│ gamestate.nim     │ │ - Reusable utilities  │    invariants
│ core.nim          │ │ - Range, ratio, sum   │  - Fine-grained validation
│ rba/config.nim    │ │ - Common patterns     │  - Domain-specific rules
└──────────────────┘ └───────────────────────┘
```

## Key Components

### 1. `src/engine/setup.nim` (Layer 2: Orchestrator)

**Purpose**: Single source of truth for game setup validation

**Types**:
```nim
type
  GameSetupParams* = object
    numPlayers*: int    # 2-12
    numTurns*: int      # 1-10000
    mapRings*: int      # 1-20 (zero explicitly not allowed)
    seed*: int64
```

**Main Function**:
```nim
proc validateGameSetup*(params: GameSetupParams): seq[string]
```

Returns empty seq if valid, otherwise list of all validation errors.

**Design Notes**:
- Collects ALL errors (doesn't stop at first failure)
- Delegates domain-specific validation to respective modules
- Validates cross-parameter constraints
- Clear, actionable error messages

**Constants**:
```nim
const
  MIN_PLAYERS* = 2
  MAX_PLAYERS* = 12
  MIN_TURNS* = 1
  MAX_TURNS* = 10000
  MIN_MAP_RINGS* = 1    # Zero rings explicitly not allowed per user requirement
  MAX_MAP_RINGS* = 20
```

### 2. `src/engine/config/validators.nim` (Layer 1: Utilities)

**Purpose**: Reusable validation utilities

**Key Functions**:

| Function | Purpose | Example |
|----------|---------|---------|
| `validateRange(value, min, max, fieldName)` | Check value in range | `validateRange(5, 1, 10, "player_count")` |
| `validatePositive(value, fieldName)` | Check value > 0 | `validatePositive(10, "build_cost")` |
| `validateNonNegative(value, fieldName)` | Check value >= 0 | `validateNonNegative(0, "upkeep")` |
| `validateRatio(value, fieldName)` | Check value in [0.0, 1.0] | `validateRatio(0.5, "aggression")` |
| `validateSumToOne(values, context)` | Check sum ≈ 1.0 | `validateSumToOne([0.33, 0.33, 0.34], "splits")` |
| `validateMinLessThanMax(min, max, fieldName)` | Check min < max | `validateMinLessThanMax(1, 10, "range")` |

**Severity Levels**:
```nim
type ValidationSeverity* = enum
  vWarning  # Log warning but continue
  vError    # Raise exception and halt
```

Most validators support configurable severity (defaults to `vError`).

### 3. Domain Validators (Layer 1: Domain Logic)

#### `src/engine/starmap.nim:validateMapRings()`

**Purpose**: Domain-specific validation for map ring configuration

```nim
proc validateMapRings*(rings: int, playerCount: int = 0): seq[string]
```

**Validates**:
- Zero rings explicitly not allowed (user requirement)
- Reasonable bounds (1-20 rings)
- No requirement that rings >= players (flexible combinations allowed)

**Design Note**: Returns list of errors rather than raising exceptions, allowing caller to collect multiple validation errors.

#### `src/ai/rba/config.nim:validateRBAConfig()`

**Purpose**: Validates RBA AI configuration after loading from TOML

**Validates**:
- Strategy personality traits (all 0.0-1.0)
- Budget allocations per act (sum to 1.0)
- Fleet composition ratios (sum to 1.0)
- Tactical/strategic thresholds (ratios)
- Orders parameters (positive integers, ratios)
- Logistics parameters (positive values, ratios)
- Economic parameters (positive costs)

**Integration**: Called automatically in `loadRBAConfig()` after TOML deserialization.

## Usage Examples

### Entry Point (Layer 3)

```nim
# tests/balance/run_simulation.nim

import ../../src/engine/setup

# Parse arguments with error handling
var numTurns, mapRings, numPlayers: int
var seed: int64

try:
  numTurns = parseInt(paramStr(1))
  # ... parse other params
except ValueError:
  echo "Error: Invalid parameter"
  quit(1)

# Validate using engine
let params = GameSetupParams(
  numPlayers: numPlayers,
  numTurns: numTurns,
  mapRings: mapRings,
  seed: seed
)

let errors = validateGameSetup(params)
if errors.len > 0:
  echo "Invalid game setup:"
  for err in errors:
    echo "  - ", err
  quit(1)

# Proceed with validated parameters...
```

### Convenience Function

```nim
# For CLI tools that should fail fast
validateGameSetupOrQuit(params, "run_simulation")
# Exits with helpful message if invalid
```

### Config Validation

```nim
# src/ai/rba/config.nim

proc loadRBAConfig*(configPath: string): RBAConfig =
  result = Toml.decode(readFile(configPath), RBAConfig)
  validateRBAConfig(result)  # Automatic validation
```

## Validation Rules

### Game Setup Parameters

| Parameter | Range | Special Rules |
|-----------|-------|---------------|
| `numPlayers` | 2-12 | Minimum for gameplay |
| `numTurns` | 1-10000 | Reasonable simulation limits |
| `mapRings` | 1-20 | **Zero explicitly not allowed** |
| `seed` | any int64 | No validation needed |

**Important**: No requirement that `mapRings >= numPlayers`. User requirement allows flexible combinations like 2 players on a 12-ring map.

### RBA Configuration

| Parameter Type | Validation |
|----------------|------------|
| Strategy traits | All ratios (0.0-1.0) |
| Budget allocations | Sum to 1.0 per act (±0.01 tolerance) |
| Fleet composition | Sum to 1.0 per doctrine (±0.01 tolerance) |
| Strategic thresholds | Ratios (0.0-1.0) |
| Tactical parameters | Positive integers |
| Economic costs | Positive integers |

## Error Handling

### Structured Errors

Validation returns structured error lists:

```nim
let errors = validateGameSetup(params)
# errors = [
#   "Invalid player count: 1 (must be 2-12)",
#   "Map rings must be >= 1 (zero rings not supported)"
# ]
```

### Clear Messages

All validation errors include:
- Field name
- Actual value
- Expected range/constraint
- Context for debugging

Examples:
- `"Invalid player count: 1 (must be 2-12)"`
- `"budget_act1_land_grab must sum to 1.0 (got 0.95, tolerance 0.01)"`
- `"strategies_aggressive.aggression must be between 0.0 and 1.0, got 1.5"`

## Testing

### Unit Tests

**File**: `tests/unit/test_validation.nim`

**Coverage**:
- All validator utilities (36 tests)
- Game setup validation (12 tests)
- Map rings domain validation (7 tests)
- Edge cases (min/max values, boundary conditions)
- Error messages (verify correct error reporting)

**Run**: `nim c -r tests/unit/test_validation.nim`

### Integration Tests

**Manual validation tests**:
```bash
# Zero rings → REJECTED
./tests/balance/run_simulation 30 1000 0 4

# Zero turns → REJECTED
./tests/balance/run_simulation 0 1000 3 4

# 1 player (min is 2) → REJECTED
./tests/balance/run_simulation 30 1000 3 1

# Valid params → ACCEPTED
./tests/balance/run_simulation 7 1000 3 2
```

## Benefits

### For Developers

✅ **No duplication**: Validation logic in one place
✅ **Easy to extend**: Add new validators to utilities module
✅ **Testable**: Each layer independently testable
✅ **Type-safe**: Nim's type system catches errors at compile time

### For Users

✅ **Clear errors**: Know exactly what's wrong and how to fix
✅ **Fast fail**: Catch errors before expensive operations
✅ **Complete feedback**: See all errors at once, not one-by-one

### For the System

✅ **Maintainable**: Change validation once, affects everywhere
✅ **Future-proof**: New features automatically get validation
✅ **Robust**: Multiple layers catch different error types
✅ **Consistent**: Same rules applied everywhere

## Migration Guide

### Adding New Entry Points

```nim
# 1. Import setup module
import src/engine/setup

# 2. Parse parameters (with error handling)
let params = GameSetupParams(...)

# 3. Validate
let errors = validateGameSetup(params)
if errors.len > 0:
  # Handle errors

# 4. Proceed with validated parameters
```

### Adding New Validation Rules

**For new setup parameters**:
1. Add field to `GameSetupParams` in `setup.nim`
2. Add validation logic to `validateGameSetup()`
3. Add unit tests in `test_validation.nim`

**For new domain rules**:
1. Add validation proc to domain module (e.g., `starmap.nim`)
2. Call from `validateGameSetup()` if cross-cutting
3. Or call locally if domain-specific
4. Add unit tests

**For new config validation**:
1. Use utilities from `validators.nim`
2. Add validation proc to config module
3. Call after TOML load
4. Add unit tests

## Future Enhancements

### Planned

1. **Game state invariants**: Validate game state at initialization
2. **Economy config validation**: Validate splits sum to 1.0
3. **Cross-config validation**: Validate relationships between configs
4. **Warning levels**: Non-fatal warnings for suboptimal configs

### Considered

1. **Type-level constraints**: Use Nim's range types where possible
2. **Validation registry**: Central registry of all validators
3. **Validation profiles**: Different strictness levels
4. **Telemetry**: Track validation failures for debugging

## Related Documentation

- **Testing Methodology**: `docs/BALANCE_TESTING_METHODOLOGY.md`
- **RBA AI System**: `docs/architecture/ai-system.md`
- **Configuration Files**: `config/*.toml`
- **Style Guide**: `docs/STYLE_GUIDE.md`

## Change Log

**2025-11-27**: Initial implementation
- Created 3-tier validation architecture
- Implemented game setup validation
- Added RBA config validation
- 36 unit tests, all passing
- Blocks zero-ring games per user requirement
- Supports flexible map/player combinations
