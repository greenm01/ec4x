## Tabs - Tab selector widget for detail views
##
## Renders a horizontal tab bar with active tab highlighting.
## Used in Planet Detail view for Summary/Economy/Construction tabs.
##
## Example output:
##   [Summary]  Economy  Construction  Defense  Settings
##
## Reference: ec-style-layout.md Planet Detail View

import ../buffer
import ../layout/rect
import ../styles/ec_palette

type
  TabItem* = object
    ## A single tab in the tab bar.
    label*: string
    enabled*: bool       ## Disabled tabs shown but not selectable

  Tabs* = object
    ## Tab bar widget configuration.
    items*: seq[TabItem]
    activeIdx*: int       ## Currently selected tab index
    activeStyle*: CellStyle    ## Style for active tab
    inactiveStyle*: CellStyle  ## Style for inactive tabs
    disabledStyle*: CellStyle  ## Style for disabled tabs
    bracketStyle*: CellStyle   ## Style for [ ] around active tab
    separator*: string         ## Separator between tabs
    showBrackets*: bool        ## Show [ ] around active tab

# -----------------------------------------------------------------------------
# Constructors
# -----------------------------------------------------------------------------

proc tabItem*(label: string, enabled: bool = true): TabItem =
  ## Create a tab item.
  TabItem(label: label, enabled: enabled)

proc tabs*(items: openArray[TabItem], activeIdx: int = 0): Tabs =
  ## Create a tab bar with explicit tab items.
  Tabs(
    items: @items,
    activeIdx: clamp(activeIdx, 0, max(0, items.len - 1)),
    activeStyle: CellStyle(
      fg: color(SelectedFgColor),
      bg: color(SelectedBgColor),
      attrs: {StyleAttr.Bold}
    ),
    inactiveStyle: canvasStyle(),
    disabledStyle: canvasDimStyle(),
    bracketStyle: canvasDimStyle(),
    separator: "  ",  # Two spaces between tabs
    showBrackets: true
  )

proc tabs*(labels: openArray[string], activeIdx: int = 0): Tabs =
  ## Create a tab bar from string labels (all enabled).
  var items: seq[TabItem] = @[]
  for label in labels:
    items.add(tabItem(label))
  tabs(items, activeIdx)

# -----------------------------------------------------------------------------
# Builder methods
# -----------------------------------------------------------------------------

proc activeIdx*(t: Tabs, idx: int): Tabs =
  ## Set the active tab index.
  result = t
  result.activeIdx = clamp(idx, 0, max(0, t.items.len - 1))

proc activeStyle*(t: Tabs, style: CellStyle): Tabs =
  ## Set style for active tab.
  result = t
  result.activeStyle = style

proc inactiveStyle*(t: Tabs, style: CellStyle): Tabs =
  ## Set style for inactive tabs.
  result = t
  result.inactiveStyle = style

proc disabledStyle*(t: Tabs, style: CellStyle): Tabs =
  ## Set style for disabled tabs.
  result = t
  result.disabledStyle = style

proc separator*(t: Tabs, sep: string): Tabs =
  ## Set separator between tabs.
  result = t
  result.separator = sep

proc showBrackets*(t: Tabs, show: bool): Tabs =
  ## Toggle [ ] brackets around active tab.
  result = t
  result.showBrackets = show

# -----------------------------------------------------------------------------
# Tab operations
# -----------------------------------------------------------------------------

proc selectNext*(t: var Tabs) =
  ## Select next enabled tab (wraps around).
  if t.items.len == 0:
    return
  var idx = t.activeIdx
  for i in 1 .. t.items.len:
    idx = (idx + 1) mod t.items.len
    if t.items[idx].enabled:
      t.activeIdx = idx
      return

proc selectPrev*(t: var Tabs) =
  ## Select previous enabled tab (wraps around).
  if t.items.len == 0:
    return
  var idx = t.activeIdx
  for i in 1 .. t.items.len:
    idx = (idx - 1 + t.items.len) mod t.items.len
    if t.items[idx].enabled:
      t.activeIdx = idx
      return

proc selectByIndex*(t: var Tabs, idx: int) =
  ## Select tab by index (only if enabled).
  if idx >= 0 and idx < t.items.len and t.items[idx].enabled:
    t.activeIdx = idx

proc activeLabel*(t: Tabs): string =
  ## Get label of currently active tab.
  if t.activeIdx >= 0 and t.activeIdx < t.items.len:
    t.items[t.activeIdx].label
  else:
    ""

proc tabCount*(t: Tabs): int =
  ## Get total number of tabs.
  t.items.len

proc enabledCount*(t: Tabs): int =
  ## Get number of enabled tabs.
  result = 0
  for item in t.items:
    if item.enabled:
      result.inc

# -----------------------------------------------------------------------------
# String rendering (for simple use cases)
# -----------------------------------------------------------------------------

proc renderToString*(t: Tabs): string =
  ## Render tab bar to a string (no styling).
  result = ""
  for i, item in t.items:
    if i > 0:
      result.add(t.separator)
    
    let isActive = i == t.activeIdx
    if isActive and t.showBrackets:
      result.add("[")
      result.add(item.label)
      result.add("]")
    else:
      result.add(item.label)

# -----------------------------------------------------------------------------
# Buffer rendering
# -----------------------------------------------------------------------------

proc render*(t: Tabs, area: Rect, buf: var CellBuffer) =
  ## Render tab bar to buffer at given area.
  ## Renders on a single line, starting at area.x, area.y.
  if area.isEmpty or area.height < 1 or t.items.len == 0:
    return
  
  var x = area.x
  let y = area.y
  let maxX = area.right
  
  for i, item in t.items:
    # Add separator after first tab
    if i > 0 and x < maxX:
      let sepWritten = buf.setString(x, y, t.separator, t.inactiveStyle)
      x += sepWritten
    
    if x >= maxX:
      break
    
    let isActive = i == t.activeIdx
    let style = if not item.enabled:
      t.disabledStyle
    elif isActive:
      t.activeStyle
    else:
      t.inactiveStyle
    
    # Opening bracket for active tab
    if isActive and t.showBrackets and x < maxX:
      discard buf.setString(x, y, "[", t.bracketStyle)
      x += 1
    
    # Tab label
    if x < maxX:
      let labelWidth = min(item.label.len, maxX - x)
      let labelToRender = if labelWidth < item.label.len:
        item.label[0 ..< labelWidth]
      else:
        item.label
      let written = buf.setString(x, y, labelToRender, style)
      x += written
    
    # Closing bracket for active tab
    if isActive and t.showBrackets and x < maxX:
      discard buf.setString(x, y, "]", t.bracketStyle)
      x += 1

# -----------------------------------------------------------------------------
# Convenience constructors for common use cases
# -----------------------------------------------------------------------------

proc planetDetailTabs*(activeIdx: int = 0): Tabs =
  ## Create tabs for Planet Detail view.
  ## Matches ec-style-layout.md specification.
  tabs([
    tabItem("Summary"),
    tabItem("Economy"),
    tabItem("Construction"),
    tabItem("Defense"),
    tabItem("Settings")
  ], activeIdx)

proc fleetDetailTabs*(activeIdx: int = 0): Tabs =
  ## Create tabs for Fleet Detail view.
  tabs([
    tabItem("Ships"),
    tabItem("Orders"),
    tabItem("Status")
  ], activeIdx)
