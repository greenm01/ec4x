## SVG builder - utilities for constructing SVG strings
##
## Provides helper procs for building SVG elements without
## external dependencies.

import std/[strformat, strutils]

type
  SvgBuilder* = object
    width*, height*: int
    elements: seq[string]

# -----------------------------------------------------------------------------
# Color constants
# -----------------------------------------------------------------------------

const
  ColorBackground* = "#000000"
  ColorWhite* = "#FFFFFF"
  ColorGold* = "#B8860B"
  ColorSteelBlue* = "#4682B4"
  ColorDarkRed* = "#8B0000"
  ColorDarkGray* = "#333333"
  ColorLightGray* = "#AAAAAA"
  ColorMediumGray* = "#888888"

# Default house colors
const HouseColors* = [
  "#4169E1",  # House 0 - Royal Blue
  "#DC143C",  # House 1 - Crimson
  "#32CD32",  # House 2 - Lime Green
  "#FFD700",  # House 3 - Gold
  "#9932CC",  # House 4 - Dark Orchid
  "#FF8C00",  # House 5 - Dark Orange
  "#00CED1",  # House 6 - Dark Turquoise
  "#FF1493",  # House 7 - Deep Pink
  "#7FFF00",  # House 8 - Chartreuse
  "#8A2BE2",  # House 9 - Blue Violet
  "#FF6347",  # House 10 - Tomato
  "#00FA9A",  # House 11 - Medium Spring Green
]

proc houseColor*(houseId: int): string =
  ## Get color for a house by ID
  if houseId >= 0 and houseId < HouseColors.len:
    HouseColors[houseId]
  else:
    ColorWhite

# -----------------------------------------------------------------------------
# Builder initialization
# -----------------------------------------------------------------------------

proc initSvgBuilder*(width, height: int): SvgBuilder =
  ## Create a new SVG builder
  SvgBuilder(width: width, height: height, elements: @[])

proc add*(builder: var SvgBuilder, element: string) =
  ## Add an element to the builder
  builder.elements.add(element)

# -----------------------------------------------------------------------------
# SVG elements
# -----------------------------------------------------------------------------

proc svgHeader*(width, height: int): string =
  ## Generate SVG header with styles
  ## Note: Background is an explicit rect, not CSS, for Inkscape compatibility
  result = &"""<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" 
     viewBox="0 0 {width} {height}"
     width="{width}" height="{height}">
  
  <defs>
    <style>
      /* Lane styles */
      .lane {{ stroke-linecap: round; }}
      .lane-major {{ stroke: {ColorGold}; stroke-width: 3; }}
      .lane-minor {{ stroke: {ColorSteelBlue}; stroke-width: 2; 
                    stroke-dasharray: 8,4; }}
      .lane-restricted {{ stroke: {ColorDarkRed}; stroke-width: 1.5; 
                         stroke-dasharray: 3,3; }}
      
      /* Node styles */
      .node-hub {{ fill: {ColorGold}; stroke: {ColorWhite}; stroke-width: 2; }}
      .node-own {{ stroke: none; }}
      .node-enemy {{ fill: transparent; stroke-width: 2; }}
      .node-neutral {{ fill: {ColorDarkGray}; stroke: {ColorWhite}; 
                       stroke-width: 1; }}
      
      /* Label styles */
      .label {{ fill: {ColorWhite}; font-family: monospace; 
               text-anchor: middle; }}
      .label-name {{ font-size: 11px; font-weight: bold; }}
      .label-coord {{ fill: {ColorLightGray}; font-size: 9px; }}
      .label-info {{ fill: {ColorMediumGray}; font-size: 8px; }}
      
      /* Legend styles */
      .legend-text {{ fill: {ColorWhite}; font-family: monospace; 
                     font-size: 10px; }}
      .legend-title {{ fill: {ColorWhite}; font-family: monospace; 
                      font-size: 12px; font-weight: bold; }}
    </style>
  </defs>
  
  <!-- Explicit background rectangle for Inkscape/export compatibility -->
  <rect id="background" x="0" y="0" width="{width}" height="{height}" fill="{ColorBackground}"/>
"""

proc svgFooter*(): string =
  ## Generate SVG footer
  "</svg>\n"

proc svgLine*(x1, y1, x2, y2: float, class: string): string =
  ## Generate a line element
  &"""  <line class="{class}" x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}"/>"""

proc svgCircle*(cx, cy, r: float, class: string,
                style: string = ""): string =
  ## Generate a circle element
  if style.len > 0:
    &"""  <circle class="{class}" cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" style="{style}"/>"""
  else:
    &"""  <circle class="{class}" cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}"/>"""

proc svgText*(x, y: float, text: string, class: string): string =
  ## Generate a text element
  let escaped = text.replace("&", "&amp;").replace("<", "&lt;")
                    .replace(">", "&gt;")
  &"""  <text class="{class}" x="{x:.1f}" y="{y:.1f}">{escaped}</text>"""

proc svgGroup*(id: string, content: string): string =
  ## Wrap content in a group
  &"""  <g id="{id}">
{content}
  </g>"""

proc svgGroupTransform*(id: string, tx, ty: float, content: string): string =
  ## Wrap content in a transformed group
  &"""  <g id="{id}" transform="translate({tx:.1f},{ty:.1f})">
{content}
  </g>"""

# -----------------------------------------------------------------------------
# Lane class helpers
# -----------------------------------------------------------------------------

proc laneClass*(laneType: int): string =
  ## Get CSS class for lane type
  ## 0 = Major, 1 = Minor, 2 = Restricted
  case laneType
  of 0: "lane lane-major"
  of 1: "lane lane-minor"
  else: "lane lane-restricted"

# -----------------------------------------------------------------------------
# Node class helpers
# -----------------------------------------------------------------------------

type
  NodeType* {.pure.} = enum
    Hub
    OwnColony
    EnemyColony
    Neutral

proc nodeClass*(nodeType: NodeType): string =
  ## Get CSS class for node type
  case nodeType
  of NodeType.Hub: "node-hub"
  of NodeType.OwnColony: "node-own"
  of NodeType.EnemyColony: "node-enemy"
  of NodeType.Neutral: "node-neutral"

proc nodeRadius*(nodeType: NodeType, isHomeworld: bool = false): float =
  ## Get radius for node type
  case nodeType
  of NodeType.Hub: 14.0
  of NodeType.OwnColony:
    if isHomeworld: 12.0 else: 10.0
  of NodeType.EnemyColony: 10.0
  of NodeType.Neutral: 6.0

# -----------------------------------------------------------------------------
# Build complete SVG
# -----------------------------------------------------------------------------

proc build*(builder: SvgBuilder): string =
  ## Build the complete SVG string
  result = svgHeader(builder.width, builder.height)
  for element in builder.elements:
    result.add(element)
    result.add("\n")
  result.add(svgFooter())
