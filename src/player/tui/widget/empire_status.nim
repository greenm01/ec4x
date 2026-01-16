## Empire Status Widget
##
## Displays empire-level statistics in a compact card format.
##
## Layout:
## ┌──────────────────────────────────────┐
## │ EMPIRE STATUS                        │
## ├──────────────────────────────────────┤
## │  COLONIES          FLEETS            │
## │  Owned   12  ▲2    Active    8       │
## │  Growth +1.4 PU    Reserve   3       │
## │  Tax Rate  52%     Mothball  2       │
## │                                      │
## │  DIPLOMACY         INTEL             │
## │  Neutral    3      Known Systems  44 │
## │  Hostile    1      Fogged         12 │
## │  Enemy      1      Scout Missions  3 │
## │  Proposals  2                        │
## └──────────────────────────────────────┘
##
## Reference: ec-style-layout.md Section 5.1

import std/[strformat, strutils]
import ../buffer
import ../layout/rect
import ../styles/ec_palette
import ./borders
import ./frame

export ec_palette

type
  EmpireStatusData* = object
    ## Data for empire status display
    # Colonies
    coloniesOwned*: int
    coloniesChange*: int          ## Change from last turn
    populationGrowth*: float      ## PU growth per turn
    taxRate*: int                 ## Tax rate percentage
    
    # Fleets
    fleetsActive*: int
    fleetsReserve*: int
    fleetsMothballed*: int
    
    # Diplomacy
    neutralHouses*: int
    hostileHouses*: int
    enemyHouses*: int
    pendingProposals*: int
    
    # Intelligence
    knownSystems*: int
    foggedSystems*: int
    scoutMissions*: int

# =============================================================================
# Empire Status Construction
# =============================================================================

proc initEmpireStatusData*(): EmpireStatusData =
  ## Create default empire status
  EmpireStatusData(
    coloniesOwned: 0,
    coloniesChange: 0,
    populationGrowth: 0.0,
    taxRate: 0,
    fleetsActive: 0,
    fleetsReserve: 0,
    fleetsMothballed: 0,
    neutralHouses: 0,
    hostileHouses: 0,
    enemyHouses: 0,
    pendingProposals: 0,
    knownSystems: 0,
    foggedSystems: 0,
    scoutMissions: 0
  )

# =============================================================================
# Empire Status Rendering
# =============================================================================

proc renderEmpireStatus*(area: Rect, buf: var CellBuffer,
                         data: EmpireStatusData) =
  ## Render empire status panel with frame
  if area.height < 6 or area.width < 30:
    return
  
  # Draw frame
  let frame = bordered()
    .title("EMPIRE STATUS")
    .borderType(BorderType.Plain)
    .borderStyle(primaryBorderStyle())
  frame.render(area, buf)
  
  let inner = frame.inner(area)
  var y = inner.y
  
  let headerStyle = canvasHeaderStyle()
  let normalStyle = canvasStyle()
  let dimStyle = canvasDimStyle()
  let positiveStyle = positiveStyle()
  let negativeStyle = negativeStyle()
  
  # === COLONIES and FLEETS (side by side) ===
  if y < inner.bottom:
    discard buf.setString(inner.x, y, "COLONIES", headerStyle)
    discard buf.setString(inner.x + 19, y, "FLEETS", headerStyle)
    y += 1
  
  # Colonies owned
  if y < inner.bottom:
    discard buf.setString(inner.x, y, "Owned   ", dimStyle)
    discard buf.setString(inner.x + 8, y, $data.coloniesOwned, normalStyle)
    
    # Change indicator
    if data.coloniesChange != 0:
      let changeStr = if data.coloniesChange > 0:
                        " " & GlyphTrendUp & $data.coloniesChange
                      else:
                        " " & GlyphTrendDown & $(-data.coloniesChange)
      let changeStyle = if data.coloniesChange > 0: positiveStyle else: negativeStyle
      discard buf.setString(inner.x + 11, y, changeStr, changeStyle)
    
    # Fleets active
    discard buf.setString(inner.x + 19, y, "Active  ", dimStyle)
    discard buf.setString(inner.x + 27, y, $data.fleetsActive, normalStyle)
    y += 1
  
  # Growth rate
  if y < inner.bottom:
    discard buf.setString(inner.x, y, "Growth ", dimStyle)
    let growthStr = if data.populationGrowth >= 0:
                      "+" & data.populationGrowth.formatFloat(ffDecimal, 1) & " PU"
                    else:
                      data.populationGrowth.formatFloat(ffDecimal, 1) & " PU"
    discard buf.setString(inner.x + 7, y, growthStr, normalStyle)
    
    # Fleets reserve
    discard buf.setString(inner.x + 19, y, "Reserve ", dimStyle)
    discard buf.setString(inner.x + 27, y, $data.fleetsReserve, normalStyle)
    y += 1
  
  # Tax rate
  if y < inner.bottom:
    discard buf.setString(inner.x, y, "Tax Rate  ", dimStyle)
    discard buf.setString(inner.x + 10, y, $data.taxRate & "%", normalStyle)
    
    # Fleets mothballed
    discard buf.setString(inner.x + 19, y, "Mothball", dimStyle)
    discard buf.setString(inner.x + 27, y, $data.fleetsMothballed, normalStyle)
    y += 1
  
  # Blank line
  y += 1
  
  # === DIPLOMACY and INTEL (side by side) ===
  if y < inner.bottom:
    discard buf.setString(inner.x, y, "DIPLOMACY", headerStyle)
    discard buf.setString(inner.x + 19, y, "INTEL", headerStyle)
    y += 1
  
  # Neutral houses / Known systems
  if y < inner.bottom:
    discard buf.setString(inner.x, y, "Neutral  ", dimStyle)
    discard buf.setString(inner.x + 9, y, $data.neutralHouses, normalStyle)
    
    discard buf.setString(inner.x + 19, y, "Known Systems ", dimStyle)
    discard buf.setString(inner.x + 33, y, $data.knownSystems, normalStyle)
    y += 1
  
  # Hostile houses / Fogged systems
  if y < inner.bottom:
    discard buf.setString(inner.x, y, "Hostile  ", dimStyle)
    discard buf.setString(inner.x + 9, y, $data.hostileHouses, normalStyle)
    
    discard buf.setString(inner.x + 19, y, "Fogged        ", dimStyle)
    discard buf.setString(inner.x + 33, y, $data.foggedSystems, normalStyle)
    y += 1
  
  # Enemy houses / Scout missions
  if y < inner.bottom:
    discard buf.setString(inner.x, y, "Enemy    ", dimStyle)
    discard buf.setString(inner.x + 9, y, $data.enemyHouses, normalStyle)
    
    discard buf.setString(inner.x + 19, y, "Scout Missions", dimStyle)
    discard buf.setString(inner.x + 33, y, $data.scoutMissions, normalStyle)
    y += 1
  
  # Proposals
  if y < inner.bottom and data.pendingProposals > 0:
    discard buf.setString(inner.x, y, "Proposals", dimStyle)
    discard buf.setString(inner.x + 9, y, $data.pendingProposals, alertStyle())

proc renderEmpireStatusCompact*(area: Rect, buf: var CellBuffer,
                                 data: EmpireStatusData) =
  ## Render compact empire status (no frame, just data)
  if area.height < 4 or area.width < 25:
    return
  
  var y = area.y
  let headerStyle = canvasHeaderStyle()
  let normalStyle = canvasStyle()
  let dimStyle = canvasDimStyle()
  
  # Header
  discard buf.setString(area.x, y, "EMPIRE STATUS", headerStyle)
  y += 1
  
  # Compact format
  if y < area.bottom:
    discard buf.setString(area.x, y, &"Colonies: {data.coloniesOwned}  ", normalStyle)
    discard buf.setString(area.x + 16, y, &"Fleets: {data.fleetsActive}", normalStyle)
    y += 1
  
  if y < area.bottom:
    discard buf.setString(area.x, y, &"Tax: {data.taxRate}%  ", normalStyle)
    discard buf.setString(area.x + 16, y, &"Growth: +{data.populationGrowth:.1f} PU", normalStyle)
    y += 1
  
  if y < area.bottom:
    let diplomacyStr = &"Neutral:{data.neutralHouses} Hostile:{data.hostileHouses} Enemy:{data.enemyHouses}"
    discard buf.setString(area.x, y, diplomacyStr, dimStyle)
