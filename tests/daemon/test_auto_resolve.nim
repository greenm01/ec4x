## Integration Tests for Auto-Resolve Turn Resolution
##
## Tests the automatic turn resolution trigger when all players submit commands

import std/[unittest, options, tables, os, strutils, times]
import db_connector/db_sqlite
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

    check countPlayersSubmitted(dbPath, gameId, 1) == 1  # Not ready yet

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
    check submitted == expected  # Ready to resolve!

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
    check submitted < expected  # Not ready yet (2/3)

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

  test "3 human + 1 AI waits for 3 human submissions":
    let (dbPath, gameId, state) = createTestGame(4, "Active")
    defer: cleanupTestGame(dbPath)

    # Only 3 houses get pubkeys (4th is AI)
    setHousePubkey(dbPath, gameId, HouseId(1), "pubkey1")
    setHousePubkey(dbPath, gameId, HouseId(2), "pubkey2")
    setHousePubkey(dbPath, gameId, HouseId(3), "pubkey3")
    # HouseId(4) has no pubkey (AI)

    check countExpectedPlayers(dbPath, gameId) == 3

    # All 3 humans submit
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
    let expected = countExpectedPlayers(dbPath, gameId)
    check submitted == expected  # 3/3 humans ready (AI doesn't count)

  test "all AI game has 0 expected players":
    let (dbPath, gameId, state) = createTestGame(4, "Active")
    defer: cleanupTestGame(dbPath)

    # No pubkeys assigned (all AI)
    check countExpectedPlayers(dbPath, gameId) == 0
