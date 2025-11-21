## Combat Test Runner
##
## Simple runner to verify the complete testing framework
## Generates scenarios, runs tests, and exports results

import harness
import reporter

when isMainModule:
  echo "=== EC4X Combat Test Runner ==="
  echo ""

  # Run quick balance test - 500 scenarios for smaller JSON output
  let results = quickTest(numTests = 500, seed = 12345, verbose = false)

  echo ""
  echo "=== Exporting Results ==="

  # Export full results
  exportToJsonFile(results, "combat_test_results.json")

  # Export summary only
  exportSummaryToJson(results, "combat_summary.json")

  # Export CSV stats
  exportStatsToCsv(results, "combat_stats.csv")

  echo ""
  echo "=== Test Run Complete ==="
  echo "Results exported to:"
  echo "  - combat_test_results.json (full details)"
  echo "  - combat_summary.json (summary only)"
  echo "  - combat_stats.csv (spreadsheet format)"
