## Economy Engine - Income Phase Orchestration
##
## Main entry point for economy system
## Orchestrates income calculation, tax collection, population growth
##
## Per gameplay.md:1.3.2 - Income Phase runs AFTER Conflict Phase
## Infrastructure damage from combat affects production

import std/[tables, options]
import types, income, production, construction, maintenance
import ../../common/types/[core, units]
import ../gamestate  # For unified Colony type

export types.IncomePhaseReport, types.HouseIncomeReport, types.ColonyIncomeReport
export types.MaintenanceReport, types.CompletedProject
# NOTE: Don't export gamestate.Colony to avoid ambiguity

## Income Phase Resolution (gameplay.md:1.3.2)

proc resolveIncomePhase*(colonies: var seq[Colony],
                        houseTaxPolicies: Table[HouseId, TaxPolicy],
                        houseTechLevels: Table[HouseId, int],
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
  ##   houseTreasuries: House treasuries (modified with income)
  ##   baseGrowthRate: Base population growth rate (loaded from config)
  ##
  ## Returns:
  ##   Complete income phase report

  result = IncomePhaseReport(
    turn: 0,  # TODO: Get from game state
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

    let treasury = if houseId in houseTreasuries:
      houseTreasuries[houseId]
    else:
      0

    # Calculate house income
    let houseReport = calculateHouseIncome(houseColonyList, elTech, taxPolicy, treasury)

    # Update treasury
    houseTreasuries[houseId] = houseReport.treasuryAfter

    # Apply population growth to colonies
    for i, colony in colonies.mpairs:
      if colony.owner == houseId:
        discard applyPopulationGrowth(colony, taxPolicy.currentRate, baseGrowthRate)
        # Note: Could update report with growth rates here

    # Store report
    result.houseReports[houseId] = houseReport

## Maintenance Phase Resolution (gameplay.md:1.3.4)

proc resolveMaintenancePhase*(colonies: var seq[Colony],
                             houseFleetData: Table[HouseId, seq[(ShipClass, bool)]],
                             houseTreasuries: var Table[HouseId, int]): MaintenanceReport =
  ## Resolve maintenance phase
  ##
  ## Steps:
  ## 1. Advance construction projects
  ## 2. Calculate fleet/building upkeep
  ## 3. Deduct from treasuries
  ## 4. Apply repairs (if treasury allows)
  ##
  ## Args:
  ##   colonies: All colonies (modified for construction)
  ##   houseFleetData: Fleet composition per house (ship class, is crippled)
  ##   houseTreasuries: House treasuries (modified for upkeep)

  result = MaintenanceReport(
    turn: 0,  # TODO: Get from game state
    completedProjects: @[],
    houseUpkeep: initTable[HouseId, int](),
    repairsApplied: @[]
  )

  # Calculate upkeep per house
  for houseId, fleetData in houseFleetData:
    let fleetUpkeep = calculateFleetMaintenance(fleetData)

    # TODO: Add building maintenance
    let totalUpkeep = fleetUpkeep

    result.houseUpkeep[houseId] = totalUpkeep

    # Deduct from treasury
    if houseId in houseTreasuries:
      houseTreasuries[houseId] -= totalUpkeep

      # Handle shortfall
      if houseTreasuries[houseId] < 0:
        let shortfall = -houseTreasuries[houseId]
        houseTreasuries[houseId] = 0

        # Apply shortfall consequences to random colony
        # TODO: Better shortfall distribution
        for colony in colonies.mitems:
          if colony.owner == houseId:
            applyMaintenanceShortfall(colony, shortfall)
            break

  # Advance construction (upfront payment model - no PP allocation needed)
  for colony in colonies.mitems:
    if colony.underConstruction.isSome:
      # Construction advances one turn per maintenance phase
      # Payment was already made upfront when construction started
      let completed = advanceConstruction(colony)
      if completed.isSome:
        result.completedProjects.add(completed.get())

  # TODO: Apply repairs from allocated PP

  return result
