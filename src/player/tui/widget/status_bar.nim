## Zellij-Style Status Bar Widget
##
## A single-line status bar that displays keybinding hints with:
## - Powerline arrow separators
## - Bracketed keys embedded in labels: re[P]orts
## - Adaptive width (full labels → short labels → keys only)
## - Visual highlighting for selected/current item
## - Context-aware: shows view tabs in Overview, context actions elsewhere

import ../buffer
import ../layout/rect
import ../styles/ec_palette
import ../../sam/bindings
import ../../sam/tui_model

export bindings, tui_model

# =============================================================================
# Constants
# =============================================================================

const
  ArrowSeparator* = ""  ## Powerline arrow glyph
  SpaceSeparator* = " "   ## Fallback when no powerline fonts

# =============================================================================
# Style Definitions (must be before rendering procs)
# =============================================================================

# Bar background
const BarBgColor = RgbColor(r: 36, g: 40, b: 59)     ## #24283b (slightly lighter)
const BarFgColor = RgbColor(r: 192, g: 202, b: 245)  ## #c0caf5
const BarKeyColor = RgbColor(r: 125, g: 207, b: 255) ## #7dcfff (cyan)
const BarAltBgColor = RgbColor(r: 42, g: 46, b: 66)  ## Slightly different bg
const BarSelectedBg = RgbColor(r: 122, g: 162, b: 247) ## #7aa2f7 (blue)
const BarSelectedFg = RgbColor(r: 26, g: 27, b: 38)  ## #1a1b26 (dark)
const BarDisabledFg = RgbColor(r: 86, g: 95, b: 137) ## #565f89 (dim)

proc barBgStyle*(): CellStyle =
  CellStyle(fg: color(BarFgColor), bg: color(BarBgColor), attrs: {})

proc barTextStyle*(): CellStyle =
  CellStyle(fg: color(BarFgColor), bg: color(BarBgColor), attrs: {})

proc barKeyStyle*(): CellStyle =
  CellStyle(fg: color(BarKeyColor), bg: color(BarBgColor),
      attrs: {StyleAttr.Bold})

proc barSepStyle*(): CellStyle =
  CellStyle(fg: color(BarBgColor), bg: color(BarBgColor), attrs: {})

proc barAltTextStyle*(): CellStyle =
  CellStyle(fg: color(BarFgColor), bg: color(BarAltBgColor), attrs: {})

proc barAltKeyStyle*(): CellStyle =
  CellStyle(fg: color(BarKeyColor), bg: color(BarAltBgColor),
      attrs: {StyleAttr.Bold})

proc barAltSepStyle*(): CellStyle =
  CellStyle(fg: color(BarAltBgColor), bg: color(BarBgColor), attrs: {})

proc barSelectedTextStyle*(): CellStyle =
  CellStyle(fg: color(BarSelectedFg), bg: color(BarSelectedBg),
      attrs: {StyleAttr.Bold})

proc barSelectedKeyStyle*(): CellStyle =
  CellStyle(fg: color(BarSelectedFg), bg: color(BarSelectedBg),
      attrs: {StyleAttr.Bold})

proc barSelectedSepStyle*(): CellStyle =
  CellStyle(fg: color(BarSelectedBg), bg: color(BarBgColor), attrs: {})

proc barDisabledStyle*(): CellStyle =
  CellStyle(fg: color(BarDisabledFg), bg: color(BarBgColor),
      attrs: {StyleAttr.Italic})

proc barCursorStyle*(): CellStyle =
  CellStyle(fg: color(BarBgColor), bg: color(BarKeyColor), attrs: {})

# =============================================================================
# Status Bar Data
# =============================================================================

type
  StatusBarData* = object
    items*: seq[BarItem]
    maxWidth*: int
    useArrows*: bool        ## Use powerline arrow separators
    expertModeActive*: bool
    expertModeInput*: string

proc initStatusBarData*(): StatusBarData =
  StatusBarData(
    items: @[],
    maxWidth: 80,
    useArrows: true,
    expertModeActive: false,
    expertModeInput: ""
  )

# =============================================================================
# Width Calculation
# =============================================================================

proc calcItemWidth(item: BarItem, useArrows: bool): int =
  ## Calculate the display width of a single bar item
  ## Format: " before[key]after " + separator
  let labelWidth = if item.labelHasPipe:
                     item.labelBefore.len + item.labelAfter.len
                   else:
                     item.label.len
  result = 1 + labelWidth + 2 + item.keyDisplay.len + 1
  if useArrows:
    result += 1  # Arrow separator

proc calcTotalWidth(items: seq[BarItem], useArrows: bool): int =
  ## Calculate total width of all bar items
  result = 0
  for item in items:
    result += calcItemWidth(item, useArrows)

proc fitItemsToWidth*(model: TuiModel, maxWidth: int,
    useArrows: bool = true): seq[BarItem] =
  ## Build bar items that fit within maxWidth
  ## Tries full labels first, then short labels, then truncates

  # Try with full labels
  var items = buildBarItems(model, useShortLabels = false)
  if calcTotalWidth(items, useArrows) <= maxWidth:
    return items

  # Try with short labels
  items = buildBarItems(model, useShortLabels = true)
  if calcTotalWidth(items, useArrows) <= maxWidth:
    return items

  # Still too wide - progressively drop items from the end (except expert)
  while items.len > 1 and calcTotalWidth(items, useArrows) > maxWidth:
    # Keep the last item if it's expert mode hint
    if items[^1].binding.actionKind == ActionKind.enterExpertMode:
      if items.len > 2:
        items.delete(items.len - 2)
      else:
        break
    else:
      items.delete(items.len - 1)

  result = items

# =============================================================================
# Status Bar Building
# =============================================================================

proc buildStatusBarData*(model: TuiModel, maxWidth: int): StatusBarData =
  ## Build status bar data from model state
  result = initStatusBarData()
  result.maxWidth = maxWidth
  result.useArrows = true
  result.expertModeActive = model.ui.expertModeActive
  result.expertModeInput = model.ui.expertModeInput

  if not model.ui.expertModeActive:
    result.items = fitItemsToWidth(model, maxWidth, useArrows = true)

# =============================================================================
# Rendering
# =============================================================================

proc renderStatusBar*(area: Rect, buf: var CellBuffer,
    data: StatusBarData) =
  ## Render the status bar to the buffer
  ## Uses Zellij-style formatting with powerline arrows

  if area.height < 1:
    return

  let y = area.y
  var x = area.x

  # Fill background
  for col in area.x ..< area.x + area.width:
    discard buf.put(col, y, " ", barBgStyle())

  # Expert mode: show prompt instead of items
  if data.expertModeActive:
    # Show ": " prompt with input
    let prompt = ":"
    let input = data.expertModeInput
    let cursor = "_"

    # Draw prompt
    discard buf.put(x, y, prompt, barKeyStyle())
    x += 1

    # Draw input
    for ch in input:
      if x >= area.x + area.width - 1:
        break
      discard buf.put(x, y, $ch, barTextStyle())
      x += 1

    # Draw cursor
    if x < area.x + area.width:
      discard buf.put(x, y, cursor, barCursorStyle())

    return

  # Render each item
  var isFirst = true
  for item in data.items:
    # Check if we have room
    let itemWidth = calcItemWidth(item, data.useArrows)
    if x + itemWidth > area.x + area.width:
      break

    # Choose style based on item mode
    let (keyStyle, textStyle, sepStyle) = case item.mode
      of BarItemMode.Selected:
        (barSelectedKeyStyle(), barSelectedTextStyle(), barSelectedSepStyle())
      of BarItemMode.Unselected:
        (barKeyStyle(), barTextStyle(), barSepStyle())
      of BarItemMode.UnselectedAlt:
        (barAltKeyStyle(), barAltTextStyle(), barAltSepStyle())
      of BarItemMode.Disabled:
        (barDisabledStyle(), barDisabledStyle(), barDisabledStyle())

    # Draw leading separator (powerline arrow from previous segment)
    if not isFirst and data.useArrows:
      discard buf.put(x, y, ArrowSeparator, sepStyle)
      x += 1
    elif not isFirst:
      discard buf.put(x, y, " ", barBgStyle())
      x += 1

    # Draw leading space
    discard buf.put(x, y, " ", textStyle)
    x += 1

    # Draw label before key
    let labelBefore = if item.labelHasPipe: item.labelBefore else: ""
    let labelAfter = if item.labelHasPipe: item.labelAfter else: item.label

    for ch in labelBefore:
      if x >= area.x + area.width:
        break
      discard buf.put(x, y, $ch, textStyle)
      x += 1

    # Draw [key]
    discard buf.put(x, y, "[", textStyle)
    x += 1
    for ch in item.keyDisplay:
      if x >= area.x + area.width:
        break
      discard buf.put(x, y, $ch, keyStyle)
      x += 1
    discard buf.put(x, y, "]", textStyle)
    x += 1

    # Draw label after key
    for ch in labelAfter:
      if x >= area.x + area.width:
        break
      discard buf.put(x, y, $ch, textStyle)
      x += 1

    # Draw trailing space
    if x < area.x + area.width:
      discard buf.put(x, y, " ", textStyle)
      x += 1

    isFirst = false

  # Fill remaining space with background
  while x < area.x + area.width:
    discard buf.put(x, y, " ", barBgStyle())
    x += 1
