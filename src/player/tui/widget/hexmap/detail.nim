## Detail panel - System information panel for hex map
##
## Renders detailed information about the selected/cursor system.
## Displayed in the right panel alongside the hex map.

import std/[options, strformat, strutils]
import ./coords
import ./symbols
import ./hexmap
import ../frame
import ../../buffer
import ../../layout/rect
import ../../styles/ec_palette
import ../../hex_labels

type
  JumpLaneInfo* = object
    ## Jump lane display info
    targetName*: string
    targetCoord*: HexCoord
    laneClass*: int        ## 0=Major, 1=Minor, 2=Restricted

  FleetInfo* = object
    ## Fleet display info
    name*: string
    shipCount*: int
    isOwned*: bool

  DetailPanelData* = object
    ## Data for the detail panel
    system*: Option[SystemInfo]
    jumpLanes*: seq[JumpLaneInfo]
    fleets*: seq[FleetInfo]

# -----------------------------------------------------------------------------
# Rendering helpers
# -----------------------------------------------------------------------------

proc renderDivider(buf: var CellBuffer, x, y, width: int, 
                   label: string, style: CellStyle) =
  ## Render a labeled divider line: ─── Label ───
  let labelLen = label.len
  let leftLen = 3
  let rightLen = max(0, width - leftLen - labelLen - 2)
  
  var line = repeat("─", leftLen) & " " & label & " " & repeat("─", rightLen)
  if line.len > width:
    line = line[0 ..< width]
  
  discard buf.setString(x, y, line, style)

proc renderLabelValue(buf: var CellBuffer, x, y, width: int,
                      label: string, value: string,
                      labelStyle, valueStyle: CellStyle): int =
  ## Render "Label: Value" and return y + 1
  let labelText = label & ": "
  discard buf.setString(x, y, labelText, labelStyle)
  discard buf.setString(x + labelText.len, y, value, valueStyle)
  y + 1

# -----------------------------------------------------------------------------
# Main render
# -----------------------------------------------------------------------------

proc renderDetailPanel*(area: Rect, buf: var CellBuffer,
                        data: DetailPanelData, colors: HexColors) =
  ## Render the detail panel for selected system
  if area.isEmpty:
    return
  
  # Base styles
  let headerStyle = CellStyle(
    fg: colors.selected.fg,
    attrs: {StyleAttr.Bold}
  )
  let labelStyle = CellStyle(
    fg: color(CanvasDimColor),
    attrs: {}
  )
  let valueStyle = CellStyle(
    fg: color(CanvasFgColor),
    attrs: {}
  )
  let dividerStyle = CellStyle(
    fg: color(CanvasFogColor),
    attrs: {}
  )
  
  var y = area.y
  let x = area.x
  let width = area.width
  
  if data.system.isNone:
    # No system selected
    discard buf.setString(x, y, "No system selected", labelStyle)
    return
  
  let sys = data.system.get()
  
  # System name header
  let nameStyle = colors.styleFor(
    if sys.isHub: HexSymbol.Hub
    elif sys.isHomeworld: HexSymbol.Homeworld
    elif sys.owner.isSome: HexSymbol.Colony
    else: HexSymbol.Neutral
  )
  let nameDisplayStyle = CellStyle(
    fg: nameStyle.fg,
    attrs: {StyleAttr.Bold}
  )
  
  # Symbol + name
  let symStr = if sys.isHub: SymHub
               elif sys.isHomeworld: SymHomeworld
               elif sys.owner.isSome: SymColony
               else: SymNeutral
  discard buf.setString(x, y, symStr & " " & sys.name, nameDisplayStyle)
  y += 1
  
  # Divider under name
  discard buf.setString(x, y, repeat("═", min(width, sys.name.len + 3)), 
                        headerStyle)
  y += 2
  
  # Coordinates - use ring+position label
  let coordLabel = coordLabel(sys.coords.q, sys.coords.r)
  let coordStr = fmt"{coordLabel} [{sys.coords.q},{sys.coords.r}]"
  let ringStr = if sys.ring == 0: "Hub" else: fmt"Ring {sys.ring}"
  y = renderLabelValue(buf, x, y, width, "Coord", coordStr, labelStyle, valueStyle)
  y = renderLabelValue(buf, x, y, width, "Ring", ringStr, labelStyle, valueStyle)
  y += 1
  
  # Owner
  if sys.owner.isSome:
    let ownerStr = fmt"House {sys.owner.get()}"  # TODO: Get house name
    y = renderLabelValue(buf, x, y, width, "Owner", ownerStr, labelStyle, valueStyle)
  else:
    y = renderLabelValue(buf, x, y, width, "Owner", "Uncolonized", 
                         labelStyle, labelStyle)
  y += 1
  
  # Planet info
  let planetName = if sys.planetClass >= 0 and sys.planetClass < 7:
                     PlanetClassNames[sys.planetClass]
                   else: "Unknown"
  let planetLevel = if sys.planetClass >= 0 and sys.planetClass < 7:
                      PlanetClassLevels[sys.planetClass]
                    else: "?"
  let planetStr = fmt"{planetName} (Level {planetLevel})"
  let planetStyle = planetClassStyle(sys.planetClass)
  let planetCellStyle = CellStyle(fg: planetStyle.fg, attrs: {})
  
  discard buf.setString(x, y, "Planet: ", labelStyle)
  discard buf.setString(x + 8, y, planetStr, planetCellStyle)
  y += 1
  
  # Resources
  let resName = if sys.resourceRating >= 0 and sys.resourceRating < 5:
                  ResourceRatingNames[sys.resourceRating]
                else: "Unknown"
  let resStyle = resourceStyle(sys.resourceRating)
  let resCellStyle = CellStyle(fg: resStyle.fg, attrs: {})
  
  discard buf.setString(x, y, "Resources: ", labelStyle)
  discard buf.setString(x + 11, y, resName, resCellStyle)
  y += 2
  
  # Jump lanes section
  if data.jumpLanes.len > 0:
    renderDivider(buf, x, y, width, "Jump Lanes", dividerStyle)
    y += 1
    
    for lane in data.jumpLanes:
      if y >= area.bottom:
        break
      
      let laneStyle = case lane.laneClass
        of 0: colors.jumpLaneMajor
        of 1: colors.jumpLaneMinor
        else: colors.jumpLaneRestricted
      let laneCellStyle = CellStyle(fg: laneStyle.fg, attrs: {})
      
      let laneSymbol = if lane.laneClass < 3: LaneClassSymbols[lane.laneClass]
                       else: "─"
      let laneName = if lane.laneClass < 3: LaneClassNames[lane.laneClass]
                     else: "Unknown"
      
      let laneStr = fmt"{laneSymbol} {lane.targetName} [{lane.targetCoord.q},{lane.targetCoord.r}] {laneName}"
      discard buf.setString(x, y, laneStr, laneCellStyle)
      y += 1
    
    y += 1
  
  # Fleets section
  if data.fleets.len > 0:
    renderDivider(buf, x, y, width, "Fleets", dividerStyle)
    y += 1
    
    for fleet in data.fleets:
      if y >= area.bottom:
        break
      
      let fleetStyle = if fleet.isOwned:
                         CellStyle(fg: colors.colony.fg, attrs: {})
                       else:
                         CellStyle(fg: colors.enemyColony.fg, attrs: {})
      
      let fleetStr = fmt"▲ {fleet.name} ({fleet.shipCount} ships)"
      discard buf.setString(x, y, fleetStr, fleetStyle)
      y += 1
