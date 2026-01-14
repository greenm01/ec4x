## Layout - Constraint-based layout solver
##
## Splits a rectangular area into segments based on constraints.
## Inspired by ratatui's layout system with a simpler implementation.
##
## USAGE:
## ------
##   let areas = Layout.horizontal()
##     .constraints(@[length(10), fill(), length(20)])
##     .split(terminalRect)
##   # areas[0] = 10 cols wide (left)
##   # areas[1] = remaining space (middle)
##   # areas[2] = 20 cols wide (right)
##
## ALGORITHM:
## ----------
## 1. Calculate fixed sizes (Length, Percentage)
## 2. Enforce Min/Max constraints
## 3. Distribute remaining space to Fill constraints by weight
## 4. Handle overflow by shrinking flexible segments
##
## FUTURE CASSOWARY INTEGRATION:
## -----------------------------
## The Layout type is designed to be solver-agnostic. To migrate:
##
## 1. Create a LayoutSolver trait/concept:
##    type LayoutSolver = concept s
##      s.solve(constraints: seq[Constraint], available: int): seq[int]
##
## 2. Current implementation becomes SimpleLayoutSolver
##
## 3. Add CassowaryLayoutSolver using amoeba:
##    - Create am_Solver instance
##    - For each constraint, add corresponding am_Constraint
##    - Add sum constraint: sum(sizes) == available
##    - Call am_solve() and read results
##
## 4. Layout.split() delegates to configured solver
##
## The amoeba library (https://github.com/starwing/amoeba) provides:
##   am_newsolver()    - Create solver
##   am_newvariable()  - Create variable bound to float*
##   am_newconstraint() - Create constraint with strength
##   am_addterm()      - Add term to constraint
##   am_setrelation()  - Set ==, >=, <=
##   am_add()          - Add constraint to solver
##   am_suggest()      - Suggest value (for edit variables)
##   am_updatevars()   - Solve and update bound variables
##
## For now, the simple solver handles all common TUI layouts.

import ./rect
import ./constraint

type
  Flex* {.pure.} = enum
    ## How to distribute extra space when constraints don't fill area.
    Start       ## Pack segments at start, extra space at end
    End         ## Pack segments at end, extra space at start
    Center      ## Center segments, split extra space
    SpaceBetween  ## Distribute extra space between segments
    SpaceAround   ## Distribute extra space around segments

  Layout* = object
    ## Layout configuration for splitting an area.
    direction: Direction
    constraints: seq[Constraint]
    margin: Margin
    spacing: int
    flex: Flex

# -----------------------------------------------------------------------------
# Builder API
# -----------------------------------------------------------------------------

proc horizontal*(): Layout =
  ## Create a horizontal layout (splits left-to-right).
  Layout(
    direction: Direction.Horizontal,
    constraints: @[],
    margin: NoMargin,
    spacing: 0,
    flex: Flex.Start
  )

proc vertical*(): Layout =
  ## Create a vertical layout (splits top-to-bottom).
  Layout(
    direction: Direction.Vertical,
    constraints: @[],
    margin: NoMargin,
    spacing: 0,
    flex: Flex.Start
  )

proc constraints*(l: Layout, cs: seq[Constraint]): Layout =
  ## Set the constraints for this layout.
  result = l
  result.constraints = cs

proc constraints*(l: Layout, cs: varargs[Constraint]): Layout =
  ## Set the constraints for this layout (varargs version).
  result = l
  result.constraints = @cs

proc margin*(l: Layout, m: Margin): Layout =
  ## Set margin around the entire layout area.
  result = l
  result.margin = m

proc margin*(l: Layout, all: int): Layout =
  ## Set equal margin on all sides.
  result = l
  result.margin = margin(all)

proc spacing*(l: Layout, s: int): Layout =
  ## Set spacing between segments.
  result = l
  result.spacing = max(0, s)

proc flex*(l: Layout, f: Flex): Layout =
  ## Set flex mode for distributing extra space.
  result = l
  result.flex = f

proc direction*(l: Layout, d: Direction): Layout =
  ## Change direction (rarely needed, use horizontal/vertical instead).
  result = l
  result.direction = d

# -----------------------------------------------------------------------------
# Layout solver
# -----------------------------------------------------------------------------

proc solveConstraints(constraints: seq[Constraint], available: int): seq[int] =
  ## Solve constraints to produce segment sizes.
  ## Returns a seq of sizes, one per constraint.
  ##
  ## Algorithm:
  ## 1. First pass: calculate base sizes
  ## 2. Enforce Min constraints
  ## 3. Distribute remaining space to Fill segments
  ## 4. Enforce Max constraints
  ## 5. Handle overflow by shrinking flexible segments
  
  let n = constraints.len
  if n == 0:
    return @[]
  
  result = newSeq[int](n)
  
  # Track which segments can grow/shrink
  var
    fillIndices: seq[int] = @[]
    totalFillWeight = 0
    totalFixed = 0
  
  # First pass: calculate base sizes and identify Fill segments
  for i, c in constraints:
    case c.kind
    of ConstraintKind.Length:
      result[i] = c.length
      totalFixed += c.length
    of ConstraintKind.Min:
      result[i] = c.minVal
      totalFixed += c.minVal
      fillIndices.add(i)  # Min can grow
      totalFillWeight += 1
    of ConstraintKind.Max:
      result[i] = 0  # Start at 0, prefer to be small
      # Max is not added to fillIndices - Fill gets priority
    of ConstraintKind.Percentage:
      result[i] = available * c.percent div 100
      totalFixed += result[i]
    of ConstraintKind.Ratio:
      result[i] = available * c.numerator div c.denominator
      totalFixed += result[i]
    of ConstraintKind.Fill:
      result[i] = 0  # Will be assigned remaining space
      fillIndices.add(i)
      totalFillWeight += c.weight
  
  # Calculate remaining space for Fill segments
  var remaining = available - totalFixed
  
  if remaining > 0 and fillIndices.len > 0:
    # Distribute remaining space to Fill segments by weight
    var distributed = 0
    for idx in fillIndices:
      let c = constraints[idx]
      let weight = case c.kind
        of ConstraintKind.Fill: c.weight
        of ConstraintKind.Min: 1
        else: 0
      
      if weight > 0 and totalFillWeight > 0:
        let share = remaining * weight div totalFillWeight
        result[idx] += share
        distributed += share
    
    # Give any rounding remainder to the last Fill segment
    let leftover = remaining - distributed
    if leftover > 0 and fillIndices.len > 0:
      result[fillIndices[^1]] += leftover
  
  # Handle Max constraints - give them leftover space up to their max
  # (after Fill has taken its share)
  remaining = available - totalFixed
  var totalAllocated = 0
  for size in result:
    totalAllocated += size
  remaining = available - totalAllocated
  
  if remaining > 0:
    for i, c in constraints:
      if c.kind == ConstraintKind.Max:
        let canTake = min(remaining, c.maxVal)
        result[i] = canTake
        remaining -= canTake
  
  # Handle overflow (total > available)
  var total = 0
  for size in result:
    total += size
  
  if total > available:
    # Need to shrink - take from Fill segments first
    var excess = total - available
    
    # Find shrinkable segments (Fill and non-Min)
    var shrinkable: seq[int] = @[]
    var shrinkableTotal = 0
    for i, c in constraints:
      if c.kind == ConstraintKind.Fill:
        shrinkable.add(i)
        shrinkableTotal += result[i]
      elif c.kind != ConstraintKind.Min and c.kind != ConstraintKind.Length:
        shrinkable.add(i)
        shrinkableTotal += result[i]
    
    # Shrink proportionally
    if shrinkable.len > 0 and shrinkableTotal > 0:
      for idx in shrinkable:
        if excess <= 0:
          break
        let proportion = result[idx] * excess div shrinkableTotal
        let reduction = min(proportion, result[idx])
        result[idx] -= reduction
        excess -= reduction
    
    # If still over, shrink everything except Min constraints
    if excess > 0:
      for i in countdown(n - 1, 0):
        if excess <= 0:
          break
        if constraints[i].kind != ConstraintKind.Min:
          let reduction = min(excess, result[i])
          result[i] -= reduction
          excess -= reduction
  
  # Ensure no negative sizes
  for i in 0 ..< n:
    result[i] = max(0, result[i])

proc split*(l: Layout, area: Rect): seq[Rect] =
  ## Split the area according to layout constraints.
  ## Returns a Rect for each constraint.
  
  let n = l.constraints.len
  if n == 0:
    return @[]
  
  # Apply margin to get inner area
  let inner = rect(
    area.x + l.margin.left,
    area.y + l.margin.top,
    area.width - l.margin.horizontal,
    area.height - l.margin.vertical
  )
  
  if inner.isEmpty:
    # No space after margin
    return newSeq[Rect](n)
  
  # Calculate total spacing
  let totalSpacing = if n > 1: l.spacing * (n - 1) else: 0
  
  # Available space for segments (minus spacing)
  let available = case l.direction
    of Direction.Horizontal: inner.width - totalSpacing
    of Direction.Vertical: inner.height - totalSpacing
  
  # Solve constraints
  let sizes = solveConstraints(l.constraints, max(0, available))
  
  # Build result rects
  result = newSeq[Rect](n)
  
  # Calculate total size for flex positioning
  var totalSize = 0
  for size in sizes:
    totalSize += size
  totalSize += totalSpacing
  
  # Calculate starting offset based on flex mode
  let extraSpace = case l.direction
    of Direction.Horizontal: inner.width - totalSize
    of Direction.Vertical: inner.height - totalSize
  
  var offset = case l.flex
    of Flex.Start: 0
    of Flex.End: max(0, extraSpace)
    of Flex.Center: max(0, extraSpace div 2)
    of Flex.SpaceBetween, Flex.SpaceAround: 0  # Handled in loop
  
  # Calculate per-gap extra space for SpaceBetween/SpaceAround
  let (gapExtra, startExtra) = case l.flex
    of Flex.SpaceBetween:
      if n > 1: (max(0, extraSpace) div (n - 1), 0)
      else: (0, max(0, extraSpace) div 2)
    of Flex.SpaceAround:
      let gap = if n > 0: max(0, extraSpace) div (n * 2) else: 0
      (gap * 2, gap)
    else: (0, 0)
  
  offset += startExtra
  
  # Generate rects
  for i in 0 ..< n:
    case l.direction
    of Direction.Horizontal:
      result[i] = rect(inner.x + offset, inner.y, sizes[i], inner.height)
      offset += sizes[i] + l.spacing + gapExtra
    of Direction.Vertical:
      result[i] = rect(inner.x, inner.y + offset, inner.width, sizes[i])
      offset += sizes[i] + l.spacing + gapExtra

# -----------------------------------------------------------------------------
# Convenience functions
# -----------------------------------------------------------------------------

proc hsplit*(area: Rect, constraints: openArray[Constraint]): seq[Rect] =
  ## Quick horizontal split without full Layout builder.
  horizontal().constraints(constraints).split(area)

proc vsplit*(area: Rect, constraints: openArray[Constraint]): seq[Rect] =
  ## Quick vertical split without full Layout builder.
  vertical().constraints(constraints).split(area)

proc hsplit*(area: Rect, n: int): seq[Rect] =
  ## Split horizontally into n equal parts.
  var cs = newSeq[Constraint](n)
  for i in 0 ..< n:
    cs[i] = fill()
  horizontal().constraints(cs).split(area)

proc vsplit*(area: Rect, n: int): seq[Rect] =
  ## Split vertically into n equal parts.
  var cs = newSeq[Constraint](n)
  for i in 0 ..< n:
    cs[i] = fill()
  vertical().constraints(cs).split(area)

# -----------------------------------------------------------------------------
# String representation
# -----------------------------------------------------------------------------

proc `$`*(l: Layout): string =
  result = "Layout("
  result.add($l.direction)
  result.add(", [")
  for i, c in l.constraints:
    if i > 0: result.add(", ")
    result.add($c)
  result.add("])")
