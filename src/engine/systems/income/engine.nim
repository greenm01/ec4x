## Economy Engine - Income Phase Orchestration
##
## Main entry point for economy system
## Orchestrates income calculation, tax collection, population growth
##
## Per gameplay.md:1.3.2 - Income Phase runs AFTER Conflict Phase
## Infrastructure damage from combat affects production
##
## **Architecture:**
## - Uses state layer APIs to read entities (state.ship, state.colony, state.house)
## - Uses entity ops for mutations (ship_ops.destroyShip)
## - Follows three-layer pattern: State → Business Logic → Entity Ops

import std/[tables, options, algorithm]
import ./[income, maintenance, multipliers]
import
  ../../types/
    [game_state, core, ship, event, income as income_types, colony, facilities, ground_unit]
import ../../state/[engine, iterators]
import ../../entities/ship_ops
import ../../globals

export income_types.IncomePhaseReport, income_types.HouseIncomeReport
export colony.ColonyIncomeReport
export multipliers  # Export economic multipliers (popGrowthMultiplier, etc.)
# NOTE: Don't export game_state.Colony to avoid ambiguity

## Income Phase Resolution (gameplay.md:1.3.2)
##
## **Optimization History:**
## - Pre-2026-01-06: Legacy API with manual colony grouping and table passing
##   * Passed colonies: var seq[Colony] (manually grouped)
##   * Passed houseTaxPolicies, houseTechLevels, houseCSTTechLevels, houseTreasuries
##   * Required O(c) scan to group colonies by owner
## - 2026-01-06: Optimized to use state layer APIs and Colonies.byOwner index
##   * Uses state.coloniesOwned(houseId) for O(1) lookup via index
##   * Gets house data directly from state (no table construction)
##   * Mutates state in-place using updateHouse()/updateColony()
##   * Eliminated 25+ lines of parameter building and passing

proc resolveIncomePhase*(
    state: var GameState, baseGrowthRate: float32 = 0.015
): IncomePhaseReport =
  ## Resolve income phase for all houses
  ##
  ## Uses state layer APIs to access colonies via Colonies.byOwner index
  ## and house data directly, eliminating manual grouping and table passing.
  ##
  ## Steps:
  ## 1. Calculate GCO for all colonies (after conflict damage)
  ## 2. Apply tax policy
  ## 3. Calculate prestige effects
  ## 4. Update treasuries
  ## 5. Apply population growth
  ##
  ## Args:
  ##   state: GameState (mutated with treasury/growth updates)
  ##   baseGrowthRate: Base population growth rate (loaded from config)
  ##
  ## Returns:
  ##   Complete income phase report

  result = IncomePhaseReport(
    turn: state.turn, houseReports: initTable[HouseId, HouseIncomeReport]()
  )

  # Process each house using state layer APIs
  for (houseId, house) in state.activeHousesWithId():
    # Get house parameters directly from state
    let taxPolicy = house.taxPolicy
    let elTech = house.techTree.levels.el # Economic Level
    let cstTech = house.techTree.levels.cst # Construction tech
    let treasury = house.treasury

    # Collect this house's colonies using byOwner index
    var houseColonies: seq[Colony] = @[]
    for colony in state.coloniesOwned(houseId):
      houseColonies.add(colony)

    # Calculate house income
    let houseReport =
      calculateHouseIncome(state, houseColonies, elTech, cstTech, taxPolicy, treasury)

    # Update treasury in state
    var updatedHouse = house
    updatedHouse.treasury = houseReport.treasuryAfter
    state.updateHouse(houseId, updatedHouse)

    # Apply population and industrial growth to colonies
    for colony in state.coloniesOwned(houseId):
      var updatedColony = colony
      discard state.applyPopulationGrowth(
        updatedColony, taxPolicy.currentRate, baseGrowthRate
      )
      discard state.applyIndustrialGrowth(
        updatedColony, taxPolicy.currentRate, baseGrowthRate
      )
      state.updateColony(colony.id, updatedColony)

    # Store report
    result.houseReports[houseId] = houseReport

## Auto-Salvage System (economy.md:3.9.1)

proc processCrippledShipSalvage*(
    state: var GameState, events: var seq[event.GameEvent]
): Table[HouseId, int32] =
  ## Process auto-salvage for ships crippled for 2+ turns
  ## Ships crippled for 2 consecutive turns are auto-salvaged at 50% of build cost
  ## Returns salvage revenue per house for reporting
  ##
  ## Per economy.md:3.9.1 - Grace period of 2 turns before salvage
  ## Salvage value: 50% of production cost (from config/ships.kdl)

  result = initTable[HouseId, int32]()

  # Track ships to destroy (can't modify during iteration)
  var shipsToSalvage: seq[(ShipId, HouseId, ShipClass)] = @[]

  # Collect all ships that have been in maintenance shortfall for 2+ turns
  for (houseId, house) in state.activeHousesWithId():
    # Check house maintenance shortfall table for ships at 2+ turns
    for shipId, shortfallTurns in house.maintenanceShortfallShips.pairs:
      if shortfallTurns >= 2:
        # Get ship to determine class for salvage value
        let shipOpt = state.ship(shipId)
        if shipOpt.isSome:
          let ship = shipOpt.get()
          shipsToSalvage.add((shipId, houseId, ship.shipClass))

  # Salvage collected ships and pay out
  for (shipId, houseId, shipClass) in shipsToSalvage:
    # Calculate salvage value: 50% of production cost
    let productionCost = gameConfig.ships.ships[shipClass].productionCost
    let salvageValue =
      int32(float32(productionCost) * gameConfig.ships.salvage.salvageValueMultiplier)

    # Add salvage to house treasury and remove from maintenance tracking
    let houseOpt = state.house(houseId)
    if houseOpt.isSome:
      var house = houseOpt.get()
      house.treasury += salvageValue

      # Remove ship from maintenance shortfall tracking table
      house.maintenanceShortfallShips.del(shipId)

      state.updateHouse(houseId, house)

      # Track salvage revenue for reporting
      result.mgetOrPut(houseId, 0) += salvageValue

    # Destroy the ship (removes from squadron, fleet, all indexes)
    state.destroyShip(shipId)

    # Emit salvage event
    events.add(
      event.GameEvent(
        eventType: event.GameEventType.Economy,
        turn: state.turn,
        houseId: some(houseId),
        description:
          "Auto-salvaged " & $shipClass & " (crippled 2+ turns): +" & $salvageValue &
          " PP",
        details: some("ShipSalvage"),
      )
    )

## Income Phase Step 3: Maintenance Upkeep Deduction (ec4x_canonical_turn_cycle.md:156-160)

proc calculateAndDeductMaintenanceUpkeep*(
    state: var GameState, events: var seq[event.GameEvent]
): Table[HouseId, int32] =
  ## Calculate and deduct maintenance upkeep costs from house treasuries
  ## This implements Income Phase Step 3 (after Conflict Phase, before resource collection)
  ##
  ## Per canonical turn cycle (ec4x_canonical_turn_cycle.md lines 156-160):
  ## - Calculate maintenance for surviving ships/facilities
  ## - Handle maintenance shortfall cascade
  ## - Deduct from treasuries
  ## - Generate MaintenancePaid events
  ##
  ## Returns: Table[HouseId, int32] of total maintenance costs per house (for reporting)

  result = initTable[HouseId, int32]()

  # STEP 1: Increment shortfall counters for all maintenance-crippled assets
  # Assets remain crippled and counter increments each turn until salvaged
  # Track at house level using maintenance shortfall tables
  for (houseId, house) in state.activeHousesWithId():
    var updatedHouse = house

    # Increment counters for all assets in house maintenance shortfall tables
    for shipId in updatedHouse.maintenanceShortfallShips.keys:
      updatedHouse.maintenanceShortfallShips[shipId] += 1

    for neoriaId in updatedHouse.maintenanceShortfallNeorias.keys:
      updatedHouse.maintenanceShortfallNeorias[neoriaId] += 1

    for kastraId in updatedHouse.maintenanceShortfallKastras.keys:
      updatedHouse.maintenanceShortfallKastras[kastraId] += 1

    for groundUnitId in updatedHouse.maintenanceShortfallGroundUnits.keys:
      updatedHouse.maintenanceShortfallGroundUnits[groundUnitId] += 1

    # Update house with incremented counters
    state.updateHouse(houseId, updatedHouse)

  # STEP 2: Process auto-salvage for ships crippled 2+ turns
  # This runs BEFORE maintenance calculation so salvaged ships don't incur costs
  # Individual salvage events are emitted by processCrippledShipSalvage
  discard processCrippledShipSalvage(state, events)

  # STEP 3: Calculate upkeep and handle shortfalls for all houses
  for (houseId, house) in state.activeHousesWithId():
    var totalUpkeep: int32 = 0

    # Fleet maintenance (surviving ships after Conflict Phase)
    for fleet in state.fleetsOwned(houseId):
      # Calculate maintenance for this fleet using entity managers
      var fleetData: seq[(ShipClass, CombatState)] = @[]

      # Iterate over ship IDs directly (squadrons removed)
      for shipId in fleet.ships:
        let shipOpt = state.ship(shipId)
        if shipOpt.isSome:
          let ship = shipOpt.get()
          fleetData.add((ship.shipClass, ship.state))

      totalUpkeep += calculateFleetMaintenance(fleetData)

    # Colony maintenance (facilities, ground forces)
    for colony in state.coloniesOwned(houseId):
      totalUpkeep += calculateColonyUpkeep(state, colony)

    result[houseId] = totalUpkeep

    # CHECK FOR SHORTFALL BEFORE DEDUCTION (economy.md:3.9.1)
    if house.treasury < totalUpkeep:
      # Graduated maintenance shortfall cascade with proportional credit
      let shortfall = totalUpkeep - house.treasury
      let paymentRatio =
        if totalUpkeep > 0:
          float32(house.treasury) / float32(totalUpkeep)
        else:
          0.0
      var shipsCrippledCount: int32 = 0
      var shipsRestoredCount: int32 = 0
      var maintenanceCovered: int32 = 0

      # PARTIAL PAYMENT CREDIT: Proportionally remove ships from shortfall tracking
      # Collect all maintenance-crippled ships from house table
      var maintenanceCrippledShips: seq[(ShipId, int32)] = @[]
      for shipId, shortfallTurns in house.maintenanceShortfallShips.pairs:
        maintenanceCrippledShips.add((shipId, shortfallTurns))

      # Sort by shortfallTurns ascending (prioritize recently-crippled ships)
      maintenanceCrippledShips.sort(
        proc(a, b: (ShipId, int32)): int =
          cmp(a[1], b[1])
      )

      # Remove from shortfall tracking for ships covered by partial payment
      let shipsToRestore = int(float32(maintenanceCrippledShips.len) * paymentRatio)

      # Update house to remove restored ships from tracking
      let houseOpt = state.house(houseId)
      if houseOpt.isSome:
        var updatedHouse = houseOpt.get()
        for i in 0 ..< shipsToRestore:
          let shipId = maintenanceCrippledShips[i][0]
          updatedHouse.maintenanceShortfallShips.del(shipId)
          shipsRestoredCount += 1
        state.updateHouse(houseId, updatedHouse)

      # Collect all active (non-crippled) ships owned by house
      var activeShips: seq[(ShipId, ShipClass, int32)] = @[]
      for fleet in state.fleetsOwned(houseId):
        # Iterate over ship IDs directly (squadrons removed)
        for shipId in fleet.ships:
          let shipOpt = state.ship(shipId)
          if shipOpt.isSome:
            let ship = shipOpt.get()
            if ship.state != CombatState.Crippled:
              let maintenanceCost =
                getShipMaintenanceCost(ship.shipClass, CombatState.Undamaged, fleet.status)
              activeShips.add((ship.id, ship.shipClass, maintenanceCost))

      # Sort by ShipId (oldest first - lower IDs = older ships)
      activeShips.sort(
        proc(a, b: (ShipId, ShipClass, int32)): int =
          cmp(a[0].int, b[0].int)
      )

      # Cripple ships until cumulative maintenance >= shortfall
      # Update house to add ships to maintenance shortfall tracking
      let houseOptForCrippling = state.house(houseId)
      if houseOptForCrippling.isSome:
        var updatedHouseForCrippling = houseOptForCrippling.get()

        for (shipId, shipClass, maintenanceCost) in activeShips:
          if maintenanceCovered >= shortfall:
            break

          # Cripple the ship due to maintenance shortfall
          let shipOpt = state.ship(shipId)
          if shipOpt.isSome:
            var ship = shipOpt.get()
            ship.state = CombatState.Crippled
            state.updateShip(shipId, ship)

            # Add to house maintenance shortfall tracking (first turn = 1)
            updatedHouseForCrippling.maintenanceShortfallShips[shipId] = 1

            shipsCrippledCount += 1
            maintenanceCovered += maintenanceCost

        state.updateHouse(houseId, updatedHouseForCrippling)

      # PRIORITIZED DEGRADATION: If shortfall still not covered, cripple facilities
      var facilitiesCrippledCount: int32 = 0
      if maintenanceCovered < shortfall:
        # Collect operational facilities (Neorias and Kastras)
        var activeFacilities: seq[(NeoriaId, int32)] = @[]  # NeoriaId with upkeep cost
        var activeKastras: seq[(KastraId, int32)] = @[]  # KastraId with upkeep cost

        for colony in state.coloniesOwned(houseId):
          # Collect operational Neorias (Spaceports, Shipyards, Drydocks)
          for neoriaId in colony.neoriaIds:
            let neoriaOpt = state.neoria(neoriaId)
            if neoriaOpt.isSome:
              let neoria = neoriaOpt.get()
              if neoria.state != CombatState.Crippled:
                let upkeepCost = case neoria.neoriaClass
                  of NeoriaClass.Spaceport: getSpaceportUpkeep()
                  of NeoriaClass.Shipyard: getShipyardUpkeep()
                  of NeoriaClass.Drydock: getDrydockUpkeep()
                activeFacilities.add((neoriaId, upkeepCost))

          # Collect operational Kastras (Starbases)
          for kastraId in colony.kastraIds:
            let kastraOpt = state.kastra(kastraId)
            if kastraOpt.isSome:
              let kastra = kastraOpt.get()
              if kastra.state != CombatState.Crippled:
                activeKastras.add((kastraId, getStarbaseUpkeep()))

        # Cripple facilities until maintenance covered
        let houseOptForFacilities = state.house(houseId)
        if houseOptForFacilities.isSome:
          var updatedHouseForFacilities = houseOptForFacilities.get()

          # Cripple Neorias first
          for (neoriaId, upkeepCost) in activeFacilities:
            if maintenanceCovered >= shortfall:
              break

            let neoriaOpt = state.neoria(neoriaId)
            if neoriaOpt.isSome:
              var neoria = neoriaOpt.get()
              neoria.state = CombatState.Crippled
              state.updateNeoria(neoriaId, neoria)

              # Add to house maintenance shortfall tracking
              updatedHouseForFacilities.maintenanceShortfallNeorias[neoriaId] = 1

              facilitiesCrippledCount += 1
              maintenanceCovered += upkeepCost

          # Then cripple Kastras if needed
          for (kastraId, upkeepCost) in activeKastras:
            if maintenanceCovered >= shortfall:
              break

            let kastraOpt = state.kastra(kastraId)
            if kastraOpt.isSome:
              var kastra = kastraOpt.get()
              kastra.state = CombatState.Crippled
              state.updateKastra(kastraId, kastra)

              # Add to house maintenance shortfall tracking
              updatedHouseForFacilities.maintenanceShortfallKastras[kastraId] = 1

              facilitiesCrippledCount += 1
              maintenanceCovered += upkeepCost

          state.updateHouse(houseId, updatedHouseForFacilities)

      # PRIORITIZED DEGRADATION: If shortfall STILL not covered, cripple ground units
      var groundUnitsCrippledCount: int32 = 0
      if maintenanceCovered < shortfall:
        # Collect operational ground units
        var activeGroundUnits: seq[(GroundUnitId, int32)] = @[]

        for colony in state.coloniesOwned(houseId):
          for groundUnitId in colony.groundUnitIds:
            let unitOpt = state.groundUnit(groundUnitId)
            if unitOpt.isSome:
              let unit = unitOpt.get()
              if unit.state != CombatState.Crippled:
                let upkeepCost = case unit.stats.unitType
                  of GroundClass.Army: getArmyUpkeep()
                  of GroundClass.Marine: getMarineUpkeep()
                  of GroundClass.GroundBattery: getGroundBatteryUpkeep()
                  of GroundClass.PlanetaryShield: getPlanetaryShieldUpkeep()
                activeGroundUnits.add((groundUnitId, upkeepCost))

        # Cripple ground units until maintenance covered
        let houseOptForGroundUnits = state.house(houseId)
        if houseOptForGroundUnits.isSome:
          var updatedHouseForGroundUnits = houseOptForGroundUnits.get()

          for (groundUnitId, upkeepCost) in activeGroundUnits:
            if maintenanceCovered >= shortfall:
              break

            let unitOpt = state.groundUnit(groundUnitId)
            if unitOpt.isSome:
              var unit = unitOpt.get()
              unit.state = CombatState.Crippled
              state.updateGroundUnit(groundUnitId, unit)

              # Add to house maintenance shortfall tracking
              updatedHouseForGroundUnits.maintenanceShortfallGroundUnits[groundUnitId] = 1

              groundUnitsCrippledCount += 1
              maintenanceCovered += upkeepCost

          state.updateHouse(houseId, updatedHouseForGroundUnits)

      # Apply infrastructure damage to colonies (economic disruption)
      for colony in state.coloniesOwned(houseId):
        var updatedColony = colony
        applyMaintenanceShortfall(updatedColony, shortfall)
        state.updateColony(colony.id, updatedColony)

      # Update house: increment shortfall counter, zero treasury, apply prestige penalty
      let houseOptForShortfall = state.house(houseId)
      if houseOptForShortfall.isSome:
        var updatedHouse = houseOptForShortfall.get()
        updatedHouse.consecutiveShortfallTurns += 1
        updatedHouse.treasury = 0  # Zero treasury after shortfall
        
        # Apply escalating prestige penalty per INC6c
        # Base: -5 prestige (turn 1), Escalates: -2 per consecutive turn (-5, -7, -9, -11, ...)
        let basePenalty = gameConfig.prestige.penalties.maintenanceShortfallBase  # int32: -5
        let escalation = gameConfig.prestige.penalties.maintenanceShortfallIncrement  # int32: -2
        let prestigePenalty: int32 = basePenalty + (escalation * int32(updatedHouse.consecutiveShortfallTurns - 1))
        updatedHouse.prestige += prestigePenalty  # prestigePenalty is negative
        
        state.updateHouse(houseId, updatedHouse)
        
        # Generate prestige penalty event
        events.add(
          event.GameEvent(
            eventType: event.GameEventType.PrestigeLost,
            turn: state.turn,
            houseId: some(houseId),
            description: "Maintenance shortfall prestige penalty: " & $prestigePenalty & " (turn " & $updatedHouse.consecutiveShortfallTurns & " of shortfall)",
            changeAmount: some(int(prestigePenalty)),
            details: some("MaintenanceShortfallPrestige"),
          )
        )

      # Emit detailed shortfall event
      let paymentPct = int(paymentRatio * 100.0)
      var description = "Maintenance shortfall: " & $shortfall & " PP (" & $paymentPct &
        "% paid, treasury zeroed, " & $shipsRestoredCount & " ships stabilized, " &
        $shipsCrippledCount & " ships crippled"

      if facilitiesCrippledCount > 0:
        description &= ", " & $facilitiesCrippledCount & " facilities crippled"
      if groundUnitsCrippledCount > 0:
        description &= ", " & $groundUnitsCrippledCount & " ground units crippled"

      description &= ", infrastructure damaged)"
      events.add(
        event.GameEvent(
          eventType: event.GameEventType.Economy,
          turn: state.turn,
          houseId: some(houseId),
          description: description,
          details: some("MaintenanceShortfall"),
        )
      )
    else:
      # Full payment - reset shortfall counters for both house and ships
      let houseOpt = state.house(houseId)
      if houseOpt.isSome:
        var updatedHouse = houseOpt.get()
        updatedHouse.consecutiveShortfallTurns = 0
        updatedHouse.treasury -= totalUpkeep
        state.updateHouse(houseId, updatedHouse)

      # Clear maintenance shortfall tracking for all assets
      # Full payment prevents salvage, but assets stay crippled until repaired
      let houseOptForPayment = state.house(houseId)
      if houseOptForPayment.isSome:
        var updatedHouseForPayment = houseOptForPayment.get()
        # Clear all maintenance shortfall tables
        updatedHouseForPayment.maintenanceShortfallShips.clear()
        updatedHouseForPayment.maintenanceShortfallNeorias.clear()
        updatedHouseForPayment.maintenanceShortfallKastras.clear()
        updatedHouseForPayment.maintenanceShortfallGroundUnits.clear()
        state.updateHouse(houseId, updatedHouseForPayment)

      # Emit maintenance paid event
      events.add(
        event.GameEvent(
          eventType: event.GameEventType.Economy,
          turn: state.turn,
          houseId: some(houseId),
          description: "Maintenance upkeep paid: " & $totalUpkeep & " PP",
          details: some("MaintenanceUpkeep"),
        )
      )
