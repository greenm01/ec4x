## Player State Creation
##
## Creates a complete PlayerState for a specific house, containing:
## - Full entity data for owned assets (not just IDs)
## - Fog-of-war filtered visibility for enemy assets
## - Public game information
##
## Used by:
## - Zero-turn command system (client-side preview)
## - SQLite persistence (Claude testing)
## - Client state synchronization

import std/[tables, options, sets]
import
  ../types/[colony, core, diplomacy, fleet, game_state, house, player_state, starmap, facilities]
import ./[engine, iterators]
import ../systems/capacity/construction_docks

# ============================================================================
# Helper Procs (Visibility Tracking)
# ============================================================================

proc ownedSystems(state: GameState, houseId: HouseId): HashSet[SystemId] =
  ## Get all systems where this house has a colony
  result = initHashSet[SystemId]()
  for colony in state.coloniesOwned(houseId):
    result.incl(colony.systemId)

proc occupiedSystems(state: GameState, houseId: HouseId): HashSet[SystemId] =
  ## Get all systems where this house has fleet(s)
  result = initHashSet[SystemId]()
  for fleet in state.fleetsOwned(houseId):
    result.incl(fleet.location)

proc scoutedSystems(
    state: GameState, houseId: HouseId, ownedSystems, occupiedSystems: HashSet[SystemId]
): HashSet[SystemId] =
  ## Get systems with stale intel from intelligence database
  result = initHashSet[SystemId]()

  if not state.intel.contains(houseId):
    return

  let intel = state.intel[houseId]

  var colonyIdToSystemId = initTable[ColonyId, SystemId]()
  for colony in state.allColonies():
    colonyIdToSystemId[colony.id] = colony.systemId

  # Systems with colony intel
  for colonyId, report in intel.colonyObservations:
    if colonyIdToSystemId.contains(colonyId):
      let systemId = colonyIdToSystemId[colonyId]
      if systemId notin ownedSystems and systemId notin occupiedSystems:
        result.incl(systemId)

  # Systems with system intel
  for systemId, report in intel.systemObservations:
    if systemId notin ownedSystems and systemId notin occupiedSystems:
      result.incl(systemId)

# ============================================================================
# Enemy Asset Creation (Limited Intel)
# ============================================================================

proc createVisibleColony(
    state: GameState,
    colony: Colony,
    colonyIntel: Option[ColonyObservation],
    orbitalIntel: Option[OrbitalObservation],
): VisibleColony =
  ## Create a visible enemy colony with limited intel
  result.colonyId = colony.id
  result.systemId = colony.systemId
  result.owner = colony.owner

  # Limited details from intelligence reports
  if colonyIntel.isSome:
    let report = colonyIntel.get
    result.intelTurn = some(report.gatheredTurn)
    result.estimatedPopulation = some(report.population)
    result.estimatedIndustry = some(report.infrastructure)
    result.estimatedDefenses = some(report.groundBatteryCount)
  if orbitalIntel.isSome:
    let report = orbitalIntel.get
    result.starbaseLevel = some(report.starbaseCount)
    result.reserveFleetCount = some(report.reserveFleetCount)
    result.mothballedFleetCount = some(report.mothballedFleetCount)
    result.shipyardCount = some(report.shipyardCount)

proc createVisibleFleet(
    state: GameState,
    fleet: Fleet,
    location: SystemId,
    intelReport: Option[SystemObservation],
    currentTurn: int32,
): VisibleFleet =
  ## Create a visible enemy fleet with limited intel
  result.fleetId = fleet.id
  result.owner = fleet.houseId
  result.location = location

  # Estimate ship count from fleet.ships seq
  result.estimatedShipCount = some(int32(fleet.ships.len))
  result.detectedInSystem = some(location)
  if intelReport.isSome:
    result.intelTurn = some(intelReport.get.gatheredTurn)
  else:
    result.intelTurn = some(currentTurn)

# ============================================================================
# Main PlayerState Creation
# ============================================================================

proc createPlayerState*(state: GameState, houseId: HouseId): PlayerState =
  ## Create a complete PlayerState for a specific house
  ## Contains full entity data for owned assets and filtered intel for enemies
  result.viewingHouse = houseId
  result.turn = state.turn
  result.homeworldSystemId = none(SystemId)
  result.treasuryBalance = none(int32)
  result.netIncome = none(int32)
  result.ltuSystems = initTable[SystemId, int32]()
  result.ltuColonies = initTable[ColonyId, int32]()
  result.ltuFleets = initTable[FleetId, int32]()

  proc updateLtu[T](table: var Table[T, int32], key: T, turn: int32) =
    if table.hasKey(key):
      table[key] = max(table[key], turn)
    else:
      table[key] = turn

  # === Visibility Tracking ===
  let houseOpt = state.house(houseId)
  if houseOpt.isSome:
    let house = houseOpt.get()
    result.treasuryBalance = some(house.treasury)
    if house.latestIncomeReport.isSome:
      result.netIncome =
        some(house.latestIncomeReport.get().totalNet)

  for systemId, owner in state.starMap.homeWorlds.pairs:
    if owner == houseId:
      result.homeworldSystemId = some(systemId)
      break
  let ownedSystems = state.ownedSystems(houseId)
  let occupiedSystems = state.occupiedSystems(houseId)
  let scoutedSystems = state.scoutedSystems(houseId, ownedSystems, occupiedSystems)

  # === Owned Assets (Full Entity Data) ===
  # Colonies
  for colony in state.coloniesOwned(houseId):
    var colonyWithDocks = colony

    # Calculate dock counts for TUI display
    let capacities = state.analyzeColonyCapacity(colony.id)
    var cdTotal = 0'i32
    var rdTotal = 0'i32
    for facility in capacities:
      let maxDocks =
        if facility.isCrippled:
          0'i32
        else:
          facility.maxDocks
      case facility.facilityType
      of NeoriaClass.Spaceport, NeoriaClass.Shipyard:
        cdTotal += maxDocks
      of NeoriaClass.Drydock:
        rdTotal += maxDocks

    colonyWithDocks.constructionDocks = cdTotal
    colonyWithDocks.repairDocks = rdTotal

    result.ownColonies.add(colonyWithDocks)
    result.ltuColonies.updateLtu(colony.id, state.turn)
    result.ltuSystems.updateLtu(colony.systemId, state.turn)

  # Fleets
  for fleet in state.fleetsOwned(houseId):
    result.ownFleets.add(fleet)
    result.ltuFleets.updateLtu(fleet.id, state.turn)

  # Ships (all ships in owned fleets + fighters at colonies)
  for fleet in result.ownFleets:
    for shipId in fleet.ships:
      let shipOpt = state.ship(shipId)
      if shipOpt.isSome:
        result.ownShips.add(shipOpt.get())

  # Colony-based fighters
  for colony in result.ownColonies:
    for fighterId in colony.fighterIds:
      let fighterOpt = state.ship(fighterId)
      if fighterOpt.isSome:
        result.ownShips.add(fighterOpt.get())

  # Ground units
  for colony in result.ownColonies:
    for unitId in colony.groundUnitIds:
      let unitOpt = state.groundUnit(unitId)
      if unitOpt.isSome:
        result.ownGroundUnits.add(unitOpt.get())

  # Neorias (production facilities)
  for colony in result.ownColonies:
    for neoriaId in colony.neoriaIds:
      let neoriaOpt = state.neoria(neoriaId)
      if neoriaOpt.isSome:
        result.ownNeorias.add(neoriaOpt.get())

  # Kastras (defensive facilities)
  for colony in result.ownColonies:
    for kastraId in colony.kastraIds:
      let kastraOpt = state.kastra(kastraId)
      if kastraOpt.isSome:
        result.ownKastras.add(kastraOpt.get())

  # === Visible Systems (Fog of War) ===
  result.visibleSystems = initTable[SystemId, VisibleSystem]()

  # Owned systems
  for systemId in ownedSystems:
    let systemOpt = state.system(systemId)
    if systemOpt.isSome:
      let system = systemOpt.get()
      let coords = (q: system.coords.q, r: system.coords.r)
      result.visibleSystems[systemId] = VisibleSystem(
        systemId: systemId,
        name: system.name,
        visibility: VisibilityLevel.Owned,
        lastScoutedTurn: some(state.turn),
        coordinates: some(coords),
        jumpLaneIds: state.starMap.lanes.neighbors.getOrDefault(systemId),
      )
      result.ltuSystems.updateLtu(systemId, state.turn)

  # Occupied systems
  for systemId in occupiedSystems:
    if systemId notin ownedSystems:
      let systemOpt = state.system(systemId)
      if systemOpt.isSome:
        let system = systemOpt.get()
        let coords = (q: system.coords.q, r: system.coords.r)
        result.visibleSystems[systemId] = VisibleSystem(
          systemId: systemId,
          name: system.name,
          visibility: VisibilityLevel.Occupied,
          lastScoutedTurn: some(state.turn),
          coordinates: some(coords),
          jumpLaneIds: state.starMap.lanes.neighbors.getOrDefault(systemId),
        )
        result.ltuSystems.updateLtu(systemId, state.turn)

  # Scouted systems
  let intel = state.intel.getOrDefault(houseId)
  for systemId in scoutedSystems:
    let systemOpt = state.system(systemId)
    if systemOpt.isSome:
      let system = systemOpt.get()
      let coords = (q: system.coords.q, r: system.coords.r)
      var lastTurn: int32 = 0
      if intel.systemObservations.contains(systemId):
        lastTurn = max(lastTurn, intel.systemObservations[systemId].gatheredTurn)
      result.visibleSystems[systemId] = VisibleSystem(
        systemId: systemId,
        name: system.name,
        visibility: VisibilityLevel.Scouted,
        lastScoutedTurn: some(lastTurn),
        coordinates: some(coords),
        jumpLaneIds: state.starMap.lanes.neighbors.getOrDefault(systemId),
      )
      if lastTurn > 0:
        result.ltuSystems.updateLtu(systemId, lastTurn)

  # Universal map awareness (all systems visible at Adjacent level)
  for system in state.allSystems():
    if system.id notin result.visibleSystems:
      let coords = (q: system.coords.q, r: system.coords.r)
      result.visibleSystems[system.id] = VisibleSystem(
        systemId: system.id,
        name: system.name,
        visibility: VisibilityLevel.Adjacent,
        lastScoutedTurn: none(int32),
        coordinates: some(coords),
        jumpLaneIds: state.starMap.lanes.neighbors.getOrDefault(system.id),
      )

  # === Enemy Assets (Limited Intel) ===
  # Visible enemy colonies
  for colony in state.allColonies():
    if colony.owner != houseId:
      let systemId = colony.systemId
      var isVisible = false
      var colonyIntel: Option[ColonyObservation]
      var orbitalIntel: Option[OrbitalObservation]
      if intel.colonyObservations.contains(colony.id):
        isVisible = true
        colonyIntel = some(intel.colonyObservations[colony.id])
      if intel.orbitalObservations.contains(colony.id):
        isVisible = true
        orbitalIntel = some(intel.orbitalObservations[colony.id])
      if systemId in ownedSystems or systemId in occupiedSystems:
        isVisible = true
      if isVisible:
        let visibleColony = state.createVisibleColony(
          colony,
          colonyIntel,
          orbitalIntel
        )
        result.visibleColonies.add(visibleColony)
        if visibleColony.intelTurn.isSome:
          let intelTurn = visibleColony.intelTurn.get()
          result.ltuColonies.updateLtu(colony.id, intelTurn)
          result.ltuSystems.updateLtu(colony.systemId, intelTurn)

  # Visible enemy fleets
  for fleet in state.allFleets():
    if fleet.houseId != houseId:
      let isVisible =
        fleet.location in ownedSystems or fleet.location in occupiedSystems
      if isVisible:
        var systemIntel: Option[SystemObservation]
        if intel.systemObservations.contains(fleet.location):
          systemIntel = some(intel.systemObservations[fleet.location])
        let visibleFleet = createVisibleFleet(
          state,
          fleet,
          fleet.location,
          systemIntel,
          state.turn
        )
        result.visibleFleets.add(visibleFleet)
        if visibleFleet.intelTurn.isSome:
          result.ltuFleets.updateLtu(
            fleet.id,
            visibleFleet.intelTurn.get()
          )

  # === Public Information ===
  result.actProgression = state.actProgression
  var colonyCounts = initTable[HouseId, int32]()
  for colony in state.allColonies():
    colonyCounts[colony.owner] = colonyCounts.getOrDefault(colony.owner) + 1

  for house in state.allHouses():
    result.housePrestige[house.id] = house.prestige
    result.houseColonyCounts[house.id] = colonyCounts.getOrDefault(house.id)
    result.houseNames[house.id] = house.name
    if house.isEliminated:
      result.eliminatedHouses.add(house.id)

  for key, relation in state.diplomaticRelation:
    result.diplomaticRelations[key] = relation.state

  # === Starmap Topology (Universal Knowledge) ===
  result.jumpLanes = state.starMap.lanes.data
