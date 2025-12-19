## Claude-Optimized Export Formats
##
## Token-efficient data formats designed specifically for Claude analysis:
## - Markdown tables (Claude's native format, best for parsing)
## - Compact JSON (aggregated statistics, minimal tokens)
## - Summary format (high-level overview, < 1K tokens)
##
## Design Goals:
## - Reduce 2-5M token CSV files to <12K tokens
## - Preserve essential information while minimizing verbosity
## - Use formats Claude parses best (Markdown > JSON > CSV)
##
## Token Efficiency Examples:
## - Full CSV:  5 MB, 2-5M tokens
## - Markdown:  10 KB, 2.5K tokens (99.9% reduction)
## - JSON:      5 KB, 1K tokens (99.95% reduction)
## - Summary:   2 KB, 500 tokens (99.99% reduction)

import std/[tables, strformat, strutils, streams, algorithm, math, json, sequtils]
import ../../types/analytics as types

export types  # Re-export types for users of this module

# Forward declarations for functions we'll use
proc getFilteredMetrics*(filter: ExportFilter, allMetrics: seq[string]): seq[string]
proc matchesFilter*(row: DiagnosticRow, filter: ExportFilter): bool

# ============================================================================
# Markdown Table Export (Claude's Native Format)
# ============================================================================

proc generateMarkdownHeader*(metrics: seq[string]): string =
  ## Generate markdown table header row
  ## Example: | Turn | House | Fighters | Destroyers |
  result = "| Turn | House |"
  for metric in metrics:
    result.add(&" {metric} |")

proc generateMarkdownSeparator*(metrics: seq[string]): string =
  ## Generate markdown table separator row
  ## Example: |------|-------|----------|------------|
  result = "|------|-------|"
  for _ in metrics:
    result.add("----------|")

proc generateMarkdownRow*(row: DiagnosticRow, metrics: seq[string]): string =
  ## Generate markdown table data row
  ## Example: | 10 | Alpha | 12 | 5 |
  result = &"| {row.turn} | {row.houseId} |"
  for metric in metrics:
    let value = row.values.getOrDefault(metric, "")
    result.add(&" {value} |")

proc exportToMarkdown*(outputPath: string, data: seq[DiagnosticRow], filter: ExportFilter) =
  ## Export diagnostic data as markdown table
  ##
  ## Advantages for Claude:
  ## - Native format (Claude parses markdown tables best)
  ## - Visual structure preserved
  ## - Token-efficient (whitespace minimized)
  ## - Easy to add annotations (⚠️ for anomalies)

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

  # Write title
  stream.writeLine(&"# Diagnostic Data Export")
  stream.writeLine()
  stream.writeLine(&"**Turns:** {filter.turnRange.a}-{filter.turnRange.b}")

  let housesDisplay = if filter.houseIds.len == 0: "All" else: filter.houseIds.mapIt($it).join(", ")
  stream.writeLine(&"**Houses:** {housesDisplay}")
  stream.writeLine(&"**Metrics:** {metricsToExport.len}")
  stream.writeLine()

  # Write table header
  stream.writeLine(generateMarkdownHeader(metricsToExport))
  stream.writeLine(generateMarkdownSeparator(metricsToExport))

  # Write data rows
  var rowCount = 0
  for row in data:
    if not matchesFilter(row, filter):
      continue

    stream.writeLine(generateMarkdownRow(row, metricsToExport))
    rowCount += 1

  stream.writeLine()
  stream.writeLine(&"*{rowCount} rows exported*")

# ============================================================================
# Statistical Aggregation
# ============================================================================

proc calculateMean*(values: seq[float]): float =
  ## Calculate mean (average) of values
  if values.len == 0:
    return 0.0
  result = values.sum() / float(values.len)

proc calculateMedian*(values: seq[float]): float =
  ## Calculate median (middle value) of values
  if values.len == 0:
    return 0.0

  var sorted = values
  sorted.sort()

  let mid = values.len div 2
  if values.len mod 2 == 0:
    result = (sorted[mid - 1] + sorted[mid]) / 2.0
  else:
    result = sorted[mid]

proc calculateStdDev*(values: seq[float]): float =
  ## Calculate standard deviation
  if values.len == 0:
    return 0.0

  let mean = calculateMean(values)
  var variance = 0.0
  for value in values:
    variance += pow(value - mean, 2)
  variance = variance / float(values.len)
  result = sqrt(variance)

proc detectOutliers*(values: seq[float], threshold: float = 3.0): seq[int] =
  ## Detect outliers using z-score method
  ## Returns indices of values beyond threshold standard deviations
  result = @[]

  if values.len < 3:
    return

  let mean = calculateMean(values)
  let stdDev = calculateStdDev(values)

  if stdDev == 0.0:
    return

  for i, value in values:
    let zScore = abs((value - mean) / stdDev)
    if zScore > threshold:
      result.add(i)

# ============================================================================
# Compact JSON Export (Aggregated Statistics)
# ============================================================================

proc aggregateMetric*(data: seq[DiagnosticRow], metric: string): JsonNode =
  ## Aggregate a single metric across all rows
  ## Returns JSON with mean, median, min, max, stddev

  var values: seq[float] = @[]
  for row in data:
    if row.values.hasKey(metric):
      try:
        values.add(parseFloat(row.values[metric]))
      except:
        discard  # Skip non-numeric values

  if values.len == 0:
    return %* {"error": "No numeric values found"}

  result = %* {
    "count": values.len,
    "mean": calculateMean(values),
    "median": calculateMedian(values),
    "min": values.min(),
    "max": values.max(),
    "stddev": calculateStdDev(values)
  }

proc findAnomalies*(data: seq[DiagnosticRow], metric: string, threshold: float = 3.0): seq[JsonNode] =
  ## Find anomalous values for a metric using z-score
  result = @[]

  var values: seq[float] = @[]
  for row in data:
    if row.values.hasKey(metric):
      try:
        values.add(parseFloat(row.values[metric]))
      except:
        values.add(0.0)
    else:
      values.add(0.0)

  let outlierIndices = detectOutliers(values, threshold)

  for idx in outlierIndices:
    if idx < data.len:
      let row = data[idx]
      result.add(%* {
        "turn": row.turn,
        "house": row.houseId,
        "metric": metric,
        "value": values[idx],
        "z_score": abs((values[idx] - calculateMean(values)) / calculateStdDev(values))
      })

proc exportToJSON*(outputPath: string, data: seq[DiagnosticRow], filter: ExportFilter, includeAnomalies: bool = true) =
  ## Export diagnostic data as compact JSON with aggregated statistics
  ##
  ## Advantages for Claude:
  ## - Structured data format
  ## - Statistical summaries (mean, median, etc.)
  ## - Anomaly detection included
  ## - Highly token-efficient (no repetition)

  if data.len == 0:
    return

  # Filter data first
  var filteredData: seq[DiagnosticRow] = @[]
  for row in data:
    if matchesFilter(row, filter):
      filteredData.add(row)

  # Determine which metrics to export
  let allMetrics = toSeq(data[0].values.keys).sorted()
  let metricsToExport = getFilteredMetrics(filter, allMetrics)

  # Build JSON structure
  let housesJson = if filter.houseIds.len == 0:
    %"all"
  else:
    %(filter.houseIds.mapIt($it))

  var jsonOutput = %* {
    "summary": {
      "turn_range": [filter.turnRange.a, filter.turnRange.b],
      "houses": housesJson,
      "total_rows": filteredData.len,
      "metrics_count": metricsToExport.len
    },
    "metrics": newJObject()
  }

  # Aggregate each metric
  for metric in metricsToExport:
    jsonOutput["metrics"][metric] = aggregateMetric(filteredData, metric)

  # Add anomalies if requested
  if includeAnomalies:
    var anomalies = newJArray()
    for metric in metricsToExport:
      let metricAnomalies = findAnomalies(filteredData, metric, threshold = 3.0)
      for anomaly in metricAnomalies:
        anomalies.add(anomaly)

    jsonOutput["anomalies"] = anomalies

  # Write to file
  writeFile(outputPath, jsonOutput.pretty(indent = 2))

# ============================================================================
# Summary Export (High-Level Overview)
# ============================================================================

proc generateSummary*(data: seq[DiagnosticRow], filter: ExportFilter): string =
  ## Generate a high-level text summary (< 1K tokens)
  ##
  ## Includes:
  ## - Data overview (turn range, houses, metrics)
  ## - Key statistics (means, trends)
  ## - Top anomalies (outliers)
  ## - Balance concerns (if any)

  let housesDisplay = if filter.houseIds.len == 0: "All" else: filter.houseIds.mapIt($it).join(", ")

  result = &"""# EC4X Diagnostic Summary

## Overview
- **Turn Range:** {filter.turnRange.a}-{filter.turnRange.b}
- **Houses:** {housesDisplay}
- **Total Data Points:** {data.len}

## Key Metrics

"""

  # Filter data first
  var filteredData: seq[DiagnosticRow] = @[]
  for row in data:
    if matchesFilter(row, filter):
      filteredData.add(row)

  if filteredData.len == 0:
    result.add("*No data matches filter criteria*\n")
    return

  # Get top metrics
  let allMetrics = toSeq(filteredData[0].values.keys).sorted()
  let metricsToExport = getFilteredMetrics(filter, allMetrics)

  # Sample a few important metrics
  let importantMetrics = @["treasuryBalance", "fighterShips", "techWEP", "spaceCombatWins"]
  for metric in importantMetrics:
    if metric in metricsToExport:
      let aggregated = aggregateMetric(filteredData, metric)
      if aggregated.hasKey("mean"):
        result.add(&"- **{metric}:** mean={aggregated[\"mean\"].getFloat():.1f}, ")
        result.add(&"min={aggregated[\"min\"].getFloat():.1f}, ")
        result.add(&"max={aggregated[\"max\"].getFloat():.1f}\n")

  result.add("\n## Anomalies Detected\n\n")

  # Find anomalies across all metrics
  var totalAnomalies = 0
  for metric in metricsToExport:
    let anomalies = findAnomalies(filteredData, metric, threshold = 3.0)
    totalAnomalies += anomalies.len
    if anomalies.len > 0:
      result.add(&"- **{metric}:** {anomalies.len} outliers detected\n")

  if totalAnomalies == 0:
    result.add("*No significant anomalies detected*\n")

  result.add(&"\n*Summary generated from {filteredData.len} data points*\n")

proc exportToSummary*(outputPath: string, data: seq[DiagnosticRow], filter: ExportFilter) =
  ## Export diagnostic data as text summary
  ##
  ## Advantages for Claude:
  ## - Highest token efficiency (< 1K tokens)
  ## - Natural language format
  ## - Focuses on insights, not raw data
  ## - Perfect for initial assessment

  let summary = generateSummary(data, filter)
  writeFile(outputPath, summary)

# ============================================================================
# Utility Functions (shared with smart_export.nim)
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
# Integration with smart_export.nim
# ============================================================================

# Export these functions for use in smart_export.nim
export exportToMarkdown, exportToJSON, exportToSummary

# ============================================================================
# Usage Examples
# ============================================================================
##
## Example 1: Markdown table for turn analysis
##   let filter = createFilter(
##     houses = @[HouseId.Alpha],
##     turnStart = 10,
##     turnEnd = 15,
##     metrics = @["fighterShips", "destroyerShips", "spaceCombatWins"],
##     format = Markdown
##   )
##   exportToMarkdown("turn_analysis.md", diagnostics, filter)
##
## Example 2: JSON summary for balance check
##   let filter = createFilter(
##     houses = @[],  # All houses
##     turnStart = 1,
##     turnEnd = 30,
##     metrics = @["fighterShips", "destroyerShips", "cruiserShips"],
##     format = JSON
##   )
##   exportToJSON("balance_check.json", diagnostics, filter)
##
## Example 3: Quick summary for Claude
##   let filter = createFilter(
##     houses = @[],
##     turnStart = 1,
##     turnEnd = 30,
##     metrics = @[],  # All metrics
##     format = Summary
##   )
##   exportToSummary("quick_summary.txt", diagnostics, filter)
##
## Token Counts:
## - turn_analysis.md:    ~500 tokens (5 turns × 3 metrics)
## - balance_check.json:  ~800 tokens (aggregated, all houses)
## - quick_summary.txt:   ~300 tokens (text summary)
