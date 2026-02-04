## Screen buffer management with dirty tracking.
##
## Provides a double-buffered cell grid for efficient terminal rendering.
## Each cell tracks both current and last state for dirty detection.
## Inspired by tcell's CellBuffer design.

import std/unicode
import term/types/[core, style]
import layout/rect


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


const
  SpaceRune = Rune(ord(' '))

type
  CellStyle* = object
    ## Style for a single cell in the buffer.
    ## Separate from term/types/style.Style which is for building styled text.
    fg*: Color
    bg*: Color
    attrs*: set[StyleAttr]

  Cell* = object
    ## A single character cell with current and last state for dirty tracking.
    currRune*: Rune           # Current rune
    lastRune*: Rune           # Last rendered rune
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
    c.lastRune = Rune(0)
  else:
    if c.currRune.int == 0:
      c.currRune = SpaceRune
      c.width = 1
    c.lastRune = c.currRune
    c.lastStyle = c.currStyle

proc isDirty*(c: Cell): bool {.inline.} =
  ## Check if cell needs rerendering.
  if c.locked:
    return false
  if c.lastStyle != c.currStyle:
    return true
  if c.lastRune != c.currRune:
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
    result.cells[i].currRune = SpaceRune
    result.cells[i].lastRune = Rune(0)
    result.cells[i].currStyle = defaultStyle()
    result.cells[i].width = 1

proc size*(cb: CellBuffer): tuple[w, h: int] {.inline.} =
  ## Returns the (width, height) in cells of the buffer.
  (cb.w, cb.h)

proc put*(cb: var CellBuffer, x, y: int, str: string,
          style: CellStyle): int =
  ## Put a single styled grapheme at the given location.
  ## Only the first grapheme in the string will be displayed.
  ## Returns the width used (1 or 2 for wide characters).
  ## Out-of-bounds coordinates are ignored.
  result = 0
  if x >= 0 and y >= 0 and x < cb.w and y < cb.h:
    let idx = (y * cb.w) + x
    let c = addr cb.cells[idx]
    
    # Extract first grapheme and determine width
    var width = 1
    var rune = SpaceRune

    if str.len == 1 and ord(str[0]) < 0x80:
      rune = Rune(ord(str[0]))
      width = 1
    elif str.len > 0:
      # Get first rune to determine width
      let r = str.runeAt(0)
      width = r.runeWidth()
      rune = r

      # For safety, ensure width is 1 or 2
      if width < 1:
        width = 1
      elif width > 2:
        width = 2
    
    # Mark wide character cells dirty if content changes
    if width > 0 and rune != c.currRune:
      c[].setDirty(true)
      for i in 1..<width:
        if x + i < cb.w:
          cb.cells[idx + i].setDirty(true)

    # Merge colors: ColorNone means keep current
    var newStyle = style
    if style.fg.isNone:
      newStyle.fg = c.currStyle.fg
    if style.bg.isNone:
      newStyle.bg = c.currStyle.bg
    
    c.currRune = rune
    c.width = width
    c.currStyle = newStyle
    
    # Clear continuation cells for wide characters to prevent leftover glyphs
    if width > 1:
      for i in 1..<width:
        if x + i < cb.w:
          let cont = addr cb.cells[idx + i]
          cont.currRune = Rune(0)  # Mark as empty/continuation
          cont.width = 0           # Width 0 indicates continuation cell
          cont.currStyle = newStyle
          cont[].setDirty(true)
    
    # If placing narrow char, clear any stale continuation from previous wide
    if width == 1 and c.width > 1:
      # We're overwriting start of a previous wide char - clear its continuations
      let oldWidth = c.width
      for i in 1..<oldWidth:
        if x + i < cb.w:
          let cont = addr cb.cells[idx + i]
          if cont.width == 0 or cont.currRune.int == 0:
            # This was a continuation - clear it
            cont.currRune = SpaceRune
            cont.width = 1
            cont.currStyle = newStyle
            cont[].setDirty(true)
    
    result = width

proc get*(cb: CellBuffer, x, y: int): tuple[str: string,
    style: CellStyle, width: int] =
  ## Get the contents of a character cell.
  ## Returns empty content for out-of-bounds coordinates.
  if x >= 0 and y >= 0 and x < cb.w and y < cb.h:
    let c = cb.cells[(y * cb.w) + x]
    var str = if c.currRune.int == 0:
                " "
              else:
                c.currRune.toUTF8
    var width = c.width
    if width == 0 or str == "":
      width = 1
      str = " "
    result = (str, c.currStyle, width)
  else:
    result = ("", defaultStyle(), 0)

proc getRune*(cb: CellBuffer, x, y: int): tuple[r: Rune,
    style: CellStyle, width: int] =
  ## Get the contents of a character cell.
  ## Returns empty content for out-of-bounds coordinates.
  if x >= 0 and y >= 0 and x < cb.w and y < cb.h:
    let c = cb.cells[(y * cb.w) + x]
    let rune = if c.currRune.int == 0:
                 SpaceRune
               else:
                 c.currRune
    let width = if c.width == 0: 1 else: c.width
    result = (rune, c.currStyle, width)
  else:
    result = (SpaceRune, defaultStyle(), 0)

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
    cb.cells[i].lastRune = Rune(0)

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
    newCells[i].currRune = SpaceRune
    newCells[i].lastRune = Rune(0)
    newCells[i].currStyle = defaultStyle()
    newCells[i].width = 1
  
  # Copy existing content
  for y in 0..<min(h, cb.h):
    for x in 0..<min(w, cb.w):
      let oldIdx = (y * cb.w) + x
      let newIdx = (y * w) + x
      newCells[newIdx].currRune = cb.cells[oldIdx].currRune
      newCells[newIdx].currStyle = cb.cells[oldIdx].currStyle
      newCells[newIdx].width = cb.cells[oldIdx].width
      # Mark as dirty (lastRune remains empty)
  
  cb.cells = newCells
  cb.h = h
  cb.w = w

proc fill*(cb: var CellBuffer, r: Rune, style: CellStyle) =
  ## Fill the entire buffer with a character and style.
  ## Typically used with ' ' to clear the screen.
  ## Does not support combining characters or width > 1.
  for i in 0..<cb.cells.len:
    let c = addr cb.cells[i]
    c.currRune = r
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

# -----------------------------------------------------------------------------
# Helper methods for widget rendering
# -----------------------------------------------------------------------------

proc setString*(cb: var CellBuffer, x, y: int, s: string, 
                style: CellStyle): int =
  ## Write a string at the given position with style.
  ## Returns the number of cells written (accounting for wide chars).
  ## Out-of-bounds text is clipped.
  result = 0
  var currentX = x
  for rune in s.runes:
    if currentX >= cb.w:
      break
    let width = cb.put(currentX, y, rune.toUTF8, style)
    currentX += width
    result += width

proc setStyle*(cb: var CellBuffer, x, y, width, height: int, 
               style: CellStyle) =
  ## Apply style to a rectangular region.
  ## Only modifies style, not content.
  for dy in 0..<height:
    let row = y + dy
    if row < 0 or row >= cb.h:
      continue
    for dx in 0..<width:
      let col = x + dx
      if col < 0 or col >= cb.w:
        continue
      let idx = (row * cb.w) + col
      var cell = addr cb.cells[idx]
      
      # Merge style (respecting None colors)
      if not style.fg.isNone:
        cell.currStyle.fg = style.fg
      if not style.bg.isNone:
        cell.currStyle.bg = style.bg
      # Attrs are additive
      cell.currStyle.attrs = cell.currStyle.attrs + style.attrs

proc fillArea*(cb: var CellBuffer, x, y, width, height: int, 
               char: string, style: CellStyle) =
  ## Fill a rectangular region with a character and style.
  for dy in 0..<height:
    let row = y + dy
    if row < 0 or row >= cb.h:
      continue
    for dx in 0..<width:
      let col = x + dx
      if col < 0 or col >= cb.w:
        continue
      discard cb.put(col, row, char, style)

# Rect-based overloads for convenience
proc setStyle*(cb: var CellBuffer, area: Rect, style: CellStyle) {.inline.} =
  ## Apply style to a rectangular region (using Rect).
  cb.setStyle(area.x, area.y, area.width, area.height, style)

proc fillArea*(cb: var CellBuffer, area: Rect, char: string, 
               style: CellStyle) {.inline.} =
  ## Fill a rectangular region (using Rect).
  cb.fillArea(area.x, area.y, area.width, area.height, char, style)
