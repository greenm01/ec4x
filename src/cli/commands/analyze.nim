## Analyze Command Module
##
## Implements all analysis subcommands for the ec4x CLI.

import std/[os, strformat, strutils]
import ../../ai/analysis/[types]
import ../../ai/analysis/data/[loader, manager]
import ../../ai/analysis/analyzers/analyzer
import ../../ai/analysis/formatters/[terminal, compact, markdown]

proc summary*(diagnosticsDir = "balance_results/diagnostics"): int =
  ## Quick terminal summary of diagnostic data
  ##
  ## Args:
  ##   diagnosticsDir: Path to directory with diagnostic CSVs
  ##
  ## Returns:
  ##   Exit code (0 = success)

  if not dirExists(diagnosticsDir):
    echo fmt"ℹ️  No diagnostics directory found: {diagnosticsDir}"
    echo ""
    echo "To generate diagnostic data, run simulations first:"
    echo "  nimble testBalanceQuick       # Quick 20-game test"
    echo "  nimble balanceQuickCheck      # 20 games with analysis"
    echo "  nimble testBalanceAct1        # 100 games, Act 1"
    echo ""
    return 0

  try:
    echo fmt"Loading diagnostics from {diagnosticsDir}..."
    let report = analyzeFromDirectory(diagnosticsDir)

    # Show quick summary
    echo formatSummary(report)

    return 0
  except IOError as e:
    # No CSV files found - this is not an error, just means no data yet
    if "No valid CSV files found" in e.msg:
      echo fmt"ℹ️  No diagnostic CSV files found in {diagnosticsDir}"
      echo ""
      echo "To generate diagnostic data, run simulations first:"
      echo "  nimble testBalanceQuick       # Quick 20-game test"
      echo "  nimble balanceQuickCheck      # 20 games with analysis"
      echo "  nimble testBalanceAct1        # 100 games, Act 1"
      echo ""
      return 0
    else:
      echo fmt"Error: {e.msg}"
      return 1
  except Exception as e:
    echo fmt"Error analyzing diagnostics: {e.msg}"
    return 1

proc full*(diagnosticsDir = "balance_results/diagnostics", save = true): int =
  ## Full terminal analysis with rich formatting
  ##
  ## Args:
  ##   diagnosticsDir: Path to directory with diagnostic CSVs
  ##   save: Whether to save report to file
  ##
  ## Returns:
  ##   Exit code (0 = success)

  if not dirExists(diagnosticsDir):
    echo fmt"ℹ️  No diagnostics directory found: {diagnosticsDir}"
    echo "Run simulations first: nimble testBalanceQuick"
    return 0

  try:
    echo fmt"Loading diagnostics from {diagnosticsDir}..."
    let report = analyzeFromDirectory(diagnosticsDir)

    # Generate terminal report
    let output = formatTerminal(report)
    echo output

    # Save if requested
    if save:
      let paths = initOutputPaths()
      createDirectories(paths)
      saveReport(paths, output, "terminal")

    return 0
  except IOError as e:
    if "No valid CSV files found" in e.msg:
      echo fmt"ℹ️  No diagnostic CSV files found in {diagnosticsDir}"
      echo "Run simulations first: nimble testBalanceQuick"
      return 0
    else:
      echo fmt"Error: {e.msg}"
      return 1
  except Exception as e:
    echo fmt"Error analyzing diagnostics: {e.msg}"
    return 1

proc compactCmd*(diagnosticsDir = "balance_results/diagnostics",
                 output = ""): int =
  ## Generate compact markdown summary (AI-friendly, ~1500 tokens)
  ##
  ## Args:
  ##   diagnosticsDir: Path to directory with diagnostic CSVs
  ##   output: Output file path (optional, defaults to summaries/compact_*.md)
  ##
  ## Returns:
  ##   Exit code (0 = success)

  if not dirExists(diagnosticsDir):
    echo fmt"ℹ️  No diagnostics directory found: {diagnosticsDir}"
    echo "Run simulations first: nimble testBalanceQuick"
    return 0

  try:
    echo fmt"Loading diagnostics from {diagnosticsDir}..."
    let report = analyzeFromDirectory(diagnosticsDir)

    # Generate compact markdown
    let content = formatCompact(report)

    # Determine output path
    let paths = initOutputPaths()
    createDirectories(paths)

    let outputPath = if output.len > 0: output else: paths.compactReport

    writeFile(outputPath, content)
    echo fmt"Compact summary saved: {outputPath}"
    echo fmt"Token count: ~{content.len div 4} tokens (approximate)"

    return 0
  except IOError as e:
    if "No valid CSV files found" in e.msg:
      echo fmt"ℹ️  No diagnostic CSV files found in {diagnosticsDir}"
      echo "Run simulations first: nimble testBalanceQuick"
      return 0
    else:
      echo fmt"Error: {e.msg}"
      return 1
  except Exception as e:
    echo fmt"Error generating compact summary: {e.msg}"
    return 1

proc detailedCmd*(diagnosticsDir = "balance_results/diagnostics",
                  output = ""): int =
  ## Generate detailed markdown report (git-committable)
  ##
  ## Args:
  ##   diagnosticsDir: Path to directory with diagnostic CSVs
  ##   output: Output file path (optional, defaults to reports/detailed_*.md)
  ##
  ## Returns:
  ##   Exit code (0 = success)

  if not dirExists(diagnosticsDir):
    echo fmt"ℹ️  No diagnostics directory found: {diagnosticsDir}"
    echo "Run simulations first: nimble testBalanceQuick"
    return 0

  try:
    echo fmt"Loading diagnostics from {diagnosticsDir}..."
    let report = analyzeFromDirectory(diagnosticsDir)

    # Generate detailed markdown
    let content = formatMarkdown(report)

    # Determine output path
    let paths = initOutputPaths()
    createDirectories(paths)

    let outputPath = if output.len > 0: output else: paths.markdownReport

    writeFile(outputPath, content)
    echo fmt"Detailed report saved: {outputPath}"

    # Update symlink
    if output.len == 0:
      updateLatestSymlink(paths)

    return 0
  except IOError as e:
    if "No valid CSV files found" in e.msg:
      echo fmt"ℹ️  No diagnostic CSV files found in {diagnosticsDir}"
      echo "Run simulations first: nimble testBalanceQuick"
      return 0
    else:
      echo fmt"Error: {e.msg}"
      return 1
  except Exception as e:
    echo fmt"Error generating detailed report: {e.msg}"
    return 1

proc all*(diagnosticsDir = "balance_results/diagnostics"): int =
  ## Generate all report formats (terminal, compact, detailed)
  ##
  ## Args:
  ##   diagnosticsDir: Path to directory with diagnostic CSVs
  ##
  ## Returns:
  ##   Exit code (0 = success)

  if not dirExists(diagnosticsDir):
    echo fmt"ℹ️  No diagnostics directory found: {diagnosticsDir}"
    echo "Run simulations first: nimble testBalanceQuick"
    return 0

  try:
    echo fmt"Loading diagnostics from {diagnosticsDir}..."
    let report = analyzeFromDirectory(diagnosticsDir)

    let paths = initOutputPaths()
    createDirectories(paths)

    # Terminal report
    echo "\nGenerating terminal report..."
    let terminalOutput = formatTerminal(report)
    saveReport(paths, terminalOutput, "terminal")
    echo terminalOutput

    # Compact summary
    echo "\nGenerating compact summary..."
    let compactOutput = formatCompact(report)
    saveReport(paths, compactOutput, "compact")

    # Detailed markdown
    echo "\nGenerating detailed report..."
    let markdownOutput = formatMarkdown(report)
    saveReport(paths, markdownOutput, "markdown")

    echo "\n" & "=".repeat(80)
    echo "All reports generated successfully!"
    echo fmt"  Terminal:  {paths.terminalReport}"
    echo fmt"  Compact:   {paths.compactReport}"
    echo fmt"  Detailed:  {paths.markdownReport}"
    echo fmt"  Latest:    {paths.latestSymlink}"
    echo "=".repeat(80)

    return 0
  except IOError as e:
    if "No valid CSV files found" in e.msg:
      echo fmt"ℹ️  No diagnostic CSV files found in {diagnosticsDir}"
      echo "Run simulations first: nimble testBalanceQuick"
      return 0
    else:
      echo fmt"Error: {e.msg}"
      return 1
  except Exception as e:
    echo fmt"Error generating reports: {e.msg}"
    return 1
