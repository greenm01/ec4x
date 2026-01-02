## Fog of War System
##
## Filters game state to create player-specific views with limited visibility.
import std/[tables, options, sets]
import ../types/intel as intel_types
import
  ../types/[colony, core, diplomacy, fleet, game_state, house, player_view, starmap]
import ./[entity_manager, iterators, entity_helpers]

proc getOwnedSystems(state: GameState, houseId: HouseId): HashSet[SystemId] =
  ## Get all systems where this house has a colony
  result = initHashSet[SystemId]()
  for colony in state.coloniesOwned(houseId):
    result.incl(colony.systemId)

proc getOccupiedSystems(state: GameState, houseId: HouseId): HashSet[SystemId] =
  ## Get all systems where this house has fleet(s)
  result = initHashSet[SystemId]()
  for fleet in state.fleetsOwned(houseId):
    result.incl(fleet.location)

proc getAdjacentSystems(
    state: GameState, knownSystems: HashSet[SystemId]
): HashSet[SystemId] =
  ## Get all systems one jump away from known systems
  result = initHashSet[SystemId]()
  for systemId in knownSystems:
    if state.starMap.lanes.neighbors.contains(systemId):
      for adjId in state.starMap.lanes.neighbors[systemId]:
        if adjId notin knownSystems:
          result.incl(adjId)

proc getScoutedSystems(
    state: GameState, houseId: HouseId, ownedSystems, occupiedSystems: HashSet[SystemId]
): HashSet[SystemId] =
  ## Get systems with stale intel from intelligence database
  result = initHashSet[SystemId]()

  if not state.intelligence.contains(houseId):
    return

  let intel = state.intelligence[houseId]

  var colonyIdToSystemId = initTable[ColonyId, SystemId]()
  for colony in state.allColonies():
    colonyIdToSystemId[colony.id] = colony.systemId

  # Systems with colony intel
  for colonyId, report in intel.colonyReports:
    if colonyIdToSystemId.contains(colonyId):
      let systemId = colonyIdToSystemId[colonyId]
      if systemId notin ownedSystems and systemId notin occupiedSystems:
        result.incl(systemId)

  # Systems with system intel
  for systemId, report in intel.systemReports:
    if systemId notin ownedSystems and systemId notin occupiedSystems:
      result.incl(systemId)

proc createVisibleColony(
    colony: Colony,
    isOwned: bool,
    colonyIntel: Option[intel_types.ColonyIntelReport],
    orbitalIntel: Option[intel_types.OrbitalIntelReport],
): VisibleColony =
  ## Create a visible colony view
  result.colonyId = colony.id
  result.systemId = colony.systemId
  result.owner = colony.owner

  if isOwned:
    # Full details for owned colonies
    result.population = some(colony.population)
    result.infrastructure = some(colony.infrastructure)
    result.planetClass = some(colony.planetClass)
    result.resources = some(colony.resources)
    result.production = some(colony.production)
  elif colonyIntel.isSome or orbitalIntel.isSome:
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

proc countShips(state: GameState, fleet: Fleet): int32 =
  result = 0
  for sqId in fleet.squadrons:
    let squadronOpt = state.squadrons.entities.entity(sqId)
    if squadronOpt.isSome:
      let squadron = squadronOpt.get()
      result += 1 + int32(squadron.ships.len)

proc createVisibleFleet(
    state: GameState,
    fleet: Fleet,
    isOwned: bool,
    location: SystemId,
    intelReport: Option[intel_types.SystemIntelReport],
    currentTurn: int32,
): VisibleFleet =
  ## Create a visible fleet view
  result.fleetId = fleet.id
  result.owner = fleet.houseId
  result.location = location
  result.isOwned = isOwned

  if not isOwned:
    result.estimatedShipCount = some(state.countShips(fleet))
    result.detectedInSystem = some(location)
    if intelReport.isSome:
      result.intelTurn = some(intelReport.get.gatheredTurn)
    else:
      result.intelTurn = some(currentTurn)

proc createPlayerView*(state: GameState, houseId: HouseId): PlayerView =
  ## Create a fog-of-war filtered view of the game state for a specific house
  result.viewingHouse = houseId
  result.turn = state.turn

  let ownedSystems = state.getOwnedSystems(houseId)
  let occupiedSystems = state.getOccupiedSystems(houseId)
  let scoutedSystems = state.getScoutedSystems(houseId, ownedSystems, occupiedSystems)
  let adjacentSystems = state.getAdjacentSystems(ownedSystems + occupiedSystems)

  for colony in state.coloniesOwned(houseId):
    result.ownColonyIds.add(colony.id)
  for fleet in state.fleetsOwned(houseId):
    result.ownFleetIds.add(fleet.id)

  result.visibleSystems = initTable[SystemId, VisibleSystem]()

  # Owned systems
  for systemId in ownedSystems:
    let systemOpt = state.systems.entities.entity(systemId)
    if systemOpt.isSome:
      let system = systemOpt.get()
      let coords = (q: system.coords.q, r: system.coords.r)
      result.visibleSystems[systemId] = VisibleSystem(
        systemId: systemId,
        visibility: VisibilityLevel.Owned,
        lastScoutedTurn: some(state.turn),
        coordinates: some(coords),
        jumpLaneIds: state.starMap.lanes.neighbors.getOrDefault(systemId),
      )

  # Occupied systems
  for systemId in occupiedSystems:
    if systemId notin ownedSystems:
      let systemOpt = state.systems.entities.entity(systemId)
      if systemOpt.isSome:
        let system = systemOpt.get()
        let coords = (q: system.coords.q, r: system.coords.r)
        result.visibleSystems[systemId] = VisibleSystem(
          systemId: systemId,
          visibility: VisibilityLevel.Occupied,
          lastScoutedTurn: some(state.turn),
          coordinates: some(coords),
          jumpLaneIds: state.starMap.lanes.neighbors.getOrDefault(systemId),
        )

  # Scouted systems
  let intel = state.intelligence.getOrDefault(houseId)
  for systemId in scoutedSystems:
    let systemOpt = state.systems.entities.entity(systemId)
    if systemOpt.isSome:
      let system = systemOpt.get()
      let coords = (q: system.coords.q, r: system.coords.r)
      var lastTurn: int32 = 0
      if intel.systemReports.contains(systemId):
        lastTurn = max(lastTurn, intel.systemReports[systemId].gatheredTurn)
      result.visibleSystems[systemId] = VisibleSystem(
        systemId: systemId,
        visibility: VisibilityLevel.Scouted,
        lastScoutedTurn: some(lastTurn),
        coordinates: some(coords),
        jumpLaneIds: state.starMap.lanes.neighbors.getOrDefault(systemId),
      )

  # Universal map awareness
  for system in state.allSystems():
    if system.id notin result.visibleSystems:
      let coords = (q: system.coords.q, r: system.coords.r)
      result.visibleSystems[system.id] = VisibleSystem(
        systemId: system.id,
        visibility: VisibilityLevel.Adjacent,
        lastScoutedTurn: none(int32),
        coordinates: some(coords),
        jumpLaneIds: state.starMap.lanes.neighbors.getOrDefault(system.id),
      )

  # Visible colonies
  for colony in state.allColonies():
    if colony.owner != houseId:
      let systemId = colony.systemId
      var isVisible = false
      var colonyIntel: Option[intel_types.ColonyIntelReport]
      var orbitalIntel: Option[intel_types.OrbitalIntelReport]
      if intel.colonyReports.contains(colony.id):
        isVisible = true
        colonyIntel = some(intel.colonyReports[colony.id])
      if intel.orbitalReports.contains(colony.id):
        isVisible = true
        orbitalIntel = some(intel.orbitalReports[colony.id])
      if systemId in ownedSystems or systemId in occupiedSystems:
        isVisible = true
      if isVisible:
        result.visibleColonies.add(
          createVisibleColony(colony, false, colonyIntel, orbitalIntel)
        )

  # Visible fleets
  for fleet in state.allFleets():
    if fleet.houseId != houseId:
      let isVisible =
        fleet.location in ownedSystems or fleet.location in occupiedSystems
      if isVisible:
        var systemIntel: Option[intel_types.SystemIntelReport]
        if intel.systemReports.contains(fleet.location):
          systemIntel = some(intel.systemReports[fleet.location])
        result.visibleFleets.add(
          createVisibleFleet(
            state, fleet, false, fleet.location, systemIntel, state.turn
          )
        )

  # Public information
  result.actProgression = state.actProgression
  var colonyCounts = initTable[HouseId, int32]()
  for colony in state.allColonies():
    colonyCounts[colony.owner] = colonyCounts.getOrDefault(colony.owner) + 1

  for house in state.allHouses():
    result.housePrestige[house.id] = house.prestige
    result.houseColonyCounts[house.id] = colonyCounts.getOrDefault(house.id)
    if house.isEliminated:
      result.eliminatedHouses.add(house.id)

  for key, relation in state.diplomaticRelation:
    result.diplomaticRelations[key] = relation.state

proc hasVisibilityOn*(state: GameState, systemId: SystemId, houseId: HouseId): bool =
  ## Check if a house has visibility on a system (fog of war)
  ## A house can see a system if:
  ## - They own a colony there
  ## - They have a fleet present
  ## - They have a spy scout present
  ##
  ## Used by Space Guild for transfer path validation

  # Check if house owns colony in this system
  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    if colony.owner == houseId:
        return true

  # Check if house has any fleets in this system using iterator
  for fleet in state.fleetsInSystem(systemId):
    if fleet.houseId == houseId:
      return true

  return false
