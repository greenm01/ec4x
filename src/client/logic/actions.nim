import std/options
import ../core/sam
import ../model/state
import ../starmap/[hex_math, camera, input]

# Helper to create proposals easily
proc createProposal*(name: string,
    mutator: proc(m: var ClientModel)): Proposal[ClientModel] =
  result = Proposal[ClientModel](
    name: name,
    payload: mutator
  )

# --- UI Actions ---

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

# --- Starmap Actions ---

proc zoomStarmap*(zoomDelta: float32, screenPos: Vec2): Proposal[ClientModel] =
  createProposal("ZoomStarmap", proc(m: var ClientModel) =
    m.starmap.camera.zoomAt(screenPos, zoomDelta)
  )

proc panStarmap*(delta: Vec2): Proposal[ClientModel] =
  createProposal("PanStarmap", proc(m: var ClientModel) =
    m.starmap.camera.pan(delta)
  )

proc hoverSystem*(hex: Option[HexCoord]): Proposal[ClientModel] =
  createProposal("HoverSystem", proc(m: var ClientModel) =
    m.starmap.hoveredSystem = hex
    m.starmap.renderData.hoveredSystem = hex
  )

proc selectSystem*(hex: Option[HexCoord]): Proposal[ClientModel] =
  createProposal("SelectSystem", proc(m: var ClientModel) =
    m.starmap.selectedSystem = hex
    m.starmap.renderData.selectedSystem = hex
  )

proc deselectSystem*(): Proposal[ClientModel] =
  createProposal("DeselectSystem", proc(m: var ClientModel) =
    m.starmap.selectedSystem = none(HexCoord)
    m.starmap.renderData.selectedSystem = none(HexCoord)
  )

proc updateStarmapCamera*(screenWidth, screenHeight: int32): Proposal[ClientModel] =
  createProposal("UpdateCamera", proc(m: var ClientModel) =
    m.starmap.camera.updateOffset(screenWidth, screenHeight)
  )

proc processStarmapAction*(action: StarmapAction): Proposal[ClientModel] =
  ## Convert a StarmapAction to a SAM Proposal.
  case action.kind
  of OnZoom:
    zoomStarmap(action.zoomDelta, action.zoomPos)
  of OnPan:
    panStarmap(action.panDelta)
  of OnHover:
    hoverSystem(action.hoverHex)
  of OnSelect:
    selectSystem(action.selectHex)
  of OnDeselect:
    deselectSystem()
  of OnNone:
    # No-op proposal
    createProposal("Noop", proc(m: var ClientModel) = discard)
