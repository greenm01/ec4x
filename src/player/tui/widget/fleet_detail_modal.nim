## Fleet Detail Modal - Modal for viewing fleet details and issuing commands
##
## A modal popup for viewing fleet composition and issuing commands via
## categorized command picker and ROE picker sub-modals.

import ./modal
import ./borders
import ./table
import ./scroll_state
import ./text/text_pkg
import ../buffer
import ../layout/rect
import ../styles/ec_palette
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
  cmdType in {FleetCommandType.Bombard, FleetCommandType.Salvage,
              FleetCommandType.Reserve, FleetCommandType.Mothball}

proc renderPickerTable(t: var Table, area: Rect, buf: var CellBuffer,
                       selectedIdx: int, itemCount: int) =
  ## Shared rendering for picker sub-modals (Command, ROE, ZTC).
  ## Handles scroll offset calculation, selection, and table rendering.
  ## Footer hint is rendered by the modal frame via renderWithFooter.
  let tableBaseHeight = 4  # top border + header + separator + bottom border
  let maxVisibleRows = max(1, area.height - tableBaseHeight)

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

proc renderCommandPicker(state: FleetDetailModalState, area: Rect,
                        buf: var CellBuffer) =
  ## Render command picker using Table widget
  if area.isEmpty:
    return

  # Build table structure
  var commandTable = table([
    tableColumn("No", width = 4, align = table.Alignment.Left),
    tableColumn("Mission", width = 14, align = table.Alignment.Left),
    tableColumn("Requirements", width = 0, align = table.Alignment.Left,
                minWidth = 20)
  ])
    .showBorders(true)
    .showHeader(true)
    .showSeparator(true)
    .cellPadding(1)
    .headerStyle(canvasHeaderStyle())
    .rowStyle(canvasStyle())
    .selectedStyle(selectedStyle())

  # Populate with all commands
  let commands = allFleetCommands()
  for cmdType in commands:
    let cmdCode = fleetCommandCode(cmdType)
    let cmdLabel = fleetCommandLabel(cmdType)
    let cmdReq = commandRequirements(cmdType)
    commandTable.addRow([cmdCode, cmdLabel, cmdReq])

  renderPickerTable(commandTable, area, buf,
    selectedIdx = state.commandIdx,
    itemCount = commands.len)

proc renderROEPicker(state: FleetDetailModalState, area: Rect,
                    buf: var CellBuffer) =
  ## Render ROE picker using Table widget
  if area.isEmpty:
    return

  var roeTable = table([
    tableColumn("ROE", width = 3, align = table.Alignment.Right),
    tableColumn("Meaning", width = 30, align = table.Alignment.Left),
    tableColumn("Use Case", width = 0, align = table.Alignment.Left,
                minWidth = 14)
  ])
    .showBorders(true)
    .showHeader(true)
    .showSeparator(true)
    .cellPadding(1)
    .headerStyle(canvasHeaderStyle())
    .rowStyle(canvasStyle())
    .selectedStyle(selectedStyle())

  for roe in 0..10:
    roeTable.addRow([$roe, roeDescription(roe), roeUseCase(roe)])

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

proc renderZTCPicker(state: FleetDetailModalState, area: Rect,
                    buf: var CellBuffer) =
  ## Render Zero-Turn Command picker using Table widget
  if area.isEmpty:
    return

  var ztcTable = table([
    tableColumn("No", width = 3, align = table.Alignment.Right),
    tableColumn("Command", width = 18, align = table.Alignment.Left),
    tableColumn("Description", width = 0, align = table.Alignment.Left,
                minWidth = 20)
  ])
    .showBorders(true)
    .showHeader(true)
    .showSeparator(true)
    .cellPadding(1)
    .headerStyle(canvasHeaderStyle())
    .rowStyle(canvasStyle())
    .selectedStyle(selectedStyle())

  let ztcCommands = allZeroTurnCommands()
  for idx, ztcType in ztcCommands:
    ztcTable.addRow([$(idx + 1), ztcLabel(ztcType), ztcDescription(ztcType)])

  renderPickerTable(ztcTable, area, buf,
    selectedIdx = state.ztcIdx,
    itemCount = ztcCommands.len)

proc renderFleetPicker(state: FleetDetailModalState, area: Rect,
                      buf: var CellBuffer) =
  ## Render fleet picker using Table widget
  if area.isEmpty:
    return

  var fleetTable = table([
    tableColumn("Fleet", width = 8, align = table.Alignment.Left),
    tableColumn("Ships", width = 5, align = table.Alignment.Right),
    tableColumn("AS", width = 4, align = table.Alignment.Right),
    tableColumn("DS", width = 4, align = table.Alignment.Right)
  ])
    .showBorders(true)
    .showHeader(true)
    .showSeparator(true)
    .cellPadding(1)
    .headerStyle(canvasHeaderStyle())
    .rowStyle(canvasStyle())
    .selectedStyle(selectedStyle())

  for fleet in state.fleetPickerCandidates:
    fleetTable.addRow([
      fleet.name,
      $fleet.shipCount,
      $fleet.attackStrength,
      $fleet.defenseStrength
    ])

  let count = max(1, state.fleetPickerCandidates.len)
  renderPickerTable(fleetTable, area, buf,
    selectedIdx = state.fleetPickerIdx,
    itemCount = count)

proc renderPlaceholderSubModal(label: string, area: Rect,
                              buf: var CellBuffer) =
  ## Render placeholder for not-yet-implemented sub-modals
  if area.isEmpty:
    return
  let centerY = area.y + area.height div 2
  let msg = label & " - Not Yet Implemented"
  let msgX = area.x + max(0, (area.width - msg.len) div 2)
  discard buf.setString(msgX, centerY, msg, canvasStyle())
  let hint = "Press [Esc] to go back"
  let hintX = area.x + max(0, (area.width - hint.len) div 2)
  if centerY + 2 < area.bottom:
    discard buf.setString(hintX, centerY + 2, hint, canvasDimStyle())

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
  let line2 = "Command: " & fleetData.command & "  ROE: " & $fleetData.roe
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
  
  let maxRows = fleetDetailMaxRows(viewport.height)
  let visibleRows = min(state.shipCount, max(1, maxRows))
  var renderScroll = state.shipScroll
  renderScroll.contentLength = state.shipCount
  renderScroll.viewportLength = max(1, maxRows)
  renderScroll.clampOffsets()

  let shipTableBase = shipListTable()
    .showBorders(true)
    .showHeader(true)
    .showSeparator(true)
    .fillHeight(true)

  let maxWidth = max(4, viewport.width - 4)
  let tableWidth = shipTableBase.renderWidth(maxWidth)
  let line1 = "Fleet " & fleetData.fleetName & " at " & fleetData.location
  let line2 = "Command: " & fleetData.command & "  ROE: " & $fleetData.roe
  let line3 = "Ships: " & $state.shipCount & "  AS: " &
    $fleetData.totalAttack & "  DS: " & $fleetData.totalDefense
  let shipHeader = "SHIPS (" & $state.shipCount & ")"
  let infoWidth = max(line1.len,
    max(line2.len, max(line3.len, shipHeader.len)))
  let desiredInnerWidth = max(tableWidth, infoWidth)

  # Sub-modal picker tables may need more width than the ship table.
  # Compute minimum inner width from known column content + padding + borders:
  #   innerWidth = sum(colContentWidths) + cols*cellPadding*2 + (cols+1)
  let subModalMinInner = case state.subModal
    of FleetSubModal.CommandPicker:
      # No(4) + Mission(14) + Requirements(34) + padding(6) + borders(4)
      62
    of FleetSubModal.ROEPicker:
      # ROE(3) + Meaning(30) + UseCase(38) + padding(6) + borders(4)
      81
    of FleetSubModal.ZTCPicker:
      # No(3) + Command(18) + Description(44) + padding(6) + borders(4)
      75
    else:
      0

  let desiredWidth = min(maxWidth, max(desiredInnerWidth, subModalMinInner) + 2)
  let isSubModal = state.subModal != FleetSubModal.None and
                   state.subModal != FleetSubModal.OrderEntry
  let modal = widget.modal
    .maxWidth(desiredWidth)
    .minWidth(desiredWidth)
    .minHeight(if isSubModal: 0 else: 25)

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
      # Command picker: 20 commands + header + separator + borders + footer
      # Table base height: 4 (top border + header + separator + bottom border)
      # Footer: 2 lines
      let commandCount = 20
      let tableBaseHeight = 4
      let footerHeight = 2
      commandCount + tableBaseHeight + footerHeight
    of FleetSubModal.ROEPicker:
      # Table-based picker: itemCount + tableBase(4) + footer(2)
      let roeCount = 11
      let tableBaseHeight = 4
      let footerHeight = 2
      roeCount + tableBaseHeight + footerHeight
    of FleetSubModal.ConfirmPrompt:
      # Confirmation dialog: compact centered message
      10
    of FleetSubModal.OrderEntry:
      # OrderEntry: not rendered in modal (uses hex map), treat as None
      let shipsContentHeight = FleetDetailShipsHeaderHeight +
        shipTable.renderHeight(visibleRows)
      FleetDetailInfoHeight + FleetDetailSeparatorHeight +
        shipsContentHeight + FleetDetailFooterHeight
    of FleetSubModal.FleetPicker:
      # Table-based picker: itemCount + tableBase(4) + footer(2)
      let fleetCount = max(1, state.fleetPickerCandidates.len)
      let tableBaseHeight = 4
      let footerHeight = 2
      fleetCount + tableBaseHeight + footerHeight
    of FleetSubModal.Staged:
      # Staged: success message, compact
      8
    of FleetSubModal.ZTCPicker:
      # Table-based picker: itemCount + tableBase(4) + footer(2)
      let ztcCount = 9
      let tableBaseHeight = 4
      let footerHeight = 2
      ztcCount + tableBaseHeight + footerHeight
    of FleetSubModal.ShipSelector:
      # Placeholder for ship selection sub-modal
      10
    of FleetSubModal.CargoParams:
      # Placeholder for cargo parameter sub-modal
      10
    of FleetSubModal.FighterParams:
      # Placeholder for fighter parameter sub-modal
      10
    of FleetSubModal.None:
      # Normal fleet detail view with ship list
      let shipsContentHeight = FleetDetailShipsHeaderHeight +
        shipTable.renderHeight(visibleRows)
      FleetDetailInfoHeight + FleetDetailSeparatorHeight +
        shipsContentHeight + FleetDetailFooterHeight
  
  let modalArea = modal.calculateArea(viewport, contentHeight)

  # Render modal frame with title
  # Determine footer text per sub-modal (pickers get bordered footers too)
  let title = "FLEET DETAIL"
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
    else:
      (false, "")

  if hasFooter:
    modal.title(title).renderWithFooter(modalArea, buf, footerText)
  else:
    modal.title(title).render(modalArea, buf)

  # Get content area (excludes footer if present)
  let inner = modal.contentArea(modalArea, hasFooter = hasFooter)

  # Check for sub-modals
  case state.subModal
  of FleetSubModal.CommandPicker:
    renderCommandPicker(state, inner, buf)
  of FleetSubModal.ROEPicker:
    renderROEPicker(state, inner, buf)
  of FleetSubModal.ConfirmPrompt:
    renderConfirmDialog(state, inner, buf)
  of FleetSubModal.OrderEntry:
    # OrderEntry is handled by switching to Overview mode (hex map)
    # If we somehow end up here, render as if None
    # Fleet info section (top 4 lines)
    let infoArea = rect(inner.x, inner.y, inner.width,
      FleetDetailInfoHeight)
    renderFleetInfo(fleetData, infoArea, buf)
    
    # Separator
    let separatorY = inner.y + FleetDetailInfoHeight
    let bs = PlainBorderSet
    discard buf.put(modalArea.x, separatorY, "├", modalBorderStyle())
    for x in (modalArea.x + 1)..<(modalArea.right - 1):
      discard buf.put(x, separatorY, bs.horizontal, modalBorderStyle())
    discard buf.put(modalArea.right - 1, separatorY, "┤", modalBorderStyle())
    
    # Ship list (boxed table)
    let shipsHeight = max(1, inner.height - (FleetDetailInfoHeight +
      FleetDetailSeparatorHeight + FleetDetailFooterHeight))
    let shipsArea = rect(inner.x, separatorY + 1, inner.width, shipsHeight)
    let shipHeader = "SHIPS (" & $state.shipCount & ")"
    for i, ch in shipHeader:
      if shipsArea.x + i < shipsArea.right:
        discard buf.put(shipsArea.x + i, shipsArea.y, $ch,
          canvasHeaderStyle())
    
    let tableArea = rect(shipsArea.x,
      shipsArea.y + FleetDetailShipsHeaderHeight,
      shipsArea.width,
      shipsArea.height - FleetDetailShipsHeaderHeight)
    shipTable.render(tableArea, buf)
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
    renderPlaceholderSubModal("Ship Selector", inner, buf)
  of FleetSubModal.CargoParams:
    renderPlaceholderSubModal("Cargo Parameters", inner, buf)
  of FleetSubModal.FighterParams:
    renderPlaceholderSubModal("Fighter Parameters", inner, buf)
  of FleetSubModal.None:
    # Render main fleet detail view
    
    # Fleet info section (top 4 lines)
    let infoArea = rect(inner.x, inner.y, inner.width,
      FleetDetailInfoHeight)
    renderFleetInfo(fleetData, infoArea, buf)
    
    # Separator
    let separatorY = inner.y + FleetDetailInfoHeight
    let bs = PlainBorderSet
    discard buf.put(modalArea.x, separatorY, "├", modalBorderStyle())
    for x in (modalArea.x + 1)..<(modalArea.right - 1):
      discard buf.put(x, separatorY, bs.horizontal, modalBorderStyle())
    discard buf.put(modalArea.right - 1, separatorY, "┤", modalBorderStyle())
    
    # Ship list (boxed table)
    let shipsHeight = max(1, inner.height - (FleetDetailInfoHeight +
      FleetDetailSeparatorHeight + FleetDetailFooterHeight))
    let shipsArea = rect(inner.x, separatorY + 1, inner.width, shipsHeight)
    let shipHeader = "SHIPS (" & $state.shipCount & ")"
    for i, ch in shipHeader:
      if shipsArea.x + i < shipsArea.right:
        discard buf.put(shipsArea.x + i, shipsArea.y, $ch,
          canvasHeaderStyle())
    
    let tableArea = rect(shipsArea.x,
      shipsArea.y + FleetDetailShipsHeaderHeight,
      shipsArea.width,
      shipsArea.height - FleetDetailShipsHeaderHeight)
    shipTable.render(tableArea, buf)
