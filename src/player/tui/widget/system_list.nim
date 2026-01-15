## System list widget - text-mode connectivity display
##
## Shows systems with their jump lane connections in a compact
## list format for TUI reference.

import std/[strutils, options]
import ../buffer
import ../layout/rect
import ../term/term
import ../term/types/core

type
  SystemListEntry* = object
    id*: int
    name*: string
    coordLabel*: string
    q*, r*: int
    connections*: seq[tuple[label: string, laneType: int]]
    ownerName*: Option[string]
    isOwned*: bool

  SystemListData* = object
    systems*: seq[SystemListEntry]
    selectedIdx*: int

# Lane type symbols
const
  LaneMajor* = "\xe2\x94\x81\xe2\x94\x81"    # ━━
  LaneMinor* = "\xe2\x94\x84\xe2\x94\x84"    # ┄┄
  LaneRestricted* = "\xc2\xb7\xc2\xb7"       # ··

proc laneSymbol(laneType: int): string =
  case laneType
  of 0: LaneMajor
  of 1: LaneMinor
  else: LaneRestricted

proc dimStyle(): CellStyle =
  CellStyle(fg: color(Ansi256Color(245)), attrs: {})

proc normalStyle(): CellStyle =
  CellStyle(fg: color(Ansi256Color(252)), attrs: {})

proc highlightStyle(): CellStyle =
  CellStyle(fg: color(Ansi256Color(226)), attrs: {StyleAttr.Bold})

proc selectedStyle(): CellStyle =
  CellStyle(fg: color(Ansi256Color(16)), bg: color(Ansi256Color(226)),
            attrs: {StyleAttr.Bold})

proc majorStyle(): CellStyle =
  CellStyle(fg: color(Ansi256Color(178)), attrs: {})  # Gold

proc minorStyle(): CellStyle =
  CellStyle(fg: color(Ansi256Color(67)), attrs: {})   # Steel blue

proc restrictedStyle(): CellStyle =
  CellStyle(fg: color(Ansi256Color(124)), attrs: {})  # Dark red

proc laneStyle(laneType: int): CellStyle =
  case laneType
  of 0: majorStyle()
  of 1: minorStyle()
  else: restrictedStyle()

proc renderSystemList*(area: Rect, buf: var CellBuffer,
                       data: SystemListData) =
  ## Render the system list
  if area.isEmpty:
    return
  
  var y = area.y
  
  for idx, sys in data.systems:
    if y >= area.bottom:
      break
    
    let isSelected = idx == data.selectedIdx
    let baseStyle = if isSelected: selectedStyle() else: normalStyle()
    
    var x = area.x
    
    # Coordinate label (e.g., "A3")
    let coordStr = sys.coordLabel.alignLeft(4)
    discard buf.setString(x, y, coordStr, 
                          if isSelected: selectedStyle() else: highlightStyle())
    x += 5
    
    # System name
    let nameStr = sys.name.alignLeft(12)
    discard buf.setString(x, y, nameStr, baseStyle)
    x += 13
    
    # Connections with lane type symbols
    for i, conn in sys.connections:
      if x >= area.right - 4:
        discard buf.setString(x, y, "...", dimStyle())
        break
      
      let sym = laneSymbol(conn.laneType)
      discard buf.setString(x, y, sym, laneStyle(conn.laneType))
      x += 2
      
      discard buf.setString(x, y, conn.label, 
                            if isSelected: selectedStyle() else: normalStyle())
      x += conn.label.len + 1
    
    # Owner tag if applicable
    if sys.ownerName.isSome and x < area.right - 10:
      let tag = "[" & sys.ownerName.get() & "]"
      let tagStyle = if sys.isOwned: highlightStyle() else: dimStyle()
      discard buf.setString(area.right - tag.len - 1, y, tag, tagStyle)
    
    y += 1

proc renderSystemDetail*(area: Rect, buf: var CellBuffer,
                         sys: SystemListEntry) =
  ## Render detailed view of a single system
  if area.isEmpty:
    return
  
  var y = area.y
  let x = area.x
  
  # Header
  discard buf.setString(x, y, sys.coordLabel & " " & sys.name, highlightStyle())
  y += 2
  
  # Owner
  if sys.ownerName.isSome:
    discard buf.setString(x, y, "Owner: ", dimStyle())
    discard buf.setString(x + 7, y, sys.ownerName.get(), normalStyle())
    y += 2
  
  # Connections header
  discard buf.setString(x, y, "Connections:", dimStyle())
  y += 1
  
  # List each connection
  for conn in sys.connections:
    if y >= area.bottom:
      break
    
    let sym = laneSymbol(conn.laneType)
    let laneTypeName = case conn.laneType
      of 0: "Major"
      of 1: "Minor"
      else: "Restricted"
    
    discard buf.setString(x + 2, y, sym, laneStyle(conn.laneType))
    discard buf.setString(x + 5, y, conn.label, normalStyle())
    discard buf.setString(x + 10, y, laneTypeName, dimStyle())
    y += 1
