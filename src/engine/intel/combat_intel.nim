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
import ../types/[core, game_state, intel, fleet, ship, combat, ground_unit, colony]

proc getShieldLevel(state: GameState, colony: Colony): int32 =
  ## Get shield level for colony (shield level from house SLD tech)
  for unitId in colony.groundUnitIds:
    let unitOpt = state.groundUnit(unitId)
    if unitOpt.isSome and unitOpt.get().stats.unitType == GroundClass.PlanetaryShield:
      let houseOpt = state.house(colony.owner)
      if houseOpt.isSome:
        return houseOpt.get().techTree.levels.sld
      return 0
  return 0

proc countGroundUnits(state: GameState, colony: Colony, unitType: GroundClass): int =
  ## Count ground units of specific type in colony
  var count = 0
  for unitId in colony.groundUnitIds:
    let unitOpt = state.groundUnit(unitId)
    if unitOpt.isSome and unitOpt.get().stats.unitType == unitType:
      count += 1
  return count

proc createFleetComposition*(
    state: GameState, fleet: Fleet, fleetId: FleetId
): CombatFleetComposition =
  ## Create fleet composition intel from combat encounter
  ## Stores ship IDs, not full details (lookup separately via FleetIntel)

  # Collect ship IDs directly from fleet
  var shipIds: seq[ShipId] = fleet.ships

  # Get fleet's active command (if any)
  var orderIntel: Option[FleetOrderIntel] = none(FleetOrderIntel)
  if fleet.missionState != MissionState.None:
    let command = fleet.command
    orderIntel = some(
      FleetOrderIntel(
        orderType: $command.commandType,
        targetSystem: command.targetSystem
      )
    )

  result = CombatFleetComposition(
    fleetId: fleetId,
    owner: fleet.houseId,
    shipIds: shipIds,
    isCloaked: false, # TODO: Implement cloaking detection logic
  )

proc generatePreCombatReport*(
    state: GameState,
    systemId: SystemId,
    phase: CombatTheater,
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
    alliedLosses: seq[ShipId],
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
    state: GameState,
    systemId: SystemId,
    phase: CombatTheater,
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
    if not state.intel.contains(houseId):
      continue # No intelligence database for this house

    var intel = state.intel[houseId]

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

    # Calculate losses (ShipIds for allies, ship classes for enemies)
    var alliedLosses: seq[ShipId] = @[]
    var enemyLosses: seq[string] = @[]

    for (fleetId, fleetBefore) in fleetsBeforeCombat:
      let shipsBefore = fleetBefore.ships.len
      var shipsAfter = 0

      if fleetId in fleetsAfterCombat:
        shipsAfter = fleetsAfterCombat[fleetId].ships.len

      let lossCount = shipsBefore - shipsAfter
      if lossCount > 0:
        # Record losses - assume first ships in list were destroyed
        for i in 0 ..< min(lossCount, fleetBefore.ships.len):
          let lostShipId = fleetBefore.ships[i]
          if fleetBefore.houseId == houseId:
            # Allied loss: store ship ID
            alliedLosses.add(lostShipId)
          else:
            # Enemy loss: lookup ship for ship class name
            let shipOpt = state.ship(lostShipId)
            if shipOpt.isSome:
              enemyLosses.add($shipOpt.get().shipClass)
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
    state.intel[houseId] = intel

proc generateBlitzIntelligence*(
    state: GameState,
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
  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    if blitzSuccess:
      # Successful blitz - emphasize ALL assets seized INTACT
      assetInfo.add("--- Assets Seized INTACT ---")
      assetInfo.add(&"Infrastructure: {colony.infrastructure} levels (NO DAMAGE)")
      assetInfo.add(&"Industrial: {colony.industrial.units} IU (NO DAMAGE)")
      assetInfo.add(&"Population: {colony.population} PU")
      assetInfo.add(&"Garrison: {state.countGroundUnits(colony, GroundClass.Marine)} Marines")
      if state.getShieldLevel(colony) > 0:
        assetInfo.add(&"Shields: SLD{state.getShieldLevel(colony)} (INTACT)")
      if state.countGroundUnits(colony, GroundClass.GroundBattery) > 0:
        assetInfo.add(&"Ground Batteries: {state.countGroundUnits(colony, GroundClass.GroundBattery)} (INTACT)")
      if colony.neoriaIds.len > 0:
        assetInfo.add(&"Production Facilities: {colony.neoriaIds.len} (INTACT)")
    else:
      # Failed blitz - defender shows surviving assets
      assetInfo.add("--- Surviving Assets ---")
      assetInfo.add(&"Infrastructure: {colony.infrastructure} levels")
      assetInfo.add(&"Industrial: {colony.industrial.units} IU")
      assetInfo.add(&"Population: {colony.population} PU")
      assetInfo.add(&"Defense: {state.countGroundUnits(colony, GroundClass.Army)} Armies, {state.countGroundUnits(colony, GroundClass.Marine)} Marines")
      if batteriesDestroyed > 0:
        assetInfo.add(
          &"Ground Batteries: {state.countGroundUnits(colony, GroundClass.GroundBattery)} ({batteriesDestroyed} destroyed in bombardment)"
        )
      else:
        assetInfo.add(&"Ground Batteries: {state.countGroundUnits(colony, GroundClass.GroundBattery)}")

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
    phase: CombatTheater.Planetary,
    reportingHouse: attackingHouse,
    alliedFleetIds: @[], # Ground forces, not fleets
    enemyFleetIds: @[],
    outcome: attackerOutcome,
    alliedLosses: @[], # No ship losses in ground combat
    enemyLosses:
      (0 ..< defenderCasualties).mapIt(if it < defendingArmies: "Army" else: "Marine"),
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: true, # Blitz fleet survives
  )

  # Write to intelligence database (Table read-modify-write)
  if state.intel.contains(attackingHouse):
    var intel = state.intel[attackingHouse]
    intel.combatReports.add(attackerReport)
    state.intel[attackingHouse] = intel

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
    phase: CombatTheater.Planetary,
    reportingHouse: defendingHouse,
    alliedFleetIds: @[],
    enemyFleetIds: @[],
    outcome: defenderOutcome,
    alliedLosses: @[], # No ship losses in ground combat
    enemyLosses: (0 ..< attackerCasualties).mapIt("Marine"),
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: true, # Defending colony survives (may change hands)
  )

  # Write to intelligence database (Table read-modify-write)
  if state.intel.contains(defendingHouse):
    var intel = state.intel[defendingHouse]
    intel.combatReports.add(defenderReport)
    state.intel[defendingHouse] = intel

proc generateInvasionIntelligence*(
    state: GameState,
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
  let colonyOpt = state.colonyBySystem(systemId)
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
      assetInfo.add(&"Garrison: {state.countGroundUnits(colony, GroundClass.Marine)} Marines")
      if state.getShieldLevel(colony) > 0:
        assetInfo.add(&"Shields: SLD{state.getShieldLevel(colony)}")
    else:
      # Failed invasion - defender shows surviving assets
      assetInfo.add("--- Surviving Assets ---")
      assetInfo.add(&"Infrastructure: {colony.infrastructure} levels")
      assetInfo.add(&"Industrial: {colony.industrial.units} IU")
      assetInfo.add(&"Population: {colony.population} PU")
      assetInfo.add(&"Defense: {state.countGroundUnits(colony, GroundClass.Army)} Armies, {state.countGroundUnits(colony, GroundClass.Marine)} Marines")
      assetInfo.add(&"Ground Batteries: {state.countGroundUnits(colony, GroundClass.GroundBattery)}")

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
    phase: CombatTheater.Planetary,
    reportingHouse: attackingHouse,
    alliedFleetIds: @[], # Ground forces, not fleets
    enemyFleetIds: @[],
    outcome: attackerOutcome,
    alliedLosses: @[], # No ship losses in ground combat
    enemyLosses:
      (0 ..< defenderCasualties).mapIt(if it < defendingArmies: "Army" else: "Marine"),
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: true, # Invading fleet survives (marines may not)
  )

  # Write to intelligence database (Table read-modify-write)
  if state.intel.contains(attackingHouse):
    var intel = state.intel[attackingHouse]
    intel.combatReports.add(attackerReport)
    state.intel[attackingHouse] = intel

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
    phase: CombatTheater.Planetary,
    reportingHouse: defendingHouse,
    alliedFleetIds: @[],
    enemyFleetIds: @[],
    outcome: defenderOutcome,
    alliedLosses: @[], # No ship losses in ground combat
    enemyLosses: (0 ..< attackerCasualties).mapIt("Marine"),
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: not invasionSuccess, # Defender survives if repelled invasion
  )

  # Write to intelligence database (Table read-modify-write)
  if state.intel.contains(defendingHouse):
    var intel = state.intel[defendingHouse]
    intel.combatReports.add(defenderReport)
    state.intel[defendingHouse] = intel

proc generateBombardmentIntelligence*(
    state: GameState,
    systemId: SystemId,
    attackingHouse: HouseId,
    attackingFleetId: FleetId,
    defendingHouse: HouseId,
    infrastructureDamaged: int,
    industrialUnitsDestroyed: int,
    shieldsActive: bool,
    groundBatteriesDestroyed: int,
    groundForcesKilled: int,
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

  let turn = state.turn

  # Get post-bombardment colony state for surviving assets intel
  var survivingAssets: seq[string] = @[]
  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    survivingAssets.add(&"Infrastructure: {colony.infrastructure} levels")
    survivingAssets.add(&"Industrial: {colony.industrial.units} IU")
    survivingAssets.add(&"Population: {colony.population} PU")
    survivingAssets.add(&"Ground Batteries: {state.countGroundUnits(colony, GroundClass.GroundBattery)}")
    if state.getShieldLevel(colony) > 0:
      survivingAssets.add(&"Shields: SLD{state.getShieldLevel(colony)}")

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
    phase: CombatTheater.Orbital,
    reportingHouse: attackingHouse,
    alliedFleetIds: @[attackingFleetId],
    enemyFleetIds: @[], # Can't see ground defenses from orbit
    outcome: CombatOutcome.Victory,
      # Bombardment always "succeeds" if executed
    alliedLosses: @[], # Bombardment doesn't lose ships
    enemyLosses: attackerEnemyLosses,
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: true,
  )

  # Write to intelligence database (Table read-modify-write)
  if state.intel.contains(attackingHouse):
    var intel = state.intel[attackingHouse]
    intel.combatReports.add(attackerReport)
    state.intel[attackingHouse] = intel

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
    phase: CombatTheater.Orbital,
    reportingHouse: defendingHouse,
    alliedFleetIds: @[], # Ground forces (no fleet composition for defenders)
    enemyFleetIds: @[attackingFleetId], # Defender can see attacking fleet
    outcome: CombatOutcome.Defeat, # Being bombarded
    alliedLosses: @[], # No ship losses in bombardment
    enemyLosses: @[], # Bombardment doesn't damage attacking fleet
    retreatedAllies: @[],
    retreatedEnemies: @[],
    survived: infrastructureDamaged < 100, # Colony survives unless completely destroyed
  )

  # Write to intelligence database (Table read-modify-write)
  if state.intel.contains(defendingHouse):
    var intel = state.intel[defendingHouse]
    intel.combatReports.add(defenderReport)
    state.intel[defendingHouse] = intel
