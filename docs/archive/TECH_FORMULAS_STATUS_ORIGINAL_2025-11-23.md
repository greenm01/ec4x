# Tech Effect Formulas - Status Report
Generated: 2025-11-23

## Summary

This document tracks which tech effect formulas need design decisions vs which are placeholders/dead code.

---

## ✅ IMPLEMENTED & WORKING

### 1. Economic Level (EL)
**Location:** `src/engine/research/effects.nim:20-28`
**Formula:** +5% GCO per level, max 50% (10 levels)
**Status:** ✅ CONFIRMED - Per economy.md:4.2
**Usage:** Applied in economy calculations

### 2. Weapons Tech (WEP)
**Location:** `src/engine/research/effects.nim:30-46`
**Formula:** +10% AS/DS per level
**Status:** ✅ CONFIRMED - Per economy.md:4.6
**Usage:** Applied to combat squadrons

### 3. Terraforming Tech (TER)
**Location:** `src/engine/research/effects.nim:80-112`
**Formulas:**
- Cost: 60/180/500/1000/1500/2000 PP by class
- Speed: `max(1, 10 - TER_level)` turns
- Requirement: TER level >= target planet class
**Status:** ✅ IMPLEMENTED (today!)
**Usage:** Fully integrated in resolve.nim

---

## 🔧 PLACEHOLDER - NEED DESIGN DECISIONS

### 4. Construction Tech (CST) - Squadron Limit
**Location:** `src/engine/research/effects.nim:56`
**Current Formula:** `10 + cstLevel`
**Status:** 🔧 PLACEHOLDER
**Usage:** Called by gamestate.nim:354

**Question for Designer:**
- Is base 10 squadrons per house correct?
- Should this scale linearly with CST level?
- Any maximum squadron limit?

### 5. Construction Tech (CST) - Build Speed
**Location:** `src/engine/research/effects.nim:63`
**Current Formula:** +5% per level
**Status:** 🔧 PLACEHOLDER (UNUSED!)
**Usage:** NOT CALLED ANYWHERE

**Question:**
- Should this be implemented?
- How should it affect ship/building construction times?
- Linear scaling appropriate?

### 6. Planetary Shields (SLD) - Strength
**Location:** `src/engine/research/effects.nim:130`
**Current Formula:** `sldLevel * 10`
**Status:** 🔧 PLACEHOLDER (UNUSED!)
**Usage:** NOT CALLED ANYWHERE

**Note:** Shield mechanics exist in combat/ground.nim but don't use this function.

**Question:**
- What should shield strength per level be?
- How does it reduce bombardment damage?
- Integration with existing shield code?

### 7. Counter-Intelligence (CIC) - Counter-Espionage Bonus
**Location:** `src/engine/research/effects.nim:138`
**Current Formula:** Direct 1:1 mapping (cicLevel)
**Status:** 🔧 PLACEHOLDER (UNUSED!)
**Usage:** NOT CALLED ANYWHERE

**Note:** CIC is used in espionage resolution but via direct tech level checks, not this function.

**Question:**
- Should this function be removed (redundant)?
- Or should espionage code use this for consistency?

### 8. Fighter Doctrine (FD) - Fighter Effectiveness
**Location:** `src/engine/research/effects.nim:146`
**Current Formula:** +5% per level
**Status:** 🔧 PLACEHOLDER (UNUSED!)
**Usage:** NOT CALLED ANYWHERE

**Question:**
- Should FD affect fighter combat effectiveness?
- How should it integrate with combat system?
- Apply to fighter AS/DS or different mechanic?

### 9. Carrier Operations (ACO) - Capacity Bonus
**Location:** `src/engine/research/effects.nim:154`
**Current Formula:** +2 fighters per level
**Status:** 🔧 PLACEHOLDER (UNUSED!)
**Usage:** NOT CALLED ANYWHERE

**Question:**
- Should ACO increase carrier fighter capacity?
- Is +2 per level appropriate?
- How does this integrate with squadron mechanics?

---

## ✅ IMPLEMENTED ELSEWHERE (Not in effects.nim)

### 10. Electronic Intelligence (ELI) - Detection
**Location:** `src/engine/intelligence/detection.nim`
**Formula:** Complex mesh network calculation with:
- Individual scout ELI levels
- Mesh network bonus: +1 per additional scout
- Starbase bonus: +2 if present
- Weighted average for multiple scouts
**Status:** ✅ FULLY IMPLEMENTED
**Note:** TODO comment in effects.nim:72 is OUTDATED - should be removed

### 11. Cloaking Tech (CLK) - Stealth
**Location:** `src/engine/intelligence/detection.nim`
**Formula:** Detection check: d20 + ELI_total vs (10 + CLK_level)
**Status:** ✅ FULLY IMPLEMENTED
**Note:** TODO comment in effects.nim:121 is OUTDATED - should be removed

---

## Recommendations

### Critical (Do Now):
1. **Remove outdated TODOs** for ELI (line 72) and CLK (line 121) - these are implemented

### High Priority (Design Decision Needed):
2. **CST Squadron Limit** - Confirm base=10 and linear scaling is correct
3. **SLD Shield Strength** - Integrate with existing shield mechanics or remove

### Medium Priority (Feature Implementation):
4. **CST Build Speed** - Decide if this should be implemented
5. **FD Fighter Effectiveness** - Decide how to integrate with combat
6. **ACO Carrier Capacity** - Decide if carriers should have tech-based capacity

### Low Priority (Code Cleanup):
7. **CIC Function** - Remove redundant function, espionage uses direct tech levels
8. Consider moving squadron limit calculation to config

---

## Dead Code Analysis

These functions exist but are NEVER called:
- `getConstructionSpeedBonus()` - Line 63
- `getELIDetectionBonus()` - Line 72 (superseded by detection.nim)
- `getCloakingDetectionDifficulty()` - Line 121 (superseded by detection.nim)
- `getPlanetaryShieldStrength()` - Line 130
- `getCICCounterEspionageBonus()` - Line 138
- `getFighterDoctrineBonus()` - Line 146
- `getCarrierCapacityBonus()` - Line 154

**Recommendation:** Either implement these features or remove the dead code.

---

## Design Questions Summary

1. **CST**: Confirm squadron limit base (currently 10) and scaling
2. **CST**: Should build speed bonus be implemented?
3. **SLD**: How should shields reduce bombardment damage? Integration needed.
4. **CIC**: Remove redundant function or refactor espionage to use it?
5. **FD**: Should fighter doctrine affect combat? How?
6. **ACO**: Should carrier capacity scale with tech? How integrate with squadrons?

---

## Code Quality Notes

**Good:**
- WEP, EL, TER formulas are well-documented and match specs
- Detection system (ELI/CLK) is sophisticated and working
- Clear separation between effects.nim and specialized systems

**Needs Work:**
- 7 placeholder/dead functions cluttering the codebase
- Outdated TODO comments confuse the implementation status
- Unclear which features are planned vs abandoned

**Suggestion:** Schedule design review session to decide fate of placeholder functions.
