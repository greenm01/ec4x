## HUD Strip Widget
##
## The HUD Strip is the top status bar showing empire-critical data at all times:
## - Empire name and turn number (left)
## - Prestige with standing (center-left)
## - Treasury PP and production (center)
## - Command capacity (center-right)
## - Alert/message counts (right)
##
## Layout (120 columns):
## ╔═══════════════════════════════════════════════════════════════════════════╗
## ║ EMPIRE: House Valerian  ▸ Turn 42  ★ 487 (2nd)  PP: 1,820  PROD: 640  ⚠ 3 ║
## ╚═══════════════════════════════════════════════════════════════════════════╝
##
## Reference: ec-style-layout.md Section 2 "Screen Regions" and Section 5.1

import std/strutils
import ../buffer
import ../layout/rect
import ../styles/ec_palette

export ec_palette

type
  HudData* = object
    ## Data for HUD strip rendering
    houseName*: string
    turn*: int
    prestige*: int
    prestigeRank*: int      ## 1st, 2nd, etc. (0 = unknown)
    totalHouses*: int       ## For "Xth of Y"
    treasury*: int          ## Credits/Production Points
    production*: int        ## Net House Value (production income)
    commandUsed*: int       ## Current command capacity used
    commandMax*: int        ## Maximum command capacity
    alertCount*: int        ## Number of alerts/warnings
    unreadMessages*: int    ## Unread messages/reports

  CommandCapacityStatus* {.pure.} = enum
    ## C2 capacity status
    Ok        ## Within capacity
    Strain    ## Over capacity (logistical penalties)

proc commandStatus*(data: HudData): CommandCapacityStatus =
  ## Get command capacity status
  if data.commandUsed <= data.commandMax:
    CommandCapacityStatus.Ok
  else:
    CommandCapacityStatus.Strain

proc formatRank*(rank: int): string =
  ## Format rank as ordinal (1st, 2nd, 3rd, etc.)
  if rank <= 0:
    return "?"
  case rank
  of 1: "1st"
  of 2: "2nd"
  of 3: "3rd"
  else: $rank & "th"

proc formatNumber*(n: int): string =
  ## Format number with comma separators for thousands
  if n < 1000:
    return $n
  var s = $n
  var res = ""
  var count = 0
  for i in countdown(s.high, 0):
    if count > 0 and count mod 3 == 0:
      res = "," & res
    res = s[i] & res
    count.inc
  res

# =============================================================================
# HUD Rendering
# =============================================================================

proc renderHudStrip*(area: Rect, buf: var CellBuffer, data: HudData) =
  ## Render the HUD strip with double-line borders
  ##
  ## The HUD uses 2 rows:
  ## - Row 0: Top border (═══)
  ## - Row 1: Content with side borders (║ ... ║)
  ## - Row 2: Bottom border (═══) -- only if height >= 3
  
  if area.height < 2 or area.width < 20:
    return
  
  let hudBorder = hudBorderStyle()
  let hudBase = hudStyle()
  let hudBold = hudBoldStyle()
  let hudDim = hudDimStyle()
  let hudAlert = hudAlertStyle()
  let hudPrest = hudPrestigeStyle()
  
  # Fill background
  for y in area.y ..< area.bottom:
    for x in area.x ..< area.right:
      discard buf.put(x, y, " ", hudBase)
  
  # Draw double-line borders
  # Top border
  discard buf.put(area.x, area.y, "╔", hudBorder)
  for x in area.x + 1 ..< area.right - 1:
    discard buf.put(x, area.y, "═", hudBorder)
  discard buf.put(area.right - 1, area.y, "╗", hudBorder)
  
  # Bottom border (if we have 3+ rows)
  if area.height >= 3:
    let bottomY = area.y + 2
    discard buf.put(area.x, bottomY, "╚", hudBorder)
    for x in area.x + 1 ..< area.right - 1:
      discard buf.put(x, bottomY, "═", hudBorder)
    discard buf.put(area.right - 1, bottomY, "╝", hudBorder)
  
  # Side borders on content row
  let contentY = area.y + 1
  discard buf.put(area.x, contentY, "║", hudBorder)
  discard buf.put(area.right - 1, contentY, "║", hudBorder)
  
  # Content area bounds
  let contentStart = area.x + 2
  let contentEnd = area.right - 2
  let contentWidth = contentEnd - contentStart
  
  if contentWidth < 10:
    return
  
  var x = contentStart
  
  # === LEFT SECTION: Empire + Turn ===
  # "EMPIRE: House Valerian  ▸ Turn 42"
  
  discard buf.setString(x, contentY, "EMPIRE: ", hudDim)
  x += 8
  
  let nameLen = min(data.houseName.len, 20)
  discard buf.setString(x, contentY, data.houseName[0 ..< nameLen], hudBold)
  x += nameLen + 2
  
  discard buf.setString(x, contentY, GlyphTurnMarker & " Turn ", hudDim)
  x += 8
  
  discard buf.setString(x, contentY, $data.turn, hudBold)
  x += ($data.turn).len + 3
  
  # === CENTER-LEFT: Prestige ===
  # "★ 487 (2nd)"
  
  if x < contentEnd - 40:
    discard buf.setString(x, contentY, GlyphPrestige & " ", hudPrest)
    x += 2
    
    discard buf.setString(x, contentY, formatNumber(data.prestige), hudPrest)
    x += formatNumber(data.prestige).len
    
    if data.prestigeRank > 0:
      let rankStr = " (" & formatRank(data.prestigeRank) & ")"
      discard buf.setString(x, contentY, rankStr, hudDim)
      x += rankStr.len
    
    x += 3
  
  # === CENTER: Treasury + Production ===
  # "PP: 1,820    PROD: 640"
  
  if x < contentEnd - 30:
    discard buf.setString(x, contentY, "PP: ", hudDim)
    x += 4
    discard buf.setString(x, contentY, formatNumber(data.treasury), hudBold)
    x += formatNumber(data.treasury).len + 3
    
    discard buf.setString(x, contentY, "PROD: ", hudDim)
    x += 6
    discard buf.setString(x, contentY, formatNumber(data.production), hudBold)
    x += formatNumber(data.production).len + 3
  
  # === CENTER-RIGHT: Command Capacity ===
  # "C2: 82/120 ●"
  
  if x < contentEnd - 20:
    discard buf.setString(x, contentY, "C2: ", hudDim)
    x += 4
    
    let c2Str = $data.commandUsed & "/" & $data.commandMax
    discard buf.setString(x, contentY, c2Str, hudBold)
    x += c2Str.len + 1
    
    let status = data.commandStatus()
    case status
    of CommandCapacityStatus.Ok:
      discard buf.setString(x, contentY, GlyphOk, 
        CellStyle(fg: color(PositiveColor), bg: color(HudBgColor), attrs: {}))
    of CommandCapacityStatus.Strain:
      discard buf.setString(x, contentY, GlyphWarning, hudAlert)
    x += 3
  
  # === RIGHT: Alerts ===
  # "⚠ 3    ✉ 2"
  
  # Calculate right-aligned position
  var rightX = contentEnd - 1
  
  # Unread messages (rightmost)
  if data.unreadMessages > 0:
    let msgStr = GlyphUnread & " " & $data.unreadMessages
    rightX -= msgStr.len
    discard buf.setString(rightX, contentY, GlyphUnread & " ", hudDim)
    discard buf.setString(rightX + 2, contentY, $data.unreadMessages, hudBold)
    rightX -= 3
  
  # Alerts
  if data.alertCount > 0:
    let alertStr = GlyphWarning & " " & $data.alertCount
    rightX -= alertStr.len
    discard buf.setString(rightX, contentY, GlyphWarning & " ", hudAlert)
    discard buf.setString(rightX + 2, contentY, $data.alertCount, hudAlert)

# =============================================================================
# Compact HUD (80 columns)
# =============================================================================

proc renderHudStripCompact*(area: Rect, buf: var CellBuffer, data: HudData) =
  ## Render compact HUD for 80-column terminals
  ##
## Layout:
## ╔════════════════════════════════════════════════════════════════════════════╗
## ║ VALERIAN ▸ T42  ★487 (2nd)  PP:1820  PROD:640  C2:82/120●  ⚠3  ✉2        ║
## ╚════════════════════════════════════════════════════════════════════════════╝
  
  if area.height < 2 or area.width < 40:
    return
  
  let hudBorder = hudBorderStyle()
  let hudBase = hudStyle()
  let hudBold = hudBoldStyle()
  let hudDim = hudDimStyle()
  let hudAlert = hudAlertStyle()
  let hudPrest = hudPrestigeStyle()
  
  # Fill background
  for y in area.y ..< area.bottom:
    for x in area.x ..< area.right:
      discard buf.put(x, y, " ", hudBase)
  
  # Draw borders (same as full HUD)
  discard buf.put(area.x, area.y, "╔", hudBorder)
  for x in area.x + 1 ..< area.right - 1:
    discard buf.put(x, area.y, "═", hudBorder)
  discard buf.put(area.right - 1, area.y, "╗", hudBorder)
  
  if area.height >= 3:
    let bottomY = area.y + 2
    discard buf.put(area.x, bottomY, "╚", hudBorder)
    for x in area.x + 1 ..< area.right - 1:
      discard buf.put(x, bottomY, "═", hudBorder)
    discard buf.put(area.right - 1, bottomY, "╝", hudBorder)
  
  let contentY = area.y + 1
  discard buf.put(area.x, contentY, "║", hudBorder)
  discard buf.put(area.right - 1, contentY, "║", hudBorder)
  
  let contentStart = area.x + 2
  let contentEnd = area.right - 2
  
  var x = contentStart
  
  # Compact: Just house name (truncated)
  let nameLen = min(data.houseName.len, 12)
  let nameUpper = data.houseName[0 ..< nameLen].toUpperAscii()
  discard buf.setString(x, contentY, nameUpper, hudBold)
  x += nameLen + 1
  
  # Turn
  discard buf.setString(x, contentY, GlyphTurnMarker & "T", hudDim)
  x += 2
  discard buf.setString(x, contentY, $data.turn, hudBold)
  x += ($data.turn).len + 2
  
  # Prestige (compact)
  discard buf.setString(x, contentY, GlyphPrestige, hudPrest)
  x += 1
  discard buf.setString(x, contentY, $data.prestige, hudPrest)
  x += ($data.prestige).len
  if data.prestigeRank > 0:
    let rankStr = "(" & formatRank(data.prestigeRank) & ")"
    discard buf.setString(x, contentY, rankStr, hudDim)
    x += rankStr.len
  x += 2
  
  # Treasury (compact)
  discard buf.setString(x, contentY, "PP:", hudDim)
  x += 3
  discard buf.setString(x, contentY, $data.treasury, hudBold)
  x += ($data.treasury).len + 2
  
  # Production (compact)
  if x < contentEnd - 20:
    discard buf.setString(x, contentY, "PROD:", hudDim)
    x += 5
    discard buf.setString(x, contentY, $data.production, hudBold)
    x += ($data.production).len + 2
  
  # C2 (compact)
  if x < contentEnd - 15:
    let c2Str = "C2:" & $data.commandUsed & "/" & $data.commandMax
    discard buf.setString(x, contentY, c2Str, hudDim)
    x += c2Str.len
    let status = data.commandStatus()
    case status
    of CommandCapacityStatus.Ok:
      discard buf.setString(x, contentY, GlyphOk,
        CellStyle(fg: color(PositiveColor), bg: color(HudBgColor), attrs: {}))
    of CommandCapacityStatus.Strain:
      discard buf.setString(x, contentY, GlyphWarning, hudAlert)
    x += 2
  
  # Alerts (right-aligned)
  var rightX = contentEnd - 1
  
  if data.unreadMessages > 0:
    let msgStr = GlyphUnread & $data.unreadMessages
    rightX -= msgStr.len
    discard buf.setString(rightX, contentY, msgStr, hudDim)
    rightX -= 2
  
  if data.alertCount > 0:
    let alertStr = GlyphWarning & $data.alertCount
    rightX -= alertStr.len
    discard buf.setString(rightX, contentY, alertStr, hudAlert)

# =============================================================================
# Adaptive HUD
# =============================================================================

proc renderHud*(area: Rect, buf: var CellBuffer, data: HudData) =
  ## Render HUD with automatic width adaptation
  if area.width >= 100:
    renderHudStrip(area, buf, data)
  else:
    renderHudStripCompact(area, buf, data)
