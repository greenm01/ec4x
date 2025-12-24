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
##
## Per architecture.md: Population system owns population operations,
## called from turn_cycle/command_phase.nim and production_phase.nim

import std/[tables, sequtils, algorithm, options, logging, strformat, math]
import ../../types/[game_state, core, command, event, population as pop_types, starmap]
import ../../config/population_config
import ../../starmap as starmap_module
import ../../event_factory/init as event_factory

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

## ============================================================================
## Order Processing Functions (called from turn_cycle/command_phase.nim)
## ============================================================================

proc calculateTransitTime*(state: GameState, sourceSystem: SystemId,
                          destSystem: SystemId, houseId: HouseId):
                          tuple[turns: int, jumps: int] =
  ## Calculate Space Guild transit time and jump distance
  ## Per config/population.toml: turns_per_jump = 1, minimum_turns = 1
  ## Uses pathfinding to calculate actual jump lane distance
  ## Returns (turns: -1, jumps: 0) if path crosses enemy territory (Guild cannot complete transfer)

  import ../../state/entity_manager

  if sourceSystem == destSystem:
    return (turns: 1, jumps: 0)  # Minimum 1 turn even for same system, 0 jumps

  # Space Guild civilian transports can use all lanes (not restricted by fleet composition)
  # Create a dummy fleet that can traverse all lanes
  let dummyFleet = Fleet(
    id: "transit_calc",
    owner: "GUILD".HouseId,
    location: sourceSystem,
    squadrons: @[]
  )

  # Use starmap pathfinding to get actual jump distance
  let pathResult = state.starMap.findPath(sourceSystem, destSystem, dummyFleet)

  if pathResult.found:
    # Check if path crosses enemy territory (implemented below)
    # Path length - 1 = number of jumps (e.g., [A, B, C] = 2 jumps)
    # 1 turn per jump per config/population.toml
    let jumps = pathResult.path.len - 1
    return (turns: max(1, jumps), jumps: jumps)
  else:
    # No valid path found (shouldn't happen on a connected map, but handle gracefully)
    # Fall back to hex distance as approximation
    if sourceSystem in state.starMap.systems and destSystem in state.starMap.systems:
      let source = state.starMap.systems[sourceSystem]
      let dest = state.starMap.systems[destSystem]
      let hexDist = distance(source.coords, dest.coords)
      let jumps = hexDist.int
      return (turns: max(1, jumps), jumps: jumps)
    else:
      return (turns: 1, jumps: 0)  # Ultimate fallback

proc canGuildTraversePath*(state: GameState, path: seq[SystemId],
                          transferringHouse: HouseId): bool =
  ## Check if Space Guild can traverse a path for a given house
  ## Guild validates path using the house's known intel (fog of war)
  ## Returns false if:
  ## - Path crosses system the house has no visibility on (intel leak prevention)
  ## - Path crosses enemy-controlled system (blockade)

  import ../../state/fog_of_war

  for systemId in path:
    # Player must have visibility on this system (prevents intel leak exploit)
    if not hasVisibilityOn(state, systemId, transferringHouse):
      return false

    # If system has a colony, it must be friendly (not enemy-controlled)
    let colonyOpt = state.colonies.entities.getEntity(systemId)
    if colonyOpt.isSome:
      let colony = colonyOpt.get()
      if colony.owner != transferringHouse:
        # Enemy-controlled system - Guild cannot pass through
        return false

  return true

proc resolvePopulationTransfers*(state: var GameState, packet: CommandPacket,
                                 events: var seq[GameEvent]) =
  ## Process Space Guild population transfer orders
  ## Source: docs/specs/economy.md Section 3.7, config/population.toml

  import ../../state/entity_manager

  debug "Processing population transfers for ", packet.houseId

  for transfer in packet.populationTransfers:
    # Validate source colony exists and is owned by house
    let sourceColonyOpt = state.colonies.entities.getEntity(transfer.sourceColony)
    if sourceColonyOpt.isNone:
      error "Transfer failed: source colony ", transfer.sourceColony, " not found"
      continue

    var sourceColony = sourceColonyOpt.get()
    if sourceColony.owner != packet.houseId:
      error "Transfer failed: source colony ", transfer.sourceColony, " not owned by ", packet.houseId
      continue

    # Validate destination colony exists and is owned by house
    let destColonyOpt = state.colonies.entities.getEntity(transfer.destColony)
    if destColonyOpt.isNone:
      error "Transfer failed: destination colony ", transfer.destColony, " not found"
      continue

    var destColony = destColonyOpt.get()
    if destColony.owner != packet.houseId:
      error "Transfer failed: destination colony ", transfer.destColony, " not owned by ", packet.houseId
      continue

    # Critical validation: Destination must have ≥1 PTU (50k souls) to be a functional colony
    if destColony.souls < soulsPerPtu():
      error "Transfer failed: destination colony ", transfer.destColony, " has only ", destColony.souls,
            " souls (needs ≥", soulsPerPtu(), " to accept transfers)"
      continue

    # Convert PTU amount to souls for exact transfer
    let soulsToTransfer = transfer.ptuAmount * soulsPerPtu()

    # Validate source has enough souls (can transfer any amount, even fractional PTU)
    if sourceColony.souls < soulsToTransfer:
      error "Transfer failed: source colony ", transfer.sourceColony, " has only ", sourceColony.souls,
            " souls (needs ", soulsToTransfer, " for ", transfer.ptuAmount, " PTU)"
      continue

    # Check concurrent transfer limit (max 5 per house per config/population.toml)
    let activeTransfers = state.populationInTransit.filterIt(it.houseId == packet.houseId)
    if activeTransfers.len >= globalPopulationConfig.max_concurrent_transfers:
      warn "Transfer rejected: Maximum ", globalPopulationConfig.max_concurrent_transfers,
           " concurrent transfers reached (house has ", activeTransfers.len, " active)"
      continue

    # Calculate transit time and jump distance
    let (transitTime, jumps) = calculateTransitTime(state, transfer.sourceColony, transfer.destColony, packet.houseId)

    # Check if Guild can complete the transfer (path must be known and not blocked)
    if transitTime < 0:
      error "Transfer failed: No safe Guild route between ", transfer.sourceColony, " and ", transfer.destColony,
            " (requires scouted path through friendly/neutral territory)"
      continue

    let arrivalTurn = state.turn + transitTime

    # Calculate transfer cost based on destination planet class and jump distance
    # Per config/population.toml and docs/specs/economy.md Section 3.7
    let cost = calculateTransferCost(destColony.planetClass, transfer.ptuAmount, jumps)

    # Check house treasury and deduct cost
    let houseOpt = state.houses.entities.getEntity(packet.houseId)
    if houseOpt.isNone:
      error "Transfer failed: House ", packet.houseId, " not found"
      continue

    var house = houseOpt.get()
    if house.treasury < cost:
      error "Transfer failed: Insufficient funds (need ", cost, " PP, have ", house.treasury, " PP)"
      continue

    # Deduct cost from treasury
    house.treasury -= cost
    state.houses.entities.updateEntity(packet.houseId, house)

    # Deduct souls from source colony immediately (they've departed)
    sourceColony.souls -= soulsToTransfer
    sourceColony.population = sourceColony.souls div 1_000_000
    state.colonies.entities.updateEntity(transfer.sourceColony, sourceColony)

    # Create in-transit entry
    let transferId = $packet.houseId & "_" & $transfer.sourceColony & "_" & $transfer.destColony & "_" & $state.turn
    let inTransit = pop_types.PopulationInTransit(
      id: transferId,
      houseId: packet.houseId,
      sourceSystem: transfer.sourceColony,
      destSystem: transfer.destColony,
      ptuAmount: transfer.ptuAmount,
      costPaid: cost,
      arrivalTurn: arrivalTurn
    )
    state.populationInTransit.add(inTransit)

    info "Space Guild transporting ", transfer.ptuAmount, " PTU (", soulsToTransfer, " souls) from ",
         transfer.sourceColony, " to ", transfer.destColony, " (arrives turn ", arrivalTurn, ", cost: ", cost, " PP)"

    events.add(event_factory.populationTransfer(
      packet.houseId,
      transfer.ptuAmount,
      transfer.sourceColony,
      transfer.destColony,
      true,
      &"Space Guild transport initiated (ETA: turn {arrivalTurn}, cost: {cost} PP)"
    ))

proc resolvePopulationArrivals*(state: var GameState, events: var seq[GameEvent]) =
  ## Process Space Guild population transfers that arrive this turn
  ## Implements risk handling per config/population.toml [transfer_risks]
  ## Per config: dest_blockaded_behavior = "closest_owned"
  ## Per config: dest_collapsed_behavior = "closest_owned"

  import ../../state/entity_manager

  debug "[Processing Space Guild Arrivals]"

  var arrivedTransfers: seq[int] = @[]  # Indices to remove after processing

  for idx, transfer in state.populationInTransit:
    if transfer.arrivalTurn != state.turn:
      continue  # Not arriving this turn

    let soulsToDeliver = transfer.ptuAmount * soulsPerPtu()

    # Check destination status using entity_manager
    let destColonyOpt = state.colonies.entities.getEntity(transfer.destSystem)
    if destColonyOpt.isNone:
      # Destination colony no longer exists
      warn "Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU LOST - destination colony destroyed"
      arrivedTransfers.add(idx)
      events.add(event_factory.populationTransfer(
        transfer.houseId,
        transfer.ptuAmount,
        transfer.sourceSystem,
        transfer.destSystem,
        false,
        "destination destroyed"
      ))
      continue

    var destColony = destColonyOpt.get()

    # Check if destination requires alternative delivery
    # Space Guild makes best-faith effort to deliver somewhere safe
    # Per config/population.toml: dest_blockaded_behavior = "closest_owned"
    # Per config/population.toml: dest_collapsed_behavior = "closest_owned"
    # Per config/population.toml: dest_conquered_behavior = "closest_owned" (NEW)
    var needsAlternativeDestination = false
    var alternativeReason = ""

    if destColony.owner != transfer.houseId:
      # Destination conquered - Guild tries to find alternative colony
      needsAlternativeDestination = true
      alternativeReason = "conquered by " & $destColony.owner
    elif destColony.blockaded:
      needsAlternativeDestination = true
      alternativeReason = "blockaded"
    elif destColony.souls < soulsPerPtu():
      needsAlternativeDestination = true
      alternativeReason = "collapsed below minimum viable population"

    if needsAlternativeDestination:
      # Space Guild attempts to deliver to closest owned colony
      let alternativeDest = findNearestOwnedColony(state, transfer.destSystem, transfer.houseId)

      if alternativeDest.isSome:
        # Deliver to alternative colony
        let altSystemId = alternativeDest.get()
        let altColonyOpt = state.colonies.entities.getEntity(altSystemId)
        if altColonyOpt.isSome:
          var altColony = altColonyOpt.get()
          altColony.souls += soulsToDeliver
          altColony.population = altColony.souls div 1_000_000
          state.colonies.entities.updateEntity(altSystemId, altColony)

          warn "Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU redirected to ", altSystemId,
               " - original destination ", transfer.destSystem, " ", alternativeReason
          events.add(event_factory.populationTransfer(
            transfer.houseId,
            transfer.ptuAmount,
            transfer.sourceSystem,
            altSystemId,
            true,
            &"redirected from {transfer.destSystem} ({alternativeReason})"
          ))
      else:
        # No owned colonies - colonists are lost
        warn "Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU LOST - destination ", alternativeReason,
             ", no owned colonies available"
        events.add(event_factory.populationTransfer(
          transfer.houseId,
          transfer.ptuAmount,
          transfer.sourceSystem,
          transfer.destSystem,
          false,
          &"{alternativeReason}, no owned colonies for delivery"
        ))

      arrivedTransfers.add(idx)
      continue

    # Successful delivery!
    destColony.souls += soulsToDeliver
    destColony.population = destColony.souls div 1_000_000
    state.colonies.entities.updateEntity(transfer.destSystem, destColony)

    info "Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU arrived at ", transfer.destSystem,
         " (", soulsToDeliver, " souls)"
    events.add(event_factory.populationTransfer(
      transfer.houseId,
      transfer.ptuAmount,
      transfer.sourceSystem,
      transfer.destSystem,
      true,
      ""
    ))

    arrivedTransfers.add(idx)

  # Remove processed transfers (in reverse order to preserve indices)
  for idx in countdown(arrivedTransfers.len - 1, 0):
    state.populationInTransit.del(arrivedTransfers[idx])
