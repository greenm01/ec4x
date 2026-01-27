## Development Cleanup & Setup Tool
##
## Automates the full development workflow:
## 1. Clears player cache and game data
## 2. Creates a new game
## 3. Displays invite codes
##
## Usage:
##   nim r tools/clean_dev.nim              # Full workflow: clean + create game + show invites
##   nim r tools/clean_dev.nim --clean      # Clean only (no game creation)
##   nim r tools/clean_dev.nim --cache      # Clear only player cache
##   nim r tools/clean_dev.nim --data       # Clear only game/player data
##   nim r tools/clean_dev.nim --dry-run    # Show what would be deleted

import std/[os, strutils, osproc]

const
  CacheDir = ".local/share/ec4x"
  CacheFile = "cache.db"
  DataGamesDir = "data/games"
  DataPlayersDir = "data/players"
  DataLogsDir = "data/logs"

type
  RunMode = enum
    FullWorkflow # Clean + create game + show invites
    CleanOnly    # Clean everything (no game creation)
    CacheOnly    # Clean only player cache
    DataOnly     # Clean only game/player data

proc getCachePath(): string =
  ## Get the full cache database path
  getHomeDir() / CacheDir / CacheFile

proc clearCache(dryRun: bool): tuple[success: bool, message: string] =
  ## Clear the player cache database
  let cachePath = getCachePath()

  if fileExists(cachePath):
    if dryRun:
      return (true, "Would delete: " & cachePath)
    else:
      try:
        removeFile(cachePath)
        return (true, "✓ Deleted cache: " & cachePath)
      except OSError as e:
        return (false, "✗ Failed to delete cache: " & e.msg)
  else:
    return (true, "• Cache already empty: " & cachePath)

proc clearDirectory(dir: string, dryRun: bool): tuple[success: bool, message: string] =
  ## Clear all contents of a directory
  if not dirExists(dir):
    return (true, "• Directory doesn't exist: " & dir)

  var deletedCount = 0
  var failedCount = 0
  var items: seq[string] = @[]

  # Collect items to delete
  for kind, path in walkDir(dir):
    if path.extractFilename() notin ["README.md", ".gitkeep"]:
      items.add(path)

  if items.len == 0:
    return (true, "• Directory already empty: " & dir)

  if dryRun:
    var msg = "Would delete " & $items.len & " item(s) from " & dir & ":"
    for item in items:
      msg &= "\n  - " & item
    return (true, msg)

  # Delete items
  for item in items:
    try:
      if dirExists(item):
        removeDir(item)
      else:
        removeFile(item)
      deletedCount.inc
    except OSError as e:
      stderr.writeLine("  Warning: Failed to delete " & item & ": " & e.msg)
      failedCount.inc

  let status = if failedCount == 0: "✓" else: "⚠"
  let msg = status & " Deleted " & $deletedCount & " item(s) from " & dir
  let success = failedCount == 0

  return (success, msg)

proc clearLogFiles(dryRun: bool): tuple[success: bool, message: string] =
  ## Clear log files but keep the directory
  if not dirExists(DataLogsDir):
    return (true, "• Logs directory doesn't exist")

  var deletedCount = 0
  var logFiles: seq[string] = @[]

  for kind, path in walkDir(DataLogsDir):
    if kind == pcFile and path.endsWith(".log"):
      logFiles.add(path)

  if logFiles.len == 0:
    return (true, "• No log files to clear")

  if dryRun:
    var msg = "Would delete " & $logFiles.len & " log file(s):"
    for file in logFiles:
      msg &= "\n  - " & file
    return (true, msg)

  for file in logFiles:
    try:
      removeFile(file)
      deletedCount.inc
    except OSError:
      discard

  return (true, "✓ Deleted " & $deletedCount & " log file(s)")

proc ensureBinary(name: string): bool =
  ## Check if binary exists, compile if needed
  let binPath = "bin" / name
  if fileExists(binPath):
    return true

  echo "Binary not found, compiling " & name & "..."
  let compileCmd =
    case name
    of "ec4x":
      "nim c -d:release --opt:speed --deepcopy:on -o:bin/ec4x src/moderator/moderator.nim"
    else:
      ""

  if compileCmd.len == 0:
    return false

  let (output, exitCode) = execCmdEx(compileCmd)
  if exitCode != 0:
    echo "Failed to compile " & name & ":"
    echo output
    return false

  return fileExists(binPath)

proc createNewGame(scenario: string = "scenarios/standard-4-player.kdl"): tuple[
    success: bool, gameSlug: string] =
  ## Create a new game and return the game slug
  if not ensureBinary("ec4x"):
    return (false, "")

  echo "Creating new game from " & scenario & "..."
  let cmd = "bin/ec4x new --scenario=" & scenario
  let (output, exitCode) = execCmdEx(cmd)

  if exitCode != 0:
    echo "Failed to create game:"
    echo output
    return (false, "")

  # Extract game slug from output (format: "Game created: {slug}")
  var gameSlug = ""
  for line in output.splitLines():
    if line.startsWith("Game created:"):
      gameSlug = line.split(":", 1)[1].strip()
      break

  if gameSlug.len == 0:
    # Try to find the last line with a game name
    let lines = output.strip().splitLines()
    if lines.len > 0:
      gameSlug = lines[^1].strip()

  if gameSlug.len > 0:
    echo "✓ Game created: " & gameSlug
    return (true, gameSlug)
  else:
    echo "Game created but couldn't extract slug"
    echo output
    return (false, "")

proc showInviteCodes(gameSlug: string): bool =
  ## Display invite codes for a game
  if not ensureBinary("ec4x"):
    return false

  echo ""
  echo "Invite codes:"
  echo "=" & "=".repeat(50)

  let cmd = "bin/ec4x invite " & gameSlug
  let (output, exitCode) = execCmdEx(cmd)

  if exitCode != 0:
    echo "Failed to get invite codes:"
    echo output
    return false

  echo output
  return true

proc showHelp() =
  echo """
EC4X Development Cleanup & Setup Tool

Automates the full development workflow for quick iteration.

Usage:
  nim r tools/clean_dev.nim [OPTIONS]

Options:
  --clean      Clean everything but don't create new game
  --cache      Clear only player cache (~/.local/share/ec4x/cache.db)
  --data       Clear only game/player data (data/games, data/players)
  --scenario   Specify scenario file (default: scenarios/standard-4-player.kdl)
  --dry-run    Show what would be deleted without actually deleting
  --logs       Also clear log files
  --help       Show this help message

Default Workflow (no options):
  1. Clear player cache
  2. Clear game/player data
  3. Create new game from scenario
  4. Display invite codes

Examples:
  nim r tools/clean_dev.nim                        # Full workflow
  nim r tools/clean_dev.nim --clean                # Clean only, no game
  nim r tools/clean_dev.nim --scenario=my.kdl      # Use custom scenario
  nim r tools/clean_dev.nim --dry-run              # Preview changes
  nim r tools/clean_dev.nim --cache                # Clear cache only
"""

proc main() =
  var mode = FullWorkflow
  var dryRun = false
  var clearLogs = false
  var scenario = "scenarios/standard-4-player.kdl"

  # Parse command line arguments
  for arg in commandLineParams():
    if arg.startsWith("--scenario="):
      scenario = arg.split("=", 1)[1]
    else:
      case arg
      of "--clean":
        mode = CleanOnly
      of "--cache":
        mode = CacheOnly
      of "--data":
        mode = DataOnly
      of "--dry-run", "--dry":
        dryRun = true
      of "--logs":
        clearLogs = true
      of "--help", "-h":
        showHelp()
        quit(0)
      else:
        echo "Unknown option: ", arg
        echo "Use --help for usage information"
        quit(1)

  # Print header
  let headerText =
    if mode == FullWorkflow: "EC4X Development Workflow"
    else: "EC4X Development Cleanup"
  echo ""
  echo headerText
  echo "=" & "=".repeat(50)
  if dryRun:
    echo "[DRY RUN - No files will be deleted]"
  echo ""

  var allSuccess = true
  var results: seq[string] = @[]

  # Clear based on mode
  case mode
  of FullWorkflow, CleanOnly:
    echo "Cleaning everything..."
    echo ""

    # Clear cache
    let (cacheOk, cacheMsg) = clearCache(dryRun)
    results.add(cacheMsg)
    allSuccess = allSuccess and cacheOk

    # Clear game data
    let (gamesOk, gamesMsg) = clearDirectory(DataGamesDir, dryRun)
    results.add(gamesMsg)
    allSuccess = allSuccess and gamesOk

    # Clear player data
    let (playersOk, playersMsg) = clearDirectory(DataPlayersDir, dryRun)
    results.add(playersMsg)
    allSuccess = allSuccess and playersOk

    # Clear logs if requested
    if clearLogs:
      let (logsOk, logsMsg) = clearLogFiles(dryRun)
      results.add(logsMsg)
      allSuccess = allSuccess and logsOk

  of CacheOnly:
    echo "Cleaning player cache only..."
    echo ""

    let (ok, msg) = clearCache(dryRun)
    results.add(msg)
    allSuccess = ok

  of DataOnly:
    echo "Cleaning game/player data only..."
    echo ""

    # Clear game data
    let (gamesOk, gamesMsg) = clearDirectory(DataGamesDir, dryRun)
    results.add(gamesMsg)
    allSuccess = allSuccess and gamesOk

    # Clear player data
    let (playersOk, playersMsg) = clearDirectory(DataPlayersDir, dryRun)
    results.add(playersMsg)
    allSuccess = allSuccess and playersOk

    # Clear logs if requested
    if clearLogs:
      let (logsOk, logsMsg) = clearLogFiles(dryRun)
      results.add(logsMsg)
      allSuccess = allSuccess and logsOk

  # Print results
  for result in results:
    echo result

  echo ""

  # Game creation workflow (only if FullWorkflow and not dry-run)
  if mode == FullWorkflow and not dryRun:
    if allSuccess:
      echo ""
      echo "=" & "=".repeat(50)
      let (gameOk, gameSlug) = createNewGame(scenario)
      if gameOk and gameSlug.len > 0:
        if not showInviteCodes(gameSlug):
          allSuccess = false
      else:
        allSuccess = false
    else:
      echo "Skipping game creation due to cleanup errors"

  # Summary
  echo ""
  if dryRun:
    echo "Dry run complete. Use without --dry-run to actually delete."
  elif mode == FullWorkflow:
    if allSuccess:
      echo "Workflow complete! You can now start testing."
    else:
      echo "Workflow completed with some errors (see above)"
  else:
    if allSuccess:
      echo "Cleanup complete!"
    else:
      echo "Cleanup completed with some warnings (see above)"

  quit(if allSuccess: 0 else: 1)

when isMainModule:
  main()
