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
import
  ../../types/[
    capacity, core, game_state, squadron, ship, production, event, colony, house,
    facilities,
  ]
import ../../state/[entity_manager, engine as gs_helpers, iterators]
import ../../entities/squadron_ops
import ../../event_factory/fleet_ops
import ../../../common/logger
import ../../globals

export
  capacity.CapacityViolation, capacity.EnforcementAction, capacity.ViolationSeverity

proc getCapitalShipCRThreshold*(): int =
  ## Get the CR threshold for capital ships from config
  ## Default: 7 (ships with CR >= 7 are capital ships)
  return gameConfig.limits.c2Limits.capitalShipCrThreshold

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
    return 0.8 # Small maps: encourage concentration
  elif systemsPerPlayer <= 12:
    return 1.0 # Medium maps: baseline
  elif systemsPerPlayer <= 16:
    return 1.3 # Large maps: +30% capacity
  else:
    return 1.6 # Huge maps: +60% capacity

proc calculateMaxCapitalSquadrons*(
    industrialUnits: int, mapRings: int = 3, numPlayers: int = 4
): int =
  ## Pure calculation of maximum capital squadron capacity
  ## Formula: max(8, floor(Total_House_IU ÷ 100) × 2) × mapMultiplier
  ## Minimum: 8 squadrons regardless of IU
  ## Map multiplier scales capacity based on map size (more territory = more ships needed)
  let baseLimit = int(floor(float(industrialUnits) / 100.0) * 2.0)
  let mapMultiplier = getMapSizeMultiplier(mapRings, numPlayers)
  let scaledLimit = int(float(baseLimit) * mapMultiplier)
  return max(8, scaledLimit)

proc getShipConfig(shipClass: ShipClass): ships_config.ShipStatsConfig =
  ## Get ship configuration from global config
  case shipClass
  of ShipClass.Corvette:
    return ships_config.globalShipsConfig.corvette
  of ShipClass.Frigate:
    return ships_config.globalShipsConfig.frigate
  of ShipClass.Destroyer:
    return ships_config.globalShipsConfig.destroyer
  of ShipClass.LightCruiser:
    return ships_config.globalShipsConfig.lightCruiser
  of ShipClass.Cruiser:
    return ships_config.globalShipsConfig.cruiser
  of ShipClass.Battlecruiser:
    return ships_config.globalShipsConfig.battlecruiser
  of ShipClass.Battleship:
    return ships_config.globalShipsConfig.battleship
  of ShipClass.Dreadnought:
    return ships_config.globalShipsConfig.dreadnought
  of ShipClass.SuperDreadnought:
    return ships_config.globalShipsConfig.super_dreadnought
  of ShipClass.Carrier:
    return ships_config.globalShipsConfig.carrier
  of ShipClass.SuperCarrier:
    return ships_config.globalShipsConfig.supercarrier
  of ShipClass.Fighter:
    return ships_config.globalShipsConfig.fighter
  of ShipClass.Raider:
    return ships_config.globalShipsConfig.raider
  of ShipClass.Scout:
    return ships_config.globalShipsConfig.scout
  of ShipClass.ETAC:
    return ships_config.globalShipsConfig.etac
  of ShipClass.TroopTransport:
    return ships_config.globalShipsConfig.troop_transport
  of ShipClass.PlanetBreaker:
    return ships_config.globalShipsConfig.planetbreaker

proc isCapitalShip*(shipClass: ShipClass): bool =
  ## Check if a ship class is a capital ship (role-based)
  ## Capital ships include: Heavy Cruiser, Battle Cruiser, Battleship,
  ## Dreadnought, Super Dreadnought, Carrier, Super Carrier, Raider
  ## Determined by ship_role field in config/ships.toml
  let config = getShipConfig(shipClass)
  return config.ship_role == "Capital"

proc countCapitalSquadronsInFleets*(state: GameState, houseId: HouseId): int =
  ## Count capital squadrons currently in fleets for a house
  ## (O(1) lookup via byHouse index)
  result = 0
  for squadron in state.squadronsOwned(houseId):
    # Get flagship ship using entity manager
    let flagshipOpt = gs_helpers.ship(state, squadron.flagshipId)
    if flagshipOpt.isSome:
      let flagship = flagshipOpt.get()
      if isCapitalShip(flagship.shipClass):
        result += 1

proc countCapitalSquadronsUnderConstruction*(state: GameState, houseId: HouseId): int =
  ## Count capital ships currently under construction house-wide
  ## Note: Uses role-based classification via isCapitalShip()
  result = 0

  # Check spaceport construction queues
  for spaceport in state.spaceportsOwned(houseId):
    for projectId in spaceport.activeConstructions & spaceport.constructionQueue:
      let projectOpt = gs_helpers.constructionProject(state, projectId)
      if projectOpt.isNone:
        continue
      let project = projectOpt.get()

      if project.projectType == BuildType.Ship:
        try:
          let shipClass = parseEnum[ShipClass](project.itemId)
          if isCapitalShip(shipClass):
            result += 1
        except ValueError:
          discard # Invalid ship class, skip

  # Check shipyard construction queues
  for shipyard in state.shipyardsOwned(houseId):
    for projectId in shipyard.activeConstructions & shipyard.constructionQueue:
      let projectOpt = gs_helpers.constructionProject(state, projectId)
      if projectOpt.isNone:
        continue
      let project = projectOpt.get()

      if project.projectType == BuildType.Ship:
        try:
          let shipClass = parseEnum[ShipClass](project.itemId)
          if isCapitalShip(shipClass):
            result += 1
        except ValueError:
          discard # Invalid ship class, skip

proc analyzeCapacity*(state: GameState, houseId: HouseId): capacity.CapacityViolation =
  ## Pure function - analyze house's capital squadron capacity status
  ## Returns capacity analysis without mutating state

  # Calculate total Industrial Units for house
  var totalIU = 0'i32
  for colony in state.coloniesOwned(houseId):
    totalIU += colony.industrial.units

  let current = countCapitalSquadronsInFleets(state, houseId)
  let mapRings = int(state.starMap.numRings)
  let numPlayers = state.starMap.playerCount
  let maximum = calculateMaxCapitalSquadrons(int(totalIU), mapRings, numPlayers)
  let excess = max(0, current - maximum)

  # Capital squadrons have no grace period - immediate enforcement
  let severity =
    if excess == 0:
      capacity.ViolationSeverity.None
    else:
      capacity.ViolationSeverity.Critical

  result = capacity.CapacityViolation(
    capacityType: capacity.CapacityType.CapitalSquadron,
    entity: capacity.EntityIdUnion(
      kind: capacity.CapacityType.CapitalSquadron, houseId: houseId
    ),
    current: int32(current),
    maximum: int32(maximum),
    excess: int32(excess),
    severity: severity,
    graceTurnsRemaining: 0'i32, # No grace period
    violationTurn: int32(state.turn),
  )

proc checkViolations*(state: GameState): seq[capacity.CapacityViolation] =
  ## Batch check all houses for capital squadron capacity violations
  ## Pure function - returns analysis without mutations
  result = @[]

  for house in state.activeHouses():
    let status = analyzeCapacity(state, house.id)
    if status.severity != capacity.ViolationSeverity.None:
      result.add(status)

type SquadronPriority = object ## Helper type for prioritizing squadrons for removal
  squadronId: string
  isCrippled: bool
  attackStrength: int

proc prioritizeSquadronsForRemoval(
    state: GameState, houseId: HouseId
): seq[SquadronPriority] =
  ## Determine priority order for removing squadrons
  ## Priority: 1) Crippled flagships first, 2) Lowest AS second
  ## Returns sorted list (highest priority first = first to remove)
  result = @[]

  for squadron in state.squadronsOwned(houseId):
    # Get flagship ship using entity manager
    let flagshipOpt = gs_helpers.ship(state, squadron.flagshipId)
    if flagshipOpt.isSome:
      let flagship = flagshipOpt.get()
      if isCapitalShip(flagship.shipClass):
        result.add(
          SquadronPriority(
            squadronId: $squadron.id,
            isCrippled: flagship.isCrippled,
            attackStrength: flagship.stats.attackStrength,
          )
        )

  # Sort: crippled first, then by lowest AS
  result.sort do(a, b: SquadronPriority) -> int:
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
  let config = getShipConfig(shipClass)
  let salvageMultiplier =
    military_config.globalMilitaryConfig.salvage.salvage_value_multiplier
  return int(float(config.build_cost) * salvageMultiplier)

proc planEnforcement*(
    state: GameState, violation: capacity.CapacityViolation
): capacity.EnforcementAction =
  ## Plan enforcement actions for violations
  ## Pure function - returns enforcement plan without mutations
  ## Capital squadrons: Auto-scrap excess units with 50% salvage

  result = capacity.EnforcementAction(
    capacityType: capacity.CapacityType.CapitalSquadron,
    entity: violation.entity,
    actionType: "",
    affectedUnitIds: @[],
    description: "",
  )

  if violation.severity != capacity.ViolationSeverity.Critical:
    return

  let houseId = violation.entity.houseId

  # Find all capital squadrons for this house and prioritize for removal
  let priorities = prioritizeSquadronsForRemoval(state, houseId)

  # Select excess squadrons for scrapping (already sorted by priority)
  let toScrapCount = min(violation.excess, int32(priorities.len))
  result.actionType = "auto_scrap"
  for i in 0 ..< toScrapCount:
    result.affectedUnitIds.add(priorities[i].squadronId)

  result.description =
    $toScrapCount & " capital squadron(s) auto-scrapped for " & $violation.entity.houseId &
    " (IU loss, 50% salvage paid)"

proc applyEnforcement*(
    state: var GameState, action: capacity.EnforcementAction, events: var seq[GameEvent]
) =
  ## Apply enforcement actions
  ## Explicit mutation - scraps capital squadrons and credits salvage value
  ## Emits SquadronScrapped events for tracking

  if action.actionType != "auto_scrap" or action.affectedUnitIds.len == 0:
    return

  let houseId = action.entity.houseId
  var totalSalvage = 0

  # Remove capital squadrons from fleets and calculate salvage
  var squadronsToRemove: seq[SquadronId] = @[]

  # First pass: identify squadrons to remove and calculate salvage
  for squadron in state.squadronsOwned(houseId):
    if $squadron.id in action.affectedUnitIds:
      squadronsToRemove.add(squadron.id)

      # Get flagship ship using entity manager
      let flagshipOpt = gs_helpers.ship(state, squadron.flagshipId)
      if flagshipOpt.isNone:
        continue

      let flagship = flagshipOpt.get()
      let salvage = calculateSalvageValue(flagship.shipClass)
      totalSalvage += salvage

      logger.logDebug(
        "Military",
        "Capital squadron auto-scrapped - IU loss",
        " squadronId=",
        $squadron.id,
        " class=",
        $flagship.shipClass,
        " salvage=",
        $salvage,
      )

      # Emit SquadronScrapped event for tracking
      events.add(
        fleet_ops.squadronScrapped(
          houseId = houseId,
          squadronId = $squadron.id,
          shipClass = flagship.shipClass,
          reason = "Capital squadron capacity exceeded (IU loss)",
          salvageValue = salvage,
          systemId = squadron.location,
        )
      )

  # Second pass: actually destroy the squadrons
  for squadronId in squadronsToRemove:
    squadron_ops.destroySquadron(state, squadronId)

  # Credit salvage to house treasury
  if totalSalvage > 0:
    let houseOpt = gs_helpers.house(state, houseId)
    if houseOpt.isSome:
      var house = houseOpt.get()
      house.treasury += int32(totalSalvage)
      state.houses.entities.updateEntity(houseId, house)
      logger.logDebug(
        "Military",
        "Salvage credited to house treasury",
        " house=",
        $houseId,
        " amount=",
        $totalSalvage,
      )

  logger.logDebug(
    "Military",
    "Capital squadron capacity enforcement complete",
    " house=",
    $houseId,
    " scrapped=",
    $action.affectedUnitIds.len,
    " salvage=",
    $totalSalvage,
  )

proc processCapacityEnforcement*(
    state: var GameState, events: var seq[GameEvent]
): seq[capacity.EnforcementAction] =
  ## Main entry point - batch process all capital squadron capacity violations
  ## Called during Maintenance phase
  ## Data-oriented: analyze all → plan enforcement → apply enforcement
  ## Returns: List of enforcement actions that were actually applied

  result = @[]

  logger.logDebug("Military", "Checking capital squadron capacity")

  # Step 1: Check all houses for violations (pure)
  let violations = checkViolations(state)

  if violations.len == 0:
    logger.logDebug("Military", "All houses within capital squadron capacity limits")
    return

  logger.logDebug(
    "Military", "Capital squadron violations found, count=", $violations.len
  )

  # Step 2: Plan enforcement (no tracking needed - immediate enforcement)
  var enforcementActions: seq[capacity.EnforcementAction] = @[]
  for violation in violations:
    let action = planEnforcement(state, violation)
    if action.actionType == "auto_scrap" and action.affectedUnitIds.len > 0:
      enforcementActions.add(action)

  # Step 3: Apply enforcement (mutations)
  if enforcementActions.len > 0:
    logger.logDebug(
      "Military",
      "Enforcing capital squadron capacity violations, count=",
      $enforcementActions.len,
    )
    for action in enforcementActions:
      applyEnforcement(state, action, events)
      result.add(action) # Track which actions were applied
  else:
    logger.logDebug("Military", "No capital squadron violations requiring enforcement")

proc canBuildCapitalShip*(state: GameState, houseId: HouseId): bool =
  ## Check if house can build a new capital ship
  ## Returns false if house is at or over capacity
  ## Pure function - no mutations

  let violation = analyzeCapacity(state, houseId)

  # Account for capital ships already under construction
  let underConstruction = countCapitalSquadronsUnderConstruction(state, houseId)

  return violation.current + int32(underConstruction) < violation.maximum

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
