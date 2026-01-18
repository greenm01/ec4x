##
## Integration test for slot claim validation and persistence.

import std/[asyncdispatch, options, os, times, unittest, tables]
import ../../src/daemon/daemon
import ../../src/daemon/transport/nostr/[events, crypto, client]
import ../../src/daemon/persistence/[init, reader]
import ../../src/engine/init/game_state
import ../../src/engine/types/core

proc createTestGame(tempRoot: string): tuple[dbPath: string, gameId: string] =
  var state = initGameState(
    setupPath = "scenarios/standard-4-player.kdl",
    gameName = "Slot Claim Test",
    configDir = "config",
    dataDir = tempRoot
  )
  state.turn = 1
  let dbPath = createGameDatabase(state, tempRoot)
  (dbPath: dbPath, gameId: state.gameId)

proc setupDaemon(tempRoot: string, gameId: string, dbPath: string) =
  daemonLoop = initTestDaemonLoop(tempRoot)
  let gameKey = GameId(gameId)
  daemonLoop.model.nostrClient = newNostrClient(@[])
  daemonLoop.model.games[gameKey] = GameInfo(
    id: gameKey,
    dbPath: dbPath,
    turn: 1,
    phase: "Active",
    transportMode: "nostr"
  )

proc prepareXdg(tempRoot: string): string =
  let previous = getEnv("XDG_DATA_HOME")
  let xdgDir = tempRoot / "xdg"
  createDir(xdgDir)
  putEnv("XDG_DATA_HOME", xdgDir)
  previous

proc restoreXdg(previous: string) =
  if previous.len == 0:
    putEnv("XDG_DATA_HOME", "")
  else:
    putEnv("XDG_DATA_HOME", previous)

suite "Slot Claim Integration":
  test "valid invite code assigns house":
    let tempRoot = getTempDir() / "ec4x_test_slot_claim_valid_" & $epochTime().int
    createDir(tempRoot)
    let previousXdg = prepareXdg(tempRoot)
    defer: restoreXdg(previousXdg)
    let (dbPath, gameId) = createTestGame(tempRoot)
    setupDaemon(tempRoot, gameId, dbPath)

    let inviteOpt = getHouseInviteCode(dbPath, gameId, HouseId(1))
    check inviteOpt.isSome
    let inviteCode = inviteOpt.get()

    let playerKeys = generateKeyPair()
    var event = createSlotClaim(gameId, inviteCode, playerKeys.publicKey)
    let privBytes = hexToBytes32(playerKeys.privateKey)
    signEvent(event, privBytes)

    waitFor processSlotClaim(event)

    let pubkeyOpt = getHousePubkey(dbPath, gameId, HouseId(1))
    check pubkeyOpt.isSome
    check pubkeyOpt.get() == playerKeys.publicKey

    removeDir(tempRoot)

  test "invalid invite code is rejected":
    let tempRoot = getTempDir() / "ec4x_test_slot_claim_invalid_" & $epochTime().int
    createDir(tempRoot)
    let previousXdg = prepareXdg(tempRoot)
    defer: restoreXdg(previousXdg)
    let (dbPath, gameId) = createTestGame(tempRoot)
    setupDaemon(tempRoot, gameId, dbPath)

    let playerKeys = generateKeyPair()
    var event = createSlotClaim(gameId, "invalid-code", playerKeys.publicKey)
    let privBytes = hexToBytes32(playerKeys.privateKey)
    signEvent(event, privBytes)

    waitFor processSlotClaim(event)

    let pubkeyOpt = getHousePubkey(dbPath, gameId, HouseId(1))
    check pubkeyOpt.isNone

    removeDir(tempRoot)
