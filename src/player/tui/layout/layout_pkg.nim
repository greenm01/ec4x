## Layout package - Constraint-based terminal layout system
##
## This module re-exports all layout functionality.
##
## USAGE:
## ------
##   import player/tui/layout/layout_pkg
##
##   let term = rect(80, 24)  # 80x24 terminal
##
##   # Split into header, content, footer
##   let areas = vertical()
##     .constraints(length(1), fill(), length(3))
##     .split(term)
##
##   # Further split content area
##   let content = horizontal()
##     .constraints(percentage(30), fill())
##     .margin(1)
##     .split(areas[1])
##
## COMPONENTS:
## -----------
## - rect.nim      - Rect type and operations
## - constraint.nim - Constraint types (Length, Min, Max, Percentage, etc.)
## - layout.nim    - Layout solver
##
## FUTURE CASSOWARY INTEGRATION:
## -----------------------------
## See individual module docs for migration notes.
## The public API will remain stable; only the solver implementation
## would change when migrating to amoeba/Cassowary.

import ./rect
import ./constraint
import ./layout

export rect
export constraint
export layout
