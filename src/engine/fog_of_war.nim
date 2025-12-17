## Fog of War System
##
## Filters game state to create player-specific views with limited visibility.
## Per Grok AI feedback: "Fog of war is mandatory for both RBA and NNA"

import std/[tables, options, sets, strformat]
import ../common/types/[core, planets]
import gamestate, fleet, squadron, starmap, order_types, logger
import intelligence/types as intel_types

type
  VisibilityLevel* {.pure.} = enum
    ## System visibility levels (per intel.md)
    None        # Never visited, no knowledge
    Adjacent    # One jump away from known system
    Scouted     # Previously visited, stale intel
    Occupied    # Player fleet currently present
    Owned       # Player colony present

  VisibleColony* = object
    ## Colony information visible to a specific house
    systemId*: SystemId
    owner*: HouseId

    # Full details (if owned)
    population*: Option[int]
    infrastructure*: Option[int]
    planetClass*: Option[PlanetClass]
    resources*: Option[ResourceRating]
    production*: Option[int]

    # Intel report details (if enemy and scouted/spied)
    intelTurn*: Option[int]          # When intel was gathered
    estimatedPopulation*: Option[int]
    estimatedIndustry*: Option[int]
    estimatedDefenses*: Option[int]  # Ground defenses only (armies, marines, batteries)
    starbaseLevel*: Option[int]

    # Orbital defense intel (from approaching colony for orbital missions)
    # Per user: orbital defenses include starbases (above), unassigned squadrons,
    # reserve/mothballed fleets, and shipyards (space-based, NOT surface spaceports)
    unassignedSquadronCount*: Option[int]   # Combat squadrons not in fleets
    reserveFleetCount*: Option[int]         # Reserve fleets at colony
    mothballedFleetCount*: Option[int]      # Mothballed fleets at colony
    shipyardCount*: Option[int]             # Space-based construction facilities

  VisibleFleet* = object
    ## Fleet information visible to a specific house
    fleetId*: FleetId
    owner*: HouseId
    location*: SystemId

    # Full details (if owned)
    fullDetails*: Option[Fleet]

    # Limited intel (if enemy and detected)
    intelTurn*: Option[int]          # When detected
    estimatedShipCount*: Option[int]
    detectedInSystem*: Option[SystemId]  # Where it was detected

  VisibleSystem* = object
    ## System information visible to a specific house
    systemId*: SystemId
    visibility*: VisibilityLevel
    lastScoutedTurn*: Option[int]    # When last visited (if scouted)

    # System details (always visible once discovered)
    coordinates*: Option[tuple[q: int, r: int]]
    jumpLanes*: seq[SystemId]        # Known connections

  FilteredGameState* = object
    ## Game state filtered for a specific house's perspective
    ## This is what the AI "sees" - enforces fog of war
    viewingHouse*: HouseId
    turn*: int
    year*: int
    month*: int

    # Own assets (full detail)
    ownHouse*: House
    ownColonies*: seq[Colony]
    ownFleets*: seq[Fleet]
    ownFleetOrders*: Table[FleetId, FleetOrder]  # Persistent orders for own fleets

    # Visible systems
    visibleSystems*: Table[SystemId, VisibleSystem]

    # Visible enemy assets
    visibleColonies*: seq[VisibleColony]
    visibleFleets*: seq[VisibleFleet]

    # Public information (all houses can see)
    housePrestige*: Table[HouseId, int]  # Prestige scores
    houseColonies*: Table[HouseId, int]  # Colony counts (public leaderboard)
    houseDiplomacy*: Table[(HouseId, HouseId), DiplomaticState]  # Diplomatic relations
    houseEliminated*: Table[HouseId, bool]  # Elimination status
    actProgression*: ActProgressionState  # Current game act (public info)

    # Star map (topology only, not full details)
    starMap*: StarMap

proc getOwnedSystems(state: GameState, houseId: HouseId): HashSet[SystemId] =
  ## Get all systems where this house has a colony
  result = initHashSet[SystemId]()
  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      result.incl(systemId)

proc getOccupiedSystems(state: GameState, houseId: HouseId): HashSet[SystemId] =
  ## Get all systems where this house has fleet(s)
  result = initHashSet[SystemId]()
  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      result.incl(fleet.location)

proc getAdjacentSystems(state: GameState, knownSystems: HashSet[SystemId]): HashSet[SystemId] =
  ## Get all systems one jump away from known systems
  result = initHashSet[SystemId]()
  for systemId in knownSystems:
    if systemId in state.starMap.systems:
      let adjacentIds = state.starMap.getAdjacentSystems(systemId)
      for adjId in adjacentIds:
        if adjId notin knownSystems:
          result.incl(adjId)

proc getScoutedSystems(state: GameState, houseId: HouseId,
                      ownedSystems, occupiedSystems: HashSet[SystemId]): HashSet[SystemId] =
  ## Get systems with stale intel from intelligence database
  result = initHashSet[SystemId]()

  let house = state.houses.getOrDefault(houseId)

  # Systems with colony intel
  for systemId, report in house.intelligence.colonyReports:
    if systemId notin ownedSystems and systemId notin occupiedSystems:
      result.incl(systemId)

  # Systems with fleet intel
  for systemId, report in house.intelligence.systemReports:
    if systemId notin ownedSystems and systemId notin occupiedSystems:
      result.incl(systemId)

proc createVisibleColony(colony: Colony, isOwned: bool,
                        intelReport: Option[intel_types.ColonyIntelReport]): VisibleColony =
  ## Create a visible colony view
  result.systemId = colony.systemId
  result.owner = colony.owner

  if isOwned:
    # Full details for owned colonies
    result.population = some(colony.population)
    result.infrastructure = some(colony.infrastructure)
    result.planetClass = some(colony.planetClass)
    result.resources = some(colony.resources)
    result.production = some(colony.production)
  elif intelReport.isSome:
    # Limited details from intelligence report
    let report = intelReport.get
    result.intelTurn = some(report.gatheredTurn)
    result.estimatedPopulation = some(report.population)
    result.estimatedIndustry = some(report.industry)
    result.estimatedDefenses = some(report.defenses)
    result.starbaseLevel = some(report.starbaseLevel)

    # Orbital defense intel (populated when approaching colony for orbital missions)
    result.unassignedSquadronCount = some(report.unassignedSquadronCount)
    result.reserveFleetCount = some(report.reserveFleetCount)
    result.mothballedFleetCount = some(report.mothballedFleetCount)
    result.shipyardCount = some(report.shipyardCount)

proc createVisibleFleet(fleet: Fleet, isOwned: bool, location: SystemId,
                       intelReport: Option[intel_types.SystemIntelReport],
                       currentTurn: int): VisibleFleet =
  ## Create a visible fleet view
  result.fleetId = fleet.id
  result.owner = fleet.owner
  result.location = location

  if isOwned:
    # Full details for owned fleets
    result.fullDetails = some(fleet)
  elif intelReport.isSome:
    # Limited intel from detection
    let report = intelReport.get
    result.intelTurn = some(report.gatheredTurn)

    # Find this specific fleet in the detected fleets
    for detectedFleet in report.detectedFleets:
      if detectedFleet.fleetId == fleet.id:
        result.estimatedShipCount = some(detectedFleet.shipCount)
        result.detectedInSystem = some(report.systemId)
        break
  else:
    # Visual detection (fleet in same system as viewer's fleet)
    # Count all squadrons (includes Combat, Intel, Expansion, Auxiliary)
    result.estimatedShipCount = some(fleet.squadrons.len)
    result.detectedInSystem = some(location)
    result.intelTurn = some(currentTurn)

proc createFogOfWarView*(state: GameState, houseId: HouseId): FilteredGameState =
  ## Create a fog-of-war filtered view of the game state for a specific house
  ##
  ## This is the ONLY way AI should access game state to ensure fair play.
  ##
  ## Visibility rules (per intel.md):
  ## - Owned: Full details for own colonies
  ## - Occupied: Full details for systems with own fleets
  ## - Scouted: Stale intel from intelligence database
  ## - Adjacent: System existence only, no details
  ## - None: System not visible at all

  result.viewingHouse = houseId
  result.turn = state.turn
  result.starMap = state.starMap

  # Get visibility sets
  let ownedSystems = state.getOwnedSystems(houseId)
  let occupiedSystems = state.getOccupiedSystems(houseId)
  let scoutedSystems = state.getScoutedSystems(houseId, ownedSystems, occupiedSystems)
  # Adjacent systems are only neighbors of owned/occupied systems (not scouted)
  let adjacentSystems = state.getAdjacentSystems(ownedSystems + occupiedSystems)

  # Own house (full details)
  result.ownHouse = state.houses.getOrDefault(houseId)

  # Own colonies (full details)
  result.ownColonies = @[]
  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      result.ownColonies.add(colony)

  # Own fleets (full details)
  result.ownFleets = @[]
  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      result.ownFleets.add(fleet)

  # Own fleet orders (persistent orders for strategic planning)
  result.ownFleetOrders = initTable[FleetId, FleetOrder]()
  for fleetId, order in state.fleetOrders:
    # Only include orders for fleets owned by this house
    if fleetId in state.fleets and state.fleets[fleetId].owner == houseId:
      result.ownFleetOrders[fleetId] = order

  # Build visible systems map
  result.visibleSystems = initTable[SystemId, VisibleSystem]()

  # Owned systems
  for systemId in ownedSystems:
    if systemId in state.starMap.systems:
      let system = state.starMap.systems[systemId]
      let adjacentIds = state.starMap.getAdjacentSystems(systemId)
      let coords: tuple[q: int, r: int] = (q: system.coords.q, r: system.coords.r)

      result.visibleSystems[systemId] = VisibleSystem(
        systemId: systemId,
        visibility: VisibilityLevel.Owned,
        lastScoutedTurn: some(state.turn),
        coordinates: some(coords),
        jumpLanes: adjacentIds
      )

  # Occupied systems
  for systemId in occupiedSystems:
    if systemId notin ownedSystems:  # Don't overwrite owned
      if systemId in state.starMap.systems:
        let system = state.starMap.systems[systemId]
        let adjacentIds = state.starMap.getAdjacentSystems(systemId)
        let coords: tuple[q: int, r: int] = (q: system.coords.q, r: system.coords.r)

        result.visibleSystems[systemId] = VisibleSystem(
          systemId: systemId,
          visibility: VisibilityLevel.Occupied,
          lastScoutedTurn: some(state.turn),
          coordinates: some(coords),
          jumpLanes: adjacentIds
        )

  # Scouted systems (stale intel)
  let house = state.houses.getOrDefault(houseId)
  for systemId in scoutedSystems:
    if systemId in state.starMap.systems:
      let system = state.starMap.systems[systemId]
      let adjacentIds = state.starMap.getAdjacentSystems(systemId)
      let coords: tuple[q: int, r: int] = (q: system.coords.q, r: system.coords.r)

      # Find most recent intel turn for this system
      var lastTurn = 0
      if house.intelligence.colonyReports.hasKey(systemId):
        lastTurn = max(lastTurn, house.intelligence.colonyReports[systemId].gatheredTurn)
      if house.intelligence.systemReports.hasKey(systemId):
        lastTurn = max(lastTurn, house.intelligence.systemReports[systemId].gatheredTurn)

      result.visibleSystems[systemId] = VisibleSystem(
        systemId: systemId,
        visibility: VisibilityLevel.Scouted,
        lastScoutedTurn: some(lastTurn),
        coordinates: some(coords),
        jumpLanes: adjacentIds
      )

  # Adjacent systems (awareness only)
  for systemId in adjacentSystems:
    if systemId notin result.visibleSystems:
      if systemId in state.starMap.systems:
        let system = state.starMap.systems[systemId]
        let coords: tuple[q: int, r: int] = (q: system.coords.q, r: system.coords.r)

        result.visibleSystems[systemId] = VisibleSystem(
          systemId: systemId,
          visibility: VisibilityLevel.Adjacent,
          lastScoutedTurn: none(int),
          coordinates: some(coords),
          jumpLanes: @[]  # Don't reveal connections beyond adjacent
        )

  # Universal map awareness - ALL systems visible from the start
  # Players know the entire star map (systems and jump lanes), but colonies/fleets remain hidden until scouted
  for systemId, system in state.starMap.systems:
    if systemId notin result.visibleSystems:
      let adjacentIds = state.starMap.getAdjacentSystems(systemId)
      let coords: tuple[q: int, r: int] = (q: system.coords.q, r: system.coords.r)

      result.visibleSystems[systemId] = VisibleSystem(
        systemId: systemId,
        visibility: VisibilityLevel.Adjacent,
        lastScoutedTurn: none(int),
        coordinates: some(coords),
        jumpLanes: adjacentIds  # Reveal all jump lanes for strategic planning
      )

  # Visible colonies
  result.visibleColonies = @[]

  # DEBUG: Log intelligence database size
  logDebug(LogCategory.lcAI, &"Fog-of-war for {houseId}: {house.intelligence.colonyReports.len} colony intel reports")

  for systemId, colony in state.colonies:
    if colony.owner != houseId:
      # Enemy colony - check if visible
      let isVisible = systemId in ownedSystems or systemId in occupiedSystems or
                     house.intelligence.colonyReports.hasKey(systemId)

      if isVisible:
        let intelReport = house.intelligence.getColonyIntel(systemId)
        let visCol = createVisibleColony(colony, false, intelReport)
        result.visibleColonies.add(visCol)

  # Visible fleets
  result.visibleFleets = @[]
  for fleetId, fleet in state.fleets:
    if fleet.owner != houseId:
      # Enemy fleet - check if visible (in occupied or owned systems)
      let isVisible = fleet.location in ownedSystems or fleet.location in occupiedSystems

      if isVisible:
        let systemIntel = house.intelligence.getSystemIntel(fleet.location)
        let visFleet = createVisibleFleet(fleet, false, fleet.location, systemIntel, state.turn)
        result.visibleFleets.add(visFleet)

  # Public information
  result.housePrestige = initTable[HouseId, int]()
  result.houseColonies = initTable[HouseId, int]()
  result.houseDiplomacy = initTable[(HouseId, HouseId), DiplomaticState]()
  result.houseEliminated = initTable[HouseId, bool]()
  result.actProgression = state.actProgression  # Current game act (public info)

  for otherId, otherHouse in state.houses:
    result.housePrestige[otherId] = otherHouse.prestige
    result.houseEliminated[otherId] = otherHouse.eliminated

    # Count colonies for public leaderboard (like prestige, visible to all)
    var colonyCount = 0
    for systemId, colony in state.colonies:
      if colony.owner == otherId:
        colonyCount += 1
    result.houseColonies[otherId] = colonyCount

  # Populate diplomatic relations involving the viewing house
  # 1. Relations *from* the viewing house *to* other houses
  let viewingHouse = state.houses.getOrDefault(houseId)
  for targetHouseId, relation in viewingHouse.diplomaticRelations.relations:
    result.houseDiplomacy[(houseId, targetHouseId)] = relation.state

  # 2. Relations *from* other houses *to* the viewing house
  #    This ensures a complete bilateral view for the viewing house.
  for otherHouseId, otherHouse in state.houses:
    if otherHouseId == houseId: # Skip self
      continue
    if otherHouse.diplomaticRelations.relations.hasKey(houseId):
      let relationToViewingHouse = otherHouse.diplomaticRelations.relations[houseId]
      result.houseDiplomacy[(otherHouseId, houseId)] = relationToViewingHouse.state

proc getIntelStaleness*(filtered: FilteredGameState, systemId: SystemId): int =
  ## Calculate how many turns old intel is for a system
  ## Returns 0 if current (owned/occupied), positive if stale, -1 if no intel
  if systemId notin filtered.visibleSystems:
    return -1  # No intel at all

  let vis = filtered.visibleSystems[systemId]
  if vis.visibility == VisibilityLevel.Owned or vis.visibility == VisibilityLevel.Occupied:
    return 0  # Current intel

  if vis.lastScoutedTurn.isSome:
    return filtered.turn - vis.lastScoutedTurn.get

  return -1  # No intel

proc canSeeColonyDetails*(filtered: FilteredGameState, systemId: SystemId): bool =
  ## Check if AI can see detailed colony information
  if systemId notin filtered.visibleSystems:
    return false

  let vis = filtered.visibleSystems[systemId]
  return vis.visibility in [VisibilityLevel.Owned, VisibilityLevel.Occupied]

proc canSeeFleets*(filtered: FilteredGameState, systemId: SystemId): bool =
  ## Check if AI can see fleets in a system
  if systemId notin filtered.visibleSystems:
    return false

  let vis = filtered.visibleSystems[systemId]
  return vis.visibility in [VisibilityLevel.Owned, VisibilityLevel.Occupied]
