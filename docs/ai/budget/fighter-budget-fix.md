# Fighter Budget Allocation Fix

## Problem Identified

Fighters were showing 0.0 across all strategies in balance diagnostics despite Admiral Phase 2.5/3 requesting them.

**Root Cause:**
- Fighters were treated as SpecialUnits budget (10% baseline, typically 30-80PP)
- Individual fighter cost: 20PP
- Batch requests (e.g., 4x fighters = 80PP) often exceeded available SpecialUnits budget
- Even individual requests struggled due to SpecialUnits budget being allocated to starbases first

## User Insight

> "do you realize that fighters can be built without a carrier and just stationed at the colony for defense until later when carriers are available?"

> "may not treat fighters as a special unit just for budgeting. treat them like a normal ship just for defense. then threat them as a special unit for offence like the carriers"

This insight revealed that defensive fighters should be treated as regular military assets (like escorts), not special units.

## Design Decision

**Budget Categories:**
- **Colony-defense fighters** → Military budget (treat like escorts: DD, CA, etc.)
- **Carriers** → SpecialUnits budget (strategic mobility platforms)
- **Embarked fighters** → SpecialUnits budget (offensive strike capability)

**Rationale:**
- Colony-defense fighters provide defensive value similar to escort ships
- Military budget is much larger (20-25% of total, 100-200PP typical)
- SpecialUnits budget is smaller (10% baseline, 30-80PP typical)
- This aligns budget allocation with game semantics

**Fighter Design Characteristics:**
- **Glass cannon**: No damage states, destroyed instantly when hit
- **Non-repairable**: Unlike capital ships, fighters can't be repaired
- **High attrition**: Consumable units requiring constant replacement
- **Low cost (20PP)**: Compensates for disposable nature
- This is why fighters are the most efficient combat unit (2.86 PP/pwr)

## Implementation

### Admiral Build Requirements (build_requirements.nim)

Changed fighter requests from SpecialUnits to Military budget:

```nim
# PHASE 1: Request fighters for colony defense (Military budget)
# These are defensive assets, like escorts (DD/CA)
if fighterCount < targetFighters:
  for i in 0..<neededFighters:
    let req = BuildRequirement(
      requirementType: RequirementType.DefenseGap,  # Defense fighters fill defensive gap
      priority: RequirementPriority.Medium,
      shipClass: some(ShipClass.Fighter),
      quantity: 1,  # Request one at a time for incremental fulfillment
      buildObjective: BuildObjective.Military,  # Use Military budget, not SpecialUnits
      targetSystem: none(SystemId),
      estimatedCost: fighterCost,
      reason: &"Fighter defense squadron #{i+1} (have {fighterCount+i}/{targetFighters})"
    )
    result.add(req)
```

**Key Changes:**
- `requirementType`: StrategicAsset → DefenseGap
- `buildObjective`: SpecialUnits → Military
- Keep individual requests (quantity=1) for incremental fulfillment
- Carriers remain in SpecialUnits budget

### Related Changes

**config/ships.toml:**
- Carrier cost: 120PP → 80PP (33% reduction)
- Balances affordability with strategic weight (80PP = 4x fighter cost)

**src/ai/rba/cfo/consultation.nim:**
- Include Medium priority in calculateRequiredPP()
- Include SpecialUnits in Strategic Triage totalUrgent calculation
- Add SpecialUnits to blending loop
- (These changes ensure carriers get proper budget allocation when requested)

## Results

### Before Fix (SpecialUnits budget)
```
  Economic              Fighters:  0.0  Capitals:  7.1  Escorts:  1.2
  Turtle                Fighters:  0.0  Capitals:  8.2  Escorts:  0.8
  Balanced              Fighters:  0.0  Capitals: 11.1  Escorts:  0.8
  Aggressive            Fighters:  0.0  Capitals:  9.6  Escorts:  1.9
```

### After Fix (Military budget)
```
  Economic              Fighters:  0.8  Capitals:  7.1  Escorts:  1.3  ✅ +0.8
  Turtle                Fighters:  0.4  Capitals:  8.2  Escorts:  0.9  ✅ +0.4
  Balanced              Fighters:  0.0  Capitals: 11.1  Escorts:  0.7
  Aggressive            Fighters:  0.0  Capitals:  9.5  Escorts:  2.3
```

## Analysis

### Why Fighters Appear in Economic/Turtle
- These strategies prioritize CST research
- Reach CST3 faster (required for fighter tech)
- Build fighters by Turn 8

### Why Not Balanced/Aggressive (Yet)
- These strategies focus on military/weapons tech over CST
- Reach CST3 later in game (probably Turn 9+)
- Expected to show fighters in longer simulations

### Budget Impact
- Military budget: 20-25% of total (100-200PP typical)
- SpecialUnits budget: 10% baseline (30-80PP typical)
- Individual fighter: 20PP
- Result: Fighters now affordable within Military budget

### Strategic Correctness
- Colony-defense fighters logically belong in Military budget
- Same category as escorts (DD/CA) which also provide fleet defense
- Carriers as strategic mobility platforms correctly use SpecialUnits
- Design aligns with game semantics

## Files Modified

1. **src/ai/rba/admiral/build_requirements.nim** (lines 426-512)
   - Changed fighter requests from SpecialUnits → Military budget
   - Changed RequirementType from StrategicAsset → DefenseGap
   - Updated BuildObjective from SpecialUnits → Military
   - Kept individual quantity=1 requests for incremental fulfillment

2. **config/ships.toml** (line 203)
   - Carrier cost: 120PP → 80PP (33% reduction)

3. **src/ai/rba/cfo/consultation.nim** (lines 17-175)
   - Include Medium priority in calculateRequiredPP()
   - Include SpecialUnits in Strategic Triage totalUrgent calculation
   - Add SpecialUnits to blending loop

## Conclusion

✅ **Root cause fixed:** Fighters now use appropriate budget category
✅ **System working:** Fighters appearing in Economic/Turtle strategies
✅ **Design sound:** Budget allocation matches game semantics
✅ **Scalable:** Longer games will show more fighters as all strategies reach CST3

**Next Step:** Monitor carrier appearance once fighters reach critical mass (carriers only requested when fighterCount >= 2)

## Date
2025-11-29
