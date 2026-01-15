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

import std/[options, strformat, tables, strutils, unicode]
import ../common/logger
import ../engine/init/game_state
import ../engine/types/[core, game_state, colony, fleet]
import ../engine/state/[engine, fog_of_war, iterators]
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
import ./sam/sam_pkg

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
  MapWidth = 24      ## Fixed width for small map panel
  MenuWidth = 16     ## Fixed width for menu panel
  MapHeight = 12     ## Fixed height for map panel

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
    of ViewMode.Map: "[MAP]"
    of ViewMode.Colonies: "[COLONIES]"
    of ViewMode.Fleets: "[FLEETS]"
    of ViewMode.Orders: "[ORDERS]"
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
    (key: "C", label: "Colonies", mode: ViewMode.Colonies),
    (key: "F", label: "Fleets", mode: ViewMode.Fleets),
    (key: "O", label: "Orders", mode: ViewMode.Orders),
    (key: "M", label: "Map", mode: ViewMode.Map),
  ]
  
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
    of ViewMode.Map: "System Info"
    of ViewMode.Colonies: "Colony Details"
    of ViewMode.Fleets: "Fleet Details"
    of ViewMode.Orders: "Order Details"
  
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

proc renderListPanel(area: Rect, buf: var CellBuffer, model: TuiModel) =
  ## Render the main list panel based on current mode
  let title = case model.mode
    of ViewMode.Colonies: "Your Colonies"
    of ViewMode.Fleets: "Your Fleets"
    of ViewMode.Orders: "Pending Orders"
    of ViewMode.Map: "Navigation"
  
  let frame = bordered().title(title).borderType(BorderType.Rounded)
  frame.render(area, buf)
  let inner = frame.inner(area)
  
  case model.mode
  of ViewMode.Colonies:
    renderColonyList(inner, buf, model)
  of ViewMode.Fleets:
    renderFleetList(inner, buf, model)
  of ViewMode.Orders:
    discard buf.setString(inner.x, inner.y, "No pending orders", dimStyle())
  of ViewMode.Map:
    var y = inner.y
    discard buf.setString(inner.x, y, "Arrow keys: Move cursor", normalStyle())
    y += 1
    discard buf.setString(inner.x, y, "Tab: Next colony", normalStyle())
    y += 1
    discard buf.setString(inner.x, y, "H: Jump to homeworld", normalStyle())
    y += 1
    discard buf.setString(inner.x, y, "Enter: Select system", normalStyle())

proc renderDashboard(buf: var CellBuffer, model: TuiModel, 
                     state: GameState, viewingHouse: HouseId) =
  ## Render the complete TUI dashboard using SAM model
  let termRect = rect(0, 0, model.termWidth, model.termHeight)
  
  let mainRows = vertical()
    .constraints(fill(), length(1))
    .split(termRect)
  
  let contentArea = mainRows[0]
  let statusArea = mainRows[1]
  
  let leftWidth = max(MapWidth, MenuWidth) + 2
  let mainCols = horizontal()
    .constraints(length(leftWidth), fill())
    .split(contentArea)
  
  let leftCol = mainCols[0]
  let rightCol = mainCols[1]
  
  let leftRows = vertical()
    .constraints(length(MapHeight + 2), fill())
    .split(leftCol)
  
  let mapArea = leftRows[0]
  let menuArea = leftRows[1]
  
  let contextHeight = max(8, contentArea.height div 3)
  let rightRows = vertical()
    .constraints(length(contextHeight), fill())
    .split(rightCol)
  
  let contextArea = rightRows[0]
  let listArea = rightRows[1]
  
  # Create map data from model for rendering
  let mapData = toFogOfWarMapData(state, viewingHouse)
  
  # Create hex map state from SAM model
  var hexState = newHexMapState(coords.hexCoord(model.mapState.cursor.q, model.mapState.cursor.r))
  hexState.viewportOrigin = coords.hexCoord(model.mapState.viewportOrigin.q, model.mapState.viewportOrigin.r)
  if model.mapState.selected.isSome:
    hexState.selected = some(coords.hexCoord(model.mapState.selected.get.q, model.mapState.selected.get.r))
  
  # Render small map
  let mapFrame = bordered().title("Map").borderType(BorderType.Rounded)
  let map = hexMap(mapData).block(mapFrame)
  map.render(mapArea, buf, hexState)
  
  # Render panels
  renderMenuPanel(menuArea, buf, model)
  renderContextPanel(contextArea, buf, model, state, viewingHouse)
  renderListPanel(listArea, buf, model)
  renderStatusBar(statusArea, buf, model)

# =============================================================================
# Output
# =============================================================================

proc outputBuffer(buf: CellBuffer) =
  ## Output buffer to terminal
  for y in 0 ..< buf.h:
    stdout.write(cursorPosition(y + 1, 1))
    for x in 0 ..< buf.w:
      let (str, style, _) = buf.get(x, y)
      if not style.fg.isNone:
        stdout.write(CSI & style.fg.sequence(false) & "m")
      if not style.bg.isNone:
        stdout.write(CSI & style.bg.sequence(true) & "m")
      if StyleAttr.Bold in style.attrs:
        stdout.write(CSI & SgrBold & "m")
      if StyleAttr.Faint in style.attrs:
        stdout.write(CSI & SgrFaint & "m")
      stdout.write(str)
      stdout.write(CSI & "0m")
  stdout.flushFile()

# =============================================================================
# Main Entry Point
# =============================================================================

proc main() =
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
  initialModel.mode = ViewMode.Colonies
  
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
  
  # =========================================================================
  # Cleanup
  # =========================================================================
  
  stdout.write(showCursor())
  stdout.write(exitAltScreen())
  stdout.flushFile()
  discard tty.stop()
  tty.close()
  
  echo "TUI Player (SAM) exited."

when isMainModule:
  main()
