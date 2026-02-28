## Queue Modal - Modal for viewing staged build orders
##
## Shows staged build commands for the selected colony and allows
## deleting staged items.

import std/options

import ./modal
import ./table
import ./scroll_state
import ../buffer
import ../layout/rect
import ../styles/ec_palette
import ../build_spec
import ../table_layout_policy
import ../../sam/tui_model
import ../../../engine/types/[core, production, ship, ground_unit, facilities]
import ../columns

type
  QueueModalWidget* = object
    modal: Modal

  QueueRow = object
    kindLabel: string
    itemLabel: string
    qty: int
    totalCost: int
    status: string

proc newQueueModalWidget*(): QueueModalWidget =
  QueueModalWidget(
    modal: newModal()
      .maxWidth(80)
      .minWidth(60)
      .minHeight(10)
      .showBackdrop(true)
  )

proc humanizeEnum(name: string): string =
  result = ""
  for idx, ch in name:
    if idx > 0 and ch >= 'A' and ch <= 'Z':
      let prev = name[idx - 1]
      if prev >= 'a' and prev <= 'z':
        result.add(' ')
    result.add(ch)

proc rowForCommand(cmd: BuildCommand): QueueRow =
  var kindLabel = "Other"
  var itemLabel = "Unknown"
  var cost = 0
  case cmd.buildType
  of BuildType.Ship:
    kindLabel = "Ship"
    if cmd.shipClass.isSome:
      itemLabel = humanizeEnum($cmd.shipClass.get())
      cost = buildRowCost(BuildRowKey(
        kind: BuildOptionKind.Ship,
        shipClass: cmd.shipClass,
        groundClass: none(GroundClass),
        facilityClass: none(FacilityClass)
      ))
  of BuildType.Ground:
    kindLabel = "Ground"
    if cmd.groundClass.isSome:
      itemLabel = humanizeEnum($cmd.groundClass.get())
      cost = buildRowCost(BuildRowKey(
        kind: BuildOptionKind.Ground,
        shipClass: none(ShipClass),
        groundClass: cmd.groundClass,
        facilityClass: none(FacilityClass)
      ))
  of BuildType.Facility:
    kindLabel = "Facility"
    if cmd.facilityClass.isSome:
      itemLabel = humanizeEnum($cmd.facilityClass.get())
      cost = buildRowCost(BuildRowKey(
        kind: BuildOptionKind.Facility,
        shipClass: none(ShipClass),
        groundClass: none(GroundClass),
        facilityClass: cmd.facilityClass
      ))
  else:
    discard
  QueueRow(
    kindLabel: kindLabel,
    itemLabel: itemLabel,
    qty: cmd.quantity.int,
    totalCost: cost * cmd.quantity.int,
    status: "Staged"
  )

proc queueRows(state: QueueModalState): seq[QueueRow] =
  let colonyId = ColonyId(state.colonyId.uint32)
  for cmd in state.stagedBuildCommands:
    if cmd.colonyId != colonyId:
      continue
    if cmd.quantity <= 0:
      continue
    result.add(rowForCommand(cmd))

proc render*(
    widget: QueueModalWidget,
    state: QueueModalState,
    viewport: Rect,
    buf: var CellBuffer
) =
  if not state.active:
    return

  let rows = queueRows(state)
  let columns = @[
    tableColumn("Type", 8, table.Alignment.Left),
    tableColumn("Item", 22, table.Alignment.Left),
    tableColumn("Qty", 4, table.Alignment.Right),
    tableColumn("PP", 6, table.Alignment.Right),
    tableColumn("Status", 8, table.Alignment.Left)
  ]

  let maxTableWidth = viewport.width - 4
  let tableWidth = tableWidthFromColumns(
    columns, maxTableWidth, showBorders = true
  )

  var tableView = table(columns)
    .showBorders(true)
    .zebraStripe(true)

  let visibleRows = clampedVisibleRows(
    rows.len,
    viewport.height,
    TableChromeRows + ModalFooterRows
  )
  let tableHeight = tableView.renderHeight(visibleRows)

  let title = "QUEUE - " & state.colonyName
  let footerText = "[PgUp/PgDn]Scroll  [D]elete  [Esc]Close"
  let finalWidth = max(tableWidth, max(title.len, footerText.len))

  let modalArea = widget.modal.calculateArea(
    viewport, finalWidth, tableHeight + 2
  )
  widget.modal.title(title).renderWithFooter(
    modalArea, buf, footerText
  )

  let contentArea = widget.modal.contentArea(modalArea, hasFooter = true)
  if contentArea.isEmpty:
    return

  let headerHeight = tableView.renderHeight(0)
  let contentRows = max(1, contentArea.height - headerHeight)

  var scroll = state.scroll
  scroll.contentLength = rows.len
  scroll.viewportLength = contentRows
  scroll.verticalOffset = clampScrollOffset(
    scroll.verticalOffset,
    rows.len,
    contentRows
  )
  scroll.ensureVisible(state.selectedIdx)

  tableView = tableView
    .selectedIdx(state.selectedIdx)
    .scrollOffset(scroll.verticalOffset)

  for row in rows:
    tableView.addRow(@[
      row.kindLabel,
      row.itemLabel,
      $row.qty,
      $row.totalCost,
      row.status
    ])

  tableView.render(contentArea, buf)
