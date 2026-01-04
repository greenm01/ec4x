## Intelligence Report Generation
##
## Generates intelligence reports from intelligence gathering operations
## Reports can be gathered by scouts, combat fleets, or any unit observing enemy forces
## Per intel.md and operations.md specifications

import std/[options, random, tables]
# import std/sequtils  # TODO: Needed for toSeq() in income calculation (restore after refactor)
import ../types/[core, game_state, intel, fleet, combat, ground_unit]
import ../types/squadron as squadron_types
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

  # Count neoria facilities (spaceports)
  let spaceportCount = colony.neoriaIds.len.int32

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

  # Collect fighter squadron IDs
  var fighterSquadronIds: seq[SquadronId] = @[]
  for squadronId in colony.fighterSquadronIds:
    fighterSquadronIds.add(squadronId)
  for squadronId in colony.unassignedSquadronIds:
    # Check if it's a fighter squadron
    let squadronOpt = state.squadron(squadronId)
    if squadronOpt.isSome:
      let squadron = squadronOpt.get()
      if squadron.squadronType == squadron_types.SquadronClass.Fighter:
        fighterSquadronIds.add(squadronId)

  var report = OrbitalIntelReport(
    colonyId: colonyOpt.get().id,  # Use actual colony ID
    targetOwner: colony.owner,
    gatheredTurn: state.turn,
    quality: quality,
    starbaseCount: int32(colony.starbaseIds.len),
    shipyardCount: int32(colony.shipyardIds.len),
    drydockCount: int32(colony.drydockIds.len),
    reserveFleetCount: reserveFleets,
    mothballedFleetCount: mothballedFleets,
    guardFleetIds: guardFleetIds,
    blockadeFleetIds: blockadeFleetIds,
    fighterSquadronIds: fighterSquadronIds,
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
  var squadronIntelData: seq[tuple[squadronId: SquadronId, intel: SquadronIntel]] = @[]

  # Find all fleets in this system that are not owned by the gathering house
  for fleet in state.fleetsAtSystem(targetSystem):
    if fleet.houseId != scoutOwner:
      detectedFleetIds.add(fleet.id)

      # Build detailed fleet intelligence
      # Count transport/space-lift squadrons
      var transportCount: int32 = 0
      for squadronId in fleet.squadrons:
        let squadronOpt = state.squadron(squadronId)
        if squadronOpt.isSome:
          let squadron = squadronOpt.get()
          if squadron.squadronType in
              {squadron_types.SquadronClass.Expansion, squadron_types.SquadronClass.Auxiliary}:
            transportCount += 1

      let fleetIntel = FleetIntel(
        fleetId: fleet.id,
        owner: fleet.houseId,
        location: targetSystem,
        shipCount: int32(fleet.squadrons.len),
        standingOrders: none(string), # Future: detect fleet orders
        spaceLiftShipCount: if transportCount > 0: some(transportCount) else: none(int32),
        squadronIds: fleet.squadrons,
      )

      fleetIntelData.add((fleet.id, fleetIntel))

      # Build detailed squadron intelligence for each squadron
      for squadronId in fleet.squadrons:
        let squadronOpt = state.squadrons(squadronId)
        if squadronOpt.isNone:
          continue

        let squadron = squadronOpt.get()

        # Get flagship for details
        let flagshipOpt = state.ship(squadron.flagshipId)
        if flagshipOpt.isNone:
          continue

        let flagship = flagshipOpt.get()

        let squadronIntel = SquadronIntel(
          squadronId: squadronId,
          shipClass: $flagship.shipClass,
          shipCount: int32(1 + squadron.ships.len), # Flagship + escorts
          # Tech level and hull integrity only for Spy+ quality
          techLevel:
            if quality == IntelQuality.Spy:
              flagship.stats.wep
            else:
              0,
          hullIntegrity:
            if quality == IntelQuality.Spy:
              (if flagship.state == CombatState.Crippled: some(int32(50)) else: some(int32(100)))
            else:
              none(int32),
        )

        squadronIntelData.add((squadronId, squadronIntel))

        # Check for embarked fighters on carriers (Spy quality only - requires infiltration)
        if quality == IntelQuality.Spy and squadron.embarkedFighters.len > 0:
          for fighterSquadronId in squadron.embarkedFighters:
            let fighterSquadronOpt = state.squadrons(fighterSquadronId)
            if fighterSquadronOpt.isNone:
              continue

            let fighterSquadron = fighterSquadronOpt.get()

            # Get fighter flagship for details
            let fighterFlagshipOpt = state.ship(fighterSquadron.flagshipId)
            if fighterFlagshipOpt.isNone:
              continue

            let fighterFlagship = fighterFlagshipOpt.get()

            let fighterIntel = SquadronIntel(
              squadronId: fighterSquadronId,
              shipClass: $fighterFlagship.shipClass,
              shipCount: int32(1 + fighterSquadron.ships.len),
              techLevel: fighterFlagship.stats.wep,
              hullIntegrity:
                if fighterFlagship.state == CombatState.Crippled:
                  some(int32(50))
                else:
                  some(int32(100)),
            )

            squadronIntelData.add((fighterSquadronId, fighterIntel))

  # Check for colony-based fighter squadrons (not in fleets)
  # Fighters can be stationed at colonies for defense
  let colonyOpt = state.colonyBySystem(targetSystem)
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    if colony.owner != scoutOwner:
      # Scan unassigned squadrons at this colony
      for squadronId in colony.unassignedSquadronIds:
        let squadronOpt = state.squadrons(squadronId)
        if squadronOpt.isNone:
          continue

        let squadron = squadronOpt.get()

        # Only report Fighter squadrons (other types should be in fleets or docked)
        if squadron.squadronType != squadron_types.SquadronClass.Fighter:
          continue

        # Get flagship for details
        let flagshipOpt = state.ship(squadron.flagshipId)
        if flagshipOpt.isNone:
          continue

        let flagship = flagshipOpt.get()

        let squadronIntel = SquadronIntel(
          squadronId: squadronId,
          shipClass: $flagship.shipClass,
          shipCount: int32(1 + squadron.ships.len), # Flagship + escorts
          # Tech level and hull integrity only for Spy+ quality
          techLevel:
            if quality == IntelQuality.Spy:
              flagship.stats.wep
            else:
              0,
          hullIntegrity:
            if quality == IntelQuality.Spy:
              (if flagship.state == CombatState.Crippled: some(int32(50)) else: some(int32(100)))
            else:
              none(int32),
        )

        squadronIntelData.add((squadronId, squadronIntel))

  # Return none if no intelligence gathered (no fleets and no colony fighters)
  if detectedFleetIds.len == 0 and squadronIntelData.len == 0:
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

    # Also corrupt fleet and squadron intel
    for i in 0 ..< fleetIntelData.len:
      fleetIntelData[i].intel = corruption.corruptFleetIntel(
        fleetIntelData[i].intel, magnitude, rng
      )

    for i in 0 ..< squadronIntelData.len:
      squadronIntelData[i].intel = corruption.corruptSquadronIntel(
        squadronIntelData[i].intel, magnitude, rng
      )

  # Return complete intelligence package
  # Caller is responsible for storing in intelligence database
  return some(
    SystemIntelPackage(
      report: report, fleetIntel: fleetIntelData, squadronIntel: squadronIntelData
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
  if colony.starbaseIds.len == 0:
    return none(StarbaseIntelReport)

  # Get target house data
  let targetHouseOpt = state.house(colony.owner)
  if targetHouseOpt.isNone:
    return none(StarbaseIntelReport)

  let targetHouse = targetHouseOpt.get()

  var report = StarbaseIntelReport(
    starbaseId: StarbaseId(targetSystem), # Using system ID as starbase identifier
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
  let maxAccum = max(
    [
      targetHouse.techTree.accumulated.economic,
      targetHouse.techTree.accumulated.science, totalTRP,
    ]
  )

  if maxAccum == targetHouse.techTree.accumulated.economic:
    report.currentResearch = some("Economic")
  elif maxAccum == targetHouse.techTree.accumulated.science:
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
