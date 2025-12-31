## Test Game Initialization
##
## Verifies that newGame() creates the correct starting configuration:
## - 4 players with proper houses
## - Each player has 4 fleets at homeworld
## - Fleet 1: ETAC with 1 PTU loaded
## - Fleet 2: Light Cruiser
## - Fleet 3: ETAC with 1 PTU loaded
## - Fleet 4: Light Cruiser
## - All fleets have GuardColony standing orders

import std/[unittest, tables, os]
import ../src/engine/initialization/game
import ../src/engine/gamestate
import ../src/engine/fleet
import ../src/engine/order_types
import ../src/common/types/[core, units]

suite "Game Initialization Tests":
  test "newGame creates 4 players with correct starting configuration":
    # Create a new 4-player game
    let game = newGame("test-game", 4, seed = 12345)

    # Verify 4 houses were created
    check game.houses.len == 4

    # Verify each house has correct fleet configuration
    for houseIdx in 0..<4:
      let houseId = "house" & $(houseIdx + 1)
      check houseId in game.houses

      # Get all fleets for this house
      var houseFleets: seq[Fleet] = @[]
      for fleetId, fleet in game.fleets:
        if fleet.owner == houseId:
          houseFleets.add(fleet)

      # Should have exactly 4 fleets
      check houseFleets.len == 4

      # Count fleet types
      var colonizationFleets = 0  # ETAC + Light Cruiser
      var destroyerFleets = 0      # Single Destroyer
      var totalPTUs = 0

      for fleet in houseFleets:
        # Check fleet location is at homeworld
        let homeworld = game.starMap.playerSystemIds[houseIdx]
        check fleet.location == homeworld

        # Fleet 1 & 2: ETAC + Light Cruiser (1 spacelift ship + 1 squadron)
        if fleet.spaceLiftShips.len == 1 and fleet.squadrons.len == 1:
          colonizationFleets += 1
          # Verify ETAC with exactly 1 PTU
          check fleet.spaceLiftShips[0].shipClass == ShipClass.ETAC
          check fleet.spaceLiftShips[0].cargo.cargoType == CargoClass.Colonists
          check fleet.spaceLiftShips[0].cargo.quantity == 1
          totalPTUs += fleet.spaceLiftShips[0].cargo.quantity
          # Verify Light Cruiser is the flagship of the squadron
          check fleet.squadrons[0].flagship.shipClass == ShipClass.LightCruiser
          # Verify squadron has no escort ships (just flagship)
          check fleet.squadrons[0].ships.len == 0
          # Verify fleet has GuardColony standing order
          check fleet.id in game.standingOrders
          let standingOrder = game.standingOrders[fleet.id]
          check standingOrder.orderType == StandingOrderType.GuardColony
          check standingOrder.enabled == true

        # Fleet 3 & 4: Single Destroyer (1 squadron, no spacelift)
        if fleet.squadrons.len == 1 and fleet.spaceLiftShips.len == 0:
          destroyerFleets += 1
          # Verify Destroyer is the flagship of the squadron
          check fleet.squadrons[0].flagship.shipClass == ShipClass.Destroyer
          # Verify squadron has no escort ships (just flagship)
          check fleet.squadrons[0].ships.len == 0
          # Verify fleet has GuardColony standing order
          check fleet.id in game.standingOrders
          let standingOrder = game.standingOrders[fleet.id]
          check standingOrder.orderType == StandingOrderType.GuardColony
          check standingOrder.enabled == true

      # Verify fleet composition: 2 colonization fleets, 2 destroyer fleets
      check colonizationFleets == 2
      check destroyerFleets == 2
      check totalPTUs == 2  # Each colonization fleet ETAC has 1 PTU

  test "newGame assigns GuardColony standing orders to all fleets":
    let game = newGame("test-game-2", 4, seed = 54321)

    # Check all fleets have GuardColony standing orders
    for fleetId, fleet in game.fleets:
      check fleetId in game.standingOrders

      let standingOrder = game.standingOrders[fleetId]
      check standingOrder.orderType == StandingOrderType.GuardColony
      check standingOrder.enabled == true
      check standingOrder.roe == 6  # Standard combat posture

  test "newGame creates homeworld colonies with correct starting conditions":
    let game = newGame("test-game-3", 4, seed = 99999)

    # Each house should have a homeworld colony
    for houseIdx in 0..<4:
      let houseId = "house" & $(houseIdx + 1)
      let homeworldSystemId = game.starMap.playerSystemIds[houseIdx]

      check homeworldSystemId in game.colonies

      let homeworld = game.colonies[homeworldSystemId]
      check homeworld.owner == houseId
      check homeworld.populationUnits == 840  # From standard.toml
      check homeworld.industrial.units == 420  # From standard.toml

  test "fleets have correct squadron and spacelift structure":
    let game = newGame("test-game-4", 2, seed = 11111)

    # Get first house's fleets
    let house1Id = "house1"
    var house1Fleets: seq[Fleet] = @[]

    for fleetId, fleet in game.fleets:
      if fleet.owner == house1Id:
        house1Fleets.add(fleet)

    check house1Fleets.len == 4

    # Verify fleet structure
    var colonizationFleets = 0  # ETAC + Light Cruiser
    var destroyerFleets = 0      # Destroyer only

    for fleet in house1Fleets:
      # Colonization fleet: 1 spacelift ship (ETAC) + 1 squadron (Light Cruiser)
      if fleet.spaceLiftShips.len == 1 and fleet.squadrons.len == 1:
        check fleet.spaceLiftShips[0].shipClass == ShipClass.ETAC
        # Verify Light Cruiser is the flagship (no escorts)
        check fleet.squadrons[0].flagship.shipClass == ShipClass.LightCruiser
        check fleet.squadrons[0].ships.len == 0  # No escort ships
        colonizationFleets += 1

      # Scout fleet: 1 squadron (Destroyer), no spacelift
      if fleet.squadrons.len == 1 and fleet.spaceLiftShips.len == 0:
        # Verify Destroyer is the flagship (no escorts)
        check fleet.squadrons[0].flagship.shipClass == ShipClass.Destroyer
        check fleet.squadrons[0].ships.len == 0  # No escort ships
        destroyerFleets += 1

    check colonizationFleets == 2
    check destroyerFleets == 2
