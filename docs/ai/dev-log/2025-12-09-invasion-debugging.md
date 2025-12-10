# Invasion System Debugging - 2025-12-09

## Session Goal
Fix RBA AI to enable colonies changing hands via combat (invasions).

## TL;DR - Critical Finding

**ROOT CAUSE IDENTIFIED:** Rules of Engagement (ROE) blocking all attacks!

- ✅ Marines load correctly (5 Marines on transports)
- ✅ Fleet utilization fixed (attack orders generated)
- ✅ Prestige inflation reduced 60%
- ❌ **ROE 1-4 prevents fleets from attacking defended colonies**

**The Problem:** Standing orders set defensive ROE (1-4) based on personality aggression. When fleets try to attack enemy colonies, the engine checks ROE and **refuses engagement** unless force superiority is 2:1 to 4:1.

**Design Clarification:** ROE is set **before combat** based on mission profile and controls **tactical retreat** behavior during combat (not whether to initiate).

Example use cases:
- **Probing mission:** ROE 2-4 (test defenses, retreat quickly)
- **Main assault:** ROE 8-10 (commit to engagement, fight through)
- **Border patrol:** ROE 5-6 (defend but don't overcommit)
- **Last stand:** ROE 10 (defend homeworld, fight to the death)
- **Raiding:** ROE 3-4 (hit and run, preserve fleet)

**Current Bug:** FleetOrder type has NO ROE field! Attack orders (Bombard/Invade) inherit the fleet's standing order ROE (defensive, 1-4), causing tactical retreat on first contact.

**The Fix:** Add ROE field to FleetOrder so attack missions can specify appropriate retreat thresholds.

**Files to modify:**
- `src/engine/order_types.nim` - Add `roe: Option[int]` to FleetOrder
- `src/ai/rba/domestikos/offensive_ops.nim` - Set ROE=8 for attack orders
- `src/engine/resolution/fleet_orders.nim` - Respect tactical order ROE

---

## Issues Found & Fixed

### 1. Marines Not Staying Loaded ✅ FIXED
**Problem:** Marines were auto-loading onto TroopTransports, then immediately unloading at homeworld.

**Root Cause:** `src/ai/rba/logistics.nim` lines 409-419 unloaded Marines when fleets were idle at own colonies.

**Fix:** Disabled auto-unload logic for Marines. Rationale: Fleets at homeworld are preparing for next attack, not "mission complete".

**Result:** 5 Marines consistently loaded on transports (turns 11-21).

**Files Changed:**
- `src/ai/rba/logistics.nim` - Disabled Marine unload

---

### 2. Invasion Orders Without Loaded Marines ✅ FIXED
**Problem:** AI generating Invade/Blitz orders even when transports were empty.

**Root Cause:** `src/ai/rba/domestikos/offensive_ops.nim` lines 278-289 checked for transport ships, not loaded Marines.

**Fix:** Added validation for `ship.cargo.quantity > 0` before allowing invasion orders. Returns `FleetOrderType.Bombard` if no loaded Marines.

**Result:** AI correctly selects Bombard when no Marines available, Invade/Blitz only when Marines loaded.

**Files Changed:**
- `src/ai/rba/domestikos/offensive_ops.nim` lines 278-321

---

### 3. Fleet Utilization Blocking All Attacks ✅ FIXED
**Problem:** 0 invasion/bombardment orders generated despite 140 space battles.

**Root Cause:** `src/ai/rba/domestikos/offensive_ops.nim` line 411 only allowed `Idle` or `UnderUtilized` fleets to attack. But ALL fleets had `DefendSystem` standing orders, marking them as `Optimal` utilization.

**Diagnosis:**
- `src/ai/rba/domestikos/fleet_analysis.nim` lines 61-68 classify fleets with DefendSystem as `Optimal`
- Only single-ship defenders are `UnderUtilized`
- Result: No fleets available for offensive operations

**Fix:** Changed line 413 to allow `Optimal` fleets (defensive fleets can be reassigned for offensive ops).

**Result:** Attack orders being generated (log shows "Domestikos: Bombard attack - fleet X → enemy colony at system Y").

**Files Changed:**
- `src/ai/rba/domestikos/offensive_ops.nim` line 413

---

### 4. Prestige Inflation ✅ PARTIALLY FIXED
**Problem:** Total prestige growing from 14k → 37k in 20 turns (not zero-sum).

**Root Cause:**
- Colonization: +25 base × 15 multiplier = +375 prestige per colony (9 colonies = +3,375)
- Tech advancement: +10 base × 15 multiplier = +150 prestige per level
- No offsetting penalties

**User Requirement:** "This is a zero sum game... award prestige for conquering planets. colonization should be minimal."

**Fix:** Reduced prestige values in `config/prestige.toml`:
- `establish_colony`: 25 → 1 (96% reduction)
- `tech_advancement`: 10 → 2 (80% reduction)

**Result:** Prestige inflation reduced 60% (+1,744/turn vs +4,376/turn), but still not zero-sum.

**Files Changed:**
- `config/prestige.toml` lines 73-74

**Notes:**
- Conquest prestige already zero-sum (attacker +50, defender -50)
- Remaining inflation from: tech, population milestones, espionage success
- Full zero-sum requires either removing non-combat sources or adding redistribution mechanic

---

## Current Status: ROE Blocking Attacks ⚠️ CRITICAL ISSUE

### Symptoms
- **Space combat:** 140 battles ✅
- **Attack orders generated:** Logs show "Bombard attack - fleet X → colony Y" ✅
- **Marines loaded:** 5 Marines on transports ✅
- **Orbital combat:** 0 ❌
- **Bombardment rounds:** 0 ❌
- **Invasions:** 0 ❌
- **Colonies captured:** 0 ❌

### ROOT CAUSE IDENTIFIED: Rules of Engagement (ROE)

**The Problem:** Standing orders set defensive ROE values that prevent offensive combat!

### Evidence
```
[INFO] [AI] house-ordos Domestikos: Bombard attack - fleet house-ordos_fleet_7_13 → enemy colony at system 38 (priority: 100.0)
[INFO] [AI] house-atreides Domestikos: Bombard attack - fleet house-atreides_fleet4 → enemy colony at system 37 (priority: 150.0)
```

But then:
```
[INFO] [ORDERS] [CONFLICT STEPS 1 & 2] Resolving space/orbital combat (0 systems)...
```

### ROE Values Observed

From simulation logs:
```
house-harkonnen (Turtle, aggression=0.1):     ROE 1 = "Engage only defenseless"
house-corrino   (Economic, aggression=0.3):   ROE 3 = "Engage with 3:1 advantage"
house-atreides  (Balanced, aggression=0.4):   ROE 4 = "Engage with 2:1 advantage"
house-ordos     (Aggressive, aggression=0.9): ROE 9 = "Engage even if outgunned 3:1"
```

**ROE Calculation:** `src/ai/rba/standing_orders_manager.nim` line 333
```nim
let baseROE = int(p.aggression * 10.0)  # 0-10 scale
```

**Applied to DefendSystem:** Line 457
```nim
let order = createDefendSystemOrder(fleet, targetSystem, 3, baseROE)
```

### The Problem

**ROE controls combat engagement**, not just retreats! From `docs/specs/operations.md`:

> **ROE Retreat Thresholds:**
> - ROE 0: Avoid all hostile forces (threshold 0.0)
> - ROE 1: Engage only defenseless (threshold 999.0)
> - ROE 2: Engage with 4:1 advantage (threshold 4.0)
> - ROE 4: Engage with 2:1 advantage (threshold 2.0)
> - ROE 6: Engage equal or inferior (threshold 1.0)
> - ROE 10: Engage regardless of size (threshold 0.0)

**Most fleets have ROE 1-4**, meaning they won't engage enemy colonies unless they have **massive force superiority** (2:1 to 4:1).

### Why Space Combat Happens But Invasions Don't

- **Space battles (140 total):** Happen when enemy fleets encounter each other in deep space
- **Orbital combat (0 total):** Requires deliberately attacking a defended colony
- **ROE check:** Before engaging colony defenses, engine checks if fleet's AS/DefenderAS >= threshold
- **Result:** Most fleets fail ROE check and refuse to attack

### Solutions

**Option 1: Separate ROE for Offensive vs Defensive Operations**
- Standing orders (DefendSystem): Use personality-based ROE (cautious)
- Tactical orders (Bombard/Invade): Use aggressive ROE (6-10)
- Rationale: Deliberate attacks should be aggressive, defense should be cautious

**Option 2: Override ROE for Explicit Attack Orders**
- When AI generates Bombard/Invade order, set ROE=10 (engage regardless)
- Rationale: If AI decided to attack, don't let ROE block it

**Option 3: Adjust ROE Calculation**
- Increase base ROE: `int(p.aggression * 10.0) + 3`
- Would give: Turtle=3, Economic=6, Balanced=7, Aggressive=12 (clamped to 10)
- Rationale: More aggressive baseline for all personalities

**Option 4: Make Attack Orders Independent of Standing Orders**
- Tactical fleet orders should NOT inherit standing order ROE
- Each order type sets appropriate ROE for its mission
- Rationale: Mission determines engagement rules, not fleet's default posture

### Recommended Fix

**Implement Option 4** - Mission-appropriate ROE:

**Rationale:** ROE is set **before combat** based on mission profile, not personality. Different missions require different retreat thresholds:

- **Probing attack:** ROE 2-4 (test defenses, gather intel, retreat quickly)
- **Main assault:** ROE 8-10 (commit to battle, fight through resistance)
- **Border patrol:** ROE 5-6 (defend territory but don't overcommit)
- **Last stand defense:** ROE 10 (defend valuable colony, fight to the death)
- **Raiding mission:** ROE 3-4 (hit and run, preserve fleet)

Currently FleetOrder has no ROE field, so missions inherit standing order ROE (defensive posture).

1. **Add ROE field to FleetOrder:**
   ```nim
   # src/engine/order_types.nim line 31
   FleetOrder* = object
     fleetId*: FleetId
     orderType*: FleetOrderType
     targetSystem*: Option[SystemId]
     targetFleet*: Option[FleetId]
     priority*: int
     roe*: Option[int]  # NEW: Mission-specific retreat threshold (overrides standing order)
   ```

2. **Set ROE when generating attack orders:**
   ```nim
   # src/ai/rba/domestikos/offensive_ops.nim
   FleetOrder(
     fleetId: attacker.fleetId,
     orderType: FleetOrderType.Bombard,
     targetSystem: some(target.systemId),
     priority: int(priority),
     roe: some(8)  # Main assault: fight through resistance
   )
   ```

3. **Engine respects order ROE over standing order ROE:**
   - Tactical order with ROE: use order's ROE
   - Tactical order without ROE: fall back to standing order ROE
   - No standing order: use default ROE (6 = engage equal/inferior)

---

## Architectural Insight: Time for GOAP

### Current RBA Architecture (Backwards)
```
1. Generate build requirements (ships, Marines, transports)
2. Build units over multiple turns
3. Look for idle fleets
4. IF idle fleets exist AND enemy colonies visible:
   - Generate attack order
```

**Problem:** Tactical system trying to do strategic planning.

### Proper Goal-Driven Architecture (GOAP)
```
1. Identify high-value target: "Capture system 15 (Corrino, 3 Marines, high value)"
2. Calculate requirements: Need 6 Marines + 2 transports + 4 combat ships
3. Generate subgoals:
   a. Build 6 Marines (3 turns)
   b. Build 2 TroopTransports (2 turns)
   c. Build 4 Destroyers (2 turns)
   d. Assemble at staging area (system 12)
   e. Move to target (1 turn)
   f. Execute invasion
4. Execute tactical steps (RBA handles movement, combat, logistics)
```

### Division of Responsibility

**GOAP (Strategic):**
- Target selection and prioritization
- Force requirement calculations
- Multi-turn campaign planning
- Resource allocation (build what we need)
- Coordinate multiple fleets for simultaneous arrival

**RBA (Tactical):**
- Fleet movement (pathfinding, fuel, avoiding enemies)
- Combat order selection (Bombard vs Invade vs Blitz)
- Logistics (loading/unloading Marines, repairs)
- Standing orders (patrol, defend, auto-repair)
- Emergency responses (retreat, regroup)

### Recommendation: Implement GOAP Now

**Why:**
1. RBA strategic planning is fundamentally flawed (reactive, not proactive)
2. Invasion problem IS a strategic planning problem
3. Engine mechanics work (Marines load, combat happens, prestige awards)
4. Only missing piece: coordinated multi-turn campaigns

**Path Forward:**
1. Keep today's quick fix (allows testing)
2. Wire GOAP for strategic goals ("capture colony X")
3. Let RBA handle tactical execution
4. Test integration with full combat cycle

---

## Test Data

**Simulation:** seed 99999, 20 turns, 4 houses

**Key Metrics:**
- Total space battles: 140
- Attack orders generated: ~20+ (from logs)
- Marines on transports: 5 (consistent)
- Orbital combats: 0
- Invasions: 0
- Colonies captured: 0

**Prestige Growth:**
- Turn 2: 3,752 total (+3,752 from start)
- Turn 10: 25,324 total (+1,836 that turn)
- Turn 21: 39,076 total (+1,744 that turn)
- Reduction: 60% from peak (+4,376 → +1,744)

---

## Files Modified

### Core Fixes
- `src/ai/rba/logistics.nim` - Disabled Marine auto-unload
- `src/ai/rba/domestikos/offensive_ops.nim` - Loaded Marine validation, fleet utilization
- `config/prestige.toml` - Reduced colonization/tech prestige

### Analysis Scripts (New)
- `scripts/analysis/check_marine_loading.py` - Diagnose Marine loading patterns
- `scripts/analysis/diagnose_transport_spam.py` - Analyze TroopTransport spam

---

## Next Steps

1. **CRITICAL:** Fix ROE for attack orders
   - Add `roe: Option[int]` field to FleetOrder type
   - Set ROE=8 for Bombard/Invade/Blitz orders in `offensive_ops.nim`
   - Verify engine respects tactical order ROE over standing order ROE

2. **Test:** Get ONE invasion working end-to-end
   - Confirm orbital combat triggers
   - Confirm bombardment executes
   - Confirm invasion with Marines works
   - Confirm colony ownership changes

3. **Medium-term:** Plan GOAP integration
   - Review existing GOAP infrastructure (`src/ai/sweep/`)
   - Design GOAP ↔ RBA interface
   - Implement "capture colony" goal
   - Test hybrid system

4. **Long-term:** Full GOAP strategic layer
   - Multi-colony campaigns
   - Economic expansion plans
   - Tech race strategies
   - Diplomatic maneuvering

---

## Commit

```bash
git commit 4dc1195
"fix: Enable invasions and reduce prestige inflation"
```

**Status:** Partial fix, investigation needed for order execution.
