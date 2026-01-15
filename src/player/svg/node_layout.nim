## Node layout - hex-to-pixel positioning for SVG starmap
##
## Converts axial hex coordinates to pixel positions for rendering
## systems as nodes in a node-edge graph.

import std/math

type
  Point* = object
    x*, y*: float

proc hexToPixel*(q, r: int, scale: float, cx, cy: float): Point =
  ## Convert axial hex coordinates to pixel coordinates
  ##
  ## Uses flat-top hex orientation:
  ##   x = scale * (3/2 * q)
  ##   y = scale * (sqrt(3)/2 * q + sqrt(3) * r)
  ##
  ## Args:
  ##   q, r: Axial hex coordinates
  ##   scale: Spacing between hex centers (pixels)
  ##   cx, cy: Center point of the SVG (hub location)
  ##
  ## Returns pixel position for the node
  let x = scale * (3.0 / 2.0 * float(q))
  let y = scale * (sqrt(3.0) / 2.0 * float(q) + sqrt(3.0) * float(r))
  Point(x: cx + x, y: cy + y)

proc hexToPixel*(coord: tuple[q, r: int], scale: float,
                 center: Point): Point =
  ## Overload taking tuple coordinate and Point center
  hexToPixel(coord.q, coord.r, scale, center.x, center.y)

proc calculateScale*(maxRing: int, viewportSize: float,
                     padding: float = 50.0): float =
  ## Calculate appropriate scale for the map to fit in viewport
  ##
  ## Args:
  ##   maxRing: Maximum ring number in the map
  ##   viewportSize: Width/height of the SVG viewport
  ##   padding: Padding from edges
  ##
  ## Returns scale value for hexToPixel
  if maxRing <= 0:
    return 60.0  # Default for hub-only maps
  
  # The outermost ring extends approximately maxRing * sqrt(3) * scale
  # from center in any direction. We want this to fit in
  # (viewportSize - 2*padding) / 2
  let availableRadius = (viewportSize - 2.0 * padding) / 2.0
  let maxExtent = float(maxRing) * sqrt(3.0)
  
  # Add some buffer for labels
  let labelBuffer = 1.3
  availableRadius / (maxExtent * labelBuffer)

proc point*(x, y: float): Point =
  ## Create a Point
  Point(x: x, y: y)
