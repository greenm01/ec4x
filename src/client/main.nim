import std/logging
import ./core/sam
import ./model/state
import ./logic/[acceptors, reactors, actions]
import ./ui/view
import ./bindings/[sokol, sokol_nuklear, sokol_gl]
import ./starmap/[hex_math, camera, theme, renderer, input]

# --- Global State ---
# Sokol callbacks are C-style and don't accept closures/context, so we need a global
var appLoop: SamLoop[ClientModel]

# --- Callbacks ---

proc init() {.cdecl.} =
  # Setup Sokol GFX
  var gfxDesc: sg_desc
  gfxDesc.environment = sglue_environment()
  gfxDesc.logger.`func` = slog_func
  sg_setup(addr gfxDesc)

  # Setup Sokol GL (for starmap rendering)
  var sglDesc: sgl_desc_t
  sglDesc.logger.`func` = slog_func
  sgl_setup(addr sglDesc)

  # Setup Sokol Nuklear
  var snkDesc: snk_desc_t
  snkDesc.dpi_scale = 1.0 # TODO: Get from sapp_dpi_scale()
  snkDesc.logger.`func` = slog_func
  snk_setup(addr snkDesc)

  # Init SAM Loop with screen dimensions
  appLoop = newSamLoop(initClientModel(sapp_width(), sapp_height()))
  appLoop.addAcceptor(defaultAcceptor)
  appLoop.addReactor(debugReactor)

  info "Client Initialized"

proc frame() {.cdecl.} =
  # SAM Process
  appLoop.process()

  # Sokol GFX Pass - clear screen
  var pass: sg_pass
  pass.action.colors[0].load_action = SG_LOADACTION_CLEAR
  # Use theme background color
  let bg = appLoop.model.starmap.theme.backgroundColor
  pass.action.colors[0].clear_value = sg_color(r: bg.r, g: bg.g, b: bg.b, a: 1.0)
  pass.swapchain = sglue_swapchain()

  sg_begin_pass(addr pass)

  # Render starmap (when on Starmap screen)
  if appLoop.model.ui.currentScreen == Screen.Starmap:
    renderStarmap(
      appLoop.model.starmap.renderData,
      appLoop.model.starmap.camera,
      appLoop.model.starmap.theme,
      sapp_width(),
      sapp_height()
    )

  # Nuklear Frame (UI on top of starmap)
  let ctx = snk_new_frame()

  # Render View (generates proposals)
  view.render(ctx, appLoop.model, proc(p: Proposal[ClientModel]) =
    appLoop.present(p)
  )

  snk_render(sapp_width(), sapp_height())
  sg_end_pass()
  sg_commit()

proc event(ev: ptr sapp_event) {.cdecl.} =
  # Forward events to Nuklear first
  let handled = snk_handle_event(ev)

  # If Nuklear didn't handle it and we're on starmap, handle starmap input
  if not handled and appLoop.model.ui.currentScreen == Screen.Starmap:
    var action: StarmapAction

    case ev.`type`
    of SAPP_EVENTTYPE_MOUSE_SCROLL:
      action = handleMouseWheel(ev.scroll_y, vec2(ev.mouse_x, ev.mouse_y))

    of SAPP_EVENTTYPE_MOUSE_MOVE:
      action = handleMouseMove(
        appLoop.model.starmap.inputState,
        ev.mouse_x, ev.mouse_y,
        appLoop.model.starmap.camera,
        appLoop.model.starmap.renderData
      )

    of SAPP_EVENTTYPE_MOUSE_DOWN:
      let button = MouseButton(ev.mouse_button)
      action = handleMouseDown(
        appLoop.model.starmap.inputState,
        button,
        ev.mouse_x, ev.mouse_y
      )

    of SAPP_EVENTTYPE_MOUSE_UP:
      let button = MouseButton(ev.mouse_button)
      action = handleMouseUp(
        appLoop.model.starmap.inputState,
        button,
        ev.mouse_x, ev.mouse_y,
        appLoop.model.starmap.camera,
        appLoop.model.starmap.renderData
      )

    of SAPP_EVENTTYPE_KEY_DOWN:
      action = handleKeyDown(ev.key_code.int)

    of SAPP_EVENTTYPE_RESIZED:
      appLoop.present(updateStarmapCamera(ev.window_width, ev.window_height))
      return

    else:
      discard

    # Dispatch starmap action if any
    if action.kind != OnNone:
      appLoop.present(processStarmapAction(action))

proc cleanup() {.cdecl.} =
  snk_shutdown()
  sgl_shutdown()
  sg_shutdown()

# --- Main ---

proc main() =
  addHandler(newConsoleLogger(fmtStr="[$time] - $levelname: "))

  var desc: sapp_desc
  desc.init_cb = init
  desc.frame_cb = frame
  desc.cleanup_cb = cleanup
  desc.event_cb = event
  desc.width = 1280
  desc.height = 720
  desc.window_title = "EC4X Client"
  desc.logger.`func` = slog_func

  sapp_run(addr desc)

main()
