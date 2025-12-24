## Simultaneous Colonization Resolution
##
## Handles simultaneous resolution of colonization orders to prevent first-mover advantages.
## Implements collection, conflict detection, resolution, and fallback logic.

import std/[tables, options, random, sequtils, algorithm, strformat]
import ../../types/simultaneous as simultaneous_types
import ../combat/simultaneous_resolver
import ../../gamestate
import ../../index_maintenance
import ../../orders
import ../../order_types
import ../../squadron
import ../../fleet
import ../../logger
import ../../state_helpers
import ../../starmap
import ../../initialization/colony
import ../colonization/engine as col_engine
import ../../standing_orders
import ../../types/resolution as res_types
import ../../event_factory/init as event_factory
import ../../types/core
import ../../types/planets
import ../../prestige as prestige_types
import ../../prestige/application as prestige_app

proc collectColonizationIntents*(
  state: GameState,
  orders: Table[HouseId, OrderPacket]
): seq[ColonizationIntent] =
  ## Collect all colonization attempts from all houses before executing any
  ##
  ## Returns: Sequence of validated colonization intents
  result = @[]

  for houseId in state.houses.keys:
    if houseId notin orders:
      continue

    for command in orders[houseId].fleetCommands:
      if command.commandType != FleetCommandType.Colonize:
        continue

      # Validate: fleet exists
      if command.fleetId notin state.fleets:
        continue

      let fleet = state.fleets[command.fleetId]

      # Validate: fleet has colonists (PTUs) in Expansion/Auxiliary squadron cargo
      var hasColonists = false
      for squadron in fleet.squadrons:
        if squadron.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
          if squadron.flagship.cargo.isSome:
            let cargo = squadron.flagship.cargo.get()
            if cargo.cargoType == CargoType.Colonists and cargo.quantity > 0:
              hasColonists = true
              break
      if not hasColonists:
        continue

      # Calculate fleet strength for conflict resolution (total attack strength)
      var fleetStrength = 0
      for squadron in fleet.squadrons:
        fleetStrength += squadron.combatStrength()

      # AutoColonize standing commands removed - manual orders only
      let hasStandingOrders = false

      # Get target system from order
      if command.targetSystem.isNone:
        continue

      let targetSystem = command.targetSystem.get()

      # Add validated intent
      result.add(ColonizationIntent(
        houseId: houseId,
        fleetId: command.fleetId,
        targetSystem: targetSystem,
        fleetStrength: fleetStrength,
        hasStandingOrders: hasStandingOrders
      ))

proc detectColonizationConflicts*(
  intents: seq[ColonizationIntent]
): seq[ColonizationConflict] =
  ## Group colonization intents by target system to detect conflicts
  ##
  ## Returns: Sequence of conflicts (one per contested system)
  var systemTargets = initTable[SystemId, seq[ColonizationIntent]]()

  # Group by target system
  for intent in intents:
    if intent.targetSystem notin systemTargets:
      systemTargets[intent.targetSystem] = @[]
    systemTargets[intent.targetSystem].add(intent)

  # Create conflict objects
  result = @[]
  for systemId, conflictingIntents in systemTargets:
    result.add(ColonizationConflict(
      targetSystem: systemId,
      intents: conflictingIntents
    ))

proc establishColony(
  state: var GameState,
  houseId: HouseId,
  fleetId: FleetId,
  systemId: SystemId,
  events: var seq[res_types.GameEvent]
): tuple[success: bool, prestigeAwarded: int] =
  ## Establish a colony at the target system for the given fleet
  ##
  ## Returns: Success status and prestige awarded
  result = (success: false, prestigeAwarded: 0)

  # Validate system not already colonized
  if systemId in state.colonies:
    logWarn(LogCategory.lcColonization, &"System {systemId} already colonized")
    return

  # Validate system exists
  if systemId notin state.starMap.systems:
    logError(LogCategory.lcColonization, &"System {systemId} not found in starMap")
    return

  # Get fleet
  if fleetId notin state.fleets:
    logError(LogCategory.lcColonization, &"Fleet {fleetId} not found")
    return

  var fleet = state.fleets[fleetId]

  # Validate fleet has colonists in Expansion/Auxiliary squadron cargo
  var hasColonists = false
  var colonistSquadronIdx = -1
  for idx, squadron in fleet.squadrons:
    if squadron.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
      if squadron.flagship.cargo.isSome:
        let cargo = squadron.flagship.cargo.get()
        if cargo.cargoType == CargoType.Colonists and cargo.quantity > 0:
          hasColonists = true
          colonistSquadronIdx = idx
          break

  if not hasColonists:
    logError(LogCategory.lcColonization, &"Fleet {fleetId} has no colonists")
    return

  # Get system properties
  let system = state.starMap.systems[systemId]
  let planetClass = system.planetClass
  let resources = system.resourceRating

  logInfo(LogCategory.lcColonization,
          &"Fleet {fleetId} colonizing {planetClass} world with {resources} resources at {systemId}")

  # Get PTU quantity from ETAC cargo (one-time consumable: deposits all PTU)
  let squadron = fleet.squadrons[colonistSquadronIdx]
  let cargo = squadron.flagship.cargo.get()
  let ptuToDeposit = cargo.quantity

  # Create ETAC colony with all PTU (foundation colony)
  let colony = createETACColony(systemId, houseId, planetClass, resources)

  # Use colonization engine to establish with prestige
  let colResult = col_engine.establishColony(
    houseId,
    systemId,
    colony.planetClass,
    colony.resources,
    ptuToDeposit  # Deposit all PTU (3 PTU = 3 PU foundation colony)
  )

  if not colResult.success:
    logError(LogCategory.lcColonization, &"Failed to establish colony at {systemId}")
    return

  # Add colony to state
  state.colonies[systemId] = colony

  # Unload ALL PTU from ETAC flagship (one-time consumable)
  var etacSquadron = fleet.squadrons[colonistSquadronIdx]
  let transferredPTU = ptuToDeposit
  etacSquadron.flagship.cargo = some(ShipCargo(
    cargoType: CargoType.None,
    quantity: 0,
    capacity: cargo.capacity
  ))
  logDebug(LogCategory.lcColonization,
    &"ETAC squadron {etacSquadron.id} transferred {transferredPTU} PTU to establish colony at {systemId} " &
    &"(0 PTU remaining)")

  # ETAC cannibalized - remove squadron from fleet, structure becomes colony infrastructure
  if etacSquadron.flagship.shipClass == ShipClass.ETAC:
    # Remove the squadron from fleet
    var newSquadrons: seq[Squadron] = @[]
    for idx, sq in fleet.squadrons:
      if idx != colonistSquadronIdx:
        newSquadrons.add(sq)
    fleet.squadrons = newSquadrons
    logInfo(LogCategory.lcEconomy,
      &"ETAC squadron {etacSquadron.id} cannibalized - structure became colony infrastructure at {systemId}")

  # Check if fleet is now empty (no squadrons)
  # Empty fleets should be automatically cleaned up to avoid maintenance waste
  if fleet.squadrons.len == 0:
    # Fleet is empty - remove it and cleanup associated orders
    state.removeFleetFromIndices(fleetId, fleet.owner, fleet.location)
    state.fleets.del(fleetId)
    if fleetId in state.fleetCommands:
      state.fleetCommands.del(fleetId)
    if fleetId in state.standingCommands:
      state.standingCommands.del(fleetId)
    logInfo(LogCategory.lcFleet,
            &"Removed empty fleet {fleetId} after ETAC colonization (auto-cleanup)")
  else:
    # Fleet still has ships - update it
    state.fleets[fleetId] = fleet

  # Apply prestige award
  if colResult.prestigeEvent.isSome:
    let prestigeEvent = colResult.prestigeEvent.get()
    prestige_app.applyPrestigeEvent(state, houseId, prestigeEvent)
    result.prestigeAwarded = prestigeEvent.amount
    logInfo(LogCategory.lcColonization,
            &"{state.houses[houseId].name} colonized {systemId} (+{prestigeEvent.amount} prestige)")

  # Generate ColonyEstablished event for diagnostics
  events.add(event_factory.colonyEstablished(
    houseId,
    systemId,
    result.prestigeAwarded
  ))

  # Generate OrderCompleted event for successful colonization
  # Cleanup handled by Command Phase
  events.add(event_factory.commandCompleted(
    houseId, fleetId, "Colonize",
    details = &"established colony at {systemId}",
    systemId = some(systemId)
  ))

  logDebug(LogCategory.lcColonization,
    &"Fleet {fleetId} colonization complete, cleanup deferred to Command Phase")

  result.success = true

proc findBestColonizationTarget(
  state: GameState,
  fleet: Fleet,
  currentLocation: SystemId,
  maxRange: int,
  preferredClasses: seq[PlanetClass]
): Option[SystemId] =
  ## Find best uncolonized system for colonization
  ## Returns nearest system with preferred planet class
  var candidates: seq[(SystemId, int, PlanetClass)] = @[]

  # Scan all systems within range
  for systemId, system in state.starMap.systems:
    # Skip if already colonized
    if systemId in state.colonies:
      continue

    # Check distance via jump lanes
    let pathResult = state.starMap.findPath(currentLocation, systemId, fleet)
    if not pathResult.found:
      continue

    let distance = pathResult.path.len - 1
    if distance > maxRange:
      continue

    # Add as candidate
    candidates.add((systemId, distance, system.planetClass))

  if candidates.len == 0:
    return none(SystemId)

  # Sort by: 1) preferred class (top priority), 2) distance (tiebreaker)
  candidates.sort(
    proc(a, b: (SystemId, int, PlanetClass)): int =
      let aPreferred = preferredClasses.len == 0 or a[2] in preferredClasses
      let bPreferred = preferredClasses.len == 0 or b[2] in preferredClasses

      if aPreferred and not bPreferred:
        return -1  # a wins
      elif bPreferred and not aPreferred:
        return 1   # b wins
      else:
        # Both preferred or both not preferred - use distance
        return cmp(a[1], b[1])
  )

  return some(candidates[0][0])

proc collectFallbackIntents(
  state: GameState,
  losers: seq[ColonizationIntent],
  originalTargets: Table[FleetId, SystemId]
): seq[ColonizationIntent] =
  ## Collect fallback colonization intents from losers
  ## NOTE: AutoColonize standing commands removed - this now returns empty
  ## Fallback behavior no longer supported (manual orders only)
  ##
  ## Returns: Empty sequence (no fallback intents)
  result = @[]

proc resolveColonizationConflict*(
  state: var GameState,
  conflict: ColonizationConflict,
  rng: var Rand,
  events: var seq[res_types.GameEvent]
): tuple[results: seq[simultaneous_types.ColonizationResult], losers: seq[ColonizationIntent]] =
  ## Resolve a single colonization conflict using fleet strength + random tiebreaker
  ##
  ## Returns: Results for winners and list of losers for fallback processing
  result.results = @[]
  result.losers = @[]

  if conflict.intents.len == 0:
    return

  # Single intent = no conflict, just colonize
  if conflict.intents.len == 1:
    let intent = conflict.intents[0]
    let (success, prestige) = establishColony(
      state,
      intent.houseId,
      intent.fleetId,
      intent.targetSystem,
      events
    )

    if success:
      result.results.add(simultaneous_types.ColonizationResult(
        houseId: intent.houseId,
        fleetId: intent.fleetId,
        originalTarget: intent.targetSystem,
        outcome: ResolutionOutcome.Success,
        actualTarget: some(intent.targetSystem),
        prestigeAwarded: prestige
      ))
    else:
      # Single intent failed - treat as loser for fallback
      result.losers.add(intent)
    return

  # Multiple intents = conflict
  # Use generic resolver to find winner
  let seed = tiebreakerSeed(state.turn, conflict.targetSystem)
  let winner = resolveConflictByStrength(
    conflict.intents,
    colonizationStrength,
    seed,
    rng
  )

  logInfo(LogCategory.lcColonization,
          &"Colonization conflict at {conflict.targetSystem}: {conflict.intents.len} houses competing")

  # Establish colony for winner
  let (success, prestige) = establishColony(
    state,
    winner.houseId,
    winner.fleetId,
    winner.targetSystem,
    events
  )

  if success:
    result.results.add(simultaneous_types.ColonizationResult(
      houseId: winner.houseId,
      fleetId: winner.fleetId,
      originalTarget: winner.targetSystem,
      outcome: ResolutionOutcome.Success,
      actualTarget: some(winner.targetSystem),
      prestigeAwarded: prestige
    ))
  else:
    # Winner failed - add to losers
    result.losers.add(winner)

  # Collect all losers for fallback processing
  let conflictLosers = conflict.intents.filterIt(it.houseId != winner.houseId or it.fleetId != winner.fleetId)
  for loser in conflictLosers:
    result.losers.add(loser)
    result.results.add(simultaneous_types.ColonizationResult(
      houseId: loser.houseId,
      fleetId: loser.fleetId,
      originalTarget: loser.targetSystem,
      outcome: ResolutionOutcome.ConflictLost,
      actualTarget: none(SystemId),
      prestigeAwarded: 0
    ))

    # Generate OrderFailed event for colonization conflict loss
    events.add(event_factory.commandFailed(
      loser.houseId,
      loser.fleetId,
      "Colonize",
      reason = "lost colonization race to another house",
      systemId = some(loser.targetSystem)
    ))

proc resolveColonization*(
  state: var GameState,
  orders: Table[HouseId, OrderPacket],
  rng: var Rand,
  events: var seq[res_types.GameEvent]
): seq[simultaneous_types.ColonizationResult] =
  ## Main entry point: Resolve all colonization orders simultaneously
  ##
  ## Returns: Results for all colonization attempts
  result = @[]

  # Phase 1: Collect all colonization intents
  let intents = collectColonizationIntents(state, orders)

  if intents.len == 0:
    return  # No colonization orders this turn

  # Phase 2: Detect conflicts
  let conflicts = detectColonizationConflicts(intents)

  # Phase 3: Resolve each conflict and collect losers
  var allLosers: seq[ColonizationIntent] = @[]
  var originalTargets = initTable[FleetId, SystemId]()

  for conflict in conflicts:
    let (conflictResults, losers) = resolveColonizationConflict(state, conflict, rng, events)
    result.add(conflictResults)

    # Track losers and their original targets
    for loser in losers:
      allLosers.add(loser)
      originalTargets[loser.fleetId] = conflict.targetSystem

  # Phase 4: Handle fallback recursively (max 3 iterations to prevent infinite loops)
  var fallbackRound = 0
  const maxFallbackRounds = 3

  while allLosers.len > 0 and fallbackRound < maxFallbackRounds:
    fallbackRound += 1
    logDebug(LogCategory.lcColonization,
             &"Fallback round {fallbackRound}: {allLosers.len} fleets seeking alternatives")

    # Collect fallback intents
    let fallbackIntents = collectFallbackIntents(state, allLosers, originalTargets)

    if fallbackIntents.len == 0:
      # No viable fallback targets found
      for loser in allLosers:
        result.add(simultaneous_types.ColonizationResult(
          houseId: loser.houseId,
          fleetId: loser.fleetId,
          originalTarget: originalTargets[loser.fleetId],
          outcome: ResolutionOutcome.NoViableTarget,
          actualTarget: none(SystemId),
          prestigeAwarded: 0
        ))

        # Generate OrderFailed event for no viable colonization target
        events.add(event_factory.commandFailed(
          loser.houseId,
          loser.fleetId,
          "Colonize",
          reason = "no viable fallback colonization target found",
          systemId = some(originalTargets[loser.fleetId])
        ))
      break

    # Detect conflicts on fallback targets
    let fallbackConflicts = detectColonizationConflicts(fallbackIntents)

    # Resolve fallback conflicts
    var nextRoundLosers: seq[ColonizationIntent] = @[]

    for conflict in fallbackConflicts:
      let (conflictResults, losers) = resolveColonizationConflict(state, conflict, rng, events)

      # Update results: mark successful fallbacks appropriately
      for res in conflictResults:
        var updatedRes = res
        if res.outcome == ResolutionOutcome.Success:
          updatedRes.outcome = ResolutionOutcome.FallbackSuccess
          updatedRes.originalTarget = originalTargets[res.fleetId]
          logInfo(LogCategory.lcColonization,
                  &"House {res.houseId} fallback colonization succeeded at {res.actualTarget.get()}")
          # Cleanup handled by Command Phase (OrderCompleted event generated by establishColony)
        result.add(updatedRes)

      nextRoundLosers.add(losers)

    allLosers = nextRoundLosers

  # Any remaining losers have no viable targets
  for loser in allLosers:
    result.add(simultaneous_types.ColonizationResult(
      houseId: loser.houseId,
      fleetId: loser.fleetId,
      originalTarget: originalTargets[loser.fleetId],
      outcome: ResolutionOutcome.NoViableTarget,
      actualTarget: none(SystemId),
      prestigeAwarded: 0
    ))

    # Generate OrderFailed event for exhausted fallback attempts
    events.add(event_factory.commandFailed(
      loser.houseId,
      loser.fleetId,
      "Colonize",
      reason = "exhausted all fallback colonization attempts",
      systemId = some(originalTargets[loser.fleetId])
    ))

proc wasColonizationHandled*(
  results: seq[simultaneous_types.ColonizationResult],
  houseId: HouseId,
  fleetId: FleetId
): bool =
  ## Check if a colonization order was already handled in simultaneous phase
  ##
  ## Used to skip already-processed orders in main fleet order loop
  for result in results:
    if result.houseId == houseId and result.fleetId == fleetId:
      return true
  return false
