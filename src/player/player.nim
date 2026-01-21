## EC4X TUI Player - SAM Pattern Entry
##
## Thin entry point that delegates to modular TUI app.

import std/[os, strutils]

import ../common/logger
import ./tui/app
import ./tui/launcher

when isMainModule:
  enableFileLogging("data/logs/tui.log")
  disableStdoutLogging()
  let opts = parseCommandLine()

  if opts.showHelp:
    showHelp()
    quit(0)

  # Launcher integration: spawn new window if enabled and possible
  if opts.spawnWindow and shouldLaunchInNewWindow():
    let binary = getAppFilename()
    if launchInNewWindow(binary, @["--no-spawn-window"]):
      # Parent process exits, child runs TUI
      quit(0)
    else:
      # Launcher failed (no emulator found)
      stdout.write(
        "Warning: No terminal emulator found, running in current terminal\n\n"
      )

  # Check terminal size before proceeding
  let (w, h) = getCurrentTerminalSize()
  let (ok, msg) = isTerminalSizeOk(w, h)
  if not ok:
    stdout.write("Error: " & msg & "\n\n")
    stdout.write("Minimum terminal size: 80x24 (compact)\n")
    stdout.write("Recommended size: 120x32 (full layout)\n")
    quit(1)
  elif msg.contains("smaller than optimal"):
    stdout.write("Note: " & msg & "\n\n")

  # Run TUI
  runTui(opts.gameId)
