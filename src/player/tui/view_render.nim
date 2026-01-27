## TUI view rendering helpers
##
## Rendering functions for the SAM-based TUI views.

import std/[options, unicode, strutils]

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
import ../tui/widget/status_bar
import ../tui/widget/scrollbar
import ../tui/widget/view_modal
import ../tui/widget/build_modal
import ../tui/widget/hexmap/symbols
import ../sam/bindings
import ../tui/styles/ec_palette
import ../tui/adapters
import ./sync

const
  ExpertPaletteMaxRows = 8
  ExpertPaletteMinWidth = 40
  ExpertPaletteMaxWidth = 80

var
  cachedExpertInput = ""
  cachedExpertMatches: seq[ExpertCommandMatch] = @[]
  cachedReportFilter = ReportCategory.Summary
  cachedReportSignature = 0'u64
  cachedReportCount = 0
  cachedReportBuckets: seq[TurnBucket] = @[]

proc reportSignature(reports: seq[ReportEntry]): uint64 =
  var sig = 1469598103934665603'u64
  for report in reports:
    sig = sig xor uint64(report.id)
    sig = sig * 1099511628211'u64
    sig = sig xor uint64(report.turn)
    sig = sig * 1099511628211'u64
    sig = sig xor uint64(ord(report.category))
    sig = sig * 1099511628211'u64
    sig = sig xor (if report.isUnread: 1'u64 else: 0'u64)
    sig = sig * 1099511628211'u64
  sig

proc expertMatchesCached(input: string): seq[ExpertCommandMatch] =
  if input != cachedExpertInput:
    cachedExpertInput = input
    cachedExpertMatches = matchExpertCommands(input)
  cachedExpertMatches

proc reportsByTurnCached(model: TuiModel): seq[TurnBucket] =
  let sig = reportSignature(model.view.reports)
  if sig != cachedReportSignature or
      cachedReportFilter != model.ui.reportFilter or
      cachedReportCount != model.view.reports.len:
    cachedReportSignature = sig
    cachedReportFilter = model.ui.reportFilter
    cachedReportCount = model.view.reports.len
    cachedReportBuckets = model.reportsByTurn()
  cachedReportBuckets

proc currentTurnReportsFromBuckets(model: TuiModel,
    buckets: seq[TurnBucket]): seq[ReportEntry] =
  if buckets.len == 0:
    return @[]
  let turnIdx = max(0, min(model.ui.reportTurnIdx, buckets.len - 1))
  buckets[turnIdx].reports

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

  let matches = expertMatchesCached(model.ui.expertModeInput)
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
  let compact = tableArea.width < 100
  var columns: seq[TableColumn] = @[]
  if compact:
    columns = @[
      tableColumn("Colony", 16, table.Alignment.Left),
      tableColumn("Sec", 4, table.Alignment.Left),
      tableColumn("Class", 6, table.Alignment.Left),
      tableColumn("Pop", 4, table.Alignment.Right),
      tableColumn("GCO", 5, table.Alignment.Right),
      tableColumn("NCV", 5, table.Alignment.Right),
      tableColumn("CDK", 5, table.Alignment.Right),
      tableColumn("RDK", 5, table.Alignment.Right),
      tableColumn("Status", 10, table.Alignment.Left)
    ]
  else:
    columns = @[
      tableColumn("Colony", 18, table.Alignment.Left),
      tableColumn("Sector", 6, table.Alignment.Left),
      tableColumn("Class", 8, table.Alignment.Left),
      tableColumn("Pop", 5, table.Alignment.Right),
      tableColumn("IU", 5, table.Alignment.Right),
      tableColumn("GCO", 6, table.Alignment.Right),
      tableColumn("NCV", 6, table.Alignment.Right),
      tableColumn("Growth", 7, table.Alignment.Right),
      tableColumn("CDK", 7, table.Alignment.Right),
      tableColumn("RDK", 7, table.Alignment.Right),
      tableColumn("Status", 12, table.Alignment.Left)
    ]

  var colonyTable = table(columns)
    .selectedIdx(model.ui.selectedIdx)
    .zebraStripe(true)

  let statusColumn = columns.len - 1
  var totalGco = 0
  var totalNcv = 0
  var idleCount = 0
  for colony in model.view.colonies:
    totalGco += colony.grossOutput
    totalNcv += colony.netValue
    if colony.idleConstruction:
      idleCount.inc

    let constructionLabel = dockLabel(
      colony.constructionDockAvailable,
      colony.constructionDockTotal
    )
    let repairLabel = dockLabel(
      colony.repairDockAvailable,
      colony.repairDockTotal
    )
    let classLabel =
      if colony.planetClass >= 0 and
          colony.planetClass < PlanetClassNames.len:
        PlanetClassNames[colony.planetClass]
      else:
        "Unknown"
    let growthLabel = formatGrowthLabel(colony.populationGrowthPu)

    var statusLabel = GlyphOk
    var statusStyle = normalStyle()
    if colony.blockaded:
      statusLabel = GlyphWarning & " Blockade"
      statusStyle = alertStyle()
    elif colony.idleConstruction:
      statusLabel = GlyphWarning & " Idle"
      statusStyle = alertStyle()

    var row: seq[string] = @[]
    if compact:
      row = @[
        colony.systemName,
        colony.sectorLabel,
        classLabel,
        $colony.populationUnits,
        $colony.grossOutput,
        $colony.netValue,
        constructionLabel,
        repairLabel,
        statusLabel
      ]
    else:
      row = @[
        colony.systemName,
        colony.sectorLabel,
        classLabel,
        $colony.populationUnits,
        $colony.industrialUnits,
        $colony.grossOutput,
        $colony.netValue,
        growthLabel,
        constructionLabel,
        repairLabel,
        statusLabel
      ]

    colonyTable.addRow(row, statusStyle, statusColumn)

  colonyTable.render(tableArea, buf)

  if footerHeight > 0 and area.height > 1:
    let footerY = area.y + tableHeight
    let taxLabel = if model.view.houseTaxRate > 0:
                     $model.view.houseTaxRate & "% tax"
                   else:
                     "tax n/a"
    let summary =
      $model.view.colonies.len & " colonies  |  GHO: " & $totalGco &
      " PP  |  NHV: " & $totalNcv &
      " PP (" & taxLabel & ")  |  " &
      $idleCount & " idle"
    let clipped = summary[0 ..< min(summary.len, area.width)]
    discard buf.setString(area.x, footerY, clipped, dimStyle())

proc renderPlanetsTable*(area: Rect, buf: var CellBuffer,
                         model: TuiModel, scroll: ScrollState) =
  ## Render Planets table per spec: 14 columns, box borders, scrolling
  if area.isEmpty:
    return

  # 14 column layout per spec
  let columns = @[
    tableColumn("System", 18, table.Alignment.Left),
    tableColumn("Sector", 5, table.Alignment.Center),
    tableColumn("Owner", 10, table.Alignment.Left),
    tableColumn("Class", 7, table.Alignment.Left),
    tableColumn("Res", 5, table.Alignment.Left),
    tableColumn("Pop", 5, table.Alignment.Right),
    tableColumn("IU", 5, table.Alignment.Right),
    tableColumn("GCO", 6, table.Alignment.Right),
    tableColumn("NCV", 6, table.Alignment.Right),
    tableColumn("Growth", 7, table.Alignment.Right),
    tableColumn("CD", 3, table.Alignment.Right),
    tableColumn("RD", 3, table.Alignment.Right),
    tableColumn("LTU", 4, table.Alignment.Right),
    tableColumn("Status", 0, table.Alignment.Left)  # Fill remaining space
  ]

  var planetsTable = table(columns)
    .selectedIdx(model.ui.selectedIdx)
    .zebraStripe(true)

  for row in model.view.planetsRows:
    let popLabel = if row.pop.isSome: $row.pop.get else: "—"
    let iuLabel = if row.iu.isSome: $row.iu.get else: "—"
    let gcoLabel = if row.gco.isSome: $row.gco.get else: "—"
    let ncvLabel = if row.ncv.isSome: $row.ncv.get else: "—"
    let cdLabel = if row.cdTotal.isSome: $row.cdTotal.get else: "—"
    let rdLabel = if row.rdTotal.isSome: $row.rdTotal.get else: "—"

    var statusStyle = normalStyle()
    var statusLabel = row.statusLabel
    if row.hasAlert:
      statusStyle = alertStyle()
      statusLabel = GlyphWarning & " " & statusLabel

    let dataRow = @[
      row.systemName,
      row.sectorLabel,
      row.ownerName,
      row.classLabel,
      row.resourceLabel,
      popLabel,
      iuLabel,
      gcoLabel,
      ncvLabel,
      row.growthLabel,
      cdLabel,
      rdLabel,
      row.ltuLabel,
      statusLabel
    ]

    planetsTable.addRow(dataRow, statusStyle, 13)  # Status column for style

  planetsTable.render(area, buf)

proc renderFleetList*(area: Rect, buf: var CellBuffer, model: TuiModel) =
  ## Render list of player's fleets from SAM model
  var y = area.y
  var idx = 0

  for fleet in model.view.fleets:
    if y >= area.bottom:
      break

    let isSelected = idx == model.ui.selectedIdx
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
  if model.ui.selectedFleetId <= 0:
    discard buf.setString(
      area.x, area.y, "No fleet selected", dimStyle()
    )
    return

  # Convert engine data to display data using adapter
  let fleetData = fleetToDetailData(
    state,
    FleetId(model.ui.selectedFleetId),
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
      tableColumn("State", 9, table.Alignment.Left),
      tableColumn("Attack", 7, table.Alignment.Right),
      tableColumn("Defense", 7, table.Alignment.Right)
    ])

    # Add ship rows
    let stateColumn = 2
    let crippledStyle = CellStyle(fg: color(PrestigeColor), attrs: {})
    for ship in fleetData.ships:
      let stateStyle = if ship.isCrippled: crippledStyle else: positiveStyle()
      shipTable.addRow(@[
        ship.name,
        ship.class,
        ship.state,
        ship.attack,
        ship.defense
      ], stateStyle, stateColumn)

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
      "Docks: CDK " & dockLabel(
        data.dockSummary.constructionAvailable,
        data.dockSummary.constructionTotal
      ) & "  RDK " & dockLabel(
        data.dockSummary.repairAvailable,
        data.dockSummary.repairTotal
      )
    discard buf.setString(right.x, rightY, dockLine, normalStyle())
    rightY += 1
  if rightY < right.bottom and data.dockedFleets.len > 0:
    discard buf.setString(right.x, rightY, "Docked Fleets:",
      canvasHeaderStyle())
    rightY += 1
    for fleet in data.dockedFleets:
      if rightY >= right.bottom:
        break
      let fleetLine =
        "  " & fleet.name &
        " (" & $fleet.shipCount & " ships)"
      discard buf.setString(right.x, rightY, fleetLine, normalStyle())
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
    "Construction Docks: " & dockLabel(
      data.dockSummary.constructionAvailable,
      data.dockSummary.constructionTotal
    ) &
    "  Repair Docks: " & dockLabel(
      data.dockSummary.repairAvailable,
      data.dockSummary.repairTotal
    )
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
        queueTable = queueTable.showSelector(false)
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
        buildTable = buildTable.showSelector(false)
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
  if rightY < right.bottom and data.dockedFleets.len > 0:
    discard buf.setString(right.x, rightY, "Guard Fleets:",
      canvasHeaderStyle())
    rightY += 1
    for fleet in data.dockedFleets:
      if rightY >= right.bottom:
        break
      let fleetLine =
        "  " & fleet.name &
        " (" & $fleet.shipCount & " ships)"
      discard buf.setString(right.x, rightY, fleetLine, normalStyle())
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

  let planetData = colonyToDetailData(
    state,
    ColonyId(model.ui.selectedColonyId),
    viewingHouse
  )

  if area.isEmpty:
    return

  var y = area.y
  let tabArea = rect(area.x, y, area.width, 1)
  let activeIdx = ord(model.ui.planetDetailTab) - 1
  let tabs = planetDetailTabs(activeIdx)
  tabs.render(tabArea, buf)
  y += 2
  if y >= area.bottom:
    return

  let contentArea = rect(area.x, y, area.width, area.bottom - y)
  case model.ui.planetDetailTab
  of PlanetDetailTab.Summary:
    renderPlanetSummaryTab(contentArea, buf, planetData)
  of PlanetDetailTab.Economy:
    renderPlanetEconomyTab(contentArea, buf, planetData)
  of PlanetDetailTab.Construction:
    renderPlanetConstructionTab(contentArea, buf, planetData)
  of PlanetDetailTab.Defense:
    renderPlanetDefenseTab(contentArea, buf, planetData)
  of PlanetDetailTab.Settings:
    renderPlanetSettingsTab(contentArea, buf, planetData)

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

  let planetData = colonyToDetailDataFromPS(ps, ColonyId(model.ui.selectedColonyId))

  if area.isEmpty:
    return

  var y = area.y
  let tabArea = rect(area.x, y, area.width, 1)
  let activeIdx = ord(model.ui.planetDetailTab) - 1
  let tabs = planetDetailTabs(activeIdx)
  tabs.render(tabArea, buf)
  y += 2
  if y >= area.bottom:
    return

  let contentArea = rect(area.x, y, area.width, area.bottom - y)
  case model.ui.planetDetailTab
  of PlanetDetailTab.Summary:
    renderPlanetSummaryTab(contentArea, buf, planetData)
  of PlanetDetailTab.Economy:
    renderPlanetEconomyTab(contentArea, buf, planetData)
  of PlanetDetailTab.Construction:
    renderPlanetConstructionTab(contentArea, buf, planetData)
  of PlanetDetailTab.Defense:
    renderPlanetDefenseTab(contentArea, buf, planetData)
  of PlanetDetailTab.Settings:
    renderPlanetSettingsTab(contentArea, buf, planetData)

proc renderFleetDetailFromPS*(
  area: Rect,
  buf: var CellBuffer,
  model: TuiModel,
  ps: PlayerState
) =
  ## Render fleet detail using PlayerState-only data
  if model.ui.selectedFleetId <= 0:
    discard buf.setString(
      area.x, area.y, "No fleet selected", dimStyle()
    )
    return

  # Convert engine data to display data using PS adapter
  let fleetData = fleetToDetailDataFromPS(ps, FleetId(model.ui.selectedFleetId))

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
      tableColumn("State", 9, table.Alignment.Left),
      tableColumn("Attack", 7, table.Alignment.Right),
      tableColumn("Defense", 7, table.Alignment.Right)
    ])

    # Add ship rows
    let stateColumn = 2
    let crippledStyle = CellStyle(fg: color(PrestigeColor), attrs: {})
    for ship in fleetData.ships:
      let stateStyle = if ship.isCrippled: crippledStyle else: positiveStyle()
      shipTable.addRow(@[
        ship.name,
        ship.class,
        ship.state,
        ship.attack,
        ship.defense
      ], stateStyle, stateColumn)

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
  let focusLabel = reportPaneLabel(model.ui.reportFocus)

  let filterLabel = reportCategoryLabel(model.ui.reportFilter)
  let filterKey = reportCategoryKey(model.ui.reportFilter)
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

  let turnTitle = if model.ui.reportFocus == ReportPaneFocus.TurnList:
                    "TURNS *"
                  else:
                    "TURNS"
  let subjectTitle = if model.ui.reportFocus == ReportPaneFocus.SubjectList:
                       "SUBJECTS *"
                     else:
                       "SUBJECTS"
  let bodyTitle = if model.ui.reportFocus == ReportPaneFocus.BodyPane:
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

  let buckets = reportsByTurnCached(model)
  var y = turnInner.y
  let turnCount = buckets.len
  var turnScroll = model.ui.reportTurnScroll
  turnScroll.contentLength = turnCount
  turnScroll.viewportLength = turnInner.height
  turnScroll.clampOffsets()
  let turnStart = turnScroll.verticalOffset
  let turnEnd = min(turnCount, turnStart + turnInner.height)
  for idx in turnStart ..< turnEnd:
    if y >= turnInner.bottom:
      break
    let bucket = buckets[idx]
    let isSelected = idx == model.ui.reportTurnIdx
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
  let reports = currentTurnReportsFromBuckets(model, buckets)
  var subjectScroll = model.ui.reportSubjectScroll
  subjectScroll.contentLength = reports.len
  subjectScroll.viewportLength = subjectInner.height
  subjectScroll.clampOffsets()
  let subjectStart = subjectScroll.verticalOffset
  let subjectEnd = min(reports.len, subjectStart + subjectInner.height)
  for idx in subjectStart ..< subjectEnd:
    if subjectY >= subjectInner.bottom:
      break
    let report = reports[idx]
    let isSelected = idx == model.ui.reportSubjectIdx
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
    var bodyScroll = model.ui.reportBodyScroll
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
    contentLength: model.ui.reportBodyScroll.contentLength,
    position: model.ui.reportBodyScroll.verticalOffset,
    viewportLength: model.ui.reportBodyScroll.viewportLength
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
  var detailScroll = model.ui.reportBodyScroll
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

# =============================================================================
# Modal Wrappers for Primary Views
# =============================================================================

proc renderPlanetsModal*(canvas: Rect, buf: var CellBuffer,
                         model: TuiModel, scroll: ScrollState) =
  ## Render planets view as centered floating modal
  let vm = newViewModal("PLANETS").maxWidth(120).minWidth(100)
  let contentHeight = model.view.planetsRows.len + 3
  let modalArea = vm.calculateViewArea(canvas, contentHeight)
  vm.render(modalArea, buf)
  let innerArea = vm.innerArea(modalArea)

  # Create local copy for scroll calculations
  var localScroll = scroll
  localScroll.contentLength = model.view.planetsRows.len
  localScroll.viewportLength = innerArea.height - 2
  localScroll.clampOffsets()

  renderPlanetsTable(innerArea, buf, model, localScroll)

proc renderFleetsModal*(canvas: Rect, buf: var CellBuffer,
                        model: TuiModel, scroll: ScrollState) =
  ## Render fleets view as centered floating modal
  let vm = newViewModal("YOUR FLEETS").maxWidth(120).minWidth(80)
  let contentHeight = max(10, model.view.fleets.len + 4)
  let modalArea = vm.calculateViewArea(canvas, contentHeight)
  vm.render(modalArea, buf)
  let innerArea = vm.innerArea(modalArea)
  renderFleetList(innerArea, buf, model)

proc renderResearchModal*(canvas: Rect, buf: var CellBuffer,
                          model: TuiModel, scroll: ScrollState) =
  ## Render research view as centered floating modal
  let vm = newViewModal("RESEARCH PROGRESS").maxWidth(120).minWidth(80)
  let contentHeight = 15
  let modalArea = vm.calculateViewArea(canvas, contentHeight)
  vm.render(modalArea, buf)
  let innerArea = vm.innerArea(modalArea)
  discard buf.setString(innerArea.x, innerArea.y,
    "Research view (TODO)", dimStyle())

proc renderEspionageModal*(canvas: Rect, buf: var CellBuffer,
                           model: TuiModel, scroll: ScrollState) =
  ## Render espionage view as centered floating modal
  let vm = newViewModal("INTEL OPERATIONS").maxWidth(120).minWidth(80)
  let contentHeight = 12
  let modalArea = vm.calculateViewArea(canvas, contentHeight)
  vm.render(modalArea, buf)
  let innerArea = vm.innerArea(modalArea)
  discard buf.setString(innerArea.x, innerArea.y,
    "Espionage view (TODO)", dimStyle())

proc renderEconomyModal*(canvas: Rect, buf: var CellBuffer,
                         model: TuiModel, scroll: ScrollState) =
  ## Render economy view as centered floating modal
  let vm = newViewModal("TREASURY & INCOME").maxWidth(120).minWidth(80)
  let contentHeight = 12
  let modalArea = vm.calculateViewArea(canvas, contentHeight)
  vm.render(modalArea, buf)
  let innerArea = vm.innerArea(modalArea)
  discard buf.setString(innerArea.x, innerArea.y,
    "Economy view (TODO)", dimStyle())

proc renderReportsModal*(canvas: Rect, buf: var CellBuffer,
                         model: TuiModel, scroll: ScrollState) =
  ## Render reports view as centered floating modal
  let vm = newViewModal("REPORTS INBOX").maxWidth(120).minWidth(80)
  # Reports view height is dynamic based on content
  let contentHeight = max(15, 20)  # Use scrolling for long lists
  let modalArea = vm.calculateViewArea(canvas, contentHeight)
  vm.render(modalArea, buf)
  let innerArea = vm.innerArea(modalArea)
  renderReportsList(innerArea, buf, model)

proc renderMessagesModal*(canvas: Rect, buf: var CellBuffer,
                          model: TuiModel, scroll: ScrollState) =
  ## Render messages view as centered floating modal
  let vm = newViewModal("DIPLOMATIC MESSAGES").maxWidth(120).minWidth(80)
  let contentHeight = 12
  let modalArea = vm.calculateViewArea(canvas, contentHeight)
  vm.render(modalArea, buf)
  let innerArea = vm.innerArea(modalArea)
  discard buf.setString(innerArea.x, innerArea.y,
    "Messages view (TODO)", dimStyle())

proc renderSettingsModal*(canvas: Rect, buf: var CellBuffer,
                          model: TuiModel, scroll: ScrollState) =
  ## Render settings view as centered floating modal
  let vm = newViewModal("GAME SETTINGS").maxWidth(120).minWidth(80)
  let contentHeight = 10
  let modalArea = vm.calculateViewArea(canvas, contentHeight)
  vm.render(modalArea, buf)
  let innerArea = vm.innerArea(modalArea)
  discard buf.setString(innerArea.x, innerArea.y,
    "Settings view (TODO)", dimStyle())

proc renderPlanetDetailModal*(canvas: Rect, buf: var CellBuffer,
                               model: TuiModel, ps: PlayerState) =
  ## Render planet detail view as centered floating modal
  if model.ui.selectedColonyId <= 0:
    return

  # Get colony data for title
  let planetData = colonyToDetailDataFromPS(ps, ColonyId(model.ui.selectedColonyId))
  let title = "COLONY: " & planetData.systemName.toUpperAscii()

  let vm = newViewModal(title).maxWidth(120).minWidth(100)
  let contentHeight = 25  # Enough for tabs + content
  let modalArea = vm.calculateViewArea(canvas, contentHeight)
  vm.render(modalArea, buf)
  let innerArea = vm.innerArea(modalArea)

  # Render planet detail inside the modal
  renderPlanetDetailFromPS(innerArea, buf, model, ps)

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
      "[1-9] Switch views  [Ctrl-Q] Quit  [J] Join", dimStyle())
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
    houseName: model.view.houseName,
    turn: model.view.turn,
    prestige: model.view.prestige,
    prestigeRank: model.view.prestigeRank,
    totalHouses: model.view.totalHouses,
    treasury: model.view.treasury,
    production: model.view.production,
    commandUsed: model.view.commandUsed,
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
  if model.ui.breadcrumbs.len == 1 and
      model.ui.breadcrumbs[0].label == "Home":
    result.add("Home", 1)
    result.add(model.ui.mode.viewModeLabel, int(model.ui.mode))
  else:
    for item in model.ui.breadcrumbs:
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
  result.setActiveView(activeViewKey(model.ui.mode))
  result.expertModeActive = model.ui.expertModeActive
  result.expertModeInput = model.ui.expertModeInput
  result.showQuit = true
  if model.ui.expertModeFeedback.len > 0:
    result.feedback = model.ui.expertModeFeedback
  else:
    result.feedback = model.ui.statusMessage

  # Order entry mode has special context actions
  if model.ui.orderEntryActive:
    result.contextActions = orderEntryContextActions(
      model.ui.orderEntryCommandType
    )
    return

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
      renderFleetsModal(canvasArea, buf, model, model.ui.fleetsScroll)
    of ViewMode.Research:
      renderResearchModal(canvasArea, buf, model, model.ui.researchScroll)
    of ViewMode.Espionage:
      renderEspionageModal(canvasArea, buf, model, model.ui.espionageScroll)
    of ViewMode.Economy:
      renderEconomyModal(canvasArea, buf, model, model.ui.economyScroll)
    of ViewMode.Reports:
      renderReportsModal(canvasArea, buf, model, model.ui.reportTurnScroll)
    of ViewMode.Messages:
      renderMessagesModal(canvasArea, buf, model, model.ui.messagesScroll)
    of ViewMode.Settings:
      renderSettingsModal(canvasArea, buf, model, model.ui.settingsScroll)
    of ViewMode.PlanetDetail:
      renderPlanetDetailModal(canvasArea, buf, model, playerState)
    of ViewMode.FleetDetail:
      renderFleetDetailFromPS(canvasArea, buf, model, playerState)
    of ViewMode.ReportDetail:
      renderReportDetail(canvasArea, buf, model)

  # Render build modal if active
  if model.ui.buildModal.active:
    let buildModalWidget = newBuildModalWidget()
    buildModalWidget.render(model.ui.buildModal, canvasArea, buf)

  if model.ui.expertModeActive:
    renderExpertPalette(buf, canvasArea, statusBarArea, model)

  # Render Zellij-style status bar (1 line)
  if model.ui.appPhase == AppPhase.InGame:
    let statusBarData = buildStatusBarData(model, statusBarArea.width)
    renderStatusBar(statusBarArea, buf, statusBarData)

  if model.ui.quitConfirmationActive:
    renderQuitConfirmation(buf, model)
