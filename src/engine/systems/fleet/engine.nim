## Fleet System - High-level API
##
## Provides high-level fleet operations that coordinate between:
## - @entities/fleet_ops (low-level state mutations)
## - Fleet validation and business logic
##
## Per DoD architecture: This layer provides coordination and validation,
## while entities layer handles index-aware state mutations.

import std/[options, algorithm]
import ../../types/[core, game_state, fleet, squadron]
import ../../entities/fleet_ops
import ../../state/[game_state as gs_helpers, entity_manager]

type FleetOperationResult* = object ## Result of a fleet operation
  success*: bool
  reason*: string
  fleetId*: Option[FleetId]

proc canCreateFleet*(
    state: GameState, houseId: HouseId, location: SystemId
): tuple[can: bool, reason: string] =
  ## Validate if a fleet can be created
  ## Check: system exists, house is active

  # Check if system exists
  let systemOpt = gs_helpers.getSystem(state, location)
  if systemOpt.isNone:
    return (false, "System does not exist")

  # Check if house exists and is active
  let houseOpt = gs_helpers.getHouse(state, houseId)
  if houseOpt.isNone:
    return (false, "House does not exist")

  let house = houseOpt.get()
  if house.isEliminated:
    return (false, "House is eliminated")

  return (true, "")

proc createFleetCoordinated*(
    state: var GameState, houseId: HouseId, location: SystemId
): FleetOperationResult =
  ## High-level fleet creation with validation
  ##
  ## Coordinates:
  ## 1. Validation (can create?)
  ## 2. Entity creation via @entities/fleet_ops
  ##
  ## Returns result with success/failure

  # Validate: Can create fleet?
  let validation = canCreateFleet(state, houseId, location)
  if not validation.can:
    return FleetOperationResult(
      success: false, reason: validation.reason, fleetId: none(FleetId)
    )

  # Create fleet via entities layer (low-level state mutation)
  let fleet = fleet_ops.createFleet(state, houseId, location)

  return FleetOperationResult(
    success: true, reason: "Fleet created successfully", fleetId: some(fleet.id)
  )

proc canMergeFleets*(
    state: GameState, sourceId: FleetId, targetId: FleetId
): tuple[can: bool, reason: string] =
  ## Validate if two fleets can be merged
  ## Check: both exist, same owner, same location, compatible squadron types

  let sourceOpt = gs_helpers.getFleet(state, sourceId)
  let targetOpt = gs_helpers.getFleet(state, targetId)

  if sourceOpt.isNone:
    return (false, "Source fleet does not exist")
  if targetOpt.isNone:
    return (false, "Target fleet does not exist")

  let source = sourceOpt.get()
  let target = targetOpt.get()

  # Must have same owner
  if source.houseId != target.houseId:
    return (false, "Fleets have different owners")

  # Must be in same location
  if source.location != target.location:
    return (false, "Fleets are in different systems")

  # Check squadron type compatibility
  # Intel squadrons cannot mix with non-Intel squadrons
  var sourceHasIntel = false
  var targetHasIntel = false
  var sourceHasNonIntel = false
  var targetHasNonIntel = false

  for sqId in source.squadrons:
    let sqOpt = gs_helpers.getSquadrons(state, sqId)
    if sqOpt.isSome:
      if sqOpt.get().squadronType == SquadronClass.Intel:
        sourceHasIntel = true
      else:
        sourceHasNonIntel = true

  for sqId in target.squadrons:
    let sqOpt = gs_helpers.getSquadrons(state, sqId)
    if sqOpt.isSome:
      if sqOpt.get().squadronType == SquadronClass.Intel:
        targetHasIntel = true
      else:
        targetHasNonIntel = true

  if (sourceHasIntel and targetHasNonIntel) or (sourceHasNonIntel and targetHasIntel):
    return (false, "Intel squadrons cannot be mixed with other squadron types")

  return (true, "")

proc mergeFleets*(
    state: var GameState, sourceId: FleetId, targetId: FleetId
): FleetOperationResult =
  ## High-level fleet merge with validation
  ##
  ## Coordinates:
  ## 1. Validation (can merge?)
  ## 2. Transfer squadrons from source to target
  ## 3. Destroy source fleet via @entities/fleet_ops
  ##
  ## Returns result with success/failure

  # Validate: Can merge?
  let validation = canMergeFleets(state, sourceId, targetId)
  if not validation.can:
    return FleetOperationResult(
      success: false, reason: validation.reason, fleetId: none(FleetId)
    )

  let sourceOpt = gs_helpers.getFleet(state, sourceId)
  let targetOpt = gs_helpers.getFleet(state, targetId)

  # Should always succeed after validation, but check anyway
  if sourceOpt.isNone or targetOpt.isNone:
    return FleetOperationResult(
      success: false, reason: "Fleet not found", fleetId: none(FleetId)
    )

  var source = sourceOpt.get()
  var target = targetOpt.get()

  # Transfer squadrons from source to target
  target.squadrons.add(source.squadrons)
  state.fleets.entities.updateEntity(targetId, target)

  # Destroy source fleet via entities layer
  fleet_ops.destroyFleet(state, sourceId)

  return FleetOperationResult(
    success: true, reason: "Fleets merged successfully", fleetId: some(targetId)
  )

proc canSplitFleet*(
    state: GameState, fleetId: FleetId, squadronIndices: seq[int]
): tuple[can: bool, reason: string] =
  ## Validate if a fleet can be split
  ## Check: fleet exists, indices valid, wouldn't leave fleet empty

  let fleetOpt = gs_helpers.getFleet(state, fleetId)
  if fleetOpt.isNone:
    return (false, "Fleet does not exist")

  let fleet = fleetOpt.get()

  # Check if indices are valid
  for idx in squadronIndices:
    if idx < 0 or idx >= fleet.squadrons.len:
      return (false, "Invalid squadron index: " & $idx)

  # Check if split would leave original fleet empty
  if squadronIndices.len >= fleet.squadrons.len:
    return (false, "Cannot split all squadrons (would leave fleet empty)")

  # Check if split would create empty new fleet
  if squadronIndices.len == 0:
    return (false, "Cannot create empty fleet (no squadrons specified)")

  return (true, "")

proc splitFleet*(
    state: var GameState, fleetId: FleetId, squadronIndices: seq[int]
): FleetOperationResult =
  ## High-level fleet split with validation
  ##
  ## Coordinates:
  ## 1. Validation (can split?)
  ## 2. Create new fleet via @entities/fleet_ops
  ## 3. Transfer squadrons to new fleet
  ##
  ## Returns result with success/failure and new fleet ID

  # Validate: Can split?
  let validation = canSplitFleet(state, fleetId, squadronIndices)
  if not validation.can:
    return FleetOperationResult(
      success: false, reason: validation.reason, fleetId: none(FleetId)
    )

  let fleetOpt = gs_helpers.getFleet(state, fleetId)
  if fleetOpt.isNone:
    return FleetOperationResult(
      success: false, reason: "Fleet not found", fleetId: none(FleetId)
    )

  var fleet = fleetOpt.get()

  # Create new fleet in same location via entities layer
  let newFleet = fleet_ops.createFleet(state, fleet.houseId, fleet.location)

  # Transfer squadrons to new fleet
  var newSquadrons: seq[SquadronId] = @[]
  for idx in squadronIndices:
    newSquadrons.add(fleet.squadrons[idx])

  # Remove squadrons from original fleet (in reverse order to maintain indices)
  var sortedIndices = squadronIndices
  sortedIndices.sort(
    proc(a, b: int): int =
      cmp(b, a)
  ) # Descending order
  for idx in sortedIndices:
    fleet.squadrons.delete(idx)

  # Update both fleets
  state.fleets.entities.updateEntity(fleetId, fleet)

  var updatedNewFleet = newFleet
  updatedNewFleet.squadrons = newSquadrons
  state.fleets.entities.updateEntity(newFleet.id, updatedNewFleet)

  return FleetOperationResult(
    success: true, reason: "Fleet split successfully", fleetId: some(newFleet.id)
  )
