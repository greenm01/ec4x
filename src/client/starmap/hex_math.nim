## Hex coordinate math utilities for flat-top hexagonal grids
##
## Uses axial coordinates (q, r) matching the engine's Hex type.
## Flat-top orientation means the hexes have a flat edge at the top.

import std/math

type
  Vec2* = object
    x*, y*: float32

  HexCoord* = object
    ## Axial hex coordinates (matches engine's Hex type)
    q*, r*: int32

  FractionalHex = object
    ## Fractional hex for pixel-to-hex conversion
    q, r: float32

const
  HexSize* = 50.0f  ## Default hex radius in pixels at zoom 1.0

# --- Vec2 helpers ---

proc vec2*(x, y: float32): Vec2 {.inline.} =
  Vec2(x: x, y: y)

proc `+`*(a, b: Vec2): Vec2 {.inline.} =
  vec2(a.x + b.x, a.y + b.y)

proc `-`*(a, b: Vec2): Vec2 {.inline.} =
  vec2(a.x - b.x, a.y - b.y)

proc `*`*(v: Vec2, s: float32): Vec2 {.inline.} =
  vec2(v.x * s, v.y * s)

proc `/`*(v: Vec2, s: float32): Vec2 {.inline.} =
  vec2(v.x / s, v.y / s)

proc length*(v: Vec2): float32 {.inline.} =
  sqrt(v.x * v.x + v.y * v.y)

proc distance*(a, b: Vec2): float32 {.inline.} =
  (b - a).length

# --- Hex coordinate helpers ---

proc hexCoord*(q, r: int32): HexCoord {.inline.} =
  HexCoord(q: q, r: r)

proc hexCoord*(q, r: int): HexCoord {.inline.} =
  HexCoord(q: q.int32, r: r.int32)

# --- Hex to Pixel (flat-top orientation) ---

proc hexToPixel*(hex: HexCoord, size: float32 = HexSize): Vec2 =
  ## Convert axial hex coordinates to pixel coordinates (flat-top).
  ## The hex at (0,0) is centered at pixel (0,0).
  let x = size * (3.0f / 2.0f * hex.q.float32)
  let y = size * (sqrt(3.0f) / 2.0f * hex.q.float32 +
                  sqrt(3.0f) * hex.r.float32)
  vec2(x, y)

# --- Pixel to Hex (flat-top orientation) ---

proc pixelToFractionalHex(point: Vec2, size: float32): FractionalHex =
  ## Convert pixel coordinates to fractional hex coordinates.
  let q = (2.0f / 3.0f * point.x) / size
  let r = (-1.0f / 3.0f * point.x + sqrt(3.0f) / 3.0f * point.y) / size
  FractionalHex(q: q, r: r)

proc hexRound(frac: FractionalHex): HexCoord =
  ## Round fractional hex coordinates to the nearest hex.
  ## Uses cube coordinate rounding for accuracy.
  var q = round(frac.q)
  var r = round(frac.r)
  let s = round(-frac.q - frac.r)

  let qDiff = abs(q - frac.q)
  let rDiff = abs(r - frac.r)
  let sDiff = abs(s - (-frac.q - frac.r))

  if qDiff > rDiff and qDiff > sDiff:
    q = -r - s
  elif rDiff > sDiff:
    r = -q - s
  # else: s is the largest, but we don't need it

  hexCoord(q.int32, r.int32)

proc pixelToHex*(point: Vec2, size: float32 = HexSize): HexCoord =
  ## Convert pixel coordinates to the nearest hex coordinate.
  hexRound(pixelToFractionalHex(point, size))

# --- Hex Geometry ---

proc hexCorner*(center: Vec2, size: float32, corner: int): Vec2 =
  ## Get the pixel position of a hex corner (0-5).
  ## Corner 0 is at the right (3 o'clock), proceeding counter-clockwise.
  ## For flat-top: corners are at 0, 60, 120, 180, 240, 300 degrees.
  let angleDeg = 60.0f * corner.float32
  let angleRad = PI.float32 / 180.0f * angleDeg
  vec2(center.x + size * cos(angleRad),
       center.y + size * sin(angleRad))

proc hexVertices*(center: Vec2, size: float32): array[6, Vec2] =
  ## Get all 6 vertices of a hex centered at the given pixel position.
  for i in 0..5:
    result[i] = hexCorner(center, size, i)

proc hexVerticesFromCoord*(hex: HexCoord,
    size: float32 = HexSize): array[6, Vec2] =
  ## Get all 6 vertices of a hex from its axial coordinates.
  let center = hexToPixel(hex, size)
  hexVertices(center, size)

# --- Hex Distance ---

proc hexDistance*(a, b: HexCoord): int32 =
  ## Calculate the hex grid distance between two hexes.
  ## Uses the cube coordinate formula.
  let dq = abs(a.q - b.q)
  let dr = abs(a.r - b.r)
  let ds = abs((-a.q - a.r) - (-b.q - b.r))
  max(dq, max(dr, ds))

# --- Point-in-Hex test ---

proc isPointInHex*(point, hexCenter: Vec2, size: float32): bool =
  ## Check if a point is inside a hex centered at hexCenter.
  ## Uses a simplified distance check (not pixel-perfect but fast).
  let d = distance(point, hexCenter)
  # Inner radius of a flat-top hex (distance from center to edge midpoint)
  let innerRadius = size * sqrt(3.0f) / 2.0f
  d <= innerRadius

proc findHexAt*(point: Vec2, size: float32 = HexSize): HexCoord =
  ## Find the hex coordinate at the given pixel position.
  ## Alias for pixelToHex for semantic clarity.
  pixelToHex(point, size)
