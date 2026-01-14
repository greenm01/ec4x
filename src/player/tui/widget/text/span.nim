## Span - Smallest styled text unit
##
## A Span represents a contiguous piece of text with uniform styling.
## This is the basic building block for styled text in widgets.
##
## Inspired by ratatui's Span type but adapted for Nim.

import std/unicode
import ../../buffer
import ../../term/types/[core, style]

export CellStyle, Color, StyleAttr, defaultStyle

type
  Span* = object
    ## A piece of text with a single style.
    content*: string
    style*: CellStyle

# -----------------------------------------------------------------------------
# Constructors
# -----------------------------------------------------------------------------

proc span*(content: string): Span =
  ## Create a span with default style.
  Span(content: content, style: defaultStyle())

proc span*(content: string, style: CellStyle): Span =
  ## Create a span with explicit style.
  Span(content: content, style: style)

proc raw*(content: string): Span {.inline.} =
  ## Alias for span() - creates unstyled span.
  span(content)

proc styled*(content: string, style: CellStyle): Span {.inline.} =
  ## Alias for span() with style.
  span(content, style)

# -----------------------------------------------------------------------------
# Fluent styling methods (return new Span)
# -----------------------------------------------------------------------------

proc style*(s: Span, style: CellStyle): Span =
  ## Set the complete style.
  result = s
  result.style = style

proc fg*(s: Span, c: Color): Span =
  ## Set foreground color.
  result = s
  result.style.fg = c

proc bg*(s: Span, c: Color): Span =
  ## Set background color.
  result = s
  result.style.bg = c

proc bold*(s: Span): Span =
  ## Add bold attribute.
  result = s
  result.style.attrs.incl(StyleAttr.Bold)

proc faint*(s: Span): Span =
  ## Add faint attribute.
  result = s
  result.style.attrs.incl(StyleAttr.Faint)

proc italic*(s: Span): Span =
  ## Add italic attribute.
  result = s
  result.style.attrs.incl(StyleAttr.Italic)

proc underline*(s: Span): Span =
  ## Add underline attribute.
  result = s
  result.style.attrs.incl(StyleAttr.Underline)

proc blink*(s: Span): Span =
  ## Add blink attribute.
  result = s
  result.style.attrs.incl(StyleAttr.Blink)

proc reverse*(s: Span): Span =
  ## Add reverse video attribute.
  result = s
  result.style.attrs.incl(StyleAttr.Reverse)

proc crossOut*(s: Span): Span =
  ## Add strikethrough attribute.
  result = s
  result.style.attrs.incl(StyleAttr.CrossOut)

proc overline*(s: Span): Span =
  ## Add overline attribute.
  result = s
  result.style.attrs.incl(StyleAttr.Overline)

# Alias
proc strikethrough*(s: Span): Span {.inline.} =
  s.crossOut()

# -----------------------------------------------------------------------------
# Properties
# -----------------------------------------------------------------------------

proc width*(s: Span): int =
  ## Calculate the display width of the span's content.
  ## Uses Unicode width calculation for proper wide character support.
  result = 0
  for rune in s.content.runes:
    let c = int(rune)
    # Simplified width calculation - matches runeWidth in buffer.nim
    if c < 0x1100:
      result += 1
    elif (c >= 0x1100 and c <= 0x115F) or
         (c >= 0x2329 and c <= 0x232A) or
         (c >= 0x2E80 and c <= 0x303E) or
         (c >= 0x3040 and c <= 0xA4CF) or
         (c >= 0xAC00 and c <= 0xD7A3) or
         (c >= 0xF900 and c <= 0xFAFF) or
         (c >= 0xFE10 and c <= 0xFE19) or
         (c >= 0xFE30 and c <= 0xFE6F) or
         (c >= 0xFF00 and c <= 0xFF60) or
         (c >= 0xFFE0 and c <= 0xFFE6) or
         (c >= 0x1F000 and c <= 0x1FFFF) or
         (c >= 0x20000 and c <= 0x3FFFF):
      result += 2
    else:
      result += 1

proc isEmpty*(s: Span): bool {.inline.} =
  ## True if span has no content.
  s.content.len == 0

# -----------------------------------------------------------------------------
# Conversions
# -----------------------------------------------------------------------------

proc `$`*(s: Span): string =
  ## String representation of span (content only).
  s.content

# Implicit conversion from string
converter toSpan*(s: string): Span =
  span(s)
