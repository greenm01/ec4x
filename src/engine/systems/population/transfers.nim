## Space Guild Population Transfer System
##
## Implements economy.md:3.5 - civilian Starliner services for inter-colony
## population movement.
##
## Architecture: Pure business logic, uses entity patterns from architecture.md

import std/[tables, sequtils, options, logging, math]
import ../../types/[
  game_state, core, event, population as pop_types, starmap, fleet, colony,
]
import ../../state/[engine, iterators]
import ../../starmap as starmap_module
import ../fleet/movement
import ../../event_factory/init as event_factory
import ../../globals

type
  TransferResult* {.pure.} = enum
    Delivered # Successfully delivered to destination
    Redirected # Delivered to alternative colony (blockade/conquest)
    Lost # No owned colonies exist - colonists dispersed

  TransferCompletion* = object
    transfer*: pop_types.PopulationInTransit
    result*: TransferResult
    actualDestination*: Option[SystemId]

# =============================================================================
# Cost Calculation
# =============================================================================

proc getPlanetClassBaseCost(planetClass: PlanetClass): int32 =
  ## Get base transfer cost per PTU for planet class
  ## Per spec economy.md:3.5 (Space Guild transfer costs)
  ## Reads from config/economy.kdl
  let costs = gameConfig.economy.populationTransfer.costsByPlanetClass
  return costs.getOrDefault(planetClass, 10'i32)

proc calculateTransferCost*(
    sourcePlanetClass: PlanetClass,
    destPlanetClass: PlanetClass,
    distance: int,
    ptuAmount: int,
): int32 =
  ## Pure cost calculation per spec economy.md:3.5
  ## Cost is based solely on destination planet class (4-15 PP/PTU)
  ## Formula: dest_cost × PTU
  ##
  ## Note: sourcePlanetClass and distance parameters kept for API compatibility
  ## but are not used per spec

  let destCost = getPlanetClassBaseCost(destPlanetClass)
  return destCost * int32(ptuAmount)

# =============================================================================
# Transfer Creation (Public API)
# =============================================================================

proc createTransferInitiation*(
    state: var GameState,
    houseId: HouseId,
    sourceSystem: SystemId,
    destSystem: SystemId,
    ptuAmount: int,
): tuple[success: bool, message: string] =
  ## Initiate a population transfer via Space Guild
  ## Returns (success, message) tuple

  # Validate concurrent transfer limit
  let activeTransfers =
    state.populationInTransit.filterIt(it.houseId == houseId)
  if activeTransfers.len >= 5:
    return (false, "Maximum 5 concurrent transfers allowed per house")

  # Validate source colony exists
  let sourceColonyOpt = state.colonyBySystem(sourceSystem)
  if sourceColonyOpt.isNone:
    return (false, "Source system has no colony")

  let sourceColony = sourceColonyOpt.get()
  let sourceColonyId = sourceColony.id # Needed for transfer ID
  if sourceColony.owner != houseId:
    return (false, "Source colony not owned by house")

  # Check source has sufficient population (must retain 1 PU per spec)
  if sourceColony.populationUnits - int32(ptuAmount) < 1:
    return (false, "Source must retain at least 1 PU")

  # Validate destination system exists
  if state.system(destSystem).isNone:
    return (false, "Destination system does not exist")

  # Calculate distance via pathfinding
  let dummyFleet = Fleet(location: sourceSystem, houseId: houseId)
  let pathResult = state.findPath(sourceSystem, destSystem, dummyFleet)
  if not pathResult.found:
    return (false, "No path exists to destination")

  let distance = pathResult.path.len - 1

  # Determine destination planet class
  let destPlanetClass =
    block:
      let destColony = state.colonyBySystem(destSystem)
      if destColony.isSome:
        destColony.get().planetClass
      else:
        PlanetClass.Benign # Uncolonized

  # Calculate cost (spec: destination cost only)
  let cost =
    calculateTransferCost(sourceColony.planetClass, destPlanetClass, distance, ptuAmount)

  # Check treasury
  let houseOpt = state.house(houseId)
  if houseOpt.isNone:
    return (false, "House does not exist")
  if houseOpt.get().treasury < cost:
    return (false, "Insufficient funds: " & $cost & " PP required")

  # Create transfer record
  let arrivalTurn = int32(state.turn + distance)
  let transfer = pop_types.PopulationInTransit(
    id: PopulationTransferId(sourceColonyId.uint32 xor destSystem.uint32 xor state.turn.uint32),
    houseId: houseId,
    sourceColony: sourceColonyId,
    destColony: state.colonyIdBySystem(destSystem).get(),  # Lookup ColonyId
    ptuAmount: int32(ptuAmount),
    costPaid: cost,
    arrivalTurn: arrivalTurn,
    status: TransferStatus.InTransit,
  )

  # Deduct population from source (using entity pattern)
  var updatedSourceColony = sourceColony
  updatedSourceColony.populationUnits -= int32(ptuAmount)
  updatedSourceColony.population = updatedSourceColony.populationUnits
  state.updateColony(sourceColonyId, updatedSourceColony)

  # Deduct cost from treasury (using entity pattern)
  var house = houseOpt.get()
  house.treasury -= cost
  state.updateHouse(houseId, house)
  
  # Add to active transfers
  state.populationInTransit.add(transfer)

  return (true, "Transfer initiated")

# =============================================================================
# Transfer Arrival Processing
# =============================================================================

proc findNearestOwnedColony*(
    state: GameState, fromSystem: SystemId, houseId: HouseId
): Option[SystemId] =
  ## Find nearest colony owned by house (for smart delivery)
  var nearestDist = high(int)
  var nearestSystem: Option[SystemId] = none(SystemId)

  for colony in state.coloniesOwned(houseId):
    let dist = int(
      distance(
        state.system(colony.systemId).get().coords,
        state.system(fromSystem).get().coords,
      )
    )
    if dist < nearestDist:
      nearestDist = dist
      nearestSystem = some(colony.systemId)

  return nearestSystem

proc processArrivingTransfer(
    state: GameState, transfer: pop_types.PopulationInTransit
): TransferCompletion =
  ## Process a transfer that has reached its destination turn
  ## Pure function - returns completion info without mutating state

  result =
    TransferCompletion(transfer: transfer, result: TransferResult.Lost, actualDestination: none(
      SystemId
    ))

  # Get destination colony directly (no cast needed)
  let destColonyOpt = state.colony(transfer.destColony)
  if destColonyOpt.isSome:
      let destColony = destColonyOpt.get()

      if destColony.owner == transfer.houseId and not destColony.blockaded:
        # Success - deliver to destination
        result.result = TransferResult.Delivered
        result.actualDestination = some(destColony.systemId)
        return

  # Destination unavailable - try smart delivery
  # Get systemId from colony for nearest search
  let destColonyForSearch = state.colony(transfer.destColony).get()
  let nearestColony = findNearestOwnedColony(state, destColonyForSearch.systemId, transfer.houseId)

  if nearestColony.isSome:
    # Found alternative - redirect
    result.result = TransferResult.Redirected
    result.actualDestination = nearestColony
  else:
    # No owned colonies - colonists lost
    result.result = TransferResult.Lost
    result.actualDestination = none(SystemId)

proc applyTransferCompletion*(
    state: var GameState, completion: TransferCompletion
) =
  ## Apply transfer completion to state
  ## Mutates state using entity patterns

  case completion.result
  of TransferResult.Delivered, TransferResult.Redirected:
    if completion.actualDestination.isSome:
      let destSystem = completion.actualDestination.get()

      # Deliver population
      let destColonyOpt = state.colonyBySystem(destSystem)
      if destColonyOpt.isSome:
          var destColony = destColonyOpt.get()
          let destColonyId = destColony.id # Needed for updateEntity
          destColony.populationUnits += completion.transfer.ptuAmount
          destColony.population = destColony.populationUnits
          state.updateColony(destColonyId, destColony)

      info(
        "Population transfer completed: ", $completion.transfer.ptuAmount, " PTU to ",
        $destSystem,
      )

      if completion.result == TransferResult.Redirected:
        # Get original destination systemId for logging
        let origColony = state.colony(completion.transfer.destColony).get()
        info("Transfer redirected from ", $origColony.systemId)

  of TransferResult.Lost:
    info(
      "Population transfer LOST: ", $completion.transfer.ptuAmount,
      " PTU (no viable destination)",
    )

# =============================================================================
# Batch Processing
# =============================================================================

proc processTransfers*(state: var GameState): seq[TransferCompletion] =
  ## Batch process all active transfers arriving this turn
  result = @[]
  var completedIndices: seq[int] = @[]

  for i, transfer in state.populationInTransit:
    if transfer.arrivalTurn == state.turn:
      let completion = processArrivingTransfer(state, transfer)
      applyTransferCompletion(state, completion)
      result.add(completion)
      completedIndices.add(i)

  # Remove completed transfers (reverse order to preserve indices)
  for i in countdown(completedIndices.len - 1, 0):
    state.populationInTransit.delete(completedIndices[i])

  info(
    "Processed ", $result.len, " population transfers (", $result.filterIt(
      it.result == TransferResult.Delivered
    ).len, " delivered, ", $result.filterIt(it.result == TransferResult.Redirected).len, " redirected, ",
    $result.filterIt(it.result == TransferResult.Lost).len, " lost)",
  )

# =============================================================================
# Event Generation
# =============================================================================

proc generateTransferEvents*(
    state: GameState, completions: seq[TransferCompletion]
): seq[event.GameEvent] =
  ## Generate events for completed transfers
  result = @[]

  for completion in completions:
    # Get systemIds from colonies (no cast - proper lookup)
    let sourceColony = state.colony(completion.transfer.sourceColony).get()
    let destColony = state.colony(completion.transfer.destColony).get()
    let sourceSystem = sourceColony.systemId
    let destSystem = destColony.systemId

    case completion.result
    of TransferResult.Delivered:
      result.add(
        event_factory.populationTransfer(
          completion.transfer.houseId, int(completion.transfer.ptuAmount),
          sourceSystem, destSystem, true, "",
        )
      )

    of TransferResult.Redirected:
      if completion.actualDestination.isSome:
        result.add(
          event_factory.populationTransfer(
            completion.transfer.houseId, int(completion.transfer.ptuAmount),
            sourceSystem, completion.actualDestination.get(), true,
            "redirected from " & $destSystem,
          )
        )

    of TransferResult.Lost:
      result.add(
        event_factory.populationTransfer(
          completion.transfer.houseId, int(completion.transfer.ptuAmount),
          sourceSystem, destSystem, false, "no viable destination",
        )
      )
