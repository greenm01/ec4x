## @engine/telemetry/collectors/capacity.nim
##
## Collect capacity violation metrics from GameState.
## Covers: squadron limits, fighter capacity, grace periods.

import std/[math, options]
import ../../types/[
  telemetry, core, game_state, colony, squadron, house, capacity
]
import ../../config/military_config
import ../../state/[iterators, entity_manager]

proc collectCapacityMetrics*(
  state: GameState,
  houseId: HouseId,
  prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  ## Collect capacity metrics from GameState
  result = prevMetrics  # Start with previous metrics

  let houseOpt = state.houses.entities.getEntity(houseId)
  if houseOpt.isNone:
    return result  # House not found
  let house = houseOpt.get()

  # ================================================================
  # FIGHTER CAPACITY
  # ================================================================

  # Fighter Doctrine multiplier (FD tech level)
  let fdMultiplier: float32 = case house.techTree.levels.fighterDoctrine
    of 1: 1.0
    of 2: 1.5
    of 3: 2.0
    else: 1.0

  # Calculate fighter capacity and violations
  let fighterIUDivisor: int32 =
    int32(globalMilitaryConfig.fighter_mechanics.fighter_capacity_iu_divisor)
  var totalFighterCapacity: int32 = 0
  var totalFighters: int32 = 0
  var capacityViolationCount: int32 = 0

  for colony in state.coloniesOwned(houseId):
    let colonyCapacity = int32(
      floor(float32(colony.industrial.units) / float32(fighterIUDivisor)) *
      fdMultiplier
    )
    totalFighterCapacity += colonyCapacity
    totalFighters += colony.fighterSquadronIds.len.int32
    if colony.capacityViolation.severity != ViolationSeverity.None:
      capacityViolationCount += 1

  result.fighterCapacityMax = totalFighterCapacity
  result.fighterCapacityUsed = totalFighters
  result.fighterCapacityViolation = totalFighters > totalFighterCapacity
  result.capacityViolationsActive = capacityViolationCount

  # ================================================================
  # SQUADRON LIMIT
  # ================================================================

  var totalIU: int32 = 0
  for colony in state.coloniesOwned(houseId):
      totalIU += colony.industrial.units

  let squadronIUDivisor: int32 =
    int32(globalMilitaryConfig.squadron_limits.squadron_limit_iu_divisor)
  let squadronMinimum: int32 =
    int32(globalMilitaryConfig.squadron_limits.squadron_limit_minimum)
  result.squadronLimitMax = max(squadronMinimum,
                                 (totalIU div squadronIUDivisor) * 2)

  # Count actual capital squadrons
  var capitalSquadrons: int32 = 0
  for squadron in state.squadronsOwned(houseId):
    if not squadron.destroyed:
      # TODO: Use isCapitalShip() helper when available
      if squadron.flagship.shipClass in {
        ShipClass.Cruiser, ShipClass.LightCruiser, ShipClass.HeavyCruiser,
        ShipClass.Battlecruiser, ShipClass.Battleship,
        ShipClass.Dreadnought, ShipClass.SuperDreadnought,
        ShipClass.Carrier, ShipClass.SuperCarrier
      }:
        capitalSquadrons += 1

  result.squadronLimitUsed = capitalSquadrons
  result.squadronLimitViolation = capitalSquadrons > result.squadronLimitMax
