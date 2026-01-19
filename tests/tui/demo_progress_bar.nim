## Progress Bar Widget Demo
##
## Tests and demonstrates the progress bar widget rendering.
## Run with: nim c -r tests/tui/demo_progress_bar.nim

import std/[unittest, strutils]
import ../../src/player/tui/widget/progress_bar
import ../../src/player/tui/buffer
import ../../src/player/tui/layout/rect
import ../../src/player/tui/styles/ec_palette

suite "ProgressBar String Rendering":
  test "0% progress":
    let pb = progressBar(0, 10, 10)
    let s = pb.renderToString()
    check "░░░░░░░░░░" in s
    check "0%" in s
  
  test "50% progress":
    let pb = progressBar(5, 10, 10)
    let s = pb.renderToString()
    check "▓▓▓▓▓░░░░░" in s
    check "50%" in s
  
  test "100% progress":
    let pb = progressBar(10, 10, 10)
    let s = pb.renderToString()
    check "▓▓▓▓▓▓▓▓▓▓" in s
    check "100%" in s
  
  test "25% progress":
    let pb = progressBar(1, 4, 8)
    let s = pb.renderToString()
    check "▓▓░░░░░░" in s
    check "25%" in s
  
  test "75% progress":
    let pb = progressBar(3, 4, 8)
    let s = pb.renderToString()
    check "▓▓▓▓▓▓░░" in s
    check "75%" in s
  
  test "with label":
    let pb = progressBar(5, 10, 10).label("Building")
    let s = pb.renderToString()
    check "Building" in s
    check "▓▓▓▓▓░░░░░" in s
  
  test "with remaining turns":
    let pb = progressBar(3, 10, 10)
      .showRemaining(true)
    let s = pb.renderToString()
    check "(7 turns)" in s
  
  test "1 turn remaining (singular)":
    let pb = progressBar(9, 10, 10)
      .showRemaining(true)
    let s = pb.renderToString()
    check "(1 turn)" in s
  
  test "construction progress helper":
    let pb = constructionProgress("Destroyer", 3, 6, 10)
    let s = pb.renderToString()
    check "Destroyer" in s
    check "▓▓▓▓▓░░░░░" in s
    check "50%" in s
    check "(3 turns)" in s

suite "ProgressBar Calculations":
  test "percentage calculation":
    check progressBar(0, 10, 10).percentage() == 0
    check progressBar(5, 10, 10).percentage() == 50
    check progressBar(10, 10, 10).percentage() == 100
    check progressBar(3, 4, 10).percentage() == 75
  
  test "percentage with zero total":
    # Zero total should return 100% (complete/undefined)
    check progressBar(0, 0, 10).percentage() == 100
  
  test "filled count":
    check progressBar(0, 10, 10).filledCount() == 0
    check progressBar(5, 10, 10).filledCount() == 5
    check progressBar(10, 10, 10).filledCount() == 10
    check progressBar(7, 10, 10).filledCount() == 7
  
  test "remaining":
    check progressBar(0, 10, 10).remaining() == 10
    check progressBar(5, 10, 10).remaining() == 5
    check progressBar(10, 10, 10).remaining() == 0

suite "ProgressBar Buffer Rendering":
  test "renders to buffer":
    var buf = initBuffer(80, 24)
    let pb = progressBar(5, 10, 10)
    let area = rect(0, 0, 40, 1)
    
    pb.render(area, buf)
    
    # Check that content was written
    let (str0, _, _) = buf.get(0, 0)
    # Should have progress bar content, not empty
    check str0 != ""
  
  test "renders with label":
    var buf = initBuffer(80, 24)
    let pb = progressBar(5, 10, 10).label("Test")
    let area = rect(0, 0, 40, 1)
    
    pb.render(area, buf)
    
    # First chars should be the label
    let (str0, _, _) = buf.get(0, 0)
    check str0 == "T"
  
  test "respects area bounds":
    var buf = initBuffer(20, 5)
    let pb = progressBar(5, 10, 10).label("Very Long Label")
    let area = rect(0, 0, 15, 1)
    
    # Should not crash with limited area
    pb.render(area, buf)
  
  test "empty area is no-op":
    var buf = initBuffer(80, 24)
    let pb = progressBar(5, 10, 10)
    let area = rect(0, 0, 0, 0)
    
    # Should not crash
    pb.render(area, buf)

suite "ProgressBar Styles":
  test "health bar low health (red)":
    let pb = healthBar(20, 100, 10)
    # Low health should have alert color
    check pb.filledStyle.fg == color(AlertColor)
  
  test "health bar medium health (yellow)":
    let pb = healthBar(40, 100, 10)
    # Medium health should have prestige (yellow) color
    check pb.filledStyle.fg == color(PrestigeColor)
  
  test "health bar high health (green)":
    let pb = healthBar(80, 100, 10)
    # High health keeps default green
    check pb.filledStyle.fg == color(PositiveColor)

# Visual demo (run to see output)
when isMainModule:
  echo "\n=== Progress Bar Visual Demo ===\n"
  
  echo "Basic progress bars:"
  echo "  0%:   ", progressBar(0, 10, 10).renderToString()
  echo " 25%:   ", progressBar(1, 4, 10).renderToString()
  echo " 50%:   ", progressBar(5, 10, 10).renderToString()
  echo " 75%:   ", progressBar(3, 4, 10).renderToString()
  echo "100%:   ", progressBar(10, 10, 10).renderToString()
  
  echo "\nConstruction queue items:"
  echo constructionProgress("Destroyer", 3, 6, 10).renderToString()
  echo constructionProgress("Shipyard", 0, 8, 10).renderToString()
  echo constructionProgress("Cruiser", 4, 4, 10).renderToString()
  
  echo "\nWith labels only (no remaining):"
  echo progressBar(7, 10, 12).label("Shield").showRemaining(false).renderToString()
  
  echo "\n=== End Demo ===\n"
