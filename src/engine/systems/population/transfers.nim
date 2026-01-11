## Space Guild Population Transfer System
##
## Implements economy.md:3.5 - civilian Starliner services for inter-colony
## population movement.
##
## **Architecture:**
## - Uses state layer APIs to read entities (state.colony, state.system)
## - Uses entity ops for mutations (population_transfer_ops)
## - Follows three-layer pattern: State → Business Logic → Entity Ops

import std/[tables, sequtils, options, math, strformat]
import ../../types/[
  game_state, core, event, population as pop_types, starmap, colony, command,
]
import ../../state/[engine, iterators]
import ../../entities/[fleet_ops, population_transfer_ops]
import ../../starmap
import ../fleet/movement
import ../../event_factory/init
import ../../globals
import ../../../common/logger

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

proc planetClassBaseCost(planetClass: PlanetClass): int32 =
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

  let destCost = planetClassBaseCost(destPlanetClass)
  return destCost * int32(ptuAmount)

# =============================================================================
# Transfer Creation (Public API)
# =============================================================================

proc createTransferInitiation*(
    state: GameState,
    houseId: HouseId,
    sourceSystem: SystemId,
    destSystem: SystemId,
    ptuAmount: int,
): tuple[success: bool, message: string] =
  ## Initiate a population transfer via Space Guild
  ## Returns (success, message) tuple

  # Validate concurrent transfer limit
  var activeTransferCount = 0
  for (_, _) in state.populationTransfersForHouse(houseId):
    activeTransferCount += 1
  if activeTransferCount >= 5:
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
  let dummyFleet = fleet_ops.newFleet(
    shipIds = @[], owner = houseId, location = sourceSystem
  )
  let pathResult = state.findPath(sourceSystem, destSystem, dummyFleet)
  if not pathResult.found:
    return (false, "No path exists to destination")

  let distance = pathResult.path.len - 1

  # Determine destination planet class (from System, not Colony)
  let destSystemOpt = state.system(destSystem)
  if destSystemOpt.isNone:
    return (false, "Destination system does not exist")
  let destPlanetClass = destSystemOpt.get().planetClass

  # Get source planet class from System
  let sourceSystemOpt = state.system(sourceSystem)
  if sourceSystemOpt.isNone:
    return (false, "Source system does not exist")
  let sourcePlanetClass = sourceSystemOpt.get().planetClass

  # Calculate cost (spec: destination cost only)
  let cost =
    calculateTransferCost(sourcePlanetClass, destPlanetClass, distance, ptuAmount)

  # Check treasury
  let houseOpt = state.house(houseId)
  if houseOpt.isNone:
    return (false, "House does not exist")
  if houseOpt.get().treasury < cost:
    return (false, "Insufficient funds: " & $cost & " PP required")

  # Get destination colony ID
  let destColonyIdOpt = state.colonyIdBySystem(destSystem)
  if destColonyIdOpt.isNone:
    return (false, "Destination system has no colony")

  # Create transfer using entity operations
  # This handles: ID generation, entity manager, indexes, population/treasury deduction
  let arrivalTurn = int32(state.turn + distance)
  let _ = population_transfer_ops.startTransfer(
    state, houseId, sourceColonyId, destColonyIdOpt.get(), int32(ptuAmount), cost,
    arrivalTurn,
  )

  return (true, "Transfer initiated")

# =============================================================================
# Transfer Arrival Processing
# =============================================================================

proc findNearestOwnedColony*(
    state: GameState, fromSystem: SystemId, houseId: HouseId
): Option[SystemId] =
  ## Find nearest colony owned by house (for smart delivery)
  var nearestDist = high(int32)
  var nearestSystem: Option[SystemId] = none(SystemId)

  for colony in state.coloniesOwned(houseId):
    let fromSystemOpt = state.system(fromSystem)
    let colonySystemOpt = state.system(colony.systemId)
    if fromSystemOpt.isNone or colonySystemOpt.isNone:
      continue

    let dist = int32(
      distance(colonySystemOpt.get().coords, fromSystemOpt.get().coords)
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
    state: GameState, transferId: PopulationTransferId, completion: TransferCompletion
) =
  ## Apply transfer completion to state
  ## Mutates state using entity patterns

  case completion.result
  of TransferResult.Delivered, TransferResult.Redirected:
    if completion.actualDestination.isSome:
      let destSystem = completion.actualDestination.get()

      # Deliver population using entity operations
      let destColonyOpt = state.colonyBySystem(destSystem)
      if destColonyOpt.isSome:
        let destColonyId = destColonyOpt.get().id
        state.deliverTransfer(transferId, destColonyId)

      logInfo(
        "Population", "Transfer completed",
        " ptu=", completion.transfer.ptuAmount, " dest=", destSystem,
      )

      if completion.result == TransferResult.Redirected:
        # Get original destination systemId for logging
        let origColony = state.colony(completion.transfer.destColony).get()
        logInfo("Population", "Transfer redirected", " from=", origColony.systemId)

  of TransferResult.Lost:
    logWarn(
      "Population", "Transfer LOST - no viable destination",
      " ptu=", completion.transfer.ptuAmount,
    )

# =============================================================================
# Batch Processing
# =============================================================================

proc processTransfers*(state: GameState): seq[TransferCompletion] =
  ## Batch process all active transfers arriving this turn
  result = @[]
  var completedIds: seq[PopulationTransferId] = @[]

  # Use iterator to access active transfers via entity manager
  for (transferId, transfer) in state.activePopulationTransfers():
    if transfer.arrivalTurn == state.turn:
      let completion = processArrivingTransfer(state, transfer)
      applyTransferCompletion(state, transferId, completion)
      result.add(completion)
      completedIds.add(transferId)

  # Remove completed transfers using entity operations
  # This handles: entity manager deletion, byHouse index, inTransit index
  for transferId in completedIds:
    state.completeTransfer(transferId)

  let delivered = result.filterIt(it.result == TransferResult.Delivered).len
  let redirected = result.filterIt(it.result == TransferResult.Redirected).len
  let lost = result.filterIt(it.result == TransferResult.Lost).len

  logInfo(
    "Population", "Processed population transfers",
    " total=", result.len, " delivered=", delivered,
    " redirected=", redirected, " lost=", lost,
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
        populationTransfer(
          completion.transfer.houseId, int(completion.transfer.ptuAmount),
          sourceSystem, destSystem, true, "",
        )
      )

    of TransferResult.Redirected:
      if completion.actualDestination.isSome:
        result.add(
          populationTransfer(
            completion.transfer.houseId, int(completion.transfer.ptuAmount),
            sourceSystem, completion.actualDestination.get(), true,
            "redirected from " & $destSystem,
          )
        )

    of TransferResult.Lost:
      result.add(
        populationTransfer(
          completion.transfer.houseId, int(completion.transfer.ptuAmount),
          sourceSystem, destSystem, false, "no viable destination",
        )
      )

# =============================================================================
# Command Resolution (Command Phase)
# =============================================================================

proc resolvePopulationTransfers*(
    state: GameState, packet: CommandPacket, events: var seq[GameEvent]
) =
  ## Process population transfer commands - initiate new transfers
  ## Called from Command Phase CMD5
  
  for command in packet.populationTransfers:
    # Get source colony's system ID
    let sourceColonyOpt = state.colony(command.sourceColony)
    if sourceColonyOpt.isNone:
      logWarn("Population",
        &"Transfer failed: source colony {command.sourceColony} not found")
      continue
    
    let sourceSystem = sourceColonyOpt.get().systemId
    
    # Get destination colony's system ID
    let destColonyOpt = state.colony(command.destColony)
    if destColonyOpt.isNone:
      logWarn("Population",
        &"Transfer failed: dest colony {command.destColony} not found")
      continue
    
    let destSystem = destColonyOpt.get().systemId
    
    # Initiate the transfer
    let (success, message) = createTransferInitiation(
      state, packet.houseId, sourceSystem, destSystem, command.ptuAmount
    )
    
    if success:
      logInfo("Population",
        &"{packet.houseId} initiated transfer of {command.ptuAmount} PTU " &
        &"from {sourceSystem} to {destSystem}")
      events.add(populationTransfer(
        packet.houseId, command.ptuAmount, sourceSystem, destSystem,
        true, "transfer initiated"
      ))
    else:
      logWarn("Population",
        &"Transfer failed for {packet.houseId}: {message}")
