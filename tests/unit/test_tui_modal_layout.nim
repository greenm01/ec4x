## Unit tests for modal layout constraints.

import std/unittest

import ../../src/player/tui/widget/modal
import ../../src/player/tui/layout/rect

suite "TUI modal layout":
  test "height-only calculateArea stays within viewport":
    let viewport = rect(0, 0, 52, 14)
    let m = newModal()
      .minWidth(84)
      .maxWidth(84)
      .minHeight(24)

    let area = m.calculateArea(viewport, 20)
    check area.width <= viewport.width
    check area.height <= viewport.height
    check area.x >= viewport.x
    check area.y >= viewport.y
    check area.x + area.width <= viewport.x + viewport.width
    check area.y + area.height <= viewport.y + viewport.height

  test "content-aware calculateArea stays within viewport":
    let viewport = rect(0, 0, 48, 12)
    let m = newModal()
      .minWidth(84)
      .maxWidth(96)
      .minHeight(24)

    let area = m.calculateArea(viewport, 120, 30)
    check area.width <= viewport.width
    check area.height <= viewport.height
    check area.x >= viewport.x
    check area.y >= viewport.y
    check area.x + area.width <= viewport.x + viewport.width
    check area.y + area.height <= viewport.y + viewport.height
