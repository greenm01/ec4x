# Config Data Structure Guide

**Purpose:** Choose the right data structure for config definitions.

## Decision Matrix

| Pattern | Use When | Don't Use When | Example |
|---------|----------|----------------|---------|
| **Table[int32, T]** | Numbered sequences (Level 1-10, Tier 1-5) | True categories with semantic meaning | Tech levels, tax tiers |
| **array[Enum, T]** | Categorical data, dense lookups | Numbered sequences (Tier1, Tier2, etc.) | Planet types, material quality |
| **Flat object** | Fixed structure, < 5 simple fields | Repetitive numbered fields | Basic config sections |

## When to Use Tables

**✅ Convert to Table when you see:**
- Numbered field suffixes: `sld1`, `sld2`, `sld3`
- Numbered enum values: `Tier1`, `Tier2`, `Tier3`
- Sequential data: level 1, level 2, level 3
- Sparse data (not all levels exist)
- May expand later (Level 11+)

**❌ Don't convert when you see:**
- Semantic enums: `Eden`, `Lush`, `Harsh` (planet types)
- Categorical data: `VeryPoor`, `Rich` (material quality)
- Dense matrix lookups (every combination exists)
- True 2D tables indexed by meaningful categories

## Pattern 1: Table for Sequential Data

### Example: Tech Levels

**Before:**
```nim
type
  TaxTier* {.pure.} = enum
    Tier1, Tier2, Tier3, Tier4, Tier5

  TaxTierData* = object
    minRate*: int32
    maxRate*: int32
    popMultiplier*: float32

  TaxPopulationGrowthConfig* = object
    tiers*: array[TaxTier, TaxTierData]
```

**Problem:** Enum offset math (Tier1 = index 0, need `tier - 1` conversions)

**After:**
```nim
type
  TaxTierData* = object
    ## Data for a single tax tier (tier 1-5)
    minRate*: int32
    maxRate*: int32
    popMultiplier*: float32

  TaxPopulationGrowthConfig* = object
    tiers*: Table[int32, TaxTierData]
```

**Benefits:**
- ✅ No offset math (`tier - 1`)
- ✅ Self-documenting (`taxTier(3)` not `Tier3`)
- ✅ Easy to extend (tier 6+ without code changes)
- ✅ Sparse data support (tier 3 can be missing)

### Parser Pattern

```nim
for child in node.children:
  if child.name == "tier" and child.args.len > 0:
    let tierNum = child.args[0].getInt().int32

    # Store with actual tier number as key (1-5)
    if tierNum >= 1 and tierNum <= 5:
      result.tiers[tierNum] = TaxTierData(
        minRate: child.requireInt32("minRate", ctx),
        maxRate: child.requireInt32("maxRate", ctx),
        popMultiplier: child.requireFloat32("popMultiplier", ctx)
      )
```

### Validation Helper

```nim
proc taxTier*(tier: int32): TaxTierData =
  ## Get tax tier data with validation
  let cfg = gameConfig.economy.taxPopulationGrowth
  return techLevel(cfg.tiers, tier, "Tax Tier", 1, 5)
```

## Pattern 2: Arrays for Categorical Data

### Example: Material Quality × Planet Type Matrix

**Keep as array:**
```nim
type
  PlanetType* {.pure.} = enum
    ## Semantic categories, not numbered sequence
    Eden, Lush, Benign, Harsh, Hostile, Desolate, Extreme

  MaterialQuality* {.pure.} = enum
    ## Semantic categories, not numbered sequence
    VeryPoor, Poor, Abundant, Rich, VeryRich

  RawMaterialEfficiencyConfig* = object
    ## Dense 2D lookup: every (quality, planet) pair has a value
    multipliers*: array[MaterialQuality, array[PlanetType, float32]]
```

**Why array is correct here:**
- ✅ Both dimensions are semantic categories (not Tier1, Tier2)
- ✅ Dense matrix - every combination exists
- ✅ Fast O(1) lookup by enum value
- ✅ Type-safe - can't use invalid combinations
- ✅ Enums have meaningful names (`Eden` not `PlanetType1`)

**Usage:**
```nim
let efficiency = config.multipliers[MaterialQuality.Rich][PlanetType.Lush]
# Clear, type-safe, fast
```

**If converted to Table (wrong):**
```nim
# ❌ Worse: loses type safety, harder to read
let efficiency = config.multipliers[(MaterialQuality.Rich, PlanetType.Lush)]
```

## Pattern 3: Flat Objects for Simple Config

**Keep flat when:**
- Fixed structure (won't add Planet8, Planet9)
- Small number of fields (< 5)
- Each field has different meaning

**Example:**
```nim
type
  CombatMechanicsConfig* = object
    criticalHitRoll*: int32
    retreatAfterRound*: int32
    maxCombatRounds*: int32
    desperationRoundTrigger*: int32
```

**Why flat is correct:**
- ✅ Each field is semantically different
- ✅ Not repetitive (no criticalHitRoll1, criticalHitRoll2)
- ✅ Won't expand (not criticalHitRoll6+)

## Refactoring Steps (for Table conversion)

### 1. Create Level Data Type

```nim
type
  SldLevelData* = object
    chance*: int32
    roll*: int32
    block*: int32

  PlanetaryShieldsConfig* = object
    levels*: Table[int32, SldLevelData]
```

### 2. Update Parser

```nim
for child in node.children:
  if child.name == "level" and child.args.len > 0:
    let levelNum = child.args[0].getInt().int32

    if levelNum >= 1 and levelNum <= 6:
      result.levels[levelNum] = SldLevelData(
        chance: child.requireInt32("chance", ctx),
        roll: child.requireInt32("roll", ctx),
        block: child.requireInt32("block", ctx)
      )
```

### 3. Add Validation Helper

```nim
proc shieldLevel*(level: int32): SldLevelData =
  let cfg = gameConfig.combat.planetaryShields
  return techLevel(cfg.levels, level, "SLD", 1, 6)
```

### 4. Update KDL Config

```kdl
planetaryShields {
  level 1 { chance 25; roll 17; block 15 }
  level 2 { chance 30; roll 16; block 20 }
  level 3 { chance 35; roll 15; block 25 }
}
```

### 5. Update Call Sites

```nim
# Before: config.sld1Chance
# After:
let data = shieldLevel(1)
let chance = data.chance
```

## Quick Reference Rules

1. **Numbered enums → Table[int32, T]**
   - `Tier1`, `Tier2`, `Tier3` → keys 1, 2, 3
   - `Level2`, `Level3` → keys 2, 3

2. **Semantic enums → Keep array[Enum, T]**
   - `Eden`, `Lush`, `Harsh` (planet types)
   - `VeryPoor`, `Rich` (quality ratings)
   - `Scout`, `Cruiser`, `Dreadnought` (ship classes)

3. **Numbered field suffixes → Table[int32, T]**
   - `sld1Chance`, `sld2Chance` → `levels[1].chance`, `levels[2].chance`

4. **Dense 2D lookups → Keep nested arrays**
   - `array[MaterialQuality, array[PlanetType, float32]]` ✅

5. **Each level type is unique**
   - Never share `StandardLevelData` - always create `XyzLevelData`

## Current Codebase Examples

### ✅ Correctly Uses Tables
- `tech.nim` - All tech levels (EL, SL, WEP, CST, etc.)
- `economy.nim` - Tax tiers (1-5)

### ✅ Correctly Uses Enums
- `economy.nim` - `RawMaterialEfficiencyConfig` (semantic categories)
- `starmap.nim` - `PlanetClass`, `ResourceRating` (semantic categories)
- `ships.nim` - `ShipClass` (semantic ship types)

### 🔄 Candidates for Table Conversion
- `combat.nim` - `PlanetaryShieldsConfig` (sld1-sld6 fields)
- `ground_units.nim` - `PlanetaryShieldConfig` (sld1BlockChance-sld6BlockChance)

---

**Last Updated:** 2025-12-31
**Reference:** See tech.nim and economy.nim refactors for examples
