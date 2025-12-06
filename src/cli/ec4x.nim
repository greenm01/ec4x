## EC4X Analysis CLI
##
## Unified command-line tool for EC4X game analysis.
## Replaces all scattered Python and Bash analysis scripts.

import cligen
import commands/[analyze, data]

proc ec4x(
  # Analysis flags (mutually exclusive - first one wins)
  summary: bool = false,
  full: bool = false,
  compact: bool = false,
  detailed: bool = false,
  all: bool = false,
  game: string = "",  # Single game analysis by seed

  # Data management flags (mutually exclusive)
  clean: bool = false,
  cleanAll: bool = false,
  info: bool = false,
  archives: bool = false,

  # Common options
  diagnosticsDir: string = "balance_results/diagnostics",
  output: string = "",
  backup: bool = true,
  keepReports: int = 5,
  keepSummaries: int = 10,
  save: bool = true
): int =
  ## EC4X Analysis and Data Management Tool
  ##
  ## Analysis commands (run one):
  ##   --summary        Quick terminal summary
  ##   --full           Full terminal analysis with Unicode tables
  ##   --compact        Token-efficient markdown (~1500 tokens)
  ##   --detailed       Detailed markdown report (git-committable)
  ##   --all            Generate all report formats
  ##   --game SEED      Detailed single-game analysis (e.g., --game 2000)
  ##
  ## Data management commands (run one):
  ##   --info           Show current analysis data status
  ##   --clean          Clean old data (keep last 5 reports, 10 summaries)
  ##   --clean-all      Clean ALL analysis data with backup
  ##   --archives       List archived diagnostic backups
  ##
  ## Options:
  ##   -d, --diagnosticsDir   Directory with diagnostic CSVs (default: balance_results/diagnostics)
  ##   -o, --output           Output file path (for compact/detailed)
  ##   -b, --backup           Backup before cleaning (default: true)
  ##   -r, --keepReports      Reports to keep when cleaning (default: 5)
  ##   -s, --keepSummaries    Summaries to keep when cleaning (default: 10)
  ##   --save                 Save terminal report to file (default: true)
  ##
  ## Examples:
  ##   ec4x --summary                  # Quick summary
  ##   ec4x --full -d mydata/          # Full analysis from custom dir
  ##   ec4x --compact -o report.md     # Compact to specific file
  ##   ec4x --all                      # All formats
  ##   ec4x --game 2000                # Analyze game_2000.csv in detail
  ##   ec4x --info                     # Show data status
  ##   ec4x --clean --keepReports 10   # Clean, keep 10 reports

  # Analysis commands
  if game != "":
    return analyze.singleGame(game, diagnosticsDir)
  elif summary:
    return analyze.summary(diagnosticsDir)
  elif full:
    return analyze.full(diagnosticsDir, save)
  elif compact:
    return analyze.compactCmd(diagnosticsDir, output)
  elif detailed:
    return analyze.detailedCmd(diagnosticsDir, output)
  elif all:
    return analyze.all(diagnosticsDir)

  # Data management commands
  elif info:
    return data.info()
  elif clean:
    return data.clean(backup, keepReports, keepSummaries)
  elif cleanAll:
    return data.cleanAll(backup)
  elif archives:
    return data.listArchives()

  # No command specified
  else:
    echo "EC4X Analysis Tool"
    echo ""
    echo "Usage: ec4x [command flags] [options]"
    echo ""
    echo "Run 'ec4x --help' for full documentation"
    return 1

dispatch(ec4x, help = {
  "summary": "Quick terminal summary",
  "full": "Full terminal analysis with Unicode tables",
  "compact": "Token-efficient markdown (~1500 tokens)",
  "detailed": "Detailed markdown report (git-committable)",
  "all": "Generate all report formats",
  "info": "Show current analysis data status",
  "clean": "Clean old data (configurable retention)",
  "cleanAll": "Clean ALL analysis data with backup",
  "archives": "List archived diagnostic backups",
  "diagnosticsDir": "Directory with diagnostic CSVs",
  "output": "Output file path (for compact/detailed)",
  "backup": "Backup before cleaning",
  "keepReports": "Reports to keep when cleaning",
  "keepSummaries": "Summaries to keep when cleaning",
  "save": "Save terminal report to file"
})
