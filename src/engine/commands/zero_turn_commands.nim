## Zero-Turn Command System for EC4X
##
## Unified administrative command system for fleet/cargo/squadron operations
## Execute immediately during order submission (0 turns, at friendly colonies)
##
## Architecture:
## - Consolidates FleetManagementCommand, CargoManagementOrder, SquadronManagementOrder
## - Separate from OrderPacket system (NOT queued for turn resolution)
## - Execute synchronously during order submission phase
## - Only available at friendly colonies (logistics infrastructure requirement)
## - Follows DRY principles with shared validation and cleanup helpers
##
## Usage:
##   let cmd = ZeroTurnCommand(...)
##   let result = submitZeroTurnCommand(state, cmd)
##   if result.success: echo "Success!"

import ../gamestate
import ../fleet
import ../squadron
import ../spacelift
import ../../common/types/[core, combat]
import ../config/population_config  # For population config (soulsPerPtu, ptuSizeMillions)
import ../logger
import std/[options, algorithm, tables, strformat]

# ============================================================================
# Type Definitions
# ============================================================================

type
  ZeroTurnCommandType* {.pure.} = enum
    ## Administrative commands that execute immediately (0 turns)
    ## All require fleet/squadron to be at friendly colony
    ## Execute during order submission phase, NOT turn resolution

    # Fleet reorganization (from FleetManagementCommand)
    DetachShips        ## Split ships from fleet → create new fleet
    TransferShips      ## Move ships between existing fleets
    MergeFleets        ## Merge entire source fleet into target fleet

    # Cargo operations (from CargoManagementOrder)
    LoadCargo          ## Load marines/colonists onto spacelift ships
    UnloadCargo        ## Unload cargo from spacelift ships

    # Squadron operations (from SquadronManagementOrder)
    FormSquadron       ## Create squadron from commissioned ships pool
    TransferShipBetweenSquadrons  ## Move individual ship between squadrons
    AssignSquadronToFleet         ## Move squadron between fleets (or create new fleet)

  ZeroTurnCommand* = object
    ## Immediate-execution administrative command
    ## Executes synchronously during order submission (NOT in OrderPacket)
    ## Returns immediate result (success/failure + error message)
    houseId*: HouseId
    commandType*: ZeroTurnCommandType

    # Context (varies by command type)
    colonySystem*: Option[SystemId]      ## Colony where action occurs (for squadron ops)
    sourceFleetId*: Option[FleetId]      ## Source fleet for fleet/cargo operations
    targetFleetId*: Option[FleetId]      ## Target fleet for transfer/merge

    # Ship/squadron selection
    shipIndices*: seq[int]               ## For ship selection (DetachShips, FormSquadron)
    sourceSquadronId*: Option[string]    ## For TransferShipBetweenSquadrons
    targetSquadronId*: Option[string]    ## For TransferShipBetweenSquadrons
    squadronId*: Option[string]          ## For AssignSquadronToFleet
    shipIndex*: Option[int]              ## For TransferShipBetweenSquadrons (single ship)

    # Cargo-specific
    cargoType*: Option[CargoType]        ## Type: Marines, Colonists
    cargoQuantity*: Option[int]          ## Amount to load/unload (0 = all available)

    # Squadron formation
    newSquadronId*: Option[string]       ## Custom squadron ID for FormSquadron
    newFleetId*: Option[FleetId]         ## Custom fleet ID for DetachShips/AssignSquadronToFleet

  ZeroTurnResult* = object
    ## Immediate result from zero-turn command execution
    success*: bool
    error*: string                       ## Human-readable error message

    # Optional result data
    newFleetId*: Option[FleetId]         ## For DetachShips, AssignSquadronToFleet
    newSquadronId*: Option[string]       ## For FormSquadron
    cargoLoaded*: int                    ## For LoadCargo (actual amount loaded)
    cargoUnloaded*: int                  ## For UnloadCargo (actual amount unloaded)
    warnings*: seq[string]               ## Non-fatal issues

  ValidationResult* = object
    ## Validation result (used internally)
    valid*: bool
    error*: string

# ============================================================================
# Shared Validation Helpers (DRY)
# ============================================================================

proc validateOwnership*(state: GameState, houseId: HouseId): ValidationResult =
  ## DRY: Validate house exists
  if houseId notin state.houses:
    return ValidationResult(valid: false, error: "House does not exist")
  return ValidationResult(valid: true, error: "")

proc validateFleetAtFriendlyColony*(state: GameState, fleetId: FleetId, houseId: HouseId): ValidationResult =
  ## DRY: Validate fleet exists, is owned by house, and is at friendly colony
  ## CRITICAL: All zero-turn fleet/cargo operations require friendly colony

  # 1. Check fleet exists
  if not state.fleets.hasKey(fleetId):
    return ValidationResult(valid: false, error: "Fleet not found")

  let fleet = state.fleets[fleetId]

  # 2. Check ownership
  if fleet.owner != houseId:
    return ValidationResult(valid: false, error: "Fleet not owned by house")

  # 3. CRITICAL: Fleet must be at friendly colony
  var colonyFound = false
  var colonyOwner: HouseId = ""

  for colony in state.colonies.values:
    if colony.systemId == fleet.location:
      colonyFound = true
      colonyOwner = colony.owner
      break

  if not colonyFound:
    return ValidationResult(valid: false, error: "Fleet must be at a colony for zero-turn operations")

  if colonyOwner != houseId:
    return ValidationResult(valid: false, error: "Fleet must be at a friendly colony for zero-turn operations")

  return ValidationResult(valid: true, error: "")

proc validateColonyOwnership*(state: GameState, systemId: SystemId, houseId: HouseId): ValidationResult =
  ## DRY: Validate colony exists and is owned by house

  if systemId notin state.colonies:
    return ValidationResult(valid: false, error: "Colony not found")

  let colony = state.colonies[systemId]
  if colony.owner != houseId:
    return ValidationResult(valid: false, error: "Colony not owned by house")

  return ValidationResult(valid: true, error: "")

proc validateShipIndices*(fleet: Fleet, indices: seq[int]): ValidationResult =
  ## DRY: Validate ship indices are valid and not selecting all ships

  let allShips = fleet.getAllShips()

  # Must select at least one ship
  if indices.len == 0:
    return ValidationResult(valid: false, error: "Must select at least one ship")

  # Validate each index
  for idx in indices:
    if idx < 0 or idx >= allShips.len:
      return ValidationResult(valid: false, error: "Invalid ship index: " & $idx)

  # Check for duplicate indices
  var seenIndices: seq[int] = @[]
  for idx in indices:
    if idx in seenIndices:
      return ValidationResult(valid: false, error: "Duplicate ship index: " & $idx)
    seenIndices.add(idx)

  return ValidationResult(valid: true, error: "")

# ============================================================================
# Main Validation Dispatcher
# ============================================================================

proc validateZeroTurnCommand*(state: GameState, cmd: ZeroTurnCommand): ValidationResult =
  ## Validate zero-turn command
  ## Multi-layer validation strategy:
  ##   Layer 1: Basic validation (house exists)
  ##   Layer 2: Fleet operations validation (ownership, location)
  ##   Layer 3: Squadron operations validation (colony ownership)
  ##   Layer 4: Command-specific validation

  # Layer 1: Basic validation
  var result = validateOwnership(state, cmd.houseId)
  if not result.valid:
    return result

  # Layer 2: Fleet operations validation
  if cmd.commandType in {ZeroTurnCommandType.DetachShips, ZeroTurnCommandType.TransferShips,
                         ZeroTurnCommandType.MergeFleets, ZeroTurnCommandType.LoadCargo,
                         ZeroTurnCommandType.UnloadCargo}:
    if cmd.sourceFleetId.isNone:
      return ValidationResult(valid: false, error: "Source fleet ID required")

    result = validateFleetAtFriendlyColony(state, cmd.sourceFleetId.get(), cmd.houseId)
    if not result.valid:
      return result

  # Layer 3: Squadron operations validation
  if cmd.commandType in {ZeroTurnCommandType.FormSquadron, ZeroTurnCommandType.TransferShipBetweenSquadrons,
                         ZeroTurnCommandType.AssignSquadronToFleet}:
    if cmd.colonySystem.isNone:
      return ValidationResult(valid: false, error: "Colony system required for squadron operations")

    result = validateColonyOwnership(state, cmd.colonySystem.get(), cmd.houseId)
    if not result.valid:
      return result

  # Layer 4: Command-specific validation
  case cmd.commandType
  of ZeroTurnCommandType.DetachShips, ZeroTurnCommandType.TransferShips:
    # Validate ship indices
    let fleet = state.fleets[cmd.sourceFleetId.get()]
    result = validateShipIndices(fleet, cmd.shipIndices)
    if not result.valid:
      return result

    # DetachShips specific: cannot detach spacelift-only fleet
    if cmd.commandType == ZeroTurnCommandType.DetachShips:
      let (squadronIndices, spaceliftIndices) = fleet.translateShipIndicesToSquadrons(cmd.shipIndices)
      if squadronIndices.len == 0 and spaceliftIndices.len > 0:
        return ValidationResult(valid: false, error: "Cannot detach spacelift ships without combat escorts")

    # TransferShips specific: validate target fleet
    if cmd.commandType == ZeroTurnCommandType.TransferShips:
      if cmd.targetFleetId.isNone:
        return ValidationResult(valid: false, error: "Target fleet ID required for transfer")

      let targetFleetId = cmd.targetFleetId.get()
      if not state.fleets.hasKey(targetFleetId):
        return ValidationResult(valid: false, error: "Target fleet not found")

      let targetFleet = state.fleets[targetFleetId]
      if targetFleet.owner != cmd.houseId:
        return ValidationResult(valid: false, error: "Target fleet not owned by house")

      let sourceFleet = state.fleets[cmd.sourceFleetId.get()]
      if targetFleet.location != sourceFleet.location:
        return ValidationResult(valid: false, error: "Both fleets must be at same location")

  of ZeroTurnCommandType.MergeFleets:
    # Validate target fleet
    if cmd.targetFleetId.isNone:
      return ValidationResult(valid: false, error: "Target fleet ID required for merge")

    let targetFleetId = cmd.targetFleetId.get()
    if not state.fleets.hasKey(targetFleetId):
      return ValidationResult(valid: false, error: "Target fleet not found")

    let targetFleet = state.fleets[targetFleetId]
    if targetFleet.owner != cmd.houseId:
      return ValidationResult(valid: false, error: "Target fleet not owned by house")

    let sourceFleet = state.fleets[cmd.sourceFleetId.get()]
    if targetFleet.location != sourceFleet.location:
      return ValidationResult(valid: false, error: "Both fleets must be at same location")

    # Cannot merge fleet into itself
    if cmd.sourceFleetId.get() == targetFleetId:
      return ValidationResult(valid: false, error: "Cannot merge fleet into itself")

  of ZeroTurnCommandType.LoadCargo, ZeroTurnCommandType.UnloadCargo:
    # Validate cargo type specified for LoadCargo
    if cmd.commandType == ZeroTurnCommandType.LoadCargo:
      if cmd.cargoType.isNone:
        return ValidationResult(valid: false, error: "Cargo type required for LoadCargo")

  of ZeroTurnCommandType.FormSquadron:
    # Must specify ships from commissioned pool
    if cmd.shipIndices.len == 0:
      return ValidationResult(valid: false, error: "Must select at least one ship for squadron")

  of ZeroTurnCommandType.TransferShipBetweenSquadrons:
    # Must specify source/target squadrons and ship index
    if cmd.sourceSquadronId.isNone or cmd.targetSquadronId.isNone or cmd.shipIndex.isNone:
      return ValidationResult(valid: false, error: "Must specify source squadron, target squadron, and ship index")

  of ZeroTurnCommandType.AssignSquadronToFleet:
    # Must specify squadron
    if cmd.squadronId.isNone:
      return ValidationResult(valid: false, error: "Must specify squadron ID")

  return ValidationResult(valid: true, error: "")

# ============================================================================
# Shared Cleanup Helper (DRY)
# ============================================================================

proc cleanupEmptyFleet*(state: var GameState, fleetId: FleetId) =
  ## DRY: Remove fleet and cleanup all associated orders
  ## Used by TransferShips, MergeFleets, AssignSquadronToFleet, DetachShips
  ## NOTE: Caller must ensure fleet should be deleted (this doesn't check isEmpty)
  if fleetId in state.fleets:
    state.fleets.del(fleetId)
    if fleetId in state.fleetOrders:
      state.fleetOrders.del(fleetId)
    if fleetId in state.standingOrders:
      state.standingOrders.del(fleetId)
    logInfo(LogCategory.lcFleet, &"Removed fleet {fleetId} and associated orders")

# ============================================================================
# Execution - Fleet Operations (from fleet_commands.nim)
# ============================================================================

proc executeDetachShips*(state: var GameState, cmd: ZeroTurnCommand): ZeroTurnResult =
  ## Split ships from source fleet to create new fleet
  ## Both fleets remain at same location

  # Get source fleet (CRITICAL: Table copy semantics - get-modify-write)
  var sourceFleet = state.fleets[cmd.sourceFleetId.get()]

  # Translate ship indices to squadron/spacelift indices
  let (squadronIndices, spaceliftIndices) = sourceFleet.translateShipIndicesToSquadrons(cmd.shipIndices)

  # Split squadrons (existing proc)
  let splitResult = sourceFleet.split(squadronIndices)

  # Split spacelift ships
  var newSpaceLiftShips: seq[SpaceLiftShip] = @[]
  # Sort indices in descending order to avoid index shifting issues
  for idx in spaceliftIndices.sorted(Descending):
    newSpaceLiftShips.add(sourceFleet.spaceLiftShips[idx])
    sourceFleet.spaceLiftShips.delete(idx)

  # Generate new fleet ID if not provided
  let newFleetId = if cmd.newFleetId.isSome:
    cmd.newFleetId.get()
  else:
    cmd.houseId & "_fleet_" & $state.turn & "_" & $state.fleets.len

  # Create new fleet
  var newFleet = Fleet(
    id: newFleetId,
    squadrons: splitResult.squadrons,
    spaceLiftShips: newSpaceLiftShips,
    owner: cmd.houseId,
    location: sourceFleet.location,
    status: FleetStatus.Active,
    autoBalanceSquadrons: true
  )

  # Balance squadrons in BOTH fleets
  sourceFleet.balanceSquadrons()
  newFleet.balanceSquadrons()

  # Check if source fleet is now empty after detaching
  if sourceFleet.isEmpty():
    # Delete empty source fleet and cleanup orders
    cleanupEmptyFleet(state, cmd.sourceFleetId.get())
    logInfo(LogCategory.lcFleet, &"DetachShips: Detached all ships from {cmd.sourceFleetId.get()}, deleted source fleet, created new fleet {newFleetId}")
  else:
    # Write back modified source fleet
    state.fleets[cmd.sourceFleetId.get()] = sourceFleet
    logInfo(LogCategory.lcFleet, &"DetachShips: Created fleet {newFleetId} with {newFleet.squadrons.len} squadrons and {newFleet.spaceLiftShips.len} spacelift ships")

  # Write new fleet to state
  state.fleets[newFleetId] = newFleet

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: some(newFleetId),
    newSquadronId: none(string),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings: @[]
  )

proc executeTransferShips*(state: var GameState, cmd: ZeroTurnCommand): ZeroTurnResult =
  ## Move ships from source fleet to target fleet
  ## If source becomes empty, it's deleted

  let targetFleetId = cmd.targetFleetId.get()

  # Get both fleets (CRITICAL: Table copy semantics)
  var sourceFleet = state.fleets[cmd.sourceFleetId.get()]
  var targetFleet = state.fleets[targetFleetId]

  # Translate ship indices to squadron/spacelift indices
  let (squadronIndices, spaceliftIndices) = sourceFleet.translateShipIndicesToSquadrons(cmd.shipIndices)

  # Transfer squadrons
  let transferredFleet = sourceFleet.split(squadronIndices)
  targetFleet.merge(transferredFleet)

  # Transfer spacelift ships
  # Sort indices in descending order to avoid index shifting issues
  for idx in spaceliftIndices.sorted(Descending):
    targetFleet.spaceLiftShips.add(sourceFleet.spaceLiftShips[idx])
    sourceFleet.spaceLiftShips.delete(idx)

  # Balance both fleets
  sourceFleet.balanceSquadrons()
  targetFleet.balanceSquadrons()

  # Write back modified target fleet first
  state.fleets[targetFleetId] = targetFleet

  # Check if source fleet is now empty
  if sourceFleet.isEmpty():
    # Delete empty fleet and cleanup orders (DRY helper)
    # NOTE: We don't write sourceFleet back since we're deleting it
    cleanupEmptyFleet(state, cmd.sourceFleetId.get())
    logInfo(LogCategory.lcFleet, &"TransferShips: Merged all ships from {cmd.sourceFleetId.get()} into {targetFleetId}, deleted source fleet")
  else:
    # Write back modified source fleet
    state.fleets[cmd.sourceFleetId.get()] = sourceFleet
    logInfo(LogCategory.lcFleet, &"TransferShips: Transferred {squadronIndices.len} squadrons and {spaceliftIndices.len} spacelift ships from {cmd.sourceFleetId.get()} to {targetFleetId}")

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: none(string),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings: @[]
  )

proc executeMergeFleets*(state: var GameState, cmd: ZeroTurnCommand): ZeroTurnResult =
  ## Merge entire source fleet into target fleet (0 turns, at colony)
  ## Source fleet is deleted, all ships transferred to target
  ##
  ## This is different from Order 13 (Join Fleet):
  ## - MergeFleets: Immediate execution (0 turns) at colony
  ## - Order 13: Can involve travel, executes during Command Phase

  let targetFleetId = cmd.targetFleetId.get()

  # Get both fleets (CRITICAL: Table copy semantics)
  let sourceFleet = state.fleets[cmd.sourceFleetId.get()]
  var targetFleet = state.fleets[targetFleetId]

  # Merge all squadrons and spacelift ships
  targetFleet.merge(sourceFleet)

  # Balance target fleet after merge
  targetFleet.balanceSquadrons()

  # Write back modified target fleet
  state.fleets[targetFleetId] = targetFleet

  # Delete source fleet from state table
  state.fleets.del(cmd.sourceFleetId.get())

  # Cleanup associated orders
  if cmd.sourceFleetId.get() in state.fleetOrders:
    state.fleetOrders.del(cmd.sourceFleetId.get())
  if cmd.sourceFleetId.get() in state.standingOrders:
    state.standingOrders.del(cmd.sourceFleetId.get())

  logInfo(LogCategory.lcFleet, &"MergeFleets: Merged {sourceFleet.squadrons.len} squadrons and {sourceFleet.spaceLiftShips.len} spacelift ships from {cmd.sourceFleetId.get()} into {targetFleetId}")

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: none(string),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings: @[]
  )

# ============================================================================
# Execution - Cargo Operations (from economy_resolution.nim)
# ============================================================================

proc executeLoadCargo*(state: var GameState, cmd: ZeroTurnCommand): ZeroTurnResult =
  ## Load marines or colonists onto spacelift ships at colony
  ## Source: economy_resolution.nim:409-501

  let cargoType = cmd.cargoType.get()
  let fleetId = cmd.sourceFleetId.get()
  var requestedQty = if cmd.cargoQuantity.isSome: cmd.cargoQuantity.get() else: 0  # 0 = all available

  # Get fleet location to find colony
  let fleet = state.fleets[fleetId]
  let colonySystem = fleet.location

  # Get mutable colony and fleet
  var colony = state.colonies[colonySystem]
  var mutableFleet = fleet
  var totalLoaded = 0

  # Check colony inventory based on cargo type
  var availableUnits = case cargoType
    of CargoType.Marines: colony.marines
    of CargoType.Colonists:
      # Calculate how many complete PTUs can be loaded from exact population
      # Using souls field for accurate counting (no float rounding errors)
      # Per config/population.toml [transfer_limits] min_source_pu_remaining = 1
      # Must keep 1 PU minimum at source colony
      let minSoulsToKeep = 1_000_000  # 1 PU = 1 million souls
      if colony.souls <= minSoulsToKeep:
        0  # Cannot load any PTUs, colony at minimum viable population
      else:
        let availableSouls = colony.souls - minSoulsToKeep
        let maxPTUs = availableSouls div soulsPerPtu()
        maxPTUs
    else: 0

  if availableUnits <= 0:
    return ZeroTurnResult(
      success: false,
      error: &"No {cargoType} available at colony {colonySystem}",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  # If quantity = 0, load all available
  if requestedQty == 0:
    requestedQty = availableUnits

  # Load cargo onto compatible spacelift ships
  var remainingToLoad = min(requestedQty, availableUnits)
  var modifiedShips: seq[SpaceLiftShip] = @[]

  for ship in mutableFleet.spaceLiftShips:
    if remainingToLoad <= 0:
      modifiedShips.add(ship)
      continue

    if ship.isCrippled:
      modifiedShips.add(ship)
      continue

    # Determine ship capacity and compatible cargo type
    let shipCargoType = case ship.shipClass
      of ShipClass.TroopTransport: CargoType.Marines
      of ShipClass.ETAC: CargoType.Colonists
      else: CargoType.None

    if shipCargoType != cargoType:
      modifiedShips.add(ship)
      continue  # Ship can't carry this cargo type

    # Try to load cargo onto this ship
    var mutableShip = ship
    let loadAmount = min(remainingToLoad, mutableShip.cargo.capacity - mutableShip.cargo.quantity)
    if mutableShip.loadCargo(cargoType, loadAmount):
      totalLoaded += loadAmount
      remainingToLoad -= loadAmount
      logDebug(LogCategory.lcEconomy, &"Loaded {loadAmount} {cargoType} onto {ship.shipClass} {ship.id}")

    modifiedShips.add(mutableShip)

  # Update colony inventory
  if totalLoaded > 0:
    case cargoType
    of CargoType.Marines:
      colony.marines -= totalLoaded
    of CargoType.Colonists:
      # Colonists come from population: 1 PTU = 50k souls
      # Use souls field for exact counting (no rounding errors)
      let soulsToLoad = totalLoaded * soulsPerPtu()
      colony.souls -= soulsToLoad
      # Update display field (population in millions)
      colony.population = colony.souls div 1_000_000
      logDebug(LogCategory.lcEconomy, &"Removed {totalLoaded} PTU ({soulsToLoad} souls, {totalLoaded.float * ptuSizeMillions()}M) from colony")
    else:
      discard

    # Write back modified state
    mutableFleet.spaceLiftShips = modifiedShips
    state.fleets[fleetId] = mutableFleet
    state.colonies[colonySystem] = colony
    logInfo(LogCategory.lcEconomy, &"LoadCargo: Successfully loaded {totalLoaded} {cargoType} onto fleet {fleetId} at system {colonySystem}")

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: none(string),
    cargoLoaded: totalLoaded,
    cargoUnloaded: 0,
    warnings: if remainingToLoad > 0: @[&"Only loaded {totalLoaded} of {requestedQty} requested (capacity or availability limit)"] else: @[]
  )

proc executeUnloadCargo*(state: var GameState, cmd: ZeroTurnCommand): ZeroTurnResult =
  ## Unload cargo from spacelift ships at colony
  ## Source: economy_resolution.nim:503-547

  let fleetId = cmd.sourceFleetId.get()

  # Get fleet location to find colony
  let fleet = state.fleets[fleetId]
  let colonySystem = fleet.location

  # Get mutable colony and fleet
  var colony = state.colonies[colonySystem]
  var mutableFleet = fleet
  var modifiedShips: seq[SpaceLiftShip] = @[]
  var totalUnloaded = 0
  var unloadedType = CargoType.None

  # Unload cargo from spacelift ships
  for ship in mutableFleet.spaceLiftShips:
    var mutableShip = ship

    if mutableShip.cargo.cargoType == CargoType.None:
      modifiedShips.add(mutableShip)
      continue  # No cargo to unload

    # Unload cargo back to colony inventory
    let (cargoType, quantity) = mutableShip.unloadCargo()
    totalUnloaded += quantity
    unloadedType = cargoType

    case cargoType
    of CargoType.Marines:
      colony.marines += quantity
      logDebug(LogCategory.lcEconomy, &"Unloaded {quantity} Marines from {ship.id} to colony")
    of CargoType.Colonists:
      # Colonists are delivered to population: 1 PTU = 50k souls
      # Use souls field for exact counting (no rounding errors)
      let soulsToUnload = quantity * soulsPerPtu()
      colony.souls += soulsToUnload
      # Update display field (population in millions)
      colony.population = colony.souls div 1_000_000
      logDebug(LogCategory.lcEconomy, &"Unloaded {quantity} PTU ({soulsToUnload} souls, {quantity.float * ptuSizeMillions()}M) from {ship.id} to colony")
    else:
      discard

    modifiedShips.add(mutableShip)

  # Write back modified state
  if totalUnloaded > 0:
    mutableFleet.spaceLiftShips = modifiedShips
    state.fleets[fleetId] = mutableFleet
    state.colonies[colonySystem] = colony
    logInfo(LogCategory.lcEconomy, &"UnloadCargo: Successfully unloaded {totalUnloaded} {unloadedType} from fleet {fleetId} at system {colonySystem}")

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: none(string),
    cargoLoaded: 0,
    cargoUnloaded: totalUnloaded,
    warnings: if totalUnloaded == 0: @["No cargo to unload"] else: @[]
  )

# ============================================================================
# Execution - Squadron Operations (from economy_resolution.nim)
# ============================================================================

proc executeFormSquadron*(state: var GameState, cmd: ZeroTurnCommand): ZeroTurnResult =
  ## Create new squadron from colony's commissioned ships pool
  ## NEW: Not in current implementation - gives players manual control
  ## before auto-assignment runs during turn resolution

  let colonySystem = cmd.colonySystem.get()
  var colony = state.colonies[colonySystem]

  # Validate ships exist in unassigned pool
  if cmd.shipIndices.len > colony.unassignedSquadrons.len:
    return ZeroTurnResult(
      success: false,
      error: &"Only {colony.unassignedSquadrons.len} unassigned squadrons available at colony",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  # For now, FormSquadron simply selects existing squadrons from unassigned pool
  # In the future, this could be extended to create squadrons from individual ships
  var selectedSquadrons: seq[Squadron] = @[]
  var remainingSquadrons: seq[Squadron] = @[]

  for i, squad in colony.unassignedSquadrons:
    if i in cmd.shipIndices:
      selectedSquadrons.add(squad)
    else:
      remainingSquadrons.add(squad)

  if selectedSquadrons.len == 0:
    return ZeroTurnResult(
      success: false,
      error: "No squadrons selected from unassigned pool",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  # Update colony's unassigned squadrons
  colony.unassignedSquadrons = remainingSquadrons
  state.colonies[colonySystem] = colony

  # Generate squadron IDs (if not custom provided)
  let newSquadronId = if cmd.newSquadronId.isSome:
    cmd.newSquadronId.get()
  else:
    selectedSquadrons[0].id  # Use first selected squadron's ID as representative

  logInfo(LogCategory.lcFleet, &"FormSquadron: Selected {selectedSquadrons.len} squadrons from unassigned pool at {colonySystem}")

  # Note: Squadrons remain in unassigned pool but are now "formed" (tracked)
  # Player can then use AssignSquadronToFleet to assign to a fleet

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: some(newSquadronId),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings: @[&"Selected {selectedSquadrons.len} squadrons, use AssignSquadronToFleet to assign to fleet"]
  )

proc executeTransferShipBetweenSquadrons*(state: var GameState, cmd: ZeroTurnCommand): ZeroTurnResult =
  ## Transfer ship between squadrons at this colony
  ## Source: economy_resolution.nim:216-291

  let colonySystem = cmd.colonySystem.get()

  # Find source and target squadrons in fleets at this colony
  var sourceFleetId: Option[FleetId] = none(FleetId)
  var targetFleetId: Option[FleetId] = none(FleetId)
  var sourceSquadIndex: int = -1
  var targetSquadIndex: int = -1

  # Locate source squadron
  for fleetId, fleet in state.fleets:
    if fleet.location == colonySystem and fleet.owner == cmd.houseId:
      for i, squad in fleet.squadrons:
        if squad.id == cmd.sourceSquadronId.get():
          sourceFleetId = some(fleetId)
          sourceSquadIndex = i
          break
      if sourceFleetId.isSome:
        break

  if sourceFleetId.isNone:
    return ZeroTurnResult(
      success: false,
      error: &"Source squadron {cmd.sourceSquadronId.get()} not found at colony",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  # Locate target squadron
  for fleetId, fleet in state.fleets:
    if fleet.location == colonySystem and fleet.owner == cmd.houseId:
      for i, squad in fleet.squadrons:
        if squad.id == cmd.targetSquadronId.get():
          targetFleetId = some(fleetId)
          targetSquadIndex = i
          break
      if targetFleetId.isSome:
        break

  if targetFleetId.isNone:
    return ZeroTurnResult(
      success: false,
      error: &"Target squadron {cmd.targetSquadronId.get()} not found at colony",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  # Remove ship from source squadron
  let shipIndex = cmd.shipIndex.get()
  var sourceFleet = state.fleets[sourceFleetId.get()]
  var sourceSquad = sourceFleet.squadrons[sourceSquadIndex]

  if shipIndex < 0 or shipIndex >= sourceSquad.ships.len:
    return ZeroTurnResult(
      success: false,
      error: &"Invalid ship index {shipIndex} (squadron has {sourceSquad.ships.len} ships)",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  let shipOpt = sourceSquad.removeShip(shipIndex)
  if shipOpt.isNone:
    return ZeroTurnResult(
      success: false,
      error: "Could not remove ship from source squadron",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  let ship = shipOpt.get()

  # Add ship to target squadron
  var targetFleet = state.fleets[targetFleetId.get()]
  var targetSquad = targetFleet.squadrons[targetSquadIndex]

  if not targetSquad.addShip(ship):
    # ROLLBACK: Put ship back in source squadron
    discard sourceSquad.addShip(ship)
    sourceFleet.squadrons[sourceSquadIndex] = sourceSquad
    state.fleets[sourceFleetId.get()] = sourceFleet
    return ZeroTurnResult(
      success: false,
      error: "Could not add ship to target squadron (may be full or incompatible)",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  # Update both squadrons in state
  sourceFleet.squadrons[sourceSquadIndex] = sourceSquad
  targetFleet.squadrons[targetSquadIndex] = targetSquad
  state.fleets[sourceFleetId.get()] = sourceFleet
  state.fleets[targetFleetId.get()] = targetFleet

  logInfo(LogCategory.lcFleet, &"TransferShipBetweenSquadrons: Transferred ship from {cmd.sourceSquadronId.get()} to {cmd.targetSquadronId.get()}")

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: none(string),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings: @[]
  )

proc executeAssignSquadronToFleet*(state: var GameState, cmd: ZeroTurnCommand): ZeroTurnResult =
  ## Assign existing squadron to fleet (move between fleets or create new fleet)
  ## Source: economy_resolution.nim:293-382

  let colonySystem = cmd.colonySystem.get()
  var colony = state.colonies[colonySystem]

  # Find squadron in existing fleets at this colony
  var foundSquadron: Option[Squadron] = none(Squadron)
  var sourceFleetId: Option[FleetId] = none(FleetId)

  for fleetId, fleet in state.fleets:
    if fleet.location == colonySystem and fleet.owner == cmd.houseId:
      for i, squad in fleet.squadrons:
        if squad.id == cmd.squadronId.get():
          foundSquadron = some(squad)
          sourceFleetId = some(fleetId)
          break
      if foundSquadron.isSome:
        break

  # If not found in fleets, check unassigned squadrons at colony
  if foundSquadron.isNone:
    for i, squad in colony.unassignedSquadrons:
      if squad.id == cmd.squadronId.get():
        foundSquadron = some(squad)
        # Remove from unassigned list
        var newUnassigned: seq[Squadron] = @[]
        for j, s in colony.unassignedSquadrons:
          if j != i:
            newUnassigned.add(s)
        colony.unassignedSquadrons = newUnassigned
        state.colonies[colonySystem] = colony
        break

  if foundSquadron.isNone:
    return ZeroTurnResult(
      success: false,
      error: &"Squadron {cmd.squadronId.get()} not found at colony {colonySystem}",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  let squadron = foundSquadron.get()

  # Remove squadron from source fleet
  if sourceFleetId.isSome:
    var srcFleet = state.fleets[sourceFleetId.get()]
    var newSquadrons: seq[Squadron] = @[]
    for squad in srcFleet.squadrons:
      if squad.id != cmd.squadronId.get():
        newSquadrons.add(squad)
    srcFleet.squadrons = newSquadrons
    state.fleets[sourceFleetId.get()] = srcFleet

    # If source fleet is now empty, remove it and clean up orders (DRY helper)
    if newSquadrons.len == 0 and srcFleet.spaceLiftShips.len == 0:
      cleanupEmptyFleet(state, sourceFleetId.get())

  # Add squadron to target fleet or create new one
  var resultFleetId: FleetId
  if cmd.targetFleetId.isSome:
    # Assign to existing fleet
    let targetId = cmd.targetFleetId.get()
    if targetId in state.fleets:
      var targetFleet = state.fleets[targetId]
      # Only allow assignment to Active fleets (exclude Reserve and Mothballed)
      if targetFleet.status != FleetStatus.Active:
        return ZeroTurnResult(
          success: false,
          error: &"Cannot assign squadrons to {targetFleet.status} fleets (only Active fleets allowed)",
          newFleetId: none(FleetId),
          newSquadronId: none(string),
          cargoLoaded: 0,
          cargoUnloaded: 0,
          warnings: @[]
        )
      targetFleet.squadrons.add(squadron)
      state.fleets[targetId] = targetFleet
      resultFleetId = targetId
      logInfo(LogCategory.lcFleet, &"AssignSquadronToFleet: Assigned squadron {squadron.id} to existing fleet {targetId}")
    else:
      return ZeroTurnResult(
        success: false,
        error: &"Target fleet {targetId} does not exist",
        newFleetId: none(FleetId),
        newSquadronId: none(string),
        cargoLoaded: 0,
        cargoUnloaded: 0,
        warnings: @[]
      )
  else:
    # Create new fleet
    let newFleetId = if cmd.newFleetId.isSome:
      cmd.newFleetId.get()
    else:
      cmd.houseId & "_fleet_" & $colonySystem & "_" & $state.turn

    state.fleets[newFleetId] = Fleet(
      id: newFleetId,
      owner: cmd.houseId,
      location: colonySystem,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )
    resultFleetId = newFleetId
    logInfo(LogCategory.lcFleet, &"AssignSquadronToFleet: Created new fleet {newFleetId} with squadron {squadron.id}")

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: some(resultFleetId),
    newSquadronId: none(string),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings: @[]
  )

# ============================================================================
# Main API Entry Point
# ============================================================================

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
    return ZeroTurnResult(
      success: false,
      error: validation.error,
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

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

# Export main types
export ZeroTurnCommandType, ZeroTurnCommand, ZeroTurnResult, ValidationResult
