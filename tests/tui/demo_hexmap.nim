## Interactive hex map dashboard demo
##
## Demonstrates the hex map widget with:
## - Split-view layout (map + detail panel)
## - Keyboard navigation
## - Real-time rendering
##
## Run: nim c -r tests/tui/demo_hexmap.nim
## Controls: Arrow keys to move, Enter to select, Tab to cycle, q to quit

import std/[tables, options]
import ../../src/player/tui/term/term
import ../../src/player/tui/term/types/core
import ../../src/player/tui/buffer
import ../../src/player/tui/events
import ../../src/player/tui/input
import ../../src/player/tui/tty
import ../../src/player/tui/signals
import ../../src/player/tui/layout/layout_pkg
import ../../src/player/tui/widget/widget_pkg
import ../../src/player/tui/widget/frame
import ../../src/player/tui/widget/hexmap/hexmap_pkg

# Helper to create Color from ANSI 256-color index
proc toColor(n: int): Color {.inline.} =
  color(Ansi256Color(n))

# -----------------------------------------------------------------------------
# Sample map data (simulates a small game)
# -----------------------------------------------------------------------------

proc createSampleMap(): MapData =
  ## Create a sample 3-ring map for demonstration
  var systems = initTable[HexCoord, SystemInfo]()
  
  # Hub system at center
  systems[hexCoord(0, 0)] = SystemInfo(
    id: 0,
    name: "Sol Prime",
    coords: hexCoord(0, 0),
    ring: 0,
    planetClass: 5,  # Lush
    resourceRating: 3,  # Rich
    owner: none(int),
    isHomeworld: false,
    isHub: true,
    fleetCount: 0
  )
  
  # Player homeworld and colonies (house 0)
  systems[hexCoord(1, 0)] = SystemInfo(
    id: 1,
    name: "Terra Nova",
    coords: hexCoord(1, 0),
    ring: 1,
    planetClass: 6,  # Eden
    resourceRating: 4,  # Very Rich
    owner: some(0),
    isHomeworld: true,
    isHub: false,
    fleetCount: 2
  )
  
  systems[hexCoord(2, 0)] = SystemInfo(
    id: 2,
    name: "Alpha Colony",
    coords: hexCoord(2, 0),
    ring: 2,
    planetClass: 4,  # Benign
    resourceRating: 2,  # Abundant
    owner: some(0),
    isHomeworld: false,
    isHub: false,
    fleetCount: 1
  )
  
  systems[hexCoord(1, 1)] = SystemInfo(
    id: 3,
    name: "Beta Outpost",
    coords: hexCoord(1, 1),
    ring: 2,
    planetClass: 3,  # Harsh
    resourceRating: 3,  # Rich
    owner: some(0),
    isHomeworld: false,
    isHub: false,
    fleetCount: 0
  )
  
  # Enemy colonies (house 1)
  systems[hexCoord(-1, 0)] = SystemInfo(
    id: 4,
    name: "Krypton",
    coords: hexCoord(-1, 0),
    ring: 1,
    planetClass: 5,  # Lush
    resourceRating: 3,  # Rich
    owner: some(1),
    isHomeworld: true,
    isHub: false,
    fleetCount: 3
  )
  
  systems[hexCoord(-2, 1)] = SystemInfo(
    id: 5,
    name: "Zod Prime",
    coords: hexCoord(-2, 1),
    ring: 2,
    planetClass: 4,  # Benign
    resourceRating: 2,  # Abundant
    owner: some(1),
    isHomeworld: false,
    isHub: false,
    fleetCount: 1
  )
  
  # Neutral systems
  systems[hexCoord(0, 1)] = SystemInfo(
    id: 6,
    name: "Pandora",
    coords: hexCoord(0, 1),
    ring: 1,
    planetClass: 2,  # Hostile
    resourceRating: 4,  # Very Rich
    owner: none(int),
    isHomeworld: false,
    isHub: false,
    fleetCount: 0
  )
  
  systems[hexCoord(0, -1)] = SystemInfo(
    id: 7,
    name: "Arrakis",
    coords: hexCoord(0, -1),
    ring: 1,
    planetClass: 0,  # Extreme
    resourceRating: 4,  # Very Rich (spice!)
    owner: none(int),
    isHomeworld: false,
    isHub: false,
    fleetCount: 0
  )
  
  systems[hexCoord(-1, 1)] = SystemInfo(
    id: 8,
    name: "Caladan",
    coords: hexCoord(-1, 1),
    ring: 1,
    planetClass: 5,  # Lush
    resourceRating: 2,  # Abundant
    owner: none(int),
    isHomeworld: false,
    isHub: false,
    fleetCount: 0
  )
  
  systems[hexCoord(1, -1)] = SystemInfo(
    id: 9,
    name: "Giedi",
    coords: hexCoord(1, -1),
    ring: 1,
    planetClass: 1,  # Desolate
    resourceRating: 3,  # Rich
    owner: none(int),
    isHomeworld: false,
    isHub: false,
    fleetCount: 0
  )
  
  # More outer ring systems
  systems[hexCoord(2, -1)] = SystemInfo(
    id: 10,
    name: "Ix",
    coords: hexCoord(2, -1),
    ring: 2,
    planetClass: 4,  # Benign
    resourceRating: 4,  # Very Rich
    owner: none(int),
    isHomeworld: false,
    isHub: false,
    fleetCount: 0
  )
  
  systems[hexCoord(-1, 2)] = SystemInfo(
    id: 11,
    name: "Tleilax",
    coords: hexCoord(-1, 2),
    ring: 2,
    planetClass: 3,  # Harsh
    resourceRating: 1,  # Poor
    owner: none(int),
    isHomeworld: false,
    isHub: false,
    fleetCount: 0
  )
  
  MapData(
    systems: systems,
    maxRing: 3,
    viewingHouse: 0  # Player is house 0
  )

proc createDetailData(mapData: MapData, state: HexMapState): DetailPanelData =
  ## Create detail panel data for current cursor position
  let coord = state.cursor
  
  var jumpLanes: seq[JumpLaneInfo] = @[]
  var fleets: seq[FleetInfo] = @[]
  
  if mapData.systems.hasKey(coord):
    let sys = mapData.systems[coord]
    
    # Add mock jump lanes to neighboring systems
    for neighbor in coord.neighbors():
      if mapData.systems.hasKey(neighbor):
        let neighborSys = mapData.systems[neighbor]
        let laneClass = if neighbor.ring() == 0 or coord.ring() == 0: 0  # Major to hub
                        elif neighborSys.owner == some(0): 0  # Major to owned
                        else: 1  # Minor
        jumpLanes.add(JumpLaneInfo(
          targetName: neighborSys.name,
          targetCoord: neighbor,
          laneClass: laneClass
        ))
    
    # Add mock fleets
    if sys.fleetCount > 0:
      for i in 0 ..< sys.fleetCount:
        let isOwned = sys.owner == some(mapData.viewingHouse)
        fleets.add(FleetInfo(
          name: (if isOwned: "Fleet " else: "Enemy ") & $(i + 1),
          shipCount: 3 + i * 2,
          isOwned: isOwned
        ))
    
    result = DetailPanelData(
      system: some(sys),
      jumpLanes: jumpLanes,
      fleets: fleets
    )
  else:
    result = DetailPanelData(
      system: none(SystemInfo),
      jumpLanes: @[],
      fleets: @[]
    )

# -----------------------------------------------------------------------------
# Rendering
# -----------------------------------------------------------------------------

proc renderHelpBar(area: Rect, buf: var CellBuffer) =
  ## Render the help bar at bottom
  let helpStyle = CellStyle(
    fg: toColor(250),
    attrs: {}
  )
  let keyStyle = CellStyle(
    fg: toColor(226),
    attrs: {StyleAttr.Bold}
  )
  
  var x = area.x
  let y = area.y
  
  # Helper to render key + description
  proc renderKey(key, desc: string) =
    discard buf.setString(x, y, "[", helpStyle)
    x += 1
    discard buf.setString(x, y, key, keyStyle)
    x += key.len
    discard buf.setString(x, y, "] ", helpStyle)
    x += 2
    discard buf.setString(x, y, desc & "  ", helpStyle)
    x += desc.len + 2
  
  renderKey("Arrows", "Move")
  renderKey("Enter", "Select")
  renderKey("Tab", "Next Colony")
  renderKey("h", "Home")
  renderKey("q", "Quit")

proc renderFrame(buf: var CellBuffer, mapData: MapData, 
                 mapState: var HexMapState, termWidth, termHeight: int) =
  ## Render the complete dashboard frame
  let termRect = rect(0, 0, termWidth, termHeight)
  
  # Main layout: content area with help bar at bottom
  let rows = vertical()
    .constraints(fill(), length(1))
    .split(termRect)
  
  let contentArea = rows[0]
  let helpArea = rows[1]
  
  # Split content into map and detail panel
  # Detail panel is fixed 32 chars, map gets the rest
  let cols = horizontal()
    .constraints(fill(), length(32))
    .spacing(1)
    .split(contentArea)
  
  let mapArea = cols[0]
  let detailArea = cols[1]
  
  # Create and render hex map
  let mapFrame = bordered().title("Starmap").borderType(BorderType.Rounded)
  let map = hexMap(mapData).block(mapFrame)
  
  map.render(mapArea, buf, mapState)
  
  # Create and render detail panel
  let detailFrameWidget = bordered().title("System Info").borderType(BorderType.Rounded)
  detailFrameWidget.render(detailArea, buf)
  let detailInner = detailFrameWidget.inner(detailArea)
  
  let detailData = createDetailData(mapData, mapState)
  renderDetailPanel(detailInner, buf, detailData, mapState.colors)

# -----------------------------------------------------------------------------
# Main loop
# -----------------------------------------------------------------------------

proc main() =
  # Initialize terminal
  var tty = openTty()
  if not tty.start():
    echo "Failed to enter raw mode"
    quit(1)
  
  # Install resize handler
  setupResizeHandler()
  
  # Get initial size
  var (termWidth, termHeight) = tty.windowSize()
  
  # Create screen buffer
  var buf = initBuffer(termWidth, termHeight)
  
  # Create map data and state
  let mapData = createSampleMap()
  var mapState = newHexMapState(hexCoord(0, 0))
  
  # Create input parser
  var parser = initParser()
  
  # Enter alternate screen
  var output = newStdoutOutput()
  stdout.write(altScreen())
  stdout.write(hideCursor())
  stdout.flushFile()
  
  var running = true
  
  # Initial render
  buf.clear()
  renderFrame(buf, mapData, mapState, termWidth, termHeight)
  
  # Output initial frame
  for y in 0 ..< buf.h:
    stdout.write(cursorPosition(y + 1, 1))  # row, col (1-based)
    for x in 0 ..< buf.w:
      let (str, style, _) = buf.get(x, y)
      # Simple output - full frame
      if not style.fg.isNone:
        stdout.write(CSI & style.fg.sequence(false) & "m")
      if StyleAttr.Bold in style.attrs:
        stdout.write(CSI & SgrBold & "m")
      stdout.write(str)
      stdout.write(CSI & "0m")  # Reset
  stdout.flushFile()
  
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
        let navResult = processNavigation(mapState, event.keyEvent, mapData)
        
        if navResult.action == NavAction.Quit:
          running = false
          break
    
    # Re-render
    buf.clear()
    renderFrame(buf, mapData, mapState, termWidth, termHeight)
    
    # Output frame (simple full redraw for demo)
    for y in 0 ..< buf.h:
      stdout.write(cursorPosition(y + 1, 1))  # row, col (1-based)
      for x in 0 ..< buf.w:
        let (str, style, _) = buf.get(x, y)
        if not style.fg.isNone:
          stdout.write(CSI & style.fg.sequence(false) & "m")
        if StyleAttr.Bold in style.attrs:
          stdout.write(CSI & SgrBold & "m")
        stdout.write(str)
        stdout.write(CSI & "0m")
    stdout.flushFile()
  
  # Cleanup
  stdout.write(showCursor())
  stdout.write(exitAltScreen())
  stdout.flushFile()
  discard tty.stop()
  tty.close()
  
  echo "Demo exited."

when isMainModule:
  main()
