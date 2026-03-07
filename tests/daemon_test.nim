import unittest
import std/[tables, os, options]
import ../src/daemon/[daemon, sam_core]
import ../src/daemon/persistence/[reader, init, writer]
import ../src/engine/init/game_state
import ../src/engine/types/[core, production, ship, facilities, ground_unit]
import ../src/engine/state/[engine, iterators]

test "initModel":
  let model = initModel("data", 30, @["ws://localhost:8080"], 2, 7, 30, 14,
    0, true, true)
  check model.running
  check tables.len(model.games) == 0
  check model.pollInterval == 30
  check model.turnDeadlineMinutes == 0

test "samProcess":
  let loop = initTestDaemonLoop("data")
  let testProposal = Proposal[DaemonModel](
    name: "test",
    payload: proc(model: var DaemonModel) =
      model.running = false
  )
  loop.present(testProposal)
  loop.process()
  check not loop.model.running

test "loadPersistence":
  var loadedCompatible = false
  if dirExists("data/games"):
    for kind, path in walkDir("data/games"):
      if kind == pcDir:
        let dbPath = path / "ec4x.db"
        if fileExists(dbPath):
          try:
            let state = loadFullState(dbPath)
            check state.gameName.len > 0
            check state.turn >= 1
            check state.systemsCount() >= 1
            check state.housesCount() >= 1
            check state.coloniesCount() >= 0
            check state.fleetsCount() >= 0
            loadedCompatible = true
            break
          except ValueError:
            continue
  check loadedCompatible or not dirExists("data/games")

test "loadFullState normalizes legacy pending commissions":
  let testDir = getTempDir() / "ec4x_test_pending_commissions"
  if dirExists(testDir):
    removeDir(testDir)
  createDir(testDir)
  defer:
    if dirExists(testDir):
      removeDir(testDir)

  var state = initGameState(
    setupPath = "scenarios/standard-4-player.kdl",
    gameName = "Pending Commission Normalization",
    configDir = "config",
    dataDir = testDir
  )
  let dbPath = createGameDatabase(state, testDir)

  var ownerColonyId = ColonyId(0)
  let ownerHouseId = state.houses.entities.data[0].id
  for colony in state.allColonies():
    if colony.owner == ownerHouseId:
      ownerColonyId = colony.id
      break

  state.pendingCommissions = @[
    CompletedProject(
      colonyId: ownerColonyId,
      projectType: BuildType.Ship,
      shipClass: some(ShipClass.Corvette),
      facilityClass: none(FacilityClass),
      groundClass: none(GroundClass),
      industrialUnits: 0,
      neoriaId: none(NeoriaId)
    )
  ]
  saveFullState(state)

  let shipsBefore = state.shipsCount()
  let loaded = loadFullState(dbPath)
  check loaded.pendingCommissions.len == 0
  check loaded.shipsCount() == shipsBefore + 1
