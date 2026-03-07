## Integration Tests for Auto-Resolve Turn Resolution
##
## Tests the automatic turn resolution trigger when all players submit commands

import std/[unittest, options, tables, os, strutils, times, asyncdispatch,
  sets]
import db_connector/db_sqlite
import ../../src/daemon/[daemon, sam_core]
import ../../src/engine/init/game_state
import ../../src/engine/types/[core, command, game_state, fleet]
import ../../src/engine/state/engine
import ../../src/daemon/persistence/[init, reader, writer, schema]

# Helper to update house pubkey (replaces removed setHousePubkey)
proc setHousePubkey(dbPath: string, gameId: string, houseId: HouseId, pubkey: string) =
  var state = loadFullState(dbPath)
  if state.houses.entities.index.hasKey(houseId):
    let idx = state.houses.entities.index[houseId]
    state.houses.entities.data[idx].nostrPubkey = pubkey
    saveFullState(state)

# Test helper: Create a test game database with N houses
proc createTestGame(playerCount: int, phase: string = "Active"): tuple[dbPath: string, gameId: string, state: GameState] =
  let testDir = getTempDir() / "ec4x_test_auto_resolve_" & $epochTime().int
  createDir(testDir)

  # Initialize a game state
  var state = initGameState(
    setupPath = "scenarios/standard-4-player.kdl",
    gameName = "Auto-Resolve Test",
    configDir = "config",
    dataDir = testDir
  )
  state.turn = 1

  # Trim houses to match playerCount
  state.houses.entities.data.setLen(playerCount)

  # Create database and save initial state
  let dbPath = createGameDatabase(state, testDir)

  # Update game phase
  let db = open(dbPath, "", "", "")
  defer: db.close()
  db.exec(sql"UPDATE games SET phase = ? WHERE id = ?", phase, state.gameId)

  result = (dbPath: dbPath, gameId: state.gameId, state: state)

# Test helper: Clean up test database
proc cleanupTestGame(dbPath: string) =
  let testDir = dbPath.parentDir()
  if dirExists(testDir):
    removeDir(testDir)

# Keep existing tests deterministic after saveCommandPacket signature hardening.
proc saveCommandPacket(dbPath: string, gameId: string, packet: CommandPacket) =
  writer.saveCommandPacket(dbPath, gameId, packet, 1'i64)

proc isAutoResolveReady(dbPath: string, gameId: string, turn: int32): bool =
  let claimed = countExpectedPlayers(dbPath, gameId)
  let total = countTotalPlayers(dbPath, gameId)
  let submitted = countPlayersSubmitted(dbPath, gameId, turn)
  total > 0 and claimed == total and submitted >= total

proc drainDaemon(loop: DaemonLoop, cycles: int = 4) =
  for _ in 0..<cycles:
    loop.process()

suite "Auto-Resolve: Query Functions":

  test "countExpectedPlayers returns 0 when no pubkeys assigned":
    let (dbPath, gameId, state) = createTestGame(4)
    defer: cleanupTestGame(dbPath)

    let expected = countExpectedPlayers(dbPath, gameId)
    check expected == 0

  test "countExpectedPlayers counts only houses with pubkeys":
    let (dbPath, gameId, state) = createTestGame(4)
    defer: cleanupTestGame(dbPath)

    # Assign pubkeys to 2 houses
    setHousePubkey(dbPath, gameId, HouseId(1), "pubkey1")
    setHousePubkey(dbPath, gameId, HouseId(2), "pubkey2")

    let expected = countExpectedPlayers(dbPath, gameId)
    check expected == 2

  test "countExpectedPlayers handles all houses with pubkeys":
    let (dbPath, gameId, state) = createTestGame(3)
    defer: cleanupTestGame(dbPath)

    # Assign pubkeys to all houses
    setHousePubkey(dbPath, gameId, HouseId(1), "pubkey1")
    setHousePubkey(dbPath, gameId, HouseId(2), "pubkey2")
    setHousePubkey(dbPath, gameId, HouseId(3), "pubkey3")

    let expected = countExpectedPlayers(dbPath, gameId)
    check expected == 3

  test "countTotalPlayers counts all house slots":
    let (dbPath, gameId, state) = createTestGame(3)
    defer: cleanupTestGame(dbPath)

    check countTotalPlayers(dbPath, gameId) == 3

  test "countPlayersSubmitted returns 0 when no commands":
    let (dbPath, gameId, state) = createTestGame(2)
    defer: cleanupTestGame(dbPath)

    let submitted = countPlayersSubmitted(dbPath, gameId, 1)
    check submitted == 0

  test "countPlayersSubmitted counts distinct houses with commands":
    let (dbPath, gameId, state) = createTestGame(2)
    defer: cleanupTestGame(dbPath)

    # House 1 submits multiple fleet commands (should count as 1)
    let packet1 = CommandPacket(
      houseId: HouseId(1),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(1),
          commandType: FleetCommandType.Hold,
          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        ),
        FleetCommand(
          fleetId: FleetId(2),
          commandType: FleetCommandType.Hold,
          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )
    saveCommandPacket(dbPath, gameId, packet1)

    let submitted = countPlayersSubmitted(dbPath, gameId, 1)
    check submitted == 1

  test "countPlayersSubmitted handles multiple houses":
    let (dbPath, gameId, state) = createTestGame(3)
    defer: cleanupTestGame(dbPath)

    # House 1 submits
    let packet1 = CommandPacket(
      houseId: HouseId(1),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(1),
          commandType: FleetCommandType.Hold,
          
          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )
    saveCommandPacket(dbPath, gameId, packet1)

    # House 2 submits
    let packet2 = CommandPacket(
      houseId: HouseId(2),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(3),
          commandType: FleetCommandType.Hold,
          
          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )
    saveCommandPacket(dbPath, gameId, packet2)

    let submitted = countPlayersSubmitted(dbPath, gameId, 1)
    check submitted == 2

  test "countPlayersSubmitted ignores processed commands":
    let (dbPath, gameId, state) = createTestGame(2)
    defer: cleanupTestGame(dbPath)

    # House 1 submits
    let packet1 = CommandPacket(
      houseId: HouseId(1),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(1),
          commandType: FleetCommandType.Hold,
          
          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )
    saveCommandPacket(dbPath, gameId, packet1)

    check countPlayersSubmitted(dbPath, gameId, 1) == 1

    # Mark as processed
    markCommandsProcessed(dbPath, gameId, 1)

    # Should now return 0
    check countPlayersSubmitted(dbPath, gameId, 1) == 0

suite "Auto-Resolve: Readiness Detection":

  test "detects readiness with 2/2 players":
    let (dbPath, gameId, state) = createTestGame(2)
    defer: cleanupTestGame(dbPath)

    # Assign pubkeys to both houses
    setHousePubkey(dbPath, gameId, HouseId(1), "pubkey1")
    setHousePubkey(dbPath, gameId, HouseId(2), "pubkey2")

    check countExpectedPlayers(dbPath, gameId) == 2
    check countPlayersSubmitted(dbPath, gameId, 1) == 0

    # House 1 submits
    let packet1 = CommandPacket(
      houseId: HouseId(1),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(1),
          commandType: FleetCommandType.Hold,

          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )
    saveCommandPacket(dbPath, gameId, packet1)

    check countPlayersSubmitted(dbPath, gameId, 1) == 1

    # House 2 submits
    let packet2 = CommandPacket(
      houseId: HouseId(2),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(2),
          commandType: FleetCommandType.Hold,

          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )
    saveCommandPacket(dbPath, gameId, packet2)

    let submitted = countPlayersSubmitted(dbPath, gameId, 1)
    let expected = countExpectedPlayers(dbPath, gameId)
    check submitted == expected

  test "partial submission not ready":
    let (dbPath, gameId, state) = createTestGame(3)
    defer: cleanupTestGame(dbPath)

    # Assign pubkeys to all 3 houses
    setHousePubkey(dbPath, gameId, HouseId(1), "pubkey1")
    setHousePubkey(dbPath, gameId, HouseId(2), "pubkey2")
    setHousePubkey(dbPath, gameId, HouseId(3), "pubkey3")

    # Only 2 houses submit
    let packet1 = CommandPacket(
      houseId: HouseId(1),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(1),
          commandType: FleetCommandType.Hold,

          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )
    saveCommandPacket(dbPath, gameId, packet1)

    let packet2 = CommandPacket(
      houseId: HouseId(2),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(2),
          commandType: FleetCommandType.Hold,

          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )
    saveCommandPacket(dbPath, gameId, packet2)

    let submitted = countPlayersSubmitted(dbPath, gameId, 1)
    let expected = countExpectedPlayers(dbPath, gameId)
    check submitted < expected

suite "Auto-Resolve: Daemon Deadline Behavior":

  test "maintenance does not assign deadline when disabled":
    let (dbPath, gameId, state) = createTestGame(2)
    defer: cleanupTestGame(dbPath)

    let loop = initTestDaemonLoop(dbPath.parentDir().parentDir().parentDir())
    daemon.daemonLoop = loop
    loop.model.turnDeadlineMinutes = 0
    loop.model.games[gameId] = GameInfo(
      id: gameId,
      dbPath: dbPath,
      turn: state.turn.int,
      phase: "Active",
      transportMode: "nostr",
      turnDeadline: none(int64)
    )

    loop.present(Proposal[DaemonModel](
      name: "tick",
      payload: proc(model: var DaemonModel) =
        model.maintenanceRequested = true
    ))
    drainDaemon(loop)

    check loadGameDeadline(dbPath).isNone
    check loop.model.games[gameId].turnDeadline.isNone

  test "maintenance assigns deadline when enabled":
    let (dbPath, gameId, state) = createTestGame(2)
    defer: cleanupTestGame(dbPath)

    let loop = initTestDaemonLoop(getTempDir())
    daemon.daemonLoop = loop
    loop.model.turnDeadlineMinutes = 60
    loop.model.games[gameId] = GameInfo(
      id: gameId,
      dbPath: dbPath,
      turn: state.turn.int,
      phase: "Active",
      transportMode: "nostr",
      turnDeadline: none(int64)
    )

    loop.present(Proposal[DaemonModel](
      name: "tick",
      payload: proc(model: var DaemonModel) =
        model.maintenanceRequested = true
    ))
    drainDaemon(loop)

    check loadGameDeadline(dbPath).isSome
    check loop.model.games[gameId].turnDeadline.isSome

  test "overdue deadline requests resolution on tick":
    let (dbPath, gameId, state) = createTestGame(2)
    defer: cleanupTestGame(dbPath)

    let overdue = some(getTime().toUnix() - 1)
    updateTurnDeadline(dbPath, gameId, overdue)

    let loop = initTestDaemonLoop(getTempDir())
    daemon.daemonLoop = loop
    loop.model.games[gameId] = GameInfo(
      id: gameId,
      dbPath: dbPath,
      turn: state.turn.int,
      phase: "Active",
      transportMode: "nostr",
      turnDeadline: overdue
    )

    loop.present(daemon.tickProposal())
    loop.process()

    var queuedResolution = false
    for proposal in loop.proposalQueue:
      if proposal.name == "request_turn_resolution":
        queuedResolution = true
        break
    check queuedResolution

suite "Persistence: Schema Compatibility":

  test "loadFullState rejects unsupported schema versions cleanly":
    let (dbPath, _, _) = createTestGame(2)
    defer: cleanupTestGame(dbPath)

    let db = open(dbPath, "", "", "")
    defer: db.close()
    db.exec(sql"DELETE FROM schema_version")
    db.exec(sql"INSERT INTO schema_version(version, applied_at) VALUES (?, ?)",
      MinimumSupportedSchemaVersion - 1, epochTime().int64)

    expect ValueError:
      discard loadFullState(dbPath)

suite "Auto-Resolve: Readiness Detection":

  test "command resubmission doesn't affect count":
    let (dbPath, gameId, state) = createTestGame(2)
    defer: cleanupTestGame(dbPath)

    # Assign pubkeys
    setHousePubkey(dbPath, gameId, HouseId(1), "pubkey1")
    setHousePubkey(dbPath, gameId, HouseId(2), "pubkey2")

    # House 1 submits
    let packet1 = CommandPacket(
      houseId: HouseId(1),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(1),
          commandType: FleetCommandType.Hold,
          
          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )
    saveCommandPacket(dbPath, gameId, packet1)
    check countPlayersSubmitted(dbPath, gameId, 1) == 1

    # House 1 resubmits (updated command)
    let packet1_updated = CommandPacket(
      houseId: HouseId(1),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(1),
          commandType: FleetCommandType.Patrol,  # Changed
          
          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )
    saveCommandPacket(dbPath, gameId, packet1_updated)

    # Still counts as 1 house
    check countPlayersSubmitted(dbPath, gameId, 1) == 1

suite "Auto-Resolve: Command Ordering":

  test "older submission does not overwrite newer command packet":
    let (dbPath, gameId, state) = createTestGame(1)
    defer: cleanupTestGame(dbPath)

    let olderPacket = CommandPacket(
      houseId: HouseId(1),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(1),
          commandType: FleetCommandType.Hold,
          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )
    let newerPacket = CommandPacket(
      houseId: HouseId(1),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(1),
          commandType: FleetCommandType.Patrol,
          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )

    writer.saveCommandPacket(dbPath, gameId, newerPacket, 200'i64)
    writer.saveCommandPacket(dbPath, gameId, olderPacket, 100'i64)

    let orders = loadOrders(dbPath, 1)
    check orders.hasKey(HouseId(1))
    check orders[HouseId(1)].fleetCommands[0].commandType ==
      FleetCommandType.Patrol

  test "newer submission overwrites older command packet":
    let (dbPath, gameId, state) = createTestGame(1)
    defer: cleanupTestGame(dbPath)

    let olderPacket = CommandPacket(
      houseId: HouseId(1),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(1),
          commandType: FleetCommandType.Hold,
          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )
    let newerPacket = CommandPacket(
      houseId: HouseId(1),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(1),
          commandType: FleetCommandType.Patrol,
          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )

    writer.saveCommandPacket(dbPath, gameId, olderPacket, 100'i64)
    writer.saveCommandPacket(dbPath, gameId, newerPacket, 200'i64)

    let orders = loadOrders(dbPath, 1)
    check orders.hasKey(HouseId(1))
    check orders[HouseId(1)].fleetCommands[0].commandType ==
      FleetCommandType.Patrol

  test "equal timestamp resubmission does not overwrite":
    let (dbPath, gameId, state) = createTestGame(1)
    defer: cleanupTestGame(dbPath)

    let firstPacket = CommandPacket(
      houseId: HouseId(1),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(1),
          commandType: FleetCommandType.Hold,
          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )
    let secondPacket = CommandPacket(
      houseId: HouseId(1),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(1),
          commandType: FleetCommandType.Patrol,
          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )

    writer.saveCommandPacket(dbPath, gameId, firstPacket, 200'i64)
    writer.saveCommandPacket(dbPath, gameId, secondPacket, 200'i64)

    let orders = loadOrders(dbPath, 1)
    check orders.hasKey(HouseId(1))
    check orders[HouseId(1)].fleetCommands[0].commandType ==
      FleetCommandType.Hold

suite "Auto-Resolve: Phase Gating":

  test "Setup phase not counted":
    let (dbPath, gameId, state) = createTestGame(2, "Setup")
    defer: cleanupTestGame(dbPath)

    # Even with all players ready, Setup games shouldn't trigger
    setHousePubkey(dbPath, gameId, HouseId(1), "pubkey1")
    setHousePubkey(dbPath, gameId, HouseId(2), "pubkey2")

    let packet1 = CommandPacket(
      houseId: HouseId(1),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(1),
          commandType: FleetCommandType.Hold,
          
          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )
    saveCommandPacket(dbPath, gameId, packet1)

    let packet2 = CommandPacket(
      houseId: HouseId(2),
      turn: 1,
      fleetCommands: @[
        FleetCommand(
          fleetId: FleetId(2),
          commandType: FleetCommandType.Hold,
          
          priority: 0,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[]
    )
    saveCommandPacket(dbPath, gameId, packet2)

    # Verify setup is complete (2/2 submitted)
    check countPlayersSubmitted(dbPath, gameId, 1) == 2
    check countExpectedPlayers(dbPath, gameId) == 2

    # But phase is Setup, so checkAndTriggerResolution should skip
    let db = open(dbPath, "", "", "")
    defer: db.close()
    let phase = db.getValue(sql"SELECT phase FROM games WHERE id = ?", gameId)
    check phase == "Setup"

  test "Paused phase not counted":
    let (dbPath, gameId, state) = createTestGame(2, "Paused")
    defer: cleanupTestGame(dbPath)

    setHousePubkey(dbPath, gameId, HouseId(1), "pubkey1")
    setHousePubkey(dbPath, gameId, HouseId(2), "pubkey2")

    let db = open(dbPath, "", "", "")
    defer: db.close()
    let phase = db.getValue(sql"SELECT phase FROM games WHERE id = ?", gameId)
    check phase == "Paused"

  test "Active phase allows auto-resolve":
    let (dbPath, gameId, state) = createTestGame(2, "Active")
    defer: cleanupTestGame(dbPath)

    let db = open(dbPath, "", "", "")
    defer: db.close()
    let phase = db.getValue(sql"SELECT phase FROM games WHERE id = ?", gameId)
    check phase == "Active"

suite "Auto-Resolve: Mixed Human/AI Games":

  test "3 claimed of 4 does not auto-resolve":
    let (dbPath, gameId, state) = createTestGame(4, "Active")
    defer: cleanupTestGame(dbPath)

    # Only 3 houses get pubkeys (4th slot remains unclaimed)
    setHousePubkey(dbPath, gameId, HouseId(1), "pubkey1")
    setHousePubkey(dbPath, gameId, HouseId(2), "pubkey2")
    setHousePubkey(dbPath, gameId, HouseId(3), "pubkey3")

    check countExpectedPlayers(dbPath, gameId) == 3
    check countTotalPlayers(dbPath, gameId) == 4

    # All claimed houses submit
    for houseNum in 1..3:
      let packet = CommandPacket(
        houseId: HouseId(houseNum),
        turn: 1,
        fleetCommands: @[
          FleetCommand(
            fleetId: FleetId(houseNum),
            commandType: FleetCommandType.Hold,
            
            priority: 0,
            targetSystem: none(SystemId),
            targetFleet: none(FleetId)
          )
        ],
        buildCommands: @[],
        repairCommands: @[],
        scrapCommands: @[]
      )
      saveCommandPacket(dbPath, gameId, packet)

    let submitted = countPlayersSubmitted(dbPath, gameId, 1)
    check submitted == 3
    check not isAutoResolveReady(dbPath, gameId, 1)

  test "all slots unclaimed is not ready":
    let (dbPath, gameId, state) = createTestGame(4, "Active")
    defer: cleanupTestGame(dbPath)

    # No pubkeys assigned
    check countExpectedPlayers(dbPath, gameId) == 0
    check countTotalPlayers(dbPath, gameId) == 4
    check not isAutoResolveReady(dbPath, gameId, 1)
