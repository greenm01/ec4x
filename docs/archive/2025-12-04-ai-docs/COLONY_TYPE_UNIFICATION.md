# Colony Type Unification Plan

## Problem Statement

Two separate `Colony` types exist violating DRY principle:
1. `engine/gamestate.nim:Colony` - Full colony with 67+ fields
2. `engine/economy/types.nim:Colony` - Economic subset with 13 fields

This creates:
- Field duplication (planetClass, resources, underConstruction in both)
- Manual conversion code scattered across modules
- Risk of field initialization errors
- 3 places to update when adding fields

## Root Cause

The economy module was designed with a lightweight Colony view for calculations, but:
- Other modules needed full Colony (colonization, construction, resolution)
- Manual field copying in economy_resolution.nim (lines 89-101, 998-1009, 1819-1830)
- No formal conversion function - prone to errors

## Solution: Single Unified Colony Type

**Decision**: Keep ONLY `gamestate.Colony` with ALL fields (DRY principle).

### Changes Made:

1. **gamestate.nim:67-106** - Added economic fields to unified Colony:
   - `populationUnits` (PU)
   - `populationTransferUnits` (PTU)
   - `industrial` (IndustrialUnits)
   - `grossOutput` (GCO)
   - `taxRate`
   - `infrastructureDamage`

2. **economy/types.nim:36** - Removed duplicate Colony type
   - Left note directing to gamestate.nim
   - Kept IndustrialUnits type (no duplication)

3. **colonization/engine.nim** - Updated to use unified Colony:
   - Changed import from `economy/types` to `gamestate`
   - Updated `ColonizationResult.newColony` type
   - Created `initNewColony()` that initializes ALL 67+ fields properly
   - Updated all function signatures to use `Colony` not `econ_types.Colony`

4. **economy/construction.nim** - Import gamestate for Colony type
   - Added `import ../gamestate`
   - Functions now work with full Colony type

## Modules Requiring Updates:

### ✅ Completed:
- [x] engine/gamestate.nim - Added economic fields
- [x] engine/economy/types.nim - Removed duplicate
- [x] engine/colonization/engine.nim - Uses unified type
- [x] engine/economy/construction.nim - Imports gamestate

### ⏳ In Progress:
- [ ] engine/resolution/economy_resolution.nim - Remove manual conversion (lines 89-101, 998-1009, 1819-1830)

### 📋 Pending:
- [ ] engine/fog_of_war.nim - Update VisibleColony for new fields
- [ ] Any other modules using econ_types.Colony

## Manual Conversion Code to Remove:

**economy_resolution.nim:89-101** - Build order processing:
```nim
# OLD: Manual conversion (REMOVE THIS)
var econColony = econ_types.Colony(
  systemId: colony.systemId,
  owner: colony.owner,
  populationUnits: colony.population,  # Wrong mapping!
  populationTransferUnits: 0,
  industrial: econ_types.IndustrialUnits(
    units: colony.infrastructure,  # Wrong! infrastructure != IU
    investmentCost: 30
  ),
  planetClass: colony.planetClass,
  resources: colony.resources,
  underConstruction: none(econ_types.ConstructionProject)
)

# NEW: Just use colony directly
# colony already has populationUnits, industrial, etc.
```

**Note**: The old conversion had BUGS:
- `populationUnits: colony.population` - Wrong! population is display field (millions), PU is different
- `units: colony.infrastructure` - Wrong! infrastructure level (0-10) != IU count

## Testing Plan:

1. **Compilation**: `nimble testBalanceDiagnostics`
   - Verify no type errors
   - Check no ambiguous identifiers

2. **Fog-of-War**: Verify new Colony fields properly filtered
   - Enemy can't see populationUnits, industrial, grossOutput
   - Only visible fields exposed in VisibleColony

3. **Colonization**: New colonies properly initialized
   - All 67+ fields have valid defaults
   - No undefined/null fields

4. **Economy Resolution**: Construction still works
   - No crashes from missing fields
   - IU investment calculates correctly

## Circular Dependency Analysis:

```
gamestate.nim
  imports: economy/types (for IndustrialUnits, ConstructionProject)

economy/types.nim
  imports: common/types (for core types)
  NO Colony type (removed)

economy/construction.nim
  imports: economy/types (for ConstructionProject)
  imports: gamestate (for Colony) ✅ No circular dependency

colonization/engine.nim
  imports: economy/types (for ConstructionProject, IndustrialUnits)
  imports: gamestate (for Colony) ✅ No circular dependency

resolution/economy_resolution.nim
  imports: economy/types
  imports: gamestate
  ✅ No circular dependency
```

**Result**: No circular dependencies. Import order is clean.

## Benefits of Unification:

1. **DRY Compliance**: Colony definition in ONE place
2. **Type Safety**: No manual conversion = no field mapping bugs
3. **Maintainability**: Add field once, available everywhere
4. **Correctness**: No more wrong mappings (population != PU, infrastructure != IU)
5. **Performance**: No conversion overhead

## Migration Status:

- ✅ Type unification complete
- ⏳ Update economy_resolution.nim (remove conversions)
- ⏳ Update fog_of_war.nim (handle new fields)
- ⏳ Test compilation
- ⏳ Test functionality
