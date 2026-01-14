## Widget - Base widget interface
##
## Defines the Widget pattern for TUI components.
##
## In Nim, we don't use formal traits like Rust. Instead, any type
## that implements `render(self, area: Rect, buf: var CellBuffer)`
## is considered a Widget through duck typing.
##
## This module provides documentation and some helper types.

import ../buffer
import ../layout/rect

# NOTE: Nim doesn't have explicit trait/interface syntax like Rust.
# A "Widget" is any type W that has:
#   proc render*(w: W, area: Rect, buf: var CellBuffer)
#
# The widget consumes self (takes ownership), matching Ratatui's pattern.
# Widgets are typically cheap to create each frame.

# For documentation purposes, we can define a concept:
type
  Widget* = concept w
    ## Any type that can render itself to a buffer within a rectangular area.
    ## 
    ## To implement Widget for your type T:
    ##   proc render*(widget: T, area: Rect, buf: var CellBuffer) =
    ##     # Render widget content to buf within area bounds
    ##
    ## Widgets consume self (not `var` or `ref`), allowing the consuming
    ## render pattern from Ratatui. Create widgets fresh each frame.
    w.render(Rect, var CellBuffer)

# For stateful widgets (like List with ListState), use a different signature:
type
  StatefulWidget*[S] = concept w
    ## Widget that requires external state to render.
    ## 
    ## State persists between frames while widget is recreated.
    ## 
    ## To implement StatefulWidget for type T with state S:
    ##   proc render*(widget: T, area: Rect, buf: var CellBuffer, 
    ##                state: var S) =
    ##     # Render using and potentially modifying state
    w.render(Rect, var CellBuffer, var S)

# Note: The concept definitions above are for documentation/type checking.
# Nim will accept any type with matching signatures without needing to
# explicitly declare it implements Widget/StatefulWidget.
