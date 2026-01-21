## Table - Multi-column data table widget
##
## Renders a table with headers, multiple columns, and row selection.
## Used for ship lists, fleet lists, and other tabular data.
##
## Example output:
##   Name         Class        State Attack  Defense
##   ─────────────────────────────────────────────────
##   Alpha-1      Destroyer    Nominal 45     38
##   Alpha-2      Destroyer    Nominal 45     38
## > Beta-1       Frigate      Crippled 28   22    <- selected
##
## Reference: ec-style-layout.md Fleet Detail View

import std/[strutils, options]
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
    showSelector*: bool         ## Show > marker for selected row
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
    showSelector: true,
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

proc showSelector*(t: Table, show: bool): Table =
  ## Toggle > selector marker for selected row.
  result = t
  result.showSelector = show

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
  
  # First pass: count fixed widths and auto columns
  for i, col in t.columns:
    if col.width > 0:
      result[i] = col.width
      totalFixed += col.width
    else:
      autoColumns.inc
  
  # Account for selector column and spacing
  let selectorWidth = if t.showSelector: 2 else: 0
  let spacing = t.columns.len - 1  # Space between columns
  let remaining = availableWidth - totalFixed - selectorWidth - spacing
  
  # Second pass: distribute remaining space to auto columns
  if autoColumns > 0 and remaining > 0:
    let autoWidth = remaining div autoColumns
    for i, col in t.columns:
      if col.width == 0:
        result[i] = max(col.minWidth, autoWidth)

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
  
  # Header row
  if t.showHeader:
    var headerLine = ""
    if t.showSelector:
      headerLine.add("  ")  # Empty selector space
    for i, col in t.columns:
      if i > 0:
        headerLine.add(" ")
      headerLine.add(alignText(col.header, colWidths[i], col.align))
    result.add(headerLine)
    
    # Separator
    if t.showSeparator:
      var sepLine = ""
      if t.showSelector:
        sepLine.add("  ")
      for i, w in colWidths:
        if i > 0:
          sepLine.add(" ")
        sepLine.add('-'.repeat(w))
      result.add(sepLine)
  
  # Data rows
  for rowIdx, row in t.rows:
    var rowLine = ""
    let isSelected = rowIdx == t.selectedIdx
    
    if t.showSelector:
      if isSelected:
        rowLine.add("> ")
      else:
        rowLine.add("  ")
    
    for colIdx, cell in row.cells:
      if colIdx >= t.columns.len:
        break
      if colIdx > 0:
        rowLine.add(" ")
      let col = t.columns[colIdx]
      rowLine.add(alignText(cell, colWidths[colIdx], col.align))
    
    result.add(rowLine)

# -----------------------------------------------------------------------------
# Buffer rendering
# -----------------------------------------------------------------------------

proc render*(t: Table, area: Rect, buf: var CellBuffer) =
  ## Render table to buffer at given area.
  if area.isEmpty or t.columns.len == 0:
    return
  
  let colWidths = t.calculateColumnWidths(area.width)
  var y = area.y
  
  # Header row
  if t.showHeader and y < area.bottom:
    var x = area.x
    
    if t.showSelector:
      discard buf.setString(x, y, "  ", t.headerStyle)
      x += 2
    
    for i, col in t.columns:
      if x >= area.right:
        break
      if i > 0:
        discard buf.setString(x, y, " ", t.headerStyle)
        x += 1
      let aligned = alignText(col.header, colWidths[i], col.align)
      discard buf.setString(x, y, aligned, t.headerStyle)
      x += colWidths[i]
    
    y.inc
    
    # Separator line
    if t.showSeparator and y < area.bottom:
      x = area.x
      if t.showSelector:
        discard buf.setString(x, y, "  ", t.separatorStyle)
        x += 2
      
      for i, w in colWidths:
        if x >= area.right:
          break
        if i > 0:
          discard buf.setString(x, y, " ", t.separatorStyle)
          x += 1
        # Use box drawing light horizontal line
        let sep = "\u2500".repeat(w)
        discard buf.setString(x, y, sep, t.separatorStyle)
        x += w
      
      y.inc
  
  # Data rows
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
    
    # Selector marker
    if t.showSelector:
      let marker = if isSelected: "> " else: "  "
      discard buf.setString(x, y, marker, style)
      x += 2
    
    # Row cells
    for colIdx, cell in row.cells:
      if colIdx >= t.columns.len or x >= area.right:
        break
      let cellStyle =
        if colIdx < row.cellStyles.len and row.cellStyles[colIdx].isSome:
          row.cellStyles[colIdx].get()
        else:
          style
      if colIdx > 0:
        discard buf.setString(x, y, " ", cellStyle)
        x += 1
      
      let col = t.columns[colIdx]
      let aligned = alignText(cell, colWidths[colIdx], col.align)
      discard buf.setString(x, y, aligned, cellStyle)
      x += colWidths[colIdx]
    
    y.inc

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
