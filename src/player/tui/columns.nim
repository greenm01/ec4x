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
    tableColumn("System", 14, table.Alignment.Left),
    tableColumn("Sec", 4, table.Alignment.Center),
    tableColumn("Cls", 3, table.Alignment.Left),
    tableColumn("Res", 3, table.Alignment.Left),
    tableColumn("Pop", 4, table.Alignment.Right),
    tableColumn("IU", 4, table.Alignment.Right),
    tableColumn("GCO", 5, table.Alignment.Right),
    tableColumn("NCV", 5, table.Alignment.Right),
    tableColumn("Grw", 5, table.Alignment.Right),
    tableColumn("CD", 2, table.Alignment.Right),
    tableColumn("RD", 2, table.Alignment.Right),
    tableColumn("Flt", 2, table.Alignment.Right),
    tableColumn("SB", 2, table.Alignment.Right),
    tableColumn("Gnd", 2, table.Alignment.Right),
    tableColumn("Bat", 2, table.Alignment.Right),
    tableColumn("Shd", 3, table.Alignment.Center),
    tableColumn("Status", 4, table.Alignment.Left)
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
    tableColumn("Flt", 4, table.Alignment.Right),
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
    tableColumn("Flt", 5, table.Alignment.Right),
    tableColumn("Location", 14, table.Alignment.Left),
    tableColumn("Sect", 5, table.Alignment.Center),
    tableColumn("Ships", 5, table.Alignment.Right),
    tableColumn("AS", 4, table.Alignment.Right),
    tableColumn("DS", 4, table.Alignment.Right),
    tableColumn("CMD", 7, table.Alignment.Left),
    tableColumn("Dest", 10, table.Alignment.Left),
    tableColumn("ETA", 3, table.Alignment.Right),
    tableColumn("ROE", 3, table.Alignment.Right),
    tableColumn("Status", 8, table.Alignment.Left)
  ]

# =============================================================================
# Intel Database
# =============================================================================

proc intelDbColumns*(): seq[TableColumn] =
  ## Column definitions for intel database table
  @[
    tableColumn("System", 14, table.Alignment.Left),
    tableColumn("Sec", 4, table.Alignment.Center),
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
