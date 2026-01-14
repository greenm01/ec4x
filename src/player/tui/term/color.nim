## Color conversion and ANSI sequence generation.
##
## This module provides:
## - Color parsing from strings (hex, ANSI codes)
## - Color conversion between profiles (TrueColor -> ANSI256 -> ANSI)
## - ANSI escape sequence generation for colors

import std/[strutils, math]
import types/core
import constants/[escape, ansi]

# =============================================================================
# ANSI Sequence Generation
# =============================================================================

proc sequence*(c: AnsiColor, background: bool = false): string =
  ## Generate ANSI escape sequence for standard color.
  ## Uses classic 30-37/40-47 (normal) or 90-97/100-107 (bright).
  let code = int(c)
  if code < 8:
    # Normal colors: fg 30-37, bg 40-47
    if background:
      result = $(40 + code)
    else:
      result = $(30 + code)
  else:
    # Bright colors: fg 90-97, bg 100-107
    if background:
      result = $(100 + code - 8)
    else:
      result = $(90 + code - 8)

proc sequence*(c: Ansi256Color, background: bool = false): string =
  ## Generate ANSI escape sequence for 256-color.
  ## Format: 38;5;N (fg) or 48;5;N (bg)
  let prefix = if background: SgrBackground else: SgrForeground
  result = prefix & ";5;" & $int(c)

proc sequence*(c: RgbColor, background: bool = false): string =
  ## Generate ANSI escape sequence for true color RGB.
  ## Format: 38;2;R;G;B (fg) or 48;2;R;G;B (bg)
  let prefix = if background: SgrBackground else: SgrForeground
  result = prefix & ";2;" & $c.r & ";" & $c.g & ";" & $c.b

proc sequence*(c: Color, background: bool = false): string =
  ## Generate ANSI escape sequence for any color variant.
  case c.kind
  of ColorKind.None:
    result = ""
  of ColorKind.Ansi:
    result = sequence(c.ansi, background)
  of ColorKind.Ansi256:
    result = sequence(c.ansi256, background)
  of ColorKind.Rgb:
    result = sequence(c.rgb, background)


# =============================================================================
# Color Parsing
# =============================================================================

proc parseColor*(s: string): Color =
  ## Parse a color string.
  ## Accepts:
  ## - Hex: "#RGB", "#RRGGBB", "RGB", "RRGGBB"
  ## - ANSI code: "0"-"255"
  ## - Empty string: NoColor
  if s.len == 0:
    return noColor()

  # Try parsing as integer (ANSI code)
  try:
    let code = parseInt(s)
    if code >= 0 and code <= 15:
      return color(AnsiColor(code))
    elif code >= 0 and code <= 255:
      return color(Ansi256Color(code))
  except ValueError:
    discard

  # Try parsing as hex color
  if s[0] == '#' or s.len == 3 or s.len == 6:
    try:
      return color(rgb(s))
    except InvalidColorError:
      discard

  raise newException(InvalidColorError, "invalid color: " & s)


# =============================================================================
# Color Conversion (Profile Downgrade)
# =============================================================================

proc colorDistance*(c1, c2: RgbColor): float =
  ## Calculate perceptual color distance.
  ## Uses simple Euclidean distance in RGB space.
  ## TODO: Implement HSLuv distance for better accuracy.
  let dr = float(c1.r) - float(c2.r)
  let dg = float(c1.g) - float(c2.g)
  let db = float(c1.b) - float(c2.b)
  sqrt(dr*dr + dg*dg + db*db)

proc toAnsi256*(c: RgbColor): Ansi256Color =
  ## Convert RGB color to nearest 256-color palette entry.
  ## Uses color distance to find closest match.
  var bestIdx = 0
  var bestDist = float.high

  for i in 0..255:
    let palColor = rgb(AnsiHexTable[i])
    let dist = colorDistance(c, palColor)
    if dist < bestDist:
      bestDist = dist
      bestIdx = i

  Ansi256Color(bestIdx)

proc toAnsi*(c: Ansi256Color): AnsiColor =
  ## Convert 256-color to nearest standard ANSI color (0-15).
  if int(c) <= 15:
    return AnsiColor(int(c))

  let rgbVal = rgb(AnsiHexTable[int(c)])
  var bestIdx = 0
  var bestDist = float.high

  for i in 0..15:
    let palColor = rgb(AnsiHexTable[i])
    let dist = colorDistance(rgbVal, palColor)
    if dist < bestDist:
      bestDist = dist
      bestIdx = i

  AnsiColor(bestIdx)

proc toAnsi*(c: RgbColor): AnsiColor =
  ## Convert RGB color to nearest standard ANSI color.
  toAnsi(toAnsi256(c))

proc convert*(c: Color, profile: Profile): Color =
  ## Convert color to match profile capabilities.
  ## Downgrades color if profile doesn't support it.
  if c.isNone:
    return c

  case profile
  of Profile.Ascii:
    return noColor()
  of Profile.Ansi:
    case c.kind
    of ColorKind.None:
      return c
    of ColorKind.Ansi:
      return c
    of ColorKind.Ansi256:
      return color(toAnsi(c.ansi256))
    of ColorKind.Rgb:
      return color(toAnsi(c.rgb))
  of Profile.Ansi256:
    case c.kind
    of ColorKind.None, ColorKind.Ansi, ColorKind.Ansi256:
      return c
    of ColorKind.Rgb:
      return color(toAnsi256(c.rgb))
  of Profile.TrueColor:
    return c


# =============================================================================
# Profile-based Color Creation
# =============================================================================

proc color*(profile: Profile, s: string): Color =
  ## Create a color from string, respecting profile capabilities.
  let c = parseColor(s)
  convert(c, profile)
