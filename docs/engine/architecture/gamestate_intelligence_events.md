# GameState, Intelligence, and Events Architecture

**Status:** Canonical
**Last Updated:** 2025-12-11
**Related:** `fog_of_war.md`, `active_fleet_order_game_events.md`

## Executive Summary

EC4X uses a three-layer architecture for game information:
1. **Intelligence Database** (persistent state) - What each house knows
2. **Fog-of-War Filter** (query layer) - Creates per-house snapshots
3. **GameEvents** (temporal stream) - What happened this turn

This architecture enforces fog-of-war, prevents AI cheating, supports stale intel,
and enables reactive behavior.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Layer 1: Intelligence Database](#layer-1-intelligence-database)
3. [Layer 2: Fog-of-War Filter](#layer-2-fog-of-war-filter)
4. [Layer 3: GameEvents](#layer-3-gameevents)
5. [Data Flow](#data-flow)
6. [Design Rationale](#design-rationale)
7. [Implementation Guidelines](#implementation-guidelines)

---

## Architecture Overview

### Three-Layer System

```
┌──────────────────────────────────────────────────────────────────┐
│ LAYER 3: GameEvents (Temporal Stream)                            │
│ ═══════════════════════════════════════════════════════════════  │
│ TurnResult.events: seq[GameEvent]                                │
│                                                                  │
│ Purpose: Notifications - "What just happened THIS turn"          │
│ Lifetime: Per-turn (generated -> consumed -> discarded)          │
│ Filtered: By fog-of-war visibility rules                         │
│ Used by: AI reactive behavior, client reports                    │
└──────────────────────────────────────────────────────────────────┘
                            ↑ FILTERED BY ↑
┌──────────────────────────────────────────────────────────────────┐
│ LAYER 2: Fog-of-War Filter (Query Layer)                         │
│ ═══════════════════════════════════════════════════════════════  │
│ proc createFogOfWarView*(state, houseId): FilteredGameState      │
│                                                                  │
│ Purpose: Aggregation - "What can I see RIGHT NOW?"               │
│ Lifetime: Per-query (created on demand, ephemeral)               │
│ Combines: Current observations + historical intelligence         │
│ Used by: AI planning, strategic decisions                        │
└──────────────────────────────────────────────────────────────────┘
                            ↓ READS FROM ↓
┌──────────────────────────────────────────────────────────────────┐
│ LAYER 1: Intelligence Database (Persistent Storage)              │
│ ═══════════════════════════════════════════════════════════════  │
│ house.intelligence: IntelligenceDatabase                         │
│                                                                  │
│ Purpose: Storage - "What I know" (accumulated knowledge)         │
│ Lifetime: Persistent (survives across turns)                     │
│ Updated by: Espionage, scouting, combat observations             │
│ Used by: Fog-of-war queries, strategic analysis                  │
└──────────────────────────────────────────────────────────────────┘
```

### Comparison Table

| Aspect               | Intelligence DB     | Fog-of-War         | GameEvents             |
|----------------------|---------------------|--------------------|------------------------|
| **Purpose**          | Knowledge storage   | View aggregation   | Temporal notifications |
| **Lifetime**         | Persistent (turns)  | Ephemeral (query)  | Ephemeral (per-turn)   |
| **Scope**            | Per-house           | Per-house snapshot | All houses (filtered)  |
| **Operations**       | Write (store intel) | Read (query)       | Read (consume)         |
| **Data Type**        | Historical reports  | Aggregated view    | Event stream           |
| **Update Frequency** | On observation      | On demand          | Every turn             |
| **Memory**           | Tables/seqs         | Full state copy    | Event sequence         |
| **Used By**          | Fog-of-war          | AI planning        | AI reactive, reports   |

---

## Layer 1: Intelligence Database

### Purpose

**Persistent storage** of what each house has learned about the game world.
Enforces fog-of-war by limiting AI to accumulated knowledge.

### Data Structure

```nim
# Per-house database (src/engine/intelligence/types.nim)
IntelligenceDatabase* = object
  # Espionage reports
  colonyReports*: Table[SystemId, ColonyIntelReport]
  systemReports*: Table[SystemId, SystemIntelReport]
  starbaseReports*: Table[SystemId, StarbaseIntelReport]

  # Historical observations
  combatReports*: seq[CombatEncounterReport]
  scoutEncounters*: seq[ScoutEncounterReport]
  fleetMovementHistory*: Table[FleetId, FleetMovementHistory]
  constructionActivity*: Table[SystemId, ConstructionActivityReport]

  # Automated intelligence
  starbaseSurveillance*: seq[StarbaseSurveillanceReport]

  # Space Guild services (own transfers only)
  populationTransferStatus*: Table[string, PopulationTransferStatusReport]
```

### Key Characteristics

| Characteristic  | Description                                      |
|-----------------|--------------------------------------------------|
| **Per-House**   | Each house has separate intelligence database    |
| **Persistent**  | Stored in GameState, survives across turns       |
| **Cumulative**  | Updates/replaces old intel with new observations |
| **Query-able**  | AI asks "What do I know about System 42?"        |
| **Stale Intel** | Reports include `gatheredTurn` - intel ages      |
| **Fog-of-War**  | Limits AI to observable information only         |

### Storage Location

```nim
# src/engine/gamestate.nim
House* = object
  id*: HouseId
  name*: string
  prestige*: int
  treasury*: int
  # ... other fields ...
  intelligence*: IntelligenceDatabase  # ← Per-house knowledge base
```

### Example Intel Report

```nim
# Spy scout reports enemy colony
ColonyIntelReport = object
  colonyId: SystemId = "sys-42"
  targetOwner: HouseId = "house-harkonnen"
  gatheredTurn: int = 87                    # ← Intel age tracking
  quality: IntelQuality = Spy               # How gathered

  # Colony stats (observed)
  population: int = 150
  industry: int = 12                        # IU count
  defenses: int = 8                         # Ground forces
  starbaseLevel: int = 2                    # SB2
  constructionQueue: seq[string] = @["Carrier_EL3", "Starbase_SB3"]

  # Economic intelligence (Spy quality)
  grossOutput: Option[int] = some(45)       # GCO
  taxRevenue: Option[int] = some(38)        # NCV
```

### Update Operations

```nim
# Espionage operation completes (src/engine/resolution/simultaneous_espionage.nim)
proc processScoutIntelligence(...):
  let report = ColonyIntelReport(...)

  # CRITICAL: Get, modify, write back to persist
  var house = state.houses[houseId]
  house.intelligence.addColonyReport(report)  # ← Store intel
  state.houses[houseId] = house

# Fleet scouting (src/engine/resolution/fleet_orders.nim)
if systemIntelReport.isSome:
  state.withHouse(houseId):
    house.intelligence.addSystemReport(systemIntelReport.get())  # ← Store
```

---

## Layer 2: Fog-of-War Filter

### Purpose

**Query layer** that creates per-house snapshots by combining:
- Real-time observations (owned/occupied systems)
- Historical intelligence (scouted systems)

Prevents AI from accessing omniscient game state.

### Data Structure

```nim
# Per-house filtered view (src/engine/fog_of_war.nim)
FilteredGameState* = object
  viewingHouse*: HouseId
  turn*: int

  # Own assets (full detail)
  ownHouse*: House
  ownColonies*: seq[Colony]
  ownFleets*: seq[Fleet]
  ownFleetOrders*: Table[FleetId, FleetOrder]

  # Visible systems (combined current + historical)
  visibleSystems*: Table[SystemId, VisibleSystem]

  # Visible enemy assets (limited by intel)
  visibleColonies*: seq[VisibleColony]
  visibleFleets*: seq[VisibleFleet]

  # Public information (all houses see)
  housePrestige*: Table[HouseId, int]
  houseDiplomacy*: Table[(HouseId, HouseId), DiplomaticState]
  houseEliminated*: Table[HouseId, bool]

  # Star map (topology only)
  starMap*: StarMap
```

### Visibility Levels

```nim
VisibilityLevel* {.pure.} = enum
  None        # Never visited, no knowledge
  Adjacent    # One jump away from known system
  Scouted     # Previously visited, stale intel from intelligence DB
  Occupied    # Player fleet currently present
  Owned       # Player colony present
```

### Visibility Rules

| Level        | Can See                           | Source            |
|--------------|-----------------------------------|-------------------|
| **Owned**    | Full colony details, real-time    | Current GameState |
| **Occupied** | Full system details, enemy fleets | Current GameState |
| **Scouted**  | Stale intel, system topology      | Intelligence DB   |
| **Adjacent** | System existence, coordinates     | Star map          |
| **None**     | Nothing                           | N/A               |

### How It Reads Intelligence

```nim
# src/engine/fog_of_war.nim lines 132-139
proc getScoutedSystems(...): HashSet[SystemId] =
  let house = state.houses.getOrDefault(houseId)

  # Systems with colony intel
  for systemId, report in house.intelligence.colonyReports:  # ← READ
    if systemId notin ownedSystems and systemId notin occupiedSystems:
      result.incl(systemId)

  # Systems with fleet intel
  for systemId, report in house.intelligence.systemReports:  # ← READ
    if systemId notin ownedSystems and systemId notin occupiedSystems:
      result.incl(systemId)

# lines 287-290
if house.intelligence.colonyReports.hasKey(systemId):  # ← READ
  lastTurn = max(lastTurn, house.intelligence.colonyReports[systemId].gatheredTurn)
  # Shows intel age: "This report is 3 turns old"

# lines 340-343
let isVisible = systemId in ownedSystems or
                systemId in occupiedSystems or
                house.intelligence.colonyReports.hasKey(systemId)  # ← READ
```

### Usage Pattern

```nim
# AI planning phase (src/ai/analysis/run_simulation.nim)
for controller in controllers:
  # Apply fog-of-war filtering - AI only sees what it should
  let filteredView = createFogOfWarView(game, controller.houseId)

  # Generate orders using filtered view (no cheating!)
  let aiSubmission = ai.generateAIOrders(controller, filteredView, rng, @[])
```

### Memory Cost

⚠️ **Performance Note:** `FilteredGameState` is a **full copy** of visible game state.

```
Average game (4 players, turn 50):
- Full GameState: ~2-5 MB
- FilteredGameState per player: ~1-2 MB
- Total for 4 players: ~4-8 MB per turn

Acceptable for current scale, but could optimize with query API if needed.
```

---

## Layer 3: GameEvents

### Purpose

**Temporal event stream** providing notifications about what happened during turn
resolution. Enables reactive AI behavior and narrative report generation.

### Data Structure

```nim
# src/engine/resolution/types.nim
GameEventType* {.pure.} = enum
  # 107 event types across categories:
  General, OrderIssued, OrderCompleted, OrderRejected, ...
  CombatResult, SystemCaptured, ColonyCaptured, ...
  SpyMissionSucceeded, SabotageConducted, ...
  WarDeclared, PeaceSigned, DiplomaticRelationChanged, ...
  # Phase 7a: Combat narrative events (50+ types)
  CombatTheaterBegan, WeaponFired, ShipDestroyed, ...
  # Phase 7b: Fleet operations events (12 types)
  StandingOrderActivated, FleetMerged, SpyScoutDeployed, ...
  # Phase 7c: Construction/economic events
  ShipCommissioned, BuildingCompleted, TechAdvance, ...
  # Phase 7d: Diplomatic events (4 types)
  DiplomaticRelationChanged, TreatyProposed, TreatyBroken, ...

GameEvent* = ref object
  # Common fields
  turn*: int
  houseId*: Option[HouseId]
  systemId*: Option[SystemId]
  description*: string
  sourceHouseId*: Option[HouseId]
  targetHouseId*: Option[HouseId]
  # ... more common fields ...

  # Case-specific fields (discriminated union)
  case eventType*: GameEventType
  of CombatResult:
    attackingHouseId*: Option[HouseId]
    defendingHouseId*: Option[HouseId]
    totalAttackStrength*: Option[int]
    # ...
  of Diplomacy, WarDeclared, PeaceSigned:
    action*: Option[string]
    oldState*: Option[DiplomaticState]
    newState*: Option[DiplomaticState]
    changeReason*: Option[string]
  # ... 105+ more case branches
```

### Event Categories

| Category         | Count | Examples                                              | Purpose            |
|------------------|-------|-------------------------------------------------------|--------------------|
| **Combat**       | 50+   | WeaponFired, ShipDestroyed, BombardmentRoundCompleted | Tactical detail    |
| **Fleet Ops**    | 12    | StandingOrderActivated, FleetMerged                   | Fleet tracking     |
| **Construction** | 8     | ShipCommissioned, BuildingCompleted                   | Production updates |
| **Economic**     | 6     | PopulationTransfer, TerraformComplete                 | Economic events    |
| **Diplomatic**   | 6     | WarDeclared, DiplomaticRelationChanged                | Relations tracking |
| **Espionage**    | 15    | SpyMissionSucceeded, ScoutDetected                    | Intel ops          |
| **Orders**       | 5     | OrderIssued, OrderCompleted, OrderAborted             | Command tracking   |
| **Prestige**     | 2     | PrestigeGained, PrestigeLost                          | Victory progress   |

### Event Lifecycle

```
┌──────────────────────────────────────────────────────────────────┐
│ 1. Generation (During Turn Resolution)                           │
├──────────────────────────────────────────────────────────────────┤
│ Engine modules emit events:                                      │
│   - Combat resolution -> WeaponFired, ShipDestroyed              │
│   - Diplomatic actions -> WarDeclared, PeaceSigned               │
│   - Fleet operations -> FleetMerged, StandingOrderActivated      │
│                                                                  │
│ events.add(event_factory.weaponFired(...))                       │
└──────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ 2. Accumulation (TurnResult)                                    │
├─────────────────────────────────────────────────────────────────┤
│ TurnResult = object                                             │
│   newState: GameState                                           │
│   events: seq[GameEvent]  # <- All events from this turn        │
│   combatReports: seq[CombatReport]                              │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ 3. Fog-of-War Filtering (Per-House)                             │
├─────────────────────────────────────────────────────────────────┤
│ proc shouldHouseSeeEvent(state, houseId, event): bool           │
│                                                                 │
│ Visibility rules:                                               │
│ - Own events: Always visible                                    │
│ - Public events: Visible to all (war, peace, elimination)       │
│ - Combat events: Visible if present in system                   │
│ - Espionage events: Only attacker sees success                  │
│ - Detection events: Defender sees when they catch someone       │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ 4. Consumption                                                  │
├─────────────────────────────────────────────────────────────────┤
│ A) AI Reactive Behavior (Phase 7e - future):                    │
│    - Update threat assessments                                  │
│    - Trigger tactical responses                                 │
│    - Revise strategic priorities                                │
│                                                                 │
│ B) Client Reports (turn_report.nim):                            │
│    - Convert events -> human-readable narratives                │
│    - Priority sorting (Critical > Important > Info)             │
│    - Context-aware formatting                                   │
│                                                                 │
│ C) Diagnostics (diagnostics.nim):                               │
│    - Track colonization vs conquest                             │
│    - Monitor espionage activity                                 │
│    - Log event patterns                                         │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ 5. Discard (Events are ephemeral)                               │
├─────────────────────────────────────────────────────────────────┤
│ Events NOT stored in GameState after turn completes             │
│ Must be consumed during turn or lost                            │
└─────────────────────────────────────────────────────────────────┘
```

### Visibility Rules

```nim
# src/engine/intelligence/event_processor/visibility.nim
proc shouldHouseSeeEvent(state, houseId, event): bool =
  # Own events always visible
  if event.houseId.isSome and event.houseId.get == houseId:
    return true

  case event.eventType:
  # Public diplomatic events (visible to all)
  of WarDeclared, PeaceSigned, DiplomaticRelationChanged, HouseEliminated:
    return true

  # Combat events - visible if present in system
  of Battle, WeaponFired, ShipDestroyed, Bombardment:
    if event.systemId.isNone:
      return false
    return hasPresenceInSystem(state, houseId, event.systemId.get())

  # Espionage events - only attacker sees success
  of SpyMissionSucceeded, SabotageConducted:
    return false  # Filtered by houseId check above

  # Detection events - defender sees when they catch someone
  of SpyMissionDetected, ScoutDetected:
    if event.targetHouseId.isSome and event.targetHouseId.get() == houseId:
      return true  # Detector sees the detection
    return false

  # Economic/construction - private to house
  of ShipCommissioned, BuildingCompleted, TechAdvance:
    return false
```

### Example Event Flow

```nim
// Turn N: Combat occurs at System 42

// 1. Engine emits events
events.add(event_factory.weaponFired(
  attackingSquadron = "fleet-123-sqd-1",
  weaponType = "Laser_EL3",
  targetSquadron = "fleet-456-sqd-2",
  cerRoll = 14,
  cerModifier = +2,
  damage = 45
))

events.add(event_factory.shipDestroyed(
  squadron = "fleet-456-sqd-2",
  killedBy = "fleet-123-sqd-1",
  criticalHit = true
))

// 2. Fog-of-war filters per house
House Atreides: Has fleet at System 42 → Sees both events
House Harkonnen: Has colony at System 42 → Sees both events
House Corrino: No presence at System 42 → Sees nothing
House Ordos: No presence at System 42 → Sees nothing

// 3. AI reacts (Phase 7e - future)
if event.eventType == FleetDestroyed and event.systemId == myColony:
  urgentlyReinforceColony(event.systemId)

// 4. Client generates report
"⚠ Critical Alert: Your fleet at System 42 was destroyed!"
"  - Squadron fleet-456-sqd-2 destroyed by fleet-123-sqd-1 (critical hit)"
"  - Weapon: Laser_EL3 (CER: 14+2=16, Damage: 45)"
```

---

## Data Flow

### Complete Turn Cycle

```
┌─────────────────────────────────────────────────────────────────┐
│ Turn N-1: AI Planning Phase                                     │
├─────────────────────────────────────────────────────────────────┤
│ 1. AI queries fog-of-war:                                       │
│    let view = createFogOfWarView(state, houseId)                │
│                                                                 │
│ 2. Fog-of-war reads intelligence:                               │
│    - Current observations (owned/occupied systems)              │
│    - Historical intel (house.intelligence.colonyReports)        │
│    - Combines into FilteredGameState                            │
│                                                                 │
│ 3. AI makes decisions based on filtered view:                   │
│    - "System 42 has weak defenses (from 3-turn-old intel)"      │
│    - "Plan invasion using 5 carriers"                           │
│                                                                 │
│ 4. AI submits orders: OrderPacket                               │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Turn N: Resolution Phase                                        │
├─────────────────────────────────────────────────────────────────┤
│ 5. Engine resolves turn:                                        │
│    - Combat occurs                                              │
│    - Espionage operations execute                               │
│    - Diplomatic actions process                                 │
│    - Fleet orders execute                                       │
│                                                                 │
│ 6. Engine emits events:                                         │
│    events.add(event_factory.weaponFired(...))                   │
│    events.add(event_factory.orderIssued("SpyOnPlanet", ...))    │
│    events.add(event_factory.warDeclared(...))                   │
│                                                                 │
│ 7. Engine updates intelligence:                                 │
│    house.intelligence.addColonyReport(report)                   │
│    house.intelligence.addCombatReport(combat)                   │
│                                                                 │
│ 8. Return TurnResult:                                           │
│    TurnResult(newState, events, combatReports)                  │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Turn N: Event Processing Phase                                  │
├─────────────────────────────────────────────────────────────────┤
│ 9. Filter events per house (fog-of-war):                        │
│    let filteredEvents = events.filter(shouldHouseSeeEvent)      │
│                                                                 │
│ 10. AI reactive behavior (Phase 7e - future):                   │
│     for event in filteredEvents:                                │
│       if event.eventType == FleetDestroyed:                     │
│         updateThreatAssessment(+50)                             │
│                                                                 │
│ 11. Generate client reports:                                    │
│     let report = generateTurnReport(oldState, turnResult, house)│
│     # Converts events -> human narratives                       │
│                                                                 │
│ 12. Update diagnostics:                                         │
│     collectDiagnostics(state, houseId, events)                  │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Turn N+1: AI Planning Phase (Cycle Repeats)                     │
├─────────────────────────────────────────────────────────────────┤
│ 13. AI queries fog-of-war again:                                │
│     let view = createFogOfWarView(state, houseId)               │
│     # Now sees UPDATED intelligence from Turn N espionage       │
│                                                                 │
│ 14. Makes new decisions with fresh intel...                     │
└─────────────────────────────────────────────────────────────────┘
```

### Intelligence Update Flow

```
Espionage Operation (Turn N)
         ↓
Generate IntelReport (ColonyIntelReport, SystemIntelReport, etc.)
         ↓
Store in house.intelligence (WRITE)
         ↓
Persisted in GameState across turns
         ↓
AI Planning (Turn N+1)
         ↓
createFogOfWarView() reads house.intelligence (READ)
         ↓
AI sees updated intel in FilteredGameState
         ↓
AI makes decisions based on fresh intel
```

### Event Generation Flow

```
Combat Resolution (conflict_phase.nim)
         ↓
events.add(event_factory.weaponFired(...))  (WRITE)
         ↓
Accumulated in TurnResult.events
         ↓
Fog-of-war filters per house (READ)
         ↓
AI reactive behavior consumes filtered events (READ)
         ↓
Client report generation consumes filtered events (READ)
         ↓
Events discarded (not persisted)
```

---

## Design Rationale

### Why Three Layers?

#### Problem: How do we enforce fog-of-war while supporting both strategic planning and reactive behavior?

**Option 1: Single filtered state (no intelligence, no events)**
- ❌ Problem: How to track intel age?
- ❌ Problem: How to show "this report is 5 turns old"?
- ❌ Problem: No reactive behavior (AI can't react to turn events)

**Option 2: Intelligence only (no fog-of-war, no events)**
- ❌ Problem: How to query "what can I see now?"
- ❌ Problem: How to handle real-time observations vs stale intel?
- ❌ Problem: No temporal notifications

**Option 3: Events only (no intelligence, no fog-of-war)**
- ❌ Problem: How to persist knowledge across turns?
- ❌ Problem: How to query historical intel?
- ❌ Problem: Events are temporal, can't store persistent state

**✅ Chosen Solution: Three layers (intelligence + fog-of-war + events)**
- ✅ Intelligence stores persistent knowledge
- ✅ Fog-of-war aggregates current + historical
- ✅ Events provide temporal notifications
- ✅ Each layer has clear, distinct responsibility

### Why Not Merge Intelligence + Fog-of-War?

**Separation Benefits:**

1. **Clear Responsibilities**
   - Intelligence = Data storage (write operations)
   - Fog-of-War = Data access (read operations)

2. **Performance**
   - Intelligence updated infrequently (espionage ops)
   - Fog-of-war queried frequently (every AI decision)
   - Separation allows optimization of each independently

3. **Testability**
   - Can unit test intelligence storage independently
   - Can unit test fog-of-war filtering independently
   - Can verify intel persistence without fog-of-war complexity

4. **Extensibility**
   - Easy to add new intel types (just update IntelligenceDatabase)
   - Easy to modify visibility rules (just update createFogOfWarView)
   - Changes isolated to specific layer

### Why Not Merge Fog-of-War + GameEvents?

**Different Purposes:**

| Aspect                | Fog-of-War               | GameEvents            |
|-----------------------|--------------------------|-----------------------|
| **Question Answered** | "What can I see?"        | "What happened?"      |
| **Time Frame**        | Current state snapshot   | Temporal events       |
| **Usage Pattern**     | Query current game state | Consume notifications |
| **Lifetime**          | Per-query                | Per-turn              |
| **Data Type**         | Aggregated state         | Event stream          |
| **AI Use Case**       | Strategic planning       | Reactive behavior     |

### Performance Considerations

#### Memory Cost: FilteredGameState Copies

**Current Approach:**
```nim
let view = createFogOfWarView(state, houseId)  # Full copy
# ~1-2 MB per house per query
```

**Overhead:** Acceptable for current scale (4 players, ~200 turns)

**Alternative (if needed):**
```nim
# Query-based API (lazy evaluation)
proc getVisibleSystems(state, houseId): seq[SystemId]
proc getColonyIntel(state, houseId, systemId): Option[ColonyIntel]
proc canObserve(state, houseId, systemId): bool

# No full copy, query on demand
# Trade-off: More complex API, harder to pass to AI
```

**Decision:** Keep current approach until profiling shows bottleneck.

#### Event Volume

**Current:** ~50-200 events per turn (average game)
- Combat heavy turn: ~300-500 events
- Quiet turn: ~20-50 events

**Filtering Cost:** Negligible (simple visibility checks)

**Memory:** Events are ephemeral, discarded after consumption

---

## Implementation Guidelines

### Adding New Intelligence Types

```nim
// 1. Define report type (src/engine/intelligence/types.nim)
type
  NewIntelReport* = object
    targetId*: SystemId
    gatheredTurn*: int
    quality*: IntelQuality
    # ... specific fields ...

// 2. Add to IntelligenceDatabase
type
  IntelligenceDatabase* = object
    # ... existing fields ...
    newIntelReports*: Table[SystemId, NewIntelReport]  # ← Add

// 3. Add storage function
proc addNewIntelReport*(db: var IntelligenceDatabase, report: NewIntelReport) =
  db.newIntelReports[report.targetId] = report

// 4. Update fog-of-war to read new intel (src/engine/fog_of_war.nim)
proc createFogOfWarView*(...): FilteredGameState =
  # ... existing code ...

  # Read new intel type
  for targetId, report in house.intelligence.newIntelReports:
    # Process into FilteredGameState
    ...
```

### Adding New Event Types

```nim
// 1. Add GameEventType enum value (src/engine/resolution/types.nim)
type
  GameEventType* {.pure.} = enum
    # ... existing values ...
    NewEventType  # ← Add

// 2. Add case branch with specific fields
GameEvent* = ref object
  # ... common fields ...
  case eventType*: GameEventType
  # ... existing branches ...
  of NewEventType:
    specificField1*: int
    specificField2*: string

// 3. Create factory function (src/engine/resolution/event_factory/category.nim)
proc newEvent*(field1: int, field2: string): GameEvent =
  GameEvent(
    eventType: GameEventType.NewEventType,
    turn: 0,  # Set by engine
    specificField1: field1,
    specificField2: field2
  )

// 4. Emit event in engine module
events.add(event_factory.newEvent(42, "data"))

// 5. Add visibility rule (src/engine/intelligence/event_processor/visibility.nim)
proc shouldHouseSeeEvent(...): bool =
  case event.eventType:
  # ... existing rules ...
  of NewEventType:
    # Define visibility logic
    return hasPresenceInSystem(state, houseId, event.systemId.get())
```

### Querying Intelligence in AI Code

```nim
// AI planning phase
proc evaluateInvasionTarget(view: FilteredGameState, systemId: SystemId): bool =
  # Query filtered view (already includes intelligence)
  for colony in view.visibleColonies:
    if colony.systemId == systemId:
      # Check intel age
      if colony.intelTurn.isSome:
        let intelAge = view.turn - colony.intelTurn.get()
        if intelAge > 5:
          # Intel too old, need fresh scouting
          return false

      # Use intel data
      if colony.estimatedDefenses.get() < 50:
        return true  # Weak target

  return false  # Unknown or too strong
```

### Consuming Events in AI Code (Phase 7e - Future)

```nim
// AI reactive behavior
proc processEvents(controller: var AIController,
                   filteredEvents: seq[GameEvent],
                   state: FilteredGameState) =
  for event in filteredEvents:
    case event.eventType:
    of FleetDestroyed:
      if event.systemId.get() in controller.strategicSystems:
        # URGENT: Lost defensive fleet at key system
        controller.threatLevel += 50
        controller.prioritizeReinforcement(event.systemId.get())

    of WarDeclared:
      if event.targetHouseId.get() == controller.houseId:
        # War declared against us - shift to defensive posture
        controller.setDefensiveMode()
        controller.recallExpeditionaryForces()

    of OrderIssued:
      if event.orderType == "SpyOnPlanet":
        # Own spy mission issued - track mission
        controller.trackSpyMission(event.fleetId, event.targetSystem)
```

### Generating Client Reports

```nim
// Client-side report generation (src/client/reports/turn_report.nim)
proc generateAlertsSection(events: seq[GameEvent], ...): ReportSection =
  for event in events:
    case event.eventType:
    of WeaponFired:
      # Use structured fields (NOT description string)
      result.lines.add(&"• {event.attackingSquadron} fired {event.weaponType} " &
                       &"at {event.targetSquadron} (CER: {event.cerRoll}, " &
                       &"Damage: {event.damage})")

    of DiplomaticRelationChanged:
      result.lines.add(&"! Diplomatic relations: {event.sourceHouseId} → " &
                       &"{event.targetHouseId} changed from {event.oldState} " &
                       &"to {event.newState} ({event.changeReason})")

    of OrderIssued:
      if event.orderType == "SpyOnPlanet":
        result.lines.add(&"• Espionage mission launched: {event.orderType} targeting " &
                         &"{event.targetSystem} ({event.fleetSize} scouts)")
```

---

## Testing Strategy

### Unit Tests

```nim
# Test intelligence storage
test "Intelligence database stores colony reports":
  var db = newIntelligenceDatabase()
  let report = ColonyIntelReport(...)
  db.addColonyReport(report)
  check db.colonyReports[report.colonyId] == report

# Test fog-of-war filtering
test "Fog-of-war shows only visible systems":
  let state = createTestState()
  let view = createFogOfWarView(state, "house-atreides")
  check "sys-owned" in view.visibleSystems  # Owned system
  check "sys-enemy" notin view.visibleSystems  # Never visited

# Test event visibility
test "Events filtered by fog-of-war":
  let event = FleetDestroyed(systemId = "sys-42", ...)
  check shouldHouseSeeEvent(state, "house-with-presence", event) == true
  check shouldHouseSeeEvent(state, "house-no-presence", event) == false
```

### Integration Tests

```nim
# Test full cycle: espionage → intelligence → fog-of-war → AI
test "Spy operation updates intelligence and fog-of-war":
  # 1. Execute spy operation
  let report = executeSpyMission(state, "spy-123", "sys-42")

  # 2. Verify intelligence updated
  check state.houses["spy-owner"].intelligence.colonyReports.hasKey("sys-42")

  # 3. Verify fog-of-war includes intel
  let view = createFogOfWarView(state, "spy-owner")
  check "sys-42" in view.visibleSystems
  check view.visibleSystems["sys-42"].visibility == Scouted

  # 4. Verify intel age tracked
  check view.visibleSystems["sys-42"].lastScoutedTurn == some(state.turn)
```

---

## Performance Optimizations

### Current Performance Characteristics

| Operation                        | Frequency           | Cost              | Impact                |
|----------------------------------|---------------------|-------------------|-----------------------|
| `createFogOfWarView()`           | Per AI decision     | ~1-2 MB copy      | Medium (4x per turn)  |
| `filterEventsByVisibility()`     | Per house per turn  | O(n) event scan   | Low (~200 events)     |
| `house.intelligence.addReport()` | Per espionage op    | Table insert      | Negligible            |
| Event generation                 | Per turn resolution | Object allocation | Low (200-500 objects) |

### Optimization Opportunities

#### 1. Query-Based Fog-of-War (Major Optimization)

**Problem:** `FilteredGameState` creates full game state copy per house.

**Current Approach:**
```nim
// Full copy (1-2 MB)
let view = createFogOfWarView(state, houseId)

// AI queries snapshot
for colony in view.visibleColonies:
  analyzeColony(colony)
```

**Optimized Approach:**
```nim
// No copy - query functions
proc getVisibleSystems(state, houseId): seq[SystemId]
proc getColonyIntel(state, houseId, systemId): Option[VisibleColony]
proc canObserveSystem(state, houseId, systemId): bool

// AI queries on demand (lazy evaluation)
for systemId in getVisibleSystems(state, houseId):
  if let colony = getColonyIntel(state, houseId, systemId):
    analyzeColony(colony)
```

**Trade-offs:**

| Aspect             | Snapshot (Current)     | Query-Based (Alternative) |
|--------------------|------------------------|---------------------------|
| **Memory**         | High (full copy)       | Low (no copy)             |
| **CPU**            | Medium (one-time copy) | Low (lazy evaluation)     |
| **API Complexity** | Simple (object access) | Complex (function calls)  |
| **AI Code**        | Easy to write          | Harder to write           |
| **Caching**        | Natural (snapshot)     | Manual (if needed)        |

**Recommendation:** Keep snapshot approach unless profiling shows bottleneck.

#### 2. Event Pooling (Minor Optimization)

**Problem:** 200-500 event allocations per turn.

**Current:**
```nim
events.add(event_factory.weaponFired(...))  # Allocates new object
```

**Optimized:**
```nim
// Pre-allocate event pool
var eventPool: seq[GameEvent] = newSeqOfCap[GameEvent](500)

// Reuse events from pool
proc allocateEvent(): GameEvent =
  if eventPool.len > 0:
    result = eventPool.pop()
    # Reset fields
  else:
    result = GameEvent()
```

**Impact:** Minimal (GC handles small allocations well in Nim)

**Recommendation:** Not worth complexity unless profiling shows GC pressure.

#### 3. Intelligence Database Compression (Future)

**Problem:** Old intel reports accumulate over long games.

**Current:** All intel reports kept forever in `house.intelligence.*`

**Optimized:**
```nim
// Prune stale intel (>20 turns old)
proc pruneStaleIntel(db: var IntelligenceDatabase, currentTurn: int) =
  for systemId, report in db.colonyReports.pairs:
    if currentTurn - report.gatheredTurn > 20:
      db.colonyReports.del(systemId)  # Remove outdated intel
```

**Impact:** Reduces memory growth in 200+ turn games

**Recommendation:** Implement if games routinely exceed 200 turns.

#### 4. Visibility Rule Caching

**Problem:** `hasPresenceInSystem()` called repeatedly for same system.

**Current:**
```nim
// Called for every event
for event in events:
  if hasPresenceInSystem(state, houseId, event.systemId):
    filteredEvents.add(event)
```

**Optimized:**
```nim
// Pre-compute presence map
let presenceMap = buildPresenceMap(state, houseId)  # O(fleets + colonies)

// Fast lookup
for event in events:
  if event.systemId in presenceMap:
    filteredEvents.add(event)
```

**Impact:** O(n*m) → O(n+m) where n=events, m=systems

**Recommendation:** Implement if event filtering shows up in profiler.

### Network Protocol Considerations (Nostr)

#### Data Transfer Requirements

**Client-Server Communication:**
```
Turn Submission:
  Client → Server: OrderPacket (~5-20 KB compressed)
  Server → Client: TurnResult (~50-200 KB compressed)

Components:
  - OrderPacket: Fleet orders, diplomatic actions, research allocation
  - TurnResult: newState (GameState), events (seq[GameEvent]), combatReports
```

#### Optimization for Nostr Protocol

##### 1. **Delta Compression (Critical for Nostr)**

**Problem:** Sending full GameState every turn is expensive (~2-5 MB).

**Solution:** Send only changes (delta):
```nim
type
  StateDelta* = object
    turn*: int
    baseStateHash*: string  # Hash of previous state (verify consistency)

    # Only changed entities
    modifiedHouses*: Table[HouseId, House]
    modifiedColonies*: Table[SystemId, Colony]
    modifiedFleets*: Table[FleetId, Fleet]
    deletedFleets*: seq[FleetId]

    # Intelligence updates (per-house deltas)
    intelligenceUpdates*: Table[HouseId, IntelligenceDelta]

  IntelligenceDelta* = object
    newColonyReports*: Table[SystemId, ColonyIntelReport]
    newSystemReports*: Table[SystemId, SystemIntelReport]
    newCombatReports*: seq[CombatEncounterReport]
    # Note: Only NEW reports, not full database

TurnResult* = object
  delta*: StateDelta        # ← Instead of full GameState
  events*: seq[GameEvent]   # ← Already small (events only)
  combatReports*: seq[CombatReport]
```

**Compression Ratio:**

| Data                         | Full State | Delta      | Savings |
|------------------------------|------------|------------|---------|
| **Early Game** (Turn 1-20)   | 2 MB       | 50-100 KB  | 95%     |
| **Mid Game** (Turn 50-100)   | 4 MB       | 100-200 KB | 95%     |
| **Late Game** (Turn 150-200) | 5 MB       | 150-300 KB | 94%     |

**Implementation:**
```nim
proc computeStateDelta(oldState, newState: GameState): StateDelta =
  result.turn = newState.turn
  result.baseStateHash = oldState.computeHash()

  # Find modified houses
  for houseId, newHouse in newState.houses:
    if houseId notin oldState.houses or
       oldState.houses[houseId] != newHouse:
      result.modifiedHouses[houseId] = newHouse

  # Find modified colonies (similar)
  # Find modified/deleted fleets (similar)

  # Intelligence deltas (per-house)
  for houseId, newHouse in newState.houses:
    let oldHouse = oldState.houses.getOrDefault(houseId)
    let delta = computeIntelligenceDelta(
      oldHouse.intelligence,
      newHouse.intelligence
    )
    if delta.hasChanges():
      result.intelligenceUpdates[houseId] = delta

proc applyStateDelta(state: var GameState, delta: StateDelta) =
  # Verify base state matches (consistency check)
  if state.computeHash() != delta.baseStateHash:
    raise newException(ValueError, "State delta mismatch - desync detected")

  # Apply changes
  for houseId, house in delta.modifiedHouses:
    state.houses[houseId] = house

  for systemId, colony in delta.modifiedColonies:
    state.colonies[systemId] = colony

  # Apply intelligence deltas
  for houseId, intelDelta in delta.intelligenceUpdates:
    state.houses[houseId].intelligence.applyDelta(intelDelta)
```

##### 2. **Event Compression**

**Problem:** 200-500 events * 20+ fields = large payload

**Solution:** Binary encoding with field presence bits
```nim
type
  CompactGameEvent* = object
    eventType*: uint8           # 1 byte (107 event types)
    fieldPresence*: uint32      # 4 bytes (bit flags for which fields present)
    compactData*: seq[byte]     # Variable length

proc compressEvent(event: GameEvent): CompactGameEvent =
  # Only serialize present fields
  var presence: uint32 = 0
  var data: seq[byte]

  if event.houseId.isSome:
    presence = presence or (1 shl 0)
    data.add(serializeHouseId(event.houseId.get()))

  if event.systemId.isSome:
    presence = presence or (1 shl 1)
    data.add(serializeSystemId(event.systemId.get()))

  # ... serialize only present fields

  result = CompactGameEvent(
    eventType: ord(event.eventType).uint8,
    fieldPresence: presence,
    compactData: data
  )
```

**Compression Ratio:**

| Format            | Size per Event | 300 Events |
|-------------------|----------------|------------|
| **JSON**          | ~200 bytes     | ~60 KB     |
| **MessagePack**   | ~80 bytes      | ~24 KB     |
| **Custom Binary** | ~30 bytes      | ~9 KB      |

##### 3. **Filtered State per Client (Fog-of-War Advantage)**

**Problem:** Each client only needs to see their filtered view.

**Solution:** Server sends per-client filtered state (already fog-of-war filtered!)

```nim
# Server computes once, sends to all clients
proc prepareClientUpdates(turnResult: TurnResult): Table[HouseId, ClientUpdate] =
  for houseId in turnResult.newState.houses.keys:
    # Fog-of-war already filters!
    let filteredView = createFogOfWarView(turnResult.newState, houseId)

    # Compute delta from client's last known state
    let delta = computeStateDelta(
      clientLastState[houseId],  # Track per client
      filteredView
    )

    # Filter events (already implemented!)
    let filteredEvents = turnResult.events.filterIt(
      shouldHouseSeeEvent(turnResult.newState, houseId, it)
    )

    result[houseId] = ClientUpdate(
      delta: delta,              # Only what changed for THIS client
      events: filteredEvents     # Only what THIS client can see
    )
```

**Network Efficiency:**

| Data                 | Full State (All Clients) | Filtered (Per Client) | Savings |
|----------------------|--------------------------|-----------------------|---------|
| **GameState**        | 5 MB                     | 500 KB - 1 MB         | 80-90%  |
| **Events**           | 300 events               | 50-150 events         | 50-83%  |
| **Total per Client** | 5.2 MB                   | 520 KB - 1.1 MB       | 80-90%  |

##### 4. **Nostr Event Structure**

**Recommended Nostr Event Kind:** `kind: 30000` (Parameterized Replaceable Event)

```json
{
  "kind": 30000,
  "tags": [
    ["d", "ec4x-game-<game-id>"],
    ["t", "ec4x"],
    ["turn", "42"],
    ["client", "<house-id>"]
  ],
  "content": "<encrypted-client-update>",
  "created_at": 1234567890
}
```

**Encryption:** Use Nostr NIP-04 encryption (client public key → encrypted content)

**Benefits:**
- Per-client filtering (each house gets own Nostr event)
- Replay protection (turn number in tags)
- Replace old events (only latest turn matters)
- Efficient relay filtering (tags)

##### 5. **Incremental Intelligence Synchronization**

**Problem:** Intelligence database grows over time (10+ MB in long games).

**Solution:** Client reconstructs intelligence from deltas:
```nim
# Client state reconstruction
var clientState = initialState  # Turn 0

for turn in 1..currentTurn:
  # Receive delta from server
  let delta = fetchTurnDelta(turn)

  # Apply delta
  clientState.applyDelta(delta)

  # Intelligence accumulated incrementally
  for houseId, intelDelta in delta.intelligenceUpdates:
    clientState.houses[houseId].intelligence.applyDelta(intelDelta)
```

**Network Traffic Over 100 Turns:**

| Approach                 | Traffic                    |
|--------------------------|----------------------------|
| **Full state each turn** | 100 turns × 5 MB = 500 MB  |
| **Delta compression**    | 100 turns × 150 KB = 15 MB |
| **Savings**              | 97%                        |

##### 6. **Event Batching with Priority**

**Problem:** Some events are more important than others.

**Solution:** Prioritize critical events, batch low-priority events:
```nim
type
  EventPriority* {.pure.} = enum
    Critical,   # Fleet destroyed, war declared
    Important,  # Combat rounds, diplomatic changes
    Info,       # Construction completed, tech advance
    Detail      # Weapon fired, ship damaged

proc prioritizeEvents(events: seq[GameEvent]): Table[EventPriority, seq[GameEvent]] =
  # Group events by priority
  for event in events:
    let priority = getEventPriority(event.eventType)
    result[priority].add(event)

# Nostr protocol: Send critical events immediately, batch others
proc sendEventsToClient(events: seq[GameEvent], clientPubkey: string) =
  let prioritized = prioritizeEvents(events)

  # Critical events: Individual Nostr events (immediate delivery)
  for event in prioritized[Critical]:
    sendNostrEvent(event, clientPubkey, immediate = true)

  # Other events: Batched Nostr event (delayed delivery OK)
  let batch = prioritized[Important] & prioritized[Info] & prioritized[Detail]
  sendNostrEventBatch(batch, clientPubkey)
```

### Profiling Recommendations

**Before optimizing, profile to find actual bottlenecks:**

```bash
# Profile full game simulation
nim c --profiler:on --stackTrace:on -d:release src/ai/analysis/run_simulation.nim
./run_simulation --turns 100 --seed 12345
# Generates profile.txt with hotspots
```

**Key metrics to watch:**
- Memory allocations per turn
- `createFogOfWarView()` call count and duration
- Event filtering time
- Intelligence database size growth
- State serialization time (for Nostr)

### Summary: Optimization Priority

| Priority          | Optimization                    | When to Implement             |
|-------------------|---------------------------------|-------------------------------|
| **P0 (Critical)** | Delta compression for Nostr     | Before multiplayer release    |
| **P0 (Critical)** | Per-client fog-of-war filtering | Already implemented!          |
| **P1 (High)**     | Event binary encoding           | If Nostr bandwidth limited    |
| **P2 (Medium)**   | Query-based fog-of-war          | If profiler shows bottleneck  |
| **P3 (Low)**      | Intelligence pruning            | If games exceed 200 turns     |
| **P4 (Nice)**     | Event pooling                   | If profiler shows GC pressure |

**Current status:** System is well-optimized for single-player. Need P0 optimizations
before Nostr multiplayer deployment.

---

## Related Documentation

- **Fog-of-War System:** `fog_of_war.md` (if exists)
- **Combat Events:** `active_fleet_order_game_events.md`
- **Spy Scouts:** `docs/specs/02-assets.md#242-spy-scouts`
- **Intelligence Gathering:** `docs/specs/intel.md`
- **Canonical Turn Cycle:** `ec4x_canonical_turn_cycle.md`

---

## Version History

| Version | Date       | Changes                                           |
|---------|------------|---------------------------------------------------|
| 1.0     | 2025-12-11 | Initial documentation of three-layer architecture |

---

## Glossary

| Term                      | Definition                                                      |
|---------------------------|-----------------------------------------------------------------|
| **Intelligence Database** | Per-house persistent storage of accumulated knowledge           |
| **Fog-of-War**            | Query layer creating filtered snapshots per house               |
| **GameEvents**            | Temporal event stream of turn happenings                        |
| **FilteredGameState**     | Per-house snapshot combining current + historical intel         |
| **Stale Intel**           | Intelligence reports with age tracking (gatheredTurn)           |
| **Visibility Level**      | System observation state (None/Adjacent/Scouted/Occupied/Owned) |
| **Event Factory**         | Functions creating structured GameEvent objects                 |
| **Reactive Behavior**     | AI responding to turn events (Phase 7e)                         |
