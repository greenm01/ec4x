## Shared native cursor target for focused text input/editors.
##
## Renderers can publish the desired terminal cursor location each frame.
## The app render loop consumes this and moves the native cursor.

import std/options
import ./term/types/screen

type
  CursorTarget* = object
    x*: int
    y*: int
    style*: CursorStyle

var gCursorTarget: Option[CursorTarget] = none(CursorTarget)

proc clearCursorTarget*() =
  ## Clear the current frame's cursor target.
  gCursorTarget = none(CursorTarget)

proc setCursorTarget*(x, y: int, style: CursorStyle = CursorStyle.SteadyBlock) =
  ## Publish a native cursor target for this frame.
  gCursorTarget = some(CursorTarget(x: x, y: y, style: style))

proc cursorTarget*(): Option[CursorTarget] =
  ## Read the current frame's cursor target.
  gCursorTarget
