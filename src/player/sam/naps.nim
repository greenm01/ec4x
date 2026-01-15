## TUI NAPs (Next-Action Predicates)
##
## NAPs run after reactors and can trigger automatic actions.
## If a NAP returns Some(Proposal), that proposal is immediately
## presented, skipping the render step. This enables automatic
## state machine transitions.
##
## Common uses:
## - Auto-scroll when cursor at edge
## - Auto-advance after certain actions
## - Chain dependent actions
## - Implement game logic sequences
##
## NAP signature: proc(model: M): Option[Proposal]

import std/[options]
import ./types
import ./tui_model
import ./actions

export types, tui_model, actions

# ============================================================================
# Auto-Center on Selection NAP
# ============================================================================

proc autoCenterNap*(model: TuiModel): Option[Proposal] =
  ## If a coordinate was just selected and it's far from cursor,
  ## center on it. (Currently disabled - cursor follows user input)
  none(Proposal)

# ============================================================================
# Turn End Processing NAP
# ============================================================================

proc turnEndNap*(model: TuiModel): Option[Proposal] =
  ## After turn ends, trigger any automatic state updates
  ## This is where AI turns, events, etc. could be triggered
  # For now, no automatic action
  none(Proposal)

# ============================================================================
# List Empty Redirect NAP
# ============================================================================

proc listEmptyRedirectNap*(model: TuiModel): Option[Proposal] =
  ## If viewing an empty list, redirect to map view
  case model.mode
  of ViewMode.Colonies:
    if model.colonies.len == 0:
      return some(actionSwitchMode(ViewMode.Map))
  of ViewMode.Fleets:
    if model.fleets.len == 0:
      return some(actionSwitchMode(ViewMode.Map))
  of ViewMode.Orders:
    # Orders can be empty - that's fine
    discard
  of ViewMode.Map:
    discard
  
  none(Proposal)

# ============================================================================
# Create All NAPs
# ============================================================================

proc createNaps*(): seq[NapProc[TuiModel]] =
  ## Create the standard set of NAPs for the TUI
  ## Note: NAPs are run in order, first one that returns Some wins
  @[
    # autoCenterNap,       # Disabled
    # turnEndNap,          # Placeholder
    # listEmptyRedirectNap # Can be enabled for UX improvement
  ]
