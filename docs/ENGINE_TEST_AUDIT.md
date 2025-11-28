# Engine Integration Test Audit

**Purpose:** Verify all engine integration tests cover the specifications in `docs/specs/`

**Date:** 2025-11-28

---

## Test Coverage Matrix

### 10.1 Space Force (19 Ship Types)

**Spec:** `docs/specs/reference.md:10.1` - 19 ship classes with CST requirements

**Test File:** `tests/integration/test_construction_comprehensive.nim`

| Ship Class | CST | Cost | Test Coverage | Status |
|------------|-----|------|---------------|--------|
| Corvette (CT) | 1 | 20 | ❓ | Unknown |
| Frigate (FG) | 1 | 30 | ❓ | Unknown |
| Destroyer (DD) | 1 | 40 | ❓ | Unknown |
| Light Cruiser (CL) | 1 | 60 | ❓ | Unknown |
| Heavy Cruiser (CA) | 2 | 80 | ❓ | Unknown |
| Battle Cruiser (BC) | 3 | 100 | ❓ | Unknown |
| Battleship (BB) | 4 | 150 | ❓ | Unknown |
| Dreadnought (DN) | 5 | 200 | ❓ | Unknown |
| Super Dreadnought (SD) | 6 | 250 | ❓ | Unknown |
| Planet-Breaker (PB) | 10 | 400 | ❓ | Unknown |
| Carrier (CV) | 3 | 120 | ❓ | Unknown |
| Super Carrier (CX) | 5 | 200 | ❓ | Unknown |
| **Fighter Squadron (FS)** | **3** | **20** | ❌ **NOT TESTED** | **GAP** |
| Raider (RR) | 3 | 150 | ❓ | Unknown |
| Scout (SC) | 1 | 50 | ✅ Tested | Pass |
| Starbase (SB) | 3 | 300 | ❓ | Unknown |
| ETAC (ET) | 1 | 25 | ✅ Tested (colonization) | Pass |
| Troop Transport (TT) | 1 | 30 | ❓ | Unknown |

**Known Gaps:**
- ❌ **Fighter Squadron (FS)** - No integration test verifies fighters can be built
- ❓ Most ship types - Test exists but doesn't explicitly test all 19 types

---

### 10.2 Ground Units (4 Types)

**Spec:** `docs/specs/reference.md:10.2`

**Test File:** `tests/integration/test_construction_comprehensive.nim` (if covered)

| Unit | CST | Cost | Test Coverage | Status |
|------|-----|------|---------------|--------|
| Planetary Shield (PS) | 5 | 100 | ❌ | **NOT TESTED** |
| Ground Batteries (GB) | 1 | 20 | ❌ | **NOT TESTED** |
| Armies (AA) | 1 | 15 | ❌ | **NOT TESTED** |
| Space Marines (MD) | 1 | 25 | ❌ | **NOT TESTED** |

**Known Gaps:**
- ❌ **All 4 ground unit types** - No integration tests verify ground units can be built
- Balance diagnostics show: Armies/Marines NEVER built, Batteries/Shields SOMETIMES built

---

### 10.3 Facilities (4 Types)

**Spec:** `docs/specs/reference.md:10.3`

| Facility | CST | Cost | Test Coverage | Status |
|----------|-----|------|---------------|--------|
| Spaceport (SP) | 1 | 100 | ✅ | Pass |
| Shipyard (SY) | 1 | 150 | ✅ | Pass |
| Starbase (SB) | 3 | 300 | ❓ | Unknown |
| ETAC (ET) | 1 | 25 | ✅ | Pass |

**Status:** Mostly covered by construction tests

---

### Tech Advancement (11 Fields)

**Spec:** `docs/specs/economy.md:4.2`

**Test File:** `tests/integration/test_technology_comprehensive.nim`

| Tech Field | Test Coverage | Status |
|------------|---------------|--------|
| EL (Economic Level) | ✅ | Pass |
| SL (Social Level) | ✅ | Pass |
| CST (Construction Tech) | ✅ | Pass |
| WEP (Weapons Tech) | ✅ | Pass |
| TER (Terraforming) | ✅ | Pass |
| ELI (Electronic Intel) | ✅ | Pass |
| CLK (Cloaking) | ✅ | Pass |
| SLD (Shielding) | ✅ | Pass |
| CIC (Combat Info Center) | ✅ | Pass |
| FD (Fighter Doctrine) | ❓ | Unknown |
| ACO (Advanced Carrier Ops) | ❓ | Unknown |

**Known Gaps:**
- ❓ FD/ACO - Tech fields exist, but unclear if fighter capacity multipliers are tested

---

### Economy System (M5)

**Spec:** `docs/specs/economy.md`

**Test Files:**
- `tests/integration/test_m5_economy_integration.nim`
- `tests/verify_economy_spec.nim`

| Component | Test Coverage | Status |
|-----------|---------------|--------|
| RAW INDEX (Planet × Resources) | ✅ | Pass |
| EL_MOD (+5% per level) | ✅ | Pass |
| CST_MOD (+10% IU capacity per level) | ✅ | Pass |
| PROD_GROWTH (tax curve) | ✅ | Pass |
| GCO calculation | ✅ | Pass |
| NCV calculation | ✅ | Pass |

**Status:** ✅ **Excellent coverage** - All formulas verified

---

### Combat System

**Spec:** `docs/specs/combat.md`

**Test File:** `tests/integration/test_combat_*.nim` (multiple files)

| Component | Test Coverage | Status |
|-----------|---------------|--------|
| CER (Combat Efficiency Rating) | ✅ | Pass |
| Targeting system | ✅ | Pass |
| Damage allocation | ✅ | Pass |
| Retreat logic | ✅ | Pass |
| Ground combat | ❓ | Unknown |

**Known Gaps:**
- ❓ Ground combat - Unclear if armies/marines tested in invasions

---

### Prestige System

**Spec:** `docs/specs/prestige.md`

**Test File:** `tests/integration/test_prestige_comprehensive.nim`

| Component | Test Coverage | Status |
|-----------|---------------|--------|
| Dynamic multiplier | ✅ | Pass |
| Prestige awards | ✅ | Pass |
| Victory conditions | ✅ | Pass |

**Status:** ✅ Comprehensive

---

### Diplomacy System

**Spec:** `docs/specs/diplomacy.md`

**Test File:** `tests/integration/test_diplomacy.nim`

**Status:** ✅ Covered

---

### Espionage System

**Spec:** `docs/specs/espionage.md`

**Test File:** `tests/integration/test_espionage.nim`

**Status:** ✅ Covered

---

## Critical Gaps Summary

### 🔴 HIGH PRIORITY

1. **Fighter Squadron Construction** (FS)
   - Spec: CST 3, Cost 20PP
   - Test: ❌ NO integration test
   - Impact: RBA shows 0 fighters built, can't verify if engine or RBA bug

2. **Ground Units (All 4 Types)**
   - Armies (AA), Marines (MD), Batteries (GB), Shields (PS)
   - Test: ❌ NO integration tests
   - Impact: Can't verify ground combat system works end-to-end

3. **Carrier Operations (FD/ACO Tech)**
   - Fighter capacity multipliers (1.0x, 1.5x, 2.0x)
   - Test: ❓ Unknown if tested
   - Impact: Can't verify fighters can be loaded onto carriers

### 🟡 MEDIUM PRIORITY

4. **Ship Type Coverage**
   - 18 of 19 ship types not explicitly tested
   - Only Scout and Cruiser have explicit tests
   - Impact: Can't verify all ship types can be built

5. **Troop Transports**
   - Spec: CST 1, Cost 30PP
   - Test: ❓ Unknown
   - Impact: Needed for invasions, RBA shows 0 transports built

### 🟢 LOW PRIORITY

6. **Ground Combat Integration**
   - Armies vs Marines vs Batteries
   - Test: ❓ Unknown if covered
   - Impact: Ground combat system may not be fully verified

---

## Recommendations

### Immediate Actions

1. **Create `test_fighter_construction.nim`**
   - Test: Fighter BuildOrder → Fighter created
   - Test: Fighter assignment to carrier
   - Test: Fighter capacity limits (FD/ACO multipliers)

2. **Create `test_ground_units_construction.nim`**
   - Test: Army/Marine/Battery/Shield BuildOrders work
   - Test: Ground unit assignment to colonies
   - Test: Planetary defense calculations

3. **Expand `test_construction_comprehensive.nim`**
   - Add explicit tests for all 19 ship types
   - Verify tech gates (CST requirements)
   - Verify costs match specs

### Investigation Tasks

1. **Audit existing tests**
   - Run: `nimble test` and capture output
   - Verify: Which ship types are actually tested?
   - Document: Coverage gaps

2. **Cross-reference with balance diagnostics**
   - Review: `claude_scripts/analyze_utilization.py` output
   - Compare: "NEVER built" assets vs "NOT TESTED" assets
   - Priority: Assets that fail both checks

---

## Next Steps

**User Decision Required:**

**Option A: Test-Driven Approach** (Recommended)
1. Create missing integration tests FIRST
2. Run tests to verify engine works
3. Then investigate RBA issues
4. Benefit: Know foundation is solid

**Option B: Continue RBA Investigation**
1. Assume engine works (risky)
2. Debug RBA fighter generation
3. Add tests later
4. Benefit: Faster to "fix" but may chase wrong bug

**Which approach do you prefer?**
