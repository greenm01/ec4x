## Tests for espionage budget availability (pool + invest - queued).

import std/[unittest, options, strutils, tables]

import ../../src/player/sam/[tui_model, acceptors, actions]
import ../../src/engine/config/engine
import ../../src/engine/types/[core, espionage]
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

  test "decreasing EBP auto-removes newest queued actions":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Espionage
    model.ui.espionageFocus = EspionageFocus.Budget
    model.ui.espionageBudgetChannel = EspionageBudgetChannel.Ebp
    model.view.espionageEbpPool = some(0)
    model.ui.stagedEbpInvestment = 2
    model.ui.stagedEspionageActions = @[
      EspionageAttempt(
        attacker: HouseId(1),
        target: HouseId(2),
        action: EspionageAction.SabotageLow,
        targetSystem: none(SystemId),
      ),
      EspionageAttempt(
        attacker: HouseId(1),
        target: HouseId(3),
        action: EspionageAction.SabotageLow,
        targetSystem: none(SystemId),
      ),
    ]

    check model.espionageQueuedTotalEbp() > model.espionageEbpTotal()
    gameActionAcceptor(model, actionEspionageBudgetAdjustDec())
    check model.ui.stagedEbpInvestment == 1
    check model.ui.stagedEspionageActions.len == 0
    check model.espionageQueuedTotalEbp() <= model.espionageEbpTotal()

  test "clear budget removes queued actions that exceed remaining EBP":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Espionage
    model.view.espionageEbpPool = some(0)
    model.ui.stagedEbpInvestment = 3
    model.ui.stagedEspionageActions = @[
      EspionageAttempt(
        attacker: HouseId(1),
        target: HouseId(2),
        action: EspionageAction.PsyopsCampaign,
        targetSystem: none(SystemId),
      ),
    ]

    check model.ui.stagedEspionageActions.len == 1
    gameActionAcceptor(model, actionEspionageClearBudget())
    check model.ui.stagedEbpInvestment == 0
    check model.ui.stagedEspionageActions.len == 0

  test "up down in budget do not toggle EBP/CIP":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Espionage
    model.ui.espionageFocus = EspionageFocus.Budget
    model.ui.espionageBudgetChannel = EspionageBudgetChannel.Ebp

    gameActionAcceptor(model, actionListDown())
    check model.ui.espionageBudgetChannel == EspionageBudgetChannel.Ebp

    gameActionAcceptor(model, actionListUp())
    check model.ui.espionageBudgetChannel == EspionageBudgetChannel.Ebp
