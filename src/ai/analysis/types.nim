## Analysis Types Module
##
## Common type definitions used across the analysis system

import std/tables

type
  SeverityLevel* {.pure.} = enum
    ## Severity level for issues and red flags
    Pass = "PASS"
    Low = "LOW"
    Medium = "MEDIUM"
    High = "HIGH"
    Critical = "CRITICAL"

  RedFlag* = object
    ## A detected issue or anomaly in the game balance
    severity*: SeverityLevel
    title*: string
    description*: string
    impact*: string
    rootCause*: string
    evidence*: seq[string]

  StrategyStats* = object
    ## Performance statistics for a single AI strategy
    count*: int                 # Number of games played
    avgPrestige*: float         # Average final prestige
    stdPrestige*: float         # Standard deviation of prestige
    avgTreasury*: float         # Average final treasury
    avgColonies*: float         # Average number of colonies
    avgShips*: float            # Average number of ships
    avgPUGrowth*: float         # Average PU growth rate
    winRate*: float             # Percentage of games won

  StrategyReport* = object
    ## Overall analysis report for all strategies
    strategies*: Table[string, StrategyStats]
    totalGames*: int
    maxTurn*: int

  EconomyStats* = object
    ## Economic metrics analysis
    avgTreasury*: float
    avgPUGrowth*: float
    avgZeroSpendTurns*: float
    chronicZeroSpendRate*: float  # Percentage with >5 zero-spend turns

  MilitaryStats* = object
    ## Military metrics analysis
    avgTotalShips*: float
    avgTotalFighters*: float
    avgIdleCarrierRate*: float
    highIdleGamesPercent*: float

  EspionageStats* = object
    ## Espionage metrics analysis
    totalSpyMissions*: int
    totalHackMissions*: int
    gamesWithEspionagePercent*: float

  RedFlagReport* = object
    ## Collection of all detected red flags
    critical*: seq[RedFlag]
    high*: seq[RedFlag]
    medium*: seq[RedFlag]
    low*: seq[RedFlag]

  AnalysisReport* = object
    ## Complete analysis report combining all aspects
    strategyReport*: StrategyReport
    economyStats*: EconomyStats
    militaryStats*: MilitaryStats
    espionageStats*: EspionageStats
    redFlags*: RedFlagReport
    metadata*: ReportMetadata

  ReportMetadata* = object
    ## Metadata about the analysis run
    numGames*: int
    numTurns*: int
    timestamp*: string
    gitHash*: string

proc newRedFlag*(severity: SeverityLevel, title, description: string): RedFlag =
  ## Create a new RedFlag with basic information
  result = RedFlag(
    severity: severity,
    title: title,
    description: description,
    impact: "",
    rootCause: "",
    evidence: @[]
  )

proc addEvidence*(flag: var RedFlag, evidence: string) =
  ## Add evidence to a red flag
  flag.evidence.add(evidence)

proc `$`*(flag: RedFlag): string =
  ## String representation of a red flag
  result = "[" & $flag.severity & "] " & flag.title & "\n"
  result &= "  " & flag.description

proc `$`*(report: StrategyReport): string =
  ## String representation of strategy report
  result = "Strategy Performance Report\n"
  result &= "  Total games: " & $report.totalGames & "\n"
  result &= "  Max turns: " & $report.maxTurn & "\n"
  result &= "  Strategies analyzed: " & $report.strategies.len
