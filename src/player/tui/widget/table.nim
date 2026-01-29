## Table - Multi-column data table widget
##
## Renders a table with headers, multiple columns, and row selection.
## Used for ship lists, fleet lists, and other tabular data.
##
## Example output:
##   ┌─────────┬─────┬──────┐
##   │ Name    │ Age │ City │
##   ├─────────┼─────┼──────┤
##   │ Alice   │  30 │ PDX  │
##   │ Bob     │  25 │ SEA  │
##   └─────────┴─────┴──────┘
##
## Reference: ec-style-layout.md Fleet Detail View

import std/[strutils, options, unicode]
import ../buffer
import ../layout/rect
import ../styles/ec_palette

type
  Alignment* {.pure.} = enum
    ## Column alignment.
    Left
    Right
    Center

  TableColumn* = object
    ## Column definition.
    header*: string
    width*: int           ## Fixed width (0 = auto)
    align*: Alignment     ## Content alignment
    minWidth*: int        ## Minimum width if auto

  TableRow* = object
    ## A single row of cell values.
    cells*: seq[string]
    cellStyles*: seq[Option[CellStyle]]

  Table* = object
    ## Table widget configuration.
    columns*: seq[TableColumn]
    rows*: seq[TableRow]
    selectedIdx*: int           ## Selected row index (-1 for none)
    headerStyle*: CellStyle     ## Style for header row
    rowStyle*: CellStyle        ## Style for normal rows
    selectedStyle*: CellStyle   ## Style for selected row
    alternateStyle*: CellStyle  ## Style for alternate rows (optional zebra)
    separatorStyle*: CellStyle  ## Style for separator line
    showHeader*: bool           ## Show header row
    showSeparator*: bool        ## Show separator line under header
    zebraStripe*: bool          ## Alternate row colors

# -----------------------------------------------------------------------------
# Constructors
# -----------------------------------------------------------------------------

proc tableColumn*(
  header: string,
  width: int = 0,
  align: Alignment = Alignment.Left,
  minWidth: int = 4
): TableColumn =
  ## Create a column definition.
  TableColumn(
    header: header,
    width: width,
    align: align,
    minWidth: minWidth
  )

proc table*(columns: openArray[TableColumn]): Table =
  ## Create a table with column definitions.
  Table(
    columns: @columns,
    rows: @[],
    selectedIdx: -1,
    headerStyle: canvasHeaderStyle(),
    rowStyle: canvasStyle(),
    selectedStyle: selectedStyle(),
    alternateStyle: canvasStyle(),
    separatorStyle: canvasDimStyle(),
    showHeader: true,
    showSeparator: true,
    zebraStripe: false
  )

# -----------------------------------------------------------------------------
# Builder methods
# -----------------------------------------------------------------------------

proc rows*(t: Table, rows: openArray[TableRow]): Table =
  ## Set table rows.
  result = t
  result.rows = @rows

proc addRow*(t: var Table, row: TableRow) =
  ## Add a row to the table.
  t.rows.add(row)

proc addRow*(t: var Table, cells: openArray[string]) =
  ## Add a row from cell values.
  t.rows.add(TableRow(cells: @cells, cellStyles: @[]))

proc addRow*(t: var Table, cells: openArray[string],
             style: CellStyle, styleColumn: int) =
  ## Add a row with a custom style for one column.
  var cellStyles: seq[Option[CellStyle]] = @[]
  cellStyles.setLen(cells.len)
  if styleColumn >= 0 and styleColumn < cellStyles.len:
    cellStyles[styleColumn] = some(style)
  t.rows.add(TableRow(cells: @cells, cellStyles: cellStyles))

proc selectedIdx*(t: Table, idx: int): Table =
  ## Set selected row index (-1 for no selection).
  result = t
  result.selectedIdx = idx

proc headerStyle*(t: Table, style: CellStyle): Table =
  ## Set header row style.
  result = t
  result.headerStyle = style

proc rowStyle*(t: Table, style: CellStyle): Table =
  ## Set normal row style.
  result = t
  result.rowStyle = style

proc selectedStyle*(t: Table, style: CellStyle): Table =
  ## Set selected row style.
  result = t
  result.selectedStyle = style

proc showHeader*(t: Table, show: bool): Table =
  ## Toggle header row visibility.
  result = t
  result.showHeader = show

proc showSeparator*(t: Table, show: bool): Table =
  ## Toggle separator line visibility.
  result = t
  result.showSeparator = show

proc zebraStripe*(t: Table, enable: bool): Table =
  ## Enable alternating row colors.
  result = t
  result.zebraStripe = enable

proc alternateStyle*(t: Table, style: CellStyle): Table =
  ## Set alternate row style (for zebra striping).
  result = t
  result.alternateStyle = style

# -----------------------------------------------------------------------------
# Column width calculation
# -----------------------------------------------------------------------------

proc calculateColumnWidths*(t: Table, availableWidth: int): seq[int] =
  ## Calculate actual column widths based on available space.
  result = newSeq[int](t.columns.len)
  var totalFixed = 0
  var autoColumns = 0
  var minWidths = newSeq[int](t.columns.len)
  var minTotal = 0
  var minAutoTotal = 0
  var fixedIndices: seq[int] = @[]
  var autoIndices: seq[int] = @[]
  
  # First pass: collect fixed widths, min widths, and auto columns
  for i, col in t.columns:
    let minWidth = max(1, col.minWidth)
    minWidths[i] = minWidth
    minTotal += minWidth
    if col.width > 0:
      result[i] = max(col.width, minWidth)
      totalFixed += result[i]
      fixedIndices.add(i)
    else:
      result[i] = minWidth
      autoColumns.inc
      minAutoTotal += minWidth
      autoIndices.add(i)
  
  # Account for borders and padding (box table)
  let borderWidth = t.columns.len + 1  # vertical separators
  let paddingWidth = t.columns.len * 2  # left/right padding per cell
  let availableContent = availableWidth - borderWidth - paddingWidth
  if availableContent <= 0:
    for i in 0 ..< t.columns.len:
      result[i] = 1
    return
  if availableContent < minTotal:
    for i in 0 ..< t.columns.len:
      result[i] = 1
    return

  let availableForFixed = availableContent - minAutoTotal
  if totalFixed > availableForFixed:
    var overflow = totalFixed - availableForFixed
    var canReduce = true
    while overflow > 0 and canReduce:
      canReduce = false
      for idx in fixedIndices:
        let minWidth = minWidths[idx]
        if result[idx] > minWidth and overflow > 0:
          result[idx].dec
          overflow.dec
          canReduce = true
    totalFixed = 0
    for idx in fixedIndices:
      totalFixed += result[idx]

  let remaining = availableContent - (totalFixed + minAutoTotal)
  
  # Second pass: distribute remaining space to auto columns
  if autoColumns > 0 and remaining > 0:
    let autoWidth = remaining div autoColumns
    var extra = remaining mod autoColumns
    for idx in autoIndices:
      result[idx] += autoWidth
      if extra > 0:
        result[idx].inc
        extra.dec

# -----------------------------------------------------------------------------
# Text alignment helper
# -----------------------------------------------------------------------------

proc alignText(text: string, width: int, align: Alignment): string =
  ## Align text within a fixed width, truncating if needed.
  let textLen = text.len
  if textLen >= width:
    return text[0 ..< width]
  
  let padding = width - textLen
  case align
  of Alignment.Left:
    result = text & ' '.repeat(padding)
  of Alignment.Right:
    result = ' '.repeat(padding) & text
  of Alignment.Center:
    let leftPad = padding div 2
    let rightPad = padding - leftPad
    result = ' '.repeat(leftPad) & text & ' '.repeat(rightPad)

# -----------------------------------------------------------------------------
# String rendering (for simple use cases)
# -----------------------------------------------------------------------------

proc renderToStrings*(t: Table, width: int = 60): seq[string] =
  ## Render table to sequence of strings.
  result = @[]
  let colWidths = t.calculateColumnWidths(width)

  if t.columns.len == 0:
    return

  proc borderLine(left, mid, right: string): string =
    var line = left
    for i, w in colWidths:
      if i > 0:
        line.add(mid)
      line.add("\u2500".repeat(w + 2))
    line.add(right)
    line

  result.add(borderLine("\u250c", "\u252c", "\u2510"))

  if t.showHeader:
    var headerLine = "\u2502"
    for i, col in t.columns:
      let aligned = alignText(col.header, colWidths[i], col.align)
      headerLine.add(" " & aligned & " ")
      headerLine.add("\u2502")
    result.add(headerLine)

    if t.showSeparator:
      result.add(borderLine("\u251c", "\u253c", "\u2524"))

  for row in t.rows:
    var rowLine = "\u2502"
    for colIdx, col in t.columns:
      let cell = if colIdx < row.cells.len: row.cells[colIdx] else: ""
      let aligned = alignText(cell, colWidths[colIdx], col.align)
      rowLine.add(" " & aligned & " ")
      rowLine.add("\u2502")
    result.add(rowLine)

  result.add(borderLine("\u2514", "\u2534", "\u2518"))

# -----------------------------------------------------------------------------
# Buffer rendering
# -----------------------------------------------------------------------------

proc render*(t: Table, area: Rect, buf: var CellBuffer) =
  ## Render table to buffer at given area.
  if area.isEmpty or t.columns.len == 0:
    return

  let colWidths = t.calculateColumnWidths(area.width)
  var y = area.y

  template putSegment(xVar: var int, segment: string, style: CellStyle) =
    if xVar >= area.right:
      discard
    else:
      var currentX = xVar
      for rune in segment.runes:
        if currentX >= area.right:
          break
        let width = buf.put(currentX, y, rune.toUTF8, style)
        currentX += width
      xVar = currentX

  template drawBorderLine(left, mid, right: string) =
    if y >= area.bottom:
      discard
    else:
      var x = area.x
      putSegment(x, left, t.separatorStyle)
      for i, w in colWidths:
        for _ in 0 ..< w + 2:
          putSegment(x, "\u2500", t.separatorStyle)
        if i < colWidths.len - 1:
          putSegment(x, mid, t.separatorStyle)
      putSegment(x, right, t.separatorStyle)
      y.inc

  drawBorderLine("\u250c", "\u252c", "\u2510")
  if y >= area.bottom:
    return

  if t.showHeader:
    var x = area.x
    putSegment(x, "\u2502", t.separatorStyle)
    for i, col in t.columns:
      let aligned = alignText(col.header, colWidths[i], col.align)
      putSegment(x, " ", t.headerStyle)
      putSegment(x, aligned, t.headerStyle)
      putSegment(x, " ", t.headerStyle)
      putSegment(x, "\u2502", t.separatorStyle)
    y.inc

    if t.showSeparator:
      drawBorderLine("\u251c", "\u253c", "\u2524")
      if y >= area.bottom:
        return

  for rowIdx, row in t.rows:
    if y >= area.bottom:
      break
    let isSelected = rowIdx == t.selectedIdx
    let isAlternate = t.zebraStripe and rowIdx mod 2 == 1
    let style = if isSelected:
      t.selectedStyle
    elif isAlternate:
      t.alternateStyle
    else:
      t.rowStyle

    var x = area.x
    putSegment(x, "\u2502", t.separatorStyle)
    for colIdx, col in t.columns:
      let cell = if colIdx < row.cells.len: row.cells[colIdx] else: ""
      let cellStyle =
        if colIdx < row.cellStyles.len and row.cellStyles[colIdx].isSome:
          row.cellStyles[colIdx].get()
        else:
          style
      let aligned = alignText(cell, colWidths[colIdx], col.align)
      putSegment(x, " ", cellStyle)
      putSegment(x, aligned, cellStyle)
      putSegment(x, " ", cellStyle)
      putSegment(x, "\u2502", t.separatorStyle)

    y.inc
    if y >= area.bottom:
      break

  drawBorderLine("\u2514", "\u2534", "\u2518")

# -----------------------------------------------------------------------------
# Convenience constructors for common use cases
# -----------------------------------------------------------------------------

proc shipListTable*(): Table =
  ## Create a table for ship lists in Fleet Detail view.
  table([
    tableColumn("Name", width = 12, align = Alignment.Left),
    tableColumn("Class", width = 12, align = Alignment.Left),
    tableColumn("State", width = 9, align = Alignment.Left),
    tableColumn("Atk", width = 5, align = Alignment.Right),
    tableColumn("Def", width = 5, align = Alignment.Right)
  ])

proc fleetListTable*(): Table =
  ## Create a table for fleet lists.
  table([
    tableColumn("Fleet", width = 10, align = Alignment.Left),
    tableColumn("Location", width = 15, align = Alignment.Left),
    tableColumn("Ships", width = 6, align = Alignment.Right),
    tableColumn("Command", width = 12, align = Alignment.Left)
  ])

proc colonyListTable*(): Table =
  ## Create a table for colony lists.
  table([
    tableColumn("Colony", width = 14, align = Alignment.Left),
    tableColumn("Pop", width = 6, align = Alignment.Right),
    tableColumn("Prod", width = 6, align = Alignment.Right),
    tableColumn("Status", width = 10, align = Alignment.Left)
  ])

proc constructionQueueTable*(): Table =
  ## Create a table for construction queue.
  table([
    tableColumn("#", width = 2, align = Alignment.Right),
    tableColumn("Item", width = 14, align = Alignment.Left),
    tableColumn("Progress", width = 12, align = Alignment.Left),
    tableColumn("ETA", width = 8, align = Alignment.Right)
  ])
