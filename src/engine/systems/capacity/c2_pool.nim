## C2 Command Pool Capacity & Logistical Strain System
##
## Implements assets.md:2.3.3.3-2.3.3.4 - C2 Pool soft cap and logistical strain penalty.
##
## C2 Pool Formula: (Total House IU × 0.3) + SC Tech Bonus
##
## Where Strategic Command (SC) Tech Level Bonus is (from config/tech.kdl):
## - SC I: +50
## - SC II: +65
## - SC III: +80
## - SC IV: +95
## - SC V: +110
## - SC VI: +125
##
## Logistical Strain Formula: max(0, Total Fleet CC - C2 Pool) × 0.5 PP per turn
##
## **Fleet Status Modifiers:**
## - Active: 100% CC (full command cost)
## - Reserve: 50% CC (reduced readiness)
## - Mothballed: 0% CC (no active command)
##
## Data-oriented design: Calculate capacity (pure), apply strain cost (explicit mutations)

import std/[options, math, tables]
import
  ../../types/[core, game_state, house, fleet, ship, event, capacity]
import ../../state/[engine, iterators]
import ../../globals
import ../../../common/logger

export capacity.C2PoolAnalysis

## Pure Calculation Functions

proc scTechC2Bonus(scLevel: int32): int32 =
  ## Get Strategic Command tech C2 Pool bonus per assets.md:2.3.3.3
  ## Reads from gameConfig.tech.sc.levels
  let cfg = gameConfig.tech.sc
  if cfg.levels.hasKey(scLevel):
    return cfg.levels[scLevel].c2Bonus
  else:
    return 0'i32 # No SC tech = no bonus

proc calculateC2Pool*(totalHouseIU: int32, scLevel: int32): int32 =
  ## Pure calculation of C2 Pool capacity
  ## Formula: C2 Pool = (Total House IU × c2ConversionRatio) + SC Tech Bonus
  ## Per assets.md:2.3.3.3 and config/limits.kdl c2ConversionRatio
  let ratio = gameConfig.limits.c2Limits.c2ConversionRatio
  let iuContribution = float32(totalHouseIU) * ratio
  let scBonus = scTechC2Bonus(scLevel)
  return int32(floor(iuContribution)) + scBonus

proc fleetStatusCCModifier(status: FleetStatus): float32 =
  ## Get CC multiplier for fleet status per assets.md:2.3.3.5
  ## Active: 100%, Reserve: 50%, Mothballed: 0%
  case status
  of FleetStatus.Active:
    return 1.0'f32
  of FleetStatus.Reserve:
    return 0.5'f32
  of FleetStatus.Mothballed:
    return 0.0'f32

proc calculateShipCC(
    state: GameState, shipId: ShipId, fleetStatus: FleetStatus
): int32 =
  ## Calculate effective CC for a single ship with fleet status modifier
  let shipOpt = state.ship(shipId)
  if shipOpt.isNone:
    return 0'i32

  let ship = shipOpt.get()

  # Get ship's base CC from config
  let shipStats = gameConfig.ships.ships[ship.shipClass]
  let baseCC = shipStats.commandCost

  # Apply fleet status modifier
  let modifier = fleetStatusCCModifier(fleetStatus)
  return int32(floor(float32(baseCC) * modifier))

proc calculateFleetCC(state: GameState, fleetId: FleetId): int32 =
  ## Calculate total CC for all ships in fleet with status modifiers
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return 0'i32

  let fleet = fleetOpt.get()
  var totalCC = 0'i32

  # Sum CC from all ships in fleet
  for shipId in fleet.ships:
    totalCC += calculateShipCC(state, shipId, fleet.status)

  return totalCC

proc calculateTotalFleetCC*(state: GameState, houseId: HouseId): int32 =
  ## Calculate total CC across all fleets owned by house
  ## Includes fleet status modifiers (Active/Reserve/Mothballed)
  var totalCC = 0'i32

  for fleet in state.fleetsOwned(houseId):
    totalCC += calculateFleetCC(state, fleet.id)

  return totalCC

proc calculateTotalHouseIU*(state: GameState, houseId: HouseId): int32 =
  ## Calculate total Industrial Units across all colonies owned by house
  var totalIU = 0'i32

  for colony in state.coloniesOwned(houseId):
    totalIU += colony.industrial.units

  return totalIU

proc calculateLogisticalStrain*(totalCC: int32, c2Pool: int32): int32 =
  ## Calculate logistical strain cost per turn
  ## Formula: max(0, Total Fleet CC - C2 Pool) × 0.5
  ## Per assets.md:2.3.3.4
  let ratio = gameConfig.limits.c2Limits.c2OverdraftRatio
  let excess = max(0'i32, totalCC - c2Pool)
  return int32(floor(float32(excess) * ratio))

## Analysis Functions

proc analyzeC2Capacity*(state: GameState, houseId: HouseId): C2PoolAnalysis =
  ## Analyze house's C2 Pool capacity status
  ## Pure function - returns analysis without mutating state
  let houseOpt = state.house(houseId)
  if houseOpt.isNone:
    return C2PoolAnalysis(houseId: houseId)

  let house = houseOpt.get()

  # Calculate components
  let totalIU = calculateTotalHouseIU(state, houseId)
  let scLevel = house.techTree.levels.sc
  let scBonus = scTechC2Bonus(scLevel)
  let c2Pool = calculateC2Pool(totalIU, scLevel)
  let totalFleetCC = calculateTotalFleetCC(state, houseId)
  let excess = max(0'i32, totalFleetCC - c2Pool)
  let strain = calculateLogisticalStrain(totalFleetCC, c2Pool)

  return C2PoolAnalysis(
    houseId: houseId,
    totalIU: totalIU,
    scLevel: scLevel,
    scBonus: scBonus,
    c2Pool: c2Pool,
    totalFleetCC: totalFleetCC,
    excess: excess,
    logisticalStrain: strain,
  )

## Application Functions

proc applyLogisticalStrain*(
    state: GameState, houseId: HouseId, strainCost: int32, events: var seq[event.GameEvent]
) =
  ## Apply logistical strain cost to house treasury
  ## Deducts PP cost from treasury and generates event
  if strainCost <= 0:
    return

  let houseOpt = state.house(houseId)
  if houseOpt.isNone:
    return

  var house = houseOpt.get()
  house.treasury -= int32(strainCost)
  state.updateHouse(houseId, house)

  # Generate event for visibility
  events.add(
    event.GameEvent(
      eventType: event.GameEventType.Economy,
      turn: state.turn,
      houseId: some(houseId),
      description: "Logistical strain penalty: " & $strainCost & " PP",
      details: some("C2PoolOverdraft"),
    )
  )

  logger.logInfo(
    "Economy",
    "[C2 POOL] Logistical strain applied",
    "house=", $houseId, " cost=", $strainCost, "PP",
  )

proc processLogisticalStrain*(
    state: GameState, houseId: HouseId, events: var seq[event.GameEvent]
): C2PoolAnalysis =
  ## Main entry point: Analyze C2 capacity and apply logistical strain
  ## Called from Income Phase
  let analysis = analyzeC2Capacity(state, houseId)

  if analysis.logisticalStrain > 0:
    applyLogisticalStrain(state, houseId, analysis.logisticalStrain, events)

  return analysis
