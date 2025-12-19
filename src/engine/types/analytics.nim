## Analytics Types Module
##
## Shared types for the analytics export system.
## Separated to avoid circular dependencies between modules.

import std/tables
import ../../../common/types/core

type
  ExportFormat* {.pure.} = enum
    ## Output format for exported data
    CSV           ## Full CSV (Excel/LibreOffice compatible)
    Markdown      ## Markdown tables (Claude-native format)
    JSON          ## Compact JSON (aggregated statistics)
    Summary       ## High-level summary (< 1K tokens)

  ExportFilter* = object
    ## Configuration for selective data export
    houseIds*: seq[HouseId]      ## Empty = all houses
    turnRange*: Slice[int]       ## e.g., 10..20 (inclusive)
    metrics*: seq[string]        ## Empty = all metrics
    format*: ExportFormat        ## Output format

  DiagnosticRow* = object
    ## Lightweight row representation for export
    ## Maps to DiagnosticMetrics from tests/balance/diagnostics.nim
    turn*: int
    houseId*: string
    values*: Table[string, string]  ## Metric name → value

  AggregationType* {.pure.} = enum
    ## Statistical aggregation methods
    Mean, Median, Min, Max, StdDev, Count
