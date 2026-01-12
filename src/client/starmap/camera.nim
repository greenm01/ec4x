## 2D Camera for starmap zoom/pan
##
## Handles coordinate transforms between screen space and world space.

import hex_math
import ../bindings/sokol_gl

type
  Camera2D* = object
    ## 2D camera for zoom/pan navigation
    target*: Vec2       ## World position the camera looks at
    offset*: Vec2       ## Screen position of the camera target (usually center)
    zoom*: float32      ## Zoom level (1.0 = default, >1 = zoomed in)
    minZoom*: float32   ## Minimum zoom level
    maxZoom*: float32   ## Maximum zoom level

const
  DefaultZoom* = 1.0f
  DefaultMinZoom* = 0.1f
  DefaultMaxZoom* = 10.0f

proc initCamera2D*(screenWidth, screenHeight: int32): Camera2D =
  ## Create a camera centered on the screen, looking at world origin.
  Camera2D(
    target: vec2(0, 0),
    offset: vec2(screenWidth.float32 / 2.0f, screenHeight.float32 / 2.0f),
    zoom: DefaultZoom,
    minZoom: DefaultMinZoom,
    maxZoom: DefaultMaxZoom
  )

proc updateOffset*(camera: var Camera2D, screenWidth, screenHeight: int32) =
  ## Update camera offset when screen size changes.
  camera.offset = vec2(screenWidth.float32 / 2.0f, screenHeight.float32 / 2.0f)

# --- Coordinate Transforms ---

proc screenToWorld*(camera: Camera2D, screenPos: Vec2): Vec2 =
  ## Convert screen coordinates to world coordinates.
  ## screenPos is in pixels from top-left of window.
  let dx = (screenPos.x - camera.offset.x) / camera.zoom
  let dy = (screenPos.y - camera.offset.y) / camera.zoom
  vec2(camera.target.x + dx, camera.target.y + dy)

proc worldToScreen*(camera: Camera2D, worldPos: Vec2): Vec2 =
  ## Convert world coordinates to screen coordinates.
  let dx = (worldPos.x - camera.target.x) * camera.zoom
  let dy = (worldPos.y - camera.target.y) * camera.zoom
  vec2(camera.offset.x + dx, camera.offset.y + dy)

# --- Camera Controls ---

proc pan*(camera: var Camera2D, delta: Vec2) =
  ## Pan the camera by the given screen-space delta.
  ## Typically called with mouse drag delta.
  camera.target.x -= delta.x / camera.zoom
  camera.target.y -= delta.y / camera.zoom

proc zoomAt*(camera: var Camera2D, screenPos: Vec2, zoomDelta: float32) =
  ## Zoom toward/away from a screen position (usually mouse position).
  ## zoomDelta > 0 zooms in, < 0 zooms out.
  let worldPosBefore = camera.screenToWorld(screenPos)

  # Apply zoom with clamping
  camera.zoom *= (1.0f + zoomDelta)
  camera.zoom = clamp(camera.zoom, camera.minZoom, camera.maxZoom)

  # Adjust target so the world point under the cursor stays fixed
  let worldPosAfter = camera.screenToWorld(screenPos)
  camera.target.x -= worldPosAfter.x - worldPosBefore.x
  camera.target.y -= worldPosAfter.y - worldPosBefore.y

proc setZoom*(camera: var Camera2D, zoom: float32) =
  ## Set absolute zoom level (clamped to min/max).
  camera.zoom = clamp(zoom, camera.minZoom, camera.maxZoom)

proc centerOn*(camera: var Camera2D, worldPos: Vec2) =
  ## Center the camera on a world position.
  camera.target = worldPos

proc centerOnHex*(camera: var Camera2D, hex: HexCoord,
    hexSize: float32 = HexSize) =
  ## Center the camera on a hex coordinate.
  camera.target = hexToPixel(hex, hexSize)

# --- Apply Transform to sokol_gl ---

proc applyTransform*(camera: Camera2D, screenWidth, screenHeight: int32) =
  ## Apply camera transform to sokol_gl's projection matrix.
  ## Call this before drawing world-space content.
  sgl_matrix_mode_projection()
  sgl_load_identity()

  # Set up orthographic projection (screen space: origin top-left)
  sgl_ortho(0, screenWidth.cfloat, screenHeight.cfloat, 0, -1, 1)

  # Translate to camera offset (screen center)
  sgl_translate(camera.offset.x, camera.offset.y, 0)

  # Apply zoom
  sgl_scale(camera.zoom, camera.zoom, 1)

  # Translate to camera target (world position)
  sgl_translate(-camera.target.x, -camera.target.y, 0)

  sgl_matrix_mode_modelview()
  sgl_load_identity()

# --- Utility ---

proc isHexVisible*(camera: Camera2D, hex: HexCoord, hexSize: float32,
    screenWidth, screenHeight: int32): bool =
  ## Check if a hex is potentially visible on screen.
  ## Uses conservative bounds (may return true for slightly off-screen hexes).
  let worldPos = hexToPixel(hex, hexSize)
  let screenPos = camera.worldToScreen(worldPos)
  let margin = hexSize * camera.zoom * 2  # Extra margin for hex size

  screenPos.x >= -margin and screenPos.x <= screenWidth.float32 + margin and
  screenPos.y >= -margin and screenPos.y <= screenHeight.float32 + margin
