## Constraint - Layout constraint types
##
## Defines how layout segments should be sized. Inspired by ratatui's
## constraint system but simplified for our needs.
##
## CONSTRAINT PRIORITY (highest to lowest):
## 1. Min   - Minimum size must be respected
## 2. Max   - Maximum size must not be exceeded
## 3. Length - Exact size (if space available)
## 4. Percentage - Relative to parent size
## 5. Ratio - Proportional to other Ratio constraints
## 6. Fill  - Takes remaining space (weighted)
##
## FUTURE CASSOWARY INTEGRATION:
## -----------------------------
## These constraints map directly to Cassowary constraint types:
##
##   Length(n)     -> var == n                    (REQUIRED)
##   Min(n)        -> var >= n                    (REQUIRED)
##   Max(n)        -> var <= n                    (REQUIRED)
##   Percentage(p) -> var == parent * p / 100    (STRONG)
##   Ratio(n, d)   -> var == total * n / d       (STRONG)
##   Fill(w)       -> var == remaining * w / sum (MEDIUM)
##
## The amoeba library uses strength levels:
##   AM_REQUIRED (1e9) - Must be satisfied
##   AM_STRONG   (1e6) - Should be satisfied
##   AM_MEDIUM   (1e3) - Nice to have
##   AM_WEAK     (1)   - Fallback
##
## When migrating to Cassowary:
## 1. Create am_Variable for each segment's size
## 2. Add constraints based on ConstraintKind
## 3. Add constraint: sum(segments) == available_space
## 4. Call am_solve() and read variable values
##
## The current simple solver handles most cases. Cassowary would be
## needed for complex inter-segment relationships like:
##   "Panel A width = Panel B width + 10"
##   "Sidebar min 20%, max 40%, but equal to header height"

type
  ConstraintKind* {.pure.} = enum
    Length      ## Exact size in cells
    Min         ## Minimum size (can grow)
    Max         ## Maximum size (can shrink)
    Percentage  ## Percentage of available space
    Ratio       ## Ratio relative to total (e.g., 1:2:1)
    Fill        ## Fill remaining space (weighted)

  Constraint* = object
    ## A single layout constraint.
    ## Use constructor procs (length, min, max, etc.) to create.
    case kind*: ConstraintKind
    of ConstraintKind.Length:
      length*: int
    of ConstraintKind.Min:
      minVal*: int
    of ConstraintKind.Max:
      maxVal*: int
    of ConstraintKind.Percentage:
      percent*: int  ## 0-100
    of ConstraintKind.Ratio:
      numerator*: int
      denominator*: int
    of ConstraintKind.Fill:
      weight*: int  ## Relative weight (default 1)

# -----------------------------------------------------------------------------
# Constructors
# -----------------------------------------------------------------------------

proc length*(size: int): Constraint =
  ## Fixed size constraint.
  ## The segment will be exactly this size if space permits.
  Constraint(kind: ConstraintKind.Length, length: max(0, size))

proc min*(size: int): Constraint =
  ## Minimum size constraint.
  ## The segment will be at least this size, can grow larger.
  Constraint(kind: ConstraintKind.Min, minVal: max(0, size))

proc max*(size: int): Constraint =
  ## Maximum size constraint.
  ## The segment will be at most this size, can be smaller.
  Constraint(kind: ConstraintKind.Max, maxVal: max(0, size))

proc percentage*(pct: int): Constraint =
  ## Percentage of available space.
  ## Values are clamped to 0-100.
  Constraint(kind: ConstraintKind.Percentage, percent: clamp(pct, 0, 100))

proc ratio*(num, denom: int): Constraint =
  ## Ratio constraint for proportional sizing.
  ## Example: ratio(1, 3) means 1/3 of total ratio space.
  ## If you have [ratio(1,3), ratio(2,3)], first gets 1/3, second 2/3.
  Constraint(kind: ConstraintKind.Ratio,
             numerator: max(0, num),
             denominator: max(1, denom))

proc fill*(weight: int = 1): Constraint =
  ## Fill remaining space with optional weight.
  ## Multiple Fill constraints share space proportionally.
  ## Example: [fill(1), fill(2)] - second is twice as wide.
  Constraint(kind: ConstraintKind.Fill, weight: max(1, weight))

# Convenience aliases matching ratatui naming
proc len*(size: int): Constraint = length(size)
proc pct*(percent: int): Constraint = percentage(percent)

# -----------------------------------------------------------------------------
# Constraint properties
# -----------------------------------------------------------------------------

proc isFixed*(c: Constraint): bool =
  ## True if constraint specifies an exact size.
  c.kind == ConstraintKind.Length

proc isFlexible*(c: Constraint): bool =
  ## True if constraint can adapt to available space.
  c.kind in {ConstraintKind.Percentage, ConstraintKind.Ratio,
             ConstraintKind.Fill, ConstraintKind.Min, ConstraintKind.Max}

proc baseSize*(c: Constraint, available: int): int =
  ## Calculate the base/preferred size for this constraint.
  ## Does not account for min/max bounds from other constraints.
  case c.kind
  of ConstraintKind.Length:
    c.length
  of ConstraintKind.Min:
    c.minVal
  of ConstraintKind.Max:
    min(c.maxVal, available)
  of ConstraintKind.Percentage:
    available * c.percent div 100
  of ConstraintKind.Ratio:
    if c.denominator > 0:
      available * c.numerator div c.denominator
    else:
      0
  of ConstraintKind.Fill:
    0  # Fill gets remaining space, starts at 0

# -----------------------------------------------------------------------------
# String representation
# -----------------------------------------------------------------------------

proc `$`*(c: Constraint): string =
  case c.kind
  of ConstraintKind.Length:
    "Length(" & $c.length & ")"
  of ConstraintKind.Min:
    "Min(" & $c.minVal & ")"
  of ConstraintKind.Max:
    "Max(" & $c.maxVal & ")"
  of ConstraintKind.Percentage:
    "Percentage(" & $c.percent & "%)"
  of ConstraintKind.Ratio:
    "Ratio(" & $c.numerator & "/" & $c.denominator & ")"
  of ConstraintKind.Fill:
    if c.weight == 1:
      "Fill"
    else:
      "Fill(" & $c.weight & ")"

# -----------------------------------------------------------------------------
# Margin type for padding/spacing
# -----------------------------------------------------------------------------

type
  Margin* = object
    ## Margin/padding for all four sides.
    left*, top*, right*, bottom*: int

proc margin*(all: int): Margin =
  ## Equal margin on all sides.
  Margin(left: all, top: all, right: all, bottom: all)

proc margin*(horizontal, vertical: int): Margin =
  ## Separate horizontal and vertical margins.
  Margin(left: horizontal, top: vertical,
         right: horizontal, bottom: vertical)

proc margin*(left, top, right, bottom: int): Margin =
  ## Individual margins for each side.
  Margin(left: left, top: top, right: right, bottom: bottom)

const NoMargin* = Margin(left: 0, top: 0, right: 0, bottom: 0)

proc horizontal*(m: Margin): int {.inline.} =
  ## Total horizontal margin (left + right).
  m.left + m.right

proc vertical*(m: Margin): int {.inline.} =
  ## Total vertical margin (top + bottom).
  m.top + m.bottom

proc `$`*(m: Margin): string =
  if m.left == m.top and m.top == m.right and m.right == m.bottom:
    "Margin(" & $m.left & ")"
  elif m.left == m.right and m.top == m.bottom:
    "Margin(" & $m.left & ", " & $m.top & ")"
  else:
    "Margin(" & $m.left & ", " & $m.top & ", " &
                $m.right & ", " & $m.bottom & ")"
