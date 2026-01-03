## C2 Command Pool Capacity & Logistical Strain System
##
## Implements assets.md:2.3.3.3-2.3.3.4 - C2 Pool soft cap and logistical strain penalty.
##
## C2 Pool Formula: (Total House IU × 0.5) + SC Tech Bonus
##
## Where Strategic Command (SC) Tech Level Bonus is:
## - SC I: +50
## - SC II: +60
## - SC III: +75
## - SC IV: +90
## - SC V: +125
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
  ../../types/[core, game_state, house, fleet, squadron, ship, event]
import ../../state/[engine as gs_helpers, iterators]
import ../../globals
import ../../../common/logger

## Pure Calculation Functions

proc getScTechC2Bonus(scLevel: int): int =
  ## Get Strategic Command tech C2 Pool bonus per assets.md:2.3.3.3
  ## Reads from gameConfig.tech.sc.levels
  let cfg = gameConfig.tech.sc
  let levelKey = int32(scLevel)
  if cfg.levels.hasKey(levelKey):
    return int(cfg.levels[levelKey].c2Bonus)
  else:
    return 0 # No SC tech = no bonus

proc calculateC2Pool*(totalHouseIU: int, scLevel: int): int =
  ## Pure calculation of C2 Pool capacity
  ## Formula: C2 Pool = (Total House IU × 0.5) + SC Tech Bonus
  ## Per assets.md:2.3.3.3
  let iuContribution = float(totalHouseIU) * 0.5
  let scBonus = getScTechC2Bonus(scLevel)
  return int(floor(iuContribution)) + scBonus

proc getFleetStatusCCModifier(status: FleetStatus): float =
  ## Get CC multiplier for fleet status per assets.md:2.3.3.5
  ## Active: 100%, Reserve: 50%, Mothballed: 0%
  case status
  of FleetStatus.Active:
    return 1.0
  of FleetStatus.Reserve:
    return 0.5
  of FleetStatus.Mothballed:
    return 0.0

proc calculateShipCC(
    state: GameState, shipId: ShipId, fleetStatus: FleetStatus
): int =
  ## Calculate effective CC for a single ship with fleet status modifier
  let shipOpt = gs_helpers.ship(state, shipId)
  if shipOpt.isNone:
    return 0

  let ship = shipOpt.get()

  # Get ship's base CC from config
  let shipStats = gameConfig.ships.ships[ship.shipClass]
  let baseCC = int(shipStats.commandCost)

  # Apply fleet status modifier
  let modifier = getFleetStatusCCModifier(fleetStatus)
  return int(floor(float(baseCC) * modifier))

proc calculateSquadronCC(
    state: GameState, squadronId: SquadronId, fleetStatus: FleetStatus
): int =
  ## Calculate total CC for all ships in squadron (excluding flagship)
  ## Flagship CC is not counted per squadron command structure
  let squadronOpt = gs_helpers.squadrons(state, squadronId)
  if squadronOpt.isNone:
    return 0

  let squadron = squadronOpt.get()
  var totalCC = 0

  # Count escort ships (flagship doesn't count toward CC)
  for shipId in squadron.ships:
    totalCC += calculateShipCC(state, shipId, fleetStatus)

  return totalCC

proc calculateFleetCC(state: GameState, fleetId: FleetId): int =
  ## Calculate total CC for all ships in fleet with status modifiers
  let fleetOpt = gs_helpers.fleet(state, fleetId)
  if fleetOpt.isNone:
    return 0

  let fleet = fleetOpt.get()
  var totalCC = 0

  # Sum CC from all squadrons in fleet
  for squadronId in fleet.squadrons:
    totalCC += calculateSquadronCC(state, squadronId, fleet.status)

  return totalCC

proc calculateTotalFleetCC*(state: GameState, houseId: HouseId): int =
  ## Calculate total CC across all fleets owned by house
  ## Includes fleet status modifiers (Active/Reserve/Mothballed)
  var totalCC = 0

  for fleet in state.fleetsOwned(houseId):
    totalCC += calculateFleetCC(state, fleet.id)

  return totalCC

proc calculateTotalHouseIU*(state: GameState, houseId: HouseId): int =
  ## Calculate total Industrial Units across all colonies owned by house
  var totalIU = 0

  for colony in state.coloniesOwned(houseId):
    totalIU += int(colony.industrial.units)

  return totalIU

proc calculateLogisticalStrain*(totalCC: int, c2Pool: int): int =
  ## Calculate logistical strain cost per turn
  ## Formula: max(0, Total Fleet CC - C2 Pool) × 0.5
  ## Per assets.md:2.3.3.4
  let excess = max(0, totalCC - c2Pool)
  return int(floor(float(excess) * 0.5))

## Analysis Functions

type C2PoolAnalysis* = object
  ## Analysis result for house C2 Pool capacity
  houseId*: HouseId
  totalIU*: int
  scLevel*: int
  scBonus*: int
  c2Pool*: int
  totalFleetCC*: int
  excess*: int
  logisticalStrain*: int

proc analyzeC2Capacity*(state: GameState, houseId: HouseId): C2PoolAnalysis =
  ## Analyze house's C2 Pool capacity status
  ## Pure function - returns analysis without mutating state
  let houseOpt = gs_helpers.house(state, houseId)
  if houseOpt.isNone:
    return C2PoolAnalysis(houseId: houseId)

  let house = houseOpt.get()

  # Calculate components
  let totalIU = calculateTotalHouseIU(state, houseId)
  let scLevel = int(house.techTree.levels.sc)
  let scBonus = getScTechC2Bonus(scLevel)
  let c2Pool = calculateC2Pool(totalIU, scLevel)
  let totalFleetCC = calculateTotalFleetCC(state, houseId)
  let excess = max(0, totalFleetCC - c2Pool)
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
    state: var GameState, houseId: HouseId, strainCost: int, events: var seq[event.GameEvent]
) =
  ## Apply logistical strain cost to house treasury
  ## Deducts PP cost from treasury and generates event
  if strainCost <= 0:
    return

  let houseOpt = gs_helpers.house(state, houseId)
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
    state: var GameState, houseId: HouseId, events: var seq[event.GameEvent]
): C2PoolAnalysis =
  ## Main entry point: Analyze C2 capacity and apply logistical strain
  ## Called from Income Phase
  let analysis = analyzeC2Capacity(state, houseId)

  if analysis.logisticalStrain > 0:
    applyLogisticalStrain(state, houseId, analysis.logisticalStrain, events)

  return analysis
