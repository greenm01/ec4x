## Unit tests for colony action parity between key bindings and command dock.

import std/[unittest, options]

import ../../src/player/sam/sam_pkg
import ../../src/player/tui/widget/command_dock

proc hasAction(actions: seq[ContextAction], key: string, label: string): bool =
  for action in actions:
    if action.key == key and action.label == label:
      return true
  false

suite "TUI colony action parity":
  setup:
    initBindings()

  test "planets command dock exposes colony command keys":
    let actions = planetsContextActions(true)
    check hasAction(actions, "B", "Build")
    check hasAction(actions, "T", "Transfer")
    check hasAction(actions, "V", "Terraform")
    check hasAction(actions, "D", "Drydock")
    check hasAction(actions, "X", "Scrap")

  test "planet detail command dock exposes colony command keys":
    let actions = planetDetailContextActions()
    check hasAction(actions, "B", "Build")
    check hasAction(actions, "T", "Transfer")
    check hasAction(actions, "V", "Terraform")
    check hasAction(actions, "D", "Drydock")
    check hasAction(actions, "X", "Scrap")

  test "planets key mapping reaches colony actions":
    var model = initTuiModel()
    model.ui.appPhase = AppPhase.InGame
    model.ui.mode = ViewMode.Planets
    model.ui.selectedIdx = 0
    model.view.planetsRows = @[
      PlanetRow(
        colonyId: some(101),
        systemId: 501,
        systemName: "Atlas",
        coordLabel: "E1",
        isOwned: true
      )
    ]
    model.view.colonies = @[
      ColonyInfo(
        colonyId: 101,
        systemId: 501,
        systemName: "Atlas",
        populationUnits: 20,
        industrialUnits: 5,
        owner: 1
      )
    ]

    let buildAct = mapKeyToAction(KeyCode.KeyB, KeyModifier.None, model)
    let transferAct = mapKeyToAction(KeyCode.KeyT, KeyModifier.None, model)
    let terraAct = mapKeyToAction(KeyCode.KeyV, KeyModifier.None, model)
    let repairAct = mapKeyToAction(KeyCode.KeyD, KeyModifier.None, model)
    let scrapAct = mapKeyToAction(KeyCode.KeyX, KeyModifier.None, model)

    check buildAct.isSome
    check transferAct.isSome
    check terraAct.isSome
    check repairAct.isSome
    check scrapAct.isSome

    if buildAct.isSome:
      check buildAct.get().actionKind == ActionKind.openBuildModal
    if transferAct.isSome:
      check transferAct.get().actionKind ==
        ActionKind.openPopulationTransferModal
    if terraAct.isSome:
      check terraAct.get().actionKind == ActionKind.stageTerraformCommand
    if repairAct.isSome:
      check repairAct.get().actionKind == ActionKind.openRepairModal
    if scrapAct.isSome:
      check scrapAct.get().actionKind == ActionKind.openScrapModal

  test "planet detail key mapping reaches colony actions":
    var model = initTuiModel()
    model.ui.appPhase = AppPhase.InGame
    model.ui.mode = ViewMode.PlanetDetail

    let transferAct = mapKeyToAction(KeyCode.KeyT, KeyModifier.None, model)
    let terraAct = mapKeyToAction(KeyCode.KeyV, KeyModifier.None, model)
    let repairAct = mapKeyToAction(KeyCode.KeyD, KeyModifier.None, model)
    let scrapAct = mapKeyToAction(KeyCode.KeyX, KeyModifier.None, model)

    check transferAct.isSome
    check terraAct.isSome
    check repairAct.isSome
    check scrapAct.isSome

    if transferAct.isSome:
      check transferAct.get().actionKind ==
        ActionKind.openPopulationTransferModal
    if terraAct.isSome:
      check terraAct.get().actionKind == ActionKind.stageTerraformCommand
    if repairAct.isSome:
      check repairAct.get().actionKind == ActionKind.openRepairModal
    if scrapAct.isSome:
      check scrapAct.get().actionKind == ActionKind.openScrapModal

  test "fleet key mapping uses repair and ROE remap":
    var model = initTuiModel()
    model.ui.appPhase = AppPhase.InGame
    model.ui.mode = ViewMode.Fleets
    model.ui.fleetViewMode = FleetViewMode.ListView
    model.view.fleets = @[
      FleetInfo(id: 1, name: "A1", shipCount: 1)
    ]

    let repairAct = mapKeyToAction(KeyCode.KeyR, KeyModifier.None, model)
    let roeAct = mapKeyToAction(KeyCode.KeyE, KeyModifier.None, model)
    let toggleAct = mapKeyToAction(KeyCode.KeyV, KeyModifier.None, model)

    check repairAct.isSome
    check roeAct.isSome
    check toggleAct.isSome
    if repairAct.isSome:
      check repairAct.get().actionKind == ActionKind.openRepairModal
    if roeAct.isSome:
      check roeAct.get().actionKind == ActionKind.fleetBatchROE
    if toggleAct.isSome:
      check toggleAct.get().actionKind == ActionKind.switchFleetView
