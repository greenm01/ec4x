## Colonize Order Execution
##
## This module contains the logic for executing the 'Colonize' fleet order,
## which involves establishing new colonies on planets.

import std/[options, tables, sequtils, strformat]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../squadron, ../../starmap, ../../logger
import ../../index_maintenance
import ../../state_helpers
import ../../initialization/colony # For createETACColony
import ../../colonization/engine as col_engine # For establishColony
import ../../config/population_config # For soulsPerPtu
import ../../prestige # For applyPrestigeEvent
import ../../types/resolution as resolution_types # For GameEvent
import ../../events/event_factory/init as event_factory # For event creation
import ../../intelligence/generator # For generateColonyIntelReport, generateSystemIntelReport
import ../../intelligence/types as intel_types # For IntelQuality, ColonyIntelReport
import ../main as orders # For FleetOrder and FleetOrderType
import ../utils/order_utils # For completeFleetOrder

proc executeColonizeOrder*(
  state: var GameState, fleet: Fleet, order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 10: Establish a new colony with prestige rewards
  if order.targetSystem.isNone:
    return OrderOutcome.Failed

  let targetId = order.targetSystem.get()
  let houseId = fleet.owner

  # Check if system already colonized
  if targetId in state.colonies:
    let colony = state.colonies[targetId]

    # ORBITAL INTELLIGENCE GATHERING
    # Fleet approaching colony for colonization/guard/blockade gets close enough to see orbital defenses
    if colony.owner != houseId:
      # Generate detailed colony intel including orbital defenses
      let colonyIntel = generateColonyIntelReport(state, houseId, targetId, intel_types.IntelQuality.Visual)
      if colonyIntel.isSome:
        state.withHouse(houseId):
          house.intelligence.addColonyReport(colonyIntel.get())
        logDebug(LogCategory.lcFleet, &"Fleet {order.fleetId} gathered orbital intelligence on enemy colony at {targetId}")

      # Also gather system intel on any fleets present (including guard/reserve fleets)
      let systemIntel = generateSystemIntelReport(state, houseId, targetId, intel_types.IntelQuality.Visual)
      if systemIntel.isSome:
        state.withHouse(houseId):
          house.intelligence.addSystemReport(systemIntel.get())

    logWarn(LogCategory.lcColonization, &"Fleet {order.fleetId}: System {targetId} already colonized by {colony.owner}")
    order_utils.completeFleetOrder(
      state, order.fleetId, "Colonize",
      details = &"failed: system already colonized by {colony.owner}",
      systemId = some(targetId),
      events
    )
    return OrderOutcome.Failed

  # Check system exists
  if targetId notin state.starMap.systems:
    logError(LogCategory.lcColonization, &"Fleet {order.fleetId}: System {targetId} not found in starMap")
    order_utils.completeFleetOrder(
      state, order.fleetId, "Colonize",
      details = &"failed: target system not found",
      systemId = some(targetId),
      events
    )
    return OrderOutcome.Failed

  # If fleet not at target, move there first (THIS SHOULD BE HANDLED BY DISPATCHER)
  # The dispatcher (fleet_order_executor) should ensure the fleet is at the target
  # before calling the execution module. So, if we are here, we assume fleet.location == targetId
  if fleet.location != targetId:
    logError(LogCategory.lcColonization, &"Fleet {order.fleetId} not at target {targetId} during colonization execution. This should be handled by dispatcher.")
    return OrderOutcome.Failed # Should not happen if dispatcher works correctly

  # Check fleet has colonists (in Expansion squadrons)
  var hasColonists = false
  for squadron in fleet.squadrons:
    if squadron.squadronType == SquadronType.Expansion:
      if squadron.flagship.cargo.isSome:
        let cargo = squadron.flagship.cargo.get()
        if cargo.cargoType == CargoType.Colonists and cargo.quantity > 0:
          hasColonists = true
          break

  if not hasColonists:
    logError(LogCategory.lcColonization, &"Fleet {order.fleetId} has no colonists (PTU) - colonization failed")
    order_utils.completeFleetOrder(
      state, order.fleetId, "Colonize",
      details = &"failed: no colonists found in fleet",
      systemId = some(targetId),
      events
    )
    return OrderOutcome.Failed

  # Establish colony using system\'s actual planet properties
  # Get system to determine planet class and resources
  let system = state.starMap.systems[targetId]
  let planetClass = system.planetClass
  let resources = system.resourceRating

  # Get PTU quantity from ETAC cargo (should be 3 for new ETACs)
  var ptuToDeposit = 0
  for squadron in fleet.squadrons:
    if squadron.squadronType == SquadronType.Expansion:
      if squadron.flagship.cargo.isSome:
        let cargo = squadron.flagship.cargo.get()
        if cargo.cargoType == CargoType.Colonists:
          ptuToDeposit = cargo.quantity
          break

  logInfo(LogCategory.lcColonization, &"Fleet {order.fleetId} colonizing {planetClass} world with {resources} resources at {targetId} (depositing {ptuToDeposit} PTU)")

  # Create ETAC colony (foundation colony with ptuToDeposit starter population)
  let colony = createETACColony(targetId, houseId, planetClass, resources,
                                ptuToDeposit)

  # Use colonization engine to establish with prestige
  let colEngineResult = col_engine.establishColony(
    houseId,
    targetId,
    colony.planetClass,
    colony.resources,
    ptuToDeposit  # Deposit all cargo (3 PTU = 3 PU foundation colony)
  )

  if not colEngineResult.success:
    logError(LogCategory.lcColonization, &"Failed to establish colony at {targetId}")
    order_utils.completeFleetOrder(
      state, order.fleetId, "Colonize",
      details = &"failed to establish colony",
      systemId = some(targetId),
      events
    )
    return OrderOutcome.Failed

  state.colonies[targetId] = colony

  # Unload colonists from Expansion squadrons
  for squadron in fleet.squadrons.mitems:
    if squadron.squadronType == SquadronType.Expansion:
      if squadron.flagship.cargo.isSome:
        var cargo = squadron.flagship.cargo.get()
        if cargo.cargoType == CargoType.Colonists:
          logInfo(LogCategory.lcColonization,
            &"⚠️  PRE-UNLOAD: {squadron.flagship.shipClass} {squadron.id} has {cargo.quantity} PTU")
          # Unload cargo
          cargo.quantity = 0
          cargo.cargoType = CargoType.None
          squadron.flagship.cargo = some(cargo)
          logInfo(LogCategory.lcColonization,
            &"⚠️  POST-UNLOAD: {squadron.flagship.shipClass} {squadron.id} has {cargo.quantity} PTU")

  # ETAC cannibalized - remove from game, structure becomes colony infrastructure
  logInfo(LogCategory.lcColonization,
    &"⚠️  CANNIBALIZATION CHECK: Fleet {order.fleetId} has " &
    &"{fleet.squadrons.len} squadrons")

  var cannibalized_count = 0
  for i in countdown(fleet.squadrons.high, 0):
    let squadron = fleet.squadrons[i]
    if squadron.squadronType == SquadronType.Expansion:
      let cargo = squadron.flagship.cargo
      let cargoQty = if cargo.isSome: cargo.get().quantity else: 0
      logInfo(LogCategory.lcColonization,
        &"⚠️  Squadron {i}: class={squadron.flagship.shipClass}, cargoQty={cargoQty}")

      if squadron.flagship.shipClass == ShipClass.ETAC and cargoQty == 0:
        # ETAC cannibalized - ship structure becomes starting IU
        fleet.squadrons.delete(i)
        cannibalized_count += 1

        # Fire GameEvent for colonization success
        events.add(event_factory.GameEvent(
          eventType: event_factory.GameEventType.ColonyEstablished,
          turn: state.turn,
          houseId: some(houseId),
          systemId: some(targetId),
          description: &"ETAC {squadron.id} cannibalized establishing colony infrastructure",
          colonyEventType: some("Established")
        ))

        logInfo(LogCategory.lcColonization,
          &"⚠️  ✅ CANNIBALIZED ETAC {squadron.id} at {targetId}")

  logInfo(LogCategory.lcColonization,
    &"⚠️  CANNIBALIZATION RESULT: {cannibalized_count} ETACs removed, " &
    &"{fleet.squadrons.len} squadrons remain")

  state.fleets[order.fleetId] = fleet

  # Apply prestige award
  var prestigeAwarded = 0
  if colEngineResult.prestigeEvent.isSome:
    let prestigeEvent = colEngineResult.prestigeEvent.get()
    prestigeAwarded = prestigeEvent.amount
    applyPrestigeEvent(state, houseId, prestigeEvent)
    logInfo(LogCategory.lcColonization, &"{state.houses[houseId].name} colonized system {targetId} (+{prestigeEvent.amount} prestige)")

  # Generate event
  events.add(event_factory.colonyEstablished(
    houseId,
    targetId,
    prestigeAwarded
  ))

  # Generate OrderCompleted event for successful colonization
  # Cleanup handled by Command Phase
  order_utils.completeFleetOrder(
    state, order.fleetId, "Colonize",
    details = &"established colony at {targetId}",
    systemId = some(targetId),
    events # Pass events directly
  )

  logDebug(LogCategory.lcColonization,
    &"Fleet {order.fleetId} colonization complete, cleanup deferred to Command Phase")

  return OrderOutcome.Success
