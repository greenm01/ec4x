## TextInput - Bounded text input widget
##
## Displays text within a bounded area with:
## - Horizontal scrolling when text exceeds display width
## - Scroll indicator (…) when content is clipped
## - Optional masking for sensitive input (nsec)
## - Optional max length enforcement
## - Cursor display when focused

import std/[strutils]
import ../buffer
import ../layout/rect

type
  TextInputState* = object
    ## State for a text input field.
    text*: string              ## The input text content
    cursorPos*: int            ## Cursor position (0 = before first char)
    scrollOffset*: int         ## First visible character index
    maxLength*: int            ## Max characters (0 = unlimited)
    maxDisplayWidth*: int      ## Max display cells (0 = use area width)

  TextInputWidget* = object
    ## Rendering configuration for text input.
    placeholder: string        ## Shown when empty
    masked: bool               ## Show asterisks instead of text
    cursorChar: string         ## Visual cursor character
    scrollIndicator: string    ## Shown when text is scrolled left
    style: CellStyle           ## Text style
    placeholderStyle: CellStyle ## Placeholder style (dimmed)
    cursorStyle: CellStyle     ## Cursor style

# =============================================================================
# State Management
# =============================================================================

proc initTextInputState*(maxLength: int = 0,
                         maxDisplayWidth: int = 0): TextInputState =
  ## Create a new text input state.
  TextInputState(
    text: "",
    cursorPos: 0,
    scrollOffset: 0,
    maxLength: maxLength,
    maxDisplayWidth: maxDisplayWidth
  )

proc appendChar*(state: var TextInputState, c: char): bool =
  ## Append a character at cursor position.
  ## Returns true if character was added, false if rejected (max length).
  if state.maxLength > 0 and state.text.len >= state.maxLength:
    return false
  if state.cursorPos >= state.text.len:
    state.text.add(c)
  else:
    state.text.insert($c, state.cursorPos)
  state.cursorPos += 1
  true

proc backspace*(state: var TextInputState) =
  ## Remove character before cursor.
  if state.cursorPos > 0 and state.text.len > 0:
    let deleteIdx = state.cursorPos - 1
    state.text = state.text[0..<deleteIdx] & state.text[state.cursorPos..^1]
    state.cursorPos -= 1

proc delete*(state: var TextInputState) =
  ## Remove character at cursor.
  if state.cursorPos < state.text.len:
    state.text = state.text[0..<state.cursorPos] &
                 state.text[state.cursorPos + 1..^1]

proc clear*(state: var TextInputState) =
  ## Clear all text.
  state.text = ""
  state.cursorPos = 0
  state.scrollOffset = 0

proc setText*(state: var TextInputState, text: string) =
  ## Set text directly, respecting maxLength.
  if state.maxLength > 0 and text.len > state.maxLength:
    state.text = text[0..<state.maxLength]
  else:
    state.text = text
  state.cursorPos = state.text.len  # Cursor at end
  state.scrollOffset = 0

proc moveCursorLeft*(state: var TextInputState) =
  ## Move cursor left one position.
  if state.cursorPos > 0:
    state.cursorPos -= 1

proc moveCursorRight*(state: var TextInputState) =
  ## Move cursor right one position.
  if state.cursorPos < state.text.len:
    state.cursorPos += 1

proc moveCursorHome*(state: var TextInputState) =
  ## Move cursor to beginning.
  state.cursorPos = 0

proc moveCursorEnd*(state: var TextInputState) =
  ## Move cursor to end.
  state.cursorPos = state.text.len

proc isEmpty*(state: TextInputState): bool =
  ## Check if input is empty.
  state.text.len == 0

proc value*(state: TextInputState): string =
  ## Get the text value.
  state.text

# =============================================================================
# Widget Builder
# =============================================================================

proc newTextInput*(): TextInputWidget =
  ## Create a text input widget with defaults.
  TextInputWidget(
    placeholder: "",
    masked: false,
    cursorChar: "_",
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

proc cursorChar*(w: TextInputWidget, c: string): TextInputWidget =
  ## Set the cursor character.
  result = w
  result.cursorChar = c

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

# =============================================================================
# Rendering
# =============================================================================

proc ensureCursorVisible*(state: var TextInputState, displayWidth: int) =
  ## Adjust scrollOffset so cursor is visible within displayWidth.
  if displayWidth <= 0:
    return
  
  # Account for scroll indicator taking 1 char when scrolled
  let effectiveWidth = if state.scrollOffset > 0: displayWidth - 1
                       else: displayWidth
  
  if state.cursorPos < state.scrollOffset:
    state.scrollOffset = state.cursorPos
  elif state.cursorPos > state.scrollOffset + effectiveWidth:
    state.scrollOffset = state.cursorPos - effectiveWidth
  
  # Clamp scroll offset to valid range
  let maxScroll = max(0, state.text.len - displayWidth + 1)
  state.scrollOffset = max(0, min(state.scrollOffset, maxScroll))

proc computeScrollOffset(state: TextInputState, displayWidth: int): int =
  ## Compute scrollOffset without mutating state (for pure render).
  if displayWidth <= 0:
    return 0
  
  var scrollOffset = state.scrollOffset
  
  # Account for scroll indicator taking 1 char when scrolled
  let effectiveWidth = if scrollOffset > 0: displayWidth - 1
                       else: displayWidth
  
  if state.cursorPos < scrollOffset:
    scrollOffset = state.cursorPos
  elif state.cursorPos > scrollOffset + effectiveWidth:
    scrollOffset = state.cursorPos - effectiveWidth
  
  # Clamp scroll offset to valid range
  let maxScroll = max(0, state.text.len - displayWidth + 1)
  scrollOffset = max(0, min(scrollOffset, maxScroll))
  scrollOffset

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
  
  # Compute scroll offset for rendering
  let scrollOffset = state.computeScrollOffset(displayWidth)
  
  # Prepare display text
  var displayText = state.text
  if w.masked:
    displayText = repeat("*", displayText.len)
  
  # Handle empty state with placeholder
  if displayText.len == 0:
    if w.placeholder.len > 0:
      let truncatedPlaceholder = if w.placeholder.len > displayWidth:
                                   w.placeholder[0..<displayWidth-1] & "…"
                                 else:
                                   w.placeholder
      discard buf.setString(area.x, area.y, truncatedPlaceholder,
                            w.placeholderStyle)
    # Draw cursor at start when focused
    if hasFocus:
      discard buf.setString(area.x, area.y, w.cursorChar, w.cursorStyle)
    return
  
  var x = area.x
  
  # Draw scroll indicator if scrolled
  if scrollOffset > 0:
    discard buf.setString(x, area.y, w.scrollIndicator, w.style)
    x += 1
  
  # Calculate visible portion
  let indicatorOffset = if scrollOffset > 0: 1 else: 0
  let visibleWidth = displayWidth - indicatorOffset
  let visibleEnd = min(displayText.len, scrollOffset + visibleWidth)
  let visibleText = if scrollOffset < displayText.len:
                      displayText[scrollOffset..<visibleEnd]
                    else:
                      ""
  
  # Draw visible text
  discard buf.setString(x, area.y, visibleText, w.style)
  
  # Draw cursor when focused
  if hasFocus:
    let cursorX = area.x + (state.cursorPos - scrollOffset) +
                  indicatorOffset
    if cursorX >= area.x and cursorX < area.x + displayWidth:
      discard buf.setString(cursorX, area.y, w.cursorChar, w.cursorStyle)
