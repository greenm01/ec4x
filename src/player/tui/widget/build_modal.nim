## Build Modal - Modal for issuing build commands
##
## A modal popup for browsing categorized build options, adding items to a
## pending queue, and confirming to stage them for turn submission.

import ./modal
import ./borders
import ./text/text_pkg
import ../buffer
import ../layout/rect
import ../styles/ec_palette
import ../../sam/tui_model

type
  BuildModalWidget* = object
    modal: Modal

proc newBuildModalWidget*(): BuildModalWidget =
  ## Create a new build modal widget
  BuildModalWidget(
    modal: newModal()
      .maxWidth(80)
      .minWidth(60)
      .minHeight(20)
  )

proc renderCategoryTabs(state: BuildModalState, area: Rect,
                       buf: var CellBuffer) =
  ## Render category tabs at the top of the modal
  if area.isEmpty:
    return

  var x = area.x
  let y = area.y

  # Tab labels
  let tabs = [
    ("Ships", BuildCategory.Ships),
    ("Facilities", BuildCategory.Facilities),
    ("Ground", BuildCategory.Ground)
  ]

  for (label, category) in tabs:
    let isSelected = state.category == category
    let style = if isSelected:
      canvasHeaderStyle()
    else:
      modalBgStyle()

    let tabText = if isSelected: "[" & label & "]" else: " " & label & " "
    for i, ch in tabText:
      if x + i < area.right:
        discard buf.put(x + i, y, $ch, style)
    x += tabText.len + 1

proc renderDockSummary(state: BuildModalState, area: Rect,
                      buf: var CellBuffer) =
  ## Render dock capacity summary
  if area.isEmpty:
    return

  let docks = state.dockSummary
  let text = "Docks: " & $docks.constructionAvailable & "/" &
    $docks.constructionTotal & " CDK | " &
    $docks.repairAvailable & "/" & $docks.repairTotal & " RDK"

  for i, ch in text:
    if area.x + i < area.right:
      discard buf.put(area.x + i, area.y, $ch, canvasDimStyle())

proc renderBuildList(state: BuildModalState, area: Rect,
                    buf: var CellBuffer) =
  ## Render available build options list
  if area.isEmpty:
    return

  # Header
  let headerText = "AVAILABLE"
  for i, ch in headerText:
    if area.x + i < area.right:
      discard buf.put(area.x + i, area.y, $ch, canvasHeaderStyle())

  # List items
  let listArea = rect(area.x, area.y + 1, area.width, area.height - 1)
  var y = listArea.y

  for idx, option in state.availableOptions:
    if y >= listArea.bottom:
      break

    let isSelected = state.focus == BuildModalFocus.BuildList and
                    idx == state.selectedBuildIdx
    let prefix = if isSelected: "► " else: "  "
    let text = prefix & option.name & " " & $option.cost

    let style = if isSelected:
      selectedStyle()
    else:
      canvasStyle()

    for i, ch in text:
      if area.x + i < area.right:
        discard buf.put(area.x + i, y, $ch, style)

    y += 1

proc renderQueue(state: BuildModalState, area: Rect,
                buf: var CellBuffer) =
  ## Render pending build queue
  if area.isEmpty:
    return

  # Header
  let headerText = "QUEUE (" & $state.pendingQueue.len & ")"
  for i, ch in headerText:
    if area.x + i < area.right:
      discard buf.put(area.x + i, area.y, $ch, canvasHeaderStyle())

  # Queue items
  let listArea = rect(area.x, area.y + 1, area.width, area.height - 3)
  var y = listArea.y
  var totalCost = 0

  for idx, item in state.pendingQueue:
    if y >= listArea.bottom:
      break

    let isSelected = state.focus == BuildModalFocus.QueueList and
                    idx == state.selectedQueueIdx
    let prefix = if isSelected: "► " else: "  "
    let quantityText = if item.quantity > 1: " ×" & $item.quantity else: ""
    let itemCost = item.cost * item.quantity
    let text = prefix & item.name & quantityText & " " & $itemCost

    let style = if isSelected:
      selectedStyle()
    else:
      canvasStyle()

    for i, ch in text:
      if area.x + i < area.right:
        discard buf.put(area.x + i, y, $ch, style)

    totalCost += itemCost
    y += 1

  # Total cost
  y = listArea.bottom
  if y < area.bottom:
    let totalText = "TOTAL: " & $totalCost & " CR"
    for i, ch in totalText:
      if area.x + i < area.right:
        discard buf.put(area.x + i, y, $ch, alertStyle())

proc renderFooter(state: BuildModalState, area: Rect,
                 buf: var CellBuffer) =
  ## Render quantity editor and hints
  if area.isEmpty:
    return

  var text = ""

  # Quantity selector for ships
  if state.category == BuildCategory.Ships:
    text = "Qty: ◄ " & $state.quantityInput & " ► "
  else:
    text = "           "

  # Action hints
  text &= "[Tab]Cat [Enter]Add [Q]Done"

  for i, ch in text:
    if area.x + i < area.right:
      discard buf.put(area.x + i, area.y, $ch, canvasDimStyle())

proc render*(widget: BuildModalWidget, state: BuildModalState,
            viewport: Rect, buf: var CellBuffer) =
  ## Render the build modal
  if not state.active:
    return

  # Calculate modal area
  let contentHeight = 18  # Approximate content height
  let modalArea = widget.modal.calculateArea(viewport, contentHeight)

  # Render modal frame with title
  let title = "BUILD - " & state.colonyName
  widget.modal.title(title).renderWithSeparator(modalArea, buf, 2)

  # Get inner content area
  let inner = widget.modal.inner(modalArea)

  # Layout sections
  let tabsArea = rect(inner.x, inner.y, inner.width, 1)
  let docksArea = rect(inner.x, inner.y + 1, inner.width, 1)
  let separatorY = inner.y + 2

  # Draw separator line after header
  let glyphs = widget.modal.separatorGlyphs()
  discard buf.put(modalArea.x, separatorY, glyphs.left,
    modalBorderStyle())
  for x in (modalArea.x + 1)..<(modalArea.right - 1):
    discard buf.put(x, separatorY, glyphs.horizontal,
      modalBorderStyle())
  discard buf.put(modalArea.right - 1, separatorY, glyphs.right,
    modalBorderStyle())

  # Content area (build list and queue)
  let contentArea = rect(inner.x, separatorY + 1, inner.width,
                        inner.height - 5)

  # Split content area into two columns
  let leftWidth = contentArea.width div 2
  let rightWidth = contentArea.width - leftWidth - 1

  let buildListArea = rect(contentArea.x, contentArea.y, leftWidth,
                          contentArea.height)
  let queueArea = rect(contentArea.x + leftWidth + 1, contentArea.y,
                      rightWidth, contentArea.height)

  # Draw vertical separator between columns
  for y in contentArea.y..<contentArea.bottom:
    discard buf.put(contentArea.x + leftWidth, y, "│", modalBorderStyle())

  # Footer area (above the bottom separator)
  let footerArea = rect(inner.x, inner.bottom - 1, inner.width, 1)

  # Render all sections
  renderCategoryTabs(state, tabsArea, buf)
  renderDockSummary(state, docksArea, buf)
  renderBuildList(state, buildListArea, buf)
  renderQueue(state, queueArea, buf)
  renderFooter(state, footerArea, buf)
