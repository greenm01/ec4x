## Style building and rendering.
##
## Provides a fluent builder API for creating styled text with
## colors and attributes. Styles are immutable - each method
## returns a new Style.

import std/[strutils, unicode]
import types/[core, style]
import constants/escape
import color

export style.Style, style.StyleAttr, style.initStyle
export style.hasForeground, style.hasBackground, style.hasAttrs, style.isEmpty

# =============================================================================
# Style Builder Methods (Fluent API)
# =============================================================================

proc withText*(s: Style, text: string): Style =
  ## Set the text content.
  result = s
  result.text = text

proc foreground*(s: Style, c: Color): Style =
  ## Set foreground color.
  result = s
  result.fg = convert(c, s.profile)

proc foreground*(s: Style, c: AnsiColor): Style =
  ## Set foreground to ANSI color.
  result = s
  result.fg = color(c)

proc foreground*(s: Style, c: Ansi256Color): Style =
  ## Set foreground to 256-color.
  result = s
  result.fg = convert(color(c), s.profile)

proc foreground*(s: Style, c: RgbColor): Style =
  ## Set foreground to RGB color.
  result = s
  result.fg = convert(color(c), s.profile)

proc foreground*(s: Style, hex: string): Style =
  ## Set foreground from color string.
  result = s
  result.fg = color(s.profile, hex)

proc background*(s: Style, c: Color): Style =
  ## Set background color.
  result = s
  result.bg = convert(c, s.profile)

proc background*(s: Style, c: AnsiColor): Style =
  ## Set background to ANSI color.
  result = s
  result.bg = color(c)

proc background*(s: Style, c: Ansi256Color): Style =
  ## Set background to 256-color.
  result = s
  result.bg = convert(color(c), s.profile)

proc background*(s: Style, c: RgbColor): Style =
  ## Set background to RGB color.
  result = s
  result.bg = convert(color(c), s.profile)

proc background*(s: Style, hex: string): Style =
  ## Set background from color string.
  result = s
  result.bg = color(s.profile, hex)

# Shorthand aliases
proc fg*(s: Style, c: Color): Style {.inline.} = s.foreground(c)
proc fg*(s: Style, c: AnsiColor): Style {.inline.} = s.foreground(c)
proc fg*(s: Style, c: Ansi256Color): Style {.inline.} = s.foreground(c)
proc fg*(s: Style, c: RgbColor): Style {.inline.} = s.foreground(c)
proc fg*(s: Style, hex: string): Style {.inline.} = s.foreground(hex)

proc bg*(s: Style, c: Color): Style {.inline.} = s.background(c)
proc bg*(s: Style, c: AnsiColor): Style {.inline.} = s.background(c)
proc bg*(s: Style, c: Ansi256Color): Style {.inline.} = s.background(c)
proc bg*(s: Style, c: RgbColor): Style {.inline.} = s.background(c)
proc bg*(s: Style, hex: string): Style {.inline.} = s.background(hex)


# =============================================================================
# Style Attribute Methods
# =============================================================================

proc bold*(s: Style): Style =
  ## Enable bold text.
  result = s
  result.attrs.incl(StyleAttr.Bold)

proc faint*(s: Style): Style =
  ## Enable faint/dim text.
  result = s
  result.attrs.incl(StyleAttr.Faint)

proc italic*(s: Style): Style =
  ## Enable italic text.
  result = s
  result.attrs.incl(StyleAttr.Italic)

proc underline*(s: Style): Style =
  ## Enable underlined text.
  result = s
  result.attrs.incl(StyleAttr.Underline)

proc blink*(s: Style): Style =
  ## Enable blinking text.
  result = s
  result.attrs.incl(StyleAttr.Blink)

proc reverse*(s: Style): Style =
  ## Enable reverse video (swap fg/bg).
  result = s
  result.attrs.incl(StyleAttr.Reverse)

proc crossOut*(s: Style): Style =
  ## Enable strikethrough text.
  result = s
  result.attrs.incl(StyleAttr.CrossOut)

proc overline*(s: Style): Style =
  ## Enable overlined text.
  result = s
  result.attrs.incl(StyleAttr.Overline)

# Alias for strikethrough
proc strikethrough*(s: Style): Style {.inline.} = s.crossOut()


# =============================================================================
# Style Rendering
# =============================================================================

proc attrSequence(attr: StyleAttr): string =
  ## Get SGR code for attribute.
  case attr
  of StyleAttr.Bold: SgrBold
  of StyleAttr.Faint: SgrFaint
  of StyleAttr.Italic: SgrItalic
  of StyleAttr.Underline: SgrUnderline
  of StyleAttr.Blink: SgrBlink
  of StyleAttr.Reverse: SgrReverse
  of StyleAttr.CrossOut: SgrCrossOut
  of StyleAttr.Overline: SgrOverline

proc renderSequence*(s: Style): string =
  ## Generate the SGR sequence string (without CSI prefix or 'm' suffix).
  ## Returns empty string if no styling.
  var parts: seq[string]

  # Add attributes
  for attr in s.attrs:
    parts.add(attrSequence(attr))

  # Add foreground
  if not s.fg.isNone:
    parts.add(sequence(s.fg, background = false))

  # Add background
  if not s.bg.isNone:
    parts.add(sequence(s.bg, background = true))

  result = parts.join(";")

proc render*(s: Style): string =
  ## Render style as ANSI escape sequence (the opening sequence only).
  ## Returns empty string if no styling.
  let seq = renderSequence(s)
  if seq.len == 0:
    return ""
  CSI & seq & "m"

proc styled*(s: Style, text: string): string =
  ## Apply this style to arbitrary text.
  ## Returns text wrapped in ANSI sequences.
  if s.isEmpty:
    return text
  render(s) & text & ResetSeq

proc `$`*(s: Style): string =
  ## Render the styled text.
  styled(s, s.text)

proc width*(s: Style): int =
  ## Calculate the visual width of the styled text.
  ## Ignores ANSI escape sequences and uses Unicode rune count.
  runeLen(s.text)


# =============================================================================
# Convenience Constructors
# =============================================================================

proc styledText*(text: string, profile: Profile = Profile.TrueColor): Style =
  ## Create a style with text.
  initStyle(text, profile)

proc newStyle*(profile: Profile = Profile.TrueColor): Style =
  ## Create an empty style.
  initStyle(profile)
