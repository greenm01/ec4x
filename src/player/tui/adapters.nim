## TUI Adapters - Convert engine types to widget types
##
## This module provides conversion functions between EC4X engine types
## and TUI widget types. Maintains separation between engine (game logic)
## and presentation (TUI) layers.

import std/[options, tables, algorithm]
import ../../engine/types/[core, starmap, colony, fleet, player_state]
import ../../engine/state/engine
import ../../engine/state/fog_of_war
import ./widget/hexmap/hexmap_pkg
import ./widget/system_list
import ./hex_labels

# -----------------------------------------------------------------------------
# Coordinate conversions
# -----------------------------------------------------------------------------

proc toHexCoord*(h: Hex): HexCoord =
  ## Convert engine Hex to widget HexCoord
  hexCoord(int(h.q), int(h.r))

proc toEngineHex*(h: HexCoord): Hex =
  ## Convert widget HexCoord to engine Hex
  Hex(q: int32(h.q), r: int32(h.r))

# -----------------------------------------------------------------------------
# System conversions
# -----------------------------------------------------------------------------

proc toSystemInfo*(sys: System, state: GameState): SystemInfo =
  ## Convert engine System to widget SystemInfo
  ##
  ## Determines ownership by checking if colony exists at this system.
  var owner = none(int)
  var isHomeworld = false
  var fleetCount = 0
  
  # Check for colony ownership
  if state.colonies.bySystem.hasKey(sys.id):
    let colonyId = state.colonies.bySystem[sys.id]
    let colony = state.colony(colonyId).get()
    owner = some(int(colony.owner))
    
    # Check if this is a homeworld
    for homeSystem, houseId in state.starmap.homeWorlds.pairs:
      if homeSystem == sys.id:
        isHomeworld = true
        break
  
  # Count fleets in this system
  if state.fleets.bySystem.hasKey(sys.id):
    fleetCount = state.fleets.bySystem[sys.id].len
  
  # Check if this is the hub
  let isHub = sys.id == state.starmap.hubId
  
  SystemInfo(
    id: int(sys.id),
    name: sys.name,
    coords: toHexCoord(sys.coords),
    ring: int(sys.ring),
    planetClass: ord(sys.planetClass),
    resourceRating: ord(sys.resourceRating),
    owner: owner,
    isHomeworld: isHomeworld,
    isHub: isHub,
    fleetCount: fleetCount
  )

# -----------------------------------------------------------------------------
# Map data conversion
# -----------------------------------------------------------------------------

proc toMapData*(state: GameState, viewingHouse: HouseId): MapData =
  ## Convert engine GameState to widget MapData
  ##
  ## Creates a complete map with all systems visible.
  ## For fog-of-war, use toFogOfWarMapData instead.
  var systems = initTable[HexCoord, SystemInfo]()
  var maxRing = 0
  
  # Convert all systems
  for systemId in state.systems.entities.index.keys:
    let sysOpt = state.system(systemId)
    if sysOpt.isSome:
      let sys = sysOpt.get()
      let sysInfo = toSystemInfo(sys, state)
      systems[sysInfo.coords] = sysInfo
      
      # Track max ring
      if int(sys.ring) > maxRing:
        maxRing = int(sys.ring)
  
  MapData(
    systems: systems,
    maxRing: maxRing,
    viewingHouse: int(viewingHouse)
  )

# -----------------------------------------------------------------------------
# Jump lane conversions
# -----------------------------------------------------------------------------

proc toJumpLaneInfo*(lane: JumpLane, state: GameState): JumpLaneInfo =
  ## Convert engine JumpLane to widget JumpLaneInfo
  let destSystem = state.system(lane.destination).get()
  
  JumpLaneInfo(
    targetName: destSystem.name,
    targetCoord: toHexCoord(destSystem.coords),
    laneClass: ord(lane.laneType)
  )

proc getJumpLanes*(systemId: SystemId, state: GameState): seq[JumpLaneInfo] =
  ## Get all jump lanes from a system as widget types
  result = @[]
  
  if state.starmap.lanes.neighbors.hasKey(systemId):
    for neighborId in state.starmap.lanes.neighbors[systemId]:
      # Look up lane info
      if state.starmap.lanes.connectionInfo.hasKey((systemId, neighborId)):
        let laneType = state.starmap.lanes.connectionInfo[(systemId, neighborId)]
        let lane = JumpLane(
          source: systemId,
          destination: neighborId,
          laneType: laneType
        )
        result.add(toJumpLaneInfo(lane, state))

# -----------------------------------------------------------------------------
# Fleet conversions
# -----------------------------------------------------------------------------

proc toFleetInfo*(fleet: Fleet, state: GameState, viewingHouse: HouseId): FleetInfo =
  ## Convert engine Fleet to widget FleetInfo
  FleetInfo(
    name: "Fleet " & $fleet.id,  # TODO: Add fleet naming system
    shipCount: fleet.ships.len,
    isOwned: fleet.houseId == viewingHouse
  )

proc getFleetsInSystem*(systemId: SystemId, state: GameState, 
                        viewingHouse: HouseId): seq[FleetInfo] =
  ## Get all fleets in a system as widget types
  result = @[]
  
  if state.fleets.bySystem.hasKey(systemId):
    for fleetId in state.fleets.bySystem[systemId]:
      let fleet = state.fleet(fleetId).get()
      result.add(toFleetInfo(fleet, state, viewingHouse))

# -----------------------------------------------------------------------------
# Detail panel data conversion
# -----------------------------------------------------------------------------

proc toDetailPanelData*(systemCoord: HexCoord, state: GameState,
                        viewingHouse: HouseId): DetailPanelData =
  ## Create detail panel data for a system coordinate
  ##
  ## Returns empty data if no system exists at the coordinate.
  let engineHex = toEngineHex(systemCoord)
  
  # Find system with these coordinates
  var systemOpt = none(System)
  for systemId in state.systems.entities.index.keys:
    let sysOpt = state.system(systemId)
    if sysOpt.isSome:
      let sys = sysOpt.get()
      if sys.coords.q == engineHex.q and sys.coords.r == engineHex.r:
        systemOpt = some(sys)
        break
  
  if systemOpt.isNone:
    return DetailPanelData(
      system: none(SystemInfo),
      jumpLanes: @[],
      fleets: @[]
    )
  
  let system = systemOpt.get()
  let systemInfo = toSystemInfo(system, state)
  let jumpLanes = getJumpLanes(system.id, state)
  let fleets = getFleetsInSystem(system.id, state, viewingHouse)
  
  DetailPanelData(
    system: some(systemInfo),
    jumpLanes: jumpLanes,
    fleets: fleets
  )

# -----------------------------------------------------------------------------
# Fog-of-War conversions using PlayerState
# -----------------------------------------------------------------------------

proc visibilityToSymbol(visibility: VisibilityLevel): HexSymbol =
  ## Map visibility level to hex symbol type
  case visibility
  of VisibilityLevel.None:
    HexSymbol.Unknown
  of VisibilityLevel.Adjacent:
    HexSymbol.Unknown  # Shows as "?" - knows it exists but no details
  of VisibilityLevel.Scouted:
    HexSymbol.Neutral  # Shows as "·" - has been explored
  of VisibilityLevel.Occupied:
    HexSymbol.Neutral  # Will be overridden if colony present
  of VisibilityLevel.Owned:
    HexSymbol.Colony   # Will be overridden by isHomeworld check

proc toSystemInfoFromPlayerState*(
    visibleSys: VisibleSystem,
    playerState: PlayerState,
    state: GameState
): SystemInfo =
  ## Convert a VisibleSystem to SystemInfo using fog-of-war data
  ##
  ## Uses only information available to the viewing house.
  let sysOpt = state.system(visibleSys.systemId)
  if sysOpt.isNone:
    # System not found - return minimal unknown info
    return SystemInfo(
      id: int(visibleSys.systemId),
      name: "???",
      coords: hexCoord(
        int(visibleSys.coordinates.get((q: 0'i32, r: 0'i32)).q),
        int(visibleSys.coordinates.get((q: 0'i32, r: 0'i32)).r)
      ),
      ring: 0,
      planetClass: 0,
      resourceRating: 0,
      owner: none(int),
      isHomeworld: false,
      isHub: false,
      fleetCount: 0
    )
  
  let sys = sysOpt.get()
  var owner = none(int)
  var isHomeworld = false
  var fleetCount = 0
  var planetClass = 0
  var resourceRating = 0
  
  # Determine what we know based on visibility level
  case visibleSys.visibility
  of VisibilityLevel.Owned:
    # Full knowledge - find our colony
    for colony in playerState.ownColonies:
      if colony.systemId == visibleSys.systemId:
        owner = some(int(colony.owner))
        break
    
    # Check homeworld
    for homeSystem, houseId in state.starmap.homeWorlds.pairs:
      if homeSystem == visibleSys.systemId and 
         houseId == playerState.viewingHouse:
        isHomeworld = true
        break
    
    # Count our fleets
    for fleet in playerState.ownFleets:
      if fleet.location == visibleSys.systemId:
        fleetCount += 1
    
    # Full planet info
    planetClass = ord(sys.planetClass)
    resourceRating = ord(sys.resourceRating)
    
  of VisibilityLevel.Occupied:
    # We have fleets here but no colony
    for fleet in playerState.ownFleets:
      if fleet.location == visibleSys.systemId:
        fleetCount += 1
    
    # Can see enemy colonies if present
    for visCol in playerState.visibleColonies:
      if visCol.systemId == visibleSys.systemId:
        owner = some(int(visCol.owner))
        break
    
    # Full planet info (we're in system)
    planetClass = ord(sys.planetClass)
    resourceRating = ord(sys.resourceRating)
    
  of VisibilityLevel.Scouted:
    # Limited info from past scouting
    for visCol in playerState.visibleColonies:
      if visCol.systemId == visibleSys.systemId:
        owner = some(int(visCol.owner))
        break
    
    # Planet info if we scouted it
    planetClass = ord(sys.planetClass)
    resourceRating = ord(sys.resourceRating)
    
  of VisibilityLevel.Adjacent, VisibilityLevel.None:
    # Minimal info - just coordinates
    # Planet details hidden
    planetClass = -1  # Unknown
    resourceRating = -1  # Unknown
  
  # Check if this is the hub (always known)
  let isHub = sys.id == state.starmap.hubId
  
  SystemInfo(
    id: int(sys.id),
    name: if visibleSys.visibility >= VisibilityLevel.Scouted: sys.name 
          else: "Unknown",
    coords: toHexCoord(sys.coords),
    ring: int(sys.ring),
    planetClass: planetClass,
    resourceRating: resourceRating,
    owner: owner,
    isHomeworld: isHomeworld,
    isHub: isHub,
    fleetCount: fleetCount
  )

proc toFogOfWarMapData*(state: GameState, viewingHouse: HouseId): MapData =
  ## Convert GameState to widget MapData with fog-of-war filtering
  ##
  ## Uses PlayerState to determine what the viewing house can see.
  ## Systems below Scouted visibility show as "?" (unknown).
  let playerState = createPlayerState(state, viewingHouse)
  
  var systems = initTable[HexCoord, SystemInfo]()
  var maxRing = 0
  
  # Convert visible systems
  for systemId, visibleSys in playerState.visibleSystems.pairs:
    let sysInfo = toSystemInfoFromPlayerState(visibleSys, playerState, state)
    systems[sysInfo.coords] = sysInfo
    
    # Track max ring (from coordinates)
    let ring = sysInfo.coords.ring()
    if ring > maxRing:
      maxRing = ring
  
  MapData(
    systems: systems,
    maxRing: maxRing,
    viewingHouse: int(viewingHouse)
  )

proc toFogOfWarDetailPanelData*(
    systemCoord: HexCoord,
    state: GameState,
    viewingHouse: HouseId
): DetailPanelData =
  ## Create detail panel data with fog-of-war filtering
  ##
  ## Only shows information the viewing house has access to.
  let playerState = createPlayerState(state, viewingHouse)
  let engineHex = toEngineHex(systemCoord)
  
  # Find system with these coordinates
  var systemId = SystemId(0)
  var found = false
  for sysId, visibleSys in playerState.visibleSystems.pairs:
    if visibleSys.coordinates.isSome:
      let coords = visibleSys.coordinates.get()
      if coords.q == engineHex.q and coords.r == engineHex.r:
        systemId = sysId
        found = true
        break
  
  if not found:
    return DetailPanelData(
      system: none(SystemInfo),
      jumpLanes: @[],
      fleets: @[]
    )
  
  let visibleSys = playerState.visibleSystems[systemId]
  let systemInfo = toSystemInfoFromPlayerState(visibleSys, playerState, state)
  
  # Get jump lanes (only if we've scouted the system)
  var jumpLanes: seq[JumpLaneInfo] = @[]
  if visibleSys.visibility >= VisibilityLevel.Scouted:
    for neighborId in visibleSys.jumpLaneIds:
      if state.starmap.lanes.connectionInfo.hasKey((systemId, neighborId)):
        let laneType = state.starmap.lanes.connectionInfo[(systemId, neighborId)]
        let destSysOpt = state.system(neighborId)
        if destSysOpt.isSome:
          let destSys = destSysOpt.get()
          jumpLanes.add(JumpLaneInfo(
            targetName: destSys.name,
            targetCoord: toHexCoord(destSys.coords),
            laneClass: ord(laneType)
          ))
  
  # Get fleet info
  var fleets: seq[FleetInfo] = @[]
  
  # Our own fleets (always visible)
  for fleet in playerState.ownFleets:
    if fleet.location == systemId:
      fleets.add(FleetInfo(
        name: "Fleet " & $fleet.id,
        shipCount: fleet.ships.len,
        isOwned: true
      ))
  
  # Enemy fleets (only if detected)
  for visFleet in playerState.visibleFleets:
    if visFleet.location == systemId:
      fleets.add(FleetInfo(
        name: "Enemy Fleet",
        shipCount: visFleet.estimatedShipCount.get(0),
        isOwned: false
      ))
  
  DetailPanelData(
    system: some(systemInfo),
    jumpLanes: jumpLanes,
    fleets: fleets
  )

# -----------------------------------------------------------------------------
# System list data conversion
# -----------------------------------------------------------------------------

proc toSystemListData*(state: GameState, viewingHouse: HouseId,
                       selectedIdx: int = 0): SystemListData =
  ## Convert GameState to SystemListData for the system list widget
  ##
  ## Systems are sorted by ring (hub first) then by position within ring.
  let playerState = createPlayerState(state, viewingHouse)
  
  var entries: seq[SystemListEntry] = @[]
  
  for systemId, visibleSys in playerState.visibleSystems.pairs:
    # Only include systems we've scouted (know the name)
    if visibleSys.visibility < VisibilityLevel.Scouted:
      continue
    
    let sysOpt = state.system(systemId)
    if sysOpt.isNone:
      continue
    
    let sys = sysOpt.get()
    let q = int(sys.coords.q)
    let r = int(sys.coords.r)
    let label = coordLabel(q, r)
    
    # Build connection list
    var connections: seq[tuple[label: string, laneType: int]] = @[]
    for neighborId in visibleSys.jumpLaneIds:
      let destSysOpt = state.system(neighborId)
      if destSysOpt.isSome:
        let destSys = destSysOpt.get()
        let destLabel = coordLabel(int(destSys.coords.q), int(destSys.coords.r))
        var laneType = 0  # Default to major
        if state.starmap.lanes.connectionInfo.hasKey((systemId, neighborId)):
          laneType = ord(state.starmap.lanes.connectionInfo[(systemId, neighborId)])
        connections.add((label: destLabel, laneType: laneType))
    
    # Sort connections by lane type (major first) then by label
    connections.sort(proc(a, b: tuple[label: string, laneType: int]): int =
      if a.laneType != b.laneType:
        a.laneType - b.laneType
      else:
        cmp(a.label, b.label)
    )
    
    # Determine owner
    var ownerName = none(string)
    var isOwned = false
    for colony in playerState.ownColonies:
      if colony.systemId == systemId:
        let houseOpt = state.house(colony.owner)
        if houseOpt.isSome:
          ownerName = some(houseOpt.get().name)
          isOwned = true
        break
    
    if ownerName.isNone:
      for visCol in playerState.visibleColonies:
        if visCol.systemId == systemId:
          let houseOpt = state.house(visCol.owner)
          if houseOpt.isSome:
            ownerName = some(houseOpt.get().name)
          break
    
    entries.add(SystemListEntry(
      id: int(systemId),
      name: sys.name,
      coordLabel: label,
      q: q,
      r: r,
      connections: connections,
      ownerName: ownerName,
      isOwned: isOwned
    ))
  
  # Sort by ring then position (H first, then A1, A2, ..., B1, B2, ...)
  entries.sort(proc(a, b: SystemListEntry): int =
    let ringA = max(abs(a.q), max(abs(a.r), abs(a.q + a.r)))
    let ringB = max(abs(b.q), max(abs(b.r), abs(b.q + b.r)))
    if ringA != ringB:
      ringA - ringB
    else:
      cmp(a.coordLabel, b.coordLabel)
  )
  
  SystemListData(
    systems: entries,
    selectedIdx: selectedIdx
  )
