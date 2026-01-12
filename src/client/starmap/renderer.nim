## Starmap Renderer - Draw hex grid and lanes using sokol_gl
##
## Renders the starmap with:
## - Jump lanes (colored by type)
## - Hex grid outlines
## - System markers (colored by owner)
## - Selection/hover highlights

import std/[options, math]
import hex_math
import camera
import theme
import ../bindings/sokol_gl

type
  LaneType* {.pure.} = enum
    Major
    Minor
    Restricted

  SystemInfo* = object
    ## Minimal system info needed for rendering
    coord*: HexCoord
    ownerIndex*: Option[int]  ## House index (0-11) or none for unowned

  LaneInfo* = object
    ## Lane info for rendering
    source*: HexCoord
    dest*: HexCoord
    laneType*: LaneType

  StarmapRenderData* = object
    ## Data needed to render the starmap
    systems*: seq[SystemInfo]
    lanes*: seq[LaneInfo]
    hoveredSystem*: Option[HexCoord]
    selectedSystem*: Option[HexCoord]

const
  HexLineWidth = 2.0f
  LaneLineWidth = 3.0f
  SelectionLineWidth = 4.0f
  HexVertexCount = 6

# --- Color Application ---

proc setColor(c: Color) {.inline.} =
  sgl_c4f(c.r, c.g, c.b, c.a)

# --- Drawing Primitives ---

proc drawLine*(p1, p2: Vec2, col: Color, width: float32 = 1.0f) =
  ## Draw a line between two points.
  ## Note: sokol_gl doesn't support line width directly,
  ## so we draw as a thin quad for thicker lines if needed.
  setColor(col)
  sgl_begin_lines()
  sgl_v2f(p1.x, p1.y)
  sgl_v2f(p2.x, p2.y)
  sgl_end()

proc drawHexOutline*(center: Vec2, size: float32, col: Color) =
  ## Draw hex outline as a line loop.
  let verts = hexVertices(center, size)
  setColor(col)
  sgl_begin_line_strip()
  for i in 0..5:
    sgl_v2f(verts[i].x, verts[i].y)
  # Close the loop
  sgl_v2f(verts[0].x, verts[0].y)
  sgl_end()

proc drawFilledHex*(center: Vec2, size: float32, col: Color) =
  ## Draw filled hex using triangle fan.
  let verts = hexVertices(center, size)
  setColor(col)
  sgl_begin_triangles()
  for i in 0..5:
    let next = (i + 1) mod 6
    # Triangle from center to edge
    sgl_v2f(center.x, center.y)
    sgl_v2f(verts[i].x, verts[i].y)
    sgl_v2f(verts[next].x, verts[next].y)
  sgl_end()

proc drawCircle*(center: Vec2, radius: float32, col: Color,
    segments: int = 16) =
  ## Draw filled circle using triangle fan.
  setColor(col)
  sgl_begin_triangles()
  for i in 0..<segments:
    let angle1 = (i.float32 / segments.float32) * 2.0f * PI.float32
    let angle2 = ((i + 1).float32 / segments.float32) * 2.0f * PI.float32
    sgl_v2f(center.x, center.y)
    sgl_v2f(center.x + radius * cos(angle1), center.y + radius * sin(angle1))
    sgl_v2f(center.x + radius * cos(angle2), center.y + radius * sin(angle2))
  sgl_end()

proc drawCircleOutline*(center: Vec2, radius: float32, col: Color,
    segments: int = 16) =
  ## Draw circle outline.
  setColor(col)
  sgl_begin_line_strip()
  for i in 0..segments:
    let angle = (i.float32 / segments.float32) * 2.0f * PI.float32
    sgl_v2f(center.x + radius * cos(angle), center.y + radius * sin(angle))
  sgl_end()

# --- Lane Rendering ---

proc laneColor(theme: StarmapTheme, laneType: LaneType): Color =
  case laneType
  of LaneType.Major: theme.majorLaneColor
  of LaneType.Minor: theme.minorLaneColor
  of LaneType.Restricted: theme.restrictedLaneColor

proc renderLanes*(data: StarmapRenderData, theme: StarmapTheme,
    hexSize: float32) =
  ## Render all jump lanes.
  for lane in data.lanes:
    let p1 = hexToPixel(lane.source, hexSize)
    let p2 = hexToPixel(lane.dest, hexSize)
    let col = theme.laneColor(lane.laneType)
    drawLine(p1, p2, col, LaneLineWidth)

# --- System Rendering ---

proc systemColor(theme: StarmapTheme, system: SystemInfo): Color =
  if system.ownerIndex.isSome:
    theme.houseColor(system.ownerIndex.get)
  else:
    theme.unownedColonyColor

proc renderSystems*(data: StarmapRenderData, theme: StarmapTheme,
    hexSize: float32) =
  ## Render all systems as hex outlines with center markers.
  for system in data.systems:
    let center = hexToPixel(system.coord, hexSize)
    let col = systemColor(theme, system)

    # Draw hex outline
    drawHexOutline(center, hexSize, theme.gridLineColor)

    # Draw center marker (small filled circle)
    let markerRadius = hexSize * 0.15f
    drawCircle(center, markerRadius, col)

# --- Selection/Hover Rendering ---

proc renderSelection*(data: StarmapRenderData, theme: StarmapTheme,
    hexSize: float32) =
  ## Render selection and hover highlights.

  # Hover highlight (lighter outline)
  if data.hoveredSystem.isSome:
    let center = hexToPixel(data.hoveredSystem.get, hexSize)
    let hoverSize = hexSize * 1.05f  # Slightly larger
    drawHexOutline(center, hoverSize, theme.unownedColonyColor.withAlpha(0.5f))

  # Selection highlight (bright outline)
  if data.selectedSystem.isSome:
    let center = hexToPixel(data.selectedSystem.get, hexSize)
    let selectSize = hexSize * 1.1f  # Larger than hover
    drawHexOutline(center, selectSize, color(1.0f, 1.0f, 1.0f, 0.8f))
    # Inner glow
    drawHexOutline(center, hexSize * 1.02f, color(1.0f, 1.0f, 1.0f, 0.4f))

# --- Main Render Function ---

proc renderStarmap*(data: StarmapRenderData, cam: Camera2D,
    theme: StarmapTheme, screenWidth, screenHeight: int32,
    hexSize: float32 = HexSize) =
  ## Main starmap render function.
  ## Call this after sg_begin_pass and before snk_render.

  # Set up sokol_gl defaults
  sgl_defaults()

  # Apply camera transform
  cam.applyTransform(screenWidth, screenHeight)

  # Draw in order: lanes -> systems -> selection
  # (back to front for proper layering)
  renderLanes(data, theme, hexSize)
  renderSystems(data, theme, hexSize)
  renderSelection(data, theme, hexSize)

  # Submit draw commands
  sgl_draw()

# --- Demo/Test Data ---

proc createDemoStarmap*(): StarmapRenderData =
  ## Create demo starmap data for testing.
  ## Generates a small hex grid with some lanes.
  result = StarmapRenderData()

  # Generate systems in a small grid (rings 0-2)
  # Ring 0: center
  result.systems.add(SystemInfo(coord: hexCoord(0, 0), ownerIndex: some(0)))

  # Ring 1: 6 hexes around center
  let ring1 = [
    hexCoord(1, 0), hexCoord(0, 1), hexCoord(-1, 1),
    hexCoord(-1, 0), hexCoord(0, -1), hexCoord(1, -1)
  ]
  for i, coord in ring1:
    let owner = if i < 3: some(i + 1) else: none(int)
    result.systems.add(SystemInfo(coord: coord, ownerIndex: owner))

  # Ring 2: 12 hexes
  let ring2 = [
    hexCoord(2, 0), hexCoord(1, 1), hexCoord(0, 2),
    hexCoord(-1, 2), hexCoord(-2, 1), hexCoord(-2, 0),
    hexCoord(-1, -1), hexCoord(0, -2), hexCoord(1, -2),
    hexCoord(2, -2), hexCoord(2, -1), hexCoord(1, -1)
  ]
  for coord in ring2:
    result.systems.add(SystemInfo(coord: coord, ownerIndex: none(int)))

  # Generate lanes from center to ring 1
  for coord in ring1:
    result.lanes.add(LaneInfo(
      source: hexCoord(0, 0),
      dest: coord,
      laneType: LaneType.Major
    ))

  # Some minor lanes between ring 1 hexes
  result.lanes.add(LaneInfo(
    source: ring1[0], dest: ring1[1], laneType: LaneType.Minor))
  result.lanes.add(LaneInfo(
    source: ring1[2], dest: ring1[3], laneType: LaneType.Minor))
  result.lanes.add(LaneInfo(
    source: ring1[4], dest: ring1[5], laneType: LaneType.Restricted))
