# Package

version       = "0.1.0"
author        = "Mason Austin Green"
description   = "EC4X - Asynchronous turn-based 4X wargame"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
# Note: nimble will look for src/main/moderator.nim and src/main/client.nim
bin           = @["main/moderator", "main/client", "cli/ec4x"]  # daemon not ready yet (needs Nostr dependencies)

# Dependencies

requires "nim >= 2.0.0"
requires "cligen >= 1.7.0"
requires "toml_serialization >= 0.2.0"
requires "datamancer >= 0.4.0"
requires "terminaltables >= 0.1.0"

# Future Nostr dependencies (TODO: uncomment when implementing)
# requires "websocket >= 0.5.0"
# requires "nimcrypto >= 0.6.0"

# Tasks

task test, "Run the complete test suite with analysis":
  exec "rm -f test_report.csv"
  exec "tests/run_all_tests.py --types all --report test_report.csv"

task testQuick, "Run complete test suite (no CSV report)":
  exec "rm -f test_report.csv"
  exec "tests/run_all_tests.py --types all"

task testUnit, "Run unit tests only":
  exec "rm -f test_report.csv"
  exec "tests/run_all_tests.py --types unit"

task testIntegration, "Run integration tests":
  exec "rm -f test_report.csv"
  exec "tests/run_all_tests.py --types integration"

task testStress, "Run stress tests":
  exec "rm -f test_report.csv"
  exec "tests/stress/run_stress_tests.py"

task testStressQuick, "Run stress tests in quick mode":
  exec "rm -f test_report.csv"
  exec "tests/stress/run_stress_tests.py --quick"

task testBalance, "Run balance tests":
  exec "rm -f test_report.csv"
  exec "tests/run_all_tests.py --types balance --timeout 300"

task testUnits, "Test all unit construction (ships, ground units, facilities)":
  echo "Testing all 34 game asset types..."
  exec "nim c -r tests/integration/test_all_units_construction.nim"

task testEconomy, "Test economy system integration":
  echo "Testing M5 economy system..."
  exec "nim c -r tests/integration/test_m5_economy_integration.nim"

task testTechnology, "Test technology advancement system":
  echo "Testing technology system..."
  exec "nim c -r tests/integration/test_technology_comprehensive.nim"

task testDiplomacy, "Test diplomacy system":
  echo "Testing diplomacy system..."
  exec "nim c -r tests/integration/test_diplomacy.nim"

task testPrestige, "Test prestige system":
  echo "Testing prestige system..."
  exec "nim c -r tests/integration/test_prestige_comprehensive.nim"

task testComprehensive, "Run all comprehensive test suites":
  echo "Running comprehensive test suites..."
  echo "=== Analytics Engine Tests ==="
  exec "nim c -r tests/integration/test_analytics_engine.nim"
  echo ""
  echo "=== Combat Engine Tests ==="
  exec "nim c -r tests/integration/test_combat_comprehensive.nim"
  echo ""
  echo "=== Unit Validation Tests ==="
  exec "nim c -r tests/integration/test_all_units_comprehensive.nim"
  echo ""
  echo "=== Resolution Engine Tests ==="
  exec "nim c -r tests/integration/test_resolution_comprehensive.nim"
  echo ""
  echo "All comprehensive tests completed successfully!"

task testAnalytics, "Test analytics engine (export, formats, statistics)":
  echo "Testing analytics engine..."
  exec "nim c -r tests/integration/test_analytics_engine.nim"

task testCombat, "Test combat engine (CER, damage, targeting)":
  echo "Testing combat engine..."
  exec "nim c -r tests/integration/test_combat_comprehensive.nim"

task testAllUnitsValidation, "Validate all units against TOML configs":
  echo "Validating all units against TOML configs..."
  exec "nim c -r tests/integration/test_all_units_comprehensive.nim"

task testResolution, "Test resolution engine (commissioning, fleet ops)":
  echo "Testing resolution engine..."
  exec "nim c -r tests/integration/test_resolution_comprehensive.nim"

# Stress Testing Tasks

task testStressEngine, "Run ALL engine stress tests (state corruption, fuzzing, performance, unknowns)":
  echo "Running comprehensive engine stress test suite..."
  echo "⚠️  WARNING: This will take 10-30 minutes to complete"
  echo ""
  echo "=== State Corruption Tests ==="
  exec "nim c -r tests/stress/test_state_corruption.nim"
  echo ""
  echo "=== Pathological Input Fuzzing ==="
  exec "nim c -r tests/stress/test_pathological_inputs.nim"
  echo ""
  echo "=== Performance Regression Tests ==="
  exec "nim c -r tests/stress/test_performance_regression.nim"
  echo ""
  echo "=== Unknown-Unknowns Detection (Stress) ==="
  exec "nim c -r tests/stress/test_unknown_unknowns.nim"
  echo ""
  echo "✅ All engine stress tests completed!"

task testStressEngineQuick, "Quick engine stress test (faster, less thorough)":
  echo "Running quick stress tests..."
  echo "=== State Corruption (quick) ==="
  exec "nim c -r tests/stress/test_state_corruption.nim -d:STRESS_QUICK"
  echo ""
  echo "=== Pathological Input Fuzzing ==="
  exec "nim c -r tests/stress/test_pathological_inputs.nim"
  echo ""
  echo "✅ Quick stress tests completed!"

task testStateCorruption, "Test for state corruption over 1000+ turns":
  echo "Testing state corruption (long-duration simulations)..."
  exec "nim c -r tests/stress/test_state_corruption.nim"

task testPathologicalInputs, "Fuzz engine with invalid/malformed inputs":
  echo "Testing pathological inputs (fuzzing)..."
  exec "nim c -r tests/stress/test_pathological_inputs.nim"

task testPerformanceRegression, "Monitor turn times for performance regression":
  echo "Testing performance regression..."
  exec "nim c -r tests/stress/test_performance_regression.nim"

task testStressUnknownUnknowns, "Statistical anomaly detection (100+ games)":
  echo "Running stress test unknown-unknowns detection..."
  echo "⚠️  This will take 5-10 minutes (runs 100+ games)"
  exec "nim c -r tests/stress/test_unknown_unknowns.nim"

task testStarmap, "Run starmap tests":
  echo "Running starmap tests..."
  exec "nim c -r tests/test_starmap_robust.nim"

task testValidation, "Run game specification validation tests":
  echo "Running game specification validation tests..."
  exec "nim c -r tests/test_starmap_validation.nim"

task testWarnings, "Run tests with warnings enabled":
  echo "Running tests with warnings enabled..."
  exec "nim c -r --warnings:on tests/test_core.nim"
  exec "nim c -r --warnings:on tests/test_starmap_robust.nim"
  exec "nim c -r --warnings:on tests/test_starmap_validation.nim"
  echo "All tests passed with no warnings!"

task build, "Build all binaries":
  echo "Building EC4X binaries..."
  mkDir "bin"
  exec "nim c --warnings:on -d:release --opt:speed -o:bin/moderator src/main/moderator.nim"
  exec "nim c --warnings:on -d:release --opt:speed -o:bin/client src/main/client.nim"
  # exec "nim c --warnings:on -d:release --opt:speed -o:bin/daemon src/main/daemon.nim"  # TODO: Enable when dependencies ready
  echo "Build completed successfully!"

task buildDebug, "Build with debug information":
  echo "Building EC4X binaries with debug info..."
  mkDir "bin"
  exec "nim c --warnings:on -d:debug --debuginfo --linedir:on -o:bin/moderator src/main/moderator.nim"
  exec "nim c --warnings:on -d:debug --debuginfo --linedir:on -o:bin/client src/main/client.nim"
  # exec "nim c --warnings:on -d:debug --debuginfo --linedir:on -o:bin/daemon src/main/daemon.nim"  # TODO: Enable when dependencies ready
  echo "Debug build completed successfully!"

task check, "Check syntax of all source files":
  echo "Checking syntax of all source files..."
  exec "nim check src/core.nim"
  exec "nim check src/main/moderator.nim"
  exec "nim check src/main/client.nim"
  echo "All syntax checks passed!"

task clean, "Clean build artifacts":
  echo "Cleaning build artifacts..."
  exec "rm -rf bin/"
  exec "rm -rf nimcache/"
  exec "find . -name '*.exe' -delete 2>/dev/null || true"
  exec "find . -name 'test_core' -delete 2>/dev/null || true"
  exec "find . -name 'test_starmap_robust' -delete 2>/dev/null || true"
  exec "find . -name 'test_starmap_validation' -delete 2>/dev/null || true"
  echo "Clean completed!"

task docs, "Generate documentation":
  echo "Generating documentation..."
  exec "nim doc --project --index:on --git.url:https://github.com/greenm01/ec4x --git.commit:main src/core.nim"
  echo "Documentation generated successfully!"

task example, "Run example commands":
  echo "Running example commands..."
  mkDir "bin"
  exec "nim c -d:release --opt:speed -o:bin/moderator src/main/moderator.nim"
  exec "nim c -d:release --opt:speed -o:bin/client src/main/client.nim"
  exec "./bin/moderator new example_game"
  exec "./bin/client offline --players=4 --output-dir=example_offline"
  echo "Example commands completed!"

task demo, "Build and run a quick demo":
  echo "Building and running EC4X demo..."
  mkDir "bin"
  exec "nim c -d:release --opt:speed -o:bin/moderator src/main/moderator.nim"
  exec "nim c -d:release --opt:speed -o:bin/client src/main/client.nim"
  echo "=== EC4X Demo ==="
  echo "Creating demo game..."
  exec "./bin/moderator new demo_game"
  echo "Creating offline test game..."
  exec "./bin/client offline --players=4 --output-dir=demo_offline"
  echo "Demo completed successfully!"

# Balance Testing Tasks

task buildSimulation, "Build simulation binary":
  echo "Building simulation binary..."
  echo "Using --forceBuild to ensure clean compilation"
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/run_simulation src/ai/analysis/run_simulation.nim"
  exec "git rev-parse --short HEAD > bin/.build_git_hash"
  echo "Simulation binary built successfully!"
  echo "Git hash: $(cat bin/.build_git_hash)"

task testBalanceQuick, "Quick balance validation (7 turns, 20 games)":
  echo "Running quick balance validation (7 turns, 20 games)..."
  echo "Cleaning old diagnostics..."
  exec "bin/ec4x --clean-all --backup"
  echo "Building simulation binary..."
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/run_simulation src/ai/analysis/run_simulation.nim"
  exec "git rev-parse --short HEAD > bin/.build_git_hash"
  exec "python3 scripts/run_balance_test_parallel.py --workers 8 --games 20 --turns 7"
  echo "Analyzing results..."
  exec "bin/ec4x --all"
  echo "Quick balance validation completed!"

task testBalanceAct1, "Act 1: Land Grab (7 turns, 100 games)":
  echo "Running Act 1 validation (7 turns, 100 games)..."
  echo "Cleaning old diagnostics..."
  exec "bin/ec4x --clean-all --backup"
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/run_simulation src/ai/analysis/run_simulation.nim"
  exec "git rev-parse --short HEAD > bin/.build_git_hash"
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 7"
  echo "Analyzing results..."
  exec "bin/ec4x --all"
  echo "Act 1 validation completed!"

task testBalanceAct2, "Act 2: Rising Tensions (15 turns, 100 games)":
  echo "Running Act 2 validation (15 turns, 100 games)..."
  echo "Cleaning old diagnostics..."
  exec "bin/ec4x --clean-all --backup"
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/run_simulation src/ai/analysis/run_simulation.nim"
  exec "git rev-parse --short HEAD > bin/.build_git_hash"
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 15"
  echo "Analyzing results..."
  exec "bin/ec4x --all"
  echo "Act 2 validation completed!"

task testBalanceAct3, "Act 3: Total War (25 turns, 100 games)":
  echo "Running Act 3 validation (25 turns, 100 games)..."
  echo "Cleaning old diagnostics..."
  exec "bin/ec4x --clean-all --backup"
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/run_simulation src/ai/analysis/run_simulation.nim"
  exec "git rev-parse --short HEAD > bin/.build_git_hash"
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 25"
  echo "Analyzing results..."
  exec "bin/ec4x --all"
  echo "Act 3 validation completed!"

task testBalanceAct4, "Act 4: Endgame (30 turns, 100 games)":
  echo "Running Act 4 validation (30 turns, 100 games)..."
  echo "Cleaning old diagnostics..."
  exec "bin/ec4x --clean-all --backup"
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/run_simulation src/ai/analysis/run_simulation.nim"
  exec "git rev-parse --short HEAD > bin/.build_git_hash"
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 30"
  echo "Analyzing results..."
  exec "bin/ec4x --all"
  echo "Act 4 validation completed!"

task testBalanceAll4Acts, "Test all 4 acts sequentially (7, 15, 25, 30 turns)":
  echo "Running complete 4-act validation suite..."
  echo "Cleaning old diagnostics..."
  exec "bin/ec4x --clean-all --backup"
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/run_simulation src/ai/analysis/run_simulation.nim"
  exec "git rev-parse --short HEAD > bin/.build_git_hash"
  echo "Git hash: $(cat bin/.build_git_hash)"
  echo "\n=== Act 1: Land Grab (7 turns) ==="
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 7"
  echo "\n=== Act 2: Rising Tensions (15 turns) ==="
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 15"
  echo "\n=== Act 3: Total War (25 turns) ==="
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 25"
  echo "\n=== Act 4: Endgame (30 turns) ==="
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 30"
  echo "\nAnalyzing all results..."
  exec "bin/ec4x --all"
  echo "\nAll 4 acts validated! Total: 400 games"

task cleanBalance, "Clean balance test artifacts":
  echo "Cleaning balance test artifacts..."
  exec "rm -f bin/run_simulation"
  exec "bin/ec4x 'data clean'"
  echo "Balance test artifacts cleaned!"

task cleanBalanceAll, "Clean ALL balance data including archives":
  echo "Cleaning ALL balance test data (including archives)..."
  exec "rm -f bin/run_simulation"
  exec "bin/ec4x --clean-all"
  echo "All balance data cleaned!"
  echo "⚠ Warning: This deletes historical test data permanently"

task cleanDiagnostics, "Clean diagnostic CSVs only":
  echo "Cleaning diagnostic CSV files..."
  exec "rm -rf balance_results/diagnostics/*.csv"
  echo "Diagnostic CSV files cleaned!"

task listArchives, "List all archived diagnostic runs":
  echo "Listing archived diagnostic runs..."
  exec "bin/ec4x 'data archives'"

task archiveStats, "Show analysis data status":
  echo "Showing analysis data status..."
  exec "bin/ec4x 'data info'"

# Advanced Balance Testing Tasks

task testBalanceDiagnostics, "Run diagnostic tests with CSV output (50 games, 30 turns)":
  echo "Running diagnostic balance tests (50 games, 30 turns)..."
  exec "bin/ec4x --clean-all --backup"
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/run_simulation src/ai/analysis/run_simulation.nim"
  exec "git rev-parse --short HEAD > bin/.build_git_hash"
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 50 --turns 30"
  echo "Analyzing results..."
  exec "bin/ec4x --all"
  echo "Diagnostic tests completed! Results in balance_results/"

task testUnknownUnknowns, "Unknown-unknowns detection (200 games, full diagnostics)":
  echo "Running unknown-unknowns detection suite (200 games, 30 turns)..."
  echo "This generates comprehensive CSV data for pattern analysis"
  exec "bin/ec4x --clean-all --backup"
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/run_simulation src/ai/analysis/run_simulation.nim"
  exec "git rev-parse --short HEAD > bin/.build_git_hash"
  echo "Git hash: $(cat bin/.build_git_hash)"
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 200 --turns 30"
  echo "\nGenerating all analysis reports..."
  exec "bin/ec4x --all"
  echo "\nUnknown-unknowns detection completed!"
  echo "Check balance_results/reports/latest.md for detailed analysis"

# Data Analysis Tasks (Pure Nim - using ec4x CLI)
# NOTE: All Python-based analysis tasks have been replaced with ec4x commands

task analyzePerformance, "Analyze RBA strategy performance (REPLACED - use analyzeFull)":
  echo "⚠️  This task has been replaced by 'analyzeFull' using pure Nim"
  echo "Use: nimble analyzeFull"
  exec "bin/ec4x 'analyze full'"

task balanceDiagnostic, "Run 100-game diagnostic + analysis":
  echo "Cleaning old diagnostic data..."
  exec "bin/ec4x --clean-all --backup"
  echo "Running 100-game diagnostic..."
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/run_simulation src/ai/analysis/run_simulation.nim"
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 7"
  echo "\nAnalyzing results..."
  exec "bin/ec4x --all"

task balanceQuickCheck, "Quick balance check (20 games + analysis)":
  echo "Cleaning old diagnostic data..."
  exec "bin/ec4x --clean-all --backup"
  echo "Running quick balance check (20 games)..."
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/run_simulation src/ai/analysis/run_simulation.nim"
  exec "python3 scripts/run_balance_test_parallel.py --workers 8 --games 20 --turns 7"
  echo "\nAnalyzing results..."
  exec "bin/ec4x --all"

task analyzeBalance, "Full analysis workflow (all report formats)":
  echo "Running full balance analysis workflow..."
  exec "bin/ec4x --all"
  echo "\n✅ Analysis complete!"
  echo "   • Terminal:  balance_results/reports/terminal_*.txt"
  echo "   • Compact:   balance_results/summaries/compact_*.md"
  echo "   • Detailed:  balance_results/reports/detailed_*.md"
  echo "   • Latest:    balance_results/reports/latest.md"

task balanceSummary, "Quick terminal summary of diagnostic data":
  exec "bin/ec4x 'analyze summary'"

task balanceReport, "Generate Markdown report (git-committable)":
  echo "Generating detailed markdown report..."
  exec "bin/ec4x 'analyze detailed'"
  echo "✅ Report generated: See balance_results/reports/latest.md"
  echo "   Commit to git for documentation"

task testMapSizes, "Test balance across different map sizes":
  echo "Testing different map sizes (4, 8, 12 players)..."
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/run_simulation src/ai/analysis/run_simulation.nim"
  exec "git rev-parse --short HEAD > bin/.build_git_hash"
  exec "python3 run_map_size_test.py"
  echo "Map size tests completed!"

task testStressAI, "AI stress test (1000 games, crash and behavior detection)":
  echo "Running AI stress test (1000 games, 30 turns each)..."
  echo "This tests AI stability and identifies edge cases"
  exec "bin/ec4x --clean-all --backup"
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/run_simulation src/ai/analysis/run_simulation.nim"
  exec "git rev-parse --short HEAD > bin/.build_git_hash"
  echo "Git hash: $(cat bin/.build_git_hash)"
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 1000 --turns 30"
  echo "\nAnalyzing results..."
  exec "bin/ec4x --all"
  echo "AI stress test completed! Check balance_results/reports/latest.md"

# AI Tuning & Optimization Tasks

task buildAITuning, "Build AI tuning tools (genetic algorithm)":
  echo "Building AI tuning tools..."
  mkDir "bin"
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/genetic_ai src/ai/tuning/genetic/genetic_ai.nim"
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/evolve_ai src/ai/tuning/genetic/evolve_ai.nim"
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/coevolution src/ai/tuning/genetic/coevolution.nim"
  echo "AI tuning tools built successfully!"
  echo "Binaries: bin/{genetic_ai,evolve_ai,coevolution}"

task evolveAI, "Evolve AI personalities via genetic algorithm (50 gen, 20 pop)":
  echo "Evolving AI personalities via genetic algorithm..."
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/evolve_ai src/ai/tuning/genetic/evolve_ai.nim"
  exec "bin/evolve_ai --generations 50 --population 20 --games 4"
  echo "Evolution completed! Results in balance_results/evolution/"

task evolveAIQuick, "Quick AI evolution test (10 gen, 10 pop)":
  echo "Running quick AI evolution test..."
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/evolve_ai src/ai/tuning/genetic/evolve_ai.nim"
  exec "bin/evolve_ai --generations 10 --population 10 --games 2"
  echo "Quick evolution completed! Results in balance_results/evolution/"

task coevolveAI, "Competitive co-evolution (4 species, 20 generations)":
  echo "Running competitive co-evolution..."
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/coevolution src/ai/tuning/genetic/coevolution.nim"
  exec "bin/coevolution"
  echo "Co-evolution completed! Results in balance_results/coevolution/"

task tuneAIDiagnostics, "Run diagnostics for AI tuning (100 games, full CSV)":
  echo "Running AI tuning diagnostics (100 games, 30 turns)..."
  exec "bin/ec4x --clean-all --backup"
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/run_simulation src/ai/analysis/run_simulation.nim"
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 30"
  echo "\nAnalyzing results..."
  exec "bin/ec4x --all"
  echo "AI tuning diagnostics completed!"

task cleanAITuning, "Clean AI tuning artifacts":
  echo "Cleaning AI tuning artifacts..."
  exec "rm -f bin/genetic_ai bin/evolve_ai bin/coevolution"
  exec "rm -rf balance_results/evolution/"
  exec "rm -rf balance_results/coevolution/"
  echo "AI tuning artifacts cleaned!"

# ==============================================================================
# EC4X Analysis CLI Tasks (Pure Nim - replaces Python scripts)
# ==============================================================================

task analyzeSummary, "Quick diagnostic summary (terminal)":
  echo "Generating quick summary..."
  exec "bin/ec4x --summary"

task analyzeFull, "Full diagnostic analysis (terminal with tables)":
  echo "Generating full terminal analysis..."
  exec "bin/ec4x --full"

task analyzeCompact, "Generate compact AI-friendly summary (~1500 tokens)":
  echo "Generating compact markdown summary..."
  exec "bin/ec4x --compact"

task analyzeDetailed, "Generate detailed markdown report":
  echo "Generating detailed markdown report..."
  exec "bin/ec4x --detailed"

task analyzeAll, "Generate all report formats":
  echo "Generating all report formats..."
  exec "bin/ec4x --all"

task dataInfo, "Show current analysis data status":
  exec "bin/ec4x --info"

task dataClean, "Clean old analysis data (keep last 5 reports, 10 summaries)":
  exec "bin/ec4x --clean"

task dataCleanAll, "Clean ALL analysis data with backup":
  exec "bin/ec4x --clean-all"

task dataArchives, "List archived diagnostic backups":
  exec "bin/ec4x --archives"

# Build ec4x CLI tool
task buildAnalysis, "Build ec4x analysis CLI tool":
  echo "Building ec4x analysis CLI..."
  mkDir "bin"
  exec "nim c -d:release --opt:speed -o:bin/ec4x src/cli/ec4x.nim"
  echo "ec4x CLI built successfully: bin/ec4x"
  echo ""
  echo "Usage examples:"
  echo "  bin/ec4x --summary          # Quick summary"
  echo "  bin/ec4x --full             # Full analysis with tables"
  echo "  bin/ec4x --compact          # Token-efficient (~1500 tokens)"
  echo "  bin/ec4x --all              # All formats"
  echo "  bin/ec4x --info             # Show data status"
  echo "  bin/ec4x --help             # Full help"

