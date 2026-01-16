## Scrollbar Widget
##
## Renders a scrollbar when content exceeds viewport.

import ../buffer
import ../layout/rect

const
  DefaultTrack = "│"
  DefaultThumb = "█"
  DefaultBegin = "↑"
  DefaultEnd = "↓"

  DefaultTrackH = "─"
  DefaultThumbH = "█"
  DefaultBeginH = "←"
  DefaultEndH = "→"

type
  ScrollbarOrientation* {.pure.} = enum
    VerticalRight
    VerticalLeft
    HorizontalBottom
    HorizontalTop

  ScrollbarState* = object
    ## State for scrollbar rendering.
    contentLength*: int
    position*: int
    viewportLength*: int

  ScrollbarStyle* = object
    track*: CellStyle
    thumb*: CellStyle
    beginStyle*: CellStyle
    endStyle*: CellStyle

proc defaultScrollbarStyle*(): ScrollbarStyle =
  ScrollbarStyle(
    track: defaultStyle(),
    thumb: defaultStyle(),
    beginStyle: defaultStyle(),
    endStyle: defaultStyle()
  )

proc renderVertical(
    area: Rect,
    buf: var CellBuffer,
    state: ScrollbarState,
    style: ScrollbarStyle,
    symbols: tuple[track, thumb, beginSymbol, endSymbol: string]
) =
  if state.contentLength <= state.viewportLength or area.height < 2:
    return

  let trackStart = area.y
  let trackEnd = area.bottom - 1
  let trackLen = max(1, trackEnd - trackStart - 1)
  let maxPos = max(1, state.contentLength - state.viewportLength)
  let ratio = float(state.position) / float(maxPos)
  let thumbPos = trackStart + 1 + int(ratio * float(trackLen - 1))

  discard buf.setString(area.x, trackStart, symbols.beginSymbol, style.beginStyle)
  discard buf.setString(area.x, trackEnd, symbols.endSymbol, style.endStyle)

  for y in trackStart + 1 ..< trackEnd:
    discard buf.setString(area.x, y, symbols.track, style.track)

  discard buf.setString(area.x, thumbPos, symbols.thumb, style.thumb)

proc renderHorizontal(
    area: Rect,
    buf: var CellBuffer,
    state: ScrollbarState,
    style: ScrollbarStyle,
    symbols: tuple[track, thumb, beginSymbol, endSymbol: string]
) =
  if state.contentLength <= state.viewportLength or area.width < 2:
    return

  let trackStart = area.x
  let trackEnd = area.right - 1
  let trackLen = max(1, trackEnd - trackStart - 1)
  let maxPos = max(1, state.contentLength - state.viewportLength)
  let ratio = float(state.position) / float(maxPos)
  let thumbPos = trackStart + 1 + int(ratio * float(trackLen - 1))

  discard buf.setString(trackStart, area.y, symbols.beginSymbol, style.beginStyle)
  discard buf.setString(trackEnd, area.y, symbols.endSymbol, style.endStyle)

  for x in trackStart + 1 ..< trackEnd:
    discard buf.setString(x, area.y, symbols.track, style.track)

  discard buf.setString(thumbPos, area.y, symbols.thumb, style.thumb)

proc renderScrollbar*(
    area: Rect,
    buf: var CellBuffer,
    state: ScrollbarState,
    orientation: ScrollbarOrientation,
    style: ScrollbarStyle = defaultScrollbarStyle(),
) =
  ## Render a scrollbar for the given area.
  case orientation
  of ScrollbarOrientation.VerticalRight:
    renderVertical(
      rect(area.right - 1, area.y, 1, area.height),
      buf,
      state,
      style,
      (DefaultTrack, DefaultThumb, DefaultBegin, DefaultEnd)
    )
  of ScrollbarOrientation.VerticalLeft:
    renderVertical(
      rect(area.x, area.y, 1, area.height),
      buf,
      state,
      style,
      (DefaultTrack, DefaultThumb, DefaultBegin, DefaultEnd)
    )
  of ScrollbarOrientation.HorizontalBottom:
    renderHorizontal(
      rect(area.x, area.bottom - 1, area.width, 1),
      buf,
      state,
      style,
      (DefaultTrackH, DefaultThumbH, DefaultBeginH, DefaultEndH)
    )
  of ScrollbarOrientation.HorizontalTop:
    renderHorizontal(
      rect(area.x, area.y, area.width, 1),
      buf,
      state,
      style,
      (DefaultTrackH, DefaultThumbH, DefaultBeginH, DefaultEndH)
    )
