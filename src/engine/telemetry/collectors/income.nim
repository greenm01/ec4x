## @engine/telemetry/collectors/income.nim
##
## Collect economic income metrics from GameState.
## Covers: treasury, tax income, maintenance costs, deficits.

import std/[options]
import ../../types/[telemetry, core, game_state, event, house, colony]
import ../../state/[entity_manager, iterators]

proc collectIncomeMetrics*(
    state: GameState, houseId: HouseId, prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  ## Collect income metrics from GameState
  result = prevMetrics # Start with previous metrics

  let houseOpt = state.houses.entities.getEntity(houseId)
  if houseOpt.isNone:
    return result
  let house = houseOpt.get()

  # Core economy
  result.treasuryBalance = house.treasury

  # Calculate comprehensive economic metrics from colonies
  var totalProduction: int32 = 0
  var totalIU: int32 = 0
  var grossColonyOutput: int32 = 0

  for colony in state.coloniesOwned(houseId):
    totalProduction += colony.production
    totalIU += colony.infrastructure
    grossColonyOutput += colony.grossOutput

  result.productionPerTurn = totalProduction
  result.totalIndustrialUnits = totalIU
  result.grossColonyOutput = grossColonyOutput

  # Tax rate and NHV
  result.taxRate = house.taxPolicy.currentRate
  result.netHouseValue = (grossColonyOutput * result.taxRate) div 100

  # Economic Health
  result.puGrowth = totalProduction - prevMetrics.productionPerTurn

  # Track zero-spend turns
  if result.treasuryBalance == prevMetrics.treasuryBalance:
    result.zeroSpendTurns = prevMetrics.zeroSpendTurns + 1
  else:
    result.zeroSpendTurns = 0

  # TODO: Track deficits from events
  result.treasuryDeficit = false
  result.maintenanceCostDeficit = 0

  # Track infrastructure damage and salvage from events
  var infrastructureDamage: int32 = 0
  var salvageValueRecovered: int32 = 0

  for event in state.lastTurnEvents:
    if event.houseId != some(houseId):
      continue
    # TODO: Add InfrastructureDamage, SalvageRecovered events
    # case event.eventType:
    # of InfrastructureDamage:
    #   infrastructureDamage += extractAmount(event)
    # of SalvageRecovered:
    #   salvageValueRecovered += extractAmount(event)
    # else:
    #   discard

  result.infrastructureDamageTotal =
    prevMetrics.infrastructureDamageTotal + infrastructureDamage
  result.salvageValueRecovered =
    prevMetrics.salvageValueRecovered + salvageValueRecovered

  # Tax rate analysis
  result.avgTaxRate6Turn = result.taxRate # TODO: Calculate 6-turn average
  result.taxPenaltyActive = result.taxRate > 50
