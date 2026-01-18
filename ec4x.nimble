# Package

version       = "0.1.0"
author        = "Mason Austin Green"
description   = "EC4X - Asynchronous turn-based 4X wargame"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"

# Dependencies

requires "nim >= 2.0.0"
requires "cligen >= 1.7.0"
requires "nimkdl >= 2.0.6"
requires "db_connector"
requires "ws >= 0.5.0"           # WebSocket client for Nostr relay
requires "zippy >= 0.10.0"       # Compression for Nostr payloads
requires "nimcrypto >= 0.6.0"    # Cryptography for SHA/HMAC
requires "secp256k1"             # Schnorr signing + ECDH
requires "nim_chacha20_poly1305" # ChaCha20 stream cipher

# ==============================================================================
# COMMON FLAGS
# ==============================================================================

const releaseFlags = "-d:release --opt:speed --deepcopy:on"
const debugFlags = "-d:debug --debuginfo --linedir:on --deepcopy:on"

# ==============================================================================
# BUILD TASKS
# ==============================================================================

task buildRelease, "Build main binary (release)":
  echo "Building EC4X moderator..."
  mkDir "bin"
  exec "nim c " & releaseFlags & " -o:bin/ec4x src/moderator/moderator.nim"
  echo "Build completed!"

task buildDebug, "Build main binary (debug)":
  echo "Building EC4X with debug info..."
  mkDir "bin"
  exec "nim c " & debugFlags & " -o:bin/ec4x src/moderator/moderator.nim"
  echo "Debug build completed!"

task buildModerator, "Build moderator CLI (release)":
  echo "Building EC4X moderator..."
  mkDir "bin"
  exec "nim c " & releaseFlags & " -o:bin/ec4x src/moderator/moderator.nim"
  echo "Moderator build completed!"

task buildDaemon, "Build daemon (release)":
  echo "Building EC4X daemon..."
  mkDir "bin"
  exec "nim c " & releaseFlags & " -o:bin/ec4x-daemon src/daemon/daemon.nim"
  echo "Daemon build completed!"

task installDaemon, "Install daemon binary to /usr/local/bin":
  echo "Installing EC4X daemon..."
  mkDir "bin"
  exec "nim c " & releaseFlags & " -o:bin/ec4x-daemon src/daemon/daemon.nim"
  exec "install -m 755 bin/ec4x-daemon /usr/local/bin/ec4x-daemon"
  echo "Daemon installed to /usr/local/bin/ec4x-daemon"

task buildClient, "Build GUI player client":
  echo "Building EC4X GUI Player Client..."
  mkDir "bin"
  exec "nim c " & releaseFlags & " -o:bin/ec4x-client --passC:-Isrc/client/vendor --passC:\"-Wno-incompatible-pointer-types\" src/client/main.nim"
  echo "GUI Client build completed!"

task buildPlayer, "Build dev player CLI/TUI":
  echo "Building EC4X Dev Player CLI/TUI..."
  mkDir "bin"
  exec "nim c " & releaseFlags & " -o:bin/ec4x-play src/player/player.nim"
  echo "Dev Player build completed!"

task buildTui, "Build TUI player (terminal interface)":
  echo "Building EC4X TUI Player..."
  mkDir "bin"
  exec "nim c " & releaseFlags & " -o:bin/ec4x-tui src/player/tui_player.nim"
  echo "TUI Player build completed!"

task buildAll, "Build all binaries (release)":
  echo "Building all EC4X binaries..."
  mkDir "bin"
  exec "nim c " & releaseFlags & " -o:bin/ec4x src/moderator/moderator.nim"
  exec "nim c " & releaseFlags & " -o:bin/ec4x-daemon src/daemon/daemon.nim"
  exec "nim c " & releaseFlags & " -o:bin/ec4x-client --passC:-Isrc/client/vendor --passC:\"-Wno-incompatible-pointer-types\" src/client/main.nim"
  exec "nim c " & releaseFlags & " -o:bin/ec4x-tui src/player/tui_player.nim"
  echo "All builds completed!"

task tidy, "Clean build artifacts":
  echo "Cleaning build artifacts..."
  exec "rm -rf bin/ nimcache/"
  exec "find . -name '*.exe' -delete 2>/dev/null || true"
  exec "find . -name 'test_*' -type f -executable -delete 2>/dev/null || true"
  echo "Clean completed!"

# ==============================================================================
# TEST TASKS
# ==============================================================================

task testAll, "Run all tests (unit + integration + stress)":
  echo "=== Unit Tests ==="
  exec "nimble testUnit"
  echo "\n=== Integration Tests ==="
  exec "nimble testIntegration"
  echo "\n=== Stress Tests (quick) ==="
  exec "nimble testStressQuick"
  echo "\nAll tests completed!"

task testUnit, "Run unit tests":
  echo "Running unit tests..."
  for file in listFiles("tests/unit"):
    if file.endsWith(".nim"):
      echo "  " & file
      exec "nim c -r " & file

task testIntegration, "Run integration tests":
  echo "Running integration tests..."
  exec "nim c -r tests/integration/test_game_initialization.nim"
  exec "nim c -r tests/integration/test_starmap_validation.nim"
  exec "nim c -r tests/integration/test_tech_integration.nim"
  exec "nim c -r tests/integration/test_intel_espionage.nim"
  exec "nim c -r tests/integration/test_capacity_limits.nim"
  exec "nim c -r tests/integration/test_combat.nim"
  exec "nim c -r tests/integration/test_construction_repair_commissioning.nim"
  exec "nim c -r tests/integration/test_fleet_operations.nim"
  exec "nim c -r tests/integration/test_economy.nim"
  exec "nim c -r tests/integration/test_diplomacy.nim"
  exec "nim c -r tests/integration/test_elimination.nim"
  exec "nim c -r tests/integration/test_slot_claim.nim"
  exec "nim c -r tests/daemon/test_replay_protection.nim"
  echo "Running daemon tests..."
  exec "nimble testDaemon"

task testDaemon, "Run daemon integration tests":
  echo "Running daemon tests..."
  exec "nim c -r tests/daemon/kdl_parser_test.nim"
  exec "nim c -r tests/daemon/test_state_kdl.nim"
  exec "nim c -r tests/daemon/test_delta_kdl.nim"
  exec "nim c -r tests/daemon/test_auto_resolve.nim"
  echo "Daemon tests completed!"

task testStress, "Run all stress tests (takes several minutes)":
  echo "Running stress test suite..."
  exec "nim c -r tests/stress/test_simple_stress.nim"
  exec "nim c -r tests/stress/test_engine_stress.nim"
  exec "nim c -r tests/stress/test_state_corruption.nim"
  exec "nim c -r tests/stress/test_pathological_inputs.nim"
  exec "nim c -r tests/stress/test_performance_regression.nim"
  exec "nim c -r tests/stress/test_unknown_unknowns.nim"
  echo "All stress tests completed!"

task testStressQuick, "Run quick stress tests (~30 seconds)":
  echo "Running quick stress tests..."
  exec "nim c -r tests/stress/test_simple_stress.nim"
  exec "nim c -r tests/stress/test_quick_demo.nim"
  echo "Quick stress tests completed!"

# Individual test runners for convenience
task testCER, "Run CER unit tests":
  exec "nim c -r tests/unit/test_cer.nim"

task testTechCosts, "Run tech costs unit tests":
  exec "nim c -r tests/unit/test_tech_costs.nim"

task testDiplomacy, "Run diplomacy unit tests":
  exec "nim c -r tests/unit/test_diplomacy.nim"

task testDetection, "Run detection modifier unit tests":
  exec "nim c -r tests/unit/test_detection.nim"

task testRetreat, "Run ROE retreat unit tests":
  exec "nim c -r tests/unit/test_retreat.nim"

task testTechAdvancement, "Run tech advancement unit tests":
  exec "nim c -r tests/unit/test_tech_advancement.nim"

task testTechEffects, "Run tech effects unit tests":
  exec "nim c -r tests/unit/test_tech_effects.nim"

task testHex, "Run hex grid unit tests":
  exec "nim c -r tests/unit/test_hex.nim"

task testMaintenance, "Run maintenance cost unit tests":
  exec "nim c -r tests/unit/test_maintenance.nim"

# ==============================================================================
# DEVELOPMENT TASKS
# ==============================================================================

task check, "Check engine compiles":
  echo "Checking engine compilation..."
  exec "nim check src/engine/engine.nim"
  echo "Engine compiles successfully!"

task checkAll, "Check all source files compile":
  echo "Checking all sources..."
  exec "nim check src/engine/engine.nim"
  exec "nim check src/moderator/moderator.nim"
  echo "All sources compile!"

task docs, "Generate documentation":
  echo "Generating documentation..."
  exec "nim doc --project --index:on src/engine/engine.nim"
  echo "Documentation generated!"
