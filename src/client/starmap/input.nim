## Starmap Input Handler - Mouse/keyboard handling for starmap interaction
##
## Handles:
## - Zoom (mouse wheel)
## - Pan (middle mouse drag)
## - System selection (left click)
## - Hover detection (mouse move)

import std/options
import hex_math
import camera
import renderer

type
  MouseButton* {.pure.} = enum
    Left = 0
    Right = 1
    Middle = 2

  StarmapInputState* = object
    ## Tracks input state for starmap interaction
    isPanning*: bool
    lastMousePos*: Vec2
    mousePos*: Vec2

const
  ZoomSpeed* = 0.1f      ## Zoom factor per scroll unit
  MinClickDist* = 5.0f   ## Minimum mouse movement to count as drag vs click

proc initInputState*(): StarmapInputState =
  StarmapInputState(
    isPanning: false,
    lastMousePos: vec2(0, 0),
    mousePos: vec2(0, 0)
  )

# --- Picking ---

proc findSystemAtScreenPos*(
    screenPos: Vec2,
    cam: Camera2D,
    data: StarmapRenderData,
    hexSize: float32 = HexSize
): Option[HexCoord] =
  ## Find which system (if any) is at the given screen position.
  let worldPos = cam.screenToWorld(screenPos)
  let clickedHex = pixelToHex(worldPos, hexSize)

  # Check if this hex has a system
  for system in data.systems:
    if system.coord.q == clickedHex.q and system.coord.r == clickedHex.r:
      return some(clickedHex)

  none(HexCoord)

proc findHexAtScreenPos*(
    screenPos: Vec2,
    cam: Camera2D,
    hexSize: float32 = HexSize
): HexCoord =
  ## Find the hex coordinate at the given screen position.
  let worldPos = cam.screenToWorld(screenPos)
  pixelToHex(worldPos, hexSize)

# --- Input Event Handlers ---
## These return actions that should be dispatched to the SAM loop.
## The actual state mutation happens in acceptors.

type
  StarmapActionKind* {.pure.} = enum
    OnNone
    OnZoom
    OnPan
    OnHover
    OnSelect
    OnDeselect

  StarmapAction* = object
    case kind*: StarmapActionKind
    of OnZoom:
      zoomDelta*: float32
      zoomPos*: Vec2
    of OnPan:
      panDelta*: Vec2
    of OnHover:
      hoverHex*: Option[HexCoord]
    of OnSelect:
      selectHex*: Option[HexCoord]
    of OnDeselect:
      discard
    of OnNone:
      discard

proc handleMouseWheel*(
    scrollY: float32,
    mousePos: Vec2
): StarmapAction =
  ## Handle mouse wheel for zooming.
  if scrollY != 0:
    StarmapAction(
      kind: OnZoom,
      zoomDelta: scrollY * ZoomSpeed,
      zoomPos: mousePos
    )
  else:
    StarmapAction(kind: OnNone)

proc handleMouseMove*(
    inputState: var StarmapInputState,
    mouseX, mouseY: float32,
    cam: Camera2D,
    data: StarmapRenderData,
    hexSize: float32 = HexSize
): StarmapAction =
  ## Handle mouse movement for panning and hover.
  let newPos = vec2(mouseX, mouseY)
  let delta = newPos - inputState.mousePos
  inputState.lastMousePos = inputState.mousePos
  inputState.mousePos = newPos

  if inputState.isPanning:
    # Return pan action
    StarmapAction(kind: OnPan, panDelta: delta)
  else:
    # Return hover action
    let hovered = findSystemAtScreenPos(newPos, cam, data, hexSize)
    StarmapAction(kind: OnHover, hoverHex: hovered)

proc handleMouseDown*(
    inputState: var StarmapInputState,
    button: MouseButton,
    mouseX, mouseY: float32
): StarmapAction =
  ## Handle mouse button press.
  inputState.mousePos = vec2(mouseX, mouseY)

  case button
  of MouseButton.Middle:
    inputState.isPanning = true
    StarmapAction(kind: OnNone)
  of MouseButton.Left, MouseButton.Right:
    StarmapAction(kind: OnNone)

proc handleMouseUp*(
    inputState: var StarmapInputState,
    button: MouseButton,
    mouseX, mouseY: float32,
    cam: Camera2D,
    data: StarmapRenderData,
    hexSize: float32 = HexSize
): StarmapAction =
  ## Handle mouse button release.
  let releasePos = vec2(mouseX, mouseY)

  case button
  of MouseButton.Middle:
    inputState.isPanning = false
    StarmapAction(kind: OnNone)

  of MouseButton.Left:
    # Check if this was a click (not drag)
    let moveDist = distance(releasePos, inputState.mousePos)
    if moveDist < MinClickDist:
      let clicked = findSystemAtScreenPos(releasePos, cam, data, hexSize)
      StarmapAction(kind: OnSelect, selectHex: clicked)
    else:
      StarmapAction(kind: OnNone)

  of MouseButton.Right:
    # Right click could be used for context menu later
    StarmapAction(kind: OnNone)

proc handleKeyDown*(keycode: int): StarmapAction =
  ## Handle key press.
  ## Escape deselects current selection.
  const KEYCODE_ESCAPE = 256  # from sokol_app.h
  if keycode == KEYCODE_ESCAPE:
    StarmapAction(kind: OnDeselect)
  else:
    StarmapAction(kind: OnNone)

# --- Apply Actions to Camera ---

proc applyZoom*(cam: var Camera2D, action: StarmapAction) =
  ## Apply zoom action to camera.
  if action.kind == OnZoom:
    cam.zoomAt(action.zoomPos, action.zoomDelta)

proc applyPan*(cam: var Camera2D, action: StarmapAction) =
  ## Apply pan action to camera.
  if action.kind == OnPan:
    cam.pan(action.panDelta)
