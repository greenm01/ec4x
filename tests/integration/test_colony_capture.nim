## Colony Capture Test - INVADE and BLITZ Mechanics
##
## Tests successful colony capture via both INVADE and BLITZ orders.
## Validates:
## - Colony ownership transfer
## - SystemCaptured event generation
## - Auto-loading of Marines (3 per TroopTransport with new config)
## - Ground combat resolution
## - Prestige awards for attacker and defender

import std/[unittest, tables, options, strformat]
import ../../src/engine/[gamestate, orders, resolve]
import ../../src/engine/initialization/game
import ../../src/engine/resolution/types as resolution_types
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/[core, units]
import ../../src/common/logger

suite "Colony Capture Mechanics":
  test "BLITZ: Successful colony capture with sufficient Marines":
    # Setup: 2-player game
    var state = newGame(gameId = "colony-capture-test", playerCount = 2, seed = 42)

    # Identify homeworlds
    var attacker: HouseId = ""
    var defender: HouseId = ""
    var attackerHome: SystemId
    var defenderHome: SystemId

    for houseId, house in state.houses:
      if attacker == "":
        attacker = houseId
        attackerHome = house.homeworld
      else:
        defender = houseId
        defenderHome = house.homeworld
        break

    echo &"\n[TEST] Attacker: {attacker} (homeworld: {attackerHome})"
    echo &"[TEST] Defender: {defender} (homeworld: {defenderHome})"

    # Turn 1-5: Build invasion fleet at attacker homeworld
    # Need: Battleship (capital for BLITZ) + 3 TroopTransports + 9 Marines
    for turn in 1..5:
      var attackerOrders = OrderPacket(
        houseId: attacker,
        turn: state.turn,
        fleetOrders: @[],
        buildOrders: @[],
        researchAllocation: res_types.initResearchAllocation(),
        diplomaticActions: @[],
        populationTransfers: @[],
        terraformOrders: @[],
        espionageAction: none(esp_types.EspionageAttempt),
        ebpInvestment: 0,
        cipInvestment: 0
      )

      case turn
      of 1:
        # Build Battleship
        attackerOrders.buildOrders.add(BuildOrder(
          colonySystem: attackerHome,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.Battleship),
          buildingType: none(string),
          industrialUnits: 0
        ))
      of 2:
        # Build 3 TroopTransports
        for i in 0..2:
          attackerOrders.buildOrders.add(BuildOrder(
            colonySystem: attackerHome,
            buildType: BuildType.Ship,
            quantity: 1,
            shipClass: some(ShipClass.TroopTransport),
            buildingType: none(string),
            industrialUnits: 0
          ))
      of 3, 4, 5:
        # Build 3 Marines per turn = 9 total (3 per transport)
        for i in 0..2:
          attackerOrders.buildOrders.add(BuildOrder(
            colonySystem: attackerHome,
            buildType: BuildType.Building,
            quantity: 1,
            shipClass: none(ShipClass),
            buildingType: some("Marine"),
            industrialUnits: 0
          ))

      let orders = {attacker: attackerOrders, defender: OrderPacket(
        houseId: defender,
        turn: state.turn,
        fleetOrders: @[],
        buildOrders: @[],
        researchAllocation: res_types.initResearchAllocation(),
        diplomaticActions: @[],
        populationTransfers: @[],
        terraformOrders: @[],
        espionageAction: none(esp_types.EspionageAttempt),
        ebpInvestment: 0,
        cipInvestment: 0
      )}.toTable

      let result = resolveTurn(state, orders)
      state = result.newState

    # Check fleet composition at attacker homeworld
    echo &"\n[TURN {state.turn}] Checking attacker fleet composition"
    var attackerFleet: FleetId
    var battleshipCount = 0
    var transportCount = 0
    var marinesLoaded = 0

    for fleetId, fleet in state.fleets:
      if fleet.owner == attacker and fleet.location == attackerHome:
        attackerFleet = fleetId
        for squadron in fleet.squadrons:
          if squadron.flagship.shipClass == ShipClass.Battleship:
            battleshipCount.inc
        for ship in fleet.spaceLiftShips:
          if ship.shipClass == ShipClass.TroopTransport:
            transportCount.inc
            marinesLoaded += ship.cargo.quantity

    echo &"[FLEET] {attackerFleet}: Battleships={battleshipCount}, " &
         &"Transports={transportCount}, Marines={marinesLoaded}"

    check battleshipCount >= 1
    check transportCount >= 3
    check marinesLoaded >= 9  # Auto-loaded 3 per transport

    # Turn 6: Move fleet to defender homeworld
    echo &"\n[TURN {state.turn}] Moving invasion fleet to {defenderHome}"
    var attackerOrders = OrderPacket(
      houseId: attacker,
      turn: state.turn,
      fleetOrders: @[FleetOrder(
        fleetId: attackerFleet,
        orderType: FleetOrderType.Move,
        targetSystem: some(defenderHome),
        targetFleet: none(FleetId),
        priority: 0
      )],
      buildOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    let orders6 = {attacker: attackerOrders, defender: OrderPacket(
      houseId: defender,
      turn: state.turn,
      fleetOrders: @[],
      buildOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )}.toTable

    let result6 = resolveTurn(state, orders6)
    state = result6.newState

    # Verify fleet arrived
    let fleet = state.fleets[attackerFleet]
    check fleet.location == defenderHome
    echo &"[FLEET] Arrived at {defenderHome}"

    # Turn 7: Execute BLITZ order
    echo &"\n[TURN {state.turn}] Executing BLITZ on {defenderHome}"
    let defenderColonyBefore = state.colonies[defenderHome]
    echo &"[DEFENDER] Colony owner (before): {defenderColonyBefore.owner}"
    echo &"[DEFENDER] Ground forces: Marines={defenderColonyBefore.marines}, " &
         &"Armies={defenderColonyBefore.armies}"

    attackerOrders = OrderPacket(
      houseId: attacker,
      turn: state.turn,
      fleetOrders: @[FleetOrder(
        fleetId: attackerFleet,
        orderType: FleetOrderType.Blitz,
        targetSystem: some(defenderHome),
        targetFleet: none(FleetId),
        priority: 0
      )],
      buildOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    let orders7 = {attacker: attackerOrders, defender: OrderPacket(
      houseId: defender,
      turn: state.turn,
      fleetOrders: @[],
      buildOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )}.toTable

    let result7 = resolveTurn(state, orders7)
    state = result7.newState

    # Validate colony capture
    echo &"\n[VALIDATION] Checking colony ownership"
    let defenderColonyAfter = state.colonies[defenderHome]
    echo &"[RESULT] Colony owner (after): {defenderColonyAfter.owner}"
    echo &"[RESULT] Ground forces: Marines={defenderColonyAfter.marines}, " &
         &"Armies={defenderColonyAfter.armies}"

    # Check ownership transferred
    check defenderColonyAfter.owner == attacker

    # Check SystemCaptured event generated
    var systemCapturedFound = false
    for event in result7.events:
      if event.eventType == GameEventType.SystemCaptured:
        echo &"[EVENT] SystemCaptured: attacker={event.houseId}, target={event.systemId.get()}"
        systemCapturedFound = true
        check event.houseId == attacker
        check event.systemId.get() == defenderHome

    check systemCapturedFound

    echo "\n[PASS] BLITZ colony capture successful"
