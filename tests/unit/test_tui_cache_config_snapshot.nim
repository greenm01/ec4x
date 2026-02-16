## Unit tests for TUI cache config snapshot storage.

import std/[unittest, os, times, options]

import ../../src/common/config_sync
import ../../src/engine/config/engine as config_engine
import ../../src/engine/globals
import ../../src/engine/types/[command, core]
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

  test "save/load/clear order draft":
    let path = tempCachePath()
    if fileExists(path):
      removeFile(path)
    let cache = openTuiCacheAt(path)
    defer:
      cache.close()
      if fileExists(path):
        removeFile(path)

    var packet = CommandPacket()
    packet.houseId = HouseId(2)
    packet.turn = 7
    packet.researchAllocation.economic = 25
    packet.researchAllocation.science = 10

    cache.saveOrderDraft(
      "game-test",
      2,
      7,
      "cfg-hash-1",
      packet
    )

    let loadedOpt = cache.loadOrderDraft("game-test", 2)
    check loadedOpt.isSome
    let draft = loadedOpt.get()
    check draft.turn == 7
    check draft.configHash == "cfg-hash-1"
    check draft.packet.researchAllocation.economic == 25
    check draft.packet.researchAllocation.science == 10

    cache.clearOrderDraft("game-test", 2)
    let clearedOpt = cache.loadOrderDraft("game-test", 2)
    check clearedOpt.isNone
