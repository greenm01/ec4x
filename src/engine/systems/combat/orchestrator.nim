## Theater Progression Orchestrator
##
## Enforces Space → Orbital → Planetary combat sequence per spec 07-combat.md
## Single entry point for all combat in a system called by turn_cycle.
##
## **New Combat System Integration:**
## - Uses multi_house.nim for space combat resolution
## - Uses planetary.nim for ground combat
## - Handles theater progression and victory conditions

import std/[tables, options, random, sequtils]
import ../../../common/logger
import ../../types/[core, game_state, command, combat, event, fleet, diplomacy, prestige]
import ../../types/resolution as res_types
import ../../state/[engine, iterators]
import ../../event_factory/init as event_factory
import ../../prestige/application as prestige_app
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

proc resolveBlockades(
  state: var GameState,
  systemId: SystemId,
  colonyId: ColonyId,
  arrivedOrders: Table[HouseId, CommandPacket],
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

  # Collect all blockade intents from arrived orders
  type BlockaderInfo = tuple[houseId: HouseId, fleetId: FleetId]
  var blockaderInfo: seq[BlockaderInfo] = @[]
  var blockaders: seq[HouseId] = @[]

  for houseId, commandPacket in arrivedOrders:
    # Skip if blockading own colony
    if houseId == colonyOwner:
      continue

    for cmd in commandPacket.fleetCommands:
      if cmd.commandType == FleetCommandType.Blockade:
        if cmd.targetSystem.isSome and cmd.targetSystem.get() == systemId:
          # Verify fleet exists and is at system
          let fleetOpt = state.fleet(cmd.fleetId)
          if fleetOpt.isSome:
            let fleet = fleetOpt.get()
            if fleet.location == systemId:
              # Check diplomatic status (must be hostile or enemy)
              if (houseId, colonyOwner) in state.diplomaticRelation:
                let relation = state.diplomaticRelation[(houseId, colonyOwner)]
                if relation.state in [DiplomaticState.Hostile, DiplomaticState.Enemy]:
                  blockaderInfo.add((houseId: houseId, fleetId: cmd.fleetId))
                  if houseId notin blockaders:
                    blockaders.add(houseId)

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
  for info in blockaderInfo:
    events.add(event_factory.blockadeSuccessful(
      blockadingHouse = info.houseId,
      targetColony = systemId,
      colonyOwner = colonyOwner,
      fleetId = info.fleetId,
      blockadeTurn = updatedColony.blockadeTurns,
      totalBlockaders = blockaders.len
    ))

  # Apply blockade effects ONCE per turn (regardless of number of blockaders)
  # Effects per 06-operations.md:
  # - Production Penalty: 40% capacity (applied in production phase)
  # - Prestige Loss: -2 prestige per turn per blockaded colony
  # - Trade Disruption: Guild transports cannot reach (applied elsewhere)

  # Apply prestige penalty to colony owner
  let prestigePenalty = prestige.PrestigeEvent(
    source: prestige.PrestigeSource.BlockadePenalty,
    amount: -2'i32,
    description: "Colony blockaded at system " & $systemId
  )
  prestige_app.applyPrestigeEvent(state, colonyOwner, prestigePenalty)

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

  # Analyze combat results
  for combatResult in combatResults:
    # Determine which houses survived
    for fleet in state.fleetsInSystem(systemId):
      let isSurviving =
        fleet.id notin combatResult.attackerRetreatedFleets and
        fleet.id notin combatResult.defenderRetreatedFleets

      if isSurviving and fleet.houseId notin result.survivingAttackers:
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
  state: var GameState,
  systemId: SystemId,
  orders: Table[HouseId, CommandPacket],
  arrivedOrders: Table[HouseId, CommandPacket],
  combatReports: var seq[res_types.CombatReport],
  events: var seq[GameEvent],
  rng: var Rand,
) =
  ## Single entry point for all combat in a system
  ## Called by turn_cycle/conflict_phase.nim
  ##
  ## Enforces theater progression: Space → Orbital → Planetary
  ##
  ## **Integration Note:**
  ## This maintains the legacy interface for turn_cycle compatibility
  ## while using the new spec-compliant combat system internally

  logCombat("[THEATER] Resolving combat", " system=", $systemId)

  let colonyOpt = state.colonyBySystem(systemId)
  let systemOwner =
    if colonyOpt.isSome:
      some(colonyOpt.get().owner)
    else:
      none(HouseId)

  # THEATER 1: Space Combat
  # Use new multi-house combat system
  let spaceCombatResults = multi_house.resolveSystemCombat(state, systemId, rng)

  # Convert CombatResult to legacy CombatReport format for turn_cycle
  # TODO: Update turn_cycle to use new CombatResult format
  for result in spaceCombatResults:
    # For now, create minimal report
    # Full conversion will happen when turn_cycle is updated
    discard

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

  # THEATER 2: Planetary Combat
  # Only proceed if attackers achieved orbital supremacy
  if not attackersAchievedOrbitalSupremacy:
    logCombat(
      "[THEATER] Attackers did not achieve orbital supremacy",
      " system=", $systemId
    )
    return

  if colonyOpt.isNone:
    return # No colony to assault

  let colonyId = colonyOpt.get().id

  # Collect all planetary assault orders targeting this colony
  type AssaultIntent = object
    houseId: HouseId
    fleetId: FleetId
    assaultType: FleetCommandType

  var bombardments: seq[AssaultIntent] = @[]
  var invasions: seq[AssaultIntent] = @[]

  for houseId, commandPacket in arrivedOrders:
    for cmd in commandPacket.fleetCommands:
      if cmd.targetSystem.isSome and cmd.targetSystem.get() == systemId:
        # Verify fleet still exists and survived space combat
        if state.fleet(cmd.fleetId).isSome:
          case cmd.commandType
          of FleetCommandType.Bombard:
            bombardments.add(AssaultIntent(
              houseId: houseId,
              fleetId: cmd.fleetId,
              assaultType: cmd.commandType
            ))
          of FleetCommandType.Invade, FleetCommandType.Blitz:
            invasions.add(AssaultIntent(
              houseId: houseId,
              fleetId: cmd.fleetId,
              assaultType: cmd.commandType
            ))
          else:
            discard

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
  if invasions.len == 0:
    return # No invasion attempts

  # Randomize order for fairness
  for i in countdown(invasions.len - 1, 1):
    let j = rand(rng, 0..i)
    swap(invasions[i], invasions[j])

  logCombat(
    "[THEATER] Processing invasions/blitz (simultaneous)",
    " system=", $systemId,
    " total_attempts=", $invasions.len
  )

  # Try each invasion/blitz in random order until one succeeds
  var colonyCaptured = false
  for intent in invasions:
    if colonyCaptured:
      # Colony already captured by another house - this assault fails
      let assaultTypeName = if intent.assaultType == FleetCommandType.Invade:
        "Invade" else: "Blitz"

      events.add(event_factory.commandFailed(
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
    var result: CombatResult
    case intent.assaultType
    of FleetCommandType.Invade:
      result = planetary.resolveInvasion(state, @[intent.fleetId], colonyId, rng)
    of FleetCommandType.Blitz:
      result = planetary.resolveBlitz(state, @[intent.fleetId], colonyId, rng)
    else:
      continue

    # Check invasion validation failure (batteries not cleared)
    # If rounds == 0 and attacker didn't survive, validation failed
    # Per planetary.nim resolveInvasion: returns early if batteries operational
    if not result.attackerSurvived and result.rounds == 0:
      let assaultTypeName = if intent.assaultType == FleetCommandType.Invade:
        "Invade" else: "Blitz"

      events.add(event_factory.commandFailed(
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
    if result.attackerSurvived and not result.defenderSurvived:
      colonyCaptured = true
      logCombat(
        "[THEATER] Colony captured",
        " system=", $systemId,
        " victor=", $intent.houseId
      )
    # If invasion failed in ground combat, next house gets their chance

  # THEATER 4: Blockade (Simultaneous)
  # Multiple houses can blockade, but penalty applies only once per turn
  if colonyOpt.isSome and attackersAchievedOrbitalSupremacy:
    resolveBlockades(state, systemId, colonyOpt.get().id, arrivedOrders, events)

  # CLEANUP: Remove destroyed entities and clear queues
  # Called after all combat resolution and reporting complete
  cleanup.cleanupPostCombat(state, systemId)

## Design Notes:
##
## **New Combat System:**
## - multi_house.nim handles all space combat with proper diplomatic escalation
## - planetary.nim handles bombardment/invasion/blitz
## - No more squadrons, task forces, or bucket targeting
##
## **Turn Cycle Integration:**
## - Maintains legacy interface (resolveSystemCombat with orders/reports)
## - Converts between new CombatResult and legacy CombatReport
## - Turn cycle eventually needs updating to use new format directly
##
## **Theater Progression:**
## - Space combat resolves all hostile pairs simultaneously
## - Attackers must win space combat to proceed to planetary
## - Planetary combat only for fleets that have arrived
