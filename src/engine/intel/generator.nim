## Intelligence Report Generation
##
## Generates intelligence reports from intelligence gathering operations
## Reports can be gathered by scouts, combat fleets, or any unit observing enemy forces
## Per intel.md and operations.md specifications

import std/[options, random, tables]
# import std/sequtils  # TODO: Needed for toSeq() in income calculation (restore after refactor)
import ../types/[core, game_state, intel, fleet, combat, ground_unit, ship]
import ../state/[engine, iterators]
# import ../systems/income/income as income_system  # TODO: Uncomment after systems refactor
import corruption

proc generateColonyIntelReport*(
    state: GameState,
    scoutOwner: HouseId,
    targetSystem: SystemId,
    quality: IntelQuality,
): Option[ColonyIntelReport] =
  ## Generate colony intelligence report from SpyOnPlanet mission
  ## Reports on ground/planetary assets and colony construction pipeline:
  ## - Population and infrastructure
  ## - Spaceports (ground-to-orbit)
  ## - Ground forces (armies, marines, batteries)
  ## - Planetary shields
  ## - Colony construction queue (Spy quality only)
  ## - Economic data (Spy quality only)

  # Use safe accessor
  let colonyOpt = state.colonyBySystem(targetSystem)
  if colonyOpt.isNone:
    return none(ColonyIntelReport)

  let colony = colonyOpt.get()

  # Don't spy on your own colonies
  if colony.owner == scoutOwner:
    return none(ColonyIntelReport)

  # Count ground units from consolidated groundUnitIds
  var armyCount, marineCount, groundBatteryCount, shieldLevel = 0i32
  for unitId in colony.groundUnitIds:
    let unitOpt = state.groundUnit(unitId)
    if unitOpt.isSome:
      let unit = unitOpt.get()
      case unit.stats.unitType
      of GroundClass.Army:
        armyCount += 1
      of GroundClass.Marine:
        marineCount += 1
      of GroundClass.GroundBattery:
        groundBatteryCount += 1
      of GroundClass.PlanetaryShield:
        # Get shield level from house SLD tech
        let houseOpt = state.house(colony.owner)
        if houseOpt.isSome:
          shieldLevel = houseOpt.get().techTree.levels.sld

  # Count spaceport facilities specifically (not all neorias)
  let spaceportCount = state.countSpaceportsAtColony(colony.id)

  var report = ColonyIntelReport(
    colonyId: colonyOpt.get().id,  # Use actual colony ID
    targetOwner: colony.owner,
    gatheredTurn: state.turn,
    quality: quality,
    population: colony.population,
    infrastructure: colony.infrastructure,
    spaceportCount: spaceportCount,
    armyCount: armyCount,
    marineCount: marineCount,
    groundBatteryCount: groundBatteryCount,
    planetaryShieldLevel: shieldLevel,
    colonyConstructionQueue: @[],
    grossOutput: none(int32),
    taxRevenue: none(int32),
  )

  # Economic intelligence visible only with spy infiltration
  if quality == IntelQuality.Spy:
    # Use colony's own economic data
    report.grossOutput = some(colony.grossOutput)
    report.taxRevenue = some(int32(colony.grossOutput * colony.taxRate / 100))

  # Colony construction queue visible only with spy infiltration
  if quality == IntelQuality.Spy:
    # Add all construction projects in queue
    report.colonyConstructionQueue = colony.constructionQueue
    # Also check underConstruction field
    if colony.underConstruction.isSome:
      let projectId = colony.underConstruction.get()
      if projectId notin report.colonyConstructionQueue:
        report.colonyConstructionQueue.add(projectId)

    # TODO: Add spaceport dock queue when spaceport construction is implemented
    # for spaceportId in colony.spaceportIds:
    #   let spaceport = state.spaceport(spaceportId)
    #   if spaceport.isSome:
    #     report.spaceportDockQueue.add(spaceport.get().constructionQueue)
    report.spaceportDockQueue = @[]

  # Apply corruption if gathering house's intelligence is compromised (disinformation)
  let corruptionEffect = corruption.hasIntelCorruption(state.ongoingEffects, scoutOwner)

  if corruptionEffect.isSome:
    var rng = initRand(state.turn xor hash(scoutOwner) xor int(targetSystem))
    let magnitude = corruptionEffect.get().magnitude
    let corrupted = corruption.corruptColonyIntel(report, magnitude, rng)
    return some(corrupted)

  return some(report)

proc generateOrbitalIntelReport*(
    state: GameState,
    scoutOwner: HouseId,
    targetSystem: SystemId,
    quality: IntelQuality,
): Option[OrbitalIntelReport] =
  ## Generate orbital intelligence report from approach/orbital missions
  ## Reports on orbital/space assets:
  ## - Starbases
  ## - Shipyards and drydocks (dock construction pipeline)
  ## - Reserve and mothballed fleets
  ## - Guard and blockade fleets
  ## - Fighter squadrons (stationed at colony)

  # Use safe accessor
  let colonyOpt = state.colonyBySystem(targetSystem)
  if colonyOpt.isNone:
    return none(OrbitalIntelReport)

  let colony = colonyOpt.get()

  # Don't spy on your own colonies
  if colony.owner == scoutOwner:
    return none(OrbitalIntelReport)

  # Count fleet statuses and identify guard/blockade fleets
  var reserveFleets: int32 = 0
  var mothballedFleets: int32 = 0
  var guardFleetIds: seq[FleetId] = @[]
  var blockadeFleetIds: seq[FleetId] = @[]

  for fleet in state.fleetsAtSystemForHouse(targetSystem, colony.owner):
    case fleet.status
    of FleetStatus.Reserve:
      reserveFleets += 1
    of FleetStatus.Mothballed:
      mothballedFleets += 1
    else:
      discard

    # Check for guard/blockade orders (Spy quality only - requires infiltration)
    if quality == IntelQuality.Spy:
      # TODO: Check fleet orders when order system is implemented
      # if fleet.orders.isSome:
      #   let order = fleet.orders.get()
      #   if order.orderType == OrderType.Guard and order.targetColony == colony.id:
      #     guardFleetIds.add(fleet.id)
      #   elif order.orderType == OrderType.Blockade and order.targetColony == colony.id:
      #     blockadeFleetIds.add(fleet.id)
      discard

  # Collect fighter IDs from colony
  var fighterIds: seq[ShipId] = colony.fighterIds

  var report = OrbitalIntelReport(
    colonyId: colonyOpt.get().id,  # Use actual colony ID
    targetOwner: colony.owner,
    gatheredTurn: state.turn,
    quality: quality,
    starbaseCount: state.countStarbasesAtColony(colony.id),
    shipyardCount: state.countShipyardsAtColony(colony.id),
    drydockCount: state.countDrydocksAtColony(colony.id),
    reserveFleetCount: reserveFleets,
    mothballedFleetCount: mothballedFleets,
    guardFleetIds: guardFleetIds,
    blockadeFleetIds: blockadeFleetIds,
    fighterIds: fighterIds,
  )

  # Apply corruption if gathering house's intelligence is compromised (disinformation)
  let corruptionEffect = corruption.hasIntelCorruption(state.ongoingEffects, scoutOwner)

  if corruptionEffect.isSome:
    var rng = initRand(state.turn xor hash(scoutOwner) xor int(targetSystem))
    let magnitude = corruptionEffect.get().magnitude
    let corrupted = corruption.corruptOrbitalIntel(report, magnitude, rng)
    return some(corrupted)

  return some(report)

proc generateSystemIntelReport*(
    state: GameState,
    scoutOwner: HouseId,
    targetSystem: SystemId,
    quality: IntelQuality,
): Option[SystemIntelPackage] =
  ## Generate system intelligence report from SpyOnSystem mission
  ## Reports on:
  ## - All enemy fleets in the system
  ## - Carrier-embarked fighter squadrons (Spy quality only - requires infiltration)
  ## - Colony-based fighter squadrons (visible like regular fleets)
  ##
  ## Quality determines detail level:
  ## - Visual: Ship counts, classes, transports
  ## - Spy: Tech levels, hull integrity, embarked fighters

  var detectedFleetIds: seq[FleetId] = @[]
  var fleetIntelData: seq[tuple[fleetId: FleetId, intel: FleetIntel]] = @[]
  var shipIntelData: seq[tuple[shipId: ShipId, intel: ShipIntel]] = @[]

  # Find all fleets in this system that are not owned by the gathering house
  for fleet in state.fleetsAtSystem(targetSystem):
    if fleet.houseId != scoutOwner:
      detectedFleetIds.add(fleet.id)

      # Build detailed fleet intelligence
      let fleetIntel = FleetIntel(
        fleetId: fleet.id,
        owner: fleet.houseId,
        location: targetSystem,
        shipCount: int32(fleet.ships.len),
        standingOrders: none(string), # Future: detect fleet orders
        shipIds: fleet.ships,
      )

      fleetIntelData.add((fleet.id, fleetIntel))

      # Build detailed ship intelligence for each ship in fleet
      for shipId in fleet.ships:
        let shipOpt = state.ship(shipId)
        if shipOpt.isNone:
          continue

        let ship = shipOpt.get()

        let shipIntel = ShipIntel(
          shipId: shipId,
          shipClass: $ship.shipClass,
          # Tech level and hull integrity only for Spy+ quality
          techLevel:
            if quality == IntelQuality.Spy:
              ship.stats.wep
            else:
              0,
          hullIntegrity:
            if quality == IntelQuality.Spy:
              (if ship.state == CombatState.Crippled: some(int32(50)) else: some(int32(100)))
            else:
              none(int32),
        )

        shipIntelData.add((shipId, shipIntel))

        # Check for embarked fighters on carriers (Spy quality only - requires infiltration)
        if quality == IntelQuality.Spy and ship.embarkedFighters.len > 0:
          for fighterShipId in ship.embarkedFighters:
            let fighterShipOpt = state.ship(fighterShipId)
            if fighterShipOpt.isNone:
              continue

            let fighterShip = fighterShipOpt.get()

            let fighterIntel = ShipIntel(
              shipId: fighterShipId,
              shipClass: $fighterShip.shipClass,
              techLevel: fighterShip.stats.wep,
              hullIntegrity:
                if fighterShip.state == CombatState.Crippled:
                  some(int32(50))
                else:
                  some(int32(100)),
            )

            shipIntelData.add((fighterShipId, fighterIntel))

  # Check for colony-based fighter ships (not in fleets)
  # Fighters can be stationed at colonies for defense
  let colonyOpt = state.colonyBySystem(targetSystem)
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    if colony.owner != scoutOwner:
      # Scan fighter ships at this colony
      for fighterShipId in colony.fighterIds:
        let fighterShipOpt = state.ship(fighterShipId)
        if fighterShipOpt.isNone:
          continue

        let fighterShip = fighterShipOpt.get()

        let fighterIntel = ShipIntel(
          shipId: fighterShipId,
          shipClass: $fighterShip.shipClass,
          # Tech level and hull integrity only for Spy+ quality
          techLevel:
            if quality == IntelQuality.Spy:
              fighterShip.stats.wep
            else:
              0,
          hullIntegrity:
            if quality == IntelQuality.Spy:
              (if fighterShip.state == CombatState.Crippled: some(int32(50)) else: some(int32(100)))
            else:
              none(int32),
        )

        shipIntelData.add((fighterShipId, fighterIntel))

  # Return none if no intelligence gathered (no fleets and no colony fighters)
  if detectedFleetIds.len == 0 and shipIntelData.len == 0:
    return none(SystemIntelPackage)

  var report = SystemIntelReport(
    systemId: targetSystem,
    gatheredTurn: state.turn,
    quality: quality,
    detectedFleetIds: detectedFleetIds,
  )

  # Apply corruption if gathering house's intelligence is compromised (disinformation)
  let corruptionEffect = corruption.hasIntelCorruption(state.ongoingEffects, scoutOwner)

  if corruptionEffect.isSome:
    var rng = initRand(state.turn xor hash(scoutOwner) xor int(targetSystem))
    let magnitude = corruptionEffect.get().magnitude
    report = corruption.corruptSystemIntel(report, magnitude, rng)

    # Also corrupt fleet intel (ship intel corruption not implemented)
    for i in 0 ..< fleetIntelData.len:
      let (fleetId, intel) = fleetIntelData[i]
      fleetIntelData[i] = (fleetId, corruption.corruptFleetIntel(intel, magnitude, rng))

  # Return complete intelligence package
  # Caller is responsible for storing in intelligence database
  return some(
    SystemIntelPackage(
      report: report, fleetIntel: fleetIntelData, shipIntel: shipIntelData
    )
  )

proc generateStarbaseIntelReport*(
    state: GameState,
    scoutOwner: HouseId,
    targetSystem: SystemId,
    quality: IntelQuality,
): Option[StarbaseIntelReport] =
  ## Generate starbase intelligence report from HackStarbase mission
  ## Per intel.md and operations.md:6.2.11 - "economic and R&D intelligence"

  # Use safe accessor
  let colonyOpt = state.colonyBySystem(targetSystem)
  if colonyOpt.isNone:
    return none(StarbaseIntelReport)

  let colony = colonyOpt.get()

  # Don't hack your own starbases
  if colony.owner == scoutOwner:
    return none(StarbaseIntelReport)

  # No starbase to hack
  if state.countStarbasesAtColony(colony.id) == 0:
    return none(StarbaseIntelReport)

  # Get target house data
  let targetHouseOpt = state.house(colony.owner)
  if targetHouseOpt.isNone:
    return none(StarbaseIntelReport)

  let targetHouse = targetHouseOpt.get()

  # Get first kastra (starbase) at colony for report identifier
  let kastras = state.kastrasAtColony(colony.id)
  let kastraId = if kastras.len > 0: kastras[0].id else: KastraId(0)

  var report = StarbaseIntelReport(
    kastraId: kastraId,
    targetOwner: colony.owner,
    gatheredTurn: state.turn,
    quality: quality,
  )

  # Economic intelligence - always available from starbase hack
  report.treasuryBalance = some(targetHouse.treasury)
  report.taxRate = some(targetHouse.taxPolicy.currentRate.float32)

  # ============================================================================
  # TODO: Restore income calculation after systems refactor
  # ============================================================================
  # let targetColonies = toSeq(state.coloniesOwned(colony.owner))
  # let incomeReport = income_system.calculateHouseIncome(
  #   targetColonies,
  #   int(targetHouse.techTree.levels.el),
  #   int(targetHouse.techTree.levels.cst),
  #   targetHouse.taxPolicy,
  #   int(targetHouse.treasury),
  # )
  # report.grossIncome = some(incomeReport.totalGross)
  # report.netIncome = some(incomeReport.totalNet)

  # Dummy values until systems refactor complete
  report.grossIncome = some(int32(1000))
  report.netIncome = some(int32(800))
  # ============================================================================

  # R&D intelligence - tech tree data
  report.techLevels = some(targetHouse.techTree.levels)

  # Research allocations (from accumulated research)
  # Calculate total TRP across all fields
  var totalTRP: int32 = 0
  for field, points in targetHouse.techTree.accumulated.technology:
    totalTRP += points

  report.researchAllocations = some(
    (
      erp: targetHouse.techTree.accumulated.economic,
      srp: targetHouse.techTree.accumulated.science,
      trp: totalTRP,
    )
  )

  # Current research focus (most accumulated type)
  let economicAccum = targetHouse.techTree.accumulated.economic
  let scienceAccum = targetHouse.techTree.accumulated.science
  let maxAccum = max([economicAccum, scienceAccum, totalTRP])

  if maxAccum == economicAccum:
    report.currentResearch = some("Economic")
  elif maxAccum == scienceAccum:
    report.currentResearch = some("Science")
  else:
    report.currentResearch = some("Technology")

  # Apply corruption if gathering house's intelligence is compromised (disinformation)
  let corruptionEffect = corruption.hasIntelCorruption(state.ongoingEffects, scoutOwner)

  if corruptionEffect.isSome:
    var rng = initRand(state.turn xor hash(scoutOwner) xor int(targetSystem))
    let magnitude = corruptionEffect.get().magnitude
    report = corruption.corruptStarbaseIntel(report, magnitude, rng)

  return some(report)
