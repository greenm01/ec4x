## Fleet Detail Modal - Modal for viewing fleet details and issuing commands
##
## A modal popup for viewing fleet composition and issuing commands via
## categorized command picker and ROE picker sub-modals.

import std/[sets, strutils]
import ./modal
import ./table
import ./scroll_state
import ./text/text_pkg
import ../buffer
import ../layout/rect
import ../styles/ec_palette
import ../table_layout_policy
import ../../sam/tui_model
import ../adapters
import ../../../engine/types/fleet

type
  FleetDetailModalWidget* = object
    modal: Modal

proc newFleetDetailModalWidget*(): FleetDetailModalWidget =
  ## Create a new fleet detail modal widget
  FleetDetailModalWidget(
    modal: newModal()
      .maxWidth(90)
      .minWidth(70)
      .minHeight(25)
      .showBackdrop(true)
  )

proc commandCategoryLabel*(category: CommandCategory): string =
  ## Get label for command category
  case category
  of CommandCategory.Movement: "Movement"
  of CommandCategory.Defense: "Defense"
  of CommandCategory.Combat: "Combat"
  of CommandCategory.Colonial: "Colonial"
  of CommandCategory.Intel: "Intel"
  of CommandCategory.FleetOps: "Fleet Ops"
  of CommandCategory.Status: "Status"

proc commandsInCategory*(category: CommandCategory): seq[FleetCommandType] =
  ## Get all commands in a category (no filtering yet)
  case category
  of CommandCategory.Movement:
    @[FleetCommandType.Hold, FleetCommandType.Move, 
      FleetCommandType.SeekHome, FleetCommandType.Patrol]
  of CommandCategory.Defense:
    @[FleetCommandType.GuardStarbase, FleetCommandType.GuardColony,
      FleetCommandType.Blockade]
  of CommandCategory.Combat:
    @[FleetCommandType.Bombard, FleetCommandType.Invade,
      FleetCommandType.Blitz]
  of CommandCategory.Colonial:
    @[FleetCommandType.Colonize]
  of CommandCategory.Intel:
    @[FleetCommandType.ScoutColony, FleetCommandType.ScoutSystem,
      FleetCommandType.HackStarbase, FleetCommandType.View]
  of CommandCategory.FleetOps:
    @[FleetCommandType.JoinFleet, FleetCommandType.Rendezvous,
      FleetCommandType.Salvage]
  of CommandCategory.Status:
    @[FleetCommandType.Reserve, FleetCommandType.Mothball]

proc requiresConfirmation*(cmdType: FleetCommandType): bool =
  ## Check if command requires confirmation
  ## Active fleet commands (00-19) never require confirmation;
  ## the fleet travels to its destination first. Reserved for
  ## future zero-turn commands (section 6.4) that execute instantly.
  result = false

proc renderPickerTable(t: var Table, area: Rect, buf: var CellBuffer,
                       selectedIdx: int, itemCount: int) =
  ## Shared rendering for picker sub-modals (Command, ROE, ZTC).
  ## Handles scroll offset calculation, selection, and table rendering.
  ## Footer hint is rendered by the modal frame via renderWithFooter.
  let maxVisibleRows = clampedVisibleRows(
    itemCount,
    area.height,
    TableChromeRows,
    rowCap = itemCount,
    maxHeightPercent = 100
  )

  # Calculate scroll offset to keep selected item visible
  var scrollOffset = 0
  if maxVisibleRows < itemCount:
    if selectedIdx >= scrollOffset + maxVisibleRows:
      scrollOffset = selectedIdx - maxVisibleRows + 1
    elif selectedIdx < scrollOffset:
      scrollOffset = selectedIdx

  t = t.selectedIdx(selectedIdx).scrollOffset(scrollOffset)

  # Render table
  let actualVisibleRows = min(itemCount - scrollOffset, maxVisibleRows)
  let tableHeight = t.renderHeight(actualVisibleRows)
  let tableArea = rect(area.x, area.y, area.width, tableHeight)
  t.render(tableArea, buf)

proc maxStringLen(values: openArray[string]): int =
  for value in values:
    result = max(result, value.len)

proc measuredColumnWidths(
    headers: openArray[string],
    rows: seq[seq[string]],
    minWidths: openArray[int]
): seq[int] =
  result = newSeq[int](headers.len)
  for i, header in headers:
    var width = max(1, header.len)
    if i < minWidths.len:
      width = max(width, minWidths[i])
    for row in rows:
      if i < row.len:
        width = max(width, row[i].len)
    result[i] = width

proc measuredTableInnerWidth(
    headers: openArray[string],
    rows: seq[seq[string]],
    minWidths: openArray[int]
): int =
  let widths = measuredColumnWidths(headers, rows, minWidths)
  var contentWidth = 0
  for width in widths:
    contentWidth += width
  let colCount = headers.len
  contentWidth + (colCount * 2) + (colCount + 1)

proc measuredTableContentHeight(
    rowCount: int,
    footerHeight: int = 2,
    rowCap: int = DefaultTableRowCap
): int =
  let visibleRows = if rowCap > 0:
      min(max(1, rowCount), rowCap)
    else:
      max(1, rowCount)
  visibleRows + TableChromeRows + footerHeight

proc renderCommandPicker(state: FleetDetailModalState, area: Rect,
                        buf: var CellBuffer) =
  ## Render command picker using Table widget
  if area.isEmpty:
    return

  let headers = @["No", "Mission", "Requirements"]
  var rows: seq[seq[string]] = @[]
  let commands = state.commandPickerCommands
  for cmdType in commands:
    rows.add(@[
      fleetCommandCode(cmdType),
      fleetCommandLabel(cmdType),
      commandRequirements(cmdType)
    ])
  let widths = measuredColumnWidths(headers, rows, @[2, 7, 12])

  # Build table structure
  var commandTable = table([
    tableColumn("No", width = widths[0], align = table.Alignment.Left),
    tableColumn("Mission", width = widths[1], align = table.Alignment.Left),
    tableColumn("Requirements", width = widths[2], align = table.Alignment.Left)
  ])
    .showBorders(true)
    .showHeader(true)
    .showSeparator(true)
    .cellPadding(1)
    .headerStyle(canvasHeaderStyle())
    .rowStyle(canvasStyle())
    .selectedStyle(selectedStyle())

  for row in rows:
    commandTable.addRow(row)

  renderPickerTable(commandTable, area, buf,
    selectedIdx = state.commandIdx,
    itemCount = commands.len)

proc renderROEPicker(state: FleetDetailModalState, area: Rect,
                    buf: var CellBuffer) =
  ## Render ROE picker using Table widget
  if area.isEmpty:
    return

  let headers = @["ROE", "Meaning", "Use Case"]
  var rows: seq[seq[string]] = @[]
  for roe in 0..10:
    rows.add(@[$roe, roeDescription(roe), roeUseCase(roe)])
  let widths = measuredColumnWidths(headers, rows, @[3, 8, 8])

  var roeTable = table([
    tableColumn("ROE", width = widths[0], align = table.Alignment.Right),
    tableColumn("Meaning", width = widths[1], align = table.Alignment.Left),
    tableColumn("Use Case", width = widths[2], align = table.Alignment.Left)
  ])
    .showBorders(true)
    .showHeader(true)
    .showSeparator(true)
    .cellPadding(1)
    .headerStyle(canvasHeaderStyle())
    .rowStyle(canvasStyle())
    .selectedStyle(selectedStyle())

  for row in rows:
    roeTable.addRow(row)

  renderPickerTable(roeTable, area, buf,
    selectedIdx = state.roeValue,
    itemCount = 11)

proc renderConfirmDialog(state: FleetDetailModalState, area: Rect,
                        buf: var CellBuffer) =
  ## Render confirmation dialog for destructive actions
  if area.isEmpty:
    return

  var y = area.y + (area.height div 2) - 2
  
  # Warning message
  let warning = "WARNING"
  let warningX = area.x + (area.width div 2) - (warning.len div 2)
  for i, ch in warning:
    if warningX + i < area.right:
      discard buf.put(warningX + i, y, $ch, alertStyle())
  y += 2

  # Confirmation message
  let msgLines = @[state.confirmMessage, "", "Proceed? [Y]es / [N]o"]
  for line in msgLines:
    if y >= area.bottom:
      break
    let lineX = area.x + (area.width div 2) - (line.len div 2)
    for i, ch in line:
      if lineX + i < area.right:
        discard buf.put(lineX + i, y, $ch, canvasStyle())
    y += 1

proc renderNoticeDialog(state: FleetDetailModalState, area: Rect,
                        buf: var CellBuffer) =
  ## Render notice dialog for empty target lists
  if area.isEmpty:
    return

  var y = area.y + (area.height div 2) - 2

  # Notice header
  let header = "NOTICE"
  let headerX = area.x + (area.width div 2) -
    (header.len div 2)
  for i, ch in header:
    if headerX + i < area.right:
      discard buf.put(headerX + i, y, $ch, alertStyle())
  y += 2

  # Notice message
  let msgLines = @[
    state.noticeMessage,
    "",
    "Press [Esc] to go back"
  ]
  for line in msgLines:
    if y >= area.bottom:
      break
    let lineX = area.x + (area.width div 2) -
      (line.len div 2)
    for i, ch in line:
      if lineX + i < area.right:
        discard buf.put(lineX + i, y, $ch, canvasStyle())
    y += 1

proc renderZTCPicker(state: FleetDetailModalState, area: Rect,
                    buf: var CellBuffer) =
  ## Render Zero-Turn Command picker using Table widget
  if area.isEmpty:
    return

  let headers = @["No", "Command", "Description"]
  var rows: seq[seq[string]] = @[]
  let ztcCommands = state.ztcPickerCommands
  for idx, ztcType in ztcCommands:
    rows.add(@[$(idx + 1), ztcLabel(ztcType), ztcDescription(ztcType)])
  let widths = measuredColumnWidths(headers, rows, @[2, 8, 12])

  var ztcTable = table([
    tableColumn("No", width = widths[0], align = table.Alignment.Right),
    tableColumn("Command", width = widths[1], align = table.Alignment.Left),
    tableColumn("Description", width = widths[2], align = table.Alignment.Left)
  ])
    .showBorders(true)
    .showHeader(true)
    .showSeparator(true)
    .cellPadding(1)
    .headerStyle(canvasHeaderStyle())
    .rowStyle(canvasStyle())
    .selectedStyle(selectedStyle())

  for row in rows:
    ztcTable.addRow(row)

  let itemCount = max(1, ztcCommands.len)
  renderPickerTable(ztcTable, area, buf,
    selectedIdx = state.ztcIdx,
    itemCount = itemCount)

proc renderFleetPicker(state: FleetDetailModalState, area: Rect,
                      buf: var CellBuffer) =
  ## Render fleet picker using Table widget
  if area.isEmpty:
    return

  let headers = @["Fleet", "Ships", "AS", "DS"]
  var rows: seq[seq[string]] = @[]
  for fleet in state.fleetPickerCandidates:
    rows.add(@[
      fleet.name,
      $fleet.shipCount,
      $fleet.attackStrength,
      $fleet.defenseStrength
    ])
  let widths = measuredColumnWidths(headers, rows, @[5, 5, 2, 2])

  var fleetTable = table([
    tableColumn("Fleet", width = widths[0], align = table.Alignment.Left),
    tableColumn("Ships", width = widths[1], align = table.Alignment.Right),
    tableColumn("AS", width = widths[2], align = table.Alignment.Right),
    tableColumn("DS", width = widths[3], align = table.Alignment.Right)
  ])
    .showBorders(true)
    .showHeader(true)
    .showSeparator(true)
    .cellPadding(1)
    .headerStyle(canvasHeaderStyle())
    .rowStyle(canvasStyle())
    .selectedStyle(selectedStyle())

  for row in rows:
    fleetTable.addRow(row)

  let count = max(1, state.fleetPickerCandidates.len)
  renderPickerTable(fleetTable, area, buf,
    selectedIdx = state.fleetPickerIdx,
    itemCount = count)

proc renderSystemPicker(state: FleetDetailModalState,
                        area: Rect,
                        buf: var CellBuffer) =
  ## Render system picker using Table widget.
  ## Two-column table: Coord (6 wide) | System Name (fill).
  ## Filter input jumps selection silently.
  if area.isEmpty:
    return

  let headers = @["Coord", "System"]
  var rows: seq[seq[string]] = @[]
  for sys in state.systemPickerSystems:
    rows.add(@[sys.coordLabel, sys.name])
  let widths = measuredColumnWidths(headers, rows, @[5, 6])

  var sysTable = table([
    tableColumn("Coord", width = widths[0],
      align = table.Alignment.Left),
    tableColumn("System", width = widths[1],
      align = table.Alignment.Left)
  ])
    .showBorders(true)
    .showHeader(true)
    .showSeparator(true)
    .cellPadding(1)
    .headerStyle(canvasHeaderStyle())
    .rowStyle(canvasStyle())
    .selectedStyle(selectedStyle())

  for row in rows:
    sysTable.addRow(row)

  let count = max(1, state.systemPickerSystems.len)
  renderPickerTable(sysTable, area, buf,
    selectedIdx = state.systemPickerIdx,
    itemCount = count)

proc renderShipSelector(state: FleetDetailModalState, area: Rect,
                        buf: var CellBuffer) =
  if area.isEmpty:
    return
  let headers = @["No", "Sel", "Class", "ShipId", "Wep", "AS", "DS", "Status"]
  var rows: seq[seq[string]] = @[]
  for idx, shipRow in state.shipSelectorRows:
    let mark = if shipRow.shipId in state.shipSelectorSelected: "[x]" else: "[ ]"
    rows.add(@[
      $(idx + 1),
      mark,
      shipRow.classLabel,
      $int(shipRow.shipId),
      $shipRow.wepTech,
      $shipRow.attackStrength,
      $shipRow.defenseStrength,
      shipRow.combatStatus
    ])
  let widths = measuredColumnWidths(
    headers,
    rows,
    @[2, 3, 14, 6, 3, 2, 2, 10]
  )
  var shipTable = table([
    tableColumn("No", width = widths[0], align = table.Alignment.Right),
    tableColumn("Sel", width = widths[1], align = table.Alignment.Left),
    tableColumn("Class", width = widths[2], align = table.Alignment.Left),
    tableColumn("ShipId", width = widths[3], align = table.Alignment.Right),
    tableColumn("Wep", width = widths[4], align = table.Alignment.Right),
    tableColumn("AS", width = widths[5], align = table.Alignment.Right),
    tableColumn("DS", width = widths[6], align = table.Alignment.Right),
    tableColumn("Status", width = widths[7], align = table.Alignment.Left)
  ])
    .showBorders(true)
    .showHeader(true)
    .showSeparator(true)
    .cellPadding(1)
    .headerStyle(canvasHeaderStyle())
    .rowStyle(canvasStyle())
    .selectedStyle(selectedStyle())
  for row in rows:
    shipTable.addRow(row)
  let count = max(1, state.shipSelectorRows.len)
  renderPickerTable(
    shipTable,
    area,
    buf,
    selectedIdx = state.shipSelectorIdx,
    itemCount = count
  )

proc renderCargoParams(state: FleetDetailModalState, area: Rect,
                       buf: var CellBuffer) =
  if area.isEmpty:
    return
  var y = area.y
  discard buf.setString(area.x, y, "CARGO PARAMETERS", canvasHeaderStyle())
  y += 2
  discard buf.setString(area.x, y, "Cargo: Marines (Troop Transport only)",
    canvasStyle())
  y += 1
  let qtyRaw = state.cargoQuantityInput.value().strip()
  let qty = if qtyRaw.len == 0: "0 (all)" else: qtyRaw
  discard buf.setString(area.x, y, "Quantity: " & qty, canvasStyle())
  y += 2
  discard buf.setString(area.x, y,
    "Use [0-9] qty, [Enter] confirm",
    canvasDimStyle())

proc renderFighterParams(state: FleetDetailModalState, area: Rect,
                         buf: var CellBuffer) =
  if area.isEmpty:
    return
  var y = area.y
  discard buf.setString(area.x, y, "FIGHTER PARAMETERS", canvasHeaderStyle())
  y += 2
  let qtyRaw = state.fighterQuantityInput.value().strip()
  let qty = if qtyRaw.len == 0: "0 (all)" else: qtyRaw
  discard buf.setString(area.x, y, "Quantity: " & qty, canvasStyle())
  y += 2
  discard buf.setString(area.x, y,
    "Use [↑↓] or [0-9], [Enter] confirm",
    canvasDimStyle())

proc renderFleetInfo(fleetData: FleetDetailData, area: Rect,
                    buf: var CellBuffer) =
  ## Render basic fleet info (top section)
  if area.isEmpty:
    return

  var y = area.y

  # Fleet ID and location
  let line1 = "Fleet " & fleetData.fleetName & " at " & fleetData.location
  for i, ch in line1:
    if area.x + i < area.right:
      discard buf.put(area.x + i, y, $ch, canvasStyle())
  y += 1

  if y >= area.bottom:
    return

  # Current command and ROE
  let line2 = "Command: " & fleetData.command & "  " &
    "Target: " & fleetData.targetLabel & "  " &
    "ROE: " & $fleetData.roe
  for i, ch in line2:
    if area.x + i < area.right:
      discard buf.put(area.x + i, y, $ch, canvasStyle())
  y += 1

  if y >= area.bottom:
    return

  # Ship count summary
  let line3 = "Ships: " & $fleetData.ships.len & "  AS: " & $fleetData.totalAttack & "  DS: " & $fleetData.totalDefense
  for i, ch in line3:
    if area.x + i < area.right:
      discard buf.put(area.x + i, y, $ch, canvasStyle())

proc render*(widget: FleetDetailModalWidget, state: FleetDetailModalState,
            fleetData: FleetDetailData, viewport: Rect, buf: var CellBuffer) =
  ## Render the fleet detail view
  ## NOTE: No longer checks state.active - called only when ViewMode == FleetDetail
  
  var renderScroll = state.shipScroll
  var visibleRows = 0

  let shipTableBase = shipListTable()
    .showBorders(true)
    .showHeader(true)
    .showSeparator(true)

  let maxWidth = max(4, viewport.width - 4)
  let tableWidth = shipTableBase.renderWidth(maxWidth)
  let line1 = "Fleet " & fleetData.fleetName & " at " & fleetData.location
  let line2 = "Command: " & fleetData.command & "  " &
    "Target: " & fleetData.targetLabel & "  " &
    "ROE: " & $fleetData.roe
  let line3 = "Ships: " & $state.shipCount & "  AS: " &
    $fleetData.totalAttack & "  DS: " & $fleetData.totalDefense
  let shipHeader = "SHIPS (" & $state.shipCount & ")"
  let infoWidth = max(line1.len,
    max(line2.len, max(line3.len, shipHeader.len)))
  let desiredInnerWidth = max(tableWidth, infoWidth)

  let subModalInnerWidth = case state.subModal
    of FleetSubModal.CommandPicker:
      var rows: seq[seq[string]] = @[]
      for cmdType in state.commandPickerCommands:
        rows.add(@[
          fleetCommandCode(cmdType),
          fleetCommandLabel(cmdType),
          commandRequirements(cmdType)
        ])
      measuredTableInnerWidth(
        @["No", "Mission", "Requirements"],
        rows,
        @[2, 7, 12]
      )
    of FleetSubModal.ROEPicker:
      var rows: seq[seq[string]] = @[]
      for roe in 0..10:
        rows.add(@[$roe, roeDescription(roe), roeUseCase(roe)])
      measuredTableInnerWidth(
        @["ROE", "Meaning", "Use Case"],
        rows,
        @[3, 8, 8]
      )
    of FleetSubModal.SystemPicker:
      var rows: seq[seq[string]] = @[]
      for sys in state.systemPickerSystems:
        rows.add(@[sys.coordLabel, sys.name])
      measuredTableInnerWidth(@["Coord", "System"], rows, @[5, 6])
    of FleetSubModal.FleetPicker:
      var rows: seq[seq[string]] = @[]
      for fleet in state.fleetPickerCandidates:
        rows.add(@[
          fleet.name,
          $fleet.shipCount,
          $fleet.attackStrength,
          $fleet.defenseStrength
        ])
      measuredTableInnerWidth(@["Fleet", "Ships", "AS", "DS"],
        rows, @[5, 5, 2, 2])
    of FleetSubModal.ZTCPicker:
      var rows: seq[seq[string]] = @[]
      for idx, ztcType in state.ztcPickerCommands:
        rows.add(@[$(idx + 1), ztcLabel(ztcType), ztcDescription(ztcType)])
      measuredTableInnerWidth(@["No", "Command", "Description"],
        rows, @[2, 8, 12])
    of FleetSubModal.ShipSelector:
      var rows: seq[seq[string]] = @[]
      for idx, shipRow in state.shipSelectorRows:
        let mark = if shipRow.shipId in state.shipSelectorSelected:
            "[x]" else: "[ ]"
        rows.add(@[
          $(idx + 1),
          mark,
          shipRow.classLabel,
          $int(shipRow.shipId),
          $shipRow.wepTech,
          $shipRow.attackStrength,
          $shipRow.defenseStrength,
          shipRow.combatStatus
        ])
      measuredTableInnerWidth(
        @["No", "Sel", "Class", "ShipId", "Wep", "AS", "DS", "Status"],
        rows,
        @[2, 3, 14, 6, 3, 2, 2, 10]
      )
    of FleetSubModal.CargoParams:
      let qtyRaw = state.cargoQuantityInput.value().strip()
      let qty = if qtyRaw.len == 0: "0 (all)" else: qtyRaw
      let lines = @[
        "CARGO PARAMETERS",
        "Cargo: Marines (Troop Transport only)",
        "Quantity: " & qty,
        "Use [0-9] qty, [Enter] confirm"
      ]
      maxStringLen(lines)
    of FleetSubModal.FighterParams:
      let qtyRaw = state.fighterQuantityInput.value().strip()
      let qty = if qtyRaw.len == 0: "0 (all)" else: qtyRaw
      let lines = @[
        "FIGHTER PARAMETERS",
        "Quantity: " & qty,
        "Use [↑↓] or [0-9], [Enter] confirm"
      ]
      maxStringLen(lines)
    of FleetSubModal.ConfirmPrompt:
      max(state.confirmMessage.len, "Proceed? [Y]es / [N]o".len)
    of FleetSubModal.NoticePrompt:
      max(state.noticeMessage.len, "Press [Esc] to go back".len)
    of FleetSubModal.Staged:
      "Command staged successfully".len
    of FleetSubModal.None:
      desiredInnerWidth

  let modal = widget.modal
    .maxWidth(maxWidth)
    .minWidth(4)
    .minHeight(0)

  var shipTable = shipTableBase
    .scrollOffset(renderScroll.verticalOffset)
  for ship in fleetData.ships:
    shipTable.addRow([
      ship.class,
      ship.state,
      ship.attack,
      ship.defense,
      $ship.wepLevel,
      ship.marines
    ])

  # Calculate content height based on active sub-modal
  let contentHeight = case state.subModal
    of FleetSubModal.CommandPicker:
      measuredTableContentHeight(
        state.commandPickerCommands.len,
        rowCap = 0
      )
    of FleetSubModal.ROEPicker:
      measuredTableContentHeight(11)
    of FleetSubModal.ConfirmPrompt:
      10
    of FleetSubModal.NoticePrompt:
      10
    of FleetSubModal.SystemPicker:
      measuredTableContentHeight(state.systemPickerSystems.len)
    of FleetSubModal.FleetPicker:
      measuredTableContentHeight(state.fleetPickerCandidates.len)
    of FleetSubModal.Staged:
      8
    of FleetSubModal.ZTCPicker:
      measuredTableContentHeight(state.ztcPickerCommands.len)
    of FleetSubModal.ShipSelector:
      measuredTableContentHeight(state.shipSelectorRows.len)
    of FleetSubModal.CargoParams:
      8
    of FleetSubModal.FighterParams:
      7
    of FleetSubModal.None:
      # Normal fleet detail view with ship list
      let maxRows = fleetDetailMaxRows(viewport.height)
      visibleRows = min(state.shipCount, max(0, maxRows))
      renderScroll.contentLength = state.shipCount
      renderScroll.viewportLength = max(1, visibleRows)
      renderScroll.clampOffsets()
      let shipsContentHeight = FleetDetailShipsHeaderHeight +
        shipTable.renderHeight(visibleRows)
      FleetDetailInfoHeight + FleetDetailSeparatorHeight +
        shipsContentHeight + FleetDetailFooterHeight
  
  var modalArea = modal.calculateArea(
    viewport,
    subModalInnerWidth,
    contentHeight
  )
  var effectiveModalArea = modalArea

  # Render modal frame with title
  # Determine footer text per sub-modal (pickers get bordered footers too)
  let title = if state.subModal in {FleetSubModal.ZTCPicker,
      FleetSubModal.ShipSelector,
      FleetSubModal.CargoParams,
      FleetSubModal.FighterParams}:
      "ZERO TURN COMMANDS"
    else:
      "FLEET DETAIL"
  let (hasFooter, footerText) = case state.subModal
    of FleetSubModal.None:
      (true, "[C]md [R]OE [Z]TC [PgUp/PgDn]Scroll [Esc]Close")
    of FleetSubModal.CommandPicker:
      (true, "[↑↓]Select [00-19]Quick [Enter]Confirm [Esc]Cancel")
    of FleetSubModal.ROEPicker:
      (true, "[↑↓]Select [0-9]Quick [Enter]Confirm [Esc]Cancel")
    of FleetSubModal.ZTCPicker:
      (true, "[↑↓]Select [1-9]Quick [Enter]Confirm [Esc]Cancel")
    of FleetSubModal.FleetPicker:
      (true, "[↑↓]Select [Enter]Confirm [Esc]Cancel")
    of FleetSubModal.SystemPicker:
      (true,
        "[↑↓←→]Nav [type]Filter [PgUp/Dn] " &
        "[Enter]Select [Esc]Back")
    of FleetSubModal.ShipSelector:
      (true, "[↑↓]Nav [X/Space]Toggle [Enter]Confirm [Esc]Cancel")
    of FleetSubModal.CargoParams:
      (true, "[0-9]Qty [Enter]Confirm [Esc]Cancel")
    of FleetSubModal.FighterParams:
      (true, "[↑↓]Qty [0-9]Qty [Enter]Confirm [Esc]Cancel")
    else:
      (false, "")

  if state.subModal == FleetSubModal.None:
    let estimatedInnerHeight = max(1,
      contentHeight - FleetDetailFooterHeight)
    let estimatedShipsHeight = max(1, estimatedInnerHeight -
      (FleetDetailInfoHeight + FleetDetailSeparatorHeight))
    let estimatedTableHeight = max(0,
      estimatedShipsHeight - FleetDetailShipsHeaderHeight)
    visibleRows = min(state.shipCount, max(0,
      estimatedTableHeight - FleetDetailTableBaseHeight))
    renderScroll.contentLength = state.shipCount
    renderScroll.viewportLength = max(1, visibleRows)
    renderScroll.clampOffsets()
    let shipsContentHeight = FleetDetailShipsHeaderHeight +
      shipTable.renderHeight(visibleRows)
    let desiredContentHeight = FleetDetailInfoHeight +
      FleetDetailSeparatorHeight + shipsContentHeight +
      FleetDetailFooterHeight
    if desiredContentHeight != contentHeight:
      effectiveModalArea = modal.calculateArea(viewport,
        subModalInnerWidth,
        desiredContentHeight)

  if hasFooter:
    modal.title(title).renderWithFooter(effectiveModalArea, buf, footerText)
  else:
    modal.title(title).render(effectiveModalArea, buf)

  # Get content area (excludes footer if present)
  let inner = modal.contentArea(effectiveModalArea, hasFooter = hasFooter)
  if state.subModal == FleetSubModal.None:
    shipTable = shipTable.scrollOffset(renderScroll.verticalOffset)

  # Check for sub-modals
  case state.subModal
  of FleetSubModal.CommandPicker:
    renderCommandPicker(state, inner, buf)
  of FleetSubModal.ROEPicker:
    renderROEPicker(state, inner, buf)
  of FleetSubModal.ConfirmPrompt:
    renderConfirmDialog(state, inner, buf)
  of FleetSubModal.NoticePrompt:
    renderNoticeDialog(state, inner, buf)
  of FleetSubModal.SystemPicker:
    renderSystemPicker(state, inner, buf)
  of FleetSubModal.FleetPicker:
    renderFleetPicker(state, inner, buf)
  of FleetSubModal.Staged:
    # Show success message
    let centerY = inner.y + inner.height div 2
    let msg = "Command staged successfully"
    let msgX = inner.x + (inner.width - msg.len) div 2
    discard buf.put(msgX, centerY, msg, canvasStyle())
  of FleetSubModal.ZTCPicker:
    renderZTCPicker(state, inner, buf)
  of FleetSubModal.ShipSelector:
    renderShipSelector(state, inner, buf)
  of FleetSubModal.CargoParams:
    renderCargoParams(state, inner, buf)
  of FleetSubModal.FighterParams:
    renderFighterParams(state, inner, buf)
  of FleetSubModal.None:
    # Render main fleet detail view
    
    # Fleet info section (top 4 lines)
    let infoArea = rect(inner.x, inner.y, inner.width,
      FleetDetailInfoHeight)
    renderFleetInfo(fleetData, infoArea, buf)
    
    # Separator
    let separatorY = inner.y + FleetDetailInfoHeight
    let glyphs = modal.separatorGlyphs()
    discard buf.put(effectiveModalArea.x, separatorY, glyphs.left,
      modalBorderStyle())
    for x in (effectiveModalArea.x + 1)..<(effectiveModalArea.right - 1):
      discard buf.put(x, separatorY, glyphs.horizontal,
        modalBorderStyle())
    discard buf.put(effectiveModalArea.right - 1, separatorY, glyphs.right,
      modalBorderStyle())
    
    # Ship list (boxed table)
    let shipsHeight = max(1, inner.height - (FleetDetailInfoHeight +
      FleetDetailSeparatorHeight))
    let shipsArea = rect(inner.x, separatorY + 1, inner.width, shipsHeight)
    let tableArea = rect(shipsArea.x,
      shipsArea.y + FleetDetailShipsHeaderHeight,
      shipsArea.width,
      shipsArea.height - FleetDetailShipsHeaderHeight)
    shipTable.render(tableArea, buf)
