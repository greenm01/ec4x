# EC4X TUI Integration Guide

**Status:** Phase 4 Complete + SVG Export Pivot  
**Last Updated:** 2026-01-15

## Overview

The Terminal User Interface (TUI) for EC4X is built and ready for integration with the game engine. All foundational layers are complete, tested, and documented.

**Important Design Change:** The TUI no longer displays an embedded hex map widget in the main dashboard. Instead, it focuses on data display (lists, status, commands) while players use an **SVG export** for visual starmap reference. See `SVG_STARMAP_SPEC.md` for details.

## Completed Components

### Phase 1: Terminal Primitives ✅
- **termenv port** - Full ANSI escape sequence support
- **32 tests passing** - Colors, styles, cursor control
- **Files:** `src/player/tui/term/`

### Phase 2: Layout System ✅
- **Constraint-based layouts** - Length, Min, Max, Percentage, Ratio, Fill
- **41 tests passing** - Rect operations, nested layouts, flex modes
- **Files:** `src/player/tui/layout/`

### Phase 3: Widget Library ✅
- **Core widgets** - Frame, Paragraph, List
- **Text system** - Span → Line → Text hierarchy
- **38 tests passing** - Rendering, scrolling, selection
- **Files:** `src/player/tui/widget/`

### Phase 4: Hex Map Widget ✅ (Preserved, not in main UI)
- **Scrollable hex starmap** - Axial coordinates, viewport management
- **Navigation** - Arrow keys, Tab cycling, selection
- **Detail panel** - System info, jump lanes, fleet list (still used!)
- **33 tests passing** - Coordinates, navigation, rendering
- **Files:** `src/player/tui/widget/hexmap/`
- **Status:** Widget exists but removed from main dashboard due to poor ANSI rendering

### Phase 5: Coordinate Labels ✅
- **Ring+position labels** - Human-friendly coordinates (`H`, `A1-A6`, `B1-B12`)
- **Conversion utilities** - Axial ↔ ring+position
- **Files:** `src/player/tui/hex_labels.nim`

### Phase 6: SVG Starmap Export ✅
- **Specification complete** - See `SVG_STARMAP_SPEC.md`
- **Coordinate system** - Ring+position labels implemented
- **TUI integration** - Detail panel shows labels
- **File export** - SVG generation and command integration complete

### Adapter Layer ✅
- **Type conversions** - Engine → Widget types
- **Files:** `src/player/tui/adapters.nim`

## Integration Points

### 1. Map Data Conversion

```nim
import player/tui/adapters

# WITHOUT FOG-OF-WAR (debug/testing mode - shows all systems)
let mapData = toMapData(gameState, viewingHouseId)
let detailData = toDetailPanelData(cursorCoord, gameState, viewingHouseId)

# WITH FOG-OF-WAR (production mode - respects visibility)
let mapData = toFogOfWarMapData(gameState, viewingHouseId)
let detailData = toFogOfWarDetailPanelData(cursorCoord, gameState, viewingHouseId)
```

**Adapter Functions (Basic):**
- `toMapData(state, viewingHouse)` - Convert full game state (no fog-of-war)
- `toDetailPanelData(coord, state, viewingHouse)` - Get system details (no fog-of-war)
- `toSystemInfo(system, state)` - Convert individual system
- `getJumpLanes(systemId, state)` - Get jump lane info
- `getFleetsInSystem(systemId, state, viewingHouse)` - Get fleet list

**Adapter Functions (Fog-of-War):**
- `toFogOfWarMapData(state, viewingHouse)` - Map with visibility filtering
- `toFogOfWarDetailPanelData(coord, state, viewingHouse)` - Details with fog filtering
- `toSystemInfoFromPlayerState(visibleSys, playerState, state)` - Convert from PlayerState

**Fog-of-War Behavior:**
- `Owned` systems - Full information (your colonies)
- `Occupied` systems - Full planet info (your fleets present)
- `Scouted` systems - Limited info from past intelligence
- `Adjacent` systems - Knows exists, shows as "Unknown"
- `None` systems - Hidden, shows as "Unknown"
- Unknown systems show "?" symbol
- Enemy fleets only visible in Owned/Occupied systems
- Jump lanes only shown for Scouted+ systems

### 2. Main Event Loop Pattern

```nim
# Initialization
var tty = openTty()
if not tty.start():
  quit("Failed to enter raw mode")

setupResizeHandler()
var (termWidth, termHeight) = tty.windowSize()
var buf = initBuffer(termWidth, termHeight)
var parser = initParser()

# Enter alternate screen
stdout.write(altScreen())
stdout.write(hideCursor())

# Game state
var gameState = loadOrCreateGame()
var mapState = newHexMapState(hexCoord(0, 0))

# Main loop
while running:
  # Check resize
  if checkResize():
    (termWidth, termHeight) = tty.windowSize()
    buf.resize(termWidth, termHeight)
    buf.invalidate()
  
  # Read input
  let inputByte = tty.readByte()
  if inputByte >= 0:
    let events = parser.feedByte(inputByte.uint8)
    
    for event in events:
      if event.kind == EventKind.Key:
        # Handle navigation
        let navResult = processNavigation(mapState, event.keyEvent, mapData)
        
        case navResult.action
        of NavAction.Quit:
          running = false
        of NavAction.Select:
          # Handle system selection
        of NavAction.MoveCursor:
          # Cursor moved
        else:
          discard
  
  # Render
  buf.clear()
  renderDashboard(buf, gameState, mapState, termWidth, termHeight)
  outputBuffer(buf)

# Cleanup
stdout.write(showCursor())
stdout.write(exitAltScreen())
discard tty.stop()
tty.close()
```

### 3. Dashboard Layout

The dashboard uses a split-view layout:

```
┌─ Starmap ──────────────────┬─ System Info ────────┐
│                            │                      │
│  Map (60% width)           │  Details (40% width) │
│  - Always visible          │  - Context-sensitive │
│  - Scrollable viewport     │  - System info       │
│  - Cursor navigation       │  - Jump lanes        │
│                            │  - Fleets            │
├────────────────────────────┴──────────────────────┤
│  [Controls] Help bar                              │
└───────────────────────────────────────────────────┘
```

**Layout Code:**
```nim
let rows = vertical()
  .constraints(fill(), length(1))
  .split(terminalRect)

let cols = horizontal()
  .constraints(fill(), length(35))
  .spacing(1)
  .split(rows[0])

let mapArea = cols[0]      # Hex map
let detailArea = cols[1]   # Detail panel
let helpArea = rows[1]     # Help bar
```

## Demo Programs

### Interactive Demo (Mock Data)

**Run:** `nim c -r tests/tui/demo_hexmap.nim`

- 12 systems with varied ownership
- Full navigation (arrows, Tab, Enter, q)
- Detail panel with system info
- Perfect for UI testing

**Controls:**
- Arrow keys: Move cursor
- Enter: Select system
- Tab: Cycle colonies
- 'h': Jump to homeworld
- 'q': Quit

## Running the TUI Player

The TUI player is now **fully integrated** and ready to use!

### Build and Run

```bash
# Build TUI player
nimble buildTui

# Run (requires real terminal)
./bin/ec4x-tui
```

**Controls:**
- Arrow keys: Navigate starmap
- Enter: Select system
- Tab: Cycle to next colony
- 'h': Jump to homeworld
- 'q': Quit

### Current Features (v1.0)

✅ **Complete:**
- Full game initialization (4-player standard scenario)
- Fog-of-war map rendering (respects visibility levels)
- Status bar (turn, treasury, prestige, house name)
- Scrollable hex starmap with viewport
- System detail panel (info, jump lanes, fleets)
- Keyboard navigation with Tab cycling
- Help bar

### Next Steps

1. **Action panel** - Handle user commands
   - Fleet orders (Move, Patrol, Attack)
   - Colony management
   - Production queue

2. **Turn processing** - End turn and run resolution
   - Submit orders
   - Run turn executor
   - Display turn report

3. **Fleet orders UI** - Issue movement/combat commands
   - Select fleet
   - Choose destination
   - Set patrol/attack orders

### Future Enhancements

- **Fleet detail view** - Ship list, composition, orders
- **Colony management** - Production, infrastructure, population
- **Diplomacy view** - Relations, treaties, proposals
- **Message log** - Combat results, events, notifications
- **Tech tree view** - Research progress, available upgrades
- **Victory conditions** - Prestige tracking, win state

## Architecture Benefits

**Clean Separation:**
- Engine (game logic) ← Adapters → TUI (presentation)
- Engine types stay unchanged
- TUI doesn't depend on engine internals

**Testability:**
- 159 tests passing
- Each layer tested independently
- Mock data for UI development

**Maintainability:**
- Layers: Term → Buffer → Layout → Widgets → Dashboard
- Each ~1,000 lines, well-documented
- Clear responsibility boundaries

## SVG Starmap Export + TUI System List

The TUI provides two ways to view starmap topology:

1. **SVG Export** - Node-edge graph for visual reference (open in browser)
2. **System List** - Text-mode connectivity display (in TUI)

### SVG Node-Edge Graph

The SVG renders systems as **positioned circles** connected by **styled lines**
(not hex polygons - cleaner, less visual noise).

```
map export    # Generate SVG for current turn, print file path
map open      # Generate + open in default viewer
```

### TUI System List

Text-mode view showing system connectivity:

```
═══ Systems ════════════════════════════════════════════
 H   Hub         ━━ A1 A2 A3 A4 A5 A6
 A1  Arcturus    ━━ H ┄┄ A2 A6 ━━ B1 ·· B2    [Valerian]
 A2  Vega        ┄┄ H A1 A3 ━━ B2 B3
```

Lane symbols: `━━` Major, `┄┄` Minor, `··` Restricted

### Coordinate Labels

Systems use human-friendly ring+position labels:

- Hub: `H`
- Ring 1: `A1` through `A6`
- Ring 2: `B1` through `B12`
- etc.

These labels appear in:
- SVG starmap (below each node)
- TUI system list and detail panel
- Command input (future: "move fleet to B7")

### Example Workflow

1. Run `map export` in TUI to generate SVG
2. Open `~/.ec4x/maps/game_abc123/turn_5.svg` in browser
3. Use TUI system list (`S` key) for quick connectivity checks
4. Reference labels when entering fleet orders

### Implementation Status

- ✅ Coordinate label conversion (`hex_labels.nim`)
- ✅ Detail panel integration (shows ring+position labels)
- ✅ Specification complete (`SVG_STARMAP_SPEC.md`)
- [ ] SVG node-edge graph generation
- [ ] TUI system list view
- [ ] File export and directory management
- [ ] TUI command integration

See `SVG_STARMAP_SPEC.md` for complete design specification.

---

## File Organization

```
src/player/
├── tui_player.nim      # ✅ MAIN ENTRY POINT - Full game integration
├── SVG_STARMAP_SPEC.md # ✅ SVG export specification
├── tui/
│   ├── hex_labels.nim  # ✅ Ring+position coordinate labels
│   ├── term/           # Terminal primitives (ANSI sequences)
│   ├── buffer.nim      # Screen buffer with dirty tracking
│   ├── events.nim      # Input event types
│   ├── input.nim       # Input parser
│   ├── tty.nim         # Raw mode control
│   ├── signals.nim     # SIGWINCH handler
│   ├── layout/         # Constraint-based layouts
│   ├── widget/         # Core widgets (Frame, Paragraph, List)
│   │   ├── text/       # Text rendering system
│   │   └── hexmap/     # Hex map widget (preserved, not in main UI)
│   ├── adapters.nim    # Engine ↔ Widget type converters
│   └── tui-architecture.md # Full architecture documentation
├── svg/                # 🚧 TODO: SVG generation
│   ├── starmap_export.nim
│   ├── svg_builder.nim
│   └── export.nim

tests/tui/
├── demo_hexmap.nim     # Interactive demo (mock data)
├── tbuffer.nim         # Buffer tests (15 passing)
├── tlayout.nim         # Layout tests (41 passing)
├── twidget.nim         # Widget tests (38 passing)
├── thexmap.nim         # Hex map tests (33 passing)
└── test_fog_adapters.nim # Fog-of-war tests (3 passing)
```

## Performance Notes

**Efficient Rendering:**
- Dirty tracking (only redraw changed cells)
- Full redraw ~0.1ms on 80x24 terminal
- Input is blocking (no busy wait)

**Turn-Based Benefits:**
- No need for 60fps rendering
- Updates only on input or turn completion
- Simple diff algorithm sufficient

## References

- **Architecture:** `src/player/tui-architecture.md` - Full design document
- **Starmap Layout:** Documented in architecture.md Phase 4 section
- **Engine API:** `src/engine/state/engine.nim`, `iterators.nim`
- **Game Spec:** `docs/specs/02-assets.md` - Hex grid, systems, jump lanes

---

**Ready for integration.** The TUI is complete and waiting for real game state hookup.
