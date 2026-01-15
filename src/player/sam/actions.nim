## TUI Actions - Pure functions that create proposals
##
## Actions are the entry point for user input in the SAM pattern.
## They are pure functions that take event data and return proposals.
## Actions should NOT have side effects - they just compute intent.
##
## The action layer translates raw input (key events) into semantic proposals
## that the acceptors can process.

import std/[options, times]
import ./types
import ./tui_model

export types, tui_model

# ============================================================================
# Action Names (for allowed/disallowed filtering)
# ============================================================================

const
  ActionQuit* = "quit"
  ActionNavigateMode* = "navigateMode"
  ActionMoveCursor* = "moveCursor"
  ActionSelect* = "select"
  ActionDeselect* = "deselect"
  ActionListUp* = "listUp"
  ActionListDown* = "listDown"
  ActionEndTurn* = "endTurn"
  ActionScroll* = "scroll"
  ActionJumpHome* = "jumpHome"
  ActionCycleColony* = "cycleColony"
  ActionResize* = "resize"

# ============================================================================
# Navigation Actions
# ============================================================================

proc actionQuit*(): Proposal =
  ## Create quit action
  quitProposal()

proc actionSwitchMode*(mode: ViewMode): Proposal =
  ## Switch to a different view mode
  Proposal(
    kind: pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionNavigateMode,
    navMode: ord(mode),
    navCursor: (0, 0)  # Not used for mode switch
  )

proc actionMoveCursor*(dir: HexDirection): Proposal =
  ## Move map cursor in direction
  # We encode direction in navMode field (reused creatively)
  Proposal(
    kind: pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionMoveCursor,
    navMode: ord(dir),  # Direction encoded here
    navCursor: (0, 0)   # Will be computed by acceptor
  )

proc actionMoveCursorTo*(coord: HexCoord): Proposal =
  ## Move cursor directly to a coordinate
  Proposal(
    kind: pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionMoveCursor,
    navMode: -1,        # -1 means direct coordinate, not direction
    navCursor: coord
  )

proc actionJumpHome*(): Proposal =
  ## Jump cursor to homeworld
  Proposal(
    kind: pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionJumpHome,
    navMode: -2,        # Special marker for jump home
    navCursor: (0, 0)   # Will be set by acceptor from model.homeworld
  )

# ============================================================================
# Selection Actions
# ============================================================================

proc actionSelect*(): Proposal =
  ## Select current item (cursor position in map, or list item)
  Proposal(
    kind: pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionSelect,
    selectIdx: -1,      # -1 means "use current"
    selectCoord: none(tuple[q, r: int])
  )

proc actionSelectIndex*(idx: int): Proposal =
  ## Select specific index in list
  Proposal(
    kind: pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionSelect,
    selectIdx: idx,
    selectCoord: none(tuple[q, r: int])
  )

proc actionSelectCoord*(coord: HexCoord): Proposal =
  ## Select specific coordinate on map
  Proposal(
    kind: pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionSelect,
    selectIdx: -1,
    selectCoord: some(coord)
  )

proc actionDeselect*(): Proposal =
  ## Clear selection
  Proposal(
    kind: pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionDeselect,
    selectIdx: -2,      # -2 means deselect
    selectCoord: none(tuple[q, r: int])
  )

# ============================================================================
# List Navigation Actions
# ============================================================================

proc actionListUp*(): Proposal =
  ## Move selection up in list
  Proposal(
    kind: pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionListUp,
    selectIdx: -3,      # -3 means "move up"
    selectCoord: none(tuple[q, r: int])
  )

proc actionListDown*(): Proposal =
  ## Move selection down in list
  Proposal(
    kind: pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionListDown,
    selectIdx: -4,      # -4 means "move down"
    selectCoord: none(tuple[q, r: int])
  )

proc actionCycleColony*(reverse: bool = false): Proposal =
  ## Cycle to next/prev owned colony on map
  Proposal(
    kind: pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionCycleColony,
    navMode: if reverse: 1 else: 0,
    navCursor: (0, 0)
  )

# ============================================================================
# Viewport Actions
# ============================================================================

proc actionScroll*(dx, dy: int): Proposal =
  ## Scroll viewport
  scrollProposal(dx, dy, ActionScroll)

# ============================================================================
# Game Actions
# ============================================================================

proc actionEndTurn*(): Proposal =
  ## End the current turn
  endTurnProposal()

# ============================================================================
# System Actions
# ============================================================================

proc actionResize*(width, height: int): Proposal =
  ## Handle terminal resize
  Proposal(
    kind: pkViewportScroll,  # Reuse for resize data
    timestamp: getTime().toUnix(),
    actionName: ActionResize,
    scrollDelta: (width, height)  # Store new dimensions
  )

# ============================================================================
# Input Mapping Helper
# ============================================================================

type
  KeyCode* = enum
    ## Simplified key codes for mapping
    KeyNone
    KeyQ, KeyC, KeyF, KeyO, KeyM, KeyE, KeyH
    KeyUp, KeyDown, KeyLeft, KeyRight
    KeyEnter, KeyEscape, KeyTab, KeyShiftTab
    KeyHome

proc mapKeyToAction*(key: KeyCode, model: TuiModel): Option[Proposal] =
  ## Map a key code to an action based on current model state
  ## Returns None if no action should be taken
  
  # Global keys (work in any mode)
  case key
  of KeyQ:
    return some(actionQuit())
  of KeyC:
    return some(actionSwitchMode(ViewMode.Colonies))
  of KeyF:
    return some(actionSwitchMode(ViewMode.Fleets))
  of KeyO:
    return some(actionSwitchMode(ViewMode.Orders))
  of KeyM:
    return some(actionSwitchMode(ViewMode.Map))
  of KeyE:
    return some(actionEndTurn())
  else:
    discard
  
  # Mode-specific keys
  case model.mode
  of ViewMode.Map:
    case key
    of KeyUp:    return some(actionMoveCursor(HexDirection.NorthWest))
    of KeyDown:  return some(actionMoveCursor(HexDirection.SouthEast))
    of KeyLeft:  return some(actionMoveCursor(HexDirection.West))
    of KeyRight: return some(actionMoveCursor(HexDirection.East))
    of KeyEnter: return some(actionSelect())
    of KeyEscape: return some(actionDeselect())
    of KeyTab:   return some(actionCycleColony(false))
    of KeyShiftTab: return some(actionCycleColony(true))
    of KeyH, KeyHome: return some(actionJumpHome())
    else: discard
  
  of ViewMode.Colonies, ViewMode.Fleets, ViewMode.Orders:
    case key
    of KeyUp:    return some(actionListUp())
    of KeyDown:  return some(actionListDown())
    of KeyEnter: return some(actionSelect())
    of KeyEscape: return some(actionDeselect())
    else: discard
  
  none(Proposal)
