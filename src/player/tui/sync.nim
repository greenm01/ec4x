## TUI state synchronization helpers
##
## Converts engine state and player state into SAM model data.

import std/[options, tables, algorithm]

import ../../engine/types/[core, colony, fleet, facilities, player_state as
  ps_types, diplomacy, starmap]
import ../../engine/state/[engine, iterators]
import ../../engine/systems/capacity/[c2_pool, construction_docks]
import ../../engine/systems/production/engine as production_engine
import ../sam/sam_pkg
import ../tui/adapters
import ../tui/widget/overview
import ../tui/hex_labels
import ../tui/widget/hexmap/symbols

# Forward declaration for PlayerState sync helper
proc syncPlanetsRows*(model: var TuiModel, ps: PlayerState)

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
  model.view.prestige = house.prestige.int
  model.view.alertCount = 0
  model.view.unreadReports = 0
  model.view.unreadMessages = 0

  # Production (from last income report if available)
  if house.latestIncomeReport.isSome:
    model.view.production = house.latestIncomeReport.get().totalNet.int
  else:
    model.view.production = 0

  model.view.houseTaxRate = house.taxPolicy.currentRate.int

  var colonyReports = initTable[ColonyId, ColonyIncomeReport]()
  if house.latestIncomeReport.isSome:
    for report in house.latestIncomeReport.get().colonies:
      colonyReports[report.colonyId] = report

  # Command capacity (C2 pool)
  let c2Analysis = analyzeC2Capacity(state, viewingHouse)
  model.view.commandUsed = c2Analysis.totalFleetCC.int
  model.view.commandMax = c2Analysis.c2Pool.int

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
        owner: int(viewingHouse),
      )
    )

  # Build fleets list
  model.view.fleets = @[]
  for fleet in state.fleetsOwned(viewingHouse):
    let sysOpt = state.system(fleet.location)
    let locName =
      if sysOpt.isSome:
        sysOpt.get().name
      else:
        "???"
    let cmdType = int(fleet.command.commandType)
    model.view.fleets.add(
      sam_pkg.FleetInfo(
        id: int(fleet.id),
        location: int(fleet.location),
        locationName: locName,
        shipCount: fleet.ships.len,
        owner: int(viewingHouse),
        command: cmdType,
        commandLabel: sam_pkg.commandLabel(cmdType),
        isIdle: fleet.command.commandType == FleetCommandType.Hold,
      )
    )

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

  # Tax rate not available in PlayerState
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
        description = "Fleet #" & $fleet.id.int & " awaiting orders",
        isDone = false,
        priority = ActionPriority.Warning,
      )

  if idleFleets.len > 0:
    result.actionQueue.addAction(
      description = $idleFleets.len & " fleet(s) awaiting orders",
      priority = ActionPriority.Warning,
      jumpView = 3,
      jumpLabel = "3",
    )

  # Placeholder recent events
  if result.recentEvents.len == 0:
    result.addEvent(ps.turn, "No recent events", false)

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
  model.view.treasury = 0  # Not available in PlayerState
  model.view.prestige =
    ps.housePrestige.getOrDefault(ps.viewingHouse, 0).int
  model.view.alertCount = 0
  model.view.unreadReports = 0
  model.view.unreadMessages = 0
  model.view.production = 0  # Would need income report
  model.view.houseTaxRate = 0
  
  # Build systems table from visible systems
  # VisibleSystem only has: id, name, visibility, lastScoutedTurn, coordinates
  model.view.systems.clear()
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
        owner: int(ps.viewingHouse),
      )
    )
  
  # Build fleets list from own fleets
  model.view.fleets = @[]
  for fleet in ps.ownFleets:
    var locName = "System " & $fleet.location.uint32
    if ps.visibleSystems.hasKey(fleet.location):
      let visSys = ps.visibleSystems[fleet.location]
      if visSys.coordinates.isSome:
        let coords = visSys.coordinates.get()
        if visSys.name.len > 0:
          locName = visSys.name
        else:
          locName = "(" & $coords.q & "," & $coords.r & ")"
    let cmdType = int(fleet.command.commandType)
    model.view.fleets.add(
      sam_pkg.FleetInfo(
        id: int(fleet.id),
        location: int(fleet.location),
        locationName: locName,
        shipCount: fleet.ships.len,
        owner: int(ps.viewingHouse),
        command: cmdType,
        commandLabel: sam_pkg.commandLabel(cmdType),
        isIdle: fleet.command.commandType == FleetCommandType.Hold,
      )
    )
  
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
  
  # Command capacity (not available in PlayerState)
  model.view.commandUsed = 0
  model.view.commandMax = 0

  # Sync planets table data
  syncPlanetsRows(model, ps)

# =============================================================================
# Planets Table Sync (PlayerState-only)
# =============================================================================

proc formatLtu[K](table: Table[K, int32], key: K, currentTurn: int32): string =
  ## Format Last Turn Updated as "T##" or "---"
  if table.hasKey(key):
    "T" & $table[key]
  else:
    "---"

proc planetClassName(classValue: int32): string =
  ## Get planet class name from int32 value
  let idx = int(classValue)
  if idx >= 0 and idx < PlanetClassNames.len:
    PlanetClassNames[idx]
  else:
    "???"

proc resourceRatingName(ratingValue: int32): string =
  ## Get resource rating name from int32 value
  let idx = int(ratingValue)
  if idx >= 0 and idx < ResourceRatingNames.len:
    ResourceRatingNames[idx]
  else:
    "???"

proc buildStatusLabel(colony: Colony): string =
  ## Build status label for colony (blockaded, etc.)
  if colony.blockaded:
    "BLOCKADED"
  else:
    "---"

proc hasOwnColonyAt(ps: PlayerState, systemId: SystemId): bool =
  ## Check if player has a colony at this system
  for colony in ps.ownColonies:
    if colony.systemId == systemId:
      return true
  false

proc buildOwnColonyRow(ps: PlayerState, colony: Colony): PlanetRow =
  ## Build PlanetRow from owned colony data
  let visSys = ps.visibleSystems.getOrDefault(colony.systemId)
  let coords = visSys.coordinates.get((0'i32, 0'i32))
  let ring = max(abs(coords.q), max(abs(coords.r), abs(-coords.q - coords.r)))

  result = PlanetRow(
    systemId: colony.systemId.int,
    colonyId: some(colony.id.int),
    systemName: visSys.name,
    sectorLabel: coordLabel(coords.q.int, coords.r.int),
    ownerName: ps.houseNames.getOrDefault(colony.owner, "???"),
    classLabel: planetClassName(visSys.planetClass),
    resourceLabel: resourceRatingName(visSys.resourceRating),
    pop: some(colony.populationUnits.int),
    iu: some(colony.industrial.units.int),
    gco: some(colony.grossOutput.int),
    ncv: none(int),  # Requires tax rate calculation not in PlayerState
    growthLabel: "---",  # Would need income report
    cdTotal: some(colony.constructionDocks.int),
    rdTotal: some(colony.repairDocks.int),
    ltuLabel: formatLtu(ps.ltuColonies, colony.id, ps.turn),
    statusLabel: buildStatusLabel(colony),
    isOwned: true,
    isHomeworld: ps.homeworldSystemId == some(colony.systemId),
    ring: ring.int,
    coordLabel: coordLabel(coords.q.int, coords.r.int),
    hasAlert: colony.blockaded,
  )

proc buildSystemRow(ps: PlayerState, visSys: VisibleSystem): PlanetRow =
  ## Build PlanetRow for non-owned system
  let coords = visSys.coordinates.get((0'i32, 0'i32))
  let ring = max(abs(coords.q), max(abs(coords.r), abs(-coords.q - coords.r)))

  # Check for enemy colony
  var ownerName = "---"
  var colonyId: Option[int] = none(int)
  var pop, iu, gco: Option[int]
  for vc in ps.visibleColonies:
    if vc.systemId == visSys.systemId:
      colonyId = some(vc.colonyId.int)
      ownerName = ps.houseNames.getOrDefault(vc.owner, "Unknown")
      pop = vc.estimatedPopulation.map(proc(x: int32): int = x.int)
      iu = vc.estimatedIndustry.map(proc(x: int32): int = x.int)
      break

  result = PlanetRow(
    systemId: visSys.systemId.int,
    colonyId: colonyId,
    systemName: visSys.name,
    sectorLabel: coordLabel(coords.q.int, coords.r.int),
    ownerName: ownerName,
    classLabel: if visSys.visibility >= Scouted:
                  planetClassName(visSys.planetClass) else: "??",
    resourceLabel: if visSys.visibility >= Scouted:
                     resourceRatingName(visSys.resourceRating) else: "??",
    pop: pop,
    iu: iu,
    gco: gco,
    ncv: none(int),
    growthLabel: "---",
    cdTotal: none(int),
    rdTotal: none(int),
    ltuLabel: formatLtu(ps.ltuSystems, visSys.systemId, ps.turn),
    statusLabel: "---",
    isOwned: false,
    isHomeworld: false,
    ring: ring.int,
    coordLabel: coordLabel(coords.q.int, coords.r.int),
    hasAlert: false,
  )

proc syncPlanetsRows*(model: var TuiModel, ps: PlayerState) =
  ## Build planetsRows from PlayerState only
  ## Order: homeworld first, then owned alpha, then non-owned alpha
  model.view.planetsRows = @[]
  var homeRow: Option[PlanetRow]
  var ownedRows, otherRows: seq[PlanetRow]

  # 1. Own colonies (full data)
  for colony in ps.ownColonies:
    let row = buildOwnColonyRow(ps, colony)
    if row.isHomeworld:
      homeRow = some(row)
    else:
      ownedRows.add(row)

  # 2. Visible systems without owned colony
  for sysId, visSys in ps.visibleSystems.pairs:
    if not ps.hasOwnColonyAt(sysId):
      otherRows.add(buildSystemRow(ps, visSys))

  # 3. Sort and merge
  ownedRows.sort(proc(a, b: PlanetRow): int = cmp(a.systemName, b.systemName))
  otherRows.sort(proc(a, b: PlanetRow): int = cmp(a.systemName, b.systemName))

  if homeRow.isSome: model.view.planetsRows.add(homeRow.get)
  model.view.planetsRows &= ownedRows
  model.view.planetsRows &= otherRows
