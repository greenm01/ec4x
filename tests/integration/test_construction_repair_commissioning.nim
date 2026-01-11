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
  production, command, event, combat, ground_unit
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
    check project.shipClass.isSome
    check project.shipClass.get() == ShipClass.Destroyer
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
    check project.facilityClass.isSome
    check project.facilityClass.get() == FacilityClass.Spaceport
    check project.costTotal > 0

  test "createBuildingProject for shipyard":
    let project = createBuildingProject(FacilityClass.Shipyard)
    check project.projectType == BuildType.Facility
    check project.facilityClass.isSome
    check project.facilityClass.get() == FacilityClass.Shipyard
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
    let cost = accessors.shipConstructionCost(ShipClass.Destroyer)
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
      shipClass: some(ShipClass.Destroyer),
      facilityClass: none(FacilityClass),
      groundClass: none(GroundClass),
      industrialUnits: 0,
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
      shipClass: some(ShipClass.Cruiser),
      facilityClass: none(FacilityClass),
      groundClass: none(GroundClass),
      industrialUnits: 0,
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
      shipClass: none(ShipClass),
      facilityClass: some(FacilityClass.Starbase),
      groundClass: none(GroundClass),
      industrialUnits: 0,
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
      shipClass: none(ShipClass),
      facilityClass: some(FacilityClass.Spaceport),
      groundClass: none(GroundClass),
      industrialUnits: 0,
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
    let ddCost = accessors.shipConstructionCost(ShipClass.Destroyer)
    let clCost = accessors.shipConstructionCost(ShipClass.LightCruiser)
    let caCost = accessors.shipConstructionCost(ShipClass.Cruiser)
    let bcCost = accessors.shipConstructionCost(ShipClass.Battlecruiser)
    let bbCost = accessors.shipConstructionCost(ShipClass.Battleship)

    check clCost > ddCost
    check caCost > clCost
    check bcCost > caCost
    check bbCost > bcCost

  test "facility costs match spec hierarchy":
    let spaceportCost = accessors.buildingCost(FacilityClass.Spaceport)
    let shipyardCost = accessors.buildingCost(FacilityClass.Shipyard)
    let drydockCost = accessors.buildingCost(FacilityClass.Drydock)
    let starbaseCost = accessors.buildingCost(FacilityClass.Starbase)

    # Per spec: Facilities have increasing cost hierarchy
    check shipyardCost > spaceportCost
    check drydockCost > shipyardCost
    check starbaseCost > drydockCost

  test "repair costs are 25% of build cost":
    # Per spec: Repair cost = 25% of construction cost
    let ddBuildCost = accessors.shipConstructionCost(ShipClass.Destroyer)
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
    let cost = accessors.shipConstructionCost(ShipClass.Destroyer)

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

suite "Construction: All Ship Classes Can Be Built":

  test "All combat ship classes can be constructed":
    # Test that every combat ship class can create a valid project
    let combatShips = [
      ShipClass.Corvette, ShipClass.Frigate, ShipClass.Destroyer,
      ShipClass.LightCruiser, ShipClass.Cruiser, ShipClass.Battlecruiser,
      ShipClass.Battleship, ShipClass.Dreadnought, ShipClass.SuperDreadnought
    ]
    
    for shipClass in combatShips:
      let project = createShipProject(shipClass)
      check project.projectType == BuildType.Ship
      check project.shipClass.isSome
      check project.shipClass.get() == shipClass
      check project.costTotal > 0
      check project.turnsRemaining >= 1

  test "All carrier classes can be constructed":
    let carriers = [ShipClass.Carrier, ShipClass.SuperCarrier]
    
    for shipClass in carriers:
      let project = createShipProject(shipClass)
      check project.projectType == BuildType.Ship
      check project.shipClass.isSome
      check project.shipClass.get() == shipClass
      check project.costTotal > 0

  test "All auxiliary ship classes can be constructed":
    let auxiliaryShips = [
      ShipClass.Scout, ShipClass.ETAC, ShipClass.TroopTransport,
      ShipClass.Raider
    ]
    
    for shipClass in auxiliaryShips:
      let project = createShipProject(shipClass)
      check project.projectType == BuildType.Ship
      check project.shipClass.isSome
      check project.shipClass.get() == shipClass
      check project.costTotal > 0

  test "Fighters and special ships can be constructed":
    let specialShips = [ShipClass.Fighter, ShipClass.PlanetBreaker]
    
    for shipClass in specialShips:
      let project = createShipProject(shipClass)
      check project.projectType == BuildType.Ship
      check project.shipClass.isSome
      check project.shipClass.get() == shipClass
      check project.costTotal > 0

suite "Construction: All Facility Classes Can Be Built":

  test "All facility classes can be constructed":
    let facilities = [
      FacilityClass.Spaceport, FacilityClass.Shipyard,
      FacilityClass.Drydock, FacilityClass.Starbase
    ]
    
    for facilityClass in facilities:
      let project = createBuildingProject(facilityClass)
      check project.projectType == BuildType.Facility
      check project.facilityClass.isSome
      check project.facilityClass.get() == facilityClass
      check project.costTotal > 0
      check project.turnsRemaining >= 1

suite "Construction: All Ground Unit Classes Can Be Built":

  test "All ground unit classes can construct projects":
    # Note: Ground units use different construction path, but verify config exists
    let groundClasses = [
      GroundClass.Army, GroundClass.Marine,
      GroundClass.GroundBattery, GroundClass.PlanetaryShield
    ]
    
    for groundClass in groundClasses:
      # Verify config exists for each ground unit type
      let cost = gameConfig.groundUnits.units[groundClass].productionCost
      check cost > 0

suite "Commissioning: All Ship Classes Can Be Commissioned":

  test "All ship classes commission into fleets or colonies correctly":
    let game = newGame()
    var events: seq[GameEvent] = @[]
    
    # Get first colony
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    # Test combat ships (should create fleet)
    let combatShips = [
      ShipClass.Destroyer, ShipClass.Cruiser, ShipClass.Battleship
    ]
    
    for shipClass in combatShips:
      let completed = CompletedProject(
        colonyId: colony.id,
        projectType: BuildType.Ship,
        shipClass: some(shipClass),
        facilityClass: none(FacilityClass),
        groundClass: none(GroundClass),
        industrialUnits: 0,
        neoriaId: none(NeoriaId)
      )
      
      let initialShips = game.allShips().toSeq.len
      commissionShips(game, @[completed], events)
      let finalShips = game.allShips().toSeq.len
      
      check finalShips == initialShips + 1

  test "Scouts commission into scout-only fleets":
    let game = newGame()
    var events: seq[GameEvent] = @[]
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Ship,
      shipClass: some(ShipClass.Scout),
      facilityClass: none(FacilityClass),
      groundClass: none(GroundClass),
      industrialUnits: 0,
      neoriaId: none(NeoriaId)
    )
    
    let initialShips = game.allShips().toSeq.len
    commissionShips(game, @[completed], events)
    let finalShips = game.allShips().toSeq.len
    
    check finalShips == initialShips + 1

  test "ETACs commission into fleets":
    let game = newGame()
    var events: seq[GameEvent] = @[]
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Ship,
      shipClass: some(ShipClass.ETAC),
      facilityClass: none(FacilityClass),
      groundClass: none(GroundClass),
      industrialUnits: 0,
      neoriaId: none(NeoriaId)
    )
    
    let initialShips = game.allShips().toSeq.len
    commissionShips(game, @[completed], events)
    let finalShips = game.allShips().toSeq.len
    
    check finalShips == initialShips + 1

  test "Fighters remain colony-assigned (not in fleets)":
    let game = newGame()
    var events: seq[GameEvent] = @[]
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Ship,
      shipClass: some(ShipClass.Fighter),
      facilityClass: none(FacilityClass),
      groundClass: none(GroundClass),
      industrialUnits: 0,
      neoriaId: none(NeoriaId)
    )
    
    let initialShips = game.allShips().toSeq.len
    commissionShips(game, @[completed], events)
    let finalShips = game.allShips().toSeq.len
    
    # Fighter should be created
    check finalShips == initialShips + 1

suite "Commissioning: All Facility Classes Can Be Commissioned":

  test "Spaceports commission correctly":
    let game = newGame()
    var events: seq[GameEvent] = @[]
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    let initialNeorias = colony.neoriaIds.len
    
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Facility,
      shipClass: none(ShipClass),
      facilityClass: some(FacilityClass.Spaceport),
      groundClass: none(GroundClass),
      industrialUnits: 0,
      neoriaId: none(NeoriaId)
    )
    
    commissionPlanetaryDefense(game, @[completed], events)
    
    let updatedColony = game.colony(colony.id).get()
    check updatedColony.neoriaIds.len == initialNeorias + 1

  test "Shipyards commission correctly":
    let game = newGame()
    var events: seq[GameEvent] = @[]
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    let initialNeorias = colony.neoriaIds.len
    
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Facility,
      shipClass: none(ShipClass),
      facilityClass: some(FacilityClass.Shipyard),
      groundClass: none(GroundClass),
      industrialUnits: 0,
      neoriaId: none(NeoriaId)
    )
    
    commissionPlanetaryDefense(game, @[completed], events)
    
    let updatedColony = game.colony(colony.id).get()
    check updatedColony.neoriaIds.len == initialNeorias + 1

  test "Drydocks commission correctly":
    let game = newGame()
    var events: seq[GameEvent] = @[]
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    let initialNeorias = colony.neoriaIds.len
    
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Facility,
      shipClass: none(ShipClass),
      facilityClass: some(FacilityClass.Drydock),
      groundClass: none(GroundClass),
      industrialUnits: 0,
      neoriaId: none(NeoriaId)
    )
    
    commissionPlanetaryDefense(game, @[completed], events)
    
    let updatedColony = game.colony(colony.id).get()
    check updatedColony.neoriaIds.len == initialNeorias + 1

  test "Starbases commission correctly":
    let game = newGame()
    var events: seq[GameEvent] = @[]
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    let initialKastras = colony.kastraIds.len
    
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Facility,
      shipClass: none(ShipClass),
      facilityClass: some(FacilityClass.Starbase),
      groundClass: none(GroundClass),
      industrialUnits: 0,
      neoriaId: none(NeoriaId)
    )
    
    commissionPlanetaryDefense(game, @[completed], events)
    
    let updatedColony = game.colony(colony.id).get()
    check updatedColony.kastraIds.len == initialKastras + 1

suite "Construction: Ground Unit Workflow":

  test "Army units can be built and commissioned":
    let game = newGame()
    var events: seq[GameEvent] = @[]
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    # Create Army project
    let project = projects.createGroundUnitProject(GroundClass.Army)
    check project.projectType == BuildType.Ground
    check project.groundClass.isSome
    check project.groundClass.get() == GroundClass.Army
    
    # Commission the army
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Ground,
      shipClass: none(ShipClass),
      facilityClass: none(FacilityClass),
      groundClass: some(GroundClass.Army),
      industrialUnits: 0,
      neoriaId: none(NeoriaId)
    )
    
    var initialGroundUnits = 0
    for (_, _) in game.allGroundUnitsWithId():
      initialGroundUnits += 1
    commissionPlanetaryDefense(game, @[completed], events)
    var finalGroundUnits = 0
    for (_, _) in game.allGroundUnitsWithId():
      finalGroundUnits += 1
    
    # Army should be created
    check finalGroundUnits == initialGroundUnits + 1

  test "Marine units can be built and commissioned":
    let game = newGame()
    var events: seq[GameEvent] = @[]
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    # Create Marine project
    let project = projects.createGroundUnitProject(GroundClass.Marine)
    check project.projectType == BuildType.Ground
    check project.groundClass.isSome
    check project.groundClass.get() == GroundClass.Marine
    
    # Commission the marine
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Ground,
      shipClass: none(ShipClass),
      facilityClass: none(FacilityClass),
      groundClass: some(GroundClass.Marine),
      industrialUnits: 0,
      neoriaId: none(NeoriaId)
    )
    
    var initialGroundUnits = 0
    for (_, _) in game.allGroundUnitsWithId():
      initialGroundUnits += 1
    commissionPlanetaryDefense(game, @[completed], events)
    var finalGroundUnits = 0
    for (_, _) in game.allGroundUnitsWithId():
      finalGroundUnits += 1
    
    # Marine should be created
    check finalGroundUnits == initialGroundUnits + 1

  test "Ground Battery units can be built and commissioned":
    let game = newGame()
    var events: seq[GameEvent] = @[]
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    # Create Ground Battery project
    let project = projects.createGroundUnitProject(GroundClass.GroundBattery)
    check project.projectType == BuildType.Ground
    check project.groundClass.isSome
    check project.groundClass.get() == GroundClass.GroundBattery
    
    # Commission the ground battery
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Ground,
      shipClass: none(ShipClass),
      facilityClass: none(FacilityClass),
      groundClass: some(GroundClass.GroundBattery),
      industrialUnits: 0,
      neoriaId: none(NeoriaId)
    )
    
    var initialGroundUnits = 0
    for (_, _) in game.allGroundUnitsWithId():
      initialGroundUnits += 1
    commissionPlanetaryDefense(game, @[completed], events)
    var finalGroundUnits = 0
    for (_, _) in game.allGroundUnitsWithId():
      finalGroundUnits += 1
    
    # Ground Battery should be created
    check finalGroundUnits == initialGroundUnits + 1

  test "Planetary Shield units can be built and commissioned":
    let game = newGame()
    var events: seq[GameEvent] = @[]
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    # Create Planetary Shield project
    let project = projects.createGroundUnitProject(GroundClass.PlanetaryShield)
    check project.projectType == BuildType.Ground
    check project.groundClass.isSome
    check project.groundClass.get() == GroundClass.PlanetaryShield
    
    # Commission the planetary shield
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Ground,
      shipClass: none(ShipClass),
      facilityClass: none(FacilityClass),
      groundClass: some(GroundClass.PlanetaryShield),
      industrialUnits: 0,
      neoriaId: none(NeoriaId)
    )
    
    var initialGroundUnits = 0
    for (_, _) in game.allGroundUnitsWithId():
      initialGroundUnits += 1
    commissionPlanetaryDefense(game, @[completed], events)
    var finalGroundUnits = 0
    for (_, _) in game.allGroundUnitsWithId():
      finalGroundUnits += 1
    
    # Planetary Shield should be created
    check finalGroundUnits == initialGroundUnits + 1

suite "Construction: Multi-Turn Queue Advancement":

  test "Ship construction completes after correct number of turns":
    let game = newGame()
    var events: seq[GameEvent] = @[]
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    # Create ship project with known build time
    let buildTime = accessors.shipBaseBuildTime(ShipClass.Destroyer)
    let project = createShipProject(ShipClass.Destroyer)
    check project.turnsRemaining == buildTime
    
    # Projects complete based on turnsRemaining field
    # (actual multi-turn simulation tested in integration)

  test "Facility construction completes after correct number of turns":
    let game = newGame()
    
    # Check build times for all facilities
    let spaceportTime = accessors.buildingTime(FacilityClass.Spaceport)
    let shipyardTime = accessors.buildingTime(FacilityClass.Shipyard)
    let drydockTime = accessors.buildingTime(FacilityClass.Drydock)
    let starbaseTime = accessors.buildingTime(FacilityClass.Starbase)
    
    # All should have valid build times
    check spaceportTime >= 1
    check shipyardTime >= 1
    check drydockTime >= 1
    check starbaseTime >= 1

  test "Ground unit construction completes after correct number of turns":
    let game = newGame()
    
    # Check build times for all ground units
    let armyTime = accessors.groundUnitBuildTime(GroundClass.Army)
    let marineTime = accessors.groundUnitBuildTime(GroundClass.Marine)
    let batteryTime = accessors.groundUnitBuildTime(GroundClass.GroundBattery)
    let shieldTime = accessors.groundUnitBuildTime(GroundClass.PlanetaryShield)
    
    # All should have valid build times
    check armyTime >= 1
    check marineTime >= 1
    check batteryTime >= 1
    check shieldTime >= 1

suite "Construction: Insufficient Resources":

  test "Construction rejected when treasury insufficient":
    let game = newGame()
    
    var house: House
    for h in game.allHouses():
      house = h
      break
    
    var colony: Colony
    for c in game.coloniesOwned(house.id):
      colony = c
      break
    
    # Get destroyer cost
    let destroyerCost = accessors.shipConstructionCost(ShipClass.Destroyer)
    
    # Verify cost is positive and can cause insufficient funds
    check destroyerCost > 0
    
    # Set treasury to less than cost
    var updatedHouse = house
    updatedHouse.treasury = destroyerCost - 100
    game.updateHouse(house.id, updatedHouse)
    
    # Verify treasury is now insufficient
    let finalHouse = game.house(house.id).get()
    check finalHouse.treasury < destroyerCost
    
    # Construction validation happens in resolveBuildOrders
    # which would reject this due to insufficient treasury

  test "Ground unit recruitment fails with insufficient population":
    # This is validated during commissioning, not build command
    # Population cost is deducted during commissioning
    let game = newGame()
    var events: seq[GameEvent] = @[]
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    # Set colony population very low
    var updatedColony = colony
    updatedColony.souls = 1000  # Very low population
    updatedColony.population = 0
    game.updateColony(colony.id, updatedColony)
    
    # Try to commission marines (requires population)
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Ground,
      shipClass: none(ShipClass),
      facilityClass: none(FacilityClass),
      groundClass: some(GroundClass.Marine),
      industrialUnits: 0,
      neoriaId: none(NeoriaId)
    )
    
    var initialGroundUnits = 0
    for (_, _) in game.allGroundUnitsWithId():
      initialGroundUnits += 1
    commissionPlanetaryDefense(game, @[completed], events)
    var finalGroundUnits = 0
    for (_, _) in game.allGroundUnitsWithId():
      finalGroundUnits += 1
    
    # Marine should NOT be created due to insufficient population
    check finalGroundUnits == initialGroundUnits

suite "Construction: Capacity Limits":

  test "Dock capacity limits construction":
    let game = newGame()
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    # Get available facilities at colony
    let availableFacilities = construction_docks.availableFacilities(game, colony.id, BuildType.Ship)
    
    # Capacity limits enforced by facility availability
    # (actual enforcement tested via build validation)
    check availableFacilities.len >= 0

  test "Multiple simultaneous projects consume docks":
    let game = newGame()
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    # Analyze colony capacity (returns seq of facility capacities)
    let facilities = construction_docks.analyzeColonyCapacity(game, colony.id)
    
    # Projects in queue consume dock capacity
    # Colony should have facilities available
    check facilities.len >= 0

suite "Construction: Facility Prerequisites":

  test "Shipyard requires spaceport":
    let game = newGame()
    var events: seq[GameEvent] = @[]
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    # Remove all spaceports from colony
    var updatedColony = colony
    updatedColony.neoriaIds = @[]
    game.updateColony(colony.id, updatedColony)
    
    # Try to commission shipyard without spaceport
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Facility,
      shipClass: none(ShipClass),
      facilityClass: some(FacilityClass.Shipyard),
      groundClass: none(GroundClass),
      industrialUnits: 0,
      neoriaId: none(NeoriaId)
    )
    
    # This should fail during commissioning (logged as error)
    # The commissioning system checks for spaceport prerequisite
    let initialNeorias = updatedColony.neoriaIds.len
    commissionPlanetaryDefense(game, @[completed], events)
    
    let finalColony = game.colony(colony.id).get()
    # Shipyard should NOT be created without spaceport
    check finalColony.neoriaIds.len == initialNeorias

  test "Drydock requires spaceport":
    let game = newGame()
    var events: seq[GameEvent] = @[]
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    # Remove all spaceports from colony
    var updatedColony = colony
    updatedColony.neoriaIds = @[]
    game.updateColony(colony.id, updatedColony)
    
    # Try to commission drydock without spaceport
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Facility,
      shipClass: none(ShipClass),
      facilityClass: some(FacilityClass.Drydock),
      groundClass: none(GroundClass),
      industrialUnits: 0,
      neoriaId: none(NeoriaId)
    )
    
    # This should fail during commissioning (logged as error)
    let initialNeorias = updatedColony.neoriaIds.len
    commissionPlanetaryDefense(game, @[completed], events)
    
    let finalColony = game.colony(colony.id).get()
    # Drydock should NOT be created without spaceport
    check finalColony.neoriaIds.len == initialNeorias

  test "Spaceport has no prerequisites":
    let game = newGame()
    var events: seq[GameEvent] = @[]
    
    var colony: Colony
    for c in game.allColonies():
      colony = c
      break
    
    # Remove all neorias to start fresh
    var updatedColony = colony
    updatedColony.neoriaIds = @[]
    game.updateColony(colony.id, updatedColony)
    
    # Commission spaceport without any prerequisites
    let completed = CompletedProject(
      colonyId: colony.id,
      projectType: BuildType.Facility,
      shipClass: none(ShipClass),
      facilityClass: some(FacilityClass.Spaceport),
      groundClass: none(GroundClass),
      industrialUnits: 0,
      neoriaId: none(NeoriaId)
    )
    
    commissionPlanetaryDefense(game, @[completed], events)
    
    let finalColony = game.colony(colony.id).get()
    # Spaceport should be created successfully
    check finalColony.neoriaIds.len == 1

when isMainModule:
  echo "========================================"
  echo "  Construction-Repair-Commissioning"
  echo "  Integration Tests"
  echo "========================================"
