## Table Widget Demo
##
## Tests and demonstrates the table widget rendering.
## Run with: nim c -r tests/tui/demo_table.nim

import std/[unittest, strutils]
import ../../src/player/tui/widget/table
import ../../src/player/tui/buffer
import ../../src/player/tui/layout/rect
import ../../src/player/tui/styles/ec_palette

suite "Table String Rendering":
  test "basic table":
    var t = table([
      tableColumn("Name", width = 10),
      tableColumn("Value", width = 8, align = Alignment.Right)
    ])
    t.addRow(@["Alpha", "100"])
    t.addRow(@["Beta", "200"])
    
    let lines = t.renderToStrings(40)
    check lines.len >= 4  # Header + separator + 2 rows
    check "Name" in lines[0]
    check "Value" in lines[0]
    check "Alpha" in lines[2]
    check "Beta" in lines[3]
  
  test "selected row marker":
    var t = table([
      tableColumn("Item", width = 10)
    ]).selectedIdx(1)
    t.addRow(@["First"])
    t.addRow(@["Second"])
    t.addRow(@["Third"])
    
    let lines = t.renderToStrings(30)
    # First row should have normal indent
    check lines[2].startsWith("  ")
    # Second row should have > marker
    check lines[3].startsWith("> ")
  
  test "right alignment":
    let t = table([
      tableColumn("Num", width = 6, align = Alignment.Right)
    ]).rows(@[@["42"]])
    
    let lines = t.renderToStrings(20)
    check lines.len >= 3
    # "42" should be right-aligned in 6 chars
    check "    42" in lines[2]
  
  test "center alignment":
    let t = table([
      tableColumn("Text", width = 10, align = Alignment.Center)
    ]).rows(@[@["Hi"]])
    
    let lines = t.renderToStrings(20)
    # "Hi" centered in 10 chars = "    Hi    "
    check "    Hi" in lines[2]
  
  test "no header":
    let t = table([
      tableColumn("Col", width = 5)
    ]).rows(@[@["X"]]).showHeader(false)
    
    let lines = t.renderToStrings(20)
    # Should not have header row
    check "Col" notin lines[0]
  
  test "no separator":
    let t = table([
      tableColumn("Col", width = 5)
    ]).rows(@[@["X"]]).showSeparator(false)
    
    let lines = t.renderToStrings(20)
    check lines.len >= 2
    # Second line should be data, not separator
    check "-" notin lines[1]
  
  test "no selector":
    let t = table([
      tableColumn("Col", width = 5)
    ]).rows(@[@["X"]]).showSelector(false).selectedIdx(0)
    
    let lines = t.renderToStrings(20)
    # Should not have > marker even for selected row
    check "> " notin lines[2]

suite "Table Column Width Calculation":
  test "fixed widths":
    let t = table([
      tableColumn("A", width = 10),
      tableColumn("B", width = 15),
      tableColumn("C", width = 8)
    ])
    let widths = t.calculateColumnWidths(50)
    check widths[0] == 10
    check widths[1] == 15
    check widths[2] == 8
  
  test "auto width columns":
    let t = table([
      tableColumn("A", width = 0, minWidth = 5),
      tableColumn("B", width = 0, minWidth = 5)
    ])
    let widths = t.calculateColumnWidths(40)
    # Both should get roughly equal share of remaining space
    check widths[0] >= 5
    check widths[1] >= 5

suite "Table Buffer Rendering":
  test "renders to buffer":
    var buf = initBuffer(80, 24)
    var t = table([
      tableColumn("Name", width = 10)
    ])
    t.addRow(@["Test"])
    let area = rect(0, 0, 40, 10)
    
    t.render(area, buf)
    
    # Check header was written
    let (str0, _, _) = buf.get(2, 0)  # After selector space
    check str0 == "N"
  
  test "respects area bounds":
    var buf = initBuffer(20, 5)
    var t = table([
      tableColumn("VeryLongHeader", width = 20)
    ])
    t.addRow(@["VeryLongValue"])
    let area = rect(0, 0, 15, 3)
    
    # Should not crash
    t.render(area, buf)
  
  test "empty table is no-op":
    var buf = initBuffer(80, 24)
    let t = table(newSeq[TableColumn]())
    let area = rect(0, 0, 40, 10)
    
    # Should not crash
    t.render(area, buf)

suite "Table Preset Constructors":
  test "ship list table":
    let t = shipListTable()
    check t.columns.len == 5
    check t.columns[0].header == "Name"
    check t.columns[2].header == "HP"
    check t.columns[2].align == Alignment.Right
  
  test "fleet list table":
    let t = fleetListTable()
    check t.columns.len == 4
    check t.columns[0].header == "Fleet"
    check t.columns[1].header == "Location"
  
  test "colony list table":
    let t = colonyListTable()
    check t.columns.len == 4
    check t.columns[0].header == "Colony"
  
  test "construction queue table":
    let t = constructionQueueTable()
    check t.columns.len == 4
    check t.columns[1].header == "Item"

# Visual demo
when isMainModule:
  echo "\n=== Table Widget Visual Demo ===\n"
  
  echo "Ship List Table:"
  var shipTable = shipListTable().selectedIdx(1)
  shipTable.addRow(@["Alpha-1", "Destroyer", "100%", "45", "38"])
  shipTable.addRow(@["Alpha-2", "Destroyer", "100%", "45", "38"])
  shipTable.addRow(@["Beta-1", "Frigate", "82%", "28", "22"])
  shipTable.addRow(@["Gamma-1", "Cruiser", "95%", "85", "70"])
  
  for line in shipTable.renderToStrings(60):
    echo "  ", line
  
  echo "\n\nFleet List Table:"
  var fleetTable = fleetListTable().selectedIdx(0)
  fleetTable.addRow(@["Alpha", "Homeworld", "4", "Hold"])
  fleetTable.addRow(@["Beta", "Nova Prime", "7", "Patrol"])
  fleetTable.addRow(@["Gamma", "Frontier", "2", "Move"])
  
  for line in fleetTable.renderToStrings(55):
    echo "  ", line
  
  echo "\n\nColony List Table:"
  var colonyTable = colonyListTable().selectedIdx(2)
  colonyTable.addRow(@["Homeworld", "1250", "340", "OK"])
  colonyTable.addRow(@["Nova Prime", "820", "180", "OK"])
  colonyTable.addRow(@["Frontier", "150", "25", "Developing"])
  
  for line in colonyTable.renderToStrings(50):
    echo "  ", line
  
  echo "\n\nConstruction Queue:"
  var queueTable = constructionQueueTable().selectedIdx(0)
  queueTable.addRow(@["1", "Destroyer", "50%", "2 turns"])
  queueTable.addRow(@["2", "Shipyard", "0%", "5 turns"])
  queueTable.addRow(@["3", "Marines x5", "0%", "8 turns"])
  
  for line in queueTable.renderToStrings(45):
    echo "  ", line
  
  echo "\n\nTable without selector (showSelector=false):"
  var noSelector = table([
    tableColumn("A", width = 8),
    tableColumn("B", width = 8)
  ]).showSelector(false)
  noSelector.addRow(@["Value1", "Value2"])
  noSelector.addRow(@["Value3", "Value4"])
  
  for line in noSelector.renderToStrings(30):
    echo "  ", line
  
  echo "\n=== End Demo ===\n"
