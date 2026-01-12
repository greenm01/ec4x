import ../bindings/nuklear
import ../core/sam
import ../model/state
import ../logic/actions

proc renderLogin(ctx: ptr nk_context, model: ClientModel, dispatch: proc(p: Proposal[ClientModel])) =
  if nk_begin(ctx, "Login", nk_make_rect(50, 50, 400, 300), NK_WINDOW_BORDER or NK_WINDOW_MOVABLE or NK_WINDOW_TITLE):
    nk_layout_row_dynamic(ctx, 30, 1)
    nk_label(ctx, "EC4X - Login", NK_TEXT_CENTERED)
    
    nk_layout_row_dynamic(ctx, 30, 1)
    if nk_button_label(ctx, "Connect to Localhost"):
      dispatch(navigateTo(Screen.Dashboard))
      
  nk_end(ctx)

proc renderDashboard(ctx: ptr nk_context, model: ClientModel, dispatch: proc(p: Proposal[ClientModel])) =
  if nk_begin(ctx, "Dashboard", nk_make_rect(50, 50, 400, 300), NK_WINDOW_BORDER or NK_WINDOW_MOVABLE or NK_WINDOW_TITLE):
    nk_layout_row_dynamic(ctx, 30, 1)
    nk_label(ctx, "Dashboard", NK_TEXT_CENTERED)
    
    nk_layout_row_dynamic(ctx, 30, 1)
    # Using a constructed string for the label
    var countStr = "Counter: " & $model.ui.debugCounter
    nk_label(ctx, countStr.cstring, NK_TEXT_LEFT)
    
    nk_layout_row_dynamic(ctx, 30, 2)
    if nk_button_label(ctx, "Increment"):
      dispatch(incrementCounter())
      
    if nk_button_label(ctx, "Logout"):
      dispatch(navigateTo(Screen.Login))
      
  nk_end(ctx)

proc render*(ctx: ptr nk_context, model: ClientModel, dispatch: proc(p: Proposal[ClientModel])) =
  case model.ui.currentScreen
  of Screen.Login:
    renderLogin(ctx, model, dispatch)
  of Screen.Dashboard:
    renderDashboard(ctx, model, dispatch)
  else:
    if nk_begin(ctx, "Error", nk_make_rect(100, 100, 200, 100), NK_WINDOW_BORDER or NK_WINDOW_MOVABLE):
      nk_layout_row_dynamic(ctx, 30, 1)
      nk_label(ctx, "Not Implemented", NK_TEXT_CENTERED)
      if nk_button_label(ctx, "Back"):
        dispatch(navigateTo(Screen.Login))
    nk_end(ctx)
