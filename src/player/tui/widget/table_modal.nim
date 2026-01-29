##
## TableModal renders a centered, modal-like table with a title
## embedded in the top border line.
##

import std/unicode
import ../buffer
import ../layout/rect
import ../styles/ec_palette
import ./table

type
  TableModal* = object
    title*: string
    maxWidth*: int
    minWidth*: int
    maxHeight*: int
    minHeight*: int
    titleStyle*: CellStyle
    bgStyle*: CellStyle

proc newTableModal*(title: string): TableModal =
  ## Create a new table modal with default settings
  TableModal(
    title: title,
    maxWidth: 120,
    minWidth: 80,
    maxHeight: 60,
    minHeight: 10,
    titleStyle: canvasHeaderStyle(),
    bgStyle: modalBgStyle()
  )

proc maxWidth*(tm: TableModal, w: int): TableModal =
  ## Set maximum width
  result = tm
  result.maxWidth = w

proc minWidth*(tm: TableModal, w: int): TableModal =
  ## Set minimum width
  result = tm
  result.minWidth = w

proc minHeight*(tm: TableModal, h: int): TableModal =
  ## Set minimum height
  result = tm
  result.minHeight = h

proc maxHeight*(tm: TableModal, h: int): TableModal =
  ## Set maximum height
  result = tm
  result.maxHeight = h

proc calculateArea*(tm: TableModal, viewport: Rect,
    contentWidth: int, contentHeight: int): Rect =
  ## Calculate modal area within viewport (tight to content)
  let maxWidth = min(viewport.width - 2, tm.maxWidth)
  let maxHeight = min(viewport.height - 2, tm.maxHeight)
  let width = max(1, min(contentWidth, maxWidth))
  let height = max(1, min(contentHeight, maxHeight))
  let x = viewport.x + (viewport.width - width) div 2
  let y = viewport.y + (viewport.height - height) div 2
  rect(x, y, width, height)

proc render*(tm: TableModal, area: Rect, buf: var CellBuffer,
    table: Table) =
  ## Render a table modal with the title embedded in the top border
  if area.isEmpty:
    return

  buf.fillArea(area, " ", tm.bgStyle)
  table.render(area, buf)

  if tm.title.len == 0 or area.width < 4:
    return

  let titleText = " " & tm.title & " "
  let maxTitleWidth = area.width - 2
  let titleWidth = min(titleText.len, maxTitleWidth)
  let startX = area.x + 1 + max(0, (maxTitleWidth - titleWidth) div 2)
  var currentX = startX
  for r in titleText.runes:
    if currentX >= startX + titleWidth:
      break
    let width = buf.put(currentX, area.y, r.toUTF8, tm.titleStyle)
    currentX += width
