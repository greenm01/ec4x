import std/logging
import ./core/sam
import ./model/state
import ./logic/[acceptors, reactors]
import ./ui/view
import ./bindings/[sokol, sokol_nuklear]

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

  # Setup Sokol Nuklear
  var snkDesc: snk_desc_t
  snkDesc.dpi_scale = 1.0 # TODO: Get from sapp_dpi_scale()
  snkDesc.logger.`func` = slog_func
  snk_setup(addr snkDesc)

  # Init SAM Loop
  appLoop = newSamLoop(initClientModel())
  appLoop.addAcceptor(defaultAcceptor)
  appLoop.addReactor(debugReactor)
  
  info "Client Initialized"

proc frame() {.cdecl.} =
  # SAM Process
  appLoop.process()

  # Nuklear Frame
  let ctx = snk_new_frame()

  # Render View (generates proposals)
  view.render(ctx, appLoop.model, proc(p: Proposal[ClientModel]) =
    appLoop.present(p)
  )

  # Sokol GFX Pass
  var pass: sg_pass
  pass.action.colors[0].load_action = SG_LOADACTION_CLEAR
  pass.action.colors[0].clear_value = sg_color(r: 0.1, g: 0.1, b: 0.12, a: 1.0)
  pass.swapchain = sglue_swapchain()
  
  sg_begin_pass(addr pass)
  snk_render(sapp_width(), sapp_height())
  sg_end_pass()
  sg_commit()

proc event(ev: ptr sapp_event) {.cdecl.} =
  # Forward events to Nuklear
  discard snk_handle_event(ev)

proc cleanup() {.cdecl.} =
  snk_shutdown()
  sg_shutdown()

# --- Main ---

proc main() =
  addHandler(newConsoleLogger(fmtStr="[$time] - $levelname: "))
  
  var desc: sapp_desc
  desc.init_cb = init
  desc.frame_cb = frame
  desc.cleanup_cb = cleanup
  desc.event_cb = event
  desc.width = 1024
  desc.height = 768
  desc.window_title = "EC4X Client"
  desc.logger.`func` = slog_func
  
  sapp_run(addr desc)

main()
