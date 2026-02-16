## Unit tests for TUI cache config snapshot storage.

import std/[unittest, os, times, options]

import ../../src/common/config_sync
import ../../src/engine/config/engine as config_engine
import ../../src/engine/globals
import ../../src/player/state/tui_cache

gameConfig = config_engine.loadGameConfig()

proc tempCachePath(): string =
  let ts = $epochTime().int64
  getTempDir() / ("ec4x_cache_test_" & ts & ".db")

suite "TuiCache Config Snapshot":
  test "save and load latest config snapshot":
    let path = tempCachePath()
    if fileExists(path):
      removeFile(path)
    let cache = openTuiCacheAt(path)
    defer:
      cache.close()
      if fileExists(path):
        removeFile(path)

    let snapshot = buildTuiRulesSnapshot(gameConfig)
    cache.saveConfigSnapshot("game-test", snapshot)

    let loadedOpt = cache.loadLatestConfigSnapshot("game-test")
    check loadedOpt.isSome
    check loadedOpt.get().configHash == snapshot.configHash
    check loadedOpt.get().schemaVersion == snapshot.schemaVersion
