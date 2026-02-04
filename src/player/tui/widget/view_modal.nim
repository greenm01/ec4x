## View Modal - Reusable wrapper for primary views as floating centered modals
##
## Wraps the existing Modal widget to provide consistent modal-based rendering
## for all 9 primary views, converting them from full-canvas to centered floating windows.
##
## Features:
## - Centers within canvas, leaving HUD/breadcrumb/dock visible
## - Width: 120 columns max (80 min for fallback)
## - Height: content-based, not full vertical
## - Consistent border styling across all views

import ./modal
import ./scroll_state
import ./scrollbar
import ../buffer
import ../layout/rect
import ../styles/ec_palette

export scroll_state, scrollbar

type
  ViewModal* = object
    ## Wrapper for primary view modals
    modal: Modal
    contentHeight: int
    enableScrollbar: bool

proc newViewModal*(title: string): ViewModal =
  ## Create a new view modal with default settings
  ViewModal(
    modal: newModal()
      .title(title)
      .maxWidth(120)
      .minWidth(80)
      .minHeight(10)
      .borderStyle(primaryBorderStyle())
      .bgStyle(modalBgStyle()),
    contentHeight: 0,
    enableScrollbar: false
  )

# Builder methods (fluent API)

proc maxWidth*(vm: ViewModal, w: int): ViewModal =
  ## Set maximum width
  result = vm
  result.modal = vm.modal.maxWidth(w)

proc minWidth*(vm: ViewModal, w: int): ViewModal =
  ## Set minimum width
  result = vm
  result.modal = vm.modal.minWidth(w)

proc contentHeight*(vm: ViewModal, h: int): ViewModal =
  ## Set content height for area calculation
  result = vm
  result.contentHeight = h

proc withScrollbar*(vm: ViewModal): ViewModal =
  ## Enable scrollbar rendering
  result = vm
  result.enableScrollbar = true

proc calculateViewArea*(vm: ViewModal, canvas: Rect, contentHeight: int): Rect =
  ## Calculate the modal's area within the canvas.
  ## Centers the modal and respects width/height constraints.
  vm.modal.calculateArea(canvas, contentHeight)

proc innerArea*(vm: ViewModal, modalArea: Rect): Rect =
  ## Get the inner content area (excluding borders)
  vm.modal.inner(modalArea)

proc render*(vm: ViewModal, area: Rect, buf: var CellBuffer) =
  ## Render the modal frame (border and title)
  vm.modal.render(area, buf)

proc renderWithScrollbar*(vm: ViewModal, area: Rect, buf: var CellBuffer,
                          scroll: ScrollState) =
  ## Render the modal frame with a scrollbar
  vm.modal.render(area, buf)

  if vm.enableScrollbar:
    let inner = vm.innerArea(area)
    let scrollbarState = ScrollbarState(
      contentLength: scroll.contentLength,
      position: scroll.verticalOffset,
      viewportLength: scroll.viewportLength
    )
    renderScrollbar(inner, buf, scrollbarState, ScrollbarOrientation.VerticalRight)

proc renderFooter*(vm: ViewModal, area: Rect, buf: var CellBuffer,
                   footerText: string) =
  ## Render a footer hint line at the bottom of the modal
  ## Typically used for context-specific keybinding hints
  let inner = vm.innerArea(area)
  let footerY = inner.bottom - 1
  if footerY >= inner.y and footerY < area.bottom:
    discard buf.setString(inner.x, footerY, footerText, canvasDimStyle())
