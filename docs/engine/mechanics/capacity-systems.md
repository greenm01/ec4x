# Capacity Systems

**Purpose:** Capacity limits, enforcement mechanisms, and overflow handling  
**Last Updated:** 2026-01-09

---

## Overview

EC4X uses multiple capacity systems to limit force composition and prevent unchecked scaling:

1. **Construction Dock Capacity** - Limits simultaneous ship building/repairs
2. **Carrier Hangar Capacity** - Limits fighters embarked on carriers
3. **Colony Fighter Capacity** - Limits fighters stationed at colonies (documented in economy.md)
4. **Squadron Capacity** - Limits total military forces per house (documented in reference.md)

This document focuses on physical capacity limits (docks and hangars).

---

## 1. Construction Dock Capacity

### Overview

Physical docks limit simultaneous construction/repair operations at orbital facilities.

### Facility Types & Capacity

| Facility | Capacity | Function | Queue Type |
|----------|----------|----------|------------|
| Spaceport | 5 docks | Construction only | constructionQueue |
| Shipyard | 10 docks | Construction only | constructionQueue |
| Drydock | 5 docks | Repairs only | repairQueue |

### Enforcement Model

**Hard Physical Limit:**
- Each queue entry occupies 1 dock
- When `queue.len = capacity`, facility at maximum
- New orders rejected if no capacity
- No grace period (immediate rejection)

### Dock Occupancy

**Construction:**
- Dock occupied from submission to commissioning
- Duration: 1+ turns (submit Turn N → commission Turn N+1 Command Phase)
- Freed when ship commissioned in Command Phase

**Repairs:**
- Dock occupied from submission to completion
- Duration: 1+ turns (1 if funded, multiple if stalled)
- Freed when repair completes AND pays in Production Phase

**Key:** Stalled repairs occupy docks indefinitely (until funded or facility destroyed)

### Capacity Checking

**Submission (Command Phase C):** Primary enforcement point  
**Production Phase:** Verification only (violations should never occur)

---

## 2. Carrier Hangar Capacity

### What This Tracks

**Fighter Squadrons Embarked on Carriers** - Fighters loaded onto Carrier (CV) and Super Carrier (CX) ships:
- Carriers (CV) - Medium carriers with fighter complement
- Super Carriers (CX) - Large carriers with extended hangar capacity

### Capacity Limits

**Based on ACO (Advanced Carrier Operations) tech level:**

| ACO Level | CV Capacity | CX Capacity |
|-----------|------------|------------|
| ACO I     | 3 FS       | 5 FS       |
| ACO II    | 4 FS       | 6 FS       |
| ACO III   | 5 FS       | 8 FS       |

### Enforcement Model

**Hard Physical Limit** - Cannot load beyond capacity:
- **Blocking at load time** - Fighter loading orders rejected if carrier at capacity
- **No grace period** - Physical space constraint (like construction docks)
- **Per-carrier tracking** - Each carrier independently tracks its hangar load
- **House-wide tech** - All carriers upgrade capacity immediately when ACO researched

**Exception:** If carrier already overloaded due to ACO tech downgrade, existing fighters remain (grandfathered) but no new loading allowed until under capacity.

### Ownership Transfer

**When fighters embark on carriers:**
- Ownership transfers from colony to carrier
- DO NOT count against colony fighter capacity
- Carrier provides all logistics (no infrastructure requirements)
- Can transit through any system without capacity impact

**When fighters disembark:**
- Ownership transfers back to colony
- Count against colony fighter capacity (must have space available)
- If colony at capacity, disembarkation blocked

### Loading Mechanics

**Auto-Loading at Commissioning:**
- When fighters commissioned at colony with docked carriers
- Automatically load to available carrier hangar space
- Prioritizes Super Carriers (CX) first (larger capacity)
- Then Carriers (CV)
- Respects hangar capacity limits

**Manual Loading:**
- Player orders fighters to load onto specific carrier
- Carrier must be at colony with fighters
- Validates available hangar space before loading
- Rejected if carrier at capacity

### Capacity Check Timing

**Production Phase:**
- Check all carriers for hangar capacity violations
- **Violations should NEVER occur** (blocked at load time)
- If found, logged as warnings for debugging

**Load Time:**
- Primary enforcement point
- Validates hangar space available
- Rejects loading if over capacity

### Strategic Implications

**Carrier Types:**
- Super Carriers (CX) have 60-67% more capacity than Carriers (CV)
- Players should prioritize building CX for fighter operations
- CV useful for smaller fighter complements or distributed operations

**ACO Tech Research:**
- Immediately upgrades ALL carrier capacities house-wide
- No ship refits required
- Strategic timing: research before major fighter production

**Tech Downgrade Risk:**
- Rare but possible if house loses ACO tech
- Already-embarked fighters remain (no forced disembarkment)
- Prevents new loading until under new capacity limit

### Integration with Other Systems

**Colony Fighter Capacity:**
- Embarked fighters DON'T count against colony capacity
- Frees up colony infrastructure for additional fighters
- Strategic: load fighters to carriers to expand total fighter force

**Fighter Squadron Capacity:**
- Colony limits: Based on IU/PU/FD tech (with 2-turn grace period)
- Carrier limits: Based on ACO tech (hard blocking)
- Players can "overflow" colony capacity by loading to carriers

**Combat:**
- Embarked fighters participate in carrier-based combat
- If carrier destroyed/crippled, embarked fighters lost
- If carrier survives, fighters can be used in subsequent battles

### Code Modules

**Module:** `src/engine/economy/capacity/carrier_hangar.nim`
- `isCarrier(shipClass)` - Check if ship is a carrier (CV/CX)
- `getCarrierMaxCapacity(shipClass, acoLevel)` - Calculate max hangar capacity
- `getCurrentHangarLoad(squadron)` - Count embarked fighters
- `analyzeCarrierCapacity(state, fleetId, squadronIdx)` - Check single carrier
- `checkViolations(state)` - Check all carriers for violations
- `canLoadFighters(state, fleetId, squadronIdx, fightersToLoad)` - Validate loading
- `getAvailableHangarSpace(state, fleetId, squadronIdx)` - Get remaining capacity
- `findCarrierBySquadronId(state, squadronId)` - Locate carrier by ID
- `processCapacityEnforcement(state)` - Production phase check (debugging only)

**Integration Module:** `src/engine/economy/engine.nim`
- `resolveProductionPhaseWithState()` - Calls carrier hangar capacity check

**Loading logic:** (TBD)
- Fighter loading orders will call `canLoadFighters()` before executing

### Common Issues & Solutions

**"Cannot load fighters to carrier"**

**Cause:** Carrier at hangar capacity

**Solutions:**
1. Wait for carrier to disembark fighters at colony
2. Use different carrier with available hangar space
3. Research ACO tech to increase carrier capacities
4. Build additional carriers (CX preferred for capacity)

**"Fighters won't disembark from carrier"**

**Cause:** Colony at fighter capacity (no space to receive)

**Solutions:**
1. Disband excess fighter squadrons at colony
2. Wait for fighter grace period to expire (if in violation)
3. Build more Industrial Units (IU) to increase colony fighter capacity
4. Transfer fighters to different colony with available capacity

**"Carrier shows violation in maintenance log"**

**Cause:** BUG - carriers should never exceed capacity (blocked at load time)

**Solutions:**
1. Report the bug with details (how carrier got overloaded)
2. Carrier will function normally but cannot load new fighters
3. Disembark fighters to get under capacity limit

---

## 3. Future Capacity Systems (Placeholder)

**Future sections:**
- Colony fighter capacity (IU-based limits)
- Total squadron capacity (IU-based limits, 2-turn grace period)
- Capital squadron capacity (IU-based limits, no grace period)
- Planet-breaker capacity (1 per owned colony)

---

## References

- **Construction:** `docs/engine/architecture/construction-repair-commissioning.md`
- **Colony Management:** `docs/engine/mechanics/colony-management.md`
- **Economy:** `docs/specs/economy.md` Section 4.13 (ACO tech)
- **Assets:** `docs/specs/assets.md` Section 2.4.1 (Carrier mechanics)
- **Reference:** `docs/specs/reference.md` Table 10.5 (Capacity limits)
- **Configuration:** ACO tech progression in `src/common/types/tech.nim`

---
