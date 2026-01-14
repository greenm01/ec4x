## Screen buffer management with dirty tracking.
##
## Provides a double-buffered cell grid for efficient terminal rendering.
## Each cell tracks both current and last state for dirty detection.
## Inspired by tcell's CellBuffer design.

import std/unicode
import term/types/[core, style]


# Width calculation for runes
proc runeWidth(r: Rune): int =
  ## Determine display width of a rune (1 or 2 for wide characters).
  ## Simplified version - East Asian characters and emoji are width 2.
  let c = int(r)
  
  # Basic ASCII and Latin-1 are width 1
  if c < 0x1100:
    return 1
  
  # East Asian Wide and Fullwidth ranges (simplified)
  # Based on Unicode East Asian Width property
  if (c >= 0x1100 and c <= 0x115F) or    # Hangul Jamo
     (c >= 0x2329 and c <= 0x232A) or    # Angle brackets
     (c >= 0x2E80 and c <= 0x303E) or    # CJK Radicals
     (c >= 0x3040 and c <= 0xA4CF) or    # CJK Unified Ideographs
     (c >= 0xAC00 and c <= 0xD7A3) or    # Hangul Syllables
     (c >= 0xF900 and c <= 0xFAFF) or    # CJK Compatibility
     (c >= 0xFE10 and c <= 0xFE19) or    # Vertical forms
     (c >= 0xFE30 and c <= 0xFE6F) or    # CJK Compatibility Forms
     (c >= 0xFF00 and c <= 0xFF60) or    # Fullwidth forms
     (c >= 0xFFE0 and c <= 0xFFE6) or    # Fullwidth symbols
     (c >= 0x1F000 and c <= 0x1FFFF) or  # Emoji and symbols
     (c >= 0x20000 and c <= 0x3FFFF):    # CJK Extension B+
    return 2
  
  return 1


type
  CellStyle* = object
    ## Style for a single cell in the buffer.
    ## Separate from term/types/style.Style which is for building styled text.
    fg*: Color
    bg*: Color
    attrs*: set[StyleAttr]

  Cell* = object
    ## A single character cell with current and last state for dirty tracking.
    currStr*: string          # Current grapheme cluster (UTF-8)
    lastStr*: string          # Last rendered content
    currStyle*: CellStyle     # Current style
    lastStyle*: CellStyle     # Last rendered style
    width*: int               # Display width (1 or 2 for wide chars)
    locked*: bool             # Prevent redraw (for graphics regions)

  CellBuffer* = object
    ## Two-dimensional array of character cells.
    ## Not thread-safe - external synchronization required.
    w*: int
    h*: int
    cells*: seq[Cell]


# CellStyle operations
proc `==`*(a, b: CellStyle): bool {.inline.} =
  ## Compare two cell styles for equality.
  a.fg == b.fg and a.bg == b.bg and a.attrs == b.attrs

proc defaultStyle*(): CellStyle {.inline.} =
  ## Create a default cell style (no colors, no attributes).
  CellStyle(
    fg: noColor(),
    bg: noColor(),
    attrs: {}
  )


# Cell operations
proc setDirty(c: var Cell, dirty: bool) =
  ## Mark cell as dirty or clean.
  ## Dirty means content differs from last render.
  if dirty:
    c.lastStr = ""
  else:
    if c.currStr == "":
      c.currStr = " "
    c.lastStr = c.currStr
    c.lastStyle = c.currStyle

proc isDirty*(c: Cell): bool {.inline.} =
  ## Check if cell needs rerendering.
  if c.locked:
    return false
  if c.lastStyle != c.currStyle:
    return true
  if c.lastStr != c.currStr:
    return true
  return false


# CellBuffer operations
proc initBuffer*(w, h: int): CellBuffer =
  ## Create a new cell buffer with given dimensions.
  ## All cells initialized to empty with default style.
  result.w = w
  result.h = h
  result.cells = newSeq[Cell](w * h)
  # Initialize all cells
  for i in 0..<result.cells.len:
    result.cells[i].currStr = " "
    result.cells[i].lastStr = ""
    result.cells[i].currStyle = defaultStyle()
    result.cells[i].width = 1

proc size*(cb: CellBuffer): tuple[w, h: int] {.inline.} =
  ## Returns the (width, height) in cells of the buffer.
  (cb.w, cb.h)

proc put*(cb: var CellBuffer, x, y: int, str: string, style: CellStyle): int =
  ## Put a single styled grapheme at the given location.
  ## Only the first grapheme in the string will be displayed.
  ## Returns the width used (1 or 2 for wide characters).
  ## Out-of-bounds coordinates are ignored.
  result = 0
  if x >= 0 and y >= 0 and x < cb.w and y < cb.h:
    let idx = (y * cb.w) + x
    let c = addr cb.cells[idx]
    
    # Extract first grapheme and determine width
    var width = 0
    var cluster = ""
    
    if str.len > 0:
      # Get first rune to determine width
      let r = str.runeAt(0)
      width = r.runeWidth()
      cluster = $r
      
      # For safety, ensure width is 1 or 2
      if width < 1:
        width = 1
      elif width > 2:
        width = 2
    
    # Mark wide character cells dirty if content changes
    if width > 0 and cluster != c.currStr:
      c[].setDirty(true)
      for i in 1..<width:
        if x + i < cb.w:
          cb.cells[idx + i].setDirty(true)
    
    c.currStr = cluster
    c.width = width
    
    # Merge colors: ColorNone means keep current
    var newStyle = style
    if style.fg.isNone:
      newStyle.fg = c.currStyle.fg
    if style.bg.isNone:
      newStyle.bg = c.currStyle.bg
    
    c.currStyle = newStyle
    result = width

proc get*(cb: CellBuffer, x, y: int): tuple[str: string, style: CellStyle, width: int] =
  ## Get the contents of a character cell.
  ## Returns empty content for out-of-bounds coordinates.
  if x >= 0 and y >= 0 and x < cb.w and y < cb.h:
    let c = cb.cells[(y * cb.w) + x]
    var str = c.currStr
    var width = c.width
    if width == 0 or str == "":
      width = 1
      str = " "
    result = (str, c.currStyle, width)
  else:
    result = ("", defaultStyle(), 0)

proc dirty*(cb: CellBuffer, x, y: int): bool =
  ## Check if a character at the given location needs to be refreshed.
  ## Returns false for out-of-bounds coordinates.
  if x >= 0 and y >= 0 and x < cb.w and y < cb.h:
    cb.cells[(y * cb.w) + x].isDirty()
  else:
    false

proc setDirty*(cb: var CellBuffer, x, y: int, dirty: bool) =
  ## Manually mark a cell as dirty (needs redraw) or clean (up to date).
  ## Used after rendering a cell or to force a redraw.
  if x >= 0 and y >= 0 and x < cb.w and y < cb.h:
    cb.cells[(y * cb.w) + x].setDirty(dirty)

proc invalidate*(cb: var CellBuffer) =
  ## Mark all characters within the buffer as dirty.
  ## Forces full screen redraw on next render.
  for i in 0..<cb.cells.len:
    cb.cells[i].lastStr = ""

proc lockCell*(cb: var CellBuffer, x, y: int) =
  ## Lock a cell from being drawn.
  ## Useful for regions with external graphics (e.g., sixel).
  if x >= 0 and y >= 0 and x < cb.w and y < cb.h:
    cb.cells[(y * cb.w) + x].locked = true

proc unlockCell*(cb: var CellBuffer, x, y: int) =
  ## Remove lock from a cell and mark it dirty.
  if x >= 0 and y >= 0 and x < cb.w and y < cb.h:
    let idx = (y * cb.w) + x
    cb.cells[idx].locked = false
    cb.cells[idx].setDirty(true)

proc resize*(cb: var CellBuffer, w, h: int) =
  ## Resize the cell buffer, preserving original contents.
  ## New cells are initialized to empty. All cells marked dirty.
  if cb.h == h and cb.w == w:
    return
  
  var newCells = newSeq[Cell](w * h)
  
  # Initialize new cells
  for i in 0..<newCells.len:
    newCells[i].currStr = " "
    newCells[i].lastStr = ""
    newCells[i].currStyle = defaultStyle()
    newCells[i].width = 1
  
  # Copy existing content
  for y in 0..<min(h, cb.h):
    for x in 0..<min(w, cb.w):
      let oldIdx = (y * cb.w) + x
      let newIdx = (y * w) + x
      newCells[newIdx].currStr = cb.cells[oldIdx].currStr
      newCells[newIdx].currStyle = cb.cells[oldIdx].currStyle
      newCells[newIdx].width = cb.cells[oldIdx].width
      # Mark as dirty (lastStr remains empty)
  
  cb.cells = newCells
  cb.h = h
  cb.w = w

proc fill*(cb: var CellBuffer, r: Rune, style: CellStyle) =
  ## Fill the entire buffer with a character and style.
  ## Typically used with ' ' to clear the screen.
  ## Does not support combining characters or width > 1.
  let str = $r
  for i in 0..<cb.cells.len:
    let c = addr cb.cells[i]
    c.currStr = str
    var newStyle = style
    if style.fg.isNone:
      newStyle.fg = c.currStyle.fg
    if style.bg.isNone:
      newStyle.bg = c.currStyle.bg
    c.currStyle = newStyle
    c.width = 1

proc clear*(cb: var CellBuffer) =
  ## Clear the buffer (fill with spaces and default style).
  cb.fill(Rune(' '), defaultStyle())
