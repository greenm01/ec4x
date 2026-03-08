## Unit tests for in-game session menu actions.

import std/[unittest, options]

import ../../src/player/sam/sam_pkg

suite "TUI session menu":
  test "session wallet action opens identity manager from in-game":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Economy

    gameActionAcceptor(model, actionEconomySessionOpen())
    check model.ui.sessionModalActive

    gameActionAcceptor(model, actionEconomySessionWallet())
    check model.ui.appPhase == AppPhase.Lobby
    check model.ui.resumeInGameAfterEntryModal
    check model.ui.entryModal.mode == EntryModalMode.ManageIdentities

  test "session switch confirms and clears staged drafts":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Economy
    model.ui.stagedTaxRate = some(60)
    model.ui.stagedEbpInvestment = 2
    model.ui.modifiedSinceSubmit = true

    gameActionAcceptor(model, actionEconomySessionOpen())
    model.ui.sessionModalSelected = SessionModalItem.SwitchGame
    gameActionAcceptor(model, actionEconomySessionSelect())

    check model.ui.sessionSwitchConfirmActive

    gameActionAcceptor(model, actionEconomySessionSwitchConfirm())
    check model.ui.appPhase == AppPhase.Lobby
    check model.ui.entryModal.mode == EntryModalMode.ManagePlayerGames
    check model.ui.stagedTaxRate.isNone
    check model.ui.stagedEbpInvestment == 0
    check not model.ui.modifiedSinceSubmit
    check model.ui.switchGameRequested
