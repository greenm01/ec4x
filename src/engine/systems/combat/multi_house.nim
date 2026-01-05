## Multi-House Combat Orchestration
##
## Handles combat resolution when multiple houses are present in a system.
## Implements proportional fleet allocation for multi-front warfare.
##
## Per docs/specs/07-combat.md Section 7.9

import std/[tables, random, options]
import ../../types/[core, game_state, combat, diplomacy, fleet]
import ../../state/[engine, iterators]
import ./resolver
import ./strength
import ./detection

proc getHousesInSystem*(state: GameState, systemId: SystemId): seq[HouseId] =
  ## Get all houses with fleets in this system
  result = @[]

  var seen: Table[HouseId, bool]
  for fleet in state.fleetsInSystem(systemId):
    if not seen.hasKey(fleet.houseId):
      seen[fleet.houseId] = true
      result.add(fleet.houseId)

proc getFleetThreatLevel*(
  state: GameState, fleet: Fleet, systemId: SystemId
): ThreatLevel =
  ## Determine threat level of fleet in this system
  ##
  ## **Mission Execution vs Traveling:**
  ## - Fleet is only threatening if THIS SYSTEM is its mission objective
  ## - Fleets traveling THROUGH a system to reach another destination are Benign
  ## - Commands without explicit targets (Hold, Patrol) threaten their current location
  ##
  ## Per docs/specs/08-diplomacy.md Section 8.1.5

  if fleet.command.isNone:
    return ThreatLevel.Benign

  let cmd = fleet.command.get()

  # Check if this system is the mission target (execution, not just traveling)
  let isExecutingMissionHere =
    if cmd.targetSystem.isSome:
      # Explicit target: only threatening if target matches this system
      cmd.targetSystem.get() == systemId
    else:
      # No explicit target (Hold, Patrol): threaten current location
      fleet.location == systemId

  if not isExecutingMissionHere:
    return ThreatLevel.Benign # Just traveling through, not executing mission here

  # Look up threat level from command type
  if CommandThreatLevels.hasKey(cmd.commandType):
    return CommandThreatLevels[cmd.commandType]
  else:
    return ThreatLevel.Benign # Unknown commands default to benign

proc getSystemOwner*(state: GameState, systemId: SystemId): Option[HouseId] =
  ## Get the house that owns this system (via colony presence)
  for colony in state.allColonies():
    if colony.systemId == systemId:
      return some(colony.owner)
  return none(HouseId)

proc shouldEscalate*(
  currentStatus: DiplomaticState,
  threatLevel: ThreatLevel
): (bool, DiplomaticState) =
  ## Determine if diplomatic status should escalate
  ## Returns (shouldEscalate, newStatus)
  ## Per docs/specs/08-diplomacy.md Section 8.1.6

  case currentStatus
  of DiplomaticState.Neutral:
    case threatLevel
    of ThreatLevel.Attack:
      return (true, DiplomaticState.Enemy)  # Direct colony attack
    of ThreatLevel.Contest:
      return (true, DiplomaticState.Hostile) # System contestation
    of ThreatLevel.Benign:
      return (false, currentStatus)

  of DiplomaticState.Hostile:
    case threatLevel
    of ThreatLevel.Attack:
      return (true, DiplomaticState.Enemy)  # Colony attack escalates to Enemy
    of ThreatLevel.Contest, ThreatLevel.Benign:
      return (false, currentStatus) # No further escalation

  of DiplomaticState.Enemy:
    return (false, currentStatus) # Already at maximum escalation

proc shouldCombatOccur*(
  currentStatus: DiplomaticState,
  threatLevel: ThreatLevel
): bool =
  ## Determine if combat should occur this turn
  ## Per docs/specs/08-diplomacy.md Section 8.1.6

  case currentStatus
  of DiplomaticState.Enemy:
    return true # Always combat

  of DiplomaticState.Hostile:
    # Combat if Attack or Contest threat present
    return threatLevel in [ThreatLevel.Attack, ThreatLevel.Contest]

  of DiplomaticState.Neutral:
    # Only Attack causes immediate combat (escalates to Enemy first)
    # Contest gives grace period (no combat this turn, escalates to Hostile)
    return threatLevel == ThreatLevel.Attack

proc areHostile*(
  state: var GameState, houseA: HouseId, houseB: HouseId, systemId: SystemId
): bool =
  ## Check if two houses should fight at this system
  ## Handles diplomatic escalation and combat triggering with grace period
  ## Per docs/specs/07-combat.md Section 7.9.1
  ## Per docs/specs/08-diplomacy.md Section 8.1.6
  ##
  ## This function checks combat at DESTINATION (mission execution phase).
  ## Travel phase combat is handled by movement system.

  # Get current diplomatic state
  let key = (houseA, houseB)
  if not state.diplomaticRelation.hasKey(key):
    return false # No diplomatic relation = peaceful

  var relation = state.diplomaticRelation[key]
  let currentStatus = relation.state

  # Get system ownership
  let systemOwner = getSystemOwner(state, systemId)

  # Determine highest threat level from either house's fleets
  var maxThreatLevel = ThreatLevel.Benign

  for fleet in state.fleetsInSystem(systemId):
    # Check if this fleet threatens the other house
    let threatenedHouse =
      if fleet.houseId == houseA and systemOwner == some(houseB):
        some(houseB)
      elif fleet.houseId == houseB and systemOwner == some(houseA):
        some(houseA)
      else:
        none(HouseId)

    if threatenedHouse.isSome:
      let fleetThreat = getFleetThreatLevel(state, fleet, systemId)
      if fleetThreat > maxThreatLevel:
        maxThreatLevel = fleetThreat

  # Check if diplomatic status should escalate
  let (shouldEsc, newStatus) = shouldEscalate(currentStatus, maxThreatLevel)
  if shouldEsc:
    relation.state = newStatus
    state.diplomaticRelation[key] = relation

  # Determine if combat occurs this turn
  return shouldCombatOccur(relation.state, maxThreatLevel)

proc identifyHostilePairs*(
  state: var GameState, systemId: SystemId, houses: seq[HouseId]
): seq[Battle] =
  ## Identify which houses are hostile to each other
  ## Handles diplomatic escalation based on fleet missions at this system
  ## Per docs/specs/07-combat.md Section 7.9.1

  result = @[]

  for i, houseA in houses:
    for j, houseB in houses:
      if j <= i:
        continue # Avoid duplicates and self-combat

      if areHostile(state, houseA, houseB, systemId):
        # Create battle between these houses
        # Check if either house is defending their homeworld
        let homeworldOwner = state.starMap.homeWorlds.getOrDefault(systemId)

        result.add(Battle(
          attacker: HouseCombatForce(
            houseId: houseA,
            fleets: @[],
            morale: 0,
            eliLevel: 0,
            clkLevel: 0,
            isDefendingHomeworld: homeworldOwner == houseA
          ),
          defender: HouseCombatForce(
            houseId: houseB,
            fleets: @[],
            morale: 0,
            eliLevel: 0,
            clkLevel: 0,
            isDefendingHomeworld: homeworldOwner == houseB
          ),
          theater: CombatTheater.Space,
          systemId: systemId,
          detectionResult: DetectionResult.Intercept,
          hasDefenderStarbase: false,
          attackerRetreatedFleets: @[],
          defenderRetreatedFleets: @[]
        ))

proc getFleetsInSystem*(
  state: GameState, systemId: SystemId, houseId: HouseId
): seq[FleetId] =
  ## Get all fleets belonging to a house in this system
  result = @[]

  for fleet in state.fleetsInSystem(systemId):
    if fleet.houseId == houseId:
      result.add(fleet.id)

proc calculateTotalEnemyAS*(
  state: GameState, houseId: HouseId, battles: seq[Battle]
): int32 =
  ## Calculate total AS of all enemies this house is fighting
  result = 0

  for battle in battles:
    if battle.attacker.houseId == houseId:
      result += calculateHouseAS(state, battle.defender)
    elif battle.defender.houseId == houseId:
      result += calculateHouseAS(state, battle.attacker)

proc allocateFleetsProportionally*(
  fleets: seq[FleetId], proportion: float
): seq[FleetId] =
  ## Allocate a proportion of fleets to a battle
  ## Uses round-robin to ensure every battle gets fleets

  let count = int(float(fleets.len) * proportion)

  # Ensure at least 1 fleet if proportion > 0
  let allocCount =
    if proportion > 0.0 and count == 0:
      1
    else:
      count

  result = @[]
  for i in 0 ..< min(allocCount, fleets.len):
    result.add(fleets[i])

proc allocateFleetsToBattles*(
  state: GameState, houseId: HouseId, systemId: SystemId, battles: var seq[Battle]
) =
  ## Allocate house's fleets to battles
  ## Proportional allocation if fighting on multiple fronts
  ## Per docs/specs/07-combat.md Section 7.9.2

  let houseFleets = getFleetsInSystem(state, systemId, houseId)

  # Find which battles this house is involved in
  var houseBattles: seq[int] = @[]
  for i, battle in battles:
    if battle.attacker.houseId == houseId or battle.defender.houseId == houseId:
      houseBattles.add(i)

  if houseBattles.len == 0:
    return

  if houseBattles.len == 1:
    # Fighting on one front - assign all fleets
    let battleIdx = houseBattles[0]
    if battles[battleIdx].attacker.houseId == houseId:
      battles[battleIdx].attacker.fleets = houseFleets
    else:
      battles[battleIdx].defender.fleets = houseFleets

  else:
    # Fighting on multiple fronts - proportional allocation
    # First pass: calculate total enemy AS to determine proportions
    var enemyASByBattle: seq[int32] = @[]
    var totalEnemyAS = 0'i32

    for battleIdx in houseBattles:
      let battle = battles[battleIdx]
      let enemyAS =
        if battle.attacker.houseId == houseId:
          calculateHouseAS(state, battle.defender)
        else:
          calculateHouseAS(state, battle.attacker)

      enemyASByBattle.add(enemyAS)
      totalEnemyAS += enemyAS

    # Second pass: allocate fleets proportionally
    if totalEnemyAS > 0:
      for i, battleIdx in houseBattles:
        let proportion = float(enemyASByBattle[i]) / float(totalEnemyAS)
        let allocatedFleets = allocateFleetsProportionally(houseFleets, proportion)

        if battles[battleIdx].attacker.houseId == houseId:
          battles[battleIdx].attacker.fleets = allocatedFleets
        else:
          battles[battleIdx].defender.fleets = allocatedFleets

proc hasStarbaseInSystem*(
  state: GameState, systemId: SystemId, houseId: HouseId
): bool =
  ## Check if house has a starbase (Kastra) in this system
  if not state.colonies.bySystem.hasKey(systemId):
    return false

  let colonyId = state.colonies.bySystem[systemId]
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone():
    return false

  let colony = colonyOpt.get()

  # Check if colony owned by this house and has any kastras
  if colony.owner == houseId and colony.kastraIds.len > 0:
    return true

  return false

proc resolveSystemCombat*(
  state: var GameState, systemId: SystemId, rng: var Rand
): seq[CombatResult] =
  ## Resolve all combat in a system (potentially multi-house)
  ## Per docs/specs/07-combat.md Section 7.9

  # Step 1: Identify all houses with fleets in system
  let housesPresent = getHousesInSystem(state, systemId)

  if housesPresent.len < 2:
    return @[] # No combat possible

  # Step 2: Identify hostile pairs based on diplomatic status
  var battles = identifyHostilePairs(state, systemId, housesPresent)

  if battles.len == 0:
    return @[] # No hostile pairs

  # Step 3: Allocate fleets to battles (proportional if multi-front)
  for house in housesPresent:
    allocateFleetsToBattles(state, house, systemId, battles)

  # Step 3.5: Roll detection for each battle (after fleets allocated)
  for battle in battles.mitems:
    # Check if defender has starbase
    battle.hasDefenderStarbase = hasStarbaseInSystem(
      state, systemId, battle.defender.houseId
    )

    # Roll detection to determine first-strike advantage
    battle.detectionResult = rollDetection(
      state, battle.attacker, battle.defender,
      battle.hasDefenderStarbase, rng
    )

  # Step 4: Resolve each battle independently
  result = @[]
  for battle in battles.mitems:
    result.add(resolveBattle(state, battle, rng))

## Design Notes:
##
## **Spec Compliance:**
## - docs/specs/07-combat.md Section 7.9 - Multi-House Combat
## - docs/specs/07-combat.md Section 7.9.1 - Hostile Pair Identification
## - docs/specs/07-combat.md Section 7.9.2 - Fleet Allocation
##
## **Proportional Allocation:**
## - House fighting on one front: All fleets assigned to that battle
## - House fighting on multiple fronts: Fleets allocated proportionally by enemy AS
## - Ensures no house is overwhelmed on one front while having idle fleets
##
## **Battle Independence:**
## - Each hostile pair resolves as separate battle
## - Battles don't affect each other (no cascading effects)
## - Results aggregated at end of combat phase
##
## **Diplomatic Integration:**
## - Only houses at War engage in combat
## - Other diplomatic states (Peace, Alliance) don't trigger combat
## - System ownership may affect combat in future (not implemented yet)
##
## **Edge Cases:**
## - Three-way war: A vs B, B vs C, A vs C (3 battles)
## - Unequal fleet allocation due to rounding (ensured ≥1 fleet per battle)
## - Zero AS enemies: Proportional allocation handles gracefully
