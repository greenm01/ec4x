# EC4X Terminal User Interface (TUI) Architecture

## Project Overview

Terminal-based user interface for EC4X, a 4X strategy game written in Nim. The TUI uses State-Action-Model (SAM) pattern with immediate-mode rendering, built on termenv-style terminal primitives with constraint-based layouts.

## Core Architecture: SAM Pattern

### State
- **Game State**: Units, resources, map, turn number, diplomatic relations, etc.
- **UI State**: Current focus, selection indices, open menus, scroll positions
- **Single Source of Truth**: All state lives in one place, no distributed state

### Actions
- **Player Commands**: Move unit, end turn, open menu, select city, etc.
- **Pure Proposals**: Actions are data structures representing intent, no side effects
- **Examples**: `MoveUnit(unitId, destination)`, `EndTurn()`, `OpenMenu(menuType)`

### Model
- **Validates Actions**: Checks if action is legal given current state
- **Computes Next State**: Applies game rules to produce new state
- **Handles All Actions**: Both player commands and AI decisions
- **Pure Function**: `(action, currentState) → nextState`

### View
- **Pure Rendering Function**: `(state) → frame`
- **Stateless**: Widgets don't maintain internal state
- **Frame Structure**: 2D grid of cells, each containing character and style

### Main Loop
```nim
while gameRunning:
  let frame = view(gameState, uiState)
  display(frame)
  let input = readInput()
  let action = parseCommand(input, uiState)
  gameState = model.present(action, gameState)
```

## Benefits of SAM for EC4X

- **Replay/Undo**: Store state history, trivial to implement
- **Save/Load**: State serialization is straightforward
- **AI Integration**: AI actions use same model.present() as player
- **Testing**: Pure functions are easy to test
- **Debugging**: State at any point is inspectable
- **Deterministic**: Same state + action = same result

---

## Terminal Layer Stack

### Foundation: termenv Port (`src/player/tui/term/`)

**✅ IMPLEMENTED** - Ported from Go's termenv library.

**Module Structure:**
```
term/
├── term.nim                 # Main export module
├── types/
│   ├── core.nim             # Profile enum, Color variants, error types
│   ├── style.nim            # Style type definition
│   └── screen.nim           # EraseMode, MouseMode, CursorStyle enums
├── constants/
│   ├── escape.nim           # ESC, CSI, OSC, ST, SGR codes
│   ├── ansi.nim             # 256-color palette with hex lookup table
│   └── sequences.nim        # Screen/cursor sequence templates
├── color.nim                # Color parsing, conversion, sequence generation
├── style.nim                # Fluent builder API for text styling
├── screen.nim               # Screen/cursor operations (functions)
├── output.nim               # Output type with terminal operations
└── platform.nim             # Profile detection from environment variables
```

**Design Decisions:**
- **Data-oriented**: Types separated from logic (types/ vs implementation files)
- **Object variants**: Color uses discriminated unions instead of interfaces
- **UFCS throughout**: All functions use Uniform Function Call Syntax
- **No external dependencies**: Uses only Nim stdlib (`std/streams`, `std/unicode`, `std/terminal`)
- **Modular**: Largest file is ~380 lines, clean separation of concerns

#### ✅ Capability Detection
- **Profile detection** via environment variables (`COLORTERM`, `TERM`, `NO_COLOR`)
- **Color profiles**: `TrueColor` (24-bit), `Ansi256` (8-bit), `Ansi` (4-bit), `Ascii` (none)
- **Automatic degradation**: Colors converted to terminal's capability level
- **Terminal size**: Uses `std/terminal.terminalWidth/Height()`
- ⚠️ **Resize events**: SIGWINCH handler not yet implemented

#### ✅ ANSI Sequence Generation
- **Cursor control**: Positioning, movement, save/restore, visibility, styles
- **Color sequences**: Foreground/background for all color types
- **Text attributes**: Bold, faint, italic, underline, blink, reverse, crossout, overline
- **Screen operations**: Clearing, scrolling, line operations
- **Alternate screen**: Enter/exit with proper cleanup sequences

#### ✅ Styled Output
- **Fluent API**: Immutable builder pattern for text styling
  ```nim
  output.newStyle("Commander").bold().fg("#0000ff").bg(Red)
  ```
- **Automatic degradation**: Colors downgrade based on profile
- **UTF-8 support**: Full Unicode via `std/unicode`
- **Width calculation**: Visual width calculation for layout

---

### Screen Management (`src/player/tui/buffer.nim`)

**❌ NOT YET IMPLEMENTED** - Planned for Phase 1.5

#### Double Buffering
- **Current Buffer**: What's displayed on screen
- **Next Buffer**: Frame being constructed
- **Diff Algorithm**: Compare buffers, emit only changes
- **Reduces Flicker**: Minimizes terminal output

#### Screen Buffer Structure
```nim
type
  Cell = object
    rune: Rune        # UTF-8 character
    fg: Color         # Foreground color (from term/types/core.nim)
    bg: Color         # Background color
    attrs: set[StyleAttr]  # From term/types/style.nim
  
  ScreenBuffer = object
    width: int
    height: int
    cells: seq[Cell]  # width * height array
```

**Note**: This is separate from `term/types/style.nim`'s `Style` type. `Style` is for building styled strings, while `Cell` is for the screen buffer grid.

#### Diff/Patch Algorithm
- Simple cell-by-cell comparison (sufficient for turn-based game)
- Group consecutive changes for efficiency
- Track cursor position to minimize movement
- Only emit differences to terminal using `term/` primitives

#### Alternate Screen Control
- Use `term/screen.altScreen()` on startup
- Game doesn't pollute terminal history
- Use `term/screen.exitAltScreen()` on quit
- Handle cleanup on crashes/signals

---

### Input Handling (`src/player/tui/input.nim`)

**❌ NOT YET IMPLEMENTED** - Planned for Phase 1.5

#### Keyboard Input
- Blocking read from stdin
- Raw mode setup/teardown using termios
- Parse escape sequences for special keys
- Arrow keys: `←↑→↓`
- Function keys: `F1-F12`
- Modifiers: `Ctrl`, `Shift`, `Alt` combinations
- Character input: letters, numbers, symbols

#### Command Parsing
- Map key presses to game actions
- Context-sensitive bindings (e.g., 'm' = move unit when unit selected)
- Modal input if desired (command mode vs normal mode)
- Help overlay showing available commands

#### Input Processing
```nim
proc parseCommand(input: Key, uiState: UIState): Action =
  case uiState.mode:
  of NormalMode:
    case input:
    of Key_M: MoveUnit(uiState.selectedUnit)
    of Key_E: EndTurn()
    of Key_Escape: OpenMenu(MainMenu)
    # ...
  of MenuMode:
    # Handle menu navigation
```

---

### Layout System

#### Constraint-Based Layout Tree

Start with simple fixed/flex model, add cassowary if needed.

#### Layout Primitives
- **Fixed Size**: Specified width/height in cells
- **Flex Size**: Grows/shrinks to fill available space
- **Min/Max Constraints**: Bounds on flexible sizing
- **Percentage**: Size relative to parent
- **Direction**: Horizontal or vertical splits

#### Layout Tree Structure
```nim
type
  LayoutConstraint = enum
    Fixed, Flex, Percentage, Min, Max
  
  LayoutNode = object
    constraint: LayoutConstraint
    value: int  # size value, depends on constraint
    direction: Direction  # Horizontal or Vertical
    children: seq[LayoutNode]
```

#### Layout Examples
```
┌─────────────────────────────────┐
│ Status Bar (Fixed: 1 row)       │
├─────────────┬───────────────────┤
│             │                   │
│ Map View    │ Unit Info         │
│ (Flex)      │ (Fixed: 30 cols)  │
│             │                   │
├─────────────┴───────────────────┤
│ Message Log (Fixed: 5 rows)     │
└─────────────────────────────────┘
```

#### Constraint Solving
- **Simple Approach**: Two-pass algorithm (measure, then layout)
- **Cassowary Integration**: If complex constraints needed
  - Use existing Nim cassowary library if available
  - Otherwise, port minimal solver
  - Expose simplified API (like ratatui)

#### Responsive Layout
- Recalculate on terminal resize
- Minimum terminal size enforcement (e.g., 80x24)
- Graceful degradation for small terminals

---

## Widget System

### Design Principles

#### Immediate-Mode Rendering
- Widgets are pure functions: `(state, bounds) → renderedCells`
- No widget lifecycle (init, update, destroy)
- No internal widget state
- Render entire UI every frame (diff/patch optimizes output)

#### Widget Function Signature
```nim
proc renderWidget(state: GameState, bounds: Rect): seq[Cell]
```

#### Composition
- Widgets can call other widgets
- Layout system provides bounds for each widget
- Parent widgets compose child widgets

---

### Core Widget Types

#### Panel/Border Widget
- Draws box around content area
- Uses UTF-8 box drawing characters
- Supports title text
- Single or double line styles
```
╔═══════════════╗
║ Panel Title   ║
║               ║
║   Content     ║
║               ║
╚═══════════════╝
```

#### Text Display Widget
- Renders text with word wrapping
- Supports styled text (colors, bold, etc.)
- Scrollable for long content
- Alignment options (left, center, right)

#### List Widget
- Vertical list of items
- Highlighted selection
- Keyboard navigation (up/down, page up/down)
- Optional item numbers/bullets
- Scrolling viewport

#### Status Display Widget
- Key-value pairs
- Resource counters
- Progress bars
- Icon + text combinations

#### Progress Bar Widget
- Horizontal bar showing completion
- Configurable characters (e.g., `[=====>    ]`)
- Percentage display
- Optional label

#### Menu Widget
- Vertical or horizontal menu
- Highlighted selection
- Nested submenus
- Keyboard shortcuts displayed

---

### EC4X-Specific Widgets

#### Map View Widget
- Primary game display
- Grid-based map representation
- Unit symbols with faction colors
- Terrain glyphs
- Fog of war rendering
- Selection highlight
- Movement range indicators

#### Unit List Widget
- Scrollable list of units
- Shows unit type, location, status
- Selection highlight
- Color-coded by faction
- Filter/sort options

#### City Info Panel
- City name and population
- Production queue
- Resource output
- Building list
- Garrison units

#### Resource Panel
- Current resource amounts
- Income/expenses per turn
- Resource icons with counts
- Warning colors for shortages

#### Command Palette
- Context-sensitive commands
- Keyboard shortcuts shown
- Categories/grouping
- Quick filter/search

#### Message Log
- Recent game events
- Color-coded by type (combat, diplomacy, etc.)
- Scrollable history
- Timestamp/turn number

#### Diplomacy View
- List of known civilizations
- Relationship status
- Treaty information
- Communication options

---

### Visual Design Elements

#### UTF-8 Glyphs for Rich Display

**Box Drawing Characters**
```
Single: ─│┌┐└┘├┤┬┴┼
Double: ═║╔╗╚╝╠╣╦╩╬
Mixed:  ╒╕╘╛╞╡╤╧╪
```

**Block Elements**
```
Full:    █
Shaded:  ▓ ▒ ░
Partial: ▀ ▄ ▌ ▐
```

**Geometric Shapes**
```
Circles:  ● ○ ◉ ◌
Squares:  ■ □ ▪ ▫
Diamonds: ◆ ◇ ⬥
Triangles: ▲ △ ▼ ▽
```

**Directional Arrows**
```
Basic: ← ↑ → ↓
Heavy: ⬅ ⬆ ➡ ⬇
Curved: ↰ ↱ ↲ ↳
```

**Game-Specific Symbols**
```
Military: ⚔ 🗡 ⚓ ✈
Terrain:  ⛰ 🏔 🌊 🌲
Cities:   ⬢ ⬡ 🏛
Resources: ⛏ 🌾 ⚙
```

#### EC4X Visual Examples

**Terrain Representation**
```
Plains:    ░░  (light shade)
Hills:     ▒▒  (medium shade)
Mountains: ▓▓  (dark shade)
Water:     ≈≈  (wave)
Forest:    ♠♠  (tree)
Desert:    ··  (sparse)
```

**Unit Representation**
```
Infantry:  ●  (circle, faction colored)
Cavalry:   ◆  (diamond, faction colored)
Artillery: ■  (square, faction colored)
Navy:      ▲  (triangle, faction colored)
Air:       ✈  (plane, faction colored)
```

**City Representation**
```
Capital:   ⬢  (large hex, faction colored)
City:      ⬡  (small hex, faction colored)
Town:      ○  (circle, faction colored)
```

**Status Indicators**
```
Selected:     → ●  (arrow + unit)
Can Move:     ● (bright)
Exhausted:    ◌ (dim/hollow)
In Combat:    ⚔●
Fortified:    ▣
Damaged:      ◍ (half-filled)
```

#### ANSI Color Usage

**Faction Colors**
- Each civilization assigned a distinct color
- Used consistently across all UI elements
- Example: Blue faction units are all blue

**Terrain Colors**
- Water: Blue/Cyan
- Forest: Green
- Desert: Yellow/Brown
- Mountains: Gray/White
- Plains: Light Green

**UI Element Colors**
- Selection: Bright Yellow or Inverse Video
- Warnings: Red
- Success: Green
- Info: Cyan
- Neutral: White/Gray

**Status Colors**
- Healthy: Green
- Damaged: Yellow
- Critical: Red
- Exhausted: Gray/Dim

#### Style Attributes
- **Bold**: Emphasis, selected items
- **Dim**: Inactive or exhausted units
- **Italic**: Flavor text, quotes
- **Underline**: Links, interactive elements
- **Inverse**: Strong selection highlight

---

## Implementation Strategy

### Phase 1: Terminal Foundation

**Status**: ✅ **Primitive Layer Complete**, ⚠️ **Buffer/Input Pending**

#### ✅ 1. Terminal Primitives (`term/`) - COMPLETE
- ✅ **Capability Detection**
  - ✅ Profile detection via environment variables
  - ✅ Color support: TrueColor, ANSI256, ANSI, Ascii
  - ✅ Terminal size via `std/terminal`
  - ❌ SIGWINCH handler (planned)

- ✅ **ANSI Output**
  - ✅ Cursor movement functions
  - ✅ Color setting functions  
  - ✅ Style attribute functions
  - ✅ Screen clearing

- ✅ **Styled Text API**
  - ✅ Fluent builder pattern
  - ✅ Automatic color degradation
  - ✅ UTF-8 support with width calculation

- ✅ **Alternate Screen**
  - ✅ Enter/exit sequences
  - ⚠️ Cleanup on signals (planned)

#### ❌ 2. Screen Buffer (`buffer.nim`) - PLANNED
- Cell structure definition
- Buffer allocation
- Basic diff algorithm
- Rendering pipeline using `term/` primitives

#### ❌ 3. Input Reading (`input.nim`) - PLANNED
- Blocking stdin read
- Raw mode setup/teardown
- Basic key parsing
- Escape sequence handling

**Current Deliverable**: Can generate all ANSI sequences, style text with automatic degradation  
**Next Deliverable**: Can render frames and read keyboard input

**Tests**: 32 tests passing across 4 test files + visual color chart demo

---

### Phase 2: Layout System

**Goal**: Flexible panel layout management

1. **Layout Tree Structure**
   - Define layout node types
   - Tree building API
   - Bounds calculation

2. **Simple Constraints**
   - Fixed sizing
   - Flex sizing
   - Min/max enforcement

3. **Layout Algorithm**
   - Two-pass layout (measure, arrange)
   - Handle parent/child relationships
   - Distribute available space

4. **Layout Testing**
   - Unit tests for common layouts
   - Edge cases (very small terminals)
   - Resize behavior

**Deliverable**: Can define and render multi-panel layouts

---

### Phase 3: Core Widget Library

**Goal**: Reusable widget implementations

1. **Panel/Border Widget**
   - Box drawing
   - Title rendering
   - Content area calculation

2. **Text Widget**
   - Word wrapping
   - Style support
   - Scrolling

3. **List Widget**
   - Item rendering
   - Selection highlight
   - Scroll viewport
   - Keyboard navigation

4. **Status Display**
   - Key-value formatting
   - Icon + text layout
   - Progress bars

5. **Menu Widget**
   - Vertical/horizontal layout
   - Selection handling
   - Shortcut display

**Deliverable**: Widget library that can build complex UIs

---

### Phase 4: Game-Specific Widgets

**Goal**: EC4X gameplay widgets

1. **Map Widget**
   - Grid rendering
   - Unit display
   - Terrain glyphs
   - Selection indicators
   - Fog of war

2. **Unit Info Panel**
   - Unit details
   - Action icons
   - Status indicators

3. **City Panel**
   - City stats
   - Production queue
   - Building list

4. **Resource Display**
   - Resource counters
   - Income/expense
   - Warnings

5. **Message Log**
   - Event history
   - Color coding
   - Scrolling

**Deliverable**: Complete game UI widgets

---

### Phase 5: SAM Integration

**Goal**: Connect UI to game logic

1. **State Structure**
   - Define complete game state
   - Define UI state
   - Serialization support

2. **Action Definitions**
   - All player commands
   - AI action types
   - Validation rules

3. **Model Implementation**
   - Action validation
   - State transitions
   - Game rules enforcement

4. **View Function**
   - Render complete UI from state
   - Handle all display modes
   - Transition animations

5. **Input Mapping**
   - Key bindings
   - Command parsing
   - Context-sensitive input

6. **Main Loop**
   - Game loop integration
   - Turn processing
   - AI execution

**Deliverable**: Playable game with complete TUI

---

### Phase 6: Polish & Features

**Goal**: Refinement and quality of life

1. **Performance**
   - Profile rendering
   - Optimize diff algorithm
   - Reduce allocations

2. **Help System**
   - Command help overlay
   - Tutorial messages
   - Tooltips

3. **Configuration**
   - Key binding customization
   - Color scheme selection
   - UI layout preferences

4. **Accessibility**
   - High contrast mode
   - Colorblind-friendly palettes
   - Screen reader considerations

5. **Testing**
   - Unit tests for widgets
   - Integration tests
   - Playtesting

**Deliverable**: Polished, feature-complete TUI

---

## Technical Implementation Notes

### Platform Support

**Primary Target**: Linux (CachyOS)
- Modern terminal with UTF-8 support
- Truecolor expected
- Standard UNIX terminal behavior

**Secondary Target**: macOS
- Similar to Linux
- Terminal.app and iTerm2 support

**Windows**: Not priority
- Would require Windows Console API handling
- Or restrict to WSL/modern Windows Terminal

### Performance Considerations

**Turn-Based Game Benefits**
- Updates only on player input or turn completion
- No need for 60fps rendering
- Simple diff algorithm sufficient
- Can afford some inefficiency

**Optimization Opportunities**
- Cache layout calculations
- Dirty region tracking (if needed)
- Batch ANSI output sequences
- Avoid unnecessary allocations

### Error Handling

**Terminal Issues**
- Handle missing terminal features gracefully
- Fallback to simpler rendering if needed
- Clear error messages for unsupported terminals

**Game State**
- Invalid actions rejected by model
- State validation on load
- Corruption detection

### Testing Strategy

**Unit Tests**
- Pure functions (widgets, layout, model) are easily testable
- Mock terminal for output testing
- Synthetic input for command parsing

**Integration Tests**
- Complete render cycles
- Input → Action → State → Render pipeline
- Save/load functionality

**Manual Testing**
- Different terminal types
- Various terminal sizes
- Edge cases (very small terminals)
- Long play sessions

### Development Tools

**Debugging**
- State inspector (dump current state)
- Action history replay
- Frame-by-frame rendering
- Performance profiling

**Hot Reload**
- Nim's compile times allow quick iteration
- Save state, recompile, restore state

---

## Example Game Flow

### Startup
1. Initialize terminal (raw mode, alternate screen)
2. Detect capabilities
3. Load or create game state
4. Enter main loop

### Main Loop Iteration
```nim
while gameRunning:
  # Render current state
  let frame = view(gameState, uiState)
  let diff = diffBuffers(currentBuffer, frame)
  emitDiff(diff)
  currentBuffer = frame
  
  # Wait for input
  let key = readKey()
  
  # Parse command
  let action = parseCommand(key, uiState)
  
  # Update state
  let result = model.present(action, gameState)
  if result.valid:
    gameState = result.newState
    
  # Check for game end
  if action is QuitGame:
    gameRunning = false
```

### Player Turn Example
1. Player sees map with units
2. Selects unit with arrow keys + Enter
3. Presses 'M' for move command
4. Map shows valid move destinations
5. Selects destination with arrow keys + Enter
6. Model validates move, updates state
7. View re-renders with unit in new position
8. Player continues or presses 'E' to end turn

### AI Turn Example
1. Player ends turn
2. Model switches to AI faction
3. AI generates action (using same Action types)
4. Model.present(aiAction, state) updates state
5. View renders AI moves (optional animation)
6. Repeat for each AI faction
7. Return to player turn

### Save/Load
- **Save**: Serialize gameState to file
- **Load**: Deserialize file to gameState
- Action history can be saved for replay

---

## Code Organization

### Module Structure (Actual Implementation)

```
src/player/
├── tui/
│   ├── term/                      # ✅ Phase 1: Terminal primitives (termenv port)
│   │   ├── term.nim               # Main export module
│   │   ├── types/
│   │   │   ├── core.nim           # Profile, Color variants, errors
│   │   │   ├── style.nim          # Style type
│   │   │   └── screen.nim         # Screen operation enums
│   │   ├── constants/
│   │   │   ├── escape.nim         # ANSI escape codes
│   │   │   ├── ansi.nim           # 256-color palette
│   │   │   └── sequences.nim      # Escape sequence templates
│   │   ├── color.nim              # Parsing, conversion
│   │   ├── style.nim              # Fluent builder API
│   │   ├── screen.nim             # Screen/cursor operations
│   │   ├── output.nim             # Output type
│   │   └── platform.nim           # Profile detection
│   ├── buffer.nim                 # ❌ Phase 1.5: Screen buffer & diff
│   ├── input.nim                  # ❌ Phase 1.5: Keyboard input
│   ├── layout/                    # ❌ Phase 2: Layout system
│   │   ├── constraint.nim
│   │   ├── tree.nim
│   │   └── solver.nim
│   ├── widget/                    # ❌ Phase 3: Core widgets
│   │   ├── core.nim
│   │   ├── panel.nim
│   │   ├── text.nim
│   │   ├── list.nim
│   │   ├── menu.nim
│   │   └── progress.nim
│   ├── game_widgets/              # ❌ Phase 4: Game-specific widgets
│   │   ├── map.nim
│   │   ├── unit_info.nim
│   │   ├── city.nim
│   │   ├── resources.nim
│   │   └── message_log.nim
│   └── tui-architecture.md        # This document
├── sam/                           # ❌ Phase 5: SAM pattern implementation
│   ├── state.nim
│   ├── action.nim
│   ├── model.nim
│   └── view.nim
└── player.nim                     # Entry point (will integrate TUI)
```

### Current Implementation Status

**✅ Completed:**
- Terminal primitives layer (`tui/term/`)
- 32 passing tests across 4 test suites
- Visual color chart demo
- Full termenv feature parity

**⚠️ In Progress:**
- Documentation updates (this file)

**❌ Not Started:**
- Screen buffer & diffing
- Input handling
- Layout system
- Widget library
- SAM integration

### Key Type Definitions

```nim
# term/types/core.nim (✅ IMPLEMENTED)
type
  Profile {.pure.} = enum
    TrueColor = 0  # 24-bit RGB
    Ansi256 = 1    # 8-bit (256 colors)
    Ansi = 2       # 4-bit (16 colors)
    Ascii = 3      # No color support
  
  AnsiColor = distinct range[0..15]
  Ansi256Color = distinct range[0..255]
  
  RgbColor = object
    r, g, b: uint8
  
  ColorKind {.pure.} = enum
    None, Ansi, Ansi256, Rgb
  
  Color = object  # Discriminated union
    case kind: ColorKind
    of ColorKind.None: discard
    of ColorKind.Ansi: ansi: AnsiColor
    of ColorKind.Ansi256: ansi256: Ansi256Color
    of ColorKind.Rgb: rgb: RgbColor

# term/types/style.nim (✅ IMPLEMENTED)
type
  StyleAttr {.pure.} = enum
    Bold, Faint, Italic, Underline, Blink, Reverse, CrossOut, Overline
  
  Style = object
    profile: Profile
    text: string
    fg, bg: Color
    attrs: set[StyleAttr]

# buffer.nim (❌ NOT YET IMPLEMENTED)
type
  Cell = object
    rune: Rune
    fg, bg: Color           # From term/types/core.nim
    attrs: set[StyleAttr]   # From term/types/style.nim
  
  ScreenBuffer = object
    width, height: int
    cells: seq[Cell]

# layout/tree.nim
type
  Constraint = object
    case kind: ConstraintKind
    of Fixed: size: int
    of Flex: weight: float
    of Percentage: percent: float
    of Min, Max: limit: int
  
  LayoutNode = object
    constraint: Constraint
    direction: Direction
    children: seq[LayoutNode]
  
  Rect = object
    x, y, width, height: int

# widget/core.nim (❌ NOT YET IMPLEMENTED)
type
  RenderContext = object
    buffer: var ScreenBuffer
    bounds: Rect
  
  Widget = proc(ctx: var RenderContext, state: GameState)

# sam/state.nim
type
  Position = object
    x, y: int
  
  UnitId = distinct int
  CityId = distinct int
  
  Unit = object
    id: UnitId
    type: UnitType
    faction: Faction
    position: Position
    health: int
    movement: int
  
  GameState = object
    turn: int
    units: Table[UnitId, Unit]
    cities: Table[CityId, City]
    map: Map
    factions: seq[Faction]
    currentFaction: Faction
  
  UIState = object
    selectedUnit: Option[UnitId]
    menuOpen: bool
    scrollPosition: int
    mode: UIMode

# sam/action.nim
type
  Action = object
    case kind: ActionKind
    of MoveUnit:
      unitId: UnitId
      destination: Position
    of AttackTarget:
      attackerId: UnitId
      targetId: UnitId
    of EndTurn: discard
    of OpenMenu:
      menuType: MenuType
    # ... more action types

# sam/model.nim
type
  ModelResult = object
    valid: bool
    newState: GameState
    message: string

proc present(action: Action, state: GameState): ModelResult
```

---

## Future Enhancements

### Advanced Features
- Mouse support (clicking units, dragging)
- Animation between states (smooth unit movement)
- Sound effects (via external player)
- Network multiplayer (separate concern)

### UI Improvements
- Minimap widget
- Detailed tooltips on hover
- Context menus
- Undo/redo support
- Replay viewer

### Performance
- Incremental rendering (render only changed widgets)
- Background AI computation
- State diff for minimal saves

### Accessibility
- Screen reader support
- Colorblind modes
- High contrast themes
- Font size scaling (if terminal supports)

---

## Conclusion

This architecture provides:
- **Clean separation**: SAM pattern keeps logic distinct
- **Testability**: Pure functions throughout
- **Maintainability**: Immediate-mode simplifies reasoning
- **Flexibility**: Constraint-based layouts adapt to terminal size
- **Rich visuals**: UTF-8 glyphs + ANSI colors
- **Inline implementation**: No external library maintenance

The approach is tailored specifically for EC4X's needs as a turn-based 4X strategy game, avoiding unnecessary complexity while providing all required functionality.
