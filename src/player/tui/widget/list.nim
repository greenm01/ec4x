## List - Scrollable list widget with selection
##
## Displays a vertical list of items with optional selection highlighting.
## Uses StatefulWidget pattern with ListState for persistent selection.

import std/options
import ./text/text_pkg
import ./frame
import ../buffer
import ../layout/rect

type
  ListItem* = object
    ## A single item in a list.
    content: Text
    style: CellStyle

  ListDirection* {.pure.} = enum
    ## Direction to render list items.
    TopToBottom
    BottomToTop

  List* = object
    ## Scrollable list widget.
    blk: Option[Frame]
    items: seq[ListItem]
    style: CellStyle
    direction: ListDirection
    highlightStyle: CellStyle
    highlightSymbol: Option[string]

  ListState* = object
    ## Persistent state for list selection and scrolling.
    selected*: Option[int]
    offset*: int  ## Scroll offset

# -----------------------------------------------------------------------------
# ListItem constructors
# -----------------------------------------------------------------------------

proc listItem*(content: string): ListItem =
  ## Create a list item from a string.
  ListItem(
    content: text(content),
    style: defaultStyle()
  )

proc listItem*(content: Text): ListItem =
  ## Create a list item from Text.
  ListItem(
    content: content,
    style: defaultStyle()
  )

proc style*(item: ListItem, s: CellStyle): ListItem =
  ## Set item style.
  result = item
  result.style = s

# -----------------------------------------------------------------------------
# List constructors
# -----------------------------------------------------------------------------

proc list*(items: openArray[ListItem]): List =
  ## Create a list from items.
  List(
    blk: none(Frame),
    items: @items,
    style: defaultStyle(),
    direction: ListDirection.TopToBottom,
    highlightStyle: defaultStyle(),
    highlightSymbol: some("> ")
  )

proc list*(items: openArray[string]): List =
  ## Create a list from strings.
  var listItems: seq[ListItem] = @[]
  for item in items:
    listItems.add(listItem(item))
  list(listItems)

# -----------------------------------------------------------------------------
# List builder methods
# -----------------------------------------------------------------------------

proc `block`*(l: List, b: Frame): List =
  ## Wrap list in a block.
  result = l
  result.blk = some(b)

proc style*(l: List, s: CellStyle): List =
  ## Set list style.
  result = l
  result.style = s

proc highlightStyle*(l: List, s: CellStyle): List =
  ## Set highlight style for selected item.
  result = l
  result.highlightStyle = s

proc highlightSymbol*(l: List, sym: string): List =
  ## Set highlight symbol (e.g., "> " or "→ ").
  result = l
  result.highlightSymbol = some(sym)

proc direction*(l: List, d: ListDirection): List =
  ## Set list direction.
  result = l
  result.direction = d

# -----------------------------------------------------------------------------
# ListState operations
# -----------------------------------------------------------------------------

proc newListState*(): ListState =
  ## Create a new list state with no selection.
  ListState(
    selected: none(int),
    offset: 0
  )

proc select*(state: var ListState, idx: int) =
  ## Select an item by index.
  state.selected = some(idx)

proc selectNext*(state: var ListState, itemCount: int) =
  ## Select next item (wraps around).
  if itemCount == 0:
    return
  let current = state.selected.get(0)
  state.selected = some((current + 1) mod itemCount)

proc selectPrev*(state: var ListState) =
  ## Select previous item (wraps around).
  if state.selected.isNone:
    return
  let current = state.selected.get()
  if current > 0:
    state.selected = some(current - 1)

proc deselect*(state: var ListState) =
  ## Clear selection.
  state.selected = none(int)

# -----------------------------------------------------------------------------
# Rendering
# -----------------------------------------------------------------------------

proc render*(l: List, area: Rect, buf: var CellBuffer, 
             state: var ListState) =
  ## Render the list to the buffer with state.
  ## Implements StatefulWidget.render.
  
  if area.isEmpty:
    return
  
  # Apply list style
  if not l.style.fg.isNone or not l.style.bg.isNone:
    buf.setStyle(area, l.style)
  
  # Render optional block
  var contentArea = area
  if l.blk.isSome:
    let blk = l.blk.get()
    blk.render(area, buf)
    contentArea = blk.inner(area)
  
  if contentArea.isEmpty or l.items.len == 0:
    return
  
  # Calculate which items to show
  let visibleHeight = contentArea.height
  let maxOffset = max(0, l.items.len - visibleHeight)
  
  # Ensure offset is valid
  if state.offset > maxOffset:
    state.offset = maxOffset
  
  # Ensure selected item is visible
  if state.selected.isSome:
    let selectedIdx = state.selected.get()
    if selectedIdx < state.offset:
      state.offset = selectedIdx
    elif selectedIdx >= state.offset + visibleHeight:
      state.offset = selectedIdx - visibleHeight + 1
  
  # Render visible items
  var y = contentArea.y
  let startIdx = state.offset
  let endIdx = min(l.items.len, startIdx + visibleHeight)
  
  for i in startIdx ..< endIdx:
    if y >= contentArea.bottom:
      break
    
    let item = l.items[i]
    let isSelected = state.selected.isSome and state.selected.get() == i
    
    var x = contentArea.x
    
    # Render highlight symbol if selected
    if isSelected and l.highlightSymbol.isSome:
      let sym = l.highlightSymbol.get()
      discard buf.setString(x, y, sym, l.highlightStyle)
      x += sym.len
    
    # Render item content (first line only for now)
    if item.content.lines.len > 0:
      let line = item.content.lines[0]
      
      # Use highlight style if selected, otherwise item style
      let itemStyle = if isSelected: l.highlightStyle else: item.style
      
      for span in line.spans:
        if x >= contentArea.right:
          break
        
        # Merge styles
        var spanStyle = span.style
        if spanStyle.fg.isNone:
          spanStyle.fg = itemStyle.fg
        if spanStyle.bg.isNone:
          spanStyle.bg = itemStyle.bg
        
        let written = buf.setString(x, y, span.content, spanStyle)
        x += written
    
    y += 1
