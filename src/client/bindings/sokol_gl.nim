## Nim bindings for sokol_gl.h
## Immediate-mode 2D/3D drawing API on top of sokol_gfx.h

import sokol  # Import sokol types to use them

# Use combined header that includes gfx before gl
const SglHeader = "sokol_gl_combined.h"

# --- Types ---

type
  sgl_desc_t* {.importc: "sgl_desc_t", header: SglHeader.} = object
    max_vertices*: int32
    max_commands*: int32
    color_format*: int32
    depth_format*: int32
    sample_count*: int32
    logger*: sgl_logger_t

  sgl_logger_t* {.importc: "sgl_logger_t", header: SglHeader.} = object
    `func`*: proc(tag: cstring, log_level: uint32, log_item: uint32,
                  message: cstring, line_nr: uint32, filename: cstring,
                  user_data: pointer) {.cdecl.}
    user_data*: pointer

  sgl_pipeline* {.importc: "sgl_pipeline", header: SglHeader.} = object
    id*: uint32

  sgl_context* {.importc: "sgl_context", header: SglHeader.} = object
    id*: uint32

  sgl_error_t* {.importc: "sgl_error", header: SglHeader, pure.} = enum
    SGL_NO_ERROR = 0
    SGL_ERROR_VERTICES_FULL
    SGL_ERROR_UNIFORMS_FULL
    SGL_ERROR_COMMANDS_FULL
    SGL_ERROR_STACK_OVERFLOW
    SGL_ERROR_STACK_UNDERFLOW
    SGL_ERROR_NO_CONTEXT

# --- Setup/Shutdown ---

proc sgl_setup*(desc: ptr sgl_desc_t) {.importc: "sgl_setup", header: SglHeader.}
proc sgl_shutdown*() {.importc: "sgl_shutdown", header: SglHeader.}

# --- Error handling ---

proc sgl_get_error*(): sgl_error_t {.importc: "sgl_error", header: SglHeader.}

# --- Rendering ---

proc sgl_defaults*() {.importc: "sgl_defaults", header: SglHeader.}
proc sgl_draw*() {.importc: "sgl_draw", header: SglHeader.}

# --- Matrix Stack ---

proc sgl_matrix_mode_modelview*() {.importc: "sgl_matrix_mode_modelview",
    header: SglHeader.}
proc sgl_matrix_mode_projection*() {.importc: "sgl_matrix_mode_projection",
    header: SglHeader.}
proc sgl_matrix_mode_texture*() {.importc: "sgl_matrix_mode_texture",
    header: SglHeader.}

proc sgl_load_identity*() {.importc: "sgl_load_identity", header: SglHeader.}
proc sgl_push_matrix*() {.importc: "sgl_push_matrix", header: SglHeader.}
proc sgl_pop_matrix*() {.importc: "sgl_pop_matrix", header: SglHeader.}

proc sgl_translate*(x, y, z: cfloat) {.importc: "sgl_translate",
    header: SglHeader.}
proc sgl_rotate*(angle, x, y, z: cfloat) {.importc: "sgl_rotate",
    header: SglHeader.}
proc sgl_scale*(x, y, z: cfloat) {.importc: "sgl_scale", header: SglHeader.}

proc sgl_ortho*(l, r, b, t, n, f: cfloat) {.importc: "sgl_ortho",
    header: SglHeader.}
proc sgl_frustum*(l, r, b, t, n, f: cfloat) {.importc: "sgl_frustum",
    header: SglHeader.}
proc sgl_perspective*(fov_y, aspect, z_near, z_far: cfloat)
    {.importc: "sgl_perspective", header: SglHeader.}
proc sgl_lookat*(eye_x, eye_y, eye_z, center_x, center_y, center_z,
    up_x, up_y, up_z: cfloat) {.importc: "sgl_lookat", header: SglHeader.}

# --- Primitive Types ---

proc sgl_begin_points*() {.importc: "sgl_begin_points", header: SglHeader.}
proc sgl_begin_lines*() {.importc: "sgl_begin_lines", header: SglHeader.}
proc sgl_begin_line_strip*() {.importc: "sgl_begin_line_strip",
    header: SglHeader.}
proc sgl_begin_triangles*() {.importc: "sgl_begin_triangles",
    header: SglHeader.}
proc sgl_begin_triangle_strip*() {.importc: "sgl_begin_triangle_strip",
    header: SglHeader.}
proc sgl_begin_quads*() {.importc: "sgl_begin_quads", header: SglHeader.}
proc sgl_end*() {.importc: "sgl_end", header: SglHeader.}

# --- Vertex Specification ---

proc sgl_v2f*(x, y: cfloat) {.importc: "sgl_v2f", header: SglHeader.}
proc sgl_v3f*(x, y, z: cfloat) {.importc: "sgl_v3f", header: SglHeader.}
proc sgl_v2f_t2f*(x, y, u, v: cfloat) {.importc: "sgl_v2f_t2f",
    header: SglHeader.}
proc sgl_v3f_t2f*(x, y, z, u, v: cfloat) {.importc: "sgl_v3f_t2f",
    header: SglHeader.}
proc sgl_v2f_c3f*(x, y, r, g, b: cfloat) {.importc: "sgl_v2f_c3f",
    header: SglHeader.}
proc sgl_v2f_c4f*(x, y, r, g, b, a: cfloat) {.importc: "sgl_v2f_c4f",
    header: SglHeader.}
proc sgl_v3f_c4f*(x, y, z, r, g, b, a: cfloat) {.importc: "sgl_v3f_c4f",
    header: SglHeader.}
proc sgl_v2f_c3b*(x, y: cfloat; r, g, b: uint8) {.importc: "sgl_v2f_c3b",
    header: SglHeader.}
proc sgl_v2f_c4b*(x, y: cfloat; r, g, b, a: uint8) {.importc: "sgl_v2f_c4b",
    header: SglHeader.}

# --- Color ---

proc sgl_c3f*(r, g, b: cfloat) {.importc: "sgl_c3f", header: SglHeader.}
proc sgl_c4f*(r, g, b, a: cfloat) {.importc: "sgl_c4f", header: SglHeader.}
proc sgl_c3b*(r, g, b: uint8) {.importc: "sgl_c3b", header: SglHeader.}
proc sgl_c4b*(r, g, b, a: uint8) {.importc: "sgl_c4b", header: SglHeader.}
proc sgl_c1i*(rgba: uint32) {.importc: "sgl_c1i", header: SglHeader.}

# --- Texture Coordinates ---

proc sgl_t2f*(u, v: cfloat) {.importc: "sgl_t2f", header: SglHeader.}

# --- State ---

proc sgl_enable_texture*() {.importc: "sgl_enable_texture",
    header: SglHeader.}
proc sgl_disable_texture*() {.importc: "sgl_disable_texture",
    header: SglHeader.}

# --- Viewport/Scissor ---

proc sgl_viewport*(x, y, w, h: int32; origin_top_left: bool)
    {.importc: "sgl_viewport", header: SglHeader.}
proc sgl_scissor_rect*(x, y, w, h: int32; origin_top_left: bool)
    {.importc: "sgl_scissor_rect", header: SglHeader.}

# --- Point Size ---

proc sgl_point_size*(s: cfloat) {.importc: "sgl_point_size",
    header: SglHeader.}

# --- Convenience: Default setup ---

proc sglSetupDefaults*(): sgl_desc_t =
  ## Returns a default sgl_desc_t for easy setup
  result = sgl_desc_t()
  # All zeros = use defaults
