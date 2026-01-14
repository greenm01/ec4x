## Tests for hex map widget and coordinate system.

import std/[unittest, options, tables, unicode]
import ../../src/player/tui/widget/hexmap/hexmap_pkg
import ../../src/player/tui/events

suite "HexCoord":
  test "construction":
    let h = hexCoord(1, 2)
    check h.q == 1
    check h.r == 2
  
  test "equality":
    let a = hexCoord(1, 2)
    let b = hexCoord(1, 2)
    let c = hexCoord(2, 1)
    check a == b
    check not (a == c)
  
  test "addition":
    let a = hexCoord(1, 2)
    let b = hexCoord(3, 4)
    let c = a + b
    check c.q == 4
    check c.r == 6
  
  test "subtraction":
    let a = hexCoord(5, 7)
    let b = hexCoord(2, 3)
    let c = a - b
    check c.q == 3
    check c.r == 4
  
  test "s coordinate":
    let h = hexCoord(1, 2)
    check h.s() == -3  # s = -q - r = -1 - 2 = -3

suite "Hex distance":
  test "distance from origin":
    check distance(hexCoord(0, 0), hexCoord(1, 0)) == 1
    check distance(hexCoord(0, 0), hexCoord(0, 1)) == 1
    check distance(hexCoord(0, 0), hexCoord(1, 1)) == 2
  
  test "distance between hexes":
    check distance(hexCoord(1, 1), hexCoord(2, 1)) == 1
    check distance(hexCoord(0, 0), hexCoord(3, 3)) == 6
  
  test "ring calculation":
    check hexCoord(0, 0).ring() == 0
    check hexCoord(1, 0).ring() == 1
    check hexCoord(0, 1).ring() == 1
    check hexCoord(2, 2).ring() == 4

suite "Hex neighbors":
  test "neighbor directions":
    let h = hexCoord(0, 0)
    check h.neighbor(HexDirection.East) == hexCoord(1, 0)
    check h.neighbor(HexDirection.West) == hexCoord(-1, 0)
    check h.neighbor(HexDirection.Southeast) == hexCoord(0, 1)
    check h.neighbor(HexDirection.Northwest) == hexCoord(0, -1)
    check h.neighbor(HexDirection.Southwest) == hexCoord(-1, 1)
    check h.neighbor(HexDirection.Northeast) == hexCoord(1, -1)
  
  test "neighbors array":
    let h = hexCoord(1, 1)
    let ns = h.neighbors()
    check ns.len == 6
    # Check that all neighbors are distance 1
    for n in ns:
      check distance(h, n) == 1

suite "Screen conversion":
  test "axial to screen - origin":
    let pos = axialToScreen(hexCoord(0, 0), hexCoord(0, 0))
    check pos.x == 0
    check pos.y == 0
  
  test "axial to screen - basic":
    # Each hex is 2 chars wide
    let pos1 = axialToScreen(hexCoord(1, 0), hexCoord(0, 0))
    check pos1.x == 2  # q * 2
    check pos1.y == 0
    
    # r adds both y and x offset (for stagger)
    let pos2 = axialToScreen(hexCoord(0, 1), hexCoord(0, 0))
    check pos2.x == 1  # r offset
    check pos2.y == 1
  
  test "axial to screen - with offset":
    let pos = axialToScreen(hexCoord(2, 1), hexCoord(1, 0))
    # Relative coords: (2-1, 1-0) = (1, 1)
    # x = 1*2 + 1 = 3, y = 1
    check pos.x == 3
    check pos.y == 1
  
  test "screen to axial - origin":
    let hex = screenToAxial(screenPos(0, 0), hexCoord(0, 0))
    check hex.q == 0
    check hex.r == 0
  
  test "screen to axial - basic":
    let hex1 = screenToAxial(screenPos(2, 0), hexCoord(0, 0))
    check hex1.q == 1
    check hex1.r == 0
    
    let hex2 = screenToAxial(screenPos(1, 1), hexCoord(0, 0))
    check hex2.q == 0
    check hex2.r == 1
  
  test "roundtrip conversion":
    let original = hexCoord(3, 2)
    let pos = axialToScreen(original, hexCoord(0, 0))
    let converted = screenToAxial(pos, hexCoord(0, 0))
    check converted == original

suite "Ring iteration":
  test "ring 0":
    var count = 0
    for hex in hexesInRing(hexCoord(0, 0), 0):
      count += 1
      check hex == hexCoord(0, 0)
    check count == 1
  
  test "ring 1":
    var coords: seq[HexCoord] = @[]
    for hex in hexesInRing(hexCoord(0, 0), 1):
      coords.add(hex)
    check coords.len == 6
    # All should be distance 1 from center
    for coord in coords:
      check distance(hexCoord(0, 0), coord) == 1
  
  test "spiral iteration":
    var coords: seq[HexCoord] = @[]
    for hex in hexesInSpiral(hexCoord(0, 0), 2):
      coords.add(hex)
    # Ring 0: 1, Ring 1: 6, Ring 2: 12 = 19 total
    check coords.len == 19

suite "HexMapState":
  test "initialization":
    let state = newHexMapState(hexCoord(0, 0))
    check state.cursor == hexCoord(0, 0)
    check state.selected.isNone
  
  test "move cursor":
    var state = newHexMapState(hexCoord(0, 0))
    state.moveCursor(HexDirection.East)
    check state.cursor == hexCoord(1, 0)
  
  test "selection":
    var state = newHexMapState(hexCoord(0, 0))
    check state.selected.isNone
    
    state.selectCurrent()
    check state.selected.isSome
    check state.selected.get() == hexCoord(0, 0)
    
    state.deselect()
    check state.selected.isNone
  
  test "center on hex":
    var state = newHexMapState(hexCoord(0, 0))
    state.centerOn(hexCoord(5, 5))
    check state.cursor == hexCoord(5, 5)

suite "MapData":
  test "system lookup":
    var systems = initTable[HexCoord, SystemInfo]()
    systems[hexCoord(0, 0)] = SystemInfo(
      id: 1,
      name: "Hub",
      coords: hexCoord(0, 0),
      ring: 0,
      isHub: true
    )
    
    let mapData = MapData(
      systems: systems,
      maxRing: 3,
      viewingHouse: 0
    )
    
    let map = hexMap(mapData)
    let sys = map.systemAt(hexCoord(0, 0))
    check sys.isSome
    check sys.get().name == "Hub"
    check sys.get().isHub

suite "Navigation":
  test "key to movement":
    var state = newHexMapState(hexCoord(0, 0))
    
    # Right arrow
    let event1 = KeyEvent(key: Key.Right, rune: Rune(0), modifiers: ModNone)
    let result1 = handleKey(state, event1, MapData())
    check result1.consumed
    check result1.action == NavAction.MoveCursor
    check state.cursor == hexCoord(1, 0)
    
    # Left arrow
    let event2 = KeyEvent(key: Key.Left, rune: Rune(0), modifiers: ModNone)
    let result2 = handleKey(state, event2, MapData())
    check result2.consumed
    check state.cursor == hexCoord(0, 0)
  
  test "enter selects":
    var state = newHexMapState(hexCoord(0, 0))
    let event = KeyEvent(key: Key.Enter, rune: Rune(0), modifiers: ModNone)
    let result = handleKey(state, event, MapData())
    
    check result.consumed
    check result.action == NavAction.Select
    check state.selected.isSome
  
  test "escape deselects":
    var state = newHexMapState(hexCoord(0, 0))
    state.selectCurrent()
    
    let event = KeyEvent(key: Key.Escape, rune: Rune(0), modifiers: ModNone)
    let result = handleKey(state, event, MapData())
    
    check result.consumed
    check result.action == NavAction.Deselect
    check state.selected.isNone
  
  test "tab cycles colonies":
    var state = newHexMapState(hexCoord(0, 0))
    let event = KeyEvent(key: Key.Tab, rune: Rune(0), modifiers: ModNone)
    let result = handleKey(state, event, MapData())
    
    check result.consumed
    check result.action == NavAction.CycleNextColony

suite "Colony cycling":
  test "find owned colonies":
    var systems = initTable[HexCoord, SystemInfo]()
    systems[hexCoord(0, 0)] = SystemInfo(
      id: 1,
      name: "Home",
      coords: hexCoord(0, 0),
      ring: 0,
      owner: some(0),
      isHomeworld: true
    )
    systems[hexCoord(1, 0)] = SystemInfo(
      id: 2,
      name: "Colony1",
      coords: hexCoord(1, 0),
      ring: 1,
      owner: some(0)
    )
    systems[hexCoord(0, 1)] = SystemInfo(
      id: 3,
      name: "Enemy",
      coords: hexCoord(0, 1),
      ring: 1,
      owner: some(1)
    )
    
    let mapData = MapData(
      systems: systems,
      maxRing: 2,
      viewingHouse: 0
    )
    
    let colonies = findOwnedColonies(mapData)
    check colonies.len == 2
    # Should be sorted by ring
    check colonies[0] == hexCoord(0, 0)  # Ring 0
    check colonies[1] == hexCoord(1, 0)  # Ring 1
  
  test "cycle to next colony":
    var state = newHexMapState(hexCoord(0, 0))
    let colonies = @[hexCoord(0, 0), hexCoord(1, 0), hexCoord(2, 0)]
    
    cycleToNextColony(state, colonies)
    check state.cursor == hexCoord(1, 0)
    
    cycleToNextColony(state, colonies)
    check state.cursor == hexCoord(2, 0)
    
    cycleToNextColony(state, colonies)
    check state.cursor == hexCoord(0, 0)  # Wraps around

suite "Viewport":
  test "viewport calculation":
    # Test the viewportForHex utility function
    let currentOrigin = hexCoord(0, 0)
    let targetHex = hexCoord(10, 10)
    
    # With small viewport, origin should shift to keep hex visible
    let newOrigin = viewportForHex(targetHex, 20, 10, currentOrigin, 2)
    
    # New origin should be different (viewport adjusted)
    # This is an indirect test - we just verify the function runs
    check newOrigin.q != currentOrigin.q or newOrigin.r != currentOrigin.r

suite "Symbol display":
  test "symbol types":
    check symbol(HexSymbol.Hub) == SymHub
    check symbol(HexSymbol.Colony) == SymColony
    check symbol(HexSymbol.Neutral) == SymNeutral
    check symbol(HexSymbol.Unknown) == SymUnknown
  
  test "ascii fallback":
    check symbol(HexSymbol.Hub, ascii = true) == AsciiHub
    check symbol(HexSymbol.Colony, ascii = true) == AsciiColony

echo "Running hex map tests..."
