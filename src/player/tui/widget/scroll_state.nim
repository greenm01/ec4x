## Scroll State - Shared scrolling logic
##
## Provides reusable scroll offsets and helper procs for list/paragraph widgets.


const
  MinOffset = 0

proc clampOffset*(offset, maxOffset: int): int =
  ## Clamp an offset between 0 and maxOffset.
  max(MinOffset, min(offset, maxOffset))

type
  ScrollState* = object
    ## Shared scroll state for widgets.
    verticalOffset*: int
    horizontalOffset*: int
    contentLength*: int
    viewportLength*: int

proc initScrollState*(): ScrollState =
  ## Create a default scroll state.
  ScrollState(
    verticalOffset: 0,
    horizontalOffset: 0,
    contentLength: 0,
    viewportLength: 0
  )

proc maxVerticalOffset*(state: ScrollState): int =
  ## Max vertical offset based on content and viewport.
  max(0, state.contentLength - state.viewportLength)

proc maxHorizontalOffset*(state: ScrollState): int =
  ## Max horizontal offset based on content and viewport.
  max(0, state.contentLength - state.viewportLength)

proc clampOffsets*(state: var ScrollState) =
  ## Clamp scroll offsets to valid range.
  state.verticalOffset = clampOffset(
    state.verticalOffset,
    state.maxVerticalOffset()
  )
  state.horizontalOffset = clampOffset(
    state.horizontalOffset,
    state.maxHorizontalOffset()
  )

proc ensureVisible*(state: var ScrollState, index: int) =
  ## Ensure an index is visible in the viewport.
  if state.viewportLength <= 0:
    return
  if index < state.verticalOffset:
    state.verticalOffset = index
  elif index >= state.verticalOffset + state.viewportLength:
    state.verticalOffset = index - state.viewportLength + 1
  state.verticalOffset = clampOffset(
    state.verticalOffset,
    state.maxVerticalOffset()
  )

proc scrollBy*(state: var ScrollState, delta: int) =
  ## Adjust vertical offset by delta.
  if delta == 0:
    return
  state.verticalOffset = clampOffset(
    state.verticalOffset + delta,
    state.maxVerticalOffset()
  )

proc isAtBottom*(state: ScrollState): bool =
  ## Return true if vertical offset is at bottom.
  state.verticalOffset >= state.maxVerticalOffset()
