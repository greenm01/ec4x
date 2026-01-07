## Fleet System - High-level API
##
## Provides high-level fleet operations that coordinate between:
## - @entities/fleet_ops (low-level state mutations)
## - Fleet validation and business logic
##
## Per DoD architecture: This layer provides coordination and validation,
## while entities layer handles index-aware state mutations.

import std/[options, algorithm]
import ../../types/[core, game_state, fleet, ship]
import ../../entities/fleet_ops
import ../../state/[engine, fleet_queries]
import ./entity as fleet_entity

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
  let systemOpt = system(state, location)
  if systemOpt.isNone:
    return (false, "System does not exist")

  # Check if house exists and is active
  let houseOpt = house(state, houseId)
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
  ## Check: both exist, same owner, same location, compatible ship types

  let sourceOpt = fleet(state, sourceId)
  let targetOpt = fleet(state, targetId)

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

  # Check ship type compatibility using state accessor
  let mergeCheck = state.canMergeWith(source, target)
  if not mergeCheck.canMerge:
    return (false, mergeCheck.reason)

  return (true, "")

proc mergeFleets*(
    state: var GameState, sourceId: FleetId, targetId: FleetId
): FleetOperationResult =
  ## High-level fleet merge with validation
  ##
  ## Coordinates:
  ## 1. Validation (can merge?)
  ## 2. Transfer ships from source to target
  ## 3. Destroy source fleet via @entities/fleet_ops
  ##
  ## Returns result with success/failure

  # Validate: Can merge?
  let validation = canMergeFleets(state, sourceId, targetId)
  if not validation.can:
    return FleetOperationResult(
      success: false, reason: validation.reason, fleetId: none(FleetId)
    )

  let sourceOpt = fleet(state, sourceId)
  let targetOpt = fleet(state, targetId)

  # Should always succeed after validation, but check anyway
  if sourceOpt.isNone or targetOpt.isNone:
    return FleetOperationResult(
      success: false, reason: "Fleet not found", fleetId: none(FleetId)
    )

  var source = sourceOpt.get()
  var target = targetOpt.get()

  # Transfer ships from source to target
  target.ships.add(source.ships)
  updateFleet(state, targetId, target)

  # Destroy source fleet via entities layer
  fleet_ops.destroyFleet(state, sourceId)

  return FleetOperationResult(
    success: true, reason: "Fleets merged successfully", fleetId: some(targetId)
  )

proc canSplitFleet*(
    state: GameState, fleetId: FleetId, shipIndices: seq[int]
): tuple[can: bool, reason: string] =
  ## Validate if a fleet can be split
  ## Check: fleet exists, indices valid, wouldn't leave fleet empty

  let fleetOpt = fleet(state, fleetId)
  if fleetOpt.isNone:
    return (false, "Fleet does not exist")

  let fleet = fleetOpt.get()

  # Check if indices are valid
  for idx in shipIndices:
    if idx < 0 or idx >= fleet.ships.len:
      return (false, "Invalid ship index: " & $idx)

  # Check if split would leave original fleet empty
  if shipIndices.len >= fleet.ships.len:
    return (false, "Cannot split all ships (would leave fleet empty)")

  # Check if split would create empty new fleet
  if shipIndices.len == 0:
    return (false, "Cannot create empty fleet (no ships specified)")

  return (true, "")

proc splitFleet*(
    state: var GameState, fleetId: FleetId, shipIndices: seq[int]
): FleetOperationResult =
  ## High-level fleet split with validation
  ##
  ## Coordinates:
  ## 1. Validation (can split?)
  ## 2. Create new fleet via @entities/fleet_ops
  ## 3. Transfer ships to new fleet
  ##
  ## Returns result with success/failure and new fleet ID

  # Validate: Can split?
  let validation = canSplitFleet(state, fleetId, shipIndices)
  if not validation.can:
    return FleetOperationResult(
      success: false, reason: validation.reason, fleetId: none(FleetId)
    )

  let fleetOpt = fleet(state, fleetId)
  if fleetOpt.isNone:
    return FleetOperationResult(
      success: false, reason: "Fleet not found", fleetId: none(FleetId)
    )

  var fleet = fleetOpt.get()

  # Create new fleet in same location via entities layer
  let newFleet = fleet_ops.createFleet(state, fleet.houseId, fleet.location)

  # Transfer ships to new fleet
  var newShips: seq[ShipId] = @[]
  for idx in shipIndices:
    newShips.add(fleet.ships[idx])

  # Remove ships from original fleet (in reverse order to maintain indices)
  var sortedIndices = shipIndices
  sortedIndices.sort(
    proc(a, b: int): int =
      cmp(b, a)
  ) # Descending order
  for idx in sortedIndices:
    fleet.ships.delete(idx)

  # Update both fleets
  updateFleet(state, fleetId, fleet)

  var updatedNewFleet = newFleet
  updatedNewFleet.ships = newShips
  updateFleet(state, newFleet.id, updatedNewFleet)

  return FleetOperationResult(
    success: true, reason: "Fleet split successfully", fleetId: some(newFleet.id)
  )
