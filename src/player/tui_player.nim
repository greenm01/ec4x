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
## Layout:
##   +- Map --------+- Context ----------------------+
##   |  (small)     | System/Fleet/Colony details   |
##   +--------------+-------------------------------+
##   | [C]olonies   | List of items based on mode   |
##   | [F]leets     |                               |
##   | [O]rders     |                               |
##   | [E]nd Turn   |                               |
##   +--------------+-------------------------------+
##   | Status bar                                   |
##   +----------------------------------------------+
##
## Run: nimble buildTui && ./bin/ec4x-tui

import std/[options, strformat, tables, strutils, unicode, parseopt, os]
import ../common/logger
import ../engine/init/game_state
import ../engine/types/[core, game_state, colony, fleet, player_state as ps_types, diplomacy]
import ../engine/state/[engine, fog_of_war, iterators, player_state]
import ./tui/term/term
import ./tui/term/types/core as termcore
import ./tui/buffer
import ./tui/events
import ./tui/input
import ./tui/tty
import ./tui/signals
import ./tui/layout/layout_pkg
import ./tui/widget/[widget_pkg, frame, paragraph]
import ./tui/widget/hexmap/hexmap_pkg
import ./tui/adapters
import ./tui/widget/system_list
import ./tui/widget/overview
import ./tui/widget/[hud, breadcrumb, command_dock]
import ./tui/launcher
import ./sam/sam_pkg
import ./svg/svg_pkg

# =============================================================================
# Bridge: Convert Engine Data to SAM Model
# =============================================================================

proc syncGameStateToModel(model: var TuiModel, state: GameState, 
                          viewingHouse: HouseId) =
  ## Sync game state into the SAM TuiModel
  let house = state.house(viewingHouse).get()
  
  model.turn = state.turn
  model.viewingHouse = int(viewingHouse)
  model.houseName = house.name
  model.treasury = house.treasury
  model.prestige = house.prestige
  
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
      fleetCount: sysInfo.fleetCount
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
    let sysName = if sysOpt.isSome: sysOpt.get().name else: "???"
    model.colonies.add(sam_pkg.ColonyInfo(
      systemId: int(colony.systemId),
      systemName: sysName,
      population: colony.population,
      production: colony.production,
      owner: int(viewingHouse)
    ))
  
  # Build fleets list
  model.fleets = @[]
  for fleet in state.fleetsOwned(viewingHouse):
    let sysOpt = state.system(fleet.location)
    let locName = if sysOpt.isSome: sysOpt.get().name else: "???"
    model.fleets.add(sam_pkg.FleetInfo(
      id: int(fleet.id),
      location: int(fleet.location),
      locationName: locName,
      shipCount: fleet.ships.len,
      owner: int(viewingHouse)
    ))

proc syncPlayerStateToOverview(ps: ps_types.PlayerState, state: GameState): OverviewData =
  ## Convert PlayerState to Overview widget data
  result = initOverviewData()
  
  # === Leaderboard (from public information) ===
  for houseId, prestige in ps.housePrestige.pairs:
    let houseOpt = state.house(houseId)
    if houseOpt.isNone: continue
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
      name = house.name,
      prestige = prestige.int,
      colonies = ps.houseColonyCounts.getOrDefault(houseId, 0).int,
      status = status,
      isPlayer = (houseId == ps.viewingHouse)
    )
  
  result.leaderboard.sortAndRank()
  result.leaderboard.totalSystems = state.systemsCount().int
  
  # Calculate total colonized systems
  var totalColonized = 0
  for count in ps.houseColonyCounts.values:
    totalColonized += count.int
  result.leaderboard.colonizedSystems = totalColonized
  
  # === Empire Status ===
  result.empireStatus.coloniesOwned = ps.ownColonies.len
  
  # Get house data for tax rate
  let houseOpt = state.house(ps.viewingHouse)
  if houseOpt.isSome:
    result.empireStatus.taxRate = houseOpt.get().taxPolicy.currentRate.int
  
  # Fleet counts by status
  for fleet in ps.ownFleets:
    case fleet.status
    of FleetStatus.Active:
      result.empireStatus.fleetsActive.inc
    of FleetStatus.Reserve:
      result.empireStatus.fleetsReserve.inc
    of FleetStatus.Mothballed:
      result.empireStatus.fleetsMothballed.inc
  
  # Intel - count known vs fogged systems
  for systemId, visSys in ps.visibleSystems.pairs:
    case visSys.visibility
    of VisibilityLevel.None:
      result.empireStatus.foggedSystems.inc
    else:
      result.empireStatus.knownSystems.inc
  
  # Diplomacy counts
  for (pair, dipState) in ps.diplomaticRelations.pairs:
    if pair[0] != ps.viewingHouse:
      continue
    case dipState
    of DiplomaticState.Neutral:
      result.empireStatus.neutralHouses.inc
    of DiplomaticState.Hostile:
      result.empireStatus.hostileHouses.inc
    of DiplomaticState.Enemy:
      result.empireStatus.enemyHouses.inc
  
  # === Action Queue - detect idle fleets ===
  var idleFleets: seq[Fleet] = @[]
  for fleet in ps.ownFleets:
    if fleet.command.commandType == FleetCommandType.Hold and 
       fleet.status == FleetStatus.Active:
      idleFleets.add(fleet)
      result.actionQueue.addChecklistItem(
        description = "Fleet #" & $fleet.id.int & " awaiting orders",
        isDone = false,
        priority = ActionPriority.Warning
      )
  
  if idleFleets.len > 0:
    result.actionQueue.addAction(
      description = $idleFleets.len & " fleet(s) awaiting orders",
      priority = ActionPriority.Warning,
      jumpView = 3,
      jumpLabel = "3"
    )

# =============================================================================
# Input Mapping: Key Events to SAM Actions
# =============================================================================

proc mapKeyEvent(event: KeyEvent, model: TuiModel): Option[Proposal] =
  ## Map raw key events to SAM actions
  
  # Map key to KeyCode
  var keyCode = KeyCode.KeyNone
  
  case event.key
  of Key.Rune:
    let ch = $event.rune
    case ch
    of "q", "Q": keyCode = KeyCode.KeyQ
    of "c", "C": keyCode = KeyCode.KeyC
    of "f", "F": keyCode = KeyCode.KeyF
    of "o", "O": keyCode = KeyCode.KeyO
    of "m", "M": keyCode = KeyCode.KeyM
    of "e", "E": keyCode = KeyCode.KeyE
    of "h", "H": keyCode = KeyCode.KeyH
    of "x", "X": keyCode = KeyCode.KeyX
    of "s", "S": keyCode = KeyCode.KeyS
    of "l", "L": keyCode = KeyCode.KeyL
    else: discard
  
  of Key.Up: keyCode = KeyCode.KeyUp
  of Key.Down: keyCode = KeyCode.KeyDown
  of Key.Left: keyCode = KeyCode.KeyLeft
  of Key.Right: keyCode = KeyCode.KeyRight
  of Key.Enter: keyCode = KeyCode.KeyEnter
  of Key.Escape: keyCode = KeyCode.KeyEscape
  of Key.Tab:
    if (event.modifiers and ModShift) != ModNone:
      keyCode = KeyCode.KeyShiftTab
    else:
      keyCode = KeyCode.KeyTab
  of Key.Home: keyCode = KeyCode.KeyHome
  else: discard
  
  # Use SAM action mapper
  mapKeyToAction(keyCode, model)

# =============================================================================
# Styles
# =============================================================================

const
  MenuWidth = 16     ## Fixed width for menu panel

proc dimStyle(): CellStyle =
  CellStyle(fg: color(Ansi256Color(245)), attrs: {})

proc normalStyle(): CellStyle =
  CellStyle(fg: color(Ansi256Color(252)), attrs: {})

proc highlightStyle(): CellStyle =
  CellStyle(fg: color(Ansi256Color(226)), attrs: {StyleAttr.Bold})

proc selectedStyle(): CellStyle =
  CellStyle(fg: color(Ansi256Color(16)), bg: color(Ansi256Color(226)), attrs: {StyleAttr.Bold})

proc headerStyle(): CellStyle =
  CellStyle(fg: color(Ansi256Color(117)), attrs: {StyleAttr.Bold})

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
  let modeStr = case model.mode
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
    let style = if isActive: selectedStyle() else: normalStyle()
    let keyStyle = if isActive: selectedStyle() else: highlightStyle()
    
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

proc renderContextPanel(area: Rect, buf: var CellBuffer, model: TuiModel,
                        state: GameState, viewingHouse: HouseId) =
  ## Render context-sensitive detail panel
  let title = case model.mode
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
    state, viewingHouse
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
    let style = if isSelected: selectedStyle() else: normalStyle()
    
    let prefix = if isSelected: "> " else: "  "
    let line = prefix & colony.systemName.alignLeft(14) & " PP:" & 
               align($colony.production, 4) & 
               " Pop:" & align($colony.population, 5)
    
    discard buf.setString(area.x, y, line[0 ..< min(line.len, area.width)], style)
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
    let style = if isSelected: selectedStyle() else: normalStyle()
    
    let prefix = if isSelected: "> " else: "  "
    let fleetName = "Fleet #" & $fleet.id
    let line = prefix & fleetName.alignLeft(12) & " @ " & 
               fleet.locationName.alignLeft(10) & " Ships:" & $fleet.shipCount
    
    discard buf.setString(area.x, y, line[0 ..< min(line.len, area.width)], style)
    y += 1
    idx += 1
  
  if idx == 0:
    discard buf.setString(area.x, y, "No fleets", dimStyle())

proc renderListPanel(area: Rect, buf: var CellBuffer, model: TuiModel,
                     state: GameState, viewingHouse: HouseId) =
  ## Render the main list panel based on current mode
  let title = case model.mode
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
    discard buf.setString(inner.x, y, "Turn: " & $model.turn, normalStyle())
    y += 1
    discard buf.setString(inner.x, y, "Colonies: " & $model.colonies.len, normalStyle())
    y += 1
    discard buf.setString(inner.x, y, "Fleets: " & $model.fleets.len, normalStyle())
    y += 2
    discard buf.setString(inner.x, y, "[1-9] Switch views  [Q] Quit", dimStyle())
  
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
    discard buf.setString(inner.x, inner.y, "Reports view (TODO)", dimStyle())
  
  of ViewMode.Messages:
    discard buf.setString(inner.x, inner.y, "Messages view (TODO)", dimStyle())
  
  of ViewMode.Settings:
    discard buf.setString(inner.x, inner.y, "Settings view (TODO)", dimStyle())
  
  of ViewMode.PlanetDetail:
    discard buf.setString(inner.x, inner.y, "Planet detail (TODO)", dimStyle())
  
  of ViewMode.FleetDetail:
    discard buf.setString(inner.x, inner.y, "Fleet detail (TODO)", dimStyle())
  
  of ViewMode.ReportDetail:
    discard buf.setString(inner.x, inner.y, "Report detail (TODO)", dimStyle())

proc renderDashboard(buf: var CellBuffer, model: TuiModel, 
                     state: GameState, viewingHouse: HouseId) =
  ## Render the complete TUI dashboard using SAM model
  let termRect = rect(0, 0, model.termWidth, model.termHeight)
  
  let mainRows = vertical()
    .constraints(fill(), length(1))
    .split(termRect)
  
  let contentArea = mainRows[0]
  let statusArea = mainRows[1]
  
  let leftWidth = MenuWidth + 2
  let mainCols = horizontal()
    .constraints(length(leftWidth), fill())
    .split(contentArea)
  
  let leftCol = mainCols[0]
  let rightCol = mainCols[1]
  
  # Left column is just menu now (no map widget)
  let menuArea = leftCol
  
  let contextHeight = max(8, contentArea.height div 3)
  let rightRows = vertical()
    .constraints(length(contextHeight), fill())
    .split(rightCol)
  
  let contextArea = rightRows[0]
  let listArea = rightRows[1]
  
  # Render panels
  renderMenuPanel(menuArea, buf, model)
  renderContextPanel(contextArea, buf, model, state, viewingHouse)
  renderListPanel(listArea, buf, model, state, viewingHouse)
  renderStatusBar(statusArea, buf, model)

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
          if style.fg.kind == termcore.ColorKind.Rgb:
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

proc runTui() =
  ## Main TUI execution (called from main() or from new terminal window)
  logInfo("TUI Player SAM", "Starting EC4X TUI Player with SAM pattern...")
  
  # Initialize game state
  logInfo("TUI Player SAM", "Creating new game...")
  var gameState = initGameState(
    setupPath = "scenarios/standard-4-player.kdl",
    gameName = "TUI Test Game",
    configDir = "config",
    dataDir = "data"
  )
  
  logInfo("TUI Player SAM", &"Game created: {gameState.housesCount()} houses, {gameState.systemsCount()} systems")
  
  let viewingHouse = HouseId(1)
  
  # Generate PlayerState (fog-of-war filtered view)
  logInfo("TUI Player SAM", "Generating PlayerState for viewing house...")
  var playerState = createPlayerState(gameState, viewingHouse)
  logInfo("TUI Player SAM", &"PlayerState created: {playerState.ownColonies.len} colonies, {playerState.ownFleets.len} fleets")
  
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
  initialModel.mode = ViewMode.Planets
  
  # Sync game state to model
  syncGameStateToModel(initialModel, gameState, viewingHouse)
  
  # Set cursor to homeworld if available
  if initialModel.homeworld.isSome:
    initialModel.mapState.cursor = initialModel.homeworld.get
  
  # Set render function (closure captures buf and gameState)
  sam.setRender(proc(model: TuiModel) =
    buf.clear()
    renderDashboard(buf, model, gameState, viewingHouse)
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
    
    # Handle map export requests (needs GameState access)
    if sam.model.exportMapRequested:
      let gameId = "game_" & $gameState.seed  # Use seed as game ID
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
  
  # =========================================================================
  # Cleanup
  # =========================================================================
  
  stdout.write(showCursor())
  stdout.write(exitAltScreen())
  stdout.flushFile()
  discard tty.stop()
  tty.close()
  
  echo "TUI Player (SAM) exited."

proc parseCommandLine(): tuple[spawnWindow: bool, showHelp: bool] =
  ## Parse command line arguments
  result = (spawnWindow: true, showHelp: false)
  
  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      case p.key
      of "no-spawn-window":
        result.spawnWindow = false
      of "spawn-window":
        result.spawnWindow = if p.val == "": true else: parseBool(p.val)
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
  runTui()
