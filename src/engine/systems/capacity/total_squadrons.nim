## Total Squadron Capacity Enforcement System
##
## Implements total squadron limits to prevent escort spam
##
## **Purpose**: While capital squadrons have IU-based limits, escorts (CT, FG, DD, etc.)
## previously had no limits, allowing players to spam thousands of cheap corvettes.
## This system adds a house-wide squadron limit to prevent unrealistic fleet compositions.
##
## Capacity Formula: max(20, floor(Total_House_IU ÷ 50) × mapMultiplier)
##
## **Key Design Points:**
## - Total squadron limit is ~2x the capital squadron limit
## - Capital squadron limit is a SUBSET of total limit (not additive)
## - Minimum 20 squadrons for early-game viability
## - Map size multipliers scale capacity for larger/smaller maps
## - Includes ALL squadrons: capital ships, escorts, raiders
## - Excludes: fighters (separate per-colony limits), auxiliary ships (ETAC/TT/Scout)
##
## **Enforcement:**
## - 2-turn grace period for losing IU (gives time to adjust)
## - Priority removal: weakest escorts first (lowest AS), then damaged ships
## - No salvage value (escorts are smaller units, just disbanded)
##
## Data-oriented design: Calculate violations (pure) → plan enforcement → apply enforcement

import std/[algorithm, options, strformat, strutils, tables]
import ../../types/[
  capacity, game_state, squadron, ship, core, production, event, colony, house
]
import ../../state/[game_state as gs_helpers, iterators]
import ../../entities/squadron_ops
import ../../event_factory/fleet_ops
import ../../config/[military_config, ships_config]
import ../../../common/logger

export capacity.CapacityViolation, capacity.EnforcementAction,
       capacity.ViolationSeverity

# Re-use map size helpers from capital_squadrons
import ./capital_squadrons

proc calculateMaxTotalSquadrons*(industrialUnits: int, mapRings: int = 3, numPlayers: int = 4): int =
  ## Pure calculation of maximum total squadron capacity
  ## Formula: max(minimum, floor(Total_House_IU ÷ divisor) × mapMultiplier)
  ## Values configurable in config/military.toml [squadron_limits]
  ## This is roughly 2x the capital squadron limit
  let divisor = float(globalMilitaryConfig.squadron_limits.total_squadron_iu_divisor)
  let minimum = globalMilitaryConfig.squadron_limits.total_squadron_minimum
  let baseLimit = int(float(industrialUnits) / divisor)
  let mapMultiplier = capital_squadrons.getMapSizeMultiplier(mapRings, numPlayers)
  let scaledLimit = int(float(baseLimit) * mapMultiplier)
  return max(minimum, scaledLimit)

proc getShipConfig(shipClass: ShipClass): ships_config.ShipStatsConfig =
  ## Get ship configuration from global config
  case shipClass
  of ShipClass.Corvette: return ships_config.globalShipsConfig.corvette
  of ShipClass.Frigate: return ships_config.globalShipsConfig.frigate
  of ShipClass.Destroyer: return ships_config.globalShipsConfig.destroyer
  of ShipClass.Cruiser: return ships_config.globalShipsConfig.cruiser
  of ShipClass.LightCruiser: return ships_config.globalShipsConfig.light_cruiser
  of ShipClass.HeavyCruiser: return ships_config.globalShipsConfig.heavy_cruiser
  of ShipClass.Battlecruiser: return ships_config.globalShipsConfig.battlecruiser
  of ShipClass.Battleship: return ships_config.globalShipsConfig.battleship
  of ShipClass.Dreadnought: return ships_config.globalShipsConfig.dreadnought
  of ShipClass.SuperDreadnought: return ships_config.globalShipsConfig.super_dreadnought
  of ShipClass.Carrier: return ships_config.globalShipsConfig.carrier
  of ShipClass.SuperCarrier: return ships_config.globalShipsConfig.supercarrier
  of ShipClass.Fighter: return ships_config.globalShipsConfig.fighter
  of ShipClass.Raider: return ships_config.globalShipsConfig.raider
  of ShipClass.Scout: return ships_config.globalShipsConfig.scout
  of ShipClass.ETAC: return ships_config.globalShipsConfig.etac
  of ShipClass.TroopTransport: return ships_config.globalShipsConfig.troop_transport
  of ShipClass.PlanetBreaker: return ships_config.globalShipsConfig.planetbreaker

proc isMilitarySquadron*(shipClass: ShipClass): bool =
  ## Check if a ship class counts toward total squadron limits
  ## Excludes: Auxiliary ships (ETAC, TT) - they're logistics, not combat squadrons
  ## Includes: All combat ships (escorts, capitals, special weapons)
  let config = getShipConfig(shipClass)
  return config.ship_role != "Auxiliary"

proc countTotalSquadronsInFleets*(state: GameState, houseId: HouseId): int =
  ## Count all military squadrons currently in fleets for a house
  ## Excludes auxiliary ships (ETAC, TT)
  ## (O(1) lookup via squadronsOwned iterator)
  result = 0
  for squadron in state.squadronsOwned(houseId):
    if isMilitarySquadron(squadron.flagship.shipClass):
      result += 1

proc countTotalSquadronsUnderConstruction*(state: GameState,
                                            houseId: HouseId): int =
  ## Count total military squadrons currently under construction
  ## Includes both activeConstruction and queued projects in facilities
  ## Mirrors capital_squadrons.nim pattern but for all military ships
  result = 0

  # Check spaceport construction queues
  for spaceport in state.spaceportsOwned(houseId):
    for projectId in spaceport.activeConstructions & spaceport.constructionQueue:
      let projectOpt = gs_helpers.getConstructionProject(state, projectId)
      if projectOpt.isNone: continue
      let project = projectOpt.get()

      if project.projectType == BuildType.Ship:
        try:
          let shipClass = parseEnum[ShipClass](project.itemId)
          if isMilitarySquadron(shipClass):
            result += 1
        except ValueError:
          discard  # Invalid ship class, skip

  # Check shipyard construction queues
  for shipyard in state.shipyardsOwned(houseId):
    for projectId in shipyard.activeConstructions & shipyard.constructionQueue:
      let projectOpt = gs_helpers.getConstructionProject(state, projectId)
      if projectOpt.isNone: continue
      let project = projectOpt.get()

      if project.projectType == BuildType.Ship:
        try:
          let shipClass = parseEnum[ShipClass](project.itemId)
          if isMilitarySquadron(shipClass):
            result += 1
        except ValueError:
          discard  # Invalid ship class, skip

proc analyzeCapacity*(state: GameState, houseId: HouseId): capacity.CapacityViolation =
  ## Pure function - analyze house's total squadron capacity status
  ## Returns capacity analysis without mutating state

  # Calculate total Industrial Units for house
  var totalIU = 0'i32
  for colony in state.coloniesOwned(houseId):
    totalIU += colony.industrial.units
  let current = countTotalSquadronsInFleets(state, houseId)
  let underConstruction = countTotalSquadronsUnderConstruction(state, houseId)
  let mapRings = int(state.starMap.numRings)
  let numPlayers = state.starMap.playerCount
  let maximum = calculateMaxTotalSquadrons(totalIU, mapRings, numPlayers)
  let excess = max(0, current - maximum)

  # DEBUG: Log capacity at key turns
  if state.turn in [1, 15, 25, 35, 45]:
    logInfo("Military", &"{houseId} T{state.turn}: {current}/{maximum} squadrons (IU={totalIU}), {underConstruction} ships under construction")

  # Check grace period status (2-turn grace per spec)
  var graceTurns: int32 = 0
  var severity = capacity.ViolationSeverity.None

  if excess > 0:
    # Check if grace period is active
    if houseId in state.gracePeriodTimers:
      let expiry = state.gracePeriodTimers[houseId].totalSquadronsExpiry
      if expiry > 0:
        # Grace period active
        graceTurns = max(0'i32, expiry - int32(state.turn))
        if graceTurns > 0:
          severity = capacity.ViolationSeverity.Warning  # Grace period active
        else:
          severity = capacity.ViolationSeverity.Critical  # Grace expired, enforce
      else:
        # No grace period set yet (will be set on first violation)
        severity = capacity.ViolationSeverity.Warning
        graceTurns = 2  # Will start 2-turn grace
    else:
      # First violation for this house
      severity = capacity.ViolationSeverity.Warning
      graceTurns = 2  # Will start 2-turn grace

  result = capacity.CapacityViolation(
    capacityType: capacity.CapacityType.TotalSquadron,
    entity: capacity.EntityIdUnion(kind: capacity.CapacityType.TotalSquadron, houseId: houseId),
    current: int32(current),
    maximum: int32(maximum),
    excess: int32(excess),
    severity: severity,
    graceTurnsRemaining: graceTurns,
    violationTurn: int32(state.turn)
  )

proc startGracePeriod*(state: var GameState, houseId: HouseId) =
  ## Start or reset grace period for total squadron violations
  ## Explicit mutation - sets 2-turn grace period expiry
  if houseId notin state.gracePeriodTimers:
    state.gracePeriodTimers[houseId] = game_state.GracePeriodTracker(
      totalSquadronsExpiry: int32(state.turn + 2),
      fighterCapacityExpiry: initTable[SystemId, int]()
    )
  else:
    # Update existing tracker, preserve fighter grace periods
    var tracker = state.gracePeriodTimers[houseId]
    tracker.totalSquadronsExpiry = int32(state.turn + 2)
    state.gracePeriodTimers[houseId] = tracker

proc clearGracePeriod*(state: var GameState, houseId: HouseId) =
  ## Clear grace period when capacity violation is resolved
  ## Explicit mutation - resets expiry to 0
  if houseId in state.gracePeriodTimers:
    var tracker = state.gracePeriodTimers[houseId]
    tracker.totalSquadronsExpiry = 0
    state.gracePeriodTimers[houseId] = tracker

proc checkViolations*(state: GameState): seq[capacity.CapacityViolation] =
  ## Batch check all houses for total squadron capacity violations
  ## Pure function - returns analysis without mutations
  result = @[]

  for house in state.activeHouses():
    let status = analyzeCapacity(state, house.id)
    if status.severity != capacity.ViolationSeverity.None:
      result.add(status)

type
  SquadronPriority = object
    ## Helper type for prioritizing squadrons for removal
    squadronId: string
    isCrippled: bool
    attackStrength: int
    isCapital: bool

proc prioritizeSquadronsForRemoval(state: GameState, houseId: HouseId): seq[SquadronPriority] =
  ## Determine priority order for removing squadrons
  ## Priority: 1) Non-capitals first (escorts), 2) Crippled ships, 3) Lowest AS
  ## Returns sorted list (highest priority first = first to remove)
  result = @[]

  for squadron in state.squadronsOwned(houseId):
    if isMilitarySquadron(squadron.flagship.shipClass):
      result.add(SquadronPriority(
        squadronId: $squadron.id,
        isCrippled: squadron.flagship.isCrippled,
        attackStrength: squadron.flagship.stats.attackStrength,
        isCapital: capital_squadrons.isCapitalShip(squadron.flagship.shipClass)
      ))

  # Sort: non-capitals first, then crippled, then by lowest AS
  result.sort do (a, b: SquadronPriority) -> int:
    # Non-capitals have higher priority for removal (escorts first)
    if not a.isCapital and b.isCapital:
      return -1
    elif a.isCapital and not b.isCapital:
      return 1
    # Among same capital status, crippled ships have higher priority
    elif a.isCrippled and not b.isCrippled:
      return -1
    elif not a.isCrippled and b.isCrippled:
      return 1
    # Among same crippled status, lower AS = higher priority
    else:
      return cmp(a.attackStrength, b.attackStrength)

proc planEnforcement*(state: GameState, violation: capacity.CapacityViolation): capacity.EnforcementAction =
  ## Plan enforcement actions for violations
  ## Pure function - returns enforcement plan without mutations
  ## Total squadrons: Auto-disband excess units (weakest escorts first, no salvage)

  result = capacity.EnforcementAction(
    capacityType: capacity.CapacityType.TotalSquadron,
    entity: violation.entity,
    actionType: "",
    affectedUnitIds: @[],
    description: ""
  )

  if violation.severity != capacity.ViolationSeverity.Critical:
    return

  let houseId = violation.entity.houseId

  # Find all military squadrons for this house and prioritize for removal
  let priorities = prioritizeSquadronsForRemoval(state, houseId)

  # Select excess squadrons for disbanding (already sorted by priority)
  let toDisbandCount = min(violation.excess, int32(priorities.len))
  result.actionType = "auto_disband"
  for i in 0 ..< toDisbandCount:
    result.affectedUnitIds.add(priorities[i].squadronId)

  result.description = $toDisbandCount & " squadron(s) auto-disbanded for " &
                      $violation.entity.houseId & " (exceeded total squadron capacity, IU loss)"

proc applyEnforcement*(state: var GameState, action: capacity.EnforcementAction,
                       events: var seq[GameEvent]) =
  ## Apply enforcement actions
  ## Explicit mutation - disbands excess squadrons
  ## Emits SquadronDisbanded events for tracking

  if action.actionType != "auto_disband" or action.affectedUnitIds.len == 0:
    return

  let houseId = action.entity.houseId

  # Remove squadrons using squadron_ops.destroySquadron
  for squadronIdStr in action.affectedUnitIds:
    let squadronId = SquadronId(parseUInt(squadronIdStr))

    # Get squadron info before destroying
    let squadronOpt = gs_helpers.getSquadrons(state, squadronId)
    if squadronOpt.isSome:
      let squadron = squadronOpt.get()

      logger.logDebug("Military", "Squadron auto-disbanded - total capacity exceeded",
                " squadronId=", squadronIdStr,
                " class=", $squadron.flagship.shipClass)

      # Emit SquadronDisbanded event
      events.add(fleet_ops.squadronDisbanded(
        houseId = houseId,
        squadronId = squadronIdStr,
        shipClass = squadron.flagship.shipClass,
        reason = "Total squadron capacity exceeded (IU loss)",
        systemId = squadron.location
      ))

    # Destroy squadron from state.squadrons EntityManager
    squadron_ops.destroySquadron(state, squadronId)

  logger.logDebug("Military", "Total squadron capacity enforcement complete",
            " house=", $houseId,
            " disbanded=", $action.affectedUnitIds.len)

proc processCapacityEnforcement*(state: var GameState,
                                events: var seq[GameEvent]): seq[capacity.EnforcementAction] =
  ## Main entry point - batch process all total squadron capacity violations
  ## Called during Income Phase (after IU loss from blockades/combat)
  ## Data-oriented: analyze all → manage grace periods → plan enforcement →
  ## apply enforcement
  ## Returns: List of enforcement actions that were actually applied

  result = @[]

  logger.logDebug("Military", "Checking total squadron capacity")

  # Step 1: Check all houses for violations (pure)
  let violations = checkViolations(state)

  if violations.len == 0:
    logger.logDebug("Military", "All houses within total squadron capacity limits")
    # Clear grace periods for houses with no violations
    for house in state.activeHouses():
      clearGracePeriod(state, house.id)
    return

  logger.logDebug("Military", "Total squadron violations found", "count=",
          $violations.len)

  # Step 2: Manage grace periods and plan enforcement
  var enforcementActions: seq[capacity.EnforcementAction] = @[]
  for violation in violations:
    let houseId = violation.entity.houseId

    if violation.severity == capacity.ViolationSeverity.Warning:
      # Start grace period if not already started
      startGracePeriod(state, houseId)
      logger.logDebug("Military",
              &"House {houseId} over total squadron capacity, grace period " &
              &"active ({violation.graceTurnsRemaining} turns remaining)")
    elif violation.severity == capacity.ViolationSeverity.Critical:
      # Grace expired, enforce
      let action = planEnforcement(state, violation)
      if action.actionType == "auto_disband" and action.affectedUnitIds.len > 0:
        enforcementActions.add(action)

  # Step 3: Apply enforcement (mutations)
  if enforcementActions.len > 0:
    logger.logEconomy("Enforcing total squadron capacity violations",
              "count=", $enforcementActions.len)
    for action in enforcementActions:
      applyEnforcement(state, action, events)
      result.add(action)
      # Clear grace period after enforcement
      let houseId = action.entity.houseId
      clearGracePeriod(state, houseId)
  else:
    logger.logDebug("Military", "No total squadron violations requiring enforcement")

proc canBuildSquadron*(state: GameState, houseId: HouseId, shipClass: ShipClass): bool =
  ## Check if house can build a new squadron of this type
  ## Returns false if house is at or over total squadron capacity
  ## Pure function - no mutations
  ##
  ## CRITICAL: Now includes ships under construction to prevent over-queuing

  # Auxiliary ships don't count toward limits
  if not isMilitarySquadron(shipClass):
    return true

  let violation = analyzeCapacity(state, houseId)
  let underConstruction = countTotalSquadronsUnderConstruction(state, houseId)

  # Check total capacity including both commissioned AND queued ships
  let atTotalCapacity = (violation.current + int32(underConstruction)) >= violation.maximum

  if capital_squadrons.isCapitalShip(shipClass):
    # Capital ships must check BOTH limits
    return not atTotalCapacity and capital_squadrons.canBuildCapitalShip(state, houseId)
  else:
    # Escorts only check total limit (now includes underConstruction)
    return not atTotalCapacity

## Design Notes:
##
## **Data-Oriented Pattern:**
## 1. analyzeCapacity() - Pure calculation of capacity status
## 2. checkViolations() - Batch analyze all houses (pure)
## 3. planEnforcement() - Pure function returns enforcement plan
## 4. applyEnforcement() - Explicit mutations apply the plan
## 5. processCapacityEnforcement() - Main batch processor
##
## **Key Differences from Capital Squadron System:**
## - Higher limit: IU/50 vs IU/100 (roughly 2x capital limit)
## - Includes escorts: All combat squadrons count
## - Escorts removed first: Prioritizes keeping expensive capitals
## - No salvage: Escorts just disband (smaller units)
## - Grace period: 2 turns vs 0 turns (more forgiving)
##
## **Relationship to Capital Squadron Limits:**
## - Total limit is OUTER bound, capital limit is INNER bound
## - Example: 1000 IU → 20 capitals max, 40 total max
## - Could have: 20 capitals + 20 escorts = 40 total
## - Could NOT have: 25 capitals (violates capital limit)
## - Could NOT have: 10 capitals + 35 escorts = 45 total (violates total limit)
##
## **Strategic Implications:**
## - Players must balance fleet composition
## - Can't spam infinite corvettes
## - Capitals take up total squadron "slots"
## - Encourages mixed fleets of quality + quantity
## - Industrial capacity drives fleet size
##
## **Integration Points:**
## - Call processCapacityEnforcement() in Maintenance phase (after capital squadron enforcement)
## - Call canBuildSquadron() before allowing construction orders
## - Enforcement happens AFTER economic resolution (IU changes applied)
