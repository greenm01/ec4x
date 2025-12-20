# Package

version       = "0.1.0"
author        = "Mason Austin Green"
description   = "EC4X - Asynchronous turn-based 4X wargame"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["cli/ec4x", "ai/analysis/run_simulation"]

# Dependencies

requires "nim >= 2.0.0"
requires "cligen >= 1.7.0"
requires "toml_serialization >= 0.2.0"
requires "datamancer >= 0.4.0"
requires "terminaltables >= 0.1.0"
requires "db_connector"

# ==============================================================================
# BUILD TASKS
# ==============================================================================

task buildPreCommit, "Build main binaries (for pre-commit hook)":
  echo "Building EC4X binaries..."
  mkDir "bin"
  exec "nim c --hints:off --warnings:off -d:release --opt:speed --passL:-lsqlite3 -o:bin/run_simulation src/ai/analysis/run_simulation.nim"
  exec "nim c --hints:off --warnings:off -d:release --opt:speed -o:bin/ec4x src/cli/ec4x.nim"
  echo "Build completed successfully!"

task buildAll, "Build all binaries":
  echo "Building EC4X binaries..."
  mkDir "bin"
  #exec "nim c --hints:off --warnings:off -d:release --opt:speed -o:bin/run_simulation src/ai/analysis/run_simulation.nim"
  #exec "nim c --hints:off --warnings:off -d:release --opt:speed -o:bin/ec4x src/cli/ec4x.nim"
  exec "nim c --hints:off --warnings:off -d:release --opt:speed -o:bin/moderator src/main/moderator.nim"
  echo "Build completed successfully!"

task buildDebug, "Build with debug information":
  echo "Building EC4X binaries with debug info..."
  mkDir "bin"
  exec "nim c --warnings:on -d:debug --debuginfo --linedir:on -o:bin/ec4x src/cli/ec4x.nim"
  exec "nim c --warnings:on -d:debug --debuginfo --linedir:on -o:bin/run_simulation src/ai/analysis/run_simulation.nim"
  echo "Debug build completed successfully!"

task buildSimulation, "Build parallel simulation (C API, static)":
  echo "Building parallel simulation binary (C API with pthreads)..."
  echo "Cleaning build artifacts and diagnostic data..."
  exec "rm -rf bin/ nimcache/"
  exec "find balance_results/diagnostics/ -type f -delete 2>/dev/null || true"
  mkDir "bin"
  # Step 1: Compile Nim engine as static library (using arc GC for thread safety)
  exec "nim c --app:staticlib --noMain --opt:speed --threads:on --mm:arc --passL:-lsqlite3 -o:bin/libec4x_engine.a src/c_api/engine_ffi.nim"
  # Step 2: Compile C orchestrator and link statically
  exec "gcc -O3 -pthread -o bin/run_simulation src/c_api/run_simulation.c bin/libec4x_engine.a -lsqlite3 -lm -ldl"
  exec "git rev-parse --short HEAD > bin/.build_git_hash"
  echo "Build completed! Git hash: $(cat bin/.build_git_hash)"
  echo "Run with: ./bin/run_simulation"

task buildSimulationNim, "Build Nim simulation (legacy, sequential)":
  echo "Building Nim simulation binary (legacy, sequential)..."
  exec "nim c --forceBuild -d:release --opt:speed --passL:-lsqlite3 -o:bin/run_simulation_nim src/ai/analysis/run_simulation.nim"
  exec "git rev-parse --short HEAD > bin/.build_git_hash"
  echo "Build completed! Git hash: $(cat bin/.build_git_hash)"

task buildCAPI, "Build C API with dynamic linking (advanced)":
  echo "Building C API simulation with dynamic linking..."
  echo "Cleaning build artifacts and diagnostic data..."
  exec "rm -rf bin/ nimcache/"
  exec "find balance_results/diagnostics/ -type f -delete 2>/dev/null || true"
  mkDir "bin"
  # Step 1: Compile Nim engine as shared library
  exec "nim c --app:lib --noMain --opt:speed --threads:on --mm:arc --passL:-lsqlite3 -o:bin/libec4x_engine.so src/c_api/engine_ffi.nim"
  # Step 2: Compile C orchestrator and link dynamically
  exec "gcc -O3 -pthread -o bin/run_simulation_c src/c_api/run_simulation.c -Lbin -lec4x_engine -lm -ldl"
  exec "git rev-parse --short HEAD > bin/.build_git_hash"
  echo "Dynamic C API simulation built! Git hash: $(cat bin/.build_git_hash)"
  echo "Run with: LD_LIBRARY_PATH=bin ./bin/run_simulation_c"

task buildAnalysis, "Build ec4x analysis CLI tool":
  echo "Building ec4x analysis CLI..."
  mkDir "bin"
  exec "nim c -d:release --opt:speed -o:bin/ec4x src/cli/ec4x.nim"
  echo "ec4x CLI built successfully!"

task buildAITuning, "Build AI tuning tools (genetic algorithm)":
  echo "Building AI tuning tools..."
  mkDir "bin"
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/genetic_ai src/ai/tuning/genetic/genetic_ai.nim"
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/evolve_ai src/ai/tuning/genetic/evolve_ai.nim"
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/coevolution src/ai/tuning/genetic/coevolution.nim"
  echo "AI tuning tools built!"

# ==============================================================================
# DEVELOPMENT & UTILITY TASKS
# ==============================================================================

task check, "Check syntax of all source files":
  echo "Checking syntax..."
  exec "nim check src/core.nim"
  exec "nim check src/cli/ec4x.nim"
  echo "All syntax checks passed!"

task tidy, "Clean build artifacts":
  echo "Cleaning build artifacts..."
  exec "rm -rf bin/ nimcache/"
  echo "Cleaning balance data..."
  exec "find balance_results/ -type f -delete"
  exec "find . -name '*.exe' -delete 2>/dev/null || true"
  exec "find . -name 'test_*' -type f -executable -delete 2>/dev/null || true"
  echo "Clean completed!"

task docs, "Generate documentation":
  echo "Generating documentation..."
  exec "nim doc --project --index:on --git.url:https://github.com/greenm01/ec4x --git.commit:main src/core.nim"
  echo "Documentation generated!"

# ==============================================================================
# UNIT & INTEGRATION TESTS
# ==============================================================================

task test, "Run complete test suite with analysis":
  exec "rm -f test_report.csv"
  exec "tests/run_all_tests.py --types all --report test_report.csv"

task testQuick, "Run complete test suite (no CSV report)":
  exec "tests/run_all_tests.py --types all"

task testUnit, "Run unit tests only":
  exec "tests/run_all_tests.py --types unit"

task testIntegration, "Run integration tests":
  exec "tests/run_all_tests.py --types integration"

task testUnits, "Test all unit construction":
  echo "Testing all 34 game asset types..."
  exec "nim c -r tests/integration/test_all_units_construction.nim"

task testEconomy, "Test M5 economy system":
  exec "nim c -r tests/integration/test_m5_economy_integration.nim"

task testTechnology, "Test technology advancement":
  exec "nim c -r tests/integration/test_technology_comprehensive.nim"

task testDiplomacy, "Test diplomacy system":
  exec "nim c -r tests/integration/test_diplomacy.nim"

task testPrestige, "Test prestige system":
  exec "nim c -r tests/integration/test_prestige_comprehensive.nim"

task testComprehensive, "Run all comprehensive test suites":
  echo "=== Analytics Engine Tests ==="
  exec "nim c -r tests/integration/test_analytics_engine.nim"
  echo "\n=== Combat Engine Tests ==="
  exec "nim c -r tests/integration/test_combat_comprehensive.nim"
  echo "\n=== Unit Validation Tests ==="
  exec "nim c -r tests/integration/test_all_units_comprehensive.nim"
  echo "\n=== Resolution Engine Tests ==="
  exec "nim c -r tests/integration/test_resolution_comprehensive.nim"
  echo "All comprehensive tests completed!"

# ==============================================================================
# STRESS TESTS
# ==============================================================================

task testStress, "Run stress tests":
  exec "tests/stress/run_stress_tests.py"

task testStressQuick, "Run stress tests in quick mode":
  exec "tests/stress/run_stress_tests.py --quick"

task testStressEngine, "Run ALL engine stress tests (10-30 min)":
  echo "Running comprehensive engine stress test suite..."
  echo "⚠️  WARNING: This will take 10-30 minutes"
  echo "\n=== State Corruption Tests ==="
  exec "nim c -r tests/stress/test_state_corruption.nim"
  echo "\n=== Pathological Input Fuzzing ==="
  exec "nim c -r tests/stress/test_pathological_inputs.nim"
  echo "\n=== Performance Regression Tests ==="
  exec "nim c -r tests/stress/test_performance_regression.nim"
  echo "\n=== Unknown-Unknowns Detection ==="
  exec "nim c -r tests/stress/test_unknown_unknowns.nim"
  echo "✅ All engine stress tests completed!"

task testStressEngineQuick, "Quick engine stress test":
  echo "=== State Corruption (quick) ==="
  exec "nim c -r tests/stress/test_state_corruption.nim -d:STRESS_QUICK"
  echo "\n=== Pathological Input Fuzzing ==="
  exec "nim c -r tests/stress/test_pathological_inputs.nim"
  echo "✅ Quick stress tests completed!"

task testStressAI, "AI stress test (1000 games)":
  echo "Running AI stress test (1000 games, 30 turns each)..."
  exec "bin/ec4x --clean-all --backup"
  exec "nimble buildSimulation"
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 1000 --turns 30"
  exec "bin/ec4x --all"
  echo "AI stress test completed!"

# ==============================================================================
# BALANCE TESTING
# ==============================================================================

task testBalanceQuick, "Quick balance validation (20 games, 7 turns)":
  echo "Running quick balance validation..."
  exec "bin/ec4x --clean-all --backup"
  exec "nimble buildSimulation"
  exec "python3 scripts/run_balance_test_parallel.py --workers 8 --games 20 --turns 7"
  exec "bin/ec4x --all"
  echo "Quick balance validation completed!"

task testBalanceAct1, "Act 1: Land Grab (100 games, 7 turns)":
  echo "Running Act 1 validation..."
  exec "bin/ec4x --clean-all --backup"
  exec "nimble buildSimulation"
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 7"
  exec "bin/ec4x --all"

task testBalanceAct2, "Act 2: Rising Tensions (100 games, 15 turns)":
  echo "Running Act 2 validation..."
  exec "bin/ec4x --clean-all --backup"
  exec "nimble buildSimulation"
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 15"
  exec "bin/ec4x --all"

task testBalanceAct3, "Act 3: Total War (100 games, 25 turns)":
  echo "Running Act 3 validation..."
  exec "bin/ec4x --clean-all --backup"
  exec "nimble buildSimulation"
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 25"
  exec "bin/ec4x --all"

task testBalanceAct4, "Act 4: Endgame (100 games, 30 turns)":
  echo "Running Act 4 validation..."
  exec "bin/ec4x --clean-all --backup"
  exec "nimble buildSimulation"
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 30"
  exec "bin/ec4x --all"

task testBalanceAll4Acts, "Test all 4 acts sequentially (400 games total)":
  echo "Running complete 4-act validation suite..."
  exec "bin/ec4x --clean-all --backup"
  exec "nimble buildSimulation"
  echo "\n=== Act 1: Land Grab (7 turns) ==="
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 7"
  echo "\n=== Act 2: Rising Tensions (15 turns) ==="
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 15"
  echo "\n=== Act 3: Total War (25 turns) ==="
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 25"
  echo "\n=== Act 4: Endgame (30 turns) ==="
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 100 --turns 30"
  exec "bin/ec4x --all"
  echo "\nAll 4 acts validated! Total: 400 games"

task testUnknownUnknowns, "Unknown-unknowns detection (200 games)":
  echo "Running unknown-unknowns detection suite (200 games)..."
  exec "bin/ec4x --clean-all --backup"
  exec "nimble buildSimulation"
  exec "python3 scripts/run_balance_test_parallel.py --workers 16 --games 200 --max-turns 45"
  exec "bin/ec4x --all"
  echo "Check balance_results/reports/latest.md for analysis"

# ==============================================================================
# DATA ANALYSIS TASKS
# ==============================================================================

task analyzeSummary, "Quick diagnostic summary (terminal)":
  exec "bin/ec4x --summary"

task analyzeFull, "Full diagnostic analysis (terminal with tables)":
  exec "bin/ec4x --full"

task analyzeCompact, "Generate compact AI-friendly summary (~1500 tokens)":
  exec "bin/ec4x --compact"

task analyzeDetailed, "Generate detailed markdown report":
  exec "bin/ec4x --detailed"

task analyzeAll, "Generate all report formats":
  exec "bin/ec4x --all"

task dataInfo, "Show current analysis data status":
  exec "bin/ec4x --info"

task dataClean, "Clean old analysis data (keep last 5 reports, 10 summaries)":
  exec "bin/ec4x --clean"

task dataCleanAll, "Clean ALL analysis data with backup":
  exec "bin/ec4x --clean-all"

task dataArchives, "List archived diagnostic backups":
  exec "bin/ec4x --archives"

# ==============================================================================
# AI TUNING & EVOLUTION
# ==============================================================================

task evolveAI, "Evolve AI personalities (50 gen, 20 pop)":
  echo "Evolving AI personalities via genetic algorithm..."
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/evolve_ai src/ai/tuning/genetic/evolve_ai.nim"
  exec "bin/evolve_ai --generations 50 --population 20 --games 4"
  echo "Results in balance_results/evolution/"

task evolveAIQuick, "Quick AI evolution test (10 gen, 10 pop)":
  echo "Running quick AI evolution test..."
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/evolve_ai src/ai/tuning/genetic/evolve_ai.nim"
  exec "bin/evolve_ai --generations 10 --population 10 --games 2"

task coevolveAI, "Competitive co-evolution (4 species, 20 generations)":
  exec "nim c --forceBuild -d:release --opt:speed -o:bin/coevolution src/ai/tuning/genetic/coevolution.nim"
  exec "bin/coevolution"
  echo "Results in balance_results/coevolution/"

# ==============================================================================
# CLEANUP TASKS
# ==============================================================================

task cleanBalance, "Clean balance test artifacts":
  exec "rm -f bin/run_simulation"
  exec "bin/ec4x 'data clean'"

task cleanBalanceAll, "Clean ALL balance data including archives":
  exec "rm -f bin/run_simulation"
  exec "bin/ec4x --clean-all"
  echo "⚠ Warning: This deletes historical test data permanently"

task cleanAITuning, "Clean AI tuning artifacts":
  exec "rm -f bin/genetic_ai bin/evolve_ai bin/coevolution"
  exec "rm -rf balance_results/evolution/ balance_results/coevolution/"
