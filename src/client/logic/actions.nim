import ../core/sam
import ../model/state

# Helper to create proposals easily
proc createProposal*(name: string, mutator: proc(m: var ClientModel)): Proposal[ClientModel] =
  result = Proposal[ClientModel](
    name: name,
    payload: mutator
  )

# --- Actions ---

proc incrementCounter*(): Proposal[ClientModel] =
  createProposal("IncrementCounter", proc(m: var ClientModel) =
    m.ui.debugCounter += 1
  )

proc navigateTo*(screen: Screen): Proposal[ClientModel] =
  createProposal("NavigateTo-" & $screen, proc(m: var ClientModel) =
    m.ui.currentScreen = screen
  )

proc updateLoginField*(url: string, username: string): Proposal[ClientModel] =
  createProposal("UpdateLogin", proc(m: var ClientModel) =
    m.ui.loginUrl = url
    m.ui.loginUsername = username
  )
