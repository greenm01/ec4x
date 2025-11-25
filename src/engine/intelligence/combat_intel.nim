## Combat Intelligence Report Generation
##
## Generates detailed intelligence reports from combat encounters
## Includes pre-combat composition and post-combat outcomes

import std/[tables, options, sequtils, strformat]
import types as intel_types
import ../gamestate, ../fleet, ../squadron, ../spacelift

proc createFleetComposition*(
  state: GameState,
  fleet: Fleet,
  fleetId: FleetId
): intel_types.CombatFleetComposition =
  ## Create detailed fleet composition intel from combat encounter
  ## This captures squadron composition and standing orders

  var squadronDetails: seq[intel_types.SquadronIntel] = @[]

  # Capture all squadrons in fleet
  for squadron in fleet.squadrons:
    let squadIntel = intel_types.SquadronIntel(
      squadronId: squadron.id,
      shipClass: $squadron.flagship.shipClass,
      shipCount: 1 + squadron.ships.len,  # Flagship + escorts
      techLevel: squadron.flagship.stats.techLevel,
      hullIntegrity: if squadron.flagship.isCrippled: some(50) else: some(100)
    )
    squadronDetails.add(squadIntel)

  # Get fleet's standing orders (if any)
  var orderIntel: Option[intel_types.FleetOrderIntel] = none(intel_types.FleetOrderIntel)
  if fleetId in state.fleetOrders:
    let order = state.fleetOrders[fleetId]
    orderIntel = some(intel_types.FleetOrderIntel(
      orderType: $order.orderType,
      targetSystem: order.targetSystem
    ))

  # Capture spacelift cargo details (CRITICAL for invasion threat assessment)
  var spaceLiftIntel: seq[intel_types.SpaceLiftCargoIntel] = @[]
  for ship in fleet.spaceLiftShips:
    let cargoTypeStr = if ship.cargo.quantity == 0:
      "Empty"
    else:
      $ship.cargo.cargoType

    spaceLiftIntel.add(intel_types.SpaceLiftCargoIntel(
      shipClass: $ship.shipClass,
      cargoType: cargoTypeStr,
      quantity: ship.cargo.quantity,
      isCrippled: ship.isCrippled
    ))

  result = intel_types.CombatFleetComposition(
    fleetId: fleetId,
    owner: fleet.owner,
    standingOrders: orderIntel,
    squadrons: squadronDetails,
    spaceLiftShips: spaceLiftIntel,
    isCloaked: fleet.isCloaked()
  )

proc generatePreCombatReport*(
  state: GameState,
  systemId: SystemId,
  phase: intel_types.CombatPhase,
  reportingHouse: HouseId,
  alliedFleets: seq[FleetId],
  enemyFleets: seq[FleetId]
): intel_types.CombatEncounterReport =
  ## Generate pre-combat intelligence report
  ## Called when combat is about to begin - captures initial force composition

  var alliedCompositions: seq[intel_types.CombatFleetComposition] = @[]
  var enemyCompositions: seq[intel_types.CombatFleetComposition] = @[]

  # Gather allied fleet compositions
  for fleetId in alliedFleets:
    if fleetId in state.fleets:
      let fleet = state.fleets[fleetId]
      alliedCompositions.add(createFleetComposition(state, fleet, fleetId))

  # Gather enemy fleet compositions (detailed intel from combat encounter)
  for fleetId in enemyFleets:
    if fleetId in state.fleets:
      let fleet = state.fleets[fleetId]
      enemyCompositions.add(createFleetComposition(state, fleet, fleetId))

  let reportId = &"{reportingHouse}-combat-{state.turn}-{systemId}"

  result = intel_types.CombatEncounterReport(
    reportId: reportId,
    turn: state.turn,
    systemId: systemId,
    phase: phase,
    reportingHouse: reportingHouse,
    alliedForces: alliedCompositions,
    enemyForces: enemyCompositions,
    outcome: intel_types.CombatOutcome.Ongoing,
    alliedLosses: @[],
    enemyLosses: @[],
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: true  # Pre-combat report always survives
  )

proc updateCombatReportOutcome*(
  report: var intel_types.CombatEncounterReport,
  outcome: intel_types.CombatOutcome,
  alliedLosses: seq[string],
  enemyLosses: seq[string],
  retreatedAllies: seq[FleetId],
  retreatedEnemies: seq[FleetId],
  survived: bool
) =
  ## Update combat report with post-combat outcome data
  ## Called after combat resolution to add losses and retreats
  report.outcome = outcome
  report.alliedLosses = alliedLosses
  report.enemyLosses = enemyLosses
  report.retreatedAllies = retreatedAllies
  report.retreatedEnemies = retreatedEnemies
  report.survived = survived

proc updatePostCombatIntelligence*(
  state: var GameState,
  systemId: SystemId,
  phase: intel_types.CombatPhase,
  fleetsBeforeCombat: seq[(FleetId, Fleet)],
  fleetsAfterCombat: Table[FleetId, Fleet],
  retreatedHouses: seq[HouseId],
  victorHouse: Option[HouseId]
) =
  ## Update all houses' combat reports with post-combat intelligence
  ## Compares fleet state before/after to determine losses
  ## Each house gets outcome from their perspective

  # Track which fleets belonged to which house
  var houseFleetsBefore: Table[HouseId, seq[FleetId]] = initTable[HouseId, seq[FleetId]]()
  for (fleetId, fleet) in fleetsBeforeCombat:
    if fleet.owner notin houseFleetsBefore:
      houseFleetsBefore[fleet.owner] = @[]
    houseFleetsBefore[fleet.owner].add(fleetId)

  # Update each house's latest combat report
  for houseId in houseFleetsBefore.keys:
    # Find most recent combat report for this system/phase
    var reportIdx = -1
    for i in countdown(state.houses[houseId].intelligence.combatReports.len - 1, 0):
      let report = state.houses[houseId].intelligence.combatReports[i]
      if report.systemId == systemId and report.phase == phase:
        reportIdx = i
        break

    if reportIdx < 0:
      continue  # No report found (shouldn't happen)

    var report = state.houses[houseId].intelligence.combatReports[reportIdx]

    # Determine outcome from this house's perspective
    let survived = houseId notin retreatedHouses
    var outcome = intel_types.CombatOutcome.Ongoing

    if victorHouse.isSome:
      if victorHouse.get() == houseId:
        outcome = intel_types.CombatOutcome.Victory
      else:
        if houseId in retreatedHouses:
          outcome = intel_types.CombatOutcome.Retreat
        else:
          outcome = intel_types.CombatOutcome.Defeat
    elif houseId in retreatedHouses:
      # Check if all houses retreated
      if retreatedHouses.len == houseFleetsBefore.len:
        outcome = intel_types.CombatOutcome.MutualRetreat
      else:
        outcome = intel_types.CombatOutcome.Retreat

    # Calculate losses (squadrons that didn't survive)
    var alliedLosses: seq[string] = @[]
    var enemyLosses: seq[string] = @[]

    for (fleetId, fleetBefore) in fleetsBeforeCombat:
      let squadronsBefore = fleetBefore.squadrons.len
      var squadronsAfter = 0

      if fleetId in fleetsAfterCombat:
        squadronsAfter = fleetsAfterCombat[fleetId].squadrons.len

      let lossCount = squadronsBefore - squadronsAfter
      if lossCount > 0:
        # Record losses as ship class names
        for i in 0..<lossCount:
          let lostShipClass = if i < fleetBefore.squadrons.len:
            $fleetBefore.squadrons[i].flagship.shipClass
          else:
            "Unknown"

          if fleetBefore.owner == houseId:
            alliedLosses.add(lostShipClass)
          else:
            enemyLosses.add(lostShipClass)

    # Determine which fleets retreated
    var retreatedAllies: seq[FleetId] = @[]
    var retreatedEnemies: seq[FleetId] = @[]

    if houseId in retreatedHouses:
      for fleetId in houseFleetsBefore.getOrDefault(houseId):
        retreatedAllies.add(fleetId)

    for otherHouse in retreatedHouses:
      if otherHouse != houseId:
        for fleetId in houseFleetsBefore.getOrDefault(otherHouse):
          retreatedEnemies.add(fleetId)

    # Update report with outcome
    report.outcome = outcome
    report.alliedLosses = alliedLosses
    report.enemyLosses = enemyLosses
    report.retreatedAllies = retreatedAllies
    report.retreatedEnemies = retreatedEnemies
    report.survived = survived

    # Save updated report
    state.houses[houseId].intelligence.combatReports[reportIdx] = report

proc generateInvasionIntelligence*(
  state: var GameState,
  systemId: SystemId,
  attackingHouse: HouseId,
  defendingHouse: HouseId,
  attackingMarines: int,
  defendingArmies: int,
  defendingMarines: int,
  invasionSuccess: bool,
  attackerCasualties: int,
  defenderCasualties: int
) =
  ## Generate intelligence reports for planetary invasion
  ## Both attacker and defender receive detailed after-action reports
  ##
  ## Invasion reports include:
  ## - Force composition (marines vs armies/marines)
  ## - Planetary defenses (shields, batteries, spaceports)
  ## - Battle outcome (success/failure)
  ## - Casualties on both sides

  let turn = state.turn

  # Attacker's invasion report
  let attackerOutcome = if invasionSuccess:
    intel_types.CombatOutcome.Victory
  else:
    intel_types.CombatOutcome.Defeat

  let attackerReport = intel_types.CombatEncounterReport(
    reportId: &"{attackingHouse}-invasion-{turn}-{systemId}",
    turn: turn,
    systemId: systemId,
    phase: intel_types.CombatPhase.Planetary,
    reportingHouse: attackingHouse,
    alliedForces: @[],  # Ground forces, not fleets
    enemyForces: @[],
    outcome: attackerOutcome,
    alliedLosses: (0..<attackerCasualties).mapIt("Marine"),
    enemyLosses: (0..<defenderCasualties).mapIt(
      if it < defendingArmies: "Army" else: "Marine"
    ),
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: true  # Invading fleet survives (marines may not)
  )

  state.houses[attackingHouse].intelligence.addCombatReport(attackerReport)

  # Defender's invasion report (mirror perspective)
  let defenderOutcome = if invasionSuccess:
    intel_types.CombatOutcome.Defeat
  else:
    intel_types.CombatOutcome.Victory

  let defenderReport = intel_types.CombatEncounterReport(
    reportId: &"{defendingHouse}-defense-{turn}-{systemId}",
    turn: turn,
    systemId: systemId,
    phase: intel_types.CombatPhase.Planetary,
    reportingHouse: defendingHouse,
    alliedForces: @[],
    enemyForces: @[],
    outcome: defenderOutcome,
    alliedLosses: (0..<defenderCasualties).mapIt(
      if it < defendingArmies: "Army" else: "Marine"
    ),
    enemyLosses: (0..<attackerCasualties).mapIt("Marine"),
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: not invasionSuccess  # Defender survives if repelled invasion
  )

  state.houses[defendingHouse].intelligence.addCombatReport(defenderReport)

proc generateBombardmentIntelligence*(
  state: var GameState,
  systemId: SystemId,
  attackingHouse: HouseId,
  attackingFleetId: FleetId,
  defendingHouse: HouseId,
  infrastructureDamaged: int,
  shieldsActive: bool,
  groundBatteriesDestroyed: int,
  groundForcesKilled: int,
  spaceLiftShipsInvolved: int
) =
  ## Generate intelligence reports for planetary bombardment
  ## Both attacker and defender receive detailed reports
  ##
  ## Bombardment reports include:
  ## - Attacking fleet composition
  ## - Infrastructure damage dealt
  ## - Planetary defenses status (shields, batteries)
  ## - Ground forces casualties
  ## - Whether invasion force is present (spacelift ships detected)

  let turn = state.turn

  # Get attacking fleet composition for intel
  var attackingFleetComposition: seq[intel_types.CombatFleetComposition] = @[]
  if attackingFleetId in state.fleets:
    let fleet = state.fleets[attackingFleetId]
    attackingFleetComposition.add(createFleetComposition(state, fleet, attackingFleetId))

  # Attacker's bombardment report (they know exactly what they did)
  let attackerReport = intel_types.CombatEncounterReport(
    reportId: &"{attackingHouse}-bombardment-{turn}-{systemId}",
    turn: turn,
    systemId: systemId,
    phase: intel_types.CombatPhase.Orbital,
    reportingHouse: attackingHouse,
    alliedForces: attackingFleetComposition,
    enemyForces: @[],  # Can't see ground defenses from orbit (except what's destroyed)
    outcome: intel_types.CombatOutcome.Victory,  # Bombardment always "succeeds" if executed
    alliedLosses: @[],  # Bombardment doesn't lose ships
    enemyLosses: @[
      &"{infrastructureDamaged} infrastructure destroyed",
      &"{groundBatteriesDestroyed} ground batteries destroyed",
      &"{groundForcesKilled} ground forces killed"
    ],
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: true
  )

  state.houses[attackingHouse].intelligence.addCombatReport(attackerReport)

  # Defender's bombardment report (knows they're being bombarded)
  let defenderReport = intel_types.CombatEncounterReport(
    reportId: &"{defendingHouse}-bombardment-defense-{turn}-{systemId}",
    turn: turn,
    systemId: systemId,
    phase: intel_types.CombatPhase.Orbital,
    reportingHouse: defendingHouse,
    alliedForces: @[],  # Ground forces (no fleet composition for defenders)
    enemyForces: attackingFleetComposition,  # Defender can see attacking fleet
    outcome: intel_types.CombatOutcome.Defeat,  # Being bombarded
    alliedLosses: @[
      &"{infrastructureDamaged} infrastructure destroyed",
      &"{groundBatteriesDestroyed} ground batteries destroyed",
      &"{groundForcesKilled} ground forces killed"
    ],
    enemyLosses: @[],  # Bombardment doesn't damage attacking fleet
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: infrastructureDamaged < 100  # Colony survives unless completely destroyed
  )

  state.houses[defendingHouse].intelligence.addCombatReport(defenderReport)

  # THREAT ASSESSMENT: If spacelift ships detected, invasion is imminent
  if spaceLiftShipsInvolved > 0:
    echo "    CRITICAL INTEL: ", spaceLiftShipsInvolved, " spacelift ships detected - invasion force present!"
