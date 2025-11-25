# Package

version       = "0.1.0"
author        = "Mason Austin Green"
description   = "EC4X - Asynchronous turn-based 4X wargame"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
# Note: nimble will look for src/main/moderator.nim and src/main/client.nim
bin           = @["main/moderator", "main/client"]  # daemon not ready yet (needs Nostr dependencies)

# Dependencies

requires "nim >= 2.0.0"
requires "cligen >= 1.7.0"
requires "toml_serialization >= 0.2.0"

# Future Nostr dependencies (TODO: uncomment when implementing)
# requires "websocket >= 0.5.0"
# requires "nimcrypto >= 0.6.0"

# Tasks

task test, "Run the complete test suite":
  echo "Running EC4X test suite..."
  exec "nim c -r tests/test_core.nim"
  # TODO: Add back when tests are created:
  # exec "nim c -r tests/test_starmap_robust.nim"
  # exec "nim c -r tests/test_starmap_validation.nim"
  echo "All tests completed successfully!"

task testCore, "Run core functionality tests":
  echo "Running core functionality tests..."
  exec "nim c -r tests/test_core.nim"

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
  exec "nim c -d:release --opt:speed -o:bin/moderator src/main/moderator.nim"
  exec "nim c -d:release --opt:speed -o:bin/client src/main/client.nim"
  # exec "nim c -d:release --opt:speed -o:bin/daemon src/main/daemon.nim"  # TODO: Enable when dependencies ready
  echo "Build completed successfully!"

task buildDebug, "Build with debug information":
  echo "Building EC4X binaries with debug info..."
  mkDir "bin"
  exec "nim c -d:debug --debuginfo --linedir:on -o:bin/moderator src/main/moderator.nim"
  exec "nim c -d:debug --debuginfo --linedir:on -o:bin/client src/main/client.nim"
  # exec "nim c -d:debug --debuginfo --linedir:on -o:bin/daemon src/main/daemon.nim"  # TODO: Enable when dependencies ready
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

task buildBalance, "Build balance test simulation binary":
  echo "Building balance test simulation binary..."
  echo "Using --forceBuild to ensure clean compilation"
  exec "nim c --forceBuild -d:release --opt:speed -o:tests/balance/run_simulation tests/balance/run_simulation.nim"
  exec "git rev-parse --short HEAD > tests/balance/.build_git_hash"
  echo "Balance test binary built successfully!"
  echo "Git hash: $(cat tests/balance/.build_git_hash)"

task testBalanceQuick, "Quick balance validation (7 turns, 20 games)":
  echo "Running quick balance validation (7 turns, 20 games)..."
  echo "Forcing clean rebuild to prevent stale binary bugs..."
  exec "nim c --forceBuild -d:release --opt:speed -o:tests/balance/run_simulation tests/balance/run_simulation.nim"
  exec "git rev-parse --short HEAD > tests/balance/.build_git_hash"
  exec "python3 run_balance_test_parallel.py --workers 8 --games 20 --turns 7"
  echo "Quick balance validation completed!"

task testBalanceAct1, "Act 1: Land Grab (7 turns, 100 games)":
  echo "Running Act 1 validation (7 turns, 100 games)..."
  exec "nim c --forceBuild -d:release --opt:speed -o:tests/balance/run_simulation tests/balance/run_simulation.nim"
  exec "git rev-parse --short HEAD > tests/balance/.build_git_hash"
  exec "python3 run_balance_test_parallel.py --workers 16 --games 100 --turns 7"
  echo "Act 1 validation completed!"

task testBalanceAct2, "Act 2: Rising Tensions (15 turns, 100 games)":
  echo "Running Act 2 validation (15 turns, 100 games)..."
  exec "nim c --forceBuild -d:release --opt:speed -o:tests/balance/run_simulation tests/balance/run_simulation.nim"
  exec "git rev-parse --short HEAD > tests/balance/.build_git_hash"
  exec "python3 run_balance_test_parallel.py --workers 16 --games 100 --turns 15"
  echo "Act 2 validation completed!"

task testBalanceAct3, "Act 3: Total War (25 turns, 100 games)":
  echo "Running Act 3 validation (25 turns, 100 games)..."
  exec "nim c --forceBuild -d:release --opt:speed -o:tests/balance/run_simulation tests/balance/run_simulation.nim"
  exec "git rev-parse --short HEAD > tests/balance/.build_git_hash"
  exec "python3 run_balance_test_parallel.py --workers 16 --games 100 --turns 25"
  echo "Act 3 validation completed!"

task testBalanceAct4, "Act 4: Endgame (30 turns, 100 games)":
  echo "Running Act 4 validation (30 turns, 100 games)..."
  exec "nim c --forceBuild -d:release --opt:speed -o:tests/balance/run_simulation tests/balance/run_simulation.nim"
  exec "git rev-parse --short HEAD > tests/balance/.build_git_hash"
  exec "python3 run_balance_test_parallel.py --workers 16 --games 100 --turns 30"
  echo "Act 4 validation completed!"

task testBalanceAll4Acts, "Test all 4 acts sequentially (7, 15, 25, 30 turns)":
  echo "Running complete 4-act validation suite..."
  exec "nim c --forceBuild -d:release --opt:speed -o:tests/balance/run_simulation tests/balance/run_simulation.nim"
  exec "git rev-parse --short HEAD > tests/balance/.build_git_hash"
  echo "Git hash: $(cat tests/balance/.build_git_hash)"
  echo "\n=== Act 1: Land Grab (7 turns) ==="
  exec "python3 run_balance_test_parallel.py --workers 16 --games 100 --turns 7"
  echo "\n=== Act 2: Rising Tensions (15 turns) ==="
  exec "python3 run_balance_test_parallel.py --workers 16 --games 100 --turns 15"
  echo "\n=== Act 3: Total War (25 turns) ==="
  exec "python3 run_balance_test_parallel.py --workers 16 --games 100 --turns 25"
  echo "\n=== Act 4: Endgame (30 turns) ==="
  exec "python3 run_balance_test_parallel.py --workers 16 --games 100 --turns 30"
  echo "\nAll 4 acts validated! Total: 400 games"

task cleanBalance, "Clean balance test artifacts":
  echo "Cleaning balance test artifacts..."
  exec "rm -f tests/balance/run_simulation"
  exec "rm -rf balance_results/*"
  echo "Balance test artifacts cleaned!"

# Advanced Balance Testing Tasks

task testBalanceDiagnostics, "Run diagnostic tests with CSV output (50 games, 30 turns)":
  echo "Running diagnostic balance tests (50 games, 30 turns)..."
  exec "nim c --forceBuild -d:release --opt:speed -o:tests/balance/run_simulation tests/balance/run_simulation.nim"
  exec "git rev-parse --short HEAD > tests/balance/.build_git_hash"
  exec "python3 tests/balance/run_parallel_diagnostics.py 50 30 16"
  echo "Diagnostic tests completed! Results in balance_results/diagnostics/"

task testUnknownUnknowns, "Unknown-unknowns detection (200 games, full diagnostics)":
  echo "Running unknown-unknowns detection suite (200 games, 30 turns)..."
  echo "This generates comprehensive CSV data for pattern analysis"
  exec "nim c --forceBuild -d:release --opt:speed -o:tests/balance/run_simulation tests/balance/run_simulation.nim"
  exec "git rev-parse --short HEAD > tests/balance/.build_git_hash"
  echo "Git hash: $(cat tests/balance/.build_git_hash)"
  exec "python3 tests/balance/run_parallel_diagnostics.py 200 30 16"
  echo "\nRunning automatic gap analysis..."
  exec "python3 tests/balance/analyze_phase2_gaps.py"
  echo "\nUnknown-unknowns detection completed!"
  echo "Review analysis output above for anomalies and red flags."

task analyzeDiagnostics, "Analyze diagnostic CSV files for Phase 2 gaps":
  echo "Analyzing diagnostic data for Phase 2 gaps..."
  exec "python3 tests/balance/analyze_phase2_gaps.py"

task analyzeProgression, "Analyze 4-act game progression":
  echo "Analyzing 4-act progression..."
  exec "python3 tests/balance/analyze_4act_progression.py"

task testMapSizes, "Test balance across different map sizes":
  echo "Testing different map sizes (4, 8, 12 players)..."
  exec "nim c --forceBuild -d:release --opt:speed -o:tests/balance/run_simulation tests/balance/run_simulation.nim"
  exec "git rev-parse --short HEAD > tests/balance/.build_git_hash"
  exec "python3 run_map_size_test.py"
  echo "Map size tests completed!"

task testStressAI, "AI stress test (1000 games, crash and behavior detection)":
  echo "Running AI stress test (1000 games, 30 turns each)..."
  echo "This tests AI stability and identifies edge cases"
  exec "nim c --forceBuild -d:release --opt:speed -o:tests/balance/run_simulation tests/balance/run_simulation.nim"
  exec "git rev-parse --short HEAD > tests/balance/.build_git_hash"
  echo "Git hash: $(cat tests/balance/.build_git_hash)"
  exec "python3 tests/balance/run_parallel_diagnostics.py 1000 30 16"
  echo "AI stress test completed! Check balance_results/diagnostics/ for anomalies"

task testStress, "Engine stress test (100k games for crash detection)":
  echo "Running engine stress test (100k games - this will take hours)..."
  echo "This tests engine stability across all configurations"
  exec "nim c --forceBuild -d:release --opt:speed -o:tests/balance/run_simulation tests/balance/run_simulation.nim"
  exec "git rev-parse --short HEAD > tests/balance/.build_git_hash"
  echo "Git hash: $(cat tests/balance/.build_git_hash)"
  exec "python3 run_stress_test.py"
  echo "Engine stress test completed!"
