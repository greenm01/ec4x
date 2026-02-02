## Fleet Detail Modal - Modal for viewing fleet details and issuing commands
##
## A modal popup for viewing fleet composition and issuing commands via
## categorized command picker and ROE picker sub-modals.

import ./modal
import ./borders
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
  ## Render command picker sub-modal
  if area.isEmpty:
    return

  # Category tabs at top
  var x = area.x
  let y = area.y

  for cat in CommandCategory:
    let isSelected = state.commandCategory == cat
    let label = commandCategoryLabel(cat)
    let style = if isSelected:
      canvasHeaderStyle()
    else:
      canvasDimStyle()
    
    let tabText = if isSelected: "[" & label & "]" else: " " & label & " "
    for i, ch in tabText:
      if x + i < area.right:
        discard buf.put(x + i, y, $ch, style)
    x += tabText.len + 1

  # Command list
  let listArea = rect(area.x, area.y + 2, area.width, area.height - 3)
  var listY = listArea.y

  let commands = commandsInCategory(state.commandCategory)
  for idx, cmdType in commands:
    if listY >= listArea.bottom:
      break

    let isSelected = idx == state.commandIdx
    let prefix = if isSelected: "► " else: "  "
    let cmdLabel = fleetCommandLabel(cmdType)
    let cmdCode = fleetCommandCode(cmdType)
    let text = prefix & cmdCode & " " & cmdLabel

    let style = if isSelected:
      selectedStyle()
    else:
      canvasStyle()

    for i, ch in text:
      if area.x + i < area.right:
        discard buf.put(area.x + i, listY, $ch, style)

    listY += 1

  # Footer hint
  let footerY = area.bottom - 1
  if footerY >= area.y:
    let hint = "[Tab]Category [↑↓]Select [Enter]Confirm [Esc]Cancel"
    for i, ch in hint:
      if area.x + i < area.right:
        discard buf.put(area.x + i, footerY, $ch, canvasDimStyle())

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
    for i, ch in hint:
      if area.x + i < area.right:
        discard buf.put(area.x + i, footerY, $ch, canvasDimStyle())

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
  
  # Calculate modal area
  let contentHeight = 24
  let modalArea = widget.modal.calculateArea(viewport, contentHeight)

  # Render modal frame with title
  let title = "FLEET DETAIL"
  widget.modal.title(title).renderWithSeparator(modalArea, buf, 2)

  # Get inner content area
  let inner = widget.modal.inner(modalArea)

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
    let infoArea = rect(inner.x, inner.y, inner.width, 4)
    renderFleetInfo(fleetData, infoArea, buf)
    
    # Separator
    let separatorY = inner.y + 4
    let bs = PlainBorderSet
    discard buf.put(modalArea.x, separatorY, "├", modalBorderStyle())
    for x in (modalArea.x + 1)..<(modalArea.right - 1):
      discard buf.put(x, separatorY, bs.horizontal, modalBorderStyle())
    discard buf.put(modalArea.right - 1, separatorY, "┤", modalBorderStyle())
    
    # Ship list (using existing renderFleetShipsTable)
    let shipsArea = rect(inner.x, separatorY + 1, inner.width,
                        inner.height - 7)
    # Note: We'll need to call the table render from view_render
    # For now, just show placeholder
    var y = shipsArea.y
    let shipHeader = "SHIPS (" & $fleetData.ships.len & ")"
    for i, ch in shipHeader:
      if shipsArea.x + i < shipsArea.right:
        discard buf.put(shipsArea.x + i, y, $ch, canvasHeaderStyle())
    y += 1
    
    for idx, ship in fleetData.ships:
      if y >= shipsArea.bottom - 1:
        break
      let line = "  " & ship.name & " (" & ship.class & 
                ") AS:" & ship.attack & " DS:" & ship.defense
      for i, ch in line:
        if shipsArea.x + i < shipsArea.right:
          discard buf.put(shipsArea.x + i, y, $ch, canvasStyle())
      y += 1
    
    # Footer with action hints
    let footerY = inner.bottom - 1
    if footerY >= inner.y:
      let hint = "[C]Command [R]ROE [Esc]Close"
      for i, ch in hint:
        if inner.x + i < inner.right:
          discard buf.put(inner.x + i, footerY, $ch, canvasDimStyle())
