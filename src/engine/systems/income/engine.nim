## Economy Engine - Income Phase Orchestration
##
## Main entry point for economy system
## Orchestrates income calculation, tax collection, population growth
##
## Per gameplay.md:1.3.2 - Income Phase runs AFTER Conflict Phase
## Infrastructure damage from combat affects production

import std/[tables, options]
import ./[income, maintenance]
import ../facilities/queue as facility_queue
import ../capacity/carrier_hangar  # For carrier hangar capacity enforcement
import ../../types/[game_state, core, units, event, income as income_types, colony, production]
import ../../state/[state_helpers, iterators]

export income_types.IncomePhaseReport, income_types.HouseIncomeReport
export colony.ColonyIncomeReport
export production.MaintenanceReport, production.CompletedProject
# NOTE: Don't export game_state.Colony to avoid ambiguity

## Income Phase Resolution (gameplay.md:1.3.2)

proc resolveIncomePhase*(colonies: var seq[Colony],
                        houseTaxPolicies: Table[HouseId, TaxPolicy],
                        houseTechLevels: Table[HouseId, int],
                        houseCSTTechLevels: Table[HouseId, int],
                        houseTreasuries: var Table[HouseId, int],
                        baseGrowthRate: float = 0.015): IncomePhaseReport =
  ## Resolve income phase for all houses
  ##
  ## Steps:
  ## 1. Calculate GCO for all colonies (after conflict damage)
  ## 2. Apply tax policy
  ## 3. Calculate prestige effects
  ## 4. Deposit to treasuries
  ## 5. Apply population growth
  ##
  ## Args:
  ##   colonies: All game colonies (modified for pop growth)
  ##   houseTaxPolicies: Tax policy per house
  ##   houseTechLevels: Economic Level tech per house
  ##   houseCSTTechLevels: Construction tech per house (affects capacity)
  ##   houseTreasuries: House treasuries (modified with income)
  ##   baseGrowthRate: Base population growth rate (loaded from config)
  ##
  ## Returns:
  ##   Complete income phase report

  result = IncomePhaseReport(
    turn: 0,  # NOTE: Legacy interface - turn tracking in GameState version
    houseReports: initTable[HouseId, HouseIncomeReport]()
  )

  # Group colonies by owner
  var houseColonies = initTable[HouseId, seq[Colony]]()
  for colony in colonies:
    if colony.owner notin houseColonies:
      houseColonies[colony.owner] = @[]
    houseColonies[colony.owner].add(colony)

  # Process each house
  for houseId, houseColonyList in houseColonies:
    # Get house parameters
    let taxPolicy = if houseId in houseTaxPolicies:
      houseTaxPolicies[houseId]
    else:
      TaxPolicy(currentRate: 50, history: @[50])  # Default

    let elTech = if houseId in houseTechLevels:
      houseTechLevels[houseId]
    else:
      1  # Default EL1

    let cstTech = if houseId in houseCSTTechLevels:
      houseCSTTechLevels[houseId]
    else:
      1  # Default CST1

    let treasury = if houseId in houseTreasuries:
      houseTreasuries[houseId]
    else:
      0

    # Calculate house income
    let houseReport = calculateHouseIncome(houseColonyList, elTech, cstTech, taxPolicy, treasury)

    # Update treasury
    houseTreasuries[houseId] = houseReport.treasuryAfter

    # Apply population and industrial growth to colonies
    for i, colony in colonies.mpairs:
      if colony.owner == houseId:
        discard applyPopulationGrowth(colony, taxPolicy.currentRate, baseGrowthRate)
        discard applyIndustrialGrowth(colony, taxPolicy.currentRate, baseGrowthRate)
        # Note: Could update report with growth rates here

    # Store report
    result.houseReports[houseId] = houseReport

## Income Phase Step 3: Maintenance Upkeep Deduction (ec4x_canonical_turn_cycle.md:156-160)

proc calculateAndDeductMaintenanceUpkeep*(
  state: var GameState,
  events: var seq[event.GameEvent]
): Table[HouseId, int] =
  ## Calculate and deduct maintenance upkeep costs from house treasuries
  ## This implements Income Phase Step 3 (after Conflict Phase, before resource collection)
  ##
  ## Per canonical turn cycle (ec4x_canonical_turn_cycle.md lines 156-160):
  ## - Calculate maintenance for surviving ships/facilities
  ## - Handle maintenance shortfall cascade
  ## - Deduct from treasuries
  ## - Generate MaintenancePaid events
  ##
  ## Returns: Table[HouseId, int] of total maintenance costs per house (for reporting)

  result = initTable[HouseId, int]()

  # Calculate upkeep and handle shortfalls for all houses
  for (houseId, house) in state.activeHousesWithId():
    var totalUpkeep = 0

    # Fleet maintenance (surviving ships after Conflict Phase)
    for fleet in state.fleetsOwned(houseId):
      # Calculate maintenance for this fleet using entity managers
      var fleetData: seq[(ShipClass, bool)] = @[]

      # Iterate over squadron IDs
      for squadronId in fleet.squadrons:
        if squadronId notin state.squadrons.entities.index:
          continue

        let squadronIdx = state.squadrons.entities.index[squadronId]
        let squadron = state.squadrons.entities.data[squadronIdx]

        # Add flagship
        if squadron.flagshipId in state.ships.entities.index:
          let flagshipIdx = state.ships.entities.index[squadron.flagshipId]
          let flagship = state.ships.entities.data[flagshipIdx]
          fleetData.add((flagship.shipClass, flagship.isCrippled))

        # Add escort ships
        for shipId in squadron.ships:
          if shipId notin state.ships.entities.index:
            continue
          let shipIdx = state.ships.entities.index[shipId]
          let ship = state.ships.entities.data[shipIdx]
          fleetData.add((ship.shipClass, ship.isCrippled))

      totalUpkeep += calculateFleetMaintenance(fleetData)

    # Colony maintenance (facilities, ground forces)
    for colony in state.coloniesOwned(houseId):
      totalUpkeep += calculateColonyUpkeep(colony)

    result[houseId] = totalUpkeep

    # CHECK FOR SHORTFALL BEFORE DEDUCTION (economy.md:3.11)
    if house.treasury < totalUpkeep:
      let shortfall = totalUpkeep - house.treasury

      # TODO: Execute maintenance shortfall cascade (not implemented yet)
      # let cascade = processShortfall(state, houseId, shortfall)
      # applyShortfallCascade(state, cascade, events)
      # Cascade should: zero treasury, add salvage, increment consecutiveShortfallTurns
      # Events should be emitted for fleet disbanding

      # Temporary: Just increment shortfall counter
      state.withHouse(houseId):
        house.consecutiveShortfallTurns += 1
    else:
      # Full payment - reset shortfall counter
      state.withHouse(houseId):
        house.consecutiveShortfallTurns = 0

    # Deduct maintenance (treasury may have salvage added by cascade)
    state.withHouse(houseId):
      house.treasury -= totalUpkeep

    # Generate MaintenancePaid event
    events.add(event.GameEvent(
      eventType: event.GameEventType.Economy,
      turn: state.turn,
      houseId: some(houseId),
      description: "Maintenance upkeep paid: " & $totalUpkeep & " PP",
      details: some("MaintenanceUpkeep")
    ))

proc tickConstructionAndRepair*(
  state: var GameState,
  events: var seq[event.GameEvent]
): MaintenanceReport =
  ## Advance construction and repair queues
  ## This is called during Maintenance Phase (Phase 4)
  ##
  ## NOTE: This does NOT calculate or deduct maintenance costs!
  ## Maintenance upkeep is handled in Income Phase Step 3 via
  ## calculateAndDeductMaintenanceUpkeep()

  result = MaintenanceReport(
    turn: state.turn,
    completedProjects: @[],
    houseUpkeep: initTable[HouseId, int](),  # Empty - maintenance handled in Income Phase
    repairsApplied: @[]
  )

  # Advance construction projects
  # TWO SYSTEMS:
  # 1. Facility queues: Capital ships + repairs (per-facility dock capacity)
  # 2. Colony queue: Fighters, buildings, ground units, IU investment (planet-side)

  for systemId, colony in state.colonies.entities.data.mpairs:
    # Advance facility queues (capital ships in spaceports/shipyards + repairs in shipyards)
    let facilityResults = facility_queue.advanceColonyQueues(colony)
    result.completedProjects.add(facilityResults.completedProjects)
    # Note: completed repairs handled separately (not in completedProjects)

    # Advance colony queue (legacy system for fighters, buildings, ground units, IU)
    if colony.underConstruction.isSome:
      let completed = advanceConstruction(colony)
      if completed.isSome:
        result.completedProjects.add(completed.get())
      # Colony is already mutated in place via mpairs

  # Infrastructure repairs handled by repair_queue.nim during Construction Phase
  # Damaged infrastructure tracked in colony.infrastructureDamage
  # Repairs applied via PP allocation in construction system

  # Check carrier hangar capacity (should find no violations - blocked at load time)
  discard carrier_hangar.processCapacityEnforcement(state)

  return result
