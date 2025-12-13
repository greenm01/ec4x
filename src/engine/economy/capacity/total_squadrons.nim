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
## - Includes ALL squadrons: capital ships, escorts, scouts, raiders
## - Excludes: fighters (separate per-colony limits), auxiliary (ETAC/TT)
##
## **Enforcement:**
## - 2-turn grace period for losing IU (gives time to adjust)
## - Priority removal: weakest escorts first (lowest AS), then damaged ships
## - No salvage value (escorts are smaller units, just disbanded)
##
## Data-oriented design: Calculate violations (pure) → plan enforcement → apply enforcement

import std/[tables, algorithm, options, strformat, strutils]
import ./types
import ../../gamestate
import ../../squadron
import ../types as econ_types
import ../../../common/types/core
import ../../../common/types/units
import ../../../common/logger
import ../../config/military_config
import ../../resolution/types as resolution_types  # For GameEvent
import ../../resolution/event_factory/fleet_ops  # For squadronDisbanded

export types.CapacityViolation, types.EnforcementAction, types.ViolationSeverity

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

proc isMilitarySquadron*(shipClass: ShipClass): bool =
  ## Check if a ship class counts toward total squadron limits
  ## Excludes: Auxiliary ships (ETAC, TT) - they're logistics, not combat squadrons
  ## Includes: All combat ships (escorts, capitals, special weapons)
  let ship = squadron.newEnhancedShip(shipClass, techLevel = 1)
  return ship.stats.role != ShipRole.Auxiliary

proc countTotalSquadronsInFleets*(state: GameState, houseId: core.HouseId): int =
  ## Count all military squadrons currently in fleets for a house
  ## Excludes auxiliary ships (ETAC, TT)
  result = 0
  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      for squadron in fleet.squadrons:
        if isMilitarySquadron(squadron.flagship.shipClass):
          result += 1

proc countTotalSquadronsUnderConstruction*(state: GameState,
                                            houseId: core.HouseId): int =
  ## Count total military squadrons currently under construction
  ## Includes both activeConstruction and queued projects in facilities
  ## Mirrors capital_squadrons.nim pattern but for all military ships
  result = 0

  for systemId, colony in state.colonies:
    if colony.owner != houseId:
      continue

    # Count from facility queues (Spaceports/Shipyards)
    for spaceport in colony.spaceports:
      # Count active constructions (multiple simultaneous projects per facility)
      for project in spaceport.activeConstructions:
        if project.projectType == econ_types.ConstructionType.Ship:
          try:
            let shipClass = parseEnum[ShipClass](project.itemId)
            if isMilitarySquadron(shipClass):
              result += 1
          except ValueError:
            discard  # Invalid ship class, skip

      # Count queued projects
      for project in spaceport.constructionQueue:
        if project.projectType == econ_types.ConstructionType.Ship:
          try:
            let shipClass = parseEnum[ShipClass](project.itemId)
            if isMilitarySquadron(shipClass):
              result += 1
          except ValueError:
            discard  # Invalid ship class, skip

    for shipyard in colony.shipyards:
      # Count active constructions (multiple simultaneous projects per facility)
      for project in shipyard.activeConstructions:
        if project.projectType == econ_types.ConstructionType.Ship:
          try:
            let shipClass = parseEnum[ShipClass](project.itemId)
            if isMilitarySquadron(shipClass):
              result += 1
          except ValueError:
            discard  # Invalid ship class, skip

      # Count queued projects
      for project in shipyard.constructionQueue:
        if project.projectType == econ_types.ConstructionType.Ship:
          try:
            let shipClass = parseEnum[ShipClass](project.itemId)
            if isMilitarySquadron(shipClass):
              result += 1
          except ValueError:
            discard  # Invalid ship class, skip

    # Also check legacy colony construction queue (backward compatibility)
    if colony.underConstruction.isSome:
      let project = colony.underConstruction.get()
      if project.projectType == econ_types.ConstructionType.Ship:
        try:
          let shipClass = parseEnum[ShipClass](project.itemId)
          if isMilitarySquadron(shipClass):
            result += 1
        except ValueError:
          discard  # Invalid ship class, skip

    for project in colony.constructionQueue:
      if project.projectType == econ_types.ConstructionType.Ship:
        try:
          let shipClass = parseEnum[ShipClass](project.itemId)
          if isMilitarySquadron(shipClass):
            result += 1
        except ValueError:
          discard  # Invalid ship class, skip

proc analyzeCapacity*(state: GameState, houseId: core.HouseId): types.CapacityViolation =
  ## Pure function - analyze house's total squadron capacity status
  ## Returns capacity analysis without mutating state

  let totalIU = state.getTotalHouseIndustrialUnits(houseId)
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
  var graceTurns = 0
  var severity = ViolationSeverity.None

  if excess > 0:
    # Check if grace period is active
    if houseId in state.gracePeriodTimers:
      let expiry = state.gracePeriodTimers[houseId].totalSquadronsExpiry
      if expiry > 0:
        # Grace period active
        graceTurns = max(0, expiry - state.turn)
        if graceTurns > 0:
          severity = ViolationSeverity.Warning  # Grace period active
        else:
          severity = ViolationSeverity.Critical  # Grace expired, enforce
      else:
        # No grace period set yet (will be set on first violation)
        severity = ViolationSeverity.Warning
        graceTurns = 2  # Will start 2-turn grace
    else:
      # First violation for this house
      severity = ViolationSeverity.Warning
      graceTurns = 2  # Will start 2-turn grace

  result = types.CapacityViolation(
    capacityType: CapacityType.TotalSquadron,
    entityId: $houseId,
    current: current,
    maximum: maximum,
    excess: excess,
    severity: severity,
    graceTurnsRemaining: graceTurns,
    violationTurn: state.turn
  )

proc startGracePeriod*(state: var GameState, houseId: core.HouseId) =
  ## Start or reset grace period for total squadron violations
  ## Explicit mutation - sets 2-turn grace period expiry
  if houseId notin state.gracePeriodTimers:
    state.gracePeriodTimers[houseId] = GracePeriodTracker(
      totalSquadronsExpiry: state.turn + 2,
      fighterCapacityExpiry: initTable[SystemId, int]()
    )
  else:
    # Update existing tracker, preserve fighter grace periods
    var tracker = state.gracePeriodTimers[houseId]
    tracker.totalSquadronsExpiry = state.turn + 2
    state.gracePeriodTimers[houseId] = tracker

proc clearGracePeriod*(state: var GameState, houseId: core.HouseId) =
  ## Clear grace period when capacity violation is resolved
  ## Explicit mutation - resets expiry to 0
  if houseId in state.gracePeriodTimers:
    var tracker = state.gracePeriodTimers[houseId]
    tracker.totalSquadronsExpiry = 0
    state.gracePeriodTimers[houseId] = tracker

proc checkViolations*(state: GameState): seq[types.CapacityViolation] =
  ## Batch check all houses for total squadron capacity violations
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
    isCapital: bool

proc prioritizeSquadronsForRemoval(state: GameState, houseId: core.HouseId): seq[SquadronPriority] =
  ## Determine priority order for removing squadrons
  ## Priority: 1) Non-capitals first (escorts), 2) Crippled ships, 3) Lowest AS
  ## Returns sorted list (highest priority first = first to remove)
  result = @[]

  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      for squadron in fleet.squadrons:
        if isMilitarySquadron(squadron.flagship.shipClass):
          result.add(SquadronPriority(
            squadronId: squadron.id,
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

proc planEnforcement*(state: GameState, violation: types.CapacityViolation): types.EnforcementAction =
  ## Plan enforcement actions for violations
  ## Pure function - returns enforcement plan without mutations
  ## Total squadrons: Auto-disband excess units (weakest escorts first, no salvage)

  result = types.EnforcementAction(
    capacityType: CapacityType.TotalSquadron,
    entityId: violation.entityId,
    actionType: "",
    affectedUnits: @[],
    description: ""
  )

  if violation.severity != ViolationSeverity.Critical:
    return

  let houseId = core.HouseId(violation.entityId)

  # Find all military squadrons for this house and prioritize for removal
  let priorities = prioritizeSquadronsForRemoval(state, houseId)

  # Select excess squadrons for disbanding (already sorted by priority)
  let toDisbandCount = min(violation.excess, priorities.len)
  result.actionType = "auto_disband"
  for i in 0 ..< toDisbandCount:
    result.affectedUnits.add(priorities[i].squadronId)

  result.description = $toDisbandCount & " squadron(s) auto-disbanded for " &
                      violation.entityId & " (exceeded total squadron capacity, IU loss)"

proc applyEnforcement*(state: var GameState, action: types.EnforcementAction,
                       events: var seq[resolution_types.GameEvent]) =
  ## Apply enforcement actions
  ## Explicit mutation - disbands excess squadrons
  ## Emits SquadronDisbanded events for tracking

  if action.actionType != "auto_disband" or action.affectedUnits.len == 0:
    return

  let houseId = core.HouseId(action.entityId)

  # Remove squadrons from fleets
  for fleetId, fleet in state.fleets.mpairs:
    if fleet.owner == houseId:
      var toRemove: seq[int] = @[]
      for idx, squadron in fleet.squadrons:
        if squadron.id in action.affectedUnits:
          toRemove.add(idx)
          logEconomy("Squadron auto-disbanded - total capacity exceeded",
                    "squadronId=", squadron.id,
                    " class=", $squadron.flagship.shipClass)

      # Remove squadrons (reverse order to maintain indices)
      for idx in toRemove.reversed:
        let squadron = fleet.squadrons[idx]

        # Emit SquadronDisbanded event
        events.add(fleet_ops.squadronDisbanded(
          houseId = houseId,
          squadronId = squadron.id,
          shipClass = squadron.flagship.shipClass,
          reason = "Total squadron capacity exceeded (IU loss)",
          systemId = fleet.location
        ))

        fleet.squadrons.delete(idx)

  logEconomy("Total squadron capacity enforcement complete",
            "house=", $houseId,
            " disbanded=", $action.affectedUnits.len)

proc processCapacityEnforcement*(state: var GameState,
                                events: var seq[resolution_types.GameEvent]): seq[types.EnforcementAction] =
  ## Main entry point - batch process all total squadron capacity violations
  ## Called during Income Phase (after IU loss from blockades/combat)
  ## Data-oriented: analyze all → manage grace periods → plan enforcement →
  ## apply enforcement
  ## Returns: List of enforcement actions that were actually applied

  result = @[]

  logDebug("Military", "Checking total squadron capacity")

  # Step 1: Check all houses for violations (pure)
  let violations = checkViolations(state)

  if violations.len == 0:
    logDebug("Military", "All houses within total squadron capacity limits")
    # Clear grace periods for houses with no violations
    for houseId in state.houses.keys:
      clearGracePeriod(state, houseId)
    return

  logDebug("Military", "Total squadron violations found", "count=",
          $violations.len)

  # Step 2: Manage grace periods and plan enforcement
  var enforcementActions: seq[types.EnforcementAction] = @[]
  for violation in violations:
    let houseId = core.HouseId(violation.entityId)

    if violation.severity == ViolationSeverity.Warning:
      # Start grace period if not already started
      startGracePeriod(state, houseId)
      logDebug("Military",
              &"House {houseId} over total squadron capacity, grace period " &
              &"active ({violation.graceTurnsRemaining} turns remaining)")
    elif violation.severity == ViolationSeverity.Critical:
      # Grace expired, enforce
      let action = planEnforcement(state, violation)
      if action.actionType == "auto_disband" and action.affectedUnits.len > 0:
        enforcementActions.add(action)

  # Step 3: Apply enforcement (mutations)
  if enforcementActions.len > 0:
    logEconomy("Enforcing total squadron capacity violations",
              "count=", $enforcementActions.len)
    for action in enforcementActions:
      applyEnforcement(state, action, events)
      result.add(action)
      # Clear grace period after enforcement
      let houseId = core.HouseId(action.entityId)
      clearGracePeriod(state, houseId)
  else:
    logDebug("Military", "No total squadron violations requiring enforcement")

proc canBuildSquadron*(state: GameState, houseId: core.HouseId, shipClass: ShipClass): bool =
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
  let atTotalCapacity = (violation.current + underConstruction) >= violation.maximum

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
