## Space and Orbital Combat Resolution - Theaters 1 & 2
##
## Per docs/specs/07-combat.md Section 7.1.1:
## "Space Combat (First Theater): Fight enemy mobile fleets in deep space"
## "Orbital Combat (Second Theater): Assault fortified orbital defenses"
##
## Implements linear progression: Space combat → Orbital combat
## See colony/planetary_combat.nim for Theater 3 (planetary operations)

import std/[tables, options, sequtils, hashes, math, random, strformat]
import ../../../common/logger
import ../../types/[core, combat, game_state, fleet, squadron, ship, colony, house, facilities as econ_types, diplomacy as dip_types, intel as intel_types, prestige]
import ../../state/[engine, iterators]
import ./[engine as combat_engine, ground]
import ../../globals # For gameConfig
import ../../prestige/[
  engine as prestige_engine, application as prestige_app, sources as prestige_sources,
  events as prestige_events,
]
import ../diplomacy/engine as dip_engine
import ../../intel/[diplomatic_intel, combat_intel]
import ../fleet/mechanics
import ../facilities/damage as facility_damage
import ../../event_factory/init as event_factory

proc applySpaceLiftScreeningLosses(
    state: var GameState,
    combatOutcome: combat_engine.CombatResult,
    fleetsBeforeCombat: Table[FleetId, Fleet],
    combatPhase: string, # "Space" or "Orbital"
    events: var seq[GameEvent],
) =
  ## Apply spacelift ship losses based on task force casualties
  ## Spacelift ships are screened by task forces - losses are proportional to task force casualties
  ## If task force destroyed → all spacelift ships destroyed
  ## If task force retreated → proportional spacelift ships destroyed (matching casualty %)

  # Track spacelift losses by house for event generation
  # Note: Spacelift ships are now in Expansion/Auxiliary squadrons - these are already
  # included in squadron casualty calculations, so we don't need separate spacelift loss logic.
  # However, we still track if these special squadrons were destroyed for event reporting.
  var spaceliftLossesByHouse: Table[HouseId, int] = initTable[HouseId, int]()

  for fleetId, fleetBefore in fleetsBeforeCombat.pairs:
    # Count Expansion/Auxiliary squadrons before
    var spaceliftSquadronsBefore = 0
    for squadronId in fleetBefore.squadrons:
      let squadronOpt = state.squadron(squadronId)
      if squadronOpt.isSome:
        let squadron = squadronOpt.get()
        if squadron.squadronType in {SquadronClass.Expansion, SquadronClass.Auxiliary}:
          spaceliftSquadronsBefore += 1

    if spaceliftSquadronsBefore == 0:
      continue # No spacelift squadrons to lose

    # Skip mothballed fleets (they don't participate in combat, handled separately)
    if fleetBefore.status == FleetStatus.Mothballed:
      continue

    # Count Expansion/Auxiliary squadrons after
    var spaceliftSquadronsAfter = 0
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isSome:
      let fleet = fleetOpt.get()
      for sqId in fleet.squadrons:
        let sqOpt = state.squadron(sqId)
        if sqOpt.isSome:
          let squadron = sqOpt.get()
          if squadron.squadronType in {SquadronClass.Expansion, SquadronClass.Auxiliary}:
            spaceliftSquadronsAfter += 1

    # Track losses
    let spaceliftLosses = spaceliftSquadronsBefore - spaceliftSquadronsAfter
    if spaceliftLosses > 0:
      spaceliftLossesByHouse[fleetBefore.houseId] =
        spaceliftLossesByHouse.getOrDefault(fleetBefore.houseId, 0) + spaceliftLosses

      logCombat(
        &"{combatPhase} combat: Fleet {fleetId} transport squadron losses",
        "casualties=",
        $spaceliftLosses,
        "before=",
        $spaceliftSquadronsBefore,
        "after=",
        $spaceliftSquadronsAfter,
      )

  # Generate events for transport squadron losses
  for houseId, losses in spaceliftLossesByHouse:
    events.add(
      event_factory.battle(
        houseId,
        combatOutcome.systemId,
        &"{combatPhase} combat: {losses} transport squadrons destroyed (screened by task force)",
      )
    )

proc isIntelOnlyFleet(state: GameState, fleet: Fleet): bool =
  ## Check if fleet contains only Intel squadrons (intelligence gathering units)
  ## Intel-only fleets are invisible to combat fleets and never participate in combat
  if fleet.squadrons.len == 0:
    return false

  for squadronId in fleet.squadrons:
    let squadronOpt = state.squadron(squadronId)
    if squadronOpt.isSome:
      let squadron = squadronOpt.get()
      if squadron.squadronType != SquadronClass.Intel:
        return false

  return true

proc getTargetBucket(shipClass: ShipClass): TargetBucket =
  ## Determine target bucket from ship class
  ## Note: Starbases use TargetBucket.Starbase but aren't in ShipClass (they're facilities)
  case shipClass
  of ShipClass.Raider: TargetBucket.Raider
  of ShipClass.Fighter: TargetBucket.Fighter
  of ShipClass.Corvette, ShipClass.Frigate, ShipClass.Destroyer:
    TargetBucket.Escort # Light warships are escorts
  else: TargetBucket.Capital # Cruisers, battleships, carriers, etc

proc getStarbaseStats(wepLevel: int): ShipStats =
  ## Load starbase combat stats from facilities.kdl
  ## Applies WEP tech modifications like ships
  let facilityConfig = gameConfig.facilities.facilities[FacilityClass.Starbase]

  # Base stats from facilities config
  var baseAS = facilityConfig.attackStrength
  var baseDS = facilityConfig.defenseStrength

  # Apply WEP tech modifications (AS and DS scale with weapons tech)
  if wepLevel > 1:
    let weaponsMultiplier = pow(1.10, float(wepLevel - 1))
    baseAS = int32(float(baseAS) * weaponsMultiplier)
    baseDS = int32(float(baseDS) * weaponsMultiplier)

  return ShipStats(
    attackStrength: baseAS,
    defenseStrength: baseDS,
    wep: int32(wepLevel),
  )

proc autoEscalateDiplomacy(
    state: var GameState,
    combatOutcome: combat_engine.CombatResult,
    combatPhase: string,
    fleetsInCombat: seq[(FleetId, Fleet)],
) =
  ## Auto-escalate diplomatic status based on combat actions
  ## - Space Combat → Hostile (deep space engagement)
  ## - Orbital Combat → Enemy (planetary attack)
  ## Per approved 4-level diplomacy system

  if combatOutcome.totalRounds == 0:
    return # No combat occurred

  # Determine target diplomatic state based on combat phase
  let targetState =
    if combatPhase == "Space Combat":
      dip_types.DiplomaticState.Hostile # Deep space combat escalates to Hostile
    else:
      dip_types.DiplomaticState.Enemy # Orbital combat escalates to Enemy

  # Collect all houses involved in combat
  var housesInvolved: seq[HouseId] = @[]
  for (fleetId, fleet) in fleetsInCombat:
    if fleet.houseId notin housesInvolved:
      housesInvolved.add(fleet.houseId)

  # Auto-escalate diplomatic relations between all pairs of combatants
  for i in 0 ..< housesInvolved.len:
    for j in (i + 1) ..< housesInvolved.len:
      let house1 = housesInvolved[i]
      let house2 = housesInvolved[j]

      # Get current diplomatic states (using entity_manager)
      let house1Opt = state.house(house1)
      let house2Opt = state.house(house2)
      if house1Opt.isNone or house2Opt.isNone:
        logWarn(
          "Combat",
          "Auto-escalation failed - house not found",
          "house1=",
          $house1,
          " house2=",
          $house2,
        )
        continue

      # Get current diplomatic state from state.diplomaticRelation
      let key = (house1, house2)
      let currentState =
        if state.diplomaticRelation.hasKey(key):
          state.diplomaticRelation[key].state
        else:
          dip_types.DiplomaticState.Neutral

      # Only escalate if current state is less hostile than target
      # Neutral (0) < Hostile (1) < Enemy (2)
      if ord(currentState) < ord(targetState):
        # Update diplomatic relation (bidirectional)
        state.diplomaticRelation[key] = dip_types.DiplomaticRelation(
          sourceHouse: house1,
          targetHouse: house2,
          state: targetState,
          sinceTurn: state.turn,
        )

        logResolve(
          "Auto-escalation",
          "phase=",
          combatPhase,
          " house1=",
          $house1,
          " house2=",
          $house2,
          " oldState=",
          $currentState,
          " newState=",
          $targetState,
        )

        # Generate intelligence about escalation
        if targetState == dip_types.DiplomaticState.Hostile:
          diplomatic_intel.generateHostilityDeclarationIntel(
            state, house1, house2, state.turn
          )
        else:
          diplomatic_intel.generateWarDeclarationIntel(
            state, house1, house2, state.turn
          )


proc executeCombat(
    state: var GameState,
    systemId: SystemId,
    fleetsInCombat: seq[(FleetId, Fleet)],
    systemOwner: Option[HouseId],
    includeStarbases: bool,
    includeUnassignedSquadrons: bool,
    combatPhase: string,
    events: var seq[GameEvent],
    preDetectedHouses: seq[HouseId] =
      @[] # Houses already detected in previous combat phase
    ,
): tuple[
  outcome: CombatResult,
  fleetsAtSystem: seq[(FleetId, Fleet)],
  detectedHouses: seq[HouseId],
] =
  ## Helper function to execute a combat phase
  ## Returns combat outcome, fleets that participated, and newly detected cloaked houses

  if fleetsInCombat.len < 2:
    return (CombatResult(), @[], @[])

  logCombat(combatPhase, "fleets=", $fleetsInCombat.len)

  # Group fleets by house
  var houseFleets: Table[HouseId, seq[Fleet]] = initTable[HouseId, seq[Fleet]]()
  for (fleetId, fleet) in fleetsInCombat:
    if fleet.houseId notin houseFleets:
      houseFleets[fleet.houseId] = @[]
    houseFleets[fleet.houseId].add(fleet)

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
        logDebug(
          "Combat", "Fleet mothballed - screened from combat", "fleetId=", $fleet.id
        )
        continue

      for squadronId in fleet.squadrons:
        let squadronOpt = state.squadron(squadronId)
        if squadronOpt.isNone:
          continue
        let squadron = squadronOpt.get()

        # Only Combat squadrons participate in combat
        # Intel, Auxiliary, Expansion, and Fighter squadrons are screened
        if squadron.squadronType != SquadronClass.Combat:
          logDebug(
            "Combat",
            "Non-combat squadron excluded from task force",
            "squadronId=",
            $squadron.id,
            "type=",
            $squadron.squadronType,
          )
          continue

        # Get flagship ship via DoD pattern (flagshipId reference)
        let flagshipOpt = state.ship(squadron.flagshipId)
        if flagshipOpt.isNone:
          continue # Skip squadron if flagship doesn't exist

        let flagship = flagshipOpt.get()

        let combatSq = CombatSquadron(
          squadronId: squadron.id,
          attackStrength: flagship.stats.attackStrength,
          defenseStrength: flagship.stats.defenseStrength,
          commandRating: gameConfig.ships.ships[flagship.shipClass].commandRating,
          state:
            if flagship.isCrippled:
              CombatState.Crippled
            else:
              CombatState.Undamaged,
          fleetStatus: fleet.status,
          damageThisTurn: 0,
          crippleRound: 0,
          bucket: getTargetBucket(flagship.shipClass),
          targetWeight: 1.0,
        )
        combatSquadrons.add(combatSq)

    # Add unassigned squadrons from colony if this is orbital combat
    if includeUnassignedSquadrons and systemOwner.isSome and systemOwner.get() == houseId:
      # Look up colony by system
      let colonyOpt = state.colonyBySystem(systemId)
      if colonyOpt.isSome:
          let colony = colonyOpt.get()
          for squadronId in colony.unassignedSquadronIds:
            # Get squadron entity via DoD pattern
            let squadronOpt = state.squadron(squadronId)
            if squadronOpt.isNone:
              continue
            let squadron = squadronOpt.get()

            # Get flagship ship via DoD pattern
            let flagshipOpt = state.ship(squadron.flagshipId)
            if flagshipOpt.isNone:
              continue # Skip squadron if flagship doesn't exist

            let flagship = flagshipOpt.get()

            let combatSq = CombatSquadron(
              squadronId: squadron.id,
              attackStrength: flagship.stats.attackStrength,
              defenseStrength: flagship.stats.defenseStrength,
              commandRating: gameConfig.ships.ships[flagship.shipClass].commandRating,
              state:
                if flagship.isCrippled:
                  CombatState.Crippled
                else:
                  CombatState.Undamaged,
              fleetStatus: FleetStatus.Active,
                # Unassigned squadrons fight at full strength
              damageThisTurn: 0,
              crippleRound: 0,
              bucket: getTargetBucket(flagship.shipClass),
              targetWeight: 1.0,
            )
            combatSquadrons.add(combatSq)
          if colony.unassignedSquadronIds.len > 0:
            logDebug(
              "Combat",
              "Added unassigned squadrons to orbital defense",
              "count=",
              $colony.unassignedSquadronIds.len,
            )

    # Add starbases for system owner (always included for detection)
    # Starbases are ALWAYS included in task forces for detection purposes
    # In space combat: Starbases detect but don't fight (controlled by allowStarbaseCombat flag)
    # In orbital combat: Starbases detect AND fight
    var combatFacilities: seq[CombatFacility] = @[]
    if systemOwner.isSome and systemOwner.get() == houseId:
      # Look up colony by system
      let colonyOpt = state.colonyBySystem(systemId)
      if colonyOpt.isSome:
          let colony = colonyOpt.get()
          let houseOpt = state.house(houseId)
          if houseOpt.isNone:
            logWarn(
              "Combat", "Cannot add starbases - house not found", "houseId=", $houseId
            )
          else:
            # Load kastras (stored tech-modified stats)
            for kastraId in colony.kastraIds:
              let kastraOpt = state.kastra(kastraId)
              if kastraOpt.isNone:
                continue

              let kastra = kastraOpt.get()

              # Use stored stats (tech-modified at construction time)
              let combatFacility = CombatFacility(
                facilityId: kastra.id,
                systemId: systemId,
                owner: houseId,
                attackStrength: kastra.stats.attackStrength,
                defenseStrength: kastra.stats.defenseStrength,
                state:
                  if kastra.isCrippled: CombatState.Crippled else: CombatState.Undamaged,
                damageThisTurn: 0,
                crippleRound: 0,
                bucket: TargetBucket.Starbase,
                targetWeight: 5.0, # Base weight for Starbase bucket
              )
              combatFacilities.add(combatFacility)
            if colony.kastraIds.len > 0:
              let combatRole =
                if includeStarbases: "defense and detection" else: "detection only"
              logDebug(
                "Combat",
                "Added starbases",
                "count=",
                $colony.kastraIds.len,
                " role=",
                combatRole,
              )

    # Get house tech levels
    let houseOpt = state.house(houseId)
    let eliLevel = if houseOpt.isSome: houseOpt.get().techTree.levels.eli else: 0
    let clkLevel = if houseOpt.isSome: houseOpt.get().techTree.levels.clk else: 0

    # Create TaskForce for this house
    taskForces[houseId] = TaskForce(
      houseId: houseId,
      squadrons: combatSquadrons,
      facilities: combatFacilities, # Starbases and other defensive facilities
      roe: 5, # Default ROE
      isCloaked: false,
      moraleModifier: 0,
      isDefendingHomeworld: false,
      eliLevel: eliLevel,
      clkLevel: clkLevel,
    )

  # Collect all task forces for battle
  var allTaskForces: seq[TaskForce] = @[]
  for houseId, tf in taskForces:
    allTaskForces.add(tf)

  # Generate deterministic seed
  let deterministicSeed = hash((state.turn, systemId, combatPhase)).int64

  # Build diplomatic relations table for combat logic
  var diplomaticRelations = initTable[tuple[a, b: HouseId], dip_types.DiplomaticState]()
  for houseA in taskForces.keys:
    for houseB in taskForces.keys:
      if houseA.int32 < houseB.int32:  # Only process each pair once
        # Look up diplomatic state from GameState
        if state.diplomaticRelation.hasKey((houseA, houseB)):
          let relationAtoB = state.diplomaticRelation[(houseA, houseB)]
          diplomaticRelations[(houseA, houseB)] = relationAtoB.state
        if state.diplomaticRelation.hasKey((houseB, houseA)):
          let relationBtoA = state.diplomaticRelation[(houseB, houseA)]
          diplomaticRelations[(houseB, houseA)] = relationBtoA.state

  # Raider Detection Logic per assets.md:2.4.3
  var raiderTFs: seq[int]
  for i, tf in allTaskForces:
    var hasRaiders = false
    for sq in tf.squadrons:
      # Get squadron to access flagship
      let squadronOpt = state.squadron(sq.squadronId)
      if squadronOpt.isSome:
        let squadron = squadronOpt.get()
        # Get flagship via DoD pattern
        let flagshipOpt = state.ship(squadron.flagshipId)
        if flagshipOpt.isSome:
          let flagship = flagshipOpt.get()
          if flagship.shipClass == ShipClass.Raider:
            hasRaiders = true
            break
    if hasRaiders:
      raiderTFs.add(i)

  var detectionRng = initRand(deterministicSeed)
  var newlyDetectedHouses: seq[HouseId] = @[]

  for i in raiderTFs:
    var attackerTF = allTaskForces[i]
    if attackerTF.houseId in preDetectedHouses:
      attackerTF.isCloaked = false
      allTaskForces[i] = attackerTF
      continue

    attackerTF.isCloaked = true
    var isDetected = false
    let attackerHouseOpt = state.house(attackerTF.houseId)
    if attackerHouseOpt.isNone:
      logWarn(
        "Combat",
        "Raider detection failed - attacker house not found",
        "house=",
        $attackerTF.houseId,
      )
      continue
    let attackerCLK = attackerHouseOpt.get().techTree.levels.clk
    let attackerRoll = detectionRng.rand(1 .. 10) + attackerCLK

    for j, defenderTF in allTaskForces:
      if i == j:
        continue
      let relation = diplomaticRelations.getOrDefault(
        (attackerTF.houseId, defenderTF.houseId), dip_types.DiplomaticState.Neutral
      )
      if relation == dip_types.DiplomaticState.Neutral:
        continue

      let defenderHouseOpt = state.house(defenderTF.houseId)
      if defenderHouseOpt.isNone:
        logWarn(
          "Combat",
          "Raider detection failed - defender house not found",
          "house=",
          $defenderTF.houseId,
        )
        continue
      let defenderELI = defenderHouseOpt.get().techTree.levels.eli
      var starbaseBonus = 0
      if systemOwner.isSome and systemOwner.get() == defenderTF.houseId:
        let colonyOpt = state.colonyBySystem(systemId)
        if colonyOpt.isSome and colonyOpt.get().kastraIds.len > 0:
            starbaseBonus = gameConfig.combat.starbase.starbaseDetectionBonus
      let defenderRoll = detectionRng.rand(1 .. 10) + defenderELI + starbaseBonus

      logInfo(
        "Combat",
        &"Raider Detection Check: {attackerTF.houseId} (CLK {attackerCLK}, roll {attackerRoll}) vs {defenderTF.houseId} (ELI {defenderELI}, bonus {starbaseBonus}, roll {defenderRoll})",
      )
      if defenderRoll >= attackerRoll:
        isDetected = true
        logInfo(
          "Combat",
          &"Raider fleet from {attackerTF.houseId} DETECTED by {defenderTF.houseId}.",
        )

        # Generate RaiderDetected events for each raider fleet
        for (fleetId, fleet) in fleetsInCombat:
          if fleet.houseId == attackerTF.houseId:
            # Check if this fleet has raiders
            var hasRaiders = false
            for squadronId in fleet.squadrons:
              let squadronOpt = state.squadron(squadronId)
              if squadronOpt.isSome:
                let squadron = squadronOpt.get()
                # Get flagship via DoD pattern
                let flagshipOpt = state.ship(squadron.flagshipId)
                if flagshipOpt.isSome:
                  let flagship = flagshipOpt.get()
                  if flagship.shipClass == ShipClass.Raider:
                    hasRaiders = true
                    break

            if hasRaiders:
              let detectorType = if starbaseBonus > 0: "Starbase" else: "Scout"
              events.add(
                event_factory.raiderDetected(
                  raiderFleetId = fleetId,
                  raiderHouse = attackerTF.houseId,
                  detectorHouse = defenderTF.houseId,
                  detectorType = detectorType,
                  systemId = systemId,
                  eliRoll = defenderRoll,
                  clkRoll = attackerRoll,
                )
              )

        break
      else:
        # Detection failed - generate stealth success events for diagnostics
        # Visible only to raider (fog-of-war)
        logInfo(
          "Combat",
          &"Raider fleet from {attackerTF.houseId} evaded {defenderTF.houseId} detection.",
        )
        for (fleetId, fleet) in fleetsInCombat:
          if fleet.houseId == attackerTF.houseId:
            # Check if this fleet has raiders
            var hasRaiders = false
            for squadronId in fleet.squadrons:
              let squadronOpt = state.squadron(squadronId)
              if squadronOpt.isSome:
                let squadron = squadronOpt.get()
                # Get flagship via DoD pattern
                let flagshipOpt = state.ship(squadron.flagshipId)
                if flagshipOpt.isSome:
                  let flagship = flagshipOpt.get()
                  if flagship.shipClass == ShipClass.Raider:
                    hasRaiders = true
                    break

            if hasRaiders:
              let detectorType = if starbaseBonus > 0: "Starbase" else: "Scout"
              events.add(
                event_factory.raiderStealthSuccess(
                  raiderFleetId = fleetId,
                  raiderHouse = attackerTF.houseId,
                  detectorHouse = defenderTF.houseId,
                  detectorType = detectorType,
                  systemId = systemId,
                  eliRoll = defenderRoll,
                  clkRoll = attackerRoll,
                )
              )

    if isDetected:
      attackerTF.isCloaked = false
      newlyDetectedHouses.add(attackerTF.houseId)
    else:
      logInfo(
        "Combat",
        &"Raider fleet from {attackerTF.houseId} remains UNDETECTED.",
      )
    allTaskForces[i] = attackerTF

  let allowAmbush = (combatPhase == "Space Combat" or combatPhase == "Orbital Combat")
  let allowStarbaseCombat = (combatPhase == "Orbital Combat" or includeStarbases)

  # Check if defender has starbases for detection bonus
  var hasDefenderStarbase = false
  if systemOwner.isSome:
    let colonyOpt = state.colonyBySystem(systemId)
    if colonyOpt.isSome:
      hasDefenderStarbase = colonyOpt.get().kastraIds.len > 0

  var battleContext = BattleContext(
    systemId: systemId,
    taskForces: allTaskForces,
    seed: deterministicSeed,
    maxRounds: 20,
    allowAmbush: allowAmbush,
    allowStarbaseCombat: allowStarbaseCombat,
    preDetectedHouses: preDetectedHouses,
    diplomaticRelations: diplomaticRelations,
    systemOwner: systemOwner,
    hasDefenderStarbase: hasDefenderStarbase,
  )

  # Execute battle
  let outcome = combat_engine.resolveCombat(state, battleContext)

  return (outcome, fleetsInCombat, newlyDetectedHouses)

proc processCombatEvents(
    state: var GameState,
    systemId: SystemId,
    combatResult: combat_engine.CombatResult,
    theater: string, # "SpaceCombat" or "OrbitalCombat"
    events: var seq[GameEvent],
) =
  ## Process CombatResult and generate detailed combat narrative events
  ## Emits phase, attack, damage, and retreat events based on combat outcome

  # Extract houses involved
  var attackers: seq[HouseId] = @[]
  var defenders: seq[HouseId] = @[]
  var casualties: seq[HouseId] = @[]

  for tf in combatResult.survivors:
    # Determine if attacker or defender based on system ownership
    let colonyOpt = state.colonyBySystem(systemId)
    let systemOwner =
      if colonyOpt.isSome:
        some(colonyOpt.get().owner)
      else:
        none(HouseId)

    if systemOwner.isSome() and systemOwner.get() == tf.houseId:
      if tf.houseId notin defenders:
        defenders.add(tf.houseId)
    else:
      if tf.houseId notin attackers:
        attackers.add(tf.houseId)

  # Add eliminated and retreated houses
  for house in combatResult.eliminated:
    casualties.add(house)
  for house in combatResult.retreated:
    casualties.add(house)

  # Emit theater began event
  events.add(
    event_factory.combatTheaterBegan(
      theater = theater,
      systemId = systemId,
      attackers = attackers,
      defenders = defenders,
      roundNumber = 1,
    )
  )

  # Process each round's phases
  for roundIdx, roundPhases in combatResult.rounds:
    let roundNum = roundIdx + 1

    for phaseResult in roundPhases:
      # Map CombatPhase enum to phase string
      let phaseName =
        case phaseResult.phase
        of combat.CombatPhase.Ambush:
          "RaiderAmbush"
        of combat.CombatPhase.Intercept:
          "FighterIntercept"
        of combat.CombatPhase.MainEngagement:
          "CapitalEngagement"
        of combat.CombatPhase.PreCombat, combat.CombatPhase.PostCombat:
          "PrePostCombat" # Shouldn't occur in round results

      # Emit phase began event
      events.add(
        event_factory.combatPhaseBegan(
          phase = phaseName, systemId = systemId, roundNumber = roundNum
        )
      )

      # Process attacks in this phase
      for attack in phaseResult.attacks:
        # Find attacker and target houses
        var attackerHouse: Option[HouseId] = none(HouseId)
        var targetHouse: Option[HouseId] = none(HouseId)

        # Search squadrons in survivors to find houses
        for tf in combatResult.survivors:
          for sq in tf.squadrons:
            if attack.attackerId.kind == CombatTargetKind.Squadron and
                sq.squadronId == attack.attackerId.squadronId:
              attackerHouse = some(tf.houseId)
            if attack.targetId.kind == CombatTargetKind.Squadron and
                sq.squadronId == attack.targetId.squadronId:
              targetHouse = some(tf.houseId)

        if attackerHouse.isSome() and targetHouse.isSome():
          # Emit weapon fired event
          let weaponType = "Energy" # Placeholder - could extract from squadron
          let attackerHouseVal = attackerHouse.get()
          let targetHouseVal = targetHouse.get()
          events.add(
            event_factory.weaponFired(
              attackerSquadron = $attack.attackerId.squadronId,
              attackerHouse = attackerHouseVal,
              targetSquadron = $attack.targetId.squadronId,
              targetHouse = targetHouseVal,
              weaponType = weaponType,
              cerRoll = 5, # Placeholder - would need to extract from cerRoll
              cerModifier = 0, # Placeholder
              damage = int(attack.damageDealt),
              systemId = systemId,
            )
          )

          # Emit damage/destruction event if state changed
          if attack.targetStateBefore != attack.targetStateAfter:
            case attack.targetStateAfter
            of combat.CombatState.Crippled:
              events.add(
                event_factory.shipDamaged(
                  squadronId = $attack.targetId.squadronId,
                  houseId = targetHouseVal,
                  damage = int(attack.damageDealt),
                  newState = "Crippled",
                  remainingDs = 0, # Placeholder
                  systemId = systemId,
                )
              )
            of combat.CombatState.Destroyed:
              events.add(
                event_factory.shipDestroyed(
                  squadronId = $attack.targetId.squadronId,
                  houseId = targetHouseVal,
                  killedByHouse = attackerHouseVal,
                  criticalHit = attack.cerRoll.isCriticalHit,
                  overkillDamage = 0, # Placeholder
                  systemId = systemId,
                )
              )
            else:
              discard # Undamaged state, no event needed

      # Emit phase completed event
      var phaseCasualties: seq[HouseId] = @[]
      for stateChange in phaseResult.stateChanges:
        # Find house for this squadron
        if stateChange.targetId.kind == CombatTargetKind.Squadron:
          for tf in combatResult.survivors:
            for sq in tf.squadrons:
              if sq.squadronId == stateChange.targetId.squadronId:
                if tf.houseId notin phaseCasualties:
                  phaseCasualties.add(tf.houseId)

      events.add(
        event_factory.combatPhaseCompleted(
          phase = phaseName,
          systemId = systemId,
          roundNumber = roundNum,
          phaseRounds = 1, # Each phase is 1 round within the round
          casualties = phaseCasualties,
        )
      )

  # Emit retreat events
  for house in combatResult.retreated:
    # Find fleet ID for this house (placeholder - would need to track this)
    let fleetId: FleetId = FleetId(0) # Placeholder - FleetId is distinct uint32
    events.add(
      event_factory.fleetRetreat(
        fleetId = fleetId,
        houseId = house,
        reason = "ROE", # Placeholder - would need to track reason
        threshold = 50, # Placeholder
        casualties = 0, # Placeholder
        systemId = systemId,
      )
    )

  # Emit theater completed event
  events.add(
    event_factory.combatTheaterCompleted(
      theater = theater,
      systemId = systemId,
      victor = combatResult.victor,
      roundNumber = combatResult.totalRounds,
      casualties = casualties,
    )
  )

proc resolveBattle*(
    state: var GameState,
    systemId: SystemId,
    combatReports: var seq[combat.CombatReport],
    events: var seq[GameEvent],
    rng: var Rand,
) =
  ## Resolve combat at a system with linear progression (operations.md:7.0)
  ## Phase 1: Space Combat - non-guard mobile fleets fight first
  ## Phase 2: Orbital Combat - if attackers survive, fight guard/reserve fleets + starbases
  ## Uses fleet commands from state to determine which fleets are on guard duty
  logCombat("Resolving battle", "system=", $systemId)

  # 1. Determine system ownership
  let colonyOpt = state.colonyBySystem(systemId)
  let systemOwner =
    if colonyOpt.isSome:
      some(colonyOpt.get().owner)
    else:
      none(HouseId)

  # 2. Gather all fleets at this system and classify by role
  # Use fleetsByLocation index for O(1) lookup instead of O(F) scan
  var fleetsAtSystem: seq[(FleetId, Fleet)] = @[]
  var orbitalDefenders: seq[(FleetId, Fleet)] =
    @[] # Guard/Reserve/Mothballed (orbital defense only)
  var attackingFleets: seq[(FleetId, Fleet)] =
    @[] # Non-owner fleets (must fight through)
  var mobileDefenders: seq[(FleetId, Fleet)] =
    @[] # Owner's mobile fleets (space combat)

  for (fleetId, fleet) in state.fleetsAtSystemWithId(systemId):
    fleetsAtSystem.add((fleetId, fleet))

    # Intel-only fleets are invisible to combat fleets and never participate in combat
    # They operate independently for intelligence gathering (per 02-assets.md:2.4.2)
    if isIntelOnlyFleet(state, fleet):
      logDebug("Combat", "Intel-only fleet excluded from combat", "fleetId=", $fleetId)
      continue

    # Classify fleet based on ownership and orders
    let isDefender = systemOwner.isSome and systemOwner.get() == fleet.houseId

    if isDefender:
      # Defender fleet classification
      var isOrbitalOnly = false

      # Check for guard orders in fleet commands
      # Guarding fleets only defend in orbital combat, not space combat
      if state.fleetCommands.hasKey(fleetId):
        let command = state.fleetCommands[fleetId]
        if command.commandType == FleetCommandType.GuardStarbase or
            command.commandType == FleetCommandType.GuardColony:
          isOrbitalOnly = true

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
  var spaceCombatSurvivors: seq[HouseId] = @[] # Houses that survived space combat
  var detectedInSpace: seq[HouseId] = @[] # Houses detected during space combat

  # Check if there are attackers and mobile defenders
  if attackingFleets.len > 0 and mobileDefenders.len > 0:
    # Space combat: attackers must fight mobile defenders
    var spaceCombatParticipants = attackingFleets & mobileDefenders

    # INTELLIGENCE GATHERING: Pre-Combat Reports
    # Each house generates detailed intel on EACH other house's forces
    # This handles multi-house combat correctly (3-way, 4-way, etc.)
    var housesInCombat: seq[HouseId] = @[]
    for (fleetId, fleet) in spaceCombatParticipants:
      if fleet.houseId notin housesInCombat:
        housesInCombat.add(fleet.houseId)

    # Generate separate reports for each house observing each other house
    for reportingHouse in housesInCombat:
      var alliedFleetIds: seq[FleetId] = @[]

      # Collect own forces
      for (fleetId, fleet) in spaceCombatParticipants:
        if fleet.houseId == reportingHouse:
          alliedFleetIds.add(fleetId)

      # Generate separate intel report for EACH other house
      for otherHouse in housesInCombat:
        if otherHouse == reportingHouse:
          continue # Don't report on yourself

        var otherHouseFleetIds: seq[FleetId] = @[]
        for (fleetId, fleet) in spaceCombatParticipants:
          if fleet.houseId == otherHouse:
            otherHouseFleetIds.add(fleetId)

        if otherHouseFleetIds.len > 0:
          let preCombatReport = combat_intel.generatePreCombatReport(
            state, systemId, intel_types.CombatPhase.Space, reportingHouse,
            alliedFleetIds, otherHouseFleetIds,
          )
          # Intelligence stored in state.intel table (DoD pattern)
          if not state.intel.hasKey(reportingHouse):
            state.intel[reportingHouse] = intel_types.IntelDatabase(houseId: reportingHouse)
          state.intel[reportingHouse].combatReports.add(preCombatReport)

    let (outcome, fleets, detected) = executeCombat(
      state,
      systemId,
      spaceCombatParticipants,
      systemOwner,
      includeStarbases = false,
      includeUnassignedSquadrons = false,
      "Space Combat",
      events,
    )
    spaceCombatOutcome = outcome
    spaceCombatFleets = fleets
    detectedInSpace = detected
    # The `detected` result here will be used to pass detected status to subsequent combat phases.

    # Track which attacker houses survived
    for tf in outcome.survivors:
      if tf.houseId != systemOwner.get() and tf.houseId notin spaceCombatSurvivors:
        spaceCombatSurvivors.add(tf.houseId)

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
      if fleet.houseId notin spaceCombatSurvivors:
        spaceCombatSurvivors.add(fleet.houseId)
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
    let colonyOpt = state.colonyBySystem(systemId)
    if colonyOpt.isSome:
      let colony = colonyOpt.get()
      if colony.kastraIds.len > 0 or colony.unassignedSquadronIds.len > 0:
        hasOrbitalDefenders = true

    if hasOrbitalDefenders:
      logCombat("Phase 2: Orbital Combat")

      # Gather surviving attacker fleets
      var survivingAttackerFleets: seq[(FleetId, Fleet)] = @[]
      for (fleetId, fleet) in fleetsAtSystem:
        if fleet.houseId in spaceCombatSurvivors and fleet.houseId != systemOwner.get():
          survivingAttackerFleets.add((fleetId, fleet))

      if survivingAttackerFleets.len > 0:
        # Combine orbital defenders and surviving attackers
        var orbitalFleets = orbitalDefenders & survivingAttackerFleets

        # INTELLIGENCE GATHERING: Pre-Combat Reports (Orbital Phase)
        # Each house generates detailed intel on EACH other house's orbital forces
        var orbitalHouses: seq[HouseId] = @[]
        for (fleetId, fleet) in orbitalFleets:
          if fleet.houseId notin orbitalHouses:
            orbitalHouses.add(fleet.houseId)

        # Generate separate reports for each house observing each other house
        for reportingHouse in orbitalHouses:
          var alliedFleetIds: seq[FleetId] = @[]

          # Collect own forces
          for (fleetId, fleet) in orbitalFleets:
            if fleet.houseId == reportingHouse:
              alliedFleetIds.add(fleetId)

          # Generate separate intel report for EACH other house
          for otherHouse in orbitalHouses:
            if otherHouse == reportingHouse:
              continue # Don't report on yourself

            var otherHouseFleetIds: seq[FleetId] = @[]
            for (fleetId, fleet) in orbitalFleets:
              if fleet.houseId == otherHouse:
                otherHouseFleetIds.add(fleetId)

            if otherHouseFleetIds.len > 0:
              let orbitalPreCombatReport = combat_intel.generatePreCombatReport(
                state, systemId, intel_types.CombatPhase.Orbital, reportingHouse,
                alliedFleetIds, otherHouseFleetIds,
              )
              # Intelligence stored in state.intel table (DoD pattern)
              if not state.intel.hasKey(reportingHouse):
                state.intel[reportingHouse] = intel_types.IntelDatabase(houseId: reportingHouse)
              state.intel[reportingHouse].combatReports.add(orbitalPreCombatReport)

        let (outcome, fleets, detected) = executeCombat(
          state,
          systemId,
          orbitalFleets,
          systemOwner,
          includeStarbases = true,
          includeUnassignedSquadrons = true,
          "Orbital Combat",
          events,
          preDetectedHouses = detectedInSpace, # Pass detection status from space combat
        )
        orbitalCombatOutcome = outcome
        orbitalCombatFleets = fleets
        logCombat(
          "Orbital combat complete", "rounds=", $orbitalCombatOutcome.totalRounds
        )
        # Note: 'detected' from orbital combat itself might contain new detections.
        # However, for the purpose of passing detection status, 'detectedInSpace' is sufficient
        # to ensure any house detected in space remains detected in orbital.

        # Auto-escalate diplomatic relations after orbital combat
        autoEscalateDiplomacy(
          state, orbitalCombatOutcome, "Orbital Combat", orbitalCombatFleets
        )

        # Generate combat narrative events for orbital combat (Phase 7a)
        processCombatEvents(
          state, systemId, orbitalCombatOutcome, "OrbitalCombat", events
        )
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
  var survivingSquadronIds: Table[SquadronId, CombatSquadron] =
    initTable[SquadronId, CombatSquadron]()
  for tf in outcome.survivors:
    for combatSq in tf.squadrons:
      survivingSquadronIds[combatSq.squadronId] = combatSq

  # Collect surviving facilities by ID
  var survivingFacilityIds: Table[StarbaseId, combat.CombatFacility] =
    initTable[StarbaseId, combat.CombatFacility]()
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

    var survivingSquadronIdsForFleet: seq[SquadronId] = @[]

    # Iterate over squadron IDs and update entities
    for squadronId in fleet.squadrons:
      if squadronId in survivingSquadronIds:
        # Squadron survived - update crippled status in entity table
        let squadronOpt = state.squadron(squadronId)
        if squadronOpt.isSome:
          let survivorState = survivingSquadronIds[squadronId]
          var updatedSquadron = squadronOpt.get()

          # Update flagship's crippled status
          let flagshipOpt = state.ship(updatedSquadron.flagshipId)
          if flagshipOpt.isSome:
            var updatedFlagship = flagshipOpt.get()
            updatedFlagship.isCrippled = (survivorState.state == CombatState.Crippled)
            state.updateShip(updatedSquadron.flagshipId, updatedFlagship)

          state.updateSquadron(squadronId, updatedSquadron)
          survivingSquadronIdsForFleet.add(squadronId)
      else:
        # Squadron destroyed - log before removal
        let squadronOpt = state.squadron(squadronId)
        if squadronOpt.isSome:
          let squadron = squadronOpt.get()
          let flagshipOpt = state.ship(squadron.flagshipId)
          if flagshipOpt.isSome:
            let flagship = flagshipOpt.get()
            logCombat(
              "Squadron destroyed",
              "id=",
              $squadronId,
              " class=",
              $flagship.shipClass,
            )

    # Update fleet with surviving squadron IDs, or remove if none survived (using entity_manager)
    if survivingSquadronIdsForFleet.len > 0:
      let updatedFleet = Fleet(
        squadrons: survivingSquadronIdsForFleet,
        id: fleet.id,
        houseId: fleet.houseId,
        location: fleet.location,
        status: fleet.status, # Preserve status (Active/Reserve)
        autoBalanceSquadrons: fleet.autoBalanceSquadrons, # Preserve balancing setting
      )
      state.updateFleet(fleetId, updatedFleet)
    else:
      # Fleet destroyed - remove fleet and clean up orders
      # Remove from bySystem index
      if state.fleets.bySystem.hasKey(fleet.location):
        state.fleets.bySystem[fleet.location] =
          state.fleets.bySystem[fleet.location].filterIt(it != fleetId)
        if state.fleets.bySystem[fleet.location].len == 0:
          state.fleets.bySystem.del(fleet.location)

      # Remove from byOwner index
      if state.fleets.byOwner.hasKey(fleet.houseId):
        state.fleets.byOwner[fleet.houseId] =
          state.fleets.byOwner[fleet.houseId].filterIt(it != fleetId)
        if state.fleets.byOwner[fleet.houseId].len == 0:
          state.fleets.byOwner.del(fleet.houseId)

      # Remove from entity manager
      state.delFleet(fleetId)
      if fleetId in state.fleetCommands:
        state.fleetCommands.del(fleetId)
      if fleetId in state.standingCommands:
        state.standingCommands.del(fleetId)
      logInfo(
        "Combat",
        "Removed empty fleet " & $fleetId & " after combat (all squadrons destroyed)",
      )

  # Apply spacelift ship screening losses (proportional to task force casualties)
  # Spacelift ships are screened by task forces in both space and orbital combat
  if outcome.totalRounds > 0:
    let combatPhaseDesc =
      if spaceCombatOutcome.totalRounds > 0 and orbitalCombatOutcome.totalRounds > 0:
        "Space+Orbital"
      elif spaceCombatOutcome.totalRounds > 0:
        "Space"
      else:
        "Orbital"

    applySpaceLiftScreeningLosses(
      state, outcome, fleetsBeforeCombatUpdate, combatPhaseDesc, events
    )

  # Check if all defenders eliminated - if so, destroy mothballed ships
  # Per economy.md:3.9 - mothballed ships are vulnerable if no Task Force defends them
  if systemOwner.isSome:
    let defendingHouse = systemOwner.get()

    # Check if defending house has any surviving active/reserve squadrons
    var defenderHasSurvivors = false
    for tf in outcome.survivors:
      if tf.houseId == defendingHouse and tf.squadrons.len > 0:
        defenderHasSurvivors = true
        break

    # If no defenders survived at friendly colony, destroy screened units
    # Per operations.md - mothballed ships and spacelift ships vulnerable if no orbital units defend them
    if not defenderHasSurvivors:
      var mothballedFleetsDestroyed = 0
      var mothballedSquadronsDestroyed = 0

      for (fleetId, fleet) in fleetsAtSystem:
        if fleet.houseId == defendingHouse:
          # Skip fleets that were already destroyed in combat (using entity_manager)
          if state.fleet(fleetId).isNone:
            continue

          # Destroy mothballed ships
          if fleet.status == FleetStatus.Mothballed:
            mothballedSquadronsDestroyed += fleet.squadrons.len
            mothballedFleetsDestroyed += 1
            # Destroy the fleet by removing all squadrons (using entity_manager)
            let emptyFleet = Fleet(
              squadrons: @[], # Empty fleet
              id: fleet.id,
              houseId: fleet.houseId,
              location: fleet.location,
              status: FleetStatus.Mothballed,
              autoBalanceSquadrons: fleet.autoBalanceSquadrons, # Preserve setting
            )
            state.updateFleet(fleetId, emptyFleet)

      if mothballedFleetsDestroyed > 0:
        logCombat(
          "Mothballed fleets destroyed - no orbital defense remains",
          "squadrons=",
          $mothballedSquadronsDestroyed,
          " fleets=",
          $mothballedFleetsDestroyed,
        )
        events.add(
          event_factory.battle(
            defendingHouse,
            systemId,
            &"Orbital defenses eliminated: {mothballedFleetsDestroyed} mothballed fleets destroyed " &
              &"({mothballedSquadronsDestroyed} squadrons)",
          )
        )

      # Destroy screened orbital facilities (spaceports, shipyards, drydocks)
      # These facilities are protected by orbital defenses - if defenses are eliminated, they're destroyed
      let colonyOpt = state.colonyBySystem(systemId)
      if colonyOpt.isSome:
        var colony = colonyOpt.get()
        var facilitiesDestroyed = 0
        var shipsUnderConstructionLost = 0
        var shipsUnderRepairLost = 0

        # Destroy spaceports
        if colony.spaceportIds.len > 0:
          facilitiesDestroyed += colony.spaceportIds.len
          logCombat(
            "Spaceports destroyed - no orbital defense remains",
            "spaceports=",
            $colony.spaceportIds.len,
            " systemId=",
            $systemId,
          )
          colony.spaceportIds = @[]

        # Destroy shipyards and clear their construction/repair queues
        if colony.shipyardIds.len > 0:
          facilitiesDestroyed += colony.shipyardIds.len
          logCombat(
            "Shipyards destroyed - no orbital defense remains",
            "shipyards=",
            $colony.shipyardIds.len,
            " systemId=",
            $systemId,
          )

          # Count ships under construction in shipyard docks
          if colony.underConstruction.isSome:
            let projectId = colony.underConstruction.get()
            let projectOpt = state.constructionProject(projectId)
            if projectOpt.isSome:
              let project = projectOpt.get()
              if project.facilityType.isSome and
                  project.facilityType.get() == econ_types.FacilityClass.Shipyard:
                shipsUnderConstructionLost += 1

          # Count ships under repair in shipyard docks
          for repairId in colony.repairQueue:
            let repairOpt = state.repairProject(repairId)
            if repairOpt.isSome:
              let repair = repairOpt.get()
              if repair.facilityType == econ_types.FacilityClass.Shipyard:
                shipsUnderRepairLost += 1

          # Clear all shipyard construction/repair queues
          facility_damage.clearFacilityQueues(colony, econ_types.FacilityClass.Shipyard, state)
          colony.shipyardIds = @[]

        # Destroy drydocks and clear their repair queues
        if colony.drydockIds.len > 0:
          facilitiesDestroyed += colony.drydockIds.len
          logCombat(
            "Drydocks destroyed - no orbital defense remains",
            "drydocks=",
            $colony.drydockIds.len,
            " systemId=",
            $systemId,
          )

          # Count ships under repair in drydock docks
          for repairId in colony.repairQueue:
            let repairOpt = state.repairProject(repairId)
            if repairOpt.isSome:
              let repair = repairOpt.get()
              if repair.facilityType == econ_types.FacilityClass.Drydock:
                shipsUnderRepairLost += 1

          # Clear all drydock repair queues
          facility_damage.clearFacilityQueues(colony, econ_types.FacilityClass.Drydock, state)
          colony.drydockIds = @[]

        # Clear construction queue if no facilities remain
        if colony.spaceportIds.len == 0 and colony.shipyardIds.len == 0:
          facility_damage.clearAllConstructionQueues(colony, state)

        # Update colony with destroyed facilities (using entity_manager)
        let colonyId = state.colonies.bySystem[systemId]
        state.updateColony(colonyId, colony)
    
        # Generate events for screened facility destruction
        if facilitiesDestroyed > 0:
          events.add(
            event_factory.battle(
              defendingHouse,
              systemId,
              &"Orbital defenses eliminated: {facilitiesDestroyed} facilities destroyed, " &
                &"{shipsUnderConstructionLost} ships under construction lost, " &
                &"{shipsUnderRepairLost} ships under repair lost",
            )
          )

  # Update starbases at colony based on survivors
  if systemOwner.isSome:
    let colonyOpt = state.colonyBySystem(systemId)
    if colonyOpt.isSome:
      let colonyId = state.colonies.bySystem[systemId]
      var colony = colonyOpt.get()
      var survivingKastraIds: seq[KastraId] = @[]

      # Iterate over kastra IDs and update entities
      for kastraId in colony.kastraIds:
        if kastraId in survivingFacilityIds:
          # Kastra survived - update crippled status in entity table
          let kastraOpt = state.kastra(kastraId)
          if kastraOpt.isSome:
            let survivorState = survivingFacilityIds[kastraId]
            var updatedKastra = kastraOpt.get()
            updatedKastra.isCrippled = (survivorState.state == combat.CombatState.Crippled)
            state.updateKastra(kastraId, updatedKastra)
            survivingKastraIds.add(kastraId)
        else:
          # Kastra destroyed - log before removal
          logCombat("Kastra destroyed", "id=", $kastraId, " systemId=", $systemId)

      colony.kastraIds = survivingKastraIds
      state.updateColony(colonyId, colony)

  # Update unassigned squadrons at colony based on survivors
  if systemOwner.isSome:
    let colonyOpt = state.colonyBySystem(systemId)
    if colonyOpt.isSome:
      let colonyId = state.colonies.bySystem[systemId]
      var colony = colonyOpt.get()
      var survivingUnassignedIds: seq[SquadronId] = @[]

      # Iterate over squadron IDs and update entities
      for squadronId in colony.unassignedSquadronIds:
        if squadronId in survivingSquadronIds:
          # Squadron survived - update crippled status in entity table
          let squadronOpt = state.squadron(squadronId)
          if squadronOpt.isSome:
            let survivorState = survivingSquadronIds[squadronId]
            var updatedSquadron = squadronOpt.get()
            let flagshipOpt = state.ship(updatedSquadron.flagshipId)
            if flagshipOpt.isSome:
              var updatedFlagship = flagshipOpt.get()
              updatedFlagship.isCrippled = (survivorState.state == CombatState.Crippled)
              state.updateShip(updatedSquadron.flagshipId, updatedFlagship)
            state.updateSquadron(squadronId, updatedSquadron)
            survivingUnassignedIds.add(squadronId)
        else:
          # Unassigned squadron destroyed - log before removal
          let squadronOpt = state.squadron(squadronId)
          if squadronOpt.isSome:
            let squadron = squadronOpt.get()
            let flagshipOpt = state.ship(squadron.flagshipId)
            if flagshipOpt.isSome:
              let flagship = flagshipOpt.get()
              logCombat(
                "Unassigned squadron destroyed",
                "id=",
                $squadronId,
                " class=",
                $flagship.shipClass,
              )

      colony.unassignedSquadronIds = survivingUnassignedIds
      state.updateColony(colonyId, colony)

  # INTELLIGENCE: Update combat reports with post-combat outcomes
  # Update for Space Combat phase if it occurred
  if spaceCombatOutcome.totalRounds > 0:
    let spaceFleetsAfterCombat = spaceCombatFleets.toTable()
    combat_intel.updatePostCombatIntelligence(
      state,
      systemId,
      intel_types.CombatPhase.Space,
      spaceCombatFleets,
      spaceFleetsAfterCombat,
      spaceCombatOutcome.retreated,
      spaceCombatOutcome.victor,
    )

  # Update for Orbital Combat phase if it occurred
  if orbitalCombatOutcome.totalRounds > 0:
    let orbitalFleetsAfterCombat = orbitalCombatFleets.toTable()
    combat_intel.updatePostCombatIntelligence(
      state,
      systemId,
      intel_types.CombatPhase.Orbital,
      orbitalCombatFleets,
      orbitalFleetsAfterCombat,
      orbitalCombatOutcome.retreated,
      orbitalCombatOutcome.victor,
    )

  # 5.5. Process retreated fleets - auto-assign Seek Home orders
  # Fleets that retreated from combat automatically receive Order 02 (Seek Home)
  # to find the nearest friendly colony and regroup
  if outcome.retreated.len > 0:
    logCombat(
      "Processing retreated fleets - auto-assigning Seek Home orders",
      "count=",
      $outcome.retreated.len,
    )

    for houseId in outcome.retreated:
      # Find all fleets belonging to this house at the battle location
      # Use fleetsAtSystemForHouseWithId iterator (using iterators)
      for (fleetId, fleet) in state.fleetsAtSystemForHouseWithId(systemId, houseId):
        # Find closest owned colony for retreat destination
        let safeDestination = findClosestOwnedColony(state, fleet.location, fleet.houseId)

        if safeDestination.isSome:
          logDebug(
            "Combat",
            "Fleet retreated - auto-assigning Seek Home",
            "fleetId=",
            $fleetId,
            " houseId=",
            $houseId,
            " destination=",
            $safeDestination.get(),
          )

          # Create Seek Home order for this fleet
          # NOTE: This creates an "in-flight" movement that will be processed immediately
          # The fleet will begin its retreat movement in the same turn
          let seekHomeOrder = FleetCommand(
            fleetId: fleetId,
            commandType: FleetCommandType.SeekHome,
            targetSystem: safeDestination,
            targetFleet: none(FleetId),
            priority: 0,
            roe: none(int32),
          )

          # Execute the seek home movement immediately (fleet retreats in same turn)
          resolveMovementCommand(state, houseId, seekHomeOrder, events)

          events.add(
            event_factory.battle(
              houseId,
              systemId,
              "Fleet " & $fleetId &
                " retreated from combat - seeking nearest friendly system " &
                $safeDestination.get(),
            )
          )
        else:
          logWarn(
            "Combat",
            "Fleet retreated but has no safe destination - holding position",
            "fleetId=",
            $fleetId,
            " houseId=",
            $houseId,
          )
          # No safe colonies - fleet holds at retreat location (will be resolved by movement system)
          events.add(
            event_factory.battle(
              houseId,
              systemId,
              "Fleet " & $fleetId &
                " retreated from combat but has no friendly colonies - holding position",
            )
          )

  # 6. Determine attacker and defender houses for reporting
  var attackerHouses: seq[HouseId] = @[]
  var defenderHouses: seq[HouseId] = @[]
  var allHouses: seq[HouseId] = @[]

  for (fleetId, fleet) in fleetsAtSystem:
    if fleet.houseId notin allHouses:
      allHouses.add(fleet.houseId)
      if systemOwner.isSome and systemOwner.get() == fleet.houseId:
        defenderHouses.add(fleet.houseId)
      else:
        attackerHouses.add(fleet.houseId)

  # 7. Count losses by house
  var houseLosses: Table[HouseId, int] = initTable[HouseId, int]()
  # Count total squadrons before combat (all fleets at system)
  for houseId in allHouses:
    var totalSquadrons = 0
    for (fleetId, fleet) in fleetsAtSystem:
      if fleet.houseId == houseId:
        totalSquadrons += fleet.squadrons.len

    # Add starbases and unassigned squadrons to defender's total
    if systemOwner.isSome and systemOwner.get() == houseId:
      let colonyOpt = state.colonyBySystem(systemId)
      if colonyOpt.isSome:
        let colony = colonyOpt.get()
        totalSquadrons += colony.kastraIds.len
        totalSquadrons += colony.unassignedSquadronIds.len

    let survivingSquadrons = outcome.survivors
      .filterIt(it.houseId == houseId)
      .mapIt(it.squadrons.len)
      .foldl(a + b, 0)
    houseLosses[houseId] = totalSquadrons - survivingSquadrons

  # 8. Generate combat report
  let victor = outcome.victor
  let attackerLosses =
    if attackerHouses.len > 0:
      attackerHouses.mapIt(houseLosses.getOrDefault(it, 0)).foldl(a + b, 0)
    else:
      0
  let defenderLosses =
    if defenderHouses.len > 0:
      defenderHouses.mapIt(houseLosses.getOrDefault(it, 0)).foldl(a + b, 0)
    else:
      0

  let report = combat.CombatReport(
    systemId: systemId,
    attackers: attackerHouses,
    defenders: defenderHouses,
    attackerLosses: int32(attackerLosses),
    defenderLosses: int32(defenderLosses),
    victor: victor,
  )
  combatReports.add(report)

  # Award prestige for combat (ZERO-SUM: victor gains, losers lose)
  if victor.isSome:
    let victorHouse = victor.get()

    # Combat victory prestige (zero-sum)
    let victorPrestige = prestige_engine.applyPrestigeMultiplier(
      prestige_sources.getPrestigeValue(PrestigeSource.CombatVictory)
    )
    let victoryEvent = prestige_events.createPrestigeEvent(
      PrestigeSource.CombatVictory, victorPrestige, "Won battle at " & $systemId
    )
    prestige_app.applyPrestigeEvent(state, victorHouse, victoryEvent)
    let victorHouseOpt = state.house(victorHouse)
    let victorHouseName =
      if victorHouseOpt.isSome: victorHouseOpt.get().name else: "Unknown"
    logCombat(
      "Combat victory prestige awarded",
      "house=",
      victorHouseName,
      " prestige=",
      $victorPrestige,
    )

    # Apply penalty to losing houses (zero-sum)
    let loserHouses =
      if victorHouse in attackerHouses: defenderHouses else: attackerHouses
    for loserHouse in loserHouses:
      let defeatEvent = prestige_events.createPrestigeEvent(
        PrestigeSource.CombatVictory, -victorPrestige, "Lost battle at " & $systemId
      )
      prestige_app.applyPrestigeEvent(state, loserHouse, defeatEvent)
      let loserHouseOpt = state.house(loserHouse)
      let loserHouseName =
        if loserHouseOpt.isSome: loserHouseOpt.get().name else: "Unknown"
      logCombat(
        "Combat defeat prestige penalty",
        "house=",
        loserHouseName,
        " prestige=",
        $(-victorPrestige),
      )

    # Squadron destruction prestige (zero-sum)
    let enemyLosses =
      if victorHouse in attackerHouses: defenderLosses else: attackerLosses
    if enemyLosses > 0:
      let squadronPrestige =
        prestige_engine.applyPrestigeMultiplier(
          prestige_sources.getPrestigeValue(PrestigeSource.SquadronDestroyed)
        ) * enemyLosses
      let squadronDestructionEvent = prestige_events.createPrestigeEvent(
        PrestigeSource.SquadronDestroyed,
        int32(squadronPrestige),
        "Destroyed " & $enemyLosses & " enemy squadrons at " & $systemId,
      )
      prestige_app.applyPrestigeEvent(state, victorHouse, squadronDestructionEvent)
      # Re-use victorHouseName from earlier
      logCombat(
        "Squadron destruction prestige awarded",
        "house=",
        victorHouseName,
        " squadrons=",
        $enemyLosses,
        " prestige=",
        $squadronPrestige,
      )

      # Apply penalty to houses that lost squadrons (zero-sum)
      for loserHouse in loserHouses:
        let squadronLossEvent = prestige_events.createPrestigeEvent(
          PrestigeSource.SquadronDestroyed,
          -int32(squadronPrestige),
          "Lost " & $enemyLosses & " squadrons at " & $systemId,
        )
        prestige_app.applyPrestigeEvent(state, loserHouse, squadronLossEvent)
        let loserHouseOpt2 = state.house(loserHouse)
        let loserHouseName2 =
          if loserHouseOpt2.isSome: loserHouseOpt2.get().name else: "Unknown"
        logCombat(
          "Squadron loss prestige penalty",
          "house=",
          loserHouseName2,
          " squadrons=",
          $enemyLosses,
          " prestige=",
          $(-squadronPrestige),
        )

  # Generate event (using entity_manager)
  var victorName = "No one"
  if victor.isSome:
    let houseOpt = state.house(victor.get())
    if houseOpt.isSome:
      victorName = houseOpt.get().name
    else:
      victorName = "Unknown Victor"

  let systemIdStr = $systemId
  let battleDesc = "Battle at " & systemIdStr & ". Victor: " & victorName
  events.add(
    event_factory.battle(
      if victor.isSome:
        victor.get()
      else:
        HouseId(0),
      systemId,
      battleDesc,
    )
  )

  logCombat("Battle complete", "victor=", victorName)
