## Tabs Widget Demo
##
## Tests and demonstrates the tab selector widget rendering.
## Run with: nim c -r tests/tui/demo_tabs.nim

import std/[unittest, strutils]
import ../../src/player/tui/widget/tabs
import ../../src/player/tui/buffer
import ../../src/player/tui/layout/rect
import ../../src/player/tui/styles/ec_palette

suite "Tabs String Rendering":
  test "basic tabs":
    let t = tabs(["One", "Two", "Three"], 0)
    let s = t.renderToString()
    check "[One]" in s
    check "Two" in s
    check "Three" in s
  
  test "second tab active":
    let t = tabs(["One", "Two", "Three"], 1)
    let s = t.renderToString()
    check "One" in s
    check "[Two]" in s
    check "Three" in s
  
  test "last tab active":
    let t = tabs(["A", "B", "C"], 2)
    let s = t.renderToString()
    check "A" in s
    check "B" in s
    check "[C]" in s
  
  test "no brackets option":
    let t = tabs(["One", "Two"], 0).showBrackets(false)
    let s = t.renderToString()
    check "[" notin s
    check "]" notin s
    check "One" in s
  
  test "custom separator":
    let t = tabs(["A", "B"], 0).separator(" | ")
    let s = t.renderToString()
    check " | " in s

suite "Tabs Navigation":
  test "select next":
    var t = tabs(["A", "B", "C"], 0)
    check t.activeIdx == 0
    t.selectNext()
    check t.activeIdx == 1
    t.selectNext()
    check t.activeIdx == 2
  
  test "select next wraps":
    var t = tabs(["A", "B", "C"], 2)
    t.selectNext()
    check t.activeIdx == 0
  
  test "select prev":
    var t = tabs(["A", "B", "C"], 2)
    t.selectPrev()
    check t.activeIdx == 1
    t.selectPrev()
    check t.activeIdx == 0
  
  test "select prev wraps":
    var t = tabs(["A", "B", "C"], 0)
    t.selectPrev()
    check t.activeIdx == 2
  
  test "select by index":
    var t = tabs(["A", "B", "C"], 0)
    t.selectByIndex(2)
    check t.activeIdx == 2
  
  test "select disabled tab skipped":
    var t = tabs([
      tabItem("A", enabled = true),
      tabItem("B", enabled = false),
      tabItem("C", enabled = true)
    ], 0)
    t.selectNext()
    # Should skip B and go to C
    check t.activeIdx == 2

suite "Tabs Properties":
  test "active label":
    let t = tabs(["One", "Two", "Three"], 1)
    check t.activeLabel() == "Two"
  
  test "tab count":
    let t = tabs(["A", "B", "C", "D", "E"], 0)
    check t.tabCount() == 5
  
  test "enabled count":
    let t = tabs([
      tabItem("A", enabled = true),
      tabItem("B", enabled = false),
      tabItem("C", enabled = true),
      tabItem("D", enabled = false)
    ], 0)
    check t.enabledCount() == 2

suite "Tabs Buffer Rendering":
  test "renders to buffer":
    var buf = initBuffer(80, 24)
    let t = tabs(["One", "Two", "Three"], 0)
    let area = rect(0, 0, 40, 1)
    
    t.render(area, buf)
    
    # Check first character is bracket
    let (str0, _, _) = buf.get(0, 0)
    check str0 == "["
  
  test "respects area bounds":
    var buf = initBuffer(20, 5)
    let t = tabs(["VeryLongTab", "AnotherLong"], 0)
    let area = rect(0, 0, 15, 1)
    
    # Should not crash with limited area
    t.render(area, buf)
  
  test "empty tabs is no-op":
    var buf = initBuffer(80, 24)
    let t = tabs(newSeq[string](), 0)
    let area = rect(0, 0, 40, 1)
    
    # Should not crash
    t.render(area, buf)

suite "Tabs Preset Constructors":
  test "planet detail tabs":
    let t = planetDetailTabs(0)
    check t.tabCount() == 5
    check t.activeLabel() == "Summary"
  
  test "planet detail tabs construction selected":
    let t = planetDetailTabs(2)
    check t.activeLabel() == "Construction"
  
  test "fleet detail tabs":
    let t = fleetDetailTabs(0)
    check t.tabCount() == 3
    check t.activeLabel() == "Ships"
  

# Visual demo
when isMainModule:
  echo "\n=== Tabs Widget Visual Demo ===\n"
  
  echo "Planet Detail Tabs (Summary active):"
  echo "  ", planetDetailTabs(0).renderToString()
  
  echo "\nPlanet Detail Tabs (Construction active):"
  echo "  ", planetDetailTabs(2).renderToString()
  
  echo "\nFleet Detail Tabs:"
  echo "  ", fleetDetailTabs(0).renderToString()
  

  echo "\nCustom tabs without brackets:"
  echo "  ", tabs(["Alpha", "Beta", "Gamma"], 1).showBrackets(false).renderToString()
  
  echo "\nWith pipe separator:"
  echo "  ", tabs(["A", "B", "C"], 0).separator(" | ").renderToString()
  
  echo "\nWith disabled tab:"
  let disabledTabs = tabs([
    tabItem("Open", enabled = true),
    tabItem("Locked", enabled = false),
    tabItem("Available", enabled = true)
  ], 0)
  echo "  ", disabledTabs.renderToString()
  
  echo "\n=== End Demo ===\n"
