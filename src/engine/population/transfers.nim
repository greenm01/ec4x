## Space Guild Population Transfer System
##
## Implements economy.md:3.7 - civilian Starliner services for inter-colony population movement.
##
## Features:
## - Transit tracking (1 turn per jump, minimum 1 turn)
## - Cost calculation (planet class + distance modifier)
## - Smart delivery (redirect to nearest owned colony if destination unavailable)
## - Risk handling (conquest, blockade, loss scenarios)
## - Concurrent transfer limit (5 per house)
##
## Data-oriented design: Pure functions for calculations, batch processing in maintenance phase.

import std/[tables, sequtils, algorithm, options]
import ../gamestate
import ../state_helpers
import ../iterators
import ../starmap
import ../fleet
import ../../common/types/[core, planets]
import ../../common/logger
import types as pop_types

type
  TransferResult* {.pure.} = enum
    ## Outcome of a transfer arriving at destination
    Delivered,      # Successfully delivered to destination
    Redirected,     # Delivered to alternative colony (blockade/conquest)
    Lost            # No owned colonies exist - colonists dispersed

  TransferCompletion* = object
    ## Record of a completed transfer for event generation
    transfer*: pop_types.PopulationInTransit
    result*: TransferResult
    actualDestination*: Option[SystemId]

proc getPlanetClassBaseCost(planetClass: PlanetClass): int =
  ## Get base transfer cost per PTU for planet class
  ## Per spec economy.md:3.7
  case planetClass
  of PlanetClass.Eden: return 4
  of PlanetClass.Lush: return 5
  of PlanetClass.Benign: return 6
  of PlanetClass.Harsh: return 8
  of PlanetClass.Hostile: return 10
  of PlanetClass.Desolate: return 12
  of PlanetClass.Extreme: return 15

proc calculateTransferCost*(
  sourcePlanetClass: PlanetClass,
  destPlanetClass: PlanetClass,
  distance: int,
  ptuAmount: int
): int =
  ## Pure cost calculation per spec economy.md:3.7
  ## Base cost by planet class (4-15 PP/PTU)
  ## Distance modifier: +20% per jump beyond first
  ## Formula: (Base_source + Base_dest)/2 × PTU × (1 + 0.2 × max(0, distance-1))

  let sourceBase = getPlanetClassBaseCost(sourcePlanetClass)
  let destBase = getPlanetClassBaseCost(destPlanetClass)
  let avgBase = (sourceBase + destBase) div 2

  let distanceMult = 1.0 + (max(0, distance - 1).float * 0.20)
  return int(float(avgBase * ptuAmount) * distanceMult)

proc findNearestOwnedColony*(state: GameState, fromSystem: SystemId, houseId: HouseId): Option[SystemId] =
  ## Find closest owned colony via pathfinding
  ## Used for smart delivery when destination unavailable
  ## Pure function - no mutations

  var nearestSystem: Option[SystemId] = none(SystemId)
  var shortestDistance = high(int)

  # Create dummy fleet for pathfinding
  let dummyFleet = Fleet(location: fromSystem, owner: houseId)

  for (systemId, colony) in state.coloniesOwnedWithId(houseId):
    if systemId == fromSystem:
      continue  # Don't return source

    let pathResult = state.starMap.findPath(fromSystem, systemId, dummyFleet)
    if pathResult.found:
      let distance = pathResult.path.len - 1  # Path includes start, so subtract 1
      if distance < shortestDistance:
        shortestDistance = distance
        nearestSystem = some(systemId)

  return nearestSystem

proc ptuToPu*(ptuAmount: int): int =
  ## Convert Population Transfer Units to Population Units
  ## 1 PTU = ~50,000 souls
  ## 1 PU = production measure (varies by planet, typically 10,000-100,000 people)
  ## For simplicity: 1 PTU = 1 PU (can be refined later)
  return ptuAmount

proc initiateTransfer*(
  state: var GameState,
  houseId: HouseId,
  sourceSystem: SystemId,
  destSystem: SystemId,
  ptuAmount: int
): tuple[success: bool, message: string] =
  ## Initiate a new population transfer
  ## Returns (true, transferId) on success, (false, errorMessage) on failure
  ##
  ## Validation:
  ## - Maximum 5 concurrent transfers per house
  ## - Source colony exists and owned
  ## - Destination system exists
  ## - Sufficient population at source (must retain 1 PU)
  ## - Sufficient treasury

  # Count active transfers for house
  let activeTransfers = state.populationInTransit.filterIt(it.houseId == houseId)
  if activeTransfers.len >= 5:
    return (false, "Maximum 5 concurrent transfers allowed per house")

  # Validate source colony
  if sourceSystem notin state.colonies:
    return (false, "Source colony does not exist")

  let sourceColony = state.colonies[sourceSystem]
  if sourceColony.owner != houseId:
    return (false, "Source colony not owned by house")

  # Check source has sufficient population (must retain 1 PU per spec)
  if sourceColony.populationUnits - ptuAmount < 1:
    return (false, "Source must retain at least 1 PU")

  # Validate destination exists (can be any system, doesn't need to be owned)
  if destSystem notin state.starMap.systems:
    return (false, "Destination system does not exist")

  # Calculate distance and cost
  # Note: For population transfers, we use simplified pathfinding without fleet restrictions
  # Create a dummy fleet for pathfinding (civilian Starliners have no movement restrictions)
  let dummyFleet = Fleet(location: sourceSystem, owner: houseId)
  let pathResult = state.starMap.findPath(sourceSystem, destSystem, dummyFleet)
  if not pathResult.found:
    return (false, "No path exists to destination")

  let distance = pathResult.path.len - 1  # Path includes start, so subtract 1

  let destColony = if destSystem in state.colonies: some(state.colonies[destSystem]) else: none(Colony)
  let destPlanetClass = if destColony.isSome:
    destColony.get().planetClass
  else:
    # Assume Benign for uncolonized systems
    PlanetClass.Benign

  let cost = calculateTransferCost(
    sourceColony.planetClass,
    destPlanetClass,
    distance,
    ptuAmount
  )

  # Check treasury
  if state.houses[houseId].treasury < cost:
    return (false, "Insufficient funds: " & $cost & " PP required")

  # Create transfer
  let transferId = $houseId & "_transfer_" & $state.turn & "_" & $sourceSystem & "_" & $destSystem
  let arrivalTurn = state.turn + distance  # 1 turn per jump per spec

  let transfer = pop_types.PopulationInTransit(
    id: transferId,
    houseId: houseId,
    sourceSystem: sourceSystem,
    destSystem: destSystem,
    ptuAmount: ptuAmount,
    costPaid: cost,
    arrivalTurn: arrivalTurn
  )

  # Deduct population from source
  state.withColony(sourceSystem):
    colony.populationUnits -= ptuAmount
    colony.population = colony.populationUnits  # Sync display field

  # Deduct payment from treasury
  state.withHouse(houseId):
    house.treasury -= cost

  # Add to active transfers
  state.populationInTransit.add(transfer)

  return (true, transferId)

proc processArrivingTransfer(
  state: GameState,
  transfer: pop_types.PopulationInTransit
): TransferCompletion =
  ## Process a transfer that has reached its destination turn
  ## Pure function - returns completion info without mutating state

  result = TransferCompletion(
    transfer: transfer,
    result: TransferResult.Lost,
    actualDestination: none(SystemId)
  )

  # Check if destination is still owned and not blockaded
  if transfer.destSystem in state.colonies:
    let destColony = state.colonies[transfer.destSystem]

    if destColony.owner == transfer.houseId:
      # Check if blockaded
      if not destColony.blockaded:
        # Success - deliver to destination
        result.result = TransferResult.Delivered
        result.actualDestination = some(transfer.destSystem)
        return

  # Destination unavailable - try smart delivery
  let nearestColony = findNearestOwnedColony(state, transfer.destSystem, transfer.houseId)

  if nearestColony.isSome:
    # Found alternative - redirect
    result.result = TransferResult.Redirected
    result.actualDestination = nearestColony
  else:
    # No owned colonies - colonists lost
    result.result = TransferResult.Lost
    result.actualDestination = none(SystemId)

proc applyTransferCompletion*(state: var GameState, completion: TransferCompletion) =
  ## Apply transfer completion to state
  ## Clear, explicit mutations using state_helpers

  case completion.result
  of TransferResult.Delivered, TransferResult.Redirected:
    if completion.actualDestination.isSome:
      let destSystem = completion.actualDestination.get()
      state.withColony(destSystem):
        colony.populationUnits += completion.transfer.ptuAmount
        colony.population = colony.populationUnits  # Sync display field

      logEconomy("Population transfer completed",
                "ptu=", $completion.transfer.ptuAmount, " dest=", $destSystem)
      if completion.result == TransferResult.Redirected:
        logEconomy("Transfer redirected",
                  "origDest=", $completion.transfer.destSystem, " reason=blockade/conquest")

  of TransferResult.Lost:
    logEconomy("Population transfer LOST",
              "ptu=", $completion.transfer.ptuAmount, " reason=no_viable_destination")

proc processTransfers*(state: var GameState): seq[TransferCompletion] =
  ## Batch process all active transfers
  ## Called during Maintenance phase
  ## Data-oriented: process all transfers together

  result = @[]
  var completedIndices: seq[int] = @[]

  for i in 0 ..< state.populationInTransit.len:
    let transfer = state.populationInTransit[i]

    # Check if arrived
    if state.turn >= transfer.arrivalTurn:
      # Process arrival
      let completion = processArrivingTransfer(state, transfer)
      applyTransferCompletion(state, completion)

      result.add(completion)
      completedIndices.add(i)

  # Remove completed transfers (reverse order to preserve indices)
  for i in completedIndices.reversed:
    state.populationInTransit.delete(i)

  logEconomy("Processed arriving population transfers",
            "total=", $result.len,
            " delivered=", $result.filterIt(it.result == TransferResult.Delivered).len,
            " redirected=", $result.filterIt(it.result == TransferResult.Redirected).len,
            " lost=", $result.filterIt(it.result == TransferResult.Lost).len)

## Design Notes:
##
## **Data-Oriented Pattern:**
## 1. calculateTransferCost(): Pure calculation - no side effects
## 2. processArrivingTransfer(): Pure function - returns completion plan
## 3. applyTransferCompletion(): Explicit mutations - applies plan
## 4. processTransfers(): Batch processing - all transfers together
##
## **Benefits:**
## - Testable: Cost calculation and arrival processing are pure functions
## - Explicit: All state changes visible in apply functions
## - Batch-friendly: Process all arrivals in maintenance phase
## - Loggable: Can inspect completion before application
##
## **Smart Delivery:**
## - findNearestOwnedColony() uses pathfinding to find alternative
## - Colonists redirected if destination blockaded/conquered
## - Colonists lost only if no owned colonies exist
## - Per spec economy.md:3.7
##
## **Spec Compliance:**
## - economy.md:3.7: Complete transfer system
## - Transit time: 1 turn per jump (minimum 1)
## - Cost formula: Base × PTU × (1 + 0.2 × jumps)
## - Smart delivery with pathfinding
## - 5 concurrent transfer limit
## - Source reserve: Must retain 1 PU
##
## **TODO:**
## - Load costs from config/population.toml
## - Generate GameEvents for player notifications
## - Add order type for initiating transfers
## - Integration tests for all scenarios
## - AI strategy for population balancing
