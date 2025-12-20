## Analytics Types Module
##
## Shared types for the analytics export system.
## Separated to avoid circular dependencies between modules.

import std/tables
import ./core

type
  ExportFormat* {.pure.} = enum
    CSV, Markdown, JSON, Summary

  AggregationType* {.pure.} = enum
    Mean, Median, Min, Max, StdDev, Count

  ExportFilter* = object
    houseIds*: seq[HouseId]
    turnRange*: Slice[int32]
    metrics*: seq[string]
    format*: ExportFormat

  DiagnosticRow* = object
    turn*: int32
    houseId*: HouseId  # Use typed ID, not string
    values*: Table[string, string]
