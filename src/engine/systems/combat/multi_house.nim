## Multi-House Combat with Targeting System
##
## Handles combat when multiple houses are present in a system.
## Uses targeting matrix for hit distribution instead of pairwise bucketing.
##
## Per docs/specs/07-combat.md Section 7.9

import std/[tables, random, options, algorithm, sequtils]
import ../../types/[core, game_state, combat, diplomacy, fleet]
import ../../state/[engine, iterators]
import ../../prestige/effects
import ./strength
import ./cer
import ./hits
import ./detection
import ./retreat

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
  ## Reused from old implementation
  ## Per docs/specs/08-diplomacy.md Section 8.1.5

  # Idle fleet is benign
  if fleet.missionState == MissionState.None:
    return ThreatLevel.Benign

  let cmd = fleet.command

  # Check if this system is the mission target
  let isExecutingMissionHere =
    if cmd.targetSystem.isSome:
      cmd.targetSystem.get() == systemId
    else:
      fleet.location == systemId

  if not isExecutingMissionHere:
    return ThreatLevel.Benign

  # Look up threat level from command type
  if CommandThreatLevels.hasKey(cmd.commandType):
    return CommandThreatLevels[cmd.commandType]
  else:
    return ThreatLevel.Benign

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
  ## Reused from old implementation
  ## Per docs/specs/08-diplomacy.md Section 8.1.6

  case currentStatus
  of DiplomaticState.Neutral:
    case threatLevel
    of ThreatLevel.Attack:
      return (true, DiplomaticState.Enemy)
    of ThreatLevel.Contest:
      return (true, DiplomaticState.Hostile)
    of ThreatLevel.Benign:
      return (false, currentStatus)

  of DiplomaticState.Hostile:
    case threatLevel
    of ThreatLevel.Attack:
      return (true, DiplomaticState.Enemy)
    of ThreatLevel.Contest, ThreatLevel.Benign:
      return (false, currentStatus)

  of DiplomaticState.Enemy:
    return (false, currentStatus)

proc shouldCombatOccur*(
  currentStatus: DiplomaticState,
  threatLevel: ThreatLevel
): bool =
  ## Determine if combat should occur this turn
  ## Reused from old implementation
  ## Per docs/specs/08-diplomacy.md Section 8.1.6

  case currentStatus
  of DiplomaticState.Enemy:
    return true

  of DiplomaticState.Hostile:
    return threatLevel in [ThreatLevel.Attack, ThreatLevel.Contest]

  of DiplomaticState.Neutral:
    return threatLevel == ThreatLevel.Attack

proc areHostile*(
  state: var GameState, houseA: HouseId, houseB: HouseId, systemId: SystemId
): bool =
  ## Check if two houses should fight at this system
  ## Handles diplomatic escalation and combat triggering with grace period
  ## Reused from old implementation
  ## Per docs/specs/07-combat.md Section 7.9.1

  # Get current diplomatic state
  let key = (houseA, houseB)
  if not state.diplomaticRelation.hasKey(key):
    return false

  var relation = state.diplomaticRelation[key]
  let currentStatus = relation.state

  # Get system ownership
  let systemOwner = getSystemOwner(state, systemId)

  # Determine highest threat level from either house's fleets
  var maxThreatLevel = ThreatLevel.Benign

  for fleet in state.fleetsInSystem(systemId):
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

proc selectTargets*(
  state: GameState,
  shooter: HouseCombatForce,
  allParticipants: seq[HouseCombatForce],
  systemId: SystemId,
  rng: var Rand
): seq[TargetingPriority] =
  ## Select targets using diplomatic priority, then AS priority
  ## Returns proportional fire distribution across all valid targets
  ##
  ## Priority order:
  ## 1. Enemy status (highest priority)
  ## 2. Hostile status (medium priority)
  ## 3. Neutral status with colony-threatening commands (lowest priority)
  ##
  ## Within each diplomatic tier, targets highest AS first

  type EnemyInfo = object
    house: HouseCombatForce
    dipStatus: DiplomaticState
    effectiveAS: int32

  var enemies: seq[EnemyInfo] = @[]

  # Collect all hostile houses with diplomatic status
  for participant in allParticipants:
    if participant.houseId == shooter.houseId:
      continue

    # Check if we should engage this house
    # Reuses existing areHostile logic which handles all diplomatic escalation
    let key = (shooter.houseId, participant.houseId)
    if not state.diplomaticRelation.hasKey(key):
      continue

    let relation = state.diplomaticRelation[key]
    let dipStatus = relation.state

    # Get system ownership for threat evaluation
    let systemOwner = getSystemOwner(state, systemId)

    # Determine max threat level from this house's fleets
    var maxThreat = ThreatLevel.Benign
    for fleet in state.fleetsInSystem(systemId):
      if fleet.houseId == participant.houseId:
        let threatenedHouse =
          if systemOwner == some(shooter.houseId):
            some(shooter.houseId)
          else:
            none(HouseId)

        if threatenedHouse.isSome:
          let threat = getFleetThreatLevel(state, fleet, systemId)
          if threat > maxThreat:
            maxThreat = threat

    # Check if combat should occur based on diplomatic status + threat
    if not shouldCombatOccur(dipStatus, maxThreat):
      continue

    # Calculate AS with small variance for tie-breaking
    let baseAS = calculateHouseAS(state, participant)
    let variance = rand(rng, -0.05..0.05)
    let effectiveAS = int32(float(baseAS) * (1.0 + variance))

    enemies.add(EnemyInfo(
      house: participant,
      dipStatus: dipStatus,
      effectiveAS: effectiveAS
    ))

  if enemies.len == 0:
    return @[]

  # Sort by diplomatic priority (Enemy > Hostile > Neutral), then by AS descending
  enemies.sort do (a, b: EnemyInfo) -> int:
    # Priority 1: Diplomatic status (Enemy=2, Hostile=1, Neutral=0)
    let dipPriority = cmp(ord(b.dipStatus), ord(a.dipStatus))
    if dipPriority != 0:
      return dipPriority

    # Priority 2: Highest AS first (bigger threat)
    return cmp(b.effectiveAS, a.effectiveAS)

  # Calculate proportional fire distribution
  let totalEnemyAS = enemies.mapIt(it.effectiveAS).foldl(a + b, 0'i32)

  result = @[]
  for enemy in enemies:
    result.add(TargetingPriority(
      targetHouse: enemy.house.houseId,
      fireProportion: float(enemy.effectiveAS) / float(totalEnemyAS)
    ))

proc getFleetsInSystem*(
  state: GameState, systemId: SystemId, houseId: HouseId
): seq[FleetId] =
  ## Get all fleets belonging to a house in this system
  result = @[]
  for fleet in state.fleetsInSystem(systemId):
    if fleet.houseId == houseId:
      result.add(fleet.id)

proc hasStarbaseInSystem*(
  state: GameState, systemId: SystemId, houseId: HouseId
): bool =
  ## Check if house has a starbase (Kastra) in this system
  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isNone():
    return false

  let colony = colonyOpt.get()
  return colony.owner == houseId and colony.kastraIds.len > 0

proc buildMultiHouseBattle*(
  state: var GameState, systemId: SystemId, rng: var Rand
): Option[MultiHouseBattle] =
  ## Build a multi-house battle structure with targeting matrix
  ## Returns none if no combat should occur

  # Step 1: Identify all houses with fleets in system
  let housesPresent = getHousesInSystem(state, systemId)

  if housesPresent.len < 2:
    return none(MultiHouseBattle)

  # Step 2: Build combat forces for each house
  var participants: seq[HouseCombatForce] = @[]
  let homeworldOwner = state.starMap.homeWorlds.getOrDefault(systemId)

  for houseId in housesPresent:
    let fleets = getFleetsInSystem(state, systemId, houseId)
    if fleets.len == 0:
      continue

    # Get house data for morale and tech levels
    let houseOpt = state.house(houseId)
    if houseOpt.isNone:
      continue

    let house = houseOpt.get()

    # Calculate morale modifier from prestige
    let morale = getMoraleCERModifier(house.prestige.int)

    participants.add(HouseCombatForce(
      houseId: houseId,
      fleets: fleets,
      morale: morale.int32,
      eliLevel: house.techTree.levels.eli,
      clkLevel: house.techTree.levels.clk,
      isDefendingHomeworld: homeworldOwner == houseId
    ))

  if participants.len < 2:
    return none(MultiHouseBattle)

  # Step 3: Check if any houses are actually hostile to each other
  var hasHostilePairs = false
  for i, houseA in participants:
    for j in (i + 1) ..< participants.len:
      let houseB = participants[j]
      if areHostile(state, houseA.houseId, houseB.houseId, systemId):
        hasHostilePairs = true
        break
    if hasHostilePairs:
      break

  if not hasHostilePairs:
    return none(MultiHouseBattle)

  # Step 4: Check starbase presence (needed for detection)
  var hasStarbase: Table[HouseId, bool]
  for participant in participants:
    hasStarbase[participant.houseId] = hasStarbaseInSystem(
      state, systemId, participant.houseId
    )

  # Step 5: Build targeting matrix
  var targeting: Table[HouseId, seq[TargetingPriority]]
  for participant in participants:
    targeting[participant.houseId] = selectTargets(
      state, participant, participants, systemId, rng
    )

  # Step 6: Roll detection for each house
  # Each house rolls detection, compared against best enemy roll
  var detection: Table[HouseId, DetectionOutcome]
  var detectionRolls: Table[HouseId, int32]

  # First pass: Roll for each house
  for participant in participants:
    # Check if this house has raiders
    let hasRaidersThisHouse = hasRaiders(state, participant)
    if not hasRaidersThisHouse:
      # No raiders = no detection advantage possible
      detectionRolls[participant.houseId] = 0
      continue

    # Calculate detection modifiers
    let isDefending = hasStarbase[participant.houseId]
    let modifier = calculateDetectionModifiers(
      participant,
      isDefending,
      isDefending
    )

    # Roll 1d10 + modifiers
    let roll = rand(rng, 1..10).int32 + modifier
    detectionRolls[participant.houseId] = roll

  # Second pass: Determine each house's detection result against enemies
  for participant in participants:
    let myRoll = detectionRolls.getOrDefault(participant.houseId, 0)

    # Find best enemy detection roll
    var bestEnemyRoll = 0'i32
    var anyEnemyHasRaiders = false

    for other in participants:
      if other.houseId == participant.houseId:
        continue
      if not areHostile(state, participant.houseId, other.houseId, systemId):
        continue

      let enemyRoll = detectionRolls.getOrDefault(other.houseId, 0)
      if enemyRoll > 0:
        anyEnemyHasRaiders = true
        if enemyRoll > bestEnemyRoll:
          bestEnemyRoll = enemyRoll

    # Determine detection result
    if myRoll == 0 and not anyEnemyHasRaiders:
      # Neither side has raiders
      detection[participant.houseId] = DetectionOutcome(
        result: DetectionResult.Intercept,
        wonDetection: false
      )
    elif myRoll > bestEnemyRoll:
      # This house wins detection
      let margin = myRoll - bestEnemyRoll
      if margin >= 5:
        detection[participant.houseId] = DetectionOutcome(
          result: DetectionResult.Ambush,
          wonDetection: true
        )
      elif margin >= 1:
        detection[participant.houseId] = DetectionOutcome(
          result: DetectionResult.Surprise,
          wonDetection: true
        )
      else:
        detection[participant.houseId] = DetectionOutcome(
          result: DetectionResult.Intercept,
          wonDetection: true
        )
    else:
      # Enemy wins or ties detection
      detection[participant.houseId] = DetectionOutcome(
        result: DetectionResult.Intercept,
        wonDetection: false
      )

  return some(MultiHouseBattle(
    systemId: systemId,
    theater: CombatTheater.Space,
    participants: participants,
    targeting: targeting,
    detection: detection,
    hasStarbase: hasStarbase,
    retreatedFleets: @[]
  ))

proc calculateCasualties(
  state: GameState,
  participant: HouseCombatForce,
  initialStates: Table[ShipId, CombatState],
  retreatedFleets: seq[FleetId]
): HouseCombatResult =
  ## Calculate casualties by ship class for reporting
  ## Groups losses by ship class for meaningful reports

  # Track losses per ship class (using string names to avoid circular dependency)
  var lossesByClass: Table[string, tuple[destroyed: int32, crippled: int32]]

  for fleetId in participant.fleets:
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isNone:
      continue

    let fleet = fleetOpt.get()

    for shipId in fleet.ships:
      let shipOpt = state.ship(shipId)
      if shipOpt.isNone:
        continue

      let ship = shipOpt.get()
      let initialState = initialStates.getOrDefault(shipId, CombatState.Undamaged)

      # Get ship class name as string
      let className = $ship.shipClass

      # Initialize class entry if needed
      if not lossesByClass.hasKey(className):
        lossesByClass[className] = (destroyed: 0'i32, crippled: 0'i32)

      # Track state changes (destroyed or newly crippled)
      if ship.state == CombatState.Destroyed and initialState != CombatState.Destroyed:
        lossesByClass[className].destroyed += 1
      elif ship.state == CombatState.Crippled and initialState == CombatState.Undamaged:
        lossesByClass[className].crippled += 1

  # Convert to seq of ShipLossesByClass
  var losses: seq[ShipLossesByClass] = @[]
  for className, counts in lossesByClass:
    if counts.destroyed > 0 or counts.crippled > 0:
      losses.add(ShipLossesByClass(
        shipClassName: className,
        destroyed: counts.destroyed,
        crippled: counts.crippled
      ))

  # Determine if house survived (has operational ships)
  let survived = calculateHouseAS(state, participant) > 0

  # Get retreated fleets for this house
  var houseRetreatedFleets: seq[FleetId] = @[]
  for fleetId in retreatedFleets:
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isSome and fleetOpt.get().houseId == participant.houseId:
      houseRetreatedFleets.add(fleetId)

  return HouseCombatResult(
    houseId: participant.houseId,
    losses: losses,
    survived: survived,
    retreatedFleets: houseRetreatedFleets
  )

proc resolveMultiHouseBattle*(
  state: var GameState, battle: var MultiHouseBattle, rng: var Rand
): seq[CombatResult] =
  ## Resolve one round of multi-house combat using targeting matrix
  ## Returns one CombatResult per house (simplified for now)

  # Snapshot initial ship states for casualty tracking
  var initialShipStates: Table[ShipId, CombatState]
  for participant in battle.participants:
    for fleetId in participant.fleets:
      let fleetOpt = state.fleet(fleetId)
      if fleetOpt.isNone:
        continue
      let fleet = fleetOpt.get()
      for shipId in fleet.ships:
        let shipOpt = state.ship(shipId)
        if shipOpt.isSome:
          initialShipStates[shipId] = shipOpt.get().state

  var round = 1'i32
  let maxRounds = 20

  while round <= maxRounds:
    # Phase 1: Calculate total AS for each house
    var houseAS: Table[HouseId, int32]
    for participant in battle.participants:
      houseAS[participant.houseId] = calculateHouseAS(state, participant)

    # Phase 2: Roll CER for each house
    var houseCER: Table[HouseId, float]
    var hitsGenerated: Table[HouseId, int32]

    for participant in battle.participants:
      let totalAS = houseAS[participant.houseId]

      # Calculate DRM (simplified - would need full DRM calculation)
      var drm = participant.morale
      
      # Detection bonus (first round only, applies to winner)
      let detectionOutcome = battle.detection[participant.houseId]
      if detectionOutcome.wonDetection and round == 1:
        if detectionOutcome.result == DetectionResult.Ambush:
          drm += 4
        elif detectionOutcome.result == DetectionResult.Surprise:
          drm += 3

      # Roll CER
      let cer = rollCER(rng, drm, battle.theater)
      houseCER[participant.houseId] = cer
      hitsGenerated[participant.houseId] = int32(float(totalAS) * cer)

    # Phase 3: Distribute hits according to targeting matrix
    for shooter in battle.participants:
      let totalHits = hitsGenerated[shooter.houseId]
      if totalHits <= 0:
        continue

      let targets = battle.targeting[shooter.houseId]
      for target in targets:
        let hits = int32(float(totalHits) * target.fireProportion)
        if hits <= 0:
          continue

        # Get all ships from target house
        var targetShips: seq[ShipId] = @[]
        for participant in battle.participants:
          if participant.houseId == target.targetHouse:
            targetShips = getAllShips(state, participant.fleets)
            break

        # Apply hits using existing hit application system
        applyHits(state, targetShips, hits)

    # Phase 4: Check retreat for each fleet (per-fleet ROE evaluation)
    for participantIdx in 0 ..< battle.participants.len:
      let participant = battle.participants[participantIdx]

      # Calculate total enemy AS for this house
      var totalEnemyAS = 0'i32
      for other in battle.participants:
        if other.houseId != participant.houseId:
          if areHostile(state, participant.houseId, other.houseId, battle.systemId):
            totalEnemyAS += houseAS[other.houseId]

      # Check each fleet in this house for retreat
      var fleetsToRemove: seq[FleetId] = @[]
      for fleetId in participant.fleets:
        let fleetOpt = state.fleet(fleetId)
        if fleetOpt.isNone:
          continue

        let fleet = fleetOpt.get()
        let fleetAS = calculateFleetAS(state, fleetId)

        # Skip if fleet has no combat power
        if fleetAS == 0:
          continue

        # Calculate ratio: fleet AS / total enemy AS
        let ratio = float(fleetAS) / float(totalEnemyAS)
        let threshold = getROEThreshold(fleet.roe)

        # Homeworld defense override
        if participant.isDefendingHomeworld:
          continue

        # Check if fleet should retreat
        if ratio < threshold:
          # Fleet retreats
          battle.retreatedFleets.add(fleetId)
          fleetsToRemove.add(fleetId)

          # Apply proportional losses to screened units
          applyRetreatLossesToScreenedUnits(state, fleetId)

      # Remove retreated fleets from participant
      if fleetsToRemove.len > 0:
        var newFleets: seq[FleetId] = @[]
        for fid in participant.fleets:
          if fid notin fleetsToRemove:
            newFleets.add(fid)

        # Update participant in battle
        battle.participants[participantIdx].fleets = newFleets

    # Phase 5: Check if combat ends
    var activeCombatants = 0
    for participant in battle.participants:
      if calculateHouseAS(state, participant) > 0:
        activeCombatants += 1

    if activeCombatants <= 1:
      break

    round += 1

  # Calculate casualties for all participants
  var allParticipants: seq[HouseCombatResult] = @[]
  for participant in battle.participants:
    allParticipants.add(calculateCasualties(
      state, participant, initialShipStates, battle.retreatedFleets
    ))

  # Determine victor (if any)
  var victor: Option[HouseId] = none(HouseId)
  var survivingHouses: seq[HouseId] = @[]
  for p in allParticipants:
    if p.survived:
      survivingHouses.add(p.houseId)

  if survivingHouses.len == 1:
    victor = some(survivingHouses[0])

  # Build single CombatResult for entire engagement
  result = @[CombatResult(
    systemId: battle.systemId,
    theater: battle.theater,
    rounds: round,
    participants: allParticipants,
    victor: victor
  )]

proc resolveSystemCombat*(
  state: var GameState, systemId: SystemId, rng: var Rand
): seq[CombatResult] =
  ## Single entry point for multi-house combat
  ## Replaces old pairwise bucketing approach
  ## Per docs/specs/07-combat.md Section 7.9

  let battleOpt = buildMultiHouseBattle(state, systemId, rng)
  if battleOpt.isNone:
    return @[]

  var battle = battleOpt.get()
  return resolveMultiHouseBattle(state, battle, rng)

## Design Notes:
##
## **Targeting System Benefits:**
## - No fleet splitting - all fleets commit full strength
## - No rounding errors - distribute hits as floats
## - Simpler code - one battle, one resolution loop
## - More realistic - everyone in same engagement
## - Tactical depth - AI makes targeting decisions
##
## **Target Selection Priority:**
## 1. Diplomatic status: Enemy > Hostile > Neutral (with threats)
## 2. Within tier: Highest AS first (biggest threat)
## 3. Small variance (±5%) for tie-breaking
##
## **Spec Compliance:**
## - Section 7.9.1: Diplomatic status checks via areHostile()
## - Section 7.9.2: Proportional allocation reinterpreted as hit distribution
## - Section 7.9.3: Retreat priority naturally emerges (all in one battle)
