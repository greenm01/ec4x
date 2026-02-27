## Starmap SVG export - generates node-edge graph visualization
##
## Creates an SVG starmap showing systems as positioned circles
## connected by styled lines for jump lanes.

import std/[options, tables, strformat]
import ./node_layout
import ./svg_builder
import ../tui/hex_labels
import ../../engine/types/[core, starmap, player_state]
import ../../engine/state/[engine, fog_of_war]

const
  DefaultWidth = 1000
  DefaultHeight = 1000
  DefaultPadding = 80.0

type
  SystemNode = object
    id: int
    name: string
    coordLabel: string
    q, r: int
    position: Point
    nodeType: NodeType
    isHomeworld: bool
    ownerHouseId: Option[int]
    planetClass: int      # -1 if unknown
    resourceRating: int   # -1 if unknown

  LaneEdge = object
    fromId, toId: int
    fromPos, toPos: Point
    laneType: int  # 0=Major, 1=Minor, 2=Restricted

# -----------------------------------------------------------------------------
# Planet/Resource code helpers
# -----------------------------------------------------------------------------

const
  PlanetCodes = ["EX", "DE", "HO", "HA", "BE", "LU", "ED"]
  ResourceCodes = ["VP", "P", "A", "R", "VR"]

proc planetCode(planetClass: int): string =
  if planetClass >= 0 and planetClass < PlanetCodes.len:
    PlanetCodes[planetClass]
  else:
    ""

proc resourceCode(resourceRating: int): string =
  if resourceRating >= 0 and resourceRating < ResourceCodes.len:
    ResourceCodes[resourceRating]
  else:
    ""

proc infoCode(planetClass, resourceRating: int): string =
  ## Generate compact info code like "EX-A" for Extreme/Average
  let pc = planetCode(planetClass)
  let rc = resourceCode(resourceRating)
  if pc.len > 0 and rc.len > 0:
    pc & "-" & rc
  elif pc.len > 0:
    pc
  elif rc.len > 0:
    rc
  else:
    ""

# -----------------------------------------------------------------------------
# Data extraction from game state
# -----------------------------------------------------------------------------

proc extractSystems(state: GameState, houseId: HouseId,
                    scale: float, center: Point): seq[SystemNode] =
  ## Extract system data with fog-of-war filtering
  let playerState = createPlayerState(state, houseId)
  
  for systemId, visibleSys in playerState.visibleSystems.pairs:
    let sysOpt = state.system(systemId)
    if sysOpt.isNone:
      continue
    
    let sys = sysOpt.get()
    let q = int(sys.coords.q)
    let r = int(sys.coords.r)
    let pos = hexToPixel(q, r, scale, center.x, center.y)
    let label = coordLabel(q, r)
    
    # Determine node type based on visibility and ownership
    var nodeType = NodeType.Neutral
    var ownerHouse = none(int)
    var isHomeworld = false
    var planetClass = -1
    var resourceRating = -1
    
    # Check if hub
    let isHub = sys.id == state.starmap.hubId
    if isHub:
      nodeType = NodeType.Hub
    
    # Check visibility and ownership
    case visibleSys.visibility
    of VisibilityLevel.Owned:
      nodeType = if isHub: NodeType.Hub else: NodeType.OwnColony
      ownerHouse = some(int(houseId))
      planetClass = ord(sys.planetClass)
      resourceRating = ord(sys.resourceRating)
      
      # Check homeworld
      for homeSystem, homeHouse in state.starmap.homeWorlds.pairs:
        if homeSystem == systemId and homeHouse == houseId:
          isHomeworld = true
          break
    
    of VisibilityLevel.Occupied, VisibilityLevel.Scouted:
      planetClass = ord(sys.planetClass)
      resourceRating = ord(sys.resourceRating)
      
      # Check for enemy colony
      for visCol in playerState.visibleColonies:
        if visCol.systemId == systemId:
          nodeType = NodeType.EnemyColony
          ownerHouse = some(int(visCol.owner))
          break
    
    of VisibilityLevel.Adjacent, VisibilityLevel.None:
      # Limited info - just coordinates visible
      discard
    
    result.add(SystemNode(
      id: int(systemId),
      name: sys.name,
      coordLabel: label,
      q: q,
      r: r,
      position: pos,
      nodeType: nodeType,
      isHomeworld: isHomeworld,
      ownerHouseId: ownerHouse,
      planetClass: planetClass,
      resourceRating: resourceRating
    ))

proc extractLanes(state: GameState, systems: seq[SystemNode]): seq[LaneEdge] =
  ## Extract jump lane data
  # Build position lookup
  var posLookup = initTable[int, Point]()
  for sys in systems:
    posLookup[sys.id] = sys.position
  
  # Track which lanes we've already added (avoid duplicates)
  var seen = initTable[(int, int), bool]()
  
  for lane in state.starmap.lanes.data:
    let fromId = int(lane.source)
    let toId = int(lane.destination)
    
    # Skip if we don't have both endpoints
    if not posLookup.hasKey(fromId) or not posLookup.hasKey(toId):
      continue
    
    # Skip duplicates (lanes are bidirectional)
    let key = if fromId < toId: (fromId, toId) else: (toId, fromId)
    if seen.hasKey(key):
      continue
    seen[key] = true
    
    result.add(LaneEdge(
      fromId: fromId,
      toId: toId,
      fromPos: posLookup[fromId],
      toPos: posLookup[toId],
      laneType: ord(lane.laneType)
    ))

# -----------------------------------------------------------------------------
# SVG rendering
# -----------------------------------------------------------------------------

proc renderLanes(builder: var SvgBuilder, lanes: seq[LaneEdge]) =
  ## Render all jump lanes
  var lanesSvg = ""
  for lane in lanes:
    let class = laneClass(lane.laneType)
    lanesSvg.add(svgLine(lane.fromPos.x, lane.fromPos.y,
                         lane.toPos.x, lane.toPos.y, class))
    lanesSvg.add("\n")
  
  builder.add(svgGroup("lanes", lanesSvg))

proc renderNodes(builder: var SvgBuilder, systems: seq[SystemNode]) =
  ## Render all system nodes with planet/resource info inside
  var nodesSvg = ""
  for sys in systems:
    let class = nodeClass(sys.nodeType)
    let radius = nodeRadius(sys.nodeType, sys.isHomeworld)
    
    # Style for owned/enemy colonies
    var style = ""
    if sys.nodeType == NodeType.OwnColony and sys.ownerHouseId.isSome:
      style = &"fill: {houseColor(sys.ownerHouseId.get)}"
    elif sys.nodeType == NodeType.EnemyColony and sys.ownerHouseId.isSome:
      style = &"stroke: {houseColor(sys.ownerHouseId.get)}"
    
    # Circle
    nodesSvg.add(svgCircle(sys.position.x, sys.position.y, radius,
                           class, style))
    nodesSvg.add("\n")
    
    # Planet/resource code inside circle (e.g., "EX-A")
    let info = infoCode(sys.planetClass, sys.resourceRating)
    if info.len > 0:
      nodesSvg.add(svgText(sys.position.x, sys.position.y,
                           info, "label-inside"))
      nodesSvg.add("\n")
  
  builder.add(svgGroup("nodes", nodesSvg))

proc renderLabels(builder: var SvgBuilder, systems: seq[SystemNode]) =
  ## Render system labels (name and coordinate below circle)
  ## Planet/resource info is rendered inside the circle by renderNodes
  var labelsSvg = ""
  for sys in systems:
    let x = sys.position.x
    let y = sys.position.y + nodeRadius(sys.nodeType, sys.isHomeworld) + 12.0
    
    # Name
    labelsSvg.add(svgText(x, y, sys.name, "label label-name"))
    labelsSvg.add("\n")
    
    # Coordinate
    labelsSvg.add(svgText(x, y + 12.0, sys.coordLabel, "label label-coord"))
    labelsSvg.add("\n")
  
  builder.add(svgGroup("labels", labelsSvg))

proc renderLegend(builder: var SvgBuilder, width, height: int,
                  viewingHouse: int,
                  houseNames: seq[tuple[id: int, name: string]]) =
  ## Render the legend in the corner
  var legendSvg = ""
  var y = 0.0

  # Title
  legendSvg.add(svgText(0.0, y, "LEGEND", "legend-title"))
  y += 20.0

  # Lane types
  legendSvg.add(svgText(0.0, y, "Lanes:", "legend-text"))
  y += 15.0
  legendSvg.add(svgLine(0.0, y, 30.0, y, "lane lane-major"))
  legendSvg.add(svgText(40.0, y + 4.0, "Major", "legend-text"))
  y += 15.0
  legendSvg.add(svgLine(0.0, y, 30.0, y, "lane lane-minor"))
  legendSvg.add(svgText(40.0, y + 4.0, "Minor", "legend-text"))
  y += 15.0
  legendSvg.add(svgLine(0.0, y, 30.0, y, "lane lane-restricted"))
  legendSvg.add(svgText(40.0, y + 4.0, "Restricted", "legend-text"))
  y += 25.0

  # Node types - use actual viewing house color so legend matches the map
  let ownColor = houseColor(viewingHouse)
  let enemyExampleId = if viewingHouse == 0: 1 else: 0
  let enemyColor = houseColor(enemyExampleId)
  legendSvg.add(svgText(0.0, y, "Systems:", "legend-text"))
  y += 18.0
  legendSvg.add(svgCircle(12.0, y, 12.0, "node-hub", ""))
  legendSvg.add(svgText(36.0, y + 4.0, "Hub", "legend-text"))
  y += 28.0
  legendSvg.add(svgCircle(12.0, y, 10.0, "node-own",
                          &"fill: {ownColor}"))
  legendSvg.add(svgText(36.0, y + 4.0, "Your Colony", "legend-text"))
  y += 26.0
  legendSvg.add(svgCircle(12.0, y, 10.0, "node-enemy",
                          &"stroke: {enemyColor}"))
  legendSvg.add(svgText(36.0, y + 4.0, "Enemy Colony", "legend-text"))
  y += 26.0
  legendSvg.add(svgCircle(12.0, y, 8.0, "node-neutral", ""))
  legendSvg.add(svgText(36.0, y + 4.0, "Neutral", "legend-text"))
  y += 28.0
  
  # Info code format explanation
  legendSvg.add(svgText(0.0, y, "Node text: Planet-Resource", "legend-text"))
  y += 18.0
  legendSvg.add(svgText(0.0, y, "e.g. HO-R = Hostile/Rich", "legend-text"))
  y += 22.0
  
  # Planet codes
  legendSvg.add(svgText(0.0, y, "Planet codes:", "legend-text"))
  y += 15.0
  legendSvg.add(svgText(0.0, y, "EX DE HO HA BE LU ED", "legend-text"))
  y += 18.0
  
  # Resource codes
  legendSvg.add(svgText(0.0, y, "Resource codes:", "legend-text"))
  y += 15.0
  legendSvg.add(svgText(0.0, y, "VP P A R VR", "legend-text"))
  y += 25.0
  
  # House colors (if any known)
  if houseNames.len > 0:
    legendSvg.add(svgText(0.0, y, "Houses:", "legend-text"))
    y += 15.0
    for house in houseNames:
      let color = houseColor(house.id)
      legendSvg.add(&"""  <rect x="0" y="{y - 8:.0f}" width="12" height="12" fill="{color}"/>""")
      legendSvg.add(svgText(20.0, y, house.name, "legend-text"))
      y += 18.0
  
  builder.add(svgGroupTransform("legend", 30.0, 30.0, legendSvg))

# -----------------------------------------------------------------------------
# Main export function
# -----------------------------------------------------------------------------

proc generateStarmap*(state: GameState, houseId: HouseId,
                      width: int = DefaultWidth,
                      height: int = DefaultHeight): string =
  ## Generate complete SVG starmap for a house
  ##
  ## Args:
  ##   state: Current game state
  ##   houseId: House viewing the map (for fog-of-war)
  ##   width, height: SVG dimensions
  ##
  ## Returns: Complete SVG string
  
  # Calculate scale based on map size
  var maxRing = 0
  for systemId in state.systems.entities.index.keys:
    let sysOpt = state.system(systemId)
    if sysOpt.isSome:
      let ring = int(sysOpt.get().ring)
      if ring > maxRing:
        maxRing = ring
  
  let scale = calculateScale(maxRing, float(min(width, height)),
                             DefaultPadding)
  let center = point(float(width) / 2.0, float(height) / 2.0)
  
  # Extract data
  let systems = extractSystems(state, houseId, scale, center)
  let lanes = extractLanes(state, systems)
  
  # Collect house names for legend
  var houseNames: seq[tuple[id: int, name: string]] = @[]
  for i in 0 ..< state.housesCount():
    let houseOpt = state.house(HouseId(i))
    if houseOpt.isSome:
      houseNames.add((id: int(i), name: houseOpt.get().name))
  
  # Build SVG
  var builder = initSvgBuilder(width, height)
  renderLanes(builder, lanes)
  renderNodes(builder, systems)
  renderLabels(builder, systems)
  renderLegend(builder, width, height, int(houseId), houseNames)

  builder.build()

proc generateStarmapFromPlayerState*(
    ps: PlayerState,
    width: int = DefaultWidth,
    height: int = DefaultHeight
): string =
  ## Generate complete SVG starmap from a PlayerState (Nostr mode)
  ##
  ## Uses fog-of-war filtered visible systems from PlayerState so no
  ## full GameState is needed. Suitable for client-only (Nostr) mode.

  # Determine map extent for scale calculation
  var maxRing = 0
  for _, visSys in ps.visibleSystems.pairs:
    if visSys.coordinates.isSome:
      let (q, r) = (visSys.coordinates.get().q.int,
                    visSys.coordinates.get().r.int)
      let ring = max(abs(q), max(abs(r), abs(-q - r)))
      if ring > maxRing:
        maxRing = ring
  if maxRing == 0:
    maxRing = 5

  let scale = calculateScale(
    maxRing, float(min(width, height)), DefaultPadding)
  let center = point(float(width) / 2.0, float(height) / 2.0)

  # Build system nodes from visible systems
  var systems: seq[SystemNode] = @[]
  var posLookup = initTable[int, Point]()

  for systemId, visSys in ps.visibleSystems.pairs:
    if visSys.coordinates.isNone:
      continue
    let coords = visSys.coordinates.get()
    let q = int(coords.q)
    let r = int(coords.r)
    let pos = hexToPixel(q, r, scale, center.x, center.y)
    let label = coordLabel(q, r)

    var nodeType = NodeType.Neutral
    var ownerHouse = none(int)
    var isHomeworld = false
    let planetClass = int(visSys.planetClass)
    let resourceRating = int(visSys.resourceRating)

    case visSys.visibility
    of VisibilityLevel.Owned:
      nodeType = NodeType.OwnColony
      ownerHouse = some(int(ps.viewingHouse))
      if ps.homeworldSystemId.isSome and
          ps.homeworldSystemId.get() == systemId:
        isHomeworld = true
    of VisibilityLevel.Occupied, VisibilityLevel.Scouted:
      for visCol in ps.visibleColonies:
        if visCol.systemId == systemId:
          nodeType = NodeType.EnemyColony
          ownerHouse = some(int(visCol.owner))
          break
    of VisibilityLevel.Adjacent, VisibilityLevel.None:
      discard

    let sysId = int(systemId)
    posLookup[sysId] = pos
    systems.add(SystemNode(
      id: sysId,
      name: visSys.name,
      coordLabel: label,
      q: q,
      r: r,
      position: pos,
      nodeType: nodeType,
      isHomeworld: isHomeworld,
      ownerHouseId: ownerHouse,
      planetClass: planetClass,
      resourceRating: resourceRating
    ))

  # Build lanes from PlayerState jump lanes
  var lanes: seq[LaneEdge] = @[]
  var seen = initTable[(int, int), bool]()
  for lane in ps.jumpLanes:
    let fromId = int(lane.source)
    let toId = int(lane.destination)
    if not posLookup.hasKey(fromId) or not posLookup.hasKey(toId):
      continue
    let key = if fromId < toId: (fromId, toId) else: (toId, fromId)
    if seen.hasKey(key):
      continue
    seen[key] = true
    lanes.add(LaneEdge(
      fromId: fromId,
      toId: toId,
      fromPos: posLookup[fromId],
      toPos: posLookup[toId],
      laneType: ord(lane.laneType)
    ))

  # Collect house names for legend
  var houseNames: seq[tuple[id: int, name: string]] = @[]
  for houseId, name in ps.houseNames.pairs:
    houseNames.add((id: int(houseId), name: name))

  # Build SVG
  var builder = initSvgBuilder(width, height)
  renderLanes(builder, lanes)
  renderNodes(builder, systems)
  renderLabels(builder, systems)
  renderLegend(builder, width, height, int(ps.viewingHouse), houseNames)

  builder.build()
