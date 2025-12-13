# Scout Espionage System Mechanics

**Purpose:** Complete specification for Scout-based espionage operations
**Last Updated:** 2025-12-13
**Status:** Implementation Complete (Fleet-Based Scout Missions)

---

## Overview

Scouts are specialized auxiliary ships that operate in **Scout-only fleets** for intelligence gathering. The system uses a fleet-based architecture where scouts travel to targets, establish persistent missions, and face detection checks each turn until destroyed or recalled.

**Key Architectural Principle:** No separate SpyScout entities. All spy missions operate through the Fleet system with mission state tracking.

---

## Scout Mission Lifecycle

### Phase 1: Order Submission (Command Phase)

Player issues spy order on Scout-only fleet:
- **Order Types**: SpyOnPlanet, SpyOnSystem, HackStarbase
- **Validation**: Fleet must contain only Scout ships
- **State Change**: Fleet.missionState = Traveling
- **Result**: Movement order created to target system

```nim
# In executor.nim (executeSpyPlanetOrder, etc.)
fleet.missionState = FleetMissionState.Traveling
fleet.missionType = some(ord(SpyMissionType.SpyOnPlanet))
fleet.missionTarget = some(targetSystem)

# Create movement order
FleetOrder(
  fleetId: fleet.id,
  orderType: FleetOrderType.MoveToSystem,
  targetSystem: some(targetSystem)
)
```

**Special Case**: If fleet already at target, mission starts immediately (skip to Phase 3).

### Phase 2: Travel to Target (Maintenance Phase)

Scout fleet travels to target using normal fleet movement system:
- **Visibility**: Scout fleets are invisible to combat fleets (one-way)
- **Scout-on-Scout**: Rival scout fleets MAY detect each other (ELI roll)
- **Cancelable**: Player can issue new orders, cancel mission en route
- **Duration**: Variable based on distance (1-2 jumps per turn)

**Movement Resolution** (fleet_orders.nim):
```nim
proc resolveMovementOrder(fleet, order, state):
  # Normal fleet movement logic
  # When fleet arrives at destination:
  if fleet.location == order.targetSystem.get():
    # Check if spy mission
    if fleet.missionState == FleetMissionState.Traveling:
      # Transition to active mission (Phase 3)
```

### Phase 3: Mission Start (Maintenance Phase - Arrival)

When scout fleet arrives at target system:
- **State Change**: Fleet.missionState = OnSpyMission
- **Fleet Locked**: Cannot accept new orders while on mission
- **Scouts "Consumed"**: Fleet dedicated to mission, cannot be recalled
- **Registration**: Added to GameState.activeSpyMissions table

```nim
# In fleet_orders.nim (resolveMovementOrder)
fleet.missionState = FleetMissionState.OnSpyMission
fleet.missionStartTurn = state.turn

state.activeSpyMissions[fleet.id] = ActiveSpyMission(
  fleetId: fleet.id,
  missionType: SpyMissionType.SpyOnPlanet,
  targetSystem: fleet.location,
  scoutCount: fleet.squadrons.len,
  startTurn: state.turn,
  ownerHouse: fleet.owner
)
```

**Game Event**: SpyMissionStarted (visible to mission owner)

### Phase 4: Persistent Detection Checks (Conflict Phase - Each Turn)

**Every turn** while mission is active, detection check runs in Conflict Phase Step 6a.5:

```nim
# In conflict_phase.nim (Step 6a.5)
for fleetId, mission in state.activeSpyMissions.pairs:
  let detectionResult = resolveSpyScoutDetection(
    state,
    mission.scoutCount,
    defender,
    targetSystem,
    rng
  )

  if detectionResult.detected:
    # DETECTED: Immediate destruction
    fleet.missionState = FleetMissionState.Detected
    state.fleets.del(fleetId)
    state.activeSpyMissions.del(fleetId)
    # Generate ScoutDetected event
    # Diplomatic escalation
  else:
    # UNDETECTED: Generate intelligence
    generateSpyIntelligence(state, fleet, mission)
```

**Detection Formula**:
```
Target = 15 - scoutCount + (defenderELI + starbaseBonus)
Roll = 1d20
Detected = (Roll >= Target)
```

**Detection Outcome**:
- **DETECTED** (roll >= target):
  - All scouts immediately destroyed
  - Fleet deleted from game
  - Mission fails, no intel gathered
  - Diplomatic stance escalates to Hostile
  - Game event: ScoutDetected (visible to both houses)

- **UNDETECTED** (roll < target):
  - Generate Perfect quality intelligence report
  - Mission continues next turn
  - Repeat detection check next turn

### Phase 5: Intelligence Generation (Conflict Phase - If Undetected)

When scouts remain undetected, generate Perfect quality intel:

**SpyOnPlanet**:
- Complete colony statistics (PU, IU, economic output)
- All facilities (Spaceport, Shipyard, Drydock counts)
- Defensive installations (Starbases, Ground Batteries, Shields)
- Construction queues with turn counts
- Fighter squadron counts

**SpyOnSystem**:
- All fleets in system with full composition
- Squadron breakdowns with tech levels
- Fleet orders and standing orders
- System owner and control status

**HackStarbase**:
- All SpyOnPlanet intelligence
- Starbase tech level and hull integrity
- Starbase sensor coverage and detection bonuses
- Connected systems (surveillance range)

**Quality Level**: Perfect (100% accurate, current as of this turn)

---

## Mission Duration and Termination

### Natural Termination

Missions persist indefinitely until:
1. **Detected**: Scouts destroyed, mission ends immediately
2. **Colony Captured**: Target colony changes ownership, mission invalid
3. **Colony Destroyed**: Target destroyed, mission ends

### Manual Termination

**NOT SUPPORTED**: Players cannot recall scouts on active missions. Once scouts arrive and mission starts (OnSpyMission state), they are committed until detected or target lost.

**Rationale**: "Consumed" means scouts are operating deep in enemy territory, maintaining covert observation posts. No safe recall mechanism.

### Mission State Machine

```
None (normal fleet)
  ↓ [Issue spy order]
Traveling (en route to target)
  ↓ [Arrive at target]
OnSpyMission (active, persistent detection checks)
  ↓ [Detected]
Detected (destroyed next phase)
  ↓ [Fleet deletion]
(Removed from game)
```

---

## Detection Mechanics

### Detection Formula (Per Spec 02-assets.md:2.4.2)

```
Target Number = 15 - (Number of Scouts) + (Defender ELI + Starbase Bonus)
Roll = 1d20
Detected if Roll >= Target
```

**Components**:
- **Base Target**: 15
- **Scout Count Modifier**: -1 per scout (more scouts = harder to detect)
- **Defender ELI**: +1 per ELI tech level (0-10)
- **Starbase Bonus**: +2 if starbase present (powerful sensor arrays)

### Strategic Implications

**Mesh Bonus** (6+ scouts):
- 6 scouts: Target = 15 - 6 + ELI + SB = 9 + ELI + SB
- At ELI 3 + Starbase (+2): Target = 14 (need 14+ on d20 = 35% detection)
- Without starbase: Target = 12 (45% detection)

**Small Mission** (1-2 scouts):
- 1 scout: Target = 15 - 1 + ELI + SB = 14 + ELI + SB
- At ELI 3 + Starbase: Target = 19 (need 19+ on d20 = 10% detection)
- Very risky, but only 1 scout lost if detected

**Detection Per Turn**:
- Cumulative risk over multiple turns
- 3-turn mission at 35% detection/turn = 72% chance detected over 3 turns
- Long missions almost guaranteed to fail against prepared defenses

### Diplomatic Escalation

When scouts detected:
```nim
# In diplomatic_resolution.nim
proc escalateDiplomaticStance(state, defender, attacker):
  if currentStance < DiplomaticStance.Hostile:
    # Escalate to Hostile
    # Generate DiplomaticStateChanged event
    # Both houses notified
```

**Escalation Path**:
- Neutral → Hostile (detected espionage)
- Friendly → Neutral (detected espionage on ally)
- Does NOT auto-escalate to Enemy (war declaration)

---

## Scout-on-Scout Detection (Reconnaissance)

**IMPLEMENTED** (Maintenance Phase Step 1e)

When scout fleets from different houses are at same location:
- Each side makes separate ELI-based detection roll
- Detection formula: `1d20 vs (15 - observerScoutCount + targetELI)`
- **Asymmetric detection possible**:
  - Fleet A may detect Fleet B
  - Fleet B may not detect Fleet A
  - No combat even if detected (scouts never fight)

**Intelligence Quality**: Visual (not Perfect, only observable data)

---

## Data Structures

### Fleet Mission State

```nim
type
  FleetMissionState* {.pure.} = enum
    None,           # Normal fleet operation
    Traveling,      # En route to spy mission target
    OnSpyMission,   # Active spy mission (locked, gathering intel)
    Detected        # Detected during spy mission (destroyed next phase)

type
  Fleet* = object
    # ... existing fields ...
    missionState*: FleetMissionState
    missionType*: Option[int]             # SpyMissionType as int
    missionTarget*: Option[SystemId]
    missionStartTurn*: int
```

### Active Spy Mission Tracking

```nim
type
  ActiveSpyMission* = object
    fleetId*: FleetId
    missionType*: SpyMissionType
    targetSystem*: SystemId
    scoutCount*: int
    startTurn*: int
    ownerHouse*: HouseId

type
  GameState* = object
    # ... existing fields ...
    activeSpyMissions*: Table[FleetId, ActiveSpyMission]
```

### Detection Result

```nim
type
  DetectionResult* = object
    detected*: bool
    roll*: int
    target*: int
```

---

## Integration Points

### Command Phase (executor.nim)

- `executeSpyPlanetOrder()`: Set fleet mission state, create movement order
- `executeSpySystemOrder()`: Set fleet mission state, create movement order
- `executeHackStarbaseOrder()`: Set fleet mission state, create movement order

### Maintenance Phase (fleet_orders.nim)

- `resolveMovementOrder()`: Detect arrival, start mission, register in activeSpyMissions

### Conflict Phase (conflict_phase.nim)

- **Step 6a.5**: Iterate activeSpyMissions, run detection, generate intel or destroy scouts

### Intelligence System (spy_resolution.nim)

- `resolveSpyScoutDetection()`: Run detection check, return DetectionResult

---

## Testing Scenarios

### Scenario 1: Successful Multi-Turn Mission

1. Turn N: Issue SpyOnPlanet order (3 scouts, target 5 jumps away)
2. Turn N+2: Fleet arrives at target (missionState = OnSpyMission)
3. Turn N+2 Conflict: Detection check #1 (undetected, intel gathered)
4. Turn N+3 Conflict: Detection check #2 (undetected, intel gathered)
5. Turn N+4 Conflict: Detection check #3 (detected, scouts destroyed)

**Result**: 2 turns of Perfect quality intel before mission fails

### Scenario 2: Immediate Detection

1. Turn N: Issue SpyOnPlanet order (1 scout, already at target)
2. Turn N: Mission starts immediately (missionState = OnSpyMission)
3. Turn N Conflict: Detection check #1 (detected, scout destroyed)

**Result**: No intel gathered, scout lost

### Scenario 3: Mission Cancellation En Route

1. Turn N: Issue SpyOnPlanet order (2 scouts, target 4 jumps away)
2. Turn N+1: Fleet traveling (missionState = Traveling)
3. Turn N+1: Player issues new Move order (cancels spy mission)
4. Turn N+1 Maintenance: Fleet changes course, missionState = None

**Result**: Mission canceled, scouts preserved

### Scenario 4: Target Colony Captured During Mission

1. Turn N: 3 scouts on active mission (missionState = OnSpyMission)
2. Turn N Conflict: Enemy captures target colony
3. Turn N Conflict Step 6a.5: Mission invalidated (target.owner changed)
4. Result: Mission ends, scouts remain (no detection event)

**Handling**: Mission validation should check colony ownership, end mission gracefully if target lost.

---

## Performance Considerations

### Per-Turn Detection Checks

- **O(n)** where n = number of active spy missions
- Typical game: 4-8 active missions across all houses
- Negligible performance impact

### Intelligence Report Generation

- **Perfect quality**: Full colony/system snapshot
- Generated each turn if undetected
- Stored in house intelligence database (incremental updates)

---

## Future Enhancements (Not Yet Implemented)

### Scout-on-Scout Detection (Phase 8)

- ELI-based detection rolls between scout fleets
- Asymmetric detection possible
- Visual quality intel generated

### Scout Combat Exclusion (Phase 8)

- Scouts never participate in Space or Orbital Combat
- Scout fleets at a location do NOT trigger combat
- Enemy fleets cannot see or engage scout fleets

### Order Validation Updates (Phase 9)

- Prevent orders on OnSpyMission fleets (locked)
- Allow order changes on Traveling fleets (pre-mission)

---

## Comparison to Legacy System

### Old System (Removed)

- **SpyScout entities**: Separate from Fleet system
- **Proxy fleets**: Temporary fleets for movement
- **One-time detection**: Single check on arrival
- **Immediate consumption**: Scouts destroyed on mission start
- **SpyScoutOrder system**: Parallel to FleetOrder

### New System (Current)

- **Fleet-based missions**: Uses normal Fleet system
- **Normal movement**: Uses standard fleet movement
- **Persistent detection**: Check every turn until detected
- **Multi-turn intel**: Scouts gather intel over multiple turns
- **Unified orders**: SpyOrders are FleetOrders

### Benefits

- **Simpler architecture**: One fleet system, not two
- **Better gameplay**: Multi-turn missions create tension
- **More strategic**: Risk/reward trade-offs (more scouts = safer but costlier)
- **Cancelable travel**: Players can change minds en route

---

## References

- **Spec**: docs/specs/02-assets.md Section 2.4.2 (Spy Scouts)
- **Spec**: docs/specs/09-intelligence.md Section 9.1.1 (Spy Scout Missions)
- **Implementation**: src/engine/commands/executor.nim (spy order execution)
- **Implementation**: src/engine/resolution/phases/conflict_phase.nim (detection checks)
- **Implementation**: src/engine/intelligence/spy_resolution.nim (detection logic)
