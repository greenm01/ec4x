# Spy Scout Fleet Mechanics

## Overview

Spy scout fleets are specialized reconnaissance units that conduct covert intelligence operations. From the player's perspective, spy scouts operate transparently as special fleets with limited order support. Internally, scouts deployed on spy missions (Orders 09/10/11) are tracked as SpyScout objects to separate them from normal fleet operations.

This document describes the implementation mechanics for spy scout fleet management, including deployment, merging, and order support.

## Architecture Decision

**Key Design:** Spy scouts are tracked as separate SpyScout objects, not as normal Fleet objects.

**Why this is pragmatic:**
1. **Clear separation of concerns** - Spy scouts are "consumed resources" that leave the fleet pool
2. **Simpler state management** - Spy scouts don't clutter the main fleet list
3. **No special cases in fleet operations** - Fleet operations don't need to filter out spy missions
4. **Cleaner detection/intelligence code** - Detection checks `GameState.spyScouts` specifically
5. **Explicit lifecycle** - SpyScout: commission → travel → mission → done (or rejoin fleet)

## Spy Scout Deployment (Orders 09/10/11)

### Order 09: Spy on Planet
### Order 10: Hack Starbase
### Order 11: Spy on System

**Requirements:**
- Fleet must contain **only scout squadrons** (no combat ships or spacelift)
- One or more scout squadrons allowed (multi-scout fleets supported)

**Execution Process:**

1. **Validation** (`orders.nim:256-278`):
   - Check fleet has at least one squadron
   - Verify all squadrons are scouts (no battleships, carriers, etc.)
   - Verify no spacelift ships attached
   - Reject order if validation fails

2. **Scout Extraction** (`executor.nim:681-724, 795-836, 893-934`):
   - Count total scouts in fleet
   - Take ELI level from first scout
   - Calculate jump lane path to target system
   - Create SpyScout object with:
     - `mergedScoutCount = totalScouts` (for mesh network bonus)
     - `eliLevel` from first scout
     - `state = Traveling`
     - `travelPath` via jump lanes
   - Remove **ALL** squadrons from fleet: `updatedFleet.squadrons = @[]`
   - Delete empty fleet automatically

3. **SpyScout Object**:
   ```nim
   SpyScout(
     id: "spy-{owner}-{turn}-{target}",
     owner: HouseId,
     location: SystemId,              # Current location (starts at deployment)
     eliLevel: int,                   # Tech level from scouts
     mission: SpyMissionType,         # SpyOnPlanet, HackStarbase, SpyOnSystem
     commissionedTurn: int,
     detected: bool,
     state: SpyScoutState,            # Traveling, OnMission, Returning, Detected
     targetSystem: SystemId,
     travelPath: seq[SystemId],       # Jump lane route
     currentPathIndex: int,           # Progress along path
     mergedScoutCount: int            # Number of scouts (mesh network bonus)
   )
   ```

**Result:**
- Original fleet deleted (all scouts consumed)
- SpyScout object created and stored in `GameState.spyScouts`
- SpyScout travels to target system via jump lanes
- Detection checks occur at each intermediate system during travel

## Mesh Network Bonuses

Multiple scouts working together gain enhanced ELI (Electronic Intelligence) bonuses:

| Scout Count | ELI Bonus |
|-------------|-----------|
| 1           | +0        |
| 2-3         | +1        |
| 4-5         | +2        |
| 6+          | +3 (max)  |

**Implementation:**
- `mergedScoutCount` field tracks total scouts in SpyScout object
- Bonus calculated during detection checks and intelligence gathering
- Persists through merging operations (counts accumulate)

**Example:**
- Deploy 3 scout squadrons on Order 09 → `mergedScoutCount = 3` → +1 ELI bonus
- Later merge with 2 more spy scouts → `mergedScoutCount = 5` → +2 ELI bonus

## Spy Scout Order Support

Spy scouts use a parallel order system (`SpyScoutOrder`) that mirrors fleet orders.

**Allowed Orders:**
- **01 (Hold)**: Stay at current location
- **02 (Move)**: Travel to new target system (recalculates path)
- **09/10/11 (Spy Missions)**: Change mission type or target
- **13 (Join Fleet)**: Merge with normal fleet (converts to squadrons)
- **14 (Rendezvous)**: Merge with other spy scouts or fleets at location
- **15 (Salvage)**: Salvage operations
- **16/17 (Reserve/Mothball)**: Place on reserve or mothball
- **19 (View World)**: View world information

**Disallowed Orders:**
- Patrol, Guard, Blockade, Bombard, Invade, Blitz, Colonize, etc.
- These require combat capability or spacelift that spy scouts lack

**Order Validation:**
- When player submits order using fleet ID
- `validateFleetOrder` checks if ID is in `state.spyScouts` (`orders.nim:179-181`)
- Routes to `validateSpyScoutOrder` helper (`orders.nim:140-168`)
- Returns error if order type not in allowed set

**Order Execution:**
- Spy scout orders resolved during Command Phase
- `resolveSpyScoutOrders` processes all pending orders (`spy_scout_orders.nim:145-186`)
- Order execution returns `bool` success status

## Merging Spy Scouts

Players control spy scout merging via **explicit orders** (not automatic).

### Spy Scout → Spy Scout (SpyScoutOrder.JoinSpyScout)

**File:** `spy_scout_orders.nim:61-110`

**Process:**
1. Validate both spy scouts exist
2. Check same owner and same location
3. Add source's `mergedScoutCount` to target
4. Delete source SpyScout object and orders
5. Calculate new mesh network bonus

**Example:**
```
SpyScout-A (mergedScoutCount=2) + SpyScout-B (mergedScoutCount=3)
→ SpyScout-B (mergedScoutCount=5, +2 ELI bonus)
→ SpyScout-A deleted
```

### Spy Scout → Normal Fleet (SpyScoutOrder.JoinFleet)

**File:** `spy_scout_orders.nim:14-59`

**Process:**
1. Find target fleet
2. Check same owner and same location
3. Convert SpyScout to squadrons:
   - Create scout ships with `eliLevel` matching spy scout
   - Add `mergedScoutCount` squadrons to fleet
4. Delete SpyScout object and orders

**Example:**
```
SpyScout (mergedScoutCount=3, eliLevel=5) → Fleet-Alpha
→ Fleet-Alpha gains 3 scout squadrons (Tech Level 5)
→ SpyScout deleted
```

### Normal Fleet → Spy Scout (Order 13: Join Fleet)

**File:** `executor.nim:1032-1076`

**Process:**
1. Player issues Order 13 targeting spy scout ID
2. Check if target ID is in `state.spyScouts`
3. Check same owner and same location
4. Convert SpyScout to squadrons (as above)
5. Add squadrons to **source fleet** (not target)
6. Delete SpyScout object and orders
7. Source fleet absorbs the scouts

**Example:**
```
Fleet-Bravo (2 battleships) → Order 13 targeting SpyScout-X
→ SpyScout-X converts to 4 scout squadrons
→ Fleet-Bravo now has 2 battleships + 4 scouts
→ SpyScout-X deleted
```

**Key Difference from Normal Merging:**
- Normal fleet-to-fleet: source absorbed into target, source deleted
- Fleet-to-SpyScout: SpyScout absorbed into fleet, SpyScout deleted

### Rendezvous with Spy Scouts (Order 14)

**File:** `executor.nim:1174-1257`

**Process:**
1. Collect all fleets with Rendezvous orders at target system
2. **NEW:** Collect all spy scouts with Rendezvous orders at target system
3. Determine host fleet (lowest ID among normal fleets)
4. Merge all fleets into host (standard rendezvous)
5. Convert all spy scouts to squadrons
6. Add all scout squadrons to host fleet
7. Delete all SpyScout objects and orders

**Example:**
```
Rendezvous at System-X:
- Fleet-A (2 cruisers)
- Fleet-B (1 carrier)
- SpyScout-1 (3 scouts)
- SpyScout-2 (2 scouts)

→ Host = Fleet-A (lowest ID)
→ Fleet-A gains: 1 carrier, 5 scout squadrons
→ Fleet-B deleted, SpyScout-1 deleted, SpyScout-2 deleted
```

## Player Experience

From the player's perspective, spy scouts are **transparent**:

1. **Deploy Scouts:** Build scouts at stardocks, form scout-only fleets
2. **Issue Spy Orders:** Order 09/10/11 on scout fleet → scouts deploy on mission
3. **Manage Spy Fleets:** Spy scouts appear as special fleets in fleet list
4. **Give Orders:** Issue supported orders (01, 02, 09/10/11, 13/14, etc.)
5. **Merge Freely:** Join spy scouts together, or merge with normal fleets
6. **No Recovery:** Scouts on spy missions are permanently consumed (cannot return)

**UI Considerations:**
- Spy scouts should display with special icon/color in fleet list
- Show mission type and target system
- Display `mergedScoutCount` and mesh network bonus
- Warn when issuing unsupported orders
- Show "spy scout fleet" in tooltips/descriptions

## Implementation Files

### Modified Files:

**`src/engine/orders.nim`**
- Lines 256-278: Relaxed validation for Orders 09/10/11 (scout-only fleets)
- Lines 140-168: Added `validateSpyScoutOrder` helper
- Lines 179-181: Route SpyScout IDs to validation helper

**`src/engine/commands/executor.nim`**
- Lines 681-724: Order 09 (Spy on Planet) - multi-scout support
- Lines 795-836: Order 10 (Hack Starbase) - multi-scout support
- Lines 893-934: Order 11 (Spy on System) - multi-scout support
- Lines 1032-1076: Order 13 (Join Fleet) - handle SpyScout targets
- Lines 1174-1257: Order 14 (Rendezvous) - collect and merge spy scouts

**`src/engine/intelligence/spy_resolution.nim`**
- Lines 263-265: Removed automatic spy scout merging (player-controlled now)

### Already Implemented:

**`src/engine/commands/spy_scout_orders.nim`**
- SpyScout order execution system (JoinFleet, JoinSpyScout, Move, etc.)

**`src/engine/gamestate.nim`**
- `SpyScoutOrderType`, `SpyScoutOrder` types
- `GameState.spyScoutOrders` table

**`src/engine/resolve.nim`**
- Command Phase calls `resolveSpyScoutOrders(state)`

## Example Scenarios

### Scenario 1: Deploy Multiple Scouts on Mission

**Turn 1:**
- Player has fleet with 3 scout squadrons at System-A
- Issue Order 09 (Spy on Planet) targeting System-D

**Validation:**
- ✅ Scout-only fleet (no combat/spacelift)
- ✅ Path exists: A → B → C → D (3 jumps)

**Execution:**
- All 3 scouts → SpyScout object (`mergedScoutCount=3`)
- Fleet deleted (empty)
- SpyScout travels with +1 ELI mesh bonus

**Turn 2:**
- SpyScout at System-B (1 jump traveled)
- Detection check (ELI 5 + 1 mesh bonus = 6)

**Turn 3:**
- SpyScout at System-C (2 jumps traveled)
- Detection check

**Turn 4:**
- SpyScout at System-D (arrived at target)
- Begin planet surveillance mission

### Scenario 2: Merge Spy Scouts for Bonus

**Turn 5:**
- Player has SpyScout-A at System-X (`mergedScoutCount=2`, +1 ELI)
- Player has SpyScout-B at System-X (`mergedScoutCount=2`, +1 ELI)
- Issue SpyScoutOrder: JoinSpyScout (A → B)

**Execution:**
- SpyScout-B: `mergedScoutCount = 2 + 2 = 4` → +2 ELI bonus
- SpyScout-A: deleted

**Result:**
- Single spy scout with 4 scouts (stronger detection capability)

### Scenario 3: Rejoin Normal Fleet

**Turn 8:**
- SpyScout mission complete at System-Y
- Fleet-Delta at System-Y (1 carrier, 2 destroyers)
- Issue SpyScoutOrder: JoinFleet (SpyScout → Fleet-Delta)

**Execution:**
- SpyScout converts to 4 scout squadrons (Tech Level 5)
- Fleet-Delta gains 4 scout squadrons
- SpyScout deleted

**Result:**
- Fleet-Delta: 1 carrier, 2 destroyers, 4 scouts
- Scouts rejoin normal operations

### Scenario 4: Fleet Absorbs Spy Scout

**Turn 10:**
- Fleet-Echo at System-Z (3 battleships)
- SpyScout-C at System-Z (`mergedScoutCount=3`)
- Issue Order 13 (Join Fleet) from Fleet-Echo targeting SpyScout-C

**Execution:**
- SpyScout-C converts to 3 scout squadrons
- Fleet-Echo gains 3 scout squadrons
- SpyScout-C deleted

**Result:**
- Fleet-Echo: 3 battleships, 3 scouts (mixed fleet)
- Can split scouts later if needed for another mission

## Detection and Intelligence

Spy scout detection mechanics are covered in detail in [intelligence.md](../specs/intelligence.md) and [assets.md Section 2.4.2](../specs/assets.md#242-scouts).

**Key Points:**
- Detection rolls at each intermediate system during travel
- Mesh network bonuses improve stealth
- Allied forces share intel but don't engage
- Hostile detection destroys spy scout and triggers diplomatic escalation
- Spy-vs-spy encounters follow counter-intelligence rules

## Future Considerations

**Potential Enhancements:**
1. **Return Home:** CancelMission order to return scouts to friendly colony (partially implemented)
2. **Mission Reassignment:** Change mission type while en route
3. **Emergency Extraction:** Recall spy scouts under threat
4. **Deep Cover:** Long-term embedded operatives vs. short-term recon

**Not Implemented:**
- Automatic merging (removed - player control preferred)
- Mixed fleet spy deployment (rejected - requires scout-only fleets)
- Scout recovery after mission (scouts permanently consumed)
