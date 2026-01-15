## TUI Reactors - Functions that derive state after mutations
##
## Reactors run after acceptors and compute derived state.
## They can read the model and update computed/derived fields.
## Common uses:
## - Update status messages based on state
## - Compute aggregations
## - Validate and clamp values
## - Update viewport to keep cursor visible
##
## Reactor signature: proc(model: var M)

import std/[strformat, options, tables]
import ./types
import ./tui_model

export types, tui_model

# ============================================================================
# Viewport Reactor
# ============================================================================

const
  HexWidth = 3        ## Width of a hex cell in screen characters
  ViewportMargin = 2  ## Keep cursor this far from viewport edge

proc viewportReactor*(model: var TuiModel) =
  ## Keep cursor visible in viewport by adjusting viewport origin
  ## This ensures smooth scrolling as user navigates the map
  
  # Calculate visible hex range based on terminal size
  # Reserve some space for UI (status bar, panels)
  let visibleWidth = max(1, (model.termWidth - 40) div HexWidth)
  let visibleHeight = max(1, model.termHeight - 10)
  
  # Get current cursor and viewport
  let cursor = model.mapState.cursor
  let vpOrigin = model.mapState.viewportOrigin
  
  # Calculate cursor position relative to viewport
  let relQ = cursor.q - vpOrigin.q
  let relR = cursor.r - vpOrigin.r
  
  # Adjust viewport if cursor is near edge
  var newQ = vpOrigin.q
  var newR = vpOrigin.r
  
  # Horizontal adjustment
  if relQ < ViewportMargin:
    newQ = cursor.q - ViewportMargin
  elif relQ > visibleWidth - ViewportMargin - 1:
    newQ = cursor.q - visibleWidth + ViewportMargin + 1
  
  # Vertical adjustment
  if relR < ViewportMargin:
    newR = cursor.r - ViewportMargin
  elif relR > visibleHeight - ViewportMargin - 1:
    newR = cursor.r - visibleHeight + ViewportMargin + 1
  
  model.mapState.viewportOrigin = (newQ, newR)

# ============================================================================
# Selection Bounds Reactor
# ============================================================================

proc selectionBoundsReactor*(model: var TuiModel) =
  ## Clamp selection index to valid range
  let maxIdx = model.currentListLength() - 1
  if maxIdx < 0:
    model.selectedIdx = 0
  elif model.selectedIdx > maxIdx:
    model.selectedIdx = maxIdx
  elif model.selectedIdx < 0:
    model.selectedIdx = 0

# ============================================================================
# Status Message Reactor
# ============================================================================

proc statusMessageReactor*(model: var TuiModel) =
  ## Update status message based on current state
  ## Only updates if not already set by an action
  if model.statusMessage.len == 0:
    case model.mode
    of ViewMode.Map:
      let cursor = model.mapState.cursor
      let sysOpt = model.systemAt(cursor)
      if sysOpt.isSome:
        model.statusMessage = sysOpt.get.name
      else:
        model.statusMessage = &"[{cursor.q},{cursor.r}]"
    
    of ViewMode.Colonies:
      if model.colonies.len > 0:
        model.statusMessage = &"{model.colonies.len} colonies"
      else:
        model.statusMessage = "No colonies"
    
    of ViewMode.Fleets:
      if model.fleets.len > 0:
        model.statusMessage = &"{model.fleets.len} fleets"
      else:
        model.statusMessage = "No fleets"
    
    of ViewMode.Orders:
      if model.orders.len > 0:
        model.statusMessage = &"{model.orders.len} pending orders"
      else:
        model.statusMessage = "No orders"
    
    of ViewMode.Systems:
      model.statusMessage = &"{model.systems.len} systems"

# ============================================================================
# Clear Transient State Reactor
# ============================================================================

proc clearTransientReactor*(model: var TuiModel) =
  ## Clear transient state flags
  model.needsResize = false
  # Don't clear statusMessage here - let it persist until next action
  # It will be cleared at the start of the next present() cycle

# ============================================================================
# Context Data Reactor  
# ============================================================================

proc contextDataReactor*(model: var TuiModel) =
  ## Update context-sensitive data based on selection
  ## This could populate detail panel data, etc.
  discard  # Placeholder for future expansion

# ============================================================================
# Create All Reactors
# ============================================================================

proc createReactors*(): seq[ReactorProc[TuiModel]] =
  ## Create the standard set of reactors for the TUI
  @[
    viewportReactor,
    selectionBoundsReactor,
    statusMessageReactor,
    # clearTransientReactor,  # Run last if needed
    # contextDataReactor,
  ]
