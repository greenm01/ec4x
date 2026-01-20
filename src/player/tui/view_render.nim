## TUI view rendering helpers
##
## Rendering functions for the SAM-based TUI views.

import std/[options, unicode]

import ../../engine/types/[core, player_state as ps_types]
import ../../engine/state/engine
import ../sam/sam_pkg
import ../sam/command_parser
import ../tui/buffer
import ../tui/layout/layout_pkg
import ../tui/widget/[widget_pkg, frame, paragraph]
import ../tui/widget/overview
import ../tui/widget/hud
import ../tui/widget/breadcrumb
import ../tui/widget/command_dock
import ../tui/widget/scrollbar
import ../tui/styles/ec_palette
import ../tui/adapters
import ./sync

const
  ExpertPaletteMaxRows = 8
  ExpertPaletteMinWidth = 40
  ExpertPaletteMaxWidth = 80

proc dimStyle*(): CellStyle =
  canvasDimStyle()

proc normalStyle*(): CellStyle =
  canvasStyle()

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
  if not model.expertModeActive:
    return

  let matches = matchExpertCommands(model.expertModeInput)
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
  if model.expertPaletteSelection >= 0 and
      model.expertPaletteSelection < matches.len:
    state.select(model.expertPaletteSelection)
  palette.render(inner, buf, state)

proc renderColonyList*(area: Rect, buf: var CellBuffer, model: TuiModel) =
  ## Render list of player's colonies from SAM model
  var y = area.y
  var idx = 0

  for colony in model.colonies:
    if y >= area.bottom:
      break

    let isSelected = idx == model.selectedIdx
    let style =
      if isSelected:
        selectedStyle()
      else:
        normalStyle()

    let prefix = if isSelected: "> " else: "  "
    let line =
      prefix & colony.systemName.alignLeft(14) & " PP:" &
      align($colony.production, 4) & " Pop:" &
      align($colony.population, 5)
    let clipped = line[0 ..< min(line.len, area.width)]
    discard buf.setString(area.x, y, clipped, style)
    y += 1
    idx += 1

  if idx == 0:
    discard buf.setString(area.x, y, "No colonies", dimStyle())

proc renderFleetList*(area: Rect, buf: var CellBuffer, model: TuiModel) =
  ## Render list of player's fleets from SAM model
  var y = area.y
  var idx = 0

  for fleet in model.fleets:
    if y >= area.bottom:
      break

    let isSelected = idx == model.selectedIdx
    let style =
      if isSelected:
        selectedStyle()
      else:
        normalStyle()

    let prefix = if isSelected: "> " else: "  "
    let fleetName = "Fleet #" & $fleet.id
    let line =
      prefix & fleetName.alignLeft(12) & " @ " &
      fleet.locationName.alignLeft(10) & " Ships:" & $fleet.shipCount
    let clipped = line[0 ..< min(line.len, area.width)]
    discard buf.setString(area.x, y, clipped, style)
    y += 1
    idx += 1

  if idx == 0:
    discard buf.setString(area.x, y, "No fleets", dimStyle())

proc renderFleetDetail*(
  area: Rect,
  buf: var CellBuffer,
  model: TuiModel,
  state: GameState,
  viewingHouse: HouseId
) =
  ## Render detailed fleet view with ship list table
  if model.selectedFleetId <= 0:
    discard buf.setString(
      area.x, area.y, "No fleet selected", dimStyle()
    )
    return

  # Convert engine data to display data using adapter
  let fleetData = fleetToDetailData(
    state,
    FleetId(model.selectedFleetId),
    viewingHouse
  )

  var y = area.y

  # Header: Fleet location and command
  discard buf.setString(
    area.x, y,
    "Fleet #" & $fleetData.fleetId & " @ " & fleetData.location,
    canvasHeaderStyle()
  )
  y += 1

  discard buf.setString(
    area.x, y,
    "Command: " & fleetData.command,
    normalStyle()
  )
  y += 1

  discard buf.setString(
    area.x, y,
    "Status: " & fleetData.status & "  ROE: " & $fleetData.roe,
    normalStyle()
  )
  y += 2

  # Ships table header
  discard buf.setString(
    area.x, y,
    "Ships (" & $fleetData.shipCount & "):",
    canvasHeaderStyle()
  )
  y += 1

  # Build table widget for ships
  if fleetData.ships.len > 0:
    var shipTable = table([
      tableColumn("Name", 12, table.Alignment.Left),
      tableColumn("Class", 16, table.Alignment.Left),
      tableColumn("HP", 6, table.Alignment.Right),
      tableColumn("Attack", 7, table.Alignment.Right),
      tableColumn("Defense", 7, table.Alignment.Right)
    ])

    # Add ship rows
    for ship in fleetData.ships:
      shipTable.addRow(@[
        ship.name,
        ship.class,
        ship.hp,
        ship.attack,
        ship.defense
      ])

    # Render table
    let tableArea = rect(area.x, y, area.width, area.height - (y - area.y))
    shipTable.render(tableArea, buf)
    y += fleetData.ships.len + 3  # Table height
  else:
    discard buf.setString(area.x, y, "  No ships", dimStyle())
    y += 1

  # Totals footer
  y += 1
  if y < area.bottom:
    discard buf.setString(
      area.x, y,
      "Total Attack: " & $fleetData.totalAttack &
        "  Total Defense: " & $fleetData.totalDefense,
      CellStyle(fg: color(PrestigeColor), attrs: {StyleAttr.Bold})
    )

proc renderPlanetDetail*(
  area: Rect,
  buf: var CellBuffer,
  model: TuiModel,
  state: GameState,
  viewingHouse: HouseId
) =
  ## Render detailed planet view with construction queue
  if model.selectedColonyId <= 0:
    discard buf.setString(
      area.x, area.y, "No colony selected", dimStyle()
    )
    return

  # Convert engine data to display data using adapter
  let planetData = colonyToDetailData(
    state,
    ColonyId(model.selectedColonyId),
    viewingHouse
  )

  var y = area.y

  # Header: Planet name and basic info
  discard buf.setString(
    area.x, y,
    planetData.systemName & " (Colony)",
    canvasHeaderStyle()
  )
  y += 1

  discard buf.setString(
    area.x, y,
    "Pop: " & $planetData.population & "  Production: " &
      $planetData.production,
    normalStyle()
  )
  y += 2

  # Tabs (for Phase 2+ - just show active tab for now)
  discard buf.setString(
    area.x, y,
    "[Construction]  Economy  Defense  Settings",
    canvasHeaderStyle()
  )
  y += 2

  # Construction Queue section
  discard buf.setString(
    area.x, y,
    "CONSTRUCTION QUEUE (Docks: " & $planetData.availableDocks & "/" &
      $planetData.totalDocks & " available)",
    canvasHeaderStyle()
  )
  y += 1

  if planetData.constructionQueue.len > 0:
    # Table header
    discard buf.setString(
      area.x, y,
      "#  Project         Cost  Progress       ETA",
      CellStyle(fg: color(CanvasFgColor), attrs: {StyleAttr.Bold})
    )
    y += 1

    # Construction items with progress bars
    var idx = 1
    for item in planetData.constructionQueue:
      if y >= area.bottom - 5:
        break

      # Item number and name
      let itemLine =
        align($idx, 2) & ". " &
        item.name.alignLeft(15) &
        align($item.costTotal, 5) & "  "
      discard buf.setString(area.x, y, itemLine, normalStyle())

      # Progress bar
      let barX = area.x + itemLine.len
      let barWidth = 10
      let progress = progressBar(item.costPaid, item.costTotal, barWidth)
        .label("")
        .showPercent(false)
        .showRemaining(false)

      progress.render(rect(barX, y, barWidth + 15, 1), buf)

      # Progress percentage manually
      let pctStr = " " & $item.progressPercent & "%"
      discard buf.setString(
        barX + barWidth + 1, y,
        pctStr,
        dimStyle()
      )
      # ETA
      let etaStr = $item.turnsRemaining & " trn"
      discard buf.setString(
        barX + barWidth + 2, y,
        etaStr,
        normalStyle()
      )

      y += 1
      idx += 1
  else:
    discard buf.setString(area.x, y, "  No projects queued", dimStyle())
    y += 1

  y += 1

  # Repair Queue section
  if planetData.repairQueue.len > 0:
    discard buf.setString(
      area.x, y,
      "REPAIR QUEUE",
      canvasHeaderStyle()
    )
    y += 1

    for repair in planetData.repairQueue:
      if y >= area.bottom:
        break
      let repairLine =
        "  " & repair.name.alignLeft(20) &
        " Cost: " & align($repair.costTotal, 4) &
        " ETA: " & $repair.turnsRemaining & " trn"
      discard buf.setString(area.x, y, repairLine, normalStyle())
      y += 1

proc reportCategoryGlyph*(category: ReportCategory): string =
  ## Glyph for report category
  case category
  of ReportCategory.Combat: "X"
  of ReportCategory.Intelligence: "I"
  of ReportCategory.Economy: "$"
  of ReportCategory.Diplomacy: "="
  of ReportCategory.Operations: "+"
  of ReportCategory.Summary: "*"
  of ReportCategory.Other: "."

proc reportCategoryStyle*(category: ReportCategory): CellStyle =
  ## Style for report category glyph
  case category
  of ReportCategory.Combat:
    CellStyle(
      fg: color(EnemyStatusColor),
      attrs: {StyleAttr.Bold}
    )
  of ReportCategory.Intelligence:
    CellStyle(
      fg: color(PrestigeColor),
      attrs: {StyleAttr.Bold}
    )
  of ReportCategory.Economy:
    CellStyle(
      fg: color(ProductionColor),
      attrs: {StyleAttr.Bold}
    )
  of ReportCategory.Diplomacy:
    CellStyle(
      fg: color(NeutralStatusColor),
      attrs: {StyleAttr.Bold}
    )
  of ReportCategory.Operations:
    CellStyle(
      fg: color(HostileStatusColor),
      attrs: {StyleAttr.Bold}
    )
  of ReportCategory.Summary:
    CellStyle(
      fg: color(PrestigeColor),
      attrs: {StyleAttr.Bold}
    )
  of ReportCategory.Other:
    CellStyle(
      fg: color(CanvasDimColor),
      attrs: {}
    )

proc renderReportsList*(area: Rect, buf: var CellBuffer, model: TuiModel) =
  ## Render the reports inbox list
  if area.height < 5 or area.width < 40:
    return

  let dimStyle = canvasDimStyle()
  let normalStyle = canvasStyle()
  let focusLabel = reportPaneLabel(model.reportFocus)

  let filterLabel = reportCategoryLabel(model.reportFilter)
  let filterKey = reportCategoryKey(model.reportFilter)
  let filterLine = "Filter [Tab]: " & filterLabel & " [" & $filterKey & "]"
  discard buf.setString(area.x, area.y, filterLine, canvasHeaderStyle())

  let bodyArea = rect(area.x, area.y + 1, area.width, area.height - 1)
  if bodyArea.isEmpty:
    return

  let columns = horizontal()
    .constraints(length(16), length(34), fill())
    .split(bodyArea)

  let turnArea = columns[0]
  let subjectArea = columns[1]
  let bodyPaneArea = columns[2]

  let turnTitle = if model.reportFocus == ReportPaneFocus.TurnList:
                    "TURNS *"
                  else:
                    "TURNS"
  let subjectTitle = if model.reportFocus == ReportPaneFocus.SubjectList:
                       "SUBJECTS *"
                     else:
                       "SUBJECTS"
  let bodyTitle = if model.reportFocus == ReportPaneFocus.BodyPane:
                    "REPORT *"
                  else:
                    "REPORT"
  let turnFrame = bordered()
    .title(turnTitle)
    .borderType(BorderType.Rounded)
  let subjectFrame = bordered()
    .title(subjectTitle)
    .borderType(BorderType.Rounded)
  let bodyFrame = bordered()
    .title(bodyTitle)
    .borderType(BorderType.Rounded)

  turnFrame.render(turnArea, buf)
  subjectFrame.render(subjectArea, buf)
  bodyFrame.render(bodyPaneArea, buf)

  let turnInner = turnFrame.inner(turnArea)
  let subjectInner = subjectFrame.inner(subjectArea)
  let bodyInner = bodyFrame.inner(bodyPaneArea)

  let buckets = model.reportsByTurn()
  var y = turnInner.y
  let turnCount = buckets.len
  var turnScroll = model.reportTurnScroll
  turnScroll.contentLength = turnCount
  turnScroll.viewportLength = turnInner.height
  turnScroll.clampOffsets()
  let turnStart = turnScroll.verticalOffset
  let turnEnd = min(turnCount, turnStart + turnInner.height)
  for idx in turnStart ..< turnEnd:
    if y >= turnInner.bottom:
      break
    let bucket = buckets[idx]
    let isSelected = idx == model.reportTurnIdx
    let rowStyle = if isSelected: selectedStyle() else: normalStyle
    let prefix = if isSelected: ">" else: " "

    let unreadLabel = if bucket.unreadCount > 0:
                        "(" & $bucket.unreadCount & ")"
                      else:
                        ""
    let rowText = prefix & " T" & $bucket.turn & " " & unreadLabel
    let clipped = rowText[0 ..< min(rowText.len, turnInner.width)]
    if y >= turnInner.y:
      discard buf.setString(turnInner.x, y, clipped, rowStyle)
    y += 1

  var subjectY = subjectInner.y
  let reports = model.currentTurnReports()
  var subjectScroll = model.reportSubjectScroll
  subjectScroll.contentLength = reports.len
  subjectScroll.viewportLength = subjectInner.height
  subjectScroll.clampOffsets()
  let subjectStart = subjectScroll.verticalOffset
  let subjectEnd = min(reports.len, subjectStart + subjectInner.height)
  for idx in subjectStart ..< subjectEnd:
    if subjectY >= subjectInner.bottom:
      break
    let report = reports[idx]
    let isSelected = idx == model.reportSubjectIdx
    let rowStyle = if isSelected: selectedStyle() else: normalStyle
    let marker = if isSelected: ">" else: " "
    let unread = if report.isUnread: GlyphUnread else: " "
    let glyph = reportCategoryGlyph(report.category)
    let glyphStyle = reportCategoryStyle(report.category)
    discard buf.setString(subjectInner.x, subjectY, marker & " ", rowStyle)
    discard buf.setString(subjectInner.x + 2, subjectY, glyph & " ", glyphStyle)
    discard buf.setString(subjectInner.x + 4, subjectY, unread & " ", rowStyle)

    let titleMax = subjectInner.width - 8
    let title = if report.title.len > titleMax:
                  report.title[0 ..< max(0, titleMax - 3)] & "..."
                else:
                  report.title
    discard buf.setString(subjectInner.x + 6, subjectY, title, rowStyle)
    subjectY += 1

  let reportOpt = model.currentReport()
  if reportOpt.isSome:
    let report = reportOpt.get()
    let lines = @[
      line("T" & $report.turn & " " & report.title),
      line(report.summary),
      line(""),
    ]
    var detailLines: seq[Line] = @[]
    for entry in report.detail:
      detailLines.add(line("- " & entry))
    let bodyText = text(lines & detailLines)
    let bodyContent = bodyInner
    var bodyScroll = model.reportBodyScroll
    bodyScroll.contentLength = bodyText.lines.len
    bodyScroll.viewportLength = bodyContent.height
    bodyScroll.clampOffsets()

    let bodyParagraph = paragraph(bodyText)
      .wrap(Wrap(trim: true))
      .scrollState(bodyScroll)
    bodyParagraph.render(bodyContent, buf)
  else:
    let emptyText = text("No report selected")
    let emptyParagraph = paragraph(emptyText)
      .wrap(Wrap(trim: true))
    emptyParagraph.render(bodyInner, buf)

  let turnScrollbar = ScrollbarState(
    contentLength: turnScroll.contentLength,
    position: turnScroll.verticalOffset,
    viewportLength: turnScroll.viewportLength
  )
  renderScrollbar(turnInner, buf, turnScrollbar,
    ScrollbarOrientation.VerticalRight)

  let subjectScrollbar = ScrollbarState(
    contentLength: subjectScroll.contentLength,
    position: subjectScroll.verticalOffset,
    viewportLength: subjectScroll.viewportLength
  )
  renderScrollbar(subjectInner, buf, subjectScrollbar,
    ScrollbarOrientation.VerticalRight)

  let bodyScrollbar = ScrollbarState(
    contentLength: model.reportBodyScroll.contentLength,
    position: model.reportBodyScroll.verticalOffset,
    viewportLength: model.reportBodyScroll.viewportLength
  )
  renderScrollbar(bodyInner, buf, bodyScrollbar,
    ScrollbarOrientation.VerticalRight)

  discard buf.setString(area.x + 1, area.y, focusLabel, dimStyle)

proc renderReportDetail*(area: Rect, buf: var CellBuffer, model: TuiModel) =
  ## Render full-screen report detail view
  if area.height < 6 or area.width < 30:
    return

  let reportOpt = model.selectedReport()
  if reportOpt.isNone:
    discard buf.setString(area.x, area.y, "No report selected", dimStyle())
    return

  let report = reportOpt.get()
  let dimStyle = canvasDimStyle()

  let detailFrame = bordered()
    .title("REPORT DETAIL")
    .borderType(BorderType.Rounded)
  detailFrame.render(area, buf)
  let detailInner = detailFrame.inner(area)

  var detailLines: seq[Line] = @[]
  detailLines.add(line("T" & $report.turn & " " & report.title))
  detailLines.add(line(report.summary))
  detailLines.add(line(""))
  for entry in report.detail:
    detailLines.add(line("- " & entry))

  let detailText = text(detailLines)
  var detailScroll = model.reportBodyScroll
  detailScroll.contentLength = detailText.lines.len
  detailScroll.viewportLength = detailInner.height
  detailScroll.clampOffsets()

  let detailParagraph = paragraph(detailText)
    .wrap(Wrap(trim: true))
    .scrollState(detailScroll)
  detailParagraph.render(detailInner, buf)

  let detailScrollbar = ScrollbarState(
    contentLength: detailScroll.contentLength,
    position: detailScroll.verticalOffset,
    viewportLength: detailScroll.viewportLength
  )
  renderScrollbar(detailInner, buf, detailScrollbar,
    ScrollbarOrientation.VerticalRight)

  let hintLine = "Enter: Jump  Backspace: Inbox"
  discard buf.setString(detailInner.x, detailInner.bottom - 1,
    hintLine, dimStyle)

proc renderListPanel*(
    area: Rect,
    buf: var CellBuffer,
    model: TuiModel,
    state: GameState,
    viewingHouse: HouseId,
) =
  ## Render the main list panel based on current mode

  let title =
    case model.mode
    of ViewMode.Overview: "Empire Status"
    of ViewMode.Planets: "Your Colonies"
    of ViewMode.Fleets: "Your Fleets"
    of ViewMode.Research: "Research Progress"
    of ViewMode.Espionage: "Intel Operations"
    of ViewMode.Economy: "Treasury & Income"
    of ViewMode.Reports: "Reports Inbox"
    of ViewMode.Messages: "Diplomatic Messages"
    of ViewMode.Settings: "Game Settings"
    of ViewMode.PlanetDetail: "Planet Info"
    of ViewMode.FleetDetail: "Fleet Info"
    of ViewMode.ReportDetail: "Report"

  let frame = bordered().title(title).borderType(BorderType.Rounded)
  frame.render(area, buf)
  let inner = frame.inner(area)

  case model.mode
  of ViewMode.Overview:
    # Overview placeholder - will show empire dashboard in Phase 2
    var y = inner.y
    discard buf.setString(inner.x, y, "STRATEGIC OVERVIEW",
      canvasHeaderStyle())
    y += 2
    discard buf.setString(inner.x, y,
      "Turn: " & $model.turn, normalStyle())
    y += 1
    discard buf.setString(inner.x, y,
      "Colonies: " & $model.colonies.len, normalStyle())
    y += 1
    discard buf.setString(inner.x, y,
      "Fleets: " & $model.fleets.len, normalStyle())
    y += 2
    discard buf.setString(inner.x, y,
      "[1-9] Switch views  [Q] Quit  [J] Join", dimStyle())
  of ViewMode.Planets:
    renderColonyList(inner, buf, model)
  of ViewMode.Fleets:
    renderFleetList(inner, buf, model)
  of ViewMode.Research:
    discard buf.setString(inner.x, inner.y,
      "Research view (TODO)", dimStyle())
  of ViewMode.Espionage:
    discard buf.setString(inner.x, inner.y,
      "Espionage view (TODO)", dimStyle())
  of ViewMode.Economy:
    discard buf.setString(inner.x, inner.y,
      "Economy view (TODO)", dimStyle())
  of ViewMode.Reports:
    renderReportsList(inner, buf, model)
  of ViewMode.Messages:
    discard buf.setString(inner.x, inner.y,
      "Messages view (TODO)", dimStyle())
  of ViewMode.Settings:
    discard buf.setString(inner.x, inner.y,
      "Settings view (TODO)", dimStyle())
  of ViewMode.PlanetDetail:
    renderPlanetDetail(inner, buf, model, state, viewingHouse)
  of ViewMode.FleetDetail:
    renderFleetDetail(inner, buf, model, state, viewingHouse)
  of ViewMode.ReportDetail:
    renderReportDetail(inner, buf, model)

proc buildHudData*(model: TuiModel): HudData =
  ## Build HUD data from TUI model
  HudData(
    houseName: model.houseName,
    turn: model.turn,
    prestige: model.prestige,
    prestigeRank: model.prestigeRank,
    totalHouses: model.totalHouses,
    treasury: model.treasury,
    production: model.production,
    commandUsed: model.commandUsed,
    commandMax: model.commandMax,
    alertCount: model.alertCount,
    unreadMessages: model.unreadMessages,
  )

proc buildBreadcrumbData*(model: TuiModel): BreadcrumbData =
  ## Build breadcrumb data from TUI model
  result = initBreadcrumbData()
  if model.breadcrumbs.len == 0:
    # Safety: should never happen, but handle gracefully
    result.add("Home", 1)
    return
  if model.breadcrumbs.len == 1 and model.breadcrumbs[0].label == "Home":
    result.add("Home", 1)
    result.add(model.mode.viewModeLabel, int(model.mode))
  else:
    for item in model.breadcrumbs:
      result.add(item.label, int(item.viewMode), item.entityId)

proc activeViewKey*(mode: ViewMode): char =
  ## Map view mode to dock key
  let modeInt = int(mode)
  if modeInt >= 1 and modeInt <= 9:
    return chr(ord('0') + modeInt)
  case mode
  of ViewMode.PlanetDetail:
    return '2'
  of ViewMode.FleetDetail:
    return '3'
  of ViewMode.ReportDetail:
    return '7'
  else:
    return '1'

proc buildCommandDockData*(model: TuiModel): CommandDockData =
  ## Build command dock data from TUI model
  result = initCommandDockData()
  result.views = standardViews()
  result.setActiveView(activeViewKey(model.mode))
  result.expertModeActive = model.expertModeActive
  result.expertModeInput = model.expertModeInput
  result.showQuit = true
  if model.expertModeFeedback.len > 0:
    result.feedback = model.expertModeFeedback
  else:
    result.feedback = model.statusMessage

  # Order entry mode has special context actions
  if model.orderEntryActive:
    result.contextActions = orderEntryContextActions(
      model.orderEntryCommandType
    )
    return

  case model.mode
  of ViewMode.Overview:
    let joinActive = model.appPhase == AppPhase.Lobby
    result.contextActions = overviewContextActions(joinActive)
  of ViewMode.Planets:
    result.contextActions = planetsContextActions(model.colonies.len > 0)
  of ViewMode.Fleets:
    result.contextActions =
      fleetsContextActions(model.fleets.len > 0, model.selectedFleetIds.len)
  of ViewMode.Research:
    result.contextActions = researchContextActions()
  of ViewMode.Espionage:
    result.contextActions = espionageContextActions(true)
  of ViewMode.Economy:
    result.contextActions = economyContextActions()
  of ViewMode.Reports:
    result.contextActions = reportsContextActions(
      model.currentListLength() > 0
    )
  of ViewMode.Messages:
    result.contextActions = messagesContextActions(false)
  of ViewMode.Settings:
    result.contextActions = settingsContextActions()
  of ViewMode.PlanetDetail:
    result.contextActions = planetDetailContextActions()
  of ViewMode.FleetDetail:
    result.contextActions = fleetDetailContextActions()
  of ViewMode.ReportDetail:
    result.contextActions = reportsContextActions(
      model.currentListLength() > 0
    )

proc renderDashboard*(
    buf: var CellBuffer,
    model: TuiModel,
    state: GameState,
    viewingHouse: HouseId,
    playerState: ps_types.PlayerState,
) =
  ## Render the complete TUI dashboard using EC-style layout
  let termRect = rect(0, 0, model.termWidth, model.termHeight)

  # Layout: HUD (2), Breadcrumb (1), Main Canvas (fill), Command Dock (3)
  let rows = if model.appPhase == AppPhase.InGame:
               vertical().constraints(length(3), length(1), fill(), length(3))
             else:
               vertical().constraints(length(0), length(0), fill(), length(3))
  let rowAreas = rows.split(termRect)

  if rowAreas.len < 4:
    discard buf.setString(0, 0, "Layout error: terminal too small", dimStyle())
    return

  let hudArea = rowAreas[0]
  let breadcrumbArea = rowAreas[1]
  let canvasArea = rowAreas[2]
  let dockArea = rowAreas[3]

  # Base background (black)
  buf.fill(Rune(' '), canvasStyle())

  # Render HUD
  if model.appPhase == AppPhase.InGame:
    let hudData = buildHudData(model)
    renderHud(hudArea, buf, hudData)

  # Render Breadcrumb
  if model.appPhase == AppPhase.InGame:
    let breadcrumbData = buildBreadcrumbData(model)
    renderBreadcrumbWithBackground(breadcrumbArea, buf, breadcrumbData)

  # Render main content based on view
  if model.appPhase == AppPhase.Lobby:
    # Entry modal renders over entire viewport (it's a centered modal)
    let viewport = rect(0, 0, buf.w, buf.h)
    model.entryModal.render(viewport, buf)
  else:
    case model.mode
    of ViewMode.Overview:
      let overviewData = syncPlayerStateToOverview(playerState, state)
      renderOverview(canvasArea, buf, overviewData)
    else:
      renderListPanel(canvasArea, buf, model, state, viewingHouse)

  if model.expertModeActive:
    renderExpertPalette(buf, canvasArea, dockArea, model)

  # Render Command Dock
  let dockData = buildCommandDockData(model)
  if dockArea.width >= 100:
    renderCommandDock(dockArea, buf, dockData)
  else:
    renderCommandDockCompact(dockArea, buf, dockData)
