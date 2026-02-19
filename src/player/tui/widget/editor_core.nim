## Shared text editor core for single-line and multiline TUI input.

type
  EditorMode* {.pure.} = enum
    SingleLine
    MultiLine

  TextInputState* = object
    ## Shared input/editor state.
    text*: string
    cursorPos*: int
    scrollOffset*: int
    maxLength*: int
    maxDisplayWidth*: int
    mode*: EditorMode
    scrollLine*: int
    preferredColumn*: int

proc initTextInputState*(
    maxLength: int = 0,
    maxDisplayWidth: int = 0,
    mode: EditorMode = EditorMode.SingleLine): TextInputState =
  TextInputState(
    text: "",
    cursorPos: 0,
    scrollOffset: 0,
    maxLength: maxLength,
    maxDisplayWidth: maxDisplayWidth,
    mode: mode,
    scrollLine: 0,
    preferredColumn: 0
  )

proc appendChar*(state: var TextInputState, c: char): bool =
  if state.maxLength > 0 and state.text.len >= state.maxLength:
    return false
  if state.cursorPos >= state.text.len:
    state.text.add(c)
  else:
    state.text.insert($c, state.cursorPos)
  state.cursorPos.inc
  true

proc appendText*(state: var TextInputState, value: string): bool =
  result = true
  for ch in value:
    if not state.appendChar(ch):
      return false

proc backspace*(state: var TextInputState) =
  if state.cursorPos > 0 and state.text.len > 0:
    let deleteIdx = state.cursorPos - 1
    state.text = state.text[0..<deleteIdx] & state.text[state.cursorPos..^1]
    state.cursorPos = deleteIdx

proc delete*(state: var TextInputState) =
  if state.cursorPos < state.text.len:
    state.text = state.text[0..<state.cursorPos] &
      state.text[state.cursorPos + 1..^1]

proc clear*(state: var TextInputState) =
  state.text = ""
  state.cursorPos = 0
  state.scrollOffset = 0
  state.scrollLine = 0
  state.preferredColumn = 0

proc setText*(state: var TextInputState, text: string) =
  if state.maxLength > 0 and text.len > state.maxLength:
    state.text = text[0..<state.maxLength]
  else:
    state.text = text
  state.cursorPos = state.text.len
  state.scrollOffset = 0
  state.scrollLine = 0

proc moveCursorLeft*(state: var TextInputState) =
  if state.cursorPos > 0:
    state.cursorPos.dec

proc moveCursorRight*(state: var TextInputState) =
  if state.cursorPos < state.text.len:
    state.cursorPos.inc

proc moveCursorHome*(state: var TextInputState) =
  state.cursorPos = 0

proc moveCursorEnd*(state: var TextInputState) =
  state.cursorPos = state.text.len

proc isEmpty*(state: TextInputState): bool =
  state.text.len == 0

proc value*(state: TextInputState): string =
  state.text

proc ensureCursorVisible*(state: var TextInputState, displayWidth: int) =
  if displayWidth <= 0:
    return
  let effectiveWidth = if state.scrollOffset > 0: displayWidth - 1
                       else: displayWidth
  if state.cursorPos < state.scrollOffset:
    state.scrollOffset = state.cursorPos
  elif state.cursorPos > state.scrollOffset + effectiveWidth:
    state.scrollOffset = state.cursorPos - effectiveWidth
  let maxScroll = max(0, state.text.len - displayWidth + 1)
  state.scrollOffset = clamp(state.scrollOffset, 0, maxScroll)

proc computeScrollOffset*(state: TextInputState, displayWidth: int): int =
  if displayWidth <= 0:
    return 0
  result = state.scrollOffset
  let effectiveWidth = if result > 0: displayWidth - 1 else: displayWidth
  if state.cursorPos < result:
    result = state.cursorPos
  elif state.cursorPos > result + effectiveWidth:
    result = state.cursorPos - effectiveWidth
  let maxScroll = max(0, state.text.len - displayWidth + 1)
  result = clamp(result, 0, maxScroll)

proc cursorLine*(text: string, cursorPos: int): int =
  let cursor = clamp(cursorPos, 0, text.len)
  result = 0
  for i in 0 ..< cursor:
    if text[i] == '\n':
      result.inc

proc cursorColumn*(text: string, cursorPos: int): int =
  let cursor = clamp(cursorPos, 0, text.len)
  var start = 0
  if cursor > 0:
    for i in countdown(cursor - 1, 0):
      if text[i] == '\n':
        start = i + 1
        break
  cursor - start

proc lineStart*(text: string, lineIdx: int): int =
  if lineIdx <= 0:
    return 0
  var line = 0
  for i, ch in text:
    if ch == '\n':
      line.inc
      if line == lineIdx:
        return i + 1
  text.len

proc lineEnd*(text: string, startPos: int): int =
  for i in startPos ..< text.len:
    if text[i] == '\n':
      return i
  text.len

proc lineCount*(text: string): int =
  result = 1
  for ch in text:
    if ch == '\n':
      result.inc

proc updatePreferredColumn*(state: var TextInputState) =
  state.preferredColumn = cursorColumn(state.text, state.cursorPos)

proc moveCursorUpLine*(state: var TextInputState) =
  let currentLine = cursorLine(state.text, state.cursorPos)
  if currentLine <= 0:
    return
  let targetStart = lineStart(state.text, currentLine - 1)
  let targetEnd = lineEnd(state.text, targetStart)
  let targetCol = min(state.preferredColumn, targetEnd - targetStart)
  state.cursorPos = targetStart + targetCol

proc moveCursorDownLine*(state: var TextInputState) =
  let currentLine = cursorLine(state.text, state.cursorPos)
  if currentLine + 1 >= lineCount(state.text):
    return
  let targetStart = lineStart(state.text, currentLine + 1)
  let targetEnd = lineEnd(state.text, targetStart)
  let targetCol = min(state.preferredColumn, targetEnd - targetStart)
  state.cursorPos = targetStart + targetCol

proc ensureCursorVisibleLines*(state: var TextInputState, viewportLines: int) =
  let lines = max(1, viewportLines)
  let currentLine = cursorLine(state.text, state.cursorPos)
  if currentLine < state.scrollLine:
    state.scrollLine = currentLine
  elif currentLine >= state.scrollLine + lines:
    state.scrollLine = currentLine - lines + 1
  state.scrollLine = max(0, state.scrollLine)

proc insertNewline*(state: var TextInputState) =
  if state.mode != EditorMode.MultiLine:
    return
  let cursor = clamp(state.cursorPos, 0, state.text.len)
  state.text.insert("\n", cursor)
  state.cursorPos = cursor + 1
  state.preferredColumn = 0
