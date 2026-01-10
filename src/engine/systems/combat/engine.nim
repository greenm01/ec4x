## Theater Progression Orchestrator
##
## Enforces Space → Orbital → Planetary combat sequence per spec 07-combat.md
## Single entry point for all combat in a system called by turn_cycle.
##
## **Combat System Integration:**
## - Uses multi_house.nim for space combat resolution
## - Uses planetary.nim for ground combat
## - Handles theater progression and victory conditions
##
## **Architecture Compliance** (per src/engine/architecture.md):
## - Uses state layer APIs (UFCS pattern)
## - Uses iterators for fleet access (no arrivedOrders table)
## - Uses entity ops for mutations
## - Uses common/logger for logging

import std/[tables, options, random, sequtils]
import ../../../common/logger
import ../../types/[core, game_state, combat, event, fleet, diplomacy, prestige]
import ../../state/[engine, iterators]
import ../../event_factory/init
import ../../prestige/engine
import multi_house # New spec-compliant multi-house combat
import planetary # Planetary combat (bombardment, invasion, blitz)
import cleanup # Post-combat entity cleanup

type
  TheaterResult* = object
    ## Result from a single combat theater
    attackersWon*: bool
    defenderWon*: bool
    wasStalemate*: bool
    survivingAttackers*: seq[HouseId]

  SystemCombatOutcome* = object
    ## Complete outcome of all combat theaters in a system
    systemId*: SystemId
    spaceResult*: Option[TheaterResult]
    orbitalResult*: Option[TheaterResult]
    planetaryAttacks*: int

  AssaultIntent = object
    ## Internal type for planetary assault tracking
    houseId: HouseId
    fleetId: FleetId
    assaultType: FleetCommandType

proc collectAssaultIntents(
  state: GameState,
  systemId: SystemId
): tuple[bombardments: seq[AssaultIntent], invasions: seq[AssaultIntent]] =
  ## Collect planetary assault intents from arrived fleets at this system
  ## Uses iterator pattern instead of arrivedOrders table
  ## Per docs/engine/ec4x_canonical_turn_cycle.md CON1d
  ##
  ## Filters:
  ## - Fleet at this system (location == systemId)
  ## - Fleet arrived (missionState == Executing)
  ## - Fleet has assault command targeting this system
  ## - Fleet still exists (survived space combat)

  result.bombardments = @[]
  result.invasions = @[]

  for fleet in state.fleetsInSystem(systemId):
    # Only fleets that have arrived at their target
    if fleet.missionState != MissionState.Executing:
      continue

    # Check if command targets this system
    let cmd = fleet.command
    if cmd.targetSystem.isNone or cmd.targetSystem.get() != systemId:
      continue

    case cmd.commandType
    of FleetCommandType.Bombard:
      result.bombardments.add(AssaultIntent(
        houseId: fleet.houseId,
        fleetId: fleet.id,
        assaultType: cmd.commandType
      ))
    of FleetCommandType.Invade, FleetCommandType.Blitz:
      result.invasions.add(AssaultIntent(
        houseId: fleet.houseId,
        fleetId: fleet.id,
        assaultType: cmd.commandType
      ))
    else:
      discard

proc collectBlockadeIntents(
  state: GameState,
  systemId: SystemId,
  colonyOwner: HouseId
): seq[tuple[houseId: HouseId, fleetId: FleetId]] =
  ## Collect blockade intents from arrived fleets at this system
  ## Uses iterator pattern instead of arrivedOrders table
  ## Per docs/specs/06-operations.md Section 6.3.8

  result = @[]

  for fleet in state.fleetsInSystem(systemId):
    # Skip if blockading own colony
    if fleet.houseId == colonyOwner:
      continue

    # Only fleets that have arrived at their target
    if fleet.missionState != MissionState.Executing:
      continue

    # Check if command is Blockade targeting this system
    let cmd = fleet.command
    if cmd.commandType != FleetCommandType.Blockade:
      continue

    if cmd.targetSystem.isNone or cmd.targetSystem.get() != systemId:
      continue

    # Check diplomatic status (must be hostile or enemy)
    if (fleet.houseId, colonyOwner) in state.diplomaticRelation:
      let relation = state.diplomaticRelation[(fleet.houseId, colonyOwner)]
      if relation.state in [DiplomaticState.Hostile, DiplomaticState.Enemy]:
        result.add((houseId: fleet.houseId, fleetId: fleet.id))

proc resolveBlockades(
  state: GameState,
  systemId: SystemId,
  colonyId: ColonyId,
  events: var seq[GameEvent]
) =
  ## Resolve simultaneous blockades after planetary combat
  ## Per docs/specs/06-operations.md Section 6.3.8
  ##
  ## Multiple houses can blockade, but penalty applies only once per turn
  ## Blockade requires orbital supremacy (achieved by winning space/orbital combat)

  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return

  let colony = colonyOpt.get()
  let colonyOwner = colony.owner

  # Collect all blockade intents using iterator pattern
  let blockadeIntents = collectBlockadeIntents(state, systemId, colonyOwner)

  # Extract unique blockading houses
  var blockaders: seq[HouseId] = @[]
  for intent in blockadeIntents:
    if intent.houseId notin blockaders:
      blockaders.add(intent.houseId)

  if blockaders.len == 0:
    # No successful blockaders - clear blockade status
    if colony.blockaded:
      var updatedColony = colony
      updatedColony.blockaded = false
      updatedColony.blockadedBy = @[]
      updatedColony.blockadeTurns = 0
      state.updateColony(colonyId, updatedColony)
    return

  # Multiple houses successfully blockading
  logCombat(
    "[BLOCKADE] Colony blockaded",
    " system=", $systemId,
    " blockaders=", $blockaders.len,
    " houses=", $blockaders
  )

  # Update colony blockade status
  var updatedColony = colony
  updatedColony.blockaded = true
  updatedColony.blockadedBy = blockaders
  updatedColony.blockadeTurns += 1
  state.updateColony(colonyId, updatedColony)

  # Generate blockade events for each blockading house
  for intent in blockadeIntents:
    events.add(blockadeSuccessful(
      blockadingHouse = intent.houseId,
      targetColony = systemId,
      colonyOwner = colonyOwner,
      fleetId = intent.fleetId,
      blockadeTurn = updatedColony.blockadeTurns,
      totalBlockaders = blockaders.len
    ))

  # Apply blockade effects ONCE per turn (regardless of number of blockaders)
  # Effects per 06-operations.md:
  # - Production Penalty: 40% capacity (applied in production phase)
  # - Prestige Loss: -2 prestige per turn per blockaded colony
  # - Trade Disruption: Guild transports cannot reach (applied elsewhere)

  # Apply prestige penalty to colony owner
  let prestigePenalty = PrestigeEvent(
    source: PrestigeSource.BlockadePenalty,
    amount: -2'i32,
    description: "Colony blockaded at system " & $systemId
  )
  applyPrestigeEvent(state, colonyOwner, prestigePenalty)

proc determineTheaterOutcome(
  state: GameState,
  combatResults: seq[CombatResult],
  systemId: SystemId,
  systemOwner: Option[HouseId]
): TheaterResult =
  ## Analyze combat results to determine theater outcome
  ## Per docs/specs/07-combat.md Section 7.4

  result = TheaterResult(
    attackersWon: false,
    defenderWon: false,
    wasStalemate: false,
    survivingAttackers: @[],
  )

  if combatResults.len == 0:
    # No combat occurred - check if attackers present
    var hasNonOwnerFleets = false
    for fleet in state.fleetsInSystem(systemId):
      if systemOwner.isNone or fleet.houseId != systemOwner.get():
        hasNonOwnerFleets = true
        if fleet.houseId notin result.survivingAttackers:
          result.survivingAttackers.add(fleet.houseId)

    result.attackersWon = hasNonOwnerFleets
    return

  # Collect all retreated fleets from all combat results
  var allRetreatedFleets: seq[FleetId] = @[]
  for combatResult in combatResults:
    allRetreatedFleets.add(combatResult.attackerRetreatedFleets)
    allRetreatedFleets.add(combatResult.defenderRetreatedFleets)

  # Single pass: determine which houses have surviving fleets
  for fleet in state.fleetsInSystem(systemId):
    if fleet.id notin allRetreatedFleets:
      if fleet.houseId notin result.survivingAttackers:
        result.survivingAttackers.add(fleet.houseId)

  # Determine outcome
  if systemOwner.isNone:
    # No defender - attackers win if any survive
    result.attackersWon = result.survivingAttackers.len > 0
  else:
    let defenderPresent = systemOwner.get() in result.survivingAttackers
    let attackersPresent = result.survivingAttackers.len > 0 and
                          (systemOwner.isNone or
                           result.survivingAttackers.anyIt(it != systemOwner.get()))

    if not defenderPresent and attackersPresent:
      result.attackersWon = true
    elif defenderPresent and not attackersPresent:
      result.defenderWon = true
    elif defenderPresent and attackersPresent:
      result.wasStalemate = true

proc resolveSystemCombat*(
  state: GameState,
  systemId: SystemId,
  events: var seq[GameEvent],
  rng: var Rand,
): seq[CombatResult] =
  ## Single entry point for all combat in a system
  ## Called by turn_cycle/conflict_phase.nim
  ##
  ## Returns seq[CombatResult] with details of all combat in this system.
  ## Enforces theater progression: Space → Orbital → Planetary
  ##
  ## **Architecture Note:**
  ## Uses iterator pattern for fleet access instead of arrivedOrders table.
  ## Fleets with missionState == Executing have arrived at targets.

  result = @[]
  logCombat("[THEATER] Resolving combat", " system=", $systemId)

  let colonyOpt = state.colonyBySystem(systemId)
  let systemOwner =
    if colonyOpt.isSome:
      some(colonyOpt.get().owner)
    else:
      none(HouseId)

  # ===================================================================
  # THEATER 1: SPACE COMBAT
  # ===================================================================
  # Use new multi-house combat system
  let spaceCombatResults =
    multi_house.resolveSystemCombat(state, systemId, rng, events)
  result.add(spaceCombatResults)

  # Determine theater outcome
  let spaceOutcome = determineTheaterOutcome(
    state, spaceCombatResults, systemId, systemOwner
  )

  # Check if attackers achieved orbital supremacy
  var attackersAchievedOrbitalSupremacy = false

  if systemOwner.isNone:
    # No colony = no orbital defense
    attackersAchievedOrbitalSupremacy = true
  elif spaceCombatResults.len == 0:
    # No combat = check for non-owner fleets
    for fleet in state.fleetsInSystem(systemId):
      if fleet.houseId != systemOwner.get():
        attackersAchievedOrbitalSupremacy = true
        break
  else:
    # Combat occurred - check outcome
    attackersAchievedOrbitalSupremacy = spaceOutcome.attackersWon

  # ===================================================================
  # THEATER 2: ORBITAL COMBAT (handled by multi_house.nim)
  # ===================================================================
  # Note: Orbital combat is currently part of space combat resolution
  # Future: Separate orbital combat theater if needed

  # ===================================================================
  # THEATER 3: PLANETARY COMBAT
  # ===================================================================
  # Only proceed if attackers achieved orbital supremacy
  if not attackersAchievedOrbitalSupremacy:
    logCombat(
      "[THEATER] Attackers did not achieve orbital supremacy",
      " system=", $systemId
    )
    # Still run cleanup for space combat effects
    cleanup.cleanupPostCombat(state, systemId)
    return

  if colonyOpt.isNone:
    # No colony to assault - just cleanup and return
    cleanup.cleanupPostCombat(state, systemId)
    return

  let colonyId = colonyOpt.get().id

  # Collect assault intents using iterator pattern
  let (bombardments, invasions) = collectAssaultIntents(state, systemId)

  # PHASE 1: Execute all bombardments sequentially (wear down defenses)
  if bombardments.len > 0:
    logCombat(
      "[THEATER] Processing bombardments",
      " system=", $systemId,
      " total=", $bombardments.len
    )

    for intent in bombardments:
      discard planetary.resolveBombardment(
        state, @[intent.fleetId], colonyId, rng
      )
      logCombat(
        "[THEATER] Bombardment executed",
        " system=", $systemId,
        " house=", $intent.houseId
      )

  # PHASE 2: Simultaneous invasion/blitz resolution (compete for capture)
  if invasions.len > 0:
    # Randomize order for fairness
    var shuffledInvasions = invasions
    for i in countdown(shuffledInvasions.len - 1, 1):
      let j = rand(rng, 0..i)
      swap(shuffledInvasions[i], shuffledInvasions[j])

    logCombat(
      "[THEATER] Processing invasions/blitz (simultaneous)",
      " system=", $systemId,
      " total_attempts=", $shuffledInvasions.len
    )

    # Try each invasion/blitz in random order until one succeeds
    var colonyCaptured = false
    for intent in shuffledInvasions:
      if colonyCaptured:
        # Colony already captured by another house - this assault fails
        let assaultTypeName = if intent.assaultType == FleetCommandType.Invade:
          "Invade" else: "Blitz"

        events.add(commandFailed(
          intent.houseId,
          intent.fleetId,
          assaultTypeName,
          reason = "colony already captured by another house",
          systemId = some(systemId)
        ))

        logCombat(
          "[THEATER] Invasion failed - colony already captured",
          " system=", $systemId,
          " house=", $intent.houseId
        )
        continue

      # Attempt invasion/blitz
      var invasionResult: CombatResult
      case intent.assaultType
      of FleetCommandType.Invade:
        invasionResult = planetary.resolveInvasion(state, @[intent.fleetId], colonyId, rng)
      of FleetCommandType.Blitz:
        invasionResult = planetary.resolveBlitz(state, @[intent.fleetId], colonyId, rng)
      else:
        continue

      # Check invasion validation failure (batteries not cleared)
      # If rounds == 0 and attacker didn't survive, validation failed
      # Per planetary.nim resolveInvasion: returns early if batteries operational
      if not invasionResult.attackerSurvived and invasionResult.rounds == 0:
        let assaultTypeName = if intent.assaultType == FleetCommandType.Invade:
          "Invade" else: "Blitz"

        events.add(commandFailed(
          intent.houseId,
          intent.fleetId,
          assaultTypeName,
          reason = "ground batteries still operational - bombardment required",
          systemId = some(systemId)
        ))

        logCombat(
          "[THEATER] Invasion failed - batteries operational",
          " system=", $systemId,
          " house=", $intent.houseId,
          " assault_type=", assaultTypeName
        )
        continue # Next house gets their chance

      # Check if invasion succeeded (attacker survived and defender didn't)
      if invasionResult.attackerSurvived and not invasionResult.defenderSurvived:
        colonyCaptured = true
        logCombat(
          "[THEATER] Colony captured",
          " system=", $systemId,
          " victor=", $intent.houseId
        )
      # If invasion failed in ground combat, next house gets their chance

  # ===================================================================
  # THEATER 4: BLOCKADE RESOLUTION
  # ===================================================================
  # Multiple houses can blockade, but penalty applies only once per turn
  if colonyOpt.isSome and attackersAchievedOrbitalSupremacy:
    resolveBlockades(state, systemId, colonyOpt.get().id, events)

  # ===================================================================
  # CON2: CLEANUP - Immediate Combat Effects
  # ===================================================================
  # Remove destroyed entities and clear queues
  # Called after all combat resolution and reporting complete
  logCombat("[CON2] Post-combat cleanup", " system=", $systemId)
  cleanup.cleanupPostCombat(state, systemId)

## Design Notes:
##
## **Architecture Compliance:**
## - Uses iterator pattern for fleet access (no arrivedOrders table)
## - Fleets with missionState == Executing have arrived at targets
## - UFCS style throughout (state.fleetsInSystem, etc.)
## - Delegates to specialized modules (multi_house, planetary, cleanup)
##
## **Combat System:**
## - multi_house.nim handles all space combat with proper diplomatic escalation
## - planetary.nim handles bombardment/invasion/blitz
## - cleanup.nim handles CON2 (Immediate Combat Effects)
##
## **Theater Progression:**
## - Space combat resolves all hostile pairs simultaneously
## - Attackers must win space combat to proceed to planetary
## - Planetary combat only for fleets that have arrived (Executing state)
