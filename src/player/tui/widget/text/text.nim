## Text - Multi-line styled text
##
## Text is composed of one or more Lines, each containing Spans.
## This is the highest level text container used by widgets like Paragraph.

import std/strutils
import ./span
import ./line
import ../../buffer
import ../../term/types/[core, style]

export span, line
export CellStyle, Color, StyleAttr, defaultStyle, Alignment

type
  Text* = object
    ## Multi-line text with optional default style and alignment.
    lines*: seq[Line]
    style*: CellStyle      # Default style for all lines
    alignment*: Alignment  # Default alignment for all lines

# -----------------------------------------------------------------------------
# Constructors
# -----------------------------------------------------------------------------

proc text*(content: string): Text =
  ## Create text from a string, splitting on newlines.
  var lines: seq[Line] = @[]
  for lineStr in content.splitLines():
    lines.add(line(lineStr))
  Text(
    lines: lines,
    style: defaultStyle(),
    alignment: Alignment.Left
  )

proc text*(lines: openArray[Line]): Text =
  ## Create text from a sequence of lines.
  Text(
    lines: @lines,
    style: defaultStyle(),
    alignment: Alignment.Left
  )

proc text*(l: Line): Text =
  ## Create text from a single line.
  Text(
    lines: @[l],
    style: defaultStyle(),
    alignment: Alignment.Left
  )

proc raw*(content: string): Text {.inline.} =
  ## Create unstyled text.
  text(content)

# -----------------------------------------------------------------------------
# Fluent styling methods
# -----------------------------------------------------------------------------

proc style*(t: Text, style: CellStyle): Text =
  ## Set default style for all lines.
  result = t
  result.style = style

proc fg*(t: Text, c: Color): Text =
  ## Set foreground color for all lines.
  result = t
  result.style.fg = c

proc bg*(t: Text, c: Color): Text =
  ## Set background color for all lines.
  result = t
  result.style.bg = c

proc bold*(t: Text): Text =
  ## Add bold to all lines.
  result = t
  result.style.attrs.incl(StyleAttr.Bold)

proc italic*(t: Text): Text =
  ## Add italic to all lines.
  result = t
  result.style.attrs.incl(StyleAttr.Italic)

proc underline*(t: Text): Text =
  ## Add underline to all lines.
  result = t
  result.style.attrs.incl(StyleAttr.Underline)

# -----------------------------------------------------------------------------
# Alignment methods
# -----------------------------------------------------------------------------

proc left*(t: Text): Text =
  ## Set default left alignment.
  result = t
  result.alignment = Alignment.Left

proc center*(t: Text): Text =
  ## Set default center alignment.
  result = t
  result.alignment = Alignment.Center

proc right*(t: Text): Text =
  ## Set default right alignment.
  result = t
  result.alignment = Alignment.Right

proc leftAligned*(t: Text): Text {.inline.} = t.left()
proc centered*(t: Text): Text {.inline.} = t.center()
proc rightAligned*(t: Text): Text {.inline.} = t.right()

# -----------------------------------------------------------------------------
# Properties
# -----------------------------------------------------------------------------

proc height*(t: Text): int {.inline.} =
  ## Number of lines.
  t.lines.len

proc width*(t: Text): int =
  ## Maximum width of any line.
  for l in t.lines:
    let w = l.width()
    if w > result:
      result = w

proc isEmpty*(t: Text): bool =
  ## True if text has no lines or all lines are empty.
  if t.lines.len == 0:
    return true
  for l in t.lines:
    if not l.isEmpty:
      return false
  true

# -----------------------------------------------------------------------------
# Line manipulation
# -----------------------------------------------------------------------------

proc add*(t: var Text, l: Line) =
  ## Add a line to the text.
  t.lines.add(l)

proc add*(t: var Text, content: string) =
  ## Add a line from a string.
  t.lines.add(line(content))

proc `&`*(t: Text, l: Line): Text =
  ## Append a line (returns new text).
  result = t
  result.lines.add(l)

proc `&`*(t: Text, content: string): Text =
  ## Append a line from string (returns new text).
  result = t
  result.lines.add(line(content))

# -----------------------------------------------------------------------------
# Iteration
# -----------------------------------------------------------------------------

iterator items*(t: Text): Line =
  ## Iterate over lines.
  for l in t.lines:
    yield l

iterator pairs*(t: Text): tuple[idx: int, line: Line] =
  ## Iterate over lines with indices.
  for i, l in t.lines:
    yield (i, l)

# -----------------------------------------------------------------------------
# Conversions
# -----------------------------------------------------------------------------

proc `$`*(t: Text): string =
  ## String representation (joined lines).
  for i, l in t.lines:
    if i > 0:
      result.add("\n")
    result.add($l)

# Implicit conversion from string
converter toText*(s: string): Text =
  text(s)

# Implicit conversion from Line
converter toText*(l: Line): Text =
  text(l)
