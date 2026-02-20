## Build Modal - Modal for issuing build commands
##
## A modal popup for browsing categorized build options, adding items to a
## pending queue, and confirming to stage them for turn submission.

import std/[options, strutils, unicode]

import ./modal
import ./text/text_pkg
import ./table
import ./tabs
import ./scroll_state
import ../buffer
import ../layout/rect
import ../styles/ec_palette
import ../build_spec
import ../columns
import ../table_layout_policy
import ../../sam/tui_model
import ../../../engine/types/[core, production]
import ../../../engine/types/[ship, ground_unit, facilities]
import ../../../engine/systems/capacity/construction_docks

type
  BuildModalWidget* = object
    modal: Modal

proc newBuildModalWidget*(): BuildModalWidget =
  ## Create a new build modal widget
  BuildModalWidget(
    modal: newModal()
      .maxWidth(96)
      .minWidth(44)
      .minHeight(10)
      .showBackdrop(true)
  )

proc columnsForCategory(category: BuildCategory): seq[TableColumn] =
  case category
  of BuildCategory.Ships:
    @[
      tableColumn("Class", 5, table.Alignment.Left),
      tableColumn("Name", 18, table.Alignment.Left),
      tableColumn("CST", 3, table.Alignment.Right),
      tableColumn("PC", 4, table.Alignment.Right),
      tableColumn("MC", 4, table.Alignment.Right),
      tableColumn("AS", 4, table.Alignment.Right),
      tableColumn("DS", 4, table.Alignment.Right),
      tableColumn("CC", 4, table.Alignment.Right),
      tableColumn("CL", 4, table.Alignment.Right),
      tableColumn("Qty", 4, table.Alignment.Right)
    ]
  of BuildCategory.Ground:
    @[
      tableColumn("Class", 5, table.Alignment.Left),
      tableColumn("Name", 18, table.Alignment.Left),
      tableColumn("CST", 3, table.Alignment.Right),
      tableColumn("PC", 4, table.Alignment.Right),
      tableColumn("MC", 4, table.Alignment.Right),
      tableColumn("AS", 4, table.Alignment.Right),
      tableColumn("DS", 4, table.Alignment.Right),
      tableColumn("Qty", 4, table.Alignment.Right)
    ]
  of BuildCategory.Facilities:
    @[
      tableColumn("Class", 5, table.Alignment.Left),
      tableColumn("Name", 14, table.Alignment.Left),
      tableColumn("CST", 3, table.Alignment.Right),
      tableColumn("PC", 4, table.Alignment.Right),
      tableColumn("MC", 4, table.Alignment.Right),
      tableColumn("AS", 4, table.Alignment.Right),
      tableColumn("DS", 4, table.Alignment.Right),
      tableColumn("Docks", 5, table.Alignment.Right),
      tableColumn("Time", 4, table.Alignment.Right),
      tableColumn("Qty", 4, table.Alignment.Right)
    ]

proc fillRow(area: Rect, buf: var CellBuffer, style: CellStyle) =
  if area.isEmpty:
    return
  for x in area.x ..< area.right:
    discard buf.put(x, area.y, " ", style)

proc renderCategoryTabs(
    state: BuildModalState, area: Rect, buf: var CellBuffer
) =
  ## Render category tabs at the top of the modal
  if area.isEmpty:
    return

  fillRow(area, buf, modalBgStyle())
  let activeTabIdx = case state.category
    of BuildCategory.Ships:
      0
    of BuildCategory.Facilities:
      1
    of BuildCategory.Ground:
      2
  var tabBar = tabs(["Ships", "Facilities", "Ground"], activeTabIdx)
    .inactiveStyle(modalBgStyle())
    .activeStyle(CellStyle(
      fg: color(SelectedBgColor),
      bg: color(TrueBlackColor),
      attrs: {StyleAttr.Bold}
    ))
    .disabledStyle(modalDimStyle())
  tabBar.bracketStyle = modalDimStyle()
  tabBar.render(area, buf)

proc pendingDockUse(state: BuildModalState): int
proc pendingPpCost(state: BuildModalState): int
proc stagedQty(state: BuildModalState, key: BuildRowKey): int

proc renderDockSummary(
    state: BuildModalState, area: Rect, buf: var CellBuffer
) =
  ## Render dock capacity summary
  if area.isEmpty:
    return
  fillRow(area, buf, modalBgStyle())

  let docks = state.dockSummary
  let pendingUsed = pendingDockUse(state)
  var used = max(0, docks.constructionTotal - docks.constructionAvailable)
  used += pendingUsed
  if used > docks.constructionTotal:
    used = docks.constructionTotal
  let availablePp =
    if state.ppAvailable >= 0:
      max(0, state.ppAvailable - pendingPpCost(state))
    else:
      -1
  let ppLabel = if availablePp >= 0:
    $availablePp & "/" & $state.ppAvailable
  else:
    "N/A"
  let text = "Docks: " & $used & "/" &
    $docks.constructionTotal & " CDK | " &
    "PP Available: " & ppLabel

  for i, ch in text:
    if area.x + i < area.right:
      discard buf.put(area.x + i, area.y, $ch, modalDimStyle())

proc stagedQty(state: BuildModalState, key: BuildRowKey): int =
  var total = 0
  let colonyId = ColonyId(state.colonyId.uint32)
  for cmd in state.stagedBuildCommands:
    if cmd.colonyId != colonyId:
      continue
    case key.kind
    of BuildOptionKind.Ship:
      if cmd.buildType == BuildType.Ship and
          cmd.shipClass.isSome and key.shipClass.isSome and
          cmd.shipClass.get() == key.shipClass.get():
        total += cmd.quantity.int
    of BuildOptionKind.Ground:
      if cmd.buildType == BuildType.Ground and
          cmd.groundClass.isSome and key.groundClass.isSome and
          cmd.groundClass.get() == key.groundClass.get():
        total += cmd.quantity.int
    of BuildOptionKind.Facility:
      if cmd.buildType == BuildType.Facility and
          cmd.facilityClass.isSome and key.facilityClass.isSome and
          cmd.facilityClass.get() == key.facilityClass.get():
        total += cmd.quantity.int
  total

proc pendingDockUse(state: BuildModalState): int =
  var used = 0
  let colonyId = ColonyId(state.colonyId.uint32)
  for cmd in state.stagedBuildCommands:
    if cmd.colonyId != colonyId:
      continue
    if cmd.buildType != BuildType.Ship or cmd.shipClass.isNone:
      continue
    if construction_docks.shipRequiresDock(cmd.shipClass.get()):
      used += cmd.quantity.int
  used

proc pendingPpCost(state: BuildModalState): int =
  var total = 0
  let colonyId = ColonyId(state.colonyId.uint32)
  for cmd in state.stagedBuildCommands:
    if cmd.colonyId != colonyId:
      continue
    case cmd.buildType
    of BuildType.Ship:
      if cmd.shipClass.isSome:
        let key = BuildRowKey(
          kind: BuildOptionKind.Ship,
          shipClass: cmd.shipClass,
          groundClass: none(GroundClass),
          facilityClass: none(FacilityClass)
        )
        total += buildRowCost(key) * cmd.quantity.int
    of BuildType.Ground:
      if cmd.groundClass.isSome:
        let key = BuildRowKey(
          kind: BuildOptionKind.Ground,
          shipClass: none(ShipClass),
          groundClass: cmd.groundClass,
          facilityClass: none(FacilityClass)
        )
        total += buildRowCost(key) * cmd.quantity.int
    of BuildType.Facility:
      if cmd.facilityClass.isSome:
        let key = BuildRowKey(
          kind: BuildOptionKind.Facility,
          shipClass: none(ShipClass),
          groundClass: none(GroundClass),
          facilityClass: cmd.facilityClass
        )
        total += buildRowCost(key) * cmd.quantity.int
    else:
      discard
  total

proc isBuildable(state: BuildModalState, key: BuildRowKey): bool =
  if buildRowCst(key) > state.cstLevel:
    return false
  for opt in state.availableOptions:
    case opt.kind
    of BuildOptionKind.Ship:
      if key.shipClass.isSome:
        try:
          let cls =
            parseEnum[ShipClass](opt.name.replace(" ", ""))
          if cls == key.shipClass.get():
            if construction_docks.shipRequiresDock(cls):
              let pendingUsed = pendingDockUse(state)
              let available =
                state.dockSummary.constructionAvailable - pendingUsed
              return available > 0
            return true
        except:
          discard
    of BuildOptionKind.Ground:
      if key.groundClass.isSome:
        try:
          let cls =
            parseEnum[GroundClass](opt.name.replace(" ", ""))
          if cls == key.groundClass.get():
            return true
        except:
          discard
    of BuildOptionKind.Facility:
      if key.facilityClass.isSome:
        try:
          let cls =
            parseEnum[FacilityClass](opt.name.replace(" ", ""))
          if cls == key.facilityClass.get():
            return true
        except:
          discard
  false

proc renderBuildTable(
    state: BuildModalState, area: Rect, buf: var CellBuffer
) =
  ## Render spec-aligned build table with qty column
  if area.isEmpty:
    return

  proc dashIf(value: int): string =
    if value < 0: "—" else: $value

  proc pct(value: int): string =
    $value & "%"

  let columns = columnsForCategory(state.category)

  var tableView = table(columns)
    .showBorders(true)
    .zebraStripe(true)

  let rowCount = buildRowCount(state.category)
  let headerHeight = tableView.renderHeight(0)
  let visibleRows = max(1, area.height - headerHeight)

  var scroll = state.buildListScroll
  scroll.contentLength = rowCount
  scroll.viewportLength = visibleRows
  scroll.ensureVisible(state.selectedBuildIdx)
  scroll.clampOffsets()

  tableView = tableView
    .selectedIdx(state.selectedBuildIdx)
    .scrollOffset(scroll.verticalOffset)

  case state.category
  of BuildCategory.Ships:
    for idx, row in ShipSpecRows:
      let key = buildRowKey(state.category, idx)
      let qty = stagedQty(state, key)
      let buildable = isBuildable(state, key)
      let qtyStyle =
        if qty > 0: some(canvasHeaderStyle()) else: none(CellStyle)
      var cellStyles: seq[Option[CellStyle]] = @[]
      cellStyles.setLen(columns.len)
      if qtyStyle.isSome:
        cellStyles[^1] = qtyStyle
      if not buildable:
        for i in 0 ..< cellStyles.len:
          if cellStyles[i].isNone:
            cellStyles[i] = some(canvasDimStyle())
      let cells = @[
        row.code,
        row.name,
        $row.cst,
        $row.pc,
        pct(row.mcPct),
        dashIf(row.attack),
        dashIf(row.defense),
        dashIf(row.command),
        dashIf(row.carry),
        $qty
      ]
      tableView.addRow(TableRow(
        cells: cells,
        cellStyles: cellStyles,
        kind: TableRowKind.Normal
      ))
  of BuildCategory.Ground:
    for idx, row in GroundSpecRows:
      let key = buildRowKey(state.category, idx)
      let qty = stagedQty(state, key)
      let buildable = isBuildable(state, key)
      let qtyStyle =
        if qty > 0: some(canvasHeaderStyle()) else: none(CellStyle)
      var cellStyles: seq[Option[CellStyle]] = @[]
      cellStyles.setLen(columns.len)
      if qtyStyle.isSome:
        cellStyles[^1] = qtyStyle
      if not buildable:
        for i in 0 ..< cellStyles.len:
          if cellStyles[i].isNone:
            cellStyles[i] = some(canvasDimStyle())
      let cells = @[
        row.code,
        row.name,
        $row.cst,
        $row.pc,
        pct(row.mcPct),
        $row.attack,
        $row.defense,
        $qty
      ]
      tableView.addRow(TableRow(
        cells: cells,
        cellStyles: cellStyles,
        kind: TableRowKind.Normal
      ))
  of BuildCategory.Facilities:
    for idx, row in FacilitySpecRows:
      let key = buildRowKey(state.category, idx)
      let qty = stagedQty(state, key)
      let buildable = isBuildable(state, key)
      let qtyStyle =
        if qty > 0: some(canvasHeaderStyle()) else: none(CellStyle)
      var cellStyles: seq[Option[CellStyle]] = @[]
      cellStyles.setLen(columns.len)
      if qtyStyle.isSome:
        cellStyles[^1] = qtyStyle
      if not buildable:
        for i in 0 ..< cellStyles.len:
          if cellStyles[i].isNone:
            cellStyles[i] = some(canvasDimStyle())
      let cells = @[
        row.code,
        row.name,
        $row.cst,
        $row.pc,
        pct(row.mcPct),
        dashIf(row.attack),
        $row.defense,
        dashIf(row.docks),
        $row.time,
        $qty
      ]
      tableView.addRow(TableRow(
        cells: cells,
        cellStyles: cellStyles,
        kind: TableRowKind.Normal
      ))

  tableView.render(area, buf)

proc renderFooter(state: BuildModalState, area: Rect,
                 buf: var CellBuffer) =
  ## Render quantity editor and hints
  if area.isEmpty:
    return

  let text =
    "[PgUp/PgDn]Scroll  [+/-]Qty  [Tab/→/L]Next  [←/H]Prev  [Esc]Close"
  var x = area.x
  for rune in text.runes:
    if x >= area.right:
      break
    let width = buf.put(x, area.y, rune.toUTF8, canvasDimStyle())
    if width <= 0:
      break
    x += width

proc render*(
    widget: BuildModalWidget, state: BuildModalState,
    viewport: Rect, buf: var CellBuffer
) =
  ## Render the build modal
  if not state.active:
    return

  # Calculate modal area
  let columns = columnsForCategory(state.category)

  var tableView = table(columns)
    .showBorders(true)
    .zebraStripe(true)

  let totalRows = buildRowCount(state.category)
  let visibleRows = clampedVisibleRows(
    totalRows,
    viewport.height,
    TableChromeRows + 5
  )
  let tableHeight = tableView.renderHeight(visibleRows)
  let contentHeight = tableHeight + 5
  let maxTableWidth = viewport.width - 4
  let tableWidth = tableWidthFromColumns(
    columns, maxTableWidth, showBorders = true
  )
  let modalArea = widget.modal.calculateArea(
    viewport, tableWidth, contentHeight
  )

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
    outerBorderStyle())
  for x in (modalArea.x + 1)..<(modalArea.right - 1):
    discard buf.put(x, separatorY, glyphs.horizontal,
      outerBorderStyle())
  discard buf.put(modalArea.right - 1, separatorY, glyphs.right,
    outerBorderStyle())

  # Content area (single table)
  let contentArea = rect(
    inner.x, separatorY + 1, inner.width, inner.height - 5
  )

  # Footer area (above the bottom separator)
  let footerArea = rect(inner.x, inner.bottom - 1, inner.width, 1)

  # Render all sections
  renderCategoryTabs(state, tabsArea, buf)
  renderDockSummary(state, docksArea, buf)
  renderBuildTable(state, contentArea, buf)
  renderFooter(state, footerArea, buf)
