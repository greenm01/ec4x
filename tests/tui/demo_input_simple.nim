## Simple interactive demo of TUI input system.
##
## Demonstrates:
## - Raw mode terminal control
## - Keyboard input parsing
## - Basic screen output (no buffer, raw ANSI)
##
## Press 'q' or ESC to quit.

import std/[unicode, strformat, strutils]
import ../../src/player/tui/[events, input, tty, signals]

proc clearScreen() =
  stdout.write("\x1b[2J\x1b[H")
  stdout.flushFile()

proc moveCursor(x, y: int) =
  stdout.write(&"\x1b[{y};{x}H")

proc main() =
  echo "Initializing terminal..."
  
  # Open terminal
  var terminal = openTty()
  defer: terminal.close()
  
  # Enter raw mode
  if not terminal.start():
    echo "Failed to enter raw mode"
    return
  defer: discard terminal.stop()
  
  # Setup resize handler
  setupResizeHandler()
  
  # Clear screen
  clearScreen()
  
  # Get initial size
  let (termW, termH) = terminal.windowSize()
  
  # Draw header
  moveCursor(1, 1)
  stdout.write("\x1b[1;32m")  # Bold green
  stdout.write("EC4X TUI Demo - Press keys to see events (q or ESC to quit)")
  stdout.write("\x1b[0m")  # Reset
  
  # Create input parser
  var parser = initParser()
  
  # Event counter
  var eventCount = 0
  
  # Flush
  stdout.flushFile()
  
  # Main loop
  while true:
    # Check for resize
    if checkResize():
      let (newW, newH) = terminal.windowSize()
      moveCursor(1, 5)
      stdout.write(&"RESIZED to {newW}x{newH}        ")
      stdout.flushFile()
    
    # Read and parse input
    let event = terminal.readEvent(parser)
    
    case event.kind
    of EventKind.Key:
      let ke = event.keyEvent
      eventCount.inc
      
      # Check for quit
      if ke.key == Key.Rune and ke.rune == Rune('q'):
        break
      if ke.key == Key.Escape:
        break
      if ke.key == Key.CtrlC:
        break
      
      # Display event info
      moveCursor(1, 3)
      stdout.write("\x1b[36m")  # Cyan
      let eventLine = &"Event #{eventCount}: {$ke}"
      stdout.write(eventLine)
      stdout.write(spaces(60 - eventLine.len))  # Clear rest of line
      stdout.write("\x1b[0m")  # Reset
      
      # Show key visualization
      moveCursor(1, 4)
      stdout.write("\x1b[1;35m")  # Bold magenta
      let keyDisplay = case ke.key
        of Key.Rune: &"Char: '{ke.rune}'"
        of Key.Up: "Arrow: ↑"
        of Key.Down: "Arrow: ↓"
        of Key.Left: "Arrow: ←"
        of Key.Right: "Arrow: →"
        of Key.Enter: "Key: Enter"
        of Key.Tab: "Key: Tab"
        of Key.Backspace: "Key: Backspace"
        else: &"Key: {ke.key.name()}"
      
      stdout.write(keyDisplay)
      stdout.write(spaces(60 - keyDisplay.len))
      stdout.write("\x1b[0m")
      
      stdout.flushFile()
    
    of EventKind.Resize:
      # Already handled above
      discard
    
    of EventKind.Error:
      moveCursor(1, 6)
      stdout.write("\x1b[1;31m")  # Bold red
      stdout.write("ERROR: " & event.message)
      stdout.write("\x1b[0m")
      stdout.flushFile()
      break
  
  # Cleanup
  clearScreen()
  echo "Demo exited."

when isMainModule:
  main()
