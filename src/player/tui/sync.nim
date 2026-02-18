## TUI state synchronization helpers
##
## Converts engine state and player state into SAM model data.

import std/[options, tables, algorithm, deques, sets, heapqueue]

import ../../engine/types/[core, colony, fleet, ship, facilities, player_state as
  ps_types, diplomacy, starmap, capacity, ground_unit, combat]
import ../../engine/state/[engine, iterators, player_state]
import ../../engine/systems/capacity/[c2_pool, construction_docks]
import ../../engine/systems/production/engine as production_engine
import ../../engine/systems/fleet/movement
import ../sam/sam_pkg
import ../sam/client_limits
import ../tui/adapters
import ../tui/widget/overview
import ../tui/hex_labels
import ../tui/widget/hexmap/symbols

# Forward declaration for PlayerState sync helpers
proc syncPlanetsRows*(model: var TuiModel, ps: PlayerState)
proc syncIntelRows*(model: var TuiModel, ps: PlayerState)
proc applyIntelNotes*(model: var TuiModel, notes: Table[int, string])

proc fleetNeedsAttention(
    hasCrippled: bool,
    isIdle: bool,
    hasSupportShips: bool,
    hasCombatShips: bool
): bool =
  hasCrippled or isIdle or (hasSupportShips and not hasCombatShips)

proc syncKnownEnemyColonies(
    model: var TuiModel,
    ps: ps_types.PlayerState
) =
  model.view.knownEnemyColonySystemIds = initHashSet[int]()
  for colony in ps.visibleColonies:
    if colony.owner == ps.viewingHouse:
      continue
    if colony.owner in ps.eliminatedHouses:
      continue
    model.view.knownEnemyColonySystemIds.incl(
      int(colony.systemId)
    )

proc syncGameStateToModel*(
    model: var TuiModel,
    state: GameState,
    viewingHouse: HouseId
) =
  ## Sync game state into the SAM TuiModel
  let house = state.house(viewingHouse).get()

  model.view.turn = state.turn
  model.view.viewingHouse = int(viewingHouse)
  model.view.houseName = house.name
  model.view.treasury = house.treasury.int
  model.view.espionageEbpPool = some(int(house.espionageBudget.ebpPoints))
  model.view.espionageCipPool = some(int(house.espionageBudget.cipPoints))
  model.view.prestige = house.prestige.int
  model.view.alertCount = 0
  # unreadMessages managed via local cache

  # Production (from last income report if available)
  if house.latestIncomeReport.isSome:
    model.view.production = house.latestIncomeReport.get().totalNet.int
  else:
    model.view.production = 0

  model.view.houseTaxRate = house.taxPolicy.currentRate.int
  model.view.techLevels = some(house.techTree.levels)
  model.view.researchPoints = some(house.techTree.accumulated)

  var colonyReports = initTable[ColonyId, ColonyIncomeReport]()
  if house.latestIncomeReport.isSome:
    for report in house.latestIncomeReport.get().colonies:
      colonyReports[report.colonyId] = report

  # Command capacity (C2 pool)
  let c2Analysis = analyzeC2Capacity(state, viewingHouse)
  model.view.commandUsed = c2Analysis.totalFleetCC.int
  model.view.commandMax = c2Analysis.c2Pool.int
  model.view.colonyLimits.clear()
  model.view.planetBreakersInFleets = 0
  for colony in state.coloniesOwned(viewingHouse):
    var snapshot = ColonyLimitSnapshot(
      industrialUnits: int(colony.industrial.units),
      fighters: colony.fighterIds.len,
      spaceports: 0,
      starbases: 0,
      shields: 0,
    )
    for neoriaId in colony.neoriaIds:
      let neoriaOpt = state.neoria(neoriaId)
      if neoriaOpt.isSome and
          neoriaOpt.get().neoriaClass == NeoriaClass.Spaceport:
        snapshot.spaceports.inc
    for kastraId in colony.kastraIds:
      let kastraOpt = state.kastra(kastraId)
      if kastraOpt.isSome and
          kastraOpt.get().kastraClass == KastraClass.Starbase:
        snapshot.starbases.inc
    for groundUnitId in colony.groundUnitIds:
      let groundOpt = state.groundUnit(groundUnitId)
      if groundOpt.isSome and
          groundOpt.get().stats.unitType == GroundClass.PlanetaryShield:
        snapshot.shields.inc
    model.view.colonyLimits[int(colony.id)] = snapshot
  for fleet in state.fleetsOwned(viewingHouse):
    for shipId in fleet.ships:
      let shipOpt = state.ship(shipId)
      if shipOpt.isSome and
          shipOpt.get().shipClass == ShipClass.PlanetBreaker:
        model.view.planetBreakersInFleets.inc

  # Prestige rank and total houses
  var prestigeList: seq[tuple[id: HouseId, prestige: int32]] = @[]
  for otherHouse in state.allHouses():
    prestigeList.add((id: otherHouse.id, prestige: otherHouse.prestige))
  prestigeList.sort(
    proc(a, b: tuple[id: HouseId, prestige: int32]): int =
      result = cmp(b.prestige, a.prestige)
      if result == 0:
        result = cmp(int(a.id), int(b.id))
  )
  model.view.totalHouses = prestigeList.len
  model.view.prestigeRank = 0
  for i, entry in prestigeList:
    if entry.id == viewingHouse:
      model.view.prestigeRank = i + 1
      break

  # Build systems table from fog-of-war map data
  let mapData = toFogOfWarMapData(state, viewingHouse)
  model.view.systems.clear()
  model.view.systemCoords.clear()
  model.view.maxRing = mapData.maxRing

  for coord, sysInfo in mapData.systems.pairs:
    let samSys = sam_pkg.SystemInfo(
      id: sysInfo.id,
      name: sysInfo.name,
      coords: (coord.q, coord.r),
      ring: sysInfo.ring,
      planetClass: sysInfo.planetClass,
      resourceRating: sysInfo.resourceRating,
      owner: sysInfo.owner,
      isHomeworld: sysInfo.isHomeworld,
      isHub: sysInfo.isHub,
      fleetCount: sysInfo.fleetCount,
    )
    model.view.systems[(coord.q, coord.r)] = samSys
    model.view.systemCoords[sysInfo.id] =
      (coord.q, coord.r)

    # Track homeworld
    if sysInfo.isHomeworld and sysInfo.owner.isSome and
        sysInfo.owner.get == int(viewingHouse):
      model.view.homeworld = some((coord.q, coord.r))

  # Build colonies list
  model.view.colonies = @[]
  for colony in state.coloniesOwned(viewingHouse):
    let sysOpt = state.system(colony.systemId)
    var sysName = "???"
    var sectorLabel = "?"
    var planetClass = 0
    if sysOpt.isSome:
      let sys = sysOpt.get()
      sysName = sys.name
      sectorLabel = coordLabel(int(sys.coords.q), int(sys.coords.r))
      planetClass = ord(sys.planetClass)

    let taxRate =
      if colony.taxRate > 0:
        colony.taxRate
      else:
        house.taxPolicy.currentRate

    var colonyWithTax = colony
    colonyWithTax.taxRate = taxRate
    let gco = state.calculateGrossOutput(
      colonyWithTax,
      house.techTree.levels.el,
      house.techTree.levels.cst
    )
    let ncv = production_engine.calculateNetValue(gco, taxRate)

    var growthPu = none(float32)
    if colonyReports.hasKey(colony.id):
      let report = colonyReports[colony.id]
      let growth = float32(colony.populationUnits) *
        (report.populationGrowth / 100.0'f32)
      growthPu = some(growth)

    let capacities = state.analyzeColonyCapacity(colony.id)
    var constructionTotal = 0
    var constructionUsed = 0
    var repairTotal = 0
    var repairUsed = 0
    for facility in capacities:
      let maxDocks =
        if facility.isCrippled:
          0'i32
        else:
          facility.maxDocks
      let usedDocks = min(facility.usedDocks, maxDocks)
      case facility.facilityType
      of NeoriaClass.Spaceport, NeoriaClass.Shipyard:
        constructionTotal += int(maxDocks)
        constructionUsed += int(usedDocks)
      of NeoriaClass.Drydock:
        repairTotal += int(maxDocks)
        repairUsed += int(usedDocks)

    let constructionAvailable =
      max(0, constructionTotal - constructionUsed)
    let repairAvailable = max(0, repairTotal - repairUsed)
    let hasConstruction =
      state.constructionProjectsAtColony(colony.id).len > 0
    let idleConstruction =
      constructionAvailable > 0 and constructionTotal > 0 and
      not hasConstruction

    model.view.colonies.add(
      sam_pkg.ColonyInfo(
        colonyId: int(colony.id),
        systemId: int(colony.systemId),
        systemName: sysName,
        sectorLabel: sectorLabel,
        planetClass: planetClass,
        populationUnits: colony.populationUnits.int,
        industrialUnits: colony.industrial.units.int,
        grossOutput: gco.int,
        netValue: ncv.int,
        populationGrowthPu: growthPu,
        constructionDockAvailable: constructionAvailable,
        constructionDockTotal: constructionTotal,
        repairDockAvailable: repairAvailable,
        repairDockTotal: repairTotal,
        blockaded: colony.blockaded,
        idleConstruction: idleConstruction,
        autoRepair: colony.autoRepair,
        autoLoadMarines: colony.autoLoadMarines,
        autoLoadFighters: colony.autoLoadFighters,
        owner: int(viewingHouse),
      )
    )

  # Build fleets list
  model.view.fleets = @[]
  for fleet in state.fleetsOwned(viewingHouse):
    let sysOpt = state.system(fleet.location)
    var locName = "???"
    var sectorLabel = "?"
    if sysOpt.isSome:
      let sys = sysOpt.get()
      locName = sys.name
      sectorLabel = coordLabel(int(sys.coords.q), int(sys.coords.r))
    let cmdType = int(fleet.command.commandType)
    var destLabel = "-"
    var destSystemId = 0
    var eta = 0
    if fleet.command.commandType == FleetCommandType.JoinFleet and
        fleet.command.targetFleet.isSome:
      let targetId = fleet.command.targetFleet.get()
      let targetOpt = state.fleet(targetId)
      if targetOpt.isSome:
        destLabel = "Fleet " & targetOpt.get().name
      else:
        destLabel = "Fleet " & $targetId
    elif fleet.command.targetSystem.isSome:
      let targetId = fleet.command.targetSystem.get()
      destSystemId = int(targetId)
      let targetOpt = state.system(targetId)
      if targetOpt.isSome:
        let target = targetOpt.get()
        destLabel = coordLabel(int(target.coords.q), int(target.coords.r))
      else:
        destLabel = $targetId
      let path = state.findPath(
        fleet.location, targetId, fleet
      )
      if path.found:
        let etaOpt = state.calculateETA(
          fleet.location, targetId,
          fleet, viewingHouse,
        )
        if etaOpt.isSome:
          eta = etaOpt.get()
    var statusLabel = "Active"
    case fleet.status
    of FleetStatus.Active:
      statusLabel = "Active"
    of FleetStatus.Reserve:
      statusLabel = "Reserve"
    of FleetStatus.Mothballed:
      statusLabel = "Mothballed"
    var hasCrippled = false
    var hasCombatShips = false
    var hasSupportShips = false
    var hasScouts = false
    var hasTroopTransports = false
    var hasEtacs = false
    var attackStr = 0
    var defenseStr = 0
    for shipId in fleet.ships:
      let shipOpt = state.ship(shipId)
      if shipOpt.isNone:
        continue
      let ship = shipOpt.get()
      if ship.state == CombatState.Crippled:
        hasCrippled = true
      if ship.state != CombatState.Destroyed:
        attackStr += int(ship.stats.attackStrength)
        defenseStr += int(ship.stats.defenseStrength)
      case ship.shipClass
      of ShipClass.ETAC:
        hasSupportShips = true
        hasEtacs = true
      of ShipClass.TroopTransport:
        hasSupportShips = true
        hasTroopTransports = true
      of ShipClass.Scout:
        hasScouts = true
      else:
        hasCombatShips = true
    let isScoutOnly = hasScouts and not hasCombatShips and not hasSupportShips
    # Compute SeekHome target: nearest friendly colony with drydocks
    var seekHome = none(int)
    block seekHomeCalc:
      var bestCost = high(uint32)
      var bestId = none(int)
      var fallbackCost = high(uint32)
      var fallbackId = none(int)
      for colony in state.coloniesOwned(viewingHouse):
        let path = state.findPath(
          fleet.location, colony.systemId, fleet)
        if path.found:
          if colony.repairDocks > 0:
            if path.totalCost < bestCost:
              bestCost = path.totalCost
              bestId = some(int(colony.systemId))
          if path.totalCost < fallbackCost:
            fallbackCost = path.totalCost
            fallbackId = some(int(colony.systemId))
      if bestId.isSome:
        seekHome = bestId
      else:
        seekHome = fallbackId
    var info = sam_pkg.FleetInfo(
        id: int(fleet.id),
        name: fleet.name,
        location: int(fleet.location),
        locationName: locName,
        sectorLabel: sectorLabel,
        shipCount: fleet.ships.len,
        owner: int(viewingHouse),
        command: cmdType,
        commandLabel: sam_pkg.commandLabel(cmdType),
        isIdle: fleet.command.commandType == FleetCommandType.Hold,
        roe: int(fleet.roe),
        attackStrength: attackStr,
        defenseStrength: defenseStr,
        statusLabel: statusLabel,
        destinationLabel: destLabel,
        destinationSystemId: destSystemId,
        eta: eta,
        hasCrippled: hasCrippled,
        hasCombatShips: hasCombatShips,
        hasSupportShips: hasSupportShips,
        hasScouts: hasScouts,
        hasTroopTransports: hasTroopTransports,
        hasEtacs: hasEtacs,
        isScoutOnly: isScoutOnly,
        seekHomeTarget: seekHome,
        needsAttention: false,
      )
    info.needsAttention = fleetNeedsAttention(
      info.hasCrippled,
      info.isIdle,
      info.hasSupportShips,
      info.hasCombatShips,
    )
    model.view.fleets.add(info)

  # Populate lane/ownership data for client-side ETA
  model.view.laneTypes.clear()
  model.view.laneNeighbors.clear()
  model.view.ownedSystemIds = initHashSet[int]()
  for lane in state.starMap.lanes.data:
    let src = int(lane.source)
    let dst = int(lane.destination)
    let lt = int(lane.laneType)
    # Bidirectional: lanes.data stores each lane
    # once but graph must be traversable both ways
    model.view.laneTypes[(src, dst)] = lt
    model.view.laneTypes[(dst, src)] = lt
    if src notin model.view.laneNeighbors:
      model.view.laneNeighbors[src] = @[]
    model.view.laneNeighbors[src].add(dst)
    if dst notin model.view.laneNeighbors:
      model.view.laneNeighbors[dst] = @[]
    model.view.laneNeighbors[dst].add(src)
  for colony in state.coloniesOwned(viewingHouse):
    model.view.ownedSystemIds.incl(
      int(colony.systemId)
    )

  let playerState = state.createPlayerState(viewingHouse)
  model.syncKnownEnemyColonies(playerState)

proc hexDistance(
    visibleSystems: Table[SystemId, ps_types.VisibleSystem],
    a: SystemId,
    b: SystemId,
): uint32 =
  ## Hex distance heuristic for A* from VisibleSystem
  ## coordinates. Falls back to 1 if coords missing.
  if visibleSystems.hasKey(a) and
      visibleSystems.hasKey(b):
    let ca = visibleSystems[a].coordinates
    let cb = visibleSystems[b].coordinates
    if ca.isSome and cb.isSome:
      let dq = abs(int(ca.get().q) - int(cb.get().q))
      let dr = abs(int(ca.get().r) - int(cb.get().r))
      let ds = abs(
        (-int(ca.get().q) - int(ca.get().r)) -
        (-int(cb.get().q) - int(cb.get().r))
      )
      return uint32(max(dq, max(dr, ds)))
  return 1'u32

proc findPathPS(
    neighbors: Table[SystemId, seq[SystemId]],
    connInfo: Table[
      (SystemId, SystemId), LaneClass
    ],
    visibleSystems: Table[
      SystemId, ps_types.VisibleSystem
    ],
    start: SystemId,
    goal: SystemId,
): (bool, seq[SystemId]) =
  ## A* pathfinding using PlayerState lane data.
  ## Returns (found, path).
  if start == goal:
    return (true, @[start])

  var openSet: HeapQueue[tuple[f: uint32, system: SystemId]]
  var cameFrom: Table[SystemId, SystemId]
  var gScore: Table[SystemId, uint32]

  gScore[start] = 0'u32
  let h = hexDistance(visibleSystems, start, goal)
  openSet.push((h, start))

  while openSet.len > 0:
    let current = openSet.pop().system
    if current == goal:
      var path: seq[SystemId] = @[current]
      var node = current
      while node != start:
        node = cameFrom[node]
        path.insert(node, 0)
      return (true, path)

    let neighs =
      neighbors.getOrDefault(current, @[])
    for neighbor in neighs:
      let lc = connInfo.getOrDefault(
        (current, neighbor), LaneClass.Minor
      )
      let edgeCost =
        case lc
        of LaneClass.Major: 1'u32
        of LaneClass.Minor: 2'u32
        of LaneClass.Restricted: 3'u32
      let tentG = gScore[current] + edgeCost
      if neighbor notin gScore or
          tentG < gScore[neighbor]:
        cameFrom[neighbor] = current
        gScore[neighbor] = tentG
        let fVal = tentG + hexDistance(
          visibleSystems, neighbor, goal
        )
        openSet.push((fVal, neighbor))

  return (false, @[])

proc calculateETAFromPS(
    neighbors: Table[SystemId, seq[SystemId]],
    connInfo: Table[
      (SystemId, SystemId), LaneClass
    ],
    ownedSystems: HashSet[SystemId],
    visibleSystems: Table[
      SystemId, ps_types.VisibleSystem
    ],
    fromSystem: SystemId,
    toSystem: SystemId,
): int =
  ## Calculate ETA using PlayerState data with
  ## turn-by-turn simulation matching engine rules.
  ## Returns 0 if unreachable or same system.
  if fromSystem == toSystem:
    return 0

  let (found, path) = findPathPS(
    neighbors, connInfo, visibleSystems,
    fromSystem, toSystem,
  )
  if not found:
    return 0

  var pos = 0
  var turns = 0

  while pos < path.len - 1:
    turns += 1
    var jumpsThisTurn = 1

    # Check 2-jump major lane rule
    if pos + 2 < path.len:
      var allOwned = true
      for i in pos .. min(pos + 2, path.len - 1):
        if path[i] notin ownedSystems:
          allOwned = false
          break

      if allOwned:
        var bothMajor = true
        for i in pos ..< pos + 2:
          let lc = connInfo.getOrDefault(
            (path[i], path[i + 1]),
            LaneClass.Minor,
          )
          if lc != LaneClass.Major:
            bothMajor = false
            break
        if bothMajor:
          jumpsThisTurn = 2

    pos += min(
      jumpsThisTurn, path.len - 1 - pos
    )

  return turns

# =============================================================================
# Fleet Console Data Sync (SystemView mode)
# =============================================================================
# Type definitions moved to tui_model.nim to support caching

proc syncFleetConsoleSystems*(
    ps: ps_types.PlayerState
): seq[FleetConsoleSystem] =
  ## Get list of systems that have fleets owned by viewing house
  result = @[]
  
  # Build a table of system ID -> fleet count
  var systemFleetCounts = initTable[SystemId, int]()
  for fleet in ps.ownFleets:
    let count = systemFleetCounts.getOrDefault(fleet.location, 0)
    systemFleetCounts[fleet.location] = count + 1
  
  # Convert to sorted list
  for systemId, count in systemFleetCounts.pairs:
    if not ps.visibleSystems.hasKey(systemId):
      continue
    
    let sys = ps.visibleSystems[systemId]
    let sectorLabel = if sys.coordinates.isSome:
      coordLabel(int(sys.coordinates.get().q), int(sys.coordinates.get().r))
    else:
      "?"
    
    result.add(FleetConsoleSystem(
      systemId: int(systemId),
      systemName: sys.name,
      sectorLabel: sectorLabel,
      fleetCount: count
    ))
  
  # Sort by system name
  result.sort(proc(a, b: FleetConsoleSystem): int =
    cmp(a.systemName, b.systemName))

proc syncFleetConsoleFleets*(
    ps: ps_types.PlayerState,
    systemId: SystemId,
    psNeighbors: Table[SystemId, seq[SystemId]],
    psConnInfo: Table[
      (SystemId, SystemId), LaneClass
    ],
    psOwnedSystems: HashSet[SystemId],
    needsAttentionByFleet: Table[int, bool],
): seq[FleetConsoleFleet] =
  ## Get list of fleets at a specific system for console
  result = @[]
  
  for fleet in ps.ownFleets:
    if fleet.location != systemId:
      continue
    
    # Calculate attack/defense strength and count ship types
    var attackStr = 0
    var defenseStr = 0
    var shipCount = 0
    var ttCount = 0
    var etacCount = 0
    var hasCrippled = false
    var hasCombatShips = false
    var hasSupportShips = false
    
    for shipId in fleet.ships:
      for ship in ps.ownShips:
        if ship.id == shipId and ship.state != CombatState.Destroyed:
          if ship.state == CombatState.Crippled:
            hasCrippled = true
          attackStr += int(ship.stats.attackStrength)
          defenseStr += int(ship.stats.defenseStrength)
          shipCount += 1
          
          # Count ship types
          if ship.shipClass == ShipClass.TroopTransport:
            ttCount += 1
            hasSupportShips = true
          elif ship.shipClass == ShipClass.ETAC:
            etacCount += 1
            hasSupportShips = true
          elif ship.shipClass != ShipClass.Scout:
            hasCombatShips = true
          
          break
    
    # Get command label
    let cmdType = int(fleet.command.commandType)
    let cmdLabel = sam_pkg.commandLabel(cmdType)
    
    # Get destination and ETA
    var destLabel = ""
    var eta = 0
    if fleet.command.commandType == FleetCommandType.JoinFleet and
        fleet.command.targetFleet.isSome:
      let targetId = fleet.command.targetFleet.get()
      var targetName = ""
      for candidate in ps.ownFleets:
        if candidate.id == targetId:
          targetName = candidate.name
          break
      if targetName.len > 0:
        destLabel = "Fleet " & targetName
      else:
        destLabel = "Fleet " & $targetId
    elif fleet.command.targetSystem.isSome:
      let targetId = fleet.command.targetSystem.get()
      if ps.visibleSystems.hasKey(targetId):
        let target = ps.visibleSystems[targetId]
        if target.coordinates.isSome:
          destLabel = coordLabel(int(target.coordinates.get().q),
            int(target.coordinates.get().r))
      else:
        destLabel = $targetId
      eta = calculateETAFromPS(
        psNeighbors, psConnInfo,
        psOwnedSystems, ps.visibleSystems,
        fleet.location, targetId,
      )
    else:
      # For patrol/hold, show current location
      if ps.visibleSystems.hasKey(fleet.location):
        let sys = ps.visibleSystems[fleet.location]
        if sys.coordinates.isSome:
          destLabel = coordLabel(int(sys.coordinates.get().q),
            int(sys.coordinates.get().r))
    
    # Map fleet status to short string
    let statusStr = case fleet.status
      of FleetStatus.Active: "A"
      of FleetStatus.Reserve: "R"
      of FleetStatus.Mothballed: "M"
    
    let isIdle = fleet.command.commandType == FleetCommandType.Hold
    let needsAttention = if needsAttentionByFleet.hasKey(int(fleet.id)):
      needsAttentionByFleet[int(fleet.id)]
    else:
      fleetNeedsAttention(
        hasCrippled,
        isIdle,
        hasSupportShips,
        hasCombatShips,
      )
    
    result.add(FleetConsoleFleet(
      fleetId: int(fleet.id),
      name: fleet.name,
      shipCount: shipCount,
      attackStrength: attackStr,
      defenseStrength: defenseStr,
      troopTransports: ttCount,
      etacs: etacCount,
      commandLabel: cmdLabel,
      destinationLabel: destLabel,
      eta: eta,
      roe: int(fleet.roe),
      status: statusStr,
      needsAttention: needsAttention
    ))

proc syncPlayerStateToOverview*(
    ps: ps_types.PlayerState
): OverviewData =
  ## Convert PlayerState to Overview widget data
  result = initOverviewData()

  # === Leaderboard (from public information) ===
  for houseId, prestige in ps.housePrestige.pairs:
    # Use houseNames from PlayerState instead of querying GameState
    let houseName = ps.houseNames.getOrDefault(houseId, "Unknown")

    # Determine diplomatic status
    var status = DiplomaticStatus.Neutral
    if houseId == ps.viewingHouse:
      status = DiplomaticStatus.Self
    elif houseId in ps.eliminatedHouses:
      status = DiplomaticStatus.Eliminated
    else:
      # Check diplomatic relations
      let key = (ps.viewingHouse, houseId)
      if ps.diplomaticRelations.hasKey(key):
        let dipState = ps.diplomaticRelations[key]
        case dipState
        of DiplomaticState.Enemy:
          status = DiplomaticStatus.Enemy
        of DiplomaticState.Hostile:
          status = DiplomaticStatus.Hostile
        of DiplomaticState.Neutral:
          status = DiplomaticStatus.Neutral

    result.leaderboard.addEntry(
      houseId = int(houseId),
      name = houseName,
      prestige = prestige.int,
      colonies = ps.houseColonyCounts.getOrDefault(houseId, 0).int,
      status = status,
      isPlayer = (houseId == ps.viewingHouse),
    )

  result.leaderboard.sortAndRank()
  result.leaderboard.totalSystems = ps.visibleSystems.len

  # Calculate total colonized systems (sum of all house colony counts)
  var totalColonized = 0
  for _, count in ps.houseColonyCounts.pairs:
    totalColonized += count.int
  result.leaderboard.colonizedSystems = totalColonized

  # === Empire Status ===
  result.empireStatus.coloniesOwned = ps.ownColonies.len

  if ps.taxRate.isSome:
    result.empireStatus.taxRate = ps.taxRate.get().int
  elif ps.ownColonies.len > 0 and ps.ownColonies[0].taxRate > 0:
    result.empireStatus.taxRate = ps.ownColonies[0].taxRate.int
  else:
    result.empireStatus.taxRate = 0

  # Fleet counts by status
  for fleet in ps.ownFleets:
    case fleet.status
    of FleetStatus.Active:
      result.empireStatus.fleetsActive.inc
    of FleetStatus.Reserve:
      result.empireStatus.fleetsReserve.inc
    of FleetStatus.Mothballed:
      result.empireStatus.fleetsMothballed.inc

  # Intel - count known vs fogged systems
  for _, visSys in ps.visibleSystems.pairs:
    case visSys.visibility
    of VisibilityLevel.None:
      result.empireStatus.foggedSystems.inc
    else:
      result.empireStatus.knownSystems.inc

  # Diplomacy counts
  for (pair, dipState) in ps.diplomaticRelations.pairs:
    if pair[0] != ps.viewingHouse:
      continue
    case dipState
    of DiplomaticState.Neutral:
      result.empireStatus.neutralHouses.inc
    of DiplomaticState.Hostile:
      result.empireStatus.hostileHouses.inc
    of DiplomaticState.Enemy:
      result.empireStatus.enemyHouses.inc

  # === Action Queue - detect idle fleets ===
  var idleFleets: seq[Fleet] = @[]
  for fleet in ps.ownFleets:
    if fleet.command.commandType == FleetCommandType.Hold and
        fleet.status == FleetStatus.Active:
      idleFleets.add(fleet)
      result.actionQueue.addChecklistItem(
        description = "Fleet " & fleet.name & " awaiting orders",
        isDone = false,
        priority = ActionPriority.Warning,
      )

  if idleFleets.len > 0:
      result.actionQueue.addAction(
        description = $idleFleets.len & " fleet(s) awaiting orders",
        priority = ActionPriority.Warning,
        jumpView = 3,
        jumpLabel = "F",
      )

  # Placeholder recent events
  if result.recentEvents.len == 0:
    result.addEvent(ps.turn, "No recent events", false)

proc bfsDistance(
    visibleSystems: Table[SystemId, ps_types.VisibleSystem],
    start: SystemId,
    goal: SystemId
): Option[uint32] =
  ## Unweighted BFS distance between two systems using
  ## PlayerState lane adjacency data. Returns none if
  ## no path exists.
  if start == goal:
    return some(0'u32)
  var visited = initTable[SystemId, uint32]()
  var queue = initDeque[SystemId]()
  visited[start] = 0
  queue.addLast(start)
  while queue.len > 0:
    let current = queue.popFirst()
    let dist = visited[current]
    if visibleSystems.hasKey(current):
      for neighbor in visibleSystems[current].jumpLaneIds:
        if neighbor == goal:
          return some(dist + 1)
        if neighbor notin visited:
          visited[neighbor] = dist + 1
          queue.addLast(neighbor)
  return none(uint32)

proc syncPlayerStateToModel*(
    model: var TuiModel,
    ps: ps_types.PlayerState
) =
  ## Sync PlayerState (fog-of-war filtered) into the SAM TuiModel
  ## Used for Nostr games where we only have PlayerState, not full GameState
  ##
  ## Note: PlayerState has limited visibility data. Some model fields
  ## (treasury, production, system names/details) may not be available.
  
  model.view.turn = ps.turn
  model.view.viewingHouse = int(ps.viewingHouse)
  model.view.houseName =
    ps.houseNames.getOrDefault(ps.viewingHouse, "Unknown")
  model.view.houseNames = initTable[int, string]()
  for houseId, name in ps.houseNames.pairs:
    model.view.houseNames[int(houseId)] = name
  if ps.treasuryBalance.isSome:
    model.view.treasury = ps.treasuryBalance.get().int
  else:
    model.view.treasury = 0
  if ps.ebpPool.isSome:
    model.view.espionageEbpPool = some(int(ps.ebpPool.get()))
  else:
    model.view.espionageEbpPool = none(int)
  if ps.cipPool.isSome:
    model.view.espionageCipPool = some(int(ps.cipPool.get()))
  else:
    model.view.espionageCipPool = none(int)
  model.view.prestige =
    ps.housePrestige.getOrDefault(ps.viewingHouse, 0).int
  model.view.alertCount = 0
  # unreadMessages managed via local cache
  if ps.netIncome.isSome:
    model.view.production = ps.netIncome.get().int
  else:
    model.view.production = 0
  if ps.taxRate.isSome:
    model.view.houseTaxRate = ps.taxRate.get().int
  elif ps.ownColonies.len > 0 and ps.ownColonies[0].taxRate > 0:
    model.view.houseTaxRate = ps.ownColonies[0].taxRate.int
  else:
    model.view.houseTaxRate = 0
  model.view.techLevels = ps.techLevels
  model.view.researchPoints = ps.researchPoints
  model.view.colonyLimits = colonyLimitSnapshotsFromPlayerState(ps)
  model.view.planetBreakersInFleets = countPlanetBreakersInFleets(ps)
  let c2 = computeBaseC2FromPlayerState(ps)
  model.view.commandUsed = c2.used
  model.view.commandMax = c2.max

  # Build lane lookup structures from jumpLanes
  var psNeighbors = initTable[SystemId, seq[SystemId]]()
  var psConnInfo =
    initTable[(SystemId, SystemId), LaneClass]()
  for lane in ps.jumpLanes:
    # Bidirectional: jumpLanes stores each lane
    # once but graph must be traversable both ways
    psConnInfo[(lane.source, lane.destination)] =
      lane.laneType
    psConnInfo[(lane.destination, lane.source)] =
      lane.laneType
    if lane.source notin psNeighbors:
      psNeighbors[lane.source] = @[]
    psNeighbors[lane.source].add(lane.destination)
    if lane.destination notin psNeighbors:
      psNeighbors[lane.destination] = @[]
    psNeighbors[lane.destination].add(lane.source)

  # Build owned system set for 2-jump rule
  var psOwnedSystems = initHashSet[SystemId]()
  for colony in ps.ownColonies:
    psOwnedSystems.incl(colony.systemId)
  
  # Build systems table from visible systems
  # VisibleSystem only has: id, name, visibility, lastScoutedTurn, coordinates
  model.view.systems.clear()
  model.view.systemCoords.clear()
  model.view.maxRing = 0
  
  for sysId, visSys in ps.visibleSystems.pairs:
    if visSys.coordinates.isNone:
      continue  # Skip systems without coordinates
    let coords = visSys.coordinates.get()
    let hexQ = int(coords.q)
    let hexR = int(coords.r)
    let ring = max(abs(hexQ), max(abs(hexR), abs(-hexQ - hexR)))
    if ring > model.view.maxRing:
      model.view.maxRing = ring
    
    # Limited info from VisibleSystem
    let sysName =
      if visSys.name.len > 0:
        visSys.name
      else:
        "System " & $sysId.uint32
    let samSys = sam_pkg.SystemInfo(
      id: int(sysId),
      name: sysName,
      coords: (hexQ, hexR),
      ring: ring,
      planetClass: 0,  # Not in VisibleSystem
      resourceRating: 0,  # Not in VisibleSystem
      owner: none(int),  # Not in VisibleSystem
      isHomeworld: false,  # Not in VisibleSystem
      isHub: false,
      fleetCount: 0,  # Not in VisibleSystem
    )
    model.view.systems[(hexQ, hexR)] = samSys
    model.view.systemCoords[int(sysId)] =
      (hexQ, hexR)
  
  # Build colonies list from own colonies
  model.view.colonies = @[]
  for colony in ps.ownColonies:
    var sysName = "System " & $colony.systemId.uint32
    var sectorLabel = "?"
    if ps.visibleSystems.hasKey(colony.systemId):
      let visSys = ps.visibleSystems[colony.systemId]
      if visSys.coordinates.isSome:
        let coords = visSys.coordinates.get()
        if visSys.name.len > 0:
          sysName = visSys.name
        else:
          sysName = "(" & $coords.q & "," & $coords.r & ")"
        sectorLabel = coordLabel(int(coords.q), int(coords.r))
    model.view.colonies.add(
      sam_pkg.ColonyInfo(
        colonyId: int(colony.id),
        systemId: int(colony.systemId),
        systemName: sysName,
        sectorLabel: sectorLabel,
        planetClass: -1,
        populationUnits: colony.populationUnits.int,
        industrialUnits: colony.industrial.units.int,
        grossOutput: colony.grossOutput.int,
        netValue: 0,
        populationGrowthPu: none(float32),
        constructionDockAvailable: 0,
        constructionDockTotal: 0,
        repairDockAvailable: 0,
        repairDockTotal: 0,
        blockaded: colony.blockaded,
        idleConstruction: false,
        autoRepair: colony.autoRepair,
        autoLoadMarines: colony.autoLoadMarines,
        autoLoadFighters: colony.autoLoadFighters,
        owner: int(ps.viewingHouse),
      )
    )
  
  # Build fleets list from own fleets
  model.view.fleets = @[]
  for fleet in ps.ownFleets:
    var locName = "System " & $fleet.location.uint32
    var sectorLabel = "?"
    if ps.visibleSystems.hasKey(fleet.location):
      let visSys = ps.visibleSystems[fleet.location]
      if visSys.coordinates.isSome:
        let coords = visSys.coordinates.get()
        if visSys.name.len > 0:
          locName = visSys.name
        else:
          locName = "(" & $coords.q & "," & $coords.r & ")"
        sectorLabel = coordLabel(coords.q.int, coords.r.int)
    let cmdType = int(fleet.command.commandType)
    var destLabel = "-"
    var destSystemId = 0
    var eta = 0
    if fleet.command.commandType == FleetCommandType.JoinFleet and
        fleet.command.targetFleet.isSome:
      let targetId = fleet.command.targetFleet.get()
      var targetName = ""
      for candidate in ps.ownFleets:
        if candidate.id == targetId:
          targetName = candidate.name
          break
      if targetName.len > 0:
        destLabel = "Fleet " & targetName
      else:
        destLabel = "Fleet " & $targetId
    elif fleet.command.targetSystem.isSome:
      let targetId = fleet.command.targetSystem.get()
      destSystemId = int(targetId)
      if ps.visibleSystems.hasKey(targetId):
        let target = ps.visibleSystems[targetId]
        if target.coordinates.isSome:
          destLabel = coordLabel(int(target.coordinates.get().q),
            int(target.coordinates.get().r))
      else:
        destLabel = $targetId
      eta = calculateETAFromPS(
        psNeighbors, psConnInfo,
        psOwnedSystems, ps.visibleSystems,
        fleet.location, targetId,
      )
    var statusLabel = "Active"
    case fleet.status
    of FleetStatus.Active:
      statusLabel = "Active"
    of FleetStatus.Reserve:
      statusLabel = "Reserve"
    of FleetStatus.Mothballed:
      statusLabel = "Mothballed"
    var hasCrippled = false
    var hasCombatShips = false
    var hasSupportShips = false
    var hasScouts = false
    var hasTroopTransports = false
    var hasEtacs = false
    var attackStr = 0
    var defenseStr = 0
    for shipId in fleet.ships:
      for ship in ps.ownShips:
        if ship.id == shipId:
          if ship.state == CombatState.Crippled:
            hasCrippled = true
          if ship.state != CombatState.Destroyed:
            attackStr += int(ship.stats.attackStrength)
            defenseStr += int(ship.stats.defenseStrength)
          case ship.shipClass
          of ShipClass.ETAC:
            hasSupportShips = true
            hasEtacs = true
          of ShipClass.TroopTransport:
            hasSupportShips = true
            hasTroopTransports = true
          of ShipClass.Scout:
            hasScouts = true
          else:
            hasCombatShips = true
          break
    let isScoutOnly = hasScouts and not hasCombatShips and not hasSupportShips
    # Compute SeekHome target via BFS over lane adjacency
    var seekHome = none(int)
    block seekHomeCalc:
      var bestDist = high(uint32)
      var bestId = none(int)
      var fallbackDist = high(uint32)
      var fallbackId = none(int)
      for colony in ps.ownColonies:
        let d = bfsDistance(
          ps.visibleSystems, fleet.location,
          colony.systemId)
        if d.isSome:
          if colony.repairDocks > 0:
            if d.get() < bestDist:
              bestDist = d.get()
              bestId = some(int(colony.systemId))
          if d.get() < fallbackDist:
            fallbackDist = d.get()
            fallbackId = some(int(colony.systemId))
      if bestId.isSome:
        seekHome = bestId
      else:
        seekHome = fallbackId
    var info = sam_pkg.FleetInfo(
        id: int(fleet.id),
        name: fleet.name,
        location: int(fleet.location),
        locationName: locName,
        sectorLabel: sectorLabel,
        shipCount: fleet.ships.len,
        owner: int(ps.viewingHouse),
        command: cmdType,
        commandLabel: sam_pkg.commandLabel(cmdType),
        isIdle: fleet.command.commandType == FleetCommandType.Hold,
        roe: int(fleet.roe),
        attackStrength: attackStr,
        defenseStrength: defenseStr,
        statusLabel: statusLabel,
        destinationLabel: destLabel,
        destinationSystemId: destSystemId,
        eta: eta,
        hasCrippled: hasCrippled,
        hasCombatShips: hasCombatShips,
        hasSupportShips: hasSupportShips,
        hasScouts: hasScouts,
        hasTroopTransports: hasTroopTransports,
        hasEtacs: hasEtacs,
        isScoutOnly: isScoutOnly,
        seekHomeTarget: seekHome,
        needsAttention: false,
      )
    info.needsAttention = fleetNeedsAttention(
      info.hasCrippled,
      info.isIdle,
      info.hasSupportShips,
      info.hasCombatShips,
    )
    model.view.fleets.add(info)
  
  # Populate lane/ownership data for client-side ETA
  model.view.laneTypes.clear()
  model.view.laneNeighbors.clear()
  model.view.ownedSystemIds = initHashSet[int]()
  for lane in ps.jumpLanes:
    let src = int(lane.source)
    let dst = int(lane.destination)
    let lt = int(lane.laneType)
    # Bidirectional: jumpLanes stores each lane
    # once but graph must be traversable both ways
    model.view.laneTypes[(src, dst)] = lt
    model.view.laneTypes[(dst, src)] = lt
    if src notin model.view.laneNeighbors:
      model.view.laneNeighbors[src] = @[]
    model.view.laneNeighbors[src].add(dst)
    if dst notin model.view.laneNeighbors:
      model.view.laneNeighbors[dst] = @[]
    model.view.laneNeighbors[dst].add(src)
  for colony in ps.ownColonies:
    model.view.ownedSystemIds.incl(
      int(colony.systemId)
    )

  model.syncKnownEnemyColonies(ps)

  # Prestige rank
  var prestigeList: seq[tuple[id: HouseId, prestige: int32]] = @[]
  for houseId, prestige in ps.housePrestige.pairs:
    prestigeList.add((id: houseId, prestige: prestige))
  prestigeList.sort(
    proc(a, b: tuple[id: HouseId, prestige: int32]): int =
      result = cmp(b.prestige, a.prestige)
      if result == 0:
        result = cmp(int(a.id), int(b.id))
  )
  model.view.totalHouses = prestigeList.len
  model.view.prestigeRank = 0
  for i, entry in prestigeList:
    if entry.id == ps.viewingHouse:
      model.view.prestigeRank = i + 1
      break
  
  # Sync planets table data
  syncPlanetsRows(model, ps)
  # Sync intel database data
  syncIntelRows(model, ps)
  
  # Sync fleet console cached data for SystemView mode
  var needsAttentionByFleet = initTable[int, bool]()
  for fleet in model.view.fleets:
    needsAttentionByFleet[fleet.id] = fleet.needsAttention
  model.ui.fleetConsoleSystems = syncFleetConsoleSystems(ps)
  model.ui.fleetConsoleFleetsBySystem.clear()
  for sys in model.ui.fleetConsoleSystems:
    model.ui.fleetConsoleFleetsBySystem[sys.systemId] = 
      syncFleetConsoleFleets(
        ps, SystemId(sys.systemId),
        psNeighbors, psConnInfo, psOwnedSystems,
        needsAttentionByFleet,
      )

# =============================================================================
# Planets Table Sync (PlayerState-only)
# =============================================================================

proc formatLtu[K](table: Table[K, int32], key: K): string =
  ## Format Last Turn Updated as "T##" or "---"
  if table.hasKey(key):
    "T" & $table[key]
  else:
    "---"

proc planetClassName(classValue: int32): string =
  ## Get planet class acronym from int32 value
  let idx = int(classValue)
  if idx >= 0 and idx < PlanetClassNames.len:
    case PlanetClassNames[idx]
    of "Eden": "EDN"
    of "Lush": "LSH"
    of "Benign": "BEN"
    of "Harsh": "HRH"
    of "Hostile": "HOS"
    of "Desolate": "DES"
    of "Extreme": "EXT"
    else: "???"
  else:
    "???"

proc resourceRatingName(ratingValue: int32): string =
  ## Get resource rating acronym from int32 value
  let idx = int(ratingValue)
  if idx >= 0 and idx < ResourceRatingNames.len:
    case ResourceRatingNames[idx]
    of "Very Poor": "VPR"
    of "Poor": "POR"
    of "Abundant": "ABN"
    of "Rich": "RCH"
    of "Very Rich": "VRH"
    else: "???"
  else:
    "???"

proc buildStatusLabel(colony: Colony): string =
  ## Build status label for colony (BLK, CAP, DMG, RPR, TF, CN, OK)
  var flags: seq[string] = @[]
  if colony.blockaded:
    flags.add("BLK")
  if colony.capacityViolation.severity != ViolationSeverity.None:
    flags.add("CAP")
  if colony.infrastructureDamage > 0.0:
    flags.add("DMG")
  if colony.repairQueue.len > 0:
    flags.add("RPR")
  if colony.activeTerraforming.isSome:
    flags.add("TF")
  if colony.underConstruction.isSome or colony.constructionQueue.len > 0:
    flags.add("CN")
  if flags.len == 0:
    flags.add("OK")
  if flags.len == 1:
    result = flags[0]
  else:
    var label = flags[0]
    for i in 1 ..< flags.len:
      label &= ", " & flags[i]
    result = label

proc ltuLabelForSystem(ps: PlayerState, systemId: SystemId,
    colonyId: Option[ColonyId], isOwned: bool): string =
  ## Get LTU label with colony/system fallback rules
  if isOwned:
    return "T" & $ps.turn
  if colonyId.isSome:
    let id = colonyId.get()
    if ps.ltuColonies.hasKey(id):
      return "T" & $ps.ltuColonies[id]
  formatLtu(ps.ltuSystems, systemId)

proc buildOwnColonyRow(ps: PlayerState, colony: Colony): PlanetRow =
  ## Build PlanetRow from owned colony data
  let visSys = ps.visibleSystems.getOrDefault(colony.systemId)
  let coords = visSys.coordinates.get((0'i32, 0'i32))
  let ring = max(abs(coords.q), max(abs(coords.r), abs(-coords.q - coords.r)))

  var systemName = visSys.name
  if systemName.len == 0:
    systemName = "System " & $colony.systemId.uint32

  var groundCount = 0
  var batteryCount = 0
  var shieldPresent = false
  for unit in ps.ownGroundUnits:
    if unit.garrison.locationType != GroundUnitLocation.OnColony:
      continue
    if unit.garrison.colonyId != colony.id:
      continue
    case unit.stats.unitType
    of GroundClass.Army, GroundClass.Marine:
      groundCount.inc
    of GroundClass.GroundBattery:
      batteryCount.inc
    of GroundClass.PlanetaryShield:
      shieldPresent = true

  var fleetCount = 0
  for fleet in ps.ownFleets:
    if fleet.location == colony.systemId:
      fleetCount.inc

  result = PlanetRow(
    systemId: colony.systemId.int,
    colonyId: some(colony.id.int),
    systemName: systemName,
    sectorLabel: coordLabel(coords.q.int, coords.r.int),
    classLabel: planetClassName(visSys.planetClass),
    resourceLabel: resourceRatingName(visSys.resourceRating),
    pop: some(colony.populationUnits.int),
    iu: some(colony.industrial.units.int),
    gco: some(colony.grossOutput.int),
    ncv: none(int),  # Requires tax rate calculation not in PlayerState
    growthLabel: "---",  # Would need income report
    cdTotal: some(colony.constructionDocks.int),
    rdTotal: some(colony.repairDocks.int),
    fleetCount: fleetCount,
    starbaseCount: colony.kastraIds.len,
    groundCount: groundCount,
    batteryCount: batteryCount,
    shieldPresent: shieldPresent,
    statusLabel: buildStatusLabel(colony),
    isOwned: true,
    isHomeworld: ps.homeworldSystemId == some(colony.systemId),
    ring: ring.int,
    coordLabel: coordLabel(coords.q.int, coords.r.int),
    hasAlert: colony.blockaded,
  )

proc syncPlanetsRows*(model: var TuiModel, ps: PlayerState) =
  ## Build planetsRows from PlayerState only (owned colonies)
  ## Order: homeworld first, then owned alpha
  model.view.planetsRows = @[]
  var homeRow: Option[PlanetRow]
  var ownedRows: seq[PlanetRow]

  for colony in ps.ownColonies:
    let row = buildOwnColonyRow(ps, colony)
    if row.isHomeworld:
      homeRow = some(row)
    else:
      ownedRows.add(row)

  ownedRows.sort(proc(a, b: PlanetRow): int = cmp(a.sectorLabel, b.sectorLabel))

  if homeRow.isSome:
    model.view.planetsRows.add(homeRow.get)
  model.view.planetsRows &= ownedRows

proc visibilityLabel(vis: VisibilityLevel, isOwned: bool): string =
  ## Short label for Intel DB visibility
  if isOwned:
    return "OWN"
  case vis
  of VisibilityLevel.Owned:
    "OWN"
  of VisibilityLevel.Occupied:
    "OCC"
  of VisibilityLevel.Scouted:
    "SCT"
  of VisibilityLevel.Adjacent:
    "ADJ"
  of VisibilityLevel.None:
    "---"

type
  IntelOwnerInfo = tuple[
    colonyId: Option[ColonyId],
    ownerName: string,
    isOwned: bool,
    starbaseCount: Option[int]
  ]

proc syncIntelRows*(model: var TuiModel, ps: PlayerState) =
  ## Build Intel DB rows from PlayerState
  model.view.intelRows = @[]

  var colonyOwners = initTable[SystemId, IntelOwnerInfo]()
  let defaultOwner = (
    colonyId: none(ColonyId),
    ownerName: "---",
    isOwned: false,
    starbaseCount: none(int)
  )

  for colony in ps.ownColonies:
    let ownerName = ps.houseNames.getOrDefault(colony.owner, "You")
    colonyOwners[colony.systemId] = (
      colonyId: some(colony.id),
      ownerName: ownerName,
      isOwned: true,
      starbaseCount: some(colony.kastraIds.len)
    )

  for visColony in ps.visibleColonies:
    if colonyOwners.hasKey(visColony.systemId):
      continue
    let ownerName = ps.houseNames.getOrDefault(visColony.owner, "Unknown")
    let sbCount = if visColony.starbaseLevel.isSome:
        some(int(visColony.starbaseLevel.get))
      else:
        none(int)
    colonyOwners[visColony.systemId] = (
      colonyId: some(visColony.colonyId),
      ownerName: ownerName,
      isOwned: false,
      starbaseCount: sbCount
    )

  for systemId, visSys in ps.visibleSystems.pairs:
    let coords = visSys.coordinates.get((0'i32, 0'i32))
    let systemName =
      if visSys.name.len > 0:
        visSys.name
      else:
        "System " & $systemId.uint32
    let ownerInfo = colonyOwners.getOrDefault(systemId, defaultOwner)
    let ltuLabel = ltuLabelForSystem(
      ps, systemId, ownerInfo.colonyId, ownerInfo.isOwned
    )
    var notes = ""
    if ownerInfo.isOwned and ps.homeworldSystemId == some(systemId):
      notes = "Homeworld"

    model.view.intelRows.add(IntelRow(
      systemId: systemId.int,
      systemName: systemName,
      sectorLabel: coordLabel(coords.q.int, coords.r.int),
      ownerName: ownerInfo.ownerName,
      intelLabel: visibilityLabel(visSys.visibility, ownerInfo.isOwned),
      ltuLabel: ltuLabel,
      notes: notes,
      starbaseCount: ownerInfo.starbaseCount
    ))

  model.view.intelRows.sort(proc(a, b: IntelRow): int =
    let sysA = SystemId(a.systemId.uint32)
    let sysB = SystemId(b.systemId.uint32)
    let infoA = colonyOwners.getOrDefault(sysA, defaultOwner)
    let infoB = colonyOwners.getOrDefault(sysB, defaultOwner)
    let visA = ps.visibleSystems.getOrDefault(sysA)
    let visB = ps.visibleSystems.getOrDefault(sysB)
    let rankA =
      if infoA.isOwned:
        0
      else:
        case visA.visibility
        of VisibilityLevel.Occupied: 1
        of VisibilityLevel.Scouted: 2
        of VisibilityLevel.Adjacent: 3
        of VisibilityLevel.None: 4
        of VisibilityLevel.Owned: 1
    let rankB =
      if infoB.isOwned:
        0
      else:
        case visB.visibility
        of VisibilityLevel.Occupied: 1
        of VisibilityLevel.Scouted: 2
        of VisibilityLevel.Adjacent: 3
        of VisibilityLevel.None: 4
        of VisibilityLevel.Owned: 1
    result = cmp(rankA, rankB)
    if result == 0:
      result = cmp(a.sectorLabel, b.sectorLabel)
  )

proc applyIntelNotes*(model: var TuiModel, notes: Table[int, string]) =
  ## Overlay local note text onto synced intel rows.
  for idx, row in model.view.intelRows:
    model.view.intelRows[idx].notes =
      notes.getOrDefault(row.systemId, "")

proc syncBuildModalData*(
    model: var TuiModel,
    ps: PlayerState
) =
  ## Populate build modal availableOptions and dockSummary
  ## Called when build modal is active
  if not model.ui.buildModal.active:
    return

  let colonyId = ColonyId(model.ui.buildModal.colonyId)

  # Get colony name from PlayerState
  for colony in ps.ownColonies:
    if colony.id == colonyId:
      let visSys = ps.visibleSystems.getOrDefault(colony.systemId)
      model.ui.buildModal.colonyName = visSys.name
      break

  # Compute build options and dock summary
  let result = computeBuildOptionsFromPS(ps, colonyId)
  model.ui.buildModal.availableOptions = result.options
  model.ui.buildModal.dockSummary = result.dockSummary
  model.ui.buildModal.ppAvailable = model.view.treasury
  model.ui.buildModal.stagedBuildCommands = model.ui.stagedBuildCommands
  if ps.techLevels.isSome:
    model.ui.buildModal.cstLevel = ps.techLevels.get().cst
  else:
    model.ui.buildModal.cstLevel = 1
