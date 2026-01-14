## Axial coordinate math for hex grid rendering
##
## Handles conversion between axial hex coordinates and screen character
## positions. Uses flat-top hex orientation matching EC4X game spec.
##
## Coordinate system:
##   - Axial coordinates (q, r) with hub at (0, 0)
##   - Flat-top hexes: q increases east, r increases southeast
##   - Screen positions use standard (x, y) with origin top-left

type
  HexCoord* = object
    ## Axial hex coordinate
    q*: int
    r*: int

  ScreenPos* = object
    ## Character grid position (0-indexed from top-left)
    x*: int
    y*: int

const
  ## Hex dimensions in character cells
  ## Each hex is 2 chars wide, 1 char tall in minimal ASCII view
  HexWidth* = 2
  HexHeight* = 1

# -----------------------------------------------------------------------------
# Coordinate constructors
# -----------------------------------------------------------------------------

proc hexCoord*(q, r: int): HexCoord {.inline.} =
  ## Create hex coordinate from q, r values
  HexCoord(q: q, r: r)

proc screenPos*(x, y: int): ScreenPos {.inline.} =
  ## Create screen position from x, y values
  ScreenPos(x: x, y: y)

# -----------------------------------------------------------------------------
# Axial coordinate math
# -----------------------------------------------------------------------------

proc `+`*(a, b: HexCoord): HexCoord {.inline.} =
  hexCoord(a.q + b.q, a.r + b.r)

proc `-`*(a, b: HexCoord): HexCoord {.inline.} =
  hexCoord(a.q - b.q, a.r - b.r)

proc `==`*(a, b: HexCoord): bool {.inline.} =
  a.q == b.q and a.r == b.r

proc s*(h: HexCoord): int {.inline.} =
  ## Third cubic coordinate (q + r + s = 0)
  -h.q - h.r

proc distance*(a, b: HexCoord): int =
  ## Hex distance using axial coordinates
  ## Formula: (|dq| + |dq + dr| + |dr|) / 2
  let dq = a.q - b.q
  let dr = a.r - b.r
  (abs(dq) + abs(dq + dr) + abs(dr)) div 2

proc ring*(h: HexCoord): int =
  ## Get ring number (distance from origin)
  distance(hexCoord(0, 0), h)

# -----------------------------------------------------------------------------
# Neighbor directions (flat-top orientation)
# -----------------------------------------------------------------------------

const
  ## Six neighbor directions for flat-top hexes
  ## Ordered: E, SE, SW, W, NW, NE
  HexDirections*: array[6, HexCoord] = [
    hexCoord(1, 0),   # East
    hexCoord(0, 1),   # Southeast
    hexCoord(-1, 1),  # Southwest
    hexCoord(-1, 0),  # West
    hexCoord(0, -1),  # Northwest
    hexCoord(1, -1),  # Northeast
  ]

type
  HexDirection* {.pure.} = enum
    East = 0
    Southeast = 1
    Southwest = 2
    West = 3
    Northwest = 4
    Northeast = 5

proc neighbor*(h: HexCoord, dir: HexDirection): HexCoord {.inline.} =
  ## Get neighbor in given direction
  h + HexDirections[ord(dir)]

proc neighbors*(h: HexCoord): array[6, HexCoord] =
  ## Get all six neighbors
  for i, dir in HexDirections:
    result[i] = h + dir

# -----------------------------------------------------------------------------
# Screen coordinate conversion
# -----------------------------------------------------------------------------

proc axialToScreen*(hex: HexCoord, origin: HexCoord = hexCoord(0, 0)): ScreenPos =
  ## Convert axial hex coordinate to screen character position
  ##
  ## Flat-top hex layout in ASCII:
  ##   Row 0:  · · · · ·      (r even: no offset)
  ##   Row 1:   · · · · ·     (r odd: offset by 1)
  ##
  ## Each hex is 2 chars wide, rows are 1 char tall.
  ## The offset pattern creates the hex stagger effect.
  let rel = hex - origin
  
  # Base x position: q * 2 (each hex is 2 chars wide)
  # Add r offset for stagger (r adds 1 char offset per row)
  let x = rel.q * HexWidth + rel.r
  
  # y position is simply r (one row per r increment)
  let y = rel.r
  
  screenPos(x, y)

proc screenToAxial*(pos: ScreenPos, origin: HexCoord = hexCoord(0, 0)): HexCoord =
  ## Convert screen position back to axial coordinate (approximate)
  ##
  ## Note: This gives the hex containing or nearest to the screen position.
  ## Due to the discrete nature of character grids, some precision is lost.
  
  # y directly maps to r
  let r = pos.y
  
  # x = q * 2 + r, so q = (x - r) / 2
  # Use integer division, rounding toward nearest hex
  let q = (pos.x - r + 1) div HexWidth
  
  hexCoord(q + origin.q, r + origin.r)

# -----------------------------------------------------------------------------
# Viewport calculations
# -----------------------------------------------------------------------------

proc hexesInRect*(
  topLeft: ScreenPos,
  width, height: int,
  origin: HexCoord
): seq[HexCoord] =
  ## Get all hex coordinates visible in a screen rectangle
  ##
  ## Returns hexes that would render within the given screen bounds.
  result = @[]
  
  for y in 0 ..< height:
    # Calculate the range of x positions for this row
    # Account for odd-row offset
    let rowOffset = if (y + origin.r) mod 2 != 0: 1 else: 0
    
    for x in countup(rowOffset, width - 1, HexWidth):
      let hex = screenToAxial(screenPos(topLeft.x + x, topLeft.y + y), origin)
      result.add(hex)

proc viewportForHex*(
  hex: HexCoord,
  viewWidth, viewHeight: int,
  currentOrigin: HexCoord,
  margin: int = 2
): HexCoord =
  ## Calculate viewport origin to keep hex visible with margin
  ##
  ## Returns new origin if hex is outside margin, else current origin.
  let pos = axialToScreen(hex, currentOrigin)
  
  var newOrigin = currentOrigin
  
  # Check if hex is too close to edges
  if pos.x < margin:
    # Shift viewport left (decrease origin q)
    newOrigin.q -= (margin - pos.x + HexWidth - 1) div HexWidth
  elif pos.x >= viewWidth - margin:
    # Shift viewport right (increase origin q)
    newOrigin.q += (pos.x - viewWidth + margin + HexWidth) div HexWidth
  
  if pos.y < margin:
    # Shift viewport up (decrease origin r)
    newOrigin.r -= margin - pos.y
  elif pos.y >= viewHeight - margin:
    # Shift viewport down (increase origin r)
    newOrigin.r += pos.y - viewHeight + margin + 1
  
  newOrigin

# -----------------------------------------------------------------------------
# Ring iteration
# -----------------------------------------------------------------------------

iterator hexesInRing*(center: HexCoord, radius: int): HexCoord =
  ## Iterate over all hexes in a ring at given radius from center
  if radius == 0:
    yield center
  else:
    # Start at "top" of ring and walk around
    var hex = center + hexCoord(0, -radius)  # Start north
    
    for dir in HexDirection:
      for _ in 0 ..< radius:
        yield hex
        hex = hex.neighbor(dir)

iterator hexesInSpiral*(center: HexCoord, maxRadius: int): HexCoord =
  ## Iterate over all hexes from center outward in spiral pattern
  for r in 0 .. maxRadius:
    for hex in hexesInRing(center, r):
      yield hex
