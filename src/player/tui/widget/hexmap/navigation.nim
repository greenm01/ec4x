## Navigation - Keyboard handling for hex map
##
## Maps keyboard input to hex map navigation actions.
## Supports arrow key movement, tab cycling, and selection.

import std/[options, tables, algorithm, unicode]
import ./coords
import ./hexmap
import ../../events

type
  NavAction* {.pure.} = enum
    ## Actions that can be triggered by navigation
    None
    MoveCursor ## Cursor moved to adjacent hex
    Select ## Current hex selected
    Deselect ## Selection cleared
    CycleNextColony ## Tab to next owned colony
    CyclePrevColony ## Shift+Tab to previous owned colony
    CenterOnHome ## Jump to homeworld
    Quit ## Exit map view

  NavResult* = object ## Result of processing a key event
    action*: NavAction
    consumed*: bool ## Whether the event was handled

# -----------------------------------------------------------------------------
# Key to direction mapping
# -----------------------------------------------------------------------------

proc keyToDirection(key: Key): Option[HexDirection] =
  ## Map arrow keys to hex directions
  ## Note: Flat-top hex grid means Up/Down move NW-NE/SW-SE
  case key
  of Key.Right:
    some(HexDirection.East)
  of Key.Left:
    some(HexDirection.West)
  of Key.Up:
    # Up moves to one of the northern neighbors
    # We choose Northeast for consistency
    some(HexDirection.Northeast)
  of Key.Down:
    # Down moves to one of the southern neighbors
    some(HexDirection.Southwest)
  else:
    none(HexDirection)

# -----------------------------------------------------------------------------
# Navigation handlers
# -----------------------------------------------------------------------------

proc handleKey*(state: var HexMapState, event: KeyEvent, mapData: MapData): NavResult =
  ## Process a key event and update state accordingly
  ## Returns action taken and whether event was consumed

  result = NavResult(action: NavAction.None, consumed: false)

  let key = event.key
  let hasShift = (event.modifiers and ModShift) != ModNone

  # Arrow keys - move cursor, viewport recenters in render
  let dir = keyToDirection(key)
  if dir.isSome:
    state.moveCursor(dir.get())
    result.action = NavAction.MoveCursor
    result.consumed = true
    return

  # Enter - select current hex
  if key == Key.Enter:
    state.selectCurrent()
    result.action = NavAction.Select
    result.consumed = true
    return

  # Escape - deselect
  if key == Key.Escape:
    if state.selected.isSome:
      state.deselect()
      result.action = NavAction.Deselect
      result.consumed = true
    return

  # Tab - cycle through owned colonies
  if key == Key.Tab:
    if hasShift:
      result.action = NavAction.CyclePrevColony
    else:
      result.action = NavAction.CycleNextColony
    result.consumed = true
    return

  # 'h' or Home - jump to homeworld
  if key == Key.Home or (key == Key.Rune and event.rune == Rune('h')):
    result.action = NavAction.CenterOnHome
    result.consumed = true
    return

  # 'q' - quit
  if key == Key.Rune and event.rune == Rune('q'):
    result.action = NavAction.Quit
    result.consumed = true
    return

# -----------------------------------------------------------------------------
# Colony cycling
# -----------------------------------------------------------------------------

proc findOwnedColonies*(mapData: MapData): seq[HexCoord] =
  ## Get list of owned colony coordinates sorted by distance from hub
  result = @[]

  for coord, sys in mapData.systems.pairs:
    if sys.owner.isSome and sys.owner.get() == mapData.viewingHouse:
      result.add(coord)

  # Sort by ring (distance from hub), then by q, then by r
  result.sort do(a, b: HexCoord) -> int:
    let ringA = a.ring()
    let ringB = b.ring()
    if ringA != ringB:
      return ringA - ringB
    if a.q != b.q:
      return a.q - b.q
    return a.r - b.r

proc centerViewportOn*(state: var HexMapState, target: HexCoord) =
  ## Pan viewport so target hex is at screen center
  ## Uses approximate center (actual center computed at render with real dims)
  let delta = target - state.cursor
  state.viewportOrigin = state.viewportOrigin + delta

proc cycleToNextColony*(state: var HexMapState, colonies: seq[HexCoord]) =
  ## Move viewport to center on next owned colony in list
  if colonies.len == 0:
    return

  # Find current position in list
  var currentIdx = -1
  for i, coord in colonies:
    if coord == state.cursor:
      currentIdx = i
      break

  # Move to next (or first if not on a colony)
  let nextIdx =
    if currentIdx < 0:
      0
    else:
      (currentIdx + 1) mod colonies.len

  state.centerViewportOn(colonies[nextIdx])

proc cycleToPrevColony*(state: var HexMapState, colonies: seq[HexCoord]) =
  ## Move viewport to center on previous owned colony in list
  if colonies.len == 0:
    return

  # Find current position in list
  var currentIdx = -1
  for i, coord in colonies:
    if coord == state.cursor:
      currentIdx = i
      break

  # Move to previous (or last if not on a colony)
  let prevIdx =
    if currentIdx <= 0:
      colonies.len - 1
    else:
      currentIdx - 1

  state.centerViewportOn(colonies[prevIdx])

proc findHomeworld*(mapData: MapData): Option[HexCoord] =
  ## Find the homeworld for the viewing player
  for coord, sys in mapData.systems.pairs:
    if sys.isHomeworld and sys.owner.isSome and sys.owner.get() == mapData.viewingHouse:
      return some(coord)
  none(HexCoord)

# -----------------------------------------------------------------------------
# High-level navigation handler
# -----------------------------------------------------------------------------

proc processNavigation*(
    state: var HexMapState, event: KeyEvent, mapData: MapData
): NavResult =
  ## Process navigation and handle colony cycling actions
  ## This is the main entry point for navigation handling

  result = handleKey(state, event, mapData)

  # Handle colony cycling actions
  case result.action
  of NavAction.CycleNextColony:
    let colonies = findOwnedColonies(mapData)
    cycleToNextColony(state, colonies)
  of NavAction.CyclePrevColony:
    let colonies = findOwnedColonies(mapData)
    cycleToPrevColony(state, colonies)
  of NavAction.CenterOnHome:
    let home = findHomeworld(mapData)
    if home.isSome:
      state.centerViewportOn(home.get())
  else:
    discard
