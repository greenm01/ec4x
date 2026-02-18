## Modal - Centered overlay modal widget
##
## A modal is a centered overlay that appears on top of other content.
## Used for dialogs, entry screens, and confirmations.
##
## Features:
## - Automatically centers within the given area
## - Configurable border style (default: Double)
## - Optional title bar with centered title
## - Calculates max width as min(termWidth - 4, maxWidth)

import std/options
import ./frame
import ./borders
import ./text/text_pkg
import ../buffer
import ../layout/rect
import ../styles/ec_palette

type
  Modal* = object
    ## Centered modal overlay widget.
    title: Option[string]
    titleStyle: CellStyle
    borderStyle: CellStyle
    bgStyle: CellStyle
    borderType: BorderType
    maxWidth: int
    minWidth: int
    minHeight: int
    showBackdrop: bool
    backdropStyle: CellStyle
    backdropMargin: int

proc newModal*(): Modal =
  ## Create a new modal with default styling.
  Modal(
    title: none(string),
    titleStyle: canvasHeaderStyle(),
    borderStyle: modalBorderStyle(),
    bgStyle: modalBgStyle(),
    borderType: BorderType.Double,
    maxWidth: 72,
    minWidth: 40,
    minHeight: 10,
    showBackdrop: false,
    backdropStyle: modalDimOverlayStyle(),
    backdropMargin: 1
  )

# Builder methods (fluent API)

proc title*(m: Modal, t: string): Modal =
  ## Set the modal title.
  result = m
  result.title = some(t)

proc titleStyle*(m: Modal, s: CellStyle): Modal =
  ## Set the title style.
  result = m
  result.titleStyle = s

proc borderStyle*(m: Modal, s: CellStyle): Modal =
  ## Set the border style.
  result = m
  result.borderStyle = s

proc borderType*(m: Modal, bt: BorderType): Modal =
  ## Set the border type.
  result = m
  result.borderType = bt

proc borderType*(m: Modal): BorderType =
  ## Get the border type.
  m.borderType

proc separatorGlyphs*(m: Modal): tuple[left, right, horizontal: string] =
  ## Separator line glyphs to use inside a modal.
  ## Keeps interior separators single-line even for double borders.
  if m.borderType == BorderType.Double:
    return ("╟", "╢", "─")
  let bs = m.borderType.borderSet()
  (left: "├", right: "┤", horizontal: bs.horizontal)

proc bgStyle*(m: Modal, s: CellStyle): Modal =
  ## Set the background style.
  result = m
  result.bgStyle = s

proc showBackdrop*(m: Modal, enabled: bool): Modal =
  ## Enable/disable dimmed backdrop behind modal.
  result = m
  result.showBackdrop = enabled

proc backdropStyle*(m: Modal, s: CellStyle): Modal =
  ## Set backdrop style.
  result = m
  result.backdropStyle = s

proc backdropMargin*(m: Modal, margin: int): Modal =
  ## Set backdrop margin around modal bounds.
  result = m
  result.backdropMargin = max(0, margin)

proc maxWidth*(m: Modal, w: int): Modal =
  ## Set maximum width.
  result = m
  result.maxWidth = w

proc minWidth*(m: Modal, w: int): Modal =
  ## Set minimum width.
  result = m
  result.minWidth = w

proc minHeight*(m: Modal, h: int): Modal =
  ## Set minimum height.
  result = m
  result.minHeight = h

proc calculateArea*(m: Modal, viewport: Rect, contentHeight: int): Rect =
  ## Calculate the modal's area within the viewport (height-only version).
  ## Centers the modal and respects min/max constraints.
  ## Width is determined by maxWidth setting.
  
  # Calculate width: min(viewport.width - 4, maxWidth), clamped to minWidth
  let effectiveMaxWidth = min(viewport.width - 4, m.maxWidth)
  let width = max(m.minWidth, effectiveMaxWidth)
  
  # Calculate height: contentHeight + 2 for borders, clamped to minHeight
  let height = max(m.minHeight, contentHeight + 2)
  
  # Center within viewport
  let x = viewport.x + (viewport.width - width) div 2
  let y = viewport.y + (viewport.height - height) div 2
  
  rect(x, y, width, height)

proc calculateArea*(m: Modal, viewport: Rect,
                    contentWidth: int, contentHeight: int): Rect =
  ## Calculate the modal's area within the viewport (content-aware version).
  ## Centers the modal and sizes it to fit actual content dimensions.
  ## Both width and height are based on content size.
  
  # Width: content + 2 (borders), clamped to viewport and min/max
  let desiredWidth = contentWidth + 2
  let maxAvailableWidth = viewport.width - 4
  let width = clamp(desiredWidth, m.minWidth,
                    min(maxAvailableWidth, m.maxWidth))
  
  # Height: content + 2 (borders), clamped to viewport and minHeight
  let maxAvailableHeight = viewport.height - 2
  let height = clamp(contentHeight + 2, m.minHeight, maxAvailableHeight)
  
  # Center within viewport
  let x = viewport.x + (viewport.width - width) div 2
  let y = viewport.y + (viewport.height - height) div 2
  
  rect(x, y, width, height)

proc inner*(m: Modal, modalArea: Rect): Rect =
  ## Get the inner content area (excluding borders).
  rect(
    modalArea.x + 1,
    modalArea.y + 1,
    modalArea.width - 2,
    modalArea.height - 2
  )

proc renderBackdrop(m: Modal, area: Rect, buf: var CellBuffer) =
  ## Render dim backdrop around modal bounds.
  if not m.showBackdrop:
    return
  let expanded = area.inflate(m.backdropMargin, m.backdropMargin)
  let clipped = expanded.clampTo(rect(0, 0, buf.w, buf.h))
  if clipped.isEmpty:
    return
  buf.fillArea(clipped, " ", m.backdropStyle)

proc render*(m: Modal, area: Rect, buf: var CellBuffer) =
  ## Render the modal frame (border and background).
  ## Content should be rendered separately in the inner area.
  
  if area.isEmpty:
    return

  m.renderBackdrop(area, buf)
  
  # Fill background
  for pos in area.positions:
    discard buf.put(pos.x, pos.y, " ", m.bgStyle)
  
  # Create frame with modal border type
  var frame = bordered()
    .borderStyle(m.borderStyle)
    .borderType(m.borderType)
  
  # Add title if present
  if m.title.isSome:
    let titleLine = line(span(" " & m.title.get & " ", m.titleStyle)).center()
    frame = frame.title(titleLine)
  
  frame.render(area, buf)

proc renderWithSeparator*(m: Modal, area: Rect, buf: var CellBuffer,
                          footerHeight: int) =
  ## Render the modal with a horizontal separator above the footer.
  ## footerHeight is the number of rows for the footer section.
  
  m.render(area, buf)
  
  if footerHeight > 0 and area.height > footerHeight + 2:
    # Draw separator line
    let sepY = area.bottom - footerHeight - 1
    let glyphs = m.separatorGlyphs()
    
    # Left junction
    discard buf.put(area.x, sepY, glyphs.left, m.borderStyle)
    # Horizontal line
    for x in (area.x + 1)..<(area.right - 1):
      discard buf.put(x, sepY, glyphs.horizontal, m.borderStyle)
    # Right junction
    discard buf.put(area.right - 1, sepY, glyphs.right, m.borderStyle)

proc renderWithFooter*(m: Modal, area: Rect, buf: var CellBuffer,
                       footerText: string) =
  ## Render modal border with title, separator, and footer text
  ## This is a convenience wrapper around renderWithSeparator that also
  ## renders the footer text in the bottom section
  m.renderWithSeparator(area, buf, 2)
  let inner = m.inner(area)
  var clipped = footerText
  if clipped.len > inner.width:
    clipped = clipped[0 ..< inner.width]
  discard buf.setString(inner.x, inner.bottom - 1, clipped, canvasDimStyle())

proc contentArea*(m: Modal, area: Rect, hasFooter: bool): Rect =
  ## Get area for content rendering
  ## If hasFooter, reserves 2 lines at bottom for separator + footer text
  ## Otherwise returns full inner area
  let inner = m.inner(area)
  if hasFooter:
    rect(inner.x, inner.y, inner.width, max(1, inner.height - 2))
  else:
    inner
