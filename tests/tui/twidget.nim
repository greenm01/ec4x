## Tests for widget system
##
## Tests text types, borders, frame, paragraph, and list widgets.

import std/[unittest, options]
import ../../src/player/tui/widget/widget_pkg
import ../../src/player/tui/buffer
import ../../src/player/tui/layout/rect

# -----------------------------------------------------------------------------
# Span tests
# -----------------------------------------------------------------------------

suite "Span":
  test "construction":
    let s = span("Hello")
    check s.content == "Hello"
    check s.style == defaultStyle()
  
  test "styled construction":
    var style = defaultStyle()
    style.attrs.incl(StyleAttr.Bold)
    let s = span("Bold", style)
    check s.content == "Bold"
    check StyleAttr.Bold in s.style.attrs
  
  test "fluent styling":
    let s = span("test").bold().italic()
    check StyleAttr.Bold in s.style.attrs
    check StyleAttr.Italic in s.style.attrs
  
  test "width calculation":
    let s1 = span("Hello")
    check s1.width() == 5
    
    let s2 = span("")
    check s2.width() == 0
  
  test "isEmpty":
    check span("").isEmpty
    check not span("x").isEmpty

# -----------------------------------------------------------------------------
# Line tests
# -----------------------------------------------------------------------------

suite "Line":
  test "construction from string":
    let l = line("Hello World")
    check l.spans.len == 1
    check l.spans[0].content == "Hello World"
    check l.alignment == Alignment.Left
  
  test "construction from spans":
    let l = line(@[span("Hello"), span(" "), span("World")])
    check l.spans.len == 3
    check l.width() == 11
  
  test "alignment":
    let l1 = line("test").left()
    check l1.alignment == Alignment.Left
    
    let l2 = line("test").center()
    check l2.alignment == Alignment.Center
    
    let l3 = line("test").right()
    check l3.alignment == Alignment.Right
  
  test "width":
    let l = line(@[span("Hello"), span(" "), span("World")])
    check l.width() == 11
  
  test "concatenation":
    let l = line("Hello") & span(" World")
    check l.spans.len == 2
    check l.width() == 11
  
  test "calculate offset":
    let l = line("test").center()  # 4 chars
    check l.calculateOffset(10) == 3  # (10-4)/2 = 3

# -----------------------------------------------------------------------------
# Text tests
# -----------------------------------------------------------------------------

suite "Text":
  test "construction from string":
    let t = text("Line 1\nLine 2\nLine 3")
    check t.lines.len == 3
    check t.lines[0].spans[0].content == "Line 1"
    check t.lines[2].spans[0].content == "Line 3"
  
  test "construction from lines":
    let t = text(@[line("A"), line("B")])
    check t.lines.len == 2
  
  test "height and width":
    let t = text("Short\nMuch longer line\nMedium")
    check t.height() == 3
    check t.width() == 16  # "Much longer line"
  
  test "isEmpty":
    check text("").lines.len == 1  # Empty string creates one empty line
    check text(@[]).isEmpty

# -----------------------------------------------------------------------------
# Border tests
# -----------------------------------------------------------------------------

suite "Borders":
  test "constants":
    check NoBorders == {}
    check AllBorders == {Border.Top, Border.Right, Border.Bottom, Border.Left}
  
  test "border checks":
    let b = {Border.Top, Border.Left}
    check b.hasTop
    check b.hasLeft
    check not b.hasRight
    check not b.hasBottom
  
  test "isEmpty and isFull":
    check NoBorders.isEmpty
    check AllBorders.isFull
    check not AllBorders.isEmpty
    check not NoBorders.isFull
  
  test "border sets":
    let plain = BorderType.Plain.borderSet()
    check plain.topLeft == "┌"
    check plain.horizontal == "─"
    check plain.vertical == "│"
    
    let rounded = BorderType.Rounded.borderSet()
    check rounded.topLeft == "╭"
    
    let double = BorderType.Double.borderSet()
    check double.topLeft == "╔"
    check double.horizontal == "═"

# -----------------------------------------------------------------------------
# Padding tests
# -----------------------------------------------------------------------------

suite "Padding":
  test "construction":
    let p1 = padding(5)
    check p1.left == 5
    check p1.top == 5
    check p1.right == 5
    check p1.bottom == 5
    
    let p2 = padding(10, 20)
    check p2.left == 10
    check p2.right == 10
    check p2.top == 20
    check p2.bottom == 20
    
    let p3 = padding(1, 2, 3, 4)
    check p3.left == 1
    check p3.top == 2
    check p3.right == 3
    check p3.bottom == 4
  
  test "horizontal and vertical":
    let p = padding(5, 10, 15, 20)
    check p.horizontal == 20  # 5 + 15
    check p.vertical == 30    # 10 + 20

# -----------------------------------------------------------------------------
# Frame tests
# -----------------------------------------------------------------------------

suite "Frame":
  test "construction":
    # Just verify construction doesn't error
    let f = newFrame()
    let b = bordered()
    # Can't check internal fields, but can check inner() behavior
    discard f
    discard b
  
  test "inner area - no borders":
    let f = newFrame()
    let area = rect(0, 0, 20, 10)
    let inner = f.inner(area)
    check inner == area
  
  test "inner area - all borders":
    let f = bordered()
    let area = rect(0, 0, 20, 10)
    let inner = f.inner(area)
    check inner.x == 1
    check inner.y == 1
    check inner.width == 18
    check inner.height == 8
  
  test "inner area - with padding":
    let f = bordered().padding(2)
    let area = rect(0, 0, 20, 10)
    let inner = f.inner(area)
    # Borders take 1 each side, padding takes 2 each side
    check inner.x == 3
    check inner.y == 3
    check inner.width == 14  # 20 - 2 (borders) - 4 (padding)
    check inner.height == 4   # 10 - 2 (borders) - 4 (padding)
  
  test "inner area - partial borders":
    let f = newFrame().borders({Border.Left, Border.Top})
    let area = rect(0, 0, 20, 10)
    let inner = f.inner(area)
    check inner.x == 1
    check inner.y == 1
    check inner.width == 19  # Only left border
    check inner.height == 9   # Only top border
  
  test "render borders":
    var buf = initBuffer(10, 5)
    let f = bordered()
    f.render(rect(0, 0, 10, 5), buf)
    
    # Check corners
    check buf.get(0, 0).str == "┌"
    check buf.get(9, 0).str == "┐"
    check buf.get(0, 4).str == "└"
    check buf.get(9, 4).str == "┘"
    
    # Check edges
    check buf.get(5, 0).str == "─"  # Top
    check buf.get(5, 4).str == "─"  # Bottom
    check buf.get(0, 2).str == "│"  # Left
    check buf.get(9, 2).str == "│"  # Right

# -----------------------------------------------------------------------------
# Paragraph tests
# -----------------------------------------------------------------------------

suite "Paragraph":
  test "construction":
    # Just verify construction works
    let p = paragraph("Hello World")
    discard p
  
  test "multiline":
    let p = paragraph("Line 1\nLine 2")
    discard p
  
  test "render simple":
    var buf = initBuffer(20, 5)
    let p = paragraph("Hello")
    p.render(rect(0, 0, 20, 5), buf)
    
    # Check first characters
    check buf.get(0, 0).str == "H"
    check buf.get(1, 0).str == "e"
    check buf.get(4, 0).str == "o"
  
  test "render with frame":
    var buf = initBuffer(20, 5)
    let p = paragraph("Hello").`block`(bordered())
    p.render(rect(0, 0, 20, 5), buf)
    
    # Border at edges
    check buf.get(0, 0).str == "┌"
    # Content inside
    check buf.get(1, 1).str == "H"

# -----------------------------------------------------------------------------
# List tests
# -----------------------------------------------------------------------------

suite "List":
  test "construction from strings":
    # Just verify construction works
    let l = list(@["Item 1", "Item 2", "Item 3"])
    discard l
  
  test "construction from ListItems":
    let items = @[listItem("A"), listItem("B")]
    let l = list(items)
    discard l
  
  test "list state":
    var state = newListState()
    check state.selected.isNone
    check state.offset == 0
    
    state.select(2)
    check state.selected.isSome
    check state.selected.get() == 2
    
    state.deselect()
    check state.selected.isNone
  
  test "select next/prev":
    var state = newListState()
    state.select(0)
    
    state.selectNext(5)
    check state.selected.get() == 1
    
    state.selectNext(5)
    check state.selected.get() == 2
    
    state.selectPrev()
    check state.selected.get() == 1
  
  test "select next wraps":
    var state = newListState()
    state.select(4)
    state.selectNext(5)  # 5 items, was at index 4
    check state.selected.get() == 0  # Wraps to 0
  
  test "render list":
    var buf = initBuffer(20, 5)
    var state = newListState()
    let l = list(@["Item A", "Item B", "Item C"])
    l.render(rect(0, 0, 20, 5), buf, state)
    
    # First item should be visible (no selection, so no highlight symbol)
    check buf.get(0, 0).str == "I"  # "Item A" starts at x=0
  
  test "render with selection":
    var buf = initBuffer(20, 5)
    var state = newListState()
    state.select(1)
    
    let l = list(@["Item A", "Item B", "Item C"])
    l.render(rect(0, 0, 20, 5), buf, state)
    
    # Second item (index 1) should have highlight symbol
    check buf.get(0, 1).str == ">"

# Run tests
when isMainModule:
  echo "Running widget tests..."
