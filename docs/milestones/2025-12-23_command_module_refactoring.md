# Command Module Refactoring - Order → Command Terminology

**Date:** 2025-12-23
**Branch:** `refactor-engine`
**Commit:** `fae5b79`

## Objective

Rename systems/command module files to follow the order→command terminology change and align with architecture.md patterns.

## Background

The codebase terminology changed from "order" to "command" but the file names in `systems/command/` still used old names:
- `orders.nim` (validation logic)
- `standing_orders.nim` (persistent behaviors)
- `executor.nim` (execution engine)

Additionally, the module needed to be verified for Data-Oriented Design (DoD) compliance per architecture.md.

## Changes Made

### File Renames

All renames done with `git mv` to preserve history:

```bash
git mv src/engine/systems/command/orders.nim commands.nim
git mv src/engine/systems/command/standing_orders.nim standing_commands.nim
git mv src/engine/systems/command/executor.nim engine.nim
```

**Rationale:**
- `engine.nim` follows architecture.md pattern for systems/*/engine.nim (high-level API)
- `commands.nim` and `standing_commands.nim` align with Command* terminology in types/command.nim

### Import Updates

**Combat Modules:**
- `src/engine/systems/combat/simultaneous_planetary.nim`: `../command/orders` → `../command/commands`
- `src/engine/systems/combat/simultaneous_blockade.nim`: `../command/orders` → `../command/commands`

**Turn Cycle Module (Partial):**
- `src/engine/turn_cycle/command_phase.nim`: Updated imports to use renamed files
  - Fixed paths to use types/command.nim
  - Updated to use CommandPacket instead of OrderPacket
  - Changed executor → engine import

  **Before:**
  ```nim
  import ../../../common/types/core
  import ../systems/orders/[cleanup as order_cleanup, executor]
  import ../types/[..., orders, ...]
  proc resolveCommandPhase*(state: var GameState,
                            orders: Table[HouseId, OrderPacket], ...)
  ```

  **After:**
  ```nim
  import ../../common/logger
  import ../types/[core, game_state, command]
  import ../systems/command/engine as command_engine
  proc resolveCommandPhase*(state: var GameState,
                            orders: Table[HouseId, CommandPacket], ...)
  ```

## Architecture Compliance Assessment

### Current State

**✅ File Organization:**
- `systems/command/engine.nim` - High-level command execution (follows architecture.md)
- `systems/command/commands.nim` - Command validation logic
- `systems/command/standing_commands.nim` - Persistent fleet behaviors
- `systems/command/zero_turn_commands.nim` - Zero-turn administrative commands

**❌ Type Definition Issues:**

`systems/command/commands.nim` currently defines types that should be in `types/command.nim`:

**Duplicate Types in commands.nim:**
```nim
type
  OrderPacket* = object          # Should use CommandPacket from types/command
  FleetOrder* = object           # Should use FleetCommand from types/fleet
  BuildOrder* = object           # Should use BuildCommand from types/production
  TerraformOrder* = object       # Should use TerraformCommand from types/command
  ValidationResult* = object     # Already exists in types/command
```

**Proper Types in types/command.nim:**
```nim
type
  CommandPacket* = object
    fleetCommands*: seq[FleetCommand]
    buildCommands*: seq[BuildCommand]
    terraformCommands*: seq[TerraformCommand]
    standingCommands*: Table[FleetId, StandingCommand]
    # etc.

  ValidationResult* = object
    valid*: bool
    error*: string
```

### Architecture.md Requirements

Per `src/engine/architecture.md`:

**@types/ - Data Schema:**
> Defines ALL pure data structures (Fleet, Ship, GameState).
> Universal data types for the entire engine.

**@systems/ - Game Logic Implementation:**
> Contains all the detailed algorithms for game features.
> Business logic, validation, algorithms. NO type definitions.

**Violation:** `systems/command/commands.nim` defines types instead of importing from `types/command.nim`.

## Known Remaining Work

### 1. Remove Duplicate Type Definitions from systems/command/commands.nim

**Required Changes:**
```nim
# REMOVE these type definitions (already in types/command.nim):
type
  OrderPacket* = object        # → Use CommandPacket from types/command
  BuildOrder* = object         # → Use BuildCommand from types/production
  TerraformOrder* = object     # → Use TerraformCommand from types/command
  DiplomaticAction* = object   # → Use DiplomaticCommand from types/diplomacy
  PopulationTransferOrder* = object  # → Use PopulationTransferCommand from types/command
  ValidationResult* = object   # → Already in types/command
  OrderValidationContext* = object   # → Use CommandValidationContext from types/command
  OrderCostSummary* = object   # → Use CommandCostSummary from types/command
```

**Add imports instead:**
```nim
import ../../types/command
import ../../types/fleet      # FleetCommand
import ../../types/production # BuildCommand

export command.CommandPacket, command.ValidationResult
export command.CommandValidationContext, command.CommandCostSummary
```

**Update all validation procs:**
```nim
# BEFORE:
proc validateFleetOrder*(order: FleetOrder, ...) -> ValidationResult

# AFTER:
proc validateFleetCommand*(cmd: FleetCommand, ...) -> ValidationResult
```

### 2. Fix Broken Imports Throughout Codebase

Multiple files have extensive import path issues (separate from this refactoring):

**turn_cycle/command_phase.nim:**
- Still references non-existent `order_cleanup` module
- Uses old function names (needs updating when cleanup module is found/fixed)
- Many other broken imports remain

**turn_cycle/income_phase.nim:**
- `import ../gamestate` → Should be `import ../types/game_state`
- `import ../orders` → Should be `import ../types/command`
- Multiple broken paths to common/

**systems/fleet/orders.nim:**
- Appears to be **obsolete code** with completely broken imports
- `import ../../common/types/[core, combat, units]` - wrong paths
- `import ../gamestate, ../orders, ../fleet, ...` - wrong paths
- Superseded by `systems/fleet/order_execution.nim`?
- **Action Required:** Determine if this file should be deleted

**systems/fleet/order_execution.nim:**
- `import ../../common/types/core` → Should be `import ../types/core`
- `import ../commands/[executor]` → Should be `import ../command/engine`
- `import ../standing_orders` → Should be `import ../command/standing_commands`
- Multiple other broken imports

### 3. Verify systems/command/engine.nim (formerly executor.nim)

**File not reviewed yet** - needs DoD compliance check:
- Does it follow architecture.md patterns?
- Does it properly use entity managers?
- Are there type definitions that belong in types/?

### 4. Verify systems/command/standing_commands.nim

**File not reviewed yet** - needs DoD compliance check:
- Alignment with types/command.nim (StandingCommand type)
- Proper separation of data and logic
- Entity manager usage if applicable

### 5. Verify systems/command/zero_turn_commands.nim

**File not reviewed yet** - already uses "commands" terminology but:
- Check for DoD compliance
- Verify no type pollution
- Check entity manager usage

## Testing Status

### Compilation Tests

**Not performed yet** - command_phase.nim has extensive import errors that block testing:

```bash
# Will need to test after fixing remaining issues:
nim check src/engine/systems/command/commands.nim
nim check src/engine/systems/command/engine.nim
nim check src/engine/systems/command/standing_commands.nim
nim check src/engine/systems/command/zero_turn_commands.nim
nim check src/engine/turn_cycle/command_phase.nim
```

### Integration Tests

**Blocked** until import issues are resolved throughout turn_cycle/ and related modules.

## Related Work

This refactoring follows the Squadron & Fleet DoD refactoring (commit `9181c43`, documented in `2025-12-23_squadron_fleet_dod_refactoring.md`).

Both refactorings are part of the larger conflict→combat system rename and architecture.md compliance effort.

## Next Steps

### Immediate (High Priority)

1. **Fix systems/command/commands.nim** - Remove duplicate types, import from types/command
2. **Determine fate of systems/fleet/orders.nim** - Delete if obsolete, or fix if needed
3. **Fix command_phase.nim imports** - Resolve all broken import paths

### Short Term

4. **Review systems/command/engine.nim** - DoD compliance check
5. **Review standing_commands.nim** - DoD compliance check
6. **Review zero_turn_commands.nim** - DoD compliance check

### Long Term

7. **Systematic import path audit** - Many files have broken imports beyond command module
8. **Turn cycle module overhaul** - command_phase.nim, income_phase.nim have systemic issues

## Conclusion

File renaming and basic import updates are **complete**. The command module now follows the order→command terminology change and aligns with architecture.md file naming patterns.

However, **significant work remains** to achieve full DoD compliance:
- Type definitions must be moved from systems/ to types/
- Duplicate types must be eliminated
- Broken imports throughout the codebase must be fixed

**Status: PARTIAL ⚠️** - Terminology aligned, but DoD compliance incomplete.

---

**Files Changed:** 6 files (3 renamed, 3 imports updated)
**Lines Changed:** 21 insertions(+), 25 deletions(-)
