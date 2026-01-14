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

**✅ IMPLEMENTED** - Phase 1.5 complete (2026-01-14)

#### Dirty Tracking (tcell-style)
- Each cell stores both **current** and **last** state
- Dirty flag: `lastStr != currStr || lastStyle != currStyle`
- Only dirty cells are re-rendered
- More efficient than full double-buffering for turn-based games

#### Screen Buffer Structure (Actual Implementation)
```nim
type
  CellStyle = object
    fg, bg: Color                 # From term/types/core.nim
    attrs: set[StyleAttr]         # From term/types/style.nim
  
  Cell = object
    currStr, lastStr: string      # Current vs last grapheme (for dirty check)
    currStyle, lastStyle: CellStyle
    width: int                    # Display width (1 or 2 for wide chars)
    locked: bool                  # Prevent redraw (for graphics regions)
  
  CellBuffer = object
    w, h: int
    cells: seq[Cell]              # Flat array: w * h
```

**Features Implemented:**
- ✅ Wide character support (East Asian, emoji width=2)
- ✅ Cell locking for special regions
- ✅ Dirty tracking with O(1) checks
- ✅ Bounds checking on all operations
- ✅ Resize with content preservation
- ✅ Fill and clear operations

**Test Coverage:**
- 15 unit tests passing (`tests/tui/tbuffer.nim`)
- Tests: init, put/get, dirty tracking, locking, resize, wide chars

---

### Input Handling (`src/player/tui/input.nim`, `tty.nim`, `events.nim`, `signals.nim`)

**✅ IMPLEMENTED** - Phase 1.5 complete (2026-01-14)

#### TTY Control (`tty.nim`)
- ✅ Raw mode via termios (disables line buffering, echo, signals)
- ✅ Terminal state save/restore
- ✅ Window size query via ioctl (TIOCGWINSZ)
- ✅ Fallback to COLUMNS/LINES env vars
- ✅ Byte reading (blocking)

#### Event System (`events.nim`)
- ✅ Unified `Event` type: Key, Resize, Error
- ✅ `Key` enum: 50+ keys (arrows, F1-F20, Ctrl-A through Z, etc.)
- ✅ `ModMask`: Shift, Ctrl, Alt, Meta
- ✅ String representation for debugging

#### Input Parser (`input.nim`)
- ✅ State machine for escape sequences (Init, Esc, CSI, SS3)
- ✅ CSI key mapping (xterm conventions)
- ✅ SS3 function key support
- ✅ Control character handling (Ctrl-A through Z)
- ✅ UTF-8 rune decoding
- ✅ Alt+key modifier support

#### Signal Handling (`signals.nim`)
- ✅ SIGWINCH (window resize) handler
- ✅ Atomic flag for async-signal-safe communication
- ✅ Safe to install multiple times

**Demo Program:**
- `tests/tui/demo_input_simple.nim` - Interactive key tester
- Shows real-time key events, modifiers, and resize detection
- Press 'q' or ESC to quit

---

### Layout System (`src/player/tui/layout/`)

**✅ IMPLEMENTED** - Phase 2 complete (2026-01-14)

**Module Structure:**
```
layout/
├── layout_pkg.nim      # Main export module
├── rect.nim            # Rect type with operations (~240 lines)
├── constraint.nim      # Constraint types (~200 lines)
└── layout.nim          # Layout solver (~280 lines)
```

#### ✅ Constraint Types (Actual Implementation)
```nim
type
  ConstraintKind = enum
    Length      ## Fixed size in cells
    Min         ## Minimum size (can grow)
    Max         ## Maximum size (can shrink)
    Percentage  ## Percentage of available space (0-100)
    Ratio       ## Ratio relative to total (numerator/denominator)
    Fill        ## Fill remaining space (weighted)

  Constraint = object
    case kind: ConstraintKind
    of Length: length: int
    of Min: minVal: int
    of Max: maxVal: int
    of Percentage: percent: int
    of Ratio: numerator, denominator: int
    of Fill: weight: int
```

**Constructor functions:**
- `length(n)` / `len(n)` - Fixed size
- `min(n)` - Minimum size
- `max(n)` - Maximum size  
- `percentage(n)` / `pct(n)` - Percentage (0-100)
- `ratio(num, denom)` - Proportional sizing
- `fill(weight=1)` - Fill remaining space

#### ✅ Layout Builder API
```nim
# Fluent builder pattern
let areas = horizontal()
  .constraints(length(10), fill(), percentage(30))
  .margin(1)
  .spacing(2)
  .flex(Flex.Center)
  .split(terminalRect)

# Convenience functions
let areas = hsplit(rect, @[length(20), fill()])
let areas = vsplit(rect, 3)  # Split into 3 equal parts
```

**Flex modes for extra space distribution:**
- `Flex.Start` - Pack at start (default)
- `Flex.End` - Pack at end
- `Flex.Center` - Center segments
- `Flex.SpaceBetween` - Space between segments
- `Flex.SpaceAround` - Space around segments

#### ✅ Constraint Solver Algorithm

**Priority order (highest to lowest):**
1. **Length** - Fixed sizes allocated first
2. **Percentage** - Calculated from available space
3. **Ratio** - Proportional allocation
4. **Min** - Minimum size enforced, can grow with Fill
5. **Fill** - Gets remaining space (weighted)
6. **Max** - Gets leftover space up to maximum

**Algorithm steps:**
1. Calculate fixed sizes (Length, Percentage, Ratio)
2. Subtract from available space
3. Distribute remaining to Fill constraints by weight
4. Enforce Min constraints (already set as base)
5. Allocate leftovers to Max constraints (up to limit)
6. Handle overflow by shrinking flexible segments

#### ✅ Rect Type Features

**Operations implemented:**
- Construction: `rect(x, y, w, h)`, `rect(w, h)`
- Properties: `right`, `bottom`, `area`, `isEmpty`, `isValid`
- Position checks: `contains(x, y)`, `contains(rect)`, `intersects`
- Transformations: `offset`, `moveTo`, `resize`, `inflate`, `shrink`
- Set operations: `intersection`, `union`
- Splitting: `splitHorizontal`, `splitVertical`, `split`
- Inner regions: `inner` (for borders/padding)
- Clipping: `clampTo`
- Iteration: `positions`, `rows`, `columns`

#### Layout Examples (Implemented)
```
┌─────────────────────────────────┐
│ Status Bar (length(1))          │
├─────────────┬───────────────────┤
│             │                   │
│ Map View    │ Unit Info         │
│ (fill())    │ (percentage(30))  │
│             │                   │
├─────────────┴───────────────────┤
│ Message Log (length(5))         │
└─────────────────────────────────┘
```

```nim
let term = rect(80, 24)
let rows = vertical()
  .constraints(length(1), fill(), length(5))
  .split(term)

let cols = horizontal()
  .constraints(fill(), percentage(30))
  .split(rows[1])
```

#### Test Coverage
- **41 tests passing** (`tests/tui/tlayout.nim`)
- Tests cover: rect ops, constraints, margins, spacing, flex modes, 
  edge cases, overflow, nested layouts, real-world examples

#### FUTURE CASSOWARY INTEGRATION NOTES

**Migration path designed into API:**

All constraint types map directly to Cassowary constraints when using
amoeba library (https://github.com/starwing/amoeba):

```nim
# Current: Simple solver
Length(n)     -> fixed arithmetic
Min(n)        -> max(n, allocated)
Max(n)        -> min(n, leftover)

# Future: Cassowary solver (amoeba FFI)
Length(n)     -> am_Constraint: var == n (AM_REQUIRED)
Min(n)        -> am_Constraint: var >= n (AM_REQUIRED)  
Max(n)        -> am_Constraint: var <= n (AM_REQUIRED)
Percentage(p) -> am_Constraint: var == parent * p/100 (AM_STRONG)
Ratio(n, d)   -> am_Constraint: var == total * n/d (AM_STRONG)
Fill(w)       -> am_Constraint: var == remain * w/sum (AM_MEDIUM)
```

**When to migrate:**
- If complex inter-segment relationships needed
- Example: "Panel A width = Panel B width + 10"
- Example: "Sidebar min 20%, max 40%, equal to header height"

**API remains stable** - only solver implementation changes.
The `Layout.split()` method would delegate to CassowaryLayoutSolver
instead of SimpleLayoutSolver.

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

**Status**: ✅ **COMPLETE** (Phase 1 + Phase 1.5)

#### ✅ 1. Terminal Primitives (`term/`) - COMPLETE
- ✅ **Capability Detection**
  - ✅ Profile detection via environment variables
  - ✅ Color support: TrueColor, ANSI256, ANSI, Ascii
  - ✅ Terminal size via `std/terminal`

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

**Tests**: 32 tests passing across 4 test files + visual color chart demo

#### ✅ 2. Screen Buffer (`buffer.nim`) - COMPLETE (Phase 1.5)
- ✅ Cell structure with dirty tracking (tcell-style)
- ✅ Buffer allocation and management
- ✅ Wide character support
- ✅ Cell locking for special regions
- ✅ Resize with content preservation

**Tests**: 15 tests passing

#### ✅ 3. Input Handling - COMPLETE (Phase 1.5)
- ✅ `tty.nim` - Raw mode via termios, window size queries
- ✅ `events.nim` - Event types (Key, Resize, Error)
- ✅ `input.nim` - Input parser with escape sequences
- ✅ `signals.nim` - SIGWINCH resize handler

**Demo**: `tests/tui/demo_input_simple.nim` - Interactive key tester

**Deliverable**: ✅ Can generate ANSI sequences, render frames, read input

---

### Phase 2: Layout System

**Status**: ✅ **COMPLETE** (2026-01-14)

**Implemented:**
- ✅ Rect type with full set of operations (240 lines)
- ✅ Constraint types: Length, Min, Max, Percentage, Ratio, Fill
- ✅ Layout builder API with fluent interface
- ✅ Constraint solver with priority-based allocation
- ✅ Margin and spacing support
- ✅ Flex modes: Start, End, Center, SpaceBetween, SpaceAround
- ✅ Horizontal and vertical splits
- ✅ Nested layouts support
- ✅ 41 tests passing (100% coverage of features)

**Files created:**
- `src/player/tui/layout/rect.nim` - Rect operations
- `src/player/tui/layout/constraint.nim` - Constraint definitions
- `src/player/tui/layout/layout.nim` - Layout solver
- `src/player/tui/layout/layout_pkg.nim` - Export module
- `tests/tui/tlayout.nim` - Comprehensive tests

**Deliverable**: ✅ Can define and render complex multi-panel layouts

**Example usage:**
```nim
let term = rect(80, 24)
let rows = vertical()
  .constraints(length(1), fill(), length(5))
  .margin(1)
  .spacing(2)
  .split(term)
```

**Future Cassowary integration:** API designed to be solver-agnostic.
Can swap simple solver for amoeba/Cassowary without API changes if
complex constraint relationships needed.

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
│   ├── buffer.nim                 # ✅ Phase 1.5: Screen buffer with dirty tracking
│   ├── events.nim                 # ✅ Phase 1.5: Event types (Key, Resize, Error)
│   ├── input.nim                  # ✅ Phase 1.5: Input parser with escape sequences
│   ├── tty.nim                    # ✅ Phase 1.5: Raw mode terminal control
│   ├── signals.nim                # ✅ Phase 1.5: SIGWINCH handler
│   ├── layout/                    # ✅ Phase 2: Layout system
│   │   ├── layout_pkg.nim         # Main export
│   │   ├── rect.nim               # Rect type and operations
│   │   ├── constraint.nim         # Constraint types
│   │   └── layout.nim             # Layout solver
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

### Current Implementation Status (2026-01-14)

**✅ Phase 1 - Terminal Primitives (Complete):**
- Terminal primitives layer (`tui/term/`)
- 32 passing tests across 4 test suites
- Visual color chart demo
- Full termenv feature parity

**✅ Phase 1.5 - Screen Buffer & Input (Complete):**
- Screen buffer with dirty tracking (`buffer.nim`)
- Event system (`events.nim`)
- Input parser with escape sequences (`input.nim`)
- TTY control and raw mode (`tty.nim`)
- SIGWINCH signal handling (`signals.nim`)
- 15 buffer tests + interactive demo

**✅ Phase 2 - Layout System (Complete):**
- Rect type with operations (`layout/rect.nim`)
- Constraint types: Length, Min, Max, Percentage, Ratio, Fill
- Layout solver with fluent builder API (`layout/layout.nim`)
- Margin, spacing, and flex mode support
- 41 tests passing (100% feature coverage)
- ~720 lines of layout code

**❌ Not Started:**
- Phase 3: Widget library (Panel, Text, List, Menu, etc.)
- Phase 4: Game-specific widgets (Map, Units, Cities, etc.)
- Phase 5: SAM integration (State-Action-Model)
- Phase 6: Polish & features

**Total Lines of Code:** ~2,144 lines (Phase 1 + 1.5 + 2)
**Total Tests:** 88 passing (32 term + 15 buffer + 41 layout)

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
