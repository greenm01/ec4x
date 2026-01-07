## Colonization Resolution
##
## Handles simultaneous colonization order resolution:
## 1. Collect intents from all houses
## 2. Detect conflicts (multiple fleets → same system)
## 3. Resolve via fleet strength + randomness (Option B)
## 4. Establish colonies for winners
## 5. Generate events for all outcomes
##
## Per operations.md:6.3.12 - Colonize a Planet command

## NOTE: This file is included by engine.nim, not imported
## Do not add it to imports elsewhere - use systems/colony/engine instead

import std/[tables, options, random, strformat]
import
  ../../types/[core, game_state, fleet, ship, starmap, colony, event, prestige]
import ../../state/[engine, iterators, fleet_queries]
import ../../entities/[fleet_ops, ship_ops, colony_ops]
import ../../event_factory/init
import ../../prestige/engine
import ../../../common/logger
import ../../globals

# Conflict resolution tuning
const StrengthWeight = 2
  ## Weight for fleet AS in conflict resolution
  ## Formula: score = random(1..100) + (fleetAS * StrengthWeight)
  ## Higher values make strength more influential vs luck

proc canColonize*(state: GameState, systemId: SystemId): bool =
  ## Check if a system can be colonized (no existing colony)
  ## Per operations.md:6.3.12
  state.colonyBySystem(systemId).isNone

proc establishColony*(
    state: var GameState,
    houseId: HouseId,
    systemId: SystemId,
    planetClass: PlanetClass,
    resources: ResourceRating,
    ptuCount: int32,
): Option[ColonyId] =
  ## Establish a new colony at system
  ##
  ## Returns:
  ## - Some(ColonyId) if successful
  ## - None if validation fails (logs error)
  ##
  ## Validation:
  ## - System must not already have a colony
  ## - Must have at least 1 PTU
  ##
  ## Side effects:
  ## - Creates colony entity via @entities/colony_ops
  ## - Awards prestige via prestige system

  # Validate: System must be uncolonized
  if not canColonize(state, systemId):
    logError("Colonization",
      &"Cannot colonize {systemId}: system already has colony")
    return none(ColonyId)

  # Validate: Must have PTU
  if ptuCount < 1:
    logError("Colonization",
      &"Cannot colonize {systemId}: insufficient PTU (need ≥1, got {ptuCount})")
    return none(ColonyId)

  # Create colony via entities layer (low-level state mutation)
  let colonyId = colony_ops.establishColony(
    state, systemId, houseId, planetClass, resources, ptuCount
  )

  # Award prestige
  let basePrestige = gameConfig.prestige.economic.establishColony
  let prestigeEvent = PrestigeEvent(
    source: PrestigeSource.ColonyEstablished,
    amount: basePrestige,
    description: &"Established colony at system {systemId}",
  )
  applyPrestigeEvent(state, houseId, prestigeEvent)

  logInfo("Colonization",
    &"House {houseId} established colony at {systemId} " &
    &"({planetClass}, {resources}, {ptuCount} PU) [+{basePrestige} prestige]")

  return some(colonyId)

# ============================================================================
# Phase 1: Intent Collection
# ============================================================================

proc collectColonizationIntents(state: GameState): seq[ColonizationIntent] =
  ## Collect all colonization attempts from arrived fleets
  ## Uses state layer iterator - clean separation of concerns
  result = @[]

  for (fleetId, fleet, command) in state.fleetsWithColonizeCommand():
    # Validate: Has colonists (ETAC with PTU cargo)
    if not state.hasColonists(fleet):
      logWarn("Colonization",
        &"Fleet {fleetId} has Colonize order but no colonists")
      continue

    # Validate: Target system specified
    if command.targetSystem.isNone:
      logWarn("Colonization",
        &"Fleet {fleetId} has Colonize order but no target system")
      continue

    let targetSystem = command.targetSystem.get()
    let fleetStrength = state.calculateFleetAS(fleet)

    result.add(
      ColonizationIntent(
        houseId: fleet.houseId,
        fleetId: fleetId,
        targetSystem: targetSystem,
        fleetStrength: fleetStrength,
      )
    )

    logDebug(
      "Colonization",
      &"Collected intent: Fleet {fleetId} → System {targetSystem} (AS={fleetStrength})",
    )

# ============================================================================
# Phase 2: Conflict Detection
# ============================================================================

proc detectConflicts(
    intents: seq[ColonizationIntent]
): seq[ColonizationConflict] =
  ## Group intents by target system to find conflicts
  var bySystem = initTable[SystemId, seq[ColonizationIntent]]()

  for intent in intents:
    if intent.targetSystem notin bySystem:
      bySystem[intent.targetSystem] = @[]
    bySystem[intent.targetSystem].add(intent)

  result = @[]
  for systemId, conflictingIntents in bySystem:
    if conflictingIntents.len > 1:
      logInfo(
        "Colonization",
        &"Conflict detected at {systemId}: {conflictingIntents.len} fleets competing",
      )
    result.add(
      ColonizationConflict(targetSystem: systemId, intents: conflictingIntents)
    )

# ============================================================================
# Phase 3: Conflict Resolution (Option B: Strength + Randomness)
# ============================================================================

proc resolveConflict(
    conflict: ColonizationConflict, rng: var Rand
): ColonizationIntent =
  ## Resolve conflict using fleet strength + random factor
  ## Formula: score = random(1..100) + (fleetAS * StrengthWeight)
  ## Higher score wins

  if conflict.intents.len == 0:
    raise newException(ValueError, "Cannot resolve empty conflict")

  if conflict.intents.len == 1:
    return conflict.intents[0]

  var bestIntent: ColonizationIntent
  var bestScore = 0

  for intent in conflict.intents:
    let randomFactor = rng.rand(1 .. 100)
    let strengthFactor = intent.fleetStrength * StrengthWeight
    let totalScore = randomFactor + strengthFactor

    logDebug(
      "Colonization",
      &"  Fleet {intent.fleetId}: roll={randomFactor} + " &
        &"(AS={intent.fleetStrength} × {StrengthWeight}) = {totalScore}",
    )

    if totalScore > bestScore:
      bestScore = totalScore
      bestIntent = intent

  logInfo(
    "Colonization", &"Winner: Fleet {bestIntent.fleetId} (score={bestScore})"
  )

  return bestIntent

# ============================================================================
# Phase 4: Colony Establishment
# ============================================================================

proc establishColonyForFleet(
    state: var GameState, intent: ColonizationIntent, events: var seq[GameEvent]
): ColonizationResult =
  ## Establish colony for winning fleet
  ## Returns result with outcome and details

  # Get fleet
  let fleetOpt = state.fleet(intent.fleetId)
  if fleetOpt.isNone:
    logError("Colonization", &"Fleet {intent.fleetId} not found")
    return
      ColonizationResult(
        houseId: intent.houseId,
        fleetId: intent.fleetId,
        targetSystem: intent.targetSystem,
        outcome: ColonizationOutcome.InsufficientResources,
        colonyId: none(ColonyId),
        prestigeAwarded: 0,
      )

  let fleet = fleetOpt.get()

  # Find ETAC with colonists
  let carrierOpt = state.firstColonistCarrier(fleet)
  if carrierOpt.isNone:
    logError(
      "Colonization",
      &"Fleet {intent.fleetId} has no ETAC with colonists",
    )
    return
      ColonizationResult(
        houseId: intent.houseId,
        fleetId: intent.fleetId,
        targetSystem: intent.targetSystem,
        outcome: ColonizationOutcome.InsufficientResources,
        colonyId: none(ColonyId),
        prestigeAwarded: 0,
      )

  let (etacId, ptuCount) = carrierOpt.get()

  # Get system properties
  let systemOpt = state.system(intent.targetSystem)
  if systemOpt.isNone:
    logError("Colonization", &"System {intent.targetSystem} not found")
    return
      ColonizationResult(
        houseId: intent.houseId,
        fleetId: intent.fleetId,
        targetSystem: intent.targetSystem,
        outcome: ColonizationOutcome.InsufficientResources,
        colonyId: none(ColonyId),
        prestigeAwarded: 0,
      )

  let system = systemOpt.get()

  # Check if system already colonized
  if not canColonize(state, intent.targetSystem):
    logWarn(
      "Colonization", &"System {intent.targetSystem} already colonized"
    )
    return
      ColonizationResult(
        houseId: intent.houseId,
        fleetId: intent.fleetId,
        targetSystem: intent.targetSystem,
        outcome: ColonizationOutcome.SystemOccupied,
        colonyId: none(ColonyId),
        prestigeAwarded: 0,
      )

  # Establish colony via engine layer
  let colonyIdOpt = establishColony(
    state, intent.houseId, intent.targetSystem, system.planetClass,
    system.resourceRating, ptuCount,
  )

  if colonyIdOpt.isNone:
    logError("Colonization", &"Failed to establish colony")
    return
      ColonizationResult(
        houseId: intent.houseId,
        fleetId: intent.fleetId,
        targetSystem: intent.targetSystem,
        outcome: ColonizationOutcome.InsufficientResources,
        colonyId: none(ColonyId),
        prestigeAwarded: 0,
      )

  let colonyId = colonyIdOpt.get()

  # Unload colonists from ETAC (clear cargo)
  let etacOpt = state.ship(etacId)
  if etacOpt.isSome:
    var etac = etacOpt.get()
    if etac.cargo.isSome:
      let capacity = etac.cargo.get().capacity
      etac.cargo =
        some(ShipCargo(cargoType: CargoClass.None, quantity: 0, capacity: capacity))
      state.updateShip(etacId, etac)

  # Cannibalize ETAC (destroy ship)
  ship_ops.destroyShip(state, etacId)
  logInfo(
    "Colonization", &"ETAC {etacId} cannibalized for colony infrastructure"
  )

  # Check if fleet is now empty
  let updatedFleetOpt = state.fleet(intent.fleetId)
  if updatedFleetOpt.isSome and updatedFleetOpt.get().ships.len == 0:
    fleet_ops.destroyFleet(state, intent.fleetId)
    logInfo(
      "Fleet", &"Fleet {intent.fleetId} disbanded after ETAC colonization"
    )

  # Get prestige amount from config
  let prestigeAmount = gameConfig.prestige.economic.establishColony

  # Generate events
  events.add(
    colonyEstablished(intent.houseId, intent.targetSystem, prestigeAmount)
  )

  events.add(
    commandCompleted(
      intent.houseId,
      intent.fleetId,
      "Colonize",
      details = &"established colony at {intent.targetSystem}",
      systemId = some(intent.targetSystem),
    )
  )

  return
    ColonizationResult(
      houseId: intent.houseId,
      fleetId: intent.fleetId,
      targetSystem: intent.targetSystem,
      outcome: ColonizationOutcome.Success,
      colonyId: some(colonyId),
      prestigeAwarded: prestigeAmount,
    )

# ============================================================================
# Phase 5: Main Entry Point
# ============================================================================

proc resolveColonization*(
    state: var GameState, rng: var Rand, events: var seq[GameEvent]
): seq[ColonizationResult] =
  ## Main entry point: Resolve all colonization attempts simultaneously
  ## No fallback behavior - players manage their fleets
  result = @[]

  # Phase 1: Collect intents
  let intents = collectColonizationIntents(state)
  if intents.len == 0:
    return

  logInfo("Colonization", &"Resolving {intents.len} colonization attempts")

  # Phase 2: Detect conflicts
  let conflicts = detectConflicts(intents)

  # Phase 3 & 4: Resolve each conflict and establish colonies
  for conflict in conflicts:
    if conflict.intents.len == 1:
      # No conflict - single fleet
      let intent = conflict.intents[0]
      let colonizationResult = establishColonyForFleet(state, intent, events)
      result.add(colonizationResult)
    else:
      # Conflict - resolve via strength + randomness
      let winner = resolveConflict(conflict, rng)
      let winnerResult = establishColonyForFleet(state, winner, events)
      result.add(winnerResult)

      # Record loser results + generate failure events
      for loser in conflict.intents:
        if loser.fleetId == winner.fleetId:
          continue

        result.add(
          ColonizationResult(
            houseId: loser.houseId,
            fleetId: loser.fleetId,
            targetSystem: loser.targetSystem,
            outcome: ColonizationOutcome.ConflictLost,
            colonyId: none(ColonyId),
            prestigeAwarded: 0,
          )
        )

        events.add(
          commandFailed(
            loser.houseId,
            loser.fleetId,
            "Colonize",
            "lost colonization race to another house",
            some(loser.targetSystem),
          )
        )

  logInfo(
    "Colonization", &"Colonization resolution complete: {result.len} results"
  )

