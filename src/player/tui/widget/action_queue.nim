## Action Queue / Checklist Widget
##
## Displays items requiring player attention with jump-to hotkeys.
##
## Layout:
## ┌───────────────────────────────────────────┐
## │ ACTION QUEUE                              │
## ├───────────────────────────────────────────┤
## │ ⚠ 1 Idle shipyard at Bigun      [jump 2] │
## │ ⚠ 2 Fleets without orders        [jump 3] │
## │ ✉ 1 Unread combat report         [jump 7] │
## └───────────────────────────────────────────┘
##
## ┌───────────────────────────────────────────┐
## │ CHECKLIST                                 │
## ├───────────────────────────────────────────┤
## │ ■ Shipyard A at Bigun idle                │
## │ ■ Fleet Omicron awaiting orders           │
## │ ■ Fleet Tau awaiting orders               │
## │ ■ Report: Zeta skirmish (unread)          │
## └───────────────────────────────────────────┘
##
## Reference: ec-style-layout.md Section 5.1

import ../buffer
import ../layout/rect
import ../styles/ec_palette
import ./borders
import ./frame

export ec_palette

type
  ActionPriority* {.pure.} = enum
    ## Priority level for actions
    Info      ## Informational
    Warning   ## Needs attention
    Critical  ## Urgent action needed

  ActionItem* = object
    ## An action item in the queue
    description*: string      ## What needs attention
    priority*: ActionPriority ## How urgent
    jumpView*: int            ## View to jump to (1-9) or 0 for none
    jumpLabel*: string        ## Jump button label (e.g., "C", "F", "R")

  ChecklistItem* = object
    ## A checklist item (more detailed than action items)
    description*: string
    isDone*: bool
    priority*: ActionPriority

  ActionQueueData* = object
    ## Data for action queue/checklist
    actions*: seq[ActionItem]
    checklist*: seq[ChecklistItem]

# =============================================================================
# Action Queue Construction
# =============================================================================

proc initActionQueueData*(): ActionQueueData =
  ## Create empty action queue
  ActionQueueData(
    actions: @[],
    checklist: @[]
  )

proc addAction*(data: var ActionQueueData, description: string,
                priority: ActionPriority, jumpView: int = 0,
                jumpLabel: string = "") =
  ## Add an action item
  data.actions.add(ActionItem(
    description: description,
    priority: priority,
    jumpView: jumpView,
    jumpLabel: jumpLabel
  ))

proc addChecklistItem*(data: var ActionQueueData, description: string,
                       isDone: bool = false, 
                       priority: ActionPriority = ActionPriority.Info) =
  ## Add a checklist item
  data.checklist.add(ChecklistItem(
    description: description,
    isDone: isDone,
    priority: priority
  ))

# =============================================================================
# Priority Display
# =============================================================================

proc priorityGlyph*(priority: ActionPriority): string =
  ## Get the glyph for priority level
  case priority
  of ActionPriority.Info: GlyphUnread
  of ActionPriority.Warning: GlyphWarning
  of ActionPriority.Critical: GlyphWarning  # Same glyph, different style

proc priorityStyle*(priority: ActionPriority): CellStyle =
  ## Get the style for priority level
  case priority
  of ActionPriority.Info:
    canvasDimStyle()
  of ActionPriority.Warning:
    warningStyle()
  of ActionPriority.Critical:
    alertStyle()

# =============================================================================
# Action Queue Rendering
# =============================================================================

proc renderActionQueue*(area: Rect, buf: var CellBuffer,
                        data: ActionQueueData) =
  ## Render action queue with frame
  if area.height < 3 or area.width < 30:
    return
  
  # Draw frame
  let frame = bordered()
    .title("ACTION QUEUE")
    .titleStyle(panelTitleStyle())
    .borderType(BorderType.Plain)
    .borderStyle(innerBorderStyle())
  frame.render(area, buf)
  
  let inner = frame.inner(area)
  var y = inner.y
  
  let normalStyle = canvasStyle()
  let dimStyle = canvasDimStyle()
  
  # Render action items
  for action in data.actions:
    if y >= inner.bottom:
      break
    
    let priorityGlyph = priorityGlyph(action.priority)
    let priorityStyle = priorityStyle(action.priority)
    
    # Glyph
    discard buf.setString(inner.x, y, priorityGlyph & " ", priorityStyle)
    
    # Description
    let maxDescLen = if action.jumpLabel.len > 0:
                       inner.width - 13  # Reserve space for "[jump X]"
                     else:
                       inner.width - 2
    
    let desc = if action.description.len > maxDescLen:
                 action.description[0 ..< maxDescLen - 3] & "..."
               else:
                 action.description
    
    discard buf.setString(inner.x + 2, y, desc, normalStyle)
    
    # Jump button
    if action.jumpLabel.len > 0:
      let jumpX = inner.right - 10
      let jumpStr = "[jump " & action.jumpLabel & "]"
      discard buf.setString(jumpX, y, jumpStr, dimStyle)
    
    y += 1
  
  # Empty message
  if data.actions.len == 0:
    discard buf.setString(inner.x, y, "No pending actions", dimStyle)

proc renderChecklist*(area: Rect, buf: var CellBuffer,
                      data: ActionQueueData) =
  ## Render checklist with frame
  if area.height < 3 or area.width < 30:
    return
  
  # Draw frame
  let frame = bordered()
    .title("CHECKLIST")
    .titleStyle(panelTitleStyle())
    .borderType(BorderType.Plain)
    .borderStyle(innerBorderStyle())
  frame.render(area, buf)
  
  let inner = frame.inner(area)
  var y = inner.y
  
  let normalStyle = canvasStyle()
  let dimStyle = canvasDimStyle()
  let doneStyle = CellStyle(fg: color(CanvasDimColor), attrs: {})
  
  # Render checklist items
  for item in data.checklist:
    if y >= inner.bottom:
      break
    
    # Checkbox
    let checkbox = if item.isDone: "☑" else: "■"
    let checkStyle = if item.isDone: doneStyle else: priorityStyle(item.priority)
    discard buf.setString(inner.x, y, checkbox & " ", checkStyle)
    
    # Description
    let desc = if item.description.len > inner.width - 3:
                 item.description[0 ..< inner.width - 6] & "..."
               else:
                 item.description
    
    let descStyle = if item.isDone: doneStyle else: normalStyle
    discard buf.setString(inner.x + 2, y, desc, descStyle)
    
    y += 1
  
  # Empty message
  if data.checklist.len == 0:
    discard buf.setString(inner.x, y, "All tasks complete", dimStyle)

proc renderActionQueueCompact*(area: Rect, buf: var CellBuffer,
                                data: ActionQueueData, maxItems: int = 5) =
  ## Render compact action queue (no frame, limited items)
  if area.height < 2 or area.width < 20:
    return
  
  var y = area.y
  let headerStyle = canvasHeaderStyle()
  
  # Header
  discard buf.setString(area.x, y, "ACTION QUEUE", headerStyle)
  y += 1
  
  # Items (limited)
  let itemsToShow = min(maxItems, data.actions.len)
  for i in 0 ..< itemsToShow:
    if y >= area.bottom:
      break
    
    let action = data.actions[i]
    let glyph = priorityGlyph(action.priority)
    let style = priorityStyle(action.priority)
    
    discard buf.setString(area.x, y, glyph & " " & action.description, style)
    y += 1
  
  if data.actions.len == 0:
    discard buf.setString(area.x, y, "No pending actions", canvasDimStyle())
