import ../core/sam
import ../model/state
import std/logging

proc debugReactor*(model: ClientModel, dispatch: proc(p: Proposal[ClientModel])) =
  ## Logs state changes
  debug "Current Screen: ", model.ui.currentScreen
  debug "Counter: ", model.ui.debugCounter
