## Zero-Turn Fleet Logistics System
##
## ⚠️ WARNING: This file is partially updated for squadron removal refactor.
## TODO: Complete refactoring of all execute functions for ship-based operations.
## Estimated work remaining: ~1500 lines across 11 functions.
##
## Unified administrative command system for fleet/cargo operations
## Execute immediately during command submission (0 turns, at friendly colonies)
##
## Architecture:
## - Immediate fleet logistics operations (detach, merge, transfer, etc.)
## - Separate from CommandPacket system (NOT queued for turn resolution)
## - Execute synchronously during command submission phase
## - Only available at friendly colonies (logistics infrastructure requirement)
## - Follows DRY principles with shared validation and cleanup helpers
##
## Usage:
##   let cmd = ZeroTurnCommand(...)
##   let result = submitZeroTurnCommand(state, cmd)
##   if result.success: echo "Success!"

import std/[options, algorithm, tables, strformat, sequtils, sets]
import ../../types/[
  core, game_state, fleet, ship, colony, ground_unit,
  event, zero_turn
]
import ../../state/[engine, iterators, id_gen]
import ../../entities/[fleet_ops, ship_ops, colony_ops]
import ../fleet/entity as fleet_entity
import ../ship/entity as ship_entity
import ../capacity/carrier_hangar
  # For isCarrier, getCarrierMaxCapacity, canLoadFighters
import ../../utils # For soulsPerPtu(), ptuSizeMillions()
import ../../event_factory/init as event_factory
import ../../../common/logger

# ============================================================================
# Type Definitions
# ============================================================================

# ============================================================================
# Shared Validation Helpers (DRY)
# ============================================================================

proc validateOwnership*(state: GameState, houseId: HouseId): ValidationResult =
  ## DRY: Validate house exists
  if state.house(houseId).isNone:
    return ValidationResult(valid: false, error: "House does not exist")
  return ValidationResult(valid: true, error: "")

proc validateFleetAtFriendlyColony*(
    state: GameState, fleetId: FleetId, houseId: HouseId
): ValidationResult =
  ## DRY: Validate fleet exists, is owned by house, and is at friendly colony
  ## CRITICAL: All zero-turn fleet/cargo operations require friendly colony

  # 1. Check fleet exists
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return ValidationResult(valid: false, error: "Fleet not found")

  let fleet = fleetOpt.get()

  # 2. Check ownership
  if fleet.houseId != houseId:
    return ValidationResult(valid: false, error: "Fleet not owned by house")

  # 3. CRITICAL: Fleet must be at friendly colony
  # Use bySystem index to map SystemId → ColonyId
  let colonyOpt = state.colonyBySystem(fleet.location)
  if colonyOpt.isNone:
    return ValidationResult(valid: false, error: "Colony not found")

  let colony = colonyOpt.get()
  if colony.owner != houseId:
    return ValidationResult(
      valid: false, error: "Fleet must be at a friendly colony for zero-turn operations"
    )

  return ValidationResult(valid: true, error: "")

proc validateColonyOwnership*(
    state: GameState, systemId: SystemId, houseId: HouseId
): ValidationResult =
  ## DRY: Validate colony exists and is owned by house

  # Use bySystem index to map SystemId → ColonyId
  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isNone:
    return ValidationResult(valid: false, error: "Colony not found")

  let colony = colonyOpt.get()
  if colony.owner != houseId:
    return ValidationResult(valid: false, error: "Colony not owned by house")

  return ValidationResult(valid: true, error: "")

proc validateShipIndices*(
    state: GameState, fleet: Fleet, indices: seq[int]
): ValidationResult =
  ## DRY: Validate ship indices are valid and not selecting all ships

  let allShips = fleet_entity.allShips(state, fleet)

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

proc validateZeroTurnCommand*(
    state: GameState, cmd: ZeroTurnCommand
): ValidationResult =
  ## Validate zero-turn command
  ## Multi-layer validation strategy:
  ##   Layer 1: Basic validation (house exists)
  ##   Layer 2: Fleet operations validation (ownership, location)
  ##   Layer 3: Squadron operations validation (colony ownership)
  ##   Layer 4: Command-specific validation

  # Layer 1: Basic validation
  result = validateOwnership(state, cmd.houseId)
  if not result.valid:
    return result

  # Layer 2: Fleet operations validation (requires colony)
  if cmd.commandType in {
    ZeroTurnCommandType.DetachShips, ZeroTurnCommandType.TransferShips,
    ZeroTurnCommandType.MergeFleets, ZeroTurnCommandType.LoadCargo,
    ZeroTurnCommandType.UnloadCargo, ZeroTurnCommandType.LoadFighters,
    ZeroTurnCommandType.UnloadFighters,
  }:
    if cmd.sourceFleetId.isNone:
      return ValidationResult(valid: false, error: "Source fleet ID required")

    result = validateFleetAtFriendlyColony(state, cmd.sourceFleetId.get(), cmd.houseId)
    if not result.valid:
      return result

  # Layer 3: Command-specific validation
  case cmd.commandType
  of ZeroTurnCommandType.DetachShips, ZeroTurnCommandType.TransferShips:
    # Validate ship indices
    let fleetOpt = state.fleet(cmd.sourceFleetId.get())
    if fleetOpt.isNone:
      return ValidationResult(valid: false, error: "Source fleet not found")
    let fleet = fleetOpt.get()

    result = validateShipIndices(state, fleet, cmd.shipIndices)
    if not result.valid:
      return result

    # DetachShips specific: cannot detach transport-only fleet (except ETACs)
    if cmd.commandType == ZeroTurnCommandType.DetachShips:
      # Check if only ETACs are being detached
      # ETACs don't need combat escorts, but transports do
      var onlyETAC = true
      var hasNonETAC = false

      for idx in cmd.shipIndices:
        if idx < 0 or idx >= fleet.ships.len:
          continue
        let shipId = fleet.ships[idx]
        let shipOpt = state.ship(shipId)
        if shipOpt.isNone:
          continue
        let ship = shipOpt.get()

        # Check ship class
        if ship.shipClass == ShipClass.ETAC:
          # ETAC ships can operate independently
          continue
        elif ship.shipClass == ShipClass.TroopTransport:
          # Non-ETAC transports need escorts
          hasNonETAC = true
          onlyETAC = false
        else:
          # Combat or other ship types
          onlyETAC = false

      if onlyETAC and hasNonETAC:
        # Only detaching ETACs, but some are non-ETAC transports
        # These need combat escorts
        return ValidationResult(
          valid: false,
          error: "Cannot detach non-ETAC transport ships without combat escorts",
        )

    # TransferShips specific: validate target fleet
    if cmd.commandType == ZeroTurnCommandType.TransferShips:
      if cmd.targetFleetId.isNone:
        return
          ValidationResult(valid: false, error: "Target fleet ID required for transfer")

      let targetFleetId = cmd.targetFleetId.get()
      let targetFleetOpt = state.fleet(targetFleetId)
      if targetFleetOpt.isNone:
        return ValidationResult(valid: false, error: "Target fleet not found")

      let targetFleet = targetFleetOpt.get()
      if targetFleet.houseId != cmd.houseId:
        return ValidationResult(valid: false, error: "Target fleet not owned by house")

      if targetFleet.location != fleet.location:
        return
          ValidationResult(valid: false, error: "Both fleets must be at same location")

      # Check scout/combat fleet mixing (validate after transfer would occur)
      # TODO: This is a simplified check - ideally we'd simulate the transfer
      # and check if the result would mix scouts with combat ships
      let mergeCheck = fleet_entity.canMergeWith(state, fleet, targetFleet)
      if not mergeCheck.canMerge:
        return ValidationResult(valid: false, error: mergeCheck.reason)
  of ZeroTurnCommandType.MergeFleets:
    # Validate target fleet
    if cmd.targetFleetId.isNone:
      return ValidationResult(valid: false, error: "Target fleet ID required for merge")

    let targetFleetId = cmd.targetFleetId.get()
    let targetFleetOpt = state.fleet(targetFleetId)
    if targetFleetOpt.isNone:
      return ValidationResult(valid: false, error: "Target fleet not found")

    let targetFleet = targetFleetOpt.get()
    if targetFleet.houseId != cmd.houseId:
      return ValidationResult(valid: false, error: "Target fleet not owned by house")

    let sourceFleetOpt = state.fleet(cmd.sourceFleetId.get())
    if sourceFleetOpt.isNone:
      return ValidationResult(valid: false, error: "Source fleet not found")
    let sourceFleet = sourceFleetOpt.get()

    if targetFleet.location != sourceFleet.location:
      return
        ValidationResult(valid: false, error: "Both fleets must be at same location")

    # Cannot merge fleet into itself
    if cmd.sourceFleetId.get() == targetFleetId:
      return ValidationResult(valid: false, error: "Cannot merge fleet into itself")

    # Check scout/combat fleet mixing
    let mergeCheck =
      fleet_entity.canMergeWith(state, sourceFleet, targetFleet)
    if not mergeCheck.canMerge:
      return ValidationResult(valid: false, error: mergeCheck.reason)
  of ZeroTurnCommandType.LoadCargo, ZeroTurnCommandType.UnloadCargo:
    # Validate cargo type specified for LoadCargo
    if cmd.commandType == ZeroTurnCommandType.LoadCargo:
      if cmd.cargoType.isNone:
        return
          ValidationResult(valid: false, error: "Cargo type required for LoadCargo")
  of ZeroTurnCommandType.LoadFighters:
    # Validate carrier ship ID
    if cmd.carrierShipId.isNone:
      return ValidationResult(valid: false, error: "Carrier ship ID required")
    # Validate at least one fighter selected
    if cmd.fighterIds.len == 0:
      return ValidationResult(
        valid: false, error: "Must select at least one fighter to load"
      )
  of ZeroTurnCommandType.UnloadFighters:
    # Validate carrier ship ID
    if cmd.carrierShipId.isNone:
      return ValidationResult(valid: false, error: "Carrier ship ID required")
    # Validate at least one fighter selected
    if cmd.fighterIds.len == 0:
      return ValidationResult(
        valid: false, error: "Must select at least one fighter to unload"
      )
  of ZeroTurnCommandType.TransferFighters:
    # TransferFighters can happen anywhere (mobile operations)
    # Validate source and target carrier ship IDs
    if cmd.sourceCarrierShipId.isNone:
      return
        ValidationResult(valid: false, error: "Source carrier ship ID required")
    if cmd.targetCarrierShipId.isNone:
      return
        ValidationResult(valid: false, error: "Target carrier ship ID required")
    if cmd.sourceCarrierShipId.get() == cmd.targetCarrierShipId.get():
      return ValidationResult(
        valid: false, error: "Cannot transfer fighters to same carrier"
      )
    # Validate at least one fighter selected
    if cmd.fighterIds.len == 0:
      return ValidationResult(
        valid: false, error: "Must select at least one embarked fighter to transfer"
      )
    # Validate both carriers exist and are at same location
    if cmd.sourceFleetId.isNone:
      return ValidationResult(valid: false, error: "Source fleet ID required")
    let sourceFleetOpt = state.fleet(cmd.sourceFleetId.get())
    if sourceFleetOpt.isNone:
      return ValidationResult(valid: false, error: "Source fleet not found")
    let sourceFleet = sourceFleetOpt.get()
    # Find both carriers and ensure they're in same fleet or adjacent fleets at same location
    # (detailed validation in execute function)

  return ValidationResult(valid: true, error: "")

# ============================================================================
# Shared Cleanup Helper (DRY)
# ============================================================================

proc cleanupEmptyFleet*(state: var GameState, fleetId: FleetId) =
  ## DRY: Remove fleet and cleanup all associated orders
  ## Used by TransferShips, MergeFleets, AssignSquadronToFleet, DetachShips
  ## NOTE: Caller must ensure fleet should be deleted (this doesn't check isEmpty)

  # Use fleet_ops to properly destroy fleet (maintains indexes, destroys squadrons)
  fleet_ops.destroyFleet(state, fleetId)

  # Cleanup associated commands
  if fleetId in state.fleetCommands:
    state.fleetCommands.del(fleetId)
  if fleetId in state.standingCommands:
    state.standingCommands.del(fleetId)

  logFleet(&"Removed fleet {fleetId} and associated orders")

# ============================================================================
# Execution - Fleet Operations (from fleet_commands.nim)
# ============================================================================

proc executeDetachShips*(
    state: var GameState, cmd: ZeroTurnCommand, events: var seq[GameEvent]
): ZeroTurnResult =
  ## Split ships from source fleet to create new fleet
  ## Both fleets remain at same location

  # Get source fleet via entity manager
  let sourceFleetOpt = state.fleet(cmd.sourceFleetId.get())
  if sourceFleetOpt.isNone:
    return ZeroTurnResult(
      success: false,
      error: "Source fleet not found",
      newFleetId: none(FleetId),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  var sourceFleet = sourceFleetOpt.get()
  let systemId = sourceFleet.location

  # Extract ships to detach based on indices
  # Convert to HashSet for O(1) lookup (avoids O(n²) with seq.contains)
  let indicesSet = cmd.shipIndices.toHashSet()
  var shipsToDetach: seq[ShipId] = @[]
  var remainingShips: seq[ShipId] = @[]

  for i, shipId in sourceFleet.ships:
    if i in indicesSet:
      shipsToDetach.add(shipId)
    else:
      remainingShips.add(shipId)

  # Generate new fleet ID if not provided
  let newFleetId =
    if cmd.newFleetId.isSome:
      cmd.newFleetId.get()
    else:
      state.generateFleetId()

  # Create new fleet using entity ops
  let newFleet = fleet_ops.newFleet(
    shipIds = shipsToDetach,
    id = newFleetId,
    owner = cmd.houseId,
    location = sourceFleet.location,
    status = FleetStatus.Active,
  )

  let shipsDetached = newFleet.ships.len

  # Update source fleet with remaining ships
  sourceFleet.ships = remainingShips

  # Check if source fleet is now empty after detaching
  if sourceFleet.ships.len == 0:
    # Delete empty source fleet and cleanup orders
    cleanupEmptyFleet(state, cmd.sourceFleetId.get())
    logFleet(
      &"DetachShips: Detached all ships from {cmd.sourceFleetId.get()}, deleted source fleet, created new fleet {newFleetId}"
    )
  else:
    # Write back modified source fleet via entity manager
    state.updateFleet(cmd.sourceFleetId.get(), sourceFleet)
    logFleet(
      &"DetachShips: Created fleet {newFleetId} with {newFleet.ships.len} ships"
    )

  # Add new fleet to state via entity manager
  state.addFleet(newFleetId, newFleet)
  # Update indexes using fleet_ops helpers
  fleet_ops.registerFleetLocation(state, newFleetId, newFleet.location)
  fleet_ops.registerFleetOwner(state, newFleetId, newFleet.houseId)

  # Emit FleetDetachment event (Phase 7b)
  events.add(
    event_factory.fleetDetachment(
      cmd.houseId, cmd.sourceFleetId.get(), newFleetId, int32(shipsDetached), systemId
    )
  )

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: some(newFleetId),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings: @[],
  )

proc executeTransferShips*(
    state: var GameState, cmd: ZeroTurnCommand, events: var seq[GameEvent]
): ZeroTurnResult =
  ## Move ships from source fleet to target fleet
  ## If source becomes empty, it's deleted

  let targetFleetId = cmd.targetFleetId.get()

  # Get both fleets via entity manager
  let sourceFleetOpt = state.fleet(cmd.sourceFleetId.get())
  if sourceFleetOpt.isNone:
    return ZeroTurnResult(
      success: false,
      error: "Source fleet not found",
      newFleetId: none(FleetId),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  let targetFleetOpt = state.fleet(targetFleetId)
  if targetFleetOpt.isNone:
    return ZeroTurnResult(
      success: false,
      error: "Target fleet not found",
      newFleetId: none(FleetId),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  var sourceFleet = sourceFleetOpt.get()
  var targetFleet = targetFleetOpt.get()
  let systemId = sourceFleet.location

  # Extract ships to transfer based on indices
  # Convert to HashSet for O(1) lookup (avoids O(n²) with seq.contains)
  let indicesSet = cmd.shipIndices.toHashSet()
  var shipsToTransfer: seq[ShipId] = @[]
  var remainingShips: seq[ShipId] = @[]

  for i, shipId in sourceFleet.ships:
    if i in indicesSet:
      shipsToTransfer.add(shipId)
    else:
      remainingShips.add(shipId)

  let shipsTransferred = shipsToTransfer.len

  # Transfer ships to target fleet
  targetFleet.ships.add(shipsToTransfer)
  sourceFleet.ships = remainingShips

  # Write back modified target fleet via entity manager
  state.updateFleet(targetFleetId, targetFleet)

  # Check if source fleet is now empty
  if sourceFleet.ships.len == 0:
    # Delete empty fleet and cleanup orders (DRY helper)
    cleanupEmptyFleet(state, cmd.sourceFleetId.get())
    logFleet(
      &"TransferShips: Merged all ships from {cmd.sourceFleetId.get()} into {targetFleetId}, deleted source fleet"
    )
  else:
    # Write back modified source fleet via entity manager
    state.updateFleet(cmd.sourceFleetId.get(), sourceFleet)
    logFleet(
      &"TransferShips: Transferred {shipsTransferred} ships from {cmd.sourceFleetId.get()} to {targetFleetId}"
    )

  # Emit FleetTransfer event (Phase 7b)
  events.add(
    event_factory.fleetTransfer(
      cmd.houseId,
      cmd.sourceFleetId.get(),
      targetFleetId,
      int32(shipsTransferred),
      systemId,
    )
  )

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings: @[],
  )

proc executeMergeFleets*(
    state: var GameState, cmd: ZeroTurnCommand, events: var seq[GameEvent]
): ZeroTurnResult =
  ## Merge entire source fleet into target fleet (0 turns, at colony)
  ## Source fleet is deleted, all ships transferred to target
  ##
  ## This is different from Order 13 (Join Fleet):
  ## - MergeFleets: Immediate execution (0 turns) at colony
  ## - Order 13: Can involve travel, executes during Command Phase

  let targetFleetId = cmd.targetFleetId.get()

  # Get both fleets via entity manager
  let sourceFleetOpt = state.fleet(cmd.sourceFleetId.get())
  if sourceFleetOpt.isNone:
    return ZeroTurnResult(
      success: false,
      error: "Source fleet not found",
      newFleetId: none(FleetId),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  let targetFleetOpt = state.fleet(targetFleetId)
  if targetFleetOpt.isNone:
    return ZeroTurnResult(
      success: false,
      error: "Target fleet not found",
      newFleetId: none(FleetId),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  let sourceFleet = sourceFleetOpt.get()
  var targetFleet = targetFleetOpt.get()

  let shipsMerged = sourceFleet.ships.len
  let systemId = sourceFleet.location

  # Merge all ships from source to target
  targetFleet.ships.add(sourceFleet.ships)

  # Write back modified target fleet via entity manager
  state.updateFleet(targetFleetId, targetFleet)

  # Delete source fleet using DRY helper (handles indexes and commands)
  cleanupEmptyFleet(state, cmd.sourceFleetId.get())

  logFleet(
    &"MergeFleets: Merged {shipsMerged} ships from {cmd.sourceFleetId.get()} into {targetFleetId}"
  )

  # Emit FleetMerged event (Phase 7b)
  events.add(
    event_factory.fleetMerged(
      cmd.houseId, cmd.sourceFleetId.get(), targetFleetId, int32(shipsMerged), systemId
    )
  )

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings: @[],
  )

# ============================================================================
# Execution - Cargo Operations (from economy_resolution.nim)
# ============================================================================

proc executeLoadCargo*(
    state: var GameState, cmd: ZeroTurnCommand, events: var seq[GameEvent]
): ZeroTurnResult =
  ## Load marines or colonists onto transport squadrons at colony
  ## Source: economy_resolution.nim:409-501

  let cargoType = cmd.cargoType.get()
  let fleetId = cmd.sourceFleetId.get()
  var requestedQty =
    if cmd.cargoQuantity.isSome:
      cmd.cargoQuantity.get()
    else:
      0 # 0 = all available

  # Get fleet via entity manager
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return ZeroTurnResult(
      success: false,
      error: "Fleet not found",
      newFleetId: none(FleetId),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  let fleet = fleetOpt.get()
  let colonySystem = fleet.location

  # Get colony via bySystem index
  if not state.colonies.bySystem.hasKey(colonySystem):
    return ZeroTurnResult(
      success: false,
      error: "Fleet not at colony",
      newFleetId: none(FleetId),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  let colonyOpt = state.colonyBySystem(colonySystem)
  if colonyOpt.isNone:
    return ZeroTurnResult(
      success: false,
      error: "Colony not found",
      newFleetId: none(FleetId),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  var colony = colonyOpt.get()
  var totalLoaded = 0

  # Check colony inventory based on cargo type
  var availableUnits =
    case cargoType
    of CargoClass.Marines:
      # Count marine units in groundUnitIds
      var marineCount = 0
      for unitId in colony.groundUnitIds:
        let unitOpt = state.groundUnit(unitId)
        if unitOpt.isSome and unitOpt.get().stats.unitType == GroundClass.Marine:
          marineCount += 1
      marineCount
    of CargoClass.Colonists:
      # Calculate how many complete PTUs can be loaded from exact population
      # Using souls field for accurate counting (no float rounding errors)
      # Per config/population.toml [transfer_limits] min_source_pu_remaining = 1
      # Must keep 1 PU minimum at source colony
      let minSoulsToKeep = 1_000_000 # 1 PU = 1 million souls
      if colony.souls <= minSoulsToKeep:
        0 # Cannot load any PTUs, colony at minimum viable population
      else:
        let availableSouls = colony.souls - minSoulsToKeep
        let maxPTUs = availableSouls div soulsPerPtu()
        maxPTUs
    else:
      0

  if availableUnits <= 0:
    return ZeroTurnResult(
      success: false,
      error: &"No {cargoType} available at colony {colonySystem}",
      newFleetId: none(FleetId),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  # If quantity = 0, load all available
  if requestedQty == 0:
    requestedQty = availableUnits

  # Load cargo onto compatible transport ships (TroopTransport/ETAC)
  var remainingToLoad = min(requestedQty, availableUnits)

  # Iterate over ship IDs, get entities via entity manager
  for shipId in fleet.ships:
    if remainingToLoad <= 0:
      break

    # Get ship entity
    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      continue

    var ship = shipOpt.get()

    # Skip crippled ships
    if ship.state == CombatState.Crippled:
      continue

    # Determine ship capacity and compatible cargo type
    let shipCargoType =
      case ship.shipClass
      of ShipClass.TroopTransport: CargoClass.Marines
      of ShipClass.ETAC: CargoClass.Colonists
      else: CargoClass.None

    if shipCargoType != cargoType:
      continue # Ship can't carry this cargo type

    # Try to load cargo onto this ship
    let currentCargo =
      if ship.cargo.isSome:
        ship.cargo.get()
      else:
        ShipCargo(cargoType: CargoClass.None, quantity: 0, capacity: 0)
    let loadAmount = min(remainingToLoad, currentCargo.capacity - currentCargo.quantity)

    if loadAmount > 0:
      var newCargo = currentCargo
      newCargo.cargoType = cargoType
      newCargo.quantity += int32(loadAmount)
      ship.cargo = some(newCargo)

      # Update ship entity
      state.updateShip(shipId, ship)

      totalLoaded += loadAmount
      remainingToLoad -= loadAmount
      logDebug(
        "Economy",
        &"Loaded {loadAmount} {cargoType} onto {ship.shipClass} ship {shipId}"
      )

  # Update colony inventory
  if totalLoaded > 0:
    case cargoType
    of CargoClass.Marines:
      # Remove loaded marines from colony (remove N marine units from groundUnitIds)
      # Note: Removes marines from end of list (FIFO loading)
      var marinesToRemove = totalLoaded
      var i = colony.groundUnitIds.len - 1
      while marinesToRemove > 0 and i >= 0:
        let unitOpt = state.groundUnit(colony.groundUnitIds[i])
        if unitOpt.isSome and unitOpt.get().stats.unitType == GroundClass.Marine:
          colony.groundUnitIds.delete(i)
          marinesToRemove -= 1
        i -= 1
    of CargoClass.Colonists:
      # Colonists come from population: 1 PTU = 50k souls
      # Use souls field for exact counting (no rounding errors)
      let soulsToLoad = int32(totalLoaded * soulsPerPtu())
      colony.souls -= soulsToLoad
      # Update display field (population in millions)
      colony.population = colony.souls div 1_000_000
      logDebug(
        "Economy",
        &"Removed {totalLoaded} PTU ({soulsToLoad} souls, {totalLoaded.float * ptuSizeMillions()}M) from colony",
      )
    else:
      discard

    # Write back modified colony via entity manager
    state.updateColony(colony.id, colony)
    logDebug(
      "Economy",
      &"LoadCargo: Successfully loaded {totalLoaded} {cargoType} onto fleet {fleetId} at system {colonySystem}"
    )

    # Emit CargoLoaded event (Phase 7b)
    events.add(
      event_factory.cargoLoaded(
        cmd.houseId, fleetId, $cargoType, int32(totalLoaded), colonySystem
      )
    )

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    cargoLoaded: int32(totalLoaded),
    cargoUnloaded: 0,
    warnings:
      if remainingToLoad > 0:
        @[
          &"Only loaded {totalLoaded} of {requestedQty} requested (capacity or availability limit)"
        ]
      else:
        @[],
  )

proc executeUnloadCargo*(
    state: var GameState, cmd: ZeroTurnCommand, events: var seq[GameEvent]
): ZeroTurnResult =
  ## Unload cargo from transport squadrons at colony
  ## Source: economy_resolution.nim:503-547

  let fleetId = cmd.sourceFleetId.get()

  # Get fleet via entity manager
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return ZeroTurnResult(
      success: false,
      error: "Fleet not found",
      newFleetId: none(FleetId),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  let fleet = fleetOpt.get()
  let colonySystem = fleet.location

  # Get colony via bySystem index
  if not state.colonies.bySystem.hasKey(colonySystem):
    return ZeroTurnResult(
      success: false,
      error: "Fleet not at colony",
      newFleetId: none(FleetId),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  let colonyOpt = state.colonyBySystem(colonySystem)
  if colonyOpt.isNone:
    return ZeroTurnResult(
      success: false,
      error: "Colony not found",
      newFleetId: none(FleetId),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  var colony = colonyOpt.get()
  var totalUnloaded = 0
  var unloadedType = CargoClass.None

  # Unload cargo from transport ships (TroopTransport/ETAC)
  # Iterate over ship IDs, get entities via entity manager
  for shipId in fleet.ships:
    # Get ship entity
    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      continue

    var ship = shipOpt.get()

    if ship.cargo.isNone:
      continue # No cargo to unload

    let cargo = ship.cargo.get()
    if cargo.cargoType == CargoClass.None or cargo.quantity == 0:
      continue # Empty cargo

    # Unload cargo back to colony inventory
    let cargoType = cargo.cargoType
    let quantity = cargo.quantity
    totalUnloaded += quantity
    unloadedType = cargoType

    case cargoType
    of CargoClass.Marines:
      # TODO: Create GroundUnit entities for marines
      # For now, marines are unloaded from ship but not added to colony
      # Proper implementation requires ground unit entity creation
      logDebug("Economy", &"Unloaded {quantity} Marines from ship {shipId} (TODO: add to colony groundUnitIds)")
    of CargoClass.Colonists:
      # Colonists are delivered to population: 1 PTU = 50k souls
      # Use souls field for exact counting (no rounding errors)
      let soulsToUnload = quantity * soulsPerPtu()
      colony.souls += soulsToUnload
      # Update display field (population in millions)
      colony.population = colony.souls div 1_000_000
      logDebug(
        "Economy",
        &"Unloaded {quantity} PTU ({soulsToUnload} souls, {quantity.float * ptuSizeMillions()}M) from ship {shipId} to colony"
      )
    else:
      discard

    # Clear cargo from ship
    ship.cargo =
      some(ShipCargo(cargoType: CargoClass.None, quantity: 0, capacity: cargo.capacity))

    # Update ship entity
    state.updateShip(shipId, ship)

  # Write back modified colony
  if totalUnloaded > 0:
    state.updateColony(colony.id, colony)
    logDebug(
      "Economy",
      &"UnloadCargo: Successfully unloaded {totalUnloaded} {unloadedType} from fleet {fleetId} at system {colonySystem}"
    )

    # Emit CargoUnloaded event (Phase 7b)
    events.add(
      event_factory.cargoUnloaded(
        cmd.houseId, fleetId, $unloadedType, int32(totalUnloaded), colonySystem
      )
    )

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    cargoLoaded: 0,
    cargoUnloaded: int32(totalUnloaded),
    warnings:
      if totalUnloaded == 0:
        @["No cargo to unload"]
      else:
        @[],
  )

# ============================================================================
# ============================================================================
# Execution - Fighter Operations
# ============================================================================

proc executeLoadFighters*(
    state: var GameState, cmd: ZeroTurnCommand, events: var seq[GameEvent]
): ZeroTurnResult =
  ## Load fighter ships from colony onto carrier
  ## Requires: Fleet at friendly colony, carrier with available hangar space

  let sourceFleetId = cmd.sourceFleetId.get()
  let carrierShipId = cmd.carrierShipId.get()

  # Get fleet via entity manager
  let fleetOpt = state.fleet(sourceFleetId)
  if fleetOpt.isNone:
    return ZeroTurnResult(success: false, error: "Fleet not found", warnings: @[])

  let fleet = fleetOpt.get()
  let systemId = fleet.location

  # Get carrier ship via entity manager
  let carrierOpt = state.ship(carrierShipId)
  if carrierOpt.isNone:
    return ZeroTurnResult(
      success: false, error: "Carrier ship not found", warnings: @[]
    )

  var carrier = carrierOpt.get()

  # Validate carrier ship is in the fleet
  if carrier.fleetId != sourceFleetId:
    return ZeroTurnResult(
      success: false, error: "Carrier ship not in specified fleet", warnings: @[]
    )

  # Validate carrier using carrier_hangar helper
  if not isCarrier(carrier.shipClass):
    return ZeroTurnResult(
      success: false, error: "Ship is not a carrier (CV/CX required)", warnings: @[]
    )

  # Get colony via bySystem index
  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isNone:
    return ZeroTurnResult(
      success: false, error: "No colony at fleet location", warnings: @[]
    )

  var colony = colonyOpt.get()

  # Get ACO tech level for capacity calculation
  let houseOpt = state.house(cmd.houseId)
  if houseOpt.isNone:
    return ZeroTurnResult(success: false, error: "House not found", warnings: @[])

  let acoLevel = houseOpt.get().techTree.levels.aco
  let maxCapacity = getCarrierMaxCapacity(carrier.shipClass, acoLevel)
  let currentLoad = carrier.embarkedFighters.len

  # Load fighters one at a time until capacity full or all requested loaded
  var loadedCount = 0
  var warnings: seq[string] = @[]

  for fighterId in cmd.fighterIds:
    # Check capacity
    if currentLoad + loadedCount >= maxCapacity:
      warnings.add(
        &"Carrier at capacity ({maxCapacity} fighters), remaining fighters not loaded"
      )
      break

    # Validate fighter exists and is at colony
    if fighterId notin colony.fighterIds:
      warnings.add(&"Fighter {fighterId} not found at colony, skipping")
      continue

    # Get fighter ship entity
    let fighterOpt = state.ship(fighterId)
    if fighterOpt.isNone:
      warnings.add(&"Fighter ship {fighterId} entity not found, skipping")
      continue

    var fighter = fighterOpt.get()

    # Load fighter
    carrier.embarkedFighters.add(fighterId)
    fighter.assignedToCarrier = some(carrierShipId)
    fighter.fleetId = sourceFleetId

    # Remove from colony's fighter pool
    colony.fighterIds.keepItIf(it != fighterId)
    loadedCount += 1

    # Update fighter entity
    state.updateShip(fighterId, fighter)

    logDebug(
      "Fleet",
      &"Loaded Fighter {fighterId} onto carrier {carrierShipId} " &
        &"({currentLoad + loadedCount}/{maxCapacity})"
    )

  # Update carrier ship in entity manager
  state.updateShip(carrierShipId, carrier)

  # Update colony in entity manager
  state.updateColony(colony.id, colony)

  return ZeroTurnResult(
    success: true, error: "", fightersLoaded: int32(loadedCount), warnings: warnings
  )

proc executeUnloadFighters*(
    state: var GameState, cmd: ZeroTurnCommand, events: var seq[GameEvent]
): ZeroTurnResult =
  ## Unload fighter ships from carrier to colony
  ## Requires: Fleet at friendly colony

  let sourceFleetId = cmd.sourceFleetId.get()
  let carrierShipId = cmd.carrierShipId.get()

  # Get fleet via entity manager
  let fleetOpt = state.fleet(sourceFleetId)
  if fleetOpt.isNone:
    return ZeroTurnResult(success: false, error: "Fleet not found", warnings: @[])

  let fleet = fleetOpt.get()
  let systemId = fleet.location

  # Get carrier ship via entity manager
  let carrierOpt = state.ship(carrierShipId)
  if carrierOpt.isNone:
    return ZeroTurnResult(
      success: false, error: "Carrier ship not found", warnings: @[]
    )

  var carrier = carrierOpt.get()

  # Validate carrier ship is in the fleet
  if carrier.fleetId != sourceFleetId:
    return ZeroTurnResult(
      success: false, error: "Carrier ship not in specified fleet", warnings: @[]
    )

  # Get colony via bySystem index
  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isNone:
    return ZeroTurnResult(
      success: false, error: "No colony at fleet location", warnings: @[]
    )

  var colony = colonyOpt.get()

  # Unload fighters
  var unloadedCount = 0
  var warnings: seq[string] = @[]

  for fighterId in cmd.fighterIds:
    # Validate fighter is embarked on this carrier
    if fighterId notin carrier.embarkedFighters:
      warnings.add(&"Fighter {fighterId} not embarked on carrier, skipping")
      continue

    # Get fighter ship entity
    let fighterOpt = state.ship(fighterId)
    if fighterOpt.isNone:
      warnings.add(&"Fighter ship {fighterId} entity not found, skipping")
      continue

    var fighter = fighterOpt.get()

    # Unload fighter
    carrier.embarkedFighters.keepItIf(it != fighterId)
    fighter.assignedToCarrier = none(ShipId)
    fighter.fleetId = FleetId(0) # Unassigned (colony-based)

    # Add to colony's fighter pool
    colony.fighterIds.add(fighterId)
    unloadedCount += 1

    # Update fighter entity
    state.updateShip(fighterId, fighter)

    logDebug(
      "Fleet",
      &"Unloaded Fighter {fighterId} from carrier {carrierShipId} to colony {systemId}"
    )

  # Update carrier ship in entity manager
  state.updateShip(carrierShipId, carrier)

  # Update colony in entity manager
  state.updateColony(colony.id, colony)

  return ZeroTurnResult(
    success: true, error: "", fightersUnloaded: int32(unloadedCount), warnings: warnings
  )

proc executeTransferFighters*(
    state: var GameState, cmd: ZeroTurnCommand, events: var seq[GameEvent]
): ZeroTurnResult =
  ## Transfer fighter ships between carriers (mobile operations)
  ## Can happen anywhere - both carriers must be in same system and owned by same house

  let sourceCarrierShipId = cmd.sourceCarrierShipId.get()
  let targetCarrierShipId = cmd.targetCarrierShipId.get()

  # Get source carrier ship via entity manager
  let sourceCarrierOpt = state.ship(sourceCarrierShipId)
  if sourceCarrierOpt.isNone:
    return ZeroTurnResult(
      success: false, error: "Source carrier ship not found", warnings: @[]
    )

  var sourceCarrier = sourceCarrierOpt.get()

  # Validate source is a carrier
  if not isCarrier(sourceCarrier.shipClass):
    return ZeroTurnResult(
      success: false, error: "Source ship is not a carrier", warnings: @[]
    )

  # Get source fleet to determine location
  let sourceFleetOpt = state.fleet(sourceCarrier.fleetId)
  if sourceFleetOpt.isNone:
    return ZeroTurnResult(
      success: false, error: "Source carrier fleet not found", warnings: @[]
    )

  let sourceLocation = sourceFleetOpt.get().location

  # Get target carrier ship via entity manager
  let targetCarrierOpt = state.ship(targetCarrierShipId)
  if targetCarrierOpt.isNone:
    return ZeroTurnResult(
      success: false, error: "Target carrier ship not found", warnings: @[]
    )

  var targetCarrier = targetCarrierOpt.get()

  # Validate target is a carrier
  if not isCarrier(targetCarrier.shipClass):
    return ZeroTurnResult(
      success: false, error: "Target ship is not a carrier", warnings: @[]
    )

  # Get target fleet to verify location
  let targetFleetOpt = state.fleet(targetCarrier.fleetId)
  if targetFleetOpt.isNone:
    return ZeroTurnResult(
      success: false, error: "Target carrier fleet not found", warnings: @[]
    )

  let targetLocation = targetFleetOpt.get().location

  # Verify both carriers are in same location
  if sourceLocation != targetLocation:
    return ZeroTurnResult(
      success: false,
      error: "Carriers must be in same system for fighter transfer",
      warnings: @[],
    )

  # Verify both carriers owned by same house
  if sourceCarrier.houseId != targetCarrier.houseId:
    return ZeroTurnResult(
      success: false, error: "Cannot transfer fighters between houses", warnings: @[]
    )

  # Get ACO tech level for capacity calculation
  let houseOpt = state.house(cmd.houseId)
  if houseOpt.isNone:
    return ZeroTurnResult(success: false, error: "House not found", warnings: @[])

  let acoLevel = houseOpt.get().techTree.levels.aco
  let targetMaxCapacity = getCarrierMaxCapacity(targetCarrier.shipClass, acoLevel)
  let targetCurrentLoad = targetCarrier.embarkedFighters.len

  # Transfer fighters
  var transferredCount = 0
  var warnings: seq[string] = @[]

  for fighterId in cmd.fighterIds:
    # Check target capacity
    if targetCurrentLoad + transferredCount >= targetMaxCapacity:
      warnings.add(
        &"Target carrier at capacity ({targetMaxCapacity} fighters), remaining fighters not transferred"
      )
      break

    # Validate fighter is embarked on source carrier
    if fighterId notin sourceCarrier.embarkedFighters:
      warnings.add(&"Fighter {fighterId} not embarked on source carrier, skipping")
      continue

    # Get fighter ship entity
    let fighterOpt = state.ship(fighterId)
    if fighterOpt.isNone:
      warnings.add(&"Fighter ship {fighterId} entity not found, skipping")
      continue

    var fighter = fighterOpt.get()

    # Transfer fighter
    sourceCarrier.embarkedFighters.keepItIf(it != fighterId)
    targetCarrier.embarkedFighters.add(fighterId)
    fighter.assignedToCarrier = some(targetCarrierShipId)

    transferredCount += 1

    # Update fighter entity
    state.updateShip(fighterId, fighter)

    logDebug(
      "Fleet",
      &"Transferred Fighter {fighterId} from carrier {sourceCarrierShipId} " &
        &"to carrier {targetCarrierShipId}"
    )

  # Update both carrier ships in entity manager
  state.updateShip(sourceCarrierShipId, sourceCarrier)
  state.updateShip(targetCarrierShipId, targetCarrier)

  return ZeroTurnResult(
    success: true,
    error: "",
    fightersTransferred: int32(transferredCount),
    warnings: warnings,
  )

# ============================================================================
# Main API Entry Point
# ============================================================================

proc submitZeroTurnCommand*(
    state: var GameState, cmd: ZeroTurnCommand, events: var seq[GameEvent]
): ZeroTurnResult =
  ## Main entry point for zero-turn administrative commands
  ## Validates and executes command immediately (0 turns)
  ##
  ## Execution Flow:
  ##   1. Validate command (ownership, location, parameters)
  ##   2. Execute command (modify game state)
  ##   3. Emit events (Phase 7b)
  ##   4. Return immediate result
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
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  # Step 2: Execute based on command type (emits events)
  case cmd.commandType
  of ZeroTurnCommandType.DetachShips:
    return executeDetachShips(state, cmd, events)
  of ZeroTurnCommandType.TransferShips:
    return executeTransferShips(state, cmd, events)
  of ZeroTurnCommandType.MergeFleets:
    return executeMergeFleets(state, cmd, events)
  of ZeroTurnCommandType.LoadCargo:
    return executeLoadCargo(state, cmd, events)
  of ZeroTurnCommandType.UnloadCargo:
    return executeUnloadCargo(state, cmd, events)
  of ZeroTurnCommandType.LoadFighters:
    return executeLoadFighters(state, cmd, events)
  of ZeroTurnCommandType.UnloadFighters:
    return executeUnloadFighters(state, cmd, events)
  of ZeroTurnCommandType.TransferFighters:
    return executeTransferFighters(state, cmd, events)

# Export main types
export ZeroTurnCommandType, ZeroTurnCommand, ZeroTurnResult, ValidationResult
