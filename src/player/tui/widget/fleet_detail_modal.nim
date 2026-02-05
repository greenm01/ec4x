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

proc roeLabel*(value: int): string =
  ## Get label for ROE value
  case value
  of 0: "Avoid"
  of 1: "Flee"
  of 2: "Flee"
  of 3: "Cautious"
  of 4: "Cautious"
  of 5: "Defensive"
  of 6: "Standard"
  of 7: "Aggressive"
  of 8: "Aggressive"
  of 9: "Desperate"
  of 10: "Suicidal"
  else: "Unknown"

proc roeDescription*(value: int): string =
  ## Get description for ROE value
  case value
  of 0: "Avoid all hostile forces"
  of 1: "Engage only defenseless targets"
  of 2: "Need 4:1 advantage to engage"
  of 3: "Need 3:1 advantage to engage"
  of 4: "Need 2:1 advantage to engage"
  of 5: "Need 3:2 advantage to engage"
  of 6: "Fight if equal or superior"
  of 7: "Fight even at 2:3 disadvantage"
  of 8: "Fight even at 1:2 disadvantage"
  of 9: "Fight even at 1:3 disadvantage"
  of 10: "Fight regardless of odds"
  else: ""

proc requiresConfirmation*(cmdType: FleetCommandType): bool =
  ## Check if command requires confirmation
  cmdType in {FleetCommandType.Bombard, FleetCommandType.Salvage,
              FleetCommandType.Reserve, FleetCommandType.Mothball}

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

  # Calculate visible rows and scrolling
  let commandCount = commands.len  # 20
  let availableHeight = area.height - 2  # Reserve 2 for footer
  let tableBaseHeight = 4  # header + separator + top/bottom borders
  let maxVisibleRows = max(1, availableHeight - tableBaseHeight)

  # Calculate scroll offset to keep selected item visible
  var scrollOffset = 0
  if maxVisibleRows < commandCount:
    if state.commandIdx >= scrollOffset + maxVisibleRows:
      scrollOffset = state.commandIdx - maxVisibleRows + 1
    elif state.commandIdx < scrollOffset:
      scrollOffset = state.commandIdx

  # Apply selection and scrolling
  commandTable = commandTable
    .selectedIdx(state.commandIdx)
    .scrollOffset(scrollOffset)

  # Render table
  let actualVisibleRows = min(commandCount - scrollOffset, maxVisibleRows)
  let tableHeight = commandTable.renderHeight(actualVisibleRows)
  let tableArea = rect(area.x, area.y, area.width, tableHeight)
  commandTable.render(tableArea, buf)

  # Render footer below table
  let footerY = tableArea.bottom + 1
  if footerY < area.bottom:
    let hint = "[↑↓]Select [00-19]Quick [Enter]Confirm [Esc]Cancel"
    let fullHint = if state.commandDigitBuffer.len > 0:
      "Cmd: " & state.commandDigitBuffer & "_ " & hint
    else:
      hint
    discard buf.setString(area.x, footerY, fullHint, canvasDimStyle())

proc renderROEPicker(state: FleetDetailModalState, area: Rect,
                    buf: var CellBuffer) =
  ## Render ROE picker sub-modal
  if area.isEmpty:
    return

  # Header
  var y = area.y
  let header = "Rules of Engagement"
  for i, ch in header:
    if area.x + i < area.right:
      discard buf.put(area.x + i, y, $ch, canvasHeaderStyle())
  y += 2

  # ROE values (0-10)
  for roe in 0..10:
    if y >= area.bottom - 2:
      break

    let isSelected = roe == state.roeValue
    let prefix = if isSelected: "► " else: "  "
    let roeNum = if roe < 10: " " & $roe else: $roe
    let label = roeLabel(roe)
    let desc = roeDescription(roe)
    let text = prefix & roeNum & "  " & label & " - " & desc

    let style = if isSelected:
      selectedStyle()
    else:
      canvasStyle()

    for i, ch in text:
      if area.x + i < area.right:
        discard buf.put(area.x + i, y, $ch, style)

    y += 1

  # Footer hint
  let footerY = area.bottom - 1
  if footerY >= area.y:
    let hint = "[↑↓]Select [Enter]Confirm [Esc]Cancel"
    discard buf.setString(area.x, footerY, hint, canvasDimStyle())

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

proc renderFleetInfo(fleetData: FleetDetailData, area: Rect,
                    buf: var CellBuffer) =
  ## Render basic fleet info (top section)
  if area.isEmpty:
    return

  var y = area.y

  # Fleet ID and location
  let line1 = "Fleet #" & $fleetData.fleetId & " at " & fleetData.location
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
  let line1 = "Fleet #" & $fleetData.fleetId & " at " & fleetData.location
  let line2 = "Command: " & fleetData.command & "  ROE: " & $fleetData.roe
  let line3 = "Ships: " & $state.shipCount & "  AS: " &
    $fleetData.totalAttack & "  DS: " & $fleetData.totalDefense
  let shipHeader = "SHIPS (" & $state.shipCount & ")"
  let infoWidth = max(line1.len,
    max(line2.len, max(line3.len, shipHeader.len)))
  let desiredInnerWidth = max(tableWidth, infoWidth)
  let desiredWidth = min(maxWidth, desiredInnerWidth + 2)
  let modal = widget.modal
    .maxWidth(desiredWidth)
    .minWidth(desiredWidth)

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
      # ROE picker: 11 values (0-10) + header + spacer + footer
      let roeCount = 11
      let headerHeight = 2  # "Rules of Engagement" + blank line
      let footerHeight = 2
      roeCount + headerHeight + footerHeight
    of FleetSubModal.ConfirmPrompt:
      # Confirmation dialog: compact centered message
      10
    of FleetSubModal.None:
      # Normal fleet detail view with ship list
      let shipsContentHeight = FleetDetailShipsHeaderHeight +
        shipTable.renderHeight(visibleRows)
      FleetDetailInfoHeight + FleetDetailSeparatorHeight +
        shipsContentHeight + FleetDetailFooterHeight
  
  let modalArea = modal.calculateArea(viewport, contentHeight)

  # Render modal frame with title and footer
  let title = "FLEET DETAIL"
  let footerText = "[C]Command [R]ROE [PgUp/PgDn]Scroll [Esc]Close"
  modal.title(title).renderWithFooter(modalArea, buf, footerText)

  # Get content area (excludes footer)
  let inner = modal.contentArea(modalArea, hasFooter = true)

  # Check for sub-modals
  case state.subModal
  of FleetSubModal.CommandPicker:
    renderCommandPicker(state, inner, buf)
  of FleetSubModal.ROEPicker:
    renderROEPicker(state, inner, buf)
  of FleetSubModal.ConfirmPrompt:
    renderConfirmDialog(state, inner, buf)
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
