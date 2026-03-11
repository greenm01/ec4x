## Unit tests for colony command modals in SAM acceptors.

import std/[unittest, options, tables, sets]

import ../../src/player/sam/sam_pkg
import ../../src/player/tui/build_spec
import ../../src/engine/globals
import ../../src/engine/types/[core, fleet, ship, colony, production,
  combat, facilities, command, diplomacy, espionage, zero_turn, tech]
import ../../src/engine/config/engine as config_engine

gameConfig = config_engine.loadGameConfig()

proc pressKey(
    sam: var SamInstance[TuiModel],
    key: KeyCode,
    modifier: KeyModifier = KeyModifier.None
) =
  let proposalOpt = mapKeyToAction(key, modifier, sam.state)
  check proposalOpt.isSome
  if proposalOpt.isSome:
    sam.present(proposalOpt.get())

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

  test "carrier picker accepts shifted plus and stages fighter unload":
    initBindings()
    var sam = initTuiSam()
    var model = initTuiModel()
    model.ui.appPhase = AppPhase.InGame
    model.ui.mode = ViewMode.FleetDetail
    model.view.viewingHouse = 1
    model.view.fleets = @[
      FleetInfo(
        id: 300,
        name: "A5",
        location: 201,
        locationName: "Gamma",
        sectorLabel: "B1",
        shipCount: 3,
        owner: 1,
        command: int(FleetCommandType.Hold),
        commandLabel: "Hold",
        isIdle: true,
        roe: 6,
        attackStrength: 18,
        defenseStrength: 48,
        statusLabel: "Active",
        destinationLabel: "-",
        destinationSystemId: 0,
        eta: 0,
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
      ships: @[ShipId(42), ShipId(43), ShipId(44)]
    )
    model.view.ownShipsById[42] = Ship(
      id: ShipId(42),
      houseId: HouseId(1),
      fleetId: FleetId(300),
      shipClass: ShipClass.Carrier,
      state: CombatState.Nominal,
      embarkedFighters: @[ShipId(44)]
    )
    model.view.ownShipsById[43] = Ship(
      id: ShipId(43),
      houseId: HouseId(1),
      fleetId: FleetId(300),
      shipClass: ShipClass.Destroyer,
      state: CombatState.Nominal
    )
    model.view.ownShipsById[44] = Ship(
      id: ShipId(44),
      houseId: HouseId(1),
      fleetId: FleetId(300),
      shipClass: ShipClass.Fighter,
      state: CombatState.Nominal,
      assignedToCarrier: some(ShipId(42))
    )
    model.ui.pristineFleets = model.view.fleets
    model.ui.pristineFleetConsoleFleetsBySystem =
      initTable[int, seq[FleetConsoleFleet]]()
    model.ui.pristineOwnFleetsById = model.view.ownFleetsById
    model.ui.pristineOwnColoniesBySystem = model.view.ownColoniesBySystem
    model.ui.pristineOwnShipsById = model.view.ownShipsById
    model.ui.fleetDetailModal.fleetId = 300
    model.ui.fleetDetailModal.ztcType =
      some(ZeroTurnCommandType.UnloadFighters)
    model.ui.fleetDetailModal.carrierPickerCandidates = @[
      CarrierPickerRow(
        shipId: ShipId(42),
        classLabel: "Carrier",
        maxCount: 1,
        stagedCount: 0,
        fighterIds: @[ShipId(44)]
      )
    ]
    model.ui.fleetDetailModal.subModal = FleetSubModal.CarrierPicker
    sam.setInitialState(model)

    sam.pressKey(KeyCode.KeyPlus, KeyModifier.Shift)
    check sam.state.ui.stagedZeroTurnCommands.len == 0
    check sam.state.ui.fleetDetailModal.carrierPickerCandidates.len == 1
    check sam.state.ui.fleetDetailModal.carrierPickerCandidates[0].stagedCount == 1
    check sam.state.view.ownColoniesBySystem[201].fighterIds.len == 0
    check sam.state.view.ownShipsById[42].embarkedFighters == @[ShipId(44)]

    sam.pressKey(KeyCode.KeyEnter)
    check sam.state.ui.stagedZeroTurnCommands.len == 1
    if sam.state.ui.stagedZeroTurnCommands.len == 1:
      check sam.state.ui.stagedZeroTurnCommands[0].commandType ==
        ZeroTurnCommandType.UnloadFighters
    check sam.state.ui.mode == ViewMode.Fleets

  test "carrier picker digit input clamps to embarked fighters":
    initBindings()
    var model = initTuiModel()
    model.ui.mode = ViewMode.FleetDetail
    model.view.viewingHouse = 1
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
      ships: @[ShipId(42), ShipId(44)]
    )
    model.view.ownShipsById[42] = Ship(
      id: ShipId(42),
      houseId: HouseId(1),
      fleetId: FleetId(300),
      shipClass: ShipClass.Carrier,
      state: CombatState.Nominal,
      embarkedFighters: @[ShipId(44)]
    )
    model.view.ownShipsById[44] = Ship(
      id: ShipId(44),
      houseId: HouseId(1),
      fleetId: FleetId(300),
      shipClass: ShipClass.Fighter,
      state: CombatState.Nominal,
      assignedToCarrier: some(ShipId(42))
    )
    model.ui.pristineFleets = model.view.fleets
    model.ui.pristineFleetConsoleFleetsBySystem =
      initTable[int, seq[FleetConsoleFleet]]()
    model.ui.pristineOwnFleetsById = model.view.ownFleetsById
    model.ui.pristineOwnColoniesBySystem = model.view.ownColoniesBySystem
    model.ui.pristineOwnShipsById = model.view.ownShipsById
    model.ui.fleetDetailModal.fleetId = 300
    model.ui.fleetDetailModal.ztcType =
      some(ZeroTurnCommandType.UnloadFighters)
    model.ui.fleetDetailModal.carrierPickerCandidates = @[
      CarrierPickerRow(
        shipId: ShipId(42),
        classLabel: "Carrier",
        maxCount: 1,
        stagedCount: 0,
        fighterIds: @[ShipId(44)]
      )
    ]
    model.ui.fleetDetailModal.subModal = FleetSubModal.CarrierPicker
    var sam = initTuiSam()
    sam.setInitialState(model)

    pressKey(sam, KeyCode.Key2)
    pressKey(sam, KeyCode.Key9)

    check sam.state.ui.stagedZeroTurnCommands.len == 0
    check sam.state.ui.fleetDetailModal.carrierPickerCandidates.len == 1
    check sam.state.ui.fleetDetailModal.carrierPickerCandidates[0].stagedCount == 1

    pressKey(sam, KeyCode.KeyEnter)

    check sam.state.ui.stagedZeroTurnCommands.len == 1
    check sam.state.ui.stagedZeroTurnCommands[0].fighterIds == @[ShipId(44)]
    check sam.state.view.ownColoniesBySystem[201].fighterIds == @[ShipId(44)]
    check sam.state.view.ownShipsById[42].embarkedFighters.len == 0

  test "optimistic replay preserves staged fighter unload state":
    var model = initTuiModel()
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
      ships: @[ShipId(42), ShipId(44)]
    )
    model.view.ownShipsById[42] = Ship(
      id: ShipId(42),
      houseId: HouseId(1),
      fleetId: FleetId(300),
      shipClass: ShipClass.Carrier,
      state: CombatState.Nominal,
      embarkedFighters: @[ShipId(44)]
    )
    model.view.ownShipsById[44] = Ship(
      id: ShipId(44),
      houseId: HouseId(1),
      fleetId: FleetId(300),
      shipClass: ShipClass.Fighter,
      state: CombatState.Nominal,
      assignedToCarrier: some(ShipId(42))
    )
    model.view.fleets = @[
      FleetInfo(id: 300, name: "A5", location: 201, shipCount: 2,
        attackStrength: 12, defenseStrength: 25)
    ]
    model.ui.pristineFleets = model.view.fleets
    model.ui.pristineFleetConsoleFleetsBySystem =
      initTable[int, seq[FleetConsoleFleet]]()
    model.ui.pristineOwnFleetsById = model.view.ownFleetsById
    model.ui.pristineOwnColoniesBySystem = model.view.ownColoniesBySystem
    model.ui.pristineOwnShipsById = model.view.ownShipsById
    model.ui.stagedZeroTurnCommands = @[
      ZeroTurnCommand(
        houseId: HouseId(1),
        commandType: ZeroTurnCommandType.UnloadFighters,
        colonySystem: some(SystemId(201)),
        sourceFleetId: some(FleetId(300)),
        targetFleetId: none(FleetId),
        shipIndices: @[],
        shipIds: @[],
        cargoType: none(CargoClass),
        cargoQuantity: none(int),
        fighterIds: @[ShipId(44)],
        carrierShipId: some(ShipId(42)),
        sourceCarrierShipId: none(ShipId),
        targetCarrierShipId: none(ShipId),
        newFleetId: none(FleetId),
      )
    ]

    model.reapplyAllOptimisticUpdates()

    check model.view.ownColoniesBySystem[201].fighterIds == @[ShipId(44)]
    check model.view.ownShipsById[42].embarkedFighters.len == 0
    check model.view.ownShipsById[44].assignedToCarrier.isNone
    check ShipId(44) notin model.view.ownFleetsById[300].ships

  test "optimistic unload clears dangling embarked fighter references":
    var model = initTuiModel()
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
      ships: @[ShipId(42)]
    )
    model.view.ownShipsById[42] = Ship(
      id: ShipId(42),
      houseId: HouseId(1),
      fleetId: FleetId(300),
      shipClass: ShipClass.Carrier,
      state: CombatState.Nominal,
      embarkedFighters: @[ShipId(44)]
    )
    model.view.fleets = @[
      FleetInfo(id: 300, name: "A5", location: 201, shipCount: 1,
        attackStrength: 6, defenseStrength: 23)
    ]
    model.ui.pristineFleets = model.view.fleets
    model.ui.pristineFleetConsoleFleetsBySystem =
      initTable[int, seq[FleetConsoleFleet]]()
    model.ui.pristineOwnFleetsById = model.view.ownFleetsById
    model.ui.pristineOwnColoniesBySystem = model.view.ownColoniesBySystem
    model.ui.pristineOwnShipsById = model.view.ownShipsById
    model.ui.stagedZeroTurnCommands = @[
      ZeroTurnCommand(
        houseId: HouseId(1),
        commandType: ZeroTurnCommandType.UnloadFighters,
        colonySystem: some(SystemId(201)),
        sourceFleetId: some(FleetId(300)),
        targetFleetId: none(FleetId),
        shipIndices: @[],
        shipIds: @[],
        cargoType: none(CargoClass),
        cargoQuantity: none(int),
        fighterIds: @[ShipId(44)],
        carrierShipId: some(ShipId(42)),
        sourceCarrierShipId: none(ShipId),
        targetCarrierShipId: none(ShipId),
        newFleetId: none(FleetId),
      )
    ]

    model.reapplyAllOptimisticUpdates()

    check model.view.ownColoniesBySystem[201].fighterIds == @[ShipId(44)]
    check model.view.ownShipsById[42].embarkedFighters.len == 0
    check ShipId(44) notin model.view.ownFleetsById[300].ships

  test "duplicate fighter unload staging is collapsed":
    var model = initTuiModel()
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
      ships: @[ShipId(42), ShipId(44)]
    )
    model.view.ownShipsById[42] = Ship(
      id: ShipId(42),
      houseId: HouseId(1),
      fleetId: FleetId(300),
      shipClass: ShipClass.Carrier,
      state: CombatState.Nominal,
      embarkedFighters: @[ShipId(44)]
    )
    model.view.ownShipsById[44] = Ship(
      id: ShipId(44),
      houseId: HouseId(1),
      fleetId: FleetId(300),
      shipClass: ShipClass.Fighter,
      state: CombatState.Nominal,
      assignedToCarrier: some(ShipId(42))
    )
    model.view.fleets = @[
      FleetInfo(id: 300, name: "A5", location: 201, shipCount: 2)
    ]
    model.ui.pristineFleets = model.view.fleets
    model.ui.pristineFleetConsoleFleetsBySystem =
      initTable[int, seq[FleetConsoleFleet]]()
    model.ui.pristineOwnFleetsById = model.view.ownFleetsById
    model.ui.pristineOwnColoniesBySystem = model.view.ownColoniesBySystem
    model.ui.pristineOwnShipsById = model.view.ownShipsById

    let unload = ZeroTurnCommand(
      houseId: HouseId(1),
      commandType: ZeroTurnCommandType.UnloadFighters,
      colonySystem: some(SystemId(201)),
      sourceFleetId: some(FleetId(300)),
      targetFleetId: none(FleetId),
      shipIndices: @[],
      shipIds: @[],
      cargoType: none(CargoClass),
      cargoQuantity: none(int),
      fighterIds: @[ShipId(44)],
      carrierShipId: some(ShipId(42)),
      sourceCarrierShipId: none(ShipId),
      targetCarrierShipId: none(ShipId),
      newFleetId: none(FleetId),
    )

    model.stageZeroTurnCommandOptimistically(unload)
    model.stageZeroTurnCommandOptimistically(unload)

    check model.ui.stagedZeroTurnCommands.len == 1
    check model.view.ownColoniesBySystem[201].fighterIds == @[ShipId(44)]
    check model.view.ownShipsById[42].embarkedFighters.len == 0

  test "unload fighters requires friendly colony at fleet location":
    var model = initTuiModel()
    model.ui.mode = ViewMode.FleetDetail
    model.view.viewingHouse = 1
    model.view.ownFleetsById[300] = Fleet(
      id: FleetId(300),
      houseId: HouseId(1),
      location: SystemId(999),
      ships: @[ShipId(42), ShipId(44)]
    )
    model.view.ownShipsById[42] = Ship(
      id: ShipId(42),
      houseId: HouseId(1),
      fleetId: FleetId(300),
      shipClass: ShipClass.Carrier,
      state: CombatState.Nominal,
      embarkedFighters: @[ShipId(44)]
    )
    model.view.ownShipsById[44] = Ship(
      id: ShipId(44),
      houseId: HouseId(1),
      fleetId: FleetId(300),
      shipClass: ShipClass.Fighter,
      state: CombatState.Nominal,
      assignedToCarrier: some(ShipId(42))
    )
    model.ui.fleetDetailModal.subModal = FleetSubModal.ZTCPicker
    model.ui.fleetDetailModal.ztcPickerCommands = @[
      ZeroTurnCommandType.UnloadFighters
    ]
    model.ui.fleetDetailModal.ztcIdx = 0
    model.ui.fleetDetailModal.fleetId = 300

    fleetDetailModalAcceptor(model, actionFleetDetailSelectCommand())

    check model.ui.statusMessage == "No friendly colony at fleet location"
    check model.ui.fleetDetailModal.subModal == FleetSubModal.ZTCPicker

  test "load fighters opens carrier picker and stages by carrier":
    initBindings()
    var model = initTuiModel()
    model.ui.mode = ViewMode.FleetDetail
    model.view.viewingHouse = 1
    model.view.techLevels = some(TechLevel(aco: 1))
    model.view.ownColoniesBySystem[201] = Colony(
      id: ColonyId(21),
      owner: HouseId(1),
      systemId: SystemId(201),
      fighterIds: @[ShipId(44), ShipId(45)],
      groundUnitIds: @[],
      neoriaIds: @[],
      kastraIds: @[]
    )
    model.view.ownFleetsById[300] = Fleet(
      id: FleetId(300),
      houseId: HouseId(1),
      location: SystemId(201),
      ships: @[ShipId(42)]
    )
    model.view.ownShipsById[42] = Ship(
      id: ShipId(42),
      houseId: HouseId(1),
      fleetId: FleetId(300),
      shipClass: ShipClass.Carrier,
      state: CombatState.Nominal,
      embarkedFighters: @[]
    )
    model.ui.pristineFleets = model.view.fleets
    model.ui.pristineFleetConsoleFleetsBySystem =
      initTable[int, seq[FleetConsoleFleet]]()
    model.ui.pristineOwnFleetsById = model.view.ownFleetsById
    model.ui.pristineOwnColoniesBySystem = model.view.ownColoniesBySystem
    model.ui.pristineOwnShipsById = model.view.ownShipsById
    model.ui.fleetDetailModal.fleetId = 300
    model.ui.fleetDetailModal.subModal = FleetSubModal.ZTCPicker
    model.ui.fleetDetailModal.ztcPickerCommands = @[
      ZeroTurnCommandType.LoadFighters
    ]
    var sam = initTuiSam()
    sam.setInitialState(model)

    pressKey(sam, KeyCode.KeyEnter)
    check sam.state.ui.fleetDetailModal.subModal == FleetSubModal.CarrierPicker
    check sam.state.ui.fleetDetailModal.carrierPickerCandidates.len == 1
    check sam.state.ui.fleetDetailModal.carrierPickerCandidates[0].maxCount == 2

    pressKey(sam, KeyCode.KeyPlus, KeyModifier.Shift)
    pressKey(sam, KeyCode.KeyEnter)

    check sam.state.ui.stagedZeroTurnCommands.len == 1
    check sam.state.ui.stagedZeroTurnCommands[0].commandType ==
      ZeroTurnCommandType.LoadFighters
    check sam.state.ui.stagedZeroTurnCommands[0].fighterIds == @[ShipId(44)]

  test "optimistic load makes unload immediately available":
    var model = initTuiModel()
    model.view.viewingHouse = 1
    model.view.ownColoniesBySystem[201] = Colony(
      id: ColonyId(21),
      owner: HouseId(1),
      systemId: SystemId(201),
      fighterIds: @[ShipId(44)],
      groundUnitIds: @[],
      neoriaIds: @[],
      kastraIds: @[]
    )
    model.view.ownFleetsById[300] = Fleet(
      id: FleetId(300),
      houseId: HouseId(1),
      location: SystemId(201),
      ships: @[ShipId(42)]
    )
    model.view.ownShipsById[42] = Ship(
      id: ShipId(42),
      houseId: HouseId(1),
      fleetId: FleetId(300),
      shipClass: ShipClass.Carrier,
      state: CombatState.Nominal,
      embarkedFighters: @[]
    )
    model.view.fleets = @[
      FleetInfo(id: 300, name: "A5", location: 201, shipCount: 1)
    ]
    model.ui.pristineFleets = model.view.fleets
    model.ui.pristineFleetConsoleFleetsBySystem =
      initTable[int, seq[FleetConsoleFleet]]()
    model.ui.pristineOwnFleetsById = model.view.ownFleetsById
    model.ui.pristineOwnColoniesBySystem = model.view.ownColoniesBySystem
    model.ui.pristineOwnShipsById = model.view.ownShipsById

    let load = ZeroTurnCommand(
      houseId: HouseId(1),
      commandType: ZeroTurnCommandType.LoadFighters,
      colonySystem: some(SystemId(201)),
      sourceFleetId: some(FleetId(300)),
      targetFleetId: none(FleetId),
      shipIndices: @[],
      shipIds: @[],
      cargoType: none(CargoClass),
      cargoQuantity: none(int),
      fighterIds: @[ShipId(44)],
      carrierShipId: some(ShipId(42)),
      sourceCarrierShipId: none(ShipId),
      targetCarrierShipId: none(ShipId),
      newFleetId: none(FleetId),
    )

    model.stageZeroTurnCommandOptimistically(load)

    check model.view.ownShipsById[42].embarkedFighters == @[ShipId(44)]
    check model.ztcValidationErrorForFleet(300,
      ZeroTurnCommandType.UnloadFighters).len == 0

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

  test "scout-system picker excludes uncolonized visible systems":
    var model = initTuiModel()
    model.view.systems[(q: 0, r: 0)] = SystemInfo(
      id: 71,
      name: "Enemy",
      coords: (q: 0, r: 0)
    )
    model.view.systems[(q: 1, r: 0)] = SystemInfo(
      id: 72,
      name: "Empty",
      coords: (q: 1, r: 0)
    )
    model.view.knownEnemyColonySystemIds.incl(71)
    model.view.intelRows = @[
      IntelRow(systemId: 71, systemName: "Enemy"),
      IntelRow(systemId: 72, systemName: "Empty")
    ]

    let picker = model.buildSystemPickerListForCommand(
      FleetCommandType.ScoutSystem,
      @[]
    )

    check picker.systems.len == 1
    check picker.systems[0].systemId == 71
    check picker.emptyMessage == "No known enemy colonies to scout"

  test "hack-starbase picker excludes enemy colonies without starbases":
    var model = initTuiModel()
    model.view.systems[(q: 0, r: 0)] = SystemInfo(
      id: 81,
      name: "NoStarbase",
      coords: (q: 0, r: 0)
    )
    model.view.systems[(q: 1, r: 0)] = SystemInfo(
      id: 82,
      name: "Starbase",
      coords: (q: 1, r: 0)
    )
    model.view.knownEnemyColonySystemIds.incl(81)
    model.view.knownEnemyColonySystemIds.incl(82)
    model.view.intelRows = @[
      IntelRow(
        systemId: 81,
        systemName: "NoStarbase",
        starbaseCount: some(0)
      ),
      IntelRow(
        systemId: 82,
        systemName: "Starbase",
        starbaseCount: some(1)
      )
    ]

    let picker = model.buildSystemPickerListForCommand(
      FleetCommandType.HackStarbase,
      @[]
    )

    check picker.systems.len == 1
    check picker.systems[0].systemId == 82
    check picker.emptyMessage == "No known enemy starbases to hack"

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

  test "expert clear uses shared staged command clearing":
    var model = initTuiModel()
    model.ui.stagedFleetCommands[11] = FleetCommand(
      fleetId: FleetId(11),
      commandType: FleetCommandType.Move,
      targetSystem: some(SystemId(101))
    )
    model.ui.stagedZeroTurnCommands = @[
      ZeroTurnCommand(commandType: ZeroTurnCommandType.Reactivate)
    ]
    model.ui.stagedBuildCommands = @[
      BuildCommand(colonyId: ColonyId(21), buildType: BuildType.Industrial)
    ]
    model.ui.stagedRepairCommands = @[
      RepairCommand(colonyId: ColonyId(21), targetType: RepairTargetType.Ship)
    ]
    model.ui.stagedScrapCommands = @[
      ScrapCommand(colonyId: ColonyId(21), targetType: ScrapTargetType.Ship)
    ]
    model.ui.stagedPopulationTransfers = @[
      PopulationTransferCommand(
        houseId: HouseId(1),
        sourceColony: ColonyId(21),
        destColony: ColonyId(22),
        ptuAmount: 1
      )
    ]
    model.ui.stagedTerraformCommands = @[
      TerraformCommand(houseId: HouseId(1), colonyId: ColonyId(21))
    ]
    model.ui.stagedColonyManagement = @[
      ColonyManagementCommand(colonyId: ColonyId(21))
    ]
    model.ui.stagedDiplomaticCommands = @[
      DiplomaticCommand(houseId: HouseId(1), targetHouse: HouseId(2))
    ]
    model.ui.stagedEspionageActions = @[
      EspionageAttempt(attacker: HouseId(1), target: HouseId(2))
    ]
    model.ui.stagedEbpInvestment = 5
    model.ui.stagedCipInvestment = 4
    model.ui.stagedTaxRate = some(15)
    model.ui.expertModeInput.setText("clear")

    gameActionAcceptor(model, actionExpertSubmit())

    check model.stagedCommandCount() == 0
    check model.ui.stagedZeroTurnCommands.len == 0
    check model.ui.stagedBuildCommands.len == 0
    check model.ui.stagedRepairCommands.len == 0
    check model.ui.stagedScrapCommands.len == 0
    check model.ui.stagedPopulationTransfers.len == 0
    check model.ui.stagedTerraformCommands.len == 0
    check model.ui.stagedColonyManagement.len == 0
    check model.ui.stagedDiplomaticCommands.len == 0
    check model.ui.stagedEspionageActions.len == 0
    check model.ui.stagedEbpInvestment == 0
    check model.ui.stagedCipInvestment == 0
    check model.ui.stagedTaxRate.isNone

  test "build modal blocks qty increment when other staged PP spends exhaust treasury":
    var model = initTuiModel()
    model.ui.mode = ViewMode.PlanetDetail
    model.ui.selectedColonyId = 21
    model.view.treasury = 0
    model.ui.buildModal.active = true
    model.ui.buildModal.colonyId = 21
    model.ui.buildModal.category = BuildCategory.Ground
    model.ui.buildModal.focus = BuildModalFocus.BuildList
    model.ui.buildModal.selectedBuildIdx = 2
    model.ui.buildModal.cstLevel = 1
    model.ui.buildModal.availableOptions = @[
      BuildOption(
        kind: BuildOptionKind.Ground,
        name: "Army",
        cost: 25,
        cstReq: 1
      )
    ]
    model.view.colonyLimits[21] = ColonyLimitSnapshot(industrialUnits: 100)

    buildModalAcceptor(model, actionBuildQtyInc())

    check model.ui.stagedBuildCommands.len == 0
    check model.ui.statusMessage == "Not buildable"

  test "build modal navigation skips rows that exceed remaining PP":
    var model = initTuiModel()
    model.ui.buildModal.active = true
    model.ui.buildModal.category = BuildCategory.Ships
    model.ui.buildModal.focus = BuildModalFocus.BuildList
    model.ui.buildModal.selectedBuildIdx = 1
    model.ui.buildModal.cstLevel = 3
    model.ui.buildModal.remainingPp = 100
    model.ui.buildModal.dockSummary = DockSummary(
      constructionAvailable: 3,
      constructionTotal: 3,
      shipyardAvailable: 3,
      shipyardTotal: 3,
      spaceportAvailable: 0,
      spaceportTotal: 0,
      repairAvailable: 0,
      repairTotal: 0,
    )
    model.ui.buildModal.availableOptions = @[
      BuildOption(
        kind: BuildOptionKind.Ship,
        name: "Frigate",
        cost: ShipSpecRows[1].pc,
        cstReq: ShipSpecRows[1].cst,
      ),
      BuildOption(
        kind: BuildOptionKind.Ship,
        name: "Destroyer",
        cost: ShipSpecRows[2].pc,
        cstReq: ShipSpecRows[2].cst,
      ),
      BuildOption(
        kind: BuildOptionKind.Ship,
        name: "Scout",
        cost: ShipSpecRows[12].pc,
        cstReq: ShipSpecRows[12].cst,
      ),
    ]

    buildModalAcceptor(model, actionBuildListDown())

    check model.ui.buildModal.selectedBuildIdx == 12
