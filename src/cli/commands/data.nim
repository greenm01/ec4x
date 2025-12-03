## Data Management Command Module
##
## Implements data management subcommands (clean, list, etc.)

import std/[os, strformat, strutils]
import ../../ai/analysis/data/manager

proc clean*(backup = true, keepReports = 5, keepSummaries = 10): int =
  ## Clean old analysis data
  ##
  ## Args:
  ##   backup: Archive old diagnostics before deleting
  ##   keepReports: Number of detailed reports to keep
  ##   keepSummaries: Number of compact summaries to keep
  ##
  ## Returns:
  ##   Exit code (0 = success)

  let paths = initOutputPaths()

  echo "Cleaning analysis data..."
  echo fmt"  Backup diagnostics: {backup}"
  echo fmt"  Keep reports: {keepReports}"
  echo fmt"  Keep summaries: {keepSummaries}"
  echo ""

  try:
    if dirExists(paths.diagnosticsDir):
      cleanDiagnostics(paths, backup)

    if dirExists(paths.reportsDir):
      cleanReports(paths, keepReports)

    if dirExists(paths.summariesDir):
      cleanSummaries(paths, keepSummaries)

    echo "\n✓ Cleanup complete!"
    return 0
  except Exception as e:
    echo fmt"Error during cleanup: {e.msg}"
    return 1

proc cleanAll*(backup = true): int =
  ## Clean ALL analysis data (diagnostics, reports, summaries)
  ##
  ## This is called automatically before new analysis runs.
  ##
  ## Args:
  ##   backup: Archive old diagnostics before deleting
  ##
  ## Returns:
  ##   Exit code (0 = success)

  let paths = initOutputPaths()

  try:
    cleanAll(paths, backup)
    return 0
  except Exception as e:
    echo fmt"Error during cleanup: {e.msg}"
    return 1

proc listArchives*(): int =
  ## List all archived diagnostic backups
  ##
  ## Returns:
  ##   Exit code (0 = success)

  let paths = initOutputPaths()

  try:
    listArchives(paths)
    return 0
  except Exception as e:
    echo fmt"Error listing archives: {e.msg}"
    return 1

proc info*(): int =
  ## Show information about current analysis data
  ##
  ## Returns:
  ##   Exit code (0 = success)

  let paths = initOutputPaths()

  echo "EC4X Analysis Data Status"
  echo "=".repeat(60)
  echo ""

  # Diagnostics
  if dirExists(paths.diagnosticsDir):
    var csvCount = 0
    for _ in walkFiles(paths.diagnosticsDir / "game_*.csv"):
      csvCount += 1
    echo fmt"Diagnostics: {csvCount} CSV files in {paths.diagnosticsDir}"
  else:
    echo fmt"Diagnostics: (none) - directory does not exist"

  # Reports
  if dirExists(paths.reportsDir):
    var terminalCount = 0
    var markdownCount = 0
    for _ in walkFiles(paths.reportsDir / "terminal_*.txt"):
      terminalCount += 1
    for _ in walkFiles(paths.reportsDir / "detailed_*.md"):
      markdownCount += 1

    echo fmt"Reports: {terminalCount} terminal, {markdownCount} markdown in {paths.reportsDir}"

    # Latest report
    let latest = getLatestReport(paths)
    if latest.len > 0:
      echo fmt"  Latest: {latest}"
  else:
    echo "Reports: (none)"

  # Summaries
  if dirExists(paths.summariesDir):
    var summaryCount = 0
    for _ in walkFiles(paths.summariesDir / "compact_*.md"):
      summaryCount += 1
    echo fmt"Summaries: {summaryCount} compact summaries in {paths.summariesDir}"
  else:
    echo "Summaries: (none)"

  # Archives
  if dirExists(paths.archivesDir):
    var archiveCount = 0
    for _ in walkDirs(paths.archivesDir / "diagnostics_backup_*"):
      archiveCount += 1
    echo fmt"Archives: {archiveCount} backups in {paths.archivesDir}"
  else:
    echo "Archives: (none)"

  echo ""
  echo "=".repeat(60)

  return 0
