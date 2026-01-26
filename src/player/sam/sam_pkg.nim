## SAM Pattern Package for EC4X TUI
##
## This module exports all SAM components for use in the TUI player.
## 
## Usage:
##   import sam/sam_pkg
##   
##   # Create SAM instance
##   var sam = initSam[TuiModel]()
##   
##   # Configure with acceptors, reactors, NAPs
##   for a in createAcceptors():
##     sam.addAcceptor(a)
##   for r in createReactors():
##     sam.addReactor(r)
##   for n in createNaps():
##     sam.addNap(n)
##   
##   # Set render function
##   sam.setRender(myRenderProc)
##   
##   # Set initial state
##   sam.setInitialState(initTuiModel())
##   
##   # Main loop - convert events to proposals
##   let proposal = mapKeyToAction(key, sam.state)
##   if proposal.isSome:
##     sam.present(proposal.get)

import ./types
import ./instance
import ./tui_model
import ./actions
import ./bindings
import ./acceptors
import ./reactors
import ./naps

export types
export instance
export tui_model
export actions
export bindings
export acceptors
export reactors
export naps

# ============================================================================
# Convenience: Create Fully Configured SAM Instance
# ============================================================================

proc initTuiSam*(withHistory: bool = false,
  maxHistory: int = 100): SamInstance[TuiModel] =
  ## Create a fully configured SAM instance for the TUI
  if withHistory:
    result = initSamWithHistory[TuiModel](maxHistory)
  else:
    result = initSam[TuiModel]()
  
  # Add all acceptors
  for acceptor in createAcceptors():
    result.addAcceptor(acceptor)
  
  # Add all reactors
  for reactor in createReactors():
    result.addReactor(reactor)
  
  # Add all NAPs
  for nap in createNaps():
    result.addNap(nap)
