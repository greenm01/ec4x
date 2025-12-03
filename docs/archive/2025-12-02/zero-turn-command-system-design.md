# TODO: Unified Zero-Turn Command System Architecture

**Status:** Design Document (Not Yet Implemented)
**Created:** 2025-12-02
**Priority:** High - Architectural inconsistency affecting player UX

---

## Executive Summary

EC4X currently has **three separate systems** for handling zero-turn administrative operations:

1. **FleetManagementCommand** - Immediate execution, separate API, NOT in OrderPacket
2. **CargoManagementOrder** - In OrderPacket, executes during turn resolution (wasteful)
3. **SquadronManagementOrder** - In OrderPacket, executes during turn resolution (wasteful)

This creates architectural inconsistency and poor player experience. **Proposed solution:** Consolidate all zero-turn operations into a unified `ZeroTurnCommand` system that executes immediately during order submission, outside the turn resolution pipeline.

**Key benefit:** Players can load troops, reorganize fleets, and issue movement orders **in the same turn** rather than wasting turns on administrative tasks.

---

## Problem Analysis

### Current State: Three Fragmented Systems

#### 1. FleetManagementCommand (Correct Architecture)

**Location:** `src/engine/commands/fleet_commands.nim`

**Operations:**
- `DetachShips` - Split ships from fleet → create new fleet
- `TransferShips` - Move ships between fleets
- `MergeFleets` - Merge entire source fleet into target

**Execution Model:**
- ✅ Executes **immediately** during order submission (0 turns)
- ✅ Separate API: `submitFleetManagementCommand(state, cmd)`
- ✅ NOT in OrderPacket
- ✅ Returns immediate result: `FleetManagementResult`

**Current API:**
```nim
# From orders.nim:61-78
FleetManagementCommand* = object
  ## Immediate-execution fleet management command
  ## Executes synchronously during order submission phase (NOT in OrderPacket)
  ## Allows player to reorganize fleets at colonies, then issue orders for next turn
  houseId*: HouseId
  sourceFleetId*: FleetId
  action*: FleetManagementAction
  shipIndices*: seq[int]
  newFleetId*: Option[FleetId]
  targetFleetId*: Option[FleetId]
```

**Validation Requirements:**
- Fleet must exist and be owned by house
- Fleet must be at **friendly colony** (fleet_commands.nim:50-65)
- Ship indices must be valid
- Cannot detach ALL ships (would leave empty fleet)
- Target fleet must be at same location (for TransferShips/MergeFleets)

**Why This Architecture Is Correct:**
- Clear player intent: "Reorganize now, before issuing turn orders"
- Immediate feedback: Player sees result instantly
- Iterative refinement: Can reorganize multiple times
- No turn consumption: Administrative task doesn't waste strategic time

#### 2. CargoManagementOrder (Incorrect Architecture)

**Location:** `src/engine/orders.nim:40-52`, executed in `economy_resolution.nim:384-543`

**Operations:**
- `LoadCargo` - Load marines or colonists onto spacelift ships
- `UnloadCargo` - Unload cargo from spacelift ships

**Execution Model:**
- ❌ In OrderPacket (orders.nim:106)
- ❌ Executes during **turn resolution** (resolve.nim:450-453)
- ❌ Consumes **full turn** to load troops at colony
- ❌ No immediate feedback to player

**Current API:**
```nim
# From orders.nim:45-52
CargoManagementOrder* = object
  ## Order to load/unload cargo on spacelift ships at colonies
  houseId*: HouseId
  colonySystem*: SystemId              # Colony where action takes place
  action*: CargoManagementAction
  fleetId*: FleetId                    # Fleet containing spacelift ships
  cargoType*: Option[CargoType]        # Type of cargo (Marines, Colonists)
  quantity*: Option[int]               # Amount to load/unload (0 = all available)
```

**Current Resolution Flow:**
```nim
# From resolve.nim:450-453
# Process cargo management (manual loading/unloading)
for houseId in state.houses.keys:
  if houseId in orders:
    resolveCargoManagement(state, orders[houseId], events)
```

**Why This Architecture Is Wrong:**

1. **Wastes Player Turns:**
   - Turn N: "Load 5 marine regiments onto Fleet-Alpha" *(entire turn consumed)*
   - Turn N+1: "Move Fleet-Alpha to enemy system" *(now can move)*
   - **Should be:** Turn N: Load troops AND move fleet (0 turns + 1 turn = 1 turn total)

2. **No Immediate Validation:**
   - Player submits cargo order
   - Turn resolves
   - **Only then** discovers error (not enough marines, ship crippled, etc.)

3. **Inconsistent with FleetManagement:**
   - FleetManagement: Reorganize ships instantly at colony
   - CargoManagement: Load cargo... next turn? Why?

4. **Real-World Analogy Fails:**
   - Military doesn't spend weeks "loading trucks" before moving
   - Loading is **preparation phase**, not operational phase

#### 3. SquadronManagementOrder (Incorrect Architecture)

**Location:** `src/engine/orders.nim:16-38`, executed in `economy_resolution.nim:202-382`

**Operations:**
- `TransferShip` - Move ship directly between squadrons at colony
- `AssignToFleet` - Assign squadron to fleet (new or existing)

**Execution Model:**
- ❌ In OrderPacket (orders.nim:105)
- ❌ Executes during **turn resolution** (resolve.nim:445-448)
- ❌ Consumes **full turn** to reorganize squadrons at colony
- ❌ Complex validation logic duplicated in resolution phase

**Current API:**
```nim
# From orders.nim:21-38
SquadronManagementOrder* = object
  ## Order to form squadrons, transfer ships, or assign to fleets at colonies
  houseId*: HouseId
  colonySystem*: SystemId              # Colony where action takes place
  action*: SquadronManagementAction

  # For FormSquadron: select ships from commissioning pool
  shipIndices*: seq[int]               # Indices into colony.commissionedShips
  newSquadronId*: Option[string]       # Optional custom squadron ID

  # For TransferShip: move ship between squadrons
  sourceSquadronId*: Option[string]    # Squadron to transfer from
  targetSquadronId*: Option[string]    # Squadron to transfer to (or create new)
  shipIndex*: Option[int]              # Index of ship in source squadron

  # For AssignToFleet: assign squadron to fleet
  squadronId*: Option[string]          # Squadron to assign
  targetFleetId*: Option[FleetId]      # Fleet to assign to (or create new)
```

**Current Resolution Flow:**
```nim
# From resolve.nim:445-448
# Process squadron management orders (form squadrons, transfer ships, assign to fleets)
for houseId in state.houses.keys:
  if houseId in orders:
    resolveSquadronManagement(state, orders[houseId], events)
```

**Why This Architecture Is Wrong:**

1. **Wastes Player Turns:**
   - Turn N: "Assign Squadron-Alpha to Fleet-Beta" *(entire turn consumed)*
   - Turn N+1: "Move Fleet-Beta to patrol route" *(now can move)*
   - **Should be:** Turn N: Assign squadron AND issue patrol order (0 turns + order execution)

2. **Complex Validation During Resolution:**
   - `resolveSquadronManagement()` is 180 lines (economy_resolution.nim:202-382)
   - Searches through all fleets at colony to find squadrons
   - Error handling **during turn resolution** (too late for player feedback)

3. **Inconsistent with Ship Construction:**
   - Ships finish construction → commissioned pool (instant)
   - Form squadron from pool → **next turn**? Why delay?

4. **Duplicates FleetManagement Semantics:**
   - FleetManagement: Reorganize ships between fleets (instant)
   - SquadronManagement: Reorganize squadrons between fleets (next turn)
   - **Same operation, different timing models!**

### Impact on Player Experience

#### Current (Broken) Workflow

**Scenario:** Player wants to invade enemy colony

```
Turn N:   Load 5 marine regiments onto Fleet-Invasion
          (Submit CargoManagementOrder)
          *Turn resolves - troops loaded*

Turn N+1: Move Fleet-Invasion to Enemy-System-Alpha
          (Submit Move order)
          *Turn resolves - fleet moves*

Turn N+2: Invade planet
          (Submit Invade order)
          *Turn resolves - ground combat*

Total: 3 turns (2 administrative, 1 operational)
```

**Problems:**
- 33% of turns wasted on loading troops
- No immediate feedback on cargo availability
- Enemy sees fleet sitting at friendly colony (telegraph intent)
- Poor UX: "Why does loading trucks take a whole turn?"

#### Desired (Fixed) Workflow

**Scenario:** Same invasion operation

```
Order Submission Phase (Turn N):
  1. submitZeroTurnCommand(LoadCargo, 5 marines, Fleet-Invasion)
     → Instant result: "Loaded 5 marine regiments"
  2. submitZeroTurnCommand(MergeFleets, Fleet-Escort → Fleet-Invasion)
     → Instant result: "Merged 3 destroyers into Fleet-Invasion"
  3. submitOrderPacket(Move to Enemy-System-Alpha)

Turn N:   Fleet moves to enemy system
          *Turn resolves - fleet arrives*

Turn N+1: Invade planet
          (Submit Invade order)
          *Turn resolves - ground combat*

Total: 2 turns (0 administrative, 2 operational)
```

**Benefits:**
- ✅ 50% turn reduction (3 turns → 2 turns)
- ✅ Immediate validation feedback during submission
- ✅ No telegraph to enemy (fleet loads and leaves same turn)
- ✅ Matches player mental model: "Prepare forces, then deploy"

---

## Proposed Solution: Unified Zero-Turn Command System

### Design Principles

1. **Immediate Execution:** All zero-turn commands execute synchronously during order submission
2. **Administrative vs Operational:** Clear separation between preparation (instant) and strategy (turn-based)
3. **Fail-Fast Validation:** Errors detected immediately, not during turn resolution
4. **Location-Gated:** All operations require fleet/squadron at **friendly colony**
5. **Iterative Refinement:** Player can reorganize multiple times before submitting turn orders

### Core Types

```nim
# New unified command system
type
  ZeroTurnCommandType* {.pure.} = enum
    ## Administrative commands that execute immediately (0 turns)
    ## All require fleet/squadron to be at friendly colony
    ## Execute during order submission phase, NOT turn resolution

    # Fleet reorganization (current FleetManagementCommand)
    DetachShips        # Split ships from fleet → create new fleet
    TransferShips      # Move ships between existing fleets
    MergeFleets        # Merge entire source fleet into target fleet

    # Cargo operations (current CargoManagementOrder)
    LoadCargo          # Load marines/colonists onto spacelift ships
    UnloadCargo        # Unload cargo from spacelift ships

    # Squadron operations (current SquadronManagementOrder)
    FormSquadron       # Create squadron from commissioned ships
    TransferShipBetweenSquadrons  # Move individual ship between squadrons
    AssignSquadronToFleet         # Move squadron between fleets (or create new fleet)

  ZeroTurnCommand* = object
    ## Immediate-execution administrative command
    ## Executes synchronously during order submission (NOT in OrderPacket)
    ## Returns immediate result (success/failure + error message)
    houseId*: HouseId
    commandType*: ZeroTurnCommandType

    # Context (varies by command type)
    colonySystem*: Option[SystemId]      # Colony where action occurs (validation only)
    sourceFleetId*: Option[FleetId]      # Source fleet for fleet operations
    targetFleetId*: Option[FleetId]      # Target fleet for transfer/merge

    # Ship/squadron selection
    shipIndices*: seq[int]               # For ship selection (DetachShips, FormSquadron)
    sourceSquadronId*: Option[string]    # For TransferShipBetweenSquadrons
    targetSquadronId*: Option[string]    # For TransferShipBetweenSquadrons
    squadronId*: Option[string]          # For AssignSquadronToFleet
    shipIndex*: Option[int]              # For TransferShipBetweenSquadrons (single ship)

    # Cargo-specific
    cargoType*: Option[CargoType]        # Type: Marines, Colonists
    cargoQuantity*: Option[int]          # Amount to load/unload (0 = all available)

    # Squadron formation
    newSquadronId*: Option[string]       # Custom squadron ID for FormSquadron
    newFleetId*: Option[FleetId]         # Custom fleet ID for DetachShips/AssignSquadronToFleet

  ZeroTurnResult* = object
    ## Immediate result from zero-turn command execution
    success*: bool
    error*: string                       # Human-readable error message

    # Optional result data
    newFleetId*: Option[FleetId]         # For DetachShips, AssignSquadronToFleet
    newSquadronId*: Option[string]       # For FormSquadron
    cargoLoaded*: int                    # For LoadCargo (actual amount loaded)
    cargoUnloaded*: int                  # For UnloadCargo (actual amount unloaded)
```

### API Design

```nim
# Single unified entry point
proc submitZeroTurnCommand*(
  state: var GameState,
  cmd: ZeroTurnCommand
): ZeroTurnResult =
  ## Main entry point for zero-turn administrative commands
  ## Validates and executes command immediately (0 turns)
  ##
  ## Execution Flow:
  ##   1. Validate command (ownership, location, parameters)
  ##   2. Execute command (modify game state)
  ##   3. Return immediate result
  ##
  ## Returns:
  ##   ZeroTurnResult with success flag, error message, and optional result data
  ##
  ## Location Requirement:
  ##   All operations require fleet/squadron at friendly colony
  ##   Validation fails if not at colony or colony not owned by house

  # Step 1: Validate
  let validation = validateZeroTurnCommand(state, cmd)
  if not validation.valid:
    return ZeroTurnResult(success: false, error: validation.error)

  # Step 2: Execute based on command type
  case cmd.commandType
  of ZeroTurnCommandType.DetachShips:
    return executeDetachShips(state, cmd)
  of ZeroTurnCommandType.TransferShips:
    return executeTransferShips(state, cmd)
  of ZeroTurnCommandType.MergeFleets:
    return executeMergeFleets(state, cmd)
  of ZeroTurnCommandType.LoadCargo:
    return executeLoadCargo(state, cmd)
  of ZeroTurnCommandType.UnloadCargo:
    return executeUnloadCargo(state, cmd)
  of ZeroTurnCommandType.FormSquadron:
    return executeFormSquadron(state, cmd)
  of ZeroTurnCommandType.TransferShipBetweenSquadrons:
    return executeTransferShipBetweenSquadrons(state, cmd)
  of ZeroTurnCommandType.AssignSquadronToFleet:
    return executeAssignSquadronToFleet(state, cmd)
```

### Validation Strategy

All zero-turn commands share common validation requirements:

```nim
proc validateZeroTurnCommand*(state: GameState, cmd: ZeroTurnCommand): ValidationResult =
  ## Validate zero-turn command
  ## Common checks across all command types

  # 1. Validate house exists
  if cmd.houseId notin state.houses:
    return ValidationResult(valid: false, error: "House does not exist")

  # 2. Fleet operations: validate source fleet
  if cmd.commandType in {DetachShips, TransferShips, MergeFleets, LoadCargo, UnloadCargo}:
    if cmd.sourceFleetId.isNone or cmd.sourceFleetId.get() notin state.fleets:
      return ValidationResult(valid: false, error: "Source fleet not found")

    let fleet = state.fleets[cmd.sourceFleetId.get()]

    # Check ownership
    if fleet.owner != cmd.houseId:
      return ValidationResult(valid: false, error: "Fleet not owned by house")

    # CRITICAL: Fleet must be at friendly colony
    let colonyOpt = state.colonies.getOrDefault(fleet.location, nil)
    if colonyOpt.isNil:
      return ValidationResult(valid: false, error: "Fleet must be at a colony for zero-turn operations")

    if colonyOpt.owner != cmd.houseId:
      return ValidationResult(valid: false, error: "Fleet must be at a friendly colony")

  # 3. Squadron operations: validate colony and squadron
  if cmd.commandType in {FormSquadron, TransferShipBetweenSquadrons, AssignSquadronToFleet}:
    if cmd.colonySystem.isNone or cmd.colonySystem.get() notin state.colonies:
      return ValidationResult(valid: false, error: "Colony not found")

    let colony = state.colonies[cmd.colonySystem.get()]
    if colony.owner != cmd.houseId:
      return ValidationResult(valid: false, error: "Colony not owned by house")

  # 4. Command-specific validation
  case cmd.commandType
  of DetachShips, TransferShips:
    # Must specify ship indices
    if cmd.shipIndices.len == 0:
      return ValidationResult(valid: false, error: "Must select at least one ship")

    # Validate ship indices exist
    let fleet = state.fleets[cmd.sourceFleetId.get()]
    let allShips = fleet.getAllShips()
    for idx in cmd.shipIndices:
      if idx < 0 or idx >= allShips.len:
        return ValidationResult(valid: false, error: "Invalid ship index: " & $idx)

    # Cannot detach ALL ships (would leave empty fleet)
    if cmd.commandType == DetachShips and cmd.shipIndices.len == allShips.len:
      return ValidationResult(valid: false, error: "Cannot detach all ships (fleet would be empty)")

  of LoadCargo, UnloadCargo:
    # Must specify cargo type
    if cmd.cargoType.isNone:
      return ValidationResult(valid: false, error: "Must specify cargo type")

  of FormSquadron:
    # Must specify ships from commissioned pool
    if cmd.shipIndices.len == 0:
      return ValidationResult(valid: false, error: "Must select at least one ship for squadron")

  of TransferShipBetweenSquadrons:
    # Must specify source/target squadrons and ship index
    if cmd.sourceSquadronId.isNone or cmd.targetSquadronId.isNone or cmd.shipIndex.isNone:
      return ValidationResult(valid: false, error: "Must specify source squadron, target squadron, and ship index")

  of AssignSquadronToFleet:
    # Must specify squadron
    if cmd.squadronId.isNone:
      return ValidationResult(valid: false, error: "Must specify squadron ID")

  else:
    discard

  return ValidationResult(valid: true, error: "")
```

---

## Implementation Plan

### Phase 1: Create New Zero-Turn Command System

**Files to create:**
- `src/engine/commands/zero_turn_commands.nim` - Core implementation

**Implementation steps:**

1. **Define types** (based on design above):
   - `ZeroTurnCommandType` enum
   - `ZeroTurnCommand` object
   - `ZeroTurnResult` object

2. **Implement validation:**
   - `validateZeroTurnCommand()` - Common validation
   - Command-specific validation helpers

3. **Implement execution functions:**
   - `executeDetachShips()` - Copy from fleet_commands.nim:145-194
   - `executeTransferShips()` - Copy from fleet_commands.nim:201-247
   - `executeMergeFleets()` - Copy from fleet_commands.nim:254-288
   - `executeLoadCargo()` - Extract from economy_resolution.nim:409-490
   - `executeUnloadCargo()` - Extract from economy_resolution.nim:491-543
   - `executeFormSquadron()` - New implementation (commission pool → squadron)
   - `executeTransferShipBetweenSquadrons()` - Extract from economy_resolution.nim:216-291
   - `executeAssignSquadronToFleet()` - Extract from economy_resolution.nim:293-382

4. **Implement main API:**
   - `submitZeroTurnCommand()` - Entry point with validation + execution dispatch

### Phase 2: Remove Old Systems

**Files to modify:**

1. **`src/engine/orders.nim`:**
   - Remove `SquadronManagementAction` enum (line 16)
   - Remove `SquadronManagementOrder` object (lines 21-38)
   - Remove `CargoManagementAction` enum (line 40)
   - Remove `CargoManagementOrder` object (lines 45-52)
   - Remove `FleetManagementCommand` object (lines 61-78) - move to zero_turn_commands.nim
   - Remove from `OrderPacket`:
     - `squadronManagement*: seq[SquadronManagementOrder]` (line 105)
     - `cargoManagement*: seq[CargoManagementOrder]` (line 106)

2. **`src/engine/resolution/economy_resolution.nim`:**
   - Delete `resolveSquadronManagement()` (lines 202-382)
   - Delete `resolveCargoManagement()` (lines 384-543)

3. **`src/engine/resolve.nim`:**
   - Remove `resolveSquadronManagement()` call (lines 445-448)
   - Remove `resolveCargoManagement()` call (lines 450-453)

4. **`src/engine/commands/fleet_commands.nim`:**
   - Delete entire file (logic moved to zero_turn_commands.nim)

### Phase 3: Update Validation

**Files to modify:**

1. **`src/engine/orders.nim` - Remove validation:**
   - Delete squadron management validation (if exists)
   - Delete cargo management validation (if exists)

2. **Validation now happens in zero_turn_commands.nim:**
   - Synchronous during submission
   - Immediate feedback to player

### Phase 4: Update Tests

**Files to modify/create:**

1. **`tests/unit/test_zero_turn_commands.nim`** (new):
   - Test all command types
   - Test validation rules
   - Test error cases
   - Test colony requirement
   - Test ownership checks

2. **Update existing tests:**
   - `tests/unit/test_fleet_commands.nim` - Remove (replaced by test_zero_turn_commands.nim)
   - `tests/integration/test_cargo_loading.nim` - Update to use new API
   - Any tests that reference `SquadronManagementOrder` or `CargoManagementOrder`

### Phase 5: Update Documentation

**Files to modify:**

1. **`docs/specs/operations.md`:**
   - Add "Zero-Turn Administrative Commands" section
   - Document all command types
   - Clarify distinction from turn-based orders
   - Update player workflow examples

2. **`docs/architecture/dataflow.md`:**
   - Update order submission flow diagram
   - Show zero-turn commands executing before turn resolution

3. **`docs/specs/fleet-management.md`** (if exists):
   - Update to reference new unified system

---

## Migration Path for API Clients

### Before (Current - Fragmented APIs)

```nim
# Option 1: FleetManagementCommand (immediate)
let cmd = FleetManagementCommand(
  houseId: house1,
  sourceFleetId: fleet1,
  action: FleetManagementAction.DetachShips,
  shipIndices: @[0, 1, 2],
  newFleetId: some(fleet2)
)
let result = submitFleetManagementCommand(state, cmd)

# Option 2: CargoManagementOrder (next turn)
var packet = OrderPacket(houseId: house1, turn: 10)
packet.cargoManagement.add(CargoManagementOrder(
  houseId: house1,
  colonySystem: sys1,
  action: CargoManagementAction.LoadCargo,
  fleetId: fleet1,
  cargoType: some(CargoType.Marines),
  quantity: some(5)
))
submitOrderPacket(state, packet)

# Option 3: SquadronManagementOrder (next turn)
packet.squadronManagement.add(SquadronManagementOrder(
  houseId: house1,
  colonySystem: sys1,
  action: SquadronManagementAction.AssignToFleet,
  squadronId: some("squad-alpha"),
  targetFleetId: some(fleet1)
))
submitOrderPacket(state, packet)
```

### After (New - Unified API)

```nim
# All zero-turn commands use same API
let result1 = submitZeroTurnCommand(state, ZeroTurnCommand(
  houseId: house1,
  commandType: ZeroTurnCommandType.DetachShips,
  sourceFleetId: some(fleet1),
  shipIndices: @[0, 1, 2],
  newFleetId: some(fleet2)
))

let result2 = submitZeroTurnCommand(state, ZeroTurnCommand(
  houseId: house1,
  commandType: ZeroTurnCommandType.LoadCargo,
  sourceFleetId: some(fleet1),
  cargoType: some(CargoType.Marines),
  cargoQuantity: some(5)
))

let result3 = submitZeroTurnCommand(state, ZeroTurnCommand(
  houseId: house1,
  commandType: ZeroTurnCommandType.AssignSquadronToFleet,
  colonySystem: some(sys1),
  squadronId: some("squad-alpha"),
  targetFleetId: some(fleet1)
))

# All execute immediately, return instant results
if result1.success and result2.success and result3.success:
  # Now submit turn orders (fleet already prepared)
  let packet = OrderPacket(houseId: house1, turn: 10)
  packet.fleetOrders.add(FleetOrder(
    fleetId: fleet1,
    orderType: FleetOrderType.Move,
    targetSystem: some(enemySys)
  ))
  submitOrderPacket(state, packet)
```

---

## Benefits Summary

### For Players

1. **Turn Efficiency:**
   - No turns wasted on administrative tasks
   - Load cargo + move fleet = 1 turn (not 2)
   - Form squadrons + issue orders = 1 turn (not 2)

2. **Immediate Feedback:**
   - Know instantly if cargo loading succeeds
   - See validation errors during submission, not next turn
   - Can retry/adjust before committing turn

3. **Better Mental Model:**
   - "Prepare forces" (instant) vs "Execute strategy" (turn-based)
   - Matches military planning: logistics → operations
   - No confusion about what consumes turns

4. **Tactical Advantage:**
   - Don't telegraph intent (load + deploy same turn)
   - Enemy can't see "fleet sitting at colony loading troops"
   - Faster response to threats

### For Developers

1. **Architectural Consistency:**
   - All zero-turn operations use same pattern
   - Clear separation: administrative vs operational
   - One API to learn, not three

2. **Simpler Turn Resolution:**
   - Remove squadron management from resolution pipeline
   - Remove cargo management from resolution pipeline
   - Fewer edge cases during turn processing

3. **Better Error Handling:**
   - Validation during submission (synchronous)
   - No deferred errors during turn resolution
   - Easier to test (immediate results)

4. **Code Consolidation:**
   - ~400 lines removed from economy_resolution.nim
   - ~200 lines removed from resolve.nim
   - Fleet/squadron/cargo operations in single module

### Performance Impact

**Negligible:**
- Commands execute during submission phase (already synchronous)
- Same operations, just moved earlier in pipeline
- Validation complexity unchanged
- No additional database queries

---

## Technical Considerations

### Location Requirement: Why Friendly Colony?

All zero-turn commands require fleet/squadron at **friendly colony**:

```nim
# From fleet_commands.nim:50-65 (current validation)
# CRITICAL: Fleet must be at friendly colony
var colonyFound = false
var colonyOwner: HouseId = ""

for colony in state.colonies.values:
  if colony.systemId == sourceFleet.location:
    colonyFound = true
    colonyOwner = colony.owner
    break

if not colonyFound:
  return ValidationResult(valid: false, error: "Fleet must be at a colony")

if colonyOwner != cmd.houseId:
  return ValidationResult(valid: false, error: "Fleet must be at friendly colony")
```

**Rationale:**

1. **Logistics Infrastructure:**
   - Loading cargo requires port facilities
   - Ship transfers require dock space
   - Squadron formation requires maintenance bays

2. **Security:**
   - Can't reorganize fleets in enemy space
   - Can't access commissioning pools at neutral colonies
   - Prevents exploits (merge fleets mid-combat)

3. **Game Balance:**
   - Forces fleet concentration at colonies
   - Creates strategic chokepoints
   - Rewards territory control

### Interaction with Turn-Based Orders

**Key principle:** Zero-turn commands execute **before** turn orders are validated

**Sequence:**

```nim
# Order submission phase (Turn N)
1. submitZeroTurnCommand(DetachShips, ...)     # Instant execution
2. submitZeroTurnCommand(LoadCargo, ...)       # Instant execution
3. submitZeroTurnCommand(MergeFleets, ...)     # Instant execution
4. submitOrderPacket(...)                      # Queued for validation

# Turn validation phase
5. validateOrderPacket(...)                    # Uses state AFTER zero-turn commands

# Turn resolution (Turn N)
6. resolveTurn(...)                            # Processes OrderPacket
```

**Example:**

```nim
# Turn N submission:
submitZeroTurnCommand(DetachShips, fleet1, ships=[0,1] → fleet2)  # Instant
submitOrderPacket(
  fleet1: Move to SystemA,  # Moves fleet1 (now has fewer ships)
  fleet2: Move to SystemB   # Moves fleet2 (newly created)
)

# Both fleets move same turn (1 turn total, not 2)
```

### Edge Cases

#### Case 1: Fleet Dissolution

**Scenario:** Transfer all non-flagship ships from fleet

```nim
submitZeroTurnCommand(TransferShips, fleet1 → fleet2, ships=[all escorts])
# Result: fleet1 has only flagship, still valid
# Can still issue orders to fleet1 (single-ship fleet)
```

**Validation:** Must keep at least 1 squadron (flagship counts)

#### Case 2: Cargo Capacity Overflow

**Scenario:** Load more cargo than ships can carry

```nim
submitZeroTurnCommand(LoadCargo, 10 marines, Fleet-Alpha)
# Fleet-Alpha can only carry 6 marines
# Result: cargoLoaded = 6, 4 marines remain at colony
```

**Behavior:** Load as much as possible, return actual amount loaded

#### Case 3: Colony Under Siege

**Scenario:** Friendly colony blockaded by enemy fleet

```nim
submitZeroTurnCommand(LoadCargo, 5 marines, Fleet-Defense)
# Fleet-Defense is at friendly colony (player owns)
# Enemy fleet also present (blockade)
```

**Decision:** **Allow** zero-turn commands during blockade

**Rationale:**
- Colony still friendly (player controls)
- Blockade affects **movement**, not **logistics**
- Defending fleet should be able to prepare
- Attacker has advantage (first strike in combat)

#### Case 4: Commissioned Ships Mid-Turn

**Scenario:** Ships complete construction during turn resolution

```nim
# Turn N: Submit build order for 2 destroyers
# Turn N+2: Ships complete, added to commissioned pool
# Turn N+2 submission: Can form squadron immediately?
```

**Answer:** **Yes** - commissioned ships available immediately after turn resolution

**Flow:**
```
Turn N+2 resolves → ships commissioned → commissioning pool updated
Player sees update → submits FormSquadron command → instant execution
Player submits turn orders with new squadron → Turn N+3 processes
```

---

## Risks and Mitigations

### Risk 1: Breaking Existing Game State

**Risk:** Old save games have `CargoManagementOrder` in OrderPacket

**Mitigation:**
- Add migration code to strip deprecated order types
- Log warning if old order types detected
- Documentation: "Save games from v1.x may lose pending cargo orders"

### Risk 2: Client Code Breakage

**Risk:** Existing API clients use `CargoManagementOrder` / `SquadronManagementOrder`

**Mitigation:**
- Provide adapter functions for backward compatibility:
  ```nim
  proc submitCargoManagement*(state: var GameState, order: CargoManagementOrder): ZeroTurnResult {.deprecated.} =
    ## DEPRECATED: Use submitZeroTurnCommand(ZeroTurnCommandType.LoadCargo) instead
    let cmd = ZeroTurnCommand(
      houseId: order.houseId,
      commandType: if order.action == LoadCargo: ZeroTurnCommandType.LoadCargo else: ZeroTurnCommandType.UnloadCargo,
      sourceFleetId: some(order.fleetId),
      cargoType: order.cargoType,
      cargoQuantity: order.quantity
    )
    return submitZeroTurnCommand(state, cmd)
  ```
- Deprecation warnings in logs
- Remove adapters after 2-3 releases

### Risk 3: Performance Impact

**Risk:** Immediate execution could slow down order submission

**Mitigation:**
- Benchmark current fleet_commands.nim execution time (already immediate)
- All operations are O(n) where n = ships in fleet (small)
- No database queries, all in-memory
- Expected: <1ms per command on typical hardware

### Risk 4: Validation Bypass

**Risk:** Player submits zero-turn commands AFTER submitting OrderPacket

**Mitigation:**
- Client enforces workflow: zero-turn → order packet
- Server validates: OrderPacket submission locks out zero-turn commands
- State machine: `OrderSubmissionPhase` → `TurnResolutionPhase`

---

## Success Metrics

### Before Implementation

**Measure baseline:**
1. Average turns spent on cargo loading per game
2. Average turns spent on squadron management per game
3. Player feedback: "Most frustrating administrative task"

### After Implementation

**Target improvements:**
1. Zero turns spent on cargo loading (instant)
2. Zero turns spent on squadron management (instant)
3. Player satisfaction survey: "+50% satisfaction with fleet management"

**Code metrics:**
- `-600 lines` from resolution pipeline (economy_resolution.nim, resolve.nim)
- `+400 lines` in zero_turn_commands.nim (net: -200 lines)
- `-3 order types` in OrderPacket (simpler validation)

---

## Open Questions

### Q1: Should zero-turn commands have PP cost?

**Context:** Some operations may consume resources (e.g., FormSquadron pays commissioning cost)

**Options:**
- **A)** All zero-turn commands are free (administrative)
- **B)** Some commands cost PP (FormSquadron, LoadCargo if requires supply purchase)
- **C)** All cargo operations free, squadron operations cost PP

**Recommendation:** **Option A** - all free

**Rationale:**
- Commissioning costs already paid during construction
- Cargo (marines/colonists) already exist at colony
- Zero-turn = reorganization, not production
- Keeps API simple (no treasury validation)

### Q2: Should zero-turn commands be logged/visible to enemy?

**Context:** Intelligence system may detect operations at colonies

**Options:**
- **A)** Zero-turn commands invisible (no intel reports)
- **B)** Visible only if enemy has spy at colony
- **C)** Always visible via intelligence reports (delayed 1 turn)

**Recommendation:** **Option B** - visible only with spy present

**Rationale:**
- Matches existing intel system (spies detect fleet activity)
- Rewards intelligence investment
- Balance: instant execution, but not invisible
- Cargo loading = visible ship activity (loading docks busy)

### Q3: Limit on zero-turn commands per turn?

**Context:** Player could submit 100 commands, reorganize entire empire instantly

**Options:**
- **A)** Unlimited commands
- **B)** Limit per fleet (e.g., 5 commands per fleet)
- **C)** Limit per house (e.g., 20 commands total)

**Recommendation:** **Option A** - unlimited

**Rationale:**
- Administrative tasks shouldn't be artificially gated
- Player can already do this with FleetManagementCommand (no limit)
- Complexity of managing many commands is self-limiting
- If abused, add rate limit later (YAGNI principle)

---

## Conclusion

The current split between FleetManagementCommand (immediate), CargoManagementOrder (delayed), and SquadronManagementOrder (delayed) creates architectural inconsistency and poor player experience.

**Proposed solution:** Consolidate all zero-turn administrative operations into unified `ZeroTurnCommand` system that executes immediately during order submission.

**Key benefits:**
- ✅ Consistent architecture (all zero-turn ops same pattern)
- ✅ Better player UX (load + move = 1 turn, not 2)
- ✅ Immediate validation feedback (fail-fast)
- ✅ Simpler codebase (-200 lines, cleaner resolution pipeline)

**Next steps:**
1. Review and approve design
2. Implement Phase 1 (new system)
3. Implement Phase 2 (remove old systems)
4. Update tests and documentation
5. Migrate API clients

**Estimated effort:** 2-3 days implementation + 1 day testing + 1 day documentation

---

## References

### Current Implementation Files

- `src/engine/commands/fleet_commands.nim` - FleetManagementCommand (correct architecture)
- `src/engine/orders.nim:16-52` - SquadronManagementOrder, CargoManagementOrder (incorrect)
- `src/engine/resolution/economy_resolution.nim:202-543` - Resolution logic (to be removed)
- `src/engine/resolve.nim:445-453` - Resolution calls (to be removed)

### Related Documentation

- `docs/specs/operations.md` - Fleet orders specification
- `docs/architecture/dataflow.md` - Turn resolution flow
- `docs/specs/economy.md` - Construction/commissioning pipeline

### Design Discussions

- 2025-12-02: User identifies cargo loading inefficiency: "load troops if available. zero turns. this would allow to load troops and then send ships on a mission right away."
- 2025-12-02: Analysis of FleetManagementCommand vs CargoManagementOrder inconsistency
- 2025-12-02: Architectural decision: consolidate all zero-turn operations

---

**Document Status:** Ready for Review
**Implementation Status:** Not Started
**Blocker Status:** None - can implement immediately after approval
