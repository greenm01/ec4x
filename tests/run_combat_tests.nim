## Combat Test Runner
##
## Simple runner to verify the complete testing framework
## Generates scenarios, runs tests, and exports results

import combat_test_harness
import combat_report_json

when isMainModule:
  echo "=== EC4X Combat Test Runner ==="
  echo ""

  # Run quick test suite
  let results = quickTest(numTests = 30, seed = 12345, verbose = true)

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
