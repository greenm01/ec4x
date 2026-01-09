# Colony Management Systems

**Purpose:** Colony-level mechanics for development, population, and automation  
**Last Updated:** 2026-01-09

---

## Overview

EC4X colonies have several management systems that affect long-term development and economic output.

---

## 1. Terraforming

### Purpose

Upgrade planet class to increase production capacity and economic output.

### Mechanics

**Planet Class Progression:**
- Class 1 → Class 2 → Class 3 → Class 4 → Class 5 → Class 6
- Each upgrade increases base PP/RP production
- Higher classes support more population and infrastructure

**Duration:**
- Tech-dependent: Based on Terraforming (TFM) tech level
- Multi-turn projects (typically 5-10 turns depending on TFM level)
- One project per colony at a time

### Architecture

**Separate Slot** (independent from construction/repair queues):

```nim
type Colony = object
  activeTerraforming: Option[TerraformProject]
  # Does not interfere with construction or repair queues

type TerraformProject = object
  targetClass: PlanetClass
  turnsRemaining: int
  cost: int  # Paid upfront
```

### Turn Cycle Integration

**Submission:** Command Phase Part C (with other build orders)  
**Payment:** Upfront (same as construction)  
**Advancement:** Production Phase Step 5 (after construction/repairs)  
**Completion:** Planet class upgraded, new production capacity unlocked

### Key Properties

- Independent system (doesn't use dock capacity)
- One project per colony maximum
- Upfront payment (like construction, not deferred like repairs)
- Advances every turn automatically
- No commissioning step (applies immediately on completion)

---

## 2. Population Management (Placeholder)

**Future sections:**
- Population growth mechanics
- Migration between colonies
- Population units (PTU) and economic impact
- Recruitment costs for armies/marines

---

## 3. Infrastructure Development (Placeholder)

**Future sections:**
- Industrial Units (IU) investment and scaling costs
- Colony improvements and upgrades
- Economic output calculations
- Blockade effects on production

---

## 4. Colony Automation

### Overview

Colony automation reduces micromanagement burden by automatically handling routine tasks like ship assignments, fighter/marine loading, and repair submissions. Each automation feature is controlled by a per-colony toggle, allowing players to customize behavior for different strategic situations.

**Key Principles:**
- **Convenience, not restriction** - Manual actions always allowed regardless of automation settings
- **Per-colony control** - Each colony has independent automation flags
- **Predictable behavior** - Automation follows clear, documented rules
- **Player override** - Players can cancel auto-submitted orders during submission window

### When Automation Runs

**Command Phase Part C** (Colony Automation)

**Sequence:**
1. Command Phase Part A: Unified Commissioning (ships/fighters/marines commissioned)
2. Command Phase Part B: Auto-Repair Submission (submit repair orders if enabled)
3. **Command Phase Part C: Colony Automation** (assign ships, load fighters/marines)
4. Command Phase Part D: Player Submission Window (players can review/cancel/add orders)
5. Command Phase Part E: Command Validation & Storage (finalize orders)

**Rationale:** Automation runs after commissioning (assets available) but before player window (players can override).

### Automation Flags

**Colony Object:**

```nim
type Colony = object
  # ... other fields ...
  
  # Automation toggles (per-colony configuration)
  autoRepair: bool        # Default: false
  autoJoinFleets: bool    # Default: true
  autoLoadMarines: bool   # Default: true
  autoLoadFighters: bool  # Default: true
```

### 1. Auto-Repair (`colony.autoRepair`)

**Default:** `false` (opt-in)

**Purpose:** Automatically submit repair orders for damaged assets at the colony.

**When:** Command Phase Part B (before player window)

**What Gets Auto-Repaired:**

Priority order (highest to lowest):
1. **Ships** (capital ships) - Highest military value, critical offensive/defensive assets
2. **Starbases** (orbital defense) - Strategic defensive platforms
3. **Ground Units** (marines, armies) - Planetary defense forces
4. **Facilities** (damaged spaceports/shipyards) - Economic infrastructure

**Algorithm:**

```nim
proc submitAutoRepairs(state: var GameState, colonyId: ColonyId):
  let colony = state.colony(colonyId).get()
  
  # Skip if disabled
  if not colony.autoRepair:
    return
  
  # Collect all damaged assets at colony
  var damagedAssets: seq[RepairableAsset]
  
  # Priority 1: Ships
  for ship in state.shipsAt(colonyId):
    if ship.status == Damaged:
      damagedAssets.add(RepairableAsset(
        entityId: ship.id,
        entityType: Ship,
        priority: 1,
        cost: calculateRepairCost(ship)
      ))
  
  # Priority 2: Starbases
  for starbase in state.starbasesAt(colonyId):
    if starbase.status == Damaged:
      damagedAssets.add(RepairableAsset(
        entityId: starbase.id,
        entityType: Starbase,
        priority: 2,
        cost: calculateRepairCost(starbase)
      ))
  
  # Priority 3: Ground units
  for groundUnit in state.groundUnitsAt(colonyId):
    if groundUnit.status == Damaged:
      damagedAssets.add(RepairableAsset(
        entityId: groundUnit.id,
        entityType: GroundUnit,
        priority: 3,
        cost: calculateRepairCost(groundUnit)
      ))
  
  # Priority 4: Facilities
  for facility in state.facilitiesAt(colonyId):
    if facility.status == Damaged:
      damagedAssets.add(RepairableAsset(
        entityId: facility.id,
        entityType: Facility,
        priority: 4,
        cost: calculateRepairCost(facility)
      ))
  
  # Sort by priority, then by cost (descending - expensive repairs first)
  damagedAssets.sort do (a, b: RepairableAsset) -> int:
    if a.priority != b.priority:
      return cmp(a.priority, b.priority)
    else:
      return cmp(b.cost, a.cost)  # Higher cost first
  
  # Submit repairs up to available capacity
  for asset in damagedAssets:
    case asset.entityType:
      of Ship, Starbase:
        # Use drydock capacity
        let drydock = findAvailableDrydock(state, colonyId)
        if drydock.isSome:
          submitRepair(state, asset.entityId, drydock.get().id)
          events.add(AutoRepairSubmitted, asset.entityId)
        else:
          break  # No more drydock capacity
      
      of GroundUnit, Facility:
        # Use colony repair capacity
        if colony.hasRepairCapacity():
          submitRepair(state, asset.entityId, none(FacilityId))
          events.add(AutoRepairSubmitted, asset.entityId)
```

**Key Properties:**
- Respects capacity limits (drydock capacity, colony repair capacity)
- Prioritizes military assets over economic infrastructure
- Within same priority, repairs expensive assets first (maximize recovery value)
- Does NOT check treasury (repairs have deferred payment)
- Players can cancel auto-repairs during Part D (player window)

**Example:**

```
Turn 10 Conflict Phase:
  Enemy attack damages: 3 Cruisers, 1 Starbase, 5 Marines, 1 Spaceport

Turn 11 Command Phase Part B:
  Colony has: 2 Drydocks (5 docks each = 10 total capacity)
  Auto-repair enabled: true
  
  Auto-repair submission (priority order):
    1. Cruiser #1 → Drydock A (Priority 1: Ships)
    2. Cruiser #2 → Drydock A
    3. Cruiser #3 → Drydock A
    4. Starbase #1 → Drydock A (Priority 2: Starbases)
    5. Marine #1 → Colony repair (Priority 3: Ground units)
    6. Marine #2 → Colony repair
    7. Marine #3 → Colony repair
    8. Marine #4 → Colony repair
    9. Marine #5 → Colony repair
    10. Spaceport #1 → Colony repair (Priority 4: Facilities)
  
  Result: All 10 assets auto-repaired

Turn 11 Command Phase Part D:
  Player reviews auto-repairs, decides to cancel Marine repairs (low priority)
  Cancels Marine #4, Marine #5 repairs
  Frees 2 colony repair slots
```

**Strategic Considerations:**

*When to enable:*
- Backline colonies (safe from immediate threats)
- Economic hubs (many facilities, stable treasury)
- Garrison colonies (many damaged ground units after combat)

*When to disable:*
- Frontline colonies (need manual control over repair priorities)
- Limited capacity colonies (avoid filling queues with low-priority repairs)
- Treasury constraints (avoid auto-committing to deferred payments)

### 2. Auto-Join Fleets (`colony.autoJoinFleets`)

**Default:** `true` (opt-out)

**Purpose:** Automatically assign newly commissioned and repaired ships to fleets.

**When:** Command Phase Part C (after commissioning Part A)

**What Gets Assigned:**

All unassigned ships at the colony:
- Newly commissioned ships (from Spaceports/Shipyards)
- Repaired ships (from Drydocks)

**Algorithm:**

```nim
proc autoAssignShipsToFleets(state: var GameState, colony: Colony):
  # Skip if disabled
  if not colony.autoJoinFleets:
    return
  
  # Get all unassigned ships at colony
  let unassignedShips = state.shipsAt(colony.id).filterIt(
    it.fleetId.isNone and it.ownerId == colony.ownerId
  )
  
  if unassignedShips.len == 0:
    return
  
  # Find or create fleet at colony
  var fleet = state.fleetsAt(colony.id, colony.ownerId).firstOrNone()
  
  if fleet.isNone:
    # Create new fleet
    fleet = some(createFleet(state, colony.ownerId, colony.id))
    events.add(FleetCreated, fleet.get().id, colony.id)
  
  # Assign all ships to fleet
  for ship in unassignedShips:
    fleet.get().ships.add(ship.id)
    ship.fleetId = some(fleet.get().id)
    events.add(ShipAutoAssigned, ship.id, fleet.get().id)
```

**Key Properties:**
- Treats newly commissioned and repaired ships uniformly (no distinction)
- Does NOT track original fleet membership for repaired ships
- Creates new fleet if none exists at colony
- Assigns to first available fleet at colony (if multiple exist)
- All ships go to same fleet (simplicity over optimization)

**Example:**

```
Turn 10 Command Phase A:
  3 ships commission at Colony X:
    - 1 Cruiser (newly built)
    - 1 Destroyer (newly built)
    - 1 Battleship (repaired from drydock)
  
  All ships unassigned (fleetId = None)

Turn 10 Command Phase C:
  Colony X has autoJoinFleets = true
  No existing fleets at Colony X
  
  Auto-assignment:
    1. Create new Fleet #42 at Colony X
    2. Assign Cruiser → Fleet #42
    3. Assign Destroyer → Fleet #42
    4. Assign Battleship → Fleet #42
  
  Result: Fleet #42 with 3 ships (1 Cruiser, 1 Destroyer, 1 Battleship)
```

**Strategic Considerations:**

*When to enable (default):*
- Standard colonies (routine ship production)
- Defensive postures (gather ships for local defense)
- Simplified fleet management (reduce micromanagement)

*When to disable:*
- Specialized production colonies (ships need specific fleet assignments)
- Forward staging bases (ships need immediate deployment to specific fleets)
- Complex fleet compositions (manual assignment for strategic balance)

**Manual Override:**

Even with auto-assignment enabled, players can:
- Manually reassign ships to different fleets during Part D
- Leave ships unassigned (will remain unassigned until next turn)
- Create new fleets and manually assign ships

### 3. Auto-Load Marines (`colony.autoLoadMarines`)

**Default:** `true` (opt-out)

**Purpose:** Automatically load marines from colony storage onto troop transports at the colony.

**When:** Command Phase Part C (after ship assignment)

**What Gets Loaded:**

- Available marines at colony (not assigned to ground defense)
- Troop Transports at colony with available capacity

**Algorithm:**

```nim
proc autoLoadMarinesToTransports(state: var GameState, colony: Colony):
  # Skip if disabled
  if not colony.autoLoadMarines:
    return
  
  let availableMarines = colony.marinesAvailable
  if availableMarines == 0:
    return
  
  # Get all troop transports at colony
  let transports = state.troopTransportsAt(colony.id, colony.ownerId)
  if transports.len == 0:
    return
  
  var marinesRemaining = availableMarines
  
  # Load marines to transports (round-robin)
  for transport in transports:
    if marinesRemaining == 0:
      break
    
    let capacity = transport.marineCapacity - transport.marinesOnboard
    if capacity > 0:
      let toLoad = min(capacity, marinesRemaining)
      transport.marinesOnboard += toLoad
      marinesRemaining -= toLoad
      events.add(MarinesAutoLoaded, transport.id, toLoad)
  
  # Update colony storage
  colony.marinesAvailable = marinesRemaining
```

**Key Properties:**
- Only loads available marines (not assigned to garrison duty)
- Respects transport capacity limits
- Round-robin distribution across multiple transports
- Does NOT unload marines from transports (one-way operation)

**Marine Capacity:**

| Ship Class | Marine Capacity |
|------------|-----------------|
| Troop Transport | 10 marines |
| ETAC (Emergency Troop Assault Carrier) | 5 marines |

**Example:**

```
Turn 10 Command Phase C:
  Colony Y has:
    - 25 marines available (in colony storage)
    - 3 Troop Transports at colony
      - Transport A: 3/10 marines (7 capacity)
      - Transport B: 0/10 marines (10 capacity)
      - Transport C: 8/10 marines (2 capacity)
  
  Auto-load enabled: true
  
  Auto-loading (round-robin):
    1. Transport A: Load 7 marines (now 10/10 - full)
    2. Transport B: Load 10 marines (now 10/10 - full)
    3. Transport C: Load 2 marines (now 10/10 - full)
  
  Result:
    - 19 marines loaded (7 + 10 + 2)
    - 6 marines remain at colony
    - All transports at full capacity
```

**Strategic Considerations:**

*When to enable (default):*
- Invasion staging bases (prepare transports for assault)
- Offensive operations (keep transports loaded for quick deployment)
- Simplified logistics (reduce loading micromanagement)

*When to disable:*
- Defensive colonies (keep marines on ground for garrison)
- Limited marine production (manual control over distribution)
- Mixed-purpose transports (manual loading for specific missions)

**Manual Override:**

Players can:
- Manually load/unload marines during Part D
- Specify exact marine counts per transport
- Override auto-loading behavior

### 4. Auto-Load Fighters (`colony.autoLoadFighters`)

**Default:** `true` (opt-out)

**Purpose:** Automatically load fighters from colony storage onto carriers at the colony.

**When:** Command Phase Part C (after ship assignment, after marine loading)

**What Gets Loaded:**

- Available fighters at colony (in hangars or storage)
- Carriers at colony meeting specific criteria

**Carrier Eligibility:**

Only loads to carriers meeting ALL criteria:
1. **Status: Active** (not Reserve, not Mothballed)
2. **Stationary** (no move orders pending, not currently moving)
3. **At colony** (same location as fighter source)
4. **Has capacity** (below max hangar capacity)

**Algorithm:**

```nim
proc autoLoadFightersToCarriers(state: var GameState, colony: Colony):
  # Skip if disabled
  if not colony.autoLoadFighters:
    return
  
  let availableFighters = colony.fightersAvailable
  if availableFighters == 0:
    return
  
  # Get eligible carriers
  let eligibleCarriers = state.carriersAt(colony.id, colony.ownerId).filterIt(
    it.status == Active and
    it.isStationary() and
    it.fighters.len < it.hangarCapacity
  )
  
  if eligibleCarriers.len == 0:
    return
  
  var fightersRemaining = availableFighters
  
  # Load fighters to carriers (round-robin)
  for carrier in eligibleCarriers:
    if fightersRemaining == 0:
      break
    
    let capacity = carrier.hangarCapacity - carrier.fighters.len
    if capacity > 0:
      let toLoad = min(capacity, fightersRemaining)
      
      # Create fighter squadrons and add to carrier
      for i in 0..<toLoad:
        let fighter = colony.fightersAvailable.pop()
        carrier.fighters.add(fighter)
      
      fightersRemaining -= toLoad
      events.add(FightersAutoLoaded, carrier.id, toLoad)
  
  # Update colony storage
  colony.fightersAvailable = fightersRemaining
```

**Key Properties:**
- Only loads to Active stationary carriers (defensive posture)
- Does NOT load to moving carriers (avoid disrupting operations)
- Does NOT load to Reserve/Mothballed carriers (intentionally inactive)
- Respects ACO tech-based hangar capacity limits
- Round-robin distribution across multiple eligible carriers

**Carrier Hangar Capacity:**

Determined by **Advanced Carrier Operations (ACO)** tech level:

| ACO Tech Level | Carrier Capacity | Super Carrier Capacity |
|----------------|------------------|------------------------|
| ACO-0 (base) | 5 fighters | 10 fighters |
| ACO-1 | 6 fighters | 12 fighters |
| ACO-2 | 7 fighters | 14 fighters |
| ACO-3 | 8 fighters | 16 fighters |

**Example:**

```
Turn 10 Command Phase C:
  Colony Z has:
    - 20 fighters available (in colony storage)
    - 4 Carriers at colony:
      - Carrier A: Active, stationary, 2/5 fighters (3 capacity)
      - Carrier B: Active, moving, 1/5 fighters (4 capacity - INELIGIBLE)
      - Carrier C: Reserve, stationary, 0/5 fighters (INELIGIBLE)
      - Carrier D: Active, stationary, 5/5 fighters (0 capacity - full)
  
  Auto-load enabled: true
  
  Eligible carriers: Carrier A only (Carrier B moving, Carrier C Reserve, Carrier D full)
  
  Auto-loading:
    1. Carrier A: Load 3 fighters (now 5/5 - full)
  
  Result:
    - 3 fighters loaded
    - 17 fighters remain at colony
    - Carrier B, C, D unchanged
```

**Strategic Considerations:**

*When to enable (default):*
- Defensive colonies (keep carriers at full strength)
- Carrier production hubs (automatically equip new carriers)
- Simplified carrier management (reduce micromanagement)

*When to disable:*
- Offensive staging (manual loading for specific mission profiles)
- Mixed carrier roles (some for combat, some for transport)
- Limited fighter production (manual control over distribution)

**Why Not Load Moving Carriers?**

Moving carriers are typically:
- Executing offensive operations (specific fighter loadouts already planned)
- Evacuating or repositioning (avoid disrupting tactical plans)
- En route to combat (last-minute loading may not be strategic)

Auto-loading only targets defensive stationary carriers to avoid interfering with player-planned operations.

**Manual Override:**

Players can:
- Manually load fighters to any carrier (including moving/Reserve)
- Specify exact fighter counts per carrier
- Launch fighters from carriers during combat

### Auto-Balance (Always Enabled)

**Purpose:** Automatically distribute resources and units across colony infrastructure for optimal efficiency.

**When:** Continuously (throughout turn resolution)

**What Gets Balanced:**

1. **Population distribution** - Across industrial facilities
2. **Industrial output** - Across production chains
3. **Power distribution** - Across facilities and infrastructure

**Key Property:** Always enabled, NOT toggleable (foundational game mechanic)

**Rationale:** Auto-balance represents competent colonial administration. Disabling it would create meaningless micromanagement without strategic depth.

### Automation Summary Table

| Feature | Default | Timing | Purpose | Toggle Name |
|---------|---------|--------|---------|-------------|
| **Auto-Repair** | `false` | Part B | Submit repair orders for damaged assets | `colony.autoRepair` |
| **Auto-Join Fleets** | `true` | Part C | Assign ships to fleets | `colony.autoJoinFleets` |
| **Auto-Load Marines** | `true` | Part C | Load marines onto transports | `colony.autoLoadMarines` |
| **Auto-Load Fighters** | `true` | Part C | Load fighters onto carriers | `colony.autoLoadFighters` |
| **Auto-Balance** | Always | Continuous | Distribute resources efficiently | (Not toggleable) |

### Configuration

**Per-Colony Settings:**

```nim
type Colony = object
  id: ColonyId
  ownerId: HouseId
  # ... other fields ...
  
  # Automation flags (player-configurable)
  autoRepair: bool = false       # Opt-in (default: disabled)
  autoJoinFleets: bool = true    # Opt-out (default: enabled)
  autoLoadMarines: bool = true   # Opt-out (default: enabled)
  autoLoadFighters: bool = true  # Opt-out (default: enabled)
```

**UI Implications:**

Players should be able to:
1. View automation status per colony (at-a-glance indicators)
2. Toggle automation flags per colony (checkboxes or toggles)
3. Review auto-submitted orders during Part D (with cancel option)
4. See automation events in turn report (transparency)

### Code Modules

**Module:** `src/engine/resolution/automation.nim`

```nim
# Main automation processor
proc processColonyAutomation(state: var GameState, colonyId: ColonyId):
  let colony = state.colony(colonyId).get()
  
  # Auto-assign ships (if enabled)
  if colony.autoJoinFleets:
    autoAssignShipsToFleets(state, colony)
  
  # Auto-load marines (if enabled)
  if colony.autoLoadMarines:
    autoLoadMarinesToTransports(state, colony)
  
  # Auto-load fighters (if enabled)
  if colony.autoLoadFighters:
    autoLoadFightersToCarriers(state, colony)

# Individual automation functions
proc autoAssignShipsToFleets(state: var GameState, colony: Colony)
proc autoLoadMarinesToTransports(state: var GameState, colony: Colony)
proc autoLoadFightersToCarriers(state: var GameState, colony: Colony)

# Auto-repair (separate timing - Part B)
proc submitAutoRepairs(state: var GameState, colonyId: ColonyId)
```

**Integration:** `src/engine/resolve.nim`

```nim
proc resolveCommandPhase(state: var GameState):
  # Part A: Unified Commissioning
  unifiedCommissioning(state)
  
  # Part B: Auto-Repair Submission
  for colony in state.allColonies():
    if colony.autoRepair:
      submitAutoRepairs(state, colony.id)
  
  # Part C: Colony Automation
  for colony in state.allColonies():
    processColonyAutomation(state, colony.id)
  
  # Part D: Player Submission Window
  # (Players review/cancel/add orders)
  
  # Part E: Command Validation & Storage
  processAllOrders(state)
```

### Events Generated

**Auto-Repair Events:**

```nim
EventType.AutoRepairSubmitted:
  colonyId: ColonyId
  entityId: EntityId
  entityType: RepairableType  # Ship, Starbase, GroundUnit, Facility
  cost: int
  priority: int
```

**Auto-Assignment Events:**

```nim
EventType.FleetCreated:
  fleetId: FleetId
  colonyId: ColonyId
  ownerId: HouseId

EventType.ShipAutoAssigned:
  shipId: ShipId
  fleetId: FleetId
  colonyId: ColonyId
```

**Auto-Loading Events:**

```nim
EventType.MarinesAutoLoaded:
  transportId: ShipId
  colonyId: ColonyId
  marinesLoaded: int
  totalOnboard: int

EventType.FightersAutoLoaded:
  carrierId: ShipId
  colonyId: ColonyId
  fightersLoaded: int
  totalOnboard: int
```

### Design Principles

**Convenience Without Restriction:**
- Automation is optional (per-colony toggles)
- Manual actions always allowed (automation never blocks players)
- Predictable behavior (documented algorithms, no surprises)

**Player Control:**
- Opt-in for risky automation (auto-repair = financial commitment)
- Opt-out for routine automation (auto-assign/auto-load = default convenience)
- Override capability (Part D player window allows cancellation)

**Strategic Depth:**
- Automation settings become strategic choices (frontline vs backline colonies)
- Different colonies require different automation profiles
- Balancing automation convenience vs manual control precision

### Common Use Cases

**Backline Economic Hub:**
```
Colony: Industrial Core (safe, high production)
  autoRepair: true         # Many facilities, stable treasury
  autoJoinFleets: true     # Gather ships for defense
  autoLoadMarines: true    # Keep transports ready
  autoLoadFighters: true   # Equip carriers automatically
```

**Frontline Combat Base:**
```
Colony: Forward Staging Alpha (contested, tactical)
  autoRepair: false        # Manual control over repair priorities
  autoJoinFleets: false    # Manual fleet composition for specific missions
  autoLoadMarines: true    # Keep transports loaded for quick assault
  autoLoadFighters: false  # Specific carrier loadouts for combat
```

**Invasion Staging Area:**
```
Colony: Invasion Prep Bravo (offensive operations)
  autoRepair: false        # Prioritize combat ships over infrastructure
  autoJoinFleets: true     # Gather invasion fleet
  autoLoadMarines: true    # Load all transports for invasion
  autoLoadFighters: true   # Equip carriers for escort duty
```

**Shipyard Colony:**
```
Colony: Production Complex (specialized shipbuilding)
  autoRepair: true         # Keep facilities operational
  autoJoinFleets: false    # Ships go to specific fleets (manual assignment)
  autoLoadMarines: false   # Marines stay for garrison defense
  autoLoadFighters: true   # Fighters equip local carriers
```

---

## References

- **Turn Cycle:** `docs/engine/architecture/ec4x_canonical_turn_cycle.md` (Command Phase Parts A-E timing)
- **Construction/Repair:** `docs/engine/architecture/construction-repair-commissioning.md` (Auto-repair integration, commissioning timing)
- **Combat:** `docs/engine/architecture/combat.md` (Queue clearing triggers)
- **Economy:** `docs/specs/economy.md` (Economic output calculations)
- **Configuration:** `config/economy.toml` (Colony parameters)

---
