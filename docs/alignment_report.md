# Assets.md and Operations.md Alignment Report

## Executive Summary

Analyzed `specs/assets.md` and `specs/operations.md` for consistency, cross-references, and alignment of game mechanics.

**Result:** Files are well-aligned with **1 significant inconsistency** requiring resolution.

---

## Cross-Reference Validation

### ✅ All Cross-References Valid

**From operations.md → assets.md:**
- Line 173: Section 2.4.3 (Raiders) ✓
- Line 248: Section 2.4.3 (Raiders) ✓
- Line 308: Section 2.4.1 (Fighter Squadrons & Carriers) ✓
- Line 321: Section 2.4.1 (Fighter Squadrons & Carriers) ✓
- Line 615: Section 2.4.1 (Fighter Squadrons & Carriers) ✓
- Line 626: Section 2.4.1 (Fighter Squadrons & Carriers) ✓

**From assets.md → operations.md:**
- Line 15: Section 6.1 (Jump Lanes) ✓

All internal cross-references between these files are valid and point to existing sections.

---

## Terminology Consistency

### ✅ Consistent Terminology

| Term | assets.md | operations.md | Status |
|------|-----------|---------------|--------|
| Fighter Squadrons | Section 2.4.1 | Section 7.3.1.2 | ✅ Consistent |
| Colony-Owned vs Carrier-Owned | Section 2.4.1 | Lines 271-321, 582-626 | ✅ Consistent |
| Combat States (Undamaged/Crippled/Destroyed) | Line 424 (Raiders) | Section 7.1.2 | ✅ Consistent |
| Task Force | Section 2.3.5 | Section 7.2 | ✅ Consistent |
| Squadrons vs Fleets | Sections 2.3.3, 2.3.4 | Throughout | ✅ Consistent |
| Starbases | Section 2.4.4 | Section 7.4 | ✅ Consistent |

---

## Mechanics Alignment Analysis

### ✅ Fighter Squadron Combat Mechanics

**assets.md (Section 2.4.1, lines 204-216):**
- Fighters attack first in combat (Phase 2)
- Combat Initiative: 1. Undetected Raiders, 2. Fighters, 3. Detected Raiders, 4. Capital Ships
- Fighters permanently crippled state with reduced DS but full AS
- Colony-owned fighters never retreat

**operations.md (Section 7.3.1.2, lines 265-322):**
- Phase 2: Fighter Squadrons (Intercept Phase)
- All fighters attack simultaneously
- Reduced DS, full AS (no 0.5x AS penalty for crippled state)
- Colony-owned never retreat, carrier-owned retreat with carrier

**Status:** ✅ Fully consistent

---

### ❌ **INCONSISTENCY #1: Carrier Fighter Deployment**

**Issue:** Contradictory rules about whether carrier-owned fighters automatically deploy in combat.

**assets.md (Section 2.4.1, line 244):**
```
Temporary Combat Deployment:
- Available in both hostile and friendly systems
- Player decides to deploy or keep embarked before combat begins
```

**operations.md (Section 7.3.1.2, line 278):**
```
Carrier-Owned Fighters:
- Automatically deploy when carrier enters combat
- Remain carrier-owned assets throughout engagement
```

**Conflict:**
- assets.md: Player **chooses** whether to deploy
- operations.md: Fighters **automatically deploy**

**Recommendation:** Decide which rule is correct and update the other file to match. The player choice mechanic (assets.md) provides more tactical depth, allowing carriers to hold fighters in reserve.

---

### ✅ Raider Detection Mechanics

**assets.md (Section 2.4.3):**
- Comprehensive detection system with ELI vs CLK levels
- Three-step process: Effective ELI Level → Detection Threshold → Detection Roll
- Pre-combat detection phase

**operations.md (Section 7.3.1.1):**
- References assets.md Section 2.4.3 for detection mechanics
- Pre-combat detection phase determines which raiders are detected
- Detected raiders lose ambush advantage (Phase 3 instead of Phase 1)

**Status:** ✅ Fully consistent - operations.md correctly delegates to assets.md

---

### ✅ Capacity Violation Mechanics

**assets.md (Section 2.4.1, lines 135-156):**
- Max FS = floor(PU / 100) × FD multiplier
- Infrastructure requirement: 1 operational Starbase per 5 FS
- Violations trigger 2-turn grace period
- Cannot commission new fighters during violation

**operations.md (lines 308, 613-619):**
- Evaluates capacity violations at end of combat
- 2-turn grace period begins following turn
- Only colony-owned fighters count toward capacity
- Carrier-owned fighters (embarked or deployed) don't count

**Status:** ✅ Fully consistent

---

### ✅ Starbase Modifiers

**assets.md:**
- Line 347: Starbases get +2 ELI modifier for spy scout detection
- Line 521: Starbases equipped with ELI to counter Raiders

**operations.md:**
- Line 252: Starbases get +2 ELI modifier for detection rolls
- Line 637: Starbases get +2 CER modifier for combat rolls

**Clarification:** Two different +2 bonuses:
1. +2 ELI for detection (spy scouts and raiders)
2. +2 CER for combat effectiveness

**Status:** ✅ Consistent (different bonuses for different purposes)

---

### ✅ Crippled Ship Movement Restrictions

**assets.md:**
- No explicit mention (appropriate for assets definition document)

**operations.md:**
- Line 9: Crippled ships cannot jump across restricted lanes
- Line 580: Crippled ships cannot retreat through restricted lanes

**Status:** ✅ Consistent - operations.md appropriately adds movement rules

---

### ✅ Fighter Ownership and Transfer

**assets.md (Section 2.4.1, lines 172-202):**
- Colony-owned: Commissioned at colony, always participate in defense
- Carrier-owned: Loaded from colony, travel with carrier
- Ownership transfer: Colony→Carrier (1 turn loading), Carrier→Colony (1 turn permanent deployment)

**operations.md (lines 271-322, 582-626):**
- Colony-owned always participate, never retreat
- Carrier-owned deploy with carrier, retreat with carrier
- No automatic ownership transfers after combat
- Carrier-owned re-embark (1 turn) after combat

**Status:** ✅ Fully consistent

---

## Summary of Findings

### Critical Issues (Require Resolution)

~~1. **Carrier Fighter Deployment** (assets.md:244 vs operations.md:278)~~
   - ~~Contradictory rules about automatic vs player-choice deployment~~
   - **✅ RESOLVED:** Updated assets.md to match operations.md - fighters automatically deploy when carrier enters combat (automated server-side combat)

### Strengths

- ✅ All cross-references valid
- ✅ Consistent terminology throughout
- ✅ Fighter mechanics well-defined and aligned
- ✅ Capacity violation rules consistent
- ✅ Detection mechanics properly delegated
- ✅ Ownership and transfer rules aligned
- ✅ 6 direct cross-references between files, all valid

---

## Recommendations

1. **Resolve carrier deployment inconsistency:**
   - **Option A:** Keep assets.md rule (player choice) - provides tactical depth
   - **Option B:** Keep operations.md rule (automatic) - simpler, fewer decisions

2. **Consider adding clarification:**
   - In assets.md or operations.md, explicitly note that Starbases have two different +2 bonuses (ELI detection and CER combat) to avoid confusion

3. **Documentation quality:** Both files are well-structured with clear section references and consistent mechanics. The single inconsistency appears to be an oversight rather than systematic misalignment.
