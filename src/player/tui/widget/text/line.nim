## Line - A single line of styled text
##
## A Line is composed of one or more Spans and can have alignment.
## This represents a single row of text in the terminal.

import ./span
import ../../buffer
import ../../term/types/[core, style]

export span
export CellStyle, Color, StyleAttr, defaultStyle

type
  Alignment* {.pure.} = enum
    ## Text alignment within available space.
    Left
    Center
    Right

  Line* = object
    ## A single line of text composed of styled spans.
    spans*: seq[Span]
    style*: CellStyle      # Applied to entire line
    alignment*: Alignment  # How to align within available width

# -----------------------------------------------------------------------------
# Constructors
# -----------------------------------------------------------------------------

proc line*(content: string): Line =
  ## Create a line from a plain string.
  Line(
    spans: @[span(content)],
    style: defaultStyle(),
    alignment: Alignment.Left
  )

proc line*(content: string, style: CellStyle): Line =
  ## Create a line from a styled string.
  Line(
    spans: @[span(content, style)],
    style: style,
    alignment: Alignment.Left
  )

proc line*(spans: openArray[Span]): Line =
  ## Create a line from multiple spans.
  Line(
    spans: @spans,
    style: defaultStyle(),
    alignment: Alignment.Left
  )

proc line*(s: Span): Line =
  ## Create a line from a single span.
  Line(
    spans: @[s],
    style: defaultStyle(),
    alignment: Alignment.Left
  )

proc raw*(content: string): Line {.inline.} =
  ## Create an unstyled line.
  line(content)

# -----------------------------------------------------------------------------
# Fluent styling methods
# -----------------------------------------------------------------------------

proc style*(l: Line, style: CellStyle): Line =
  ## Set the line's base style.
  result = l
  result.style = style

proc fg*(l: Line, c: Color): Line =
  ## Set foreground color for entire line.
  result = l
  result.style.fg = c

proc bg*(l: Line, c: Color): Line =
  ## Set background color for entire line.
  result = l
  result.style.bg = c

proc bold*(l: Line): Line =
  ## Add bold to entire line.
  result = l
  result.style.attrs.incl(StyleAttr.Bold)

proc italic*(l: Line): Line =
  ## Add italic to entire line.
  result = l
  result.style.attrs.incl(StyleAttr.Italic)

proc underline*(l: Line): Line =
  ## Add underline to entire line.
  result = l
  result.style.attrs.incl(StyleAttr.Underline)

# -----------------------------------------------------------------------------
# Alignment methods
# -----------------------------------------------------------------------------

proc left*(l: Line): Line =
  ## Set left alignment.
  result = l
  result.alignment = Alignment.Left

proc center*(l: Line): Line =
  ## Set center alignment.
  result = l
  result.alignment = Alignment.Center

proc right*(l: Line): Line =
  ## Set right alignment.
  result = l
  result.alignment = Alignment.Right

proc leftAligned*(l: Line): Line {.inline.} = l.left()
proc centered*(l: Line): Line {.inline.} = l.center()
proc rightAligned*(l: Line): Line {.inline.} = l.right()

# -----------------------------------------------------------------------------
# Properties
# -----------------------------------------------------------------------------

proc width*(l: Line): int =
  ## Calculate total display width of all spans.
  for s in l.spans:
    result += s.width()

proc isEmpty*(l: Line): bool =
  ## True if line has no content.
  l.spans.len == 0 or (l.spans.len == 1 and l.spans[0].isEmpty)

# -----------------------------------------------------------------------------
# Span manipulation
# -----------------------------------------------------------------------------

proc add*(l: var Line, s: Span) =
  ## Add a span to the line.
  l.spans.add(s)

proc add*(l: var Line, content: string) =
  ## Add an unstyled span to the line.
  l.spans.add(span(content))

proc `&`*(l: Line, s: Span): Line =
  ## Concatenate a span to a line (returns new line).
  result = l
  result.spans.add(s)

proc `&`*(l: Line, content: string): Line =
  ## Concatenate a string as a span (returns new line).
  result = l
  result.spans.add(span(content))

# -----------------------------------------------------------------------------
# Rendering helpers
# -----------------------------------------------------------------------------

proc calculateOffset*(l: Line, availableWidth: int): int =
  ## Calculate the starting X offset for rendering based on alignment.
  ## Returns 0 for Left, centered offset for Center, right offset for Right.
  let contentWidth = l.width()
  if contentWidth >= availableWidth:
    return 0
  
  case l.alignment
  of Alignment.Left:
    0
  of Alignment.Center:
    (availableWidth - contentWidth) div 2
  of Alignment.Right:
    availableWidth - contentWidth

# -----------------------------------------------------------------------------
# Conversions
# -----------------------------------------------------------------------------

proc `$`*(l: Line): string =
  ## String representation (concatenated span content).
  for s in l.spans:
    result.add($s)

# Implicit conversion from string
converter toLine*(s: string): Line =
  line(s)

# Implicit conversion from Span
converter toLine*(s: Span): Line =
  line(s)
