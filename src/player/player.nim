## EC4X TUI Player - SAM Pattern Entry
##
## Thin entry point that delegates to modular TUI app.

import std/[os, strutils]

import ../common/logger
import ./tui/app
import ./tui/launcher
import ./state/tui_cache

when isMainModule:
  enableFileLogging("data/logs/tui.log")
  disableStdoutLogging()
  let opts = parseCommandLine()

  if opts.cleanCache.len > 0:
    let mode = opts.cleanCache
    if mode == "all" or mode == "":
      let removed = deleteCacheFile()
      if removed:
        stdout.write("Cache cleared: removed cache.db\n")
      else:
        stdout.write("Cache already empty\n")
      quit(0)
    elif mode == "games":
      if clearCacheGames():
        stdout.write("Cache cleared: games\n")
      else:
        stdout.write("Cache not found\n")
      quit(0)
    elif mode.startsWith("game:"):
      let gameId = mode.split(":", 1)[1]
      if clearCacheGame(gameId):
        stdout.write("Cache cleared for game: " & gameId & "\n")
      else:
        stdout.write("Cache not found or invalid game id\n")
      quit(0)
    else:
      stdout.write("Unknown clean-cache mode: " & mode & "\n")
      quit(1)

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
