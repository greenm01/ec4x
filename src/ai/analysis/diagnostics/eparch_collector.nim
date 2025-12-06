## Eparch Collector - Economy & Infrastructure Domain
##
## Tracks core economy (treasury, production, IU, PU), economic health,
## population management, blockades, colony counts, and construction pipelines.
##
## REFACTORED: 2025-12-06 - Extracted from diagnostics.nim
## (lines 373-404, 476-550 from collectEconomyMetrics + 890-933 from collectDefenseMetrics)

import std/tables
import ./types
import ../../../engine/[gamestate, fleet]
import ../../../common/types/core

proc collectEparchMetrics*(state: GameState, houseId: HouseId,
                           prevMetrics: DiagnosticMetrics): DiagnosticMetrics =
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
      totalPU += colony.population  # Population in millions (display field)
      totalPTU += colony.souls div 50000  # souls / 50k = PTU (approximation)
      totalIU += colony.industrial.units  # Actual IU count
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

  # Population growth rate (base 2.0% + tax modifiers from economy.md)
  # Simplified: just track base rate for now
  result.populationGrowthRate = 200  # 2.00% in basis points

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
  # TODO: Track actual maintenance cost from turn resolution
  result.treasuryDeficit = false  # Will be set by turn resolution
  result.maintenanceCostDeficit = 0

  # TODO: Track infrastructure damage from bombardment/sabotage
  result.infrastructureDamageTotal = 0

  # TODO: Track salvage value recovered from ship destruction
  result.salvageValueRecovered = 0

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
  # Total transfers in transit (not filtered by house)
  result.populationTransfersActive = state.populationInTransit.len

  # TODO: Filter to only this house's transfers
  # TODO: Track from turn resolution
  result.populationTransfersCompleted = 0
  result.populationTransfersLost = 0
  result.ptuTransferredTotal = 0

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
  # CONSTRUCTION PIPELINES (TODO - Not yet implemented)
  # ================================================================

  # Build Queue tracking
  result.totalBuildQueueDepth = 0
  result.etacInConstruction = 0
  result.shipsUnderConstruction = 0
  result.buildingsUnderConstruction = 0

  # Commissioning tracking
  result.shipsCommissionedThisTurn = 0
  result.etacCommissionedThisTurn = 0
  result.squadronsCommissionedThisTurn = 0

  # Orders tracking (set by orchestrator when processing OrderPackets)
  result.fleetOrdersSubmitted = 0
  result.buildOrdersSubmitted = 0
  result.colonizeOrdersSubmitted = 0
  result.totalOrders = 0
  result.invalidOrders = 0
