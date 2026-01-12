import ./nuklear
import ./sokol

# Use wrapper header to ensure correct inclusion order
const snkHeader = "snk_wrapper.h"

type
  snk_desc_t* {.importc: "snk_desc_t", header: snkHeader.} = object
    max_vertices*: int32
    image_pool_size*: int32
    # We skip detailed binding of formats/allocators for now as we use defaults
    dpi_scale*: float32
    logger*: snk_logger_t

  snk_logger_t* {.importc: "snk_logger_t", header: snkHeader.} = object
    `func`*: proc(tag: cstring, log_level: uint32, log_item: uint32,
                  message: cstring, line_nr: uint32, filename: cstring,
                  user_data: pointer) {.cdecl.}
    user_data*: pointer

# --- Functions ---

proc snk_setup*(desc: ptr snk_desc_t) {.importc, header: snkHeader.}
proc snk_new_frame*(): ptr nk_context {.importc, header: snkHeader.}
proc snk_render*(width, height: int32) {.importc, header: snkHeader.}
proc snk_handle_event*(ev: ptr sapp_event): bool {.importc, header: snkHeader.}
proc snk_shutdown*() {.importc, header: snkHeader.}
