## Eparch Collector - Economy & Infrastructure Domain
##
## Tracks core economy (treasury, production, IU, PU), economic health,
## population management, blockades, colony counts, and construction pipelines.
##
## REFACTORED: 2025-12-06 - Extracted from diagnostics.nim
## (lines 373-404, 476-550 from collectEconomyMetrics + 890-933 from collectDefenseMetrics)

import std/[tables, options]
import ./types
import ../../../engine/[gamestate, fleet]
import ../../../engine/economy/types as econ_types
import ../../../common/types/core

proc collectEparchMetrics*(state: GameState, houseId: HouseId,
                           prevMetrics: DiagnosticMetrics,
                           report: TurnResolutionReport): DiagnosticMetrics =
  ## Collect economy & infrastructure metrics
  result = initDiagnosticMetrics(state.turn, houseId)

  let house = state.houses.getOrDefault(houseId)

  # ================================================================
  # CORE ECONOMY
  # ================================================================

  result.treasuryBalance = house.treasury

  # Calculate comprehensive economic metrics from colonies
  var totalProduction = 0
  var totalPU = 0
  var totalPTU = 0
  var totalIU = 0
  var grossColonyOutput = 0

  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      totalProduction += colony.production
      totalPU += colony.populationUnits  # Actual PU (economic units)
      totalPTU += colony.populationTransferUnits  # Actual PTU
      totalIU += colony.infrastructure  # Infrastructure units
      # GCO = colony output before tax (use production as proxy)
      grossColonyOutput += colony.production

  result.productionPerTurn = totalProduction
  result.totalPopulationUnits = totalPU
  result.totalPopulationPTU = totalPTU
  result.totalIndustrialUnits = totalIU
  result.grossColonyOutput = grossColonyOutput

  # Tax rate and NHV
  result.taxRate = house.taxPolicy.currentRate
  result.netHouseValue =
    (grossColonyOutput * house.taxPolicy.currentRate) div 100

  # Population growth rate (actual from config with map scaling)
  # Base rate (5%) × tax multiplier × map multiplier
  # Simplified: report base config rate in basis points
  result.populationGrowthRate = 500  # 5.00% base rate in basis points

  # ================================================================
  # ECONOMIC HEALTH
  # ================================================================

  # Calculate PU growth (change from last turn)
  result.puGrowth = totalProduction - prevMetrics.productionPerTurn

  # Track zero-spend turns
  if house.treasury == prevMetrics.treasuryBalance:
    result.zeroSpendTurns = prevMetrics.zeroSpendTurns + 1
  else:
    result.zeroSpendTurns = prevMetrics.zeroSpendTurns

  # Economic Health indicators
  result.treasuryDeficit = report.treasuryDeficit
  result.maintenanceCostDeficit = report.maintenanceCostDeficit

  # Track infrastructure damage from bombardment/sabotage
  result.infrastructureDamageTotal = prevMetrics.infrastructureDamageTotal + report.infrastructureDamage

  # Track salvage value recovered from ship destruction
  result.salvageValueRecovered = prevMetrics.salvageValueRecovered + report.salvageValueRecovered

  # Tax rate analysis (6-turn rolling average)
  # TODO: Calculate true 6-turn average from history
  result.avgTaxRate6Turn = house.taxPolicy.currentRate
  result.taxPenaltyActive = house.taxPolicy.currentRate > 50  # Simplified

  # ================================================================
  # POPULATION & COLONY MANAGEMENT
  # ================================================================

  # Blockade tracking
  var blockadedCount = 0
  var blockadeTurns = 0
  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      if colony.blockaded:
        blockadedCount += 1
        blockadeTurns += colony.blockadeTurns
  result.coloniesBlockadedCount = blockadedCount
  result.blockadeTurnsCumulative = blockadeTurns

  # Population transfers (from Space Guild transfers)
  var thisHouseTransfers = 0
  for transfer in state.populationInTransit:
    if transfer.id == houseId:
      thisHouseTransfers += 1
  result.populationTransfersActive = thisHouseTransfers

  # Track from turn resolution
  result.populationTransfersCompleted = report.popTransfersCompleted
  result.populationTransfersLost = report.popTransfersLost
  result.ptuTransferredTotal = prevMetrics.ptuTransferredTotal + report.ptuTransferredTotal

  # ================================================================
  # COLONY COUNTS
  # ================================================================

  # Count colonies with and without ground defense
  # Undefended = NO ground units (armies, marines, or batteries)
  # This matches prestige penalty definition
  var undefendedColonies = 0
  var totalColonies = 0

  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      totalColonies += 1

      # Check if colony has ground defense
      # NOTE: Planetary shields don't count (passive only)
      # NOTE: Starbases and fleets are orbital defense, not ground defense
      let hasGroundDefense = (colony.armies > 0 or
                               colony.marines > 0 or
                               colony.groundBatteries > 0)

      if not hasGroundDefense:
        undefendedColonies += 1

  result.coloniesWithoutDefense = undefendedColonies
  result.totalColonies = totalColonies

  # ================================================================
  # FLEET LIFECYCLE MANAGEMENT
  # ================================================================

  # Track mothballed and reserve fleets
  var mothballedCount = 0
  var reserveCount = 0
  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      case fleet.status
      of FleetStatus.Mothballed:
        mothballedCount += 1
      of FleetStatus.Reserve:
        reserveCount += 1
      of FleetStatus.Active:
        discard

  # Combined lifecycle management count
  result.mothballedFleetsTotal = mothballedCount + reserveCount

  # mothballedFleetsUsed tracks reactivations (cumulative, tracked elsewhere)
  result.mothballedFleetsUsed = 0

  # ================================================================
  # CONSTRUCTION PIPELINES
  # ================================================================

  # Build Queue tracking
  var totalBuildQueueDepth = 0
  var etacInConstruction = 0
  var shipsUnderConstruction = 0
  var buildingsUnderConstruction = 0

  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      if colony.underConstruction.isSome():
        totalBuildQueueDepth += 1
      totalBuildQueueDepth += colony.constructionQueue.len

      if colony.underConstruction.isSome:
        let project = colony.underConstruction.get()
        if project.projectType == econ_types.ConstructionType.Ship:
          shipsUnderConstruction += 1
          if project.itemId == "ETAC":
            etacInConstruction += 1
        else:
          buildingsUnderConstruction += 1
      
      for project in colony.constructionQueue:
        if project.projectType == econ_types.ConstructionType.Ship:
          shipsUnderConstruction += 1
          if project.itemId == "ETAC":
            etacInConstruction += 1
        else:
          buildingsUnderConstruction += 1
  
  result.totalBuildQueueDepth = totalBuildQueueDepth
  result.etacInConstruction = etacInConstruction
  result.shipsUnderConstruction = shipsUnderConstruction
  result.buildingsUnderConstruction = buildingsUnderConstruction

  # Commissioning tracking
  result.shipsCommissionedThisTurn = report.shipsCommissioned
  result.etacCommissionedThisTurn = report.etacsCommissioned
  result.squadronsCommissionedThisTurn = report.squadronsCommissioned

  # Orders tracking (set by orchestrator when processing OrderPackets)
  result.fleetOrdersSubmitted = 0
  result.buildOrdersSubmitted = 0
  result.colonizeOrdersSubmitted = 0
  result.totalOrders = 0
  result.invalidOrders = 0
