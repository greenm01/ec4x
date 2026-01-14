## Interactive demo of TUI input and buffer system.
##
## Demonstrates:
## - Raw mode terminal control
## - Keyboard input parsing
## - Screen buffer rendering
## - SIGWINCH resize handling
##
## Press 'q' or Ctrl-C to quit.

import std/[unicode, strformat]
import ../../src/player/tui/[buffer, events, input, tty, signals]
import ../../src/player/tui/term/types/[core, style]
import ../../src/player/tui/term/[screen, output]

proc drawBuffer(buf: CellBuffer, output: var Output) =
  ## Render dirty cells to terminal.
  output.hideCursor()
  
  let (w, h) = buf.size()
  for y in 0..<h:
    for x in 0..<w:
      if buf.dirty(x, y):
        let (str, cellStyle, width) = buf.get(x, y)
        
        # Convert CellStyle to term.Style for rendering
        var s = output.newStyle(str)
        if not cellStyle.fg.isNone:
          s = s.fg(cellStyle.fg)
        if not cellStyle.bg.isNone:
          s = s.bg(cellStyle.bg)
        if StyleAttr.Bold in cellStyle.attrs:
          s = s.bold()
        if StyleAttr.Italic in cellStyle.attrs:
          s = s.italic()
        if StyleAttr.Underline in cellStyle.attrs:
          s = s.underline()
        
        # Position cursor and write
        output.moveCursor(x + 1, y + 1)  # 1-based terminal coords
        output.write($s)

proc main() =
  echo "Initializing terminal..."
  
  # Open terminal
  var terminal = openTty()
  defer: terminal.close()
  
  # Create output for terminal operations
  var output = initOutput()
  defer:
    # Cleanup on exit
    output.clearScreen()
    output.exitAltScreen()
    output.showCursor()
  
  # Enter alternate screen and raw mode
  output.enterAltScreen()
  output.clearScreen()
  
  if not terminal.start():
    echo "Failed to enter raw mode"
    return
  defer: discard terminal.stop()
  
  # Setup resize handler
  setupResizeHandler()
  
  # Get initial size
  let (termW, termH) = terminal.windowSize()
  var buffer = initBuffer(termW, termH)
  
  # Create input parser
  var parser = initParser()
  
  # Draw initial UI
  var style = defaultStyle()
  style.fg = color(AnsiColor(2))  # Green
  style.attrs = {StyleAttr.Bold}
  
  let title = "EC4X TUI Demo - Press keys to see events (q to quit)"
  for i, r in title.toRunes():
    if i < buffer.w:
      discard buffer.put(i, 0, $r, style)
  
  # Status line style
  var statusStyle = defaultStyle()
  statusStyle.fg = color(AnsiColor(6))  # Cyan
  
  # Event counter
  var eventCount = 0
  var lastEvent = "None"
  
  # Initial render
  drawBuffer(buffer, output)
  output.showCursor()
  output.flush()
  
  # Main loop
  while true:
    # Check for resize
    if checkResize():
      let (newW, newH) = terminal.windowSize()
      buffer.resize(newW, newH)
      buffer.invalidate()
      
      # Redraw title after resize
      let resizeTitle = "RESIZED! " & title
      style.fg = color(AnsiColor(3))  # Yellow
      for i, r in resizeTitle.toRunes():
        if i < buffer.w:
          discard buffer.put(i, 0, $r, style)
      
      drawBuffer(buffer, output)
      output.flush()
    
    # Read and parse input
    let event = terminal.readEvent(parser)
    
    case event.kind
    of EventKind.Key:
      let ke = event.keyEvent
      eventCount.inc
      lastEvent = $ke
      
      # Check for quit
      if ke.key == Key.Rune and ke.rune == Rune('q'):
        break
      if ke.key == Key.CtrlC:
        break
      
      # Display event info
      let eventLine = &"Event #{eventCount}: {lastEvent}"
      for i in 0..<buffer.w:
        discard buffer.put(i, 2, " ", statusStyle)
      
      for i, r in eventLine.toRunes():
        if i < buffer.w:
          discard buffer.put(i, 2, $r, statusStyle)
      
      # Show key visualization
      var keyStyle = defaultStyle()
      keyStyle.fg = color(AnsiColor(5))  # Magenta
      keyStyle.attrs = {StyleAttr.Bold}
      
      let keyDisplay = case ke.key
        of Key.Rune: &"'{ke.rune}'"
        of Key.Up: "↑"
        of Key.Down: "↓"
        of Key.Left: "←"
        of Key.Right: "→"
        else: ke.key.name()
      
      let keyLine = &"  Key: {keyDisplay}"
      for i in 0..<buffer.w:
        discard buffer.put(i, 4, " ", keyStyle)
      
      for i, r in keyLine.toRunes():
        if i < buffer.w:
          discard buffer.put(i, 4, $r, keyStyle)
      
      # Draw changes
      drawBuffer(buffer, output)
      output.flush()
    
    of EventKind.Resize:
      # Already handled above
      discard
    
    of EventKind.Error:
      break

when isMainModule:
  main()
