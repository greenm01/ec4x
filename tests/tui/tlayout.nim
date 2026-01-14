## Tests for layout system
##
## Tests rect operations, constraints, and layout solving.

import std/unittest
import ../../src/player/tui/layout/layout_pkg

# -----------------------------------------------------------------------------
# Rect tests
# -----------------------------------------------------------------------------

suite "Rect":
  test "construction":
    let r1 = rect(10, 20, 30, 40)
    check r1.x == 10
    check r1.y == 20
    check r1.width == 30
    check r1.height == 40
    
    let r2 = rect(80, 24)
    check r2.x == 0
    check r2.y == 0
    check r2.width == 80
    check r2.height == 24
  
  test "properties":
    let r = rect(10, 20, 30, 40)
    check r.right == 40
    check r.bottom == 60
    check r.area == 1200
    check not r.isEmpty
    check r.isValid
    
    let empty = rect(0, 0, 0, 10)
    check empty.isEmpty
    check not empty.isValid
  
  test "contains point":
    let r = rect(10, 10, 20, 20)
    check r.contains(10, 10)  # Top-left corner
    check r.contains(29, 29)  # Bottom-right - 1
    check not r.contains(30, 30)  # Bottom-right (exclusive)
    check not r.contains(9, 15)   # Outside left
    check not r.contains(15, 9)   # Outside top
  
  test "contains rect":
    let outer = rect(0, 0, 100, 100)
    let inner = rect(10, 10, 50, 50)
    check outer.contains(inner)
    check not inner.contains(outer)
    
    let overlapping = rect(50, 50, 60, 60)
    check not outer.contains(overlapping)
  
  test "intersects":
    let a = rect(0, 0, 50, 50)
    let b = rect(25, 25, 50, 50)
    check a.intersects(b)
    check b.intersects(a)
    
    let c = rect(100, 100, 10, 10)
    check not a.intersects(c)
  
  test "offset":
    let r = rect(10, 20, 30, 40)
    let moved = r.offset(5, -10)
    check moved.x == 15
    check moved.y == 10
    check moved.width == 30
    check moved.height == 40
  
  test "resize":
    let r = rect(10, 20, 30, 40)
    let resized = r.resize(100, 200)
    check resized.x == 10
    check resized.y == 20
    check resized.width == 100
    check resized.height == 200
  
  test "shrink":
    let r = rect(10, 10, 100, 100)
    let shrunken = r.shrink(5)
    check shrunken.x == 15
    check shrunken.y == 15
    check shrunken.width == 90
    check shrunken.height == 90
    
    let custom = r.shrink(1, 2, 3, 4)
    check custom.x == 11
    check custom.y == 12
    check custom.width == 96  # 100 - 1 - 3
    check custom.height == 94  # 100 - 2 - 4
  
  test "intersection":
    let a = rect(0, 0, 50, 50)
    let b = rect(25, 25, 50, 50)
    let inter = a.intersection(b)
    check inter.x == 25
    check inter.y == 25
    check inter.width == 25
    check inter.height == 25
    
    let c = rect(100, 100, 10, 10)
    let noInter = a.intersection(c)
    check noInter.isEmpty
  
  test "union":
    let a = rect(0, 0, 50, 50)
    let b = rect(25, 25, 50, 50)
    let u = a.union(b)
    check u.x == 0
    check u.y == 0
    check u.width == 75
    check u.height == 75
  
  test "split horizontal":
    let r = rect(0, 0, 100, 50)
    let (left, right) = r.splitHorizontal(30)
    
    check left.x == 0
    check left.width == 30
    check left.height == 50
    
    check right.x == 30
    check right.width == 70
    check right.height == 50
  
  test "split vertical":
    let r = rect(0, 0, 100, 50)
    let (top, bottom) = r.splitVertical(20)
    
    check top.y == 0
    check top.width == 100
    check top.height == 20
    
    check bottom.y == 20
    check bottom.width == 100
    check bottom.height == 30

# -----------------------------------------------------------------------------
# Constraint tests
# -----------------------------------------------------------------------------

suite "Constraint":
  test "length":
    let c = length(100)
    check c.kind == ConstraintKind.Length
    check c.length == 100
    check c.isFixed
    check not c.isFlexible
  
  test "min":
    let c = min(50)
    check c.kind == ConstraintKind.Min
    check c.minVal == 50
    check not c.isFixed
    check c.isFlexible
  
  test "max":
    let c = max(200)
    check c.kind == ConstraintKind.Max
    check c.maxVal == 200
    check not c.isFixed
    check c.isFlexible
  
  test "percentage":
    let c = percentage(30)
    check c.kind == ConstraintKind.Percentage
    check c.percent == 30
    check c.isFlexible
    
    let clamped = percentage(150)
    check clamped.percent == 100
  
  test "ratio":
    let c = ratio(1, 3)
    check c.kind == ConstraintKind.Ratio
    check c.numerator == 1
    check c.denominator == 3
  
  test "fill":
    let c1 = fill()
    check c1.kind == ConstraintKind.Fill
    check c1.weight == 1
    
    let c2 = fill(3)
    check c2.weight == 3
  
  test "base size":
    check length(100).baseSize(1000) == 100
    check percentage(30).baseSize(1000) == 300
    check ratio(1, 4).baseSize(1000) == 250
    check min(50).baseSize(1000) == 50

# -----------------------------------------------------------------------------
# Margin tests
# -----------------------------------------------------------------------------

suite "Margin":
  test "construction":
    let m1 = margin(5)
    check m1.left == 5
    check m1.top == 5
    check m1.right == 5
    check m1.bottom == 5
    
    let m2 = margin(10, 20)
    check m2.left == 10
    check m2.right == 10
    check m2.top == 20
    check m2.bottom == 20
    
    let m3 = margin(1, 2, 3, 4)
    check m3.left == 1
    check m3.top == 2
    check m3.right == 3
    check m3.bottom == 4
  
  test "totals":
    let m = margin(5, 10, 15, 20)
    check m.horizontal == 20  # 5 + 15
    check m.vertical == 30    # 10 + 20

# -----------------------------------------------------------------------------
# Layout solver tests
# -----------------------------------------------------------------------------

suite "Layout - Simple splits":
  test "horizontal equal split":
    let area = rect(80, 24)
    let areas = hsplit(area, 2)
    
    check areas.len == 2
    check areas[0].width == 40
    check areas[1].width == 40
    check areas[0].x == 0
    check areas[1].x == 40
  
  test "vertical equal split":
    let area = rect(80, 24)
    let areas = vsplit(area, 3)
    
    check areas.len == 3
    check areas[0].height == 8
    check areas[1].height == 8
    check areas[2].height == 8
  
  test "horizontal with fixed sizes":
    let area = rect(100, 50)
    let areas = hsplit(area, @[length(20), length(30), fill()])
    
    check areas.len == 3
    check areas[0].width == 20
    check areas[1].width == 30
    check areas[2].width == 50  # Remaining space
  
  test "vertical with percentage":
    let area = rect(100, 100)
    let areas = vsplit(area, @[percentage(30), fill()])
    
    check areas.len == 2
    check areas[0].height == 30
    check areas[1].height == 70

suite "Layout - Complex constraints":
  test "multiple fill with weights":
    let area = rect(90, 50)
    let areas = hsplit(area, @[fill(1), fill(2), fill(1)])
    
    check areas.len == 3
    # Total weight = 4, space = 90
    # Each weight unit = 22 or 23 (with rounding)
    check areas[0].width + areas[1].width + areas[2].width == 90
    check areas[1].width >= areas[0].width  # Weight 2 should be bigger
  
  test "min constraint":
    let area = rect(100, 50)
    let areas = hsplit(area, @[min(30), fill()])
    
    check areas.len == 2
    check areas[0].width >= 30
    check areas[0].width + areas[1].width == 100
  
  test "max constraint":
    let area = rect(100, 50)
    let areas = hsplit(area, @[max(20), fill()])
    
    check areas.len == 2
    check areas[0].width <= 20
    check areas[1].width >= 80
  
  test "ratio constraints":
    let area = rect(120, 50)
    let areas = hsplit(area, @[ratio(1, 4), ratio(3, 4)])
    
    check areas.len == 2
    check areas[0].width == 30   # 1/4 of 120
    check areas[1].width == 90   # 3/4 of 120

suite "Layout - Margins and spacing":
  test "horizontal with margin":
    let area = rect(100, 100)
    let areas = horizontal()
      .constraints(fill(), fill())
      .margin(10)
      .split(area)
    
    check areas.len == 2
    # After 10px margin on all sides: 80x80 inner area
    check areas[0].x == 10
    check areas[0].y == 10
    check areas[1].x == 50
    check areas[0].width + areas[1].width == 80
    check areas[0].height == 80
  
  test "vertical with spacing":
    let area = rect(100, 100)
    let areas = vertical()
      .constraints(fill(), fill(), fill())
      .spacing(5)
      .split(area)
    
    check areas.len == 3
    # 100 - (2 * 5) spacing = 90 for content
    # Each gets 30
    check areas[0].height == 30
    check areas[1].height == 30
    check areas[2].height == 30
    check areas[1].y == areas[0].y + 30 + 5  # Spacing between
  
  test "margin and spacing combined":
    let area = rect(100, 100)
    let areas = horizontal()
      .constraints(fill(), fill())
      .margin(5)
      .spacing(10)
      .split(area)
    
    check areas.len == 2
    # After 5px margin: 90x90 inner
    # After 10px spacing: 80 for content
    check areas[0].width + areas[1].width == 80
    check areas[1].x == areas[0].x + areas[0].width + 10

suite "Layout - Flex modes":
  test "flex start (default)":
    let area = rect(100, 50)
    let areas = horizontal()
      .constraints(length(20), length(20))
      .flex(Flex.Start)
      .split(area)
    
    check areas[0].x == 0
    check areas[1].x == 20
    # 60 pixels of empty space at the right
  
  test "flex end":
    let area = rect(100, 50)
    let areas = horizontal()
      .constraints(length(20), length(20))
      .flex(Flex.End)
      .split(area)
    
    # Should start at x=60 (100 - 40)
    check areas[0].x == 60
    check areas[1].x == 80
  
  test "flex center":
    let area = rect(100, 50)
    let areas = horizontal()
      .constraints(length(20), length(20))
      .flex(Flex.Center)
      .split(area)
    
    # Should start at x=30 (60/2 extra space)
    check areas[0].x == 30
    check areas[1].x == 50

suite "Layout - Edge cases":
  test "empty constraints":
    let area = rect(100, 50)
    let areas = hsplit(area, @[])
    check areas.len == 0
  
  test "zero-size area":
    let area = rect(0, 0)
    let areas = hsplit(area, @[fill(), fill()])
    check areas.len == 2
    check areas[0].isEmpty
    check areas[1].isEmpty
  
  test "overflow handling":
    let area = rect(50, 50)
    # Request more space than available
    let areas = hsplit(area, @[length(30), length(30), length(30)])
    
    check areas.len == 3
    # Should shrink to fit (total = 50)
    check areas[0].width + areas[1].width + areas[2].width <= 50
  
  test "negative sizes clamped":
    let area = rect(20, 20)
    let areas = hsplit(area, @[length(15), length(15)])
    
    # Both request 15, but only 20 available
    check areas.len == 2
    for a in areas:
      check a.width >= 0  # No negative sizes

suite "Layout - Real world examples":
  test "typical TUI layout":
    # Header, content (sidebar + main), footer
    let term = rect(80, 24)
    let rows = vertical()
      .constraints(length(1), fill(), length(2))
      .split(term)
    
    check rows.len == 3
    check rows[0].height == 1  # Header
    check rows[2].height == 2  # Footer
    check rows[1].height == 21 # Content
    
    # Split content into sidebar and main
    let cols = horizontal()
      .constraints(percentage(25), fill())
      .margin(1)
      .split(rows[1])
    
    check cols.len == 2
    check cols[0].width == 19  # ~25% of 78 (after margin)
    check cols[1].width > cols[0].width  # Main area bigger
  
  test "nested layouts":
    let term = rect(100, 30)
    
    # Horizontal split: left panel + right panel
    let main = hsplit(term, @[percentage(30), fill()])
    
    # Split right panel vertically
    let right = vsplit(main[1], @[length(5), fill(), length(5)])
    
    check right.len == 3
    check right[0].y == main[1].y
    check right[0].height == 5
    check right[1].height == 20
    check right[2].height == 5

# Run tests
when isMainModule:
  echo "Running layout tests..."
