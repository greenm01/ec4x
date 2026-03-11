import std/[unittest, os]

import ../../src/engine/init/game_state
import ../../src/daemon/persistence/msgpack_state

suite "GameState msgpack roundtrip":
  test "preserves turn for ref-backed GameState":
    let testDir = getTempDir() / "ec4x_test_msgpack_state_roundtrip"
    createDir(testDir)
    defer:
      if dirExists(testDir):
        removeDir(testDir)

    var state = initGameState(
      setupPath = "scenarios/standard-2-player.kdl",
      gameName = "Msgpack Roundtrip",
      configDir = "config",
      dataDir = testDir
    )
    state.turn = 7

    let packed = serializeGameState(state)
    let unpacked = deserializeGameState(packed)

    check unpacked.turn == 7
