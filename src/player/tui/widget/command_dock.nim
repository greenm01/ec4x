## Command Dock Widget
##
## The Command Dock is the bottom action bar showing:
## - Primary row: View shortcuts [1-9] and [Q]uit
## - Context row: Dynamic actions based on current view
## - Expert mode indicator (: prompt when active)
##
## Layout (120 columns):
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## [1]Ovrvw [2]Planets [3]Fleets [4]Research [5]Espionage [6]Economy [7]Reports...
## [M] Move  [P] Patrol  [H] Hold  [G] Guard                        [: ] Expert
##
## Reference: ec-style-layout.md Section 2 "Screen Regions"

import ../buffer
import ../layout/rect
import ../styles/ec_palette

export ec_palette

type
  ViewTab* = object
    ## A view tab in the command dock
    key*: char              ## Hotkey (1-9, Q)
    label*: string          ## Short label
    isActive*: bool         ## Currently active view
  
  ContextAction* = object
    ## A context-sensitive action
    key*: string            ## Hotkey letter(s)
    label*: string          ## Action description
    enabled*: bool          ## Whether action is available
  
  CommandDockData* = object
    ## Data for command dock rendering
    views*: seq[ViewTab]              ## Primary view tabs
    contextActions*: seq[ContextAction]  ## Context-specific actions
    expertModeActive*: bool           ## Expert mode (: prompt) active
    expertModeInput*: string          ## Current expert mode input
    showQuit*: bool                   ## Show quit option
    feedback*: string                 ## Status/feedback text

# =============================================================================
# Command Dock Data Construction
# =============================================================================

proc initCommandDockData*(): CommandDockData =
  ## Create command dock with default views
  result = CommandDockData(
    views: @[],
    contextActions: @[],
    expertModeActive: false,
    expertModeInput: "",
    showQuit: true,
    feedback: ""
  )

proc addView*(data: var CommandDockData, key: char, label: string, 
              isActive: bool = false) =
  ## Add a view tab
  data.views.add(ViewTab(key: key, label: label, isActive: isActive))

proc addContextAction*(data: var CommandDockData, key, label: string,
                       enabled: bool = true) =
  ## Add a context action
  data.contextActions.add(ContextAction(
    key: key,
    label: label,
    enabled: enabled
  ))

proc clearContextActions*(data: var CommandDockData) =
  ## Clear all context actions
  data.contextActions.setLen(0)

proc setActiveView*(data: var CommandDockData, viewKey: char) =
  ## Set the active view by key
  for i in 0 ..< data.views.len:
    data.views[i].isActive = (data.views[i].key == viewKey)

# =============================================================================
# Standard Command Dock Configurations
# =============================================================================

proc standardViews*(): seq[ViewTab] =
  ## Get the standard 9 views + Quit
  @[
    ViewTab(key: '1', label: "Ovrvw", isActive: false),
    ViewTab(key: '2', label: "Planets", isActive: false),
    ViewTab(key: '3', label: "Fleets", isActive: false),
    ViewTab(key: '4', label: "Research", isActive: false),
    ViewTab(key: '5', label: "Espionage", isActive: false),
    ViewTab(key: '6', label: "Economy", isActive: false),
    ViewTab(key: '7', label: "Reports", isActive: false),
    ViewTab(key: '8', label: "Msgs", isActive: false),
    ViewTab(key: '9', label: "Settings", isActive: false),
  ]

proc overviewContextActions*(joinActive: bool): seq[ContextAction] =
  ## Context actions for Overview (View 1)
  if joinActive:
    @[
      ContextAction(key: "Tab", label: "Next pane", enabled: true),
      ContextAction(key: "Shift-Tab", label: "Prev pane", enabled: true),
      ContextAction(key: "Y", label: "Edit pubkey", enabled: true),
      ContextAction(key: "U", label: "Edit name", enabled: true),
      ContextAction(key: "G", label: "Session key", enabled: true),
      ContextAction(key: "R", label: "Refresh join list", enabled: true),
      ContextAction(key: "Enter", label: "Select", enabled: true),
    ]
  else:
    @[
      ContextAction(key: "L", label: "Diplomatic matrix", enabled: true),
      ContextAction(key: "2,3,7", label: "Jump to action", enabled: true),
    ]

proc planetsContextActions*(hasSelection: bool): seq[ContextAction] =
  ## Context actions for Planets list (View 2)
  @[
    ContextAction(key: "Enter", label: "View Colony", enabled: hasSelection),
    ContextAction(key: "B", label: "Build", enabled: hasSelection),
    ContextAction(key: "S", label: "Sort", enabled: true),
    ContextAction(key: "F", label: "Filter", enabled: true),
  ]

proc planetDetailContextActions*(): seq[ContextAction] =
  ## Context actions for Planet detail view
  @[
    ContextAction(key: "Tab", label: "Next section", enabled: true),
    ContextAction(key: "1-5", label: "Switch tab", enabled: true),
    ContextAction(key: "B", label: "Build", enabled: true),
    ContextAction(key: "G", label: "Garrison", enabled: true),
    ContextAction(key: "Bksp", label: "Back", enabled: true),
  ]

proc fleetsContextActions*(hasSelection: bool, 
                           multiSelect: int): seq[ContextAction] =
  ## Context actions for Fleets (View 3)
  if multiSelect > 1:
    # Batch operations
    @[
      ContextAction(key: "M", label: "Move all", enabled: true),
      ContextAction(key: "J", label: "Join into one", enabled: true),
      ContextAction(key: "V", label: "Rendezvous at...", enabled: true),
    ]
  else:
    @[
      ContextAction(key: "X", label: "Toggle select", enabled: hasSelection),
      ContextAction(
      key: "Enter",
      label: "Fleet Details",
      enabled: hasSelection
    ),
      ContextAction(key: "S", label: "Sort", enabled: true),
      ContextAction(key: "F", label: "Filter", enabled: true),
    ]

proc fleetDetailContextActions*(): seq[ContextAction] =
  ## Context actions for Fleet detail view
  @[
    ContextAction(key: "M", label: "Move", enabled: true),
    ContextAction(key: "P", label: "Patrol", enabled: true),
    ContextAction(key: "H", label: "Hold", enabled: true),
    ContextAction(key: "G", label: "Guard", enabled: true),
    ContextAction(key: "R", label: "ROE", enabled: true),
    ContextAction(key: "J", label: "Join", enabled: true),
    ContextAction(key: "D", label: "Detach ships", enabled: true),
    ContextAction(key: "Bksp", label: "Back", enabled: true),
  ]

proc researchContextActions*(): seq[ContextAction] =
  ## Context actions for Research (View 4)
  @[
    ContextAction(key: "E/S/T", label: "Adjust pools", enabled: true),
    ContextAction(key: "Enter", label: "Confirm allocation", enabled: true),
    ContextAction(key: "?", label: "Tech tree details", enabled: true),
  ]

proc espionageContextActions*(hasSelection: bool): seq[ContextAction] =
  ## Context actions for Espionage (View 5)
  @[
    ContextAction(
      key: "Enter",
      label: "Queue operation",
      enabled: hasSelection
    ),
    ContextAction(
      key: "T",
      label: "Select target",
      enabled: hasSelection
    ),
    ContextAction(key: "B", label: "Buy EBP", enabled: true),
    ContextAction(key: "C", label: "Buy CIP", enabled: true),
  ]

proc economyContextActions*(): seq[ContextAction] =
  ## Context actions for Economy (View 6)
  @[
    ContextAction(key: "Left/Right", label: "Adjust tax", enabled: true),
    ContextAction(key: "Enter", label: "Confirm", enabled: true),
    ContextAction(key: "I", label: "Industrial investment", enabled: true),
    ContextAction(key: "G", label: "Guild transfer", enabled: true),
  ]

proc reportsContextActions*(hasSelection: bool): seq[ContextAction] =
  ## Context actions for Reports (View 7)
  @[
    ContextAction(
      key: "Enter",
      label: "Open detail",
      enabled: hasSelection
    ),
    ContextAction(key: "Tab", label: "Focus pane", enabled: true),
    ContextAction(key: "←/→", label: "Switch pane", enabled: true),
    ContextAction(key: "D", label: "Delete", enabled: hasSelection),
    ContextAction(key: "A", label: "Archive", enabled: hasSelection),
    ContextAction(key: "M", label: "Mark read/unread", enabled: hasSelection),
  ]

proc messagesContextActions*(hasSelection: bool): seq[ContextAction] =
  ## Context actions for Messages (View 8)
  @[
    ContextAction(key: "L", label: "Diplomatic matrix", enabled: true),
    ContextAction(key: "C", label: "Compose", enabled: true),
    ContextAction(key: "P", label: "Propose", enabled: hasSelection),
    ContextAction(key: "A", label: "Accept", enabled: hasSelection),
  ]

proc settingsContextActions*(): seq[ContextAction] =
  ## Context actions for Settings (View 9)
  @[
    ContextAction(key: "Space", label: "Toggle", enabled: true),
    ContextAction(key: "Enter", label: "Change value", enabled: true),
    ContextAction(key: "R", label: "Reset to defaults", enabled: true),
    ContextAction(key: "Bksp", label: "Back", enabled: true),
  ]

proc orderEntryContextActions*(cmdType: int): seq[ContextAction] =
  ## Context actions for order entry target selection mode
  ## cmdType: 1=Move, 3=Patrol, etc.
  let cmdLabel = case cmdType
    of 1: "Move"
    of 3: "Patrol"
    else: "Order"
  @[
    ContextAction(key: "Arrows", label: "Navigate map", enabled: true),
    ContextAction(key: "Enter", label: "Confirm " & cmdLabel, enabled: true),
    ContextAction(key: "Esc", label: "Cancel", enabled: true),
    ContextAction(key: "H", label: "Home system", enabled: true),
  ]

# =============================================================================
# Command Dock Rendering
# =============================================================================

proc renderSeparatorLine*(area: Rect, buf: var CellBuffer) =
  ## Render the separator line above the dock
  let style = CellStyle(fg: color(DockSeparatorColor), attrs: {})
  for x in area.x ..< area.right:
    discard buf.put(x, area.y, "━", style)

proc renderViewTabs*(area: Rect, buf: var CellBuffer, views: seq[ViewTab],
                     showQuit: bool) =
  ## Render the view tabs row
  let y = area.y
  var x = area.x + 1
  
  let dimStyle = dockDimStyle()
  let keyStyle = dockKeyStyle()
  let normalStyle = dockStyle()
  let activeStyle = selectedStyle()
  
  for view in views:
    if x + view.label.len + 4 > area.right - 10:
      # Not enough room, show ellipsis
      discard buf.setString(x, y, "...", dimStyle)
      break
    
    # [N] Label format
    discard buf.setString(x, y, "[", dimStyle)
    x += 1
    
    if view.isActive:
      discard buf.setString(x, y, $view.key, activeStyle)
    else:
      discard buf.setString(x, y, $view.key, keyStyle)
    x += 1
    
    discard buf.setString(x, y, "]", dimStyle)
    x += 1
    
    if view.isActive:
      discard buf.setString(x, y, view.label, activeStyle)
    else:
      discard buf.setString(x, y, view.label, normalStyle)
    x += view.label.len + 1
  
  # [Q]uit at the end (right-aligned)
  if showQuit:
    let quitStr = "[Q]Quit"
    let quitX = area.right - quitStr.len - 1
    if quitX > x + 2:
      discard buf.setString(quitX, y, "[", dimStyle)
      discard buf.setString(quitX + 1, y, "Q", keyStyle)
      discard buf.setString(quitX + 2, y, "]", dimStyle)
      discard buf.setString(quitX + 3, y, "Quit", normalStyle)

proc renderContextActions*(area: Rect, buf: var CellBuffer, 
                           actions: seq[ContextAction]) =
  ## Render the context actions row
  let y = area.y
  var x = area.x + 1
  
  let dimStyle = dockDimStyle()
  let keyStyle = dockKeyStyle()
  let normalStyle = dockStyle()
  let disabledStyle = CellStyle(
    fg: color(DisabledColor),
    bg: color(DockBgColor),
    attrs: {}
  )
  
  for action in actions:
    # Check if we have room
    let neededWidth = action.key.len + action.label.len + 4  # [K] Label + space
    if x + neededWidth > area.right - 15:
      break
    
    # [K] Label format
    discard buf.setString(x, y, "[", dimStyle)
    x += 1
    
    if action.enabled:
      discard buf.setString(x, y, action.key, keyStyle)
    else:
      discard buf.setString(x, y, action.key, disabledStyle)
    x += action.key.len
    
    discard buf.setString(x, y, "] ", dimStyle)
    x += 2
    
    if action.enabled:
      discard buf.setString(x, y, action.label, normalStyle)
    else:
      discard buf.setString(x, y, action.label, disabledStyle)
    x += action.label.len + 2

proc renderExpertModeIndicator*(area: Rect, buf: var CellBuffer,
                                 isActive: bool, input: string) =
  ## Render the expert mode indicator (right-aligned)
  let y = area.y
  let dimStyle = dockDimStyle()
  let keyStyle = dockKeyStyle()
  let normalStyle = dockStyle()
  
  if isActive:
    # Show ": <input>" prompt
    let promptStr = ": " & input
    let promptX = area.right - promptStr.len - 2
    discard buf.setString(promptX, y, ": ", keyStyle)
    discard buf.setString(promptX + 2, y, input, normalStyle)
    # Show cursor position
    let cursorX = promptX + 2 + input.len
    discard buf.setString(cursorX, y, "_", keyStyle)
  else:
    # Show "[: ] Expert Mode"
    let hintStr = "[: ] Expert Mode"
    let hintX = area.right - hintStr.len - 1
    discard buf.setString(hintX, y, "[", dimStyle)
    discard buf.setString(hintX + 1, y, ": ", keyStyle)
    discard buf.setString(hintX + 3, y, "]", dimStyle)
    discard buf.setString(hintX + 5, y, "Expert Mode", normalStyle)

proc renderCommandDock*(area: Rect, buf: var CellBuffer, 
                        data: CommandDockData) =
  ## Render the complete command dock (2-3 lines)
  ##
  ## Layout:
  ##   Row 0: Separator line (━━━)
  ##   Row 1: View tabs [1-9] [Q]uit
  ##   Row 2: Context actions + Expert mode indicator
  ##
  
  if area.height < 2 or area.width < 40:
    return
  
  # Fill background
  let bgStyle = dockStyle()
  for y in area.y ..< area.bottom:
    for x in area.x ..< area.right:
      discard buf.put(x, y, " ", bgStyle)
  
  # Row 0: Separator line
  renderSeparatorLine(rect(area.x, area.y, area.width, 1), buf)
  
  # Row 1: View tabs or feedback
  if area.height >= 2:
    let tabArea = rect(area.x, area.y + 1, area.width, 1)
    if data.feedback.len > 0:
      let dimStyle = dockDimStyle()
      let normalStyle = dockStyle()
      let label = "Status: "
      discard buf.setString(tabArea.x + 1, tabArea.y, label, dimStyle)
      let maxLen = tabArea.width - label.len - 3
      if maxLen > 0:
        let text = if data.feedback.len > maxLen:
                     data.feedback[0 ..< maxLen - 3] & "..."
                   else:
                     data.feedback
        discard buf.setString(tabArea.x + 1 + label.len, tabArea.y,
          text, normalStyle)
    else:
      renderViewTabs(tabArea, buf, data.views, data.showQuit)
  
  # Row 2: Context actions + Expert mode
  if area.height >= 3:
    let contextArea = rect(area.x, area.y + 2, area.width, 1)
    renderContextActions(contextArea, buf, data.contextActions)
    renderExpertModeIndicator(contextArea, buf, 
                               data.expertModeActive, data.expertModeInput)


# =============================================================================
# Compact Command Dock (80 columns)
# =============================================================================

proc renderCommandDockCompact*(area: Rect, buf: var CellBuffer,
                                data: CommandDockData) =
  ## Render compact command dock for 80-column terminals
  ##
  ## Layout (2 lines):
  ##   Row 0: Separator + abbreviated view tabs
  ##   Row 1: Key context actions + Expert mode
  ##
  
  if area.height < 2 or area.width < 40:
    return
  
  let bgStyle = dockStyle()
  for y in area.y ..< area.bottom:
    for x in area.x ..< area.right:
      discard buf.put(x, y, " ", bgStyle)
  
  # Row 0: Separator + abbreviated tabs
  renderSeparatorLine(rect(area.x, area.y, area.width, 1), buf)
  
  # In compact mode, show tabs on separator line after a few chars
  var x = area.x + 2
  let y0 = area.y
  let dimStyle = dockDimStyle()
  let keyStyle = dockKeyStyle()
  
  if data.feedback.len > 0:
    let label = "Status: "
    discard buf.setString(x, y0, label, dimStyle)
    let maxLen = area.width - label.len - 6
    if maxLen > 0:
      let text = if data.feedback.len > maxLen:
                   data.feedback[0 ..< maxLen - 3] & "..."
                 else:
                   data.feedback
      discard buf.setString(x + label.len, y0, text, dockStyle())
  else:
    for view in data.views:
      if x + 4 > area.right - 8:
        break
      discard buf.setString(x, y0, "[", dimStyle)
      if view.isActive:
        discard buf.setString(x + 1, y0, $view.key, selectedStyle())
      else:
        discard buf.setString(x + 1, y0, $view.key, keyStyle)
      discard buf.setString(x + 2, y0, "]", dimStyle)
      x += 3
    
    # [Q] at end of row 0
    if data.showQuit:
      let quitX = area.right - 4
      discard buf.setString(quitX, y0, "[", dimStyle)
      discard buf.setString(quitX + 1, y0, "Q", keyStyle)
      discard buf.setString(quitX + 2, y0, "]", dimStyle)
  
  # Row 1: Context actions
  if area.height >= 2:
    let contextArea = rect(area.x, area.y + 1, area.width, 1)
    # Render fewer actions in compact mode
    let limitedActions = if data.contextActions.len > 4: 
                           data.contextActions[0 ..< 4] 
                         else: 
                           data.contextActions
    renderContextActions(contextArea, buf, limitedActions)
    renderExpertModeIndicator(contextArea, buf,
                               data.expertModeActive, data.expertModeInput)

