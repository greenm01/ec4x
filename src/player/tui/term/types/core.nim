## Core types for terminal environment handling.
##
## This module defines the fundamental types used throughout the termenv port:
## - Profile: Represents terminal color capability levels
## - Color: A concept for types that can generate ANSI sequences
## - Error types for terminal operations

import std/[colors, strutils]

type
  Profile* {.pure.} = enum
    ## Terminal color profile representing capability levels.
    ## Order matters: higher values = less capability (for downgrade logic).
    TrueColor = 0  ## 24-bit RGB (16 million colors)
    Ansi256 = 1    ## 8-bit (256 colors)
    Ansi = 2       ## 4-bit (16 colors)
    Ascii = 3      ## No color support

  TermError* = object of CatchableError
    ## Base error type for terminal operations.

  StatusReportError* = object of TermError
    ## Unable to retrieve terminal status report.

  InvalidColorError* = object of TermError
    ## Invalid color specification.

# Forward declarations for color types (defined in color.nim)
type
  NoColor* = object
    ## Represents no color / unset color.
    discard

  AnsiColor* = distinct range[0..15]
    ## Standard ANSI color (0-15).
    ## 0-7: normal colors, 8-15: bright colors.

  Ansi256Color* = distinct range[0..255]
    ## Extended 256-color palette.
    ## 0-15: standard ANSI, 16-231: color cube, 232-255: grayscale.

  RgbColor* = object
    ## True color RGB value.
    r*, g*, b*: uint8

  ## Unified color type using object variants for type-safe color handling.
  ColorKind* {.pure.} = enum
    None
    Ansi
    Ansi256
    Rgb

  Color* = object
    ## Polymorphic color type using object variant.
    case kind*: ColorKind
    of ColorKind.None:
      discard
    of ColorKind.Ansi:
      ansi*: AnsiColor
    of ColorKind.Ansi256:
      ansi256*: Ansi256Color
    of ColorKind.Rgb:
      rgb*: RgbColor

# Equality operators for distinct types
proc `==`*(a, b: AnsiColor): bool = int(a) == int(b)
proc `==`*(a, b: Ansi256Color): bool = int(a) == int(b)


# Constructors for Color variant
proc noColor*(): Color {.inline.} =
  Color(kind: ColorKind.None)

proc color*(c: AnsiColor): Color {.inline.} =
  Color(kind: ColorKind.Ansi, ansi: c)

proc color*(c: Ansi256Color): Color {.inline.} =
  Color(kind: ColorKind.Ansi256, ansi256: c)

proc color*(c: RgbColor): Color {.inline.} =
  Color(kind: ColorKind.Rgb, rgb: c)

proc color*(r, g, b: uint8): Color {.inline.} =
  Color(kind: ColorKind.Rgb, rgb: RgbColor(r: r, g: g, b: b))


# Profile utilities
proc name*(p: Profile): string =
  ## Returns human-readable profile name.
  case p
  of Profile.TrueColor: "TrueColor"
  of Profile.Ansi256: "ANSI256"
  of Profile.Ansi: "ANSI"
  of Profile.Ascii: "Ascii"

proc `$`*(p: Profile): string = p.name

proc supportsColor*(p: Profile): bool {.inline.} =
  ## Returns true if profile supports any color.
  p != Profile.Ascii

proc supports256*(p: Profile): bool {.inline.} =
  ## Returns true if profile supports 256 colors or more.
  p <= Profile.Ansi256

proc supportsTrueColor*(p: Profile): bool {.inline.} =
  ## Returns true if profile supports 24-bit color.
  p == Profile.TrueColor


# AnsiColor utilities
proc `$`*(c: AnsiColor): string = $int(c)

proc isBright*(c: AnsiColor): bool {.inline.} =
  ## Returns true if this is a bright/high-intensity color (8-15).
  int(c) >= 8


# Ansi256Color utilities
proc `$`*(c: Ansi256Color): string = $int(c)

proc isStandard*(c: Ansi256Color): bool {.inline.} =
  ## Returns true if color is in standard ANSI range (0-15).
  int(c) <= 15

proc isCube*(c: Ansi256Color): bool {.inline.} =
  ## Returns true if color is in the 6x6x6 color cube (16-231).
  int(c) >= 16 and int(c) <= 231

proc isGrayscale*(c: Ansi256Color): bool {.inline.} =
  ## Returns true if color is in grayscale ramp (232-255).
  int(c) >= 232


# RgbColor utilities
proc `==`*(a, b: RgbColor): bool {.inline.} =
  a.r == b.r and a.g == b.g and a.b == b.b

proc toHexByte(v: uint8): string =
  ## Convert byte to 2-char hex string.
  const hexChars = "0123456789abcdef"
  result = newString(2)
  result[0] = hexChars[v shr 4]
  result[1] = hexChars[v and 0xF]

proc `$`*(c: RgbColor): string =
  "#" & toHexByte(c.r) & toHexByte(c.g) & toHexByte(c.b)

proc rgb*(hex: string): RgbColor =
  ## Parse hex color string (with or without #).
  ## Supports: "#RRGGBB", "RRGGBB", "#RGB", "RGB"
  var s = hex
  if s.len > 0 and s[0] == '#':
    s = s[1..^1]

  if s.len == 3:
    # Short form: #RGB -> #RRGGBB
    result.r = uint8(parseHexInt($s[0] & $s[0]))
    result.g = uint8(parseHexInt($s[1] & $s[1]))
    result.b = uint8(parseHexInt($s[2] & $s[2]))
  elif s.len == 6:
    result.r = uint8(parseHexInt(s[0..1]))
    result.g = uint8(parseHexInt(s[2..3]))
    result.b = uint8(parseHexInt(s[4..5]))
  else:
    raise newException(InvalidColorError, "invalid hex color: " & hex)

proc fromStdColor*(c: colors.Color): RgbColor =
  ## Convert std/colors Color to RgbColor.
  let (r, g, b) = c.extractRGB()
  RgbColor(r: uint8(r), g: uint8(g), b: uint8(b))

proc toStdColor*(c: RgbColor): colors.Color =
  ## Convert RgbColor to std/colors Color.
  colors.rgb(int(c.r), int(c.g), int(c.b))


# Color variant utilities
proc `==`*(a, b: Color): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of ColorKind.None: true
  of ColorKind.Ansi: int(a.ansi) == int(b.ansi)
  of ColorKind.Ansi256: int(a.ansi256) == int(b.ansi256)
  of ColorKind.Rgb: a.rgb.r == b.rgb.r and a.rgb.g == b.rgb.g and a.rgb.b == b.rgb.b

proc isNone*(c: Color): bool {.inline.} =
  c.kind == ColorKind.None

proc `$`*(c: Color): string =
  case c.kind
  of ColorKind.None: ""
  of ColorKind.Ansi: $c.ansi
  of ColorKind.Ansi256: $c.ansi256
  of ColorKind.Rgb: $c.rgb
