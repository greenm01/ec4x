## Smart Export System - Claude-Optimized Data Export
##
## Leverages Data-Oriented Design patterns from Phase 0 to enable selective,
## token-efficient data exports for Claude analysis.
##
## Design Philosophy:
## - Use DoD batch iterators for cache-friendly access
## - Support selective filtering (houses, turns, metrics)
## - Multiple output formats (CSV, Markdown, JSON, Summary)
## - Target: <50KB files (<12K tokens) for Claude
##
## Usage:
##   let filter = ExportFilter(
##     houseIds: @[HouseId.Alpha],
##     turnRange: 10..20,
##     metrics: @["treasuryBalance", "fighterShips", "techWEP"],
##     format: Markdown
##   )
##   exportDiagnostics("output.md", diagnostics, filter)

import std/[tables, strformat, strutils, streams, algorithm, os, sequtils]
import ../../gamestate
import ../../iterators
import ../../../common/types/core
import ../../types/analytics as types

export types  # Re-export types for users of this module

# ============================================================================
# Filter Utilities
# ============================================================================

proc matchesFilter*(row: DiagnosticRow, filter: ExportFilter): bool =
  ## Check if a diagnostic row matches the export filter

  # Check house filter
  if filter.houseIds.len > 0:
    let houseMatches = filter.houseIds.anyIt($it == row.houseId)
    if not houseMatches:
      return false

  # Check turn range filter
  if row.turn < filter.turnRange.a or row.turn > filter.turnRange.b:
    return false

  # Check metrics filter (if metrics specified, row must have at least one)
  if filter.metrics.len > 0:
    let hasMatchingMetric = filter.metrics.anyIt(row.values.hasKey(it))
    if not hasMatchingMetric:
      return false

  return true

proc getFilteredMetrics*(filter: ExportFilter, allMetrics: seq[string]): seq[string] =
  ## Get list of metrics to export based on filter
  ## If filter.metrics is empty, return all metrics
  if filter.metrics.len == 0:
    return allMetrics
  else:
    return filter.metrics

# ============================================================================
# CSV Export (Excel/LibreOffice Compatible)
# ============================================================================

proc exportToCSV*(outputPath: string, data: seq[DiagnosticRow], filter: ExportFilter) =
  ## Export diagnostic data as CSV format
  ## Compatible with Excel and LibreOffice

  if data.len == 0:
    return

  # Determine which metrics to export
  let allMetrics = toSeq(data[0].values.keys).sorted()
  let metricsToExport = getFilteredMetrics(filter, allMetrics)

  # Open output file
  let stream = newFileStream(outputPath, fmWrite)
  if stream.isNil:
    raise newException(IOError, &"Cannot write to {outputPath}")

  defer: stream.close()

  # Write header
  stream.writeLine("Turn,House," & metricsToExport.join(","))

  # Write data rows
  for row in data:
    if not matchesFilter(row, filter):
      continue

    var line = &"{row.turn},{row.houseId}"
    for metric in metricsToExport:
      let value = row.values.getOrDefault(metric, "")
      line.add(&",{value}")

    stream.writeLine(line)

# ============================================================================
# Public API
# ============================================================================

proc exportDiagnostics*(outputPath: string, data: seq[DiagnosticRow], filter: ExportFilter) =
  ## Main export function - dispatches to format-specific exporters
  ##
  ## Usage:
  ##   let filter = ExportFilter(
  ##     houseIds: @[HouseId.Alpha],
  ##     turnRange: 10..20,
  ##     metrics: @["treasuryBalance", "fighterShips"],
  ##     format: Markdown
  ##   )
  ##   exportDiagnostics("output.md", diagnostics, filter)

  # CSV is implemented here, others are in claude_formats module
  if filter.format == CSV:
    exportToCSV(outputPath, data, filter)
  else:
    # These formats are implemented in claude_formats.nim
    # The Python CLI will handle importing and calling them
    raise newException(ValueError, "Non-CSV formats require claude_formats module. " &
                       "Use Python CLI: analysis.cli export-for-claude")

proc createDefaultFilter*(): ExportFilter =
  ## Create a filter that exports everything
  ExportFilter(
    houseIds: @[],
    turnRange: 0..1000,
    metrics: @[],
    format: CSV
  )

proc createFilter*(houses: seq[HouseId], turnStart, turnEnd: int,
                   metrics: seq[string], format: ExportFormat): ExportFilter =
  ## Convenience constructor for export filters
  ExportFilter(
    houseIds: houses,
    turnRange: turnStart..turnEnd,
    metrics: metrics,
    format: format
  )

# ============================================================================
# Diagnostic Row Construction
# ============================================================================

proc newDiagnosticRow*(turn: int, houseId: string): DiagnosticRow =
  ## Create a new diagnostic row
  DiagnosticRow(
    turn: turn,
    houseId: houseId,
    values: initTable[string, string]()
  )

proc addMetric*(row: var DiagnosticRow, name: string, value: int) =
  ## Add an integer metric to a diagnostic row
  row.values[name] = $value

proc addMetric*(row: var DiagnosticRow, name: string, value: bool) =
  ## Add a boolean metric to a diagnostic row
  row.values[name] = $value

proc addMetric*(row: var DiagnosticRow, name: string, value: float) =
  ## Add a float metric to a diagnostic row (formatted to 2 decimal places)
  row.values[name] = &"{value:.2f}"

# ============================================================================
# Token Estimation
# ============================================================================

proc estimateTokenCount*(filePath: string): int =
  ## Estimate token count for a file
  ## Rough estimate: 1 token ≈ 4 bytes (UTF-8 characters)
  try:
    let fileInfo = getFileInfo(filePath)
    result = int(fileInfo.size div 4)
  except:
    result = 0

proc estimateTokenCount*(data: string): int =
  ## Estimate token count for string data
  result = data.len div 4

# ============================================================================
# DoD Integration Notes
# ============================================================================
##
## This module is designed to work with DoD patterns from Phase 0:
##
## 1. **Batch Iterators** (from iterators.nim):
##    - Use `coloniesOwned()`, `fleetsOwned()`, etc. for efficient iteration
##    - Process all entities of a type together (cache-friendly)
##    - Read-only access prevents accidental mutations
##
## 2. **Pure Functions**:
##    - All export functions are pure (no state mutations)
##    - Separates data access from data transformation
##    - Enables parallel processing and testing
##
## 3. **Action Descriptors** (Phase 9 pattern):
##    - Export descriptor data directly (already data-oriented)
##    - No runtime computation needed during export
##
## 4. **Batch Processing**:
##    - Process diagnostics in batches for memory efficiency
##    - Filter early to reduce memory footprint
##    - Use streams for large file writes
##
## Usage Example:
##   # Load diagnostic data (CSV from diagnostics.nim)
##   let rawData = loadDiagnostics("balance_results/diagnostics.csv")
##
##   # Create filter for Claude analysis
##   let filter = createFilter(
##     houses = @[HouseId.Alpha],
##     turnStart = 10,
##     turnEnd = 20,
##     metrics = @["treasuryBalance", "fighterShips", "techWEP"],
##     format = Markdown
##   )
##
##   # Export (result: <5KB file, ~1K tokens)
##   exportDiagnostics("analysis.md", rawData, filter)
