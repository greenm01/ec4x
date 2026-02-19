## TextInput - Bounded text input widget
##
## Displays text within a bounded area with:
## - Horizontal scrolling when text exceeds display width
## - Scroll indicator (…) when content is clipped
## - Optional masking for sensitive input (nsec)
## - Optional max length enforcement
## - Native cursor when focused

import std/[strutils]
import ../buffer
import ../layout/rect
import ../cursor_target
import ./editor_core

type
  TextInputWidget* = object
    ## Rendering configuration for text input.
    placeholder: string         ## Shown when empty
    masked: bool                ## Show asterisks instead of text
    scrollIndicator: string     ## Shown when text is scrolled left
    style: CellStyle            ## Text style
    placeholderStyle: CellStyle ## Placeholder style (dimmed)
    cursorStyle: CellStyle      ## Cursor style (visual only)

proc newTextInput*(): TextInputWidget =
  ## Create a text input widget with defaults.
  TextInputWidget(
    placeholder: "",
    masked: false,
    scrollIndicator: "…",
    style: defaultStyle(),
    placeholderStyle: defaultStyle(),
    cursorStyle: defaultStyle()
  )

proc placeholder*(w: TextInputWidget, text: string): TextInputWidget =
  ## Set placeholder text shown when input is empty.
  result = w
  result.placeholder = text

proc masked*(w: TextInputWidget, val: bool = true): TextInputWidget =
  ## Enable masking (show asterisks instead of text).
  result = w
  result.masked = val

proc scrollIndicator*(w: TextInputWidget, s: string): TextInputWidget =
  ## Set the scroll indicator (shown when text is scrolled).
  result = w
  result.scrollIndicator = s

proc style*(w: TextInputWidget, s: CellStyle): TextInputWidget =
  ## Set the text style.
  result = w
  result.style = s

proc placeholderStyle*(w: TextInputWidget, s: CellStyle): TextInputWidget =
  ## Set the placeholder text style.
  result = w
  result.placeholderStyle = s

proc cursorStyle*(w: TextInputWidget, s: CellStyle): TextInputWidget =
  ## Set the cursor style.
  result = w
  result.cursorStyle = s

proc render*(w: TextInputWidget, state: TextInputState,
             area: Rect, buf: var CellBuffer, hasFocus: bool) =
  ## Render the text input within the bounded area.
  ## This is a pure render - scrollOffset is computed but not stored.
  if area.isEmpty or area.width < 1:
    return

  let displayWidth = if state.maxDisplayWidth > 0:
      min(state.maxDisplayWidth, area.width)
    else:
      area.width

  let scrollOffset = state.computeScrollOffset(displayWidth)

  var displayText = state.text
  if w.masked:
    displayText = repeat("*", displayText.len)

  if displayText.len == 0:
    if w.placeholder.len > 0:
      let truncatedPlaceholder = if w.placeholder.len > displayWidth:
          w.placeholder[0..<displayWidth - 1] & "…"
        else:
          w.placeholder
      discard buf.setString(area.x, area.y, truncatedPlaceholder,
        w.placeholderStyle)
    if hasFocus:
      setCursorTarget(area.x, area.y)
    return

  var x = area.x
  if scrollOffset > 0:
    discard buf.setString(x, area.y, w.scrollIndicator, w.style)
    x.inc

  let indicatorOffset = if scrollOffset > 0: 1 else: 0
  let visibleWidth = displayWidth - indicatorOffset
  let visibleEnd = min(displayText.len, scrollOffset + visibleWidth)
  let visibleText = if scrollOffset < displayText.len:
      displayText[scrollOffset..<visibleEnd]
    else:
      ""

  discard buf.setString(x, area.y, visibleText, w.style)

  if hasFocus:
    let cursorX = area.x + (state.cursorPos - scrollOffset) + indicatorOffset
    if cursorX >= area.x and cursorX < area.x + displayWidth:
      setCursorTarget(cursorX, area.y)

export editor_core
