## Unit tests for carrier hangar capacity system
##
## Tests per-carrier hangar capacity enforcement for fighters embarked on carriers.
##
## Test Coverage:
## 1. Capacity calculation per ACO level
## 2. Per-carrier violation checking
## 3. Loading validation (canLoadFighters)
## 4. Available space calculation
## 5. ACO tech upgrade effects
## 6. Multi-carrier scenarios

import std/[unittest, tables, options]
import ../../src/engine/economy/capacity/carrier_hangar
import ../../src/engine/economy/capacity/types as capacity_types
import ../../src/engine/gamestate
import ../../src/engine/squadron
import ../../src/engine/fleet
import ../../src/engine/research/types as research_types
import ../../src/common/types/[core, units, tech]

suite "Carrier Hangar Capacity - Basic Calculations":
  test "isCarrier correctly identifies carrier ship classes":
    check isCarrier(ShipClass.Carrier) == true
    check isCarrier(ShipClass.SuperCarrier) == true
    check isCarrier(ShipClass.Fighter) == false
    check isCarrier(ShipClass.Destroyer) == false
    check isCarrier(ShipClass.Cruiser) == false
    check isCarrier(ShipClass.Battleship) == false
    check isCarrier(ShipClass.Dreadnought) == false

  test "CV capacity at ACO I":
    check getCarrierMaxCapacity(ShipClass.Carrier, 1) == 3

  test "CV capacity at ACO II":
    check getCarrierMaxCapacity(ShipClass.Carrier, 2) == 4

  test "CV capacity at ACO III":
    check getCarrierMaxCapacity(ShipClass.Carrier, 3) == 5

  test "CX capacity at ACO I":
    check getCarrierMaxCapacity(ShipClass.SuperCarrier, 1) == 5

  test "CX capacity at ACO II":
    check getCarrierMaxCapacity(ShipClass.SuperCarrier, 2) == 6

  test "CX capacity at ACO III":
    check getCarrierMaxCapacity(ShipClass.SuperCarrier, 3) == 8

  test "Non-carrier ships have zero hangar capacity":
    check getCarrierMaxCapacity(ShipClass.Fighter, 1) == 0
    check getCarrierMaxCapacity(ShipClass.Destroyer, 1) == 0
    check getCarrierMaxCapacity(ShipClass.Cruiser, 1) == 0
    check getCarrierMaxCapacity(ShipClass.Battleship, 1) == 0

  test "Invalid ACO levels default to ACO I":
    check getCarrierMaxCapacity(ShipClass.Carrier, 0) == 3
    check getCarrierMaxCapacity(ShipClass.Carrier, 4) == 3
    check getCarrierMaxCapacity(ShipClass.SuperCarrier, 0) == 5
    check getCarrierMaxCapacity(ShipClass.SuperCarrier, -1) == 5

suite "Carrier Hangar Capacity - Squadron Analysis":
  test "getCurrentHangarLoad counts embarked fighters":
    var squadron = Squadron(
      id: "SQ-001",
      flagship: newShip(ShipClass.Carrier, techLevel = 1),
      ships: @[],
      embarkedFighters: @[
        CarrierFighter(id: "FS-001", commissionedTurn: 1),
        CarrierFighter(id: "FS-002", commissionedTurn: 1),
        CarrierFighter(id: "FS-003", commissionedTurn: 2)
      ]
    )
    check getCurrentHangarLoad(squadron) == 3

  test "Empty carrier has zero load":
    var squadron = Squadron(
      id: "SQ-002",
      flagship: newShip(ShipClass.Carrier, techLevel = 1),
      ships: @[],
      embarkedFighters: @[]
    )
    check getCurrentHangarLoad(squadron) == 0

suite "Carrier Hangar Capacity - Violation Detection":
  test "CV at ACO I with 3 fighters - no violation":
    var state = GameState(
      turn: 1,
      houses: {
        HouseId("HOUSE1"): House(
          id: HouseId("HOUSE1"),
          name: "Test House",
          eliminated: false,
          treasury: 1000,
          techTree: research_types.initTechTree(TechLevel(
            economicLevel: 1,
            scienceLevel: 1,
            constructionTech: 1,
            weaponsTech: 1,
            terraformingTech: 1,
            electronicIntelligence: 1,
            cloakingTech: 1,
            shieldTech: 1,
            counterIntelligence: 1,
            fighterDoctrine: 1,
            advancedCarrierOps: 1
          ))
        )
      }.toTable,
      fleets: {
        FleetId("FLEET1"): newFleet(
          id = FleetId("FLEET1"),
          owner = HouseId("HOUSE1"),
          location = SystemId(1),
          squadrons = @[
            Squadron(
              id: "SQ-001",
              flagship: newShip(ShipClass.Carrier, techLevel = 1),
              ships: @[],
              embarkedFighters: @[
                CarrierFighter(id: "FS-001", commissionedTurn: 1),
                CarrierFighter(id: "FS-002", commissionedTurn: 1),
                CarrierFighter(id: "FS-003", commissionedTurn: 1)
              ]
            )
          ]
        )
      }.toTable,
      colonies: initTable[SystemId, Colony](),
          fleetOrders: initTable[FleetId, FleetOrder]()
    )

    let violation = analyzeCarrierCapacity(state, FleetId("FLEET1"), 0)
    check violation.isNone

  test "CV at ACO I with 4 fighters - violation":
    var state = GameState(
      turn: 1,
      houses: {
        HouseId("HOUSE1"): House(
          id: HouseId("HOUSE1"),
          name: "Test House",
          eliminated: false,
          treasury: 1000,
          techTree: research_types.initTechTree(TechLevel(
            economicLevel: 1,
            scienceLevel: 1,
            constructionTech: 1,
            weaponsTech: 1,
            terraformingTech: 1,
            electronicIntelligence: 1,
            cloakingTech: 1,
            shieldTech: 1,
            counterIntelligence: 1,
            fighterDoctrine: 1,
            advancedCarrierOps: 1
          ))
        )
      }.toTable,
      fleets: {
        FleetId("FLEET1"): newFleet(
          id = FleetId("FLEET1"),
          owner = HouseId("HOUSE1"),
          location = SystemId(1),
          squadrons = @[
            Squadron(
              id: "SQ-001",
              flagship: newShip(ShipClass.Carrier, techLevel = 1),
              ships: @[],
              embarkedFighters: @[
                CarrierFighter(id: "FS-001", commissionedTurn: 1),
                CarrierFighter(id: "FS-002", commissionedTurn: 1),
                CarrierFighter(id: "FS-003", commissionedTurn: 1),
                CarrierFighter(id: "FS-004", commissionedTurn: 1)
              ]
            )
          ]
        )
      }.toTable,
      colonies: initTable[SystemId, Colony](),
          fleetOrders: initTable[FleetId, FleetOrder]()
    )

    let violation = analyzeCarrierCapacity(state, FleetId("FLEET1"), 0)
    check violation.isSome
    check violation.get().current == 4
    check violation.get().maximum == 3
    check violation.get().excess == 1
    check violation.get().severity == ViolationSeverity.Critical

  test "CX at ACO III with 8 fighters - no violation":
    var state = GameState(
      turn: 1,
      houses: {
        HouseId("HOUSE1"): House(
          id: HouseId("HOUSE1"),
          name: "Test House",
          eliminated: false,
          treasury: 1000,
          techTree: research_types.initTechTree(TechLevel(
            economicLevel: 1,
            scienceLevel: 1,
            constructionTech: 1,
            weaponsTech: 1,
            terraformingTech: 1,
            electronicIntelligence: 1,
            cloakingTech: 1,
            shieldTech: 1,
            counterIntelligence: 1,
            fighterDoctrine: 1,
            advancedCarrierOps: 3
          ))
        )
      }.toTable,
      fleets: {
        FleetId("FLEET1"): newFleet(
          id = FleetId("FLEET1"),
          owner = HouseId("HOUSE1"),
          location = SystemId(1),
          squadrons = @[
            Squadron(
              id: "SQ-CX-001",
              flagship: newShip(ShipClass.SuperCarrier, techLevel = 1),
              ships: @[],
              embarkedFighters: @[
                CarrierFighter(id: "FS-001", commissionedTurn: 1),
                CarrierFighter(id: "FS-002", commissionedTurn: 1),
                CarrierFighter(id: "FS-003", commissionedTurn: 1),
                CarrierFighter(id: "FS-004", commissionedTurn: 1),
                CarrierFighter(id: "FS-005", commissionedTurn: 1),
                CarrierFighter(id: "FS-006", commissionedTurn: 1),
                CarrierFighter(id: "FS-007", commissionedTurn: 1),
                CarrierFighter(id: "FS-008", commissionedTurn: 1)
              ]
            )
          ]
        )
      }.toTable,
      colonies: initTable[SystemId, Colony](),
          fleetOrders: initTable[FleetId, FleetOrder]()
    )

    let violation = analyzeCarrierCapacity(state, FleetId("FLEET1"), 0)
    check violation.isNone

  test "Non-carrier squadrons have no violations":
    var state = GameState(
      turn: 1,
      houses: {
        HouseId("HOUSE1"): House(
          id: HouseId("HOUSE1"),
          name: "Test House",
          eliminated: false,
          treasury: 1000,
          techTree: research_types.initTechTree(TechLevel(
            economicLevel: 1,
            scienceLevel: 1,
            constructionTech: 1,
            weaponsTech: 1,
            terraformingTech: 1,
            electronicIntelligence: 1,
            cloakingTech: 1,
            shieldTech: 1,
            counterIntelligence: 1,
            fighterDoctrine: 1,
            advancedCarrierOps: 1
          ))
        )
      }.toTable,
      fleets: {
        FleetId("FLEET1"): newFleet(
          id = FleetId("FLEET1"),
          owner = HouseId("HOUSE1"),
          location = SystemId(1),
          squadrons = @[
            Squadron(
              id: "SQ-BB-001",
              flagship: newShip(ShipClass.Battleship, techLevel = 1),
              ships: @[],
              embarkedFighters: @[]
            )
          ]
        )
      }.toTable,
      colonies: initTable[SystemId, Colony](),
          fleetOrders: initTable[FleetId, FleetOrder]()
    )

    let violation = analyzeCarrierCapacity(state, FleetId("FLEET1"), 0)
    check violation.isNone

suite "Carrier Hangar Capacity - Loading Operations":
  test "Empty CV at ACO I can load 3 fighters":
    var state = GameState(
      turn: 1,
      houses: {
        HouseId("HOUSE1"): House(
          id: HouseId("HOUSE1"),
          name: "Test House",
          eliminated: false,
          treasury: 1000,
          techTree: research_types.initTechTree(TechLevel(
            economicLevel: 1,
            scienceLevel: 1,
            constructionTech: 1,
            weaponsTech: 1,
            terraformingTech: 1,
            electronicIntelligence: 1,
            cloakingTech: 1,
            shieldTech: 1,
            counterIntelligence: 1,
            fighterDoctrine: 1,
            advancedCarrierOps: 1
          ))
        )
      }.toTable,
      fleets: {
        FleetId("FLEET1"): newFleet(
          id = FleetId("FLEET1"),
          owner = HouseId("HOUSE1"),
          location = SystemId(1),
          squadrons = @[
            Squadron(
              id: "SQ-001",
              flagship: newShip(ShipClass.Carrier, techLevel = 1),
              ships: @[],
              embarkedFighters: @[]
            )
          ]
        )
      }.toTable,
      colonies: initTable[SystemId, Colony](),
          fleetOrders: initTable[FleetId, FleetOrder]()
    )

    check canLoadFighters(state, FleetId("FLEET1"), 0, 3) == true
    check canLoadFighters(state, FleetId("FLEET1"), 0, 4) == false
    check getAvailableHangarSpace(state, FleetId("FLEET1"), 0) == 3

  test "Partially loaded CV can load to capacity":
    var state = GameState(
      turn: 1,
      houses: {
        HouseId("HOUSE1"): House(
          id: HouseId("HOUSE1"),
          name: "Test House",
          eliminated: false,
          treasury: 1000,
          techTree: research_types.initTechTree(TechLevel(
            economicLevel: 1,
            scienceLevel: 1,
            constructionTech: 1,
            weaponsTech: 1,
            terraformingTech: 1,
            electronicIntelligence: 1,
            cloakingTech: 1,
            shieldTech: 1,
            counterIntelligence: 1,
            fighterDoctrine: 1,
            advancedCarrierOps: 1
          ))
        )
      }.toTable,
      fleets: {
        FleetId("FLEET1"): newFleet(
          id = FleetId("FLEET1"),
          owner = HouseId("HOUSE1"),
          location = SystemId(1),
          squadrons = @[
            Squadron(
              id: "SQ-001",
              flagship: newShip(ShipClass.Carrier, techLevel = 1),
              ships: @[],
              embarkedFighters: @[
                CarrierFighter(id: "FS-001", commissionedTurn: 1)
              ]
            )
          ]
        )
      }.toTable,
      colonies: initTable[SystemId, Colony](),
          fleetOrders: initTable[FleetId, FleetOrder]()
    )

    check getAvailableHangarSpace(state, FleetId("FLEET1"), 0) == 2
    check canLoadFighters(state, FleetId("FLEET1"), 0, 2) == true
    check canLoadFighters(state, FleetId("FLEET1"), 0, 3) == false

  test "Full carrier rejects new loads":
    var state = GameState(
      turn: 1,
      houses: {
        HouseId("HOUSE1"): House(
          id: HouseId("HOUSE1"),
          name: "Test House",
          eliminated: false,
          treasury: 1000,
          techTree: research_types.initTechTree(TechLevel(
            economicLevel: 1,
            scienceLevel: 1,
            constructionTech: 1,
            weaponsTech: 1,
            terraformingTech: 1,
            electronicIntelligence: 1,
            cloakingTech: 1,
            shieldTech: 1,
            counterIntelligence: 1,
            fighterDoctrine: 1,
            advancedCarrierOps: 1
          ))
        )
      }.toTable,
      fleets: {
        FleetId("FLEET1"): newFleet(
          id = FleetId("FLEET1"),
          owner = HouseId("HOUSE1"),
          location = SystemId(1),
          squadrons = @[
            Squadron(
              id: "SQ-001",
              flagship: newShip(ShipClass.Carrier, techLevel = 1),
              ships: @[],
              embarkedFighters: @[
                CarrierFighter(id: "FS-001", commissionedTurn: 1),
                CarrierFighter(id: "FS-002", commissionedTurn: 1),
                CarrierFighter(id: "FS-003", commissionedTurn: 1)
              ]
            )
          ]
        )
      }.toTable,
      colonies: initTable[SystemId, Colony](),
          fleetOrders: initTable[FleetId, FleetOrder]()
    )

    check getAvailableHangarSpace(state, FleetId("FLEET1"), 0) == 0
    check canLoadFighters(state, FleetId("FLEET1"), 0, 1) == false

  test "Non-carrier ships have no hangar space":
    var state = GameState(
      turn: 1,
      houses: {
        HouseId("HOUSE1"): House(
          id: HouseId("HOUSE1"),
          name: "Test House",
          eliminated: false,
          treasury: 1000,
          techTree: research_types.initTechTree(TechLevel(
            economicLevel: 1,
            scienceLevel: 1,
            constructionTech: 1,
            weaponsTech: 1,
            terraformingTech: 1,
            electronicIntelligence: 1,
            cloakingTech: 1,
            shieldTech: 1,
            counterIntelligence: 1,
            fighterDoctrine: 1,
            advancedCarrierOps: 1
          ))
        )
      }.toTable,
      fleets: {
        FleetId("FLEET1"): newFleet(
          id = FleetId("FLEET1"),
          owner = HouseId("HOUSE1"),
          location = SystemId(1),
          squadrons = @[
            Squadron(
              id: "SQ-DD-001",
              flagship: newShip(ShipClass.Destroyer, techLevel = 1),
              ships: @[],
              embarkedFighters: @[]
            )
          ]
        )
      }.toTable,
      colonies: initTable[SystemId, Colony](),
          fleetOrders: initTable[FleetId, FleetOrder]()
    )

    check getAvailableHangarSpace(state, FleetId("FLEET1"), 0) == 0
    check canLoadFighters(state, FleetId("FLEET1"), 0, 1) == false

suite "Carrier Hangar Capacity - ACO Tech Effects":
  test "ACO upgrade increases carrier capacity immediately":
    # Start with CV at ACO I (3 FS capacity)
    var state = GameState(
      turn: 1,
      houses: {
        HouseId("HOUSE1"): House(
          id: HouseId("HOUSE1"),
          name: "Test House",
          eliminated: false,
          treasury: 1000,
          techTree: research_types.initTechTree(TechLevel(
            economicLevel: 1,
            scienceLevel: 1,
            constructionTech: 1,
            weaponsTech: 1,
            terraformingTech: 1,
            electronicIntelligence: 1,
            cloakingTech: 1,
            shieldTech: 1,
            counterIntelligence: 1,
            fighterDoctrine: 1,
            advancedCarrierOps: 1
          ))
        )
      }.toTable,
      fleets: {
        FleetId("FLEET1"): newFleet(
          id = FleetId("FLEET1"),
          owner = HouseId("HOUSE1"),
          location = SystemId(1),
          squadrons = @[
            Squadron(
              id: "SQ-001",
              flagship: newShip(ShipClass.Carrier, techLevel = 1),
              ships: @[],
              embarkedFighters: @[
                CarrierFighter(id: "FS-001", commissionedTurn: 1),
                CarrierFighter(id: "FS-002", commissionedTurn: 1),
                CarrierFighter(id: "FS-003", commissionedTurn: 1)
              ]
            )
          ]
        )
      }.toTable,
      colonies: initTable[SystemId, Colony](),
          fleetOrders: initTable[FleetId, FleetOrder]()
    )

    # At ACO I: 3/3 capacity, no violations
    check analyzeCarrierCapacity(state, FleetId("FLEET1"), 0).isNone
    check getAvailableHangarSpace(state, FleetId("FLEET1"), 0) == 0

    # Upgrade to ACO II (4 FS capacity)
    state.houses[HouseId("HOUSE1")].techTree.levels.advancedCarrierOps = 2

    # Now at ACO II: 3/4 capacity, 1 space available
    check analyzeCarrierCapacity(state, FleetId("FLEET1"), 0).isNone
    check getAvailableHangarSpace(state, FleetId("FLEET1"), 0) == 1
    check canLoadFighters(state, FleetId("FLEET1"), 0, 1) == true

  test "ACO downgrade grandfathers existing fighters":
    # CV at ACO II with 4 fighters loaded
    var state = GameState(
      turn: 1,
      houses: {
        HouseId("HOUSE1"): House(
          id: HouseId("HOUSE1"),
          name: "Test House",
          eliminated: false,
          treasury: 1000,
          techTree: research_types.initTechTree(TechLevel(
            economicLevel: 1,
            scienceLevel: 1,
            constructionTech: 1,
            weaponsTech: 1,
            terraformingTech: 1,
            electronicIntelligence: 1,
            cloakingTech: 1,
            shieldTech: 1,
            counterIntelligence: 1,
            fighterDoctrine: 1,
            advancedCarrierOps: 2
          ))
        )
      }.toTable,
      fleets: {
        FleetId("FLEET1"): newFleet(
          id = FleetId("FLEET1"),
          owner = HouseId("HOUSE1"),
          location = SystemId(1),
          squadrons = @[
            Squadron(
              id: "SQ-001",
              flagship: newShip(ShipClass.Carrier, techLevel = 1),
              ships: @[],
              embarkedFighters: @[
                CarrierFighter(id: "FS-001", commissionedTurn: 1),
                CarrierFighter(id: "FS-002", commissionedTurn: 1),
                CarrierFighter(id: "FS-003", commissionedTurn: 1),
                CarrierFighter(id: "FS-004", commissionedTurn: 1)
              ]
            )
          ]
        )
      }.toTable,
      colonies: initTable[SystemId, Colony](),
          fleetOrders: initTable[FleetId, FleetOrder]()
    )

    # At ACO II: 4/4 capacity, no violations
    check analyzeCarrierCapacity(state, FleetId("FLEET1"), 0).isNone

    # Downgrade to ACO I (3 FS capacity)
    state.houses[HouseId("HOUSE1")].techTree.levels.advancedCarrierOps = 1

    # Now over capacity: 4/3, violation detected
    let violation = analyzeCarrierCapacity(state, FleetId("FLEET1"), 0)
    check violation.isSome
    check violation.get().current == 4
    check violation.get().maximum == 3
    check violation.get().excess == 1

    # Cannot load new fighters (over capacity)
    check canLoadFighters(state, FleetId("FLEET1"), 0, 1) == false

suite "Carrier Hangar Capacity - Multi-Carrier Scenarios":
  test "Multiple carriers track capacity independently":
    var state = GameState(
      turn: 1,
      houses: {
        HouseId("HOUSE1"): House(
          id: HouseId("HOUSE1"),
          name: "Test House",
          eliminated: false,
          treasury: 1000,
          techTree: research_types.initTechTree(TechLevel(
            economicLevel: 1,
            scienceLevel: 1,
            constructionTech: 1,
            weaponsTech: 1,
            terraformingTech: 1,
            electronicIntelligence: 1,
            cloakingTech: 1,
            shieldTech: 1,
            counterIntelligence: 1,
            fighterDoctrine: 1,
            advancedCarrierOps: 1
          ))
        )
      }.toTable,
      fleets: {
        FleetId("FLEET1"): newFleet(
          id = FleetId("FLEET1"),
          owner = HouseId("HOUSE1"),
          location = SystemId(1),
          squadrons = @[
            Squadron(
              id: "SQ-CV1",
              flagship: newShip(ShipClass.Carrier, techLevel = 1),
              ships: @[],
              embarkedFighters: @[
                CarrierFighter(id: "FS-001", commissionedTurn: 1),
                CarrierFighter(id: "FS-002", commissionedTurn: 1)
              ]
            ),
            Squadron(
              id: "SQ-CV2",
              flagship: newShip(ShipClass.Carrier, techLevel = 1),
              ships: @[],
              embarkedFighters: @[
                CarrierFighter(id: "FS-003", commissionedTurn: 1),
                CarrierFighter(id: "FS-004", commissionedTurn: 1),
                CarrierFighter(id: "FS-005", commissionedTurn: 1)
              ]
            )
          ]
        )
      }.toTable,
      colonies: initTable[SystemId, Colony](),
          fleetOrders: initTable[FleetId, FleetOrder]()
    )

    # CV1: 2/3 capacity, 1 space available
    check analyzeCarrierCapacity(state, FleetId("FLEET1"), 0).isNone
    check getAvailableHangarSpace(state, FleetId("FLEET1"), 0) == 1

    # CV2: 3/3 capacity, full
    check analyzeCarrierCapacity(state, FleetId("FLEET1"), 1).isNone
    check getAvailableHangarSpace(state, FleetId("FLEET1"), 1) == 0

  test "Mix of CV and CX carriers with different capacities":
    var state = GameState(
      turn: 1,
      houses: {
        HouseId("HOUSE1"): House(
          id: HouseId("HOUSE1"),
          name: "Test House",
          eliminated: false,
          treasury: 1000,
          techTree: research_types.initTechTree(TechLevel(
            economicLevel: 1,
            scienceLevel: 1,
            constructionTech: 1,
            weaponsTech: 1,
            terraformingTech: 1,
            electronicIntelligence: 1,
            cloakingTech: 1,
            shieldTech: 1,
            counterIntelligence: 1,
            fighterDoctrine: 1,
            advancedCarrierOps: 2
          ))
        )
      }.toTable,
      fleets: {
        FleetId("FLEET1"): newFleet(
          id = FleetId("FLEET1"),
          owner = HouseId("HOUSE1"),
          location = SystemId(1),
          squadrons = @[
            Squadron(
              id: "SQ-CV",
              flagship: newShip(ShipClass.Carrier, techLevel = 1),
              ships: @[],
              embarkedFighters: @[
                CarrierFighter(id: "FS-001", commissionedTurn: 1),
                CarrierFighter(id: "FS-002", commissionedTurn: 1)
              ]
            ),
            Squadron(
              id: "SQ-CX",
              flagship: newShip(ShipClass.SuperCarrier, techLevel = 1),
              ships: @[],
              embarkedFighters: @[
                CarrierFighter(id: "FS-003", commissionedTurn: 1),
                CarrierFighter(id: "FS-004", commissionedTurn: 1),
                CarrierFighter(id: "FS-005", commissionedTurn: 1),
                CarrierFighter(id: "FS-006", commissionedTurn: 1)
              ]
            )
          ]
        )
      }.toTable,
      colonies: initTable[SystemId, Colony](),
          fleetOrders: initTable[FleetId, FleetOrder]()
    )

    # CV at ACO II: 2/4 capacity
    check getAvailableHangarSpace(state, FleetId("FLEET1"), 0) == 2

    # CX at ACO II: 4/6 capacity
    check getAvailableHangarSpace(state, FleetId("FLEET1"), 1) == 2

  test "checkViolations finds all carriers with violations":
    var state = GameState(
      turn: 1,
      houses: {
        HouseId("HOUSE1"): House(
          id: HouseId("HOUSE1"),
          name: "Test House",
          eliminated: false,
          treasury: 1000,
          techTree: research_types.initTechTree(TechLevel(
            economicLevel: 1,
            scienceLevel: 1,
            constructionTech: 1,
            weaponsTech: 1,
            terraformingTech: 1,
            electronicIntelligence: 1,
            cloakingTech: 1,
            shieldTech: 1,
            counterIntelligence: 1,
            fighterDoctrine: 1,
            advancedCarrierOps: 1
          ))
        )
      }.toTable,
      fleets: {
        FleetId("FLEET1"): Fleet(
          id: FleetId("FLEET1"),
          name: "Fleet 1",
          owner: HouseId("HOUSE1"),
          location: SystemId("SYS1"),
          squadrons: @[
            Squadron(
              id: "SQ-CV1",
              flagship: newShip(ShipClass.Carrier, techLevel = 1),
              ships: @[],
              embarkedFighters: @[
                CarrierFighter(id: "FS-001", commissionedTurn: 1),
                CarrierFighter(id: "FS-002", commissionedTurn: 1),
                CarrierFighter(id: "FS-003", commissionedTurn: 1),
                CarrierFighter(id: "FS-004", commissionedTurn: 1)  # Over capacity
              ]
            )
          ]
        ),
        FleetId("FLEET2"): newFleet(
          id = FleetId("FLEET2"),
          owner = HouseId("HOUSE1"),
          location = SystemId(2),
          squadrons = @[
            Squadron(
              id: "SQ-CV2",
              flagship: newShip(ShipClass.Carrier, techLevel = 1),
              ships: @[],
              embarkedFighters: @[
                CarrierFighter(id: "FS-005", commissionedTurn: 1),
                CarrierFighter(id: "FS-006", commissionedTurn: 1)  # Within capacity
              ]
            )
          ]
        )
      }.toTable,
      colonies: initTable[SystemId, Colony](),
          fleetOrders: initTable[FleetId, FleetOrder]()
    )

    let violations = checkViolations(state)
    check violations.len == 1
    check violations[0].entityId == "SQ-CV1"
    check violations[0].excess == 1

suite "Carrier Hangar Capacity - Helper Functions":
  test "findCarrierBySquadronId locates carrier in fleet":
    var state = GameState(
      turn: 1,
      houses: initTable[HouseId, House](),
      fleets: {
        FleetId("FLEET1"): newFleet(
          id = FleetId("FLEET1"),
          owner = HouseId("HOUSE1"),
          location = SystemId(1),
          squadrons = @[
            Squadron(
              id: "SQ-001",
              flagship: newShip(ShipClass.Carrier, techLevel = 1),
              ships: @[],
              embarkedFighters: @[]
            )
          ]
        )
      }.toTable,
      colonies: initTable[SystemId, Colony](),
          fleetOrders: initTable[FleetId, FleetOrder]()
    )

    let location = findCarrierBySquadronId(state, "SQ-001")
    check location.isSome
    check location.get().fleetId == FleetId("FLEET1")
    check location.get().squadronIdx == 0

  test "findCarrierBySquadronId returns none for non-existent squadron":
    var state = GameState(
      turn: 1,
      houses: initTable[HouseId, House](),
      fleets: initTable[FleetId, Fleet](),
      colonies: initTable[SystemId, Colony](),
          fleetOrders: initTable[FleetId, FleetOrder]()
    )

    let location = findCarrierBySquadronId(state, "NONEXISTENT")
    check location.isNone

  test "getAvailableHangarSpaceById works via squadron ID":
    var state = GameState(
      turn: 1,
      houses: {
        HouseId("HOUSE1"): House(
          id: HouseId("HOUSE1"),
          name: "Test House",
          eliminated: false,
          treasury: 1000,
          techTree: research_types.initTechTree(TechLevel(
            economicLevel: 1,
            scienceLevel: 1,
            constructionTech: 1,
            weaponsTech: 1,
            terraformingTech: 1,
            electronicIntelligence: 1,
            cloakingTech: 1,
            shieldTech: 1,
            counterIntelligence: 1,
            fighterDoctrine: 1,
            advancedCarrierOps: 1
          ))
        )
      }.toTable,
      fleets: {
        FleetId("FLEET1"): newFleet(
          id = FleetId("FLEET1"),
          owner = HouseId("HOUSE1"),
          location = SystemId(1),
          squadrons = @[
            Squadron(
              id: "SQ-CV-TEST",
              flagship: newShip(ShipClass.Carrier, techLevel = 1),
              ships: @[],
              embarkedFighters: @[
                CarrierFighter(id: "FS-001", commissionedTurn: 1)
              ]
            )
          ]
        )
      }.toTable,
      colonies: initTable[SystemId, Colony](),
          fleetOrders: initTable[FleetId, FleetOrder]()
    )

    check getAvailableHangarSpaceById(state, "SQ-CV-TEST") == 2

  test "canLoadFightersById works via squadron ID":
    var state = GameState(
      turn: 1,
      houses: {
        HouseId("HOUSE1"): House(
          id: HouseId("HOUSE1"),
          name: "Test House",
          eliminated: false,
          treasury: 1000,
          techTree: research_types.initTechTree(TechLevel(
            economicLevel: 1,
            scienceLevel: 1,
            constructionTech: 1,
            weaponsTech: 1,
            terraformingTech: 1,
            electronicIntelligence: 1,
            cloakingTech: 1,
            shieldTech: 1,
            counterIntelligence: 1,
            fighterDoctrine: 1,
            advancedCarrierOps: 1
          ))
        )
      }.toTable,
      fleets: {
        FleetId("FLEET1"): newFleet(
          id = FleetId("FLEET1"),
          owner = HouseId("HOUSE1"),
          location = SystemId(1),
          squadrons = @[
            Squadron(
              id: "SQ-CV-TEST",
              flagship: newShip(ShipClass.Carrier, techLevel = 1),
              ships: @[],
              embarkedFighters: @[]
            )
          ]
        )
      }.toTable,
      colonies: initTable[SystemId, Colony](),
          fleetOrders: initTable[FleetId, FleetOrder]()
    )

    check canLoadFightersById(state, "SQ-CV-TEST", 3) == true
    check canLoadFightersById(state, "SQ-CV-TEST", 4) == false
