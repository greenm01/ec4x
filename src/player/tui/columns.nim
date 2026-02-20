## Table Column Definitions
##
## Single source of truth for all table column layouts in the TUI.
## Each proc returns a sequence of TableColumn definitions that can be
## used to build tables and calculate widths.

import ./widget/table

export table

# =============================================================================
# Colony / Planets View
# =============================================================================

proc planetsColumns*(): seq[TableColumn] =
  ## Column definitions for planets/colony table
  @[
    tableColumn("System", 6, table.Alignment.Center),
    tableColumn("Colony Name", 0, table.Alignment.Left, 12),
    tableColumn("Status", 7, table.Alignment.Left),
    tableColumn("Queue", 5, table.Alignment.Right),
    tableColumn("Class", 5, table.Alignment.Center),
    tableColumn("Resource", 8, table.Alignment.Center),
    tableColumn("Population", 8, table.Alignment.Right),
    tableColumn("Industry", 8, table.Alignment.Right),
    tableColumn("Gross", 7, table.Alignment.Right),
    tableColumn("Net", 7, table.Alignment.Right),
    tableColumn("Growth", 6, table.Alignment.Right),
    tableColumn("C-Dock", 6, table.Alignment.Right),
    tableColumn("R-Dock", 6, table.Alignment.Right),
    tableColumn("Fleets", 6, table.Alignment.Right),
    tableColumn("Starbase", 8, table.Alignment.Right),
    tableColumn("Ground", 6, table.Alignment.Right),
    tableColumn("Battery", 7, table.Alignment.Right),
    tableColumn("Shield", 6, table.Alignment.Center)
  ]

# =============================================================================
# Fleet Console - Systems Pane
# =============================================================================

proc fleetConsoleSystemsColumns*(): seq[TableColumn] =
  ## Column definitions for fleet console systems pane
  @[
    tableColumn("System", 14, table.Alignment.Left),
    tableColumn("Sect", 5, table.Alignment.Center)
  ]

# =============================================================================
# Fleet Console - Fleets Pane
# =============================================================================

proc fleetConsoleFleetsColumns*(): seq[TableColumn] =
  ## Column definitions for fleet console fleets pane
  @[
    tableColumn("!", 1, table.Alignment.Center),
    tableColumn("Flt", 3, table.Alignment.Left),
    tableColumn("Ships", 5, table.Alignment.Right),
    tableColumn("AS", 4, table.Alignment.Right),
    tableColumn("DS", 4, table.Alignment.Right),
    tableColumn("TT", 3, table.Alignment.Right),
    tableColumn("ETAC", 4, table.Alignment.Right),
    tableColumn("CMD", 6, table.Alignment.Left),
    tableColumn("TGT", 5, table.Alignment.Left),
    tableColumn("ETA", 3, table.Alignment.Right),
    tableColumn("ROE", 3, table.Alignment.Right),
    tableColumn("STS", 3, table.Alignment.Center)
  ]

# =============================================================================
# Fleet List - Full Table (ListView)
# =============================================================================

proc fleetListColumns*(): seq[TableColumn] =
  ## Column definitions for fleet list table (ListView)
  @[
    tableColumn("!", 1, table.Alignment.Center),
    tableColumn("Fleet", 5, table.Alignment.Left),
    tableColumn("Location", 14, table.Alignment.Left),
    tableColumn("Sect", 5, table.Alignment.Center),
    tableColumn("Ships", 6, table.Alignment.Right),
    tableColumn("AS", 4, table.Alignment.Right),
    tableColumn("DS", 4, table.Alignment.Right),
    tableColumn("CMD", 7, table.Alignment.Left),
    tableColumn("Target", 10, table.Alignment.Left),
    tableColumn("ETA", 4, table.Alignment.Right),
    tableColumn("ROE", 4, table.Alignment.Right),
    tableColumn("Status", 8, table.Alignment.Left)
  ]

# =============================================================================
# Intel Database
# =============================================================================

proc intelDbColumns*(): seq[TableColumn] =
  ## Column definitions for intel database table
  @[
    tableColumn("System", 6, table.Alignment.Center),
    tableColumn("Name", 14, table.Alignment.Left),
    tableColumn("Owner", 10, table.Alignment.Left),
    tableColumn("Intel", 8, table.Alignment.Left),
    tableColumn("LTU", 4, table.Alignment.Center),
    tableColumn("Notes", 0, table.Alignment.Left, 20)
  ]

# =============================================================================
# Width Calculator Helper
# =============================================================================

proc tableWidthFromColumns*(columns: seq[TableColumn],
                            maxWidth: int,
                            showBorders: bool = true): int =
  ## Calculate rendered width of a table with these columns
  ## Without needing to build the full table with data
  var t = table(columns)
  if showBorders:
    t = t.showBorders(true)
  t.renderWidth(maxWidth)
