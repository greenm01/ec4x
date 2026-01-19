## Starmap Theme - Colors from config/dynatoi.kdl
##
## Loads house colors and starmap colors for rendering.
## Simplified loader that doesn't depend on engine config system.

import std/strutils

type
  Color* = object
    ## RGBA color (0.0-1.0 range)
    r*, g*, b*, a*: float32

  StarmapTheme* = object
    ## Colors for starmap rendering
    backgroundColor*: Color
    majorLaneColor*: Color
    minorLaneColor*: Color
    restrictedLaneColor*: Color
    unownedColonyColor*: Color
    gridLineColor*: Color
    houseColors*: array[12, Color]
    houseNames*: array[12, string]

# --- Color Helpers ---

proc color*(r, g, b: float32, a: float32 = 1.0f): Color {.inline.} =
  Color(r: r, g: g, b: b, a: a)

proc color*(r, g, b: uint8, a: uint8 = 255): Color {.inline.} =
  Color(
    r: r.float32 / 255.0f,
    g: g.float32 / 255.0f,
    b: b.float32 / 255.0f,
    a: a.float32 / 255.0f
  )

proc parseHexColor*(hex: string): Color =
  ## Parse hex color string like "#4169E1" or "#FF0000"
  var s = hex
  if s.startsWith("#"):
    s = s[1..^1]
  
  if s.len == 6:
    let r = parseHexInt(s[0..1]).uint8
    let g = parseHexInt(s[2..3]).uint8
    let b = parseHexInt(s[4..5]).uint8
    return color(r, g, b)
  elif s.len == 8:
    let r = parseHexInt(s[0..1]).uint8
    let g = parseHexInt(s[2..3]).uint8
    let b = parseHexInt(s[4..5]).uint8
    let a = parseHexInt(s[6..7]).uint8
    return color(r, g, b, a)
  else:
    # Fallback to white
    return color(1.0f, 1.0f, 1.0f)

proc withAlpha*(c: Color, a: float32): Color {.inline.} =
  Color(r: c.r, g: c.g, b: c.b, a: a)

proc lighter*(c: Color, factor: float32 = 0.3f): Color =
  ## Make color lighter by mixing with white
  Color(
    r: c.r + (1.0f - c.r) * factor,
    g: c.g + (1.0f - c.g) * factor,
    b: c.b + (1.0f - c.b) * factor,
    a: c.a
  )

proc darker*(c: Color, factor: float32 = 0.3f): Color =
  ## Make color darker by scaling toward black
  Color(
    r: c.r * (1.0f - factor),
    g: c.g * (1.0f - factor),
    b: c.b * (1.0f - factor),
    a: c.a
  )

# --- Default Theme (hardcoded from dynatoi.kdl) ---

proc defaultTheme*(): StarmapTheme =
  ## Returns the default dynatoi theme with hardcoded values.
  ## This avoids needing KDL parsing in the client for now.
  result.backgroundColor = parseHexColor("#000000")  # black
  result.majorLaneColor = parseHexColor("#B8860B")   # darkgoldenrod
  result.minorLaneColor = parseHexColor("#4682B4")   # steelblue
  result.restrictedLaneColor = parseHexColor("#8B0000")  # darkred
  result.unownedColonyColor = parseHexColor("#FFFFF0")   # ivory
  result.gridLineColor = parseHexColor("#404040")    # dark charcoal gray

  # House colors (from dynatoi.kdl)
  result.houseColors[0] = parseHexColor("#4169E1")   # royalblue - Valerian
  result.houseColors[1] = parseHexColor("#DC143C")   # crimson - Thelon
  result.houseColors[2] = parseHexColor("#2E8B57")   # seagreen - Marius
  result.houseColors[3] = parseHexColor("#FFD700")   # gold - Kalan
  result.houseColors[4] = parseHexColor("#9932CC")   # darkorchid - Delos
  result.houseColors[5] = parseHexColor("#FF8C00")   # darkorange - Stratos
  result.houseColors[6] = parseHexColor("#00BFFF")   # deepskyblue - Nikos
  result.houseColors[7] = parseHexColor("#5F9EA0")   # cadetblue - Hektor
  result.houseColors[8] = parseHexColor("#6B8E23")   # olivedrab - Krios
  result.houseColors[9] = parseHexColor("#4B0082")   # indigo - Zenos
  result.houseColors[10] = parseHexColor("#008B8B")  # darkcyan - Theron
  result.houseColors[11] = parseHexColor("#B22222")  # firebrick - Alexos

  # House names
  result.houseNames[0] = "Valerian"
  result.houseNames[1] = "Thelon"
  result.houseNames[2] = "Marius"
  result.houseNames[3] = "Kalan"
  result.houseNames[4] = "Delos"
  result.houseNames[5] = "Stratos"
  result.houseNames[6] = "Nikos"
  result.houseNames[7] = "Hektor"
  result.houseNames[8] = "Krios"
  result.houseNames[9] = "Zenos"
  result.houseNames[10] = "Theron"
  result.houseNames[11] = "Alexos"

proc houseColor*(theme: StarmapTheme, houseIndex: int): Color =
  ## Get color for a house by index (0-11)
  if houseIndex >= 0 and houseIndex < 12:
    theme.houseColors[houseIndex]
  else:
    theme.unownedColonyColor

proc houseName*(theme: StarmapTheme, houseIndex: int): string =
  ## Get name for a house by index (0-11)
  if houseIndex >= 0 and houseIndex < 12:
    theme.houseNames[houseIndex]
  else:
    "Unknown"
