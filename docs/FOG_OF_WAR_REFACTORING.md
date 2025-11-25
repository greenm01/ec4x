# Fog-of-War Refactoring Plan

## Status: ✅ COMPLETE

**Last Updated:** 2025-11-24
**Completed:** 2025-11-24

## Goal

Refactor `tests/balance/ai_controller.nim` to enforce fog-of-war at the type level by using `FilteredGameState` instead of `GameState` throughout.

## Progress

### ✅ Completed
1. Created `ai_modules/types.nim` - Extracted all AI type definitions
2. Fixed `assessRelativeStrength()` - Uses `FilteredGameState`, respects fog-of-war
3. Fixed `identifyVulnerableTargets()` - Uses `FilteredGameState`, only sees visible colonies
4. Fixed fog-of-war violations in threat assessment
5. **Refactored ALL ~37 functions to use `FilteredGameState`** ✅
6. **REMOVED TEMPORARY BRIDGE** (lines 2987-3030) ✅
7. **File compiles successfully** ✅

### ⏳ Pending
- Run balance tests to verify AI still functions correctly
- Re-enable diplomatic proposal handling when FilteredGameState exposes it

## The Challenge

The refactoring requires changing data access patterns:

| Old Pattern (GameState) | New Pattern (FilteredGameState) | Notes |
|------------------------|--------------------------------|-------|
| `state.houses[houseId]` | `filtered.ownHouse` | Only own house visible |
| `state.colonies` | `filtered.ownColonies` | Only own colonies |
| Enemy colonies | `filtered.visibleColonies` | Limited intel |
| `state.fleets` | `filtered.ownFleets` | Only own fleets |
| Enemy fleets | `filtered.visibleFleets` | Limited intel |
| `state.turn` | `filtered.turn` | Direct access |
| `state.starMap` | `filtered.starMap` | Direct access |
| Enemy house data | `filtered.housePrestige[id]` | Only prestige visible |
| Intel database | `filtered.ownHouse.intelligence` | Via own house |

## Functions Requiring Refactoring

~37 functions still use `GameState` and need conversion:

**Helper Functions:**
- `getOwnedColonies` - Easy, return filtered.ownColonies
- `getOwnedFleets` - Easy, return filtered.ownFleets
- `findNearestUncolonizedSystem` - Medium, check visible systems
- `findWeakestEnemyColony` - Medium, use visibleColonies

**Intelligence:**
- `updateIntelligence` - Easy, already uses controller.intelligence
- `findBestColonizationTarget` - Medium

**Strategic:**
- `planCoordinatedOperation` - Hard, complex logic
- `updateOperationStatus` - Medium
- `identifyImportantColonies` - Easy
- `updateFallbackRoutes` - Medium
- `syncFallbackRoutesToEngine` - Easy
- `planCoordinatedInvasion` - Hard
- `manageStrategicReserves` - Medium
- `respondToThreats` - Hard
- `assessGarrisonNeeds` - Medium

**Order Generation:**
- `generateFleetOrders` - Hard, main function
- `generateBuildOrders` - Medium
- `generateResearchAllocation` - Easy
- `generateDiplomaticActions` - Medium
- `generatePopulationTransfers` - Medium
- `generateSquadronManagement` - Medium
- `generateCargoManagement` - Medium
- `generateEspionageAction` - Medium

**Main Entry Point:**
- `generateAIOrders` - Critical, remove TEMPORARY BRIDGE (lines 2946-2995)

## Strategy

Given the complexity (3059 lines, 37+ functions), recommended approach:

1. **Phase A: Core Helpers** - Fix getOwnedColonies, getOwnedFleets (easy wins)
2. **Phase B: Intelligence** - Fix intelligence gathering functions
3. **Phase C: Strategic** - Fix strategic planning functions
4. **Phase D: Order Generation** - Fix order generation functions
5. **Phase E: Remove Bridge** - Delete TEMPORARY BRIDGE in generateAIOrders
6. **Phase F: Test** - Comprehensive testing

## Key Insights

**The core issue:** Functions often iterate over ALL colonies/fleets in the game, but FilteredGameState only provides:
- Own assets (full details)
- Visible enemy assets (limited intel)

**Solution patterns:**

1. **For own assets only:**
   ```nim
   for colony in filtered.ownColonies:
     # process own colony
   ```

2. **For enemy assets:**
   ```nim
   for visCol in filtered.visibleColonies:
     # process visible enemy colony (limited intel)
   ```

3. **For all known systems:**
   ```nim
   # Own colonies
   for colony in filtered.ownColonies:
     processColony(colony.systemId)

   # Known enemy colonies
   for visCol in filtered.visibleColonies:
     processEnemyColony(visCol.systemId)
   ```

4. **Check if system is colonized:**
   ```nim
   # Old: systemId in state.colonies
   # New: Check both own and visible
   proc isSystemColonized(filtered: FilteredGameState, systemId: SystemId): bool =
     for colony in filtered.ownColonies:
       if colony.systemId == systemId:
         return true
     for visCol in filtered.visibleColonies:
       if visCol.systemId == systemId:
         return true
     return false
   ```

## Next Steps

1. Add helper functions for common patterns (isSystemColonized, etc.)
2. Refactor functions in phases A-F
3. Remove TEMPORARY BRIDGE
4. Test thoroughly

## Why This Matters

**Enforcing fog-of-war at the type level prevents bugs** where the AI accidentally uses information it shouldn't have access to. This ensures fair play and realistic AI behavior.

The TEMPORARY BRIDGE currently defeats this purpose by converting FilteredGameState back to GameState, allowing functions to access omniscient data.
