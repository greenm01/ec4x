## Unit tests for colony command modals in SAM acceptors.

import std/[unittest, options, tables]

import ../../src/player/sam/sam_pkg
import ../../src/engine/types/[core, fleet, ship, colony, production,
  combat, facilities, command]

suite "TUI modal acceptors":
  test "population transfer modal stages command":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Planets
    model.ui.selectedIdx = 0
    model.view.viewingHouse = 1
    model.view.planetsRows = @[
      PlanetRow(
        colonyId: some(11),
        systemId: 101,
        systemName: "Alpha",
        coordLabel: "A1",
        isOwned: true
      ),
      PlanetRow(
        colonyId: some(12),
        systemId: 102,
        systemName: "Beta",
        coordLabel: "A2",
        isOwned: true
      )
    ]
    model.view.colonies = @[
      ColonyInfo(
        colonyId: 11,
        systemId: 101,
        systemName: "Alpha",
        populationUnits: 20,
        industrialUnits: 8,
        owner: 1
      ),
      ColonyInfo(
        colonyId: 12,
        systemId: 102,
        systemName: "Beta",
        populationUnits: 15,
        industrialUnits: 6,
        owner: 1
      )
    ]

    populationTransferModalAcceptor(model, actionOpenPopulationTransferModal())
    check model.ui.populationTransferModal.active

    model.ui.populationTransferModal.focus = TransferModalFocus.Amount
    model.ui.populationTransferModal.ptuAmount = 4
    populationTransferModalAcceptor(model, actionPopulationTransferConfirm())

    check model.ui.stagedPopulationTransfers.len == 1
    check model.ui.stagedPopulationTransfers[0].sourceColony == ColonyId(11)
    check model.ui.stagedPopulationTransfers[0].destColony == ColonyId(12)
    check model.ui.stagedPopulationTransfers[0].ptuAmount == 4

  test "population transfer delete route removes staged command":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Planets
    model.ui.selectedIdx = 0
    model.view.viewingHouse = 1
    model.view.planetsRows = @[
      PlanetRow(
        colonyId: some(11),
        systemId: 101,
        systemName: "Alpha",
        coordLabel: "A1",
        isOwned: true
      ),
      PlanetRow(
        colonyId: some(12),
        systemId: 102,
        systemName: "Beta",
        coordLabel: "A2",
        isOwned: true
      )
    ]
    model.view.colonies = @[
      ColonyInfo(
        colonyId: 11,
        systemId: 101,
        systemName: "Alpha",
        populationUnits: 20,
        industrialUnits: 8,
        owner: 1
      ),
      ColonyInfo(
        colonyId: 12,
        systemId: 102,
        systemName: "Beta",
        populationUnits: 15,
        industrialUnits: 6,
        owner: 1
      )
    ]
    model.ui.stagedPopulationTransfers = @[
      PopulationTransferCommand(
        houseId: HouseId(1),
        sourceColony: ColonyId(11),
        destColony: ColonyId(12),
        ptuAmount: 3
      )
    ]

    populationTransferModalAcceptor(model, actionOpenPopulationTransferModal())
    check model.ui.populationTransferModal.active
    populationTransferModalAcceptor(model, actionPopulationTransferDeleteRoute())
    check model.ui.stagedPopulationTransfers.len == 0

  test "population transfer confirm replaces same route":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Planets
    model.ui.selectedIdx = 0
    model.view.viewingHouse = 1
    model.view.planetsRows = @[
      PlanetRow(
        colonyId: some(11),
        systemId: 101,
        systemName: "Alpha",
        coordLabel: "A1",
        isOwned: true
      ),
      PlanetRow(
        colonyId: some(12),
        systemId: 102,
        systemName: "Beta",
        coordLabel: "A2",
        isOwned: true
      )
    ]
    model.view.colonies = @[
      ColonyInfo(
        colonyId: 11,
        systemId: 101,
        systemName: "Alpha",
        populationUnits: 20,
        industrialUnits: 8,
        owner: 1
      ),
      ColonyInfo(
        colonyId: 12,
        systemId: 102,
        systemName: "Beta",
        populationUnits: 15,
        industrialUnits: 6,
        owner: 1
      )
    ]
    model.ui.stagedPopulationTransfers = @[
      PopulationTransferCommand(
        houseId: HouseId(1),
        sourceColony: ColonyId(11),
        destColony: ColonyId(12),
        ptuAmount: 2
      )
    ]

    populationTransferModalAcceptor(model, actionOpenPopulationTransferModal())
    model.ui.populationTransferModal.focus = TransferModalFocus.Amount
    model.ui.populationTransferModal.ptuAmount = 7
    populationTransferModalAcceptor(model, actionPopulationTransferConfirm())

    check model.ui.stagedPopulationTransfers.len == 1
    check model.ui.stagedPopulationTransfers[0].sourceColony == ColonyId(11)
    check model.ui.stagedPopulationTransfers[0].destColony == ColonyId(12)
    check model.ui.stagedPopulationTransfers[0].ptuAmount == 7

  test "population transfer amount clamps to source max":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Planets
    model.ui.selectedIdx = 0
    model.view.viewingHouse = 1
    model.view.planetsRows = @[
      PlanetRow(
        colonyId: some(21),
        systemId: 201,
        systemName: "Gamma",
        coordLabel: "B1",
        isOwned: true
      ),
      PlanetRow(
        colonyId: some(22),
        systemId: 202,
        systemName: "Delta",
        coordLabel: "B2",
        isOwned: true
      )
    ]
    model.view.colonies = @[
      ColonyInfo(
        colonyId: 21,
        systemId: 201,
        systemName: "Gamma",
        populationUnits: 5,
        industrialUnits: 7,
        owner: 1
      ),
      ColonyInfo(
        colonyId: 22,
        systemId: 202,
        systemName: "Delta",
        populationUnits: 20,
        industrialUnits: 11,
        owner: 1
      )
    ]

    populationTransferModalAcceptor(model, actionOpenPopulationTransferModal())
    model.ui.populationTransferModal.focus = TransferModalFocus.Amount
    model.ui.populationTransferModal.ptuAmount = 99
    populationTransferModalAcceptor(model, actionPopulationTransferConfirm())

    check model.ui.stagedPopulationTransfers.len == 1
    check model.ui.stagedPopulationTransfers[0].ptuAmount == 4

  test "maintenance modal stages repair command":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Planets
    model.ui.selectedIdx = 0
    model.view.planetsRows = @[
      PlanetRow(
        colonyId: some(21),
        systemId: 201,
        systemName: "Gamma",
        coordLabel: "B1",
        isOwned: true
      )
    ]
    model.view.colonies = @[
      ColonyInfo(
        colonyId: 21,
        systemId: 201,
        systemName: "Gamma",
        populationUnits: 25,
        industrialUnits: 12,
        repairDockAvailable: 2,
        repairDockTotal: 2,
        owner: 1
      )
    ]
    model.view.ownColoniesBySystem[201] = Colony(
      id: ColonyId(21),
      owner: HouseId(1),
      systemId: SystemId(201),
      fighterIds: @[],
      groundUnitIds: @[],
      neoriaIds: @[],
      kastraIds: @[]
    )
    model.view.ownFleetsById[300] = Fleet(
      id: FleetId(300),
      houseId: HouseId(1),
      location: SystemId(201),
      ships: @[ShipId(500)]
    )
    model.view.ownShipsById[500] = Ship(
      id: ShipId(500),
      houseId: HouseId(1),
      shipClass: ShipClass.Destroyer,
      state: CombatState.Crippled
    )

    maintenanceModalAcceptor(model, actionOpenRepairModal())
    check model.ui.maintenanceModal.active
    check model.ui.maintenanceModal.candidates.len > 0

    maintenanceModalAcceptor(model, actionMaintenanceSelect())
    check model.ui.stagedRepairCommands.len == 1
    check model.ui.stagedRepairCommands[0].targetType == RepairTargetType.Ship
    check model.ui.stagedRepairCommands[0].targetId == 500

  test "fleet repair mode stages damaged ships at local drydock":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Fleets
    model.ui.fleetViewMode = FleetViewMode.ListView
    model.ui.selectedIdx = 0
    model.view.viewingHouse = 1
    model.view.fleets = @[
      FleetInfo(
        id: 300,
        name: "A1",
        location: 201,
        locationName: "Gamma",
        shipCount: 2,
        hasCrippled: true
      )
    ]
    model.view.colonies = @[
      ColonyInfo(
        colonyId: 21,
        systemId: 201,
        systemName: "Gamma",
        populationUnits: 25,
        industrialUnits: 12,
        repairDockAvailable: 2,
        repairDockTotal: 2,
        owner: 1
      )
    ]
    model.view.ownColoniesBySystem[201] = Colony(
      id: ColonyId(21),
      owner: HouseId(1),
      systemId: SystemId(201),
      fighterIds: @[],
      groundUnitIds: @[],
      neoriaIds: @[],
      kastraIds: @[]
    )
    model.view.ownFleetsById[300] = Fleet(
      id: FleetId(300),
      houseId: HouseId(1),
      location: SystemId(201),
      ships: @[ShipId(500), ShipId(501)]
    )
    model.view.ownShipsById[500] = Ship(
      id: ShipId(500),
      houseId: HouseId(1),
      shipClass: ShipClass.Destroyer,
      state: CombatState.Crippled
    )
    model.view.ownShipsById[501] = Ship(
      id: ShipId(501),
      houseId: HouseId(1),
      shipClass: ShipClass.Frigate,
      state: CombatState.Nominal
    )

    maintenanceModalAcceptor(model, actionOpenRepairModal())
    check model.ui.maintenanceModal.active
    check model.ui.maintenanceModal.candidates.len == 1

    maintenanceModalAcceptor(model, actionMaintenanceSelect())
    check model.ui.stagedRepairCommands.len == 1
    check model.ui.stagedRepairCommands[0].colonyId == ColonyId(21)
    check model.ui.stagedRepairCommands[0].targetId == 500

  test "fleet list toggle select ignores negative cursor index":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Fleets
    model.ui.fleetViewMode = FleetViewMode.ListView
    model.ui.selectedIdx = -1
    model.view.fleets = @[
      FleetInfo(id: 1, name: "A1", shipCount: 1),
      FleetInfo(id: 2, name: "A2", shipCount: 1)
    ]

    gameActionAcceptor(model, Proposal(
      kind: ProposalKind.pkGameAction,
      actionKind: ActionKind.toggleFleetSelect
    ))
    check model.ui.selectedFleetIds.len == 0

  test "fleet toggle proposal keeps selected fleet id stable":
    initBindings()
    var model = initTuiModel()
    model.ui.appPhase = AppPhase.InGame
    model.ui.mode = ViewMode.Fleets
    model.ui.fleetViewMode = FleetViewMode.ListView
    model.ui.selectedIdx = 0
    model.view.fleets = @[
      FleetInfo(id: 5, name: "A5", shipCount: 1),
      FleetInfo(id: 6, name: "A6", shipCount: 1)
    ]
    model.view.ownFleetsById[5] = Fleet(id: FleetId(5), houseId: HouseId(1))
    model.view.ownFleetsById[6] = Fleet(id: FleetId(6), houseId: HouseId(1))

    let proposalOpt = mapKeyToAction(KeyCode.KeyX, KeyModifier.None, model)
    check proposalOpt.isSome
    let proposal = proposalOpt.get()
    check proposal.selectIdx == 5

    # Move cursor before accepting; selection should still apply to A5.
    model.ui.selectedIdx = 1
    selectionAcceptor(model, proposal)
    check 5 in model.ui.selectedFleetIds
    check 6 notin model.ui.selectedFleetIds

  test "fleet batch ROE applies only to X-selected snapshot":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Fleets
    model.ui.fleetViewMode = FleetViewMode.ListView
    model.ui.selectedIdx = 0
    model.view.fleets = @[
      FleetInfo(id: 1, name: "A1", roe: 6, command: int(FleetCommandType.Hold)),
      FleetInfo(id: 5, name: "A5", roe: 6, command: int(FleetCommandType.Hold)),
      FleetInfo(id: 6, name: "A6", roe: 6, command: int(FleetCommandType.Hold))
    ]
    model.view.ownFleetsById[1] = Fleet(id: FleetId(1), houseId: HouseId(1))
    model.view.ownFleetsById[5] = Fleet(id: FleetId(5), houseId: HouseId(1))
    model.view.ownFleetsById[6] = Fleet(id: FleetId(6), houseId: HouseId(1))

    model.ui.selectedFleetIds = @[5, 6]
    gameActionAcceptor(model, actionFleetBatchROE())

    check model.ui.mode == ViewMode.FleetDetail
    check model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker
    check model.ui.fleetDetailModal.batchFleetIds == @[5, 6]

    # Simulate drift in live selected ids while picker is open.
    model.ui.selectedFleetIds = @[1, 5]
    model.ui.fleetDetailModal.roeValue = 3
    fleetDetailModalAcceptor(model, actionFleetDetailSelectROE())

    check 5 in model.ui.stagedFleetCommands
    check 6 in model.ui.stagedFleetCommands
    check 1 notin model.ui.stagedFleetCommands
    check model.ui.stagedFleetCommands[5].roe.get() == 3
    check model.ui.stagedFleetCommands[6].roe.get() == 3

  test "fleet batch ZTC uses X-selected snapshot despite selection drift":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Fleets
    model.ui.fleetViewMode = FleetViewMode.ListView
    model.ui.selectedIdx = 0
    model.view.fleets = @[
      FleetInfo(
        id: 1,
        name: "A1",
        location: 11,
        locationName: "Columba",
        statusLabel: "Active"
      ),
      FleetInfo(
        id: 5,
        name: "A5",
        location: 11,
        locationName: "Columba",
        statusLabel: "Reserve"
      ),
      FleetInfo(
        id: 6,
        name: "A6",
        location: 11,
        locationName: "Columba",
        statusLabel: "Reserve"
      )
    ]
    model.view.ownColoniesBySystem[11] = Colony(
      id: ColonyId(70),
      owner: HouseId(1),
      systemId: SystemId(11)
    )
    model.view.ownFleetsById[1] = Fleet(
      id: FleetId(1),
      houseId: HouseId(1),
      location: SystemId(11),
      status: FleetStatus.Active
    )
    model.view.ownFleetsById[5] = Fleet(
      id: FleetId(5),
      houseId: HouseId(1),
      location: SystemId(11),
      status: FleetStatus.Reserve
    )
    model.view.ownFleetsById[6] = Fleet(
      id: FleetId(6),
      houseId: HouseId(1),
      location: SystemId(11),
      status: FleetStatus.Reserve
    )

    model.ui.selectedFleetIds = @[5, 6]
    gameActionAcceptor(model, actionFleetBatchZeroTurn())

    check model.ui.mode == ViewMode.FleetDetail
    check model.ui.fleetDetailModal.subModal == FleetSubModal.ZTCPicker
    check model.ui.fleetDetailModal.batchFleetIds == @[5, 6]
    check ZeroTurnCommandType.Reactivate in
      model.ui.fleetDetailModal.ztcPickerCommands

    # Drift live selected ids; source fleets must remain snapshot based.
    model.ui.selectedFleetIds = @[1, 5]
    let refreshed = model.buildZtcPickerList()
    check ZeroTurnCommandType.Reactivate in refreshed

  test "maintenance scrap sets queue-loss acknowledgement when needed":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Planets
    model.ui.selectedIdx = 0
    model.view.planetsRows = @[
      PlanetRow(
        colonyId: some(31),
        systemId: 301,
        systemName: "Delta",
        coordLabel: "C1",
        isOwned: true
      )
    ]
    model.view.colonies = @[
      ColonyInfo(
        colonyId: 31,
        systemId: 301,
        systemName: "Delta",
        populationUnits: 30,
        industrialUnits: 14,
        owner: 1
      )
    ]
    model.view.ownColoniesBySystem[301] = Colony(
      id: ColonyId(31),
      owner: HouseId(1),
      systemId: SystemId(301),
      fighterIds: @[],
      groundUnitIds: @[],
      neoriaIds: @[NeoriaId(700)],
      kastraIds: @[]
    )
    model.view.ownNeoriasById[700] = Neoria(
      id: NeoriaId(700),
      neoriaClass: NeoriaClass.Spaceport,
      colonyId: ColonyId(31),
      state: CombatState.Nominal,
      constructionQueue: @[ConstructionProjectId(1)],
      repairQueue: @[]
    )

    maintenanceModalAcceptor(model, actionOpenScrapModal())
    check model.ui.maintenanceModal.active
    check model.ui.maintenanceModal.candidates.len > 0

    maintenanceModalAcceptor(model, actionMaintenanceSelect())
    check model.ui.stagedScrapCommands.len == 1
    check model.ui.stagedScrapCommands[0].targetType == ScrapTargetType.Neoria
    check model.ui.stagedScrapCommands[0].targetId == 700
    check model.ui.stagedScrapCommands[0].acknowledgeQueueLoss

  test "maintenance select toggles staged scrap command":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Planets
    model.ui.selectedIdx = 0
    model.view.planetsRows = @[
      PlanetRow(
        colonyId: some(51),
        systemId: 501,
        systemName: "Zeta",
        coordLabel: "F1",
        isOwned: true
      )
    ]
    model.view.colonies = @[
      ColonyInfo(
        colonyId: 51,
        systemId: 501,
        systemName: "Zeta",
        populationUnits: 30,
        industrialUnits: 14,
        owner: 1
      )
    ]
    model.view.ownColoniesBySystem[501] = Colony(
      id: ColonyId(51),
      owner: HouseId(1),
      systemId: SystemId(501),
      fighterIds: @[],
      groundUnitIds: @[],
      neoriaIds: @[NeoriaId(810)],
      kastraIds: @[]
    )
    model.view.ownNeoriasById[810] = Neoria(
      id: NeoriaId(810),
      neoriaClass: NeoriaClass.Drydock,
      colonyId: ColonyId(51),
      state: CombatState.Nominal
    )

    maintenanceModalAcceptor(model, actionOpenScrapModal())
    check model.ui.maintenanceModal.active
    maintenanceModalAcceptor(model, actionMaintenanceSelect())
    check model.ui.stagedScrapCommands.len == 1
    maintenanceModalAcceptor(model, actionMaintenanceSelect())
    check model.ui.stagedScrapCommands.len == 0

  test "terraform action toggles staged terraform command":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Planets
    model.ui.selectedIdx = 0
    model.view.viewingHouse = 1
    model.view.turn = 15
    model.view.planetsRows = @[
      PlanetRow(
        colonyId: some(41),
        systemId: 401,
        systemName: "Epsilon",
        coordLabel: "D1",
        isOwned: true
      )
    ]
    model.view.colonies = @[
      ColonyInfo(
        colonyId: 41,
        systemId: 401,
        systemName: "Epsilon",
        populationUnits: 18,
        industrialUnits: 9,
        owner: 1
      )
    ]
    model.view.ownColoniesBySystem[401] = Colony(
      id: ColonyId(41),
      owner: HouseId(1),
      systemId: SystemId(401),
      activeTerraforming: none(TerraformProject)
    )

    populationTransferModalAcceptor(model, actionStageTerraformCommand())
    check model.ui.stagedTerraformCommands.len == 1
    check model.ui.stagedTerraformCommands[0].colonyId == ColonyId(41)

    populationTransferModalAcceptor(model, actionStageTerraformCommand())
    check model.ui.stagedTerraformCommands.len == 0
