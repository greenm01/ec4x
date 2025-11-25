## AI Controller for Balance Testing
##
## Implements strategic decision-making for different AI personalities
## to enable realistic game simulations

import std/[tables, options, random, sequtils, strformat, algorithm, hashes]
import ../../src/engine/[gamestate, orders, fleet, squadron, starmap, fog_of_war, logger]
import ../../src/common/types/[core, units, tech, planets]
import ../../src/engine/espionage/types as esp_types
import ../../src/engine/research/types as res_types
import ../../src/engine/diplomacy/types as dip_types
import ../../src/engine/diplomacy/proposals as dip_proposals
import ../../src/engine/economy/construction

# Export FallbackRoute from gamestate for use in this module
export gamestate.FallbackRoute

type
  AIStrategy* {.pure.} = enum
    ## Different AI play styles for balance testing (12 max for max players)
    Aggressive,          # Heavy military, early attacks
    Economic,            # Focus on growth and tech
    Espionage,           # Intelligence and sabotage
    Diplomatic,          # Pacts and manipulation
    Balanced,            # Mixed approach
    Turtle,              # Defensive, slow expansion
    Expansionist,        # Rapid colonization
    TechRush,            # Maximum tech priority, minimal military
    Raider,              # Hit-and-run, harassment focus
    MilitaryIndustrial,  # Balanced military + economy
    Opportunistic,       # Flexible, adapts to circumstances
    Isolationist         # Minimal interaction, self-sufficient

  AIPersonality* = object
    aggression*: float       # 0.0-1.0: How likely to attack
    riskTolerance*: float    # 0.0-1.0: Willingness to take risks
    economicFocus*: float    # 0.0-1.0: Priority on economy vs military
    expansionDrive*: float   # 0.0-1.0: How aggressively to expand
    diplomacyValue*: float   # 0.0-1.0: Value placed on alliances
    techPriority*: float     # 0.0-1.0: Research investment priority

  IntelligenceReport* = object
    ## Intelligence gathered about a system
    systemId*: SystemId
    lastUpdated*: int         # Turn number of last intel
    hasColony*: bool          # Is system colonized?
    owner*: Option[HouseId]   # Who owns the colony?
    estimatedFleetStrength*: int  # Estimated military strength
    estimatedDefenses*: int   # Starbases, ground batteries
    planetClass*: Option[PlanetClass]
    resources*: Option[ResourceRating]
    confidenceLevel*: float   # 0.0-1.0: How reliable is this intel?

  OperationType* {.pure.} = enum
    ## Types of coordinated operations
    Invasion,      # Multi-fleet invasion of enemy colony
    Defense,       # Multiple fleets defending important system
    Raid,          # Quick strike with concentrated force
    Blockade       # Economic warfare with fleet support

  CoordinatedOperation* = object
    ## Planned multi-fleet operation
    operationType*: OperationType
    targetSystem*: SystemId
    assemblyPoint*: SystemId  # Where fleets rendezvous
    requiredFleets*: seq[FleetId]  # Fleets assigned to operation
    readyFleets*: seq[FleetId]     # Fleets that have arrived at assembly
    turnScheduled*: int            # When operation was planned
    executionTurn*: Option[int]    # When to execute (after assembly)

  StrategicReserve* = object
    ## Fleet designated as strategic reserve
    fleetId*: FleetId
    assignedTo*: Option[SystemId]  # System assigned to defend
    responseRadius*: int           # How far can respond (in jumps)

  AIController* = object
    houseId*: HouseId
    strategy*: AIStrategy
    personality*: AIPersonality
    lastTurnReport*: string  ## Previous turn's report for context
    intelligence*: Table[SystemId, IntelligenceReport]  ## Gathered intel on systems
    operations*: seq[CoordinatedOperation]  ## Planned multi-fleet operations
    reserves*: seq[StrategicReserve]        ## Strategic reserve fleets
    fallbackRoutes*: seq[FallbackRoute]     ## Phase 2h: Safe retreat routes

# =============================================================================
# Strategy Profiles
# =============================================================================

proc getStrategyPersonality*(strategy: AIStrategy): AIPersonality =
  ## Get personality parameters for a strategy
  case strategy
  of AIStrategy.Aggressive:
    AIPersonality(
      aggression: 0.9,
      riskTolerance: 0.8,
      economicFocus: 0.5,  # Increased from 0.3 - prevents military build starvation of ETACs
      expansionDrive: 0.8,  # Aggressive expansion, then pivot to conquest
      diplomacyValue: 0.2,
      techPriority: 0.4
    )
  of AIStrategy.Economic:
    AIPersonality(
      aggression: 0.3,  # Increased from 0.2 - needs basic defense capability
      riskTolerance: 0.3,
      economicFocus: 0.9,
      expansionDrive: 0.5,
      diplomacyValue: 0.6,
      techPriority: 0.8
    )
  of AIStrategy.Espionage:
    AIPersonality(
      aggression: 0.5,
      riskTolerance: 0.6,
      economicFocus: 0.5,
      expansionDrive: 0.65,  # Increased from 0.4 - aggressive expansion even with spy focus
      diplomacyValue: 0.4,
      techPriority: 0.6
    )
  of AIStrategy.Diplomatic:
    AIPersonality(
      aggression: 0.3,
      riskTolerance: 0.4,
      economicFocus: 0.6,
      expansionDrive: 0.5,
      diplomacyValue: 0.9,
      techPriority: 0.5
    )
  of AIStrategy.Balanced:
    AIPersonality(
      aggression: 0.4,       # Defensive but reactive - won't overcommit to military
      riskTolerance: 0.5,    # Moderate - calculated risks
      economicFocus: 0.7,    # Economic foundation first (like Turtle)
      expansionDrive: 0.5,   # Controlled expansion (same as Aggressive/Economic)
      diplomacyValue: 0.6,   # Can leverage alliances when beneficial
      techPriority: 0.5      # Keeps up but doesn't prioritize
    )
  of AIStrategy.Turtle:
    AIPersonality(
      aggression: 0.1,       # Stay defensive - only fight when necessary
      riskTolerance: 0.3,    # Increased from 0.2 - willing to expand into safe areas
      economicFocus: 0.7,    # Keep high economic focus
      expansionDrive: 0.4,   # Increased from 0.2 - "defensive expansion" not "no expansion"
      diplomacyValue: 0.7,   # Keep high diplomacy for safety
      techPriority: 0.7      # Keep high tech priority
    )
  of AIStrategy.Expansionist:
    AIPersonality(
      aggression: 0.6,
      riskTolerance: 0.7,
      economicFocus: 0.4,
      expansionDrive: 0.95,
      diplomacyValue: 0.3,
      techPriority: 0.3
    )
  of AIStrategy.TechRush:
    AIPersonality(
      aggression: 0.2,  # Minimal military early
      riskTolerance: 0.4,
      economicFocus: 0.8,  # Strong economy to fund research
      expansionDrive: 0.4,  # Moderate expansion for research facilities
      diplomacyValue: 0.7,  # Need allies for protection
      techPriority: 0.95  # Maximum tech investment
    )
  of AIStrategy.Raider:
    AIPersonality(
      aggression: 0.85,  # Very aggressive
      riskTolerance: 0.9,  # High risk, high reward
      economicFocus: 0.4,  # Moderate economy
      expansionDrive: 0.6,  # Expand to find targets
      diplomacyValue: 0.1,  # Minimal diplomacy
      techPriority: 0.5  # Need tech for fast ships
    )
  of AIStrategy.MilitaryIndustrial:
    AIPersonality(
      aggression: 0.7,  # Aggressive but calculated
      riskTolerance: 0.5,  # Moderate risk
      economicFocus: 0.75,  # Strong industrial base
      expansionDrive: 0.6,  # Expand for resources
      diplomacyValue: 0.3,  # Minimal diplomacy
      techPriority: 0.6  # Need tech for advanced weapons
    )
  of AIStrategy.Opportunistic:
    AIPersonality(
      aggression: 0.5,  # Flexible - attack when advantageous
      riskTolerance: 0.6,  # Willing to take calculated risks
      economicFocus: 0.6,  # Balanced economy
      expansionDrive: 0.6,  # Expand opportunistically
      diplomacyValue: 0.5,  # Use diplomacy when beneficial
      techPriority: 0.5  # Balanced tech investment
    )
  of AIStrategy.Isolationist:
    AIPersonality(
      aggression: 0.15,  # Defensive only
      riskTolerance: 0.2,  # Very risk-averse
      economicFocus: 0.85,  # Maximum self-sufficiency
      expansionDrive: 0.3,  # Minimal expansion
      diplomacyValue: 0.2,  # Avoid entanglements
      techPriority: 0.75  # Tech for defense & efficiency
    )

proc newAIController*(houseId: HouseId, strategy: AIStrategy): AIController =
  ## Create a new AI controller for a house
  AIController(
    houseId: houseId,
    strategy: strategy,
    personality: getStrategyPersonality(strategy),
    intelligence: initTable[SystemId, IntelligenceReport](),
    operations: @[],
    reserves: @[],
    fallbackRoutes: @[]
  )

proc newAIControllerWithPersonality*(houseId: HouseId, personality: AIPersonality): AIController =
  ## Create a new AI controller with a custom personality (for genetic algorithm)
  AIController(
    houseId: houseId,
    strategy: AIStrategy.Balanced,  # Strategy field is unused with custom personality
    personality: personality,
    intelligence: initTable[SystemId, IntelligenceReport](),
    operations: @[],
    reserves: @[],
    fallbackRoutes: @[]
  )

# =============================================================================
# Helper Functions
# =============================================================================

proc isSystemColonized(filtered: FilteredGameState, systemId: SystemId): bool =
  ## Check if a system is colonized (own or visible enemy colony)
  ## RESPECTS FOG-OF-WAR: Only checks known colonies
  for colony in filtered.ownColonies:
    if colony.systemId == systemId:
      return true
  for visCol in filtered.visibleColonies:
    if visCol.systemId == systemId:
      return true
  return false

proc getColony(filtered: FilteredGameState, systemId: SystemId): Option[Colony] =
  ## Get colony by system ID (only own colonies with full details)
  ## RESPECTS FOG-OF-WAR: Returns none for enemy colonies
  for colony in filtered.ownColonies:
    if colony.systemId == systemId:
      return some(colony)
  return none(Colony)

proc getOwnedColonies(filtered: FilteredGameState, houseId: HouseId): seq[Colony] =
  ## Get all colonies owned by a house
  ## RESPECTS FOG-OF-WAR: Only returns own colonies
  if houseId != filtered.viewingHouse:
    return @[]  # Can't see other houses' colonies
  return filtered.ownColonies

proc getOwnedFleets(filtered: FilteredGameState, houseId: HouseId): seq[Fleet] =
  ## Get all fleets owned by a house
  ## RESPECTS FOG-OF-WAR: Only returns own fleets
  if houseId != filtered.viewingHouse:
    return @[]  # Can't see other houses' fleets
  return filtered.ownFleets

proc getFleetStrength(fleet: Fleet): int =
  ## Calculate total attack strength of a fleet
  result = 0
  for squadron in fleet.squadrons:
    result += squadron.combatStrength()

proc isSingleScoutSquadron(squadron: Squadron): bool =
  ## Check if squadron is a single scout (ideal for espionage)
  ## Phase 2c: Scout Operational Modes
  result = squadron.flagship.shipClass == ShipClass.Scout and squadron.ships.len == 0

proc countScoutsInFleet(fleet: Fleet): int =
  ## Count total scouts in a fleet (for ELI mesh calculation)
  ## Phase 2c: Scout Operational Modes
  result = 0
  for squadron in fleet.squadrons:
    if squadron.flagship.shipClass == ShipClass.Scout:
      result += 1  # Flagship
    for ship in squadron.ships:
      if ship.shipClass == ShipClass.Scout:
        result += 1

proc getAvailableSingleScouts(filtered: FilteredGameState, houseId: HouseId): seq[Fleet] =
  ## Get all single-scout fleets available for espionage missions
  ## Phase 2c: Scout Operational Modes
  ## RESPECTS FOG-OF-WAR: Only returns own fleets
  result = @[]
  for fleet in filtered.ownFleets:
    if fleet.owner == houseId and fleet.squadrons.len == 1:
      if isSingleScoutSquadron(fleet.squadrons[0]):
        result.add(fleet)

proc findNearestUncolonizedSystem(filtered: FilteredGameState, fromSystem: SystemId, fleetId: FleetId): Option[SystemId] =
  ## Find nearest uncolonized system using cube distance
  ## Returns closest uncolonized system to avoid all AIs targeting the same one
  ## EXPLORATION: Considers ALL systems (players know the star map exists)
  ## Only colonization status is checked (not visible due to fog-of-war)
  ## NOTE: "uncolonized" includes UNKNOWN systems - fog-of-war means we don't know if they're colonized
  ## ETACs will discover on arrival if a system is already taken (realistic exploration)
  type SystemDist = tuple[systemId: SystemId, distance: int]
  var candidates: seq[SystemDist] = @[]

  let fromCoords = filtered.starMap.systems[fromSystem].coords

  for systemId, system in filtered.starMap.systems:
    # Check ALL systems on the map (exploration discovers what's there)
    # Don't restrict to visibleSystems - that prevents exploration!
    # In classic EC, you could see the star map and send fleets anywhere
    if not isSystemColonized(filtered, systemId):
      # Not colonized = either truly empty OR unknown (fog-of-war)
      # Calculate cube distance (Manhattan distance in hex coordinates)
      let dx = abs(system.coords.q - fromCoords.q)
      let dy = abs(system.coords.r - fromCoords.r)
      let dz = abs((system.coords.q + system.coords.r) - (fromCoords.q + fromCoords.r))
      let distance = (dx + dy + dz) div 2
      let item: SystemDist = (systemId: systemId, distance: distance)
      candidates.add(item)

  if candidates.len > 0:
    # Sort by distance
    candidates.sort(proc(a, b: SystemDist): int = cmp(a.distance, b.distance))

    # Use fleetId hash to get consistent but unique selection per fleet
    # This prevents all ETAC fleets from targeting the same system
    let minDistance = candidates[0].distance
    var closestSystems: seq[SystemId] = @[]
    for candidate in candidates:
      if candidate.distance == minDistance:
        closestSystems.add(candidate.systemId)
      else:
        break  # candidates sorted by distance, so we're done

    if closestSystems.len > 1:
      # Multiple systems at same distance - use fleet ID hash for deterministic but unique selection
      let fleetHash = hash(fleetId)
      # Use bitwise AND to ensure positive value (avoid abs() overflow at int.low)
      let selectedIdx = (fleetHash and 0x7FFFFFFF) mod closestSystems.len
      return some(closestSystems[selectedIdx])
    else:
      return some(closestSystems[0])

  return none(SystemId)

proc findWeakestEnemyColony(filtered: FilteredGameState, houseId: HouseId, rng: var Rand): Option[SystemId] =
  ## Find an enemy colony to attack (prefer weaker targets)
  ## RESPECTS FOG-OF-WAR: Only considers visible enemy colonies
  var targets: seq[tuple[systemId: SystemId, strength: int]] = @[]

  # Check visible enemy colonies
  for visCol in filtered.visibleColonies:
    if visCol.owner != houseId:
      # Calculate defensive strength from intel (may be incomplete)
      let defenseStr = visCol.estimatedDefenses.get(0)
      targets.add((visCol.systemId, defenseStr))

  if targets.len > 0:
    # Sort by strength (weakest first)
    targets.sort(proc(a, b: auto): int = cmp(a.strength, b.strength))
    return some(targets[0].systemId)

  return none(SystemId)

# =============================================================================
# Intelligence Gathering
# =============================================================================

proc updateIntelligence*(controller: var AIController, filtered: FilteredGameState, systemId: SystemId,
                         turn: int, confidenceLevel: float = 1.0) =
  ## Update intelligence report for a system
  ## Called when scouts gather intel or when we have direct visibility
  ## RESPECTS FOG-OF-WAR: Updates based on visible/scouted information
  var report = IntelligenceReport(
    systemId: systemId,
    lastUpdated: turn,
    hasColony: isSystemColonized(filtered, systemId),
    confidenceLevel: confidenceLevel
  )

  if report.hasColony:
    # Check if it's our colony (full details)
    var foundOwn = false
    for colony in filtered.ownColonies:
      if colony.systemId == colony.systemId:
        report.owner = some(colony.owner)
        report.planetClass = some(colony.planetClass)
        report.resources = some(colony.resources)
        report.estimatedDefenses = colony.starbases.len * 10 + colony.groundBatteries * 5
        foundOwn = true
        break

    # Otherwise check visible enemy colonies (limited intel)
    if not foundOwn:
      for visCol in filtered.visibleColonies:
        if visCol.systemId == systemId:
          report.owner = some(visCol.owner)
          report.planetClass = visCol.planetClass
          report.resources = visCol.resources
          report.estimatedDefenses = visCol.estimatedDefenses.get(0)
          break

  # Estimate fleet strength at this system (only visible fleets)
  var totalStrength = 0
  for fleet in filtered.ownFleets:
    if fleet.location == systemId:
      for squadron in fleet.squadrons:
        totalStrength += squadron.combatStrength()
  for visFleet in filtered.visibleFleets:
    if visFleet.location == systemId:
      # Rough estimate based on ship count
      totalStrength += visFleet.estimatedShipCount.get(0) * 20

  report.estimatedFleetStrength = totalStrength

  controller.intelligence[systemId] = report

proc getIntelAge*(controller: AIController, systemId: SystemId, currentTurn: int): Option[int] =
  ## Get how many turns old our intelligence is for a system
  if systemId in controller.intelligence:
    return some(currentTurn - controller.intelligence[systemId].lastUpdated)
  return none(int)

proc needsReconnaissance*(controller: AIController, systemId: SystemId, currentTurn: int): bool =
  ## Check if a system needs reconnaissance
  ## Returns true if we have no intel or intel is stale (>5 turns old)
  if systemId notin controller.intelligence:
    return true

  let age = currentTurn - controller.intelligence[systemId].lastUpdated
  return age > 5  # Intel becomes stale after 5 turns

proc findBestColonizationTarget*(controller: var AIController, filtered: FilteredGameState,
                                  fromSystem: SystemId, fleetId: FleetId): Option[SystemId] =
  ## Find best colonization target using intelligence
  ## Prioritizes: Eden/Abundant > Strategic > Nearby > Unknown
  ## NOTE: "uncolonized" includes UNKNOWN systems - fog-of-war means we don't know if they're colonized
  ## ETACs will discover on arrival if a system is already taken (realistic exploration)
  type TargetScore = tuple[systemId: SystemId, score: float, distance: int]
  var candidates: seq[TargetScore] = @[]

  let fromCoords = filtered.starMap.systems[fromSystem].coords

  for systemId, system in filtered.starMap.systems:
    if not isSystemColonized(filtered, systemId):
      # Not colonized = either truly empty OR unknown (fog-of-war)
      var score = 0.0

      # Calculate distance
      let dx = abs(system.coords.q - fromCoords.q)
      let dy = abs(system.coords.r - fromCoords.r)
      let dz = abs((system.coords.q + system.coords.r) - (fromCoords.q + fromCoords.r))
      let distance = (dx + dy + dz) div 2

      # Distance penalty (prefer nearby, but not overwhelmingly)
      score -= float(distance) * 0.5

      # Use intelligence if available
      if systemId in controller.intelligence:
        let intel = controller.intelligence[systemId]

        # Planet quality bonus (per spec: Extreme/Desolate/Hostile/Harsh/Benign/Lush/Eden)
        if intel.planetClass.isSome:
          case intel.planetClass.get()
          of PlanetClass.Eden:
            score += 25.0  # Highest priority (Level VII: 2k+ PU)
          of PlanetClass.Lush:
            score += 20.0  # Level VI: 1k-2k PU
          of PlanetClass.Benign:
            score += 15.0  # Level V: 501-1000 PU
          of PlanetClass.Harsh:
            score += 10.0  # Level IV: 181-500 PU
          of PlanetClass.Hostile:
            score += 5.0   # Level III: 61-180 PU
          of PlanetClass.Desolate:
            score += 2.0   # Level II: 21-60 PU
          of PlanetClass.Extreme:
            score += 1.0   # Level I: 1-20 PU (still colonize if close)

        # Resource bonus
        if intel.resources.isSome:
          case intel.resources.get()
          of ResourceRating.VeryRich:
            score += 20.0  # Exceptional resources
          of ResourceRating.Rich:
            score += 15.0  # Excellent resources
          of ResourceRating.Abundant:
            score += 10.0  # Good resources
          of ResourceRating.Poor:
            score += 3.0   # Minimal resources
          of ResourceRating.VeryPoor:
            score += 0.0   # Worst resources

        # Confidence modifier (prefer systems we've scouted)
        score *= intel.confidenceLevel
      else:
        # Unknown system - small bonus for exploration
        score += 2.0

      let item: TargetScore = (systemId: systemId, score: score, distance: distance)
      candidates.add(item)

  if candidates.len > 0:
    # Sort by score (highest first)
    candidates.sort(proc(a, b: TargetScore): int =
      if b.score > a.score: 1
      elif b.score < a.score: -1
      else: 0
    )

    # Use fleetId hash to get consistent but unique selection per fleet
    # This prevents all ETAC fleets from targeting the same system
    let maxScore = candidates[0].score
    var topSystems: seq[SystemId] = @[]
    for candidate in candidates:
      if candidate.score == maxScore:
        topSystems.add(candidate.systemId)
      else:
        break  # candidates sorted by score, so we're done

    if topSystems.len > 1:
      # Multiple systems with same score - use fleet ID hash for deterministic but unique selection
      let fleetHash = hash(fleetId)
      let selectedIdx = abs(fleetHash) mod topSystems.len
      return some(topSystems[selectedIdx])
    else:
      return some(topSystems[0])

  return none(SystemId)

# =============================================================================
# Fleet Coordination
# =============================================================================

proc planCoordinatedOperation*(controller: var AIController, filtered: FilteredGameState,
                                opType: OperationType, target: SystemId,
                                fleets: seq[FleetId], assembly: SystemId, turn: int) =
  ## Plan a multi-fleet coordinated operation
  let operation = CoordinatedOperation(
    operationType: opType,
    targetSystem: target,
    assemblyPoint: assembly,
    requiredFleets: fleets,
    readyFleets: @[],
    turnScheduled: turn,
    executionTurn: none(int)
  )
  controller.operations.add(operation)

proc updateOperationStatus*(controller: var AIController, filtered: FilteredGameState) =
  ## Update status of ongoing coordinated operations
  ## Check which fleets have arrived at assembly points
  for op in controller.operations.mitems:
    op.readyFleets.setLen(0)  # Reset ready fleets
    for fleetId in op.requiredFleets:
      # Find fleet in ownFleets
      for fleet in filtered.ownFleets:
        if fleet.id == fleetId:
          if fleet.location == op.assemblyPoint:
            op.readyFleets.add(fleetId)
          break

    # If all fleets ready and not yet executed, set execution for next turn
    if op.readyFleets.len == op.requiredFleets.len and op.executionTurn.isNone:
      op.executionTurn = some(filtered.turn + 1)

proc shouldExecuteOperation*(controller: AIController, op: CoordinatedOperation, turn: int): bool =
  ## Check if operation should execute this turn
  if op.executionTurn.isSome and op.executionTurn.get() <= turn:
    return op.readyFleets.len == op.requiredFleets.len
  return false

proc removeCompletedOperations*(controller: var AIController, turn: int) =
  ## Remove operations that are too old or completed
  controller.operations = controller.operations.filterIt(
    it.executionTurn.isNone or it.executionTurn.get() >= turn - 2
  )

proc identifyImportantColonies*(controller: AIController, filtered: FilteredGameState): seq[SystemId] =
  ## Identify colonies that need defense-in-depth
  ## Important = high production OR strategic resources
  ##
  ## **Thresholds (Phase 2f - adjusted for early-game relevance):**
  ## - Production >= 30 PU/turn (lowered from 50 for mid-game industrial centers)
  ## - Resources: Rich/VeryRich/Abundant (strategic value)
  ##
  ## **Rationale:** Early game colonies produce ~40-45 PU/turn. The old threshold
  ## of 50 meant NO colonies qualified as "important" in early game, causing the
  ## proactive defense logic to never trigger. Lowering to 30 ensures medium+
  ## production colonies get defended.
  result = @[]
  for colony in filtered.ownColonies:
    if colony.owner == controller.houseId:
      # Medium+ production colonies (lowered from 50 to 30 for early-game relevance)
      if colony.production >= 30:
        result.add(colony.systemId)
      # Abundant/Rich resource colonies (strategic value)
      elif colony.resources in [ResourceRating.Rich, ResourceRating.VeryRich, ResourceRating.Abundant]:
        result.add(colony.systemId)

proc assignStrategicReserve*(controller: var AIController, fleetId: FleetId,
                              assignedSystem: Option[SystemId], radius: int = 3) =
  ## Designate a fleet as strategic reserve
  let reserve = StrategicReserve(
    fleetId: fleetId,
    assignedTo: assignedSystem,
    responseRadius: radius
  )
  controller.reserves.add(reserve)

proc updateFallbackRoutes*(controller: var AIController, filtered: FilteredGameState) =
  ## Phase 2h: Update fallback/retreat routes for all colonies
  ## Call this periodically to refresh safe retreat destinations
  ## RESPECTS FOG-OF-WAR: Uses visible systems and intelligence

  let myColonies = getOwnedColonies(filtered, controller.houseId)
  if myColonies.len == 0:
    return

  # Clear stale routes (>20 turns old)
  controller.fallbackRoutes = controller.fallbackRoutes.filterIt(
    filtered.turn - it.lastUpdated < 20
  )

  # For each colony, find nearest safe colony as fallback
  for colony in myColonies:
    # Skip if we already have a recent route for this region
    var hasRecentRoute = false
    for route in controller.fallbackRoutes:
      if route.region == colony.systemId and filtered.turn - route.lastUpdated < 10:
        hasRecentRoute = true
        break

    if hasRecentRoute:
      continue

    # Find nearest safe colony (not under threat)
    var bestFallback: Option[SystemId] = none(SystemId)
    var minDist = 999

    for otherColony in myColonies:
      if otherColony.systemId == colony.systemId:
        continue

      # Check if destination is safe (has starbase or strong fleet presence)
      var isSafe = otherColony.starbases.len > 0
      if not isSafe:
        var fleetStrength = 0
        for fleet in filtered.ownFleets:
          if fleet.owner == controller.houseId and fleet.location == otherColony.systemId:
            fleetStrength += fleet.squadrons.len
        isSafe = fleetStrength >= 2

      # Skip if destination isn't safe
      if not isSafe:
        continue

      # Check if path to destination avoids hostile territory
      let dummyFleet = Fleet(
        id: "temp",
        owner: controller.houseId,
        location: colony.systemId,
        squadrons: @[],
        spaceLiftShips: @[],
        status: FleetStatus.Active
      )

      let pathResult = filtered.starMap.findPath(colony.systemId, otherColony.systemId, dummyFleet)
      if pathResult.path.len == 0:
        continue  # No valid path

      # Verify path doesn't go through enemy systems
      var pathIsSafe = true
      for pathSystemId in pathResult.path:
        if pathSystemId != colony.systemId and isSystemColonized(filtered, pathSystemId):
          let pathColonyOpt = getColony(filtered, pathSystemId)
          if pathColonyOpt.isSome:
            let pathColony = pathColonyOpt.get()
            if pathColony.owner != controller.houseId:
              # Check diplomatic status
              let house = filtered.ownHouse
              if house.diplomaticRelations.isEnemy(pathColony.owner):
                pathIsSafe = false
                break

      if not pathIsSafe:
        continue  # Skip routes through enemy territory

      # Calculate actual pathfinding distance (safer than hex distance)
      let dist = pathResult.path.len - 1

      if dist < minDist:
        minDist = dist
        bestFallback = some(otherColony.systemId)

    # Add or update fallback route
    if bestFallback.isSome:
      # Remove old route for this region
      controller.fallbackRoutes = controller.fallbackRoutes.filterIt(
        it.region != colony.systemId
      )
      # Add new route
      controller.fallbackRoutes.add(FallbackRoute(
        region: colony.systemId,
        fallbackSystem: bestFallback.get(),
        lastUpdated: filtered.turn
      ))

proc syncFallbackRoutesToEngine*(controller: AIController, state: var GameState) =
  ## Sync AI controller's fallback routes to engine's House state
  ## This allows engine's automatic seek-home behavior to use AI-planned routes
  if controller.houseId in state.houses:
    state.houses[controller.houseId].fallbackRoutes = controller.fallbackRoutes

proc findFallbackSystem*(controller: AIController, currentSystem: SystemId): Option[SystemId] =
  ## Phase 2h: Find designated fallback system for a region
  for route in controller.fallbackRoutes:
    if route.region == currentSystem:
      return some(route.fallbackSystem)
  return none(SystemId)

proc getReserveForSystem*(controller: AIController, systemId: SystemId): Option[FleetId] =
  ## Get strategic reserve assigned to defend a system
  for reserve in controller.reserves:
    if reserve.assignedTo.isSome and reserve.assignedTo.get() == systemId:
      return some(reserve.fleetId)
  return none(FleetId)

proc assessRelativeStrength*(controller: AIController, filtered: FilteredGameState, targetHouse: HouseId): float =
  ## Phase 2i: Assess relative strength of a house (0.0 = weakest, 1.0 = strongest)
  ## RESPECTS FOG-OF-WAR: Only uses public information (prestige) and visible/intel data
  ## NOTE: Prestige is public information (like a scoreboard)
  if targetHouse notin filtered.housePrestige:
    return 0.5  # Unknown strength

  let targetPrestige = filtered.housePrestige[targetHouse]
  let myHouse = filtered.ownHouse

  # Calculate strength factors
  var targetStrength = 0.0
  var myStrength = 0.0

  # Prestige weight: 50% (PUBLIC INFORMATION - always visible)
  targetStrength += targetPrestige.float * 0.5
  myStrength += myHouse.prestige.float * 0.5

  # Known colony count weight: 30% (from intelligence database + visible)
  var targetKnownColonies = 0
  let myColonies = filtered.ownColonies.len

  # Target colonies (only count from intelligence database - respects fog-of-war)
  for systemId, colonyReport in myHouse.intelligence.colonyReports:
    if colonyReport.targetOwner == targetHouse:
      targetKnownColonies += 1

  targetStrength += targetKnownColonies.float * 20.0 * 0.3
  myStrength += myColonies.float * 20.0 * 0.3

  # Visible fleet strength weight: 20% (only fleets we can see - respects fog-of-war)
  var myFleets = 0

  # Count my own fleet strength (perfect knowledge)
  for fleet in filtered.ownFleets:
    myFleets += fleet.combatStrength()

  # Enemy fleets - can only estimate based on detected presence
  # NOTE: We don't have detailed combat strength from intel, so estimate conservatively
  # Assume average detected fleet has ~100 combat strength (rough estimate)
  var targetEstimatedFleetCount = 0
  for systemId, systemReport in myHouse.intelligence.systemReports:
    for detectedFleet in systemReport.detectedFleets:
      if detectedFleet.owner == targetHouse:
        targetEstimatedFleetCount += 1

  let estimatedFleetStrength = targetEstimatedFleetCount * 100  # Rough estimate
  targetStrength += estimatedFleetStrength.float * 0.2
  myStrength += myFleets.float * 0.2

  # Return relative strength (target vs me)
  # NOTE: This is an ESTIMATE based on incomplete information
  if myStrength == 0:
    return 1.0  # Assume target is stronger if we have no strength
  return targetStrength / (targetStrength + myStrength)

proc identifyVulnerableTargets*(controller: var AIController, filtered: FilteredGameState): seq[tuple[systemId: SystemId, owner: HouseId, relativeStrength: float]] =
  ## Phase 2i: Identify colonies owned by weaker players
  ## Returns targets sorted by vulnerability (weakest first)
  ## RESPECTS FOG-OF-WAR: Only considers visible enemy colonies
  result = @[]

  # Check visible enemy colonies from fog-of-war view
  for visCol in filtered.visibleColonies:
    if visCol.owner == controller.houseId:
      continue

    # Assess relative strength of colony owner
    let strength = controller.assessRelativeStrength(filtered, visCol.owner)

    # Prefer targets that are weaker than us (strength < 0.5)
    # But also consider targets slightly stronger if valuable
    result.add((visCol.systemId, visCol.owner, strength))

  # Sort by relative strength (weakest first)
  result.sort(proc(a, b: auto): int = cmp(a.relativeStrength, b.relativeStrength))

proc identifyInvasionOpportunities*(controller: var AIController, filtered: FilteredGameState): seq[SystemId] =
  ## Identify enemy colonies that warrant coordinated invasion
  ## Phase 2i: Now prioritizes weaker players instead of strongest
  ## Criteria: valuable target, requires multiple fleets, within reach
  result = @[]

  # Get vulnerable targets (weakest players first)
  let vulnerableTargets = controller.identifyVulnerableTargets(filtered)

  for target in vulnerableTargets:
    let systemId = target.systemId
    let colonyOpt = getColony(filtered, systemId)
    if colonyOpt.isNone:
      continue  # Can't invade a system we can't see
    let colony = colonyOpt.get()

    # Estimate defense strength (ground forces + starbase + nearby fleets)
    var defenseStrength = 0
    if colony.starbases.len > 0:
      defenseStrength += 100 * colony.getOperationalStarbaseCount()  # Each starbase adds significant defense

    # Check for defending fleets
    for fleet in filtered.ownFleets:
      if fleet.owner == colony.owner and fleet.location == systemId:
        defenseStrength += fleet.combatStrength()

    # High-value targets (production >= 50 or rich resources)
    let isValuable = colony.production >= 50 or
                     colony.resources in [ResourceRating.Rich, ResourceRating.VeryRich]

    # Prefer weaker targets (relative strength < 0.4) for easier victories
    # Or stronger targets if very valuable AND we're strong enough
    let preferTarget = (target.relativeStrength < 0.4) or
                       (isValuable and target.relativeStrength < 0.6)

    # Invade weak or moderately defended targets
    # Early game: defense < 50, mid-game: defense 50-150, late game: attack anything
    if preferTarget and defenseStrength < 200:
      result.add(systemId)

proc countAvailableFleets*(controller: AIController, filtered: FilteredGameState): int =
  ## Count fleets not currently in operations
  result = 0
  for fleet in filtered.ownFleets:
    if fleet.owner != controller.houseId:
      continue

    # Check if fleet is already in an operation
    var inOperation = false
    for op in controller.operations:
      if fleet.id in op.requiredFleets:
        inOperation = true
        break

    if not inOperation and fleet.combatStrength() > 0:
      result += 1

proc planCoordinatedInvasion*(controller: var AIController, filtered: FilteredGameState,
                                target: SystemId, turn: int) =
  ## Plan multi-fleet invasion of a high-value target
  ## Assembles at nearby friendly system, then attacks together

  # Find nearby friendly system as assembly point
  var assemblyPoint: Option[SystemId] = none(SystemId)
  var minDist = 999

  let targetCoords = filtered.starMap.systems[target].coords

  for colony in filtered.ownColonies:
    if colony.owner != controller.houseId:
      continue

    let coords = filtered.starMap.systems[colony.systemId].coords
    let dx = abs(coords.q - targetCoords.q)
    let dy = abs(coords.r - targetCoords.r)
    let dz = abs((coords.q + coords.r) - (targetCoords.q + targetCoords.r))
    let dist = (dx + dy + dz) div 2

    if dist < minDist and dist > 0:
      minDist = dist
      assemblyPoint = some(colony.systemId)

  if assemblyPoint.isNone:
    return

  # Identify fleets for invasion force (need 2-3 combat fleets)
  var selectedFleets: seq[FleetId] = @[]
  var scoutFleets: seq[FleetId] = @[]  # Phase 2c: ELI mesh support

  for fleet in filtered.ownFleets:
    if fleet.owner == controller.houseId:
      # Skip fleets already in operations
      var inOperation = false
      for op in controller.operations:
        if fleet.id in op.requiredFleets:
          inOperation = true
          break

      if not inOperation:
        # Collect combat fleets
        if fleet.combatStrength() > 0:
          selectedFleets.add(fleet.id)
          if selectedFleets.len >= 3:
            break
        # Phase 2c: Collect single scouts for ELI mesh (need 3+ for mesh network)
        elif fleet.squadrons.len == 1 and isSingleScoutSquadron(fleet.squadrons[0]):
          if scoutFleets.len < 4:  # Up to 4 scouts for strong ELI mesh
            scoutFleets.add(fleet.id)

  # Phase 2c: Add scouts to invasion force for ELI mesh
  # Per specs: 3+ scouts form mesh network with magnified ELI capability
  if selectedFleets.len >= 2:
    selectedFleets.add(scoutFleets)  # Append scout fleets to invasion force
    controller.planCoordinatedOperation(
      filtered,
      OperationType.Invasion,
      target,
      selectedFleets,
      assemblyPoint.get(),
      turn
    )

proc manageStrategicReserves*(controller: var AIController, filtered: FilteredGameState) =
  ## Assign fleets as strategic reserves for important colonies
  ## Defense-in-depth: keep reserves positioned near key systems

  let importantSystems = controller.identifyImportantColonies(filtered)

  # Assign one reserve per important system (if available)
  for systemId in importantSystems:
    if controller.getReserveForSystem(systemId).isSome:
      continue  # Already has reserve

    # Find nearby idle fleet
    let systemCoords = filtered.starMap.systems[systemId].coords
    var bestFleet: Option[FleetId] = none(FleetId)
    var minDist = 999

    for fleet in filtered.ownFleets:
      if fleet.owner != controller.houseId or fleet.combatStrength() == 0:
        continue

      # Check if already assigned as reserve
      var isReserve = false
      for reserve in controller.reserves:
        if reserve.fleetId == fleet.id:
          isReserve = true
          break

      if isReserve:
        continue

      # Check distance
      let fleetCoords = filtered.starMap.systems[fleet.location].coords
      let dx = abs(fleetCoords.q - systemCoords.q)
      let dy = abs(fleetCoords.r - systemCoords.r)
      let dz = abs((fleetCoords.q + fleetCoords.r) - (systemCoords.q + systemCoords.r))
      let dist = (dx + dy + dz) div 2

      if dist < minDist and dist <= 3:
        minDist = dist
        bestFleet = some(fleet.id)

    if bestFleet.isSome:
      controller.assignStrategicReserve(bestFleet.get(), some(systemId), 3)

proc respondToThreats*(controller: var AIController, filtered: FilteredGameState): seq[tuple[reserveFleet: FleetId, threatSystem: SystemId]] =
  ## Check for enemy fleets near protected systems and return reserve/threat pairs
  ## Strategic reserves should move to intercept nearby threats
  result = @[]

  for reserve in controller.reserves:
    if reserve.assignedTo.isNone:
      continue

    let protectedSystem = reserve.assignedTo.get()
    let protectedCoords = filtered.starMap.systems[protectedSystem].coords

    # Look for enemy fleets within response radius
    for fleet in filtered.ownFleets:
      if fleet.owner == controller.houseId or fleet.combatStrength() == 0:
        continue

      let fleetCoords = filtered.starMap.systems[fleet.location].coords
      let dx = abs(fleetCoords.q - protectedCoords.q)
      let dy = abs(fleetCoords.r - protectedCoords.r)
      let dz = abs((fleetCoords.q + fleetCoords.r) - (protectedCoords.q + protectedCoords.r))
      let dist = (dx + dy + dz) div 2

      if dist <= reserve.responseRadius:
        # Threat detected - reserve should respond
        result.add((reserveFleet: reserve.fleetId, threatSystem: fleet.location))
        break  # One threat per reserve per turn

# =============================================================================
# Phase 4: Ground Force Management
# =============================================================================

type
  GarrisonPlan* = object
    ## Plan for maintaining marine garrisons
    systemId*: SystemId
    currentMarines*: int
    targetMarines*: int
    priority*: float  # Higher = more important to defend

proc assessGarrisonNeeds*(controller: AIController, filtered: FilteredGameState): seq[GarrisonPlan] =
  ## Identify colonies that need marine garrisons
  result = @[]

  for colony in filtered.ownColonies:
    if colony.owner != controller.houseId:
      continue

    # Calculate current marine count (from colony data)
    let currentMarines = colony.marines

    # Determine target garrison size based on importance
    var targetMarines = 0
    var priority = 0.0

    # Important colonies need larger garrisons
    # Detect homeworld heuristically (high infrastructure + population)
    let isLikelyHomeworld = colony.infrastructure >= 7 and colony.population >= 50

    if isLikelyHomeworld:
      targetMarines = 8  # Homeworld - maximum defense
      priority = 15.0
    elif colony.production >= 50:
      targetMarines = 5  # Major production center
      priority = 10.0
    elif colony.resources in [ResourceRating.Rich, ResourceRating.VeryRich]:
      targetMarines = 4  # Valuable resources
      priority = 8.0
    else:
      targetMarines = 2  # Standard colony
      priority = 5.0

    # Frontier colonies (near enemy territory) need extra defense
    var isFrontier = false
    let systemCoords = filtered.starMap.systems[colony.systemId].coords
    for enemyColony in filtered.visibleColonies:
      if enemyColony.owner == controller.houseId:
        continue
      let enemyCoords = filtered.starMap.systems[enemyColony.systemId].coords
      let dx = abs(enemyCoords.q - systemCoords.q)
      let dy = abs(enemyCoords.r - systemCoords.r)
      let dz = abs((enemyCoords.q + enemyCoords.r) - (systemCoords.q + systemCoords.r))
      let dist = (dx + dy + dz) div 2
      if dist <= 2:
        isFrontier = true
        break

    if isFrontier:
      targetMarines += 2
      priority += 5.0

    # Only add to plan if we need more marines
    if currentMarines < targetMarines:
      result.add(GarrisonPlan(
        systemId: colony.systemId,
        currentMarines: currentMarines,
        targetMarines: targetMarines,
        priority: priority
      ))

proc shouldBuildMarines*(controller: AIController, filtered: FilteredGameState, colony: Colony): bool =
  ## Marines are for INVASIONS, not garrison defense (see ground_units.toml:53)
  ## Build marines when planning invasions and have/building transports
  ## Armies handle garrison duty (ground_units.toml:39)

  let p = controller.personality
  let house = filtered.ownHouse

  # PHASE 2B FIX: Don't build marines in early game - prioritize colonization
  # Early game = less than 1/3 of available systems colonized (scales with map size)
  # Approximate formula: ~30% of map colonized = mid-game transition
  let totalSystems = filtered.starMap.systems.len
  let targetColonies = max(5, totalSystems div 6)  # At least 5, or ~17% of systems
  let isEarlyGame = filtered.ownColonies.len < targetColonies
  if isEarlyGame:
    return false

  # Only aggressive AIs build marines for invasion
  if p.aggression < 0.4:
    return false

  # Count existing transports and marines
  var transportCount = 0
  var totalTransportCapacity = 0
  var loadedMarines = 0

  for fleet in filtered.ownFleets:
    if fleet.owner != controller.houseId:
      continue
    for transport in fleet.spaceLiftShips:
      if transport.shipClass == ShipClass.TroopTransport:
        transportCount += 1
        totalTransportCapacity += transport.cargo.capacity
        loadedMarines += transport.cargo.quantity

  # If we have transports, build marines to fill them (invasion prep)
  if transportCount > 0:
    let marinesNeeded = totalTransportCapacity - loadedMarines
    if marinesNeeded > 0:
      return true

  # If we're building transports, prepare marines in advance
  # Check if transport is in build queue (aggressive prep)
  if p.aggression > 0.6 and transportCount > 0:
    # Keep building a small stockpile for future invasions
    let totalMarines = colony.marines
    if totalMarines < 3:  # Small invasion force stockpile
      return true

  return false

proc ensureTransportsLoaded*(controller: var AIController, filtered: FilteredGameState): seq[tuple[transportId: string, needsMarines: int]] =
  ## Identify transports that need marines loaded
  ## Returns list of transports and how many marines they need
  result = @[]

  for fleet in filtered.ownFleets:
    if fleet.owner != controller.houseId:
      continue

    for transport in fleet.spaceLiftShips:
      if transport.shipClass == ShipClass.TroopTransport:
        # Check if transport is empty or not fully loaded
        if transport.cargo.quantity < transport.cargo.capacity:
          let needed = transport.cargo.capacity - transport.cargo.quantity
          result.add((transportId: transport.id, needsMarines: needed))

# =============================================================================
# Phase 5: Economic Intelligence
# =============================================================================

type
  EconomicIntelligence* = object
    ## Economic assessment of enemy houses
    targetHouse*: HouseId
    estimatedProduction*: int      # Total PP across all visible colonies
    highValueTargets*: seq[SystemId]  # Colonies with production >= 50
    economicStrength*: float        # Relative strength vs us (1.0 = equal)

proc gatherEconomicIntelligence*(controller: var AIController, filtered: FilteredGameState): seq[EconomicIntelligence] =
  ## Assess enemy economic strength for targeting
  result = @[]

  let ourHouse = filtered.ownHouse
  var ourProduction = 0
  for colony in filtered.ownColonies:
    if colony.owner == controller.houseId:
      ourProduction += colony.production

  for targetHouse in filtered.housePrestige.keys:
    if targetHouse == controller.houseId:
      continue

    var intel = EconomicIntelligence(
      targetHouse: targetHouse,
      estimatedProduction: 0,
      highValueTargets: @[],
      economicStrength: 0.0
    )

    # Gather data from visible enemy colonies
    for colony in filtered.visibleColonies:
      if colony.owner != targetHouse:
        continue

      # VisibleColony has Option[int] for production (limited intel)
      if colony.production.isSome:
        intel.estimatedProduction += colony.production.get()

        # Identify high-value economic targets
        if colony.production.get() >= 50:
          intel.highValueTargets.add(colony.systemId)

    # Calculate relative strength
    if ourProduction > 0:
      intel.economicStrength = float(intel.estimatedProduction) / float(ourProduction)

    result.add(intel)

proc identifyEconomicTargets*(controller: var AIController, filtered: FilteredGameState): seq[tuple[systemId: SystemId, value: float]] =
  ## Find best targets for economic warfare (blockades, raids)
  result = @[]

  let econIntel = controller.gatherEconomicIntelligence(filtered)

  for intel in econIntel:
    # Target high-value colonies of economically strong enemies
    if intel.economicStrength > 0.8:  # Only target if they're competitive
      for systemId in intel.highValueTargets:
        let colonyOpt = getColony(filtered, systemId)
        if colonyOpt.isNone:
          continue  # Can't see this colony
        let colony = colonyOpt.get()
        var value = float(colony.production)

        # Bonus for rich resources (denying them is valuable)
        if colony.resources in [ResourceRating.VeryRich, ResourceRating.Rich]:
          value *= 1.5

        result.add((systemId: systemId, value: value))

  # Sort by value (highest first)
  result.sort(proc(a, b: tuple[systemId: SystemId, value: float]): int =
    if b.value > a.value: 1
    elif b.value < a.value: -1
    else: 0
  )

# =============================================================================
# Strategic Diplomacy Assessment
# =============================================================================

type
  DiplomaticAssessment* = object
    ## Assessment of diplomatic situation with target house
    targetHouse*: HouseId
    relativeMilitaryStrength*: float  # Our strength / their strength (1.0 = equal)
    relativeEconomicStrength*: float  # Our economy / their economy (1.0 = equal)
    mutualEnemies*: seq[HouseId]      # Houses both consider enemies
    geographicProximity*: int         # Number of neighboring systems
    violationRisk*: float             # 0.0-1.0: Risk they violate pact
    currentState*: dip_types.DiplomaticState
    recommendPact*: bool              # Should we propose/maintain pact?
    recommendBreak*: bool             # Should we break existing pact?
    recommendEnemy*: bool             # Should we declare enemy?

proc calculateMilitaryStrength(filtered: FilteredGameState, houseId: HouseId): int =
  ## Calculate total military strength for a house
  result = 0
  let fleets = getOwnedFleets(filtered, houseId)
  for fleet in fleets:
    result += getFleetStrength(fleet)

proc calculateEconomicStrength(filtered: FilteredGameState, houseId: HouseId): int =
  ## Calculate total economic strength for a house
  ## RESPECTS FOG-OF-WAR: Can only see own house's full details
  result = 0

  if houseId == filtered.viewingHouse:
    # Own house - full details
    let house = filtered.ownHouse
    let colonies = filtered.ownColonies

    # Treasury value
    result += house.treasury

    # Colony production value
    for colony in colonies:
      result += colony.production * 10  # Weight production highly
      result += colony.infrastructure * 5
  else:
    # Enemy house - estimate from visible colonies only
    for visCol in filtered.visibleColonies:
      if visCol.owner == houseId:
        if visCol.production.isSome:
          result += visCol.production.get() * 10
        # Can't see infrastructure for enemy colonies

proc findMutualEnemies(filtered: FilteredGameState, houseA: HouseId, houseB: HouseId): seq[HouseId] =
  ## Find houses that both houseA and houseB consider enemies
  ## RESPECTS FOG-OF-WAR: Can only see our own house's diplomatic relations
  result = @[]

  # Can only determine mutual enemies if we are houseA
  if houseA != filtered.viewingHouse:
    return result  # Can't see other house's diplomatic relations

  let ourHouse = filtered.ownHouse

  for otherHouse in filtered.housePrestige.keys:
    if otherHouse == houseA or otherHouse == houseB:
      continue

    # We can see our own enemies
    let weAreEnemies = dip_types.isEnemy(ourHouse.diplomaticRelations, otherHouse)
    # Assume houseB has similar enemies (imperfect information)
    if weAreEnemies:
      result.add(otherHouse)

proc estimateViolationRisk(filtered: FilteredGameState, targetHouse: HouseId): float =
  ## Estimate risk that target house will violate a pact (0.0-1.0)
  ## RESPECTS FOG-OF-WAR: Can't see other houses' violation history
  ## Returns a conservative default estimate

  # Without access to violation history, use a moderate default risk
  # TODO: Could enhance with intelligence reports if available
  return 0.3  # 30% baseline risk

proc assessDiplomaticSituation(controller: AIController, filtered: FilteredGameState,
                               targetHouse: HouseId): DiplomaticAssessment =
  ## Evaluate diplomatic relationship with target house
  ## Returns strategic assessment for decision making
  ## RESPECTS FOG-OF-WAR: Uses only available information
  let myHouse = filtered.ownHouse
  let p = controller.personality

  result.targetHouse = targetHouse
  result.currentState = dip_types.getDiplomaticState(
    myHouse.diplomaticRelations,
    targetHouse
  )

  # Calculate relative strengths
  let myMilitary = calculateMilitaryStrength(filtered, controller.houseId)
  let theirMilitary = calculateMilitaryStrength(filtered, targetHouse)
  result.relativeMilitaryStrength = if theirMilitary > 0:
    float(myMilitary) / float(theirMilitary)
  else:
    10.0  # They have no military

  let myEconomy = calculateEconomicStrength(filtered, controller.houseId)
  let theirEconomy = calculateEconomicStrength(filtered, targetHouse)
  result.relativeEconomicStrength = if theirEconomy > 0:
    float(myEconomy) / float(theirEconomy)
  else:
    10.0  # They have no economy

  # Find mutual enemies
  result.mutualEnemies = findMutualEnemies(filtered, controller.houseId, targetHouse)

  # Estimate violation risk
  result.violationRisk = estimateViolationRisk(filtered, targetHouse)

  # Strategic recommendations based on personality
  case result.currentState
  of dip_types.DiplomaticState.Neutral:
    # Should we propose a pact?
    var pactScore = 0.0

    # Stronger neighbor = want pact (defensive)
    if result.relativeMilitaryStrength < 0.8:
      pactScore += 0.3

    # Mutual enemies = want pact (alliance)
    pactScore += float(result.mutualEnemies.len) * 0.2

    # High diplomacy value = more likely to seek pacts
    pactScore += p.diplomacyValue * 0.4

    # Low violation risk = more likely to trust
    pactScore += (1.0 - result.violationRisk) * 0.2

    result.recommendPact = pactScore > 0.5

    # Should we declare enemy?
    var enemyScore = 0.0

    # Aggressive personality
    enemyScore += p.aggression * 0.5

    # Weaker target
    if result.relativeMilitaryStrength > 1.5:
      enemyScore += 0.3

    # Low diplomacy value
    enemyScore += (1.0 - p.diplomacyValue) * 0.3

    result.recommendEnemy = enemyScore > 0.6

  of dip_types.DiplomaticState.NonAggression:
    # Should we break the pact?
    var breakScore = 0.0

    # Aggressive strategy willing to violate
    if controller.strategy == AIStrategy.Aggressive:
      breakScore += 0.4

    # Much weaker target = tempting
    if result.relativeMilitaryStrength > 2.0:
      breakScore += 0.3

    # Low diplomacy value = less concerned with reputation
    breakScore += (1.0 - p.diplomacyValue) * 0.4

    # High risk tolerance
    breakScore += p.riskTolerance * 0.2

    result.recommendBreak = breakScore > 0.7  # High threshold for violation

  of dip_types.DiplomaticState.Enemy:
    # Should we normalize relations?
    var normalizeScore = 0.0

    # Much stronger enemy = want peace
    if result.relativeMilitaryStrength < 0.5:
      normalizeScore += 0.5

    # High diplomacy value
    normalizeScore += p.diplomacyValue * 0.4

    # Low aggression
    normalizeScore += (1.0 - p.aggression) * 0.3

    # Recommend neutral if score high enough
    if normalizeScore > 0.6:
      result.recommendEnemy = false
    else:
      result.recommendEnemy = true  # Stay enemies

# =============================================================================
# Strategic Military Assessment
# =============================================================================

type
  CombatAssessment* = object
    ## Assessment of combat situation for attacking a target system
    targetSystem*: SystemId
    targetOwner*: HouseId

    # Fleet strengths
    attackerFleetStrength*: int    # Our attack power
    defenderFleetStrength*: int    # Enemy fleet defense at target

    # Defensive installations
    starbaseStrength*: int         # Starbase attack/defense
    groundBatteryCount*: int       # Ground batteries
    planetaryShieldLevel*: int     # Shield level (0-6)
    groundForces*: int             # Armies + marines

    # Combat odds
    estimatedCombatOdds*: float    # 0.0-1.0: Probability of victory
    expectedCasualties*: int       # Expected ship losses

    # Strategic factors
    violatesPact*: bool            # Would attack violate non-aggression pact?
    strategicValue*: int           # Value of target (production, resources)

    # Recommendations
    recommendAttack*: bool         # Should we attack?
    recommendReinforce*: bool      # Should we send reinforcements?
    recommendRetreat*: bool        # Should we retreat from system?

  InvasionViability* = object
    ## 3-phase invasion assessment
    ## Per docs/specs/operations.md: Invasions have 3 phases

    # Phase 1: Space Combat
    canWinSpaceCombat*: bool       # Can defeat enemy fleets?
    spaceOdds*: float              # Space combat victory odds

    # Phase 2: Starbase Assault
    canDestroyStarbases*: bool     # Can destroy defensive starbases?
    starbaseOdds*: float           # Starbase destruction odds

    # Phase 3: Ground Invasion
    canWinGroundCombat*: bool      # Can overcome ground forces?
    groundOdds*: float             # Ground combat victory odds
    attackerGroundForces*: int     # Marines available (engine doesn't track loading!)
    defenderGroundForces*: int     # Enemy marines + armies + batteries

    # Overall assessment
    invasionViable*: bool          # All 3 phases passable?
    recommendInvade*: bool         # Full invasion recommended?
    recommendBlitz*: bool          # Blitz (skip ground) recommended?
    recommendBlockade*: bool       # Too strong - blockade instead?
    strategicValue*: int           # Value of target (production, resources)

proc calculateDefensiveStrength(filtered: FilteredGameState, systemId: SystemId): int =
  ## Calculate total defensive strength of a colony
  if not isSystemColonized(filtered, systemId):
    return 0

  let colonyOpt = getColony(filtered, systemId)
  if colonyOpt.isNone:
    return 0  # Can't assess defense of invisible colony
  let colony = colonyOpt.get()
  result = 0

  # Starbase strength (each starbase adds attack + defense strength)
  for starbase in colony.starbases:
    if not starbase.isCrippled:
      # Starbases are powerful defensive assets
      result += 100  # Simplified: each starbase worth 100 defense points

  # Ground batteries
  result += colony.groundBatteries * 20

  # Planetary shields (reduce attacker effectiveness)
  result += colony.planetaryShieldLevel * 15

  # Ground forces (armies + marines)
  result += (colony.armies + colony.marines) * 10

proc calculateFleetStrengthAtSystem(filtered: FilteredGameState, systemId: SystemId,
                                   houseId: HouseId): int =
  ## Calculate fleet strength for a specific house at a system
  result = 0
  for fleet in filtered.ownFleets:
    if fleet.owner == houseId and fleet.location == systemId:
      result += getFleetStrength(fleet)

proc estimateColonyValue(filtered: FilteredGameState, systemId: SystemId): int =
  ## Estimate strategic value of a colony
  if not isSystemColonized(filtered, systemId):
    return 0

  let colonyOpt = getColony(filtered, systemId)
  if colonyOpt.isNone:
    return 0  # Can't assess value of invisible colony
  let colony = colonyOpt.get()
  result = 0

  # Production value
  result += colony.production * 10

  # Infrastructure value
  result += colony.infrastructure * 20

  # Resource rating bonus
  case colony.resources
  of ResourceRating.VeryRich:
    result += 70
  of ResourceRating.Rich:
    result += 50
  of ResourceRating.Abundant:
    result += 30
  of ResourceRating.Poor:
    result += 10
  of ResourceRating.VeryPoor:
    result += 0

proc assessCombatSituation(controller: AIController, filtered: FilteredGameState,
                          targetSystem: SystemId): CombatAssessment =
  ## Evaluate combat situation for attacking a target system
  ## Returns strategic assessment for attack decision

  result.targetSystem = targetSystem

  # Check if system has a colony
  if not isSystemColonized(filtered, targetSystem):
    result.recommendAttack = false
    return

  let targetColonyOpt = getColony(filtered, targetSystem)
  if targetColonyOpt.isNone:
    result.recommendAttack = false
    return  # Can't attack invisible colony
  let targetColony = targetColonyOpt.get()
  result.targetOwner = targetColony.owner

  # Don't attack our own colonies
  if result.targetOwner == controller.houseId:
    result.recommendAttack = false
    return

  # Check diplomatic status
  let myHouse = filtered.ownHouse
  let dipState = dip_types.getDiplomaticState(
    myHouse.diplomaticRelations,
    result.targetOwner
  )
  result.violatesPact = dipState == dip_types.DiplomaticState.NonAggression

  # Calculate military strengths
  result.attackerFleetStrength = calculateFleetStrengthAtSystem(
    filtered, targetSystem, controller.houseId
  )
  result.defenderFleetStrength = calculateFleetStrengthAtSystem(
    filtered, targetSystem, result.targetOwner
  )

  # Calculate defensive installations
  result.starbaseStrength = 0
  result.groundBatteryCount = targetColony.groundBatteries
  result.planetaryShieldLevel = targetColony.planetaryShieldLevel
  result.groundForces = targetColony.armies + targetColony.marines

  for starbase in targetColony.starbases:
    if not starbase.isCrippled:
      result.starbaseStrength += 100

  # Total defensive strength
  let totalDefense = result.defenderFleetStrength +
                     calculateDefensiveStrength(filtered, targetSystem)

  # Estimate combat odds
  # Simple model: odds = attacker / (attacker + defender)
  # Attacker needs advantage to have good odds
  if result.attackerFleetStrength == 0:
    result.estimatedCombatOdds = 0.0
  elif totalDefense == 0:
    result.estimatedCombatOdds = 1.0
  else:
    let ratio = float(result.attackerFleetStrength) / float(totalDefense)
    # Apply sigmoid-like curve: need ~2:1 advantage for 75% odds
    result.estimatedCombatOdds = ratio / (ratio + 0.8)
    result.estimatedCombatOdds = min(result.estimatedCombatOdds, 0.95)

  # Estimate casualties (% of attacker strength lost)
  let expectedLossRate = 1.0 - result.estimatedCombatOdds
  result.expectedCasualties = int(
    float(result.attackerFleetStrength) * expectedLossRate * 0.3
  )

  # Calculate strategic value
  result.strategicValue = estimateColonyValue(filtered, targetSystem)

  # PRESTIGE OPTIMIZATION: Starbase destruction gives +5 prestige
  # Boost strategic value if target has starbases
  if result.starbaseStrength > 0:
    result.strategicValue += 50  # Starbase destruction is high-value target

  # Make recommendations based on personality and odds
  let p = controller.personality

  # Attack recommendation
  var attackThreshold = 0.6  # Base: 60% odds needed

  # Adjust threshold by personality
  if controller.strategy == AIStrategy.Aggressive:
    attackThreshold = 0.4  # Aggressive: attack at 40% odds
  elif p.riskTolerance > 0.7:
    attackThreshold = 0.5  # High risk tolerance
  elif p.aggression < 0.3:
    attackThreshold = 0.8  # Cautious: need 80% odds

  # PRESTIGE OPTIMIZATION: Lower threshold for starbase targets (+5 prestige)
  if result.starbaseStrength > 0 and attackThreshold > 0.5:
    attackThreshold -= 0.1  # More willing to attack starbase targets

  # Don't attack if it violates pact (unless we're deciding to break it)
  if result.violatesPact:
    result.recommendAttack = false
  else:
    result.recommendAttack = result.estimatedCombatOdds >= attackThreshold

  # Reinforce recommendation (we have fleet there but odds not good enough)
  result.recommendReinforce = (
    result.attackerFleetStrength > 0 and
    result.estimatedCombatOdds < attackThreshold and
    result.estimatedCombatOdds > 0.2  # But not hopeless
  )

  # Retreat recommendation (we're outmatched)
  result.recommendRetreat = (
    result.attackerFleetStrength > 0 and
    result.estimatedCombatOdds < 0.3  # Less than 30% odds
  )

proc assessInvasionViability(controller: AIController, filtered: FilteredGameState,
                             fleet: Fleet, targetSystem: SystemId): InvasionViability =
  ## IMPROVEMENT: 3-phase invasion viability assessment
  ## Invasions require winning 3 sequential battles:
  ## 1. Space Combat - Defeat enemy fleets
  ## 2. Starbase Assault - Destroy defensive installations
  ## 3. Ground Invasion - Overcome marines, armies, ground batteries
  ## ## Per docs/specs/operations.md:
  ## - Invasion: Full planetary assault (all 3 phases)
  ## - Blitz: Skip ground combat, just destroy orbital defenses
  ## - Blockade: If too strong to invade, starve them economically (-60% GCO)

  # Get basic combat assessment first
  let combat = assessCombatSituation(controller, filtered, targetSystem)
  let targetColonyOpt = getColony(filtered, targetSystem)
  if targetColonyOpt.isNone:
    result.invasionViable = false
    return  # Can't invade invisible colony
  let targetColony = targetColonyOpt.get()
  let p = controller.personality

  # =============================================================================
  # Space Combat Assessment
  # =============================================================================
  # Can we defeat enemy fleets in the system?

  let spaceAttackStrength = fleet.squadrons.foldl(a + b.combatStrength(), 0)
  let spaceDefenseStrength = combat.defenderFleetStrength

  if spaceDefenseStrength == 0:
    result.spaceOdds = 1.0
    result.canWinSpaceCombat = true
  else:
    let spaceRatio = float(spaceAttackStrength) / float(spaceDefenseStrength)
    result.spaceOdds = spaceRatio / (spaceRatio + 0.8)
    result.canWinSpaceCombat = result.spaceOdds >= 0.5  # Need 50%+ odds

  # =============================================================================
  # Starbase Assault Assessment
  # =============================================================================
  # Can we destroy defensive starbases?
  # Starbases have both attack and defense, must be destroyed before landing

  if combat.starbaseStrength == 0:
    result.starbaseOdds = 1.0
    result.canDestroyStarbases = true
  else:
    # Starbases are tough - assume ~100 AS each
    # Need sufficient firepower to overcome them
    let starbaseRatio = float(spaceAttackStrength) / float(combat.starbaseStrength)
    result.starbaseOdds = starbaseRatio / (starbaseRatio + 1.2)  # Harder than space combat
    result.canDestroyStarbases = result.starbaseOdds >= 0.4  # Can take more losses here

  # =============================================================================
  # Ground Combat Assessment
  # =============================================================================
  # Can we overcome ground forces (marines + armies + ground batteries)?
  result.defenderGroundForces = combat.groundForces + combat.groundBatteryCount

  # Count loaded marines from cargo system
  var marineCount = 0
  for spaceLiftShip in fleet.spaceLiftShips:
    if spaceLiftShip.shipClass == ShipClass.TroopTransport and not spaceLiftShip.isCrippled:
      if spaceLiftShip.cargo.cargoType == CargoType.Marines:
        marineCount += spaceLiftShip.cargo.quantity

  result.attackerGroundForces = marineCount

  if result.defenderGroundForces == 0:
    result.groundOdds = 1.0
    result.canWinGroundCombat = true
  elif result.attackerGroundForces == 0:
    result.groundOdds = 0.0
    result.canWinGroundCombat = false
  else:
    # Ground combat requires ~2:1 advantage typically
    let groundRatio = float(result.attackerGroundForces) / float(result.defenderGroundForces)
    result.groundOdds = groundRatio / (groundRatio + 1.5)  # Need advantage
    result.canWinGroundCombat = result.groundOdds >= 0.5

  # =============================================================================
  # Overall Assessment
  # =============================================================================

  # Invasion is only viable if we can pass all 3 phases
  result.invasionViable = (
    result.canWinSpaceCombat and
    result.canDestroyStarbases and
    result.canWinGroundCombat
  )

  # Strategic value (for prestige/resource gain)
  result.strategicValue = combat.strategicValue

  # =============================================================================
  # Decision: Invade, Blitz, Blockade, or Move?
  # =============================================================================

  # Personality modifiers
  let invasionThreshold = if p.riskTolerance > 0.6: 0.5 else: 0.65
  let blitzThreshold = if p.aggression > 0.6: 0.4 else: 0.5

  if result.invasionViable:
    # Full invasion possible - gives +10 prestige (highest!)
    result.recommendInvade = true
    result.recommendBlitz = false
    result.recommendBlockade = false

  elif result.canWinSpaceCombat and result.canDestroyStarbases:
    # Can't win ground combat, but can destroy orbital defenses
    # Blitz gives +5 prestige for starbase destruction
    result.recommendInvade = false
    result.recommendBlitz = true
    result.recommendBlockade = false

  elif result.canWinSpaceCombat and result.spaceOdds >= 0.6:
    # Strong in space but can't overcome starbases
    # Consider blockade for economic warfare (-60% GCO)
    result.recommendInvade = false
    result.recommendBlitz = false
    result.recommendBlockade = (p.aggression < 0.5)  # Cautious AIs prefer blockade

  else:
    # Too weak - don't attempt invasion
    result.recommendInvade = false
    result.recommendBlitz = false
    result.recommendBlockade = false

# =============================================================================
# Order Generation
# =============================================================================

proc generateFleetOrders(controller: var AIController, filtered: FilteredGameState, rng: var Rand): seq[FleetOrder] =
  ## Generate fleet orders based on strategic military assessment
  ## Now updates intelligence when making decisions
  when not defined(release):
    logDebug(LogCategory.lcAI, &"{controller.houseId} generateFleetOrders called for turn {filtered.turn}")
  result = @[]
  let p = controller.personality
  let myFleets = getOwnedFleets(filtered, controller.houseId)
  when not defined(release):
    logDebug(LogCategory.lcAI, &"{controller.houseId} has {myFleets.len} fleets")

  # Update intelligence for systems we have visibility on
  # (Our colonies + systems with our fleets = automatic intel)
  for colony in filtered.ownColonies:
    if colony.owner == controller.houseId:
      controller.updateIntelligence(filtered, colony.systemId, filtered.turn, 1.0)

  for fleet in myFleets:
    # Fleets give us visibility into their current system
    controller.updateIntelligence(filtered, fleet.location, filtered.turn, 0.8)

  # Update coordinated operations status
  controller.updateOperationStatus(filtered)
  controller.removeCompletedOperations(filtered.turn)

  for fleet in myFleets:
    var order: FleetOrder
    order.fleetId = fleet.id
    order.priority = 1

    # Check current location for combat situation
    let currentCombat = assessCombatSituation(
      controller, filtered, fleet.location
    )

    # BALANCE FIX: Priority 0 - Stay at colony to absorb unassigned squadrons
    # If at a friendly colony with unassigned squadrons, hold position so auto-assign works
    if isSystemColonized(filtered, fleet.location):
      let colonyOpt = getColony(filtered, fleet.location)
      if colonyOpt.isSome:
        let colony = colonyOpt.get()
        if colony.owner == controller.houseId and colony.unassignedSquadrons.len > 0:
          # Stay at colony to pick up newly built ships
          order.orderType = FleetOrderType.Hold
          order.targetSystem = some(fleet.location)
          order.targetFleet = none(FleetId)
          result.add(order)
          continue

    # Priority 0.5: Coordinated Operations
    # Check if this fleet is part of a coordinated operation
    for op in controller.operations:
      if fleet.id in op.requiredFleets:
        # Fleet is part of coordinated operation
        if fleet.location != op.assemblyPoint:
          # Not at assembly point - issue Rendezvous order
          order.orderType = FleetOrderType.Rendezvous
          order.targetSystem = some(op.assemblyPoint)
          order.targetFleet = none(FleetId)
          result.add(order)
          continue
        elif controller.shouldExecuteOperation(op, filtered.turn):
          # At assembly point and ready to execute
          case op.operationType
          of OperationType.Invasion:
            order.orderType = FleetOrderType.Invade
            order.targetSystem = some(op.targetSystem)
          of OperationType.Raid:
            order.orderType = FleetOrderType.Blitz
            order.targetSystem = some(op.targetSystem)
          of OperationType.Blockade:
            order.orderType = FleetOrderType.BlockadePlanet
            order.targetSystem = some(op.targetSystem)
          of OperationType.Defense:
            order.orderType = FleetOrderType.Patrol
            order.targetSystem = some(op.targetSystem)
          order.targetFleet = none(FleetId)
          result.add(order)
          continue
        else:
          # At assembly but not ready - hold position
          order.orderType = FleetOrderType.Hold
          order.targetSystem = some(fleet.location)
          order.targetFleet = none(FleetId)
          result.add(order)
          continue

    # Priority 0.75: Strategic Reserve Threat Response
    # Check if this fleet is a reserve responding to a nearby threat
    let threats = controller.respondToThreats(filtered)
    var isRespondingToThreat = false
    for threat in threats:
      if threat.reserveFleet == fleet.id:
        # Reserve fleet should move to intercept threat
        order.orderType = FleetOrderType.Move
        order.targetSystem = some(threat.threatSystem)
        order.targetFleet = none(FleetId)
        result.add(order)
        isRespondingToThreat = true
        break

    if isRespondingToThreat:
      continue

    # Priority 1: Retreat if we're in a losing battle
    if currentCombat.recommendRetreat:
      # Phase 2h: Use designated fallback system if available
      var retreatTarget = controller.findFallbackSystem(fleet.location)

      # Fallback: Find nearest friendly colony
      if retreatTarget.isNone:
        var minDist = 999
        let fromCoords = filtered.starMap.systems[fleet.location].coords
        for colony in filtered.ownColonies:
          if colony.owner == controller.houseId and colony.systemId != fleet.location:
            let toCoords = filtered.starMap.systems[colony.systemId].coords
            let dx = abs(toCoords.q - fromCoords.q)
            let dy = abs(toCoords.r - fromCoords.r)
            let dz = abs((toCoords.q + toCoords.r) - (fromCoords.q + fromCoords.r))
            let dist = (dx + dy + dz) div 2
            if dist < minDist:
              minDist = dist
              retreatTarget = some(colony.systemId)

      if retreatTarget.isSome:
        order.orderType = FleetOrderType.Move
        order.targetSystem = retreatTarget
        order.targetFleet = none(FleetId)
        result.add(order)
        continue
      # If no friendly colonies, hold and hope for the best
      order.orderType = FleetOrderType.Hold
      order.targetSystem = none(SystemId)
      order.targetFleet = none(FleetId)
      result.add(order)
      continue

    # Priority 2: Attack if we have good odds
    if currentCombat.recommendAttack:
      # We're already at an enemy system with good odds
      # Stay and fight (patrol to maintain presence)
      order.orderType = FleetOrderType.Patrol
      order.targetSystem = some(fleet.location)
      order.targetFleet = none(FleetId)
      result.add(order)
      continue

    # Priority 2.5: Check if fleet needed for colony defense (Phase 2f)
    # Before committing to offensive operations, ensure important/frontier colonies defended
    var undefendedColony: Option[SystemId] = none(SystemId)

    # First: Check important colonies (production >= 30 or strategic resources)
    let importantColonies = controller.identifyImportantColonies(filtered)
    for systemId in importantColonies:
      var hasDefense = false
      for otherFleet in myFleets:
        if otherFleet.location == systemId and otherFleet.id != fleet.id:
          hasDefense = true
          break
      let colonyOpt = getColony(filtered, systemId)
      if colonyOpt.isSome:
        let colony = colonyOpt.get()
        if colony.starbases.len > 0:
          hasDefense = true
      if not hasDefense:
        undefendedColony = some(systemId)
        break

    # Second: Check frontier colonies (adjacent to enemy territory)
    if undefendedColony.isNone:
      for colony in filtered.ownColonies:
        if colony.owner != controller.houseId:
          continue
        var isFrontier = false
        let adjacentIds = filtered.starMap.getAdjacentSystems(colony.systemId)
        for neighborId in adjacentIds:
          let neighborColony = getColony(filtered, neighborId)
          if neighborColony.isSome and neighborColony.get().owner != controller.houseId:
            isFrontier = true
            break
        if isFrontier:
          var hasDefense = false
          for otherFleet in myFleets:
            if otherFleet.location == colony.systemId and otherFleet.id != fleet.id:
              hasDefense = true
              break
          if colony.starbases.len > 0:
            hasDefense = true
          if not hasDefense:
            undefendedColony = some(colony.systemId)
            break

    # If colony needs defense, position there instead of attacking
    if undefendedColony.isSome:
      if fleet.location != undefendedColony.get():
        order.orderType = FleetOrderType.Move
        order.targetSystem = undefendedColony
      else:
        order.orderType = FleetOrderType.Patrol
        order.targetSystem = some(fleet.location)
      order.targetFleet = none(FleetId)
      result.add(order)
      continue

    # Priority 3: Find targets to attack based on aggression OR military focus
    let militaryFocus = 1.0 - p.economicFocus
    let shouldSeekTargets = p.aggression > 0.3 or militaryFocus > 0.7

    if shouldSeekTargets:
      # Look for vulnerable enemy colonies
      var bestTarget: Option[SystemId] = none(SystemId)
      var bestOdds = 0.0

      # Economic Warfare - prioritize high-value economic targets
      # if we're economically focused (lower aggression, higher economic focus)
      if p.economicFocus > 0.6 and p.aggression < 0.6:
        # Get economic targets for warfare
        let econTargets = controller.identifyEconomicTargets(filtered)

        # Find best economic target we can reach
        for target in econTargets:
          let combat = assessCombatSituation(controller, filtered, target.systemId)
          # For economic warfare, we prefer blockades over invasions
          # Target high-value economies even with moderate odds
          if combat.estimatedCombatOdds > 0.4:  # Lower threshold for economic targets
            bestTarget = some(target.systemId)
            bestOdds = combat.estimatedCombatOdds
            break  # Take first viable economic target (already sorted by value)

      # If no economic target found (or not economically focused), use standard military targeting
      if bestTarget.isNone:
        for colony in filtered.ownColonies:
          if colony.owner == controller.houseId:
            continue  # Skip our own colonies

          let combat = assessCombatSituation(controller, filtered, colony.systemId)
          if combat.recommendAttack and combat.estimatedCombatOdds > bestOdds:
            bestOdds = combat.estimatedCombatOdds
            bestTarget = some(colony.systemId)

      if bestTarget.isSome:
        # ARCHITECTURE FIX: Check if fleet has troop transports (spacelift ships)
        var hasTransports = false
        for spaceLiftShip in fleet.spaceLiftShips:
          if spaceLiftShip.shipClass == ShipClass.TroopTransport:
            hasTransports = true
            break

        # IMPROVEMENT: Use 3-phase invasion viability assessment
        # Invasions give +10 prestige (highest reward!) - prioritize them
        if hasTransports:
          # Perform comprehensive 3-phase invasion assessment
          let invasion = assessInvasionViability(controller, filtered, fleet, bestTarget.get)

          if invasion.recommendInvade:
            # Full invasion - can win all 3 phases (space, starbase, ground)
            order.orderType = FleetOrderType.Invade
          elif invasion.recommendBlitz:
            # Blitz - can win space + starbase, but not ground
            # Still gets +5 prestige for starbase destruction
            order.orderType = FleetOrderType.Blitz
          elif invasion.recommendBlockade:
            # Too strong to invade, use economic warfare
            order.orderType = FleetOrderType.BlockadePlanet
          else:
            # Not viable - just do space combat
            order.orderType = FleetOrderType.Move
        else:
          # No transports, just move to attack (space combat only)
          order.orderType = FleetOrderType.Move

        order.targetSystem = bestTarget
        order.targetFleet = none(FleetId)
        result.add(order)
        continue

    # Priority 3.5: Scout Reconnaissance Missions
    # Check if this is a scout-only fleet (single squadron with scouts)
    var isScoutFleet = false
    var hasOnlyScouts = false
    if fleet.squadrons.len == 1:
      let squadron = fleet.squadrons[0]
      # Single-squadron scout fleets are ideal for spy missions (per operations.md:45)
      if squadron.flagship.shipClass == ShipClass.Scout and squadron.ships.len == 0:
        isScoutFleet = true
        hasOnlyScouts = true

    # PHASE 2G: Enhanced espionage mission targeting
    # Scouts should actively gather intelligence, not just for colonization/invasion
    if isScoutFleet:
      # Intelligence operations for scouts
      # Priority: Strategic intel > Pre-colonization recon > Pre-invasion intel

      # A) Strategic intelligence gathering - HackStarbase on enemy production centers
      # Target: Enemy colonies with high production or shipyards
      if p.techPriority > 0.3 or (1.0 - p.economicFocus) > 0.5:
        var highValueTargets: seq[SystemId] = @[]
        for colony in filtered.ownColonies:
          if colony.owner != controller.houseId:
            # High-value targets: production > 50 OR has shipyards
            if colony.production > 50 or colony.shipyards.len > 0:
              # Check if we need fresh intel (data older than 10 turns)
              if controller.needsReconnaissance(colony.systemId, filtered.turn):
                highValueTargets.add(colony.systemId)

        if highValueTargets.len > 0:
          # Pick closest high-value target
          var closest: Option[SystemId] = none(SystemId)
          var minDist = 999
          let fromCoords = filtered.starMap.systems[fleet.location].coords
          for sysId in highValueTargets:
            let coords = filtered.starMap.systems[sysId].coords
            let dx = abs(coords.q - fromCoords.q)
            let dy = abs(coords.r - fromCoords.r)
            let dz = abs((coords.q + coords.r) - (fromCoords.q + fromCoords.r))
            let dist = (dx + dy + dz) div 2
            if dist < minDist:
              minDist = dist
              closest = some(sysId)

          if closest.isSome:
            # Issue HackStarbase mission to gather production/fleet intel
            order.orderType = FleetOrderType.HackStarbase
            order.targetSystem = closest
            order.targetFleet = none(FleetId)
            result.add(order)
            continue

      # B) Pre-colonization reconnaissance - scout systems before sending ETACs
      if p.expansionDrive > 0.4:
        # Find uncolonized systems that need scouting
        var needsRecon: seq[SystemId] = @[]
        for systemId, system in filtered.starMap.systems:
          if not isSystemColonized(filtered, systemId) and
             controller.needsReconnaissance(systemId, filtered.turn):
            needsRecon.add(systemId)

        if needsRecon.len > 0:
          # Pick closest system needing recon
          var closest: Option[SystemId] = none(SystemId)
          var minDist = 999
          let fromCoords = filtered.starMap.systems[fleet.location].coords
          for sysId in needsRecon:
            let coords = filtered.starMap.systems[sysId].coords
            let dx = abs(coords.q - fromCoords.q)
            let dy = abs(coords.r - fromCoords.r)
            let dz = abs((coords.q + coords.r) - (fromCoords.q + fromCoords.r))
            let dist = (dx + dy + dz) div 2
            if dist < minDist:
              minDist = dist
              closest = some(sysId)

          if closest.isSome:
            # Issue spy mission to gather planetary intelligence
            order.orderType = FleetOrderType.SpyPlanet
            order.targetSystem = closest
            order.targetFleet = none(FleetId)
            result.add(order)
            continue

      # C) Pre-invasion intelligence - SpySystem on enemy colonies before invasion
      # Lowered threshold from 0.4 to 0.2 to enable more intelligence gathering
      if p.aggression > 0.2 or (1.0 - p.economicFocus) > 0.4:
        # Find enemy colonies that need updated intelligence
        var needsIntel: seq[SystemId] = @[]
        for colony in filtered.ownColonies:
          if colony.owner != controller.houseId and
             controller.needsReconnaissance(colony.systemId, filtered.turn):
            needsIntel.add(colony.systemId)

        if needsIntel.len > 0:
          # Pick closest enemy colony needing intel
          var closest: Option[SystemId] = none(SystemId)
          var minDist = 999
          let fromCoords = filtered.starMap.systems[fleet.location].coords
          for sysId in needsIntel:
            let coords = filtered.starMap.systems[sysId].coords
            let dx = abs(coords.q - fromCoords.q)
            let dy = abs(coords.r - fromCoords.r)
            let dz = abs((coords.q + coords.r) - (fromCoords.q + fromCoords.r))
            let dist = (dx + dy + dz) div 2
            if dist < minDist:
              minDist = dist
              closest = some(sysId)

          if closest.isSome:
            # Issue spy mission to gather defense intelligence
            order.orderType = FleetOrderType.SpySystem
            order.targetSystem = closest
            order.targetFleet = none(FleetId)
            result.add(order)
            continue

    # Priority 4: Expansion and Exploration
    # ARCHITECTURE FIX: Check if fleet has ETAC (spacelift ship for colonization)
    var hasETAC = false
    for spaceLiftShip in fleet.spaceLiftShips:
      if spaceLiftShip.shipClass == ShipClass.ETAC:
        hasETAC = true
        break

    if hasETAC:
      # Intelligence-driven colonization
      # ETAC fleets: Issue COLONIZE order to best uncolonized target
      # The engine will automatically move the fleet there and colonize
      let targetOpt = findBestColonizationTarget(controller, filtered, fleet.location, fleet.id)
      if targetOpt.isSome:
        # ALWAYS LOG: Critical for diagnosing colonization order timing
        # Count PTUs in fleet
        var ptuCount = 0
        for spaceLift in fleet.spaceLiftShips:
          if spaceLift.cargo.cargoType == CargoType.Colonists:
            ptuCount += spaceLift.cargo.quantity
        logInfo(LogCategory.lcAI, &"{controller.houseId} ETAC fleet {fleet.id} issuing colonize order for system {targetOpt.get()} " &
                &"(location: {fleet.location}, ETACs: {fleet.spaceLiftShips.len}, PTUs: {ptuCount})")
        order.orderType = FleetOrderType.Colonize
        order.targetSystem = targetOpt
        order.targetFleet = none(FleetId)
        result.add(order)
        continue
      else:
        # ALWAYS LOG: Warns when ETAC has no valid targets
        logWarn(LogCategory.lcAI, &"{controller.houseId} ETAC fleet {fleet.id} has NO colonization target " &
                &"(location: {fleet.location}, all systems colonized?)")
    elif p.expansionDrive > 0.3:
      # Non-ETAC fleets with expansion drive: Scout uncolonized systems
      let targetOpt = findNearestUncolonizedSystem(filtered, fleet.location, fleet.id)
      if targetOpt.isSome:
        order.orderType = FleetOrderType.Move
        order.targetSystem = targetOpt
        order.targetFleet = none(FleetId)
        result.add(order)
        continue

    # Priority 5: Defend home colonies (patrol)
    # Find a colony that needs defense
    var needsDefense: Option[SystemId] = none(SystemId)
    for colony in filtered.ownColonies:
      if colony.owner == controller.houseId:
        # Check if there are enemy fleets nearby (simplified: just check this colony)
        let hasEnemyFleets = calculateFleetStrengthAtSystem(
          filtered, colony.systemId, colony.owner
        ) < getFleetStrength(fleet)
        if hasEnemyFleets or colony.blockaded:
          needsDefense = some(colony.systemId)
          break

    if needsDefense.isSome:
      order.orderType = FleetOrderType.Move
      order.targetSystem = needsDefense
      order.targetFleet = none(FleetId)
    else:
      # Priority 5.5: Proactive Colony Defense (Phase 2f)
      ## **Purpose:** Address 73.8% undefended colony rate by positioning fleets proactively
      ##
      ## **Strategy:**
      ## 1. Prioritize important colonies (high production or rich resources)
      ## 2. Fall back to frontier colonies (adjacent to enemy territory)
      ## 3. Consider colony defended if it has fleet OR starbase
      ##
      ## **Defense Layering:**
      ## - Important colonies get first priority (production >= 30 or rich resources)
      ## - Frontier colonies get second priority (adjacent to enemy systems)
      ## - Fleets move to guard position or patrol if already in position
      ##
      ## **Why This Matters:**
      ## Proactive defense prevents surprise attacks and resource loss. Undefended
      ## colonies are easy targets that can snowball into strategic losses.
      ##
      ## **CRITICAL FIX:** Exempt ETAC/colonization fleets from defense duty
      ## - ETAC fleets must expand, not defend
      ## - Prevents "fleet oscillation" where all fleets recall to homeworld

      # Skip defense for ETAC fleets (they need to colonize)
      let hasETAC = fleet.spaceLiftShips.anyIt(it.shipClass == ShipClass.ETAC)
      if hasETAC:
        # ETAC fleets prioritize expansion over defense
        continue

      # Position fleets at undefended colonies (especially high-value or frontier)
      var undefendedColony: Option[SystemId] = none(SystemId)
      let importantColonies = controller.identifyImportantColonies(filtered)

      # DEBUG logging (Phase 2f)
      if importantColonies.len > 0 and filtered.turn mod 10 == 0:
        echo "  [DEBUG] ", controller.houseId, " Turn ", filtered.turn, ": ", importantColonies.len, " important colonies found"

      for systemId in importantColonies:
        # Check if colony has any defensive fleet
        var hasDefense = false
        for otherFleet in myFleets:
          if otherFleet.location == systemId and otherFleet.id != fleet.id:
            hasDefense = true
            break

        # Check if colony has starbase
        let colonyOpt = getColony(filtered, systemId)
        if colonyOpt.isSome:
          let colony = colonyOpt.get()
          if colony.starbases.len > 0:
            hasDefense = true

        if not hasDefense:
          undefendedColony = some(systemId)
          break

      # If no important colony needs defense, check frontier colonies
      if undefendedColony.isNone:
        for colony in filtered.ownColonies:
          if colony.owner != controller.houseId:
            continue

          # Check if this is a frontier colony (adjacent to enemy territory)
          var isFrontier = false
          let adjacentIds = filtered.starMap.getAdjacentSystems(colony.systemId)
          for neighborId in adjacentIds:
            if isSystemColonized(filtered, neighborId):
              let neighborOpt = getColony(filtered, neighborId)
              if neighborOpt.isSome:
                let neighbor = neighborOpt.get()
                if neighbor.owner != controller.houseId:
                  isFrontier = true
                  break

          if isFrontier:
            # Check if colony has defensive fleet
            var hasDefense = false
            for otherFleet in myFleets:
              if otherFleet.location == colony.systemId and otherFleet.id != fleet.id:
                hasDefense = true
                break

            if colony.starbases.len > 0:
              hasDefense = true

            if not hasDefense:
              undefendedColony = some(colony.systemId)
              break

      if undefendedColony.isSome:
        # Move to guard undefended colony
        if fleet.location != undefendedColony.get():
          order.orderType = FleetOrderType.Move
          order.targetSystem = undefendedColony
        else:
          # Already at colony - patrol to maintain presence
          order.orderType = FleetOrderType.Patrol
          order.targetSystem = some(fleet.location)
        order.targetFleet = none(FleetId)
        result.add(order)
        continue

      # Priority 6: Exploration - send fleets to unknown systems
      # Instead of sitting idle, explore uncolonized systems
      if p.expansionDrive > 0.2 or rng.rand(1.0) < 0.3:
        let exploreTarget = findNearestUncolonizedSystem(filtered, fleet.location, fleet.id)
        if exploreTarget.isSome:
          order.orderType = FleetOrderType.Move
          order.targetSystem = exploreTarget
          order.targetFleet = none(FleetId)
          result.add(order)
          continue

      # Default: Patrol current location
      order.orderType = FleetOrderType.Patrol
      order.targetSystem = some(fleet.location)
      order.targetFleet = none(FleetId)
      result.add(order)
      continue

    # SHOULD NEVER REACH HERE - all priorities should end with continue or result.add+continue
    when not defined(release):
      logWarn(LogCategory.lcAI, &"Fleet {fleet.id} reached end of order generation without being handled!")

  when not defined(release):
    logDebug(LogCategory.lcAI, &"{controller.houseId} generated {result.len} fleet orders")

proc hasViableColonizationTargets(filtered: FilteredGameState, houseId: HouseId): bool =
  ## Returns true if there is at least one reachable uncolonized system
  ## THE CORRECT QUESTION: "Can I still colonize?" not "Do I have enough ETACs?"
  ## This prevents building useless ETACs when all systems are colonized

  # Quick check: are there ANY uncolonized systems at all?
  var hasUncolonized = false
  for systemId, system in filtered.starMap.systems:
    if not isSystemColonized(filtered, systemId):
      hasUncolonized = true
      break

  if not hasUncolonized:
    return false  # All systems colonized - no point building ETACs

  # Check if we have any colonies that could send an ETAC
  for colony in filtered.ownColonies:
    if colony.owner == houseId:
      # Can this colony reach an uncolonized system?
      # Use the existing pathfinding logic
      for targetId, targetSys in filtered.starMap.systems:
        if not isSystemColonized(filtered, targetId):
          # Found an uncolonized system - is it reachable?
          # Simple check: if there's a path, colonization is viable
          # (More sophisticated: check for safe routes, but start simple)
          return true

  return false

proc hasIdleETAC(filtered: FilteredGameState, houseId: HouseId): bool =
  ## Returns true if we have an ETAC with PTU at a HIGH-PRODUCTION colony ready to colonize
  ## PHASE 2B FIX: Only count ETACs at productive colonies (50+ PU) - prevents blocking
  ## when ETAC is at remote low-production colony

  # Only check unassigned ETACs at high-production colonies
  for colony in filtered.ownColonies:
    if colony.owner != houseId:
      continue

    # PHASE 2B: Only count as "idle" if at high-production colony (can build replacement fast)
    if colony.production < 50:
      continue

    if colony.unassignedSpaceLiftShips.len > 0:
      for spaceLift in colony.unassignedSpaceLiftShips:
        if spaceLift.shipClass == ShipClass.ETAC:
          # Check if ETAC has colonist cargo loaded
          if spaceLift.cargo.cargoType == CargoType.Colonists and spaceLift.cargo.quantity > 0:
            return true

  # Check fleets at high-production owned colonies
  for fleet in filtered.ownFleets:
    if fleet.owner != houseId:
      continue

    # Is fleet at a high-production owned colony?
    var atHighProdColony = false
    for colony in filtered.ownColonies:
      if colony.owner == houseId and colony.systemId == fleet.location and colony.production >= 50:
        atHighProdColony = true
        break

    if atHighProdColony:
      for spaceLift in fleet.spaceLiftShips:
        if spaceLift.shipClass == ShipClass.ETAC:
          # Check if ETAC has colonist cargo loaded
          if spaceLift.cargo.cargoType == CargoType.Colonists and spaceLift.cargo.quantity > 0:
            return true

  return false

proc generateBuildOrders(controller: AIController, filtered: FilteredGameState, rng: var Rand): seq[BuildOrder] =
  ## COMPREHENSIVE 4X STRATEGIC AI - Handles all asset types intelligently
  ## Ships: Combat warships, fighters, carriers, raiders, scouts, ETACs, transports
  ## Defenses: Starbases, planetary shields, ground batteries, armies, marines
  ## Facilities: Spaceports, shipyards, infrastructure
  result = @[]
  let p = controller.personality
  let house = filtered.ownHouse
  let myColonies = getOwnedColonies(filtered, controller.houseId)

  if myColonies.len == 0:
    return  # No colonies, can't build

  # ==========================================================================
  # ASSET INVENTORY - Count existing assets
  # ==========================================================================
  var scoutCount = 0
  var raiderCount = 0
  var carrierCount = 0
  var fighterCount = 0
  var etacCount = 0  # DEPRECATED: Global count (includes committed ETACs)
  var transportCount = 0
  var militaryCount = 0
  var capitalShipCount = 0  # BB, BC, DN, SD
  var starbaseCount = 0

  # BALANCE FIX: Count squadrons in fleets AND unassigned squadrons
  # ARCHITECTURE FIX: Count spacelift ships separately (NOT in squadrons)
  for fleet in filtered.ownFleets:
    if fleet.owner == controller.houseId:
      # Count combat squadrons
      for squadron in fleet.squadrons:
        case squadron.flagship.shipClass:
        of ShipClass.Scout:
          scoutCount += 1
        of ShipClass.Raider:
          raiderCount += 1
        of ShipClass.Carrier, ShipClass.SuperCarrier:
          carrierCount += 1
        of ShipClass.Fighter:
          fighterCount += 1
        of ShipClass.Battleship, ShipClass.Battlecruiser,
           ShipClass.Dreadnought, ShipClass.SuperDreadnought:
          capitalShipCount += 1
          militaryCount += 1
        of ShipClass.Starbase:
          starbaseCount += 1
        else:
          if squadron.flagship.shipType == ShipType.Military:
            militaryCount += 1

        for ship in squadron.ships:
          case ship.shipClass:
          of ShipClass.Scout:
            scoutCount += 1
          of ShipClass.Raider:
            raiderCount += 1
          of ShipClass.Fighter:
            fighterCount += 1
          else:
            if ship.shipType == ShipType.Military:
              militaryCount += 1

      # ARCHITECTURE FIX: Count spacelift ships separately
      for spaceLiftShip in fleet.spaceLiftShips:
        case spaceLiftShip.shipClass:
        of ShipClass.ETAC:
          etacCount += 1
        of ShipClass.TroopTransport:
          transportCount += 1
        else:
          discard  # Shouldn't happen, spacelift ships are only ETAC/TroopTransport

  # BALANCE FIX: Also count unassigned squadrons and spacelift ships at colonies
  for colony in myColonies:
    # Count unassigned combat squadrons
    for squadron in colony.unassignedSquadrons:
      case squadron.flagship.shipClass:
      of ShipClass.Scout:
        scoutCount += 1
      of ShipClass.Raider:
        raiderCount += 1
      of ShipClass.Carrier, ShipClass.SuperCarrier:
        carrierCount += 1
      of ShipClass.Fighter:
        fighterCount += 1
      of ShipClass.Battleship, ShipClass.Battlecruiser,
         ShipClass.Dreadnought, ShipClass.SuperDreadnought:
        capitalShipCount += 1
        militaryCount += 1
      of ShipClass.Starbase:
        starbaseCount += 1
      else:
        if squadron.flagship.shipType == ShipType.Military:
          militaryCount += 1

    # ARCHITECTURE FIX: Count unassigned spacelift ships
    for spaceLiftShip in colony.unassignedSpaceLiftShips:
      case spaceLiftShip.shipClass:
      of ShipClass.ETAC:
        etacCount += 1
      of ShipClass.TroopTransport:
        transportCount += 1
      else:
        discard

  # ==========================================================================
  # RESOURCE MANAGEMENT - Calculate maintenance affordability
  # ==========================================================================

  # Calculate total production across all colonies
  var totalProduction = 0
  for colony in myColonies:
    totalProduction += colony.production

  # Estimate current maintenance costs (approximate from squadron/spacelift counts)
  # Average maintenance: ~2 PP per squadron, ~1 PP per spacelift ship
  let totalSquadrons = militaryCount + scoutCount + raiderCount + carrierCount + fighterCount + starbaseCount
  let totalSpaceLift = etacCount + transportCount
  let estimatedMaintenance = (totalSquadrons * 2) + totalSpaceLift

  # Calculate maintenance buffer - how much production is left after maintenance
  let maintenanceBuffer = totalProduction - estimatedMaintenance
  let maintenanceRatio = if totalProduction > 0:
    float(estimatedMaintenance) / float(totalProduction)
  else:
    0.0

  # CRITICAL: AI should NOT build new ships if maintenance is already consuming too much
  # Target: Keep maintenance under 40% of production to allow for growth/colonization
  # This prevents death spirals where maintenance consumes all production
  # Formula: Allow building if (maintenance < 40% of production) AND (buffer > 20 PP)
  let canAffordMoreShips = maintenanceRatio < 0.4 and maintenanceBuffer > 20

  # Check squadron limit based on actual PU level
  # Formula from military.toml: House PU / 100 (min 8)
  # Calculate total PU from colonies
  var totalPU = 0
  for colony in myColonies:
    totalPU += colony.population  # Population units = PU

  let squadronLimit = max(8, totalPU div 100)
  # Add 1-squadron buffer to account for ships completing from previous builds
  let atSquadronLimit = totalSquadrons >= (squadronLimit - 1)

  # ==========================================================================
  # STRATEGIC ASSESSMENT - What does this AI need?
  # ==========================================================================

  # Assess military situation
  let myMilitaryStrength = calculateMilitaryStrength(filtered, controller.houseId)
  var totalEnemyStrength = 0
  var hasEnemies = false
  for otherHouse in filtered.housePrestige.keys:
    if otherHouse != controller.houseId:
      let dipState = dip_types.getDiplomaticState(
        house.diplomaticRelations,
        otherHouse
      )
      if dipState == dip_types.DiplomaticState.Enemy:
        totalEnemyStrength += calculateMilitaryStrength(filtered, otherHouse)
        hasEnemies = true

  let militaryRatio = if totalEnemyStrength > 0:
    float(myMilitaryStrength) / float(totalEnemyStrength)
  else:
    2.0  # No declared enemies

  # Check for threatened colonies
  var threatenedColonies = 0
  var criticalThreat = false
  for colony in myColonies:
    let combat = assessCombatSituation(controller, filtered, colony.systemId)
    if combat.recommendRetreat or combat.recommendReinforce:
      threatenedColonies += 1
      if combat.recommendRetreat:
        criticalThreat = true

  # Strategic needs assessment - Phase 2c: Scout Operational Modes
  # Need 5-7 scouts: 2-3 for espionage missions, 3+ for ELI mesh on invasions
  # EARLY GAME: Delay scouts until economy established (turn 5+ AND 3+ colonies)
  # Changed from "or" to "and" logic - was blocking ALL scout builds in 7-turn tests
  let isEarlyGame = filtered.turn < 5 and myColonies.len < 3
  let needScouts = scoutCount < 2 and not isEarlyGame  # Start with 2 scouts for intel
  let needMoreScouts = scoutCount < 5 and p.techPriority >= 0.3 and not isEarlyGame
  let needELIMesh = scoutCount < 7 and p.aggression >= 0.3

  # ========================================================================
  # STRATEGIC MATURITY: "Can I still colonize?" not "Do I have enough ETACs?"
  # ========================================================================
  # ETACs are ONLY useful for colonization. Once all systems are colonized,
  # switch to Troop Transports for conquest. This is the correct 4X progression.
  let canColonize = hasViableColonizationTargets(filtered, controller.houseId)
  let hasIdleETACWaiting = hasIdleETAC(filtered, controller.houseId)
  let needETACs = canColonize and not hasIdleETACWaiting and p.expansionDrive > 0.3

  # EARLY GAME: Need cheap exploration/combat ships (frigates) before expensive military
  # Frigates cost 30 PP (vs 80+ for cruisers), build time 1 turn
  # Build 3-5 frigates early for exploration and basic defense
  let needFrigates = isEarlyGame and militaryCount < 5 and p.expansionDrive > 0.3

  # PRESTIGE OPTIMIZATION: Invasions give +10 prestige (highest single gain)
  # Build transports for aggressive AIs to enable invasions
  let needTransports = (
    transportCount < 1 and
    (p.aggression > 0.4 or p.expansionDrive > 0.6) and  # Lower threshold
    militaryCount > 3
  )

  # Military needs - MUCH more nuanced
  # BALANCE FIX: Made military building more aggressive to enable combat
  let militaryFocus = 1.0 - p.economicFocus
  let needMilitary = (
    militaryRatio < 1.0 or  # Was: 0.8 - now build until parity or better
    threatenedColonies > 0 or  # Colonies under threat
    (p.aggression > 0.4 and militaryCount < 8) or  # Was: 0.6 & 10 - more aggressive
    (militaryFocus > 0.6 and militaryCount < 12) or  # Military-focused: build big fleet
    militaryCount < 2  # Was: 3 - minimum defense lower to prioritize offense
  )

  # PRESTIGE OPTIMIZATION: Starbases give +5 prestige when destroyed (enemy)
  # Losing starbases costs -5 prestige. Build for all important colonies.
  let needDefenses = (
    threatenedColonies > 0 or  # Under attack
    starbaseCount < myColonies.len or  # Starbases for all colonies
    (hasEnemies and militaryCount < 5) or  # Enemies exist but weak military
    (starbaseCount == 0 and myColonies.len > 0)  # Always have at least one starbase
  )

  # Phase 2d: Build Raiders if we've researched CLK (cloaking advantage)
  let hasCLK = house.techTree.levels.cloakingTech > 0
  let needRaiders = (
    hasCLK and raiderCount < 3 and p.aggression > 0.4 and militaryCount > 3
  )

  let needCarriers = (
    fighterCount > 3 and carrierCount == 0 and house.treasury > 150
  )

  # Phase 2e: Fighter build strategy
  # Build fighters for aggressive/military-focused AIs
  # Start with small number even without carriers (they stay at colonies until carriers built)
  let needFighters = (
    p.aggression >= 0.3 and fighterCount < 8 and
    house.treasury > 60  # Can afford fighter + maintenance (fighter cost = 20 PP)
  )

  # ==========================================================================
  # BUILD DECISION LOGIC - Priority order with dynamic decision making
  # ==========================================================================

  # Build at most productive colonies first
  var coloniesToBuild = myColonies
  coloniesToBuild.sort(proc(a, b: Colony): int = cmp(b.production, a.production))

  for colony in coloniesToBuild:
    if house.treasury < 30:
      break  # Not enough funds for anything

    let hasShipyard = colony.shipyards.len > 0
    let hasSpaceport = colony.spaceports.len > 0
    let hasStarbase = colony.starbases.len > 0
    let needsInfrastructure = not hasSpaceport or not hasShipyard

    # ------------------------------------------------------------------------
    # INFRASTRUCTURE: Build spaceports/shipyards when needed for military
    # EARLY GAME FIX: Don't block ETAC building - homeworld starts with shipyard
    # ------------------------------------------------------------------------
    if not hasShipyard and (needMilitary or p.aggression > 0.4):
      # No shipyard at all - need to build one (shouldn't happen at homeworld)
      if hasSpaceport and house.treasury >= 150:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Building,
          quantity: 1,
          shipClass: none(ShipClass),
          buildingType: some("Shipyard"),
          industrialUnits: 0
        ))
        break  # Build shipyard first
      elif not hasSpaceport and house.treasury >= 100:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Building,
          quantity: 1,
          shipClass: none(ShipClass),
          buildingType: some("Spaceport"),
          industrialUnits: 0
        ))
        break  # Build spaceport first

    if not hasShipyard:
      continue  # Can't build ships without shipyard

    # ------------------------------------------------------------------------
    # CRISIS RESPONSE: Critical threats get immediate defense
    # ------------------------------------------------------------------------
    if criticalThreat:
      let combat = assessCombatSituation(controller, filtered, colony.systemId)
      if combat.recommendRetreat:
        # This colony is under critical attack - emergency defenses
        if not hasStarbase and house.treasury >= 300:
          result.add(BuildOrder(
            colonySystem: colony.systemId,
            buildType: BuildType.Ship,
            quantity: 1,
            shipClass: some(ShipClass.Starbase),
            buildingType: none(string),
            industrialUnits: 0
          ))
          break
        elif colony.groundBatteries < 5 and house.treasury >= 20:
          result.add(BuildOrder(
            colonySystem: colony.systemId,
            buildType: BuildType.Building,
            quantity: 1,
            shipClass: none(ShipClass),
            buildingType: some("GroundBattery"),
            industrialUnits: 0
          ))
          break

    # ------------------------------------------------------------------------
    # EARLY GAME: Initial exploration and expansion
    # CRITICAL: ETACs BEFORE scouts - colonize first, intel second
    # Priority: ETACs → Frigates → Scouts
    # CRITICAL FIX: Don't break after ETAC - allow multiple builds per turn
    # ------------------------------------------------------------------------
    # ========================================================================
    # ETAC BUILD LOGIC: Only build if colonization is still viable
    # ========================================================================
    if needETACs:
      let etacCost = getShipConstructionCost(ShipClass.ETAC)
      # Build on high-production colonies only (efficient ETAC production)
      if house.treasury >= etacCost and colony.production >= 50:
        # ALWAYS LOG: Critical for diagnosing colonization deadlock
        logInfo(LogCategory.lcAI, &"{controller.houseId} building ETAC at colony {colony.systemId} - " &
                &"colonization targets available (expansionDrive: {p.expansionDrive:.2f}, " &
                &"treasury: {house.treasury} PP, production: {colony.production} PU)")
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.ETAC),
          buildingType: none(string),
          industrialUnits: 0
        ))
        # Continue to allow other colonies to build if needed
      else:
        # ALWAYS LOG: Critical for diagnosing why ETACs aren't being built
        if house.treasury < etacCost:
          logDebug(LogCategory.lcAI, &"{controller.houseId} cannot build ETAC at {colony.systemId} - " &
                   &"insufficient funds (need {etacCost} PP, have {house.treasury} PP)")
        elif colony.production < 50:
          logDebug(LogCategory.lcAI, &"{controller.houseId} skipping ETAC build at {colony.systemId} - " &
                   &"low production ({colony.production} PU, need 50+ PU)")
    else:
      # ALWAYS LOG: Critical for understanding expansion strategy
      if not canColonize:
        logDebug(LogCategory.lcAI, &"{controller.houseId} not building ETAC - no viable colonization targets")
      elif hasIdleETACWaiting:
        logDebug(LogCategory.lcAI, &"{controller.houseId} not building ETAC - idle ETAC already available")
      elif p.expansionDrive <= 0.3:
        logDebug(LogCategory.lcAI, &"{controller.houseId} not building ETAC - low expansionDrive ({p.expansionDrive:.2f})")

    # ========================================================================
    # CONQUEST PHASE: Switch to Troop Transports when colonization ends
    # ========================================================================
    if not canColonize and p.aggression > 0.4 and myColonies.len >= 4:
      # No more colonies → switch to invasion fleet buildup
      let transportCost = getShipConstructionCost(ShipClass.TroopTransport)
      if house.treasury >= transportCost and colony.production >= 80 and rng.rand(1.0) < 0.7:
        logInfo(LogCategory.lcAI, &"{controller.houseId} building Troop Transport at colony {colony.systemId} - " &
                &"CONQUEST PHASE (no colonization targets left, aggression: {p.aggression:.2f})")
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.TroopTransport),
          buildingType: none(string),
          industrialUnits: 0
        ))

    # Early game frigates for cheap exploration and combat
    # Cost 30 PP, build time 1 turn, can explore and fight
    if needFrigates:
      let frigateCost = getShipConstructionCost(ShipClass.Frigate)
      if house.treasury >= frigateCost and canAffordMoreShips and not atSquadronLimit:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.Frigate),
          buildingType: none(string),
          industrialUnits: 0
        ))
        break

    if needScouts:
      let scoutCost = getShipConstructionCost(ShipClass.Scout)
      if house.treasury >= scoutCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.Scout),
          buildingType: none(string),
          industrialUnits: 0
        ))
        break

    # ------------------------------------------------------------------------
    # Marine Garrison Management
    # MOVED AFTER ETACs: Marines are defensive, colonization is strategic
    # ------------------------------------------------------------------------
    if controller.shouldBuildMarines(filtered, colony):
      # This colony needs more marines for garrison
      if house.treasury >= 30:  # Cost of marines
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Building,
          quantity: 1,
          shipClass: none(ShipClass),
          buildingType: some("Marines"),
          industrialUnits: 0
        ))
        break  # Build marines, then check next colony

    # ------------------------------------------------------------------------
    # MID GAME: Military buildup and defense
    # ------------------------------------------------------------------------

    # Phase 2e: Fighter squadrons for aggressive AIs
    if needFighters:
      let fighterCost = getShipConstructionCost(ShipClass.Fighter)
      if house.treasury >= fighterCost and canAffordMoreShips and not atSquadronLimit:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.Fighter),
          buildingType: none(string),
          industrialUnits: 0
        ))
        break  # One at a time to avoid treasury depletion

    # Phase 2e: Starbases for fighter capacity (1 per 5 fighters rule)
    # Per assets.md:2.4.1: "Requires 1 operational Starbase per 5 FS (ceil)"
    let fightersAtColony = colony.fighterSquadrons.len
    let requiredStarbases = (fightersAtColony + 4) div 5  # Ceiling division
    let currentStarbases = colony.starbases.len
    if fightersAtColony > 0 and currentStarbases < requiredStarbases:
      # Need more starbases to support fighter capacity
      if house.treasury >= 300 and canAffordMoreShips and not atSquadronLimit:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.Starbase),
          buildingType: none(string),
          industrialUnits: 0
        ))
        break

    # Starbases for defense (before expensive military buildup)
    # RESOURCE MANAGEMENT: Starbases also have maintenance, check affordability
    if needDefenses and not hasStarbase and house.treasury >= 300 and canAffordMoreShips and not atSquadronLimit:
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(ShipClass.Starbase),
        buildingType: none(string),
        industrialUnits: 0
      ))
      break

    # Military ships - COMPREHENSIVE SHIP SELECTION
    # RESOURCE MANAGEMENT: Only build if we can afford maintenance
    if needMilitary and canAffordMoreShips and not atSquadronLimit:
      var shipClass: ShipClass
      var shipCost: int

      # Choose ship based on treasury, aggression, and strategic needs
      if house.treasury > 100 and needRaiders:
        # Raiders for ambush tactics (requires CLK research)
        shipClass = ShipClass.Raider
      elif house.treasury > 120 and needCarriers:
        # Carriers for fighter projection
        shipClass = ShipClass.Carrier
      elif house.treasury > 150 and capitalShipCount < 2 and p.aggression > 0.6:
        # Build at least 2 capital ships for aggressive AIs
        shipClass = ShipClass.Battleship
      elif house.treasury > 100 and militaryCount < 5:
        # Early military: Battle Cruisers
        shipClass = ShipClass.Battlecruiser
      elif house.treasury > 80:
        # Mid-tier: Heavy Cruisers
        shipClass = ShipClass.HeavyCruiser
      elif house.treasury > 60:
        # Mid-tier: Cruisers and Light Cruisers
        shipClass = if rng.rand(1.0) > 0.5: ShipClass.Cruiser else: ShipClass.LightCruiser
      elif house.treasury > 40:
        # Budget: Destroyers
        shipClass = ShipClass.Destroyer
      elif house.treasury > 30:
        # Cheap: Frigates
        shipClass = ShipClass.Frigate
      else:
        # Last resort: Corvettes
        shipClass = ShipClass.Corvette

      shipCost = getShipConstructionCost(shipClass)
      if house.treasury >= shipCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(shipClass),
          buildingType: none(string),
          industrialUnits: 0
        ))
        break

    # Ground defenses for threatened colonies
    if threatenedColonies > 0 and colony.groundBatteries < 5:
      let batteryCost = getBuildingCost("GroundBattery")
      if house.treasury >= batteryCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Building,
          quantity: 1,
          shipClass: none(ShipClass),
          buildingType: some("GroundBattery"),
          industrialUnits: 0
        ))
        break

    # IMPROVEMENT: Proactive garrison management
    # Build marine garrisons BEFORE invasions threaten, not after
    # # Strategic priorities:
    # - Homeworld: 5+ marine garrison (critical)
    # - Important colonies: 3+ marines (high production, resources)
    # - Frontier colonies: 1-2 marines (minimum defense)
    # - Prepare marines for loading onto transports for invasions

    let isHomeworld = (colony.systemId == filtered.starMap.playerSystemIds[0])  # Assume homeworld
    let isImportant = (colony.production >= 50 or colony.resources == ResourceRating.Abundant)
    let isFrontier = (threatenedColonies > 0)  # Near enemies

    var targetGarrison = 0
    if isHomeworld:
      targetGarrison = 5  # Homeworld: strong garrison
    elif isImportant:
      targetGarrison = 3  # Important: medium garrison
    elif hasEnemies:
      targetGarrison = 2  # Any colony when enemies exist: minimum garrison
    else:
      targetGarrison = 1  # Peacetime: minimal garrison

    # Build marines proactively if below target
    if colony.marines < targetGarrison:
      let marineCost = getBuildingCost("Marines")
      if house.treasury >= marineCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Building,
          quantity: 1,
          shipClass: none(ShipClass),
          buildingType: some("Marines"),
          industrialUnits: 0
        ))
        break

    # Build extra marines for invasion preparation
    # If we have transports but they're not loaded (engine limitation!),
    # at least ensure colonies have spare marines available
    if needTransports and transportCount > 0 and colony.marines < targetGarrison + 2:
      let marineCost = getBuildingCost("Marines")
      if house.treasury >= marineCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Building,
          quantity: 1,
          shipClass: none(ShipClass),
          buildingType: some("Marines"),
          industrialUnits: 0
        ))
        break

    # ------------------------------------------------------------------------
    # LATE GAME: Specialized assets and optimization
    # ------------------------------------------------------------------------

    # Additional scouts for ELI mesh networks (Phase 2c)
    if (needMoreScouts or needELIMesh) and scoutCount < 7:
      let scoutCost = getShipConstructionCost(ShipClass.Scout)
      if house.treasury >= scoutCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.Scout),
          buildingType: none(string),
          industrialUnits: 0
        ))
        break

    # Troop transports for invasion capability
    if needTransports:
      let transportCost = getShipConstructionCost(ShipClass.TroopTransport)
      if house.treasury >= transportCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.TroopTransport),
          buildingType: none(string),
          industrialUnits: 0
        ))
        break

    # Economic infrastructure
    if p.economicFocus > 0.6 and colony.infrastructure < 10 and house.treasury >= 150:
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Infrastructure,
        quantity: 1,
        shipClass: none(ShipClass),
        buildingType: none(string),
        industrialUnits: 1
      ))
      break

proc calculateFighterCapacityUtilization(filtered: FilteredGameState, houseId: HouseId): float =
  ## Calculate percentage of fighter capacity currently used
  ## Phase 2e: Used to determine when to research Fighter Doctrine
  var totalFighters = 0
  var totalCapacity = 0

  for colony in filtered.ownColonies:
    if colony.owner == houseId:
      totalFighters += colony.fighterSquadrons.len
      # Calculate max capacity: floor(PU / 100) × FD multiplier
      let baseCapacity = colony.production div 100
      # FD multiplier from tech level (engine handles this, but we estimate)
      let fdMultiplier = filtered.ownHouse.techTree.levels.fighterDoctrine
      totalCapacity += baseCapacity * fdMultiplier

  if totalCapacity == 0:
    return 0.0

  return float(totalFighters) / float(totalCapacity)

proc generateResearchAllocation(controller: AIController, filtered: FilteredGameState): res_types.ResearchAllocation =
  ## Allocate research PP based on strategy
  ## Per economy.md:4.0:
  ## - Economic Level (EL) purchased with ERP
  ## - Science Level (SL) purchased with SRP
  ## - Technologies (CST, WEP, etc.) purchased with TRP
  result = res_types.ResearchAllocation(
    economic: 0,
    science: 0,
    technology: initTable[TechField, int]()
  )

  let p = controller.personality
  let house = filtered.ownHouse

  # Calculate available PP budget from production
  # Get house's production from all colonies
  var totalProduction = 0
  for colony in filtered.ownColonies:
    if colony.owner == controller.houseId:
      totalProduction += colony.production

  # Allocate percentage of production to research based on tech priority
  let researchBudget = int(float(totalProduction) * p.techPriority)

  if researchBudget > 0:
    # Distribute research budget across EL/SL/TRP based on strategy
    if p.techPriority > 0.6:
      # Heavy research investment - balance across all three categories
      result.economic = researchBudget div 3        # 33% to EL
      result.science = researchBudget div 4         # 25% to SL

      # Remaining ~42% to technologies
      let techBudget = researchBudget - result.economic - result.science

      # Phase 2e: Check if we should prioritize Fighter Doctrine/ACO
      let capacityUtil = calculateFighterCapacityUtilization(filtered, controller.houseId)
      let needFD = capacityUtil > 0.7  # Research FD when >70% capacity used
      let fdLevel = house.techTree.levels.fighterDoctrine
      let acoLevel = house.techTree.levels.advancedCarrierOps

      if p.aggression > 0.5:
        # Aggressive: weapons + cloaking for Raiders (Phase 2d) + fighters (Phase 2e)
        if needFD and fdLevel < 3:
          # High capacity utilization - prioritize FD to expand fighter capacity
          result.technology[TechField.FighterDoctrine] = techBudget div 4     # 25%
          result.technology[TechField.AdvancedCarrierOps] = techBudget div 5  # 20% (synergy)
          result.technology[TechField.WeaponsTech] = techBudget div 4          # 25%
          result.technology[TechField.CloakingTech] = techBudget div 10        # 10%
          result.technology[TechField.ConstructionTech] = techBudget div 10    # 10%
          result.technology[TechField.ElectronicIntelligence] = techBudget div 10  # 10%
        else:
          # Standard aggressive research allocation
          result.technology[TechField.WeaponsTech] = techBudget * 2 div 5  # 40%
          result.technology[TechField.CloakingTech] = techBudget div 5     # 20% (for Raider ambush)
          result.technology[TechField.ConstructionTech] = techBudget div 5 # 20%
          result.technology[TechField.ElectronicIntelligence] = techBudget div 5  # 20%
      else:
        # Peaceful: infrastructure + counter-intel for defense
        result.technology[TechField.ConstructionTech] = techBudget div 2
        result.technology[TechField.TerraformingTech] = techBudget div 4
        result.technology[TechField.CounterIntelligence] = techBudget div 4

    elif p.techPriority >= 0.4:
      # Moderate research - focus on fundamentals (EL/SL)
      result.economic = researchBudget div 2        # 50% to EL
      result.science = researchBudget div 3         # 33% to SL

      # Remaining ~17% to key tech(s)
      let techBudget = researchBudget - result.economic - result.science
      if p.aggression > 0.5:
        # Aggressive with moderate tech: split between weapons and cloaking
        result.technology[TechField.WeaponsTech] = techBudget * 2 div 3  # 67%
        result.technology[TechField.CloakingTech] = techBudget div 3      # 33%
      else:
        result.technology[TechField.ConstructionTech] = techBudget
    else:
      # Minimal research - just EL for economic growth
      result.economic = researchBudget

proc generateDiplomaticActions(controller: AIController, filtered: FilteredGameState, rng: var Rand): seq[DiplomaticAction] =
  ## Generate diplomatic actions based on strategic assessment
  result = @[]
  let p = controller.personality
  let myHouse = filtered.ownHouse

  # Priority 0: Respond to pending proposals
  # AI must respond to proposals before proposing new actions
  # TODO: FilteredGameState needs to expose pending proposals
  #[
  for proposal in filtered.pendingProposals:
    if proposal.target == controller.houseId and proposal.status == dip_proposals.ProposalStatus.Pending:
      # Assess the proposer
      let assessment = assessDiplomaticSituation(controller, filtered, proposal.proposer)

      # Decision logic: Accept if beneficial, reject if enemy, wait if uncertain
      if assessment.recommendPact and not assessment.recommendEnemy:
        # Accept proposal
        result.add(DiplomaticAction(
          targetHouse: proposal.proposer,
          actionType: DiplomaticActionType.AcceptProposal,
          proposalId: some(proposal.id),
          message: none(string)
        ))
        return result  # Only one action per turn

      elif assessment.recommendEnemy or proposal.expiresIn <= 1:
        # Reject if enemy or about to expire
        result.add(DiplomaticAction(
          targetHouse: proposal.proposer,
          actionType: DiplomaticActionType.RejectProposal,
          proposalId: some(proposal.id),
          message: none(string)
        ))
        return result  # Only one action per turn

      # Otherwise wait and think about it (let it pend)
  ]#

  # Assess all other houses
  var assessments: seq[DiplomaticAssessment] = @[]
  for otherHouseId in filtered.housePrestige.keys:
    if otherHouseId == controller.houseId:
      continue
    assessments.add(assessDiplomaticSituation(controller, filtered, otherHouseId))

  # Priority 1: Break pacts if strategically advantageous (rare)
  # PRESTIGE OPTIMIZATION: Pact violations cost -10 prestige - avoid unless huge advantage
  for assessment in assessments:
    if assessment.recommendBreak and assessment.currentState == dip_types.DiplomaticState.NonAggression:
      # Double-check with random roll to avoid too frequent violations (-10 prestige penalty)
      if rng.rand(1.0) < 0.2:  # Only 20% chance even when recommended
        result.add(DiplomaticAction(
          targetHouse: assessment.targetHouse,
          actionType: DiplomaticActionType.BreakPact
        ))
        return result  # Only one action per turn

  # Priority 2: Propose pacts with strategic partners
  # PRESTIGE OPTIMIZATION: Forming pacts gives +5 prestige - pursue actively
  # BALANCE FIX: Don't form pacts too aggressively - creates peaceful meta
  for assessment in assessments:
    if assessment.recommendPact and assessment.currentState == dip_types.DiplomaticState.Neutral:
      # Check if we can form pacts (not isolated)
      if dip_types.canFormPact(myHouse.violationHistory):
        # Check if we can reinstate with this specific house
        if dip_types.canReinstatePact(myHouse.violationHistory, assessment.targetHouse, filtered.turn):
          # BALANCE FIX: Only form pacts if diplomatic-focused OR random chance
          # This prevents everyone from pacting with everyone
          let pactChance = if p.diplomacyValue > 0.6: 0.6 else: 0.2
          if rng.rand(1.0) < pactChance:
            result.add(DiplomaticAction(
              targetHouse: assessment.targetHouse,
              actionType: DiplomaticActionType.ProposeNonAggressionPact
            ))
            return result  # Only one action per turn

  # Priority 3: Declare enemy against weak/aggressive targets
  for assessment in assessments:
    if assessment.recommendEnemy and assessment.currentState == dip_types.DiplomaticState.Neutral:
      # Aggressive strategies more likely to declare enemies
      let declareChance = p.aggression * 0.5
      if rng.rand(1.0) < declareChance:
        result.add(DiplomaticAction(
          targetHouse: assessment.targetHouse,
          actionType: DiplomaticActionType.DeclareEnemy
        ))
        return result  # Only one action per turn

  # Priority 4: Normalize relations with dangerous enemies
  for assessment in assessments:
    if not assessment.recommendEnemy and assessment.currentState == dip_types.DiplomaticState.Enemy:
      # Only if we're significantly weaker
      if assessment.relativeMilitaryStrength < 0.6:
        result.add(DiplomaticAction(
          targetHouse: assessment.targetHouse,
          actionType: DiplomaticActionType.SetNeutral
        ))
        return result  # Only one action per turn

proc generateEspionageAction(controller: AIController, filtered: FilteredGameState, rng: var Rand): Option[esp_types.EspionageAttempt] =
  ## Generate espionage action based on strategy and personality
  ## Use personality weights to determine if we should use espionage
  let p = controller.personality
  let house = filtered.ownHouse

  # Check if we have EBP to use espionage (need at least 5 EBP for basic actions)
  if house.espionageBudget.ebpPoints < 5:
    return none(esp_types.EspionageAttempt)

  # CRITICAL: Don't do espionage if prestige is low
  # Detection costs -2 prestige, victims lose -1 to -7 prestige
  # If prestige < 20, focus on prestige-safe activities (expansion, tech, economy)
  if house.prestige < 20:
    return none(esp_types.EspionageAttempt)

  # Use espionage based on personality rather than strategy enum
  # High risk tolerance + low aggression = espionage focus
  let espionageChance = p.riskTolerance * 0.5 + (1.0 - p.aggression) * 0.3 + p.techPriority * 0.2

  # Reduce espionage frequency dramatically - it's a prestige drain
  # Even with high espionage personality, only 20% chance per turn
  if rng.rand(1.0) > (espionageChance * 0.2):
    return none(esp_types.EspionageAttempt)

  # Find a target house
  var targetHouses: seq[HouseId] = @[]
  for houseId in filtered.housePrestige.keys:
    if houseId != controller.houseId:
      targetHouses.add(houseId)

  if targetHouses.len == 0:
    return none(esp_types.EspionageAttempt)

  let target = targetHouses[rng.rand(targetHouses.len - 1)]

  # Simple espionage attempt (tech theft)
  return some(esp_types.EspionageAttempt(
    attacker: controller.houseId,
    target: target,
    action: esp_types.EspionageAction.TechTheft,
    targetSystem: none(SystemId)
  ))

# =============================================================================
# Main Order Generation
# =============================================================================

proc generatePopulationTransfers(controller: AIController, filtered: FilteredGameState, rng: var Rand): seq[PopulationTransferOrder] =
  ## Generate Space Guild population transfer orders
  ## Per config/population.toml and economy.md:3.7
  result = @[]
  let p = controller.personality
  let house = filtered.ownHouse

  # Only economically-focused AI uses population transfers
  if p.economicFocus < 0.5 or p.expansionDrive < 0.4:
    return result

  # Need minimum treasury (transfers are expensive)
  if house.treasury < 500:
    return result

  # Find overpopulated source colonies and underpopulated destinations
  var sources: seq[tuple[systemId: SystemId, pop: int]] = @[]
  var destinations: seq[tuple[systemId: SystemId, pop: int]] = @[]

  for colony in filtered.ownColonies:
    if colony.owner == controller.houseId:
      if colony.population > 15:  # Overpopulated
        sources.add((colony.systemId, colony.population))
      elif colony.population < 10 and colony.population > 0:  # Growing colony
        destinations.add((colony.systemId, colony.population))

  if sources.len == 0 or destinations.len == 0:
    return result

  # Transfer from highest pop source to lowest pop destination
  sources.sort(proc(a, b: auto): int = b.pop - a.pop)
  destinations.sort(proc(a, b: auto): int = a.pop - b.pop)

  # One transfer per turn (they're expensive)
  result.add(PopulationTransferOrder(
    sourceColony: sources[0].systemId,
    destColony: destinations[0].systemId,
    ptuAmount: 1  # Conservative: 1 PTU at a time
  ))

proc generateSquadronManagement(controller: AIController, filtered: FilteredGameState, rng: var Rand): seq[SquadronManagementOrder] =
  ## Generate squadron management orders (commissioning and fleet assignment)
  ## The engine auto-commissions ships, but AI can manually manage squadrons if needed
  result = @[]

  # Currently the engine handles auto-commissioning well
  # AI can add manual squadron management here if needed for advanced tactics
  # For now, rely on engine's automatic squadron formation

proc generateCargoManagement(controller: AIController, filtered: FilteredGameState, rng: var Rand): seq[CargoManagementOrder] =
  ## Generate cargo loading/unloading orders for spacelift operations
  ## Load marines for invasions, colonists for colonization
  result = @[]
  let p = controller.personality

  # Aggressive AI loads marines for invasions
  if p.aggression < 0.4:
    return result

  # Find fleets with spacelift capability at colonies
  for colony in filtered.ownColonies:
    if colony.owner != controller.houseId:
      continue

    # Check if we have fleets here with spacelift ships
    for fleet in filtered.ownFleets:
      if fleet.owner == controller.houseId and fleet.location == colony.systemId:
        # Check if fleet has spacelift capability
        var hasSpacelift = false
        for squadron in fleet.squadrons:
          if squadron.flagship.shipClass in [ShipClass.TroopTransport, ShipClass.ETAC]:
            hasSpacelift = true
            break

        if hasSpacelift:
          # Load marines if we have them and fleet isn't full
          if colony.marines > 5:
            result.add(CargoManagementOrder(
              houseId: controller.houseId,
              colonySystem: colony.systemId,
              action: CargoManagementAction.LoadCargo,
              fleetId: fleet.id,
              cargoType: some(CargoType.Marines),
              quantity: some(3)  # Load 3 marine units
            ))
            return result  # One cargo operation per turn

  return result

proc generateAIOrders*(controller: var AIController, filtered: FilteredGameState, rng: var Rand): OrderPacket =
  ## Generate complete order packet for an AI player using fog-of-war filtered view
  ##
  ## IMPORTANT: AI receives FilteredGameState, NOT full GameState
  ## This enforces limited visibility - AI only sees:
  ## - Own assets (full detail)
  ## - Enemy assets in occupied/owned systems
  ## - Stale intel from intelligence database
  ##
  ## Context available:
  ## - controller.lastTurnReport: Previous turn's report (for AI learning)
  ## - filtered: Fog-of-war filtered game state for this house
  ## - controller.personality: Strategic personality parameters
  ## - controller.intelligence: System intelligence reports
  ## - controller.operations: Coordinated operations
  ##
  ## TODO: Gradually refactor helper functions to use FilteredGameState directly
  ## For now, we create a temporary GameState-like structure for compatibility

  let p = controller.personality
  let house = filtered.ownHouse

  # Strategic planning before generating orders
  # Update operation status (check which fleets have reached assembly points)
  controller.updateOperationStatus(filtered)

  # Phase 2h: Update fallback routes (every 5 turns)
  if filtered.turn mod 5 == 0:
    controller.updateFallbackRoutes(filtered)

  # Manage strategic reserves (assign fleets to defend important colonies)
  controller.manageStrategicReserves(filtered)

  # Plan new coordinated operations if moderately aggressive and have free fleets
  # Threshold: 0.4 allows Balanced strategy (0.5) to invade, not just Aggressive (0.8)
  if p.aggression >= 0.4 and controller.countAvailableFleets(filtered) >= 2:
    let opportunities = controller.identifyInvasionOpportunities(filtered)
    if opportunities.len > 0:
      # Plan invasion of highest-value target
      controller.planCoordinatedInvasion(filtered, opportunities[0], filtered.turn)

  result = OrderPacket(
    houseId: controller.houseId,
    turn: filtered.turn,
    fleetOrders: generateFleetOrders(controller, filtered, rng),
    buildOrders: generateBuildOrders(controller, filtered, rng),
    researchAllocation: generateResearchAllocation(controller, filtered),
    diplomaticActions: generateDiplomaticActions(controller, filtered, rng),
    populationTransfers: generatePopulationTransfers(controller, filtered, rng),
    squadronManagement: generateSquadronManagement(controller, filtered, rng),
    cargoManagement: generateCargoManagement(controller, filtered, rng),
    espionageAction: generateEspionageAction(controller, filtered, rng),
    ebpInvestment: 0,
    cipInvestment: 0
  )

  # Set espionage budget based on personality (not strategy enum)
  # Use riskTolerance + (1-aggression) as proxy for espionage focus
  let espionageFocus = (p.riskTolerance + (1.0 - p.aggression)) / 2.0

  # CRITICAL: Base investment on PRODUCTION (PP), not treasury (IU)
  # This prevents catastrophic over-investment penalties
  let ebpCost = 15  # PP per EBP (from config/espionage.toml)
  let cipCost = 15  # PP per CIP (from config/espionage.toml)
  let safeThreshold = 10  # Stay at 10% threshold (from config/espionage.toml)
  let turnProduction = house.espionageBudget.turnBudget  # Actual production this turn

  # Calculate maximum safe budget that won't trigger penalties
  let maxSafeBudget = turnProduction * safeThreshold div 100

  if espionageFocus > 0.6:
    # High espionage focus - invest up to 10% of production (at threshold)
    let budget = maxSafeBudget
    result.ebpInvestment = min(budget div ebpCost, 50)
    result.cipInvestment = min((budget - (result.ebpInvestment * ebpCost)) div cipCost, 25)
  elif espionageFocus > 0.4:
    # Moderate espionage focus - invest up to 6% of production (below threshold)
    let budget = turnProduction * 6 div 100
    result.ebpInvestment = min(budget div ebpCost, 20)
    result.cipInvestment = min((budget - (result.ebpInvestment * ebpCost)) div cipCost, 10)
  else:
    # Low espionage focus - invest up to 3% of production (well below threshold)
    let budget = turnProduction * 3 div 100
    result.ebpInvestment = min(budget div ebpCost, 10)
    result.cipInvestment = min((budget - (result.ebpInvestment * ebpCost)) div cipCost, 5)

# =============================================================================
# Export
# =============================================================================

export AIStrategy, AIPersonality, AIController
export newAIController, generateAIOrders, getStrategyPersonality
