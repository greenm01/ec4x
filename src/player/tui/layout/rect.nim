## Rect - Rectangle type for layout calculations
##
## Represents a rectangular area in terminal coordinates (0-indexed).
## Used by the layout system to define regions for widgets.
##
## FUTURE CASSOWARY INTEGRATION:
## -----------------------------
## When migrating to amoeba/Cassowary, Rect fields would become
## constraint variables rather than fixed integers:
##
##   type Rect = object
##     x, y, width, height: ConstraintVar  # Instead of int
##
## The API (intersect, union, split, etc.) would remain the same,
## but return Rects with constraint relationships rather than
## computed values. The solver would resolve actual positions.
##
## For now, we use simple integer arithmetic which covers most
## TUI layout needs without the complexity of a constraint solver.

type
  Rect* = object
    x*, y*: int           ## Top-left corner (0-indexed)
    width*, height*: int  ## Dimensions (can be 0)

  Direction* {.pure.} = enum
    Horizontal  ## Split left-to-right
    Vertical    ## Split top-to-bottom

# -----------------------------------------------------------------------------
# Constructors
# -----------------------------------------------------------------------------

proc rect*(x, y, width, height: int): Rect =
  ## Create a Rect with explicit bounds.
  ## Negative dimensions are clamped to 0.
  Rect(
    x: x,
    y: y,
    width: max(0, width),
    height: max(0, height)
  )

proc rect*(width, height: int): Rect =
  ## Create a Rect at origin (0, 0) with given dimensions.
  rect(0, 0, width, height)

const EmptyRect* = Rect(x: 0, y: 0, width: 0, height: 0)

# -----------------------------------------------------------------------------
# Properties
# -----------------------------------------------------------------------------

proc right*(r: Rect): int {.inline.} =
  ## X coordinate of right edge (exclusive).
  r.x + r.width

proc bottom*(r: Rect): int {.inline.} =
  ## Y coordinate of bottom edge (exclusive).
  r.y + r.height

proc area*(r: Rect): int {.inline.} =
  ## Total area in cells.
  r.width * r.height

proc isEmpty*(r: Rect): bool {.inline.} =
  ## True if rect has zero area.
  r.width <= 0 or r.height <= 0

proc isValid*(r: Rect): bool {.inline.} =
  ## True if rect has positive dimensions.
  r.width > 0 and r.height > 0

# -----------------------------------------------------------------------------
# Position checks
# -----------------------------------------------------------------------------

proc contains*(r: Rect, x, y: int): bool {.inline.} =
  ## Check if point (x, y) is inside the rect.
  x >= r.x and x < r.right and y >= r.y and y < r.bottom

proc contains*(outer, inner: Rect): bool =
  ## Check if inner rect is completely inside outer rect.
  inner.x >= outer.x and
  inner.y >= outer.y and
  inner.right <= outer.right and
  inner.bottom <= outer.bottom

proc intersects*(a, b: Rect): bool =
  ## Check if two rects overlap.
  not (a.right <= b.x or b.right <= a.x or
       a.bottom <= b.y or b.bottom <= a.y)

# -----------------------------------------------------------------------------
# Transformations
# -----------------------------------------------------------------------------

proc offset*(r: Rect, dx, dy: int): Rect =
  ## Move rect by (dx, dy).
  rect(r.x + dx, r.y + dy, r.width, r.height)

proc moveTo*(r: Rect, x, y: int): Rect =
  ## Move rect to position (x, y).
  rect(x, y, r.width, r.height)

proc resize*(r: Rect, width, height: int): Rect =
  ## Change dimensions, keeping position.
  rect(r.x, r.y, width, height)

proc inflate*(r: Rect, dx, dy: int): Rect =
  ## Grow rect by dx on each side horizontally, dy vertically.
  ## Can shrink if dx/dy are negative.
  rect(r.x - dx, r.y - dy, r.width + 2*dx, r.height + 2*dy)

proc shrink*(r: Rect, amount: int): Rect =
  ## Shrink rect by amount on all sides (for margins/padding).
  r.inflate(-amount, -amount)

proc shrink*(r: Rect, horizontal, vertical: int): Rect =
  ## Shrink rect by different amounts horizontally and vertically.
  r.inflate(-horizontal, -vertical)

proc shrink*(r: Rect, left, top, right, bottom: int): Rect =
  ## Shrink rect by specific amounts on each side.
  rect(
    r.x + left,
    r.y + top,
    r.width - left - right,
    r.height - top - bottom
  )

# -----------------------------------------------------------------------------
# Set operations
# -----------------------------------------------------------------------------

proc intersection*(a, b: Rect): Rect =
  ## Return the overlapping region of two rects.
  ## Returns EmptyRect if no overlap.
  let
    x1 = max(a.x, b.x)
    y1 = max(a.y, b.y)
    x2 = min(a.right, b.right)
    y2 = min(a.bottom, b.bottom)
  if x2 > x1 and y2 > y1:
    rect(x1, y1, x2 - x1, y2 - y1)
  else:
    EmptyRect

proc union*(a, b: Rect): Rect =
  ## Return the smallest rect containing both rects.
  if a.isEmpty: return b
  if b.isEmpty: return a
  let
    x1 = min(a.x, b.x)
    y1 = min(a.y, b.y)
    x2 = max(a.right, b.right)
    y2 = max(a.bottom, b.bottom)
  rect(x1, y1, x2 - x1, y2 - y1)

# -----------------------------------------------------------------------------
# Splitting
# -----------------------------------------------------------------------------

proc splitHorizontal*(r: Rect, at: int): tuple[left, right: Rect] =
  ## Split rect vertically at x=at (relative to rect origin).
  ## Returns (left portion, right portion).
  let splitX = clamp(at, 0, r.width)
  result.left = rect(r.x, r.y, splitX, r.height)
  result.right = rect(r.x + splitX, r.y, r.width - splitX, r.height)

proc splitVertical*(r: Rect, at: int): tuple[top, bottom: Rect] =
  ## Split rect horizontally at y=at (relative to rect origin).
  ## Returns (top portion, bottom portion).
  let splitY = clamp(at, 0, r.height)
  result.top = rect(r.x, r.y, r.width, splitY)
  result.bottom = rect(r.x, r.y + splitY, r.width, r.height - splitY)

proc split*(r: Rect, dir: Direction, at: int): tuple[first, second: Rect] =
  ## Split rect in given direction at offset.
  case dir
  of Direction.Horizontal:
    let (left, right) = r.splitHorizontal(at)
    (left, right)
  of Direction.Vertical:
    let (top, bottom) = r.splitVertical(at)
    (top, bottom)

# -----------------------------------------------------------------------------
# Inner regions (for borders/padding)
# -----------------------------------------------------------------------------

proc inner*(r: Rect, border: int = 1): Rect =
  ## Return inner rect after removing border on all sides.
  ## Useful for calculating content area inside a bordered panel.
  r.shrink(border)

proc inner*(r: Rect, horizontal, vertical: int): Rect =
  ## Return inner rect with asymmetric borders.
  r.shrink(horizontal, vertical)

# -----------------------------------------------------------------------------
# Clipping
# -----------------------------------------------------------------------------

proc clampTo*(r, bounds: Rect): Rect =
  ## Clamp rect to fit within bounds.
  ## Adjusts position and size to fit.
  result = r
  # Clamp position
  if result.x < bounds.x:
    result.width -= bounds.x - result.x
    result.x = bounds.x
  if result.y < bounds.y:
    result.height -= bounds.y - result.y
    result.y = bounds.y
  # Clamp size
  if result.right > bounds.right:
    result.width = bounds.right - result.x
  if result.bottom > bounds.bottom:
    result.height = bounds.bottom - result.y
  # Ensure non-negative
  result.width = max(0, result.width)
  result.height = max(0, result.height)

# -----------------------------------------------------------------------------
# Iteration helpers
# -----------------------------------------------------------------------------

iterator positions*(r: Rect): tuple[x, y: int] =
  ## Iterate over all (x, y) positions in the rect, row by row.
  for y in r.y ..< r.bottom:
    for x in r.x ..< r.right:
      yield (x, y)

iterator rows*(r: Rect): tuple[y: int, startX, endX: int] =
  ## Iterate over rows, yielding y and x range.
  for y in r.y ..< r.bottom:
    yield (y, r.x, r.right)

iterator columns*(r: Rect): tuple[x: int, startY, endY: int] =
  ## Iterate over columns, yielding x and y range.
  for x in r.x ..< r.right:
    yield (x, r.y, r.bottom)

# -----------------------------------------------------------------------------
# String representation
# -----------------------------------------------------------------------------

proc `$`*(r: Rect): string =
  "Rect(" & $r.x & ", " & $r.y & ", " & $r.width & "x" & $r.height & ")"

proc `$`*(d: Direction): string =
  case d
  of Direction.Horizontal: "Horizontal"
  of Direction.Vertical: "Vertical"
