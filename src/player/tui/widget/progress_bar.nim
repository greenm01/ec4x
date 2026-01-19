## Progress Bar - Construction queue progress display
##
## Renders a horizontal progress bar using block characters.
## Uses Tokyo Night palette colors for filled/empty segments.
##
## Example output:
##   Building: Destroyer   ▓▓▓▓▓░░░░░  50%  (2 turns)
##
## Reference: ec-style-layout.md Section 3 "Visual Language"

import ../buffer
import ../layout/rect
import ../styles/ec_palette

type
  ProgressBar* = object
    ## Progress bar widget configuration.
    current*: int           ## Current value (e.g., turns completed)
    total*: int             ## Total value (e.g., total build time)
    width*: int             ## Bar width in characters (not including label)
    label*: string          ## Optional left label
    showPercent*: bool      ## Show percentage after bar
    showRemaining*: bool    ## Show "(X turns)" remaining
    filledStyle*: CellStyle ## Style for filled segments
    emptyStyle*: CellStyle  ## Style for empty segments
    labelStyle*: CellStyle  ## Style for label text
    percentStyle*: CellStyle ## Style for percentage text

# -----------------------------------------------------------------------------
# Constructors
# -----------------------------------------------------------------------------

proc progressBar*(current, total: int, width: int = 10): ProgressBar =
  ## Create a progress bar with default Tokyo Night styling.
  ProgressBar(
    current: current,
    total: total,
    width: width,
    label: "",
    showPercent: true,
    showRemaining: false,
    filledStyle: CellStyle(
      fg: color(PositiveColor),
      bg: color(CanvasBgColor),
      attrs: {}
    ),
    emptyStyle: CellStyle(
      fg: color(CanvasDimColor),
      bg: color(CanvasBgColor),
      attrs: {}
    ),
    labelStyle: canvasStyle(),
    percentStyle: canvasDimStyle()
  )

# -----------------------------------------------------------------------------
# Builder methods
# -----------------------------------------------------------------------------

proc label*(pb: ProgressBar, text: string): ProgressBar =
  ## Set the label displayed before the bar.
  result = pb
  result.label = text

proc showPercent*(pb: ProgressBar, show: bool): ProgressBar =
  ## Toggle percentage display after bar.
  result = pb
  result.showPercent = show

proc showRemaining*(pb: ProgressBar, show: bool): ProgressBar =
  ## Toggle "(X turns)" remaining display.
  result = pb
  result.showRemaining = show

proc filledStyle*(pb: ProgressBar, style: CellStyle): ProgressBar =
  ## Set style for filled bar segments.
  result = pb
  result.filledStyle = style

proc emptyStyle*(pb: ProgressBar, style: CellStyle): ProgressBar =
  ## Set style for empty bar segments.
  result = pb
  result.emptyStyle = style

proc labelStyle*(pb: ProgressBar, style: CellStyle): ProgressBar =
  ## Set style for label text.
  result = pb
  result.labelStyle = style

proc width*(pb: ProgressBar, w: int): ProgressBar =
  ## Set bar width in characters.
  result = pb
  result.width = w

# -----------------------------------------------------------------------------
# Calculations
# -----------------------------------------------------------------------------

proc percentage*(pb: ProgressBar): int =
  ## Calculate percentage complete (0-100).
  if pb.total <= 0:
    return 100
  result = (pb.current * 100) div pb.total
  result = clamp(result, 0, 100)

proc filledCount*(pb: ProgressBar): int =
  ## Calculate number of filled segments.
  if pb.total <= 0:
    return pb.width
  result = (pb.current * pb.width) div pb.total
  result = clamp(result, 0, pb.width)

proc remaining*(pb: ProgressBar): int =
  ## Calculate remaining units (e.g., turns).
  max(0, pb.total - pb.current)

# -----------------------------------------------------------------------------
# String rendering (for simple use cases)
# -----------------------------------------------------------------------------

proc renderToString*(pb: ProgressBar): string =
  ## Render progress bar to a string (no styling).
  ## Useful for testing or simple display.
  let filled = pb.filledCount()
  let empty = pb.width - filled
  
  result = ""
  
  # Label
  if pb.label.len > 0:
    result.add(pb.label)
    result.add(" ")
  
  # Bar
  for i in 0 ..< filled:
    result.add(GlyphProgressFull)
  for i in 0 ..< empty:
    result.add(GlyphProgressEmpty)
  
  # Percentage
  if pb.showPercent:
    result.add(" ")
    let pct = pb.percentage()
    if pct < 10:
      result.add("  ")
    elif pct < 100:
      result.add(" ")
    result.add($pct)
    result.add("%")
  
  # Remaining
  if pb.showRemaining:
    let rem = pb.remaining()
    result.add(" (")
    result.add($rem)
    if rem == 1:
      result.add(" turn)")
    else:
      result.add(" turns)")

# -----------------------------------------------------------------------------
# Buffer rendering
# -----------------------------------------------------------------------------

proc render*(pb: ProgressBar, area: Rect, buf: var CellBuffer) =
  ## Render progress bar to buffer at given area.
  ## Renders on a single line, starting at area.x, area.y.
  if area.isEmpty or area.height < 1:
    return
  
  var x = area.x
  let y = area.y
  let maxX = area.right
  
  # Render label
  if pb.label.len > 0:
    let written = buf.setString(x, y, pb.label, pb.labelStyle)
    x += written
    if x < maxX:
      discard buf.setString(x, y, " ", pb.labelStyle)
      x += 1
  
  # Calculate bar dimensions
  let availableWidth = min(pb.width, maxX - x - 6)  # Leave room for " 100%"
  if availableWidth <= 0:
    return
  
  let filledCount = if pb.total <= 0:
    availableWidth
  else:
    clamp((pb.current * availableWidth) div pb.total, 0, availableWidth)
  let emptyCount = availableWidth - filledCount
  
  # Render filled segments
  for i in 0 ..< filledCount:
    if x >= maxX:
      break
    discard buf.setString(x, y, GlyphProgressFull, pb.filledStyle)
    x += 1
  
  # Render empty segments
  for i in 0 ..< emptyCount:
    if x >= maxX:
      break
    discard buf.setString(x, y, GlyphProgressEmpty, pb.emptyStyle)
    x += 1
  
  # Render percentage
  if pb.showPercent and x + 5 <= maxX:
    discard buf.setString(x, y, " ", pb.percentStyle)
    x += 1
    let pct = pb.percentage()
    let pctStr = if pct < 10:
      "  " & $pct & "%"
    elif pct < 100:
      " " & $pct & "%"
    else:
      $pct & "%"
    discard buf.setString(x, y, pctStr, pb.percentStyle)
    x += pctStr.len
  
  # Render remaining turns
  if pb.showRemaining and x + 10 <= maxX:
    let rem = pb.remaining()
    let remStr = if rem == 1:
      " (1 turn)"
    else:
      " (" & $rem & " turns)"
    discard buf.setString(x, y, remStr, pb.percentStyle)

# -----------------------------------------------------------------------------
# Convenience constructors for common use cases
# -----------------------------------------------------------------------------

proc constructionProgress*(
  itemName: string,
  turnsComplete: int,
  totalTurns: int,
  barWidth: int = 10
): ProgressBar =
  ## Create a construction queue progress bar.
  ## Example: "Destroyer ▓▓▓▓▓░░░░░ 50% (2 turns)"
  progressBar(turnsComplete, totalTurns, barWidth)
    .label(itemName)
    .showPercent(true)
    .showRemaining(true)

proc healthBar*(
  currentHp: int,
  maxHp: int,
  barWidth: int = 10
): ProgressBar =
  ## Create a health/damage bar with red for low health.
  let pct = if maxHp <= 0: 100 else: (currentHp * 100) div maxHp
  var pb = progressBar(currentHp, maxHp, barWidth)
    .showPercent(true)
    .showRemaining(false)
  
  # Color based on health level
  if pct < 25:
    pb.filledStyle = CellStyle(
      fg: color(AlertColor),
      bg: color(CanvasBgColor),
      attrs: {}
    )
  elif pct < 50:
    pb.filledStyle = CellStyle(
      fg: color(PrestigeColor),  # Yellow/amber for caution
      bg: color(CanvasBgColor),
      attrs: {}
    )
  
  pb
