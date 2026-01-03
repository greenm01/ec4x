## Combat Intelligence Report Generation
##
## Generates detailed intelligence reports from combat encounters
## Includes pre-combat composition and post-combat outcomes
##
## **Architecture Role:** Business logic (like @systems modules)
## - Reads from @state using safe accessors
## - Writes using Table read-modify-write pattern

import std/[tables, options, sequtils, strformat]
import ../../common/logger
import ../state/engine
import ../types/[core, game_state, intel, fleet, squadron]

proc createFleetComposition*(
    state: GameState, fleet: Fleet, fleetId: FleetId
): CombatFleetComposition =
  ## Create fleet composition intel from combat encounter
  ## Stores squadron IDs, not full details (lookup separately via FleetIntel)

  # Collect squadron IDs
  var squadronIds: seq[SquadronId] = fleet.squadrons
  var spaceLiftSquadronIds: seq[SquadronId] = @[]

  # Track space-lift capable squadrons separately
  for squadronId in fleet.squadrons:
    let squadronOpt = state.squadron(squadronId)
    if squadronOpt.isSome:
      let squadron = squadronOpt.get()
      if squadron.squadronType in {SquadronClass.Expansion, SquadronClass.Auxiliary}:
        spaceLiftSquadronIds.add(squadronId)

  # Get fleet's standing commands (if any)
  var orderIntel: Option[FleetOrderIntel] = none(FleetOrderIntel)
  if fleet.command.isSome:
    let command = fleet.command.get()
    orderIntel = some(
      FleetOrderIntel(
        orderType: $command.commandType,
        targetSystem: command.targetSystem
      )
    )

  result = CombatFleetComposition(
    fleetId: fleetId,
    owner: fleet.houseId,
    standingOrders: orderIntel,
    squadronIds: squadronIds,
    spaceLiftSquadronIds: spaceLiftSquadronIds,
    isCloaked: false, # TODO: Implement cloaking detection logic
  )

proc generatePreCombatReport*(
    state: GameState,
    systemId: SystemId,
    phase: CombatPhase,
    reportingHouse: HouseId,
    alliedFleets: seq[FleetId],
    enemyFleets: seq[FleetId],
): CombatEncounterReport =
  ## Generate pre-combat intelligence report
  ## Called when combat is about to begin - captures initial force composition

  let reportId = &"{reportingHouse}-combat-{state.turn}-{systemId}"

  result = CombatEncounterReport(
    reportId: reportId,
    turn: state.turn,
    systemId: systemId,
    phase: phase,
    reportingHouse: reportingHouse,
    alliedFleetIds: alliedFleets,
    enemyFleetIds: enemyFleets,
    outcome: CombatOutcome.Ongoing,
    alliedLosses: @[],
    enemyLosses: @[],
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: true, # Pre-combat report always survives
  )

proc updateCombatReportOutcome*(
    report: var CombatEncounterReport,
    outcome: CombatOutcome,
    alliedLosses: seq[SquadronId],
    enemyLosses: seq[string],
    retreatedAllies: seq[FleetId],
    retreatedEnemies: seq[FleetId],
    survived: bool,
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
    phase: CombatPhase,
    fleetsBeforeCombat: seq[(FleetId, Fleet)],
    fleetsAfterCombat: Table[FleetId, Fleet],
    retreatedHouses: seq[HouseId],
    victorHouse: Option[HouseId],
) =
  ## Update all houses' combat reports with post-combat intelligence
  ## Compares fleet state before/after to determine losses
  ## Each house gets outcome from their perspective

  # Track which fleets belonged to which house
  var houseFleetsBefore: Table[HouseId, seq[FleetId]] =
    initTable[HouseId, seq[FleetId]]()
  for (fleetId, fleet) in fleetsBeforeCombat:
    if fleet.houseId notin houseFleetsBefore:
      houseFleetsBefore[fleet.houseId] = @[]
    houseFleetsBefore[fleet.houseId].add(fleetId)

  # Update each house's latest combat report
  for houseId in houseFleetsBefore.keys:
    # Get intelligence database (Table read-modify-write)
    if not state.intelligence.contains(houseId):
      continue # No intelligence database for this house

    var intel = state.intelligence[houseId]

    # Find most recent combat report for this system/phase
    var reportIdx = -1
    for i in countdown(intel.combatReports.len - 1, 0):
      let report = intel.combatReports[i]
      if report.systemId == systemId and report.phase == phase:
        reportIdx = i
        break

    if reportIdx < 0:
      continue # No report found (shouldn't happen)

    var report = intel.combatReports[reportIdx]

    # Determine outcome from this house's perspective
    let survived = houseId notin retreatedHouses
    var outcome = CombatOutcome.Ongoing

    if victorHouse.isSome:
      if victorHouse.get() == houseId:
        outcome = CombatOutcome.Victory
      else:
        if houseId in retreatedHouses:
          outcome = CombatOutcome.Retreat
        else:
          outcome = CombatOutcome.Defeat
    elif houseId in retreatedHouses:
      # Check if all houses retreated
      if retreatedHouses.len == houseFleetsBefore.len:
        outcome = CombatOutcome.MutualRetreat
      else:
        outcome = CombatOutcome.Retreat

    # Calculate losses (SquadronIds for allies, ship classes for enemies)
    var alliedLosses: seq[SquadronId] = @[]
    var enemyLosses: seq[string] = @[]

    for (fleetId, fleetBefore) in fleetsBeforeCombat:
      let squadronsBefore = fleetBefore.squadrons.len
      var squadronsAfter = 0

      if fleetId in fleetsAfterCombat:
        squadronsAfter = fleetsAfterCombat[fleetId].squadrons.len

      let lossCount = squadronsBefore - squadronsAfter
      if lossCount > 0:
        # Record losses - assume first squadrons in list were destroyed
        for i in 0 ..< min(lossCount, fleetBefore.squadrons.len):
          let lostSquadronId = fleetBefore.squadrons[i]
          if fleetBefore.houseId == houseId:
            # Allied loss: store squadron ID
            alliedLosses.add(lostSquadronId)
          else:
            # Enemy loss: lookup squadron for ship class name
            let squadronOpt = state.squadrons(lostSquadronId)
            if squadronOpt.isSome:
              let squadron = squadronOpt.get()
              let shipOpt = state.ship(squadron.flagshipId)
              if shipOpt.isSome:
                enemyLosses.add($shipOpt.get().shipClass)
              else:
                enemyLosses.add("Unknown")
            else:
              enemyLosses.add("Unknown")

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

    # Write back updated intelligence (Table mutation)
    intel.combatReports[reportIdx] = report
    state.intelligence[houseId] = intel

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
    batteriesDestroyed: int,
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
  let colonyOpt = state.colony(ColonyId(systemId))
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    if blitzSuccess:
      # Successful blitz - emphasize ALL assets seized INTACT
      assetInfo.add("--- Assets Seized INTACT ---")
      assetInfo.add(&"Infrastructure: {colony.infrastructure} levels (NO DAMAGE)")
      assetInfo.add(&"Industrial: {colony.industrial.units} IU (NO DAMAGE)")
      assetInfo.add(&"Population: {colony.population} PU")
      assetInfo.add(&"Garrison: {colony.marineIds.len} Marines")
      if colony.planetaryShieldLevel > 0:
        assetInfo.add(&"Shields: SLD{colony.planetaryShieldLevel} (INTACT)")
      if colony.groundBatteryIds.len > 0:
        assetInfo.add(&"Ground Batteries: {colony.groundBatteryIds.len} (INTACT)")
      if colony.spaceportIds.len > 0:
        assetInfo.add(&"Spaceports: {colony.spaceportIds.len} (INTACT)")
    else:
      # Failed blitz - defender shows surviving assets
      assetInfo.add("--- Surviving Assets ---")
      assetInfo.add(&"Infrastructure: {colony.infrastructure} levels")
      assetInfo.add(&"Industrial: {colony.industrial.units} IU")
      assetInfo.add(&"Population: {colony.population} PU")
      assetInfo.add(&"Defense: {colony.armyIds.len} Armies, {colony.marineIds.len} Marines")
      if batteriesDestroyed > 0:
        assetInfo.add(
          &"Ground Batteries: {colony.groundBatteryIds.len} ({batteriesDestroyed} destroyed in bombardment)"
        )
      else:
        assetInfo.add(&"Ground Batteries: {colony.groundBatteryIds.len}")

  # Attacker's blitz report
  let attackerOutcome =
    if blitzSuccess:
      CombatOutcome.Victory
    else:
      CombatOutcome.Defeat

  var attackerInfo: seq[string] = @[]
  attackerInfo.add((0 ..< attackerCasualties).mapIt("Marine"))
  if blitzSuccess:
    attackerInfo.add("Blitz successful - all assets seized intact")
  attackerInfo.add(assetInfo)

  let attackerReport = CombatEncounterReport(
    reportId: &"{attackingHouse}-blitz-{turn}-{systemId}",
    turn: turn,
    systemId: systemId,
    phase: CombatPhase.Planetary,
    reportingHouse: attackingHouse,
    alliedFleetIds: @[], # Ground forces, not fleets
    enemyFleetIds: @[],
    outcome: attackerOutcome,
    alliedLosses: @[], # No squadron losses in ground combat
    enemyLosses:
      (0 ..< defenderCasualties).mapIt(if it < defendingArmies: "Army" else: "Marine"),
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: true, # Blitz fleet survives
  )

  # Write to intelligence database (Table read-modify-write)
  if state.intelligence.contains(attackingHouse):
    var intel = state.intelligence[attackingHouse]
    intel.combatReports.add(attackerReport)
    state.intelligence[attackingHouse] = intel

  # Defender's blitz report (mirror perspective)
  let defenderOutcome =
    if blitzSuccess:
      CombatOutcome.Defeat
    else:
      CombatOutcome.Victory

  var defenderInfo: seq[string] = @[]
  defenderInfo.add(
    (0 ..< defenderCasualties).mapIt(if it < defendingArmies: "Army" else: "Marine")
  )
  if blitzSuccess:
    defenderInfo.add("Colony seized by blitz - all assets captured intact")
  else:
    defenderInfo.add("Blitz repelled - all attacking marines destroyed")
  defenderInfo.add(assetInfo)

  let defenderReport = CombatEncounterReport(
    reportId: &"{defendingHouse}-defense-{turn}-{systemId}",
    turn: turn,
    systemId: systemId,
    phase: CombatPhase.Planetary,
    reportingHouse: defendingHouse,
    alliedFleetIds: @[],
    enemyFleetIds: @[],
    outcome: defenderOutcome,
    alliedLosses: @[], # No squadron losses in ground combat
    enemyLosses: (0 ..< attackerCasualties).mapIt("Marine"),
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: true, # Defending colony survives (may change hands)
  )

  # Write to intelligence database (Table read-modify-write)
  if state.intelligence.contains(defendingHouse):
    var intel = state.intelligence[defendingHouse]
    intel.combatReports.add(defenderReport)
    state.intelligence[defendingHouse] = intel

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
    industrialUnitsDestroyed: int,
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
  let colonyOpt = state.colony(ColonyId(systemId))
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    if invasionSuccess:
      # Successful invasion - show captured assets
      assetInfo.add("--- Assets Seized ---")
      assetInfo.add(&"Infrastructure: {colony.infrastructure} levels (50% destroyed)")
      assetInfo.add(
        &"Industrial: {colony.industrial.units} IU ({industrialUnitsDestroyed} IU destroyed)"
      )
      assetInfo.add(&"Population: {colony.population} PU")
      assetInfo.add(&"Garrison: {colony.marineIds.len} Marines")
      if colony.planetaryShieldLevel > 0:
        assetInfo.add(&"Shields: SLD{colony.planetaryShieldLevel}")
    else:
      # Failed invasion - defender shows surviving assets
      assetInfo.add("--- Surviving Assets ---")
      assetInfo.add(&"Infrastructure: {colony.infrastructure} levels")
      assetInfo.add(&"Industrial: {colony.industrial.units} IU")
      assetInfo.add(&"Population: {colony.population} PU")
      assetInfo.add(&"Defense: {colony.armyIds.len} Armies, {colony.marineIds.len} Marines")
      assetInfo.add(&"Ground Batteries: {colony.groundBatteryIds.len}")

  # Attacker's invasion report
  let attackerOutcome =
    if invasionSuccess:
      CombatOutcome.Victory
    else:
      CombatOutcome.Defeat

  var attackerInfo: seq[string] = @[]
  attackerInfo.add((0 ..< attackerCasualties).mapIt("Marine"))
  if invasionSuccess and industrialUnitsDestroyed > 0:
    attackerInfo.add(&"{industrialUnitsDestroyed} IU destroyed in fighting")
  attackerInfo.add(assetInfo)

  let attackerReport = CombatEncounterReport(
    reportId: &"{attackingHouse}-invasion-{turn}-{systemId}",
    turn: turn,
    systemId: systemId,
    phase: CombatPhase.Planetary,
    reportingHouse: attackingHouse,
    alliedFleetIds: @[], # Ground forces, not fleets
    enemyFleetIds: @[],
    outcome: attackerOutcome,
    alliedLosses: @[], # No squadron losses in ground combat
    enemyLosses:
      (0 ..< defenderCasualties).mapIt(if it < defendingArmies: "Army" else: "Marine"),
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: true, # Invading fleet survives (marines may not)
  )

  # Write to intelligence database (Table read-modify-write)
  if state.intelligence.contains(attackingHouse):
    var intel = state.intelligence[attackingHouse]
    intel.combatReports.add(attackerReport)
    state.intelligence[attackingHouse] = intel

  # Defender's invasion report (mirror perspective)
  let defenderOutcome =
    if invasionSuccess:
      CombatOutcome.Defeat
    else:
      CombatOutcome.Victory

  var defenderInfo: seq[string] = @[]
  defenderInfo.add(
    (0 ..< defenderCasualties).mapIt(if it < defendingArmies: "Army" else: "Marine")
  )
  if invasionSuccess and industrialUnitsDestroyed > 0:
    defenderInfo.add(&"{industrialUnitsDestroyed} IU destroyed")
    defenderInfo.add("50% infrastructure destroyed")
    defenderInfo.add("Shields and spaceports destroyed")
  defenderInfo.add(assetInfo)

  let defenderReport = CombatEncounterReport(
    reportId: &"{defendingHouse}-defense-{turn}-{systemId}",
    turn: turn,
    systemId: systemId,
    phase: CombatPhase.Planetary,
    reportingHouse: defendingHouse,
    alliedFleetIds: @[],
    enemyFleetIds: @[],
    outcome: defenderOutcome,
    alliedLosses: @[], # No squadron losses in ground combat
    enemyLosses: (0 ..< attackerCasualties).mapIt("Marine"),
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: not invasionSuccess, # Defender survives if repelled invasion
  )

  # Write to intelligence database (Table read-modify-write)
  if state.intelligence.contains(defendingHouse):
    var intel = state.intelligence[defendingHouse]
    intel.combatReports.add(defenderReport)
    state.intelligence[defendingHouse] = intel

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
    spaceLiftShipsInvolved: int,
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

  # Get post-bombardment colony state for surviving assets intel
  var survivingAssets: seq[string] = @[]
  let colonyOpt = state.colony(ColonyId(systemId))
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    survivingAssets.add(&"Infrastructure: {colony.infrastructure} levels")
    survivingAssets.add(&"Industrial: {colony.industrial.units} IU")
    survivingAssets.add(&"Population: {colony.population} PU")
    survivingAssets.add(&"Ground Batteries: {colony.groundBatteryIds.len}")
    if colony.planetaryShieldLevel > 0:
      survivingAssets.add(&"Shields: SLD{colony.planetaryShieldLevel}")

  # Attacker's bombardment report (they know exactly what they did)
  var attackerEnemyLosses =
    @[
      &"{infrastructureDamaged} infrastructure levels destroyed",
      &"{industrialUnitsDestroyed} IU destroyed",
      &"{groundBatteriesDestroyed} ground batteries destroyed",
      &"{groundForcesKilled} PU casualties",
      "--- Surviving Enemy Assets ---",
    ]
  attackerEnemyLosses.add(survivingAssets)

  let attackerReport = CombatEncounterReport(
    reportId: &"{attackingHouse}-bombardment-{turn}-{systemId}",
    turn: turn,
    systemId: systemId,
    phase: CombatPhase.Orbital,
    reportingHouse: attackingHouse,
    alliedFleetIds: @[attackingFleetId],
    enemyFleetIds: @[], # Can't see ground defenses from orbit
    outcome: CombatOutcome.Victory,
      # Bombardment always "succeeds" if executed
    alliedLosses: @[], # Bombardment doesn't lose squadrons
    enemyLosses: attackerEnemyLosses,
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: true,
  )

  # Write to intelligence database (Table read-modify-write)
  if state.intelligence.contains(attackingHouse):
    var intel = state.intelligence[attackingHouse]
    intel.combatReports.add(attackerReport)
    state.intelligence[attackingHouse] = intel

  # Defender's bombardment report (knows they're being bombarded)
  var defenderAlliedLosses =
    @[
      &"{infrastructureDamaged} infrastructure levels destroyed",
      &"{industrialUnitsDestroyed} IU destroyed",
      &"{groundBatteriesDestroyed} ground batteries destroyed",
      &"{groundForcesKilled} PU casualties",
      "--- Surviving Assets ---",
    ]
  defenderAlliedLosses.add(survivingAssets)

  let defenderReport = CombatEncounterReport(
    reportId: &"{defendingHouse}-bombardment-defense-{turn}-{systemId}",
    turn: turn,
    systemId: systemId,
    phase: CombatPhase.Orbital,
    reportingHouse: defendingHouse,
    alliedFleetIds: @[], # Ground forces (no fleet composition for defenders)
    enemyFleetIds: @[attackingFleetId], # Defender can see attacking fleet
    outcome: CombatOutcome.Defeat, # Being bombarded
    alliedLosses: @[], # No squadron losses in bombardment
    enemyLosses: @[], # Bombardment doesn't damage attacking fleet
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: infrastructureDamaged < 100, # Colony survives unless completely destroyed
  )

  # Write to intelligence database (Table read-modify-write)
  if state.intelligence.contains(defendingHouse):
    var intel = state.intelligence[defendingHouse]
    intel.combatReports.add(defenderReport)
    state.intelligence[defendingHouse] = intel

  # THREAT ASSESSMENT: If transport squadrons detected, invasion is imminent
  if spaceLiftShipsInvolved > 0:
    logWarn(
      "Intelligence",
      "CRITICAL: Invasion force detected",
      "transportSquadrons=",
      $spaceLiftShipsInvolved,
      " system=",
      $systemId,
    )
