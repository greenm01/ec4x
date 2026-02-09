## TUI Adapters - Convert engine types to widget types
##
## This module provides conversion functions between EC4X engine types
## and TUI widget types. Maintains separation between engine (game logic)
## and presentation (TUI) layers.

import std/[options, tables, algorithm, strutils]
import ../../common/logger
import ../../engine/types/[core, starmap, colony, fleet, player_state, ship,
  combat, production, facilities, ground_unit, tech]
import ../../engine/state/engine
import ../../engine/state/iterators
import ../../engine/state/fog_of_war
import ../../engine/systems/capacity/[construction_docks, fighter,
  planet_breakers, planetary_shields, spaceports, starbases]
import ../../engine/systems/production/engine as production_engine
import ../../engine/globals
import ./widget/hexmap/hexmap_pkg
import ./widget/system_list
import ./hex_labels
import ./widget/hexmap/symbols
from ../sam/tui_model import BuildOption, BuildOptionKind, DockSummary,
  commandLabel, fleetCommandNumber

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
    let fallbackName =
      if visibleSys.name.len > 0:
        visibleSys.name
      else:
        "???"
    return SystemInfo(
      id: int(visibleSys.systemId),
      name: fallbackName,
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
  let systemName =
    if visibleSys.name.len > 0:
      visibleSys.name
    else:
      sys.name
  
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
    name: systemName,
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
  ## Planet details stay hidden until systems are scouted.
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
  
  # Get jump lanes
  var jumpLanes: seq[JumpLaneInfo] = @[]
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

# -----------------------------------------------------------------------------
# Fleet Detail conversions
# -----------------------------------------------------------------------------

type
  ShipDetailRow* = object
    ## Single ship entry for fleet detail view
    name*: string           # Ship name (e.g., "Alpha-1", "Beta-2")
    class*: string          # Ship class name (e.g., "Destroyer")
    state*: string          # Combat state label (e.g., "Nominal")
    attack*: string         # Attack strength (e.g., "45")
    defense*: string        # Defense strength (e.g., "38")
    isCrippled*: bool       # For rendering (crippled ships in yellow/red)
    wepLevel*: int          # WEP tech level ship was built at
    marines*: string        # Marines carried (e.g., "2" for TT, "-" for others)

  FleetDetailData* = object
    ## Complete fleet detail information for rendering
    fleetId*: int
    fleetName*: string      ## Per-house label (e.g. "A1", "B3")
    location*: string       # System name (e.g., "Homeworld")
    systemId*: int          # For navigation to system detail
    shipCount*: int         # Total ships in fleet
    totalAttack*: int       # Sum of all ship AS
    totalDefense*: int      # Sum of all ship DS
    command*: string        # Human-readable command (e.g., "Hold")
    commandType*: int       # FleetCommandType as int for logic
    targetLabel*: string    # Target system coord (e.g., "A10") or "-"
    status*: string         # "Active", "Reserve", "Mothballed"
    roe*: int               # Rules of engagement 0-10
    ships*: seq[ShipDetailRow]
    auxShips*: string       # Auxiliary ships summary (e.g., "2 ETAC, 4 TT")

proc fleetToDetailData*(
  state: GameState,
  fleetId: FleetId,
  houseId: HouseId
): FleetDetailData =
  ## Convert engine Fleet to FleetDetailData for TUI rendering
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    logWarn("TUI", "Fleet ", fleetId, " not found in state (turn ", state.turn, ")")
    return FleetDetailData(
      fleetId: int(fleetId),
      fleetName: "??",
      location: "Fleet Missing",
      shipCount: 0,
      totalAttack: 0,
      totalDefense: 0,
      targetLabel: "-",
      ships: @[],
      auxShips: ""
    )
  let fleet = fleetOpt.get()
  
  # Get location name
  var locationName = "Unknown"
  let systemOpt = state.system(fleet.location)
  if systemOpt.isSome:
    locationName = systemOpt.get().name
  
  # Convert command to short label
  let cmdNum = fleetCommandNumber(
    fleet.command.commandType
  )
  let commandStr = commandLabel(cmdNum)

  # Target label (coord if known)
  var targetLabel = "-"
  if fleet.command.commandType == FleetCommandType.JoinFleet and
      fleet.command.targetFleet.isSome:
    let targetId = fleet.command.targetFleet.get()
    let targetOpt = state.fleet(targetId)
    if targetOpt.isSome:
      targetLabel = "Fleet " & targetOpt.get().name
    else:
      targetLabel = "Fleet " & $targetId
  elif fleet.command.targetSystem.isSome:
    let targetId = fleet.command.targetSystem.get()
    let targetOpt = state.system(targetId)
    if targetOpt.isSome:
      let target = targetOpt.get()
      targetLabel = coordLabel(
        int(target.coords.q), int(target.coords.r)
      )
    else:
      targetLabel = $targetId
  
  # Convert status to string
  var statusStr = "Active"
  case fleet.status:
  of FleetStatus.Active:
    statusStr = "Active"
  of FleetStatus.Reserve:
    statusStr = "Reserve"
  of FleetStatus.Mothballed:
    statusStr = "Mothballed"
  
  # Build ship rows using shipsInFleet iterator
  var shipRows: seq[ShipDetailRow] = @[]
  var totalAS = 0
  var totalDS = 0
  var shipIdx = 0
  
  for ship in state.shipsInFleet(fleetId):
    shipIdx += 1
    
    # Generate ship name (Alpha-1, Alpha-2, ..., Zulu-26, etc.)
    let groupIdx = (shipIdx - 1) div 26
    let letterIdx = (shipIdx - 1) mod 26
    let groupName = 
      if groupIdx == 0: "Alpha"
      elif groupIdx == 1: "Beta"
      elif groupIdx == 2: "Gamma"
      elif groupIdx == 3: "Delta"
      elif groupIdx == 4: "Echo"
      elif groupIdx == 5: "Foxtrot"
      elif groupIdx == 6: "Golf"
      elif groupIdx == 7: "Hotel"
      elif groupIdx == 8: "India"
      elif groupIdx == 9: "Juliet"
      elif groupIdx == 10: "Kilo"
      elif groupIdx == 11: "Lima"
      elif groupIdx == 12: "Mike"
      elif groupIdx == 13: "November"
      elif groupIdx == 14: "Oscar"
      elif groupIdx == 15: "Papa"
      elif groupIdx == 16: "Quebec"
      elif groupIdx == 17: "Romeo"
      elif groupIdx == 18: "Sierra"
      elif groupIdx == 19: "Tango"
      elif groupIdx == 20: "Uniform"
      elif groupIdx == 21: "Victor"
      elif groupIdx == 22: "Whiskey"
      elif groupIdx == 23: "X-ray"
      elif groupIdx == 24: "Yankee"
      else: "Zulu"
    let shipName = groupName & "-" & $(letterIdx + 1)
    
    # Get ship class name
    let className = $ship.shipClass
    
    # Calculate combat state display
    var stateLabel = "Nominal"
    var isDestroyed = false
    var isCrippled = false
    case ship.state:
    of CombatState.Nominal:
      stateLabel = "Nominal"
    of CombatState.Crippled:
      stateLabel = "Crippled"
      isCrippled = true
    of CombatState.Destroyed:
      isDestroyed = true

    if isDestroyed:
      continue

    totalAS += int(ship.stats.attackStrength)
    totalDS += int(ship.stats.defenseStrength)
    
    # Get marine count for TroopTransports
    var marinesStr = "-"
    if ship.shipClass == ShipClass.TroopTransport:
      if ship.cargo.isSome and ship.cargo.get().cargoType == CargoClass.Marines:
        marinesStr = $ship.cargo.get().quantity
      else:
        marinesStr = "0"

    shipRows.add(ShipDetailRow(
      name: shipName,
      class: className,
      state: stateLabel,
      attack: $ship.stats.attackStrength,
      defense: $ship.stats.defenseStrength,
      isCrippled: isCrippled,
      wepLevel: int(ship.stats.wep),
      marines: marinesStr
    ))
  
  # Build auxiliary ships summary
  var etacCount = 0
  var ttCount = 0
  for ship in state.shipsInFleet(fleetId):
    if ship.state == CombatState.Destroyed:
      continue
    case ship.shipClass
    of ShipClass.ETAC:
      etacCount += 1
    of ShipClass.TroopTransport:
      ttCount += 1
    else:
      discard
  
  var auxShipsStr = ""
  if etacCount > 0 or ttCount > 0:
    var parts: seq[string] = @[]
    if etacCount > 0:
      parts.add($etacCount & " ETAC")
    if ttCount > 0:
      parts.add($ttCount & " Troop Transport")
    auxShipsStr = parts.join(", ")
  
  FleetDetailData(
    fleetId: int(fleetId),
    fleetName: fleet.name,
    location: locationName,
    systemId: int(fleet.location),
    shipCount: shipRows.len,
    totalAttack: totalAS,
    totalDefense: totalDS,
    command: commandStr,
    commandType: int(fleet.command.commandType),
    targetLabel: targetLabel,
    status: statusStr,
    roe: int(fleet.roe),
    ships: shipRows,
    auxShips: auxShipsStr
  )

# -----------------------------------------------------------------------------
# Planet Detail conversions
# -----------------------------------------------------------------------------

type
  QueueKind* {.pure.} = enum
    Construction
    Repair

  QueueItem* = object
    kind*: QueueKind
    name*: string
    cost*: int
    status*: string

  PlanetDetailData* = object
    colonyId*: int
    systemName*: string
    sectorLabel*: string
    planetClass*: string
    resourceRating*: string
    rawIndex*: float32
    populationUnits*: int
    industrialUnits*: int
    populationOutput*: int
    industrialOutput*: int
    gco*: int
    ncv*: int
    populationGrowthPu*: Option[float32]
    taxRate*: int
    starbaseBonusPct*: int
    blockaded*: bool
    spaceports*: int
    shipyards*: int
    drydocks*: int
    starbases*: int
    dockSummary*: DockSummary
    fleetsActive*: int
    fleetsReserve*: int
    fleetsMothball*: int
    fighters*: int
    armies*: int
    marines*: int
    batteries*: int
    shields*: int
    queue*: seq[QueueItem]
    buildOptions*: seq[BuildOption]
    autoRepair*: bool
    autoLoadMarines*: bool
    autoLoadFighters*: bool

proc defaultTechLevels(): TechLevel =
  TechLevel(
    el: 1,
    sl: 1,
    cst: 1,
    wep: 1,
    ter: 1,
    eli: 1,
    clk: 1,
    sld: 1,
    cic: 1,
    stl: 1,
    fc: 1,
    sc: 1,
    fd: 1,
    aco: 1
  )

proc humanizeEnum(name: string): string =
  result = ""
  for idx, ch in name:
    if idx > 0 and ch >= 'A' and ch <= 'Z':
      let prev = name[idx - 1]
      if prev >= 'a' and prev <= 'z':
        result.add(' ')
    result.add(ch)

proc hasOperationalFacility(
    state: GameState, colony: Colony, target: NeoriaClass
): bool =
  for neoriaId in colony.neoriaIds:
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isSome:
      let neoria = neoriaOpt.get()
      if neoria.neoriaClass == target and
          neoria.state != CombatState.Crippled:
        return true
  false

proc dockSummary(state: GameState, colonyId: ColonyId): DockSummary =
  let capacities = state.analyzeColonyCapacity(colonyId)
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

  let constructionAvailable = max(0, constructionTotal - constructionUsed)
  let repairAvailable = max(0, repairTotal - repairUsed)
  DockSummary(
    constructionAvailable: constructionAvailable,
    constructionTotal: constructionTotal,
    repairAvailable: repairAvailable,
    repairTotal: repairTotal,
  )

proc colonyToDetailData*(
  state: GameState,
  colonyId: ColonyId,
  houseId: HouseId
): PlanetDetailData =
  ## Convert engine Colony to PlanetDetailData for TUI rendering
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    logWarn("TUI", "Colony ", colonyId, " not found in state (turn ", state.turn, ")")
    return PlanetDetailData(
      colonyId: int(colonyId),
      systemName: "Colony Missing",
      sectorLabel: "?",
      planetClass: "Unknown",
      populationUnits: 0,
      industrialUnits: 0,
      gco: 0,
      ncv: 0,
      taxRate: 0
    )
  let colony = colonyOpt.get()

  var techLevels = defaultTechLevels()
  var taxRate = colony.taxRate
  var populationGrowthPu = none(float32)
  let houseOpt = state.house(houseId)
  if houseOpt.isSome:
    let house = houseOpt.get()
    techLevels = house.techTree.levels
    if taxRate <= 0:
      taxRate = house.taxPolicy.currentRate
    if house.latestIncomeReport.isSome:
      for report in house.latestIncomeReport.get().colonies:
        if report.colonyId == colonyId:
          let growth = float32(colony.populationUnits) *
            (report.populationGrowth / 100.0'f32)
          populationGrowthPu = some(growth)
          break

  var systemName = "Unknown"
  var sectorLabel = "?"
  var planetClassName = "Unknown"
  var resourceName = "Unknown"
  var rawIdx = 0.0'f32
  let systemOpt = state.system(colony.systemId)
  if systemOpt.isSome:
    let system = systemOpt.get()
    systemName = system.name
    sectorLabel = coordLabel(int(system.coords.q), int(system.coords.r))
    let classOrd = ord(system.planetClass)
    if classOrd >= 0 and classOrd < PlanetClassNames.len:
      planetClassName = PlanetClassNames[classOrd]
    let resourceOrd = ord(system.resourceRating)
    if resourceOrd >= 0 and resourceOrd < ResourceRatingNames.len:
      resourceName = ResourceRatingNames[resourceOrd]
    rawIdx =
      gameConfig.economy.rawMaterialEfficiency.multipliers[
        system.resourceRating][system.planetClass]

  let starbaseBonus = state.starbaseGrowthBonus(colony)
  let elMod = production_engine.economicLevelModifier(techLevels.el)
  let cstMod = 1.0 + (float32(techLevels.cst - 1) * 0.10)
  let prodGrowth = production_engine.productivityGrowth(taxRate)
  let populationOutput = int32(float32(colony.populationUnits) * rawIdx)
  let industrialOutput = int32(
    float32(colony.industrial.units) * elMod * cstMod *
      (1.0 + prodGrowth + starbaseBonus)
  )
  var gco = populationOutput + industrialOutput
  if colony.blockaded:
    gco = int32(float32(gco) * 0.4)
  let ncv = production_engine.calculateNetValue(gco, taxRate)
  let starbaseBonusPct = int(starbaseBonus * 100.0)

  let dockInfo = dockSummary(state, colonyId)
  let spaceports = state.countSpaceportsAtColony(colonyId).int
  let shipyards = state.countShipyardsAtColony(colonyId).int
  let drydocks = state.countDrydocksAtColony(colonyId).int
  let starbasesCount = state.countStarbasesAtColony(colonyId).int

  var armies = 0
  var marines = 0
  var batteries = 0
  var shields = 0
  for unit in state.groundUnitsAtColony(colonyId):
    case unit.stats.unitType
    of GroundClass.Army:
      armies.inc
    of GroundClass.Marine:
      marines.inc
    of GroundClass.GroundBattery:
      batteries.inc
    of GroundClass.PlanetaryShield:
      shields.inc

  let fighters = colony.fighterIds.len

  var fleetsActive = 0
  var fleetsReserve = 0
  var fleetsMothball = 0
  for fleet in state.fleetsInSystem(colony.systemId):
    if fleet.houseId != houseId:
      continue
    case fleet.status
    of FleetStatus.Active:
      fleetsActive.inc
    of FleetStatus.Reserve:
      fleetsReserve.inc
    of FleetStatus.Mothballed:
      fleetsMothball.inc

  var queue: seq[QueueItem] = @[]
  for project in state.constructionProjectsAtColony(colonyId):
    var projectName = "Unknown"
    case project.projectType
    of BuildType.Ship:
      if project.shipClass.isSome:
        projectName = humanizeEnum($project.shipClass.get())
    of BuildType.Facility:
      if project.facilityClass.isSome:
        projectName = humanizeEnum($project.facilityClass.get())
    of BuildType.Ground:
      if project.groundClass.isSome:
        projectName = humanizeEnum($project.groundClass.get())
    of BuildType.Industrial:
      projectName = "Industrial Units"
    of BuildType.Infrastructure:
      projectName = "Infrastructure"

    let status = if project.costPaid > 0: "Active" else: "Queued"
    queue.add(QueueItem(
      kind: QueueKind.Construction,
      name: projectName,
      cost: int(project.costTotal),
      status: status
    ))

  for repair in state.repairProjectsAtColony(colonyId):
    var repairName = "Repair"
    case repair.targetType
    of RepairTargetType.Ship:
      if repair.shipClass.isSome:
        repairName = humanizeEnum($repair.shipClass.get())
      else:
        repairName = "Ship"
    of RepairTargetType.Starbase:
      repairName = "Starbase"
    of RepairTargetType.GroundUnit:
      repairName = "Ground Unit"
    of RepairTargetType.Facility:
      repairName = "Facility"
    queue.add(QueueItem(
      kind: QueueKind.Repair,
      name: repairName,
      cost: int(repair.cost),
      status: "Repairing"
    ))

  var buildOptions: seq[BuildOption] = @[]
  let hasSpaceport =
    hasOperationalFacility(state, colony, NeoriaClass.Spaceport)
  let hasShipyard =
    hasOperationalFacility(state, colony, NeoriaClass.Shipyard)

  for shipClass in ShipClass:
    let cstReq =
      gameConfig.ships.ships[shipClass].minCST.int
    if techLevels.cst < cstReq:
      continue
    if shipClass == ShipClass.Fighter:
      if not state.canCommissionFighter(colony):
        continue
    if shipClass == ShipClass.PlanetBreaker:
      if not state.canBuildPlanetBreaker(houseId):
        continue
    let requiresDock = construction_docks.shipRequiresDock(shipClass)
    if requiresDock and dockInfo.constructionAvailable <= 0:
      continue
    if requiresDock and dockInfo.constructionTotal <= 0:
      continue
    let cost = int(
      gameConfig.ships.ships[shipClass].productionCost
    )
    buildOptions.add(BuildOption(
      kind: BuildOptionKind.Ship,
      name: humanizeEnum($shipClass),
      cost: cost,
      cstReq: cstReq
    ))

  for groundClass in GroundClass:
    let cstReq =
      gameConfig.groundUnits.units[groundClass].minCST.int
    if techLevels.cst < cstReq:
      continue
    if groundClass == GroundClass.PlanetaryShield:
      if not state.canBuildPlanetaryShield(colony):
        continue
    let cost = int(
      gameConfig.groundUnits.units[groundClass].productionCost
    )
    buildOptions.add(BuildOption(
      kind: BuildOptionKind.Ground,
      name: humanizeEnum($groundClass),
      cost: cost,
      cstReq: cstReq
    ))

  for facilityClass in FacilityClass:
    let cstReq =
      gameConfig.facilities.facilities[facilityClass].minCST.int
    if techLevels.cst < cstReq:
      continue
    if facilityClass == FacilityClass.Spaceport:
      if not state.canBuildSpaceport(colony):
        continue
    if facilityClass == FacilityClass.Starbase:
      if not state.canBuildStarbase(colony):
        continue
      if gameConfig.construction.construction.starbaseRequiresShipyard and
          not hasShipyard:
        continue
    if facilityClass in {FacilityClass.Shipyard, FacilityClass.Drydock}:
      if gameConfig.construction.construction.shipyardRequiresSpaceport and
          not hasSpaceport:
        continue
    if facilityClass == FacilityClass.Starbase and not hasSpaceport:
      continue
    let cost = int(
      gameConfig.facilities.facilities[facilityClass].buildCost
    )
    buildOptions.add(BuildOption(
      kind: BuildOptionKind.Facility,
      name: humanizeEnum($facilityClass),
      cost: cost,
      cstReq: cstReq
    ))

  PlanetDetailData(
    colonyId: int(colonyId),
    systemName: systemName,
    sectorLabel: sectorLabel,
    planetClass: planetClassName,
    resourceRating: resourceName,
    rawIndex: rawIdx,
    populationUnits: colony.populationUnits.int,
    industrialUnits: colony.industrial.units.int,
    populationOutput: populationOutput.int,
    industrialOutput: industrialOutput.int,
    gco: gco.int,
    ncv: ncv.int,
    populationGrowthPu: populationGrowthPu,
    taxRate: taxRate.int,
    starbaseBonusPct: starbaseBonusPct,
    blockaded: colony.blockaded,
    spaceports: spaceports,
    shipyards: shipyards,
    drydocks: drydocks,
    starbases: starbasesCount,
    dockSummary: dockInfo,
    fleetsActive: fleetsActive,
    fleetsReserve: fleetsReserve,
    fleetsMothball: fleetsMothball,
    fighters: fighters,
    armies: armies,
    marines: marines,
    batteries: batteries,
    shields: shields,
    queue: queue,
    buildOptions: buildOptions,
    autoRepair: colony.autoRepair,
    autoLoadMarines: colony.autoLoadMarines,
    autoLoadFighters: colony.autoLoadFighters
  )

# -----------------------------------------------------------------------------
# PlayerState-Only Detail Adapters (for Nostr mode)
# -----------------------------------------------------------------------------

proc shipToRow(ship: Ship): ShipDetailRow =
  ## Convert Ship to ShipDetailRow (simple version for PS-only mode)
  let shipName = "Ship #" & $ship.id
  let className = $ship.shipClass
  var stateLabel = "Nominal"
  var isCrippled = false
  case ship.state:
  of CombatState.Nominal:
    stateLabel = "Nominal"
  of CombatState.Crippled:
    stateLabel = "Crippled"
    isCrippled = true
  of CombatState.Destroyed:
    stateLabel = "Destroyed"
  
  # Get marine count for TroopTransports
  var marinesStr = "-"
  if ship.shipClass == ShipClass.TroopTransport:
    if ship.cargo.isSome and ship.cargo.get().cargoType == CargoClass.Marines:
      marinesStr = $ship.cargo.get().quantity
    else:
      marinesStr = "0"
  
  ShipDetailRow(
    name: shipName,
    class: className,
    state: stateLabel,
    attack: $ship.stats.attackStrength,
    defense: $ship.stats.defenseStrength,
    isCrippled: isCrippled,
    wepLevel: int(ship.stats.wep),
    marines: marinesStr
  )

proc fleetToDetailDataFromPS*(ps: PlayerState, fleetId: FleetId): FleetDetailData =
  ## Build FleetDetailData from PlayerState only
  ## Limited data compared to full GameState version
  for fleet in ps.ownFleets:
    if fleet.id == fleetId:
      # Get location name (include coords if known)
      var locationName = "Unknown"
      if ps.visibleSystems.hasKey(fleet.location):
        let visSys = ps.visibleSystems[fleet.location]
        locationName = visSys.name
        if visSys.coordinates.isSome:
          let coords = visSys.coordinates.get()
          let label = coordLabel(coords.q.int, coords.r.int)
          locationName &= " (" & label & ")"

      # Build command string (short label)
      let cmdNum = fleetCommandNumber(
        fleet.command.commandType
      )
      let commandStr = commandLabel(cmdNum)

      # Target label (coord if known)
      var targetLabel = "-"
      if fleet.command.commandType == FleetCommandType.JoinFleet and
          fleet.command.targetFleet.isSome:
        let targetId = fleet.command.targetFleet.get()
        var targetName = ""
        for candidate in ps.ownFleets:
          if candidate.id == targetId:
            targetName = candidate.name
            break
        if targetName.len > 0:
          targetLabel = "Fleet " & targetName
        else:
          targetLabel = "Fleet " & $targetId
      elif fleet.command.targetSystem.isSome:
        let targetId = fleet.command.targetSystem.get()
        if ps.visibleSystems.hasKey(targetId):
          let target = ps.visibleSystems[targetId]
          if target.coordinates.isSome:
            let coords = target.coordinates.get()
            targetLabel = coordLabel(coords.q.int, coords.r.int)
        else:
          targetLabel = $targetId

      # Build status string
      var statusStr = "Active"
      case fleet.status:
      of FleetStatus.Active:
        statusStr = "Active"
      of FleetStatus.Reserve:
        statusStr = "Reserve"
      of FleetStatus.Mothballed:
        statusStr = "Mothballed"

      # Build ship rows
      var shipRows: seq[ShipDetailRow] = @[]
      var totalAS = 0
      var totalDS = 0
      var etacCount = 0
      var ttCount = 0
      for shipId in fleet.ships:
        for ship in ps.ownShips:
          if ship.id == shipId:
            if ship.state != CombatState.Destroyed:
              shipRows.add(shipToRow(ship))
              totalAS += ship.stats.attackStrength.int
              totalDS += ship.stats.defenseStrength.int
              case ship.shipClass
              of ShipClass.ETAC:
                etacCount += 1
              of ShipClass.TroopTransport:
                ttCount += 1
              else:
                discard
            break
      
      # Build aux ships summary
      var auxShipsStr = ""
      if etacCount > 0 or ttCount > 0:
        var parts: seq[string] = @[]
        if etacCount > 0:
          parts.add($etacCount & " ETAC")
        if ttCount > 0:
          parts.add($ttCount & " Troop Transport")
        auxShipsStr = parts.join(", ")

      return FleetDetailData(
        fleetId: fleetId.int,
        fleetName: fleet.name,
        location: locationName,
        systemId: fleet.location.int,
        shipCount: shipRows.len,
        totalAttack: totalAS,
        totalDefense: totalDS,
        command: commandStr,
        commandType: fleet.command.commandType.int,
        targetLabel: targetLabel,
        status: statusStr,
        roe: fleet.roe.int,
        ships: shipRows,
        auxShips: auxShipsStr
      )

  # Fleet not found
  FleetDetailData(
    fleetId: fleetId.int,
    fleetName: "??",
    location: "Fleet Not Found",
    shipCount: 0,
    totalAttack: 0,
    totalDefense: 0,
    targetLabel: "-",
    ships: @[],
    auxShips: ""
  )

proc colonyToDetailDataFromPS*(ps: PlayerState, colonyId: ColonyId): PlanetDetailData =
  ## Build PlanetDetailData from PlayerState only
  ## Limited data compared to full GameState version (no build options, etc.)
  for colony in ps.ownColonies:
    if colony.id == colonyId:
      # Get system info
      var systemName = "Unknown"
      var sectorLabel = "?"
      var planetClassLabel = "Unknown"
      var resourceLabel = "Unknown"
      if ps.visibleSystems.hasKey(colony.systemId):
        let visSys = ps.visibleSystems[colony.systemId]
        systemName = visSys.name
        if visSys.coordinates.isSome:
          let coords = visSys.coordinates.get()
          sectorLabel = coordLabel(coords.q.int, coords.r.int)
        # Get planet class name
        let classIdx = int(visSys.planetClass)
        if classIdx >= 0 and classIdx < PlanetClassNames.len:
          planetClassLabel = PlanetClassNames[classIdx]
        # Get resource rating name
        let resourceIdx = int(visSys.resourceRating)
        if resourceIdx >= 0 and resourceIdx < ResourceRatingNames.len:
          resourceLabel = ResourceRatingNames[resourceIdx]

      # Count facilities by type
      var spaceports, shipyards, drydocks, starbases = 0

      for neoriaId in colony.neoriaIds:
        for neoria in ps.ownNeorias:
          if neoria.id == neoriaId:
            case neoria.neoriaClass
            of NeoriaClass.Spaceport: spaceports.inc
            of NeoriaClass.Shipyard: shipyards.inc
            of NeoriaClass.Drydock: drydocks.inc
            break

      for kastraId in colony.kastraIds:
        for kastra in ps.ownKastras:
          if kastra.id == kastraId:
            starbases.inc
            break
      
      var fleetsActive = 0
      var fleetsReserve = 0
      var fleetsMothball = 0
      let fighters = colony.fighterIds.len
      for fleet in ps.ownFleets:
        if fleet.location != colony.systemId:
          continue
        case fleet.status
        of FleetStatus.Active:
          fleetsActive.inc
        of FleetStatus.Reserve:
          fleetsReserve.inc
        of FleetStatus.Mothballed:
          fleetsMothball.inc

      return PlanetDetailData(
        colonyId: colonyId.int,
        systemName: systemName,
        sectorLabel: sectorLabel,
        planetClass: planetClassLabel,
        resourceRating: resourceLabel,
        rawIndex: 0.0,  # Not available in PlayerState
        populationUnits: colony.populationUnits.int,
        industrialUnits: colony.industrial.units.int,
        populationOutput: 0,  # Not calculated in PlayerState
        industrialOutput: 0,  # Not calculated in PlayerState
        gco: colony.grossOutput.int,
        ncv: 0,  # Would need tax rate
        populationGrowthPu: none(float32),
        taxRate: colony.taxRate.int,
        starbaseBonusPct: 0,
        blockaded: colony.blockaded,
        spaceports: spaceports,
        shipyards: shipyards,
        drydocks: drydocks,
        starbases: starbases,
        dockSummary: DockSummary(
          constructionAvailable: 0,  # Would need construction project data
          constructionTotal: colony.constructionDocks.int,
          repairAvailable: 0,
          repairTotal: colony.repairDocks.int,
        ),
        fleetsActive: fleetsActive,
        fleetsReserve: fleetsReserve,
        fleetsMothball: fleetsMothball,
        fighters: fighters,
        armies: 0,  # Would need ground unit data
        marines: 0,
        batteries: 0,
        shields: 0,
        queue: @[],  # Construction queue not fully detailed in PlayerState
        buildOptions: @[],  # Would need full GameState to compute
        autoRepair: colony.autoRepair,
        autoLoadMarines: colony.autoLoadMarines,
        autoLoadFighters: colony.autoLoadFighters
      )

  # Colony not found
  PlanetDetailData(
    colonyId: colonyId.int,
    systemName: "Colony Not Found",
    sectorLabel: "?",
    planetClass: "Unknown",
    populationUnits: 0,
    industrialUnits: 0,
    gco: 0,
    ncv: 0,
    taxRate: 0
  )

# -----------------------------------------------------------------------------
# Build Options from PlayerState (for Nostr mode)
# -----------------------------------------------------------------------------

proc computeBuildOptionsFromPS*(ps: PlayerState,
                               colonyId: ColonyId): tuple[
                                 options: seq[BuildOption],
                                 dockSummary: DockSummary] =
  ## Compute build options from PlayerState + gameConfig
  ## Used in Nostr mode where full GameState is not available
  ##
  ## TODO: Get tech levels from PlayerState (currently using defaults)

  # Find colony in PlayerState
  var colony: Option[Colony] = none(Colony)
  for col in ps.ownColonies:
    if col.id == colonyId:
      colony = some(col)
      break

  if colony.isNone:
    return (
      options: @[],
      dockSummary: DockSummary(
        constructionAvailable: 0,
        constructionTotal: 0,
        repairAvailable: 0,
        repairTotal: 0
      )
    )

  let col = colony.get()

  # TODO: Get tech levels from PlayerState
  # For now, use default tech levels (CST=1)
  # This means only basic builds will be available
  var techLevels = defaultTechLevels()

  # Get dock summary from colony data
  let dockInfo = DockSummary(
    constructionAvailable: max(0, col.constructionDocks.int),
    constructionTotal: col.constructionDocks.int,
    repairAvailable: max(0, col.repairDocks.int),
    repairTotal: col.repairDocks.int
  )

  # Compute available build options
  var options: seq[BuildOption] = @[]

  # Note: Some checks like hasOperationalFacility, canCommissionFighter, etc.
  # require GameState. For now, we skip those checks in PS-only mode.
  # TODO: Add facility counts to PlayerState or compute from neoria counts

  # Ships
  for shipClass in ShipClass:
    let cstReq = gameConfig.ships.ships[shipClass].minCST.int
    if techLevels.cst < cstReq:
      continue
    # Skip fighters and planet breakers for now (need special checks)
    if shipClass in {ShipClass.Fighter, ShipClass.PlanetBreaker}:
      continue
    let requiresDock = construction_docks.shipRequiresDock(shipClass)
    if requiresDock and dockInfo.constructionTotal <= 0:
      continue
    let cost = int(gameConfig.ships.ships[shipClass].productionCost)
    options.add(BuildOption(
      kind: BuildOptionKind.Ship,
      name: humanizeEnum($shipClass),
      cost: cost,
      cstReq: cstReq
    ))

  # Ground units
  for groundClass in GroundClass:
    let cstReq = gameConfig.groundUnits.units[groundClass].minCST.int
    if techLevels.cst < cstReq:
      continue
    # Skip planetary shields for now (needs special check)
    if groundClass == GroundClass.PlanetaryShield:
      continue
    let cost = int(gameConfig.groundUnits.units[groundClass].productionCost)
    options.add(BuildOption(
      kind: BuildOptionKind.Ground,
      name: humanizeEnum($groundClass),
      cost: cost,
      cstReq: cstReq
    ))

  # Facilities
  for facilityClass in FacilityClass:
    let cstReq = gameConfig.facilities.facilities[facilityClass].minCST.int
    if techLevels.cst < cstReq:
      continue
    # Skip spaceport and starbase for now (need special checks)
    if facilityClass in {FacilityClass.Spaceport, FacilityClass.Starbase}:
      continue
    let cost = int(gameConfig.facilities.facilities[facilityClass].buildCost)
    options.add(BuildOption(
      kind: BuildOptionKind.Facility,
      name: humanizeEnum($facilityClass),
      cost: cost,
      cstReq: cstReq
    ))

  (options: options, dockSummary: dockInfo)

# =============================================================================
# Fleet Command Filtering Helpers
# =============================================================================

proc fleetHasStagedCommand*(fleetId: int, stagedCommands: seq[FleetCommand]): bool =
  ## Check if a fleet has a staged command
  for cmd in stagedCommands:
    if int(cmd.fleetId) == fleetId:
      return true
  false

proc isFleetCommandAvailable*(
  cmdType: FleetCommandType,
  fleet: ref Fleet,
  ps: PlayerState
): bool =
  ## Check if a fleet command is available for the given fleet
  ## Phase 1: Simple checks, Phase 2 will add composition filtering
  
  # All movement commands are always available
  if cmdType in {FleetCommandType.Hold, FleetCommandType.Move,
                FleetCommandType.SeekHome, FleetCommandType.Patrol}:
    return true
  
  # Status commands are always available
  if cmdType in {FleetCommandType.Reserve, FleetCommandType.Mothball}:
    return true
  
  # Fleet ops are always available
  if cmdType in {FleetCommandType.JoinFleet, FleetCommandType.Rendezvous,
                FleetCommandType.Salvage}:
    return true
  
  # Intel commands - View is always available, others need scouts (TODO Phase 2)
  if cmdType == FleetCommandType.View:
    return true
  
  if cmdType in {FleetCommandType.ScoutColony, FleetCommandType.ScoutSystem,
                FleetCommandType.HackStarbase}:
    # Phase 2: check for scout/EW ships
    return true
  
  # Defense commands - need combat ships (TODO Phase 2)
  if cmdType in {FleetCommandType.GuardStarbase, FleetCommandType.GuardColony,
                FleetCommandType.Blockade}:
    # Phase 2: check for combat ships
    return true
  
  # Combat commands
  if cmdType == FleetCommandType.Bombard:
    # Phase 2: check for combat ships
    return true
  
  if cmdType in {FleetCommandType.Invade, FleetCommandType.Blitz}:
    # Phase 2: check for TroopTransports with marines
    return true
  
  # Colonial commands
  if cmdType == FleetCommandType.Colonize:
    # Phase 2: check for ColonyShip
    return true
  
  false
