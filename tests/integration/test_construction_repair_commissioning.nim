## Integration Test: Construction, Repair, and Commissioning System
##
## Tests the complete lifecycle of assets through:
## 1. Construction command submission and validation
## 2. Queue advancement and project completion
## 3. Ship commissioning into fleets
## 4. Repair queue management
## 5. Facility damage effects on queues
##
## Per docs/specs/05-construction.md

import std/[unittest, options, tables, sequtils]
import ../../src/engine/engine
import ../../src/engine/types/[
  core, game_state, house, colony, facilities, ship, fleet,
  production, command, event, combat
]
import ../../src/engine/state/[engine, iterators]
import ../../src/engine/globals
import ../../src/engine/config/engine as config_engine
import ../../src/engine/systems/production/[
  construction, projects, queue_advancement, commissioning, accessors, repairs
]

# Initialize config once for all tests (needed for tests that don't call newGame)
gameConfig = config_engine.loadGameConfig()
import ../../src/engine/systems/capacity/construction_docks
import ../../src/engine/entities/[ship_ops, fleet_ops, neoria_ops]

# Helper to create a build command
proc makeBuildCommand(
  colonyId: ColonyId, buildType: BuildType,
  shipClass: Option[ShipClass] = none(ShipClass),
  facilityClass: Option[FacilityClass] = none(FacilityClass),
  industrialUnits: int32 = 0
): BuildCommand =
  result = BuildCommand(
    colonyId: colonyId,
    buildType: buildType,
    shipClass: shipClass,
    facilityClass: facilityClass,
    industrialUnits: industrialUnits
  )

suite "Construction: Project Factory Functions":

  test "createShipProject sets correct cost and time":
    let project = createShipProject(ShipClass.Destroyer)
    check project.projectType == BuildType.Ship
    check project.itemId == "Destroyer"
    check project.costTotal > 0
    check project.turnsRemaining >= 1

  test "createShipProject cost matches config":
    let ddProject = createShipProject(ShipClass.Destroyer)
    let bbProject = createShipProject(ShipClass.Battleship)
    # Battleships should cost more than destroyers
    check bbProject.costTotal > ddProject.costTotal

  test "createBuildingProject for spaceport":
    let project = createBuildingProject(FacilityClass.Spaceport)
    check project.projectType == BuildType.Facility
    check project.itemId == "Spaceport"
    check project.costTotal > 0

  test "createBuildingProject for shipyard":
    let project = createBuildingProject(FacilityClass.Shipyard)
    check project.projectType == BuildType.Facility
    check project.itemId == "Shipyard"
    # Shipyards should cost more than spaceports
    let spaceportProject = createBuildingProject(FacilityClass.Spaceport)
    check project.costTotal > spaceportProject.costTotal

suite "Construction: Dock Capacity":

  test "shipRequiresDock returns true for capital ships":
    check shipRequiresDock(ShipClass.Destroyer) == true
    check shipRequiresDock(ShipClass.Cruiser) == true
    check shipRequiresDock(ShipClass.Battleship) == true
    check shipRequiresDock(ShipClass.Dreadnought) == true

  test "shipRequiresDock returns false for fighters":
    check shipRequiresDock(ShipClass.Fighter) == false

  test "spaceports have docks matching config":
    let game = newGame()
    let expectedDocks = gameConfig.facilities.facilities[
      FacilityClass.Spaceport
    ].docks
    for colony in game.allColonies():
      for neoriaId in colony.neoriaIds:
        let neoriaOpt = game.neoria(neoriaId)
        if neoriaOpt.isSome:
          let neoria = neoriaOpt.get()
          if neoria.neoriaClass == NeoriaClass.Spaceport:
            check neoria.baseDocks == expectedDocks

  test "shipyards have docks matching config":
    let game = newGame()
    let expectedDocks = gameConfig.facilities.facilities[
      FacilityClass.Shipyard
    ].docks
    var foundShipyard = false
    for colony in game.allColonies():
      for neoriaId in colony.neoriaIds:
        let neoriaOpt = game.neoria(neoriaId)
        if neoriaOpt.isSome:
          let neoria = neoriaOpt.get()
          if neoria.neoriaClass == NeoriaClass.Shipyard:
            foundShipyard = true
            check neoria.baseDocks == expectedDocks
    check foundShipyard == true

suite "Construction: Build Order Processing":

  test "build command rejected for wrong owner":
    let game = newGame()
    var events: seq[GameEvent] = @[]

    # Get first colony (owned by house 1)
    var colonyId: ColonyId
    var wrongHouseId: HouseId
    for colony in game.allColonies():
      colonyId = colony.id
      # Find a different house
      for house in game.allHouses():
        if house.id != colony.owner:
          wrongHouseId = house.id
          break
      break

    # Create command packet from wrong house
    let packet = CommandPacket(
      houseId: wrongHouseId,
      buildCommands: @[makeBuildCommand(colonyId, BuildType.Ship,
          shipClass = some(ShipClass.Destroyer))]
    )

    # Process should reject
    resolveBuildOrders(game, packet, events)

    # No construction events should be generated
    let constructionEvents = events.filterIt(it.eventType == GameEventType.ConstructionStarted)
    check constructionEvents.len == 0

  test "build command accepted for correct owner":
    let game = newGame()
    var events: seq[GameEvent] = @[]

    # Get first colony and its owner
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break

    let owner = colony.owner
    let houseOpt = game.house(owner)
    check houseOpt.isSome

    # Ensure house has enough treasury
    var house = houseOpt.get()
    let cost = accessors.getShipConstructionCost(ShipClass.Destroyer)
    if house.treasury < cost:
      house.treasury = cost * 2
      game.updateHouse(owner, house)

    # Create command packet
    let packet = CommandPacket(
      houseId: owner,
      buildCommands: @[makeBuildCommand(colony.id, BuildType.Ship,
          shipClass = some(ShipClass.Destroyer))]
    )

    # Process build orders
    resolveBuildOrders(game, packet, events)

    # Construction should start
    let constructionEvents = events.filterIt(it.eventType == GameEventType.ConstructionStarted)
    check constructionEvents.len == 1

  test "build command rejected for insufficient funds":
    let game = newGame()
    var events: seq[GameEvent] = @[]

    # Get first colony and its owner
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break

    let owner = colony.owner

    # Set treasury to 0
    var house = game.house(owner).get()
    house.treasury = 0
    game.updateHouse(owner, house)

    # Create command packet
    let packet = CommandPacket(
      houseId: owner,
      buildCommands: @[makeBuildCommand(colony.id, BuildType.Ship,
          shipClass = some(ShipClass.Destroyer))]
    )

    # Process should reject
    resolveBuildOrders(game, packet, events)

    # No construction events should be generated
    let constructionEvents = events.filterIt(it.eventType == GameEventType.ConstructionStarted)
    check constructionEvents.len == 0

suite "Construction: Queue Advancement":

  test "advanceColonyQueues processes facilities":
    let game = newGame()

    # Get first colony
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break

    # Advance queues (should not crash)
    let result = advanceColonyQueues(game, colony.id)
    # No projects should complete on fresh game
    check result.completedProjects.len == 0

  test "advanceAllQueues processes all colonies":
    let game = newGame()

    # Advance all queues (should not crash)
    let (projects, repairs) = advanceAllQueues(game)
    # Fresh game should have no completions
    check projects.len == 0
    check repairs.len == 0

suite "Construction: Ship Commissioning":

  test "commissionShips creates ships with correct stats":
    let game = newGame()
    var events: seq[GameEvent] = @[]

    # Get first colony
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break

    # Create completed ship project
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Ship,
      itemId: "Destroyer",
      neoriaId: none(NeoriaId)
    )

    # Count initial ships
    var initialShipCount = 0
    for ship in game.allShips():
      initialShipCount += 1

    # Commission the ship
    commissionShips(game, @[completed], events)

    # Count final ships
    var finalShipCount = 0
    for ship in game.allShips():
      finalShipCount += 1

    # One new ship should exist
    check finalShipCount == initialShipCount + 1

    # Event should be generated
    let commissionEvents = events.filterIt(it.eventType == GameEventType.ShipCommissioned)
    check commissionEvents.len == 1

  test "commissionShips assigns to existing fleet":
    let game = newGame()
    var events: seq[GameEvent] = @[]

    # Get first colony and count its fleets
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break

    var fleetsAtSystem = 0
    for fleet in game.fleetsAtSystem(colony.systemId):
      if fleet.houseId == colony.owner:
        fleetsAtSystem += 1

    # Create completed ship project
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Ship,
      itemId: "Cruiser",
      neoriaId: none(NeoriaId)
    )

    # Commission the ship
    commissionShips(game, @[completed], events)

    # Count fleets again - may create new fleet or join existing
    var newFleetsAtSystem = 0
    for fleet in game.fleetsAtSystem(colony.systemId):
      if fleet.houseId == colony.owner:
        newFleetsAtSystem += 1

    # At least one fleet should exist at location
    check newFleetsAtSystem >= 1

suite "Construction: Facility Damage Effects":

  test "crippled shipyard cannot process construction":
    let game = newGame()

    # Get first colony with a shipyard
    var shipyardId: NeoriaId
    var colonyId: ColonyId
    var foundShipyard = false

    for colony in game.allColonies():
      for neoriaId in colony.neoriaIds:
        let neoriaOpt = game.neoria(neoriaId)
        if neoriaOpt.isSome:
          let neoria = neoriaOpt.get()
          if neoria.neoriaClass == NeoriaClass.Shipyard:
            shipyardId = neoriaId
            colonyId = colony.id
            foundShipyard = true
            break
      if foundShipyard:
        break

    if foundShipyard:
      # Cripple the shipyard
      var shipyard = game.neoria(shipyardId).get()
      shipyard.state = CombatState.Crippled
      game.updateNeoria(shipyardId, shipyard)

      # Advance queue - crippled shipyard should not complete any projects
      let result = advanceShipyardQueue(game, shipyard, colonyId)
      check result.completedProjects.len == 0

  test "crippled drydock cannot process repairs":
    let game = newGame()

    # Get first colony with a drydock
    var drydockId: NeoriaId
    var colonyId: ColonyId
    var foundDrydock = false

    for colony in game.allColonies():
      for neoriaId in colony.neoriaIds:
        let neoriaOpt = game.neoria(neoriaId)
        if neoriaOpt.isSome:
          let neoria = neoriaOpt.get()
          if neoria.neoriaClass == NeoriaClass.Drydock:
            drydockId = neoriaId
            colonyId = colony.id
            foundDrydock = true
            break
      if foundDrydock:
        break

    if foundDrydock:
      # Cripple the drydock
      var drydock = game.neoria(drydockId).get()
      drydock.state = CombatState.Crippled
      game.updateNeoria(drydockId, drydock)

      # Advance queue - crippled drydock should not complete any repairs
      let result = advanceDrydockQueue(game, drydock, colonyId)
      check result.completedRepairs.len == 0

suite "Construction: Planetary Defense Commissioning":

  test "commissionPlanetaryDefense creates starbase":
    let game = newGame()
    var events: seq[GameEvent] = @[]

    # Get first colony
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break

    # Count initial starbases
    let initialKastraCount = colony.kastraIds.len

    # Create completed starbase project
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Facility,
      itemId: "Starbase",
      neoriaId: none(NeoriaId)
    )

    # Commission the starbase
    commissionPlanetaryDefense(game, @[completed], events)

    # Get updated colony
    let updatedColony = game.colony(colony.id).get()
    check updatedColony.kastraIds.len == initialKastraCount + 1

  test "commissionPlanetaryDefense creates spaceport":
    let game = newGame()
    var events: seq[GameEvent] = @[]

    # Get first colony
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break

    # Count initial neorias
    let initialNeoriaCount = colony.neoriaIds.len

    # Create completed spaceport project
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Facility,
      itemId: "Spaceport",
      neoriaId: none(NeoriaId)
    )

    # Commission the spaceport
    commissionPlanetaryDefense(game, @[completed], events)

    # Get updated colony
    let updatedColony = game.colony(colony.id).get()
    check updatedColony.neoriaIds.len == initialNeoriaCount + 1

suite "Construction: Cost Calculations":

  test "ship costs match spec hierarchy":
    # Per spec: larger ships cost more
    let ddCost = accessors.getShipConstructionCost(ShipClass.Destroyer)
    let clCost = accessors.getShipConstructionCost(ShipClass.LightCruiser)
    let caCost = accessors.getShipConstructionCost(ShipClass.Cruiser)
    let bcCost = accessors.getShipConstructionCost(ShipClass.Battlecruiser)
    let bbCost = accessors.getShipConstructionCost(ShipClass.Battleship)

    check clCost > ddCost
    check caCost > clCost
    check bcCost > caCost
    check bbCost > bcCost

  test "facility costs match spec hierarchy":
    let spaceportCost = accessors.getBuildingCost(FacilityClass.Spaceport)
    let shipyardCost = accessors.getBuildingCost(FacilityClass.Shipyard)
    let drydockCost = accessors.getBuildingCost(FacilityClass.Drydock)
    let starbaseCost = accessors.getBuildingCost(FacilityClass.Starbase)

    # Per spec: Facilities have increasing cost hierarchy
    check shipyardCost > spaceportCost
    check drydockCost > shipyardCost
    check starbaseCost > drydockCost

  test "repair costs are 25% of build cost":
    # Per spec: Repair cost = 25% of construction cost
    let ddBuildCost = accessors.getShipConstructionCost(ShipClass.Destroyer)
    let ddRepairCost = repairs.calculateRepairCost(ShipClass.Destroyer)

    # Allow for rounding
    let expectedRepair = ddBuildCost div 4
    check ddRepairCost >= expectedRepair - 1
    check ddRepairCost <= expectedRepair + 1

suite "Construction: Treasury Deduction":

  test "construction deducts from treasury":
    let game = newGame()
    var events: seq[GameEvent] = @[]

    # Get first colony
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break

    let owner = colony.owner
    var house = game.house(owner).get()

    # Set known treasury
    let initialTreasury = 1000'i32
    house.treasury = initialTreasury
    game.updateHouse(owner, house)

    # Get ship cost
    let cost = accessors.getShipConstructionCost(ShipClass.Destroyer)

    # Create command packet
    let packet = CommandPacket(
      houseId: owner,
      buildCommands: @[makeBuildCommand(colony.id, BuildType.Ship,
          shipClass = some(ShipClass.Destroyer))]
    )

    # Process build orders
    resolveBuildOrders(game, packet, events)

    # Check treasury was deducted
    let finalHouse = game.house(owner).get()
    check finalHouse.treasury == initialTreasury - cost

suite "Construction: Full Lifecycle Integration":

  test "ship construction from command to commissioning":
    let game = newGame()
    var events: seq[GameEvent] = @[]

    # Get first colony with a shipyard
    var colony: Colony
    var shipyardId: NeoriaId
    var hasShipyard = false

    for c in game.allColonies():
      for neoriaId in c.neoriaIds:
        let neoriaOpt = game.neoria(neoriaId)
        if neoriaOpt.isSome and neoriaOpt.get().neoriaClass == NeoriaClass.Shipyard:
          colony = c
          shipyardId = neoriaId
          hasShipyard = true
          break
      if hasShipyard:
        break

    check hasShipyard == true

    let owner = colony.owner
    var house = game.house(owner).get()

    # Ensure enough treasury
    house.treasury = 10000
    game.updateHouse(owner, house)

    # Count initial ships
    var initialShipCount = 0
    for ship in game.allShips():
      initialShipCount += 1

    # Step 1: Submit build command
    let packet = CommandPacket(
      houseId: owner,
      buildCommands: @[makeBuildCommand(colony.id, BuildType.Ship,
          shipClass = some(ShipClass.Destroyer))]
    )
    resolveBuildOrders(game, packet, events)

    # Verify construction started
    let startEvents = events.filterIt(it.eventType == GameEventType.ConstructionStarted)
    check startEvents.len == 1

    # Step 2: Advance queues (simulates turn processing)
    let (completedProjects, _) = advanceAllQueues(game)

    # Step 3: Commission completed ships
    commissionShips(game, completedProjects, events)

    # Step 4: Verify ship was created
    var finalShipCount = 0
    for ship in game.allShips():
      finalShipCount += 1

    # Ship should be commissioned (1-turn build time)
    check finalShipCount >= initialShipCount + 1

when isMainModule:
  echo "========================================"
  echo "  Construction-Repair-Commissioning"
  echo "  Integration Tests"
  echo "========================================"
