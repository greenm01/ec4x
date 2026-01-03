## @engine/telemetry/collectors/capacity.nim
##
## Collect capacity violation metrics from GameState.
## Covers: squadron limits, fighter capacity, grace periods.

import std/[math, options]
import ../../types/[telemetry, core, game_state, colony, squadron, house, capacity, ship]
import ../../globals
import ../../state/[engine, iterators]

proc collectCapacityMetrics*(
    state: GameState, houseId: HouseId, prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  ## Collect capacity metrics from GameState
  result = prevMetrics # Start with previous metrics

  let houseOpt = state.house(houseId)
  if houseOpt.isNone:
    return result # House not found
  let house = houseOpt.get()

  # ================================================================
  # FIGHTER CAPACITY
  # ================================================================

  # Fighter Doctrine multiplier (FD tech level)
  let fdMultiplier: float32 =
    case house.techTree.levels.fd
    of 1: 1.0
    of 2: 1.5
    of 3: 2.0
    else: 1.0

  # Calculate fighter capacity and violations
  let fighterIUDivisor: int32 = gameConfig.limits.fighterCapacity.iuDivisor
  var totalFighterCapacity: int32 = 0
  var totalFighters: int32 = 0
  var capacityViolationCount: int32 = 0

  for colony in state.coloniesOwned(houseId):
    let colonyCapacity = int32(
      floor(float32(colony.industrial.units) / float32(fighterIUDivisor)) * fdMultiplier
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

  # Capital squadron limit formula: max(8, floor(Total_House_IU ÷ 100) × 2)
  # Per docs/specs/10-reference.md Table 10.5
  const squadronIUDivisor: int32 = 100
  const squadronMinimum: int32 = 8
  result.squadronLimitMax = max(squadronMinimum, (totalIU div squadronIUDivisor) * 2)

  # Count actual capital squadrons
  var capitalSquadrons: int32 = 0
  for squadron in state.squadronsOwned(houseId):
    if not squadron.destroyed:
      # Lookup flagship ship to check if it's a capital ship
      let flagshipOpt = state.ship(squadron.flagshipId)
      if flagshipOpt.isSome:
        let flagship = flagshipOpt.get()
        # TODO: Use isCapitalShip() helper when available
        if flagship.shipClass in [
          ShipClass.LightCruiser, ShipClass.Cruiser,
          ShipClass.Battlecruiser, ShipClass.Battleship, ShipClass.Dreadnought,
          ShipClass.SuperDreadnought, ShipClass.Carrier, ShipClass.SuperCarrier,
        ]:
          capitalSquadrons += 1

  result.squadronLimitUsed = capitalSquadrons
  result.squadronLimitViolation = capitalSquadrons > result.squadronLimitMax
