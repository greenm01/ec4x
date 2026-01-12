import std/[strformat, options]
import ../bindings/nuklear
import ../core/sam
import ../model/state
import ../logic/actions

proc renderLogin(ctx: ptr nk_context, model: ClientModel,
    dispatch: proc(p: Proposal[ClientModel])) =
  let flags = NK_WINDOW_BORDER or NK_WINDOW_MOVABLE or NK_WINDOW_TITLE
  if nk_begin(ctx, "Login", nk_make_rect(50, 50, 400, 300), flags):
    nk_layout_row_dynamic(ctx, 30, 1)
    nk_label(ctx, "EC4X - Login", NK_TEXT_CENTERED)

    nk_layout_row_dynamic(ctx, 30, 1)
    if nk_button_label(ctx, "Connect to Localhost"):
      dispatch(navigateTo(Screen.Starmap))

  nk_end(ctx)

proc renderDashboard(ctx: ptr nk_context, model: ClientModel,
    dispatch: proc(p: Proposal[ClientModel])) =
  let flags = NK_WINDOW_BORDER or NK_WINDOW_MOVABLE or NK_WINDOW_TITLE
  if nk_begin(ctx, "Dashboard", nk_make_rect(50, 50, 400, 300), flags):
    nk_layout_row_dynamic(ctx, 30, 1)
    nk_label(ctx, "Dashboard", NK_TEXT_CENTERED)

    nk_layout_row_dynamic(ctx, 30, 1)
    var countStr = "Counter: " & $model.ui.debugCounter
    nk_label(ctx, countStr.cstring, NK_TEXT_LEFT)

    nk_layout_row_dynamic(ctx, 30, 2)
    if nk_button_label(ctx, "Increment"):
      dispatch(incrementCounter())

    if nk_button_label(ctx, "Starmap"):
      dispatch(navigateTo(Screen.Starmap))

    nk_layout_row_dynamic(ctx, 30, 1)
    if nk_button_label(ctx, "Logout"):
      dispatch(navigateTo(Screen.Login))

  nk_end(ctx)

proc renderStarmapUI(ctx: ptr nk_context, model: ClientModel,
    dispatch: proc(p: Proposal[ClientModel])) =
  ## Render UI overlay for starmap screen.
  ## The actual starmap is rendered via sokol_gl in main.nim

  # Top-left info panel
  let flags = NK_WINDOW_BORDER or NK_WINDOW_NO_SCROLLBAR
  if nk_begin(ctx, "Starmap Info", nk_make_rect(10, 10, 200, 120), flags):
    nk_layout_row_dynamic(ctx, 20, 1)
    nk_label(ctx, "Starmap View", NK_TEXT_LEFT)

    nk_layout_row_dynamic(ctx, 20, 1)
    let zoomStr = fmt"Zoom: {model.starmap.camera.zoom:.2f}x"
    nk_label(ctx, zoomStr.cstring, NK_TEXT_LEFT)

    # Show selected system info
    if model.starmap.selectedSystem.isSome:
      let hex = model.starmap.selectedSystem.get
      let coordStr = fmt"Selected: ({hex.q}, {hex.r})"
      nk_layout_row_dynamic(ctx, 20, 1)
      nk_label(ctx, coordStr.cstring, NK_TEXT_LEFT)

    nk_layout_row_dynamic(ctx, 25, 1)
    if nk_button_label(ctx, "Back"):
      dispatch(navigateTo(Screen.Login))

  nk_end(ctx)

  # Help text at bottom
  let helpFlags = NK_WINDOW_NO_SCROLLBAR.uint32
  if nk_begin(ctx, "Help", nk_make_rect(10, 650, 300, 60), helpFlags):
    nk_layout_row_dynamic(ctx, 15, 1)
    nk_label(ctx, "Scroll: Zoom | Middle-drag: Pan", NK_TEXT_LEFT)
    nk_label(ctx, "Left-click: Select | Esc: Deselect", NK_TEXT_LEFT)
  nk_end(ctx)

proc render*(ctx: ptr nk_context, model: ClientModel,
    dispatch: proc(p: Proposal[ClientModel])) =
  case model.ui.currentScreen
  of Screen.Login:
    renderLogin(ctx, model, dispatch)
  of Screen.Dashboard:
    renderDashboard(ctx, model, dispatch)
  of Screen.Starmap:
    renderStarmapUI(ctx, model, dispatch)
  else:
    let flags = NK_WINDOW_BORDER or NK_WINDOW_MOVABLE
    if nk_begin(ctx, "Error", nk_make_rect(100, 100, 200, 100), flags):
      nk_layout_row_dynamic(ctx, 30, 1)
      nk_label(ctx, "Not Implemented", NK_TEXT_CENTERED)
      if nk_button_label(ctx, "Back"):
        dispatch(navigateTo(Screen.Login))
    nk_end(ctx)
