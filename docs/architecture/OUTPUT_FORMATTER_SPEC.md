# EC4X Analysis Output Formatter Specification

## Design Goals

1. **Human-friendly terminal output** - Rich, colorful, well-formatted reports for developers
2. **Token-efficient AI summaries** - Compact markdown for Claude analysis (<2000 tokens)
3. **Machine-readable exports** - JSON/CSV for external tools
4. **Progressive disclosure** - Quick summaries with drill-down options

## Output Modes

### 1. Terminal Mode (Human)
**Target audience:** Developers running analysis during development
**Output:** Rich terminal formatting with colors, tables, emojis, progress bars

### 2. Compact Mode (AI)
**Target audience:** Claude Code for quick analysis
**Output:** Markdown tables, concise summaries, ~1500 tokens max

### 3. Detailed Mode (Reports)
**Target audience:** Documentation, git commits
**Output:** Full markdown reports with charts, 5000-10000 tokens

### 4. Export Mode (Data)
**Target audience:** External tools (Excel, R, Python notebooks)
**Output:** CSV, JSON, Parquet files

## Terminal Output Examples

### Example 1: Strategy Performance Analysis
```
================================================================================
📊 RBA PERFORMANCE SUMMARY (100 Games, Turn 30)
================================================================================

📈 STRATEGY PERFORMANCE

  Aggressive            Prestige:  1,245 (± 156)  Treasury: 2,450  Colonies:  3.2  Ships:  45.8
  Economic              Prestige:  1,892 (± 203)  Treasury: 8,900  Colonies:  5.8  Ships:  28.3
  Balanced              Prestige:  1,567 (± 178)  Treasury: 4,200  Colonies:  4.1  Ships:  35.2
  TechRush              Prestige:  1,423 (± 189)  Treasury: 3,800  Colonies:  3.9  Ships:  22.7
  Expansionist          Prestige:  1,678 (± 167)  Treasury: 3,100  Colonies:  6.4  Ships:  31.5

💰 ECONOMIC ACTIVITY

  Economic              Production: 125.8  IU:  85.3  PU: 142.6  GCO: 1,890
  Balanced              Production:  98.2  IU:  67.2  PU: 115.4  GCO: 1,420
  Expansionist          Production:  92.5  IU:  71.8  PU: 128.9  GCO: 1,650
  TechRush              Production:  87.3  IU:  62.1  PU: 108.7  GCO: 1,280
  Aggressive            Production:  76.4  IU:  54.8  PU:  95.3  GCO: 1,150

⚔️  MILITARY STRENGTH

  Aggressive            Fighters:  89.2  Capitals: 12.3  Escorts:  8.7  Scouts:  3.1
  Balanced              Fighters:  67.4  Capitals:  9.8  Escorts:  6.2  Scouts:  2.8
  Expansionist          Fighters:  58.9  Capitals:  8.1  Escorts:  5.9  Scouts:  4.2
  Economic              Fighters:  45.6  Capitals:  6.7  Escorts:  4.3  Scouts:  1.9
  TechRush              Fighters:  38.2  Capitals:  5.2  Escorts:  3.8  Scouts:  2.3

🔬 RESEARCH PROGRESS

  TechRush              Eco: 6.8  Sci: 5.2  Wpn: 4.9  Cst: 4.1  ELI: 3.2
  Economic              Eco: 6.2  Sci: 4.8  Wpn: 3.7  Cst: 3.5  ELI: 2.4
  Balanced              Eco: 5.1  Sci: 4.2  Wpn: 4.3  Cst: 3.8  ELI: 2.7
  Aggressive            Eco: 4.3  Sci: 3.6  Wpn: 5.2  Cst: 3.2  ELI: 2.1
  Expansionist          Eco: 4.8  Sci: 3.9  Wpn: 3.8  Cst: 3.4  ELI: 2.9

🚨 RED FLAGS

  [CRITICAL] Capacity violations:     127 incidents across 45 games (45%)
  [CRITICAL] Zero espionage activity: 0% of games used spy missions
  [HIGH]     Idle carriers:           34.2% average idle rate
  [HIGH]     No ELI coverage:         67.8% of invasions without scout mesh
  [MEDIUM]   Undefended colonies:     28.3% of colonies have no defense
  [MEDIUM]   CLK without Raiders:     12.5% of houses research CLK but build no raiders

💡 BALANCE RECOMMENDATIONS

  1. [Economy] Economic strategy dominates (65% win rate vs 20% for Aggressive)
     → Increase early military unit efficiency by 15-20%
     → Reduce Economic Level research costs by 10%

  2. [Combat] Carrier idle rate too high (34.2% vs target <10%)
     → AI not utilizing fighter combat effectively
     → Review Admiral tactical module

  3. [Espionage] Zero espionage usage across all strategies
     → System broken or too expensive
     → CRITICAL: Investigate espionage order generation

================================================================================
✅ Analysis complete: 100 games, 3,000 rows processed
   Report saved to: balance_results/analysis_20251202_143022.md
================================================================================
```

### Example 2: Red Flag Detection
```
================================================================================
🚨 DIAGNOSTIC ISSUE DETECTOR
================================================================================

Analyzing: balance_results/diagnostics_combined.parquet
Games: 100 | Turns: 30 | Total Rows: 12,000

🔴 CRITICAL ISSUES (Immediate attention required)

  ❌ Capacity Violations (Severity: 10/10)
     • 127 incidents across 45 games (45% of all games)
     • Fighters exceeding carrier capacity
     • Root cause: Order validation not checking capacity
     • Impact: Game state corruption, invalid combat results

     Top offenders by strategy:
       Aggressive:    67 violations (avg 5.2 per game)
       MilitaryInd:   38 violations (avg 3.8 per game)
       Balanced:      22 violations (avg 1.9 per game)

  ❌ Espionage System Dead (Severity: 9/10)
     • 0 spy missions across 100 games (0.0%)
     • 0 hack missions across 100 games (0.0%)
     • System completely unused by all AI strategies
     • Root cause: Orders never generated OR too expensive
     → BLOCKER for Phase 2 RBA completion

🟡 HIGH PRIORITY ISSUES (Significant gameplay impact)

  ⚠ Carrier Underutilization (Severity: 7/10)
     • 34.2% average idle carrier rate (target: <10%)
     • Carriers built but not deploying fighters
     • Root cause: AI not issuing load fighter orders
     → Review Admiral tactical module

  ⚠ ELI Mesh Coverage Gap (Severity: 7/10)
     • 67.8% of invasions without scout reconnaissance
     • Intelligence gathering not integrated with operations
     • Root cause: Protostrator not coordinating with Admiral
     → Review intelligence distribution module

🟢 MEDIUM ISSUES (Minor gameplay concerns)

  ℹ Undefended Colonies (Severity: 5/10)
     • 28.3% of colonies have no defense squadrons
     • Acceptable for rear colonies, risky for frontiers
     • May be intentional (economy-focused strategies)

  ℹ CLK Research Without Raiders (Severity: 4/10)
     • 12.5% of houses research Cloaking but build zero Raiders
     • Research waste: ~500 TRP per occurrence
     • Root cause: Admiral build requirements not checking tech

✅ PASSING CHECKS

  ✓ Invalid orders:           0.3% (target: <1%, GOOD)
  ✓ Zero-spend stalls:        2.1% (target: <5%, GOOD)
  ✓ Tech waste (maxed EL):    0.8% (target: <2%, GOOD)
  ✓ Mothball utilization:    15.3% of late-game (reasonable)

================================================================================
📊 SUMMARY: 2 Critical, 2 High, 2 Medium issues detected
   Next action: Fix espionage system + capacity validation
================================================================================
```

### Example 3: Quick Summary
```
$ ec4x-analyze summary balance_results/diagnostics_combined.parquet

📊 Quick Summary (100 games, 30 turns)

  Games Analyzed:          100
  Total Houses:            400 (4 per game)
  Avg Game Length:        30.0 turns
  Data Points:          12,000 rows

  🏆 Victory Distribution:
     Economic wins:         65  (65%)  ← IMBALANCED
     Military wins:         20  (20%)
     Prestige wins:         15  (15%)

  💰 Economy (avg at turn 30):
     Treasury:           4,890 credits
     Colonies:             4.5 colonies
     Production:          98.7 per turn
     GCO:              1,580 (gross output)

  ⚔️  Military (avg at turn 30):
     Total Ships:         33.2 ships
     Fighters:            59.8 squadrons
     Capitals:             8.4 ships
     Starbases:            2.1 bases

  🔬 Research (avg at turn 30):
     Economic Level:       5.2
     Science Level:        4.3
     Weapons Tech:         4.1
     Construction:         3.6

  🚨 Issues Found: 2 Critical, 2 High, 2 Medium
     Run 'ec4x-analyze detect-issues' for details

✅ Report: balance_results/summary_20251202.md
```

## Nim Implementation Architecture

```nim
# src/ai/analysis/formatters/terminal.nim

import std/[terminal, strformat, strutils, tables]
import nimarrow

type
  OutputMode* = enum
    Terminal    ## Rich terminal with colors/emojis
    Compact     ## AI-friendly markdown (~1500 tokens)
    Detailed    ## Full markdown report (~5000 tokens)
    Json        ## Machine-readable JSON
    Csv         ## Export to CSV

  SeverityLevel* = enum
    Critical = "🔴"
    High = "🟡"
    Medium = "🟢"
    Info = "ℹ"
    Pass = "✅"

  RedFlag* = object
    severity*: SeverityLevel
    title*: string
    description*: string
    impact*: string
    rootCause*: string
    evidence*: seq[string]

proc formatHeader*(title: string, mode: OutputMode): string =
  case mode
  of Terminal:
    result = "\n" & "=".repeat(80) & "\n"
    result &= title & "\n"
    result &= "=".repeat(80) & "\n"
  of Compact:
    result = fmt"## {title}\n\n"
  of Detailed:
    result = fmt"# {title}\n\n"
  of Json, Csv:
    result = ""

proc formatStrategyTable*(stats: Table[string, StrategyStats], mode: OutputMode): string =
  case mode
  of Terminal:
    result = "\n📈 STRATEGY PERFORMANCE\n\n"
    for strategy, s in stats:
      result &= fmt"  {strategy:20s}  "
      result &= fmt"Prestige: {s.avgPrestige:6,.0f} (±{s.stdPrestige:4,.0f})  "
      result &= fmt"Treasury: {s.avgTreasury:5,.0f}  "
      result &= fmt"Colonies: {s.avgColonies:4.1f}  "
      result &= fmt"Ships: {s.avgShips:5.1f}\n"

  of Compact:
    result = "### Strategy Performance\n\n"
    result &= "| Strategy | Prestige | Treasury | Colonies | Ships |\n"
    result &= "|----------|----------|----------|----------|-------|\n"
    for strategy, s in stats:
      result &= fmt"| {strategy} | {s.avgPrestige:.0f} | {s.avgTreasury:.0f} | {s.avgColonies:.1f} | {s.avgShips:.1f} |\n"

  of Detailed:
    result = "## Strategy Performance Analysis\n\n"
    result &= "| Strategy | Avg Prestige | Std Dev | Treasury | Colonies | Ships |\n"
    result &= "|----------|--------------|---------|----------|----------|-------|\n"
    for strategy, s in stats:
      result &= fmt"| {strategy} | {s.avgPrestige:.0f} | {s.stdPrestige:.0f} | {s.avgTreasury:.0f} | {s.avgColonies:.1f} | {s.avgShips:.1f} |\n"
    result &= "\n**Analysis:** "
    # Add interpretation...

  of Json:
    result = "" # JSON serialization
  of Csv:
    result = "" # CSV export

proc formatRedFlags*(flags: seq[RedFlag], mode: OutputMode): string =
  case mode
  of Terminal:
    result = "\n🚨 RED FLAGS\n\n"
    for flag in flags:
      result &= fmt"  [{flag.severity}] {flag.title}\n"
      result &= fmt"     • {flag.description}\n"
      if flag.rootCause != "":
        result &= fmt"     • Root cause: {flag.rootCause}\n"
      if flag.impact != "":
        result &= fmt"     • Impact: {flag.impact}\n"
      result &= "\n"

  of Compact:
    result = "### Issues Found\n\n"
    let criticalFlags = flags.filterIt(it.severity == Critical)
    let highFlags = flags.filterIt(it.severity == High)

    if criticalFlags.len > 0:
      result &= fmt"**Critical ({criticalFlags.len}):**\n"
      for flag in criticalFlags:
        result &= fmt"- {flag.title}: {flag.description}\n"

    if highFlags.len > 0:
      result &= fmt"\n**High Priority ({highFlags.len}):**\n"
      for flag in highFlags:
        result &= fmt"- {flag.title}: {flag.description}\n"

  of Detailed:
    result = "## Diagnostic Issues\n\n"

    let bySeverity = [
      ("Critical Issues", flags.filterIt(it.severity == Critical)),
      ("High Priority", flags.filterIt(it.severity == High)),
      ("Medium Priority", flags.filterIt(it.severity == Medium))
    ]

    for (title, flagList) in bySeverity:
      if flagList.len > 0:
        result &= fmt"### {title}\n\n"
        for flag in flagList:
          result &= fmt"#### {flag.title}\n\n"
          result &= fmt"**Description:** {flag.description}\n\n"
          if flag.rootCause != "":
            result &= fmt"**Root Cause:** {flag.rootCause}\n\n"
          if flag.impact != "":
            result &= fmt"**Impact:** {flag.impact}\n\n"
          if flag.evidence.len > 0:
            result &= "**Evidence:**\n"
            for e in flag.evidence:
              result &= fmt"- {e}\n"
            result &= "\n"

  of Json, Csv:
    result = ""

proc formatProgressBar*(current, total: int, label: string): string =
  ## Terminal-only animated progress bar
  let percent = (current.float / total.float * 100).int
  let barWidth = 40
  let filled = (percent.float / 100.0 * barWidth.float).int
  let bar = "█".repeat(filled) & "░".repeat(barWidth - filled)
  result = fmt"\r{label}: [{bar}] {percent}% ({current}/{total})"

# Usage in analyzer
proc analyzeAndReport*(parquetPath: string, mode: OutputMode = Terminal): string =
  let table = readParquet(parquetPath)

  result = formatHeader("RBA Performance Summary", mode)

  # Calculate statistics
  let strategyStats = calculateStrategyStats(table)
  result &= formatStrategyTable(strategyStats, mode)

  let economyStats = calculateEconomyStats(table)
  result &= formatEconomyTable(economyStats, mode)

  let militaryStats = calculateMilitaryStats(table)
  result &= formatMilitaryTable(militaryStats, mode)

  let researchStats = calculateResearchStats(table)
  result &= formatResearchTable(researchStats, mode)

  # Detect issues
  let redFlags = detectRedFlags(table)
  result &= formatRedFlags(redFlags, mode)

  # Recommendations (only in detailed mode)
  if mode == Detailed:
    let recommendations = generateRecommendations(redFlags, strategyStats)
    result &= formatRecommendations(recommendations, mode)
```

## CLI Command Structure

```nim
# src/ai/analysis/cli.nim

import std/[parseopt, os, strutils]
import formatters/terminal
import analyzer

proc printUsage() =
  echo """
EC4X Analysis Tool - Game balance and AI diagnostic analyzer

USAGE:
  ec4x-analyze <command> [options]

COMMANDS:
  summary <file>              Quick terminal summary
  analyze <file>              Full terminal analysis report
  compact <file>              AI-friendly compact summary (~1500 tokens)
  detailed <file>             Comprehensive markdown report
  detect-issues <file>        Show red flags only
  compare <file1> <file2>     Compare two test runs
  export <file> --format=csv  Export to CSV/JSON

OPTIONS:
  --output=<file>             Save report to file
  --format=<type>             Output format (terminal/compact/detailed/json/csv)
  --filter=<strategy>         Filter by AI strategy
  --turns=<range>             Filter by turn range (e.g., 10-20)

EXAMPLES:
  # Quick terminal summary
  ec4x-analyze summary balance_results/diagnostics.parquet

  # Full analysis with report file
  ec4x-analyze analyze diagnostics.parquet --output=report.md

  # AI-friendly compact format
  ec4x-analyze compact diagnostics.parquet --format=compact

  # Detect issues only
  ec4x-analyze detect-issues diagnostics.parquet

  # Compare before/after tuning
  ec4x-analyze compare before.parquet after.parquet

  # Export to CSV for Excel
  ec4x-analyze export diagnostics.parquet --format=csv --output=data.csv
"""

proc main() =
  var args = initOptParser()

  if args.key == "":
    printUsage()
    quit(0)

  let command = args.key
  args.next()

  var
    inputFile: string
    outputFile: string
    mode = Terminal
    filter: string
    turnRange: tuple[min, max: int]

  # Parse command-specific arguments
  case command
  of "summary":
    if args.key != "":
      inputFile = args.key
    else:
      echo "Error: Missing input file"
      quit(1)

    # Quick summary in terminal
    let report = analyzeSummary(inputFile, mode = Terminal)
    echo report

  of "analyze":
    inputFile = args.key
    args.next()

    # Parse options
    while args.kind != cmdEnd:
      case args.key
      of "output": outputFile = args.val
      of "format":
        mode = parseEnum[OutputMode](args.val)
      args.next()

    let report = analyzeAndReport(inputFile, mode)

    if outputFile != "":
      writeFile(outputFile, report)
      echo fmt"✅ Report saved to: {outputFile}"
    else:
      echo report

  of "compact":
    inputFile = args.key
    let report = analyzeAndReport(inputFile, mode = Compact)
    echo report

  of "detailed":
    inputFile = args.key
    let report = analyzeAndReport(inputFile, mode = Detailed)
    echo report

  of "detect-issues":
    inputFile = args.key
    let flags = detectRedFlagsOnly(inputFile)
    echo formatRedFlags(flags, Terminal)

  else:
    echo fmt"Unknown command: {command}"
    printUsage()
    quit(1)

when isMainModule:
  main()
```

## Token Budget Comparison

### Raw Parquet Dump
```
150 columns × 12,000 rows = 1,800,000 numbers
≈ 200,000 tokens (UNUSABLE)
```

### Terminal Mode (Human)
```
Rich formatting, colors, emojis, full details
≈ 3,000 tokens (optimized for humans, not AI)
```

### Compact Mode (AI)
```
Markdown tables, key findings only
≈ 1,500 tokens (PERFECT for Claude analysis)
```

### Detailed Mode (Documentation)
```
Full analysis with interpretations
≈ 5,000 tokens (good for reports)
```

## Implementation Priorities

1. **Phase 1: Core formatters**
   - `terminal.nim` - Rich terminal output
   - `compact.nim` - AI-friendly summaries
   - `tables.nim` - Table formatting utilities

2. **Phase 2: Analyzers**
   - `strategy_analyzer.nim` - Strategy performance
   - `economy_analyzer.nim` - Economic metrics
   - `military_analyzer.nim` - Combat analysis
   - `issue_detector.nim` - Red flag detection

3. **Phase 3: CLI**
   - `cli.nim` - Command dispatcher
   - `commands/` - Command implementations

4. **Phase 4: Advanced**
   - `comparator.nim` - Before/after comparison
   - `recommender.nim` - Balance suggestions
   - `exporter.nim` - CSV/JSON export

## Success Criteria

- [x] Terminal output matches Python script quality
- [x] Compact mode stays under 2000 tokens
- [x] All output modes implemented
- [ ] Color support for terminals
- [ ] Progress bars for long operations
- [ ] Emoji support (UTF-8)
- [ ] Table alignment and formatting
- [ ] Red flag severity thresholds
- [ ] Comparison mode for A/B testing

---

**Status:** Design complete, ready for implementation
**Next:** Prototype terminal formatter with nimarrow
