## TUI Acceptors - Functions that mutate model state
##
## Acceptors receive proposals and mutate the model accordingly.
## They are the ONLY place where model mutation happens.
## Each acceptor handles specific proposal types or aspects of state.
##
## Acceptor signature: proc(model: var M, proposal: Proposal)

import std/[options]
import ./types
import ./tui_model
import ./actions

export types, tui_model, actions

# ============================================================================
# Navigation Acceptor
# ============================================================================

proc navigationAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle navigation proposals (mode changes, cursor movement)
  if proposal.kind != pkNavigation:
    return
  
  case proposal.actionName
  
  of ActionNavigateMode:
    # Mode switch
    let newMode = ViewMode(proposal.navMode)
    model.mode = newMode
    model.selectedIdx = 0  # Reset selection when switching modes
  
  of ActionMoveCursor:
    if proposal.navMode >= 0:
      # Direction-based movement
      let dir = HexDirection(proposal.navMode)
      model.mapState.cursor = model.mapState.cursor.neighbor(dir)
    else:
      # Direct coordinate movement
      model.mapState.cursor = proposal.navCursor
  
  of ActionJumpHome:
    if model.homeworld.isSome:
      model.mapState.cursor = model.homeworld.get
  
  of ActionCycleColony:
    let coords = model.ownedColonyCoords()
    if coords.len > 0:
      # Find current cursor in owned colonies
      var currentIdx = -1
      for i, coord in coords:
        if coord == model.mapState.cursor:
          currentIdx = i
          break
      
      # Cycle to next/prev
      let reverse = proposal.navMode == 1
      if reverse:
        if currentIdx <= 0:
          model.mapState.cursor = coords[coords.len - 1]
        else:
          model.mapState.cursor = coords[currentIdx - 1]
      else:
        if currentIdx < 0 or currentIdx >= coords.len - 1:
          model.mapState.cursor = coords[0]
        else:
          model.mapState.cursor = coords[currentIdx + 1]
  
  else:
    discard

# ============================================================================
# Selection Acceptor
# ============================================================================

proc selectionAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle selection proposals (list selection, map selection)
  if proposal.kind != pkSelection:
    return
  
  case proposal.actionName
  
  of ActionSelect:
    case model.mode
    of ViewMode.Map:
      # Select hex at cursor
      model.mapState.selected = some(model.mapState.cursor)
    
    of ViewMode.Colonies, ViewMode.Fleets, ViewMode.Orders:
      # Select current list item (idx is already set)
      if proposal.selectIdx >= 0:
        model.selectedIdx = proposal.selectIdx
  
  of ActionDeselect:
    model.mapState.selected = none(HexCoord)
  
  of ActionListUp:
    if model.selectedIdx > 0:
      model.selectedIdx -= 1
  
  of ActionListDown:
    let maxIdx = model.currentListLength() - 1
    if model.selectedIdx < maxIdx:
      model.selectedIdx += 1
  
  else:
    discard

# ============================================================================
# Viewport Acceptor
# ============================================================================

proc viewportAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle viewport/scroll proposals
  if proposal.kind != pkViewportScroll:
    return
  
  case proposal.actionName
  
  of ActionScroll:
    model.mapState.viewportOrigin = (
      model.mapState.viewportOrigin.q + proposal.scrollDelta.dx,
      model.mapState.viewportOrigin.r + proposal.scrollDelta.dy
    )
  
  of ActionResize:
    model.termWidth = proposal.scrollDelta.dx
    model.termHeight = proposal.scrollDelta.dy
    model.needsResize = true
  
  else:
    discard

# ============================================================================
# Game Action Acceptor
# ============================================================================

proc gameActionAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle game action proposals
  case proposal.kind
  
  of pkEndTurn:
    model.statusMessage = "Turn ended. Processing..."
    # Actual turn processing would be done elsewhere (integration with engine)
  
  of pkQuit:
    model.running = false
  
  of pkGameAction:
    # Handle game-specific actions (build, move fleet, etc.)
    model.statusMessage = "Action: " & proposal.gameActionType
  
  else:
    discard

# ============================================================================
# Error Acceptor
# ============================================================================

proc errorAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle error proposals
  if proposal.kind == pkError:
    model.statusMessage = "Error: " & proposal.errorMsg

# ============================================================================
# Create All Acceptors
# ============================================================================

proc createAcceptors*(): seq[AcceptorProc[TuiModel]] =
  ## Create the standard set of acceptors for the TUI
  @[
    navigationAcceptor,
    selectionAcceptor,
    viewportAcceptor,
    gameActionAcceptor,
    errorAcceptor
  ]
