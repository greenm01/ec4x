# Nuklear bindings - implementation is in c_impl.c

type
  nk_context* {.importc: "struct nk_context", header: "nuklear.h".} = object
  
  nk_rect* {.importc: "struct nk_rect", header: "nuklear.h".} = object
    x*, y*, w*, h*: float32

  nk_flags* = uint32

const
  NK_WINDOW_BORDER* = 1.nk_flags
  NK_WINDOW_MOVABLE* = 2.nk_flags
  NK_WINDOW_SCALABLE* = 4.nk_flags
  NK_WINDOW_CLOSABLE* = 8.nk_flags
  NK_WINDOW_MINIMIZABLE* = 16.nk_flags
  NK_WINDOW_NO_SCROLLBAR* = 32.nk_flags
  NK_WINDOW_TITLE* = 64.nk_flags
  NK_WINDOW_SCROLL_AUTO_HIDE* = 128.nk_flags
  NK_WINDOW_BACKGROUND* = 256.nk_flags
  NK_WINDOW_SCALE_LEFT* = 512.nk_flags
  NK_WINDOW_NO_INPUT* = 1024.nk_flags

  NK_TEXT_LEFT* = 0x01.nk_flags
  NK_TEXT_CENTERED* = 0x02.nk_flags
  NK_TEXT_RIGHT* = 0x04.nk_flags

  NK_STATIC* = 0
  NK_DYNAMIC* = 1

# --- Helpers ---

proc nk_make_rect*(x, y, w, h: float32): nk_rect {.importc: "nk_rect", header: "nuklear.h".}

# --- Functions ---

proc nk_begin*(ctx: ptr nk_context, title: cstring, bounds: nk_rect, flags: nk_flags): bool {.importc: "nk_begin", header: "nuklear.h".}
proc nk_end*(ctx: ptr nk_context) {.importc: "nk_end", header: "nuklear.h".}

proc nk_layout_row_dynamic*(ctx: ptr nk_context, height: float32, cols: int32) {.importc: "nk_layout_row_dynamic", header: "nuklear.h".}
proc nk_layout_row_static*(ctx: ptr nk_context, height: float32, item_width: int32, cols: int32) {.importc: "nk_layout_row_static", header: "nuklear.h".}

proc nk_button_label*(ctx: ptr nk_context, title: cstring): bool {.importc: "nk_button_label", header: "nuklear.h".}
proc nk_label*(ctx: ptr nk_context, text: cstring, align: nk_flags) {.importc: "nk_label", header: "nuklear.h".}
proc nk_button_text*(ctx: ptr nk_context, title: cstring, len: int32): bool {.importc: "nk_button_text", header: "nuklear.h".}
