## Intelligence Report Generation
##
## Generates intelligence reports from intelligence gathering operations
## Reports can be gathered by scouts, combat fleets, or any unit observing enemy forces
## Per intel.md and operations.md specifications

import std/[options, random, tables]
import ../types/[core, game_state, intel, fleet, combat, ground_unit, ship]
import ../state/[engine, iterators]
import corruption

proc generateColonyIntelReport*(
    state: GameState,
    scoutOwner: HouseId,
    targetSystem: SystemId,
    quality: IntelQuality,
): Option[ColonyIntelReport] =
  ## Generate colony intelligence report from Scout missions
  ## Reports on ground/planetary assets and colony construction pipeline:
  ## - Population and infrastructure
  ## - Spaceports (ground-to-orbit)
  ## - Ground forces (armies, marines, batteries)
  ## - Planetary shields
  ## - Colony construction queue (Perfect quality only)
  ## - Economic data (Perfect quality only)

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

  # Economic intelligence visible only with Perfect quality intel
  if quality == IntelQuality.Perfect:
    # Use colony's own economic data
    report.grossOutput = some(colony.grossOutput)
    report.taxRevenue = some(int32(colony.grossOutput * colony.taxRate / 100))

  # Colony construction queue visible only with Perfect quality intel
  if quality == IntelQuality.Perfect:
    # Add all construction projects in queue
    report.colonyConstructionQueue = colony.constructionQueue
    # Also check underConstruction field
    if colony.underConstruction.isSome:
      let projectId = colony.underConstruction.get()
      if projectId notin report.colonyConstructionQueue:
        report.colonyConstructionQueue.add(projectId)

    # Populate spaceport dock queue from neorias at this colony
    report.spaceportDockQueue = @[]
    for neoria in state.neoriasAtColony(colony.id):
      # Add queued projects
      for projectId in neoria.constructionQueue:
        report.spaceportDockQueue.add(projectId)
      # Add active construction projects
      for projectId in neoria.activeConstructions:
        report.spaceportDockQueue.add(projectId)

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

    # Check for guard/blockade commands (Perfect quality only - requires detailed intel)
    if quality == IntelQuality.Perfect:
      let command = fleet.command
      # Check if guarding this colony
      if command.commandType == FleetCommandType.GuardColony:
        if command.targetSystem.isSome and command.targetSystem.get() == targetSystem:
          guardFleetIds.add(fleet.id)
      # Check if blockading this colony
      elif command.commandType == FleetCommandType.Blockade:
        if command.targetSystem.isSome and command.targetSystem.get() == targetSystem:
          blockadeFleetIds.add(fleet.id)

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
  ## Generate system intelligence report from Scout missions
  ## Reports on:
  ## - All enemy fleets in the system
  ## - Carrier-embarked fighter squadrons (Perfect quality only - from scout missions)
  ## - Colony-based fighter squadrons (visible like regular fleets)
  ##
  ## Quality determines detail level:
  ## - Visual: Ship counts, classes, transports (fleet encounters during transit)
  ## - Perfect: Tech levels, hull integrity, embarked fighters (scout missions)

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
          # Tech level and hull integrity only for Perfect quality
          techLevel:
            if quality == IntelQuality.Perfect:
              ship.stats.wep
            else:
              0,
          hullIntegrity:
            if quality == IntelQuality.Perfect:
              (if ship.state == CombatState.Crippled: some(int32(50)) else: some(int32(100)))
            else:
              none(int32),
        )

        shipIntelData.add((shipId, shipIntel))

        # Check for embarked fighters on carriers (Perfect quality only - scout missions)
        if quality == IntelQuality.Perfect and ship.embarkedFighters.len > 0:
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
          # Tech level and hull integrity only for Perfect quality
          techLevel:
            if quality == IntelQuality.Perfect:
              fighterShip.stats.wep
            else:
              0,
          hullIntegrity:
            if quality == IntelQuality.Perfect:
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

  # Note: Intelligence reports provide rough income estimates
  # Actual income calculation requires full house state (tax rates, maintenance, tech, etc.)
  # which is beyond the scope of colony-level intelligence gathering
  # Future: Could implement rough estimation based on visible colony count and tech levels
  report.grossIncome = none(int32)
  report.netIncome = none(int32)

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
