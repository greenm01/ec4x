## HexMap - Scrollable hex grid starmap widget
##
## Displays the EC4X starmap as a scrollable hex grid with cursor navigation.
## Uses StatefulWidget pattern with HexMapState for persistent state.
##
## Key features:
## - Axial coordinate system (flat-top hexes)
## - Viewport scrolling to keep cursor visible
## - Fog-of-war aware rendering
## - Selection highlighting

import std/[options, tables]
import ./coords
import ./symbols
import ../frame
import ../../buffer
import ../../layout/rect

type
  SystemInfo* = object
    ## Minimal system info for rendering (decoupled from engine types)
    id*: int
    name*: string
    coords*: HexCoord
    ring*: int
    planetClass*: int       ## 0=Extreme to 6=Eden
    resourceRating*: int    ## 0=VeryPoor to 4=VeryRich
    owner*: Option[int]     ## House ID if colonized
    isHomeworld*: bool
    isHub*: bool
    fleetCount*: int        ## Number of fleets present

  MapData* = object
    ## Map data for rendering (view layer, not engine types)
    systems*: Table[HexCoord, SystemInfo]
    maxRing*: int
    viewingHouse*: int      ## House ID of the player viewing

  HexMapState* = object
    ## Persistent state for hex map widget
    cursor*: HexCoord       ## Current cursor position
    selected*: Option[HexCoord]  ## Selected hex (if any)
    viewportOrigin*: HexCoord    ## Top-left of visible area
    colors*: HexColors

  HexMap* = object
    ## Hex map widget
    data*: MapData
    blk: Option[Frame]
    ascii: bool             ## Use ASCII fallback symbols
    showRings: bool         ## Show ring indicators

# -----------------------------------------------------------------------------
# HexMapState operations
# -----------------------------------------------------------------------------

proc newHexMapState*(startAt: HexCoord = hexCoord(0, 0)): HexMapState =
  ## Create new hex map state with cursor at given position
  HexMapState(
    cursor: startAt,
    selected: none(HexCoord),
    viewportOrigin: hexCoord(0, 0),
    colors: defaultColors()
  )

proc moveCursor*(state: var HexMapState, dir: HexDirection) =
  ## Move cursor to adjacent hex
  state.cursor = state.cursor.neighbor(dir)

proc selectCurrent*(state: var HexMapState) =
  ## Select hex at cursor position
  state.selected = some(state.cursor)

proc deselect*(state: var HexMapState) =
  ## Clear selection
  state.selected = none(HexCoord)

proc centerOn*(state: var HexMapState, hex: HexCoord) =
  ## Center viewport on a hex
  state.cursor = hex

# -----------------------------------------------------------------------------
# HexMap constructors
# -----------------------------------------------------------------------------

proc hexMap*(data: MapData): HexMap =
  ## Create a hex map widget from map data
  HexMap(
    data: data,
    blk: none(Frame),
    ascii: false,
    showRings: false
  )

proc `block`*(m: HexMap, b: Frame): HexMap =
  ## Wrap hex map in a frame
  result = m
  result.blk = some(b)

proc ascii*(m: HexMap, useAscii: bool = true): HexMap =
  ## Use ASCII fallback symbols
  result = m
  result.ascii = useAscii

proc showRings*(m: HexMap, show: bool = true): HexMap =
  ## Show ring distance indicators
  result = m
  result.showRings = show

# -----------------------------------------------------------------------------
# Symbol selection
# -----------------------------------------------------------------------------

proc getHexSymbol(m: HexMap, coord: HexCoord): HexSymbol =
  ## Determine which symbol to show for a hex
  if not m.data.systems.hasKey(coord):
    return HexSymbol.Empty
  
  let sys = m.data.systems[coord]
  
  if sys.isHub:
    return HexSymbol.Hub
  
  if sys.owner.isNone:
    return HexSymbol.Neutral
  
  let owner = sys.owner.get()
  
  if owner == m.data.viewingHouse:
    if sys.isHomeworld:
      return HexSymbol.Homeworld
    else:
      return HexSymbol.Colony
  else:
    return HexSymbol.EnemyColony

proc getHexStyle(m: HexMap, coord: HexCoord, state: HexMapState): CellStyle =
  ## Get style for rendering a hex
  let sym = m.getHexSymbol(coord)
  let baseStyle = state.colors.styleFor(sym)
  
  # Convert Style to CellStyle
  result = CellStyle(
    fg: baseStyle.fg,
    bg: baseStyle.bg,
    attrs: baseStyle.attrs
  )
  
  # Override for cursor position
  if coord == state.cursor:
    let cursorStyle = state.colors.cursor
    result.fg = cursorStyle.fg
    result.attrs = result.attrs + cursorStyle.attrs

# -----------------------------------------------------------------------------
# Rendering
# -----------------------------------------------------------------------------

proc updateViewport(state: var HexMapState, contentArea: Rect) =
  ## Ensure cursor is visible, adjusting viewport if needed
  let margin = 2
  state.viewportOrigin = viewportForHex(
    state.cursor,
    contentArea.width div HexWidth,
    contentArea.height,
    state.viewportOrigin,
    margin
  )

proc render*(m: HexMap, area: Rect, buf: var CellBuffer,
             state: var HexMapState) =
  ## Render the hex map to the buffer
  if area.isEmpty:
    return
  
  # Render optional frame
  var contentArea = area
  if m.blk.isSome:
    let blk = m.blk.get()
    blk.render(area, buf)
    contentArea = blk.inner(area)
  
  if contentArea.isEmpty:
    return
  
  # Update viewport to keep cursor visible
  state.updateViewport(contentArea)
  
  # Render hex grid
  # We iterate through screen positions and convert to hex coords
  for screenY in 0 ..< contentArea.height:
    let absY = contentArea.y + screenY
    
    # Calculate hex row (r coordinate)
    let r = state.viewportOrigin.r + screenY
    
    # Determine x offset for this row (odd r values offset right)
    let rowOffset = if (r and 1) != 0: 1 else: 0
    
    var screenX = rowOffset
    while screenX < contentArea.width:
      let absX = contentArea.x + screenX
      
      # Convert screen position to hex coordinate
      let q = state.viewportOrigin.q + (screenX - rowOffset) div HexWidth
      let coord = hexCoord(q, r)
      
      # Get symbol and style for this hex
      let sym = m.getHexSymbol(coord)
      let symStr = sym.symbol(m.ascii)
      let style = m.getHexStyle(coord, state)
      
      # Check if this hex is selected or under cursor
      let isSelected = state.selected.isSome and state.selected.get() == coord
      let isCursor = coord == state.cursor
      
      if isSelected or isCursor:
        # Render with selection brackets: [X]
        if absX > contentArea.x:
          discard buf.put(absX - 1, absY, SelectLeft, style)
        discard buf.put(absX, absY, symStr, style)
        if absX + 1 < contentArea.right:
          discard buf.put(absX + 1, absY, SelectRight, style)
      else:
        # Render just the symbol
        discard buf.put(absX, absY, symStr, style)
      
      screenX += HexWidth

# -----------------------------------------------------------------------------
# Query helpers
# -----------------------------------------------------------------------------

proc systemAt*(m: HexMap, coord: HexCoord): Option[SystemInfo] =
  ## Get system info at a hex coordinate (if any)
  if m.data.systems.hasKey(coord):
    some(m.data.systems[coord])
  else:
    none(SystemInfo)

proc cursorSystem*(m: HexMap, state: HexMapState): Option[SystemInfo] =
  ## Get system info at cursor position
  m.systemAt(state.cursor)

proc selectedSystem*(m: HexMap, state: HexMapState): Option[SystemInfo] =
  ## Get system info at selected position
  if state.selected.isSome:
    m.systemAt(state.selected.get())
  else:
    none(SystemInfo)
