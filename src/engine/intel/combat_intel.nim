## Combat Intelligence Report Generation
##
## Generates detailed intelligence reports from combat encounters
## Includes pre-combat composition and post-combat outcomes

import std/[tables, options, sequtils, strformat]
import types as intel_types
import ../../common/logger
import ../gamestate, ../fleet, ../squadron

proc createFleetComposition*(
  state: GameState,
  fleet: Fleet,
  fleetId: FleetId
): intel_types.CombatFleetComposition =
  ## Create detailed fleet composition intel from combat encounter
  ## This captures squadron composition and standing commands

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

  # Get fleet's standing commands (if any)
  var orderIntel: Option[intel_types.FleetOrderIntel] = none(intel_types.FleetOrderIntel)
  if fleetId in state.fleetCommands:
    let order = state.fleetCommands[fleetId]
    orderIntel = some(intel_types.FleetOrderIntel(
      orderType: $order.commandType,
      targetSystem: order.targetSystem
    ))

  # Capture Expansion/Auxiliary squadron cargo details (CRITICAL for invasion threat assessment)
  var spaceLiftIntel: seq[intel_types.SpaceLiftCargoIntel] = @[]
  for squadron in fleet.squadrons:
    if squadron.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
      let cargo = squadron.flagship.cargo
      let cargoQty = if cargo.isSome: cargo.get().quantity else: 0
      let cargoTypeStr = if cargoQty == 0:
        "Empty"
      else:
        $cargo.get().cargoType

      spaceLiftIntel.add(intel_types.SpaceLiftCargoIntel(
        shipClass: $squadron.flagship.shipClass,
        cargoType: cargoTypeStr,
        quantity: cargoQty,
        isCrippled: squadron.flagship.isCrippled
      ))

  result = intel_types.CombatFleetComposition(
    fleetId: fleetId,
    owner: fleet.owner,
    standingOrders: orderIntel,
    squadrons: squadronDetails,
    spaceLiftShips: spaceLiftIntel,  # Note: field name unchanged (refers to transport squadrons)
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

proc generateBlitzIntelligence*(
  state: var GameState,
  systemId: SystemId,
  attackingHouse: HouseId,
  defendingHouse: HouseId,
  attackingMarines: int,
  defendingArmies: int,
  defendingMarines: int,
  blitzSuccess: bool,
  attackerCasualties: int,
  defenderCasualties: int,
  batteriesDestroyed: int
) =
  ## Generate intelligence reports for planetary blitz assault
  ## Both attacker and defender receive detailed after-action reports
  ##
  ## Blitz reports emphasize assets seized INTACT (key difference from invasion)
  ##
  ## Blitz reports include:
  ## - Force composition (marines vs armies/marines)
  ## - Planetary defenses (shields, batteries, spaceports)
  ## - Battle outcome (success/failure)
  ## - Casualties on both sides
  ## - Assets seized INTACT (no infrastructure/IU damage on success)
  ## - Surviving/captured assets post-blitz

  let turn = state.turn

  # Get post-blitz colony state for asset reporting
  var assetInfo: seq[string] = @[]
  if systemId in state.colonies:
    let colony = state.colonies[systemId]
    if blitzSuccess:
      # Successful blitz - emphasize ALL assets seized INTACT
      assetInfo.add("--- Assets Seized INTACT ---")
      assetInfo.add(&"Infrastructure: {colony.infrastructure} levels (NO DAMAGE)")
      assetInfo.add(&"Industrial: {colony.industrial.units} IU (NO DAMAGE)")
      assetInfo.add(&"Population: {colony.population} PU")
      assetInfo.add(&"Garrison: {colony.marines} Marines")
      if colony.planetaryShieldLevel > 0:
        assetInfo.add(&"Shields: SLD{colony.planetaryShieldLevel} (INTACT)")
      if colony.groundBatteries > 0:
        assetInfo.add(&"Ground Batteries: {colony.groundBatteries} (INTACT)")
      if colony.spaceports.len > 0:
        assetInfo.add(&"Spaceports: {colony.spaceports.len} (INTACT)")
    else:
      # Failed blitz - defender shows surviving assets
      assetInfo.add("--- Surviving Assets ---")
      assetInfo.add(&"Infrastructure: {colony.infrastructure} levels")
      assetInfo.add(&"Industrial: {colony.industrial.units} IU")
      assetInfo.add(&"Population: {colony.population} PU")
      assetInfo.add(&"Defense: {colony.armies} Armies, {colony.marines} Marines")
      if batteriesDestroyed > 0:
        assetInfo.add(&"Ground Batteries: {colony.groundBatteries} ({batteriesDestroyed} destroyed in bombardment)")
      else:
        assetInfo.add(&"Ground Batteries: {colony.groundBatteries}")

  # Attacker's blitz report
  let attackerOutcome = if blitzSuccess:
    intel_types.CombatOutcome.Victory
  else:
    intel_types.CombatOutcome.Defeat

  var attackerInfo: seq[string] = @[]
  attackerInfo.add((0..<attackerCasualties).mapIt("Marine"))
  if blitzSuccess:
    attackerInfo.add("Blitz successful - all assets seized intact")
  attackerInfo.add(assetInfo)

  let attackerReport = intel_types.CombatEncounterReport(
    reportId: &"{attackingHouse}-blitz-{turn}-{systemId}",
    turn: turn,
    systemId: systemId,
    phase: intel_types.CombatPhase.Planetary,
    reportingHouse: attackingHouse,
    alliedForces: @[],  # Ground forces, not fleets
    enemyForces: @[],
    outcome: attackerOutcome,
    alliedLosses: attackerInfo,
    enemyLosses: (0..<defenderCasualties).mapIt(
      if it < defendingArmies: "Army" else: "Marine"
    ),
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: true  # Blitz fleet survives
  )

  # CRITICAL: Get, modify, write back to persist
  var attackerHouse = state.houses[attackingHouse]
  attackerHouse.intelligence.addCombatReport(attackerReport)
  state.houses[attackingHouse] = attackerHouse

  # Defender's blitz report (mirror perspective)
  let defenderOutcome = if blitzSuccess:
    intel_types.CombatOutcome.Defeat
  else:
    intel_types.CombatOutcome.Victory

  var defenderInfo: seq[string] = @[]
  defenderInfo.add((0..<defenderCasualties).mapIt(
    if it < defendingArmies: "Army" else: "Marine"
  ))
  if blitzSuccess:
    defenderInfo.add("Colony seized by blitz - all assets captured intact")
  else:
    defenderInfo.add("Blitz repelled - all attacking marines destroyed")
  defenderInfo.add(assetInfo)

  let defenderReport = intel_types.CombatEncounterReport(
    reportId: &"{defendingHouse}-defense-{turn}-{systemId}",
    turn: turn,
    systemId: systemId,
    phase: intel_types.CombatPhase.Planetary,
    reportingHouse: defendingHouse,
    alliedForces: @[],
    enemyForces: @[],
    outcome: defenderOutcome,
    alliedLosses: defenderInfo,
    enemyLosses: (0..<attackerCasualties).mapIt("Marine"),
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: true  # Defending colony survives (may change hands)
  )

  # CRITICAL: Get, modify, write back to persist
  var defenderHouse = state.houses[defendingHouse]
  defenderHouse.intelligence.addCombatReport(defenderReport)
  state.houses[defendingHouse] = defenderHouse

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
  defenderCasualties: int,
  industrialUnitsDestroyed: int
) =
  ## Generate intelligence reports for planetary invasion
  ## Both attacker and defender receive detailed after-action reports
  ##
  ## Invasion reports include:
  ## - Force composition (marines vs armies/marines)
  ## - Planetary defenses (shields, batteries, spaceports)
  ## - Battle outcome (success/failure)
  ## - Casualties on both sides
  ## - Infrastructure and industrial damage (on success)
  ## - Surviving/captured assets post-invasion

  let turn = state.turn

  # Get post-invasion colony state for asset reporting
  var assetInfo: seq[string] = @[]
  if systemId in state.colonies:
    let colony = state.colonies[systemId]
    if invasionSuccess:
      # Successful invasion - show captured assets
      assetInfo.add("--- Assets Seized ---")
      assetInfo.add(&"Infrastructure: {colony.infrastructure} levels (50% destroyed)")
      assetInfo.add(&"Industrial: {colony.industrial.units} IU ({industrialUnitsDestroyed} IU destroyed)")
      assetInfo.add(&"Population: {colony.population} PU")
      assetInfo.add(&"Garrison: {colony.marines} Marines")
      if colony.planetaryShieldLevel > 0:
        assetInfo.add(&"Shields: SLD{colony.planetaryShieldLevel}")
    else:
      # Failed invasion - defender shows surviving assets
      assetInfo.add("--- Surviving Assets ---")
      assetInfo.add(&"Infrastructure: {colony.infrastructure} levels")
      assetInfo.add(&"Industrial: {colony.industrial.units} IU")
      assetInfo.add(&"Population: {colony.population} PU")
      assetInfo.add(&"Defense: {colony.armies} Armies, {colony.marines} Marines")
      assetInfo.add(&"Ground Batteries: {colony.groundBatteries}")

  # Attacker's invasion report
  let attackerOutcome = if invasionSuccess:
    intel_types.CombatOutcome.Victory
  else:
    intel_types.CombatOutcome.Defeat

  var attackerInfo: seq[string] = @[]
  attackerInfo.add((0..<attackerCasualties).mapIt("Marine"))
  if invasionSuccess and industrialUnitsDestroyed > 0:
    attackerInfo.add(&"{industrialUnitsDestroyed} IU destroyed in fighting")
  attackerInfo.add(assetInfo)

  let attackerReport = intel_types.CombatEncounterReport(
    reportId: &"{attackingHouse}-invasion-{turn}-{systemId}",
    turn: turn,
    systemId: systemId,
    phase: intel_types.CombatPhase.Planetary,
    reportingHouse: attackingHouse,
    alliedForces: @[],  # Ground forces, not fleets
    enemyForces: @[],
    outcome: attackerOutcome,
    alliedLosses: attackerInfo,
    enemyLosses: (0..<defenderCasualties).mapIt(
      if it < defendingArmies: "Army" else: "Marine"
    ),
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: true  # Invading fleet survives (marines may not)
  )

  # CRITICAL: Get, modify, write back to persist
  var attackerHouse = state.houses[attackingHouse]
  attackerHouse.intelligence.addCombatReport(attackerReport)
  state.houses[attackingHouse] = attackerHouse

  # Defender's invasion report (mirror perspective)
  let defenderOutcome = if invasionSuccess:
    intel_types.CombatOutcome.Defeat
  else:
    intel_types.CombatOutcome.Victory

  var defenderInfo: seq[string] = @[]
  defenderInfo.add((0..<defenderCasualties).mapIt(
    if it < defendingArmies: "Army" else: "Marine"
  ))
  if invasionSuccess and industrialUnitsDestroyed > 0:
    defenderInfo.add(&"{industrialUnitsDestroyed} IU destroyed")
    defenderInfo.add("50% infrastructure destroyed")
    defenderInfo.add("Shields and spaceports destroyed")
  defenderInfo.add(assetInfo)

  let defenderReport = intel_types.CombatEncounterReport(
    reportId: &"{defendingHouse}-defense-{turn}-{systemId}",
    turn: turn,
    systemId: systemId,
    phase: intel_types.CombatPhase.Planetary,
    reportingHouse: defendingHouse,
    alliedForces: @[],
    enemyForces: @[],
    outcome: defenderOutcome,
    alliedLosses: defenderInfo,
    enemyLosses: (0..<attackerCasualties).mapIt("Marine"),
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: not invasionSuccess  # Defender survives if repelled invasion
  )

  # CRITICAL: Get, modify, write back to persist
  var defenderHouse = state.houses[defendingHouse]
  defenderHouse.intelligence.addCombatReport(defenderReport)
  state.houses[defendingHouse] = defenderHouse

proc generateBombardmentIntelligence*(
  state: var GameState,
  systemId: SystemId,
  attackingHouse: HouseId,
  attackingFleetId: FleetId,
  defendingHouse: HouseId,
  infrastructureDamaged: int,
  industrialUnitsDestroyed: int,
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
  ## - Infrastructure levels damaged
  ## - Industrial capacity (IU) destroyed
  ## - Planetary defenses status (shields, batteries)
  ## - Ground forces/population casualties (PU)
  ## - Whether invasion force is present (transport squadrons detected)

  let turn = state.turn

  # Get attacking fleet composition for intel
  var attackingFleetComposition: seq[intel_types.CombatFleetComposition] = @[]
  if attackingFleetId in state.fleets:
    let fleet = state.fleets[attackingFleetId]
    attackingFleetComposition.add(createFleetComposition(state, fleet, attackingFleetId))

  # Get post-bombardment colony state for surviving assets intel
  var survivingAssets: seq[string] = @[]
  if systemId in state.colonies:
    let colony = state.colonies[systemId]
    survivingAssets.add(&"Infrastructure: {colony.infrastructure} levels")
    survivingAssets.add(&"Industrial: {colony.industrial.units} IU")
    survivingAssets.add(&"Population: {colony.population} PU")
    survivingAssets.add(&"Ground Batteries: {colony.groundBatteries}")
    if colony.planetaryShieldLevel > 0:
      survivingAssets.add(&"Shields: SLD{colony.planetaryShieldLevel}")

  # Attacker's bombardment report (they know exactly what they did)
  var attackerEnemyLosses = @[
    &"{infrastructureDamaged} infrastructure levels destroyed",
    &"{industrialUnitsDestroyed} IU destroyed",
    &"{groundBatteriesDestroyed} ground batteries destroyed",
    &"{groundForcesKilled} PU casualties",
    "--- Surviving Enemy Assets ---"
  ]
  attackerEnemyLosses.add(survivingAssets)

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
    enemyLosses: attackerEnemyLosses,
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: true
  )

  # CRITICAL: Get, modify, write back to persist
  var attackerHouse = state.houses[attackingHouse]
  attackerHouse.intelligence.addCombatReport(attackerReport)
  state.houses[attackingHouse] = attackerHouse

  # Defender's bombardment report (knows they're being bombarded)
  var defenderAlliedLosses = @[
    &"{infrastructureDamaged} infrastructure levels destroyed",
    &"{industrialUnitsDestroyed} IU destroyed",
    &"{groundBatteriesDestroyed} ground batteries destroyed",
    &"{groundForcesKilled} PU casualties",
    "--- Surviving Assets ---"
  ]
  defenderAlliedLosses.add(survivingAssets)

  let defenderReport = intel_types.CombatEncounterReport(
    reportId: &"{defendingHouse}-bombardment-defense-{turn}-{systemId}",
    turn: turn,
    systemId: systemId,
    phase: intel_types.CombatPhase.Orbital,
    reportingHouse: defendingHouse,
    alliedForces: @[],  # Ground forces (no fleet composition for defenders)
    enemyForces: attackingFleetComposition,  # Defender can see attacking fleet
    outcome: intel_types.CombatOutcome.Defeat,  # Being bombarded
    alliedLosses: defenderAlliedLosses,
    enemyLosses: @[],  # Bombardment doesn't damage attacking fleet
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: infrastructureDamaged < 100  # Colony survives unless completely destroyed
  )

  # CRITICAL: Get, modify, write back to persist
  var defenderHouse = state.houses[defendingHouse]
  defenderHouse.intelligence.addCombatReport(defenderReport)
  state.houses[defendingHouse] = defenderHouse

  # THREAT ASSESSMENT: If transport squadrons detected, invasion is imminent
  if spaceLiftShipsInvolved > 0:
    logWarn("Intelligence", "CRITICAL: Invasion force detected",
            "transportSquadrons=", $spaceLiftShipsInvolved, " system=", $systemId)
