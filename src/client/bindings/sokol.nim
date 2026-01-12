{.passC: "-DSOKOL_GLCORE33 -DSOKOL_GLCORE -DSOKOL_NO_ENTRY".}
{.passC: "-Wno-incompatible-pointer-types".}

# Link against system libraries on Linux
when defined(linux):
  {.passL: "-lGL -lX11 -lXi -lXcursor -ldl -lpthread -lm".}

# Include the C implementation
{.compile: "../c_impl.c".}

# --- Type Definitions ---

type
  sapp_desc* {.importc: "sapp_desc", header: "sokol_app.h".} = object
    init_cb*: proc() {.cdecl.}
    frame_cb*: proc() {.cdecl.}
    cleanup_cb*: proc() {.cdecl.}
    event_cb*: proc(ev: ptr sapp_event) {.cdecl.}
    width*: int32
    height*: int32
    window_title*: cstring
    logger*: sapp_logger

  sapp_event_type* {.importc: "sapp_event_type", header: "sokol_app.h".} = enum
    SAPP_EVENTTYPE_INVALID
    SAPP_EVENTTYPE_KEY_DOWN
    SAPP_EVENTTYPE_KEY_UP
    SAPP_EVENTTYPE_CHAR
    SAPP_EVENTTYPE_MOUSE_DOWN
    SAPP_EVENTTYPE_MOUSE_UP
    SAPP_EVENTTYPE_MOUSE_SCROLL
    SAPP_EVENTTYPE_MOUSE_MOVE
    SAPP_EVENTTYPE_MOUSE_ENTER
    SAPP_EVENTTYPE_MOUSE_LEAVE
    SAPP_EVENTTYPE_TOUCHES_BEGAN
    SAPP_EVENTTYPE_TOUCHES_MOVED
    SAPP_EVENTTYPE_TOUCHES_ENDED
    SAPP_EVENTTYPE_TOUCHES_CANCELLED
    SAPP_EVENTTYPE_RESIZED
    SAPP_EVENTTYPE_ICONIFIED
    SAPP_EVENTTYPE_RESTORED
    SAPP_EVENTTYPE_FOCUSED
    SAPP_EVENTTYPE_UNFOCUSED
    SAPP_EVENTTYPE_SUSPENDED
    SAPP_EVENTTYPE_RESUMED
    SAPP_EVENTTYPE_QUIT_REQUESTED
    SAPP_EVENTTYPE_CLIPBOARD_PASTED
    SAPP_EVENTTYPE_FILES_DROPPED
    SAPP_EVENTTYPE_NUM
    SAPP_EVENTTYPE_FORCE_U32 = 0x7FFFFFFF

  sapp_keycode* {.importc: "sapp_keycode", header: "sokol_app.h".} = enum
    SAPP_KEYCODE_INVALID = 0
    SAPP_KEYCODE_SPACE = 32
    SAPP_KEYCODE_APOSTROPHE = 39
    SAPP_KEYCODE_COMMA = 44
    SAPP_KEYCODE_MINUS = 45
    SAPP_KEYCODE_PERIOD = 46
    SAPP_KEYCODE_SLASH = 47
    SAPP_KEYCODE_0 = 48
    SAPP_KEYCODE_1 = 49
    SAPP_KEYCODE_2 = 50
    SAPP_KEYCODE_3 = 51
    SAPP_KEYCODE_4 = 52
    SAPP_KEYCODE_5 = 53
    SAPP_KEYCODE_6 = 54
    SAPP_KEYCODE_7 = 55
    SAPP_KEYCODE_8 = 56
    SAPP_KEYCODE_9 = 57
    SAPP_KEYCODE_SEMICOLON = 59
    SAPP_KEYCODE_EQUAL = 61
    SAPP_KEYCODE_A = 65
    SAPP_KEYCODE_B = 66
    SAPP_KEYCODE_C = 67
    SAPP_KEYCODE_D = 68
    SAPP_KEYCODE_E = 69
    SAPP_KEYCODE_F = 70
    SAPP_KEYCODE_G = 71
    SAPP_KEYCODE_H = 72
    SAPP_KEYCODE_I = 73
    SAPP_KEYCODE_J = 74
    SAPP_KEYCODE_K = 75
    SAPP_KEYCODE_L = 76
    SAPP_KEYCODE_M = 77
    SAPP_KEYCODE_N = 78
    SAPP_KEYCODE_O = 79
    SAPP_KEYCODE_P = 80
    SAPP_KEYCODE_Q = 81
    SAPP_KEYCODE_R = 82
    SAPP_KEYCODE_S = 83
    SAPP_KEYCODE_T = 84
    SAPP_KEYCODE_U = 85
    SAPP_KEYCODE_V = 86
    SAPP_KEYCODE_W = 87
    SAPP_KEYCODE_X = 88
    SAPP_KEYCODE_Y = 89
    SAPP_KEYCODE_Z = 90
    SAPP_KEYCODE_LEFT_BRACKET = 91
    SAPP_KEYCODE_BACKSLASH = 92
    SAPP_KEYCODE_RIGHT_BRACKET = 93
    SAPP_KEYCODE_GRAVE_ACCENT = 96
    SAPP_KEYCODE_WORLD_1 = 161
    SAPP_KEYCODE_WORLD_2 = 162
    SAPP_KEYCODE_ESCAPE = 256
    SAPP_KEYCODE_ENTER = 257
    SAPP_KEYCODE_TAB = 258
    SAPP_KEYCODE_BACKSPACE = 259
    SAPP_KEYCODE_INSERT = 260
    SAPP_KEYCODE_DELETE = 261
    SAPP_KEYCODE_RIGHT = 262
    SAPP_KEYCODE_LEFT = 263
    SAPP_KEYCODE_DOWN = 264
    SAPP_KEYCODE_UP = 265
    SAPP_KEYCODE_PAGE_UP = 266
    SAPP_KEYCODE_PAGE_DOWN = 267
    SAPP_KEYCODE_HOME = 268
    SAPP_KEYCODE_END = 269
    SAPP_KEYCODE_CAPS_LOCK = 280
    SAPP_KEYCODE_SCROLL_LOCK = 281
    SAPP_KEYCODE_NUM_LOCK = 282
    SAPP_KEYCODE_PRINT_SCREEN = 283
    SAPP_KEYCODE_PAUSE = 284
    SAPP_KEYCODE_F1 = 290
    SAPP_KEYCODE_F2 = 291
    SAPP_KEYCODE_F3 = 292
    SAPP_KEYCODE_F4 = 293
    SAPP_KEYCODE_F5 = 294
    SAPP_KEYCODE_F6 = 295
    SAPP_KEYCODE_F7 = 296
    SAPP_KEYCODE_F8 = 297
    SAPP_KEYCODE_F9 = 298
    SAPP_KEYCODE_F10 = 299
    SAPP_KEYCODE_F11 = 300
    SAPP_KEYCODE_F12 = 301
    SAPP_KEYCODE_F13 = 302
    SAPP_KEYCODE_F14 = 303
    SAPP_KEYCODE_F15 = 304
    SAPP_KEYCODE_F16 = 305
    SAPP_KEYCODE_F17 = 306
    SAPP_KEYCODE_F18 = 307
    SAPP_KEYCODE_F19 = 308
    SAPP_KEYCODE_F20 = 309
    SAPP_KEYCODE_F21 = 310
    SAPP_KEYCODE_F22 = 311
    SAPP_KEYCODE_F23 = 312
    SAPP_KEYCODE_F24 = 313
    SAPP_KEYCODE_F25 = 314
    SAPP_KEYCODE_KP_0 = 320
    SAPP_KEYCODE_KP_1 = 321
    SAPP_KEYCODE_KP_2 = 322
    SAPP_KEYCODE_KP_3 = 323
    SAPP_KEYCODE_KP_4 = 324
    SAPP_KEYCODE_KP_5 = 325
    SAPP_KEYCODE_KP_6 = 326
    SAPP_KEYCODE_KP_7 = 327
    SAPP_KEYCODE_KP_8 = 328
    SAPP_KEYCODE_KP_9 = 329
    SAPP_KEYCODE_KP_DECIMAL = 330
    SAPP_KEYCODE_KP_DIVIDE = 331
    SAPP_KEYCODE_KP_MULTIPLY = 332
    SAPP_KEYCODE_KP_SUBTRACT = 333
    SAPP_KEYCODE_KP_ADD = 334
    SAPP_KEYCODE_KP_ENTER = 335
    SAPP_KEYCODE_KP_EQUAL = 336
    SAPP_KEYCODE_LEFT_SHIFT = 340
    SAPP_KEYCODE_LEFT_CONTROL = 341
    SAPP_KEYCODE_LEFT_ALT = 342
    SAPP_KEYCODE_LEFT_SUPER = 343
    SAPP_KEYCODE_RIGHT_SHIFT = 344
    SAPP_KEYCODE_RIGHT_CONTROL = 345
    SAPP_KEYCODE_RIGHT_ALT = 346
    SAPP_KEYCODE_RIGHT_SUPER = 347
    SAPP_KEYCODE_MENU = 348

  sapp_event* {.importc: "sapp_event", header: "sokol_app.h".} = object
    frame_count*: uint64
    `type`*: sapp_event_type
    key_code*: sapp_keycode
    char_code*: uint32
    modifiers*: uint32
    mouse_button*: int32
    mouse_x*: float32
    mouse_y*: float32
    mouse_dx*: float32
    mouse_dy*: float32
    scroll_x*: float32
    scroll_y*: float32
    num_touches*: int32
    window_width*: int32
    window_height*: int32
    framebuffer_width*: int32
    framebuffer_height*: int32

  sapp_logger* {.importc: "sapp_logger", header: "sokol_app.h".} = object
    `func`*: proc(tag: cstring, log_level: uint32, log_item: uint32, message: cstring, line_nr: uint32, filename: cstring, user_data: pointer) {.cdecl.}
    user_data*: pointer

  sg_desc* {.importc: "sg_desc", header: "sokol_gfx.h".} = object
    environment*: sg_environment
    logger*: sg_logger

  sg_environment* {.importc: "sg_environment", header: "sokol_gfx.h".} = object
  
  sg_logger* {.importc: "sg_logger", header: "sokol_gfx.h".} = object
    `func`*: proc(tag: cstring, log_level: uint32, log_item: uint32, message: cstring, line_nr: uint32, filename: cstring, user_data: pointer) {.cdecl.}
    user_data*: pointer

  sg_pass_action* {.importc: "sg_pass_action", header: "sokol_gfx.h".} = object
    colors*: array[4, sg_color_attachment_action]

  sg_color_attachment_action* {.importc: "sg_color_attachment_action", header: "sokol_gfx.h".} = object
    load_action*: sg_load_action
    clear_value*: sg_color

  sg_load_action* {.importc: "sg_load_action", header: "sokol_gfx.h".} = enum
    SG_LOADACTION_CLEAR
    SG_LOADACTION_LOAD
    SG_LOADACTION_DONTCARE

  sg_color* {.importc: "sg_color", header: "sokol_gfx.h".} = object
    r*, g*, b*, a*: float32

  sg_pass* {.importc: "sg_pass", header: "sokol_gfx.h".} = object
    action*: sg_pass_action
    swapchain*: sg_swapchain

  sg_swapchain* {.importc: "sg_swapchain", header: "sokol_gfx.h".} = object

# --- Sokol Functions ---

proc sapp_run*(desc: ptr sapp_desc) {.importc: "sapp_run", header: "sokol_app.h".}
proc sapp_width*(): int32 {.importc: "sapp_width", header: "sokol_app.h".}
proc sapp_height*(): int32 {.importc: "sapp_height", header: "sokol_app.h".}
proc sapp_quit*() {.importc: "sapp_quit", header: "sokol_app.h".}

proc sg_setup*(desc: ptr sg_desc) {.importc: "sg_setup", header: "sokol_gfx.h".}
proc sg_shutdown*() {.importc: "sg_shutdown", header: "sokol_gfx.h".}
proc sg_begin_pass*(pass: ptr sg_pass) {.importc: "sg_begin_pass", header: "sokol_gfx.h".}
proc sg_end_pass*() {.importc: "sg_end_pass", header: "sokol_gfx.h".}
proc sg_commit*() {.importc: "sg_commit", header: "sokol_gfx.h".}

proc sglue_environment*(): sg_environment {.importc: "sglue_environment", header: "sokol_glue.h".}
proc sglue_swapchain*(): sg_swapchain {.importc: "sglue_swapchain", header: "sokol_glue.h".}

proc slog_func*(tag: cstring, log_level: uint32, log_item: uint32, message: cstring, line_nr: uint32, filename: cstring, user_data: pointer) {.cdecl, importc: "slog_func", header: "sokol_log.h".}
