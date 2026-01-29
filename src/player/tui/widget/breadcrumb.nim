## Breadcrumb Widget
##
## Displays navigation path showing where the player is in the UI hierarchy.
## Players can press Esc to navigate up the breadcrumb trail.
##
## Layout:
##   Home > Planets > Bigun > Economy
##
## Reference: ec-style-layout.md Section 2 "Screen Regions"

import ../buffer
import ../layout/rect
import ../styles/ec_palette

export ec_palette

type
  BreadcrumbItem* = object
    ## A single breadcrumb segment
    label*: string
    viewKey*: int           ## View number (1-9) or 0 for sub-views
    entityId*: int          ## Entity ID if drilling down (colony ID, etc.)

  BreadcrumbData* = object
    ## Data for breadcrumb rendering
    items*: seq[BreadcrumbItem]

# =============================================================================
# Breadcrumb Construction Helpers
# =============================================================================

proc breadcrumbItem*(label: string, viewKey: int = 0, 
                     entityId: int = 0): BreadcrumbItem =
  ## Create a breadcrumb item
  BreadcrumbItem(label: label, viewKey: viewKey, entityId: entityId)

proc initBreadcrumbData*(): BreadcrumbData =
  ## Create empty breadcrumb data
  BreadcrumbData(items: @[])

proc add*(data: var BreadcrumbData, item: BreadcrumbItem) =
  ## Add a breadcrumb item
  data.items.add(item)

proc add*(data: var BreadcrumbData, label: string, viewKey: int = 0,
          entityId: int = 0) =
  ## Add a breadcrumb item by fields
  data.items.add(breadcrumbItem(label, viewKey, entityId))

proc pop*(data: var BreadcrumbData): bool =
  ## Remove the last breadcrumb item, returns false if at root
  if data.items.len > 1:
    data.items.setLen(data.items.len - 1)
    return true
  return false

proc current*(data: BreadcrumbData): BreadcrumbItem =
  ## Get the current (last) breadcrumb item
  if data.items.len > 0:
    return data.items[^1]
  return breadcrumbItem("Home", 1)

proc depth*(data: BreadcrumbData): int =
  ## Get breadcrumb depth
  data.items.len

# =============================================================================
# Standard Breadcrumbs for Each View
# =============================================================================

proc overviewBreadcrumb*(): BreadcrumbData =
  ## Breadcrumb for Overview (View 1)
  result = initBreadcrumbData()
  result.add("Home", 1)

proc planetsBreadcrumb*(): BreadcrumbData =
  ## Breadcrumb for Colony list (View 2)
  result = initBreadcrumbData()
  result.add("Home", 1)
  result.add("Colony", 2)

proc planetDetailBreadcrumb*(colonyName: string, colonyId: int): BreadcrumbData =
  ## Breadcrumb for Planet detail view
  result = initBreadcrumbData()
  result.add("Home", 1)
  result.add("Colony", 2)
  result.add(colonyName, 0, colonyId)

proc planetTabBreadcrumb*(colonyName: string, colonyId: int, 
                          tabName: string): BreadcrumbData =
  ## Breadcrumb for Planet detail tab (Economy, Construction, etc.)
  result = initBreadcrumbData()
  result.add("Home", 1)
  result.add("Colony", 2)
  result.add(colonyName, 0, colonyId)
  result.add(tabName, 0)

proc fleetsBreadcrumb*(): BreadcrumbData =
  ## Breadcrumb for Fleets list (View 3)
  result = initBreadcrumbData()
  result.add("Home", 1)
  result.add("Fleets", 3)

proc fleetDetailBreadcrumb*(fleetName: string, fleetId: int): BreadcrumbData =
  ## Breadcrumb for Fleet detail view
  result = initBreadcrumbData()
  result.add("Home", 1)
  result.add("Fleets", 3)
  result.add(fleetName, 0, fleetId)

proc researchBreadcrumb*(): BreadcrumbData =
  ## Breadcrumb for Tech (View 4)
  result = initBreadcrumbData()
  result.add("Home", 1)
  result.add("Tech", 4)

proc espionageBreadcrumb*(): BreadcrumbData =
  ## Breadcrumb for Espionage (View 5)
  result = initBreadcrumbData()
  result.add("Home", 1)
  result.add("Espionage", 5)

proc economyBreadcrumb*(): BreadcrumbData =
  ## Breadcrumb for General (View 6)
  result = initBreadcrumbData()
  result.add("Home", 1)
  result.add("General", 6)

proc reportsBreadcrumb*(): BreadcrumbData =
  ## Breadcrumb for Reports (View 7)
  result = initBreadcrumbData()
  result.add("Home", 1)
  result.add("Reports", 7)

proc messagesBreadcrumb*(): BreadcrumbData =
  ## Breadcrumb for Intel DB (View 8)
  result = initBreadcrumbData()
  result.add("Home", 1)
  result.add("Intel DB", 8)

proc settingsBreadcrumb*(): BreadcrumbData =
  ## Breadcrumb for Settings (View 9)
  result = initBreadcrumbData()
  result.add("Home", 1)
  result.add("Settings", 9)

# =============================================================================
# Breadcrumb Rendering
# =============================================================================

proc renderBreadcrumb*(area: Rect, buf: var CellBuffer, data: BreadcrumbData) =
  ## Render the breadcrumb line
  ##
  ## Format: " Home > Planets > Bigun > Economy"
  ##         inactive  >  inactive  >  active
  
  if area.height < 1 or area.width < 10:
    return
  
  let y = area.y
  var x = area.x + 1  # 1-char left margin
  
  let inactiveStyle = breadcrumbStyle()
  let activeStyle = breadcrumbActiveStyle()
  let sepStyle = breadcrumbSeparatorStyle()
  
  for i, item in data.items:
    # Check if we have room for this item
    let isLast = (i == data.items.len - 1)
    let neededWidth = item.label.len + (if isLast: 0 else: 3)  # " > "
    
    if x + neededWidth > area.right - 1:
      # Truncate with ellipsis if not enough room
      if x < area.right - 3:
        discard buf.setString(x, y, "...", inactiveStyle)
      break
    
    # Render the item label
    let style = if isLast: activeStyle else: inactiveStyle
    discard buf.setString(x, y, item.label, style)
    x += item.label.len
    
    # Render separator (except for last item)
    if not isLast:
      discard buf.setString(x, y, " " & GlyphBreadcrumbSep & " ", sepStyle)
      x += 3

proc renderBreadcrumbWithBackground*(area: Rect, buf: var CellBuffer, 
                                      data: BreadcrumbData) =
  ## Render breadcrumb with subtle background
  ## (For when breadcrumb line needs visual separation)
  
  if area.height < 1:
    return
  
  # Fill with subtle background
  let bgStyle = CellStyle(
    fg: color(CanvasDimColor),
    bg: color(CanvasBgColor),
    attrs: {}
  )
  
  for x in area.x ..< area.right:
    discard buf.put(x, area.y, " ", bgStyle)
  
  # Now render the breadcrumb items with adjusted styles
  let y = area.y
  var x = area.x + 1
  
  let inactiveStyle = CellStyle(
    fg: color(BreadcrumbFgColor),
    bg: color(CanvasBgColor),
    attrs: {}
  )
  let activeStyle = CellStyle(
    fg: color(BreadcrumbActiveColor),
    bg: color(CanvasBgColor),
    attrs: {}
  )
  let sepStyle = CellStyle(
    fg: color(BreadcrumbSeparatorColor),
    bg: color(CanvasBgColor),
    attrs: {}
  )
  
  for i, item in data.items:
    let isLast = (i == data.items.len - 1)
    let neededWidth = item.label.len + (if isLast: 0 else: 3)
    
    if x + neededWidth > area.right - 1:
      if x < area.right - 3:
        discard buf.setString(x, y, "...", inactiveStyle)
      break
    
    let style = if isLast: activeStyle else: inactiveStyle
    discard buf.setString(x, y, item.label, style)
    x += item.label.len
    
    if not isLast:
      discard buf.setString(x, y, " " & GlyphBreadcrumbSep & " ", sepStyle)
      x += 3
