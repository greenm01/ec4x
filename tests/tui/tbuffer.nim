## Tests for screen buffer operations.

import std/[unittest, unicode]
import ../../src/player/tui/buffer
import ../../src/player/tui/term/types/core

suite "CellBuffer":
  test "initialization":
    let buf = initBuffer(80, 24)
    check buf.w == 80
    check buf.h == 24
    check buf.cells.len == 80 * 24
    
    # All cells should be empty spaces
    let (str, style, width) = buf.get(0, 0)
    check str == " "
    check width == 1
  
  test "size":
    let buf = initBuffer(100, 40)
    let (w, h) = buf.size()
    check w == 100
    check h == 40
  
  test "put and get":
    var buf = initBuffer(10, 10)
    let style = defaultStyle()
    
    discard buf.put(5, 5, "A", style)
    let (str, _, width) = buf.get(5, 5)
    check str == "A"
    check width == 1
  
  test "put out of bounds":
    var buf = initBuffer(10, 10)
    let style = defaultStyle()
    
    # Should be ignored, not crash
    let w1 = buf.put(-1, 5, "X", style)
    let w2 = buf.put(5, -1, "X", style)
    let w3 = buf.put(100, 5, "X", style)
    let w4 = buf.put(5, 100, "X", style)
    check w1 == 0
    check w2 == 0
    check w3 == 0
    check w4 == 0
  
  test "get out of bounds":
    let buf = initBuffer(10, 10)
    let (str, _, width) = buf.get(100, 100)
    check str == ""
    check width == 0
  
  test "dirty tracking":
    var buf = initBuffer(10, 10)
    let style = defaultStyle()
    
    # Initially all dirty (lastStr is empty)
    check buf.dirty(0, 0) == true
    
    # Put makes cell dirty
    discard buf.put(5, 5, "A", style)
    check buf.dirty(5, 5) == true
    
    # Mark clean
    buf.setDirty(5, 5, false)
    check buf.dirty(5, 5) == false
    
    # Mark dirty again
    buf.setDirty(5, 5, true)
    check buf.dirty(5, 5) == true
  
  test "cell locking":
    var buf = initBuffer(10, 10)
    
    # Lock a cell
    buf.lockCell(5, 5)
    check buf.dirty(5, 5) == false  # Locked cells report not dirty
    
    # Unlock and check it's dirty
    buf.unlockCell(5, 5)
    check buf.dirty(5, 5) == true
  
  test "fill":
    var buf = initBuffer(10, 10)
    buf.fill(Rune('X'), defaultStyle())
    
    # Check a few cells
    let (str1, _, _) = buf.get(0, 0)
    let (str2, _, _) = buf.get(5, 5)
    let (str3, _, _) = buf.get(9, 9)
    check str1 == "X"
    check str2 == "X"
    check str3 == "X"
  
  test "clear":
    var buf = initBuffer(10, 10)
    let style = defaultStyle()
    
    # Put some data
    discard buf.put(5, 5, "A", style)
    
    # Clear
    buf.clear()
    
    # Should be space
    let (str, _, _) = buf.get(5, 5)
    check str == " "
  
  test "invalidate":
    var buf = initBuffer(10, 10)
    let style = defaultStyle()
    
    # Put and mark clean
    discard buf.put(5, 5, "A", style)
    buf.setDirty(5, 5, false)
    check buf.dirty(5, 5) == false
    
    # Invalidate all
    buf.invalidate()
    check buf.dirty(5, 5) == true
  
  test "resize larger":
    var buf = initBuffer(10, 10)
    let style = defaultStyle()
    
    # Put some content
    discard buf.put(5, 5, "A", style)
    
    # Resize larger
    buf.resize(20, 20)
    check buf.w == 20
    check buf.h == 20
    
    # Old content preserved
    let (str, _, _) = buf.get(5, 5)
    check str == "A"
    
    # New cells are spaces
    let (str2, _, _) = buf.get(15, 15)
    check str2 == " "
  
  test "resize smaller":
    var buf = initBuffer(20, 20)
    let style = defaultStyle()
    
    # Put content in various places
    discard buf.put(5, 5, "A", style)
    discard buf.put(15, 15, "B", style)
    
    # Resize smaller
    buf.resize(10, 10)
    check buf.w == 10
    check buf.h == 10
    
    # Content within new bounds preserved
    let (str1, _, _) = buf.get(5, 5)
    check str1 == "A"
    
    # Content outside new bounds lost (can't access)
    let (str2, _, _) = buf.get(15, 15)
    check str2 == ""  # Out of bounds
  
  test "resize same size is no-op":
    var buf = initBuffer(10, 10)
    let style = defaultStyle()
    
    discard buf.put(5, 5, "A", style)
    let oldCells = buf.cells
    
    buf.resize(10, 10)
    
    # Should be exact same buffer
    check buf.cells == oldCells
  
  test "wide character support":
    var buf = initBuffer(10, 10)
    let style = defaultStyle()
    
    # Put a wide character (Japanese)
    let width = buf.put(5, 5, "あ", style)
    check width == 2  # Wide characters have width 2
    
    let (str, _, w) = buf.get(5, 5)
    check str == "あ"
    check w == 2

suite "CellStyle":
  test "equality":
    let s1 = defaultStyle()
    let s2 = defaultStyle()
    check s1 == s2
    
    var s3 = defaultStyle()
    s3.fg = color(AnsiColor(1))
    check s1 != s3

when isMainModule:
  echo "Running buffer tests..."
