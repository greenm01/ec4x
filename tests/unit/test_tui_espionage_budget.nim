## Tests for espionage budget availability (pool + invest - queued).

import std/[unittest, options, strutils, tables]

import ../../src/player/sam/[tui_model, acceptors, actions]
import ../../src/engine/config/engine
import ../../src/engine/globals

gameConfig = loadGameConfig()

suite "TUI Espionage Budget":
  test "queue add uses total available EBP":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Espionage
    model.view.viewingHouse = 1
    model.view.houseNames[1] = "House 1"
    model.view.houseNames[2] = "House 2"
    model.ui.espionageTargetIdx = 0
    model.ui.espionageOperationIdx = 0
    model.ui.stagedEbpInvestment = 0

    let ops = espionageActions()
    check ops.len > 0
    let opCost = espionageActionCost(ops[0])
    model.view.espionageEbpPool = some(opCost * 2)

    gameActionAcceptor(model, actionEspionageQueueAdd())
    check model.ui.stagedEspionageActions.len == 1
    check model.espionageEbpTotal() == opCost * 2
    check model.espionageEbpAvailable() == opCost

    gameActionAcceptor(model, actionEspionageQueueAdd())
    check model.ui.stagedEspionageActions.len == 2
    check model.espionageEbpAvailable() == 0

    gameActionAcceptor(model, actionEspionageQueueAdd())
    check model.ui.stagedEspionageActions.len == 2
    check model.ui.statusMessage.contains("Insufficient EBP")
