## Tests for replay protection persistence and cleanup.

import std/[os, times, unittest]
import db_connector/db_sqlite
import ../../src/daemon/persistence/[init, reader, writer]
import ../../src/daemon/transport/nostr/types
import ../../src/engine/init/game_state

proc createTestGame(): tuple[dbPath: string, gameId: string] =
  let testDir = getTempDir() / "ec4x_test_replay_" & $epochTime().int
  createDir(testDir)
  var state = initGameState(
    setupPath = "scenarios/standard-4-player.kdl",
    gameName = "Replay Test",
    configDir = "config",
    dataDir = testDir
  )
  state.turn = 1
  let dbPath = createGameDatabase(state, testDir)
  (dbPath: dbPath, gameId: state.gameId)

proc cleanupTestGame(dbPath: string) =
  let testDir = dbPath.parentDir()
  if dirExists(testDir):
    removeDir(testDir)

suite "Replay Protection":
  test "records and detects processed events":
    let (dbPath, gameId) = createTestGame()
    defer: cleanupTestGame(dbPath)

    writer.insertProcessedEvent(
      dbPath, gameId, 1, EventKindTurnCommands, "evt-inbound",
      reader.ReplayDirection.Inbound
    )

    check reader.hasProcessedEvent(
      dbPath, gameId, EventKindTurnCommands, "evt-inbound",
      reader.ReplayDirection.Inbound
    )

    check not reader.hasProcessedEvent(
      dbPath, gameId, EventKindTurnCommands, "evt-inbound",
      reader.ReplayDirection.Outbound
    )

  test "cleans up turn and time retention":
    let (dbPath, gameId) = createTestGame()
    defer: cleanupTestGame(dbPath)

    writer.insertProcessedEvent(
      dbPath, gameId, 1, EventKindTurnCommands, "evt-old",
      reader.ReplayDirection.Inbound
    )
    writer.insertProcessedEvent(
      dbPath, gameId, 2, EventKindTurnCommands, "evt-keep",
      reader.ReplayDirection.Inbound
    )
    writer.insertProcessedEvent(
      dbPath, gameId, 0, EventKindGameDefinition, "evt-stale",
      reader.ReplayDirection.Outbound
    )

    let db = open(dbPath, "", "", "")
    defer: db.close()
    let oldTimestamp = getTime().toUnix() - int64(8 * 24 * 60 * 60)
    db.exec(
      sql"UPDATE nostr_event_log SET created_at = ? WHERE event_id = ?",
      $oldTimestamp,
      "evt-stale"
    )
    db.exec(
      sql"UPDATE nostr_event_log SET created_at = ? WHERE event_id = ?",
      $oldTimestamp,
      "evt-stale-def"
    )

    writer.cleanupProcessedEvents(dbPath, gameId, 3, 2, 7, 30, 14)

    check not reader.hasProcessedEvent(
      dbPath, gameId, EventKindTurnCommands, "evt-old",
      reader.ReplayDirection.Inbound
    )
    check reader.hasProcessedEvent(
      dbPath, gameId, EventKindTurnCommands, "evt-keep",
      reader.ReplayDirection.Inbound
    )
    check reader.hasProcessedEvent(
      dbPath, gameId, EventKindGameDefinition, "evt-stale",
      reader.ReplayDirection.Outbound
    )

    writer.cleanupProcessedEvents(dbPath, gameId, 3, 2, 0, 0, 0)
    check reader.hasProcessedEvent(
      dbPath, gameId, EventKindGameDefinition, "evt-stale",
      reader.ReplayDirection.Outbound
    )

    writer.cleanupProcessedEvents(dbPath, gameId, 3, 2, 0, 1, 0)
    check not reader.hasProcessedEvent(
      dbPath, gameId, EventKindGameDefinition, "evt-stale",
      reader.ReplayDirection.Outbound
    )
