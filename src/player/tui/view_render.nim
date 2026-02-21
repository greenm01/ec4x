## TUI view rendering helpers
##
## Rendering functions for the SAM-based TUI views.

import std/[options, unicode, strutils, tables]
import std/tables as stdtables

import ../../engine/types/[core, player_state as ps_types, fleet, colony,
  ground_unit, facilities, ship, tech]
import ../../engine/state/engine
import ../../engine/globals
import ../../engine/systems/tech/[advancement, costs]
import ../sam/sam_pkg
import ../sam/client_limits
import ../sam/command_parser
import ../tui/buffer
import ../tui/layout/layout_pkg
import ../tui/widget/[widget_pkg, frame, paragraph]
import ../tui/data/tech_info
import ../tui/widget/text_input
import ../tui/widget/overview
import ../tui/widget/breadcrumb
import ../tui/widget/command_dock
import ../tui/widget/progress_bar
import ../tui/widget/hud
import ../tui/widget/status_bar
import ../tui/styles/ec_palette
import ../tui/widget/modal
import ../tui/widget/table
import ../tui/cursor_target
import ../tui/widget/build_modal
import ../tui/widget/queue_modal
import ../tui/widget/fleet_detail_modal
import ../tui/widget/hexmap/symbols
import ../sam/bindings
import ../tui/adapters
import ../tui/columns
import ../tui/hex_labels
import ../tui/help_registry
import ../tui/data/research_projection
import ../tui/table_layout_policy
import ./sync
import ../../common/message_types

const
  ExpertPaletteMaxRows = 8
  ExpertPaletteMinWidth = 40
  ExpertPaletteMaxWidth = 80
  IntelNotesPreviewMaxRunes = 80

var
  cachedExpertInput = ""
  cachedExpertMatches: seq[ExpertCommandMatch] = @[]

proc renderResearchPanel(area: Rect, buf: var CellBuffer, model: TuiModel)

proc helpContextFor(model: TuiModel): HelpContext =
  case model.ui.mode
  of ViewMode.Overview:
    HelpContext.Overview
  of ViewMode.Planets, ViewMode.PlanetDetail:
    HelpContext.Planets
  of ViewMode.Fleets:
    if model.ui.fleetViewMode == FleetViewMode.ListView:
      HelpContext.FleetList
    else:
      HelpContext.FleetConsole
  of ViewMode.FleetDetail:
    HelpContext.FleetDetail
  of ViewMode.Research:
    HelpContext.Research
  of ViewMode.Espionage:
    HelpContext.Espionage
  of ViewMode.Economy:
    HelpContext.Economy
  of ViewMode.IntelDb:
    HelpContext.IntelDb
  of ViewMode.IntelDetail:
    HelpContext.IntelDb
  of ViewMode.Settings:
    HelpContext.Settings
  of ViewMode.Messages:
    HelpContext.Messages

proc renderHelpOverlay(area: Rect, buf: var CellBuffer, model: TuiModel) =
  if not model.ui.showHelpOverlay:
    return
  if model.ui.appPhase != AppPhase.InGame:
    return
  if area.width < 20 or area.height < 6:
    return
  let ctx = helpContextFor(model)
  var lines = helpLines(ctx)
  if lines.len == 0:
    lines = @["No help available for this screen."]
  let footerText = "Ctrl+/ Toggle Help"
  let footerHeight = 2
  let maxVisible = max(1, area.height - footerHeight - 2)
  let visible = min(lines.len, maxVisible)
  var maxLen = 0
  for i in 0 ..< visible:
    if lines[i].len > maxLen:
      maxLen = lines[i].len
  let maxWidth = max(20, area.width - 2)
  let width = clamp(maxLen + 2, 20, maxWidth)
  let height = min(area.height, visible + footerHeight + 2)
  let x = area.x + (area.width - width) div 2
  let y = area.bottom - height
  let modalArea = rect(x, y, width, height)
  let modal = newModal()
    .title("HELP")
    .maxWidth(width)
    .minWidth(width)
    .minHeight(height)
    .showBackdrop(true)
    .borderStyle(outerBorderStyle())
    .bgStyle(modalBgStyle())
  modal.renderWithFooter(modalArea, buf, footerText)
  let contentArea = modal.contentArea(modalArea, hasFooter = true)
  for i in 0 ..< visible:
    let rowY = contentArea.y + i
    if rowY >= contentArea.bottom:
      break
    var line = lines[i]
    if line.len > contentArea.width:
      line = line[0 ..< contentArea.width]
    discard buf.setString(contentArea.x, rowY, line, canvasStyle())

proc expertMatchesCached(input: string): seq[ExpertCommandMatch] =
  if input != cachedExpertInput:
    cachedExpertInput = input
    cachedExpertMatches = matchExpertCommands(input)
  cachedExpertMatches

proc dimStyle*(): CellStyle =
  canvasDimStyle()

proc normalStyle*(): CellStyle =
  canvasStyle()

proc formatGrowthLabel*(growthOpt: Option[float32]): string =
  if growthOpt.isNone:
    return "—"
  let growth = growthOpt.get()
  let sign = if growth >= 0: "+" else: ""
  sign & formatFloat(growth, ffDecimal, 1)

proc dockLabel*(available, total: int): string =
  if total <= 0:
    "—"
  else:
    $available & "/" & $total

proc buildMatchSpans(label: string, matchIndices: seq[int],
                     normalStyle: CellStyle, matchStyle: CellStyle):
                     seq[Span] =
  ## Build spans with highlighted match indices
  var spans: seq[Span] = @[]
  var current = ""
  var currentStyle = normalStyle
  var matchIdx = 0

  for i in 0 ..< label.len:
    let isMatch = matchIdx < matchIndices.len and
      matchIndices[matchIdx] == i
    if isMatch:
      matchIdx += 1
    let nextStyle = if isMatch: matchStyle else: normalStyle
    if nextStyle != currentStyle and current.len > 0:
      spans.add(span(current, currentStyle))
      current = ""
    if nextStyle != currentStyle:
      currentStyle = nextStyle
    current.add(label[i])

  if current.len > 0:
    spans.add(span(current, currentStyle))

  spans

proc renderExpertPalette*(buf: var CellBuffer, canvasArea: Rect,
                          dockArea: Rect, model: TuiModel) =
  ## Render helix-style expert command palette above the dock
  if not model.ui.expertModeActive:
    return

  let matches = expertMatchesCached(model.ui.expertModeInput.value())
  if matches.len == 0:
    return

  let visibleRows = min(ExpertPaletteMaxRows, matches.len)
  let paletteHeight = visibleRows + 2
  if dockArea.y - paletteHeight < canvasArea.y:
    return

  let width = min(ExpertPaletteMaxWidth, canvasArea.width)
  if width < ExpertPaletteMinWidth:
    return

  let x = canvasArea.x + (canvasArea.width - width) div 2
  let y = dockArea.y - paletteHeight
  let paletteArea = rect(x, y, width, paletteHeight)

  let frame = bordered()
    .title("Commands")
    .borderType(BorderType.Plain)
    .borderStyle(modalBorderStyle())
    .style(modalBgStyle())
  frame.render(paletteArea, buf)
  let inner = frame.inner(paletteArea)
  if inner.isEmpty:
    return

  buf.fillArea(inner, " ", modalBgStyle())

  let normalStyle = modalBgStyle()
  let dimStyle = modalDimStyle()
  let matchStyle = prestigeStyle()

  var items: seq[ListItem] = @[]
  for match in matches:
    let labelSpans = buildMatchSpans(
      match.label,
      match.matchIndices,
      normalStyle,
      matchStyle
    )
    var lineSpans = labelSpans
    let hint = expertCommandHint(match.command)
    if hint.len > 0:
      lineSpans.add(span("  ", dimStyle))
      lineSpans.add(span(hint, dimStyle))
    items.add(listItem(text(line(lineSpans))))

  var palette = list(items)
    .style(modalBgStyle())
    .highlightStyle(selectedStyle())
    .highlightSymbol("")

  var state = newListState()
  if model.ui.expertPaletteSelection >= 0 and
      model.ui.expertPaletteSelection < matches.len:
    state.select(model.ui.expertPaletteSelection)
  palette.render(inner, buf, state)

proc renderQuitConfirmation*(buf: var CellBuffer, model: TuiModel) =
  ## Render quit confirmation modal
  if not model.ui.quitConfirmationActive:
    return

  if model.ui.termWidth < 30 or model.ui.termHeight < 7:
    return

  let width = min(56, model.ui.termWidth - 4)
  let height = 7
  let x = (model.ui.termWidth - width) div 2
  let y = (model.ui.termHeight - height) div 2
  let modalArea = rect(x, y, width, height)

  buf.fillArea(modalArea, " ", modalBgStyle())

  let frame = bordered()
    .title("Confirm Quit")
    .borderType(BorderType.Plain)
    .borderStyle(modalBorderStyle())
    .style(modalBgStyle())
  frame.render(modalArea, buf)
  let inner = frame.inner(modalArea)
  if inner.isEmpty:
    return

  let messageX = inner.x + 2
  var currentY = inner.y + 1
  discard buf.setString(
    messageX, currentY,
    "Are you sure you want to quit?",
    modalBgStyle()
  )
  currentY += 2

  let stagedCount = model.stagedCommandCount()
  if stagedCount > 0 and currentY < inner.bottom - 2:
    let warningStyle = CellStyle(
      fg: color(AlertColor),
      bg: color(TrueBlackColor),
      attrs: {StyleAttr.Bold}
    )
    discard buf.setString(
      messageX, currentY,
      "You have " & $stagedCount & " staged command(s).",
      warningStyle
    )
    currentY += 1

  if currentY < inner.bottom:
    let choice = model.ui.quitConfirmationChoice
    let normalStyle = modalDimStyle()
    let highlightStyle = selectedStyle()
    let quitStyle =
      if choice == QuitConfirmationChoice.QuitExit:
        highlightStyle
      else:
        normalStyle
    let stayStyle =
      if choice == QuitConfirmationChoice.QuitStay:
        highlightStyle
      else:
        normalStyle
    let quitMarkerLeft =
      if choice == QuitConfirmationChoice.QuitExit:
        ">"
      else:
        " "
    let quitMarkerRight =
      if choice == QuitConfirmationChoice.QuitExit:
        "<"
      else:
        " "
    let stayMarkerLeft =
      if choice == QuitConfirmationChoice.QuitStay:
        ">"
      else:
        " "
    let stayMarkerRight =
      if choice == QuitConfirmationChoice.QuitStay:
        "<"
      else:
        " "
    let line =
      "[Y] " & quitMarkerLeft & "Quit" & quitMarkerRight &
      "  [N] " & stayMarkerLeft & "Stay" & stayMarkerRight
    let lineX = inner.x + max(0, (inner.width - line.len) div 2)
    var x = lineX
    discard buf.setString(x, currentY, "[Y] ", normalStyle)
    x += 4
    discard buf.setString(x, currentY, quitMarkerLeft, quitStyle)
    x += 1
    discard buf.setString(x, currentY, "Quit", quitStyle)
    x += 4
    discard buf.setString(x, currentY, quitMarkerRight, quitStyle)
    x += 1
    discard buf.setString(x, currentY, "  [N] ", normalStyle)
    x += 6
    discard buf.setString(x, currentY, stayMarkerLeft, stayStyle)
    x += 1
    discard buf.setString(x, currentY, "Stay", stayStyle)
    x += 4
    discard buf.setString(x, currentY, stayMarkerRight, stayStyle)

proc renderColonyList*(area: Rect, buf: var CellBuffer, model: TuiModel) =
  ## Render list of player's colonies from SAM model
  if area.isEmpty:
    return

  let footerHeight = if area.height >= 4: 1 else: 0
  let tableHeight = area.height - footerHeight
  if tableHeight <= 0:
    return

  let tableArea = rect(area.x, area.y, area.width, tableHeight)
  proc displayedQueueCount(row: PlanetRow): int =
    result = row.queueCount
    if row.colonyId.isNone:
      return
    let colonyId = ColonyId(row.colonyId.get().uint32)
    for cmd in model.ui.stagedBuildCommands:
      if cmd.colonyId == colonyId and cmd.quantity > 0:
        result += cmd.quantity

  let columns = @[
    tableColumn("System", 6, table.Alignment.Center),
    tableColumn("Name", 14, table.Alignment.Left),
    tableColumn("Status", 7, table.Alignment.Left),
    tableColumn("Queue", 5, table.Alignment.Right),
    tableColumn("Class", 5, table.Alignment.Center),
    tableColumn("Resource", 8, table.Alignment.Center),
    tableColumn("PU", 6, table.Alignment.Right),
    tableColumn("Industry", 8, table.Alignment.Right),
    tableColumn("Growth", 6, table.Alignment.Right),
    tableColumn("Fleets", 6, table.Alignment.Right),
    tableColumn("Starbase", 8, table.Alignment.Right),
    tableColumn("C-Dock", 6, table.Alignment.Right),
    tableColumn("R-Dock", 6, table.Alignment.Right),
    tableColumn("A+M", 6, table.Alignment.Right),
    tableColumn("Battery", 7, table.Alignment.Right),
    tableColumn("Shield", 6, table.Alignment.Center)
  ]

  var colonyTable = table(columns)
    .selectedIdx(model.ui.selectedIdx)
    .zebraStripe(true)
    .showBorders(false)

  let statusColumn = 2
  for row in model.view.planetsRows:
    let popLabel = if row.pop.isSome: $row.pop.get else: "-"
    let iuLabel = if row.iu.isSome: $row.iu.get else: "-"
    let gcoLabel = if row.gco.isSome: $row.gco.get else: "-"
    let ncvLabel = if row.ncv.isSome: $row.ncv.get else: "-"
    let cdLabel = if row.cdTotal.isSome: $row.cdTotal.get else: "-"
    let rdLabel = if row.rdTotal.isSome: $row.rdTotal.get else: "-"
    let shieldLabel = if row.shieldPresent: "Y" else: "N"

    var statusStyle = normalStyle()
    var statusLabel = row.statusLabel
    if row.hasAlert:
      statusStyle = alertStyle()
      statusLabel = GlyphWarning & " " & statusLabel

    let dataRow = @[
      row.sectorLabel,
      row.systemName,
      statusLabel,
      $displayedQueueCount(row),
      row.classLabel,
      row.resourceLabel,
      popLabel,
      iuLabel,
      row.growthLabel,
      $row.fleetCount,
      $row.starbaseCount,
      cdLabel,
      rdLabel,
      $row.groundCount,
      $row.batteryCount,
      shieldLabel
    ]

    colonyTable.addRow(dataRow, statusStyle, statusColumn)

  colonyTable.render(tableArea, buf)

  if footerHeight > 0 and area.height > 1:
    let footerY = area.y + tableHeight
    let summary = $model.view.planetsRows.len & " colonies"
    let clipped = summary[0 ..< min(summary.len, area.width)]
    discard buf.setString(area.x, footerY, clipped, dimStyle())

proc buildPlanetsTable*(model: TuiModel, scroll: ScrollState): table.Table =
  ## Build Colony table per spec (boxed)
  let columns = planetsColumns()
  proc displayedQueueCount(row: PlanetRow): int =
    result = row.queueCount
    if row.colonyId.isNone:
      return
    let colonyId = ColonyId(row.colonyId.get().uint32)
    for cmd in model.ui.stagedBuildCommands:
      if cmd.colonyId == colonyId and cmd.quantity > 0:
        result += cmd.quantity

  let startIdx = scroll.verticalOffset
  let endIdx = min(model.view.planetsRows.len,
    startIdx + scroll.viewportLength)
  let selectedIdx =
    if model.ui.selectedIdx >= startIdx and
        model.ui.selectedIdx < endIdx:
      model.ui.selectedIdx - startIdx
    else:
      -1

  result = table(columns)
    .selectedIdx(selectedIdx)
    .zebraStripe(true)
    .showBorders(true)

  if startIdx >= endIdx:
    return

  for i in startIdx ..< endIdx:
    let row = model.view.planetsRows[i]
    let popLabel = if row.pop.isSome: $row.pop.get else: "—"
    let iuLabel = if row.iu.isSome: $row.iu.get else: "—"
    let gcoLabel = if row.gco.isSome: $row.gco.get else: "—"
    let ncvLabel = if row.ncv.isSome: $row.ncv.get else: "—"
    let cdLabel = if row.cdTotal.isSome: $row.cdTotal.get else: "—"
    let rdLabel = if row.rdTotal.isSome: $row.rdTotal.get else: "—"
    let shieldLabel = if row.shieldPresent: "Y" else: "N"

    var statusStyle = normalStyle()
    var statusLabel = row.statusLabel
    if row.hasAlert:
      statusStyle = alertStyle()
      statusLabel = GlyphWarning & " " & statusLabel

    let dataRow = @[
      row.sectorLabel,
      row.systemName,
      statusLabel,
      $displayedQueueCount(row),
      row.classLabel,
      row.resourceLabel,
      popLabel,
      iuLabel,
      row.growthLabel,
      $row.fleetCount,
      $row.starbaseCount,
      cdLabel,
      rdLabel,
      $row.groundCount,
      $row.batteryCount,
      shieldLabel
    ]

    result.addRow(dataRow, statusStyle, 2)

proc renderIntelDbTable*(area: Rect, buf: var CellBuffer,
                         model: TuiModel, scroll: ScrollState) =
  ## Render Intel DB table (starmap database)
  if area.isEmpty:
    return

  let columns = @[
    tableColumn("System", 6, table.Alignment.Center),
    tableColumn("Name", 18, table.Alignment.Left),
    tableColumn("Owner", 10, table.Alignment.Left),
    tableColumn("Intel", 6, table.Alignment.Left),
    tableColumn("LTU", 4, table.Alignment.Right),
    tableColumn("Notes", IntelNotesPreviewMaxRunes, table.Alignment.Left)
  ]

  let startIdx = scroll.verticalOffset
  let endIdx = min(model.view.intelRows.len,
    startIdx + scroll.viewportLength)
  let selectedIdx =
    if model.ui.selectedIdx >= startIdx and
        model.ui.selectedIdx < endIdx:
      model.ui.selectedIdx - startIdx
    else:
      -1

  var intelTable = table(columns)
    .selectedIdx(selectedIdx)
    .zebraStripe(true)

  if startIdx >= endIdx:
    intelTable.render(area, buf)
    return

  for i in startIdx ..< endIdx:
    let row = model.view.intelRows[i]
    var notePreview = row.notes
      .replace("\n", " ↵ ")
      .replace("\t", " ")
    if notePreview.runeLen > IntelNotesPreviewMaxRunes:
      var clipped = ""
      var runeCount = 0
      for rune in notePreview.runes:
        if runeCount >= IntelNotesPreviewMaxRunes - 3:
          break
        clipped.add(rune.toUTF8)
        runeCount.inc
      notePreview = clipped & "..."
    let dataRow = @[
      row.sectorLabel,
      row.systemName,
      row.ownerName,
      row.intelLabel,
      row.ltuLabel,
      notePreview
    ]
    intelTable.addRow(dataRow)

  intelTable.render(area, buf)

proc fleetFlag(
  needsAttention: bool,
  isSelected: bool,
  hasStaged: bool
): string =
  if isSelected:
    return "X"
  if needsAttention:
    return GlyphWarning
  if hasStaged:
    return GlyphOk
  " "

proc buildFleetListTable*(model: TuiModel,
                          scroll: ScrollState): table.Table =
  ## Build fleet list table (ListView)
  let columns = fleetListColumns()
  let fleets = model.filteredFleets()
  let startIdx = scroll.verticalOffset
  let endIdx = min(fleets.len, startIdx + scroll.viewportLength)
  let selectedIdx =
    if model.ui.selectedIdx >= startIdx and
        model.ui.selectedIdx < endIdx:
      model.ui.selectedIdx - startIdx
    else:
      -1

  result = table(columns)
    .selectedIdx(selectedIdx)
    .zebraStripe(true)
    .showBorders(true)
    .sortColumn(
      model.ui.fleetListState.sortState.columnIdx,
      model.ui.fleetListState.sortState.ascending)

  if startIdx >= endIdx:
    return

  for i in startIdx ..< endIdx:
    let fleet = fleets[i]
    let flag = fleetFlag(
      fleet.needsAttention,
      model.isFleetSelected(fleet.id),
      fleet.id in model.ui.stagedFleetCommands
    )
    let etaLabel = if fleet.destinationSystemId != 0:
      $fleet.eta
    else:
      "-"
    let dataRow = @[
      flag,
      fleet.name,
      fleet.locationName,
      fleet.sectorLabel,
      $fleet.shipCount,
      $fleet.attackStrength,
      $fleet.defenseStrength,
      fleet.commandLabel,
      fleet.destinationLabel,
      etaLabel,
      $fleet.roe,
      fleet.statusLabel
    ]
    result.addRow(dataRow)

proc renderFleetList*(area: Rect, buf: var CellBuffer, model: TuiModel) =
  ## Render fleet list table (ListView)
  if area.isEmpty:
    return

  let fleets = model.filteredFleets()
  let columns = fleetListColumns()
  let maxTableWidth = area.width
  let tableWidth = tableWidthFromColumns(columns, maxTableWidth,
    showBorders = true)

  let visibleRows = clampedVisibleRows(
    fleets.len,
    area.height,
    TableChromeRows
  )

  var localScroll = model.ui.fleetsScroll
  localScroll.contentLength = fleets.len
  localScroll.viewportLength = visibleRows
  localScroll.clampOffsets()

  let table = buildFleetListTable(model, localScroll)
  let tableHeight = table.renderHeight(visibleRows)
  let tableArea = rect(area.x, area.y, tableWidth,
    min(tableHeight, area.height))
  table.render(tableArea, buf)

# ============================================================================
# Deprecated: Old fleet detail render functions (replaced by modal)
# ============================================================================
# renderFleetDetail and renderFleetDetailFromPS have been removed.
# Fleet details are now shown in a popup modal (fleet_detail_modal.nim)
# triggered by pressing Enter on a fleet in the Fleets view.

proc renderFleetConsoleSystems(
  area: Rect,
  buf: var CellBuffer,
  systems: seq[FleetConsoleSystem],
  selectedIdx: int,
  hasFocus: bool,
  scrollOffset: int = 0
) =
  ## Render systems pane as table (systems with fleets)
  if area.isEmpty:
    return
  
  # Build table using shared column definitions
  let columns = fleetConsoleSystemsColumns()
  
  var systemsTable = table(columns)
    .showBorders(true)
    .scrollOffset(scrollOffset)
  
  # Only show selection if this pane has focus
  if hasFocus and selectedIdx >= 0 and selectedIdx < systems.len:
    systemsTable = systemsTable.selectedIdx(selectedIdx)
  
  # Add rows
  for sys in systems:
    systemsTable.addRow([sys.systemName, sys.sectorLabel])
  
  # Render table
  systemsTable.render(area, buf)

proc renderFleetConsoleFleets(
  area: Rect,
  buf: var CellBuffer,
  fleets: seq[FleetConsoleFleet],
  selectedIdx: int,
  hasFocus: bool,
  stagedCommands: stdtables.Table[int, FleetCommand],
  selectedFleetIds: seq[int],
  scrollOffset: int = 0
) =
  ## Render fleets pane as table (fleets at selected system)
  if area.isEmpty:
    return
  
  # Build table using shared column definitions
  let columns = fleetConsoleFleetsColumns()
  
  var fleetsTable = table(columns)
    .showBorders(true)
    .scrollOffset(scrollOffset)
  
  # Only show selection if this pane has focus
  if hasFocus and selectedIdx >= 0 and selectedIdx < fleets.len:
    fleetsTable = fleetsTable.selectedIdx(selectedIdx)
  
  # Add rows
  for flt in fleets:
    let flag = fleetFlag(
      flt.needsAttention,
      flt.fleetId in selectedFleetIds,
      flt.fleetId in stagedCommands
    )
    
    fleetsTable.addRow([
      flag,
      flt.name,
      $flt.shipCount,
      $flt.attackStrength,
      $flt.defenseStrength,
      $flt.troopTransports,
      $flt.etacs,
      flt.commandLabel,
      flt.destinationLabel,
      $flt.eta,
      $flt.roe,
      flt.status
    ])
  
  # Render table
  fleetsTable.render(area, buf)

proc renderFleetConsole*(
  area: Rect,
  buf: var CellBuffer,
  model: var TuiModel,
  ps: ps_types.PlayerState
) =
  ## Render 2-pane fleet console (SystemView mode)
  ## Layout: Full height, two columns side-by-side
  ## Left column: Systems pane (exact width needed)
  ## Right column: Fleets pane (exact width needed)
  ## Detail view is now a popup modal (opened with Enter)
  
  if area.isEmpty or area.height < 6:
    return
  
  # Calculate exact widths needed for each table
  let systemsWidth = tableWidthFromColumns(
    fleetConsoleSystemsColumns(), area.width, showBorders = true)
  let fleetsWidth = tableWidthFromColumns(
    fleetConsoleFleetsColumns(), area.width, showBorders = true)
  
  let systemsPane = rect(area.x, area.y, systemsWidth, area.height)
  let fleetsPane = rect(area.x + systemsWidth, area.y, fleetsWidth, area.height)
  
  # Use cached data from model (synced in syncPlayerStateToModel)
  let systems = model.ui.fleetConsoleSystems
  
  # Determine selected system
  let systemIdx = clamp(model.ui.fleetConsoleSystemIdx, 0,
    max(0, systems.len - 1))
  
  # Get fleets for selected system from cache
  var fleets: seq[FleetConsoleFleet] = @[]
  if systems.len > 0:
    let selectedSystemId = systems[systemIdx].systemId
    if stdtables.hasKey(model.ui.fleetConsoleFleetsBySystem, selectedSystemId):
      fleets = model.ui.fleetConsoleFleetsBySystem[selectedSystemId]
  
  let effectiveFocus = if model.ui.fleetConsoleFocus == FleetConsoleFocus.ShipsPane:
      FleetConsoleFocus.FleetsPane
    else:
      model.ui.fleetConsoleFocus

  let systemsFocused = effectiveFocus == FleetConsoleFocus.SystemsPane
  let fleetsFocused = effectiveFocus == FleetConsoleFocus.FleetsPane

  let systemsFrame = bordered()
    .title("SYSTEMS")
    .borderType(BorderType.Rounded)
    .borderStyle(modalPanelBorderStyle(systemsFocused))
  systemsFrame.render(systemsPane, buf)
  let systemsInner = systemsFrame.inner(systemsPane)

  let fleetsFrame = bordered()
    .title("FLEETS")
    .borderType(BorderType.Rounded)
    .borderStyle(modalPanelBorderStyle(fleetsFocused))
  fleetsFrame.render(fleetsPane, buf)
  let fleetsInner = fleetsFrame.inner(fleetsPane)

  # Keep pane scroll viewports synchronized with actual rendered table rows.
  let systemsViewportRows = max(
    1, systemsInner.height - TableChromeRows
  )
  model.ui.fleetConsoleSystemScroll.contentLength = systems.len
  model.ui.fleetConsoleSystemScroll.viewportLength = systemsViewportRows
  model.ui.fleetConsoleSystemScroll.verticalOffset = clampScrollOffset(
    model.ui.fleetConsoleSystemScroll.verticalOffset,
    systems.len,
    systemsViewportRows
  )

  let fleetsViewportRows = max(
    1, fleetsInner.height - TableChromeRows
  )
  model.ui.fleetConsoleFleetScroll.contentLength = fleets.len
  model.ui.fleetConsoleFleetScroll.viewportLength = fleetsViewportRows
  model.ui.fleetConsoleFleetScroll.verticalOffset = clampScrollOffset(
    model.ui.fleetConsoleFleetScroll.verticalOffset,
    fleets.len,
    fleetsViewportRows
  )

  # Render systems pane
  renderFleetConsoleSystems(systemsInner, buf, systems, systemIdx,
    effectiveFocus == FleetConsoleFocus.SystemsPane,
    model.ui.fleetConsoleSystemScroll.verticalOffset)
  
  # Render fleets pane
  let fleetIdx = clamp(model.ui.fleetConsoleFleetIdx, 0,
    max(0, fleets.len - 1))
  renderFleetConsoleFleets(fleetsInner, buf, fleets, fleetIdx,
    effectiveFocus == FleetConsoleFocus.FleetsPane,
    model.ui.stagedFleetCommands,
    model.ui.selectedFleetIds,
    model.ui.fleetConsoleFleetScroll.verticalOffset)

proc renderPlanetSummaryTab*(
  area: Rect,
  buf: var CellBuffer,
  data: PlanetDetailData
) =
  if area.isEmpty:
    return

  var y = area.y
  discard buf.setString(
    area.x, y,
    "COLONY: " & data.systemName,
    canvasHeaderStyle()
  )
  y += 1
  if y >= area.bottom:
    return

  let locationLine =
    "Location: " & data.sectorLabel & "  Class: " & data.planetClass
  discard buf.setString(area.x, y, locationLine, normalStyle())
  y += 1
  if y >= area.bottom:
    return

  let rawLabel = formatFloat(data.rawIndex, ffDecimal, 2)
  let resourceLine =
    "Resources: " & data.resourceRating & "  RAW: " & rawLabel
  discard buf.setString(area.x, y, resourceLine, normalStyle())
  y += 1
  if y >= area.bottom:
    return

  let growthLabel = formatGrowthLabel(data.populationGrowthPu)
  let economyLine =
    "GCO: " & $data.gco & "  NCV: " & $data.ncv &
    "  Tax: " & $data.taxRate & "%" &
    "  Growth: " & growthLabel
  discard buf.setString(area.x, y, economyLine, normalStyle())
  y += 1
  if y >= area.bottom:
    return

  let columnsArea = rect(area.x, y, area.width, area.bottom - y)
  if columnsArea.height <= 0:
    return
  let columns = horizontal()
    .constraints(percentage(50), fill())
    .split(columnsArea)

  let left = columns[0]
  let right = columns[1]

  var leftY = left.y
  discard buf.setString(left.x, leftY, "SURFACE", canvasHeaderStyle())
  leftY += 1
  if leftY < left.bottom:
    discard buf.setString(
      left.x, leftY,
      "Population: " & $data.populationUnits & " PU",
      normalStyle()
    )
    leftY += 1
  if leftY < left.bottom:
    discard buf.setString(
      left.x, leftY,
      "Industrial: " & $data.industrialUnits & " IU",
      normalStyle()
    )
    leftY += 1
  if leftY < left.bottom:
    discard buf.setString(
      left.x, leftY,
      "Armies: " & $data.armies & "  Marines: " & $data.marines,
      normalStyle()
    )
    leftY += 1
  if leftY < left.bottom:
    discard buf.setString(
      left.x, leftY,
      "Batteries: " & $data.batteries,
      normalStyle()
    )
    leftY += 1
  if leftY < left.bottom:
    let shieldLabel = if data.shields > 0: "Present" else: "None"
    discard buf.setString(
      left.x, leftY,
      "Shields: " & shieldLabel,
      normalStyle()
    )

  var rightY = right.y
  discard buf.setString(right.x, rightY, "ORBITAL", canvasHeaderStyle())
  rightY += 1
  if rightY < right.bottom:
    let facilityLine =
      "Spaceports: " & $data.spaceports &
      "  Shipyards: " & $data.shipyards
    discard buf.setString(right.x, rightY, facilityLine, normalStyle())
    rightY += 1
  if rightY < right.bottom:
    let orbitalLine =
      "Drydocks: " & $data.drydocks &
      "  Starbases: " & $data.starbases
    discard buf.setString(right.x, rightY, orbitalLine, normalStyle())
    rightY += 1
  if rightY < right.bottom:
    let dockLine =
      "Docks: CD " & $data.dockSummary.constructionTotal &
      "  RD " & $data.dockSummary.repairTotal
    discard buf.setString(right.x, rightY, dockLine, normalStyle())
    rightY += 1

proc renderPlanetEconomyTab*(
  area: Rect,
  buf: var CellBuffer,
  data: PlanetDetailData
) =
  if area.isEmpty:
    return

  var y = area.y
  discard buf.setString(area.x, y, "COLONY ECONOMY", canvasHeaderStyle())
  y += 1
  if y >= area.bottom:
    return

  let headline =
    "GCO: " & $data.gco & "  NCV: " & $data.ncv &
    "  Tax: " & $data.taxRate & "%"
  discard buf.setString(area.x, y, headline, normalStyle())
  y += 1
  if y >= area.bottom:
    return

  let outputLine =
    "Population: " & $data.populationOutput &
    "  Industry: " & $data.industrialOutput
  discard buf.setString(area.x, y, outputLine, normalStyle())
  y += 1
  if y >= area.bottom:
    return

  let growthLabel = formatGrowthLabel(data.populationGrowthPu)
  let bonusLine =
    "Starbase bonus: " & $data.starbaseBonusPct & "%" &
    "  Growth: " & growthLabel
  discard buf.setString(area.x, y, bonusLine, normalStyle())
  y += 1

  if data.blockaded and y < area.bottom:
    discard buf.setString(
      area.x, y,
      "Blockaded: output reduced",
      alertStyle()
    )

proc renderPlanetConstructionTab*(
  area: Rect,
  buf: var CellBuffer,
  data: PlanetDetailData
) =
  if area.isEmpty:
    return

  var y = area.y
  let docksLine =
    "Docks: CD " & $data.dockSummary.constructionTotal &
    "  RD " & $data.dockSummary.repairTotal
  discard buf.setString(area.x, y, docksLine, canvasHeaderStyle())
  y += 1
  if y >= area.bottom:
    return

  let contentArea = rect(area.x, y, area.width, area.bottom - y)
  let sections = vertical()
    .constraints(percentage(45), fill())
    .split(contentArea)
  let queueArea = sections[0]
  let buildArea = sections[1]

  if queueArea.height > 0:
    discard buf.setString(queueArea.x, queueArea.y, "QUEUE",
      canvasHeaderStyle())
    let queueInner = rect(
      queueArea.x,
      queueArea.y + 1,
      queueArea.width,
      max(0, queueArea.height - 1)
    )
    if queueInner.height > 0:
      if data.queue.len > 0:
        var queueTable = table([
        tableColumn("Type", 6, table.Alignment.Left),
        tableColumn("Item", 18, table.Alignment.Left),
        tableColumn("Cost", 6, table.Alignment.Right),
        tableColumn("Status", 10, table.Alignment.Left)
        ])
        for item in data.queue:
          let kindLabel =
            if item.kind == QueueKind.Construction: "Build" else: "Repair"
          queueTable.addRow(@[
            kindLabel,
            item.name,
            $item.cost,
            item.status
          ])
        queueTable.render(queueInner, buf)
      else:
        discard buf.setString(queueInner.x, queueInner.y,
          "No queued projects", dimStyle())

  if buildArea.height > 0:
    discard buf.setString(buildArea.x, buildArea.y, "AVAILABLE TO BUILD",
      canvasHeaderStyle())
    let buildInner = rect(
      buildArea.x,
      buildArea.y + 1,
      buildArea.width,
      max(0, buildArea.height - 1)
    )
    if buildInner.height > 0:
      if data.buildOptions.len > 0:
        var buildTable = table([
        tableColumn("Item", 18, table.Alignment.Left),
        tableColumn("Cost", 6, table.Alignment.Right),
        tableColumn("CST", 4, table.Alignment.Right),
        tableColumn("Kind", 8, table.Alignment.Left)
        ])
        for option in data.buildOptions:
          let kindLabel =
            case option.kind
            of BuildOptionKind.Ship: "Ship"
            of BuildOptionKind.Ground: "Ground"
            of BuildOptionKind.Facility: "Facility"
          buildTable.addRow(@[
            option.name,
            $option.cost,
            $option.cstReq,
            kindLabel
          ])
        buildTable.render(buildInner, buf)
      else:
        discard buf.setString(buildInner.x, buildInner.y,
          "No build options", dimStyle())

proc renderPlanetDefenseTab*(
  area: Rect,
  buf: var CellBuffer,
  data: PlanetDetailData
) =
  if area.isEmpty:
    return

  let columns = horizontal()
    .constraints(percentage(50), fill())
    .split(area)
  let left = columns[0]
  let right = columns[1]

  var leftY = left.y
  discard buf.setString(left.x, leftY, "ORBITAL DEFENSES",
    canvasHeaderStyle())
  leftY += 1
  if leftY < left.bottom:
    discard buf.setString(left.x, leftY,
      "Starbases: " & $data.starbases, normalStyle())
    leftY += 1
  if leftY < left.bottom:
    discard buf.setString(left.x, leftY,
      "Shipyards: " & $data.shipyards, normalStyle())
    leftY += 1
  if leftY < left.bottom:
    discard buf.setString(left.x, leftY,
      "Drydocks: " & $data.drydocks, normalStyle())

  var rightY = right.y
  discard buf.setString(right.x, rightY, "PLANETARY DEFENSES",
    canvasHeaderStyle())
  rightY += 1
  if rightY < right.bottom:
    let shieldLabel = if data.shields > 0: "Present" else: "None"
    discard buf.setString(right.x, rightY,
      "Shields: " & shieldLabel, normalStyle())
    rightY += 1
  if rightY < right.bottom:
    discard buf.setString(right.x, rightY,
      "Batteries: " & $data.batteries, normalStyle())
    rightY += 1
  if rightY < right.bottom:
    let garrisonLine =
      "Armies: " & $data.armies & "  Marines: " & $data.marines
    discard buf.setString(right.x, rightY, garrisonLine, normalStyle())
    rightY += 1

proc renderPlanetSettingsTab*(
  area: Rect,
  buf: var CellBuffer,
  data: PlanetDetailData
) =
  if area.isEmpty:
    return

  var y = area.y
  discard buf.setString(area.x, y, "COLONY AUTOMATION",
    canvasHeaderStyle())
  y += 1
  if y >= area.bottom:
    return

  let repairLabel = if data.autoRepair: "ON" else: "OFF"
  let marinesLabel = if data.autoLoadMarines: "ON" else: "OFF"
  let fightersLabel = if data.autoLoadFighters: "ON" else: "OFF"
  let repairLine = "Auto-Repair Ships: " & repairLabel
  discard buf.setString(area.x, y, repairLine, normalStyle())
  y += 1
  if y < area.bottom:
    let marinesLine = "Auto-Load Marines: " & marinesLabel
    discard buf.setString(area.x, y, marinesLine, normalStyle())
    y += 1
  if y < area.bottom:
    let fightersLine = "Auto-Load Fighters: " & fightersLabel
    discard buf.setString(area.x, y, fightersLine, normalStyle())

proc buildColonyStatusChips(data: PlanetDetailData): string =
  var parts: seq[string] = @[]
  if data.blockaded:
    parts.add("[BLK]")
  var hasConstruction = false
  var hasRepair = false
  for item in data.queue:
    case item.kind
    of QueueKind.Construction:
      hasConstruction = true
    of QueueKind.Repair:
      hasRepair = true
  if hasRepair:
    parts.add("[RPR]")
  if hasConstruction:
    parts.add("[CN]")
  if parts.len == 0:
    parts.add("[OK]")
  result = parts.join(" ")

proc renderPlanetUnifiedView*(
  area: Rect,
  buf: var CellBuffer,
  data: PlanetDetailData,
  sectionBorder: CellStyle = innerBorderStyle()
) =
  if area.isEmpty:
    return

  let sections = vertical()
    .constraints(length(3), fill(), length(1))
    .split(area)
  let headerArea = sections[0]
  let bodyArea = sections[1]
  let footerArea = sections[2]

  var y = headerArea.y
  if y < headerArea.bottom:
    let statusLine = "STATUS: " & buildColonyStatusChips(data)
    discard buf.setString(headerArea.x, y, statusLine, normalStyle())
    y += 1
  if y < headerArea.bottom:
    let rawLabel = formatFloat(data.rawIndex, ffDecimal, 2)
    let locationLine =
      "Sector: " & data.sectorLabel &
      "  Class: " & data.planetClass &
      "  Resources: " & data.resourceRating &
      "  RAW: " & rawLabel
    discard buf.setString(headerArea.x, y, locationLine, normalStyle())
    y += 1
  if y < headerArea.bottom:
    let growthLabel = formatGrowthLabel(data.populationGrowthPu)
    let economyLine =
      "GCO: " & $data.gco &
      "  NCV: " & $data.ncv &
      "  Tax: " & $data.taxRate & "%" &
      "  Growth: " & growthLabel &
      "  Bonus: " & $data.starbaseBonusPct & "%"
    discard buf.setString(headerArea.x, y, economyLine, normalStyle())

  let useColumns = area.width >= 80
  if useColumns:
    let columns = horizontal()
      .constraints(percentage(50), fill())
      .split(bodyArea)
    let left = columns[0]
    let right = columns[1]

    let surfaceFrame = bordered()
      .title("SURFACE ASSETS")
      .borderType(BorderType.Rounded)
      .borderStyle(sectionBorder)
    surfaceFrame.render(left, buf)
    let surfaceInner = surfaceFrame.inner(left)

    var leftY = surfaceInner.y
    if leftY < surfaceInner.bottom:
      let popLine =
        "Population: " & $data.populationUnits & " PU" &
        "  Industry: " & $data.industrialUnits & " IU"
      discard buf.setString(surfaceInner.x, leftY, popLine,
        normalStyle())
      leftY += 1
    if leftY < surfaceInner.bottom:
      let garrisonLine =
        "Armies: " & $data.armies &
        "  Marines: " & $data.marines &
        "  Fighters: " & $data.fighters
      discard buf.setString(surfaceInner.x, leftY, garrisonLine,
        normalStyle())
      leftY += 1
    if leftY < surfaceInner.bottom:
      let shieldLabel = if data.shields > 0: "Present" else: "None"
      let defenseLine =
        "Batteries: " & $data.batteries &
        "  Shields: " & shieldLabel
      discard buf.setString(surfaceInner.x, leftY, defenseLine,
        normalStyle())

    let orbitalFrame = bordered()
      .title("FACILITIES")
      .borderType(BorderType.Rounded)
      .borderStyle(sectionBorder)
    orbitalFrame.render(right, buf)
    let orbitalInner = orbitalFrame.inner(right)

    var rightY = orbitalInner.y
    if rightY < orbitalInner.bottom:
      let facilityLine =
        "Spaceports: " & $data.spaceports &
        "  Shipyards: " & $data.shipyards
      discard buf.setString(orbitalInner.x, rightY, facilityLine,
        normalStyle())
      rightY += 1
    if rightY < orbitalInner.bottom:
      let orbitalLine =
        "Drydocks: " & $data.drydocks &
        "  Starbases: " & $data.starbases
      discard buf.setString(orbitalInner.x, rightY, orbitalLine,
        normalStyle())
      rightY += 1
    if rightY < orbitalInner.bottom:
      let dockLine =
        "Docks: CD " & $data.dockSummary.constructionTotal &
        "  RD " & $data.dockSummary.repairTotal
      discard buf.setString(orbitalInner.x, rightY, dockLine,
        normalStyle())
      rightY += 1
  else:
    let stacked = vertical()
      .constraints(fill(), fill())
      .split(bodyArea)
    let topPanel = stacked[0]
    let bottomPanel = stacked[1]

    let surfaceFrame = bordered()
      .title("SURFACE ASSETS")
      .borderType(BorderType.Rounded)
      .borderStyle(sectionBorder)
    surfaceFrame.render(topPanel, buf)
    let surfaceInner = surfaceFrame.inner(topPanel)

    var leftY = surfaceInner.y
    if leftY < surfaceInner.bottom:
      let popLine =
        "Population: " & $data.populationUnits & " PU" &
        "  Industry: " & $data.industrialUnits & " IU"
      discard buf.setString(surfaceInner.x, leftY, popLine,
        normalStyle())
      leftY += 1
    if leftY < surfaceInner.bottom:
      let garrisonLine =
        "Armies: " & $data.armies &
        "  Marines: " & $data.marines &
        "  Fighters: " & $data.fighters
      discard buf.setString(surfaceInner.x, leftY, garrisonLine,
        normalStyle())
      leftY += 1
    if leftY < surfaceInner.bottom:
      let shieldLabel = if data.shields > 0: "Present" else: "None"
      let defenseLine =
        "Batteries: " & $data.batteries &
        "  Shields: " & shieldLabel
      discard buf.setString(surfaceInner.x, leftY, defenseLine,
        normalStyle())

    let orbitalFrame = bordered()
      .title("FACILITIES")
      .borderType(BorderType.Rounded)
      .borderStyle(sectionBorder)
    orbitalFrame.render(bottomPanel, buf)
    let orbitalInner = orbitalFrame.inner(bottomPanel)

    var rightY = orbitalInner.y
    if rightY < orbitalInner.bottom:
      let facilityLine =
        "Spaceports: " & $data.spaceports &
        "  Shipyards: " & $data.shipyards
      discard buf.setString(orbitalInner.x, rightY, facilityLine,
        normalStyle())
      rightY += 1
    if rightY < orbitalInner.bottom:
      let orbitalLine =
        "Drydocks: " & $data.drydocks &
        "  Starbases: " & $data.starbases
      discard buf.setString(orbitalInner.x, rightY, orbitalLine,
        normalStyle())
      rightY += 1
    if rightY < orbitalInner.bottom:
      let dockLine =
        "Docks: CD " & $data.dockSummary.constructionTotal &
        "  RD " & $data.dockSummary.repairTotal
      discard buf.setString(orbitalInner.x, rightY, dockLine,
        normalStyle())
      rightY += 1

  let repairLabel = if data.autoRepair: "ON" else: "OFF"
  let marinesLabel = if data.autoLoadMarines: "ON" else: "OFF"
  let fightersLabel = if data.autoLoadFighters: "ON" else: "OFF"
  let automationLine =
    "Auto-Repair: " & repairLabel &
    "  Auto-Load Marines: " & marinesLabel &
    "  Auto-Load Fighters: " & fightersLabel
  discard buf.setString(footerArea.x, footerArea.y, automationLine,
    normalStyle())

proc renderPlanetDetail*(
  area: Rect,
  buf: var CellBuffer,
  model: TuiModel,
  state: GameState,
  viewingHouse: HouseId
) =
  ## Render detailed planet view with tabs
  if model.ui.selectedColonyId <= 0:
    discard buf.setString(
      area.x, area.y, "No colony selected", dimStyle()
    )
    return

  var planetData = colonyToDetailData(
    state,
    ColonyId(model.ui.selectedColonyId),
    viewingHouse
  )
  for cmd in model.ui.stagedColonyManagement:
    if int(cmd.colonyId) == planetData.colonyId:
      planetData.autoRepair = cmd.autoRepair
      planetData.autoLoadMarines = cmd.autoLoadMarines
      planetData.autoLoadFighters = cmd.autoLoadFighters
      break

  if area.isEmpty:
    return

  renderPlanetUnifiedView(area, buf, planetData)

proc renderPlanetDetailFromPS*(
  area: Rect,
  buf: var CellBuffer,
  model: TuiModel,
  ps: PlayerState
) =
  ## Render planet detail using PlayerState-only data
  if model.ui.selectedColonyId <= 0:
    discard buf.setString(
      area.x, area.y, "No colony selected", dimStyle()
    )
    return

  var planetData =
    colonyToDetailDataFromPS(ps, ColonyId(model.ui.selectedColonyId))
  for cmd in model.ui.stagedColonyManagement:
    if int(cmd.colonyId) == planetData.colonyId:
      planetData.autoRepair = cmd.autoRepair
      planetData.autoLoadMarines = cmd.autoLoadMarines
      planetData.autoLoadFighters = cmd.autoLoadFighters
      break

  if area.isEmpty:
    return

  renderPlanetUnifiedView(area, buf, planetData, modalBorderStyle())

# renderFleetDetailFromPS removed - see deprecated section above

# =============================================================================
# Modal Wrappers for Primary Views
# =============================================================================

proc renderPlanetsModal*(canvas: Rect, buf: var CellBuffer,
                         model: TuiModel, scroll: ScrollState) =
  ## Render colony view as centered table modal with content-aware sizing
  
  # Calculate actual table width from column definitions
  let columns = planetsColumns()
  let maxTableWidth = canvas.width - 4
  let tableWidth = tableWidthFromColumns(columns, maxTableWidth, showBorders = true)
  
  # Calculate visible rows and height
  let totalRows = model.view.planetsRows.len
  let visibleRows = clampedVisibleRows(
    totalRows,
    canvas.height,
    TableChromeRows + ModalFooterRows
  )
  
  # Create scroll state
  var localScroll = scroll
  localScroll.contentLength = totalRows
  localScroll.viewportLength = visibleRows
  localScroll.verticalOffset = clampScrollOffset(
    localScroll.verticalOffset, totalRows, visibleRows
  )
  localScroll.clampOffsets()
  
  let table = buildPlanetsTable(model, localScroll)
  let tableHeight = table.renderHeight(visibleRows)
  
  # Create modal sized to fit actual content
  let modal = newModal()
    .title("COLONY")
    .maxWidth(tableWidth + 2)
    .minWidth(min(80, tableWidth + 2))
    .minHeight(1)  # Don't force extra height
    .borderStyle(outerBorderStyle())
    .bgStyle(modalBgStyle())
  
  # Use content-aware sizing: +2 for footer separator + text
  let modalArea = modal.calculateArea(canvas, tableWidth, tableHeight + 2)
  
  let footerText =
    "[↑↓] Navigate  [Enter] Details  [B] Build  [Q] Queue  " &
    "[PgUp/PgDn] Scroll  [A-Z0-9]Jump  [/]Help"
  modal.renderWithFooter(modalArea, buf, footerText)
  
  let contentArea = modal.contentArea(modalArea, hasFooter = true)
  table.render(contentArea, buf)

proc renderFleetsModal*(canvas: Rect, buf: var CellBuffer,
                        model: var TuiModel, ps: ps_types.PlayerState,
                        scroll: ScrollState) =
  ## Render fleets view as centered floating modal
  ## Dispatches between ListView and SystemView based on fleetViewMode
  
  case model.ui.fleetViewMode
  of FleetViewMode.ListView:
    # List view (modal with full table)
    let columns = fleetListColumns()
    let maxTableWidth = canvas.width - 4
    let tableWidth = tableWidthFromColumns(columns, maxTableWidth,
      showBorders = true)
    let fleets = model.filteredFleets()
    let visibleRows = clampedVisibleRows(
      fleets.len,
      canvas.height,
      TableChromeRows + ModalFooterRows
    )
    var localScroll = model.ui.fleetsScroll
    localScroll.contentLength = fleets.len
    localScroll.viewportLength = visibleRows
    localScroll.verticalOffset = clampScrollOffset(
      localScroll.verticalOffset, fleets.len, visibleRows
    )
    localScroll.clampOffsets()
    let table = buildFleetListTable(model, localScroll)
    let tableHeight = table.renderHeight(visibleRows)
    let modal = newModal()
      .title("YOUR FLEETS")
      .maxWidth(tableWidth + 2)
      .minWidth(min(90, tableWidth + 2))
      .minHeight(1)
      .borderStyle(outerBorderStyle())
      .bgStyle(modalBgStyle())
    let modalArea = modal.calculateArea(canvas, tableWidth,
      tableHeight + 2)
    modal.renderWithSeparator(modalArea, buf, 2)
    let inner = modal.inner(modalArea)
    let contentArea = rect(inner.x, inner.y, inner.width,
      max(1, inner.height - 2))
    let hintLine =
      "[↑↓]Nav [Enter]Details [X]Select [←→]Sort [S]Asc/Desc " &
      "[A-Z0-9]Jump [C]md [R]OE [Z]TC [V]iew [/]Help"
    let footerY = inner.bottom - 1
    discard buf.setString(inner.x, footerY, hintLine,
      canvasDimStyle())
    table.render(contentArea, buf)
  
  of FleetViewMode.SystemView:
    # 2-pane fleet console with content-aware sizing
    # Calculate actual table widths from column definitions
    let maxAvailableWidth = canvas.width - 4
    let systemsWidth = tableWidthFromColumns(
      fleetConsoleSystemsColumns(), maxAvailableWidth, showBorders = true)
    let fleetsWidth = tableWidthFromColumns(
      fleetConsoleFleetsColumns(), maxAvailableWidth, showBorders = true)
    
    # Total content width = both tables side by side
    let contentWidth = systemsWidth + fleetsWidth
    
    # Calculate dynamic height based on content
    let systems = model.ui.fleetConsoleSystems
    var maxFleetCount = 0
    for sys in systems:
      if stdtables.hasKey(model.ui.fleetConsoleFleetsBySystem, sys.systemId):
        let fleets = model.ui.fleetConsoleFleetsBySystem[sys.systemId]
        maxFleetCount = max(maxFleetCount, fleets.len)
    
    let paneRows = clampedVisibleRows(
      max(systems.len, maxFleetCount),
      canvas.height,
      PanelFrameRows + TableChromeRows + ModalFooterRows
    )
    # Content area includes pane frame + table internals, plus modal footer rows.
    let contentHeight = contentHeightFromVisibleRows(
      paneRows,
      PanelFrameRows + TableChromeRows + ModalFooterRows
    )
    
    let modal = newModal()
      .title("FLEET COMMAND")
      .maxWidth(contentWidth + 2)
      .minWidth(min(90, contentWidth + 2))
      .minHeight(1)  # Don't force extra height
      .borderStyle(outerBorderStyle())
      .bgStyle(modalBgStyle())
    
    # Use content-aware sizing
    let modalArea = modal.calculateArea(canvas, contentWidth, contentHeight)
    modal.renderWithFooter(modalArea, buf,
      "[Arrows]Nav  [Tab]Pane  [Enter]Details  [X]Select  " &
      "[A-Z0-9]Jump  [C]md  [R]OE  [Z]eroTurn  [V]iew  [/]Help")
    let contentArea = modal.contentArea(modalArea, hasFooter = true)
    renderFleetConsole(contentArea, buf, model, ps)

proc renderResearchModal*(canvas: Rect, buf: var CellBuffer,
                          model: TuiModel, scroll: ScrollState) =
  ## Render research view as centered floating modal
  let modal = newModal()
    .title("RESEARCH & DEVELOPMENT")
    .maxWidth(128)
    .minWidth(90)
    .borderStyle(outerBorderStyle())
    .bgStyle(modalBgStyle())
  # +2 for footer (1 separator + 1 text line)
  let maxLevelCap = max(@[
    maxEconomicLevel,
    maxScienceLevel,
    maxConstructionTech,
    maxWeaponsTech,
    maxTerraformingTech,
    maxElectronicIntelligence,
    maxCloakingTech,
    maxShieldTech,
    maxCounterIntelligence,
    maxStrategicLiftTech,
    maxFlagshipCommandTech,
    maxStrategicCommandTech,
    maxFighterDoctrine,
    maxAdvancedCarrierOps
  ])
  let desiredContentHeight = max(23, maxLevelCap + 10)
  let maxContentHeight = max(12, canvas.height - 4)
  let contentHeight = min(desiredContentHeight, maxContentHeight) + 2
  let modalArea = modal.calculateArea(canvas, contentHeight)
  let footerLine =
    "[Up/Down/J/K]Navigate  [+/-]+/-5  [Shift+/-]+/-1  [0]Clear  " &
    "[/]Help"
  modal.renderWithFooter(modalArea, buf, footerLine)
  let contentArea = modal.contentArea(modalArea, hasFooter = true)
  renderResearchPanel(contentArea, buf, model)

proc researchItemAllocation(
    allocation: ResearchAllocation,
    item: ResearchItem
): int =
  case item.kind
  of ResearchItemKind.EconomicLevel:
    allocation.economic.int
  of ResearchItemKind.ScienceLevel:
    allocation.science.int
  of ResearchItemKind.Technology:
    if allocation.technology.hasKey(item.field):
      allocation.technology[item.field].int
    else:
      0

proc researchAllocatedTotal(allocation: ResearchAllocation): int =
  var total = allocation.economic + allocation.science
  for pp in allocation.technology.values:
    total += pp
  total.int

proc researchPoolLabel(item: ResearchItem): string =
  case item.kind
  of ResearchItemKind.EconomicLevel:
    "ERP"
  of ResearchItemKind.ScienceLevel:
    "SRP"
  of ResearchItemKind.Technology:
    case item.field
    of TechField.TerraformingTech, TechField.ElectronicIntelligence,
        TechField.CloakingTech, TechField.ShieldTech,
        TechField.CounterIntelligence, TechField.StrategicLiftTech:
      "SRP"
    else:
      "TRP"

proc renderResearchPanel(area: Rect, buf: var CellBuffer, model: TuiModel) =
  if area.isEmpty or area.height < 10:
    return

  proc renderLine(
      area: Rect,
      buf: var CellBuffer,
      x, y: int,
      text: string,
      style: CellStyle
    ) =
    if y >= area.bottom:
      return
    let maxWidth = max(0, area.right - x)
    if maxWidth <= 0:
      return
    let clipped = if text.len > maxWidth: text[0 ..< maxWidth] else: text
    discard buf.setString(x, y, clipped, style)

  let items = researchItems()
  let selection = clamp(model.ui.selectedIdx, 0, max(0, items.len - 1))
  let levels = if model.view.techLevels.isSome:
    model.view.techLevels.get()
  else:
    TechLevel(
      el: 1, sl: 1, cst: 1, wep: 1, ter: 1, eli: 1, clk: 1,
      sld: 1, cic: 1, stl: 1, fc: 1, sc: 1, fd: 1, aco: 1
    )
  let points = if model.view.researchPoints.isSome:
    model.view.researchPoints.get()
  else:
    ResearchPoints(
      economic: 0,
      science: 0,
      technology: initTable[TechField, int32]()
    )

  let columns = horizontal()
    .constraints(percentage(55), fill())
    .split(area)
  let listArea = columns[0]
  let detailArea = columns[1]

  let listFocused = model.ui.researchFocus == ResearchFocus.List
  let listFrame = bordered()
    .title("RESEARCH PROJECTS")
    .borderType(BorderType.Rounded)
    .borderStyle(panelBorderStyle(listFocused))
    .padding(1)
  listFrame.render(listArea, buf)
  let listInner = listFrame.inner(listArea)

  let listColumns = @[
    tableColumn("Pool", 4, table.Alignment.Left),
    tableColumn("Tech", 4, table.Alignment.Left),
    tableColumn("Name", 0, table.Alignment.Left, 6),
    tableColumn("Lvl", 3, table.Alignment.Center),
    tableColumn("Alloc (PP)", 10, table.Alignment.Right)
  ]

  var listTable = table(listColumns)
    .showBorders(true)
    .rowStyle(normalStyle())
    .selectedStyle(if listFocused: selectedStyle() else: normalStyle())

  var lastPool = ""
  var rowIdx = 0
  var selectedRowIdx = -1
  for idx, item in items:
    let pool = researchPoolLabel(item)
    if lastPool.len > 0 and pool != lastPool:
      listTable.addSeparatorRow()
      rowIdx.inc
    let level = research_projection.projectedTechLevel(
      levels, points, model.ui.researchAllocation, item
    )
    let allocated = researchItemAllocation(model.ui.researchAllocation, item)
    let blocked = research_projection.isBlockedProjected(
      levels, points, model.ui.researchAllocation, item
    )
    var cellStyles: seq[Option[CellStyle]] = @[]
    cellStyles.setLen(listColumns.len)
    if blocked:
      for i in 0 ..< cellStyles.len:
        cellStyles[i] = some(canvasDimStyle())
    listTable.addRow(TableRow(
      cells: @[
        pool,
        item.code,
        item.name,
        $level,
        $allocated
      ],
      cellStyles: cellStyles,
      kind: TableRowKind.Normal
    ))
    if idx == selection:
      selectedRowIdx = rowIdx
    rowIdx.inc
    lastPool = pool

  if items.len > 0 and selectedRowIdx >= 0:
    listTable = listTable.selectedIdx(selectedRowIdx)

  let tableFullH = listTable.renderHeight(listTable.rows.len)
  let tableArea = rect(
    listInner.x, listInner.y,
    listInner.width,
    min(tableFullH, listInner.height)
  )
  listTable.render(tableArea, buf)

  let totalAllocated = researchAllocatedTotal(
    model.ui.researchAllocation
  )
  let allocLine = "Allocated: " &
    formatNumber(totalAllocated) & " PP"
  let summaryY = listInner.y + tableArea.height
  if summaryY < listArea.bottom - 1:
    renderLine(
      listArea, buf,
      listInner.x, summaryY,
      allocLine, modalDimStyle()
    )

  if detailArea.isEmpty:
    return

  let detailTitle =
    if items.len > 0:
      "DETAIL: " & items[selection].code & " " & items[selection].name
    else:
      "DETAIL"
  let detailFrame = bordered()
    .title(detailTitle)
    .borderType(BorderType.Rounded)
    .borderStyle(panelBorderStyle(not listFocused))
    .padding(1)
  detailFrame.render(detailArea, buf)
  let detailInner = detailFrame.inner(detailArea)

  if items.len > 0:
    let item = items[selection]
    var dy = detailInner.y
    let level = research_projection.projectedTechLevel(
      levels, points, model.ui.researchAllocation, item
    )
    let currentLevel = research_projection.currentTechLevel(levels, item)
    let maxLevel = progressionMaxLevel(item)
    if dy < detailInner.bottom:
      let levelHeader = "Level: " & $level & " / " & $maxLevel
      renderLine(
        detailInner,
        buf,
        detailInner.x,
        dy,
        levelHeader,
        modalDimStyle()
      )
      dy += 1
    let staged = researchItemAllocation(model.ui.researchAllocation, item)
    let basePoints = research_projection.currentResearchPoints(points, item)
    var pointsCurrent = basePoints + staged
    let cost = techProgressCost(item, currentLevel)
    if pointsCurrent > cost:
      pointsCurrent = cost
    let barWidth = max(8, detailInner.width - 18)
    let pb = progressBar(pointsCurrent, cost, barWidth)
      .showPercent(false)
      .showRemaining(false)
    if dy < detailInner.bottom:
      let lineArea = rect(detailInner.x, dy, detailInner.width, 1)
      pb.render(lineArea, buf)
      dy += 1
    if dy < detailInner.bottom:
      let progressLine =
        "Progress: " & $pointsCurrent & "/" & $cost
      renderLine(
        detailInner,
        buf,
        detailInner.x,
        dy,
        progressLine,
        modalDimStyle()
      )
      dy += 1
    let slReq = techSlRequiredForLevel(item, level + 1)
    if slReq > 0 and dy < detailInner.bottom:
      let slLine = "SL Required: " & $slReq
      renderLine(
        detailInner,
        buf,
        detailInner.x,
        dy,
        slLine,
        modalDimStyle()
      )
      dy += 1

    if dy < detailInner.bottom:
      let desc = paragraph(techDescription(item))
        .wrap(Wrap(trim: true))
        .style(modalDimStyle())
      let descHeight = min(2, max(1, detailInner.bottom - dy))
      let descArea = rect(detailInner.x, dy, detailInner.width, descHeight)
      desc.render(descArea, buf)
      dy += descHeight

    if dy < detailInner.bottom:
      renderLine(
        detailInner,
        buf,
        detailInner.x,
        dy,
        "PROGRESSION",
        canvasHeaderStyle()
      )
      dy += 1

    let progColumns = @[
      tableColumn("Lvl", 3, table.Alignment.Center),
      tableColumn("Cost", 6, table.Alignment.Right),
      tableColumn("SL", 4, table.Alignment.Right),
      tableColumn("Effect", 0, table.Alignment.Left, 16)
    ]

    var progTable = table(progColumns)
      .showBorders(true)
      .rowStyle(modalDimStyle())
      .selectedStyle(selectedStyle())

    let maxLevelInt = max(1, maxLevel)
    for lvl in 1 .. maxLevelInt:
      let costFor = techCostForLevel(item, lvl)
      let slFor = techSlRequiredForLevel(item, lvl)
      let effect = techEffectForLevel(item, lvl)
      progTable.addRow(@[$lvl, $costFor, $slFor, effect])

    let selectedLevel = clamp(level - 1, 0, maxLevelInt - 1)
    progTable = progTable.selectedIdx(selectedLevel)

    let availableHeight = max(1, detailInner.bottom - dy)
    let visibleRows = clampedVisibleRows(
      maxLevelInt,
      availableHeight,
      TableChromeRows,
      maxHeightPercent = 100
    )
    let tableHeight = min(
      progTable.renderHeight(visibleRows),
      availableHeight
    )
    let tableArea = rect(detailInner.x, dy, detailInner.width, tableHeight)
    progTable.render(tableArea, buf)

proc renderEspionageModal*(canvas: Rect, buf: var CellBuffer,
                           model: TuiModel, scroll: ScrollState) =
  ## Render espionage view as centered floating modal
  let targets = model.espionageTargetHouses()
  let operations = espionageActions()
  let targetIdx = clamp(model.ui.espionageTargetIdx, 0, max(0, targets.len - 1))
  let opIdx = clamp(model.ui.espionageOperationIdx, 0, max(0, operations.len - 1))
  let ebpCostPp = int(gameConfig.espionage.costs.ebpCostPp)
  let cipCostPp = int(gameConfig.espionage.costs.cipCostPp)
  let ebpPool =
    if model.view.espionageEbpPool.isSome:
      model.view.espionageEbpPool.get()
    else:
      0
  let cipPool =
    if model.view.espionageCipPool.isSome:
      model.view.espionageCipPool.get()
    else:
      0
  let ebpInvest = int(model.ui.stagedEbpInvestment)
  let cipInvest = int(model.ui.stagedCipInvestment)
  let ebpRemaining = model.espionageEbpAvailable()
  let cipTotal = model.espionageCipTotal()
  let ebpPp = ebpInvest * ebpCostPp
  let cipPp = cipInvest * cipCostPp
  let queuedEbp = model.espionageQueuedTotalEbp()
  let availableEbp = model.espionageEbpAvailable()
  let stagedEspionagePp = stagedEspionagePp(
    model.ui.stagedEbpInvestment,
    model.ui.stagedCipInvestment
  )
  let treasuryFree = optimisticTreasury(
    model.view.treasury,
    model.ui.stagedBuildCommands,
    model.ui.researchAllocation,
    model.ui.stagedEbpInvestment,
    model.ui.stagedCipInvestment
  )
  let selectedTargetName = if targets.len > 0:
    targets[targetIdx].name
  else:
    "No Target"
  let opColumns = @[
    tableColumn("Operation", 24, table.Alignment.Left),
    tableColumn("Cost", 7, table.Alignment.Left),
    tableColumn("Qty", 3, table.Alignment.Right)
  ]
  let targetsPanelWidth = 24
  let opsTableWidth = tableWidthFromColumns(
    opColumns,
    max(48, canvas.width - targetsPanelWidth - 10),
    showBorders = true
  )
  let contentWidth = clamp(
    targetsPanelWidth + 1 + opsTableWidth,
    66,
    max(66, canvas.width - 6)
  )
  var opsTableProbe = table(opColumns).showBorders(true)
  let opsTableHeightNeeded = opsTableProbe.renderHeight(operations.len) + 2
  let budgetHeight = 10
  let bodyHeight = max(6, max(opsTableHeightNeeded, targets.len + 2))
  let desiredMainHeight = budgetHeight + bodyHeight
  let modalMainHeight = min(desiredMainHeight, max(8, canvas.height - 6))

  proc panelTitleStyle(focus: EspionageFocus): CellStyle =
    if model.ui.espionageFocus == focus:
      selectedStyle()
    else:
      canvasHeaderStyle()

  proc drawTextLine(
      outBuf: var CellBuffer,
      x, y, width: int,
      text: string,
      style: CellStyle
  ) =
    if width <= 0:
      return
    var line = text
    if line.len > width:
      line = line[0 ..< width]
    discard outBuf.setString(x, y, line, style)

  proc drawMetric(
      outBuf: var CellBuffer,
      x, y, width: int,
      label, value: string,
      style: CellStyle
  ) =
    if width <= 0:
      return
    let prefix = label & " "
    let valueWidth = max(0, width - prefix.len)
    drawTextLine(outBuf, x, y, width, prefix & align(value, valueWidth), style)

  let modal = newModal()
    .title("INTEL OPERATIONS")
    .maxWidth(112)
    .minWidth(64)
    .borderStyle(outerBorderStyle())
    .bgStyle(modalBgStyle())
  let modalArea = modal.calculateArea(
    canvas,
    contentWidth,
    modalMainHeight + 2
  )
  let footerText =
    "[Tab]Panel  [Arrows]Nav  [E]BP  [C]IP  [+/−]Adjust"
  modal.renderWithFooter(modalArea, buf, footerText)
  let contentArea = modal.contentArea(modalArea, hasFooter = true)
  if contentArea.height <= 0 or contentArea.width <= 0:
    return

  let rows = vertical()
    .constraints(length(budgetHeight), fill())
    .split(contentArea)
  let budgetArea = rows[0]
  let bodyArea = rows[1]
  let bodyCols = horizontal()
    .constraints(length(targetsPanelWidth), fill())
    .split(bodyArea)
  let targetsArea = bodyCols[0]
  let opsArea = bodyCols[1]

  bordered().title("BUDGET ALLOCATION").borderStyle(
    modalPanelBorderStyle(model.ui.espionageFocus == EspionageFocus.Budget)
  ).render(budgetArea, buf)
  let bInner = bordered().inner(budgetArea)
  if bInner.isEmpty:
    return
  let cardsH = max(1, bInner.height - 1)
  let leftW = max(24, (bInner.width - 1) div 2)
  let rightW = max(24, bInner.width - leftW - 1)
  let ebpArea = rect(bInner.x, bInner.y, leftW, cardsH)
  let cipArea = rect(ebpArea.right + 1, bInner.y, rightW, cardsH)
  let ebpActive = model.ui.espionageFocus == EspionageFocus.Budget and
    model.ui.espionageBudgetChannel == EspionageBudgetChannel.Ebp
  let cipActive = model.ui.espionageFocus == EspionageFocus.Budget and
    model.ui.espionageBudgetChannel == EspionageBudgetChannel.Cip
  bordered().title("EBP (OFFENSE)").borderStyle(
    nestedPanelBorderStyle(ebpActive)
  ).render(ebpArea, buf)
  bordered().title("CIP (DEFENSE)").borderStyle(
    nestedPanelBorderStyle(cipActive)
  ).render(cipArea, buf)
  let ebpInner = bordered().inner(ebpArea)
  let cipInner = bordered().inner(cipArea)
  drawMetric(
    buf,
    ebpInner.x, ebpInner.y, ebpInner.width,
    "Pool:",
    formatNumber(ebpPool),
    dimStyle()
  )
  drawTextLine(
    buf,
    ebpInner.x, ebpInner.y + 1, ebpInner.width,
    "Invest: [ " & align($ebpInvest, 3) & " ]",
    if ebpActive: selectedStyle() else: normalStyle()
  )
  drawMetric(
    buf,
    ebpInner.x, ebpInner.y + 2, ebpInner.width,
    "Total:",
    formatNumber(ebpRemaining),
    dimStyle()
  )
  drawMetric(
    buf,
    ebpInner.x, ebpInner.y + 3, ebpInner.width,
    "Cost:",
    formatNumber(ebpPp) & " PP",
    dimStyle()
  )
  drawMetric(
    buf,
    cipInner.x, cipInner.y, cipInner.width,
    "Pool:",
    formatNumber(cipPool),
    dimStyle()
  )
  drawTextLine(
    buf,
    cipInner.x, cipInner.y + 1, cipInner.width,
    "Invest: [ " & align($cipInvest, 3) & " ]",
    if cipActive: selectedStyle() else: normalStyle()
  )
  drawMetric(
    buf,
    cipInner.x, cipInner.y + 2, cipInner.width,
    "Total:",
    formatNumber(cipTotal),
    dimStyle()
  )
  drawMetric(
    buf,
    cipInner.x, cipInner.y + 3, cipInner.width,
    "Cost:",
    formatNumber(cipPp) & " PP",
    dimStyle()
  )
  let summary = "Staged PP: " & formatNumber(stagedEspionagePp) &
    "   Treasury Free: " & formatNumber(treasuryFree) &
    "   EBP Queued: " & formatNumber(queuedEbp) &
    "   EBP Avail: " & formatNumber(availableEbp)
  drawTextLine(
    buf,
    bInner.x,
    bInner.bottom - 1,
    bInner.width,
    summary,
    dimStyle()
  )

  bordered().title("TARGETS").titleStyle(
    panelTitleStyle(EspionageFocus.Targets)
  ).borderStyle(
    modalPanelBorderStyle(model.ui.espionageFocus == EspionageFocus.Targets)
  ).render(targetsArea, buf)
  let tInner = bordered().inner(targetsArea)
  if targets.len == 0:
    drawTextLine(
      buf,
      tInner.x, tInner.y, tInner.width,
      "No known targets",
      dimStyle()
    )
  else:
    for i in 0 ..< min(tInner.height, targets.len):
      let rowStyle = if i == targetIdx: selectedStyle() else: normalStyle()
      drawTextLine(buf, tInner.x, tInner.y + i, tInner.width, targets[i].name,
        rowStyle)

  let opsTitle = "OPERATIONS (vs " & selectedTargetName & ")"
  bordered().title(opsTitle).titleStyle(
    panelTitleStyle(EspionageFocus.Operations)
  ).borderStyle(
    modalPanelBorderStyle(model.ui.espionageFocus == EspionageFocus.Operations)
  ).render(opsArea, buf)
  let oInner = bordered().inner(opsArea)
  let targetId = if targets.len > 0:
    HouseId(targets[targetIdx].id.uint32)
  else:
    HouseId(0'u32)
  var opsTable = table(opColumns)
    .showBorders(true)
    .rowStyle(normalStyle())
    .selectedStyle(selectedStyle())
  let selectedRow = if model.ui.espionageFocus == EspionageFocus.Operations:
    opIdx
  else:
    -1
  opsTable = opsTable.selectedIdx(selectedRow)
  let visibleRows = max(1, oInner.height - TableChromeRows)
  let startIdx = if operations.len > visibleRows and opIdx >= visibleRows:
    clamp(opIdx - visibleRows + 1, 0, max(0, operations.len - visibleRows))
  else:
    0
  opsTable = opsTable.scrollOffset(startIdx)
  for i in 0 ..< operations.len:
    let action = operations[i]
    let qty = if targets.len > 0:
      model.espionageQueuedQty(targetId, action)
    else:
      0
    let qtyLabel = if qty > 0: $qty else: ""
    opsTable.addRow(@[
      espionageActionLabel(action),
      $espionageActionCost(action) & " EBP",
      qtyLabel
    ])
  opsTable.render(oInner, buf)

proc renderEconomyModal*(canvas: Rect, buf: var CellBuffer,
                         model: TuiModel, scroll: ScrollState) =
  ## Render general view as centered floating modal
  let modal = newModal()
    .title("GENERAL POLICY")
    .maxWidth(120)
    .minWidth(80)
    .borderStyle(outerBorderStyle())
    .bgStyle(modalBgStyle())
  # +2 for footer (1 separator + 1 text line)
  let contentHeight = 12 + 2
  let modalArea = modal.calculateArea(canvas, contentHeight)
  modal.renderWithFooter(modalArea, buf,
    "[↑↓] Navigate  [Enter] Select  [/]Help")
  let contentArea = modal.contentArea(modalArea, hasFooter = true)
  discard buf.setString(contentArea.x, contentArea.y,
    "General view (TODO)", dimStyle())

proc renderSettingsModal*(canvas: Rect, buf: var CellBuffer,
                          model: TuiModel, scroll: ScrollState) =
  ## Render settings view as centered floating modal
  let modal = newModal()
    .title("GAME SETTINGS")
    .maxWidth(120)
    .minWidth(80)
    .borderStyle(outerBorderStyle())
    .bgStyle(modalBgStyle())
  # +2 for footer (1 separator + 1 text line)
  let contentHeight = 10 + 2
  let modalArea = modal.calculateArea(canvas, contentHeight)
  modal.renderWithFooter(modalArea, buf,
    "[↑↓] Navigate  [Enter] Select  [/]Help")
  let contentArea = modal.contentArea(modalArea, hasFooter = true)
  discard buf.setString(contentArea.x, contentArea.y,
    "Settings view (TODO)", dimStyle())

proc renderInboxLeftPanel(area: Rect, buf: var CellBuffer,
                          model: var TuiModel) =
  ## Render the left panel: flat list of houses + turn buckets
  let items = model.view.inboxItems
  let listIdx = model.ui.inboxListIdx
  let isFocused = model.ui.inboxFocus ==
    InboxPaneFocus.List
  let maxWidth = max(1, area.width)

  proc truncateLabel(label: string): string =
    ## Truncate label to fit within panel width
    if label.len <= maxWidth:
      return label
    if maxWidth <= 3:
      return label[0 ..< maxWidth]
    return label[0 ..< (maxWidth - 3)] & "..."

  var y = area.y
  for i, item in items:
    if y >= area.bottom:
      break
    let isSelected = (i == listIdx)
    case item.kind
    of InboxItemKind.SectionHeader:
      # Section header: bold, non-selectable
      let style = canvasHeaderStyle()
      let label = truncateLabel(item.label)
      discard buf.setString(area.x, y, label,
        style)
    of InboxItemKind.MessageHouse:
      let prefix = "  "
      var label = prefix & item.label
      if item.unread > 0:
        label &= " (" & $item.unread & ")"
      let style = if isSelected and isFocused:
        selectedStyle()
      elif isSelected:
        modalDimStyle()
      else:
        modalBgStyle()
      label = truncateLabel(label)
      discard buf.setString(area.x, y, label, style)
    of InboxItemKind.TurnBucket:
      let prefix = "  "  # 2-char indent for turn buckets
      var label = prefix
      # Show expand indicator on left
      let turnIdx = item.turnIdx
      let isExpanded = model.ui.inboxSection ==
          InboxSection.Reports and
          model.ui.inboxTurnIdx == turnIdx and
          model.ui.inboxTurnExpanded
      if isExpanded:
        label &= "[-]"
      else:
        label &= "[+]"
      label &= " " & item.label
      if item.unread > 0:
        label &= " (" & $item.unread & ")"
      # Dim the parent when expanded (child report gets the highlight)
      let style = if isSelected and isFocused and not isExpanded:
        selectedStyle()
      elif isSelected and isFocused and isExpanded:
        canvasHeaderStyle()
      elif isSelected and not isExpanded:
        modalDimStyle()
      elif isSelected and isExpanded:
        canvasHeaderStyle()
      else:
        modalBgStyle()
      label = truncateLabel(label)
      discard buf.setString(area.x, y, label, style)
      # Render expanded reports below this bucket
      if model.ui.inboxSection ==
          InboxSection.Reports and
          model.ui.inboxTurnIdx == turnIdx and
          model.ui.inboxTurnExpanded:
        if turnIdx < model.view.turnBuckets.len:
          let bucket = model.view.turnBuckets[turnIdx]
          for ri, rpt in bucket.reports:
            y += 1
            if y >= area.bottom:
              break
            let rptSel = (ri ==
              model.ui.inboxReportIdx) and
              model.ui.inboxTurnExpanded and
              isFocused
            let rPrefix = "    "
            var rLabel = rPrefix & rpt.title
            if rpt.isUnread:
              rLabel &= " *"
            let rStyle = if rptSel and isFocused:
              selectedStyle()
            elif rptSel:
              modalDimStyle()
            else:
              modalDimStyle()
            rLabel = truncateLabel(rLabel)
            discard buf.setString(
              area.x, y, rLabel, rStyle)
    y += 1

proc renderInboxDetailMessages(
    area: Rect, buf: var CellBuffer,
    model: var TuiModel) =
  ## Render message conversation in the detail pane
  var selectedHouseId = int32(0)
  if model.view.messageHouses.len > 0:
    let idx = clamp(model.ui.messageHouseIdx, 0,
      model.view.messageHouses.len - 1)
    selectedHouseId = model.view.messageHouses[idx].id

  let messages = model.view.messageThreads.getOrDefault(
    selectedHouseId, @[])

  # Reserve space for compose input
  let convoHeight = max(1, area.height - 2)
  let convoArea = rect(area.x, area.y,
    area.width, convoHeight)
  let composeArea = rect(area.x,
    area.y + convoHeight + 1, area.width, 1)

  var lines: seq[Line] = @[]
  for msg in messages:
    let sender =
      if msg.fromHouse ==
          int32(model.view.viewingHouse):
        "You"
      elif msg.fromHouse == 0:
        "System"
      else:
        let hname = model.view.houseNames.getOrDefault(
          int(msg.fromHouse), "House " &
            $msg.fromHouse)
        hname
    lines.add(line(sender & ": " & msg.text))
  if lines.len == 0:
    lines.add(line("No messages"))

  let convoText = text(lines)
  var convoScroll = model.ui.messagesScroll
  convoScroll.contentLength = convoText.lines.len
  convoScroll.viewportLength = max(1, convoArea.height)
  convoScroll.clampOffsets()
  model.ui.messagesScroll = convoScroll

  let convoParagraph = paragraph(convoText)
    .wrap(Wrap(trim: true))
    .scrollState(convoScroll)
  convoParagraph.render(convoArea, buf)

  if model.ui.messageComposeActive:
    let sepY = area.y + convoHeight
    if sepY < area.bottom:
      discard buf.setString(area.x, sepY,
        "─".repeat(area.width),
        modalDimStyle())

  let inputWidget = newTextInput()
    .placeholder("Type a message...")
    .style(modalBgStyle())
    .placeholderStyle(modalDimStyle())
    .cursorStyle(selectedStyle())
  inputWidget.render(model.ui.messageComposeInput,
    composeArea, buf, model.ui.messageComposeActive)

proc renderInboxDetailReports(
    area: Rect, buf: var CellBuffer,
    model: var TuiModel) =
  ## Render report detail in the detail pane
  let turnIdx = model.ui.inboxTurnIdx
  if turnIdx >= model.view.turnBuckets.len:
    discard buf.setString(area.x, area.y,
      "No reports", modalDimStyle())
    return

  let bucket = model.view.turnBuckets[turnIdx]
  if not model.ui.inboxTurnExpanded:
    # Show turn summary: list of report titles
    discard buf.setString(area.x, area.y,
      "Turn " & $bucket.turn & " - " &
        $bucket.reports.len & " reports",
      canvasHeaderStyle())
    var y = area.y + 2
    for rpt in bucket.reports:
      if y >= area.bottom:
        break
      var label = rpt.title
      if rpt.isUnread:
        label &= " *"
      discard buf.setString(area.x, y, label,
        modalBgStyle())
      y += 1
      discard buf.setString(area.x + 2, y,
        rpt.summary, modalDimStyle())
      y += 2
  else:
    # Show specific report detail
    let rptIdx = model.ui.inboxReportIdx
    if rptIdx < 0 or rptIdx >= bucket.reports.len:
      discard buf.setString(area.x, area.y,
        "No report selected", modalDimStyle())
      return
    let rpt = bucket.reports[rptIdx]
    # Title
    discard buf.setString(area.x, area.y,
      rpt.title, canvasHeaderStyle())
    # Category + turn
    discard buf.setString(area.x, area.y + 1,
      $rpt.category & " - Turn " & $rpt.turn,
      modalDimStyle())
    # Summary
    discard buf.setString(area.x, area.y + 3,
      rpt.summary, canvasBoldStyle())
    # Detail lines
    var y = area.y + 5
    var detailScroll = model.ui.inboxDetailScroll
    detailScroll.contentLength = rpt.detail.len
    detailScroll.viewportLength = max(1,
      area.bottom - y)
    detailScroll.clampOffsets()
    model.ui.inboxDetailScroll = detailScroll
    let startLine = detailScroll.verticalOffset
    for i in startLine ..< rpt.detail.len:
      if y >= area.bottom:
        break
      discard buf.setString(area.x, y,
        rpt.detail[i], modalBgStyle())
      y += 1
    # Link label at bottom
    if rpt.linkLabel.len > 0 and y < area.bottom:
      y += 1
      if y < area.bottom:
        discard buf.setString(area.x, y,
          "[Enter] Go to " & rpt.linkLabel,
          canvasBoldStyle())

proc renderInboxModal*(canvas: Rect,
    buf: var CellBuffer, model: var TuiModel) =
  ## Render unified inbox as centered floating modal
  let modal = newModal()
    .title("INBOX")
    .maxWidth(120)
    .minWidth(80)
    .borderStyle(outerBorderStyle())
    .bgStyle(modalBgStyle())
  let contentHeight = max(16,
    min(canvas.height - 6, 28)) + 2
  let modalArea = modal.calculateArea(
    canvas, contentHeight)
  let footerText =
    "[↑↓]Nav [←→/H/L/Tab]Focus [C]Compose" &
    " [M]Messages [R]Reports [Esc]Back"
  modal.renderWithFooter(modalArea, buf, footerText)
  let contentArea = modal.contentArea(
    modalArea, hasFooter = true)

  # Split: left panel (26 chars) | right detail panel
  let columns = horizontal()
    .constraints(length(32), fill())
    .split(contentArea)

  let listArea = columns[0]
  let detailArea = columns[1]

  # Left panel frame - highlight when focused
  let listBorder = modalPanelBorderStyle(
    model.ui.inboxFocus == InboxPaneFocus.List
  )
  let listFrame = bordered()
    .title("INBOX")
    .borderType(BorderType.Rounded)
    .borderStyle(listBorder)
  listFrame.render(listArea, buf)
  let listInner = listFrame.inner(listArea)

  # Right panel frame - highlight when focused
  let detailTitle =
    if model.ui.inboxSection ==
        InboxSection.Messages:
      "CONVERSATION"
    else:
      "REPORT"
  let detailFocused =
    model.ui.inboxFocus == InboxPaneFocus.Detail
  let detailBorder = modalPanelBorderStyle(detailFocused)
  let detailFrame = bordered()
    .title(detailTitle)
    .borderType(BorderType.Rounded)
    .borderStyle(detailBorder)
  detailFrame.render(detailArea, buf)
  let detailInner = detailFrame.inner(detailArea)

  # Render left panel
  renderInboxLeftPanel(listInner, buf, model)

  # Render right panel based on section
  if model.ui.inboxSection == InboxSection.Messages:
    renderInboxDetailMessages(
      detailInner, buf, model)
  else:
    renderInboxDetailReports(
      detailInner, buf, model)

proc renderPlanetDetailModal*(canvas: Rect, buf: var CellBuffer,
                               model: TuiModel, ps: PlayerState) =
  ## Render planet detail view as centered floating modal
  if model.ui.selectedColonyId <= 0:
    return

  # Get colony data for title
  let planetData = colonyToDetailDataFromPS(ps, ColonyId(model.ui.selectedColonyId))
  let title = "COLONY: " & planetData.systemName.toUpperAscii()

  let modal = newModal()
    .title(title)
    .maxWidth(120)
    .minWidth(100)
    .borderStyle(outerBorderStyle())
    .bgStyle(modalBgStyle())
  let headerLines = 3
  let panelContentLines = 3
  let panelHeight = panelContentLines + 2
  let footerLines = 1
  let useColumns = canvas.width >= 80
  let bodyHeight = if useColumns: panelHeight else: panelHeight * 2
  let desiredContentHeight =
    headerLines + bodyHeight + footerLines + 2
  let maxContentHeight = max(1, canvas.height - 4)
  let contentHeight = min(desiredContentHeight, maxContentHeight)
  let modalArea = modal.calculateArea(canvas, contentHeight)
  let footerText =
    "[Tab/→/L]Next  [←/H]Prev  [Esc]Close  [B]uild  [Q]ueue  " &
    "[R]epair  [M]arines  [F]ighters"
  modal.renderWithFooter(modalArea, buf, footerText)
  let contentArea = modal.contentArea(modalArea, hasFooter = true)

  # Render planet detail inside the modal
  renderPlanetDetailFromPS(contentArea, buf, model, ps)

proc intelConfidence(model: TuiModel, row: IntelRow): string =
  ## Estimate confidence from visibility class and LTU freshness.
  var intelTurn = -1
  if row.ltuLabel.len > 1 and row.ltuLabel[0] == 'T':
    try:
      intelTurn = parseInt(row.ltuLabel[1..^1])
    except ValueError:
      intelTurn = -1
  let age = if intelTurn >= 0: max(0, model.view.turn - intelTurn) else: 99
  if row.intelLabel == "OWN" or row.intelLabel == "OCC":
    if age <= 1:
      return "HIGH"
    if age <= 3:
      return "MED"
    return "LOW"
  if row.intelLabel == "SCT":
    if age <= 2:
      return "MED"
    return "LOW"
  "LOW"

proc renderIntelDbModal*(canvas: Rect, buf: var CellBuffer,
                         model: var TuiModel) =
  ## Render intel database view as centered floating modal.
  let columns = @[
    tableColumn("System", 6, table.Alignment.Center),
    tableColumn("Name", 18, table.Alignment.Left),
    tableColumn("Owner", 10, table.Alignment.Left),
    tableColumn("Intel", 6, table.Alignment.Left),
    tableColumn("LTU", 4, table.Alignment.Right),
    tableColumn("Notes", IntelNotesPreviewMaxRunes, table.Alignment.Left)
  ]
  let maxTableWidth = canvas.width - 4
  let tableWidth = tableWidthFromColumns(columns, maxTableWidth,
    showBorders = true)
  let totalRows = model.view.intelRows.len
  let visibleRows = clampedVisibleRows(
    totalRows,
    canvas.height,
    TableChromeRows + ModalFooterRows
  )
  var localScroll = model.ui.intelScroll
  localScroll.contentLength = totalRows
  localScroll.viewportLength = visibleRows
  localScroll.verticalOffset = clampScrollOffset(
    localScroll.verticalOffset, totalRows, visibleRows
  )
  localScroll.clampOffsets()
  model.ui.intelScroll = localScroll
  let tableHeight = contentHeightFromVisibleRows(visibleRows, TableChromeRows)

  let modal = newModal()
    .title("INTEL DATABASE")
    .maxWidth(tableWidth + 2)
    .minWidth(min(80, tableWidth + 2))
    .minHeight(1)
    .borderStyle(outerBorderStyle())
    .bgStyle(modalBgStyle())
  let modalArea = modal.calculateArea(canvas, tableWidth,
    tableHeight + 2)
  let footerText =
    "[↑↓] Navigate  [Enter] Detail  [N] Note  [PgUp/PgDn] Scroll  [A-Z0-9]Jump  [/]Help"
  modal.renderWithFooter(modalArea, buf, footerText)
  let contentArea = modal.contentArea(modalArea, hasFooter = true)
  renderIntelDbTable(contentArea, buf, model, localScroll)

proc renderIntelDetailModal*(canvas: Rect, buf: var CellBuffer,
                             model: var TuiModel, ps: ps_types.PlayerState) =
  ## Render intel detail for selected system with structured layout
  if model.ui.intelDetailSystemId <= 0:
    return

  var rowOpt: Option[IntelRow] = none(IntelRow)
  for row in model.view.intelRows:
    if row.systemId == model.ui.intelDetailSystemId:
      rowOpt = some(row)
      break
  if rowOpt.isNone:
    return

  let row = rowOpt.get()
  let systemId = SystemId(model.ui.intelDetailSystemId)
  let title = "INTEL: " & row.systemName.toUpperAscii()

  # Get system properties from visibleSystems (needed for width calc)
  var planetClass = "Unknown"
  var resourceRating = "Unknown"
  var jumpLaneLabels: seq[string] = @[]
  if ps.visibleSystems.hasKey(systemId):
    let visSys = ps.visibleSystems[systemId]
    let classIdx = int(visSys.planetClass)
    if classIdx >= 0 and classIdx < PlanetClassNames.len:
      planetClass = PlanetClassNames[classIdx]
    let resIdx = int(visSys.resourceRating)
    if resIdx >= 0 and resIdx < ResourceRatingNames.len:
      resourceRating = ResourceRatingNames[resIdx]
    for laneId in visSys.jumpLaneIds:
      if ps.visibleSystems.hasKey(laneId):
        let laneSys = ps.visibleSystems[laneId]
        if laneSys.coordinates.isSome:
          let coords = laneSys.coordinates.get()
          let label = coordLabel(coords.q.int, coords.r.int)
          let name = if laneSys.name.len > 0: laneSys.name else: "System " & $laneId.uint32
          jumpLaneLabels.add(label & " (" & name & ")")

  # Header lines for width calculation
  let header1 = "Sector: " & row.sectorLabel &
    "  Class: " & planetClass &
    "  Resources: " & resourceRating
  let header2 = "Owner: " & row.ownerName &
    "  Intel: " & row.intelLabel &
    "  LTU: " & row.ltuLabel &
    "  Confidence: " & intelConfidence(model, row)

  # Build fleet table for width calculation
  var fleetTable = table(@[
      tableColumn("Owner", 0, table.Alignment.Left, minWidth = 14),
      tableColumn("Fleet", 8, table.Alignment.Left),
      tableColumn("Ships", 6, table.Alignment.Right),
      tableColumn("AS", 4, table.Alignment.Right),
      tableColumn("DS", 4, table.Alignment.Right),
      tableColumn("CMD", 8, table.Alignment.Left),
      tableColumn("ROE", 4, table.Alignment.Right),
      tableColumn("LTU", 5, table.Alignment.Right)
    ])
  var fleetRows = 0
  var fleetMeta: seq[tuple[isOwn: bool, fleetId: int]] = @[]
  for fleet in ps.ownFleets:
    if fleet.location == systemId:
      var attackStr, defenseStr = 0
      for shipId in fleet.ships:
        for ship in ps.ownShips:
          if ship.id == shipId:
            attackStr += ship.stats.attackStrength
            defenseStr += ship.stats.defenseStrength
            break
      var cmdLabel: string
      var roeLabel: string
      let fleetId = int(fleet.id)
      if fleetId in model.ui.stagedFleetCommands:
        let staged = model.ui.stagedFleetCommands[fleetId]
        let cmdNum = sam_pkg.fleetCommandNumber(staged.commandType)
        cmdLabel = sam_pkg.commandLabel(cmdNum)
        if staged.roe.isSome:
          roeLabel = $int(staged.roe.get())
        else:
          roeLabel = $int(fleet.roe)
      else:
        let cmdNum = sam_pkg.fleetCommandNumber(fleet.command.commandType)
        cmdLabel = sam_pkg.commandLabel(cmdNum)
        roeLabel = $int(fleet.roe)
      fleetTable.addRow(@[
        "You",
        fleet.name,
        $fleet.ships.len,
        $attackStr,
        $defenseStr,
        cmdLabel,
        roeLabel,
        "T" & $model.view.turn
      ])
      fleetRows.inc
      fleetMeta.add((true, int(fleet.id)))
  for fleet in ps.visibleFleets:
    if fleet.location == systemId:
      let ships = if fleet.estimatedShipCount.isSome:
        "~" & $fleet.estimatedShipCount.get()
      else:
        "?"
      let intelAge = if fleet.intelTurn.isSome:
        "T" & $fleet.intelTurn.get()
      else:
        "---"
      let houseName = ps.houseNames.getOrDefault(fleet.owner, "Unknown")
      fleetTable.addRow(@[
        houseName,
        "---",
        ships,
        "?",
        "?",
        "?",
        "?",
        intelAge
      ])
      fleetRows.inc
      fleetMeta.add((false, int(fleet.fleetId)))

  model.ui.intelDetailFleetCount = fleetRows

  # Calculate required content width
  var contentWidth = max(header1.len, header2.len)
  if jumpLaneLabels.len > 0:
    contentWidth = max(contentWidth, jumpLaneLabels.join(", ").len)
  let noteLines =
    if row.notes.len > 0: row.notes.splitLines(keepEol = false)
    else: @["(none)"]
  for noteLine in noteLines:
    contentWidth = max(contentWidth, noteLine.len)
  # Ensure minimum width for side-by-side panels (surface assets + facilities)
  let panelMinWidth = 80  # ~38 chars per panel * 2 + gap + borders
  contentWidth = max(contentWidth, panelMinWidth)
  contentWidth = min(max(32, canvas.width - 8), contentWidth)

  # Calculate dynamic content height
  let panelsHeight = 5  # panelHeight (no gap after panels)
  let fleetContentRows = fleetRows + 6  # table + header/border overhead + frame borders
  let fleetBoxHeightCalc = min(26, max(7, fleetContentRows))
  let jumpLanesHeightCalc = if jumpLaneLabels.len > 0: 3 else: 0
  let notesContentRows = noteLines.len + 2  # content + border overhead
  let notesBoxHeightCalc = min(7, max(3, notesContentRows))
  let headerHeight = 3  # header1 + header2 + blank
  let footerHeight = 2  # separator + footer text
  let neededHeight = headerHeight + panelsHeight + fleetBoxHeightCalc + jumpLanesHeightCalc + notesBoxHeightCalc + footerHeight
  let contentHeight = min(max(neededHeight, 15), canvas.height - 6)

  let modal = newModal()
    .title(title)
    .maxWidth(contentWidth + 2)
    .minWidth(max(40, contentWidth + 2))
    .borderStyle(outerBorderStyle())
    .bgStyle(modalBgStyle())
  let modalArea = modal.calculateArea(canvas, contentWidth, contentHeight)
  let footerText =
    "[↑↓/J/K]Fleet  [Enter]Details  [PgUp/PgDn]Notes  [N]Edit Note  [Esc]Back"
  modal.renderWithFooter(modalArea, buf, footerText)
  let contentArea = modal.contentArea(modalArea, hasFooter = true)

  var y = contentArea.y
  discard buf.setString(contentArea.x, y, header1, normalStyle())
  y += 1
  discard buf.setString(contentArea.x, y, header2, normalStyle())
  y += 2

  # Find colony data
  var ownColony: Option[Colony] = none[Colony]()
  var enemyColony: Option[VisibleColony] = none[VisibleColony]()
  for colony in ps.ownColonies:
    if colony.systemId == systemId:
      ownColony = some(colony)
      break
  if ownColony.isNone:
    for colony in ps.visibleColonies:
      if colony.systemId == systemId:
        enemyColony = some(colony)
        break

  # Render COLONY / ORBITAL panels side-by-side
  let useColumns = contentArea.width >= 50
  let panelHeight = 5
  if useColumns and y + panelHeight < contentArea.bottom:
    let columns = horizontal()
      .constraints(percentage(50), fill())
      .split(rect(contentArea.x, y, contentArea.width, panelHeight))
    let leftPanel = columns[0]
    let rightPanel = columns[1]

    # Surface assets panel (left)
    let colonyFrame = bordered()
      .title("SURFACE ASSETS")
      .borderType(BorderType.Rounded)
      .borderStyle(modalBorderStyle())
    colonyFrame.render(leftPanel, buf)
    let colonyInner = colonyFrame.inner(leftPanel)
    var cy = colonyInner.y
    if ownColony.isSome:
      let col = ownColony.get()
      let popLine =
        "Population: " & $col.populationUnits & " PU" &
        "  Industry: " & $col.industrial.units & " IU"
      discard buf.setString(colonyInner.x, cy, popLine, normalStyle())
      cy += 1
      # Count ground assets from ps.ownGroundUnits
      var armies, marines, batteries, shields = 0
      for unit in ps.ownGroundUnits:
        if unit.garrison.locationType == GroundUnitLocation.OnColony and
            unit.garrison.colonyId == col.id:
          case unit.stats.unitType
          of GroundClass.Army: armies.inc
          of GroundClass.Marine: marines.inc
          of GroundClass.GroundBattery: batteries.inc
          of GroundClass.PlanetaryShield: shields.inc
      let fighterCount = col.fighterIds.len
      let garrisonLine =
        "Armies: " & $armies &
        "  Marines: " & $marines &
        "  Fighters: " & $fighterCount
      discard buf.setString(colonyInner.x, cy, garrisonLine, normalStyle())
      cy += 1
      let shieldLabel = if shields > 0: "Present" else: "None"
      let defenseLine =
        "Batteries: " & $batteries &
        "  Shields: " & shieldLabel
      discard buf.setString(colonyInner.x, cy, defenseLine, normalStyle())
    elif enemyColony.isSome:
      let col = enemyColony.get()
      let pop = if col.estimatedPopulation.isSome: "~" & $col.estimatedPopulation.get() & " PU" else: "?"
      let ind = if col.estimatedIndustry.isSome: "~" & $col.estimatedIndustry.get() & " IU" else: "?"
      let arm = if col.estimatedArmies.isSome: "~" & $col.estimatedArmies.get() else: "?"
      let mar = if col.estimatedMarines.isSome: "~" & $col.estimatedMarines.get() else: "?"
      let bat = if col.estimatedBatteries.isSome: "~" & $col.estimatedBatteries.get() else: "?"
      let shd = if col.estimatedShields.isSome:
        (if col.estimatedShields.get() > 0: "Present" else: "None")
      else:
        "?"
      let popLine = "Population: " & pop & "  Industry: " & ind
      discard buf.setString(colonyInner.x, cy, popLine, normalStyle())
      cy += 1
      let garrisonLine =
        "Armies: " & arm &
        "  Marines: " & mar &
        "  Fighters: ?"
      discard buf.setString(colonyInner.x, cy, garrisonLine, normalStyle())
      cy += 1
      let defenseLine =
        "Batteries: " & bat &
        "  Shields: " & shd
      discard buf.setString(colonyInner.x, cy, defenseLine, normalStyle())
    else:
      discard buf.setString(colonyInner.x, cy, "No colony detected", dimStyle())

    # Facilities panel (right)
    let orbitalFrame = bordered()
      .title("FACILITIES")
      .borderType(BorderType.Rounded)
      .borderStyle(modalBorderStyle())
    orbitalFrame.render(rightPanel, buf)
    let orbitalInner = orbitalFrame.inner(rightPanel)
    var oy = orbitalInner.y
    if ownColony.isSome:
      let col = ownColony.get()
      let starbases = col.kastraIds.len
      # Count facilities from ps.ownNeorias
      var spaceports, shipyards, drydocks = 0
      for neoriaId in col.neoriaIds:
        for neoria in ps.ownNeorias:
          if neoria.id == neoriaId:
            case neoria.neoriaClass
            of NeoriaClass.Spaceport: spaceports.inc
            of NeoriaClass.Shipyard: shipyards.inc
            of NeoriaClass.Drydock: drydocks.inc
            break
      let facilitiesLine =
        "Spaceports: " & $spaceports &
        "  Shipyards: " & $shipyards
      discard buf.setString(orbitalInner.x, oy, facilitiesLine, normalStyle())
      oy += 1
      let orbitalLine =
        "Drydocks: " & $drydocks &
        "  Starbases: " & $starbases
      discard buf.setString(orbitalInner.x, oy, orbitalLine, normalStyle())
      oy += 1
      let dockLine =
        "Docks: CD " & $col.constructionDocks &
        "  RD " & $col.repairDocks
      discard buf.setString(orbitalInner.x, oy, dockLine, normalStyle())
    elif enemyColony.isSome:
      let col = enemyColony.get()
      let sb = if col.starbaseLevel.isSome: $col.starbaseLevel.get() else: "?"
      let sp = if col.spaceportCount.isSome: $col.spaceportCount.get() else: "?"
      let sy = if col.shipyardCount.isSome: $col.shipyardCount.get() else: "?"
      let dd = if col.drydockCount.isSome: $col.drydockCount.get() else: "?"
      let facilitiesLine =
        "Spaceports: " & sp &
        "  Shipyards: " & sy
      discard buf.setString(orbitalInner.x, oy, facilitiesLine, normalStyle())
      oy += 1
      let orbitalLine =
        "Drydocks: " & dd &
        "  Starbases: " & sb
      discard buf.setString(orbitalInner.x, oy, orbitalLine, normalStyle())
      oy += 1
      discard buf.setString(orbitalInner.x, oy, "Docks: CD ?  RD ?",
        normalStyle())
    else:
      discard buf.setString(orbitalInner.x, oy, "No orbital assets", dimStyle())
    
    y += panelHeight

  let hasJumpLanes = jumpLaneLabels.len > 0

  let notesBoxMin = 3
  let notesBoxMax = 7
  var notesBoxHeight = min(notesBoxMax, max(notesBoxMin, noteLines.len + 2))
  let jumpBoxHeight = if hasJumpLanes: 3 else: 0
  let fleetBoxMin = 7
  let remainingRows = max(0, contentArea.bottom - y)
  var fleetBoxHeight =
    remainingRows - jumpBoxHeight - notesBoxHeight
  if fleetBoxHeight < fleetBoxMin:
    let deficit = fleetBoxMin - fleetBoxHeight
    notesBoxHeight = max(notesBoxMin, notesBoxHeight - deficit)
    fleetBoxHeight =
      remainingRows - jumpBoxHeight - notesBoxHeight
  fleetBoxHeight = max(3, fleetBoxHeight)

  if y < contentArea.bottom:
    let fleetsFrame = bordered()
      .title("FLEETS")
      .borderType(BorderType.Rounded)
      .borderStyle(modalBorderStyle())
    let fleetsArea = rect(
      contentArea.x,
      y,
      contentArea.width,
      min(fleetBoxHeight, contentArea.bottom - y)
    )
    fleetsFrame.render(fleetsArea, buf)
    let fleetsInner = fleetsFrame.inner(fleetsArea)
    if fleetRows > 0 and fleetsInner.height > 0:
      let visibleFleetRows = max(1, fleetsInner.height - 4)
      let maxFleetOffset = max(0, fleetRows - visibleFleetRows)
      var selectedFleet = clamp(
        model.ui.intelDetailFleetSelectedIdx, 0, fleetRows - 1)
      model.ui.intelDetailFleetSelectedIdx = selectedFleet
      var fleetOffset = 0
      if selectedFleet >= visibleFleetRows:
        fleetOffset = selectedFleet - visibleFleetRows + 1
      fleetOffset = min(fleetOffset, maxFleetOffset)
      fleetTable = fleetTable.scrollOffset(fleetOffset)
      fleetTable = fleetTable.selectedIdx(selectedFleet)
      fleetTable.render(fleetsInner, buf)
    elif fleetsInner.height > 0:
      discard buf.setString(fleetsInner.x, fleetsInner.y, "None known",
        dimStyle())
    y = fleetsArea.bottom

  if hasJumpLanes and y < contentArea.bottom:
    let jumpFrame = bordered()
      .title("JUMP LANES")
      .borderType(BorderType.Rounded)
      .borderStyle(modalBorderStyle())
    let jumpArea = rect(contentArea.x, y,
      contentArea.width,
      min(jumpBoxHeight, contentArea.bottom - y))
    jumpFrame.render(jumpArea, buf)
    let jumpInner = jumpFrame.inner(jumpArea)
    if jumpInner.height > 0:
      discard buf.setString(jumpInner.x, jumpInner.y,
        jumpLaneLabels.join(", "), normalStyle())
    y = jumpArea.bottom

  if y < contentArea.bottom:
    let notesFrame = bordered()
      .title("NOTES")
      .borderType(BorderType.Rounded)
      .borderStyle(modalBorderStyle())
    let notesArea = rect(contentArea.x, y,
      contentArea.width,
      min(notesBoxHeight, contentArea.bottom - y))
    notesFrame.render(notesArea, buf)
    let notesInner = notesFrame.inner(notesArea)
    if notesInner.height > 0:
      let maxNoteOffset = max(0, noteLines.len - notesInner.height)
      let noteOffset = clamp(
        model.ui.intelDetailNoteScrollOffset, 0, maxNoteOffset)
      model.ui.intelDetailNoteScrollOffset = noteOffset
      for i in 0 ..< notesInner.height:
        let lineIdx = noteOffset + i
        if lineIdx >= noteLines.len:
          break
        let lineText = noteLines[lineIdx]
        let lineStyle =
          if row.notes.len > 0: normalStyle() else: dimStyle()
        discard buf.setString(notesInner.x, notesInner.y + i, lineText,
          lineStyle)

  proc shipClassCode(cls: ShipClass): string =
    case cls
    of ShipClass.Corvette: "CT"
    of ShipClass.Frigate: "FG"
    of ShipClass.Destroyer: "DD"
    of ShipClass.LightCruiser: "CL"
    of ShipClass.Cruiser: "CA"
    of ShipClass.Battlecruiser: "BC"
    of ShipClass.Battleship: "BB"
    of ShipClass.Dreadnought: "DN"
    of ShipClass.SuperDreadnought: "SD"
    of ShipClass.Carrier: "CV"
    of ShipClass.SuperCarrier: "CX"
    of ShipClass.Raider: "RR"
    of ShipClass.Scout: "SC"
    of ShipClass.ETAC: "ET"
    of ShipClass.TroopTransport: "TT"
    of ShipClass.Fighter: "F"
    of ShipClass.PlanetBreaker: "PB"

  proc shipClassName(cls: ShipClass): string =
    case cls
    of ShipClass.Corvette: "Corvette"
    of ShipClass.Frigate: "Frigate"
    of ShipClass.Destroyer: "Destroyer"
    of ShipClass.LightCruiser: "Light Cruiser"
    of ShipClass.Cruiser: "Cruiser"
    of ShipClass.Battlecruiser: "Battle Cruiser"
    of ShipClass.Battleship: "Battleship"
    of ShipClass.Dreadnought: "Dreadnought"
    of ShipClass.SuperDreadnought: "Super Dreadnought"
    of ShipClass.Carrier: "Carrier"
    of ShipClass.SuperCarrier: "Super Carrier"
    of ShipClass.Raider: "Raider"
    of ShipClass.Scout: "Scout"
    of ShipClass.ETAC: "ETAC"
    of ShipClass.TroopTransport: "Troop Transport"
    of ShipClass.Fighter: "Fighter"
    of ShipClass.PlanetBreaker: "Planet Breaker"

  if model.ui.intelDetailFleetPopupActive and fleetRows > 0:
    let selectedFleet = max(0,
      min(model.ui.intelDetailFleetSelectedIdx, fleetRows - 1))
    let meta = fleetMeta[selectedFleet]
    var headerLines: seq[string] = @[]
    var totalLine = "Total Ships: ?"
    var shipTable = table(@[
        tableColumn("Class", 6, table.Alignment.Left),
        tableColumn("Name", 24, table.Alignment.Left),
        tableColumn("Count", 8, table.Alignment.Right)
      ])

    if meta.isOwn:
      for fleet in ps.ownFleets:
        if int(fleet.id) == meta.fleetId:
          var cmdLabel: string
          var roeLabel: string
          let fleetId = int(fleet.id)
          if fleetId in model.ui.stagedFleetCommands:
            let staged = model.ui.stagedFleetCommands[fleetId]
            let cmdNum = sam_pkg.fleetCommandNumber(staged.commandType)
            cmdLabel = sam_pkg.commandLabel(cmdNum)
            if staged.roe.isSome:
              roeLabel = $int(staged.roe.get())
            else:
              roeLabel = $int(fleet.roe)
          else:
            let cmdNum = sam_pkg.fleetCommandNumber(fleet.command.commandType)
            cmdLabel = sam_pkg.commandLabel(cmdNum)
            roeLabel = $int(fleet.roe)
          var classCounts = stdtables.initTable[ShipClass, int]()
          var totalShips = 0
          for shipId in fleet.ships:
            for ship in ps.ownShips:
              if ship.id == shipId:
                let cls = ship.shipClass
                classCounts[cls] = classCounts.getOrDefault(cls, 0) + 1
                totalShips.inc
                break
          headerLines.add("Owner: You  Fleet: " & fleet.name)
          headerLines.add("Command/ROE: " & cmdLabel & "/" & roeLabel)
          for cls in ShipClass:
            if classCounts.hasKey(cls):
              shipTable.addRow(@[
                shipClassCode(cls),
                shipClassName(cls),
                $classCounts[cls]
              ])
          if shipTable.rows.len == 0:
            shipTable.addRow(@["--", "(none)", "0"])
          totalLine = "Total Ships: " & $totalShips
          break
    else:
      for fleet in ps.visibleFleets:
        if int(fleet.fleetId) == meta.fleetId:
          let ownerName = ps.houseNames.getOrDefault(fleet.owner, "Unknown")
          let estShips = if fleet.estimatedShipCount.isSome:
            "~" & $fleet.estimatedShipCount.get()
          else:
            "?"
          let intelTurn = if fleet.intelTurn.isSome:
            "T" & $fleet.intelTurn.get()
          else:
            "---"
          headerLines.add("Owner: " & ownerName & "  Fleet: ---")
          headerLines.add("Intel: " & intelTurn & "  Command/ROE: ?/?")
          shipTable.addRow(@["??", "Unknown", "?"])
          totalLine = "Total Ships: " & estShips
          break

    let maxTableWidth = max(32, canvas.width - 8)
    let tableWidth = shipTable.renderWidth(maxTableWidth)
    var contentWidth = tableWidth
    for ln in headerLines:
      contentWidth = max(contentWidth, ln.len)
    contentWidth = max(contentWidth, totalLine.len)
    contentWidth = min(maxTableWidth, contentWidth)

    let maxContentHeight = max(10, canvas.height - 8)
    let visibleRows = clampedVisibleRows(
      shipTable.rows.len,
      maxContentHeight,
      headerLines.len + 5
    )
    let tableHeight = shipTable.renderHeight(visibleRows)
    let bodyHeight = headerLines.len + tableHeight + 1

    let detailModal = newModal()
      .title("FLEET INTEL")
      .maxWidth(contentWidth + 2)
      .minWidth(max(32, contentWidth + 2))
      .showBackdrop(true)
      .borderStyle(outerBorderStyle())
      .bgStyle(modalBgStyle())
    let detailArea = detailModal.calculateArea(canvas, contentWidth,
      bodyHeight + 2)
    detailModal.renderWithFooter(detailArea, buf, "[Esc]Close")
    let detailInner = detailModal.contentArea(detailArea, hasFooter = true)
    var dy = detailInner.y
    for ln in headerLines:
      if dy >= detailInner.bottom:
        break
      discard buf.setString(detailInner.x, dy, ln, normalStyle())
      dy += 1
    if dy < detailInner.bottom:
      shipTable.render(rect(detailInner.x, dy, detailInner.width, tableHeight),
        buf)
      dy += tableHeight
    if dy < detailInner.bottom:
      discard buf.setString(detailInner.x, dy, totalLine, canvasBoldStyle())

proc renderIntelNoteEditor*(canvas: Rect, buf: var CellBuffer,
                            model: TuiModel) =
  ## Render overlay for editing intel notes.
  if not model.ui.intelNoteEditActive:
    return

  let modal = newModal()
    .title("EDIT INTEL NOTE")
    .maxWidth(100)
    .minWidth(70)
    .showBackdrop(true)
    .borderStyle(outerBorderStyle())
    .bgStyle(modalBgStyle())
  let modalHeight = min(max(12, canvas.height - 6), canvas.height - 2)
  let modalArea = modal.calculateArea(canvas, modalHeight)
  modal.renderWithFooter(modalArea, buf,
    "[Ctrl+S] Save  [Enter] New Line  [Esc] Cancel")
  let contentArea = modal.contentArea(modalArea, hasFooter = true)
  discard buf.setString(contentArea.x, contentArea.y,
    "Note (multiline):", canvasDimStyle())

  let textArea = rect(
    contentArea.x,
    contentArea.y + 1,
    contentArea.width,
    max(1, contentArea.height - 1)
  )
  if textArea.isEmpty:
    return

  let lines = model.ui.intelNoteEditor.text.splitLines(keepEol = false)
  let lineCount = max(1, lines.len)
  let cursorLineIdx = cursorLine(
    model.ui.intelNoteEditor.text,
    model.ui.intelNoteEditor.cursorPos
  )
  let cursorCol = cursorColumn(
    model.ui.intelNoteEditor.text,
    model.ui.intelNoteEditor.cursorPos
  )
  var scrollLine = model.ui.intelNoteEditor.scrollLine
  scrollLine = max(0, min(scrollLine, max(0, lineCount - textArea.height)))
  if cursorLineIdx < scrollLine:
    scrollLine = cursorLineIdx
  elif cursorLineIdx >= scrollLine + textArea.height:
    scrollLine = cursorLineIdx - textArea.height + 1

  for row in 0 ..< textArea.height:
    let lineIdx = scrollLine + row
    if lineIdx >= lineCount:
      break
    let lineText = if lineIdx < lines.len: lines[lineIdx] else: ""
    var xPos = textArea.x
    var charIdx = 0
    var lineCursorX = textArea.x
    for ch in lineText.runes:
      if xPos >= textArea.right:
        break
      if lineIdx == cursorLineIdx and charIdx == cursorCol:
        lineCursorX = xPos
      let written = buf.put(xPos, textArea.y + row, ch.toUTF8, normalStyle())
      xPos += written
      charIdx.inc
    if lineIdx == cursorLineIdx:
      if cursorCol >= charIdx:
        lineCursorX = min(xPos, textArea.right - 1)
      setCursorTarget(lineCursorX, textArea.y + row)

proc renderListPanel*(
    area: Rect,
    buf: var CellBuffer,
    model: TuiModel,
    state: GameState,
    viewingHouse: HouseId,
) =
  ## Render the main list panel based on current mode

  let title =
    case model.ui.mode
    of ViewMode.Overview: "Empire Status"
    of ViewMode.Planets: "Your Colonies"
    of ViewMode.Fleets: "Your Fleets"
    of ViewMode.Research: "Tech Progress"
    of ViewMode.Espionage: "Intel Operations"
    of ViewMode.Economy: "General Policy"
    of ViewMode.IntelDb: "Intel Database"
    of ViewMode.IntelDetail: "Intel System"
    of ViewMode.Settings: "Game Settings"
    of ViewMode.Messages: "Inbox"
    of ViewMode.PlanetDetail: "Planet Info"
    of ViewMode.FleetDetail: "Fleet Info"

  let frame = bordered().title(title).borderType(BorderType.Rounded)
  frame.render(area, buf)
  let inner = frame.inner(area)

  case model.ui.mode
  of ViewMode.Overview:
    # Overview placeholder - will show empire dashboard in Phase 2
    var y = inner.y
    discard buf.setString(inner.x, y, "STRATEGIC OVERVIEW",
      canvasHeaderStyle())
    y += 2
    discard buf.setString(inner.x, y,
      "Turn: " & $model.view.turn, normalStyle())
    y += 1
    discard buf.setString(inner.x, y,
      "Colonies: " & $model.view.colonies.len, normalStyle())
    y += 1
    discard buf.setString(inner.x, y,
      "Fleets: " & $model.view.fleets.len, normalStyle())
    y += 2
    discard buf.setString(inner.x, y,
      "F1-F8 Switch views  F12 Quit  [J] Join", dimStyle())
  of ViewMode.Planets:
    renderColonyList(inner, buf, model)
  of ViewMode.Fleets:
    renderFleetList(inner, buf, model)
  of ViewMode.Research:
    discard buf.setString(inner.x, inner.y,
      "Tech view (TODO)", dimStyle())
  of ViewMode.Espionage:
    discard buf.setString(inner.x, inner.y,
      "Espionage view (TODO)", dimStyle())
  of ViewMode.Economy:
    discard buf.setString(inner.x, inner.y,
      "General view (TODO)", dimStyle())
  of ViewMode.IntelDb:
    discard buf.setString(inner.x, inner.y,
      "Intel DB view (deprecated)", dimStyle())
  of ViewMode.IntelDetail:
    discard buf.setString(inner.x, inner.y,
      "Intel detail view", dimStyle())
  of ViewMode.Settings:
    discard buf.setString(inner.x, inner.y,
      "Settings view (TODO)", dimStyle())
  of ViewMode.PlanetDetail:
    renderPlanetDetail(inner, buf, model, state, viewingHouse)
  of ViewMode.FleetDetail:
    # FleetDetail view mode deprecated - now uses popup modal from Fleets view
    discard buf.setString(inner.x, inner.y,
      "Fleet detail modal (press Enter on fleet)", dimStyle())
  of ViewMode.Messages:
    discard buf.setString(inner.x, inner.y,
      "Inbox view uses modal", dimStyle())

proc buildHudData*(model: TuiModel): HudData =
  ## Build HUD data from TUI model
  let optimisticC2 = optimisticC2Used(
    model.view.commandUsed,
    model.ui.stagedBuildCommands,
  )
  let optimisticPp = optimisticTreasury(
    model.view.treasury,
    model.ui.stagedBuildCommands,
    model.ui.researchAllocation,
    model.ui.stagedEbpInvestment,
    model.ui.stagedCipInvestment,
  )
  HudData(
    houseName: model.view.houseName,
    turn: model.view.turn,
    prestige: model.view.prestige,
    prestigeRank: model.view.prestigeRank,
    totalHouses: model.view.totalHouses,
    taxRate: model.view.houseTaxRate,
    treasury: optimisticPp,
    production: model.view.production,
    commandUsed: optimisticC2,
    commandMax: model.view.commandMax,
    alertCount: model.view.alertCount,
    unreadMessages: model.view.unreadMessages,
  )

proc buildBreadcrumbData*(model: TuiModel): BreadcrumbData =
  ## Build breadcrumb data from TUI model
  result = initBreadcrumbData()
  if model.ui.breadcrumbs.len == 0:
    # Safety: should never happen, but handle gracefully
    result.add("Home", 1)
    return
  
  # For primary views (depth 1-2 with Home), show just the view name
  if model.ui.breadcrumbs.len <= 2 and model.ui.breadcrumbs[0].label == "Home":
    # Primary view: Show just "Fleets" not "Home > Fleets"
    if model.ui.breadcrumbs.len == 1:
      result.add(model.ui.mode.viewModeLabel, int(model.ui.mode))
    else:
      # Use the last breadcrumb (the actual view)
      let item = model.ui.breadcrumbs[^1]
      result.add(item.label, int(item.viewMode), item.entityId)
  else:
    # Detail view: Show full path (e.g., "Fleets > Fleet #3")
    # Skip "Home" and start from the first primary view
    for i in 1..<model.ui.breadcrumbs.len:
      let item = model.ui.breadcrumbs[i]
      result.add(item.label, int(item.viewMode), item.entityId)

proc activeViewKey*(mode: ViewMode): string =
  ## Map view mode to dock key label
  case mode
  of ViewMode.PlanetDetail:
    return "F2"
  of ViewMode.FleetDetail:
    return "F3"
  of ViewMode.Overview:
    return "F1"
  of ViewMode.Planets:
    return "F2"
  of ViewMode.Fleets:
    return "F3"
  of ViewMode.Research:
    return "F4"
  of ViewMode.Espionage:
    return "F5"
  of ViewMode.Economy:
    return "F6"
  of ViewMode.Settings:
    return "F8"
  of ViewMode.Messages:
    return "^N"
  of ViewMode.IntelDb:
    return ""
  of ViewMode.IntelDetail:
    return ""

proc buildCommandDockData*(model: TuiModel): CommandDockData =
  ## Build command dock data from TUI model
  result = initCommandDockData()
  result.views = standardViews()
  result.setActiveView(activeViewKey(model.ui.mode))
  result.expertModeActive = model.ui.expertModeActive
  result.expertModeInput = model.ui.expertModeInput.value()
  result.showQuit = true
  if model.ui.expertModeFeedback.len > 0:
    result.feedback = model.ui.expertModeFeedback
  else:
    result.feedback = model.ui.statusMessage

  case model.ui.mode
  of ViewMode.Overview:
    let joinActive = model.ui.appPhase == AppPhase.Lobby
    result.contextActions = overviewContextActions(joinActive)
  of ViewMode.Planets:
    result.contextActions = planetsContextActions(
      model.hasColonySelection()
    )
  of ViewMode.Fleets:
    result.contextActions =
      fleetsContextActions(model.view.fleets.len > 0,
        model.ui.selectedFleetIds.len)
  of ViewMode.Research:
    result.contextActions = researchContextActions()
  of ViewMode.Espionage:
    result.contextActions = espionageContextActions(true)
  of ViewMode.Economy:
    result.contextActions = economyContextActions()
  of ViewMode.IntelDb:
    result.contextActions = @[]
  of ViewMode.IntelDetail:
    result.contextActions = @[]
  of ViewMode.Settings:
    result.contextActions = settingsContextActions()
  of ViewMode.PlanetDetail:
    result.contextActions = planetDetailContextActions()
  of ViewMode.FleetDetail:
    result.contextActions = fleetDetailContextActions()
  of ViewMode.Messages:
    result.contextActions = @[
      ContextAction(
        key: "Tab", label: "Cycle focus",
        enabled: true),
      ContextAction(
        key: "M", label: "Messages",
        enabled: true),
      ContextAction(
        key: "R", label: "Reports",
        enabled: true),
      ContextAction(
        key: "C", label: "Compose",
        enabled: true),
    ]

proc renderDashboard*(
    buf: var CellBuffer,
    model: var TuiModel,
    playerState: ps_types.PlayerState,
) =
  ## Render the complete TUI dashboard using EC-style layout
  let termRect = rect(0, 0, model.ui.termWidth, model.ui.termHeight)

  # Layout: HUD (3), Breadcrumb (1), Main Canvas (fill), Status Bar (1)
  # Changed from 3-line dock to 1-line Zellij-style status bar
  let rows = if model.ui.appPhase == AppPhase.InGame:
               vertical().constraints(length(3), length(1), fill(), length(1))
             else:
               vertical().constraints(length(0), length(0), fill(), length(1))
  let rowAreas = rows.split(termRect)

  if rowAreas.len < 4:
    discard buf.setString(0, 0, "Layout error: terminal too small", dimStyle())
    return

  let hudArea = rowAreas[0]
  let breadcrumbArea = rowAreas[1]
  let canvasArea = rowAreas[2]
  let statusBarArea = rowAreas[3]

  # Base background (black)
  buf.fill(Rune(' '), canvasStyle())

  # Render HUD
  if model.ui.appPhase == AppPhase.InGame:
    let hudData = buildHudData(model)
    renderHud(hudArea, buf, hudData)

  # Render Breadcrumb
  if model.ui.appPhase == AppPhase.InGame:
    let breadcrumbData = buildBreadcrumbData(model)
    renderBreadcrumbWithBackground(breadcrumbArea, buf, breadcrumbData)

  # Render main content based on view
  if model.ui.appPhase == AppPhase.Lobby:
    # Entry modal renders over entire viewport (it's a centered modal)
    let viewport = rect(0, 0, buf.w, buf.h)
    model.ui.entryModal.render(viewport, buf)
  else:
    # Fill canvas with dark background (modals will render centered on top)
    buf.fillArea(canvasArea, " ", canvasStyle())

    case model.ui.mode
    of ViewMode.Overview:
      let overviewData = syncPlayerStateToOverview(playerState)
      renderOverviewModal(canvasArea, buf, overviewData,
        model.ui.overviewScroll)
    of ViewMode.Planets:
      renderPlanetsModal(canvasArea, buf, model, model.ui.planetsScroll)
    of ViewMode.Fleets:
      renderFleetsModal(canvasArea, buf, model, playerState,
        model.ui.fleetsScroll)
    of ViewMode.Research:
      renderResearchModal(canvasArea, buf, model, model.ui.researchScroll)
    of ViewMode.Espionage:
      renderEspionageModal(canvasArea, buf, model, model.ui.espionageScroll)
    of ViewMode.Economy:
      renderEconomyModal(canvasArea, buf, model, model.ui.economyScroll)
    of ViewMode.Messages:
      renderInboxModal(canvasArea, buf, model)
    of ViewMode.IntelDb:
      renderIntelDbModal(canvasArea, buf, model)
    of ViewMode.Settings:
      renderSettingsModal(canvasArea, buf, model, model.ui.settingsScroll)
    of ViewMode.PlanetDetail:
      renderPlanetDetailModal(canvasArea, buf, model, playerState)
    of ViewMode.FleetDetail:
      # Render fleet detail as stacked overlay over fleets context
      renderFleetsModal(canvasArea, buf, model, playerState,
        model.ui.fleetsScroll)
      let fleetDetailWidget = newFleetDetailModalWidget()
      var fleetData = fleetToDetailDataFromPS(
        playerState, FleetId(model.ui.fleetDetailModal.fleetId)
      )
      let fid = int(model.ui.fleetDetailModal.fleetId)
      if fid in model.ui.stagedFleetCommands:
        let staged = model.ui.stagedFleetCommands[fid]
        let cmdNum = sam_pkg.fleetCommandNumber(
          staged.commandType
        )
        fleetData.command = sam_pkg.commandLabel(cmdNum)
        fleetData.commandType = int(staged.commandType)
        if staged.roe.isSome:
          fleetData.roe = int(staged.roe.get())
        if staged.commandType == FleetCommandType.JoinFleet and
            staged.targetFleet.isSome:
          let targetId = staged.targetFleet.get()
          var targetName = ""
          for candidate in playerState.ownFleets:
            if candidate.id == targetId:
              targetName = candidate.name
              break
          if targetName.len > 0:
            fleetData.targetLabel = "Fleet " & targetName
          else:
            fleetData.targetLabel = "Fleet " & $targetId
        elif staged.targetSystem.isSome:
          let targetId = staged.targetSystem.get()
          if playerState.visibleSystems.hasKey(targetId):
            let target = playerState.visibleSystems[targetId]
            if target.coordinates.isSome:
              let coords = target.coordinates.get()
              fleetData.targetLabel = coordLabel(
                coords.q.int, coords.r.int
              )
            else:
              fleetData.targetLabel = $targetId
          else:
            fleetData.targetLabel = $targetId
        else:
          fleetData.targetLabel = "-"
      fleetDetailWidget.render(
        model.ui.fleetDetailModal,
        fleetData, canvasArea, buf
      )
    of ViewMode.IntelDetail:
      renderIntelDetailModal(canvasArea, buf, model, playerState)

  # Render build modal if active
  if model.ui.buildModal.active:
    let buildModalWidget = newBuildModalWidget()
    buildModalWidget.render(model.ui.buildModal, canvasArea, buf)
  if model.ui.queueModal.active:
    let queueModalWidget = newQueueModalWidget()
    queueModalWidget.render(model.ui.queueModal, canvasArea, buf)
  renderIntelNoteEditor(canvasArea, buf, model)

  if model.ui.expertModeActive:
    renderExpertPalette(buf, canvasArea, statusBarArea, model)

  renderHelpOverlay(canvasArea, buf, model)

  # Render Zellij-style status bar (1 line)
  if model.ui.appPhase == AppPhase.InGame:
    let statusBarData = buildStatusBarData(model, statusBarArea.width)
    renderStatusBar(statusBarArea, buf, statusBarData)

  if model.ui.quitConfirmationActive:
    renderQuitConfirmation(buf, model)
