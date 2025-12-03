## Unified Analyzer Module
##
## Combines all analysis functions to generate complete reports.

import datamancer
import std/[times, strformat]
import ../types
import ../data/loader
import performance, red_flags

proc analyzeAll*(df: DataFrame): AnalysisReport =
  ## Run complete analysis on diagnostic data
  ##
  ## This is the main entry point for analysis. It runs:
  ## - Strategy performance analysis
  ## - Economy metrics
  ## - Military metrics
  ## - Espionage metrics
  ## - Red flag detection
  ##
  ## Args:
  ##   df: DataFrame with diagnostic data
  ##
  ## Returns:
  ##   Complete AnalysisReport
  result = AnalysisReport()

  # Strategy performance
  result.strategyReport = analyzeStrategies(df)

  # Economic analysis
  result.economyStats = analyzeEconomy(df)

  # Military analysis
  result.militaryStats = analyzeMilitary(df)

  # Espionage analysis
  result.espionageStats = analyzeEspionage(df)

  # Red flag detection
  result.redFlags = detectAll(df)

  # Metadata
  result.metadata = ReportMetadata()
  result.metadata.numGames = result.strategyReport.totalGames
  result.metadata.numTurns = result.strategyReport.maxTurn
  result.metadata.timestamp = now().format("yyyy-MM-dd HH:mm:ss")
  result.metadata.gitHash = ""  # Will be filled in by CLI if needed

proc analyzeFromCSV*(csvPath: string): AnalysisReport =
  ## Load CSV and run complete analysis
  ##
  ## Convenience function that loads a single CSV file and analyzes it.
  ##
  ## Args:
  ##   csvPath: Path to diagnostic CSV file
  ##
  ## Returns:
  ##   Complete AnalysisReport
  let df = loadDiagnostics(csvPath)
  result = analyzeAll(df)

proc analyzeFromDirectory*(dirPath: string): AnalysisReport =
  ## Load all CSVs in directory and run complete analysis
  ##
  ## Convenience function that loads all game_*.csv files from a directory
  ## and analyzes the combined data.
  ##
  ## Args:
  ##   dirPath: Path to directory containing diagnostic CSVs
  ##
  ## Returns:
  ##   Complete AnalysisReport
  let df = loadDiagnosticsDir(dirPath)
  result = analyzeAll(df)
