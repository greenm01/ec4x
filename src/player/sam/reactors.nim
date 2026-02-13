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

import std/strformat
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
  let visibleWidth = max(1, (model.ui.termWidth - 40) div HexWidth)
  let visibleHeight = max(1, model.ui.termHeight - 10)
  
  # Get current cursor and viewport
  let cursor = model.ui.mapState.cursor
  let vpOrigin = model.ui.mapState.viewportOrigin
  
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
  
  model.ui.mapState.viewportOrigin = (newQ, newR)

# ============================================================================
# Selection Bounds Reactor
# ============================================================================

proc selectionBoundsReactor*(model: var TuiModel) =
  ## Clamp selection index to valid range
  let maxIdx = model.currentListLength() - 1
  if maxIdx < 0:
    model.ui.selectedIdx = 0
  elif model.ui.selectedIdx > maxIdx:
    model.ui.selectedIdx = maxIdx
  elif model.ui.selectedIdx < 0:
    model.ui.selectedIdx = 0

# ============================================================================
# Status Message Reactor
# ============================================================================

proc statusMessageReactor*(model: var TuiModel) =
  ## Update status message based on current state
  ## Only updates if not already set by an action
  
  # Show staged command count if we have any
  let stagedCount = model.stagedCommandCount()
  if stagedCount > 0 and model.ui.statusMessage.len == 0:
    model.ui.statusMessage =
      &"{stagedCount} command(s) staged | :submit to submit turn"
    return
  
  if model.ui.statusMessage.len == 0:
    if model.ui.expertModeFeedback.len > 0:
      model.ui.statusMessage = model.ui.expertModeFeedback
      return
    case model.ui.mode
    of ViewMode.Overview:
      model.ui.statusMessage = "Strategic Overview"
    
    of ViewMode.Planets:
      if model.view.colonies.len > 0:
        model.ui.statusMessage = &"{model.view.colonies.len} colonies"
      else:
        model.ui.statusMessage = "No colonies"
    
    of ViewMode.Fleets:
      if model.view.fleets.len > 0:
        model.ui.statusMessage = &"{model.view.fleets.len} fleets"
      else:
        model.ui.statusMessage = "No fleets"
    
    of ViewMode.Research:
      model.ui.statusMessage = "Research & Technology"
    
    of ViewMode.Espionage:
      model.ui.statusMessage = "Espionage Operations"
    
    of ViewMode.Economy:
      model.ui.statusMessage = "Empire Economy"
    
    of ViewMode.Reports:
      model.ui.statusMessage = "Reports Inbox"
    
    of ViewMode.IntelDb:
      model.ui.statusMessage = "Intel Database"
    of ViewMode.IntelDetail:
      model.ui.statusMessage = "Intel System Detail"

    of ViewMode.Messages:
      model.ui.statusMessage = "Messages"


    of ViewMode.Settings:
      model.ui.statusMessage = "Game Settings"
    
    of ViewMode.PlanetDetail:
      model.ui.statusMessage = "Planet Details"
    
    of ViewMode.FleetDetail:
      model.ui.statusMessage = "Fleet Details"
    
    of ViewMode.ReportDetail:
      model.ui.statusMessage = "Report Details"

# ============================================================================
# Clear Transient State Reactor
# ============================================================================

proc clearTransientReactor*(model: var TuiModel) =
  ## Clear transient state flags
  model.ui.needsResize = false
  # Don't clear statusMessage here - let it persist until next action
  # It will be cleared at the start of the next present() cycle
  if not model.ui.expertModeActive:
    model.clearExpertFeedback()

# ============================================================================
# Context Data Reactor  
# ============================================================================

proc contextDataReactor*(model: var TuiModel) =
  ## Update context-sensitive data based on selection
  ## This could populate detail panel data, etc.
  discard  # Placeholder for future expansion

# ============================================================================
# Turn Submission Reactor
# ============================================================================

proc turnSubmissionReactor*(model: var TuiModel) =
  ## Handle turn submission flag set by acceptor
  ## Requires confirmation before setting turnSubmissionPending
  if model.ui.turnSubmissionRequested:
    # Check if already confirmed (via :submit command or second submit)
    if model.ui.turnSubmissionConfirmed:
      model.ui.turnSubmissionPending = true
      model.ui.turnSubmissionRequested = false
      model.ui.turnSubmissionConfirmed = false
    else:
      # First press - ask for confirmation
      let count = model.stagedCommandCount()
      model.ui.statusMessage = "Type :submit again to confirm submitting " &
        $count & " commands, or :clear to cancel"
      model.ui.turnSubmissionConfirmed = true
      model.ui.turnSubmissionRequested = false

# ============================================================================
# Create All Reactors
# ============================================================================

proc createReactors*(): seq[ReactorProc[TuiModel]] =
  ## Create the standard set of reactors for the TUI
  @[
    viewportReactor,
    selectionBoundsReactor,
    statusMessageReactor,
    turnSubmissionReactor,
    # clearTransientReactor,  # Run last if needed
    # contextDataReactor,
  ]
