# Zero-Turn Command System

**Purpose:** Instant fleet logistics and administrative commands that execute during the order submission window (CMD5), not during turn resolution.

**Key Principle:** Zero-turn commands modify state immediately when submitted, before operational orders are queued.

---

## Command Types (9)

| Command | Category | Description |
|---------|----------|-------------|
| DetachShips | Fleet Org | Split ships from fleet to create new fleet |
| TransferShips | Fleet Org | Move ships between fleets at same location |
| MergeFleets | Fleet Org | Merge entire fleet into target fleet |
| LoadCargo | Logistics | Load marines/colonists onto transports |
| UnloadCargo | Logistics | Unload cargo at colony |
| LoadFighters | Hangar Ops | Load fighters from colony onto carrier |
| UnloadFighters | Hangar Ops | Unload fighters from carrier to colony |
| TransferFighters | Hangar Ops | Transfer fighters between carriers |
| Reactivate | Status | Return Reserve/Mothballed fleet to Active |

---

## Location Requirements

Zero-turn commands have different location requirements based on whether they involve colony resources:

### Requires Friendly Colony

These commands interact with colony infrastructure or resources:

| Command | Reason |
|---------|--------|
| LoadCargo | Colony is source of marines/colonists |
| UnloadCargo | Colony is destination for cargo |
| LoadFighters | Colony fighter pool is source |
| UnloadFighters | Colony receives fighters |
| Reactivate | Needs facilities for crew/refit |

**Validation:** Fleet must be at a system with a colony owned by the same house.

### Same Location Only (No Colony Required)

These commands only require fleets to be in the same system:

| Command | Reason |
|---------|--------|
| DetachShips | Administrative ship reassignment |
| TransferShips | Administrative ship transfer between fleets |
| MergeFleets | Administrative fleet combination |
| TransferFighters | Carrier-to-carrier shuttle in space |

**Validation:** Fleets must be at the same system (no colony infrastructure needed).

---

## Execution Model

### Execution Flow

```
Player submits CommandPacket
    │
    ├── Zero-turn commands extracted
    │       │
    │       ├── Validate each command
    │       ├── Execute sequentially (state modified immediately)
    │       └── Return ZeroTurnResult (success/failure)
    │
    └── Operational orders queued for turn resolution
```

### Client/Server Model

**Server-Side (Authoritative):**
- `submitZeroTurnCommand(state: var GameState, cmd, events)` in `logistics.nim`
- Modifies authoritative `GameState`
- Emits `GameEvent`s for telemetry/audit

**Client-Side (Preview):**
- Zero-turn commands can be simulated on `PlayerState` for UI preview
- Final execution always happens server-side
- Client submits `ZeroTurnCommand` in `CommandPacket`

---

## API Reference

### Types

```nim
type
  ZeroTurnCommandType* {.pure.} = enum
    DetachShips, TransferShips, MergeFleets,
    LoadCargo, UnloadCargo,
    LoadFighters, UnloadFighters, TransferFighters,
    Reactivate

  ZeroTurnCommand* = object
    houseId*: HouseId
    commandType*: ZeroTurnCommandType
    sourceFleetId*: Option[FleetId]
    targetFleetId*: Option[FleetId]
    shipIndices*: seq[int]           # For DetachShips/TransferShips
    cargoType*: Option[CargoClass]   # For LoadCargo
    cargoQuantity*: Option[int]      # For LoadCargo (0 = all available)
    carrierShipId*: Option[ShipId]   # For Load/UnloadFighters
    sourceCarrierShipId*: Option[ShipId]  # For TransferFighters
    targetCarrierShipId*: Option[ShipId]  # For TransferFighters
    fighterIds*: seq[ShipId]         # For fighter operations

  ZeroTurnResult* = object
    success*: bool
    error*: string
    newFleetId*: Option[FleetId]     # For DetachShips
    cargoLoaded*: int32              # For LoadCargo
    cargoUnloaded*: int32            # For UnloadCargo
    fightersLoaded*: int32           # For LoadFighters
    fightersUnloaded*: int32         # For UnloadFighters
    fightersTransferred*: int32      # For TransferFighters
    warnings*: seq[string]
```

### Entry Point

```nim
proc submitZeroTurnCommand*(
    state: var GameState,
    cmd: ZeroTurnCommand,
    events: var seq[GameEvent]
): ZeroTurnResult
```

**Validation:** Multi-layer validation strategy:
- Layer 1: Basic validation (house exists)
- Layer 2a: Colony-required commands (validate fleet at friendly colony)
- Layer 2b: Same-location commands (validate fleet ownership only)
- Layer 3: Command-specific validation (ship indices, cargo types, etc.)

---

## Command Details

### DetachShips

**Purpose:** Split ships from source fleet to create new fleet at same location.

**Parameters:**
- `sourceFleetId` - Fleet to detach from
- `shipIndices` - Indices of ships to detach (0-based)

**Result:**
- `newFleetId` - ID of newly created fleet
- Source fleet remains with remaining ships

**Validation:**
- Cannot detach all ships (would leave source empty)
- Cannot detach non-ETAC transports without combat escorts
- Ship indices must be valid

**Location:** Anywhere (no colony required)

---

### TransferShips

**Purpose:** Move ships from source fleet to target fleet at same location.

**Parameters:**
- `sourceFleetId` - Fleet to transfer from
- `targetFleetId` - Fleet to transfer to
- `shipIndices` - Indices of ships to transfer (0-based)

**Result:**
- Source fleet updated (or deleted if empty)
- Target fleet gains ships

**Validation:**
- Both fleets must be at same location
- Cannot mix scouts with combat fleets
- Ship indices must be valid

**Location:** Anywhere (no colony required)

---

### MergeFleets

**Purpose:** Merge entire source fleet into target fleet.

**Parameters:**
- `sourceFleetId` - Fleet to merge (will be deleted)
- `targetFleetId` - Fleet to merge into

**Result:**
- Source fleet deleted
- Target fleet gains all ships from source

**Validation:**
- Both fleets must be at same location
- Cannot mix scouts with combat fleets
- Cannot merge fleet into itself

**Location:** Anywhere (no colony required)

---

### LoadCargo

**Purpose:** Load marines or colonists from colony onto transport ships.

**Parameters:**
- `sourceFleetId` - Fleet with transports
- `cargoType` - Marines or Colonists
- `cargoQuantity` - Number to load (0 = all available)

**Result:**
- `cargoLoaded` - Number of units loaded
- Colony inventory reduced
- Transport cargo holds filled

**Validation:**
- Colony must have available cargo
- Fleet must have compatible transport ships (TroopTransport for Marines, ETAC for Colonists)
- Colonists: Must leave minimum 1 PU at source colony

**Location:** Friendly colony required

---

### UnloadCargo

**Purpose:** Unload cargo from transport ships to colony.

**Parameters:**
- `sourceFleetId` - Fleet with loaded transports

**Result:**
- `cargoUnloaded` - Number of units unloaded
- Colony inventory increased
- Transport cargo holds emptied

**Validation:**
- Fleet must have cargo to unload

**Location:** Friendly colony required

---

### LoadFighters

**Purpose:** Load fighter ships from colony onto carrier.

**Parameters:**
- `sourceFleetId` - Fleet containing carrier
- `carrierShipId` - Carrier ship to load onto
- `fighterIds` - Fighter IDs to load from colony

**Result:**
- `fightersLoaded` - Number of fighters loaded
- Colony fighter pool reduced
- Carrier hangar filled

**Validation:**
- Carrier must have hangar capacity
- Fighters must exist at colony
- Carrier capacity based on ship class and ACO tech level

**Location:** Friendly colony required

---

### UnloadFighters

**Purpose:** Unload fighter ships from carrier to colony.

**Parameters:**
- `sourceFleetId` - Fleet containing carrier
- `carrierShipId` - Carrier ship to unload from
- `fighterIds` - Fighter IDs to unload

**Result:**
- `fightersUnloaded` - Number of fighters unloaded
- Colony fighter pool increased
- Carrier hangar emptied

**Validation:**
- Fighters must be embarked on specified carrier

**Location:** Friendly colony required

---

### TransferFighters

**Purpose:** Transfer fighter ships between carriers (can happen in deep space).

**Parameters:**
- `sourceFleetId` - Fleet containing source carrier (for ownership check)
- `sourceCarrierShipId` - Carrier to transfer from
- `targetCarrierShipId` - Carrier to transfer to
- `fighterIds` - Fighter IDs to transfer

**Result:**
- `fightersTransferred` - Number of fighters transferred
- Source carrier hangar reduced
- Target carrier hangar increased

**Validation:**
- Both carriers must be at same location
- Both carriers must be owned by same house
- Target carrier must have hangar capacity
- Fighters must be embarked on source carrier

**Location:** Anywhere (no colony required) - carriers shuttle fighters in space

---

### Reactivate

**Purpose:** Return Reserve or Mothballed fleet to Active status instantly.

**Parameters:**
- `sourceFleetId` - Fleet to reactivate

**Result:**
- Fleet status → Active
- Fleet command → Hold (ready for new orders)
- 100% maintenance and CC costs resume

**Validation:**
- Fleet must be Reserve or Mothballed (not already Active)

**Location:** Friendly colony required (needs crew/supplies/refit)

---

## Events (Server-Side Only)

Zero-turn commands emit `GameEvent`s for telemetry and audit:
- `FleetDetachment` - Ships detached to new fleet
- `FleetTransfer` - Ships transferred between fleets
- `FleetMerged` - Fleet merged into another
- `CargoLoaded` - Cargo loaded onto transports
- `CargoUnloaded` - Cargo unloaded at colony

**Note:** Events are generated server-side only. Clients receive `ZeroTurnResult` for immediate feedback; events are for the server's turn log.

---

## Example Usage

### Scenario: Reorganize Invasion Fleet

Player has two fleets at Colony Alpha:
- Fleet A: 5 Destroyers, 2 Troop Transports (empty)
- Fleet B: 3 Cruisers, 1 ETAC (empty)

**Goal:** Create combined invasion fleet with ground forces.

**Commands submitted:**
1. `LoadCargo` - Load 10 Marines from Colony Alpha onto Fleet A transports
2. `LoadCargo` - Load 2 PTU colonists from Colony Alpha onto Fleet B ETAC
3. `MergeFleets` - Merge Fleet B into Fleet A
4. `DetachShips` - Detach ETAC from merged fleet to create new colonization fleet

**Result:**
- Fleet A: 5 Destroyers, 3 Cruisers, 2 Troop Transports (10 Marines)
- Fleet C (new): 1 ETAC (2 PTU colonists)
- All commands execute instantly, ready to submit operational orders (Move, Invade, etc.)

---

## Related Documentation

- [Turn Cycle](ec4x_canonical_turn_cycle.md) - CMD5 submission window
- [Orders](orders.md) - Order system overview
- [Operations Spec](../specs/06-operations.md) - Section 6.4 zero-turn commands
- [Dataflow](../architecture/dataflow.md) - Section 5 zero-turn flow
- [Implementation](../../../src/engine/systems/fleet/logistics.nim) - Source code
