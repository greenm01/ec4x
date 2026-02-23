## Leaderboard Widget
##
## Displays houses ranked by prestige with diplomatic status indicators.
##
## Layout:
## ┌───────────────────────────────────────┐
## │ LEADERBOARD                           │
## ├───────────────────────────────────────┤
## │  #  HOUSE       ★PRESTIGE  COLONIES   │
## │  1. Valerian       487       12       │
## │  2. Stratos        412        9       │
## │  ...                                  │
## └───────────────────────────────────────┘
##
## Reference: ec-style-layout.md Section 5.1

import std/[strformat, strutils, algorithm]
import ../buffer
import ../layout/rect
import ../styles/ec_palette
import ./borders
import ./frame

export ec_palette

type
  DiplomaticStatus* {.pure.} = enum
    ## Diplomatic status between houses
    Self       ## Your house
    Neutral    ## Neutral relations
    Hostile    ## Hostile relations
    Enemy      ## At war
    Eliminated ## House eliminated

  HouseEntry* = object
    ## A house entry in the leaderboard
    rank*: int                    ## Position (1st, 2nd, etc.)
    houseId*: int                 ## House ID for stable sorting
    houseName*: string            ## House name
    prestige*: int                ## Prestige score
    colonyCount*: int             ## Number of colonies
    diplomaticStatus*: DiplomaticStatus  ## Status with viewing house
    isPlayer*: bool               ## Is this the player's house

  LeaderboardData* = object
    ## Data for leaderboard rendering
    entries*: seq[HouseEntry]
    totalSystems*: int            ## Total systems in galaxy
    colonizedSystems*: int        ## Systems with colonies

# =============================================================================
# Leaderboard Construction
# =============================================================================

proc initLeaderboardData*(): LeaderboardData =
  ## Create empty leaderboard
  LeaderboardData(
    entries: @[],
    totalSystems: 0,
    colonizedSystems: 0
  )

proc addEntry*(data: var LeaderboardData, houseId: int, name: string, 
               prestige: int, colonies: int, status: DiplomaticStatus, 
               isPlayer: bool = false) =
  ## Add a house entry to the leaderboard
  data.entries.add(HouseEntry(
    rank: 0,  # Will be assigned after sorting
    houseId: houseId,
    houseName: name,
    prestige: prestige,
    colonyCount: colonies,
    diplomaticStatus: status,
    isPlayer: isPlayer
  ))

proc sortAndRank*(data: var LeaderboardData) =
  ## Sort entries by prestige (descending) and assign ranks.
  ## Ties share rank by prestige; player is shown first within tie groups.
  data.entries.sort(proc(a, b: HouseEntry): int =
    # Primary ordering: prestige, then colonies.
    if a.prestige != b.prestige:
      return b.prestige - a.prestige
    if a.colonyCount != b.colonyCount:
      return b.colonyCount - a.colonyCount
    # Keep viewer visible at top when everything else is tied.
    if a.isPlayer != b.isPlayer:
      return (if a.isPlayer: -1 else: 1)
    return a.houseId - b.houseId
  )

  # Assign ranks by prestige only (competition ranking: 1,1,3...)
  for i in 0 ..< data.entries.len:
    if i == 0:
      data.entries[i].rank = 1
    elif data.entries[i].prestige == data.entries[i - 1].prestige:
      data.entries[i].rank = data.entries[i - 1].rank
    else:
      data.entries[i].rank = i + 1

# =============================================================================
# Diplomatic Status Display
# =============================================================================

proc statusGlyph*(status: DiplomaticStatus): string =
  ## Get the glyph for diplomatic status
  case status
  of DiplomaticStatus.Self: ""
  of DiplomaticStatus.Neutral: GlyphOk
  of DiplomaticStatus.Hostile: GlyphWarning
  of DiplomaticStatus.Enemy: GlyphEnemy
  of DiplomaticStatus.Eliminated: GlyphEliminated

proc statusLabel*(status: DiplomaticStatus): string =
  ## Get the label for diplomatic status
  case status
  of DiplomaticStatus.Self: "YOU"
  of DiplomaticStatus.Neutral: "NEU"
  of DiplomaticStatus.Hostile: "HOS"
  of DiplomaticStatus.Enemy: "ENM"
  of DiplomaticStatus.Eliminated: "ELIM"

proc statusFullLabel*(status: DiplomaticStatus): string =
  ## Get the full-length label for diplomatic status
  case status
  of DiplomaticStatus.Self: "You"
  of DiplomaticStatus.Neutral: "Neutral"
  of DiplomaticStatus.Hostile: "Hostile"
  of DiplomaticStatus.Enemy: "Enemy"
  of DiplomaticStatus.Eliminated: "Eliminated"

proc statusStyle*(status: DiplomaticStatus): CellStyle =
  ## Get the style for diplomatic status
  case status
  of DiplomaticStatus.Self:
    CellStyle(fg: color(PrestigeColor), attrs: {StyleAttr.Bold})
  of DiplomaticStatus.Neutral:
    CellStyle(fg: color(NeutralStatusColor), attrs: {})
  of DiplomaticStatus.Hostile:
    CellStyle(fg: color(HostileStatusColor), attrs: {})
  of DiplomaticStatus.Enemy:
    CellStyle(fg: color(EnemyStatusColor), attrs: {StyleAttr.Bold})
  of DiplomaticStatus.Eliminated:
    CellStyle(fg: color(EliminatedColor), attrs: {})

# =============================================================================
# Leaderboard Rendering
# =============================================================================

proc renderLeaderboard*(area: Rect, buf: var CellBuffer, 
                        data: LeaderboardData) =
  ## Render the leaderboard with frame
  if area.height < 3 or area.width < 20:
    return
  
  # Draw frame
  let frame = bordered()
    .title("LEADERBOARD")
    .titleStyle(panelTitleStyle())
    .borderType(BorderType.Plain)
    .borderStyle(innerBorderStyle())
  frame.render(area, buf)
  
  let inner = frame.inner(area)
  
  # Header row
  var y = inner.y
  let headerStyle = canvasHeaderStyle()
  let dimStyle = canvasDimStyle()
  
  if y < inner.bottom:
    discard buf.setString(inner.x, y, " #  HOUSE       ", headerStyle)
    discard buf.setString(inner.x + 16, y, GlyphPrestige & "PRESTIGE  ", headerStyle)
    discard buf.setString(inner.x + 27, y, "COLONIES  ", headerStyle)
    y += 1
  
  # Separator line
  if y < inner.bottom:
    for x in inner.x ..< min(inner.right, inner.x + 37):
      discard buf.put(x, y, "─", dimStyle)
    y += 1
  
  # House entries
  for entry in data.entries:
    if y >= inner.bottom:
      break
    
    let entryStyle = if entry.isPlayer: selectedStyle() else: canvasStyle()
    let prestigeStyle = if entry.isPlayer: prestigeStyle() else: canvasStyle()
    
    # Rank
    let rankStr = $entry.rank & "."
    discard buf.setString(inner.x + 1, y, rankStr.alignLeft(3), entryStyle)
    
    # House name
    let nameStr = entry.houseName[0 ..< min(entry.houseName.len, 12)]
    discard buf.setString(inner.x + 4, y, nameStr.alignLeft(12), entryStyle)
    
    # Prestige
    if entry.diplomaticStatus == DiplomaticStatus.Eliminated:
      discard buf.setString(inner.x + 16, y, "ELIM".alignLeft(10), 
                           statusStyle(entry.diplomaticStatus))
    else:
      discard buf.setString(inner.x + 16, y, $entry.prestige, prestigeStyle)
    
    # Colony count
    let colStr = if entry.diplomaticStatus == DiplomaticStatus.Eliminated:
                   "0"
                 else:
                   $entry.colonyCount
    discard buf.setString(inner.x + 27, y, colStr.alignLeft(10), entryStyle)

    y += 1
  
  # Footer with map progress
  y = inner.bottom - 2
  if y > inner.y and data.totalSystems > 0:
    discard buf.setString(inner.x, y, "─" .repeat(min(37, inner.width)), dimStyle)
    y += 1
    
    let progressStr = &"Map: {data.colonizedSystems}/{data.totalSystems} systems colonized"
    discard buf.setString(inner.x + 1, y, progressStr, dimStyle)

proc renderLeaderboardCompact*(area: Rect, buf: var CellBuffer,
                                data: LeaderboardData, maxLines: int = 6) =
  ## Render compact leaderboard without frame (for inclusion in larger layout)
  if area.height < 2 or area.width < 30:
    return
  
  var y = area.y
  let headerStyle = canvasHeaderStyle()
  
  # Header
  discard buf.setString(area.x, y, "LEADERBOARD", headerStyle)
  y += 1
  
  # Entries (limited)
  let entriesToShow = min(maxLines, data.entries.len)
  for i in 0 ..< entriesToShow:
    if y >= area.bottom:
      break
    
    let entry = data.entries[i]
    let entryStyle = if entry.isPlayer: selectedStyle() else: canvasStyle()
    
    # Compact format: "1. Valerian ★487 (12) YOU"
    var line = $entry.rank & ". " & entry.houseName
    
    if entry.diplomaticStatus == DiplomaticStatus.Eliminated:
      line.add(" ELIM")
    else:
      line.add(" " & GlyphPrestige & $entry.prestige)
      line.add(" (" & $entry.colonyCount & ")")
    
    let statusText = " " & statusLabel(entry.diplomaticStatus)
    
    discard buf.setString(area.x, y, line[0 ..< min(line.len, area.width - 8)], 
                         entryStyle)
    
    if line.len + statusText.len <= area.width:
      let statusStyle = statusStyle(entry.diplomaticStatus)
      discard buf.setString(area.x + line.len, y, statusText, statusStyle)
    
    y += 1
