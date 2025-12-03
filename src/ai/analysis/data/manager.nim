## Data Manager Module
##
## Manages organized storage of analysis outputs in balance_results/
## Handles cleanup of old data before new analysis runs.

import std/[os, times, strformat, algorithm]

type
  OutputPaths* = object
    ## Organized paths for analysis outputs (all in balance_results/)
    root*: string                    # balance_results/
    diagnosticsDir*: string          # balance_results/diagnostics/
    reportsDir*: string              # balance_results/reports/
    summariesDir*: string            # balance_results/summaries/
    archivesDir*: string             # balance_results/archives/

    # Report files
    terminalReport*: string          # reports/terminal_YYYYMMDD_HHMMSS.txt
    compactReport*: string           # reports/compact_YYYYMMDD_HHMMSS.md
    markdownReport*: string          # reports/detailed_YYYYMMDD_HHMMSS.md
    latestSymlink*: string           # reports/latest.md (symlink)

proc timestamp*(): string =
  ## Generate timestamp string for filenames
  ## Format: YYYYMMDD_HHMMSS
  let t = now()
  result = t.format("yyyyMMdd") & "_" & t.format("HHmmss")

proc initOutputPaths*(root = "balance_results"): OutputPaths =
  ## Initialize organized output paths
  ##
  ## Directory structure:
  ##   balance_results/
  ##   ├── diagnostics/      # CSV files from game runs
  ##   ├── reports/          # Analysis reports (terminal, markdown)
  ##   ├── summaries/        # Compact summaries for Claude
  ##   └── archives/         # Old data backups
  ##
  ## Args:
  ##   root: Root directory (default: balance_results)
  ##
  ## Returns:
  ##   OutputPaths with all paths configured
  result.root = root
  result.diagnosticsDir = root / "diagnostics"
  result.reportsDir = root / "reports"
  result.summariesDir = root / "summaries"
  result.archivesDir = root / "archives"

  let ts = timestamp()
  result.terminalReport = result.reportsDir / fmt"terminal_{ts}.txt"
  result.compactReport = result.summariesDir / fmt"compact_{ts}.md"
  result.markdownReport = result.reportsDir / fmt"detailed_{ts}.md"
  result.latestSymlink = result.reportsDir / "latest.md"

proc createDirectories*(paths: OutputPaths) =
  ## Create all necessary directories
  createDir(paths.root)
  createDir(paths.diagnosticsDir)
  createDir(paths.reportsDir)
  createDir(paths.summariesDir)
  createDir(paths.archivesDir)

proc cleanDiagnostics*(paths: OutputPaths, backup = true) =
  ## Clean diagnostic CSV files
  ##
  ## Args:
  ##   paths: Output paths configuration
  ##   backup: If true, archive old files before deleting
  if not dirExists(paths.diagnosticsDir):
    return

  # Backup if requested
  if backup:
    let archiveName = fmt"diagnostics_backup_{timestamp()}"
    let archivePath = paths.archivesDir / archiveName

    if dirExists(paths.diagnosticsDir):
      echo fmt"Backing up old diagnostics to {archivePath}..."
      createDir(archivePath)

      for file in walkFiles(paths.diagnosticsDir / "*.csv"):
        let filename = extractFilename(file)
        copyFile(file, archivePath / filename)

  # Clean CSV files
  echo fmt"Cleaning diagnostic CSVs from {paths.diagnosticsDir}..."
  for file in walkFiles(paths.diagnosticsDir / "game_*.csv"):
    removeFile(file)

proc cleanReports*(paths: OutputPaths, keepLatest = 5) =
  ## Clean old report files, keeping only the latest N
  ##
  ## Args:
  ##   paths: Output paths configuration
  ##   keepLatest: Number of most recent reports to keep (default: 5)

  # Clean terminal reports
  if dirExists(paths.reportsDir):
    var terminalReports: seq[tuple[path: string, time: Time]]
    for file in walkFiles(paths.reportsDir / "terminal_*.txt"):
      let info = getFileInfo(file)
      terminalReports.add((file, info.lastWriteTime))

    # Sort by time, newest first
    terminalReports.sort do (a, b: tuple[path: string, time: Time]) -> int:
      if a.time > b.time: -1
      elif a.time < b.time: 1
      else: 0

    # Remove old files
    if terminalReports.len > keepLatest:
      echo fmt"Keeping {keepLatest} most recent terminal reports..."
      for i in keepLatest ..< terminalReports.len:
        removeFile(terminalReports[i].path)

  # Clean markdown reports (same logic)
  if dirExists(paths.reportsDir):
    var mdReports: seq[tuple[path: string, time: Time]]
    for file in walkFiles(paths.reportsDir / "detailed_*.md"):
      let info = getFileInfo(file)
      mdReports.add((file, info.lastWriteTime))

    mdReports.sort do (a, b: tuple[path: string, time: Time]) -> int:
      if a.time > b.time: -1
      elif a.time < b.time: 1
      else: 0

    if mdReports.len > keepLatest:
      echo fmt"Keeping {keepLatest} most recent markdown reports..."
      for i in keepLatest ..< mdReports.len:
        removeFile(mdReports[i].path)

proc cleanSummaries*(paths: OutputPaths, keepLatest = 10) =
  ## Clean old compact summaries, keeping only the latest N
  ##
  ## Args:
  ##   paths: Output paths configuration
  ##   keepLatest: Number of summaries to keep (default: 10)

  if not dirExists(paths.summariesDir):
    return

  var summaries: seq[tuple[path: string, time: Time]]
  for file in walkFiles(paths.summariesDir / "compact_*.md"):
    let info = getFileInfo(file)
    summaries.add((file, info.lastWriteTime))

  summaries.sort do (a, b: tuple[path: string, time: Time]) -> int:
    if a.time > b.time: -1
    elif a.time < b.time: 1
    else: 0

  if summaries.len > keepLatest:
    echo fmt"Keeping {keepLatest} most recent compact summaries..."
    for i in keepLatest ..< summaries.len:
      removeFile(summaries[i].path)

proc cleanAll*(paths: OutputPaths, backupDiagnostics = true) =
  ## Clean all analysis outputs
  ##
  ## This is called before starting a new analysis run.
  ##
  ## Args:
  ##   paths: Output paths configuration
  ##   backupDiagnostics: Whether to archive old diagnostics
  echo "Cleaning old analysis data..."
  cleanDiagnostics(paths, backupDiagnostics)
  cleanReports(paths, keepLatest = 5)
  cleanSummaries(paths, keepLatest = 10)
  echo "Cleanup complete!"

proc updateLatestSymlink*(paths: OutputPaths) =
  ## Update the 'latest.md' symlink to point to the newest detailed report
  ##
  ## This provides a stable path for users to reference the most recent report.

  # Find most recent detailed report
  if not dirExists(paths.reportsDir):
    return

  var newestReport = ""
  var newestTime = fromUnix(0)

  for file in walkFiles(paths.reportsDir / "detailed_*.md"):
    let info = getFileInfo(file)
    if info.lastWriteTime > newestTime:
      newestTime = info.lastWriteTime
      newestReport = file

  if newestReport.len > 0:
    # Remove old symlink if it exists
    if fileExists(paths.latestSymlink) or symlinkExists(paths.latestSymlink):
      removeFile(paths.latestSymlink)

    # Create new symlink (relative path for portability)
    let targetFilename = extractFilename(newestReport)
    createSymlink(targetFilename, paths.latestSymlink)
    echo fmt"Updated latest.md → {targetFilename}"

proc listArchives*(paths: OutputPaths) =
  ## List all archived diagnostic backups
  if not dirExists(paths.archivesDir):
    echo "No archives found."
    return

  echo "Archived diagnostic backups:"
  var count = 0
  for dir in walkDirs(paths.archivesDir / "diagnostics_backup_*"):
    let dirName = extractFilename(dir)
    let info = getFileInfo(dir)
    let timestamp = info.lastWriteTime.format("yyyy-MM-dd HH:mm:ss")
    echo fmt"  {dirName} ({timestamp})"
    count += 1

  if count == 0:
    echo "  (none)"
  else:
    echo fmt"\nTotal: {count} archives"

proc getLatestReport*(paths: OutputPaths): string =
  ## Get path to the latest detailed report
  ##
  ## Returns:
  ##   Path to latest report, or empty string if none found
  if symlinkExists(paths.latestSymlink):
    result = paths.latestSymlink
  elif fileExists(paths.markdownReport):
    result = paths.markdownReport
  else:
    result = ""

proc saveReport*(paths: OutputPaths, content: string, format: string) =
  ## Save a report to the appropriate location
  ##
  ## Args:
  ##   paths: Output paths configuration
  ##   content: Report content
  ##   format: Report format ("terminal", "compact", "markdown")
  createDirectories(paths)

  case format
  of "terminal":
    writeFile(paths.terminalReport, content)
    echo fmt"Terminal report saved: {paths.terminalReport}"
  of "compact":
    writeFile(paths.compactReport, content)
    echo fmt"Compact summary saved: {paths.compactReport}"
  of "markdown", "detailed":
    writeFile(paths.markdownReport, content)
    echo fmt"Markdown report saved: {paths.markdownReport}"
    updateLatestSymlink(paths)
  else:
    echo fmt"Unknown report format: {format}"
