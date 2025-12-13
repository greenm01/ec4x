## Capital Squadron Capacity Enforcement System
##
## Implements capital ship squadron limits per reference.md Table 10.5
##
## Capacity Formula: max(8, floor(Total_House_IU ÷ 100) × 2)
##
## **IMPORTANT:** Capital squadrons are limited by industrial capacity to reflect
## the massive infrastructure needed to maintain capital warships (dockyards, crew,
## supplies, training facilities). Only houses with strong industrial bases can
## field large capital fleets.
##
## **Capital Ship Definition:** Ships with Command Rating (CR) >= capital_ship_cr_threshold
## Default threshold: 7 (configurable via config/military.toml)
##
## Enforcement: Cannot build beyond limit, auto-scrap excess if IU is lost
## Salvage: Space Guilds pay 50% of build cost for excess ships
##
## Data-oriented design: Calculate violations (pure), apply enforcement (explicit mutations)

import std/[tables, strutils, algorithm, options, math]
import ./types
import ../../gamestate
import ../../squadron  # For newEnhancedShip
import ../../config/military_config  # For capital_ship_cr_threshold
import ../types as econ_types  # For ConstructionType, ConstructionProject
import ../../../common/types/core
import ../../../common/types/units  # For ShipClass, Ship
import ../../../common/logger
import ../../resolution/types as resolution_types  # For GameEvent
import ../../resolution/event_factory/fleet_ops  # For squadronScrapped

export types.CapacityViolation, types.EnforcementAction, types.ViolationSeverity

proc getCapitalShipCRThreshold*(): int =
  ## Get the CR threshold for capital ships from config
  ## Default: 7 (ships with CR >= 7 are capital ships)
  return military_config.globalMilitaryConfig.squadron_limits.capital_ship_cr_threshold

proc getSystemsForRings(mapRings: int): int =
  ## Estimate total systems for a given map ring count
  ## Formula: Approximate hex grid growth (1 + 3*rings*(rings+1))
  ## Ring 0 (center): 1 system
  ## Ring 1: +6 systems = 7 total
  ## Ring 2: +12 systems = 19 total
  ## Ring 3: +18 systems = 37 total
  ## Ring 4: +24 systems = 61 total
  ## Ring 5: +30 systems = 91 total
  return 1 + (3 * mapRings * (mapRings + 1))

proc getMapSizeMultiplier*(mapRings: int, numPlayers: int): float =
  ## Calculate capacity multiplier based on map size
  ## Larger maps need larger fleets to control more territory
  ## Exported for use by total_squadrons module
  let totalSystems = getSystemsForRings(mapRings)
  let systemsPerPlayer = totalSystems div max(1, numPlayers)

  if systemsPerPlayer < 8:
    return 0.8  # Small maps: encourage concentration
  elif systemsPerPlayer <= 12:
    return 1.0  # Medium maps: baseline
  elif systemsPerPlayer <= 16:
    return 1.3  # Large maps: +30% capacity
  else:
    return 1.6  # Huge maps: +60% capacity

proc calculateMaxCapitalSquadrons*(industrialUnits: int, mapRings: int = 3, numPlayers: int = 4): int =
  ## Pure calculation of maximum capital squadron capacity
  ## Formula: max(8, floor(Total_House_IU ÷ 100) × 2) × mapMultiplier
  ## Minimum: 8 squadrons regardless of IU
  ## Map multiplier scales capacity based on map size (more territory = more ships needed)
  let baseLimit = int(floor(float(industrialUnits) / 100.0) * 2.0)
  let mapMultiplier = getMapSizeMultiplier(mapRings, numPlayers)
  let scaledLimit = int(float(baseLimit) * mapMultiplier)
  return max(8, scaledLimit)

proc isCapitalShip*(shipClass: ShipClass): bool =
  ## Check if a ship class is a capital ship (role-based)
  ## Capital ships include: Heavy Cruiser, Battle Cruiser, Battleship,
  ## Dreadnought, Super Dreadnought, Carrier, Super Carrier, Raider
  ## Determined by ship_role field in config/ships.toml

  # Get ship stats from global ship data
  let ship = squadron.newEnhancedShip(shipClass, techLevel = 1)

  return ship.stats.role == ShipRole.Capital

proc countCapitalSquadronsInFleets*(state: GameState, houseId: core.HouseId): int =
  ## Count capital squadrons currently in fleets for a house
  result = 0
  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      for squadron in fleet.squadrons:
        if isCapitalShip(squadron.flagship.shipClass):
          result += 1

proc countCapitalSquadronsUnderConstruction*(state: GameState, houseId: core.HouseId): int =
  ## Count capital ships currently under construction house-wide
  ## Note: Uses role-based classification via isCapitalShip()
  result = 0

  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      # Check underConstruction (legacy single project)
      if colony.underConstruction.isSome:
        let project = colony.underConstruction.get()
        if project.projectType == econ_types.ConstructionType.Ship:
          try:
            let shipClass = parseEnum[ShipClass](project.itemId)
            if isCapitalShip(shipClass):
              result += 1
          except ValueError:
            discard  # Invalid ship class, skip

      # Check construction queue
      for project in colony.constructionQueue:
        if project.projectType == econ_types.ConstructionType.Ship:
          try:
            let shipClass = parseEnum[ShipClass](project.itemId)
            if isCapitalShip(shipClass):
              result += 1
          except ValueError:
            discard  # Invalid ship class, skip

proc analyzeCapacity*(state: GameState, houseId: core.HouseId): types.CapacityViolation =
  ## Pure function - analyze house's capital squadron capacity status
  ## Returns capacity analysis without mutating state

  let totalIU = state.getTotalHouseIndustrialUnits(houseId)
  let current = countCapitalSquadronsInFleets(state, houseId)
  let mapRings = int(state.starMap.numRings)
  let numPlayers = state.starMap.playerCount
  let maximum = calculateMaxCapitalSquadrons(totalIU, mapRings, numPlayers)
  let excess = max(0, current - maximum)

  # Capital squadrons have no grace period - immediate enforcement
  let severity = if excess == 0:
                   ViolationSeverity.None
                 else:
                   ViolationSeverity.Critical

  result = types.CapacityViolation(
    capacityType: CapacityType.CapitalSquadron,
    entityId: $houseId,
    current: current,
    maximum: maximum,
    excess: excess,
    severity: severity,
    graceTurnsRemaining: 0,  # No grace period
    violationTurn: state.turn
  )

proc checkViolations*(state: GameState): seq[types.CapacityViolation] =
  ## Batch check all houses for capital squadron capacity violations
  ## Pure function - returns analysis without mutations
  result = @[]

  for houseId, house in state.houses:
    if not house.eliminated:
      let status = analyzeCapacity(state, houseId)
      if status.severity != ViolationSeverity.None:
        result.add(status)

type
  SquadronPriority = object
    ## Helper type for prioritizing squadrons for removal
    squadronId: string
    isCrippled: bool
    attackStrength: int

proc prioritizeSquadronsForRemoval(state: GameState, houseId: core.HouseId): seq[SquadronPriority] =
  ## Determine priority order for removing squadrons
  ## Priority: 1) Crippled flagships first, 2) Lowest AS second
  ## Returns sorted list (highest priority first = first to remove)
  result = @[]

  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      for squadron in fleet.squadrons:
        if isCapitalShip(squadron.flagship.shipClass):
          result.add(SquadronPriority(
            squadronId: squadron.id,
            isCrippled: squadron.flagship.isCrippled,
            attackStrength: squadron.flagship.stats.attackStrength
          ))

  # Sort: crippled first, then by lowest AS
  result.sort do (a, b: SquadronPriority) -> int:
    # Crippled ships have higher priority (removed first)
    if a.isCrippled and not b.isCrippled:
      return -1
    elif not a.isCrippled and b.isCrippled:
      return 1
    else:
      # Among same crippled status, lower AS = higher priority
      return cmp(a.attackStrength, b.attackStrength)

proc calculateSalvageValue*(shipClass: ShipClass): int =
  ## Calculate salvage value for a ship (50% of build cost)
  ## Space Guilds pay fair market value for excess capital ships
  let ship = squadron.newEnhancedShip(shipClass, techLevel = 1)
  let salvageMultiplier = military_config.globalMilitaryConfig.salvage.salvage_value_multiplier
  return int(float(ship.stats.buildCost) * salvageMultiplier)

proc planEnforcement*(state: GameState, violation: types.CapacityViolation): types.EnforcementAction =
  ## Plan enforcement actions for violations
  ## Pure function - returns enforcement plan without mutations
  ## Capital squadrons: Auto-scrap excess units with 50% salvage

  result = types.EnforcementAction(
    capacityType: CapacityType.CapitalSquadron,
    entityId: violation.entityId,
    actionType: "",
    affectedUnits: @[],
    description: ""
  )

  if violation.severity != ViolationSeverity.Critical:
    return

  let houseId = core.HouseId(violation.entityId)

  # Find all capital squadrons for this house and prioritize for removal
  let priorities = prioritizeSquadronsForRemoval(state, houseId)

  # Select excess squadrons for scrapping (already sorted by priority)
  let toScrapCount = min(violation.excess, priorities.len)
  result.actionType = "auto_scrap"
  for i in 0 ..< toScrapCount:
    result.affectedUnits.add(priorities[i].squadronId)

  result.description = $toScrapCount & " capital squadron(s) auto-scrapped for " &
                      violation.entityId & " (IU loss, 50% salvage paid)"

proc applyEnforcement*(state: var GameState, action: types.EnforcementAction,
                       events: var seq[resolution_types.GameEvent]) =
  ## Apply enforcement actions
  ## Explicit mutation - scraps capital squadrons and credits salvage value
  ## Emits SquadronScrapped events for tracking

  if action.actionType != "auto_scrap" or action.affectedUnits.len == 0:
    return

  let houseId = core.HouseId(action.entityId)
  var totalSalvage = 0

  # Remove capital squadrons from fleets and calculate salvage
  for fleetId, fleet in state.fleets.mpairs:
    if fleet.owner == houseId:
      var toRemove: seq[int] = @[]
      for idx, squadron in fleet.squadrons:
        if squadron.id in action.affectedUnits:
          toRemove.add(idx)
          let salvage = calculateSalvageValue(squadron.flagship.shipClass)
          totalSalvage += salvage
          logEconomy("Capital squadron auto-scrapped - IU loss",
                    "squadronId=", squadron.id,
                    " class=", $squadron.flagship.shipClass,
                    " salvage=", $salvage)

      # Remove squadrons (reverse order to maintain indices)
      for idx in toRemove.reversed:
        let squadron = fleet.squadrons[idx]
        let salvage = calculateSalvageValue(squadron.flagship.shipClass)

        # Emit SquadronScrapped event
        events.add(fleet_ops.squadronScrapped(
          houseId = houseId,
          squadronId = squadron.id,
          shipClass = squadron.flagship.shipClass,
          reason = "Capital squadron capacity exceeded (IU loss)",
          salvageValue = salvage,
          systemId = fleet.location
        ))

        fleet.squadrons.delete(idx)

  # Credit salvage to house treasury
  if totalSalvage > 0 and state.houses.hasKey(houseId):
    state.houses[houseId].treasury += totalSalvage
    logEconomy("Salvage credited to house treasury",
              "house=", $houseId,
              " amount=", $totalSalvage)

  logEconomy("Capital squadron capacity enforcement complete",
            "house=", $houseId,
            " scrapped=", $action.affectedUnits.len,
            " salvage=", $totalSalvage)

proc processCapacityEnforcement*(state: var GameState,
                                events: var seq[resolution_types.GameEvent]): seq[types.EnforcementAction] =
  ## Main entry point - batch process all capital squadron capacity violations
  ## Called during Maintenance phase
  ## Data-oriented: analyze all → plan enforcement → apply enforcement
  ## Returns: List of enforcement actions that were actually applied

  result = @[]

  logDebug("Military", "Checking capital squadron capacity")

  # Step 1: Check all houses for violations (pure)
  let violations = checkViolations(state)

  if violations.len == 0:
    logDebug("Military", "All houses within capital squadron capacity limits")
    return

  logDebug("Military", "Capital squadron violations found", "count=", $violations.len)

  # Step 2: Plan enforcement (no tracking needed - immediate enforcement)
  var enforcementActions: seq[types.EnforcementAction] = @[]
  for violation in violations:
    let action = planEnforcement(state, violation)
    if action.actionType == "auto_scrap" and action.affectedUnits.len > 0:
      enforcementActions.add(action)

  # Step 3: Apply enforcement (mutations)
  if enforcementActions.len > 0:
    logEconomy("Enforcing capital squadron capacity violations",
              "count=", $enforcementActions.len)
    for action in enforcementActions:
      applyEnforcement(state, action, events)
      result.add(action)  # Track which actions were applied
  else:
    logDebug("Military", "No capital squadron violations requiring enforcement")

proc canBuildCapitalShip*(state: GameState, houseId: core.HouseId): bool =
  ## Check if house can build a new capital ship
  ## Returns false if house is at or over capacity
  ## Pure function - no mutations

  let violation = analyzeCapacity(state, houseId)

  # Account for capital ships already under construction
  let underConstruction = countCapitalSquadronsUnderConstruction(state, houseId)

  return violation.current + underConstruction < violation.maximum

## Design Notes:
##
## **Data-Oriented Pattern:**
## 1. analyzeCapacity() - Pure calculation of capacity status
## 2. checkViolations() - Batch analyze all houses (pure)
## 3. planEnforcement() - Pure function returns enforcement plan
## 4. applyEnforcement() - Explicit mutations apply the plan
## 5. processCapacityEnforcement() - Main batch processor
##
## **Key Differences from Other Capacity Systems:**
## - IU-based formula (not colony-count like planet-breakers)
## - NO grace period (immediate enforcement on IU loss)
## - Per-house limit (not per-colony like fighters)
## - 50% salvage value (space guilds buy excess ships)
## - Smart prioritization (crippled first, then lowest AS)
##
## **Spec Compliance:**
## - reference.md Table 10.5: max(8, floor(Total_House_IU ÷ 100) × 2)
## - Immediate enforcement when IU is lost
## - Cannot build beyond current capacity + queued construction
## - Salvage value: 50% of build cost (config/military.toml)
## - CR threshold configurable (default 7)
##
## **Integration Points:**
## - Call processCapacityEnforcement() in Maintenance phase
## - Call canBuildCapitalShip() before allowing construction orders
## - Enforcement happens AFTER economic resolution (IU changes applied)
##
## **Strategic Implications:**
## - Crippled ships are vulnerable to involuntary salvage
## - Players should repair crippled flagships quickly
## - Losing colonies reduces IU, which can reduce fleet capacity
## - Salvage payments soften the blow but don't fully compensate
