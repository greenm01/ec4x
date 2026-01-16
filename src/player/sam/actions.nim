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
  ActionSwitchView* = "switchView"       ## Switch to primary view [1-9]
  ActionBreadcrumbBack* = "breadcrumbBack"  ## Navigate up breadcrumb
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
  ActionExportMap* = "exportMap"
  ActionOpenMap* = "openMap"
  ActionEnterExpertMode* = "enterExpertMode"
  ActionExitExpertMode* = "exitExpertMode"
  ActionExpertInputAppend* = "expertInputAppend"
  ActionExpertInputBackspace* = "expertInputBackspace"
  ActionExpertSubmit* = "expertSubmit"
  ActionToggleFleetSelect* = "toggleFleetSelect"
  ActionSwitchPlanetTab* = "switchPlanetTab"
  ActionSwitchFleetView* = "switchFleetView"
  ActionCycleReportFilter* = "cycleReportFilter"

# ============================================================================
# Navigation Actions
# ============================================================================

proc actionQuit*(): Proposal =
  ## Create quit action
  quitProposal()

proc actionSwitchMode*(mode: ViewMode): Proposal =
  ## Switch to a different view mode (legacy)
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionNavigateMode,
    navMode: ord(mode),
    navCursor: (0, 0)  # Not used for mode switch
  )

proc actionSwitchView*(viewNum: int): Proposal =
  ## Switch to primary view by number [1-9]
  ## This resets breadcrumbs to the primary view level
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionSwitchView,
    navMode: viewNum,
    navCursor: (0, 0)
  )

proc actionBreadcrumbBack*(): Proposal =
  ## Navigate up the breadcrumb trail (Backspace)
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionBreadcrumbBack,
    navMode: 0,
    navCursor: (0, 0)
  )

proc actionMoveCursor*(dir: HexDirection): Proposal =
  ## Move map cursor in direction
  # We encode direction in navMode field (reused creatively)
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionMoveCursor,
    navMode: ord(dir),  # Direction encoded here
    navCursor: (0, 0)   # Will be computed by acceptor
  )

proc actionMoveCursorTo*(coord: HexCoord): Proposal =
  ## Move cursor directly to a coordinate
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionMoveCursor,
    navMode: -1,        # -1 means direct coordinate, not direction
    navCursor: coord
  )

proc actionJumpHome*(): Proposal =
  ## Jump cursor to homeworld
  Proposal(
    kind: ProposalKind.pkNavigation,
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
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionSelect,
    selectIdx: -1,      # -1 means "use current"
    selectCoord: none(tuple[q, r: int])
  )

proc actionSelectIndex*(idx: int): Proposal =
  ## Select specific index in list
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionSelect,
    selectIdx: idx,
    selectCoord: none(tuple[q, r: int])
  )

proc actionSelectCoord*(coord: HexCoord): Proposal =
  ## Select specific coordinate on map
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionSelect,
    selectIdx: -1,
    selectCoord: some(coord)
  )

proc actionDeselect*(): Proposal =
  ## Clear selection
  Proposal(
    kind: ProposalKind.pkSelection,
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
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionListUp,
    selectIdx: -3,      # -3 means "move up"
    selectCoord: none(tuple[q, r: int])
  )

proc actionListDown*(): Proposal =
  ## Move selection down in list
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionListDown,
    selectIdx: -4,      # -4 means "move down"
    selectCoord: none(tuple[q, r: int])
  )

proc actionCycleColony*(reverse: bool = false): Proposal =
  ## Cycle to next/prev owned colony on map
  Proposal(
    kind: ProposalKind.pkNavigation,
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
# Map Export Actions
# ============================================================================

proc actionExportMap*(): Proposal =
  ## Export SVG starmap to file
  gameActionProposal(ActionExportMap, "")

proc actionOpenMap*(): Proposal =
  ## Export SVG starmap and open in viewer
  gameActionProposal(ActionOpenMap, "")

# ============================================================================
# Expert Mode Actions
# ============================================================================

proc actionEnterExpertMode*(): Proposal =
  ## Enter expert mode (: prompt)
  gameActionProposal(ActionEnterExpertMode, "")

proc actionExitExpertMode*(): Proposal =
  ## Exit expert mode
  gameActionProposal(ActionExitExpertMode, "")

proc actionExpertInputAppend*(value: string): Proposal =
  ## Append input to expert mode buffer
  gameActionProposal(ActionExpertInputAppend, value)

proc actionExpertInputBackspace*(): Proposal =
  ## Remove last character from expert mode buffer
  gameActionProposal(ActionExpertInputBackspace, "")

proc actionExpertSubmit*(): Proposal =
  ## Submit expert mode command
  gameActionProposal(ActionExpertSubmit, "")

# ============================================================================
# Fleet Multi-Select Actions
# ============================================================================

proc actionToggleFleetSelect*(fleetId: int): Proposal =
  ## Toggle fleet selection for batch operations
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionToggleFleetSelect,
    selectIdx: fleetId,
    selectCoord: none(tuple[q, r: int])
  )

# ============================================================================
# Sub-View Navigation Actions
# ============================================================================

proc actionSwitchPlanetTab*(tab: int): Proposal =
  ## Switch planet detail tab (1-5)
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionSwitchPlanetTab,
    navMode: tab,
    navCursor: (0, 0)
  )

proc actionSwitchFleetView*(): Proposal =
  ## Toggle between fleet System View and List View
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionSwitchFleetView,
    navMode: 0,
    navCursor: (0, 0)
  )

proc actionCycleReportFilter*(): Proposal =
  ## Cycle the Reports view filter
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionCycleReportFilter,
    navMode: 0,
    navCursor: (0, 0)
  )

# ============================================================================
# System Actions
# ============================================================================

proc actionResize*(width, height: int): Proposal =
  ## Handle terminal resize
  Proposal(
    kind: ProposalKind.pkViewportScroll,  # Reuse for resize data
    timestamp: getTime().toUnix(),
    actionName: ActionResize,
    scrollDelta: (width, height)  # Store new dimensions
  )

# ============================================================================
# Input Mapping Helper
# ============================================================================

type
  KeyCode* {.pure.} = enum
    ## Simplified key codes for mapping
    KeyNone
    # Number keys for view switching
    Key1, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9
    # Letter keys
    KeyQ, KeyC, KeyF, KeyO, KeyM, KeyE, KeyH, KeyX, KeyS, KeyL
    KeyB, KeyG, KeyR, KeyJ, KeyD, KeyP, KeyV, KeyN, KeyW, KeyI, KeyT, KeyA
    # Navigation
    KeyUp, KeyDown, KeyLeft, KeyRight
    KeyEnter, KeyEscape, KeyTab, KeyShiftTab
    KeyHome, KeyBackspace
    # Special
    KeyColon  # Expert mode trigger

proc mapKeyToAction*(key: KeyCode, model: TuiModel): Option[Proposal] =
  ## Map a key code to an action based on current model state
  ## Returns None if no action should be taken
  
  # Expert mode has its own input handling
  if model.expertModeActive:
    case key
    of KeyCode.KeyEscape:
      return some(actionExitExpertMode())
    of KeyCode.KeyEnter:
      return some(actionExpertSubmit())
    of KeyCode.KeyBackspace:
      return some(actionExpertInputBackspace())
    else:
      # Other keys add to input buffer - handled by acceptor
      return none(Proposal)
  
  # Global keys (work in any mode)
  case key
  # Number keys [1-9] switch primary views
  of KeyCode.Key1: return some(actionSwitchView(1))
  of KeyCode.Key2: return some(actionSwitchView(2))
  of KeyCode.Key3: return some(actionSwitchView(3))
  of KeyCode.Key4: return some(actionSwitchView(4))
  of KeyCode.Key5: return some(actionSwitchView(5))
  of KeyCode.Key6: return some(actionSwitchView(6))
  of KeyCode.Key7: return some(actionSwitchView(7))
  of KeyCode.Key8: return some(actionSwitchView(8))
  of KeyCode.Key9: return some(actionSwitchView(9))
  # Quit
  of KeyCode.KeyQ: return some(actionQuit())
  # Backspace goes up breadcrumb
  of KeyCode.KeyBackspace: return some(actionBreadcrumbBack())
  # Colon enters expert mode
  of KeyCode.KeyColon: return some(actionEnterExpertMode())
  else:
    discard
  
  # Mode-specific keys
  case model.mode
  of ViewMode.Overview:
    case key
    of KeyCode.KeyL:
      return some(actionSwitchMode(ViewMode.Overview))
    of KeyCode.KeyUp:    return some(actionListUp())
    of KeyCode.KeyDown:  return some(actionListDown())
    of KeyCode.KeyEnter: return some(actionSelect())  # Jump to action item
    else: discard
  
  of ViewMode.Planets:
    case key
    of KeyCode.KeyUp:    return some(actionListUp())
    of KeyCode.KeyDown:  return some(actionListDown())
    of KeyCode.KeyEnter: return some(actionSelect())  # View colony
    of KeyCode.KeyB:
      return some(actionSelect())
    of KeyCode.KeyS:     return some(actionSelect())  # Sort - TODO
    of KeyCode.KeyF:     return some(actionSelect())  # Filter - TODO
    else: discard
  
  of ViewMode.Fleets:
    case key
    of KeyCode.KeyUp:    return some(actionListUp())
    of KeyCode.KeyDown:  return some(actionListDown())
    of KeyCode.KeyEnter: return some(actionSelect())  # Fleet details
    of KeyCode.KeyX:     return some(actionToggleFleetSelect(model.selectedIdx))
    of KeyCode.KeyL:
      return some(actionSwitchFleetView())
    of KeyCode.KeyM:     return some(actionSelect())  # Move
    of KeyCode.KeyP:     return some(actionSelect())  # Patrol
    of KeyCode.KeyH:     return some(actionSelect())  # Hold
    of KeyCode.KeyR:     return some(actionSelect())  # ROE
    else: discard
  
  of ViewMode.Research:
    case key
    of KeyCode.KeyE:     return some(actionSelect())  # Adjust ERP
    of KeyCode.KeyS:     return some(actionSelect())  # Adjust SRP
    of KeyCode.KeyT:     return some(actionSelect())  # Adjust TRP
    of KeyCode.KeyEnter: return some(actionSelect())  # Confirm allocation
    else: discard
  
  of ViewMode.Espionage:
    case key
    of KeyCode.KeyUp:    return some(actionListUp())
    of KeyCode.KeyDown:  return some(actionListDown())
    of KeyCode.KeyEnter: return some(actionSelect())  # Queue operation
    of KeyCode.KeyT:     return some(actionSelect())  # Select target
    of KeyCode.KeyB:     return some(actionSelect())  # Buy EBP
    of KeyCode.KeyC:     return some(actionSelect())  # Buy CIP
    else: discard
  
  of ViewMode.Economy:
    case key
    of KeyCode.KeyLeft:  return some(actionSelect())  # Decrease tax
    of KeyCode.KeyRight: return some(actionSelect())  # Increase tax
    of KeyCode.KeyEnter: return some(actionSelect())  # Confirm
    of KeyCode.KeyI:     return some(actionSelect())  # Industrial investment
    of KeyCode.KeyG:     return some(actionSelect())  # Guild transfer
    else: discard
  
  of ViewMode.Reports:
    case key
    of KeyCode.KeyUp:
      return some(actionListUp())
    of KeyCode.KeyDown:
      return some(actionListDown())
    of KeyCode.KeyEnter:
      return some(actionSelect())  # View report
    of KeyCode.KeyD:
      return some(actionSelect())  # Delete
    of KeyCode.KeyA:
      return some(actionSelect())  # Archive
    of KeyCode.KeyM:
      return some(actionSelect())  # Mark read/unread
    of KeyCode.KeyTab:
      return some(actionCycleReportFilter())
    else: discard
  
  of ViewMode.Messages:
    case key
    of KeyCode.KeyUp:    return some(actionListUp())
    of KeyCode.KeyDown:  return some(actionListDown())
    of KeyCode.KeyL:     return some(actionSelect())  # Diplomatic matrix
    of KeyCode.KeyC:     return some(actionSelect())  # Compose
    of KeyCode.KeyP:     return some(actionSelect())  # Propose
    of KeyCode.KeyA:     return some(actionSelect())  # Accept
    of KeyCode.KeyR:     return some(actionSelect())  # Reject
    else: discard
  
  of ViewMode.Settings:
    case key
    of KeyCode.KeyUp:    return some(actionListUp())
    of KeyCode.KeyDown:  return some(actionListDown())
    of KeyCode.KeyEnter: return some(actionSelect())  # Change value
    of KeyCode.KeyR:     return some(actionSelect())  # Reset to defaults
    else: discard
  
  of ViewMode.PlanetDetail:
    case key
    of KeyCode.KeyTab:   return some(actionSelect())  # Next section
    of KeyCode.Key1:     return some(actionSwitchPlanetTab(1))  # Summary
    of KeyCode.Key2:     return some(actionSwitchPlanetTab(2))  # Economy
    of KeyCode.Key3:     return some(actionSwitchPlanetTab(3))  # Construction
    of KeyCode.Key4:     return some(actionSwitchPlanetTab(4))  # Defense
    of KeyCode.Key5:     return some(actionSwitchPlanetTab(5))  # Settings
    of KeyCode.KeyB:     return some(actionSelect())  # Build
    of KeyCode.KeyG:     return some(actionSelect())  # Garrison
    else: discard
  
  of ViewMode.FleetDetail:
    case key
    of KeyCode.KeyM:     return some(actionSelect())  # Move
    of KeyCode.KeyP:     return some(actionSelect())  # Patrol
    of KeyCode.KeyH:     return some(actionSelect())  # Hold
    of KeyCode.KeyG:     return some(actionSelect())  # Guard
    of KeyCode.KeyR:     return some(actionSelect())  # ROE
    of KeyCode.KeyJ:     return some(actionSelect())  # Join
    of KeyCode.KeyD:     return some(actionSelect())  # Detach ships
    else: discard
  
  of ViewMode.ReportDetail:
    case key
    of KeyCode.KeyBackspace:
      return some(actionBreadcrumbBack())
    of KeyCode.KeyN:
      return some(actionSelect())  # Next report
    of KeyCode.KeyEnter:
      return some(actionSelect())  # Jump to linked view
    else: discard

  none(Proposal)

