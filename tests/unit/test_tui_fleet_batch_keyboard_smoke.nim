## Keyboard-smoke tests for fleet multi-select batch flows.

import std/[unittest, options, tables]

import ../../src/player/sam/sam_pkg
import ../../src/engine/types/[core, fleet]

proc pressKey(
    sam: var SamInstance[TuiModel],
    key: KeyCode,
    modifier: KeyModifier = KeyModifier.None
) =
  let proposalOpt = mapKeyToAction(key, modifier, sam.state)
  check proposalOpt.isSome
  if proposalOpt.isSome:
    sam.present(proposalOpt.get())

proc seedFleetListState(model: var TuiModel) =
  model.ui.appPhase = AppPhase.InGame
  model.ui.mode = ViewMode.Fleets
  model.ui.fleetViewMode = FleetViewMode.ListView
  model.view.fleets = @[
    FleetInfo(
      id: 1,
      name: "A1",
      location: 11,
      locationName: "Columba",
      sectorLabel: "D21",
      shipCount: 2,
      command: int(FleetCommandType.Hold),
      commandLabel: "Hold",
      destinationLabel: "-",
      statusLabel: "Active",
      roe: 6
    ),
    FleetInfo(
      id: 4,
      name: "A4",
      location: 11,
      locationName: "Columba",
      sectorLabel: "D21",
      shipCount: 1,
      command: int(FleetCommandType.Hold),
      commandLabel: "Hold",
      destinationLabel: "-",
      statusLabel: "Active",
      roe: 6
    ),
    FleetInfo(
      id: 5,
      name: "A5",
      location: 11,
      locationName: "Columba",
      sectorLabel: "D21",
      shipCount: 2,
      command: int(FleetCommandType.Hold),
      commandLabel: "Hold",
      destinationLabel: "-",
      statusLabel: "Active",
      roe: 6
    ),
    FleetInfo(
      id: 6,
      name: "A6",
      location: 11,
      locationName: "Columba",
      sectorLabel: "D21",
      shipCount: 1,
      command: int(FleetCommandType.Hold),
      commandLabel: "Hold",
      destinationLabel: "-",
      statusLabel: "Active",
      roe: 6
    )
  ]
  for fleetId in [1, 4, 5, 6]:
    model.view.ownFleetsById[fleetId] = Fleet(
      id: FleetId(fleetId),
      houseId: HouseId(1),
      location: SystemId(11)
    )

suite "Fleet batch keyboard smoke":
  setup:
    initBindings()

  test "batch ROE from X-selected fleets ignores cursor drift":
    var sam = initTuiSam()
    var model = initTuiModel()
    model.seedFleetListState()
    sam.setInitialState(model)

    # Select A5 (down twice), then A6 (down once).
    sam.pressKey(KeyCode.KeyDown)
    sam.pressKey(KeyCode.KeyDown)
    sam.pressKey(KeyCode.KeyX)
    sam.pressKey(KeyCode.KeyDown)
    sam.pressKey(KeyCode.KeyX)
    check 5 in sam.state.ui.selectedFleetIds
    check 6 in sam.state.ui.selectedFleetIds

    # Change sort order, then apply batch ROE.
    sam.pressKey(KeyCode.KeyS)

    sam.pressKey(KeyCode.KeyE)
    check sam.state.ui.mode == ViewMode.FleetDetail
    check sam.state.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker
    check sam.state.ui.fleetDetailModal.batchFleetIds == @[5, 6]

    # Adjust value and commit.
    for _ in 0 ..< 4:
      sam.pressKey(KeyCode.KeyDown)
    sam.pressKey(KeyCode.KeyEnter)

    check 5 in sam.state.ui.stagedFleetCommands
    check 6 in sam.state.ui.stagedFleetCommands
    check 1 notin sam.state.ui.stagedFleetCommands
    check sam.state.ui.stagedFleetCommands[5].roe.isSome
    check sam.state.ui.stagedFleetCommands[6].roe.isSome
    check sam.state.ui.stagedFleetCommands[5].roe.get() ==
      sam.state.ui.stagedFleetCommands[6].roe.get()

  test "batch command from X-selected fleets ignores cursor drift":
    var sam = initTuiSam()
    var model = initTuiModel()
    model.seedFleetListState()
    sam.setInitialState(model)

    # Select A5 (down twice) and A6 (down once).
    sam.pressKey(KeyCode.KeyDown)
    sam.pressKey(KeyCode.KeyDown)
    sam.pressKey(KeyCode.KeyX)
    sam.pressKey(KeyCode.KeyDown)
    sam.pressKey(KeyCode.KeyX)

    # Open batch command picker.
    sam.pressKey(KeyCode.KeyC)
    check sam.state.ui.mode == ViewMode.FleetDetail
    check sam.state.ui.fleetDetailModal.subModal == FleetSubModal.CommandPicker
    check sam.state.ui.fleetDetailModal.batchFleetIds == @[5, 6]

    # Use command quick-entry (0 => "00" Hold), then commit.
    sam.pressKey(KeyCode.Key0)
    sam.pressKey(KeyCode.KeyEnter)

    check 5 in sam.state.ui.stagedFleetCommands
    check 6 in sam.state.ui.stagedFleetCommands
    check 1 notin sam.state.ui.stagedFleetCommands
    check sam.state.ui.stagedFleetCommands[5].commandType == FleetCommandType.Hold
    check sam.state.ui.stagedFleetCommands[6].commandType == FleetCommandType.Hold
