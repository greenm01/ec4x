## Frame - Container widget with borders and titles
##
## Frame is the foundational widget that draws borders and titles around
## content. Most other widgets accept an optional Frame to wrap themselves.
##
## Named 'Frame' to avoid Nim's 'block' keyword. Equivalent to ratatui's Block.

import std/options
import ./text/text_pkg
import ./borders
import ../buffer
import ../layout/rect
import ../term/types/core

# Re-export isNone for Color checking
export isNone

type
  TitlePosition* {.pure.} = enum
    ## Where to position titles.
    Top
    Bottom

  Padding* = object
    ## Internal padding within borders.
    left*, top*, right*, bottom*: int

  Frame* = object
    ## Container widget with borders, titles, and padding.
    titles: seq[tuple[pos: TitlePosition, line: Line]]
    titlesStyle: CellStyle
    titlesAlignment: Alignment
    borders: Borders
    borderStyle: CellStyle
    borderType: BorderType
    style: CellStyle
    padding: Padding

# -----------------------------------------------------------------------------
# Padding helpers
# -----------------------------------------------------------------------------

proc padding*(all: int): Padding =
  ## Equal padding on all sides.
  Padding(left: all, top: all, right: all, bottom: all)

proc padding*(horizontal, vertical: int): Padding =
  ## Separate horizontal and vertical padding.
  Padding(left: horizontal, top: vertical, 
          right: horizontal, bottom: vertical)

proc padding*(left, top, right, bottom: int): Padding =
  ## Individual padding for each side.
  Padding(left: left, top: top, right: right, bottom: bottom)

const NoPadding* = Padding(left: 0, top: 0, right: 0, bottom: 0)

proc horizontal*(p: Padding): int {.inline.} =
  p.left + p.right

proc vertical*(p: Padding): int {.inline.} =
  p.top + p.bottom

# -----------------------------------------------------------------------------
# Frame constructors
# -----------------------------------------------------------------------------

proc newFrame*(): Frame =
  ## Create a block with no borders or padding.
  Frame(
    titles: @[],
    titlesStyle: defaultStyle(),
    titlesAlignment: Alignment.Left,
    borders: NoBorders,
    borderStyle: defaultStyle(),
    borderType: BorderType.Plain,
    style: defaultStyle(),
    padding: NoPadding
  )

proc bordered*(): Frame =
  ## Create a block with all borders.
  result = newFrame()
  result.borders = AllBorders

# -----------------------------------------------------------------------------
# Builder methods (fluent API)
# -----------------------------------------------------------------------------

proc title*(b: Frame, t: Line): Frame =
  ## Add a title at the default position (top).
  result = b
  result.titles.add((TitlePosition.Top, t))

proc title*(b: Frame, t: string): Frame =
  ## Add a title from string.
  result = b
  result.titles.add((TitlePosition.Top, line(t)))

proc titleTop*(b: Frame, t: Line): Frame =
  ## Add a title at the top.
  result = b
  result.titles.add((TitlePosition.Top, t))

proc titleTop*(b: Frame, t: string): Frame =
  result = b
  result.titles.add((TitlePosition.Top, line(t)))

proc titleBottom*(b: Frame, t: Line): Frame =
  ## Add a title at the bottom.
  result = b
  result.titles.add((TitlePosition.Bottom, t))

proc titleBottom*(b: Frame, t: string): Frame =
  result = b
  result.titles.add((TitlePosition.Bottom, line(t)))

proc titleStyle*(b: Frame, s: CellStyle): Frame =
  ## Set style for all titles.
  result = b
  result.titlesStyle = s

proc titleAlignment*(b: Frame, a: Alignment): Frame =
  ## Set default alignment for titles.
  result = b
  result.titlesAlignment = a

proc borders*(b: Frame, borders: Borders): Frame =
  ## Set which borders to show.
  result = b
  result.borders = borders

proc borderStyle*(b: Frame, s: CellStyle): Frame =
  ## Set border style.
  result = b
  result.borderStyle = s

proc borderType*(b: Frame, bt: BorderType): Frame =
  ## Set border character set.
  result = b
  result.borderType = bt

proc style*(b: Frame, s: CellStyle): Frame =
  ## Set base style for entire block.
  result = b
  result.style = s

proc padding*(b: Frame, p: Padding): Frame =
  ## Set padding.
  result = b
  result.padding = p

proc padding*(b: Frame, all: int): Frame =
  result = b
  result.padding = padding(all)

# -----------------------------------------------------------------------------
# Key method: calculate inner area
# -----------------------------------------------------------------------------

proc inner*(b: Frame, area: Rect): Rect =
  ## Calculate the inner area after accounting for borders and padding.
  ## This is where content should be rendered.
  var x = area.x
  var y = area.y
  var width = area.width
  var height = area.height
  
  # Account for borders
  if b.borders.hasLeft:
    x += 1
    width -= 1
  if b.borders.hasRight:
    width -= 1
  if b.borders.hasTop:
    y += 1
    height -= 1
  if b.borders.hasBottom:
    height -= 1
  
  # Account for padding
  x += b.padding.left
  y += b.padding.top
  width -= b.padding.horizontal
  height -= b.padding.vertical
  
  # Ensure non-negative
  if width < 0: width = 0
  if height < 0: height = 0
  
  rect(x, y, width, height)

# -----------------------------------------------------------------------------
# Rendering
# -----------------------------------------------------------------------------

proc renderBorders(b: Frame, area: Rect, buf: var CellBuffer, 
                   borderSet: BorderSet) =
  ## Render border characters.
  let style = b.borderStyle
  
  # Top border
  if b.borders.hasTop:
    for x in area.x ..< area.right:
      # Skip corners for now
      if (x == area.x and b.borders.hasLeft) or 
         (x == area.right - 1 and b.borders.hasRight):
        continue
      discard buf.put(x, area.y, borderSet.horizontal, style)
  
  # Bottom border
  if b.borders.hasBottom:
    for x in area.x ..< area.right:
      if (x == area.x and b.borders.hasLeft) or 
         (x == area.right - 1 and b.borders.hasRight):
        continue
      discard buf.put(x, area.bottom - 1, borderSet.horizontal, style)
  
  # Left border
  if b.borders.hasLeft:
    for y in area.y ..< area.bottom:
      if (y == area.y and b.borders.hasTop) or 
         (y == area.bottom - 1 and b.borders.hasBottom):
        continue
      discard buf.put(area.x, y, borderSet.vertical, style)
  
  # Right border
  if b.borders.hasRight:
    for y in area.y ..< area.bottom:
      if (y == area.y and b.borders.hasTop) or 
         (y == area.bottom - 1 and b.borders.hasBottom):
        continue
      discard buf.put(area.right - 1, y, borderSet.vertical, style)
  
  # Corners
  if b.borders.hasTop and b.borders.hasLeft:
    discard buf.put(area.x, area.y, borderSet.topLeft, style)
  if b.borders.hasTop and b.borders.hasRight:
    discard buf.put(area.right - 1, area.y, borderSet.topRight, style)
  if b.borders.hasBottom and b.borders.hasLeft:
    discard buf.put(area.x, area.bottom - 1, borderSet.bottomLeft, style)
  if b.borders.hasBottom and b.borders.hasRight:
    discard buf.put(area.right - 1, area.bottom - 1, 
                   borderSet.bottomRight, style)

proc renderTitles(b: Frame, area: Rect, buf: var CellBuffer, 
                  pos: TitlePosition) =
  ## Render titles at the given position.
  # Filter titles for this position
  var titlesAtPos: seq[Line] = @[]
  for (titlePos, titleLine) in b.titles:
    if titlePos == pos:
      titlesAtPos.add(titleLine)
  
  if titlesAtPos.len == 0:
    return
  
  # Determine Y position
  let y = case pos
    of TitlePosition.Top: area.y
    of TitlePosition.Bottom: area.bottom - 1
  
  # Group titles by alignment
  var leftTitles: seq[Line] = @[]
  var centerTitles: seq[Line] = @[]
  var rightTitles: seq[Line] = @[]
  
  for title in titlesAtPos:
    case title.alignment
    of Alignment.Left: leftTitles.add(title)
    of Alignment.Center: centerTitles.add(title)
    of Alignment.Right: rightTitles.add(title)
  
  # Calculate available width
  var availableWidth = area.width
  if b.borders.hasLeft:
    availableWidth -= 1
  if b.borders.hasRight:
    availableWidth -= 1
  
  if availableWidth <= 0:
    return
  
  # Render left-aligned titles
  var x = area.x
  if b.borders.hasLeft:
    x += 1
  
  for title in leftTitles:
    for span in title.spans:
      let written = buf.setString(x, y, span.content, span.style)
      x += written
      if x >= area.right - (if b.borders.hasRight: 1 else: 0):
        return
    # Space between titles
    x += 1
  
  # Render right-aligned titles (from right)
  if rightTitles.len > 0:
    x = area.right
    if b.borders.hasRight:
      x -= 1
    
    for i in countdown(rightTitles.len - 1, 0):
      let title = rightTitles[i]
      # Calculate title width
      var titleWidth = 0
      for span in title.spans:
        titleWidth += span.width()
      
      x -= titleWidth
      if x < area.x + (if b.borders.hasLeft: 1 else: 0):
        break
      
      # Render spans
      var currentX = x
      for span in title.spans:
        discard buf.setString(currentX, y, span.content, span.style)
        currentX += span.width()
      
      x -= 1  # Space before next title
  
  # Render centered titles
  if centerTitles.len > 0:
    # Calculate total width of centered titles
    var totalWidth = 0
    for title in centerTitles:
      totalWidth += title.width()
    totalWidth += (centerTitles.len - 1)  # Spaces between
    
    # Center position
    x = area.x + (area.width - totalWidth) div 2
    
    for title in centerTitles:
      for span in title.spans:
        let written = buf.setString(x, y, span.content, span.style)
        x += written
      x += 1  # Space

proc render*(b: Frame, area: Rect, buf: var CellBuffer) =
  ## Render the block to the buffer.
  ## Implements Widget.render.
  
  if area.isEmpty:
    return
  
  # Apply base style to entire area
  if not b.style.fg.isNone or not b.style.bg.isNone:
    buf.setStyle(area, b.style)
  
  # Render borders
  if not b.borders.isEmpty:
    let borderSet = b.borderType.borderSet()
    b.renderBorders(area, buf, borderSet)
  
  # Render titles
  if b.titles.len > 0:
    b.renderTitles(area, buf, TitlePosition.Top)
    b.renderTitles(area, buf, TitlePosition.Bottom)
