## EC4X TUI Player - SAM Pattern Implementation
##
## Main entry point for the TUI player client using the SAM pattern.
## This replaces the original event-driven approach with a proper
## State-Action-Model architecture.
##
## SAM Flow:
##   Input Event -> Action -> Proposal -> Present -> Acceptors -> 
##   Reactors -> NAPs -> Render
##
import std/[options, strformat, tables, strutils, unicode,
  parseopt, os, algorithm, asyncdispatch]
import ../common/logger
import
  ../engine/types/[core, colony, fleet,
    player_state as ps_types, diplomacy]
import ../engine/state/[engine, iterators]
import ../engine/systems/capacity/c2_pool
import ../daemon/transport/nostr/[client, types, events, nip19, wire]
import ./tui/term/term
import ./tui/buffer
import ./tui/events
import ./tui/input
import ./tui/tty
import ./tui/signals
import ./tui/layout/layout_pkg
import ./tui/widget/[widget_pkg, frame, paragraph]
import ./tui/widget/hexmap/hexmap_pkg
import ./tui/adapters
import ./tui/widget/overview
import ./tui/widget/[hud, breadcrumb, command_dock, scrollbar]
import ./tui/launcher
import ./sam/sam_pkg
import ./state/join_flow
import ./state/lobby_profile
import ./state/order_builder
import ./svg/svg_pkg

# =============================================================================
# Bridge: Convert Engine Data to SAM Model
# =============================================================================

proc syncGameStateToModel(
    model: var TuiModel, state: GameState, viewingHouse: HouseId
) =
  ## Sync game state into the SAM TuiModel
  let house = state.house(viewingHouse).get()

  model.turn = state.turn
  model.viewingHouse = int(viewingHouse)
  model.houseName = house.name
  model.treasury = house.treasury.int
  model.prestige = house.prestige.int
  model.alertCount = 0
  model.unreadReports = 0
  model.unreadMessages = 0

  # Production (from last income report if available)
  if house.latestIncomeReport.isSome:
    model.production = house.latestIncomeReport.get().totalNet.int
  else:
    model.production = 0

  # Command capacity (C2 pool)
  let c2Analysis = analyzeC2Capacity(state, viewingHouse)
  model.commandUsed = c2Analysis.totalFleetCC.int
  model.commandMax = c2Analysis.c2Pool.int

  # Prestige rank and total houses
  var prestigeList: seq[tuple[id: HouseId, prestige: int32]] = @[]
  for otherHouse in state.allHouses():
    prestigeList.add((id: otherHouse.id, prestige: otherHouse.prestige))
  prestigeList.sort(
    proc(a, b: tuple[id: HouseId, prestige: int32]): int =
      result = cmp(b.prestige, a.prestige)
      if result == 0:
        result = cmp(int(a.id), int(b.id))
  )
  model.totalHouses = prestigeList.len
  model.prestigeRank = 0
  for i, entry in prestigeList:
    if entry.id == viewingHouse:
      model.prestigeRank = i + 1
      break

  # Build systems table from fog-of-war map data
  let mapData = toFogOfWarMapData(state, viewingHouse)
  model.systems.clear()
  model.maxRing = mapData.maxRing

  for coord, sysInfo in mapData.systems.pairs:
    let samSys = sam_pkg.SystemInfo(
      id: sysInfo.id,
      name: sysInfo.name,
      coords: (coord.q, coord.r),
      ring: sysInfo.ring,
      planetClass: sysInfo.planetClass,
      resourceRating: sysInfo.resourceRating,
      owner: sysInfo.owner,
      isHomeworld: sysInfo.isHomeworld,
      isHub: sysInfo.isHub,
      fleetCount: sysInfo.fleetCount,
    )
    model.systems[(coord.q, coord.r)] = samSys

    # Track homeworld
    if sysInfo.isHomeworld and sysInfo.owner.isSome and
        sysInfo.owner.get == int(viewingHouse):
      model.homeworld = some((coord.q, coord.r))

  # Build colonies list
  model.colonies = @[]
  for colony in state.coloniesOwned(viewingHouse):
    let sysOpt = state.system(colony.systemId)
    let sysName =
      if sysOpt.isSome:
        sysOpt.get().name
      else:
        "???"
    model.colonies.add(
      sam_pkg.ColonyInfo(
        systemId: int(colony.systemId),
        systemName: sysName,
        population: colony.population.int,
        production: colony.production.int,
        owner: int(viewingHouse),
      )
    )

  # Build fleets list
  model.fleets = @[]
  for fleet in state.fleetsOwned(viewingHouse):
    let sysOpt = state.system(fleet.location)
    let locName =
      if sysOpt.isSome:
        sysOpt.get().name
      else:
        "???"
    let cmdType = int(fleet.command.commandType)
    model.fleets.add(
      sam_pkg.FleetInfo(
        id: int(fleet.id),
        location: int(fleet.location),
        locationName: locName,
        shipCount: fleet.ships.len,
        owner: int(viewingHouse),
        command: cmdType,
        commandLabel: sam_pkg.commandLabel(cmdType),
        isIdle: fleet.command.commandType == FleetCommandType.Hold,
      )
    )

proc syncPlayerStateToOverview(
    ps: ps_types.PlayerState, state: GameState
): OverviewData =
  ## Convert PlayerState to Overview widget data
  result = initOverviewData()

  # === Leaderboard (from public information) ===
  for houseId, prestige in ps.housePrestige.pairs:
    let houseOpt = state.house(houseId)
    if houseOpt.isNone:
      continue
    let house = houseOpt.get()

    # Determine diplomatic status
    var status = DiplomaticStatus.Neutral
    if houseId == ps.viewingHouse:
      status = DiplomaticStatus.Self
    elif houseId in ps.eliminatedHouses:
      status = DiplomaticStatus.Eliminated
    else:
      # Check diplomatic relations
      let key = (ps.viewingHouse, houseId)
      if ps.diplomaticRelations.hasKey(key):
        let dipState = ps.diplomaticRelations[key]
        case dipState
        of DiplomaticState.Enemy:
          status = DiplomaticStatus.Enemy
        of DiplomaticState.Hostile:
          status = DiplomaticStatus.Hostile
        of DiplomaticState.Neutral:
          status = DiplomaticStatus.Neutral

    result.leaderboard.addEntry(
      houseId = int(houseId),
      name = house.name,
      prestige = prestige.int,
      colonies = ps.houseColonyCounts.getOrDefault(houseId, 0).int,
      status = status,
      isPlayer = (houseId == ps.viewingHouse),
    )

  result.leaderboard.sortAndRank()
  result.leaderboard.totalSystems = state.systemsCount().int

  # Calculate total colonized systems
  result.leaderboard.colonizedSystems = state.coloniesCount().int

  # === Empire Status ===
  result.empireStatus.coloniesOwned = ps.ownColonies.len

  # Get house data for tax rate
  let houseOpt = state.house(ps.viewingHouse)
  if houseOpt.isSome:
    result.empireStatus.taxRate = houseOpt.get().taxPolicy.currentRate.int

  # Fleet counts by status
  for fleet in ps.ownFleets:
    case fleet.status
    of FleetStatus.Active: result.empireStatus.fleetsActive.inc
    of FleetStatus.Reserve: result.empireStatus.fleetsReserve.inc
    of FleetStatus.Mothballed: result.empireStatus.fleetsMothballed.inc

  # Intel - count known vs fogged systems
  for systemId, visSys in ps.visibleSystems.pairs:
    case visSys.visibility
    of VisibilityLevel.None: result.empireStatus.foggedSystems.inc
    else: result.empireStatus.knownSystems.inc

  # Diplomacy counts
  for (pair, dipState) in ps.diplomaticRelations.pairs:
    if pair[0] != ps.viewingHouse:
      continue
    case dipState
    of DiplomaticState.Neutral: result.empireStatus.neutralHouses.inc
    of DiplomaticState.Hostile: result.empireStatus.hostileHouses.inc
    of DiplomaticState.Enemy: result.empireStatus.enemyHouses.inc

  # === Action Queue - detect idle fleets ===
  var idleFleets: seq[Fleet] = @[]
  for fleet in ps.ownFleets:
    if fleet.command.commandType == FleetCommandType.Hold and
       fleet.status == FleetStatus.Active:
      idleFleets.add(fleet)
      result.actionQueue.addChecklistItem(
        description = "Fleet #" & $fleet.id.int & " awaiting orders",
        isDone = false,
        priority = ActionPriority.Warning,
      )

  if idleFleets.len > 0:
    result.actionQueue.addAction(
      description = $idleFleets.len & " fleet(s) awaiting orders",
      priority = ActionPriority.Warning,
      jumpView = 3,
      jumpLabel = "3",
    )

  # Placeholder recent events
  if result.recentEvents.len == 0:
    result.addEvent(ps.turn, "No recent events", false)

# =============================================================================
# Input Mapping: Key Events to SAM Actions
# =============================================================================

proc mapKeyEvent(event: KeyEvent, model: TuiModel): Option[Proposal] =
  ## Map raw key events to SAM actions

  # Map key to KeyCode
  var keyCode = KeyCode.KeyNone

  case event.key
  of Key.Rune:
    if model.expertModeActive:
      if event.rune.int >= 0x20:
        return some(actionExpertInputAppend($event.rune))
      return none(Proposal)
    # Entry modal import mode: append characters to nsec buffer
    if model.appPhase == AppPhase.Lobby and
        model.entryModal.mode == EntryModalMode.ImportNsec:
      if event.rune.int >= 0x20:
        return some(actionEntryImportAppend($event.rune))
      return none(Proposal)
    # Entry modal invite code input: append characters
    if model.appPhase == AppPhase.Lobby and
        model.entryModal.mode == EntryModalMode.Normal and
        model.entryModal.focus == EntryModalFocus.InviteCode:
      if event.rune.int >= 0x20:
        return some(actionEntryInviteAppend($event.rune))
      return none(Proposal)
    # Lobby input mode: append characters to pubkey/name
    if model.appPhase == AppPhase.Lobby and
        model.lobbyInputMode != LobbyInputMode.None:
      if event.rune.int >= 0x20:
        return some(actionLobbyInputAppend($event.rune))
      return none(Proposal)
    let ch = $event.rune
    case ch
    of "1":
      keyCode = KeyCode.Key1
    of "2":
      keyCode = KeyCode.Key2
    of "3":
      keyCode = KeyCode.Key3
    of "4":
      keyCode = KeyCode.Key4
    of "5":
      keyCode = KeyCode.Key5
    of "6":
      keyCode = KeyCode.Key6
    of "7":
      keyCode = KeyCode.Key7
    of "8":
      keyCode = KeyCode.Key8
    of "9":
      keyCode = KeyCode.Key9
    of "q", "Q":
      keyCode = KeyCode.KeyQ
    of "c", "C":
      keyCode = KeyCode.KeyC
    of "f", "F":
      keyCode = KeyCode.KeyF
    of "o", "O":
      keyCode = KeyCode.KeyO
    of "m", "M":
      keyCode = KeyCode.KeyM
    of "e", "E":
      keyCode = KeyCode.KeyE
    of "h", "H":
      keyCode = KeyCode.KeyH
    of "x", "X":
      keyCode = KeyCode.KeyX
    of "s", "S":
      keyCode = KeyCode.KeyS
    of "l", "L":
      keyCode = KeyCode.KeyL
    of "b", "B":
      keyCode = KeyCode.KeyB
    of "g", "G":
      keyCode = KeyCode.KeyG
    of "r", "R":
      keyCode = KeyCode.KeyR
    of "j", "J":
      keyCode = KeyCode.KeyJ
    of "d", "D":
      keyCode = KeyCode.KeyD
    of "p", "P":
      keyCode = KeyCode.KeyP
    of "v", "V":
      keyCode = KeyCode.KeyV
    of "n", "N":
      keyCode = KeyCode.KeyN
    of "w", "W":
      keyCode = KeyCode.KeyW
    of "i", "I":
      keyCode = KeyCode.KeyI
    of "t", "T":
      keyCode = KeyCode.KeyT
    of "a", "A":
      keyCode = KeyCode.KeyA
    of "y", "Y":
      keyCode = KeyCode.KeyY
    of "u", "U":
      keyCode = KeyCode.KeyU
    of ":":
      keyCode = KeyCode.KeyColon
    else:
      discard
  of Key.Up:
    keyCode = KeyCode.KeyUp
  of Key.Down:
    keyCode = KeyCode.KeyDown
  of Key.Left:
    keyCode = KeyCode.KeyLeft
  of Key.Right:
    keyCode = KeyCode.KeyRight
  of Key.Enter:
    keyCode = KeyCode.KeyEnter
  of Key.Escape:
    keyCode = KeyCode.KeyEscape
  of Key.Tab:
    if (event.modifiers and ModShift) != ModNone:
      keyCode = KeyCode.KeyShiftTab
    else:
      keyCode = KeyCode.KeyTab
  of Key.CtrlL:
    keyCode = KeyCode.KeyCtrlL
  of Key.Home:
    keyCode = KeyCode.KeyHome
  of Key.Backspace:
    keyCode = KeyCode.KeyBackspace
  else:
    discard

  # Use SAM action mapper
  mapKeyToAction(keyCode, model)

# =============================================================================
# Styles
# =============================================================================

const MenuWidth = 16 ## Fixed width for menu panel

proc dimStyle(): CellStyle =
  canvasDimStyle()

proc normalStyle(): CellStyle =
  canvasStyle()

proc highlightStyle(): CellStyle =
  selectedStyle()

proc headerStyle(): CellStyle =
  canvasHeaderStyle()


# =============================================================================
# Rendering (View Functions)
# =============================================================================

proc renderStatusBar(area: Rect, buf: var CellBuffer, model: TuiModel) =
  ## Render bottom status bar from SAM model
  var x = area.x + 1
  let y = area.y

  # Turn
  discard buf.setString(x, y, "Turn: ", dimStyle())
  x += 6
  discard buf.setString(x, y, $model.turn, highlightStyle())
  x += ($model.turn).len + 3

  # Treasury
  discard buf.setString(x, y, "Treasury: ", dimStyle())
  x += 10
  discard buf.setString(x, y, $model.treasury & " MCr", highlightStyle())
  x += ($model.treasury).len + 7

  # Prestige
  discard buf.setString(x, y, "Prestige: ", dimStyle())
  x += 10
  discard buf.setString(x, y, $model.prestige, highlightStyle())
  x += ($model.prestige).len + 3

  # Current mode
  let modeStr =
    case model.mode
    of ViewMode.Overview: "[OVERVIEW]"
    of ViewMode.Planets: "[PLANETS]"
    of ViewMode.Fleets: "[FLEETS]"
    of ViewMode.Research: "[RESEARCH]"
    of ViewMode.Espionage: "[ESPIONAGE]"
    of ViewMode.Economy: "[ECONOMY]"
    of ViewMode.Reports: "[REPORTS]"
    of ViewMode.Messages: "[MESSAGES]"
    of ViewMode.Settings: "[SETTINGS]"
    of ViewMode.PlanetDetail: "[PLANET]"
    of ViewMode.FleetDetail: "[FLEET]"
    of ViewMode.ReportDetail: "[REPORT]"
  discard buf.setString(x, y, modeStr, headerStyle())

  # House name (right-aligned)
  let nameX = area.x + area.width - model.houseName.len - 2
  discard buf.setString(nameX, y, model.houseName, highlightStyle())

proc renderMenuPanel(area: Rect, buf: var CellBuffer, model: TuiModel) =
  ## Render the menu shortcuts panel
  let frame = bordered().title("Menu").borderType(BorderType.Rounded)
  frame.render(area, buf)
  let inner = frame.inner(area)

  var y = inner.y

  let items = [
    (key: "C", label: "Colonies", mode: ViewMode.Planets),
    (key: "F", label: "Fleets", mode: ViewMode.Fleets),
    (key: "O", label: "Orders", mode: ViewMode.Fleets),
    (key: "M", label: "Map", mode: ViewMode.Overview),
    (key: "L", label: "Systems", mode: ViewMode.Overview),
  ]

  # Note: Map mode will show coordinate info, not render the starmap
  # Use external SVG export for visual starmap reference

  for item in items:
    if y >= inner.bottom:
      break

    let isActive = model.mode == item.mode
    let style =
      if isActive:
        selectedStyle()
      else:
        normalStyle()
    let keyStyle =
      if isActive:
        selectedStyle()
      else:
        highlightStyle()

    discard buf.setString(inner.x, y, "[", dimStyle())
    discard buf.setString(inner.x + 1, y, item.key, keyStyle)
    discard buf.setString(inner.x + 2, y, "] ", dimStyle())
    discard buf.setString(inner.x + 4, y, item.label, style)
    y += 1

  y += 1
  if y < inner.bottom:
    discard buf.setString(inner.x, y, "[", dimStyle())
    discard buf.setString(inner.x + 1, y, "E", highlightStyle())
    discard buf.setString(inner.x + 2, y, "] ", dimStyle())
    discard buf.setString(inner.x + 4, y, "End Turn", normalStyle())
    y += 1

  if y < inner.bottom:
    discard buf.setString(inner.x, y, "[", dimStyle())
    discard buf.setString(inner.x + 1, y, "Q", highlightStyle())
    discard buf.setString(inner.x + 2, y, "] ", dimStyle())
    discard buf.setString(inner.x + 4, y, "Quit", normalStyle())

proc renderContextPanel(
    area: Rect,
    buf: var CellBuffer,
    model: TuiModel,
    state: GameState,
    viewingHouse: HouseId,
) =
  ## Render context-sensitive detail panel
  let title =
    case model.mode
    of ViewMode.Overview: "Overview Details"
    of ViewMode.Planets: "Colony Details"
    of ViewMode.Fleets: "Fleet Details"
    of ViewMode.Research: "Research Details"
    of ViewMode.Espionage: "Intel Details"
    of ViewMode.Economy: "Economy Details"
    of ViewMode.Reports: "Report Details"
    of ViewMode.Messages: "Message Details"
    of ViewMode.Settings: "Settings"
    of ViewMode.PlanetDetail: "Planet Details"
    of ViewMode.FleetDetail: "Fleet Details"
    of ViewMode.ReportDetail: "Report Content"

  let frame = bordered().title(title).borderType(BorderType.Rounded)
  frame.render(area, buf)
  let inner = frame.inner(area)

  # Get detail data using existing adapters
  let detailData = toFogOfWarDetailPanelData(
    coords.hexCoord(model.mapState.cursor.q, model.mapState.cursor.r),
    state,
    viewingHouse,
  )

  # Use existing detail renderer
  let colors = defaultColors()
  renderDetailPanel(inner, buf, detailData, colors)

proc renderColonyList(area: Rect, buf: var CellBuffer, model: TuiModel) =
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

proc renderFleetList(area: Rect, buf: var CellBuffer, model: TuiModel) =
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

proc reportCategoryGlyph(category: ReportCategory): string =
  ## Glyph for report category
  case category
  of ReportCategory.Combat: "⚔"
  of ReportCategory.Intelligence: "✦"
  of ReportCategory.Economy: "¤"
  of ReportCategory.Diplomacy: "●"
  of ReportCategory.Operations: "✚"
  of ReportCategory.Summary: "★"
  of ReportCategory.Other: "■"

proc reportCategoryStyle(category: ReportCategory): CellStyle =
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

proc renderReportsList(area: Rect, buf: var CellBuffer, model: TuiModel) =
  ## Render the reports inbox list
  if area.height < 5 or area.width < 40:
    return

  let headerStyle = canvasHeaderStyle()
  let dimStyle = canvasDimStyle()
  let normalStyle = canvasStyle()
  let highlightStyle = selectedStyle()
  let focusLabel = reportPaneLabel(model.reportFocus)

  let filterLabel = reportCategoryLabel(model.reportFilter)
  let filterKey = reportCategoryKey(model.reportFilter)
  let filterLine = "Filter [Tab]: " & filterLabel & " [" & $filterKey & "]"
  discard buf.setString(area.x, area.y, filterLine, headerStyle)

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
    let rowStyle = if isSelected: highlightStyle else: normalStyle
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
    let rowStyle = if isSelected: highlightStyle else: normalStyle
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

proc renderReportDetail(area: Rect, buf: var CellBuffer, model: TuiModel) =
  ## Render full-screen report detail view
  if area.height < 6 or area.width < 30:
    return

  let reportOpt = model.selectedReport()
  if reportOpt.isNone:
    discard buf.setString(area.x, area.y, "No report selected", dimStyle())
    return

  let report = reportOpt.get()
  let headerStyle = canvasHeaderStyle()
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

proc renderLobbyPanel(area: Rect, buf: var CellBuffer, model: TuiModel) =
  let frame = bordered().title("Lobby").borderType(BorderType.Rounded)
  frame.render(area, buf)
  let inner = frame.inner(area)

  if inner.width < 30 or inner.height < 10:
    discard buf.setString(inner.x, inner.y, "Terminal too small", dimStyle())
    return

  let columns = horizontal()
    .constraints(length(inner.width div 3), length(inner.width div 3), fill())
    .split(inner)

  if columns.len < 3:
    discard buf.setString(inner.x, inner.y, "Layout error", dimStyle())
    return

  let profileArea = columns[0]
  let activeArea = columns[1]
  let joinArea = columns[2]

  let profileFrame = bordered().title("PROFILE").borderType(BorderType.Rounded)
  let activeFrame = bordered().title("ACTIVE GAMES").borderType(BorderType.Rounded)
  let joinFrame = bordered().title("JOIN GAME").borderType(BorderType.Rounded)

  profileFrame.render(profileArea, buf)
  activeFrame.render(activeArea, buf)
  joinFrame.render(joinArea, buf)

  let profileInner = profileFrame.inner(profileArea)
  let activeInner = activeFrame.inner(activeArea)
  let joinInner = joinFrame.inner(joinArea)

  let headerStyle = canvasHeaderStyle()
  let dimStyle = canvasDimStyle()
  let normalStyle = canvasStyle()
  let highlightStyle = selectedStyle()

  var y = profileInner.y
  discard buf.setString(profileInner.x, y, "Nostr Pubkey:", headerStyle)
  y += 1
  let pubkeyLine = if model.lobbyProfilePubkey.len > 0:
                     model.lobbyProfilePubkey
                   else:
                     "(none)"
  discard buf.setString(profileInner.x, y, pubkeyLine, normalStyle)
  y += 2
  discard buf.setString(profileInner.x, y, "Player Name:", headerStyle)
  y += 1
  let nameLine = if model.lobbyProfileName.len > 0:
                   model.lobbyProfileName
                 else:
                   "(optional)"
  discard buf.setString(profileInner.x, y, nameLine, normalStyle)
  y += 2
  if model.lobbySessionKeyActive:
    discard buf.setString(profileInner.x, y, "Session-only key active",
      alertStyle())
    y += 1
  if model.lobbyWarning.len > 0:
    discard buf.setString(profileInner.x, y, model.lobbyWarning, dimStyle)

  var ay = activeInner.y
  if model.lobbyActiveGames.len == 0:
    discard buf.setString(activeInner.x, ay, "No active games", dimStyle)
  else:
    for idx, game in model.lobbyActiveGames:
      if ay >= activeInner.bottom:
        break
      let marker = if idx == model.lobbySelectedIdx: ">" else: " "
      let lineText = marker & " " & game.name & " T" & $game.turn
      let style = if idx == model.lobbySelectedIdx: highlightStyle
                  else: normalStyle
      discard buf.setString(activeInner.x, ay, lineText, style)
      ay += 1
    if ay < activeInner.bottom:
      discard buf.setString(activeInner.x, ay, "Enter: Open game", dimStyle)

  var jy = joinInner.y
  if model.lobbyJoinStatus == JoinStatus.SelectingGame:
    for idx, game in model.lobbyJoinGames:
      if jy >= joinInner.bottom:
        break
      let marker = if idx == model.lobbyJoinSelectedIdx: ">" else: " "
      let count = $game.assignedCount & "/" & $game.playerCount
      let lineText = marker & " " & game.name & " [" & count & "]"
      let style = if idx == model.lobbyJoinSelectedIdx: highlightStyle
                  else: normalStyle
      discard buf.setString(joinInner.x, jy, lineText, style)
      jy += 1
  elif model.lobbyJoinStatus == JoinStatus.EnteringPubkey:
    discard buf.setString(joinInner.x, jy, "Enter pubkey:", headerStyle)
    jy += 1
    discard buf.setString(joinInner.x, jy, model.lobbyProfilePubkey, normalStyle)
  elif model.lobbyJoinStatus == JoinStatus.EnteringName:
    discard buf.setString(joinInner.x, jy, "Enter name:", headerStyle)
    jy += 1
    discard buf.setString(joinInner.x, jy, model.lobbyProfileName, normalStyle)
    jy += 1
    discard buf.setString(joinInner.x, jy, "Enter: Submit", dimStyle)
  elif model.lobbyJoinStatus == JoinStatus.WaitingResponse:
    discard buf.setString(joinInner.x, jy, "Waiting for response...",
      dimStyle)
  elif model.lobbyJoinStatus == JoinStatus.Failed:
    discard buf.setString(joinInner.x, jy, "Join failed:", alertStyle())
    jy += 1
    discard buf.setString(joinInner.x, jy, model.lobbyJoinError, normalStyle)
  elif model.lobbyJoinStatus == JoinStatus.Joined:
    discard buf.setString(joinInner.x, jy, "Joined game!", normalStyle)
  else:
    discard buf.setString(joinInner.x, jy, "Press R to refresh", dimStyle)

  let hintLine = "Tab: Next Pane  Y: Pubkey  U: Name  G: Session Key  R: Refresh"
  discard buf.setString(inner.x, inner.bottom - 1, hintLine, dimStyle)

proc renderListPanel(
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
    discard buf.setString(inner.x, y, "STRATEGIC OVERVIEW", headerStyle())
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
    discard buf.setString(inner.x, inner.y, "Research view (TODO)", dimStyle())
  of ViewMode.Espionage:
    discard buf.setString(inner.x, inner.y, "Espionage view (TODO)", dimStyle())
  of ViewMode.Economy:
    discard buf.setString(inner.x, inner.y, "Economy view (TODO)", dimStyle())
  of ViewMode.Reports:
    renderReportsList(inner, buf, model)
  of ViewMode.Messages:
    discard buf.setString(inner.x, inner.y, "Messages view (TODO)", dimStyle())
  of ViewMode.Settings:
    discard buf.setString(inner.x, inner.y, "Settings view (TODO)", dimStyle())
  of ViewMode.PlanetDetail:
    discard buf.setString(inner.x, inner.y, "Planet detail (TODO)", dimStyle())
  of ViewMode.FleetDetail:
    discard buf.setString(inner.x, inner.y, "Fleet detail (TODO)", dimStyle())
  of ViewMode.ReportDetail:
    renderReportDetail(inner, buf, model)

proc buildHudData(model: TuiModel): HudData =
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

proc buildBreadcrumbData(model: TuiModel): BreadcrumbData =
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

proc activeViewKey(mode: ViewMode): char =
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

proc buildCommandDockData(model: TuiModel): CommandDockData =
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
    result.contextActions = orderEntryContextActions(model.orderEntryCommandType)
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

proc renderDashboard(
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

  # Render Command Dock
  let dockData = buildCommandDockData(model)
  if dockArea.width >= 100:
    renderCommandDock(dockArea, buf, dockData)
  else:
    renderCommandDockCompact(dockArea, buf, dockData)

# =============================================================================
# Output
# =============================================================================

proc outputBuffer(buf: CellBuffer) =
  ## Output buffer to terminal with proper ANSI escape sequences
  var lastStyle = defaultStyle()

  for y in 0 ..< buf.h:
    # Position cursor at start of line (1-based ANSI coordinates)
    stdout.write("\e[", y + 1, ";1H")

    for x in 0 ..< buf.w:
      let (str, style, _) = buf.get(x, y)

      # Only emit style changes when needed (optimization)
      if style != lastStyle:
        # Build ANSI SGR codes
        var codes: seq[string] = @[]

        # Reset if needed
        if style.fg.isNone and style.bg.isNone and style.attrs.len == 0:
          stdout.write("\e[0m")
        else:
          # Attributes
          if StyleAttr.Bold in style.attrs:
            codes.add("1")
          if StyleAttr.Italic in style.attrs:
            codes.add("3")
          if StyleAttr.Underline in style.attrs:
            codes.add("4")

          # Foreground color (24-bit RGB)
          if style.fg.kind == ColorKind.Rgb:
            let rgb = style.fg.rgb
            codes.add("38;2;" & $rgb.r & ";" & $rgb.g & ";" & $rgb.b)
          elif style.fg.kind == ColorKind.Ansi256:
            codes.add("38;5;" & $int(style.fg.ansi256))
          elif style.fg.kind == ColorKind.Ansi:
            codes.add("38;5;" & $int(style.fg.ansi))

          # Background color (24-bit RGB)
          if style.bg.kind == ColorKind.Rgb:
            let rgb = style.bg.rgb
            codes.add("48;2;" & $rgb.r & ";" & $rgb.g & ";" & $rgb.b)
          elif style.bg.kind == ColorKind.Ansi256:
            codes.add("48;5;" & $int(style.bg.ansi256))
          elif style.bg.kind == ColorKind.Ansi:
            codes.add("48;5;" & $int(style.bg.ansi))

          # Emit codes
          if codes.len > 0:
            stdout.write("\e[0m\e[", codes.join(";"), "m")

        lastStyle = style

      stdout.write(str)

  # Reset at end
  stdout.write("\e[0m")
  stdout.flushFile()

# =============================================================================
# Main Entry Point
# =============================================================================

proc hexToBytes32(hexStr: string): array[32, byte] =
  ## Convert hex string to 32-byte array
  if hexStr.len != 64:
    raise newException(ValueError, "Invalid hex length: expected 64, got " &
      $hexStr.len)
  for i in 0..<32:
    let hexByte = hexStr[i * 2 .. i * 2 + 1]
    result[i] = byte(parseHexInt(hexByte))

proc hexToBytes32Safe(hexStr: string): Option[array[32, byte]] =
  ## Convert hex string to bytes without raising
  try:
    some(hexToBytes32(hexStr))
  except CatchableError:
    none(array[32, byte])

proc runTui(gameId: string = "") =
  ## Main TUI execution (called from main() or from new terminal window)
  logInfo("TUI Player SAM", "Starting EC4X TUI Player with SAM pattern...")

  # Initialize game state
  var gameState = GameState()
  var playerState = ps_types.PlayerState()
  var viewingHouse = HouseId(1)
  var activeGameId = gameId
  var nostrClient: NostrClient = nil
  var nostrRelayUrl = ""

  # Initialize terminal
  var tty = openTty()
  if not tty.start():
    logError("TUI Player SAM", "Failed to enter raw mode")
    quit(1)

  setupResizeHandler()
  var (termWidth, termHeight) = tty.windowSize()
  logInfo("TUI Player SAM", &"Terminal size: {termWidth}x{termHeight}")

  var buf = initBuffer(termWidth, termHeight)

  # =========================================================================
  # SAM Setup
  # =========================================================================

  # Create SAM instance with history (for potential undo)
  var sam = initTuiSam(withHistory = true, maxHistory = 50)

  # Create initial model
  var initialModel = initTuiModel()
  initialModel.termWidth = termWidth
  initialModel.termHeight = termHeight
  initialModel.viewingHouse = int(viewingHouse)
  initialModel.mode = ViewMode.Overview

  if gameId.len > 0:
    initialModel.appPhase = AppPhase.InGame
    activeGameId = gameId
    let infoOpt = loadGameInfo("data", gameId)
    if infoOpt.isSome:
      let gameInfo = infoOpt.get()
      initialModel.turn = gameInfo.turn
      initialModel.houseName = gameInfo.name
    else:
      initialModel.statusMessage = "Game not found"

  if initialModel.lobbyProfilePubkey.len > 0:
    initialModel.lobbyActiveGames = loadActiveGamesData("data",
      initialModel.lobbyProfilePubkey)
  else:
    let profiles = loadProfiles("data")
    if profiles.len > 0:
      initialModel.lobbyProfilePubkey = profiles[0]
      let profileInfo = loadProfile("data", initialModel.lobbyProfilePubkey)
      initialModel.lobbyProfileName = profileInfo.name
      initialModel.lobbySessionKeyActive = profileInfo.session
      initialModel.lobbyActiveGames = loadActiveGamesData("data",
        initialModel.lobbyProfilePubkey)

  # Auto-load join games on lobby entry
  if initialModel.appPhase == AppPhase.Lobby:
    initialModel.lobbyJoinGames = loadJoinGames("data")
    if initialModel.lobbyJoinGames.len > 0:
      initialModel.lobbyJoinStatus = JoinStatus.SelectingGame

  if initialModel.entryModal.relayUrl().len > 0:
    initialModel.nostrRelayUrl = initialModel.entryModal.relayUrl()

  # Sync game state to model (only after joining a game)
  if initialModel.appPhase == AppPhase.InGame:
    syncGameStateToModel(initialModel, gameState, viewingHouse)
    initialModel.resetBreadcrumbs(initialModel.mode)

    if initialModel.homeworld.isSome:
      initialModel.mapState.cursor = initialModel.homeworld.get

  if initialModel.nostrRelayUrl.len > 0 and
      activeGameId.len > 0:
    try:
      let identity = initialModel.entryModal.identity
      let relayList = @[initialModel.nostrRelayUrl]
      nostrClient = newNostrClient(relayList)
      nostrClient.onEvent = proc(subId: string, event: NostrEvent) =
        let privOpt = hexToBytes32Safe(identity.nsecHex)
        let pubOpt = hexToBytes32Safe(event.pubkey)
        if privOpt.isNone or pubOpt.isNone:
          sam.model.nostrLastError = "Invalid key material"
          sam.model.nostrStatus = "error"
          sam.model.nostrEnabled = false
          sam.present(emptyProposal())
          return
        try:
          let payload = decodePayload(event.content, privOpt.get(), pubOpt.get())
          if event.kind == EventKindGameState:
            let stateOpt = parseFullStateKdl(payload)
            if stateOpt.isSome:
              playerState = stateOpt.get()
              sam.model.playerStateLoaded = true
              viewingHouse = playerState.viewingHouse
              sam.model.viewingHouse = int(viewingHouse)
              sam.model.turn = int(playerState.turn)
              sam.model.statusMessage = "Full state received"
              if sam.model.nostrEnabled:
                sam.model.nostrStatus = "connected"
          elif event.kind == EventKindTurnResults:
            let turnOpt = applyDeltaToCachedState("data",
              identity.npubHex, activeGameId, playerState, payload)
            if turnOpt.isSome:
              sam.model.turn = int(turnOpt.get())
              sam.model.playerStateLoaded = true
              sam.model.statusMessage = "Delta applied"
          sam.present(emptyProposal())
        except CatchableError as e:
          sam.model.nostrLastError = e.msg
          sam.model.nostrStatus = "error"
          sam.model.nostrEnabled = false
          sam.present(emptyProposal())
      asyncCheck nostrClient.connect()
      initialModel.nostrStatus = "connecting"
      initialModel.nostrEnabled = true
    except CatchableError as e:
      initialModel.nostrLastError = e.msg
      initialModel.nostrStatus = "error"
      initialModel.nostrEnabled = false

  # Set render function (closure captures buf and gameState)
  sam.setRender(
    proc(model: TuiModel) =
      buf.clear()
      renderDashboard(buf, model, gameState, viewingHouse, playerState)
      outputBuffer(buf)
  )

  # Set initial state (this triggers initial render)
  sam.setInitialState(initialModel)

  logInfo("TUI Player SAM", "SAM initialized, entering TUI mode...")

  # Enter alternate screen
  stdout.write(altScreen())
  stdout.write(hideCursor())
  stdout.flushFile()

  # Create input parser
  var parser = initParser()

  # Initial render
  sam.present(emptyProposal())

  # =========================================================================
  # Main Loop (SAM-based)
  # =========================================================================

  while sam.state.running:
    # Check for resize
    if checkResize():
      (termWidth, termHeight) = tty.windowSize()
      buf.resize(termWidth, termHeight)
      buf.invalidate()
      sam.present(actionResize(termWidth, termHeight))

    # Read input (blocking)
    let inputByte = tty.readByte()
    if inputByte < 0:
      continue

    let events = parser.feedByte(inputByte.uint8)

    for event in events:
      if event.kind == EventKind.Key:
        # Map key event to SAM action
        let proposalOpt = mapKeyEvent(event.keyEvent, sam.state)
        if proposalOpt.isSome:
          sam.present(proposalOpt.get)

    if sam.model.nostrEnabled and nostrClient != nil:
      if sam.model.nostrStatus == "connecting" and
          nostrClient.isConnected():
        let playerPubHex = sam.model.entryModal.identity.npubHex
        asyncCheck nostrClient.subscribeGame(activeGameId, playerPubHex)
        asyncCheck nostrClient.listen()
        sam.model.nostrStatus = "connected"
        sam.model.statusMessage = "Nostr connected"
      elif sam.model.nostrStatus == "connected" and
          not nostrClient.isConnected():
        sam.model.nostrStatus = "error"
        sam.model.nostrLastError = "Relay disconnected"
        sam.model.nostrEnabled = false

    # Poll for join response when waiting
    if sam.model.appPhase == AppPhase.Lobby and
        sam.model.lobbyJoinStatus == JoinStatus.WaitingResponse:
      sam.present(actionLobbyJoinPoll())

    if sam.model.loadGameRequested:
      let gameId = sam.model.loadGameId
      let houseId = HouseId(sam.model.loadHouseId.uint32)
      let dataDir = "data"
      let dbPath = dataDir / "games" / gameId / "ec4x.db"
      sam.model.playerStateLoaded = false
      if fileExists(dbPath):
        try:
          gameState = loadGameStateForHouse(dbPath, houseId)
          viewingHouse = houseId
          let pubkey = sam.model.lobbyProfilePubkey
          if pubkey.len > 0:
            let cachedOpt = loadCachedPlayerState(dataDir, pubkey, gameId,
              houseId)
            if cachedOpt.isSome:
              playerState = cachedOpt.get()
            else:
              playerState = loadPlayerState(gameState, houseId)
              cachePlayerState(dataDir, pubkey, gameId, playerState)
            sam.model.playerStateLoaded = true
          else:
            playerState = loadPlayerState(gameState, houseId)
            sam.model.playerStateLoaded = true
          sam.model.appPhase = AppPhase.InGame
          sam.model.viewingHouse = int(houseId)
          sam.model.mode = ViewMode.Overview
          syncGameStateToModel(sam.model, gameState, viewingHouse)
          sam.model.resetBreadcrumbs(sam.model.mode)
          sam.model.statusMessage = "Loaded game " & gameId
        except CatchableError as e:
          sam.model.statusMessage = "Load failed: " & e.msg
      else:
        sam.model.statusMessage = "Game DB not found"
      sam.model.loadGameRequested = false

      # Re-render to show status
      sam.present(emptyProposal())

    # Handle map export requests (needs GameState access)
    if sam.model.exportMapRequested:
      let gameId = "game_" & $gameState.seed # Use seed as game ID
      let svg = generateStarmap(gameState, viewingHouse)
      let path = exportSvg(svg, gameId, gameState.turn)
      sam.model.lastExportPath = path
      sam.model.statusMessage = "Exported: " & path

      if sam.model.openMapRequested:
        discard openInViewer(path)
        sam.model.statusMessage = "Opened: " & path

      sam.model.exportMapRequested = false
      sam.model.openMapRequested = false

      # Re-render to show status
      sam.present(emptyProposal())

    # Handle pending fleet orders (write to KDL files)
    if sam.model.pendingFleetOrderReady and activeGameId.len > 0:
      let gameDir = "data/games/" & activeGameId
      let orderPath = writeFleetOrderFromModel(gameDir, sam.model)
      if orderPath.len > 0:
        let cmdLabel = commandLabel(sam.model.pendingFleetOrderCommandType)
        sam.model.statusMessage = cmdLabel & " order written: " &
          extractFilename(orderPath)
        logInfo("TUI Player SAM", "Fleet order written: " & orderPath)
      sam.model.clearPendingOrder()
      
      # Re-render to show status
      sam.present(emptyProposal())

  # =========================================================================
  # Cleanup
  # =========================================================================

  stdout.write(showCursor())
  stdout.write(exitAltScreen())
  stdout.flushFile()
  discard tty.stop()
  tty.close()

  echo "TUI Player (SAM) exited."

proc parseCommandLine(): tuple[spawnWindow: bool, showHelp: bool, gameId: string] =
  ## Parse command line arguments
  result = (spawnWindow: true, showHelp: false, gameId: "")

  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdLongOption, cmdShortOption:
      case p.key
      of "no-spawn-window":
        result.spawnWindow = false
      of "spawn-window":
        result.spawnWindow =
          if p.val == "":
            true
          else:
            parseBool(p.val)
      of "game":
        result.gameId = p.val
      of "help", "h":
        result.showHelp = true
      else:
        echo "Unknown option: --", p.key
        result.showHelp = true
    of cmdArgument:
      echo "Unexpected argument: ", p.key
      result.showHelp = true

proc showHelp() =
  echo """
EC4X TUI Player

Usage: ec4x-tui [options]

Options:
  --spawn-window        Launch in new terminal window (default: true)
  --no-spawn-window     Run in current terminal
  --game <id>           Enter a game directly
  --help, -h            Show this help message

Controls:
  [1-9]    Switch views
  [Q]      Quit
  [C]      Colonies view
  [F]      Fleets view
  [M]      Map view
  [:]      Expert mode (vim-style commands)
  
See docs/tools/ec4x-play.md for full documentation.
"""

when isMainModule:
  let opts = parseCommandLine()

  if opts.showHelp:
    showHelp()
    quit(0)

  # Launcher integration: spawn new window if enabled and possible
  if opts.spawnWindow and shouldLaunchInNewWindow():
    let binary = getAppFilename()
    if launchInNewWindow(binary & " --no-spawn-window"):
      # Parent process exits, child runs TUI
      quit(0)
    else:
      # Launcher failed (no emulator found)
      echo "Warning: No terminal emulator found, running in current terminal"
      echo ""

  # Check terminal size before proceeding
  let (w, h) = getCurrentTerminalSize()
  let (ok, msg) = isTerminalSizeOk(w, h)
  if not ok:
    echo "Error: ", msg
    echo ""
    echo "Minimum terminal size: 80x24 (compact)"
    echo "Recommended size: 120x32 (full layout)"
    quit(1)
  elif "smaller than optimal" in msg:
    echo "Note: ", msg
    echo ""

  # Run TUI
  runTui(opts.gameId)
