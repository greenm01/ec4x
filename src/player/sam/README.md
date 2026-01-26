# SAM Pattern Implementation

## What is SAM?

SAM (State-Action-Model) is a software architecture pattern based on the semantics of TLA+ (Temporal Logic of Actions), created by Jean-Jacques Dubray. It enforces a unidirectional data flow where state changes happen through a well-defined, synchronized mutation process.

Unlike MVC or Flux, SAM makes the distinction between:
- **Actions**: Compute *proposals* (intent to change state)
- **Model**: *Accepts* proposals and mutates state
- **State**: *Derives* additional data and determines what to render

## Core Concepts

### Data Flow

```
Input Event → Action → Proposal → present() → Acceptors → Reactors → NAPs → Render
                                      │                                    │
                                      └──────── History Snapshot ──────────┘
```

### Components

| Component | Purpose | Signature |
|-----------|---------|-----------|
| **Action** | Pure function that creates a proposal from an event | `event → Proposal` |
| **Proposal** | Immutable data representing intent to change | `{kind, data, timestamp}` |
| **Acceptor** | Mutates model state based on proposal | `(model, proposal) → void` |
| **Reactor** | Derives/computes additional state after mutation | `(model) → void` |
| **NAP** | Next-Action Predicate - triggers automatic actions | `(model) → Option[Proposal]` |
| **Render** | Displays state representation | `(model) → void` |

### The `present()` Function

The heart of SAM is the `present()` function which orchestrates the entire cycle:

```nim
proc present(sam: var SamInstance, proposal: Proposal) =
  # 1. Validate action is allowed
  if not sam.isAllowed(proposal.actionName):
    return
  
  # 2. Run acceptors to mutate model
  for acceptor in sam.acceptors:
    acceptor(sam.model, proposal)
  
  # 3. Run reactors to derive state
  for reactor in sam.reactors:
    reactor(sam.model)
  
  # 4. Check safety conditions (rollback if violated)
  if not sam.checkSafety():
    return
  
  # 5. Snapshot for history/time-travel
  sam.history.snap(sam.model)
  
  # 6. Check NAPs for automatic next action
  let nextProposal = sam.checkNaps()
  if nextProposal.isSome:
    sam.present(nextProposal.get)  # Recursive
    return
  
  # 7. Render state representation
  sam.render(sam.model)
```

## Advantages

### 1. Single Source of Truth

All application state lives in one place (`TuiModel`). No scattered state across multiple objects, closures, or global variables.

```nim
type TuiModel = object
  # UI State
  mode: ViewMode
  selectedIdx: int
  mapState: MapState
  
  # Game Data
  turn: int
  treasury: int
  colonies: seq[ColonyInfo]
  # ... everything in one place
```

**Benefits:**
- Easy to serialize for save/load
- Simple to debug - inspect one object
- Clear understanding of what the app "knows"

### 2. Time Travel / Undo

Built-in history support enables:

```nim
# Undo last action
sam.travelPrev()

# Redo
sam.travelNext()

# Jump to specific point
sam.travelTo(5)

# Reset to initial state
sam.travelReset()
```

**Use cases:**
- Player undo in turn-based games
- Debugging by rewinding state
- Replay functionality

### 3. Testability

Every component is a pure function that can be tested in isolation:

```nim
# Test an action
test "move cursor creates correct proposal":
  let p = actionMoveCursor(HexDirection.East)
  check p.kind == pkNavigation
  check p.actionName == "moveCursor"

# Test an acceptor
test "navigation acceptor updates cursor":
  var model = initTuiModel()
  model.mapState.cursor = (0, 0)
  navigationAcceptor(model, actionMoveCursor(HexDirection.East))
  check model.mapState.cursor == (1, 0)

# Test a reactor
test "selection bounds clamps index":
  var model = initTuiModel()
  model.selectedIdx = 100
  model.colonies = @[colony1, colony2]  # only 2 items
  selectionBoundsReactor(model)
  check model.selectedIdx == 1  # clamped
```

No mocking terminals, no UI setup - just pure functions.

### 4. Predictable Data Flow

State only changes through `present()`. No "spooky action at a distance":

```
❌ Bad (scattered mutations):
  onClick → updateUI()
  onKeyPress → modifyState()
  onTimer → changeData()
  
✅ Good (SAM):
  onClick → present(clickProposal)
  onKeyPress → present(keyProposal)
  onTimer → present(timerProposal)
```

This eliminates race conditions and makes debugging straightforward.

### 5. Decoupled Layers

The view layer (`TuiModel`) is decoupled from the domain layer (`GameState`):

```nim
# Bridge syncs engine state to UI model
proc syncGameStateToModel(model: var TuiModel, state: GameState) =
  model.turn = state.turn
  model.treasury = state.house.treasury
  # ... transform and filter for UI
```

**Benefits:**
- UI can evolve independently
- Fog-of-war filtering at boundary
- Easy to swap rendering backends

### 6. Automatic Actions (NAPs)

Next-Action Predicates enable state machines:

```nim
proc autoScrollNap(model: TuiModel): Option[Proposal] =
  # If cursor at edge, auto-scroll
  if model.cursorAtEdge:
    return some(actionScroll(1, 0))
  none(Proposal)

proc turnEndNap(model: TuiModel): Option[Proposal] =
  # After player ends turn, trigger AI
  if model.awaitingAI:
    return some(actionRunAI())
  none(Proposal)
```

### 7. Safety Conditions

Define invariants that trigger automatic rollback:

```nim
sam.addSafetyCondition(SafetyCondition(
  name: "treasury cannot go negative",
  expression: proc(m: TuiModel): bool = m.treasury < 0
))

# If any action causes treasury < 0, state rolls back automatically
```

## Disadvantages

### 1. More Boilerplate

SAM requires more ceremony than direct mutation:

```nim
# Direct mutation (less code)
proc handleKey(key: Key) =
  if key == KeyUp:
    selectedIdx -= 1

# SAM (more code)
proc handleKey(key: Key): Option[Proposal] =
  if key == KeyUp:
    return some(actionListUp())
  none(Proposal)

proc listUpAcceptor(model: var TuiModel, p: Proposal) =
  if p.actionName == "listUp":
    model.selectedIdx -= 1
```

### 2. Learning Curve

Developers must understand:
- Proposal vs Action vs Acceptor vs Reactor
- When to use NAPs
- How `present()` orchestrates everything

### 3. Indirection

Following the code path requires understanding the flow:
- Key press → Action → Proposal → Acceptor → Reactor → Render

vs direct:
- Key press → Handler → Update

### 4. Potential Performance Overhead

Running all acceptors and reactors on every action, plus history snapshots, adds overhead. For turn-based games this is negligible, but for 60fps applications it could matter.

### 5. Not Ideal for Simple Apps

For a basic CRUD form, SAM is overkill. The pattern shines in complex, stateful applications.

## When to Use SAM

**Good fit:**
- Turn-based games (undo, replay, save/load)
- Complex state machines
- Applications needing time-travel debugging
- Multi-step workflows
- Collaborative/multiplayer (action replay)

**Not ideal:**
- Simple forms
- Real-time 60fps games
- Thin wrappers around APIs
- Prototypes/throwaway code

## Comparison with Other Patterns

| Aspect | SAM | Redux | MVC | Direct Mutation |
|--------|-----|-------|-----|-----------------|
| Boilerplate | High | High | Medium | Low |
| Testability | Excellent | Excellent | Medium | Poor |
| Time Travel | Built-in | With middleware | Manual | Manual |
| Learning Curve | Steep | Medium | Low | None |
| State Location | Single | Single | Distributed | Scattered |
| Mutation Control | Strict | Strict | Loose | None |

## EC4X Implementation

This implementation adapts SAM for Nim with these design choices:

1. **Generic over Model type**: `SamInstance[M]` works with any model
2. **Nimcall procs**: Acceptors/reactors are regular procs, not closures
3. **Closure for render**: Allows capturing terminal buffer
4. **Discriminated unions**: Proposals use Nim's object variants
5. **Optional history**: Can disable time-travel for memory savings

### File Structure

```
sam/
├── types.nim       # Proposal, AcceptorProc, ReactorProc, NapProc, History
├── instance.nim    # SamInstance, present(), time travel
├── tui_model.nim   # TuiModel - the single source of truth
├── actions.nim     # Action creators (pure functions)
├── acceptors.nim   # State mutation functions
├── reactors.nim    # Derived state computation
├── naps.nim        # Next-Action Predicates
├── bridge.nim      # Engine ↔ SAM integration
└── sam_pkg.nim     # Package exports
```

### Quick Start

```nim
import sam/sam_pkg

# Create instance (history disabled by default)
# Use initTuiSam(withHistory = true) to enable time travel.
var sam = initTuiSam()

# Set render function
sam.setRender(proc(model: TuiModel) =
  renderUI(model)
)

# Set initial state
sam.setInitialState(initTuiModel())

# Main loop
while sam.state.running:
  let event = readInput()
  let proposal = mapKeyEvent(event, sam.state)
  if proposal.isSome:
    sam.present(proposal.get)
```

## References

- [SAM Pattern](https://sam.js.org/) - Official site by Jean-Jacques Dubray
- [sam-pattern npm](https://www.npmjs.com/package/sam-pattern) - JavaScript implementation
- [TLA+](https://lamport.azurewebsites.net/tla/tla.html) - Temporal Logic of Actions by Leslie Lamport
