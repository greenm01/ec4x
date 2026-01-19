## Strategic Overview View (View 1)
##
## Main dashboard showing empire status, leaderboard, and action queue.
## This is the primary view players see when launching the game.
##
## Layout (120 columns):
## ┌────────────────┬─────────────────┬───────────────────┐
## │ RECENT EVENTS  │ EMPIRE STATUS   │ LEADERBOARD       │
## ├────────────────┴─────────────────┴───────────────────┤
## │ ACTION QUEUE                   │ CHECKLIST          │
## └────────────────────────────────┴────────────────────┘
##
## Reference: ec-style-layout.md Section 5.1

import ../buffer
import ../layout/layout_pkg
import ../styles/ec_palette
import ./borders
import ./frame
import ./leaderboard
import ./empire_status
import ./action_queue

export ec_palette
export leaderboard, empire_status, action_queue

type
  RecentEvent* = object
    ## A recent game event for display
    turn*: int
    description*: string
    isImportant*: bool

  OverviewData* = object
    ## Data for overview rendering
    leaderboard*: LeaderboardData
    empireStatus*: EmpireStatusData
    actionQueue*: ActionQueueData
    recentEvents*: seq[RecentEvent]

# =============================================================================
# Overview Data Construction
# =============================================================================

proc initOverviewData*(): OverviewData =
  ## Create empty overview data
  OverviewData(
    leaderboard: initLeaderboardData(),
    empireStatus: initEmpireStatusData(),
    actionQueue: initActionQueueData(),
    recentEvents: @[]
  )

proc addEvent*(data: var OverviewData, turn: int, description: string,
               isImportant: bool = false) =
  ## Add a recent event
  data.recentEvents.add(RecentEvent(
    turn: turn,
    description: description,
    isImportant: isImportant
  ))

# =============================================================================
# Recent Events Panel
# =============================================================================

proc renderRecentEvents(area: Rect, buf: var CellBuffer, 
                        events: seq[RecentEvent]) =
  ## Render recent events panel
  if area.height < 3 or area.width < 20:
    return
  
  # Draw frame
  let frame = bordered()
    .title("RECENT EVENTS")
    .borderType(BorderType.Plain)
    .borderStyle(primaryBorderStyle())
  frame.render(area, buf)
  
  let inner = frame.inner(area)
  var y = inner.y
  
  let normalStyle = canvasStyle()
  let dimStyle = canvasDimStyle()
  let importantStyle = CellStyle(fg: color(PrestigeColor), attrs: {StyleAttr.Bold})
  
  # Render events (newest first)
  let maxEvents = min(events.len, inner.height)
  for i in 0 ..< maxEvents:
    if y >= inner.bottom:
      break
    
    let event = events[i]
    let style = if event.isImportant: importantStyle else: normalStyle
    
    # Format: "[T42] Description"
    let turnStr = "[T" & $event.turn & "] "
    discard buf.setString(inner.x, y, turnStr, dimStyle)
    
    let descStart = inner.x + turnStr.len
    let maxDescLen = inner.width - turnStr.len
    let desc = if event.description.len > maxDescLen:
                 event.description[0 ..< maxDescLen - 3] & "..."
               else:
                 event.description
    
    discard buf.setString(descStart, y, desc, style)
    y += 1
  
  # Empty message
  if events.len == 0:
    discard buf.setString(inner.x, y, "No recent events", dimStyle)

# =============================================================================
# Overview Layout Rendering
# =============================================================================

proc renderOverviewCompact*(area: Rect, buf: var CellBuffer, data: OverviewData) =
  ## Render compact overview for narrow terminals (80 columns)
  ## Stacks panels vertically
  
  if area.height < 8:
    return
  
  # Vertical stacking: Leaderboard, Empire Status, Action Queue
  let sections = vertical()
    .constraints(length(10), length(12), fill())
    .spacing(1)
    .split(area)
  
  if sections.len >= 1:
    renderLeaderboardCompact(sections[0], buf, data.leaderboard, 6)
  if sections.len >= 2:
    renderEmpireStatusCompact(sections[1], buf, data.empireStatus)
  if sections.len >= 3:
    renderActionQueueCompact(sections[2], buf, data.actionQueue, 8)

proc renderOverview*(area: Rect, buf: var CellBuffer, data: OverviewData) =
  ## Render the complete Strategic Overview (View 1)
  ##
  ## Layout uses a 3-column top row and 2-column bottom row
  
  if area.height < 12 or area.width < 60:
    # Fall back to vertical stacking for small terminals
    renderOverviewCompact(area, buf, data)
    return
  
  # Split into top (3 columns) and bottom (2 columns) sections
  let topBottomSplit = vertical()
    .constraints(percentage(60), fill())
    .split(area)
  
  if topBottomSplit.len < 2:
    return
  
  let topArea = topBottomSplit[0]
  let bottomArea = topBottomSplit[1]
  
  # Top row: 3 columns (Events, Empire Status, Leaderboard)
  let topCols = horizontal()
    .constraints(percentage(30), percentage(35), fill())
    .spacing(1)
    .split(topArea)
  
  if topCols.len < 3:
    return
  
  let eventsArea = topCols[0]
  let statusArea = topCols[1]
  let leaderboardArea = topCols[2]
  
  # Bottom row: 2 columns (Action Queue, Checklist)
  let bottomCols = horizontal()
    .constraints(percentage(50), fill())
    .spacing(1)
    .split(bottomArea)
  
  if bottomCols.len < 2:
    return
  
  let actionQueueArea = bottomCols[0]
  let checklistArea = bottomCols[1]
  
  # Render panels
  renderRecentEvents(eventsArea, buf, data.recentEvents)
  renderEmpireStatus(statusArea, buf, data.empireStatus)
  renderLeaderboard(leaderboardArea, buf, data.leaderboard)
  renderActionQueue(actionQueueArea, buf, data.actionQueue)
  renderChecklist(checklistArea, buf, data.actionQueue)
