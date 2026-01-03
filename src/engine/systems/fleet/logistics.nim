## Zero-Turn Fleet Logistics System
##
## Unified administrative command system for fleet/cargo/squadron operations
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

import ../../types/[core, game_state, fleet, squadron, ship, colony, event, ground_unit]
import ../../state/[engine, iterators]
import ../../entities/[fleet_ops, squadron_ops, colony_ops]
import ../fleet/entity as fleet_entity
import ../squadron/entity as squadron_entity
import ../ship/entity as ship_entity
import
  ../../config/population_config # For population config (soulsPerPtu, ptuSizeMillions)
import ../../event_factory/init as event_factory
import std/[options, algorithm, tables, strformat, sequtils]
import ../../../common/logger

# ============================================================================
# Type Definitions
# ============================================================================

type
  ZeroTurnCommandType* {.pure.} = enum
    ## Administrative commands that execute immediately (0 turns)
    ## All require fleet/squadron to be at friendly colony
    ## Execute during order submission phase, NOT turn resolution

    # Fleet reorganization (from FleetManagementCommand)
    DetachShips ## Split ships from fleet → create new fleet
    TransferShips ## Move ships between existing fleets
    MergeFleets ## Merge entire source fleet into target fleet

    # Cargo operations (from CargoManagementOrder)
    LoadCargo ## Load marines/colonists onto transport squadrons
    UnloadCargo ## Unload cargo from transport squadrons

    # Fighter operations (from FighterManagementOrder)
    LoadFighters ## Load fighter squadrons from colony to carrier
    UnloadFighters ## Unload fighter squadrons from carrier to colony
    TransferFighters ## Transfer fighter squadrons between carriers

    # Squadron operations (from SquadronManagementOrder)
    FormSquadron ## Create squadron from commissioned ships pool
    TransferShipBetweenSquadrons ## Move individual ship between squadrons
    AssignSquadronToFleet ## Move squadron between fleets (or create new fleet)

  ZeroTurnCommand* = object
    ## Immediate-execution administrative command
    ## Executes synchronously during order submission (NOT in OrderPacket)
    ## Returns immediate result (success/failure + error message)
    houseId*: HouseId
    commandType*: ZeroTurnCommandType

    # Context (varies by command type)
    colonySystem*: Option[SystemId] ## Colony where action occurs (for squadron ops)
    sourceFleetId*: Option[FleetId] ## Source fleet for fleet/cargo operations
    targetFleetId*: Option[FleetId] ## Target fleet for transfer/merge

    # Ship/squadron selection
    shipIndices*: seq[int] ## For ship selection (DetachShips, FormSquadron)
    sourceSquadronId*: Option[string] ## For TransferShipBetweenSquadrons
    targetSquadronId*: Option[string] ## For TransferShipBetweenSquadrons
    squadronId*: Option[string] ## For AssignSquadronToFleet
    shipIndex*: Option[int] ## For TransferShipBetweenSquadrons (single ship)

    # Cargo-specific
    cargoType*: Option[CargoClass] ## Type: Marines, Colonists
    cargoQuantity*: Option[int] ## Amount to load/unload (0 = all available)

    # Fighter-specific
    fighterSquadronIndices*: seq[int]
      ## Colony fighter squadron indices (for LoadFighters)
    carrierSquadronId*: Option[string] ## Carrier squadron ID (for Load/Unload)
    embarkedFighterIndices*: seq[int] ## Embarked fighter indices (for Unload/Transfer)
    sourceCarrierSquadronId*: Option[string] ## Source carrier (for TransferFighters)
    targetCarrierSquadronId*: Option[string] ## Target carrier (for TransferFighters)

    # Squadron formation
    newSquadronId*: Option[string] ## Custom squadron ID for FormSquadron
    newFleetId*: Option[FleetId] ## Custom fleet ID for DetachShips/AssignSquadronToFleet

  ZeroTurnResult* = object ## Immediate result from zero-turn command execution
    success*: bool
    error*: string ## Human-readable error message

    # Optional result data
    newFleetId*: Option[FleetId] ## For DetachShips, AssignSquadronToFleet
    newSquadronId*: Option[string] ## For FormSquadron
    cargoLoaded*: int ## For LoadCargo (actual amount loaded)
    cargoUnloaded*: int ## For UnloadCargo (actual amount unloaded)
    fightersLoaded*: int ## For LoadFighters (squadrons loaded)
    fightersUnloaded*: int ## For UnloadFighters (squadrons unloaded)
    fightersTransferred*: int ## For TransferFighters (squadrons transferred)
    warnings*: seq[string] ## Non-fatal issues

  ValidationResult* = object ## Validation result (used internally)
    valid*: bool
    error*: string

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
    fleet: Fleet, squadrons: Squadrons, ships: Ships, indices: seq[int]
): ValidationResult =
  ## DRY: Validate ship indices are valid and not selecting all ships

  let allShips = fleet_entity.allShips(fleet, squadrons, ships)

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

  # Layer 3: Squadron operations validation
  if cmd.commandType in {
    ZeroTurnCommandType.FormSquadron, ZeroTurnCommandType.TransferShipBetweenSquadrons,
    ZeroTurnCommandType.AssignSquadronToFleet,
  }:
    if cmd.colonySystem.isNone:
      return ValidationResult(
        valid: false, error: "Colony system required for squadron operations"
      )

    result = validateColonyOwnership(state, cmd.colonySystem.get(), cmd.houseId)
    if not result.valid:
      return result

  # Layer 4: Command-specific validation
  case cmd.commandType
  of ZeroTurnCommandType.DetachShips, ZeroTurnCommandType.TransferShips:
    # Validate ship indices
    let fleetOpt = state.fleet(cmd.sourceFleetId.get())
    if fleetOpt.isNone:
      return ValidationResult(valid: false, error: "Source fleet not found")
    let fleet = fleetOpt.get()

    result = validateShipIndices(fleet, state.squadrons[], state.ships, cmd.shipIndices)
    if not result.valid:
      return result

    # DetachShips specific: cannot detach transport-only fleet (except ETACs)
    if cmd.commandType == ZeroTurnCommandType.DetachShips:
      let squadronIndices = fleet_entity.translateShipIndicesToSquadrons(
        fleet, state.squadrons[], cmd.shipIndices
      )

      # Check if only Expansion squadrons (ETACs) are being detached
      # ETACs don't need combat escorts, but transports do
      if squadronIndices.len > 0:
        var onlyExpansion = true
        var hasNonETAC = false

        for idx in squadronIndices:
          if idx < 0 or idx >= fleet.squadrons.len:
            continue
          let squadronId = fleet.squadrons[idx]
          let squadronOpt = state.squadron(squadronId)
          if squadronOpt.isNone:
            continue
          let squadron = squadronOpt.get()

          if squadron.squadronType != SquadronClass.Expansion:
            onlyExpansion = false
          else:
            # Check flagship ship class
            let flagshipOpt = state.ship(squadron.flagshipId)
            if flagshipOpt.isSome:
              let flagship = flagshipOpt.get()
              if flagship.shipClass != ShipClass.ETAC:
                hasNonETAC = true

        if onlyExpansion and hasNonETAC:
          # Only detaching Expansion squadrons, but some are non-ETAC transports
          # These need combat escorts
          return ValidationResult(
            valid: false,
            error: "Cannot detach non-ETAC transport squadrons without combat escorts",
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
      let mergeCheck = fleet_entity.canMergeWith(fleet, targetFleet, state.squadrons[])
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
      fleet_entity.canMergeWith(sourceFleet, targetFleet, state.squadrons[])
    if not mergeCheck.canMerge:
      return ValidationResult(valid: false, error: mergeCheck.reason)
  of ZeroTurnCommandType.LoadCargo, ZeroTurnCommandType.UnloadCargo:
    # Validate cargo type specified for LoadCargo
    if cmd.commandType == ZeroTurnCommandType.LoadCargo:
      if cmd.cargoType.isNone:
        return
          ValidationResult(valid: false, error: "Cargo type required for LoadCargo")
  of ZeroTurnCommandType.LoadFighters:
    # Validate carrier squadron ID
    if cmd.carrierSquadronId.isNone:
      return ValidationResult(valid: false, error: "Carrier squadron ID required")
    # Validate at least one fighter squadron selected
    if cmd.fighterSquadronIndices.len == 0:
      return ValidationResult(
        valid: false, error: "Must select at least one fighter squadron to load"
      )
  of ZeroTurnCommandType.UnloadFighters:
    # Validate carrier squadron ID
    if cmd.carrierSquadronId.isNone:
      return ValidationResult(valid: false, error: "Carrier squadron ID required")
    # Validate at least one embarked fighter selected
    if cmd.embarkedFighterIndices.len == 0:
      return ValidationResult(
        valid: false, error: "Must select at least one embarked fighter to unload"
      )
  of ZeroTurnCommandType.TransferFighters:
    # TransferFighters can happen anywhere (mobile operations)
    # Validate source and target carrier squadron IDs
    if cmd.sourceCarrierSquadronId.isNone:
      return
        ValidationResult(valid: false, error: "Source carrier squadron ID required")
    if cmd.targetCarrierSquadronId.isNone:
      return
        ValidationResult(valid: false, error: "Target carrier squadron ID required")
    if cmd.sourceCarrierSquadronId.get() == cmd.targetCarrierSquadronId.get():
      return ValidationResult(
        valid: false, error: "Cannot transfer fighters to same carrier"
      )
    # Validate at least one embarked fighter selected
    if cmd.embarkedFighterIndices.len == 0:
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
  of ZeroTurnCommandType.FormSquadron:
    # Must specify ships from commissioned pool
    if cmd.shipIndices.len == 0:
      return ValidationResult(
        valid: false, error: "Must select at least one ship for squadron"
      )
  of ZeroTurnCommandType.TransferShipBetweenSquadrons:
    # Must specify source/target squadrons and ship index
    if cmd.sourceSquadronId.isNone or cmd.targetSquadronId.isNone or cmd.shipIndex.isNone:
      return ValidationResult(
        valid: false,
        error: "Must specify source squadron, target squadron, and ship index",
      )
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
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  var sourceFleet = sourceFleetOpt.get()
  let systemId = sourceFleet.location

  # Translate ship indices to squadron indices
  let squadronIndices = fleet_entity.translateShipIndicesToSquadrons(
    sourceFleet, state.squadrons[], cmd.shipIndices
  )

  # Split squadrons (existing proc)
  let splitResult = fleet_entity.split(sourceFleet, squadronIndices)

  # Generate new fleet ID if not provided
  let newFleetId =
    if cmd.newFleetId.isSome:
      cmd.newFleetId.get()
    else:
      generateFleetId(state)

  # Create new fleet structure
  var newFleet = Fleet(
    id: newFleetId,
    squadrons: splitResult.squadrons,
    houseId: cmd.houseId,
    location: sourceFleet.location,
    status: FleetStatus.Active,
    autoBalanceSquadrons: true,
    missionState: FleetMissionState.None,
    missionType: none(int32),
    missionTarget: none(SystemId),
    missionStartTurn: 0,
  )

  let squadronsDetached = newFleet.squadrons.len

  # Note: balanceSquadrons() is deprecated, removed calls

  # Check if source fleet is now empty after detaching
  if fleet_entity.isEmpty(sourceFleet):
    # Delete empty source fleet and cleanup orders
    cleanupEmptyFleet(state, cmd.sourceFleetId.get())
    logFleet(
      &"DetachShips: Detached all ships from {cmd.sourceFleetId.get()}, deleted source fleet, created new fleet {newFleetId}"
    )
  else:
    # Write back modified source fleet via entity manager
    state.updateFleet(cmd.sourceFleetId.get(), sourceFleet)
    logFleet(
      &"DetachShips: Created fleet {newFleetId} with {newFleet.squadrons.len} squadrons"
    )

  # Add new fleet to state via entity manager
  state.addFleet(newFleetId, newFleet)
  # Update indexes
  state.fleets.bySystem.mgetOrPut(newFleet.location, @[]).add(newFleetId)
  state.fleets.byOwner.mgetOrPut(newFleet.houseId, @[]).add(newFleetId)

  # Emit FleetDetachment event (Phase 7b)
  events.add(
    event_factory.fleetDetachment(
      cmd.houseId, cmd.sourceFleetId.get(), newFleetId, squadronsDetached, systemId
    )
  )

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: some(newFleetId),
    newSquadronId: none(string),
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
      newSquadronId: none(string),
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
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  var sourceFleet = sourceFleetOpt.get()
  var targetFleet = targetFleetOpt.get()
  let systemId = sourceFleet.location

  # Translate ship indices to squadron indices
  let squadronIndices = fleet_entity.translateShipIndicesToSquadrons(
    sourceFleet, state.squadrons[], cmd.shipIndices
  )
  let squadronsTransferred = squadronIndices.len

  # Transfer squadrons
  let transferredFleet = fleet_entity.split(sourceFleet, squadronIndices)
  fleet_entity.merge(targetFleet, transferredFleet)

  # Note: balanceSquadrons() is deprecated, removed calls

  # Write back modified target fleet via entity manager
  state.updateFleet(targetFleetId, targetFleet)

  # Check if source fleet is now empty
  if fleet_entity.isEmpty(sourceFleet):
    # Delete empty fleet and cleanup orders (DRY helper)
    # NOTE: We don't write sourceFleet back since we're deleting it
    cleanupEmptyFleet(state, cmd.sourceFleetId.get())
    logFleet(
      &"TransferShips: Merged all ships from {cmd.sourceFleetId.get()} into {targetFleetId}, deleted source fleet"
    )
  else:
    # Write back modified source fleet via entity manager
    state.updateFleet(cmd.sourceFleetId.get(), sourceFleet)
    logFleet(
      &"TransferShips: Transferred {squadronIndices.len} squadrons from {cmd.sourceFleetId.get()} to {targetFleetId}"
    )

  # Emit FleetTransfer event (Phase 7b)
  events.add(
    event_factory.fleetTransfer(
      cmd.houseId,
      cmd.sourceFleetId.get(),
      targetFleetId,
      squadronsTransferred,
      systemId,
    )
  )

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: none(string),
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
      newSquadronId: none(string),
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
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  let sourceFleet = sourceFleetOpt.get()
  var targetFleet = targetFleetOpt.get()

  let squadronsMerged = sourceFleet.squadrons.len
  let systemId = sourceFleet.location

  # Merge all squadrons
  fleet_entity.merge(targetFleet, sourceFleet)

  # Note: balanceSquadrons() is deprecated, removed call

  # Write back modified target fleet via entity manager
  state.updateFleet(targetFleetId, targetFleet)

  # Delete source fleet using DRY helper (handles indexes and commands)
  cleanupEmptyFleet(state, cmd.sourceFleetId.get())

  logFleet(
    &"MergeFleets: Merged {squadronsMerged} squadrons from {cmd.sourceFleetId.get()} into {targetFleetId}"
  )

  # Emit FleetMerged event (Phase 7b)
  events.add(
    event_factory.fleetMerged(
      cmd.houseId, cmd.sourceFleetId.get(), targetFleetId, squadronsMerged, systemId
    )
  )

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: none(string),
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
      newSquadronId: none(string),
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
      newSquadronId: none(string),
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
      newSquadronId: none(string),
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
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  # If quantity = 0, load all available
  if requestedQty == 0:
    requestedQty = availableUnits

  # Load cargo onto compatible transport squadrons (Expansion/Auxiliary flagships)
  var remainingToLoad = min(requestedQty, availableUnits)

  # Iterate over squadron IDs, get entities via entity manager
  for squadronId in fleet.squadrons:
    if remainingToLoad <= 0:
      break

    # Get squadron entity
    let squadronOpt = state.squadron(squadronId)
    if squadronOpt.isNone:
      continue

    let squadron = squadronOpt.get()

    # Only Expansion and Auxiliary squadrons carry cargo
    if squadron.squadronType notin {SquadronClass.Expansion, SquadronClass.Auxiliary}:
      continue

    # Get flagship ship entity
    let flagshipOpt = state.ship(squadron.flagshipId)
    if flagshipOpt.isNone:
      continue

    var flagship = flagshipOpt.get()

    if flagship.isCrippled:
      continue

    # Determine ship capacity and compatible cargo type
    let shipCargoType =
      case flagship.shipClass
      of ShipClass.TroopTransport: CargoClass.Marines
      of ShipClass.ETAC: CargoClass.Colonists
      else: CargoClass.None

    if shipCargoType != cargoType:
      continue # Ship can't carry this cargo type

    # Try to load cargo onto this flagship
    let currentCargo =
      if flagship.cargo.isSome:
        flagship.cargo.get()
      else:
        ShipCargo(cargoType: CargoClass.None, quantity: 0, capacity: 0)
    let loadAmount = min(remainingToLoad, currentCargo.capacity - currentCargo.quantity)

    if loadAmount > 0:
      var newCargo = currentCargo
      newCargo.cargoType = cargoType
      newCargo.quantity += loadAmount
      flagship.cargo = some(newCargo)

      # Update ship entity
      state.updateShip(squadron.flagshipId, flagship)

      totalLoaded += loadAmount
      remainingToLoad -= loadAmount
      logDebug(
        "Economy",
        &"Loaded {loadAmount} {cargoType} onto {flagship.shipClass} squadron {squadronId}",
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
      let soulsToLoad = totalLoaded * soulsPerPtu()
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
    state.updateColony(colonyId, colony)
    logEconomy(
      &"LoadCargo: Successfully loaded {totalLoaded} {cargoType} onto fleet {fleetId} at system {colonySystem}"
    )

    # Emit CargoLoaded event (Phase 7b)
    events.add(
      event_factory.cargoLoaded(
        cmd.houseId, fleetId, $cargoType, totalLoaded, colonySystem
      )
    )

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: none(string),
    cargoLoaded: totalLoaded,
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
      newSquadronId: none(string),
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
      newSquadronId: none(string),
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
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  var colony = colonyOpt.get()
  var totalUnloaded = 0
  var unloadedType = CargoClass.None

  # Unload cargo from transport squadrons (Expansion/Auxiliary flagships)
  # Iterate over squadron IDs, get entities via entity manager
  for squadronId in fleet.squadrons:
    # Get squadron entity
    let squadronOpt = state.squadron(squadronId)
    if squadronOpt.isNone:
      continue

    let squadron = squadronOpt.get()

    # Only Expansion and Auxiliary squadrons carry cargo
    if squadron.squadronType notin {SquadronClass.Expansion, SquadronClass.Auxiliary}:
      continue

    # Get flagship ship entity
    let flagshipOpt = state.ship(squadron.flagshipId)
    if flagshipOpt.isNone:
      continue

    var flagship = flagshipOpt.get()

    if flagship.cargo.isNone:
      continue # No cargo to unload

    let cargo = flagship.cargo.get()
    if cargo.cargoType == CargoClass.None or cargo.quantity == 0:
      continue # Empty cargo

    # Unload cargo back to colony inventory
    let cargoType = cargo.cargoType
    let quantity = cargo.quantity
    totalUnloaded += quantity
    unloadedType = cargoType

    case cargoType
    of CargoClass.Marines:
      colony.marines += quantity
      logDebug(
        "Economy", &"Unloaded {quantity} Marines from squadron {squadronId} to colony"
      )
    of CargoClass.Colonists:
      # Colonists are delivered to population: 1 PTU = 50k souls
      # Use souls field for exact counting (no rounding errors)
      let soulsToUnload = quantity * soulsPerPtu()
      colony.souls += soulsToUnload
      # Update display field (population in millions)
      colony.population = colony.souls div 1_000_000
      logDebug(
        "Economy",
        &"Unloaded {quantity} PTU ({soulsToUnload} souls, {quantity.float * ptuSizeMillions()}M) from squadron {squadronId} to colony",
      )
    else:
      discard

    # Clear cargo from flagship
    flagship.cargo =
      some(ShipCargo(cargoType: CargoClass.None, quantity: 0, capacity: cargo.capacity))

    # Update ship entity
    state.updateShip(squadron.flagshipId, flagship)

  # Write back modified colony
  if totalUnloaded > 0:
    state.updateColony(colonyId, colony)
    logEconomy(
      &"UnloadCargo: Successfully unloaded {totalUnloaded} {unloadedType} from fleet {fleetId} at system {colonySystem}"
    )

    # Emit CargoUnloaded event (Phase 7b)
    events.add(
      event_factory.cargoUnloaded(
        cmd.houseId, fleetId, $unloadedType, totalUnloaded, colonySystem
      )
    )

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: none(string),
    cargoLoaded: 0,
    cargoUnloaded: totalUnloaded,
    warnings:
      if totalUnloaded == 0:
        @["No cargo to unload"]
      else:
        @[],
  )

# ============================================================================
# Execution - Squadron Operations (from economy_resolution.nim)
# ============================================================================

proc executeFormSquadron*(
    state: var GameState, cmd: ZeroTurnCommand, events: var seq[GameEvent]
): ZeroTurnResult =
  ## Create new squadron from colony's commissioned ships pool
  ## NEW: Not in current implementation - gives players manual control
  ## before auto-assignment runs during turn resolution

  let colonySystem = cmd.colonySystem.get()

  # Get colony via bySystem index
  if not state.colonies.bySystem.hasKey(colonySystem):
    return ZeroTurnResult(
      success: false,
      error: "Colony not found",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
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
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  var colony = colonyOpt.get()

  # Validate ships exist in unassigned pool
  if cmd.shipIndices.len > colony.unassignedSquadronIds.len:
    return ZeroTurnResult(
      success: false,
      error:
        &"Only {colony.unassignedSquadronIds.len} unassigned squadrons available at colony",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  # For now, FormSquadron simply selects existing squadrons from unassigned pool
  # In the future, this could be extended to create squadrons from individual ships
  var selectedSquadronIds: seq[SquadronId] = @[]
  var remainingSquadronIds: seq[SquadronId] = @[]

  for i, squadronId in colony.unassignedSquadronIds:
    if i in cmd.shipIndices:
      selectedSquadronIds.add(squadronId)
    else:
      remainingSquadronIds.add(squadronId)

  if selectedSquadronIds.len == 0:
    return ZeroTurnResult(
      success: false,
      error: "No squadrons selected from unassigned pool",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  # Update colony's unassigned squadrons
  colony.unassignedSquadronIds = remainingSquadronIds
  state.updateColony(colonyId, colony)

  # Generate squadron IDs (if not custom provided)
  let newSquadronId =
    if cmd.newSquadronId.isSome:
      cmd.newSquadronId.get()
    else:
      selectedSquadronIds[0] # Use first selected squadron's ID as representative

  logFleet(
    &"FormSquadron: Selected {selectedSquadronIds.len} squadrons from unassigned pool at {colonySystem}"
  )

  # Note: Squadrons remain in unassigned pool but are now "formed" (tracked)
  # Player can then use AssignSquadronToFleet to assign to a fleet

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: some(newSquadronId),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings:
      @[
        &"Selected {selectedSquadronIds.len} squadrons, use AssignSquadronToFleet to assign to fleet"
      ],
  )

proc executeTransferShipBetweenSquadrons*(
    state: var GameState, cmd: ZeroTurnCommand, events: var seq[GameEvent]
): ZeroTurnResult =
  ## Transfer ship between squadrons at this colony
  ## Source: economy_resolution.nim:216-291

  let colonySystem = cmd.colonySystem.get()
  let sourceSquadronId = cmd.sourceSquadronId.get()
  let targetSquadronId = cmd.targetSquadronId.get()
  let shipIndex = cmd.shipIndex.get()

  # Find source and target squadrons in fleets at this colony
  # Use entity manager to access fleets
  var sourceFleetId: Option[FleetId] = none(FleetId)
  var targetFleetId: Option[FleetId] = none(FleetId)

  # Locate source squadron by searching fleets at this colony
  if state.fleets.bySystem.hasKey(colonySystem):
    for fleetId in state.fleets.bySystem[colonySystem]:
      let fleetOpt = state.fleet(fleetId)
      if fleetOpt.isNone:
        continue

      let fleet = fleetOpt.get()
      if fleet.houseId != cmd.houseId:
        continue

      # Check if this fleet has the source squadron
      if sourceSquadronId in fleet.squadrons:
        sourceFleetId = some(fleetId)
        break

  if sourceFleetId.isNone:
    return ZeroTurnResult(
      success: false,
      error: &"Source squadron {sourceSquadronId} not found at colony",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  # Locate target squadron
  if state.fleets.bySystem.hasKey(colonySystem):
    for fleetId in state.fleets.bySystem[colonySystem]:
      let fleetOpt = state.fleet(fleetId)
      if fleetOpt.isNone:
        continue

      let fleet = fleetOpt.get()
      if fleet.houseId != cmd.houseId:
        continue

      # Check if this fleet has the target squadron
      if targetSquadronId in fleet.squadrons:
        targetFleetId = some(fleetId)
        break

  if targetFleetId.isNone:
    return ZeroTurnResult(
      success: false,
      error: &"Target squadron {targetSquadronId} not found at colony",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  # Get source squadron via entity manager
  let sourceSquadOpt = state.squadron(sourceSquadronId)
  if sourceSquadOpt.isNone:
    return ZeroTurnResult(
      success: false,
      error: &"Source squadron {sourceSquadronId} not found in entity manager",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  var sourceSquad = sourceSquadOpt.get()

  # Validate ship index
  if shipIndex < 0 or shipIndex >= sourceSquad.ships.len:
    return ZeroTurnResult(
      success: false,
      error:
        &"Invalid ship index {shipIndex} (squadron has {sourceSquad.ships.len} ships)",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  # Remove ship from source squadron using squadron_entity helper
  let shipIdOpt = squadron_entity.removeShip(sourceSquad, shipIndex)
  if shipIdOpt.isNone:
    return ZeroTurnResult(
      success: false,
      error: "Could not remove ship from source squadron",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  let shipId = shipIdOpt.get()

  # Get target squadron via entity manager
  let targetSquadOpt = state.squadron(targetSquadronId)
  if targetSquadOpt.isNone:
    # ROLLBACK: Put ship back in source squadron
    discard squadron_entity.addShip(sourceSquad, shipId, state.ships)
    state.updateSquadron(sourceSquadronId, sourceSquad)
    return ZeroTurnResult(
      success: false,
      error: &"Target squadron {targetSquadronId} not found in entity manager",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  var targetSquad = targetSquadOpt.get()

  # Try to add ship to target squadron using squadron_entity helper
  if not squadron_entity.addShip(targetSquad, shipId, state.ships):
    # ROLLBACK: Put ship back in source squadron
    discard squadron_entity.addShip(sourceSquad, shipId, state.ships)
    state.updateSquadron(sourceSquadronId, sourceSquad)
    return ZeroTurnResult(
      success: false,
      error: "Could not add ship to target squadron (may be full or incompatible)",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  # Update both squadrons in entity manager
  state.updateSquadron(sourceSquadronId, sourceSquad)
  state.updateSquadron(targetSquadronId, targetSquad)

  logFleet(
    &"TransferShipBetweenSquadrons: Transferred ship from {sourceSquadronId} to {targetSquadronId}"
  )

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: none(string),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings: @[],
  )

proc executeAssignSquadronToFleet*(
    state: var GameState, cmd: ZeroTurnCommand, events: var seq[GameEvent]
): ZeroTurnResult =
  ## Assign existing squadron to fleet (move between fleets or create new fleet)
  ## Source: economy_resolution.nim:293-382

  let colonySystem = cmd.colonySystem.get()
  let squadronId = cmd.squadronId.get()

  # Get colony via bySystem index
  if not state.colonies.bySystem.hasKey(colonySystem):
    return ZeroTurnResult(
      success: false,
      error: &"Colony not found at system {colonySystem}",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  let colonyOpt = state.colonyBySystem(colonySystem)
  if colonyOpt.isNone:
    return ZeroTurnResult(
      success: false,
      error: "Colony entity not found",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  var colony = colonyOpt.get()

  # Find squadron in existing fleets at this colony or in unassigned pool
  var foundInFleet = false
  var sourceFleetId: Option[FleetId] = none(FleetId)

  # Search fleets at colony using bySystem index
  if state.fleets.bySystem.hasKey(colonySystem):
    for fleetId in state.fleets.bySystem[colonySystem]:
      let fleetOpt = state.fleet(fleetId)
      if fleetOpt.isNone:
        continue

      let fleet = fleetOpt.get()
      if fleet.houseId != cmd.houseId:
        continue

      # Check if squadron is in this fleet
      if squadronId in fleet.squadrons:
        foundInFleet = true
        sourceFleetId = some(fleetId)
        break

  # If not found in fleets, check unassigned squadrons at colony
  var foundInUnassigned = false
  if not foundInFleet:
    if squadronId in colony.unassignedSquadronIds:
      foundInUnassigned = true
      # Remove from unassigned list
      colony.unassignedSquadronIds =
        colony.unassignedSquadronIds.filterIt(it != squadronId)
      state.updateColony(colonyId, colony)

  if not foundInFleet and not foundInUnassigned:
    return ZeroTurnResult(
      success: false,
      error: &"Squadron {squadronId} not found at colony {colonySystem}",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  # Get squadron entity to check its type
  let squadronOpt = state.squadron(squadronId)
  if squadronOpt.isNone:
    return ZeroTurnResult(
      success: false,
      error: &"Squadron {squadronId} entity not found",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[],
    )

  let squadron = squadronOpt.get()

  # Remove squadron from source fleet if it was in one
  if sourceFleetId.isSome:
    let srcFleetOpt = state.fleet(sourceFleetId.get())
    if srcFleetOpt.isSome:
      var srcFleet = srcFleetOpt.get()
      srcFleet.squadrons = srcFleet.squadrons.filterIt(it != squadronId)
      state.updateFleet(sourceFleetId.get(), srcFleet)

      # If source fleet is now empty, remove it and clean up orders (DRY helper)
      if srcFleet.squadrons.len == 0:
        cleanupEmptyFleet(state, sourceFleetId.get())

  # Add squadron to target fleet or create new one
  var resultFleetId: FleetId
  if cmd.targetFleetId.isSome:
    # Assign to existing fleet
    let targetId = cmd.targetFleetId.get()
    let targetFleetOpt = state.fleet(targetId)

    if targetFleetOpt.isNone:
      return ZeroTurnResult(
        success: false,
        error: &"Target fleet {targetId} does not exist",
        newFleetId: none(FleetId),
        newSquadronId: none(string),
        cargoLoaded: 0,
        cargoUnloaded: 0,
        warnings: @[],
      )

    var targetFleet = targetFleetOpt.get()

    # Only allow assignment to Active fleets (exclude Reserve and Mothballed)
    if targetFleet.status != FleetStatus.Active:
      return ZeroTurnResult(
        success: false,
        error:
          &"Cannot assign squadrons to {targetFleet.status} fleets (only Active fleets allowed)",
        newFleetId: none(FleetId),
        newSquadronId: none(string),
        cargoLoaded: 0,
        cargoUnloaded: 0,
        warnings: @[],
      )

    # CRITICAL: Validate squadron type compatibility (Intel never mixes)
    let squadronIsIntel = squadron.squadronType == SquadronClass.Intel
    var fleetHasIntel = false
    var fleetHasNonIntel = false

    # Check existing squadrons in fleet
    for existingSquadronId in targetFleet.squadrons:
      let existingSquadOpt = state.squadron(existingSquadronId)
      if existingSquadOpt.isSome:
        let existingSquad = existingSquadOpt.get()
        if existingSquad.squadronType == SquadronClass.Intel:
          fleetHasIntel = true
        else:
          fleetHasNonIntel = true

    if squadronIsIntel and fleetHasNonIntel:
      return ZeroTurnResult(
        success: false,
        error:
          "Cannot assign Intel squadron to fleet with non-Intel squadrons (Intel operations require dedicated fleets)",
        newFleetId: none(FleetId),
        newSquadronId: none(string),
        cargoLoaded: 0,
        cargoUnloaded: 0,
        warnings: @[],
      )

    if not squadronIsIntel and fleetHasIntel:
      return ZeroTurnResult(
        success: false,
        error:
          "Cannot assign non-Intel squadron to Intel-only fleet (Intel operations require dedicated fleets)",
        newFleetId: none(FleetId),
        newSquadronId: none(string),
        cargoLoaded: 0,
        cargoUnloaded: 0,
        warnings: @[],
      )

    targetFleet.squadrons.add(squadronId)
    state.updateFleet(targetId, targetFleet)
    resultFleetId = targetId
    logFleet(
      &"AssignSquadronToFleet: Assigned squadron {squadronId} to existing fleet {targetId}"
    )
  else:
    # Create new fleet
    let newFleetId =
      if cmd.newFleetId.isSome:
        cmd.newFleetId.get()
      else:
        generateFleetId(state)

    var newFleet = Fleet(
      id: newFleetId,
      houseId: cmd.houseId,
      location: colonySystem,
      squadrons: @[squadronId],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true,
      missionState: FleetMissionState.None,
      missionType: none(int32),
      missionTarget: none(SystemId),
      missionStartTurn: 0,
    )

    # Add to entity manager and update indexes
    state.addFleet(newFleetId, newFleet)
    state.fleets.bySystem.mgetOrPut(colonySystem, @[]).add(newFleetId)
    state.fleets.byOwner.mgetOrPut(cmd.houseId, @[]).add(newFleetId)

    resultFleetId = newFleetId
    logFleet(
      &"AssignSquadronToFleet: Created new fleet {newFleetId} with squadron {squadronId}"
    )

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: some(resultFleetId),
    newSquadronId: none(string),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings: @[],
  )

# ============================================================================
# Execution - Fighter Operations
# ============================================================================

proc executeLoadFighters*(
    state: var GameState, cmd: ZeroTurnCommand, events: var seq[GameEvent]
): ZeroTurnResult =
  ## Load fighter squadrons from colony onto carrier
  ## Requires: Fleet at friendly colony, carrier with available hangar space

  let sourceFleetId = cmd.sourceFleetId.get()
  let carrierSquadronId = cmd.carrierSquadronId.get()

  # Get fleet via entity manager
  let fleetOpt = state.fleet(sourceFleetId)
  if fleetOpt.isNone:
    return ZeroTurnResult(success: false, error: "Fleet not found", warnings: @[])

  let fleet = fleetOpt.get()
  let systemId = fleet.location

  # Check if carrier squadron is in fleet
  if carrierSquadronId notin fleet.squadrons:
    return ZeroTurnResult(
      success: false, error: "Carrier squadron not found in fleet", warnings: @[]
    )

  # Get carrier squadron via entity manager
  let carrierSquadOpt = state.squadron(carrierSquadronId)
  if carrierSquadOpt.isNone:
    return ZeroTurnResult(
      success: false, error: "Carrier squadron entity not found", warnings: @[]
    )

  var carrierSquadron = carrierSquadOpt.get()

  # Validate carrier using squadron_entity helper
  if not squadron_entity.isCarrier(carrierSquadron, state.ships):
    return ZeroTurnResult(
      success: false, error: "Squadron is not a carrier (CV/CX required)", warnings: @[]
    )

  # Get colony via bySystem index
  if not state.colonies.bySystem.hasKey(systemId):
    return ZeroTurnResult(
      success: false, error: "No colony at fleet location", warnings: @[]
    )

  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isNone:
    return
      ZeroTurnResult(success: false, error: "Colony entity not found", warnings: @[])

  var colony = colonyOpt.get()

  # Get ACO tech level for capacity calculation
  let acoLevel = state.houses[cmd.houseId].techTree.levels.advancedCarrierOps
  let maxCapacity =
    squadron_entity.getCarrierCapacity(carrierSquadron, state.ships, acoLevel)
  let currentLoad = carrierSquadron.embarkedFighters.len

  # Load fighters one at a time until capacity full or all requested loaded
  var loadedCount = 0
  var warnings: seq[string] = @[]

  for fighterIdx in cmd.fighterSquadronIndices:
    # Check capacity
    if currentLoad + loadedCount >= maxCapacity:
      warnings.add(
        &"Carrier at capacity ({maxCapacity} squadrons), remaining fighters not loaded"
      )
      break

    # Validate fighter index
    if fighterIdx < 0 or fighterIdx >= colony.fighterSquadronIds.len:
      warnings.add(&"Invalid fighter squadron index {fighterIdx}, skipping")
      continue

    # Get fighter squadron ID
    let fighterSquadronId = colony.fighterSquadronIds[fighterIdx]

    # Get fighter squadron entity for logging
    let fighterSquadOpt = state.squadron(fighterSquadronId)
    if fighterSquadOpt.isNone:
      warnings.add(&"Fighter squadron {fighterSquadronId} not found, skipping")
      continue

    let fighterSquadron = fighterSquadOpt.get()

    # Load fighter (add ID to carrier's embarkedFighters)
    carrierSquadron.embarkedFighters.add(fighterSquadronId)
    # Remove from colony's fighter pool
    colony.fighterSquadronIds.delete(fighterIdx)
    loadedCount += 1

    let totalFighters = 1 + fighterSquadron.ships.len
    logFleet(
      &"Loaded Fighter squadron {fighterSquadronId} ({totalFighters}/12) " &
        &"onto carrier {carrierSquadronId} ({currentLoad + loadedCount}/{maxCapacity})"
    )

  # Update carrier squadron in entity manager
  state.updateSquadron(carrierSquadronId, carrierSquadron)

  # Update colony in entity manager
  state.updateColony(colonyId, colony)

  return ZeroTurnResult(
    success: true, error: "", fightersLoaded: loadedCount, warnings: warnings
  )

proc executeUnloadFighters*(
    state: var GameState, cmd: ZeroTurnCommand, events: var seq[GameEvent]
): ZeroTurnResult =
  ## Unload fighter squadrons from carrier to colony
  ## Requires: Fleet at friendly colony

  let sourceFleetId = cmd.sourceFleetId.get()
  let carrierSquadronId = cmd.carrierSquadronId.get()

  # Get fleet via entity manager
  let fleetOpt = state.fleet(sourceFleetId)
  if fleetOpt.isNone:
    return ZeroTurnResult(success: false, error: "Fleet not found", warnings: @[])

  let fleet = fleetOpt.get()
  let systemId = fleet.location

  # Check if carrier squadron is in fleet
  if carrierSquadronId notin fleet.squadrons:
    return ZeroTurnResult(
      success: false, error: "Carrier squadron not found in fleet", warnings: @[]
    )

  # Get carrier squadron via entity manager
  let carrierSquadOpt = state.squadron(carrierSquadronId)
  if carrierSquadOpt.isNone:
    return ZeroTurnResult(
      success: false, error: "Carrier squadron entity not found", warnings: @[]
    )

  var carrierSquadron = carrierSquadOpt.get()

  # Get colony via bySystem index
  if not state.colonies.bySystem.hasKey(systemId):
    return ZeroTurnResult(
      success: false, error: "No colony at fleet location", warnings: @[]
    )

  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isNone:
    return
      ZeroTurnResult(success: false, error: "Colony entity not found", warnings: @[])

  var colony = colonyOpt.get()

  # Unload fighters (reverse order to avoid index issues)
  var unloadedCount = 0
  var warnings: seq[string] = @[]
  var sortedIndices = cmd.embarkedFighterIndices
  sortedIndices.sort(system.cmp, order = SortOrder.Descending)

  for fighterIdx in sortedIndices:
    # Validate fighter index
    if fighterIdx < 0 or fighterIdx >= carrierSquadron.embarkedFighters.len:
      warnings.add(&"Invalid embarked fighter index {fighterIdx}, skipping")
      continue

    # Get fighter squadron ID
    let fighterSquadronId = carrierSquadron.embarkedFighters[fighterIdx]

    # Get fighter squadron entity for logging
    let fighterSquadOpt = state.squadron(fighterSquadronId)
    if fighterSquadOpt.isSome:
      let fighterSquadron = fighterSquadOpt.get()
      let totalFighters = 1 + fighterSquadron.ships.len
      logFleet(
        &"Unloaded Fighter squadron {fighterSquadronId} ({totalFighters}/12) " &
          &"from carrier {carrierSquadronId} to colony {systemId}"
      )

    # Unload fighter (move ID from carrier to colony)
    colony.fighterSquadronIds.add(fighterSquadronId)
    carrierSquadron.embarkedFighters.delete(fighterIdx)
    unloadedCount += 1

  # Update carrier squadron in entity manager
  state.updateSquadron(carrierSquadronId, carrierSquadron)

  # Update colony in entity manager
  state.updateColony(colonyId, colony)

  return ZeroTurnResult(
    success: true, error: "", fightersUnloaded: unloadedCount, warnings: warnings
  )

proc executeTransferFighters*(
    state: var GameState, cmd: ZeroTurnCommand, events: var seq[GameEvent]
): ZeroTurnResult =
  ## Transfer fighter squadrons between carriers (mobile operations)
  ## Can happen anywhere - both carriers must be in same fleet or adjacent fleets at same location

  let sourceFleetId = cmd.sourceFleetId.get()
  let sourceCarrierSquadronId = cmd.sourceCarrierSquadronId.get()
  let targetCarrierSquadronId = cmd.targetCarrierSquadronId.get()

  # Get source fleet via entity manager
  let sourceFleetOpt = state.fleet(sourceFleetId)
  if sourceFleetOpt.isNone:
    return
      ZeroTurnResult(success: false, error: "Source fleet not found", warnings: @[])

  let sourceFleet = sourceFleetOpt.get()
  let sourceLocation = sourceFleet.location

  # Check if source carrier is in source fleet
  if sourceCarrierSquadronId notin sourceFleet.squadrons:
    return ZeroTurnResult(
      success: false, error: "Source carrier squadron not found in fleet", warnings: @[]
    )

  # Get source carrier squadron via entity manager
  let sourceCarrierOpt = state.squadron(sourceCarrierSquadronId)
  if sourceCarrierOpt.isNone:
    return ZeroTurnResult(
      success: false, error: "Source carrier squadron entity not found", warnings: @[]
    )

  var sourceCarrier = sourceCarrierOpt.get()

  # Validate source is a carrier
  if not squadron_entity.isCarrier(sourceCarrier, state.ships):
    return ZeroTurnResult(
      success: false, error: "Source squadron is not a carrier", warnings: @[]
    )

  # Find target carrier (could be in same fleet or different fleet at same location)
  var targetFleetId: Option[FleetId] = none(FleetId)

  # Check if target is in same fleet first
  if targetCarrierSquadronId in sourceFleet.squadrons:
    targetFleetId = some(sourceFleetId)
  else:
    # Search other fleets at same location using bySystem index
    if state.fleets.bySystem.hasKey(sourceLocation):
      for fleetId in state.fleets.bySystem[sourceLocation]:
        if fleetId == sourceFleetId:
          continue # Already checked

        let fleetOpt = state.fleet(fleetId)
        if fleetOpt.isNone:
          continue

        let fleet = fleetOpt.get()
        if fleet.houseId != cmd.houseId:
          continue

        if targetCarrierSquadronId in fleet.squadrons:
          targetFleetId = some(fleetId)
          break

  if targetFleetId.isNone:
    return ZeroTurnResult(
      success: false,
      error: "Target carrier squadron not found at same location",
      warnings: @[],
    )

  # Get target carrier squadron via entity manager
  let targetCarrierOpt = state.squadron(targetCarrierSquadronId)
  if targetCarrierOpt.isNone:
    return ZeroTurnResult(
      success: false, error: "Target carrier squadron entity not found", warnings: @[]
    )

  var targetCarrier = targetCarrierOpt.get()

  # Validate target is a carrier
  if not squadron_entity.isCarrier(targetCarrier, state.ships):
    return ZeroTurnResult(
      success: false, error: "Target squadron is not a carrier", warnings: @[]
    )

  # Get ACO tech level for capacity calculation
  let acoLevel = state.houses[cmd.houseId].techTree.levels.advancedCarrierOps
  let targetMaxCapacity =
    squadron_entity.getCarrierCapacity(targetCarrier, state.ships, acoLevel)
  let targetCurrentLoad = targetCarrier.embarkedFighters.len

  # Transfer fighters (reverse order to avoid index issues)
  var transferredCount = 0
  var warnings: seq[string] = @[]
  var sortedIndices = cmd.embarkedFighterIndices
  sortedIndices.sort(system.cmp, order = SortOrder.Descending)

  for fighterIdx in sortedIndices:
    # Check target capacity
    if targetCurrentLoad + transferredCount >= targetMaxCapacity:
      warnings.add(
        &"Target carrier at capacity ({targetMaxCapacity} squadrons), remaining fighters not transferred"
      )
      break

    # Validate fighter index
    if fighterIdx < 0 or fighterIdx >= sourceCarrier.embarkedFighters.len:
      warnings.add(&"Invalid embarked fighter index {fighterIdx}, skipping")
      continue

    # Get fighter squadron ID
    let fighterSquadronId = sourceCarrier.embarkedFighters[fighterIdx]

    # Get fighter squadron entity for logging
    let fighterSquadOpt = state.squadron(fighterSquadronId)
    if fighterSquadOpt.isSome:
      let fighterSquadron = fighterSquadOpt.get()
      let totalFighters = 1 + fighterSquadron.ships.len
      logFleet(
        &"Transferred Fighter squadron {fighterSquadronId} ({totalFighters}/12) " &
          &"from carrier {sourceCarrierSquadronId} to {targetCarrierSquadronId}"
      )

    # Transfer fighter (move ID from source to target)
    targetCarrier.embarkedFighters.add(fighterSquadronId)
    sourceCarrier.embarkedFighters.delete(fighterIdx)
    transferredCount += 1

  # Update both carrier squadrons in entity manager
  state.updateSquadron(sourceCarrierSquadronId, sourceCarrier)
  state.updateSquadron(targetCarrierSquadronId, targetCarrier)

  return ZeroTurnResult(
    success: true, error: "", fightersTransferred: transferredCount, warnings: warnings
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
      newSquadronId: none(string),
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
  of ZeroTurnCommandType.FormSquadron:
    return executeFormSquadron(state, cmd, events)
  of ZeroTurnCommandType.TransferShipBetweenSquadrons:
    return executeTransferShipBetweenSquadrons(state, cmd, events)
  of ZeroTurnCommandType.AssignSquadronToFleet:
    return executeAssignSquadronToFleet(state, cmd, events)

# Export main types
export ZeroTurnCommandType, ZeroTurnCommand, ZeroTurnResult, ValidationResult
