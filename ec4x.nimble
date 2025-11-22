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
