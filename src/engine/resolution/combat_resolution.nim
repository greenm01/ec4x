## Combat resolution system - Battle, bombardment, invasion, and blitz operations
##
## This module handles all combat-related resolution including:
## - Space battles with linear progression (space combat -> orbital combat)
## - Orbital bombardment of planetary defenses
## - Ground invasions of enemy colonies
## - Blitz operations (fast insertion variant)
## - Retreat processing and automated Seek Home

import std/[tables, algorithm, options, sequtils, hashes, math]
import ../../common/[hex, types/core, types/combat, types/units]
import ../gamestate, ../orders, ../fleet, ../squadron, ../starmap, ../spacelift
import ../combat/[engine as combat_engine, types as combat_types, ground]
import ../economy/[types as econ_types]
import ../config/[prestige_config, military_config, ground_units_config]
import ../prestige
import ./types  # Common resolution types
import ./fleet_orders  # For findClosestOwnedColony, resolveMovementOrder
import ../intelligence/[types as intel_types, combat_intel]

proc getTargetBucket(shipClass: ShipClass): TargetBucket =
  ## Determine target bucket from ship class
  case shipClass
  of ShipClass.Raider: TargetBucket.Raider
  of ShipClass.Fighter: TargetBucket.Fighter
  of ShipClass.Destroyer: TargetBucket.Destroyer
  of ShipClass.Starbase: TargetBucket.Starbase
  else: TargetBucket.Capital

proc executeCombat(
  state: var GameState,
  systemId: SystemId,
  fleetsInCombat: seq[(FleetId, Fleet)],
  systemOwner: Option[HouseId],
  includeStarbases: bool,
  includeUnassignedSquadrons: bool,
  combatPhase: string,
  preDetectedHouses: seq[HouseId] = @[]
): tuple[outcome: CombatResult, fleetsAtSystem: seq[(FleetId, Fleet)], detectedHouses: seq[HouseId]] =
  ## Helper function to execute a combat phase
  ## Returns combat outcome, fleets that participated, and newly detected cloaked houses
  ## preDetectedHouses: Houses already detected in previous combat phase

  if fleetsInCombat.len < 2:
    return (CombatResult(), @[], @[])

  echo "        ", combatPhase, " - ", fleetsInCombat.len, " fleets engaged"

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
        echo "          Fleet ", fleet.id, " is mothballed - screened from combat"
        continue

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
          echo "          Added ", colony.unassignedSquadrons.len, " unassigned squadron(s) to orbital defense"

    # Add starbases for system owner (always included for detection)
    # Starbases are ALWAYS included in task forces for detection purposes
    # In space combat: Starbases detect but don't fight (controlled by allowStarbaseCombat flag)
    # In orbital combat: Starbases detect AND fight
    if systemOwner.isSome and systemOwner.get() == houseId:
      if systemId in state.colonies:
        let colony = state.colonies[systemId]
        for starbase in colony.starbases:
          # Convert Starbase to Squadron-like structure for combat
          # Starbases are treated as special squadrons with fixed installations
          # Create EnhancedShip from Starbase using stats from config/ships.toml
          # TODO: Load stats from config instead of hardcoding (requires GameConfig in GameState)
          let starbaseShip = EnhancedShip(
            shipClass: ShipClass.Starbase,
            shipType: ShipType.Military,
            stats: ShipStats(
              attackStrength: 45,   # From config/ships.toml [starbase]
              defenseStrength: 50,  # From config/ships.toml [starbase]
              commandCost: 0,
              commandRating: 0,
              techLevel: 0
            ),
            isCrippled: starbase.isCrippled,
            name: "Starbase-" & starbase.id
          )

          let starbaseSquadron = Squadron(
            id: starbase.id,
            flagship: starbaseShip,
            ships: @[],  # Starbases have no escort ships
            owner: houseId,
            location: systemId,
            embarkedFighters: @[]
          )
          let combatSq = CombatSquadron(
            squadron: starbaseSquadron,
            state: if starbase.isCrippled: CombatState.Crippled else: CombatState.Undamaged,
            fleetStatus: FleetStatus.Active,  # Always active for detection
            damageThisTurn: 0,
            crippleRound: 0,
            bucket: TargetBucket.Starbase,
            targetWeight: 1.0
          )
          combatSquadrons.add(combatSq)
        if colony.starbases.len > 0:
          let combatRole = if includeStarbases: "defense and detection" else: "detection only"
          echo "          Added ", colony.starbases.len, " starbase(s) for ", combatRole

    # Create TaskForce for this house
    taskForces[houseId] = TaskForce(
      house: houseId,
      squadrons: combatSquadrons,
      roe: 5,  # Default ROE
      isCloaked: false,
      moraleModifier: 0,
      scoutBonus: false,
      isDefendingHomeworld: false
    )

  # Collect all task forces for battle
  var allTaskForces: seq[TaskForce] = @[]
  for houseId, tf in taskForces:
    allTaskForces.add(tf)

  # Generate deterministic seed
  let deterministicSeed = hash((state.turn, systemId, combatPhase)).int64

  # Determine if ambush bonuses and starbase combat apply
  # Ambush (+4 CER) only in space combat, NOT orbital combat
  # Starbases can fight only in orbital combat, NOT space combat (but always detect)
  let allowAmbush = (combatPhase == "Space Combat")
  let allowStarbaseCombat = (combatPhase == "Orbital Combat" or includeStarbases)

  var battleContext = BattleContext(
    systemId: systemId,
    taskForces: allTaskForces,
    seed: deterministicSeed,
    maxRounds: 20,
    allowAmbush: allowAmbush,
    allowStarbaseCombat: allowStarbaseCombat,
    preDetectedHouses: preDetectedHouses
  )

  # Execute battle
  let outcome = combat_engine.resolveCombat(battleContext)

  # Track detected houses (any that were cloaked but are now detected)
  var detectedHouses: seq[HouseId] = @[]
  for tf in outcome.survivors:
    # If house had Raiders but is no longer cloaked, they were detected
    if not tf.isCloaked:
      detectedHouses.add(tf.house)

  return (outcome, fleetsInCombat, detectedHouses)

proc resolveBattle*(state: var GameState, systemId: SystemId,
                  orders: Table[HouseId, OrderPacket],
                  combatReports: var seq[CombatReport], events: var seq[GameEvent]) =
  ## Resolve combat at a system with linear progression (operations.md:7.0)
  ## Phase 1: Space Combat - non-guard mobile fleets fight first
  ## Phase 2: Orbital Combat - if attackers survive, fight guard/reserve fleets + starbases
  ## Uses orders to determine which fleets are on guard duty
  echo "    Combat at ", systemId

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
  echo "      Phase 1: Space Combat"
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
      "Space Combat",
      preDetectedHouses = @[]  # No pre-detection in space combat (first phase)
    )
    spaceCombatOutcome = outcome
    spaceCombatFleets = fleets
    detectedInSpace = detected

    # Track which attacker houses survived
    for tf in outcome.survivors:
      if tf.house != systemOwner.get() and tf.house notin spaceCombatSurvivors:
        spaceCombatSurvivors.add(tf.house)

    echo "          Space combat complete - ", spaceCombatOutcome.totalRounds, " rounds"
    echo "          ", spaceCombatSurvivors.len, " attacking house(s) survived"
    if detectedInSpace.len > 0:
      echo "          ", detectedInSpace.len, " cloaked house(s) detected"
  elif attackingFleets.len > 0:
    # No mobile defenders - attackers proceed directly to orbital combat
    echo "          No space combat (no mobile defenders)"
    # All attackers advance to orbital combat
    for (fleetId, fleet) in attackingFleets:
      if fleet.owner notin spaceCombatSurvivors:
        spaceCombatSurvivors.add(fleet.owner)
  else:
    echo "          No space combat (no attackers)"

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
      echo "      Phase 2: Orbital Combat"

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
          preDetectedHouses = detectedInSpace  # Pass detection state from space combat
        )
        orbitalCombatOutcome = outcome
        orbitalCombatFleets = fleets
        echo "          Orbital combat complete - ", orbitalCombatOutcome.totalRounds, " rounds"
        if detected.len > detectedInSpace.len:
          echo "          ", (detected.len - detectedInSpace.len), " additional house(s) detected in orbital phase"
      else:
        echo "          No surviving attacker fleets for orbital combat"
    else:
      echo "      Phase 2: No orbital combat (no orbital defenders)"
      # Attackers achieved orbital supremacy without a fight
  elif systemOwner.isSome and spaceCombatSurvivors.len == 0:
    echo "      Phase 2: No orbital combat (attackers eliminated in space combat)"
  else:
    echo "      Phase 2: No orbital combat (no colony)"

  # 5. Apply losses to game state
  # Combine outcomes from both combat phases
  var allCombatFleets = spaceCombatFleets & orbitalCombatFleets
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

    # Update fleet with surviving squadrons, or remove if none survived
    if updatedSquadrons.len > 0:
      state.fleets[fleetId] = Fleet(
        squadrons: updatedSquadrons,
        spaceLiftShips: fleet.spaceLiftShips,
        id: fleet.id,
        owner: fleet.owner,
        location: fleet.location,
        status: fleet.status  # Preserve status (Active/Reserve)
      )
    else:
      # Fleet destroyed
      state.fleets.del(fleetId)

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
      var spaceliftShipsDestroyed = 0

      for (fleetId, fleet) in fleetsAtSystem:
        if fleet.owner == defendingHouse:
          # Skip fleets that were already destroyed in combat
          if fleetId notin state.fleets:
            continue

          # Destroy mothballed ships
          if fleet.status == FleetStatus.Mothballed:
            mothballedSquadronsDestroyed += fleet.squadrons.len
            mothballedFleetsDestroyed += 1
            # Destroy the fleet by removing all squadrons
            state.fleets[fleetId] = Fleet(
              squadrons: @[],  # Empty fleet
              spaceLiftShips: @[],
              id: fleet.id,
              owner: fleet.owner,
              location: fleet.location,
              status: FleetStatus.Mothballed
            )

          # Destroy spacelift ships in any fleet (they were screened by orbital units)
          if fleet.spaceLiftShips.len > 0:
            spaceliftShipsDestroyed += fleet.spaceLiftShips.len
            # Remove spacelift ships from fleet (check again as fleet might have been emptied above)
            if fleetId in state.fleets:
              var updatedFleet = state.fleets[fleetId]
              updatedFleet.spaceLiftShips = @[]
              state.fleets[fleetId] = updatedFleet

      if mothballedFleetsDestroyed > 0:
        echo "      ", mothballedSquadronsDestroyed, " mothballed squadron(s) in ",
             mothballedFleetsDestroyed, " fleet(s) destroyed - no orbital defense remains"

      if spaceliftShipsDestroyed > 0:
        echo "      ", spaceliftShipsDestroyed, " spacelift ship(s) destroyed - no orbital defense remains"

  # Update starbases at colony based on survivors
  if systemOwner.isSome and systemId in state.colonies:
    var colony = state.colonies[systemId]
    var survivingStarbases: seq[Starbase] = @[]
    for starbase in colony.starbases:
      if starbase.id in survivingSquadronIds:
        # Starbase survived - update crippled status
        let survivorState = survivingSquadronIds[starbase.id]
        var updatedStarbase = starbase
        updatedStarbase.isCrippled = (survivorState.state == CombatState.Crippled)
        survivingStarbases.add(updatedStarbase)
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
    echo "      Processing retreated fleets - auto-assigning Seek Home orders"

    for houseId in outcome.retreated:
      # Find all fleets belonging to this house at the battle location
      for fleetId, fleet in state.fleets:
        if fleet.owner == houseId and fleet.location == systemId:
          # Find closest owned colony for retreat destination
          let safeDestination = findClosestOwnedColony(state, fleet.location, fleet.owner)

          if safeDestination.isSome:
            echo "        Fleet ", fleetId, " (", houseId, ") retreated - auto-assigning Seek Home to system ", safeDestination.get()

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

            events.add(GameEvent(
              eventType: GameEventType.Battle,
              houseId: houseId,
              description: "Fleet " & fleetId & " retreated from combat - seeking nearest friendly system " & $safeDestination.get(),
              systemId: some(systemId)
            ))
          else:
            echo "        Fleet ", fleetId, " (", houseId, ") retreated but has no safe destination - holding position"
            # No safe colonies - fleet holds at retreat location (will be resolved by movement system)
            events.add(GameEvent(
              eventType: GameEventType.Battle,
              houseId: houseId,
              description: "Fleet " & fleetId & " retreated from combat but has no friendly colonies - holding position",
              systemId: some(systemId)
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

  # Award prestige for combat
  if victor.isSome:
    let victorHouse = victor.get()
    let victorPrestige = getPrestigeValue(PrestigeSource.CombatVictory)
    state.houses[victorHouse].prestige += victorPrestige
    echo "      ", state.houses[victorHouse].name, " victory (+", victorPrestige, " prestige)"

    # Award prestige for squadrons destroyed
    let enemyLosses = if victorHouse in attackerHouses: defenderLosses else: attackerLosses
    if enemyLosses > 0:
      let squadronPrestige = getPrestigeValue(PrestigeSource.SquadronDestroyed) * enemyLosses
      state.houses[victorHouse].prestige += squadronPrestige
      echo "      ", state.houses[victorHouse].name, " destroyed ", enemyLosses, " squadrons (+", squadronPrestige, " prestige)"

  # Generate event
  let victorName = if victor.isSome: state.houses[victor.get()].name else: "No one"
  events.add(GameEvent(
    eventType: GameEventType.Battle,
    houseId: if victor.isSome: victor.get() else: "",
    description: "Battle at " & $systemId & ". Victor: " & victorName,
    systemId: some(systemId)
  ))

  echo "      Battle complete. Victor: ", victorName

proc resolveBombardment*(state: var GameState, houseId: HouseId, order: FleetOrder,
                       events: var seq[GameEvent]) =
  ## Process planetary bombardment order (operations.md:7.5)
  ## Phase 2 of planetary combat - requires orbital supremacy
  ## Attacks planetary shields, ground batteries, and infrastructure

  if order.targetSystem.isNone:
    return

  let targetId = order.targetSystem.get()

  # Validate fleet exists and is at target
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    echo "      Bombardment failed: fleet not found"
    return

  let fleet = fleetOpt.get()
  if fleet.location != targetId:
    echo "      Bombardment failed: fleet not at target system"
    return

  # Validate target colony exists
  if targetId notin state.colonies:
    echo "      Bombardment failed: no colony at target"
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

  # Ships-in-dock destruction (economy.md:5.0)
  var shipsDestroyedInDock = false
  if infrastructureLoss > 0 and updatedColony.underConstruction.isSome:
    let project = updatedColony.underConstruction.get()
    if project.projectType == econ_types.ConstructionType.Ship:
      updatedColony.underConstruction = none(econ_types.ConstructionProject)
      shipsDestroyedInDock = true
      echo "      Ship under construction destroyed in bombardment!"

  state.colonies[targetId] = updatedColony

  echo "      Bombardment at ", targetId, ": ", infrastructureLoss, " infrastructure destroyed"

  # Generate intelligence reports for both attacker and defender
  let groundForcesKilled = result.populationDamage  # Population damage represents casualties
  combat_intel.generateBombardmentIntelligence(
    state,
    targetId,
    houseId,  # Attacking house
    order.fleetId,
    colony.owner,  # Defending house
    infrastructureLoss,
    defense.shields.isSome,  # Were shields active?
    result.batteriesDestroyed,
    groundForcesKilled,
    fleet.spaceLiftShips.len  # Invasion threat assessment
  )

  # Generate event
  var eventDesc = "Bombarded system " & $targetId & ", destroyed " & $infrastructureLoss & " infrastructure"
  if shipsDestroyedInDock:
    eventDesc &= " (ship under construction destroyed)"

  events.add(GameEvent(
    eventType: GameEventType.Bombardment,
    houseId: houseId,
    description: eventDesc,
    systemId: some(targetId)
  ))
proc resolveInvasion*(state: var GameState, houseId: HouseId, order: FleetOrder,
                    events: var seq[GameEvent]) =
  ## Process planetary invasion order (operations.md:7.6)
  ## Phase 3 of planetary combat - requires all ground batteries destroyed
  ## Marines attack ground forces to capture colony

  if order.targetSystem.isNone:
    return

  let targetId = order.targetSystem.get()

  # Validate fleet exists and is at target
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    echo "      Invasion failed: fleet not found"
    return

  let fleet = fleetOpt.get()
  if fleet.location != targetId:
    echo "      Invasion failed: fleet not at target system"
    return

  # Validate target colony exists
  if targetId notin state.colonies:
    echo "      Invasion failed: no colony at target"
    return

  let colony = state.colonies[targetId]

  # Check if colony belongs to attacker (can't invade your own colony)
  if colony.owner == houseId:
    echo "      Invasion failed: cannot invade your own colony"
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
    echo "      Invasion failed: no marines in fleet"
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
    echo "      Invasion failed: ", defense.groundBatteries.len, " ground batteries still operational (bombardment required first)"
    return

  # Ground forces already added above
  defense.groundForces = defendingForces

  # Spaceport
  defense.spaceport = colony.spaceports.len > 0

  # Generate deterministic seed
  let invasionSeed = hash((state.turn, targetId, houseId)).int64

  # Conduct invasion
  let result = conductInvasion(attackingForces, defendingForces, defense, invasionSeed)

  # INTELLIGENCE: Generate invasion reports for both houses
  combat_intel.generateInvasionIntelligence(
    state, targetId, houseId, colony.owner,
    attackingForces.len,
    colony.armies,
    colony.marines,
    result.success,
    result.attackerCasualties.len,
    result.defenderCasualties.len
  )

  # Apply results
  var updatedColony = colony

  if result.success:
    # Invasion succeeded - colony captured
    echo "      Invasion SUCCESS: ", houseId, " captured ", targetId, " from ", colony.owner

    # Transfer ownership
    updatedColony.owner = houseId

    # Apply infrastructure damage (50% destroyed per operations.md:7.6.2)
    updatedColony.infrastructure = updatedColony.infrastructure div 2

    # Shields and spaceports destroyed on landing (per spec)
    updatedColony.planetaryShieldLevel = 0
    updatedColony.spaceports = @[]

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

    # Prestige changes
    let attackerPrestige = getPrestigeValue(PrestigeSource.ColonySeized)
    state.houses[houseId].prestige += attackerPrestige
    echo "      ", houseId, " gains ", attackerPrestige, " prestige for capturing colony"

    # Defender loses prestige for colony loss
    let defenderPenalty = -attackerPrestige  # Equal but opposite
    state.houses[colony.owner].prestige += defenderPenalty
    echo "      ", colony.owner, " loses ", -defenderPenalty, " prestige for losing colony"

    # Generate event
    events.add(GameEvent(
      eventType: GameEventType.SystemCaptured,
      houseId: houseId,
      description: houseId & " captured colony at " & $targetId & " from " & colony.owner,
      systemId: some(targetId)
    ))
  else:
    # Invasion failed - ALL attacking marines destroyed (no retreat from ground combat)
    echo "      Invasion FAILED: ", colony.owner, " repelled ", houseId, " invasion at ", targetId
    echo "      All ", attackingForces.len, " attacking marine divisions destroyed"

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
    events.add(GameEvent(
      eventType: GameEventType.InvasionRepelled,
      houseId: colony.owner,
      description: colony.owner & " repelled " & houseId & " invasion at " & $targetId & " - all attacking marines destroyed",
      systemId: some(targetId)
    ))

  state.colonies[targetId] = updatedColony

proc resolveBlitz*(state: var GameState, houseId: HouseId, order: FleetOrder,
                 events: var seq[GameEvent]) =
  ## Process planetary blitz order (operations.md:7.6.2)
  ## Fast insertion variant - seizes assets intact but marines get 0.5x AS penalty
  ## Transports vulnerable to ground batteries during insertion

  if order.targetSystem.isNone:
    return

  let targetId = order.targetSystem.get()

  # Validate fleet exists and is at target
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    echo "      Blitz failed: fleet not found"
    return

  let fleet = fleetOpt.get()
  if fleet.location != targetId:
    echo "      Blitz failed: fleet not at target system"
    return

  # Validate target colony exists
  if targetId notin state.colonies:
    echo "      Blitz failed: no colony at target"
    return

  let colony = state.colonies[targetId]

  # Check if colony belongs to attacker
  if colony.owner == houseId:
    echo "      Blitz failed: cannot blitz your own colony"
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
    echo "      Blitz failed: no marines in fleet"
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

  # Conduct blitz
  let result = conductBlitz(attackingFleet, attackingForces, defense, blitzSeed)

  # Apply results
  var updatedColony = colony

  if result.success:
    # Blitz succeeded - colony captured with assets intact
    echo "      Blitz SUCCESS: ", houseId, " captured ", targetId, " from ", colony.owner, " (assets seized)"

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

    # Prestige changes (blitz gets same prestige as invasion)
    let attackerPrestige = getPrestigeValue(PrestigeSource.ColonySeized)
    state.houses[houseId].prestige += attackerPrestige
    echo "      ", houseId, " gains ", attackerPrestige, " prestige for blitzing colony"

    # Defender loses prestige for colony loss
    let defenderPenalty = -attackerPrestige
    state.houses[colony.owner].prestige += defenderPenalty
    echo "      ", colony.owner, " loses ", -defenderPenalty, " prestige for losing colony"

    # Generate event
    events.add(GameEvent(
      eventType: GameEventType.ColonyCaptured,
      houseId: houseId,
      description: houseId & " blitzed colony at " & $targetId & " from " & colony.owner & " (assets seized)",
      systemId: some(targetId)
    ))
  else:
    # Blitz failed - ALL attacking marines destroyed (no retreat from ground combat)
    echo "      Blitz FAILED: ", colony.owner, " repelled ", houseId, " blitz at ", targetId
    echo "      All ", attackingForces.len, " attacking marine divisions destroyed"

    # Update defender ground forces
    let survivingDefenders = defendingForces.len - result.defenderCasualties.len
    let totalDefenders = colony.armies + colony.marines
    if totalDefenders > 0:
      let armyFraction = float(colony.armies) / float(totalDefenders)
      updatedColony.armies = int(float(survivingDefenders) * armyFraction)
      updatedColony.marines = survivingDefenders - updatedColony.armies

    # Update ground batteries (some may have been destroyed)
    # TODO: Track which batteries were destroyed in blitz result

    # All attacker marines destroyed - unload ALL marines from spacelift ships
    # Marines cannot retreat once they've landed on the planet
    var updatedFleet = state.fleets[order.fleetId]
    for ship in updatedFleet.spaceLiftShips.mitems:
      if ship.cargo.cargoType == CargoType.Marines:
        discard ship.unloadCargo()  # Remove all marines (destroyed in combat)
    state.fleets[order.fleetId] = updatedFleet

    # Generate event
    events.add(GameEvent(
      eventType: GameEventType.InvasionRepelled,
      houseId: colony.owner,
      description: colony.owner & " repelled " & houseId & " blitz at " & $targetId & " - all attacking marines destroyed",
      systemId: some(targetId)
    ))

  state.colonies[targetId] = updatedColony
