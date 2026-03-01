import unittest
import std/[tables, os]
import ../src/daemon/[daemon, sam_core]
import ../src/daemon/persistence/reader
import ../src/engine/state/engine

test "initModel":
  let model = initModel("data", 30, @["ws://localhost:8080"], 2, 7, 30, 14,
    60, true, true)
  check model.running
  check tables.len(model.games) == 0
  check model.pollInterval == 30

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
  if dirExists("data/games"):
    for kind, path in walkDir("data/games"):
      if kind == pcDir:
        let dbPath = path / "ec4x.db"
        if fileExists(dbPath):
          let state = loadFullState(dbPath)
          check state.gameName.len > 0
          check state.turn >= 1
          check state.systemsCount() >= 1
          check state.housesCount() >= 1
          check state.coloniesCount() >= 0
          check state.fleetsCount() >= 0
          break

