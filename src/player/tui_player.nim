## EC4X TUI Player - Terminal User Interface
##
## Main entry point for the TUI player client. Displays game state
## with fog-of-war and provides interactive control interface.
##
## Layout:
##   ┌─ Map ────────┬─ Context ────────────────────────┐
##   │  (small)     │ System/Fleet/Colony details      │
##   ├──────────────┼──────────────────────────────────┤
##   │ [C]olonies   │ List of items based on mode      │
##   │ [F]leets     │                                  │
##   │ [O]rders     │                                  │
##   │ [E]nd Turn   │                                  │
##   ├──────────────┴──────────────────────────────────┤
##   │ Status bar                                      │
##   └─────────────────────────────────────────────────┘
##
## Run: nimble buildTui && ./bin/ec4x-tui

import std/[options, strformat, tables, strutils, unicode]
import ../common/logger
import ../engine/init/game_state
import ../engine/types/[core, game_state, colony, fleet]
import ../engine/state/[engine, fog_of_war, iterators]
import ./tui/term/term
import ./tui/term/types/core
import ./tui/buffer
import ./tui/events
import ./tui/input
import ./tui/tty
import ./tui/signals
import ./tui/layout/layout_pkg
import ./tui/widget/[widget_pkg, frame, paragraph]
import ./tui/widget/hexmap/hexmap_pkg
import ./tui/adapters

type
  ViewMode* {.pure.} = enum
    Map        ## Navigating the starmap
    Colonies   ## Colony list
    Fleets     ## Fleet list
    Orders     ## Pending orders
  
  TuiState* = object
    mode*: ViewMode
    mapState*: HexMapState
    selectedIdx*: int  ## Index in current list

# -----------------------------------------------------------------------------
# Styles
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Status Bar (Bottom)
# -----------------------------------------------------------------------------

proc renderStatusBar(area: Rect, buf: var CellBuffer, state: GameState, 
                     viewingHouse: HouseId, tuiState: TuiState) =
  ## Render bottom status bar with game info
  let house = state.house(viewingHouse).get()
  
  var x = area.x + 1
  let y = area.y
  
  # Turn
  discard buf.setString(x, y, "Turn: ", dimStyle())
  x += 6
  discard buf.setString(x, y, $state.turn, highlightStyle())
  x += ($state.turn).len + 3
  
  # Treasury
  discard buf.setString(x, y, "Treasury: ", dimStyle())
  x += 10
  discard buf.setString(x, y, $house.treasury & " MCr", highlightStyle())
  x += ($house.treasury).len + 7
  
  # Prestige
  discard buf.setString(x, y, "Prestige: ", dimStyle())
  x += 10
  discard buf.setString(x, y, $house.prestige, highlightStyle())
  x += ($house.prestige).len + 3
  
  # Current mode
  let modeStr = case tuiState.mode
    of ViewMode.Map: "[MAP]"
    of ViewMode.Colonies: "[COLONIES]"
    of ViewMode.Fleets: "[FLEETS]"
    of ViewMode.Orders: "[ORDERS]"
  discard buf.setString(x, y, modeStr, headerStyle())
  
  # House name (right-aligned)
  let nameX = area.x + area.width - house.name.len - 2
  discard buf.setString(nameX, y, house.name, highlightStyle())

# -----------------------------------------------------------------------------
# Menu Panel (Left side, below map)
# -----------------------------------------------------------------------------

proc renderMenuPanel(area: Rect, buf: var CellBuffer, tuiState: TuiState) =
  ## Render the menu shortcuts panel
  let frame = bordered().title("Menu").borderType(BorderType.Rounded)
  frame.render(area, buf)
  let inner = frame.inner(area)
  
  var y = inner.y
  
  # Menu items with highlight for current mode
  let items = [
    (key: "C", label: "Colonies", mode: ViewMode.Colonies),
    (key: "F", label: "Fleets", mode: ViewMode.Fleets),
    (key: "O", label: "Orders", mode: ViewMode.Orders),
    (key: "M", label: "Map", mode: ViewMode.Map),
  ]
  
  for item in items:
    if y >= inner.bottom:
      break
    
    let isActive = tuiState.mode == item.mode
    let style = if isActive: selectedStyle() else: normalStyle()
    let keyStyle = if isActive: selectedStyle() else: highlightStyle()
    
    discard buf.setString(inner.x, y, "[", dimStyle())
    discard buf.setString(inner.x + 1, y, item.key, keyStyle)
    discard buf.setString(inner.x + 2, y, "] ", dimStyle())
    discard buf.setString(inner.x + 4, y, item.label, style)
    y += 1
  
  # Separator
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

# -----------------------------------------------------------------------------
# Context Panel (Top right - shows details)
# -----------------------------------------------------------------------------

proc renderContextPanel(area: Rect, buf: var CellBuffer, state: GameState,
                        viewingHouse: HouseId, tuiState: TuiState) =
  ## Render context-sensitive detail panel
  let title = case tuiState.mode
    of ViewMode.Map: "System Info"
    of ViewMode.Colonies: "Colony Details"
    of ViewMode.Fleets: "Fleet Details"
    of ViewMode.Orders: "Order Details"
  
  let frame = bordered().title(title).borderType(BorderType.Rounded)
  frame.render(area, buf)
  let inner = frame.inner(area)
  
  # For now, show system info from map cursor
  let detailData = toFogOfWarDetailPanelData(
    tuiState.mapState.cursor, state, viewingHouse
  )
  renderDetailPanel(inner, buf, detailData, tuiState.mapState.colors)

# -----------------------------------------------------------------------------
# List Panel (Bottom right - shows lists)
# -----------------------------------------------------------------------------

proc renderColonyList(area: Rect, buf: var CellBuffer, state: GameState,
                      viewingHouse: HouseId, selectedIdx: int) =
  ## Render list of player's colonies
  var y = area.y
  var idx = 0
  
  for colony in state.coloniesOwned(viewingHouse):
    if y >= area.bottom:
      break
    
    let isSelected = idx == selectedIdx
    let style = if isSelected: selectedStyle() else: normalStyle()
    let sysOpt = state.system(colony.systemId)
    let name = if sysOpt.isSome: sysOpt.get().name else: "???"
    
    # Format: "  Name          PP:xxx  Pop:xxx"
    let prefix = if isSelected: "> " else: "  "
    let line = prefix & name.alignLeft(14) & " PP:" & 
               align($colony.production, 4) & 
               " Pop:" & align($colony.population, 5)
    
    discard buf.setString(area.x, y, line[0 ..< min(line.len, area.width)], style)
    y += 1
    idx += 1
  
  if idx == 0:
    discard buf.setString(area.x, y, "No colonies", dimStyle())

proc renderFleetList(area: Rect, buf: var CellBuffer, state: GameState,
                     viewingHouse: HouseId, selectedIdx: int) =
  ## Render list of player's fleets
  var y = area.y
  var idx = 0
  
  for fleet in state.fleetsOwned(viewingHouse):
    if y >= area.bottom:
      break
    
    let isSelected = idx == selectedIdx
    let style = if isSelected: selectedStyle() else: normalStyle()
    let sysOpt = state.system(fleet.location)
    let locName = if sysOpt.isSome: sysOpt.get().name else: "???"
    
    # Format: "  Fleet #ID    @ Location    Ships:x"
    let prefix = if isSelected: "> " else: "  "
    let fleetName = "Fleet #" & $int(fleet.id)
    let line = prefix & fleetName.alignLeft(12) & " @ " & 
               locName.alignLeft(10) & " Ships:" & $fleet.ships.len
    
    discard buf.setString(area.x, y, line[0 ..< min(line.len, area.width)], style)
    y += 1
    idx += 1
  
  if idx == 0:
    discard buf.setString(area.x, y, "No fleets", dimStyle())

proc renderListPanel(area: Rect, buf: var CellBuffer, state: GameState,
                     viewingHouse: HouseId, tuiState: TuiState) =
  ## Render the main list panel based on current mode
  let title = case tuiState.mode
    of ViewMode.Colonies: "Your Colonies"
    of ViewMode.Fleets: "Your Fleets"
    of ViewMode.Orders: "Pending Orders"
    of ViewMode.Map: "Navigation"
  
  let frame = bordered().title(title).borderType(BorderType.Rounded)
  frame.render(area, buf)
  let inner = frame.inner(area)
  
  case tuiState.mode
  of ViewMode.Colonies:
    renderColonyList(inner, buf, state, viewingHouse, tuiState.selectedIdx)
  of ViewMode.Fleets:
    renderFleetList(inner, buf, state, viewingHouse, tuiState.selectedIdx)
  of ViewMode.Orders:
    discard buf.setString(inner.x, inner.y, "No pending orders", dimStyle())
  of ViewMode.Map:
    # Show map navigation help
    var y = inner.y
    discard buf.setString(inner.x, y, "Arrow keys: Move cursor", normalStyle())
    y += 1
    discard buf.setString(inner.x, y, "Tab: Next colony", normalStyle())
    y += 1
    discard buf.setString(inner.x, y, "H: Jump to homeworld", normalStyle())
    y += 1
    discard buf.setString(inner.x, y, "Enter: Select system", normalStyle())

# -----------------------------------------------------------------------------
# Main Dashboard
# -----------------------------------------------------------------------------

proc renderDashboard(buf: var CellBuffer, state: GameState, 
                     tuiState: var TuiState, viewingHouse: HouseId,
                     termWidth, termHeight: int) =
  ## Render the complete TUI dashboard
  ##
  ## Layout:
  ##   ┌─ Map ────────┬─ Context ─────────────────────┐
  ##   │  (small)     │ System/Fleet/Colony details   │
  ##   ├──────────────┼───────────────────────────────┤
  ##   │ [C]olonies   │ List panel                    │
  ##   │ [F]leets     │                               │
  ##   │ [M]ap        │                               │
  ##   │ [E]nd Turn   │                               │
  ##   ├──────────────┴───────────────────────────────┤
  ##   │ Status bar                                   │
  ##   └──────────────────────────────────────────────┘
  
  let termRect = rect(0, 0, termWidth, termHeight)
  
  # Main vertical split: content area + status bar at bottom
  let mainRows = vertical()
    .constraints(fill(), length(1))
    .split(termRect)
  
  let contentArea = mainRows[0]
  let statusArea = mainRows[1]
  
  # Left column (map + menu) vs right column (context + list)
  let leftWidth = max(MapWidth, MenuWidth) + 2  # +2 for borders
  let mainCols = horizontal()
    .constraints(length(leftWidth), fill())
    .split(contentArea)
  
  let leftCol = mainCols[0]
  let rightCol = mainCols[1]
  
  # Left column: map (top) + menu (bottom)
  let leftRows = vertical()
    .constraints(length(MapHeight + 2), fill())  # +2 for borders
    .split(leftCol)
  
  let mapArea = leftRows[0]
  let menuArea = leftRows[1]
  
  # Right column: context (top) + list (bottom)
  # Context panel is ~1/3 of height, list gets rest
  let contextHeight = max(8, contentArea.height div 3)
  let rightRows = vertical()
    .constraints(length(contextHeight), fill())
    .split(rightCol)
  
  let contextArea = rightRows[0]
  let listArea = rightRows[1]
  
  # Create map data with fog-of-war
  let mapData = toFogOfWarMapData(state, viewingHouse)
  
  # Render small map
  let mapFrame = bordered().title("Map").borderType(BorderType.Rounded)
  let map = hexMap(mapData).block(mapFrame)
  map.render(mapArea, buf, tuiState.mapState)
  
  # Render menu panel
  renderMenuPanel(menuArea, buf, tuiState)
  
  # Render context panel (details)
  renderContextPanel(contextArea, buf, state, viewingHouse, tuiState)
  
  # Render list panel
  renderListPanel(listArea, buf, state, viewingHouse, tuiState)
  
  # Render status bar
  renderStatusBar(statusArea, buf, state, viewingHouse, tuiState)

# -----------------------------------------------------------------------------
# Output
# -----------------------------------------------------------------------------

proc outputBuffer(buf: CellBuffer) =
  ## Output buffer to terminal (simple full redraw)
  for y in 0 ..< buf.h:
    stdout.write(cursorPosition(y + 1, 1))  # row, col (1-based)
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
      stdout.write(CSI & "0m")  # Reset
  stdout.flushFile()

# -----------------------------------------------------------------------------
# Input Handling
# -----------------------------------------------------------------------------

proc handleInput(tuiState: var TuiState, event: KeyEvent, 
                 mapData: MapData, state: GameState, 
                 viewingHouse: HouseId): bool =
  ## Handle keyboard input. Returns false if should quit.
  
  # Global keys (work in any mode)
  if event.key == Key.Rune:
    let ch = $event.rune
    case ch
    of "q", "Q":
      return false
    of "c", "C":
      tuiState.mode = ViewMode.Colonies
      tuiState.selectedIdx = 0
      return true
    of "f", "F":
      tuiState.mode = ViewMode.Fleets
      tuiState.selectedIdx = 0
      return true
    of "o", "O":
      tuiState.mode = ViewMode.Orders
      tuiState.selectedIdx = 0
      return true
    of "m", "M":
      tuiState.mode = ViewMode.Map
      return true
    of "e", "E":
      # TODO: End turn
      return true
    else:
      discard
  
  # Mode-specific input
  case tuiState.mode
  of ViewMode.Map:
    # Map navigation
    let navResult = processNavigation(tuiState.mapState, event, mapData)
    if navResult.action == NavAction.Quit:
      return false
  
  of ViewMode.Colonies, ViewMode.Fleets:
    # List navigation
    case event.key
    of Key.Up:
      if tuiState.selectedIdx > 0:
        tuiState.selectedIdx -= 1
    of Key.Down:
      tuiState.selectedIdx += 1
      # TODO: Clamp to list length
    of Key.Enter:
      # TODO: Select item, show details or actions
      discard
    else:
      discard
  
  of ViewMode.Orders:
    discard
  
  return true

# -----------------------------------------------------------------------------
# Main Entry Point
# -----------------------------------------------------------------------------

proc main() =
  logInfo("TUI Player", "Starting EC4X TUI Player...")
  
  # Initialize game state
  logInfo("TUI Player", "Creating new game...")
  var state = initGameState(
    setupPath = "scenarios/standard-4-player.kdl",
    gameName = "TUI Test Game",
    configDir = "config",
    dataDir = "data"
  )
  
  logInfo("TUI Player", &"Game created: {state.housesCount()} houses, {state.systemsCount()} systems")
  
  # Player is house 1
  let viewingHouse = HouseId(1)
  
  # Initialize terminal
  var tty = openTty()
  if not tty.start():
    logError("TUI Player", "Failed to enter raw mode")
    quit(1)
  
  # Install resize handler
  setupResizeHandler()
  
  # Get initial size
  var (termWidth, termHeight) = tty.windowSize()
  logInfo("TUI Player", &"Terminal size: {termWidth}x{termHeight}")
  
  # Create screen buffer
  var buf = initBuffer(termWidth, termHeight)
  
  # Find player homeworld for initial cursor position
  var initialCoord = hexCoord(0, 0)
  for systemId, houseId in state.starMap.homeWorlds.pairs():
    if houseId == viewingHouse:
      let sys = state.system(systemId).get()
      initialCoord = toHexCoord(sys.coords)
      break
  
  # Create TUI state
  var tuiState = TuiState(
    mode: ViewMode.Colonies,  # Start in colonies view
    mapState: newHexMapState(initialCoord),
    selectedIdx: 0
  )
  
  logInfo("TUI Player", &"Initial cursor position: {initialCoord.q}, {initialCoord.r}")
  
  # Create input parser
  var parser = initParser()
  
  logInfo("TUI Player", "Entering TUI mode...")
  
  # Enter alternate screen
  stdout.write(altScreen())
  stdout.write(hideCursor())
  stdout.flushFile()
  
  var running = true
  
  # Initial render
  buf.clear()
  renderDashboard(buf, state, tuiState, viewingHouse, termWidth, termHeight)
  outputBuffer(buf)
  
  while running:
    # Check for resize
    if checkResize():
      (termWidth, termHeight) = tty.windowSize()
      buf.resize(termWidth, termHeight)
      buf.invalidate()
    
    # Read input (blocking)
    let inputByte = tty.readByte()
    if inputByte < 0:
      continue
    
    let events = parser.feedByte(inputByte.uint8)
    
    for event in events:
      if event.kind == EventKind.Key:
        let mapData = toFogOfWarMapData(state, viewingHouse)
        if not handleInput(tuiState, event.keyEvent, mapData, state, viewingHouse):
          running = false
          break
    
    # Re-render
    buf.clear()
    renderDashboard(buf, state, tuiState, viewingHouse, termWidth, termHeight)
    outputBuffer(buf)
  
  # Cleanup
  stdout.write(showCursor())
  stdout.write(exitAltScreen())
  stdout.flushFile()
  discard tty.stop()
  tty.close()
  
  echo "TUI Player exited."

when isMainModule:
  main()
