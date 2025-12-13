## Combat resolution system - Battle, bombardment, invasion, and blitz operations
##
## This module handles all combat-related resolution including:
## - Space battles with linear progression (space combat -> orbital combat)
## - Orbital bombardment of planetary defenses
## - Ground invasions of enemy colonies
## - Blitz operations (fast insertion variant)
## - Retreat processing and automated Seek Home

import std/[tables, options, sequtils, hashes, math, random, strformat]
import ../../common/[types/core, types/combat, types/units, logger as common_logger]
import ../gamestate, ../orders, ../fleet, ../squadron, ../spacelift, ../logger
import ../combat/[engine as combat_engine, types as combat_types, ground]
import ../economy/[types as econ_types, facility_damage]
import ../prestige
import ../config/[prestige_multiplier, prestige_config, facilities_config]
import ../diplomacy/[types as dip_types, engine as dip_engine]
import ../intelligence/diplomatic_intel
import ./types  # Common resolution types
import ./fleet_orders  # For findClosestOwnedColony, resolveMovementOrder
import ./event_factory/init as event_factory
import ../intelligence/[types as intel_types, combat_intel]

proc applySpaceLiftScreeningLosses(
  state: var GameState,
  combatOutcome: combat_engine.CombatResult,
  fleetsBeforeCombat: Table[FleetId, Fleet],
  combatPhase: string,  # "Space" or "Orbital"
  events: var seq[GameEvent]
) =
  ## Apply spacelift ship losses based on task force casualties
  ## Spacelift ships are screened by task forces - losses are proportional to task force casualties
  ## If task force destroyed → all spacelift ships destroyed
  ## If task force retreated → proportional spacelift ships destroyed (matching casualty %)

  # Track spacelift losses by house for event generation
  var spaceliftLossesByHouse: Table[HouseId, int] = initTable[HouseId, int]()

  for fleetId, fleetBefore in fleetsBeforeCombat.pairs:
    if fleetBefore.spaceLiftShips.len == 0:
      continue  # No spacelift ships to lose

    # Skip mothballed fleets (they don't participate in combat, handled separately)
    if fleetBefore.status == FleetStatus.Mothballed:
      continue

    # Calculate task force casualties for this fleet
    var squadronsBefore = fleetBefore.squadrons.len
    var squadronsAfter = 0

    if fleetId in state.fleets:
      squadronsAfter = state.fleets[fleetId].squadrons.len

    # If fleet was completely destroyed, destroy all spacelift ships
    if squadronsAfter == 0:
      let spaceliftCount = fleetBefore.spaceLiftShips.len
      spaceliftLossesByHouse[fleetBefore.owner] = spaceliftLossesByHouse.getOrDefault(fleetBefore.owner, 0) + spaceliftCount

      logCombat(&"{combatPhase} combat: Fleet {fleetId} destroyed, all spacelift ships lost",
                "spaceliftShips=", $spaceliftCount)

      # Fleet already destroyed, no need to update
      continue

    # Check if fleet retreated
    let didRetreat = fleetBefore.owner in combatOutcome.retreated

    # Calculate casualty percentage
    let casualtyPercent = if squadronsBefore > 0:
      float(squadronsBefore - squadronsAfter) / float(squadronsBefore)
    else:
      0.0

    # Apply proportional spacelift losses if casualties occurred or fleet retreated
    if casualtyPercent > 0.0 or didRetreat:
      let spaceliftBefore = fleetBefore.spaceLiftShips.len
      let spaceliftLosses = if didRetreat:
        # On retreat, lose percentage matching task force casualties (minimum 1 if any casualties)
        max(1, int(float(spaceliftBefore) * casualtyPercent))
      else:
        # Normal combat casualties
        int(float(spaceliftBefore) * casualtyPercent)

      if spaceliftLosses > 0:
        var updatedFleet = state.fleets[fleetId]
        let actualLosses = min(spaceliftLosses, updatedFleet.spaceLiftShips.len)

        # Remove spacelift ships from the end of the list
        if actualLosses >= updatedFleet.spaceLiftShips.len:
          updatedFleet.spaceLiftShips = @[]
        else:
          updatedFleet.spaceLiftShips = updatedFleet.spaceLiftShips[0 ..< (updatedFleet.spaceLiftShips.len - actualLosses)]

        state.fleets[fleetId] = updatedFleet
        spaceliftLossesByHouse[fleetBefore.owner] = spaceliftLossesByHouse.getOrDefault(fleetBefore.owner, 0) + actualLosses

        logCombat(&"{combatPhase} combat: Fleet {fleetId} spacelift screening losses",
                  "casualties=", $actualLosses,
                  "casualtyPercent=", $(int(casualtyPercent * 100)), "%",
                  "retreated=", $didRetreat)

  # Generate events for spacelift losses
  for houseId, losses in spaceliftLossesByHouse:
    events.add(event_factory.battle(
      houseId,
      combatOutcome.systemId,
      &"{combatPhase} combat: {losses} spacelift ships destroyed (screened by task force)"
    ))

proc isScoutOnlyFleet(fleet: Fleet): bool =
  ## Check if fleet contains only Scout ships (auxiliary units for intel gathering)
  ## Scout-only fleets are invisible to combat fleets and never participate in combat
  if fleet.squadrons.len == 0:
    return false

  for squadron in fleet.squadrons:
    if squadron.flagship.shipClass != ShipClass.Scout:
      return false

  return true

proc getTargetBucket(shipClass: ShipClass): TargetBucket =
  ## Determine target bucket from ship class
  ## Note: Starbases use TargetBucket.Starbase but aren't in ShipClass (they're facilities)
  case shipClass
  of ShipClass.Raider: TargetBucket.Raider
  of ShipClass.Fighter: TargetBucket.Fighter
  of ShipClass.Destroyer: TargetBucket.Destroyer
  else: TargetBucket.Capital

proc getStarbaseStats(wepLevel: int): ShipStats =
  ## Load starbase combat stats from facilities.toml
  ## Applies WEP tech modifications like ships
  let facilityConfig = globalFacilitiesConfig.starbase

  # Base stats from facilities.toml
  var stats = ShipStats(
    name: "Starbase",
    class: "SB",
    role: ShipRole.SpecialWeapon,
    attackStrength: facilityConfig.attack_strength,
    defenseStrength: facilityConfig.defense_strength,
    commandCost: 0,  # Starbases don't consume command
    commandRating: 0,  # Starbases can't lead squadrons
    techLevel: facilityConfig.cst_min,
    buildCost: facilityConfig.build_cost,
    upkeepCost: facilityConfig.upkeep_cost,
    specialCapability: "",  # No special capabilities
    carryLimit: 0
  )

  # Apply WEP tech modifications (AS and DS scale with weapons tech)
  if wepLevel > 1:
    let weaponsMultiplier = pow(1.10, float(wepLevel - 1))
    stats.attackStrength = int(float(stats.attackStrength) * weaponsMultiplier)
    stats.defenseStrength = int(float(stats.defenseStrength) * weaponsMultiplier)

  return stats

proc autoEscalateDiplomacy(
  state: var GameState,
  combatOutcome: CombatResult,
  combatPhase: string,
  fleetsInCombat: seq[(FleetId, Fleet)]
) =
  ## Auto-escalate diplomatic status based on combat actions
  ## - Space Combat → Hostile (deep space engagement)
  ## - Orbital Combat → Enemy (planetary attack)
  ## Per approved 4-level diplomacy system

  if combatOutcome.totalRounds == 0:
    return  # No combat occurred

  # Determine target diplomatic state based on combat phase
  let targetState = if combatPhase == "Space Combat":
    dip_types.DiplomaticState.Hostile  # Deep space combat escalates to Hostile
  else:
    dip_types.DiplomaticState.Enemy  # Orbital combat escalates to Enemy

  # Collect all houses involved in combat
  var housesInvolved: seq[HouseId] = @[]
  for (fleetId, fleet) in fleetsInCombat:
    if fleet.owner notin housesInvolved:
      housesInvolved.add(fleet.owner)

  # Auto-escalate diplomatic relations between all pairs of combatants
  for i in 0..<housesInvolved.len:
    for j in (i+1)..<housesInvolved.len:
      let house1 = housesInvolved[i]
      let house2 = housesInvolved[j]

      # Get current diplomatic states
      let currentState1 = dip_engine.getDiplomaticState(
        state.houses[house1].diplomaticRelations,
        house2
      )
      let currentState2 = dip_engine.getDiplomaticState(
        state.houses[house2].diplomaticRelations,
        house1
      )

      # Only escalate if current state is less hostile than target
      # Only escalate if current state is less hostile than target
      # Neutral (0) < Hostile (1) < Enemy (2)
      if ord(currentState1) < ord(targetState):
        var house = state.houses[house1]
        house.diplomaticRelations.setDiplomaticState(
          house2,
          targetState,
          state.turn
        )
        state.houses[house1] = house

        logResolve("Auto-escalation",
                   "phase=", combatPhase, " house=", $house1, " target=", $house2,
                   " oldState=", $currentState1, " newState=", $targetState)

        # Generate intelligence about escalation
        if targetState == dip_types.DiplomaticState.Hostile:
          diplomatic_intel.generateHostilityDeclarationIntel(state, house1, house2, state.turn)
        else:
          diplomatic_intel.generateWarDeclarationIntel(state, house1, house2, state.turn)

      if ord(currentState2) < ord(targetState):
        var house = state.houses[house2]
        house.diplomaticRelations.setDiplomaticState(
          house1,
          targetState,
          state.turn
        )
        state.houses[house2] = house

        logResolve("Auto-escalation",
                   "phase=", combatPhase, " house=", $house2, " target=", $house1,
                   " oldState=", $currentState2, " newState=", $targetState)

        # Generate intelligence about escalation
        if targetState == dip_types.DiplomaticState.Hostile:
          diplomatic_intel.generateHostilityDeclarationIntel(state, house2, house1, state.turn)
        else:
          diplomatic_intel.generateWarDeclarationIntel(state, house2, house1, state.turn)

proc executeCombat(
  state: var GameState,
  systemId: SystemId,
  fleetsInCombat: seq[(FleetId, Fleet)],
  systemOwner: Option[HouseId],
  includeStarbases: bool,
  includeUnassignedSquadrons: bool,
  combatPhase: string,
  preDetectedHouses: seq[HouseId] = @[]  # Houses already detected in previous combat phase
): tuple[outcome: CombatResult, fleetsAtSystem: seq[(FleetId, Fleet)], detectedHouses: seq[HouseId]] =
  ## Helper function to execute a combat phase
  ## Returns combat outcome, fleets that participated, and newly detected cloaked houses

  if fleetsInCombat.len < 2:
    return (CombatResult(), @[], @[])

  logCombat(combatPhase, "fleets=", $fleetsInCombat.len)

  # Group fleets by house
  var houseFleets: Table[HouseId, seq[Fleet]] = initTable[HouseId, seq[Fleet]]()
  for (fleetId, fleet) in fleetsInCombat:
    if fleet.owner notin houseFleets:
      houseFleets[fleet.owner] = @[]
    houseFleets[fleet.owner].add(fleet)

  # Check if there's actual conflict (need at least 2 different houses)
  if houseFleets.len < 2:
    return (CombatResult(), @[], @[])

  # Build Task Forces for combat
  var taskForces: Table[HouseId, TaskForce] = initTable[HouseId, TaskForce]()

  for houseId, fleets in houseFleets:
    # Convert all house fleets to CombatSquadrons
    var combatSquadrons: seq[CombatSquadron] = @[]

    for fleet in fleets:
      # Mothballed ships are screened during combat and cannot fight
      if fleet.status == FleetStatus.Mothballed:
        logDebug("Combat", "Fleet mothballed - screened from combat", "fleetId=", $fleet.id)
        continue

      for squadron in fleet.squadrons:
        # Scout squadrons never participate in combat (auxiliary units for intel gathering)
        # They are excluded from task forces even if in mixed fleets
        if squadron.flagship.shipClass == ShipClass.Scout:
          logDebug("Combat", "Scout squadron excluded from task force", "squadronId=", $squadron.id)
          continue

        let combatSq = CombatSquadron(
          squadron: squadron,
          state: if squadron.flagship.isCrippled: CombatState.Crippled else: CombatState.Undamaged,
          fleetStatus: fleet.status,
          damageThisTurn: 0,
          crippleRound: 0,
          bucket: getTargetBucket(squadron.flagship.shipClass),
          targetWeight: 1.0
        )
        combatSquadrons.add(combatSq)

    # Add unassigned squadrons from colony if this is orbital combat
    if includeUnassignedSquadrons and systemOwner.isSome and systemOwner.get() == houseId:
      if systemId in state.colonies:
        let colony = state.colonies[systemId]
        for squadron in colony.unassignedSquadrons:
          let combatSq = CombatSquadron(
            squadron: squadron,
            state: if squadron.flagship.isCrippled: CombatState.Crippled else: CombatState.Undamaged,
            fleetStatus: FleetStatus.Active,  # Unassigned squadrons fight at full strength
            damageThisTurn: 0,
            crippleRound: 0,
            bucket: getTargetBucket(squadron.flagship.shipClass),
            targetWeight: 1.0
          )
          combatSquadrons.add(combatSq)
        if colony.unassignedSquadrons.len > 0:
          logDebug("Combat", "Added unassigned squadrons to orbital defense", "count=", $colony.unassignedSquadrons.len)

    # Add starbases for system owner (always included for detection)
    # Starbases are ALWAYS included in task forces for detection purposes
    # In space combat: Starbases detect but don't fight (controlled by allowStarbaseCombat flag)
    # In orbital combat: Starbases detect AND fight
    var combatFacilities: seq[CombatFacility] = @[]
    if systemOwner.isSome and systemOwner.get() == houseId:
      if systemId in state.colonies:
        let colony = state.colonies[systemId]
        for starbase in colony.starbases:
          # Load starbase combat stats from facilities.toml
          # Apply owner's WEP tech level to starbase AS/DS
          let ownerWepLevel = state.houses[houseId].techTree.levels.weaponsTech
          let starbaseStats = getStarbaseStats(ownerWepLevel)

          let combatFacility = CombatFacility(
            facilityId: starbase.id,
            systemId: systemId,
            owner: houseId,
            attackStrength: starbaseStats.attackStrength,
            defenseStrength: starbaseStats.defenseStrength,
            state: if starbase.isCrippled: CombatState.Crippled else: CombatState.Undamaged,
            damageThisTurn: 0,
            crippleRound: 0,
            bucket: TargetBucket.Starbase,
            targetWeight: 5.0  # Base weight for Starbase bucket
          )
          combatFacilities.add(combatFacility)
        if colony.starbases.len > 0:
          let combatRole = if includeStarbases: "defense and detection" else: "detection only"
          logDebug("Combat", "Added starbases", "count=", $colony.starbases.len, " role=", combatRole)

    # Create TaskForce for this house
    taskForces[houseId] = TaskForce(
      house: houseId,
      squadrons: combatSquadrons,
      facilities: combatFacilities,  # Starbases and other defensive facilities
      roe: 5,  # Default ROE
      isCloaked: false,
      moraleModifier: 0,
      isDefendingHomeworld: false
    )

  # Collect all task forces for battle
  var allTaskForces: seq[TaskForce] = @[]
  for houseId, tf in taskForces:
    allTaskForces.add(tf)

  # Generate deterministic seed
  let deterministicSeed = hash((state.turn, systemId, combatPhase)).int64

  # Build diplomatic relations table for combat logic
  var diplomaticRelations = initTable[tuple[a, b: HouseId], dip_types.DiplomaticState]()
  let houseIds = toSeq(taskForces.keys)
  for i in 0..<houseIds.len:
    for j in (i+1)..<houseIds.len:
      let houseA = houseIds[i]
      let houseB = houseIds[j]
      let stateAtoB = dip_engine.getDiplomaticState(state.houses[houseA].diplomaticRelations, houseB)
      let stateBtoA = dip_engine.getDiplomaticState(state.houses[houseB].diplomaticRelations, houseA)
      diplomaticRelations[(houseA, houseB)] = stateAtoB
      diplomaticRelations[(houseB, houseA)] = stateBtoA

  # Raider Detection Logic per assets.md:2.4.3
  var raiderTFs: seq[int]
  for i, tf in allTaskForces:
    var hasRaiders = false
    for sq in tf.squadrons:
      if sq.squadron.flagship.shipClass == ShipClass.Raider:
        hasRaiders = true
        break
    if hasRaiders:
      raiderTFs.add(i)

  var detectionRng = initRand(deterministicSeed)
  var newlyDetectedHouses: seq[HouseId] = @[]

  for i in raiderTFs:
    var attackerTF = allTaskForces[i]
    if attackerTF.house in preDetectedHouses:
      attackerTF.isCloaked = false
      allTaskForces[i] = attackerTF
      continue

    attackerTF.isCloaked = true
    var isDetected = false
    let attackerHouse = state.houses[attackerTF.house]
    let attackerCLK = attackerHouse.techTree.levels.cloakingTech
    let attackerRoll = detectionRng.rand(1..10) + attackerCLK

    for j, defenderTF in allTaskForces:
      if i == j: continue
      let relation = diplomaticRelations.getOrDefault((attackerTF.house, defenderTF.house), dip_types.DiplomaticState.Neutral)
      if relation == dip_types.DiplomaticState.Neutral: continue

      let defenderHouse = state.houses[defenderTF.house]
      let defenderELI = defenderHouse.techTree.levels.electronicIntelligence
      var starbaseBonus = 0
      if systemOwner.isSome and systemOwner.get() == defenderTF.house:
        if systemId in state.colonies and state.colonies[systemId].starbases.len > 0:
          starbaseBonus = globalFacilitiesConfig.starbase.economic_lift_bonus
      let defenderRoll = detectionRng.rand(1..10) + defenderELI + starbaseBonus

      logInfo(LogCategory.lcCombat, &"Raider Detection Check: {attackerTF.house} (CLK {attackerCLK}, roll {attackerRoll}) vs {defenderTF.house} (ELI {defenderELI}, bonus {starbaseBonus}, roll {defenderRoll})")
      if defenderRoll >= attackerRoll:
        isDetected = true
        logInfo(LogCategory.lcCombat, &"Raider fleet from {attackerTF.house} DETECTED by {defenderTF.house}.")
        break

    if isDetected:
      attackerTF.isCloaked = false
      newlyDetectedHouses.add(attackerTF.house)
    else:
      logInfo(LogCategory.lcCombat, &"Raider fleet from {attackerTF.house} remains UNDETECTED.")
    allTaskForces[i] = attackerTF

  let allowAmbush = (combatPhase == "Space Combat" or combatPhase == "Orbital Combat")
  let allowStarbaseCombat = (combatPhase == "Orbital Combat" or includeStarbases)

  var battleContext = BattleContext(
    systemId: systemId,
    taskForces: allTaskForces,
    seed: deterministicSeed,
    maxRounds: 20,
    allowAmbush: allowAmbush,
    allowStarbaseCombat: allowStarbaseCombat,
    preDetectedHouses: preDetectedHouses,
    diplomaticRelations: diplomaticRelations,
    systemOwner: systemOwner
  )

  # Execute battle
  let outcome = combat_engine.resolveCombat(battleContext)

  return (outcome, fleetsInCombat, newlyDetectedHouses)

proc processCombatEvents(
  state: var GameState,
  systemId: SystemId,
  combatResult: combat_engine.CombatResult,
  theater: string,  # "SpaceCombat" or "OrbitalCombat"
  events: var seq[GameEvent]
) =
  ## Process CombatResult and generate detailed combat narrative events
  ## Emits phase, attack, damage, and retreat events based on combat outcome

  # Extract houses involved
  var attackers: seq[HouseId] = @[]
  var defenders: seq[HouseId] = @[]
  var casualties: seq[HouseId] = @[]

  for tf in combatResult.survivors:
    # Determine if attacker or defender based on system ownership
    let systemOwner = if systemId in state.colonies:
      some(state.colonies[systemId].owner)
    else:
      none(HouseId)

    if systemOwner.isSome() and systemOwner.get() == tf.house:
      if tf.house notin defenders:
        defenders.add(tf.house)
    else:
      if tf.house notin attackers:
        attackers.add(tf.house)

  # Add eliminated and retreated houses
  for house in combatResult.eliminated:
    casualties.add(house)
  for house in combatResult.retreated:
    casualties.add(house)

  # Emit theater began event
  events.add(event_factory.combatTheaterBegan(
    theater = theater,
    systemId = systemId,
    attackers = attackers,
    defenders = defenders,
    roundNumber = 1
  ))

  # Process each round's phases
  for roundIdx, roundPhases in combatResult.rounds:
    let roundNum = roundIdx + 1

    for phaseResult in roundPhases:
      # Map CombatPhase enum to phase string
      let phaseName = case phaseResult.phase:
        of combat_types.CombatPhase.Ambush: "RaiderAmbush"
        of combat_types.CombatPhase.Intercept: "FighterIntercept"
        of combat_types.CombatPhase.MainEngagement: "CapitalEngagement"
        of combat_types.CombatPhase.PreCombat, combat_types.CombatPhase.PostCombat:
          "PrePostCombat"  # Shouldn't occur in round results

      # Emit phase began event
      events.add(event_factory.combatPhaseBegan(
        phase = phaseName,
        systemId = systemId,
        roundNumber = roundNum
      ))

      # Process attacks in this phase
      for attack in phaseResult.attacks:
        # Find attacker and target houses
        var attackerHouse: Option[HouseId] = none(HouseId)
        var targetHouse: Option[HouseId] = none(HouseId)

        # Search squadrons in survivors to find houses
        for tf in combatResult.survivors:
          for sq in tf.squadrons:
            if sq.squadron.id == attack.attackerId:
              attackerHouse = some(tf.house)
            if sq.squadron.id == attack.targetId:
              targetHouse = some(tf.house)

        if attackerHouse.isSome() and targetHouse.isSome():
          # Emit weapon fired event
          let weaponType = "Energy"  # Placeholder - could extract from squadron
          events.add(event_factory.weaponFired(
            attackerSquadron = attack.attackerId,
            attackerHouse = attackerHouse.get(),
            targetSquadron = attack.targetId,
            targetHouse = targetHouse.get(),
            weaponType = weaponType,
            cerRoll = 5,  # Placeholder - would need to extract from cerRoll
            cerModifier = 0,  # Placeholder
            damage = attack.damageDealt,
            systemId = systemId
          ))

          # Emit damage/destruction event if state changed
          if attack.targetStateBefore != attack.targetStateAfter:
            case attack.targetStateAfter
            of combat_types.CombatState.Crippled:
              events.add(event_factory.shipDamaged(
                squadronId = attack.targetId,
                houseId = targetHouse.get(),
                damage = attack.damageDealt,
                newState = "Crippled",
                remainingDs = 0,  # Placeholder
                systemId = systemId
              ))
            of combat_types.CombatState.Destroyed:
              events.add(event_factory.shipDestroyed(
                squadronId = attack.targetId,
                houseId = targetHouse.get(),
                killedByHouse = attackerHouse.get(),
                criticalHit = attack.cerRoll.isCriticalHit,
                overkillDamage = 0,  # Placeholder
                systemId = systemId
              ))
            else:
              discard  # Undamaged state, no event needed

      # Emit phase completed event
      var phaseCasualties: seq[HouseId] = @[]
      for stateChange in phaseResult.stateChanges:
        # Find house for this squadron
        for tf in combatResult.survivors:
          for sq in tf.squadrons:
            if sq.squadron.id == stateChange.squadronId:
              if tf.house notin phaseCasualties:
                phaseCasualties.add(tf.house)

      events.add(event_factory.combatPhaseCompleted(
        phase = phaseName,
        systemId = systemId,
        roundNumber = roundNum,
        phaseRounds = 1,  # Each phase is 1 round within the round
        casualties = phaseCasualties
      ))

  # Emit retreat events
  for house in combatResult.retreated:
    # Find fleet ID for this house (placeholder - would need to track this)
    let fleetId: FleetId = ""  # Placeholder - FleetId is string type
    events.add(event_factory.fleetRetreat(
      fleetId = fleetId,
      houseId = house,
      reason = "ROE",  # Placeholder - would need to track reason
      threshold = 50,  # Placeholder
      casualties = 0,  # Placeholder
      systemId = systemId
    ))

  # Emit theater completed event
  events.add(event_factory.combatTheaterCompleted(
    theater = theater,
    systemId = systemId,
    victor = combatResult.victor,
    roundNumber = combatResult.totalRounds,
    casualties = casualties
  ))

proc resolveBattle*(state: var GameState, systemId: SystemId,
                  orders: Table[HouseId, OrderPacket],
                  combatReports: var seq[CombatReport], events: var seq[GameEvent], rng: var Rand) =
  ## Resolve combat at a system with linear progression (operations.md:7.0)
  ## Phase 1: Space Combat - non-guard mobile fleets fight first
  ## Phase 2: Orbital Combat - if attackers survive, fight guard/reserve fleets + starbases
  ## Uses orders to determine which fleets are on guard duty
  logCombat("Resolving battle", "system=", $systemId)

  # 1. Determine system ownership
  let systemOwner = if systemId in state.colonies: some(state.colonies[systemId].owner) else: none(HouseId)

  # 2. Gather all fleets at this system and classify by role
  var fleetsAtSystem: seq[(FleetId, Fleet)] = @[]
  var orbitalDefenders: seq[(FleetId, Fleet)] = @[]  # Guard/Reserve/Mothballed (orbital defense only)
  var attackingFleets: seq[(FleetId, Fleet)] = @[]   # Non-owner fleets (must fight through)
  var mobileDefenders: seq[(FleetId, Fleet)] = @[]   # Owner's mobile fleets (space combat)

  for fleetId, fleet in state.fleets:
    if fleet.location == systemId:
      fleetsAtSystem.add((fleetId, fleet))

      # Scout-only fleets are invisible to combat fleets and never participate in combat
      # They operate independently for intelligence gathering (per 02-assets.md:2.4.2)
      if isScoutOnlyFleet(fleet):
        logDebug("Combat", "Scout-only fleet excluded from combat", "fleetId=", $fleetId)
        continue

      # Classify fleet based on ownership and orders
      let isDefender = systemOwner.isSome and systemOwner.get() == fleet.owner

      if isDefender:
        # Defender fleet classification
        var isOrbitalOnly = false

        # Check for guard orders
        if fleet.owner in orders:
          for order in orders[fleet.owner].fleetOrders:
            if order.fleetId == fleetId and
               (order.orderType == FleetOrderType.GuardStarbase or
                order.orderType == FleetOrderType.GuardPlanet):
              isOrbitalOnly = true
              break

        # Reserve and mothballed fleets only defend in orbital combat
        if fleet.status == FleetStatus.Reserve or fleet.status == FleetStatus.Mothballed:
          isOrbitalOnly = true

        if isOrbitalOnly:
          orbitalDefenders.add((fleetId, fleet))
        else:
          mobileDefenders.add((fleetId, fleet))
      else:
        # All non-owner fleets are attackers (must fight through space combat first)
        attackingFleets.add((fleetId, fleet))

  if fleetsAtSystem.len < 2:
    # Need at least 2 fleets for combat
    return

  # 3. PHASE 1: Space Combat (attackers vs mobile defenders)
  # All attacking fleets must fight through mobile defending fleets first
  # Mobile defenders = owner's active fleets without guard orders
  logCombat("Phase 1: Space Combat")
  var spaceCombatOutcome: CombatResult
  var spaceCombatFleets: seq[(FleetId, Fleet)] = @[]
  var spaceCombatSurvivors: seq[HouseId] = @[]  # Houses that survived space combat
  var detectedInSpace: seq[HouseId] = @[]  # Houses detected during space combat

  # Check if there are attackers and mobile defenders
  if attackingFleets.len > 0 and mobileDefenders.len > 0:
    # Space combat: attackers must fight mobile defenders
    var spaceCombatParticipants = attackingFleets & mobileDefenders

    # INTELLIGENCE GATHERING: Pre-Combat Reports
    # Each house generates detailed intel on EACH other house's forces
    # This handles multi-house combat correctly (3-way, 4-way, etc.)
    var housesInCombat: seq[HouseId] = @[]
    for (fleetId, fleet) in spaceCombatParticipants:
      if fleet.owner notin housesInCombat:
        housesInCombat.add(fleet.owner)

    # Generate separate reports for each house observing each other house
    for reportingHouse in housesInCombat:
      var alliedFleetIds: seq[FleetId] = @[]

      # Collect own forces
      for (fleetId, fleet) in spaceCombatParticipants:
        if fleet.owner == reportingHouse:
          alliedFleetIds.add(fleetId)

      # Generate separate intel report for EACH other house
      for otherHouse in housesInCombat:
        if otherHouse == reportingHouse:
          continue  # Don't report on yourself

        var otherHouseFleetIds: seq[FleetId] = @[]
        for (fleetId, fleet) in spaceCombatParticipants:
          if fleet.owner == otherHouse:
            otherHouseFleetIds.add(fleetId)

        if otherHouseFleetIds.len > 0:
          let preCombatReport = combat_intel.generatePreCombatReport(
            state, systemId, intel_types.CombatPhase.Space,
            reportingHouse, alliedFleetIds, otherHouseFleetIds
          )
          # CRITICAL: Get, modify, write back to persist
          var house = state.houses[reportingHouse]
          house.intelligence.addCombatReport(preCombatReport)
          state.houses[reportingHouse] = house

    let (outcome, fleets, detected) = executeCombat(
      state, systemId, spaceCombatParticipants, systemOwner,
      includeStarbases = false,
      includeUnassignedSquadrons = false,
      "Space Combat"
    )
    spaceCombatOutcome = outcome
    spaceCombatFleets = fleets
    detectedInSpace = detected
    # The `detected` result here will be used to pass detected status to subsequent combat phases.

    # Track which attacker houses survived
    for tf in outcome.survivors:
      if tf.house != systemOwner.get() and tf.house notin spaceCombatSurvivors:
        spaceCombatSurvivors.add(tf.house)

    logCombat("Space combat complete", "rounds=", $spaceCombatOutcome.totalRounds)
    logCombat("Combat result", "survivors=", $spaceCombatSurvivors.len)
    if detectedInSpace.len > 0:
      logCombat("Cloaked detection", "detected=", $detectedInSpace.len)

    # Auto-escalate diplomatic relations after space combat
    autoEscalateDiplomacy(state, spaceCombatOutcome, "Space Combat", spaceCombatFleets)

    # Generate combat narrative events for space combat (Phase 7a)
    processCombatEvents(state, systemId, spaceCombatOutcome, "SpaceCombat", events)

  elif attackingFleets.len > 0:
    # No mobile defenders - attackers proceed directly to orbital combat
    logCombat("No space combat - no mobile defenders")
    # All attackers advance to orbital combat
    for (fleetId, fleet) in attackingFleets:
      if fleet.owner notin spaceCombatSurvivors:
        spaceCombatSurvivors.add(fleet.owner)
  else:
    logCombat("No space combat - no attackers")

  # 4. PHASE 2: Orbital Combat (surviving attackers vs orbital defenders)
  # Only attackers who survived space combat can engage orbital defenders
  # Orbital defenders = guard fleets + reserve + starbases + unassigned squadrons
  var orbitalCombatOutcome: CombatResult
  var orbitalCombatFleets: seq[(FleetId, Fleet)] = @[]

  # Only run if there's a colony with defenders and surviving attackers
  if systemOwner.isSome and spaceCombatSurvivors.len > 0:
    # Check if there are orbital defenders
    var hasOrbitalDefenders = orbitalDefenders.len > 0
    if systemId in state.colonies:
      let colony = state.colonies[systemId]
      if colony.starbases.len > 0 or colony.unassignedSquadrons.len > 0:
        hasOrbitalDefenders = true

    if hasOrbitalDefenders:
      logCombat("Phase 2: Orbital Combat")

      # Gather surviving attacker fleets
      var survivingAttackerFleets: seq[(FleetId, Fleet)] = @[]
      for (fleetId, fleet) in fleetsAtSystem:
        if fleet.owner in spaceCombatSurvivors and fleet.owner != systemOwner.get():
          survivingAttackerFleets.add((fleetId, fleet))

      if survivingAttackerFleets.len > 0:
        # Combine orbital defenders and surviving attackers
        var orbitalFleets = orbitalDefenders & survivingAttackerFleets

        # INTELLIGENCE GATHERING: Pre-Combat Reports (Orbital Phase)
        # Each house generates detailed intel on EACH other house's orbital forces
        var orbitalHouses: seq[HouseId] = @[]
        for (fleetId, fleet) in orbitalFleets:
          if fleet.owner notin orbitalHouses:
            orbitalHouses.add(fleet.owner)

        # Generate separate reports for each house observing each other house
        for reportingHouse in orbitalHouses:
          var alliedFleetIds: seq[FleetId] = @[]

          # Collect own forces
          for (fleetId, fleet) in orbitalFleets:
            if fleet.owner == reportingHouse:
              alliedFleetIds.add(fleetId)

          # Generate separate intel report for EACH other house
          for otherHouse in orbitalHouses:
            if otherHouse == reportingHouse:
              continue  # Don't report on yourself

            var otherHouseFleetIds: seq[FleetId] = @[]
            for (fleetId, fleet) in orbitalFleets:
              if fleet.owner == otherHouse:
                otherHouseFleetIds.add(fleetId)

            if otherHouseFleetIds.len > 0:
              let orbitalPreCombatReport = combat_intel.generatePreCombatReport(
                state, systemId, intel_types.CombatPhase.Orbital,
                reportingHouse, alliedFleetIds, otherHouseFleetIds
              )
              # CRITICAL: Get, modify, write back to persist
              var house = state.houses[reportingHouse]
              house.intelligence.addCombatReport(orbitalPreCombatReport)
              state.houses[reportingHouse] = house

        let (outcome, fleets, detected) = executeCombat(
          state, systemId, orbitalFleets, systemOwner,
          includeStarbases = true,
          includeUnassignedSquadrons = true,
          "Orbital Combat",
          preDetectedHouses = detectedInSpace  # Pass detection status from space combat
        )
        orbitalCombatOutcome = outcome
        orbitalCombatFleets = fleets
        logCombat("Orbital combat complete", "rounds=", $orbitalCombatOutcome.totalRounds)
        # Note: 'detected' from orbital combat itself might contain new detections.
        # However, for the purpose of passing detection status, 'detectedInSpace' is sufficient
        # to ensure any house detected in space remains detected in orbital.

        # Auto-escalate diplomatic relations after orbital combat
        autoEscalateDiplomacy(state, orbitalCombatOutcome, "Orbital Combat", orbitalCombatFleets)

        # Generate combat narrative events for orbital combat (Phase 7a)
        processCombatEvents(state, systemId, orbitalCombatOutcome, "OrbitalCombat", events)

      else:
        logCombat("No surviving attacker fleets for orbital combat")
    else:
      logCombat("Phase 2: No orbital combat - no orbital defenders")
      # Attackers achieved orbital supremacy without a fight
  elif systemOwner.isSome and spaceCombatSurvivors.len == 0:
    logCombat("Phase 2: No orbital combat - attackers eliminated in space")
  else:
    logCombat("Phase 2: No orbital combat - no colony")

  # 5. Apply losses to game state
  # Combine outcomes from both combat phases
  var combinedOutcome: CombatResult
  if spaceCombatOutcome.totalRounds > 0:
    combinedOutcome = spaceCombatOutcome
  if orbitalCombatOutcome.totalRounds > 0:
    # Merge outcomes
    combinedOutcome.totalRounds += orbitalCombatOutcome.totalRounds
    for survivor in orbitalCombatOutcome.survivors:
      combinedOutcome.survivors.add(survivor)
    for retreated in orbitalCombatOutcome.retreated:
      if retreated notin combinedOutcome.retreated:
        combinedOutcome.retreated.add(retreated)
    for eliminated in orbitalCombatOutcome.eliminated:
      if eliminated notin combinedOutcome.eliminated:
        combinedOutcome.eliminated.add(eliminated)
    if orbitalCombatOutcome.victor.isSome:
      combinedOutcome.victor = orbitalCombatOutcome.victor

  let outcome = combinedOutcome
  # Collect surviving squadrons by ID
  var survivingSquadronIds: Table[SquadronId, CombatSquadron] = initTable[SquadronId, CombatSquadron]()
  for tf in outcome.survivors:
    for combatSq in tf.squadrons:
      survivingSquadronIds[combatSq.squadron.id] = combatSq

  # Collect surviving facilities by ID
  var survivingFacilityIds: Table[string, CombatFacility] = initTable[string, CombatFacility]()
  for tf in outcome.survivors:
    for combatFac in tf.facilities:
      survivingFacilityIds[combatFac.facilityId] = combatFac

  # INTELLIGENCE: Capture fleet state before applying losses
  var fleetsBeforeCombatUpdate: Table[FleetId, Fleet] = initTable[FleetId, Fleet]()
  for (fleetId, fleet) in fleetsAtSystem:
    fleetsBeforeCombatUpdate[fleetId] = fleet

  # Update or remove fleets based on survivors
  for (fleetId, fleet) in fleetsAtSystem:
    # Mothballed fleets didn't participate in combat - handle separately
    if fleet.status == FleetStatus.Mothballed:
      continue

    var updatedSquadrons: seq[Squadron] = @[]

    for squadron in fleet.squadrons:
      if squadron.id in survivingSquadronIds:
        # Squadron survived - update crippled status
        let survivorState = survivingSquadronIds[squadron.id]
        var updatedSquadron = squadron
        updatedSquadron.flagship.isCrippled = (survivorState.state == CombatState.Crippled)
        updatedSquadrons.add(updatedSquadron)
      else:
        # Squadron destroyed - mark it before removal
        var destroyedSquadron = squadron
        destroyedSquadron.destroyed = true
        logCombat("Squadron destroyed", "id=", destroyedSquadron.id, " class=", $destroyedSquadron.flagship.shipClass)

    # Update fleet with surviving squadrons, or remove if none survived
    if updatedSquadrons.len > 0:
      state.fleets[fleetId] = Fleet(
        squadrons: updatedSquadrons,
        spaceLiftShips: fleet.spaceLiftShips,
        id: fleet.id,
        owner: fleet.owner,
        location: fleet.location,
        status: fleet.status,  # Preserve status (Active/Reserve)
        autoBalanceSquadrons: fleet.autoBalanceSquadrons  # Preserve balancing setting
      )
    else:
      # Fleet destroyed - remove fleet and clean up orders
      state.fleets.del(fleetId)
      if fleetId in state.fleetOrders:
        state.fleetOrders.del(fleetId)
      if fleetId in state.standingOrders:
        state.standingOrders.del(fleetId)
      logInfo(LogCategory.lcCombat, "Removed empty fleet " & $fleetId & " after combat (all squadrons destroyed)")

  # Apply spacelift ship screening losses (proportional to task force casualties)
  # Spacelift ships are screened by task forces in both space and orbital combat
  if outcome.totalRounds > 0:
    let combatPhaseDesc = if spaceCombatOutcome.totalRounds > 0 and orbitalCombatOutcome.totalRounds > 0:
      "Space+Orbital"
    elif spaceCombatOutcome.totalRounds > 0:
      "Space"
    else:
      "Orbital"

    applySpaceLiftScreeningLosses(state, outcome, fleetsBeforeCombatUpdate, combatPhaseDesc, events)

  # Check if all defenders eliminated - if so, destroy mothballed ships
  # Per economy.md:3.9 - mothballed ships are vulnerable if no Task Force defends them
  if systemOwner.isSome:
    let defendingHouse = systemOwner.get()

    # Check if defending house has any surviving active/reserve squadrons
    var defenderHasSurvivors = false
    for tf in outcome.survivors:
      if tf.house == defendingHouse and tf.squadrons.len > 0:
        defenderHasSurvivors = true
        break

    # If no defenders survived at friendly colony, destroy screened units
    # Per operations.md - mothballed ships and spacelift ships vulnerable if no orbital units defend them
    if not defenderHasSurvivors:
      var mothballedFleetsDestroyed = 0
      var mothballedSquadronsDestroyed = 0

      for (fleetId, fleet) in fleetsAtSystem:
        if fleet.owner == defendingHouse:
          # Skip fleets that were already destroyed in combat
          if fleetId notin state.fleets:
            continue

          # Destroy mothballed ships
          if fleet.status == FleetStatus.Mothballed:
            mothballedSquadronsDestroyed += fleet.squadrons.len
            mothballedFleetsDestroyed += 1
            # Destroy the fleet by removing all squadrons and spacelift ships
            state.fleets[fleetId] = Fleet(
              squadrons: @[],  # Empty fleet
              spaceLiftShips: @[],  # Empty spacelift
              id: fleet.id,
              owner: fleet.owner,
              location: fleet.location,
              status: FleetStatus.Mothballed,
              autoBalanceSquadrons: fleet.autoBalanceSquadrons  # Preserve setting
            )

      if mothballedFleetsDestroyed > 0:
        logCombat("Mothballed fleets destroyed - no orbital defense remains",
                  "squadrons=", $mothballedSquadronsDestroyed,
                  " fleets=", $mothballedFleetsDestroyed)
        events.add(event_factory.battle(
          defendingHouse,
          systemId,
          &"Orbital defenses eliminated: {mothballedFleetsDestroyed} mothballed fleets destroyed " &
          &"({mothballedSquadronsDestroyed} squadrons)"
        ))

      # Destroy screened orbital facilities (spaceports, shipyards, drydocks)
      # These facilities are protected by orbital defenses - if defenses are eliminated, they're destroyed
      if systemId in state.colonies:
        var colony = state.colonies[systemId]
        var facilitiesDestroyed = 0
        var shipsUnderConstructionLost = 0
        var shipsUnderRepairLost = 0

        # Destroy spaceports
        if colony.spaceports.len > 0:
          facilitiesDestroyed += colony.spaceports.len
          logCombat("Spaceports destroyed - no orbital defense remains",
                    "spaceports=", $colony.spaceports.len,
                    " systemId=", $systemId)
          colony.spaceports = @[]

        # Destroy shipyards and clear their construction/repair queues
        if colony.shipyards.len > 0:
          facilitiesDestroyed += colony.shipyards.len
          logCombat("Shipyards destroyed - no orbital defense remains",
                    "shipyards=", $colony.shipyards.len,
                    " systemId=", $systemId)

          # Count ships under construction in shipyard docks
          if colony.underConstruction.isSome:
            let project = colony.underConstruction.get()
            if project.facilityType.isSome and project.facilityType.get() == econ_types.FacilityType.Shipyard:
              shipsUnderConstructionLost += 1

          # Count ships under repair in shipyard docks
          for repair in colony.repairQueue:
            if repair.facilityType == econ_types.FacilityType.Shipyard:
              shipsUnderRepairLost += 1

          # Clear all shipyard construction/repair queues
          facility_damage.clearFacilityQueues(colony, econ_types.FacilityType.Shipyard)
          colony.shipyards = @[]

        # Destroy drydocks and clear their repair queues
        if colony.drydocks.len > 0:
          facilitiesDestroyed += colony.drydocks.len
          logCombat("Drydocks destroyed - no orbital defense remains",
                    "drydocks=", $colony.drydocks.len,
                    " systemId=", $systemId)

          # Count ships under repair in drydock docks
          for repair in colony.repairQueue:
            if repair.facilityType == econ_types.FacilityType.Drydock:
              shipsUnderRepairLost += 1

          # Clear all drydock repair queues
          facility_damage.clearFacilityQueues(colony, econ_types.FacilityType.Drydock)
          colony.drydocks = @[]

        # Clear construction queue if no facilities remain
        if colony.spaceports.len == 0 and colony.shipyards.len == 0:
          facility_damage.clearAllConstructionQueues(colony)

        # Update colony with destroyed facilities
        state.colonies[systemId] = colony

        # Generate events for screened facility destruction
        if facilitiesDestroyed > 0:
          events.add(event_factory.battle(
            defendingHouse,
            systemId,
            &"Orbital defenses eliminated: {facilitiesDestroyed} facilities destroyed, " &
            &"{shipsUnderConstructionLost} ships under construction lost, " &
            &"{shipsUnderRepairLost} ships under repair lost"
          ))

  # Update starbases at colony based on survivors
  if systemOwner.isSome and systemId in state.colonies:
    var colony = state.colonies[systemId]
    var survivingStarbases: seq[Starbase] = @[]
    for starbase in colony.starbases:
      if starbase.id in survivingFacilityIds:
        # Starbase survived - update crippled status
        let survivorState = survivingFacilityIds[starbase.id]
        var updatedStarbase = starbase
        updatedStarbase.isCrippled = (survivorState.state == CombatState.Crippled)
        survivingStarbases.add(updatedStarbase)
      else:
        # Starbase destroyed - log before removal
        logCombat("Starbase destroyed", "id=", starbase.id, " systemId=", $systemId)
    colony.starbases = survivingStarbases
    state.colonies[systemId] = colony

  # Update unassigned squadrons at colony based on survivors
  if systemOwner.isSome and systemId in state.colonies:
    var colony = state.colonies[systemId]
    var survivingUnassigned: seq[Squadron] = @[]
    for squadron in colony.unassignedSquadrons:
      if squadron.id in survivingSquadronIds:
        # Squadron survived - update crippled status
        let survivorState = survivingSquadronIds[squadron.id]
        var updatedSquadron = squadron
        updatedSquadron.flagship.isCrippled = (survivorState.state == CombatState.Crippled)
        survivingUnassigned.add(updatedSquadron)
      else:
        # Unassigned squadron destroyed - mark it before removal
        var destroyedSquadron = squadron
        destroyedSquadron.destroyed = true
        logCombat("Unassigned squadron destroyed", "id=", destroyedSquadron.id, " class=", $destroyedSquadron.flagship.shipClass)
    colony.unassignedSquadrons = survivingUnassigned
    state.colonies[systemId] = colony

  # INTELLIGENCE: Update combat reports with post-combat outcomes
  # Update for Space Combat phase if it occurred
  if spaceCombatOutcome.totalRounds > 0:
    combat_intel.updatePostCombatIntelligence(
      state, systemId, intel_types.CombatPhase.Space,
      spaceCombatFleets,
      state.fleets,
      spaceCombatOutcome.retreated.mapIt(it),
      spaceCombatOutcome.victor
    )

  # Update for Orbital Combat phase if it occurred
  if orbitalCombatOutcome.totalRounds > 0:
    combat_intel.updatePostCombatIntelligence(
      state, systemId, intel_types.CombatPhase.Orbital,
      orbitalCombatFleets,
      state.fleets,
      orbitalCombatOutcome.retreated.mapIt(it),
      orbitalCombatOutcome.victor
    )

  # 5.5. Process retreated fleets - auto-assign Seek Home orders
  # Fleets that retreated from combat automatically receive Order 02 (Seek Home)
  # to find the nearest friendly colony and regroup
  if outcome.retreated.len > 0:
    logCombat("Processing retreated fleets - auto-assigning Seek Home orders",
              "count=", $outcome.retreated.len)

    for houseId in outcome.retreated:
      # Find all fleets belonging to this house at the battle location
      for fleetId, fleet in state.fleets:
        if fleet.owner == houseId and fleet.location == systemId:
          # Find closest owned colony for retreat destination
          let safeDestination = findClosestOwnedColony(state, fleet.location, fleet.owner)

          if safeDestination.isSome:
            logDebug("Combat", "Fleet retreated - auto-assigning Seek Home",
                     "fleetId=", $fleetId, " houseId=", $houseId,
                     " destination=", $safeDestination.get())

            # Create Seek Home order for this fleet
            # NOTE: This creates an "in-flight" movement that will be processed immediately
            # The fleet will begin its retreat movement in the same turn
            let seekHomeOrder = FleetOrder(
              fleetId: fleetId,
              orderType: FleetOrderType.SeekHome,
              targetSystem: safeDestination,
              targetFleet: none(FleetId),
              priority: 0
            )

            # Execute the seek home movement immediately (fleet retreats in same turn)
            resolveMovementOrder(state, houseId, seekHomeOrder, events)

            events.add(event_factory.battle(
              houseId,
              systemId,
              "Fleet " & fleetId & " retreated from combat - seeking nearest friendly system " & $safeDestination.get()
            ))
          else:
            logWarn("Combat", "Fleet retreated but has no safe destination - holding position",
                    "fleetId=", $fleetId, " houseId=", $houseId)
            # No safe colonies - fleet holds at retreat location (will be resolved by movement system)
            events.add(event_factory.battle(
              houseId,
              systemId,
              "Fleet " & fleetId & " retreated from combat but has no friendly colonies - holding position"
            ))

  # 6. Determine attacker and defender houses for reporting
  var attackerHouses: seq[HouseId] = @[]
  var defenderHouses: seq[HouseId] = @[]
  var allHouses: seq[HouseId] = @[]

  for (fleetId, fleet) in fleetsAtSystem:
    if fleet.owner notin allHouses:
      allHouses.add(fleet.owner)
      if systemOwner.isSome and systemOwner.get() == fleet.owner:
        defenderHouses.add(fleet.owner)
      else:
        attackerHouses.add(fleet.owner)

  # 7. Count losses by house
  var houseLosses: Table[HouseId, int] = initTable[HouseId, int]()
  # Count total squadrons before combat (all fleets at system)
  for houseId in allHouses:
    var totalSquadrons = 0
    for (fleetId, fleet) in fleetsAtSystem:
      if fleet.owner == houseId:
        totalSquadrons += fleet.squadrons.len

    # Add starbases and unassigned squadrons to defender's total
    if systemOwner.isSome and systemOwner.get() == houseId and systemId in state.colonies:
      let colony = state.colonies[systemId]
      totalSquadrons += colony.starbases.len
      totalSquadrons += colony.unassignedSquadrons.len

    let survivingSquadrons = outcome.survivors.filterIt(it.house == houseId)
                                   .mapIt(it.squadrons.len).foldl(a + b, 0)
    houseLosses[houseId] = totalSquadrons - survivingSquadrons

  # 8. Generate combat report
  let victor = outcome.victor
  let attackerLosses = if attackerHouses.len > 0:
                         attackerHouses.mapIt(houseLosses.getOrDefault(it, 0)).foldl(a + b, 0)
                       else: 0
  let defenderLosses = if defenderHouses.len > 0:
                         defenderHouses.mapIt(houseLosses.getOrDefault(it, 0)).foldl(a + b, 0)
                       else: 0

  let report = CombatReport(
    systemId: systemId,
    attackers: attackerHouses,
    defenders: defenderHouses,
    attackerLosses: attackerLosses,
    defenderLosses: defenderLosses,
    victor: victor
  )
  combatReports.add(report)

  # Award prestige for combat (ZERO-SUM: victor gains, losers lose)
  if victor.isSome:
    let victorHouse = victor.get()

    # Combat victory prestige (zero-sum)
    let victorPrestige = applyMultiplier(getPrestigeValue(PrestigeSource.CombatVictory))
    let victoryEvent = createPrestigeEvent(
      PrestigeSource.CombatVictory,
      victorPrestige,
      "Won battle at " & $systemId
    )
    applyPrestigeEvent(state, victorHouse, victoryEvent)
    logCombat("Combat victory prestige awarded",
              "house=", state.houses[victorHouse].name,
              " prestige=", $victorPrestige)

    # Apply penalty to losing houses (zero-sum)
    let loserHouses = if victorHouse in attackerHouses: defenderHouses else: attackerHouses
    for loserHouse in loserHouses:
      let defeatEvent = createPrestigeEvent(
        PrestigeSource.CombatVictory,
        -victorPrestige,
        "Lost battle at " & $systemId
      )
      applyPrestigeEvent(state, loserHouse, defeatEvent)
      logCombat("Combat defeat prestige penalty",
                "house=", state.houses[loserHouse].name,
                " prestige=", $(-victorPrestige))

    # Squadron destruction prestige (zero-sum)
    let enemyLosses = if victorHouse in attackerHouses: defenderLosses else: attackerLosses
    if enemyLosses > 0:
      let squadronPrestige = applyMultiplier(getPrestigeValue(PrestigeSource.SquadronDestroyed)) * enemyLosses
      let squadronDestructionEvent = createPrestigeEvent(
        PrestigeSource.SquadronDestroyed,
        squadronPrestige,
        "Destroyed " & $enemyLosses & " enemy squadrons at " & $systemId
      )
      applyPrestigeEvent(state, victorHouse, squadronDestructionEvent)
      logCombat("Squadron destruction prestige awarded",
                "house=", state.houses[victorHouse].name,
                " squadrons=", $enemyLosses,
                " prestige=", $squadronPrestige)

      # Apply penalty to houses that lost squadrons (zero-sum)
      for loserHouse in loserHouses:
        let squadronLossEvent = createPrestigeEvent(
          PrestigeSource.SquadronDestroyed,
          -squadronPrestige,
          "Lost " & $enemyLosses & " squadrons at " & $systemId
        )
        applyPrestigeEvent(state, loserHouse, squadronLossEvent)
        logCombat("Squadron loss prestige penalty",
                  "house=", state.houses[loserHouse].name,
                  " squadrons=", $enemyLosses,
                  " prestige=", $(-squadronPrestige))

  # Generate event
  let victorName = if victor.isSome: state.houses[victor.get()].name else: "No one"
  events.add(event_factory.battle(
    if victor.isSome: victor.get() else: HouseId(""),
    systemId,
    "Battle at " & $systemId & ". Victor: " & victorName
  ))

  logCombat("Battle complete", "victor=", victorName)

proc resolveBombardment*(state: var GameState, houseId: HouseId, order: FleetOrder,
                       events: var seq[GameEvent]) =
  ## Process planetary bombardment order (operations.md:7.5)
  ## Phase 2 of planetary combat - requires orbital supremacy
  ## Attacks planetary shields, ground batteries, and infrastructure

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Bombard",
      reason = "no target system specified",
      systemId = none(SystemId)
    ))
    return

  let targetId = order.targetSystem.get()

  # Validate fleet exists and is at target
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    logWarn("Combat", "Bombardment failed - fleet not found",
            "fleetId=", $order.fleetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Bombard",
      reason = "fleet destroyed",
      systemId = some(targetId)
    ))
    return

  let fleet = fleetOpt.get()
  if fleet.location != targetId:
    logWarn("Combat", "Bombardment failed - fleet not at target system",
            "fleetId=", $order.fleetId, " location=", $fleet.location,
            " target=", $targetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Bombard",
      reason = "fleet not at target system",
      systemId = some(targetId)
    ))
    return

  # Validate target colony exists
  if targetId notin state.colonies:
    logWarn("Combat", "Bombardment failed - no colony at target",
            "systemId=", $targetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Bombard",
      reason = "target colony no longer exists",
      systemId = some(targetId)
    ))
    return

  # Fleet now uses Squadrons - convert to CombatSquadrons
  var combatSquadrons: seq[CombatSquadron] = @[]
  for squadron in fleet.squadrons:
    let combatSq = CombatSquadron(
      squadron: squadron,
      state: if squadron.flagship.isCrippled: CombatState.Crippled else: CombatState.Undamaged,
      fleetStatus: fleet.status,  # Pass fleet status for reserve AS/DS penalty
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: getTargetBucket(squadron.flagship.shipClass),
      targetWeight: 1.0
    )
    combatSquadrons.add(combatSq)

  # Get colony's planetary defense
  let colony = state.colonies[targetId]

  # Build full PlanetaryDefense from colony data
  var defense = PlanetaryDefense()

  # Shields: Convert colony shield level to ShieldLevel object
  if colony.planetaryShieldLevel > 0:
    let (rollNeeded, blockPct) = getShieldData(colony.planetaryShieldLevel)
    defense.shields = some(ShieldLevel(
      level: colony.planetaryShieldLevel,
      blockChance: float(rollNeeded) / 20.0,  # Convert d20 roll to probability
      blockPercentage: blockPct
    ))
  else:
    defense.shields = none(ShieldLevel)

  # Ground Batteries: Create GroundUnit objects from colony count
  defense.groundBatteries = @[]
  let ownerCSTLevel = state.houses[colony.owner].techTree.levels.constructionTech
  for i in 0 ..< colony.groundBatteries:
    let battery = createGroundBattery(
      id = $targetId & "_GB" & $i,
      owner = colony.owner,
      techLevel = ownerCSTLevel  # Use colony owner's actual CST level
    )
    defense.groundBatteries.add(battery)

  # Ground Forces: Create GroundUnit objects from armies and marines
  defense.groundForces = @[]
  for i in 0 ..< colony.armies:
    let army = createArmy(
      id = $targetId & "_AA" & $i,
      owner = colony.owner
    )
    defense.groundForces.add(army)

  for i in 0 ..< colony.marines:
    let marine = createMarine(
      id = $targetId & "_MD" & $i,
      owner = colony.owner
    )
    defense.groundForces.add(marine)

  # Spaceports: Check if colony has any operational spaceports
  defense.spaceport = colony.spaceports.len > 0

  # Generate deterministic seed for bombardment (turn + target system)
  let bombardmentSeed = hash((state.turn, targetId)).int64

  # Conduct bombardment
  let result = conductBombardment(combatSquadrons, defense, seed = bombardmentSeed, maxRounds = 3)

  # Apply damage to colony
  var updatedColony = colony

  # Infrastructure damage from bombardment result
  let infrastructureLoss = result.infrastructureDamage div 10  # Convert IU damage to infrastructure levels
  updatedColony.infrastructure -= infrastructureLoss
  if updatedColony.infrastructure < 0:
    updatedColony.infrastructure = 0

  # Industrial capacity damage (IU)
  updatedColony.industrial.units -= result.infrastructureDamage
  if updatedColony.industrial.units < 0:
    updatedColony.industrial.units = 0

  # Population casualties (PU)
  # result.populationDamage is in PU, convert to souls (1 PU = 1M souls)
  let soulsCasualties = result.populationDamage * 1_000_000
  updatedColony.souls -= soulsCasualties
  if updatedColony.souls < 0:
    updatedColony.souls = 0
  # Update display fields
  updatedColony.population = updatedColony.souls div 1_000_000
  updatedColony.populationUnits = updatedColony.population

  # Apply battery destruction from bombardment
  updatedColony.groundBatteries -= result.batteriesDestroyed
  if updatedColony.groundBatteries < 0:
    updatedColony.groundBatteries = 0

  # Ships-in-dock destruction (economy.md:5.0)
  # Bombardment only affects SPACEPORT docks, not shipyard docks
  var shipsDestroyedInDock = false
  if infrastructureLoss > 0 and updatedColony.underConstruction.isSome:
    let project = updatedColony.underConstruction.get()
    if project.projectType == econ_types.ConstructionType.Ship:
      # Only destroy if in spaceport dock (bombardment doesn't affect shipyard docks)
      if project.facilityType.isSome and project.facilityType.get() == econ_types.FacilityType.Spaceport:
        updatedColony.underConstruction = none(econ_types.ConstructionProject)
        shipsDestroyedInDock = true
        logCombat("Ship under construction destroyed in bombardment (spaceport dock)",
                  "systemId=", $targetId)

  state.colonies[targetId] = updatedColony

  logCombat("Bombardment complete",
            "systemId=", $targetId,
            " infrastructure=", $infrastructureLoss,
            " IU=", $result.infrastructureDamage,
            " casualties=", $result.populationDamage, " PU")

  # Generate intelligence reports for both attacker and defender
  let groundForcesKilled = result.populationDamage  # Population damage represents casualties
  combat_intel.generateBombardmentIntelligence(
    state,
    targetId,
    houseId,  # Attacking house
    order.fleetId,
    colony.owner,  # Defending house
    infrastructureLoss,
    result.infrastructureDamage,  # IU damage
    defense.shields.isSome,  # Were shields active?
    result.batteriesDestroyed,
    groundForcesKilled,
    fleet.spaceLiftShips.len  # Invasion threat assessment
  )

  # Generate bombardment event with COMPLETE tactical data (Phase 7a fix)
  # Attacker casualties: squadronsDestroyed + squadronsCrippled from result
  let attackerCasualties = result.squadronsDestroyed + result.squadronsCrippled
  let facilitiesDestroyed = if shipsDestroyedInDock: 1 else: 0

  events.add(event_factory.bombardmentRoundCompleted(
    round = result.roundsCompleted,
    attackingHouse = houseId,
    defendingHouse = colony.owner,
    systemId = targetId,
    batteriesDestroyed = result.batteriesDestroyed,
    batteriesCrippled = result.batteriesCrippled,
    shieldBlocked = result.shieldBlocked,
    groundForcesDamaged = 0,  # Not tracked separately, part of populationDamage
    infrastructureDamage = result.infrastructureDamage,
    populationKilled = result.populationDamage,
    facilitiesDestroyed = facilitiesDestroyed,
    attackerCasualties = attackerCasualties
  ))

  # Generate OrderCompleted event
  events.add(event_factory.orderCompleted(
    houseId,
    order.fleetId,
    "Bombard",
    details = &"destroyed {infrastructureLoss} infrastructure at {targetId}",
    systemId = some(targetId)
  ))

# ============================================================================
# HELPER FUNCTIONS - Ground Defense Detection
# ============================================================================

proc isColonyUndefended(colony: Colony): bool =
  ## Check if colony lacks any ground defense
  ## Returns true if colony has NO armies, marines, or ground batteries
  ##
  ## NOTE: Planetary shields alone don't count as "defended"
  ## Shields slow invasions but don't stop them - troops are required
  result = colony.armies == 0 and
           colony.marines == 0 and
           colony.groundBatteries == 0

# ============================================================================
# INVASION RESOLUTION
# ============================================================================

proc resolveInvasion*(state: var GameState, houseId: HouseId, order: FleetOrder,
                    events: var seq[GameEvent]) =
  ## Process planetary invasion order (operations.md:7.6)
  ## Phase 3 of planetary combat - requires all ground batteries destroyed
  ## Marines attack ground forces to capture colony

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Invade",
      reason = "no target system specified",
      systemId = none(SystemId)
    ))
    return

  let targetId = order.targetSystem.get()

  # Validate fleet exists and is at target
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    logWarn("Combat", "Invasion failed - fleet not found",
            "fleetId=", $order.fleetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Invade",
      reason = "fleet destroyed",
      systemId = some(targetId)
    ))
    return

  let fleet = fleetOpt.get()
  if fleet.location != targetId:
    logWarn("Combat", "Invasion failed - fleet not at target system",
            "fleetId=", $order.fleetId, " location=", $fleet.location,
            " target=", $targetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Invade",
      reason = "fleet not at target system",
      systemId = some(targetId)
    ))
    return

  # Validate target colony exists
  if targetId notin state.colonies:
    logWarn("Combat", "Invasion failed - no colony at target",
            "systemId=", $targetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Invade",
      reason = "target colony no longer exists",
      systemId = some(targetId)
    ))
    return

  let colony = state.colonies[targetId]

  # Check if colony belongs to attacker (can't invade your own colony)
  if colony.owner == houseId:
    logWarn("Combat", "Invasion failed - cannot invade your own colony",
            "houseId=", $houseId, " systemId=", $targetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Invade",
      reason = "target is now friendly (cannot invade own colony)",
      systemId = some(targetId)
    ))
    return

  # Build attacking ground forces from spacelift ships (marines only)
  var attackingForces: seq[GroundUnit] = @[]
  for ship in fleet.spaceLiftShips:
    if ship.cargo.cargoType == CargoType.Marines and ship.cargo.quantity > 0:
      for i in 0 ..< ship.cargo.quantity:
        let marine = createMarine(
          id = $houseId & "_MD_" & $targetId & "_" & $i,
          owner = houseId
        )
        attackingForces.add(marine)

  if attackingForces.len == 0:
    logWarn("Combat", "Invasion failed - no marines in fleet",
            "fleetId=", $order.fleetId)
    return

  # Build defending ground forces
  var defendingForces: seq[GroundUnit] = @[]
  for i in 0 ..< colony.armies:
    let army = createArmy(
      id = $targetId & "_AA_" & $i,
      owner = colony.owner
    )
    defendingForces.add(army)

  for i in 0 ..< colony.marines:
    let marine = createMarine(
      id = $targetId & "_MD_" & $i,
      owner = colony.owner
    )
    defendingForces.add(marine)

  # Build planetary defense
  var defense = PlanetaryDefense()

  # Shields
  if colony.planetaryShieldLevel > 0:
    let (rollNeeded, blockPct) = getShieldData(colony.planetaryShieldLevel)
    defense.shields = some(ShieldLevel(
      level: colony.planetaryShieldLevel,
      blockChance: float(rollNeeded) / 20.0,
      blockPercentage: blockPct
    ))

  # Ground Batteries (must be destroyed for invasion to proceed)
  let ownerCSTLevel = state.houses[colony.owner].techTree.levels.constructionTech
  for i in 0 ..< colony.groundBatteries:
    let battery = createGroundBattery(
      id = $targetId & "_GB" & $i,
      owner = colony.owner,
      techLevel = ownerCSTLevel
    )
    defense.groundBatteries.add(battery)

  # Check prerequisite: all ground batteries must be destroyed
  # Per operations.md:7.6, invasion requires bombardment to destroy ground batteries first
  if defense.groundBatteries.len > 0:
    logWarn("Combat", "Invasion failed - ground batteries still operational (bombardment required first)",
            "systemId=", $targetId, " batteries=", $defense.groundBatteries.len)
    return

  # Ground forces already added above
  defense.groundForces = defendingForces

  # Spaceport
  defense.spaceport = colony.spaceports.len > 0

  # Generate deterministic seed
  let invasionSeed = hash((state.turn, targetId, houseId)).int64

  # Generate InvasionBegan event (Phase 7a)
  events.add(event_factory.invasionBegan(
    fleetId = order.fleetId,
    attackingHouse = houseId,
    defendingHouse = colony.owner,
    systemId = targetId,
    marinesLanding = attackingForces.len
  ))

  # Conduct invasion
  let result = conductInvasion(attackingForces, defendingForces, defense, invasionSeed)

  # Apply results
  var updatedColony = colony

  if result.success:
    # Invasion succeeded - colony captured
    logCombat("Invasion SUCCESS - colony captured",
              "attacker=", $houseId, " defender=", $colony.owner,
              " systemId=", $targetId)

    # Transfer ownership
    updatedColony.owner = houseId

    # Apply infrastructure damage (50% destroyed per operations.md:7.6.2)
    updatedColony.infrastructure = updatedColony.infrastructure div 2

    # Apply industrial capacity damage (IU lost from invasion)
    updatedColony.industrial.units -= result.infrastructureDestroyed
    if updatedColony.industrial.units < 0:
      updatedColony.industrial.units = 0

    # Shields and spaceports destroyed on landing (per spec)
    updatedColony.planetaryShieldLevel = 0
    updatedColony.spaceports = @[]

    # Destroy ships under construction/repair in spaceport docks (per economy.md:5.0)
    handleFacilityDestruction(updatedColony, econ_types.FacilityType.Spaceport)

    # Update ground forces
    # Attacker marines that survived become garrison
    let survivingMarines = attackingForces.len - result.attackerCasualties.len
    updatedColony.marines = survivingMarines
    updatedColony.armies = 0  # Defender armies all destroyed/disbanded

    # Unload marines from spacelift ships (they've landed)
    var updatedFleet = state.fleets[order.fleetId]
    for ship in updatedFleet.spaceLiftShips.mitems:
      if ship.cargo.cargoType == CargoType.Marines:
        discard ship.unloadCargo()
    state.fleets[order.fleetId] = updatedFleet

    # Check if colony was undefended (BEFORE taking ownership)
    let wasUndefended = isColonyUndefended(colony)

    # Prestige changes
    let attackerPrestige = applyMultiplier(getPrestigeValue(PrestigeSource.ColonySeized))
    let invasionEvent = createPrestigeEvent(
      PrestigeSource.ColonySeized,
      attackerPrestige,
      "Captured colony at " & $targetId & " via invasion"
    )
    applyPrestigeEvent(state, houseId, invasionEvent)
    logCombat("Invasion prestige awarded",
              "house=", $houseId, " prestige=", $attackerPrestige)

    # Defender loses prestige for colony loss (with undefended penalty if applicable)
    var defenderPenalty = -attackerPrestige  # Base: equal but opposite

    # Apply +50% penalty for losing undefended colony
    if wasUndefended:
      let undefendedMultiplier = globalPrestigeConfig.military.undefended_colony_penalty_multiplier
      defenderPenalty = int(float(defenderPenalty) * undefendedMultiplier)
      logCombat("Undefended colony penalty applied",
                "house=", $colony.owner, " multiplier=", $undefendedMultiplier,
                " total_penalty=", $defenderPenalty,
                " additional_penalty=", $int(abs(defenderPenalty) - abs(-attackerPrestige)))

    let colonyLossEvent = createPrestigeEvent(
      PrestigeSource.ColonySeized,
      defenderPenalty,
      "Lost colony at " & $targetId & " to invasion" & (if wasUndefended: " (undefended)" else: "")
    )
    applyPrestigeEvent(state, colony.owner, colonyLossEvent)
    logCombat("Colony loss prestige penalty",
              "house=", $colony.owner, " prestige=", $defenderPenalty)

    # Generate event
    events.add(event_factory.colonyCaptured(
      houseId,
      colony.owner,
      targetId,
      "Invasion"
    ))

    # Generate OrderCompleted event for successful invasion
    events.add(event_factory.orderCompleted(
      houseId,
      order.fleetId,
      "Invade",
      details = &"captured system {targetId}",
      systemId = some(targetId)
    ))
  else:
    # Invasion failed - ALL attacking marines destroyed (no retreat from ground combat)
    logCombat("Invasion FAILED - attacker repelled",
              "defender=", $colony.owner, " attacker=", $houseId,
              " systemId=", $targetId)
    logCombat("All attacking marines destroyed",
              "marines=", $attackingForces.len)

    # Update defender ground forces
    let survivingDefenders = defendingForces.len - result.defenderCasualties.len
    # Simplified: assume casualties distributed evenly between armies and marines
    let totalDefenders = colony.armies + colony.marines
    if totalDefenders > 0:
      let armyFraction = float(colony.armies) / float(totalDefenders)
      updatedColony.armies = int(float(survivingDefenders) * armyFraction)
      updatedColony.marines = survivingDefenders - updatedColony.armies

    # All attacker marines destroyed - unload ALL marines from spacelift ships
    # Marines cannot retreat once they've landed on the planet
    var updatedFleet = state.fleets[order.fleetId]
    for ship in updatedFleet.spaceLiftShips.mitems:
      if ship.cargo.cargoType == CargoType.Marines:
        discard ship.unloadCargo()  # Remove all marines (destroyed in combat)
    state.fleets[order.fleetId] = updatedFleet

    # Generate event
    events.add(event_factory.invasionRepelled(
      colony.owner,
      targetId,
      houseId
    ))

    # Generate OrderFailed event for failed invasion
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Invade",
      reason = "invasion repelled - all marines destroyed",
      systemId = some(targetId)
    ))

  state.colonies[targetId] = updatedColony

  # INTELLIGENCE: Generate invasion reports for both houses (after state updates)
  combat_intel.generateInvasionIntelligence(
    state, targetId, houseId, colony.owner,
    attackingForces.len,
    colony.armies,
    colony.marines,
    result.success,
    result.attackerCasualties.len,
    result.defenderCasualties.len,
    result.infrastructureDestroyed
  )

proc resolveBlitz*(state: var GameState, houseId: HouseId, order: FleetOrder,
                 events: var seq[GameEvent]) =
  ## Process planetary blitz order (operations.md:7.6.2)
  ## Fast insertion variant - seizes assets intact but marines get 0.5x AS penalty
  ## Transports vulnerable to ground batteries during insertion

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Blitz",
      reason = "no target system specified",
      systemId = none(SystemId)
    ))
    return

  let targetId = order.targetSystem.get()

  # Validate fleet exists and is at target
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    logWarn("Combat", "Blitz failed - fleet not found",
            "fleetId=", $order.fleetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Blitz",
      reason = "fleet destroyed",
      systemId = some(targetId)
    ))
    return

  let fleet = fleetOpt.get()
  if fleet.location != targetId:
    logWarn("Combat", "Blitz failed - fleet not at target system",
            "fleetId=", $order.fleetId, " location=", $fleet.location,
            " target=", $targetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Blitz",
      reason = "fleet not at target system",
      systemId = some(targetId)
    ))
    return

  # Validate target colony exists
  if targetId notin state.colonies:
    logWarn("Combat", "Blitz failed - no colony at target",
            "systemId=", $targetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Blitz",
      reason = "target colony no longer exists",
      systemId = some(targetId)
    ))
    return

  let colony = state.colonies[targetId]

  # Check if colony belongs to attacker
  if colony.owner == houseId:
    logWarn("Combat", "Blitz failed - cannot blitz your own colony",
            "houseId=", $houseId, " systemId=", $targetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Blitz",
      reason = "target is now friendly (cannot blitz own colony)",
      systemId = some(targetId)
    ))
    return

  # Build attacking fleet (squadrons needed for blitz vs ground batteries)
  var attackingFleet: seq[CombatSquadron] = @[]
  for squadron in fleet.squadrons:
    let combatSq = CombatSquadron(
      squadron: squadron,
      state: if squadron.flagship.isCrippled: CombatState.Crippled else: CombatState.Undamaged,
      fleetStatus: fleet.status,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: getTargetBucket(squadron.flagship.shipClass),
      targetWeight: 1.0
    )
    attackingFleet.add(combatSq)

  # Build attacking ground forces from spacelift ships (marines only)
  var attackingForces: seq[GroundUnit] = @[]
  for ship in fleet.spaceLiftShips:
    if ship.cargo.cargoType == CargoType.Marines and ship.cargo.quantity > 0:
      for i in 0 ..< ship.cargo.quantity:
        let marine = createMarine(
          id = $houseId & "_MD_" & $targetId & "_" & $i,
          owner = houseId
        )
        attackingForces.add(marine)

  if attackingForces.len == 0:
    logWarn("Combat", "Blitz failed - no marines in fleet",
            "fleetId=", $order.fleetId)
    return

  # Build defending ground forces
  var defendingForces: seq[GroundUnit] = @[]
  for i in 0 ..< colony.armies:
    let army = createArmy(
      id = $targetId & "_AA_" & $i,
      owner = colony.owner
    )
    defendingForces.add(army)

  for i in 0 ..< colony.marines:
    let marine = createMarine(
      id = $targetId & "_MD_" & $i,
      owner = colony.owner
    )
    defendingForces.add(marine)

  # Build planetary defense
  var defense = PlanetaryDefense()

  # Shields
  if colony.planetaryShieldLevel > 0:
    let (rollNeeded, blockPct) = getShieldData(colony.planetaryShieldLevel)
    defense.shields = some(ShieldLevel(
      level: colony.planetaryShieldLevel,
      blockChance: float(rollNeeded) / 20.0,
      blockPercentage: blockPct
    ))

  # Ground Batteries (blitz fights through them unlike invasion)
  let ownerCSTLevel = state.houses[colony.owner].techTree.levels.constructionTech
  for i in 0 ..< colony.groundBatteries:
    let battery = createGroundBattery(
      id = $targetId & "_GB" & $i,
      owner = colony.owner,
      techLevel = ownerCSTLevel
    )
    defense.groundBatteries.add(battery)

  # Ground forces
  defense.groundForces = defendingForces

  # Spaceport
  defense.spaceport = colony.spaceports.len > 0

  # Generate deterministic seed
  let blitzSeed = hash((state.turn, targetId, houseId, "blitz")).int64

  # Generate BlitzBegan event (Phase 7a)
  # Blitz: marines get 0.5x AS penalty, transports vulnerable during insertion
  events.add(event_factory.blitzBegan(
    fleetId = order.fleetId,
    attackingHouse = houseId,
    defendingHouse = colony.owner,
    systemId = targetId,
    marinesLanding = attackingForces.len,
    transportsVulnerable = true,
    marineAsPenalty = 0.5
  ))

  # Conduct blitz
  let result = conductBlitz(attackingFleet, attackingForces, defense, blitzSeed)

  # Apply results
  var updatedColony = colony

  if result.success:
    # Blitz succeeded - colony captured with assets intact
    logCombat("Blitz SUCCESS - colony captured with assets seized",
              "attacker=", $houseId, " defender=", $colony.owner,
              " systemId=", $targetId)

    # Transfer ownership
    updatedColony.owner = houseId

    # NO infrastructure damage on blitz (assets seized intact per operations.md:7.6.2)
    # Shields, spaceports, ground batteries all seized intact

    # Update ground forces
    let survivingMarines = attackingForces.len - result.attackerCasualties.len
    updatedColony.marines = survivingMarines
    updatedColony.armies = 0

    # Unload marines from spacelift ships
    var updatedFleet = state.fleets[order.fleetId]
    for ship in updatedFleet.spaceLiftShips.mitems:
      if ship.cargo.cargoType == CargoType.Marines:
        discard ship.unloadCargo()
    state.fleets[order.fleetId] = updatedFleet

    # Check if colony was undefended (BEFORE taking ownership)
    let wasUndefended = isColonyUndefended(colony)

    # Prestige changes (blitz gets same prestige as invasion)
    let attackerPrestige = applyMultiplier(getPrestigeValue(PrestigeSource.ColonySeized))
    let blitzEvent = createPrestigeEvent(
      PrestigeSource.ColonySeized,
      attackerPrestige,
      "Captured colony at " & $targetId & " via blitz"
    )
    applyPrestigeEvent(state, houseId, blitzEvent)
    logCombat("Blitz prestige awarded",
              "house=", $houseId, " prestige=", $attackerPrestige)

    # Defender loses prestige for colony loss (with undefended penalty if applicable)
    var defenderPenalty = -attackerPrestige  # Base: equal but opposite

    # Apply +50% penalty for losing undefended colony
    if wasUndefended:
      let undefendedMultiplier = globalPrestigeConfig.military.undefended_colony_penalty_multiplier
      defenderPenalty = int(float(defenderPenalty) * undefendedMultiplier)
      logCombat("Undefended colony penalty applied (blitz)",
                "house=", $colony.owner, " multiplier=", $undefendedMultiplier,
                " total_penalty=", $defenderPenalty,
                " additional_penalty=", $int(abs(defenderPenalty) - abs(-attackerPrestige)))

    let colonyLossBlitzEvent = createPrestigeEvent(
      PrestigeSource.ColonySeized,
      defenderPenalty,
      "Lost colony at " & $targetId & " to blitz" & (if wasUndefended: " (undefended)" else: "")
    )
    applyPrestigeEvent(state, colony.owner, colonyLossBlitzEvent)
    logCombat("Colony loss prestige penalty",
              "house=", $colony.owner, " prestige=", $defenderPenalty)

    # Generate event
    events.add(event_factory.colonyCaptured(
      houseId,
      colony.owner,
      targetId,
      "Blitz"
    ))

    # Generate OrderCompleted event for successful blitz
    events.add(event_factory.orderCompleted(
      houseId,
      order.fleetId,
      "Blitz",
      details = &"captured system {targetId} via blitz",
      systemId = some(targetId)
    ))
  else:
    # Blitz failed - ALL attacking marines destroyed (no retreat from ground combat)
    logCombat("Blitz FAILED - attacker repelled",
              "defender=", $colony.owner, " attacker=", $houseId,
              " systemId=", $targetId)
    logCombat("All attacking marines destroyed",
              "marines=", $attackingForces.len)

    # Update defender ground forces
    let survivingDefenders = defendingForces.len - result.defenderCasualties.len
    let totalDefenders = colony.armies + colony.marines
    if totalDefenders > 0:
      let armyFraction = float(colony.armies) / float(totalDefenders)
      updatedColony.armies = int(float(survivingDefenders) * armyFraction)
      updatedColony.marines = survivingDefenders - updatedColony.armies

    # Update ground batteries (destroyed during Phase 1 bombardment)
    updatedColony.groundBatteries -= result.batteriesDestroyed
    if updatedColony.groundBatteries < 0:
      updatedColony.groundBatteries = 0

    # All attacker marines destroyed - unload ALL marines from spacelift ships
    # Marines cannot retreat once they've landed on the planet
    var updatedFleet = state.fleets[order.fleetId]
    for ship in updatedFleet.spaceLiftShips.mitems:
      if ship.cargo.cargoType == CargoType.Marines:
        discard ship.unloadCargo()  # Remove all marines (destroyed in combat)
    state.fleets[order.fleetId] = updatedFleet

    # Generate event
    events.add(event_factory.invasionRepelled(
      colony.owner,
      targetId,
      houseId
    ))

    # Generate OrderFailed event for failed blitz
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Blitz",
      reason = "blitz repelled - all marines destroyed",
      systemId = some(targetId)
    ))

  state.colonies[targetId] = updatedColony

  # INTELLIGENCE: Generate blitz reports for both houses (after state updates)
  combat_intel.generateBlitzIntelligence(
    state, targetId, houseId, colony.owner,
    attackingForces.len,
    colony.armies,
    colony.marines,
    result.success,
    result.attackerCasualties.len,
    result.defenderCasualties.len,
    result.batteriesDestroyed
  )
