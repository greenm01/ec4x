## Data Loading Module
##
## This module provides convenient wrappers around Datamancer for loading
## diagnostic CSV files from balance test runs.

import datamancer
import std/[os, strutils, sequtils]

proc loadDiagnostics*(path: string): DataFrame =
  ## Load a single diagnostic CSV file
  ##
  ## Args:
  ##   path: Path to the diagnostic CSV file
  ##
  ## Returns:
  ##   DataFrame with diagnostic data
  if not fileExists(path):
    raise newException(IOError, "Diagnostic file not found: " & path)

  result = readCsv(path, sep = ',')

proc loadDiagnosticsDir*(dirPath: string): DataFrame =
  ## Load all diagnostic CSV files from a directory and concatenate them
  ##
  ## Args:
  ##   dirPath: Path to directory containing game_*.csv files
  ##
  ## Returns:
  ##   Combined DataFrame with all diagnostic data
  if not dirExists(dirPath):
    raise newException(IOError, "Diagnostic directory not found: " & dirPath)

  var dfs: seq[DataFrame]

  # Find all game_*.csv files
  for file in walkFiles(dirPath / "game_*.csv"):
    try:
      let df = readCsv(file, sep = ',')
      if df.len > 0:
        dfs.add(df)
    except Exception as e:
      echo "Warning: Failed to load ", file, ": ", e.msg

  if dfs.len == 0:
    raise newException(IOError, "No valid CSV files found in " & dirPath)

  # Concatenate all DataFrames vertically
  result = bind_rows(dfs)

proc filterByTurn*(df: DataFrame, turn: int): DataFrame =
  ## Filter DataFrame to specific turn
  result = df.filter(f{`turn` == turn})

proc filterByHouse*(df: DataFrame, house: string): DataFrame =
  ## Filter DataFrame to specific house
  result = df.filter(f{`house` == house})

proc filterByStrategy*(df: DataFrame, strategy: string): DataFrame =
  ## Filter DataFrame to specific strategy
  result = df.filter(f{`strategy` == strategy})

proc getFinalTurnData*(df: DataFrame): DataFrame =
  ## Get data from the final turn of each game
  ## This is useful for analyzing end-game states
  let maxTurn = df["turn", int].max()
  result = df.filter(f{`turn` == maxTurn})

proc getColumnNames*(df: DataFrame): seq[string] =
  ## Get list of all column names in the DataFrame
  result = df.getKeys()

proc info*(df: DataFrame): string =
  ## Get summary information about the DataFrame
  ## Returns a human-readable string with shape and column info
  let nRows = df.len
  let nCols = df.getKeys().len
  result = "DataFrame with " & $nCols & " columns and " & $nRows & " rows"
