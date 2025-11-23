## AI Controller for Balance Testing
##
## Implements strategic decision-making for different AI personalities
## to enable realistic game simulations

import std/[tables, options, random, sequtils, strformat, algorithm]
import ../../src/engine/[gamestate, orders, fleet, squadron, starmap]
import ../../src/common/types/[core, units, tech, planets]
import ../../src/engine/espionage/types as esp_types
import ../../src/engine/research/types as res_types
import ../../src/engine/diplomacy/types as dip_types
import ../../src/engine/diplomacy/proposals as dip_proposals
import ../../src/engine/economy/construction

type
  AIStrategy* {.pure.} = enum
    ## Different AI play styles for balance testing
    Aggressive,      # Heavy military, early attacks
    Economic,        # Focus on growth and tech
    Espionage,       # Intelligence and sabotage
    Diplomatic,      # Pacts and manipulation
    Balanced,        # Mixed approach
    Turtle,          # Defensive, slow expansion
    Expansionist     # Rapid colonization

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
    operations*: seq[CoordinatedOperation]  ## PHASE 3: Planned multi-fleet operations
    reserves*: seq[StrategicReserve]        ## PHASE 3: Strategic reserve fleets

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
      economicFocus: 0.3,
      expansionDrive: 0.7,
      diplomacyValue: 0.2,
      techPriority: 0.4
    )
  of AIStrategy.Economic:
    AIPersonality(
      aggression: 0.2,
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
      expansionDrive: 0.4,
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
      aggression: 0.5,
      riskTolerance: 0.5,
      economicFocus: 0.5,
      expansionDrive: 0.5,
      diplomacyValue: 0.5,
      techPriority: 0.5
    )
  of AIStrategy.Turtle:
    AIPersonality(
      aggression: 0.1,
      riskTolerance: 0.2,
      economicFocus: 0.7,
      expansionDrive: 0.2,
      diplomacyValue: 0.7,
      techPriority: 0.7
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

proc newAIController*(houseId: HouseId, strategy: AIStrategy): AIController =
  ## Create a new AI controller for a house
  AIController(
    houseId: houseId,
    strategy: strategy,
    personality: getStrategyPersonality(strategy),
    intelligence: initTable[SystemId, IntelligenceReport](),
    operations: @[],
    reserves: @[]
  )

proc newAIControllerWithPersonality*(houseId: HouseId, personality: AIPersonality): AIController =
  ## Create a new AI controller with a custom personality (for genetic algorithm)
  AIController(
    houseId: houseId,
    strategy: AIStrategy.Balanced,  # Strategy field is unused with custom personality
    personality: personality,
    intelligence: initTable[SystemId, IntelligenceReport](),
    operations: @[],
    reserves: @[]
  )

# =============================================================================
# Helper Functions
# =============================================================================

proc getOwnedColonies(state: GameState, houseId: HouseId): seq[Colony] =
  ## Get all colonies owned by a house
  result = @[]
  for colony in state.colonies.values:
    if colony.owner == houseId:
      result.add(colony)

proc getOwnedFleets(state: GameState, houseId: HouseId): seq[Fleet] =
  ## Get all fleets owned by a house
  result = @[]
  for fleet in state.fleets.values:
    if fleet.owner == houseId:
      result.add(fleet)

proc getFleetStrength(fleet: Fleet): int =
  ## Calculate total attack strength of a fleet
  result = 0
  for squadron in fleet.squadrons:
    result += squadron.combatStrength()

proc findNearestUncolonizedSystem(state: GameState, fromSystem: SystemId): Option[SystemId] =
  ## Find nearest uncolonized system using cube distance
  ## Returns closest uncolonized system to avoid all AIs targeting the same one
  type SystemDist = tuple[systemId: SystemId, distance: int]
  var candidates: seq[SystemDist] = @[]

  let fromCoords = state.starMap.systems[fromSystem].coords

  for systemId, system in state.starMap.systems:
    if systemId notin state.colonies:
      # Calculate cube distance (Manhattan distance in hex coordinates)
      let dx = abs(system.coords.q - fromCoords.q)
      let dy = abs(system.coords.r - fromCoords.r)
      let dz = abs((system.coords.q + system.coords.r) - (fromCoords.q + fromCoords.r))
      let distance = (dx + dy + dz) div 2
      let item: SystemDist = (systemId: systemId, distance: distance)
      candidates.add(item)

  if candidates.len > 0:
    # Sort by distance and return closest
    candidates.sort(proc(a, b: SystemDist): int = cmp(a.distance, b.distance))
    return some(candidates[0].systemId)

  return none(SystemId)

proc findWeakestEnemyColony(state: GameState, houseId: HouseId, rng: var Rand): Option[SystemId] =
  ## Find an enemy colony to attack (prefer weaker targets)
  var targets: seq[tuple[systemId: SystemId, strength: int]] = @[]

  for systemId, colony in state.colonies:
    if colony.owner != houseId:
      # Calculate defensive strength (simplified)
      let defenseStr = colony.infrastructure * 10 + colony.groundBatteries * 20
      targets.add((systemId, defenseStr))

  if targets.len > 0:
    # Sort by strength (weakest first)
    targets.sort(proc(a, b: auto): int = cmp(a.strength, b.strength))
    return some(targets[0].systemId)

  return none(SystemId)

# =============================================================================
# Intelligence Gathering (Phase 2)
# =============================================================================

proc updateIntelligence*(controller: var AIController, state: GameState, systemId: SystemId,
                         turn: int, confidenceLevel: float = 1.0) =
  ## Update intelligence report for a system
  ## Called when scouts gather intel or when we have direct visibility
  var report = IntelligenceReport(
    systemId: systemId,
    lastUpdated: turn,
    hasColony: systemId in state.colonies,
    confidenceLevel: confidenceLevel
  )

  if report.hasColony:
    let colony = state.colonies[systemId]
    report.owner = some(colony.owner)
    report.planetClass = some(colony.planetClass)
    report.resources = some(colony.resources)

    # Estimate defenses (starbases, ground batteries)
    report.estimatedDefenses = colony.starbases.len * 10 + colony.groundBatteries * 5

  # Estimate fleet strength at this system
  var totalStrength = 0
  for fleet in state.fleets.values:
    if fleet.location == systemId:
      for squadron in fleet.squadrons:
        totalStrength += squadron.combatStrength()
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

proc findBestColonizationTarget*(controller: var AIController, state: GameState,
                                  fromSystem: SystemId): Option[SystemId] =
  ## Find best colonization target using intelligence
  ## Prioritizes: Eden/Abundant > Strategic > Nearby > Unknown
  type TargetScore = tuple[systemId: SystemId, score: float, distance: int]
  var candidates: seq[TargetScore] = @[]

  let fromCoords = state.starMap.systems[fromSystem].coords

  for systemId, system in state.starMap.systems:
    if systemId notin state.colonies:
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
    return some(candidates[0].systemId)

  return none(SystemId)

# =============================================================================
# Fleet Coordination (Phase 3)
# =============================================================================

proc planCoordinatedOperation*(controller: var AIController, state: GameState,
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

proc updateOperationStatus*(controller: var AIController, state: GameState) =
  ## Update status of ongoing coordinated operations
  ## Check which fleets have arrived at assembly points
  for op in controller.operations.mitems:
    op.readyFleets.setLen(0)  # Reset ready fleets
    for fleetId in op.requiredFleets:
      if fleetId in state.fleets:
        let fleet = state.fleets[fleetId]
        if fleet.location == op.assemblyPoint:
          op.readyFleets.add(fleetId)

    # If all fleets ready and not yet executed, set execution for next turn
    if op.readyFleets.len == op.requiredFleets.len and op.executionTurn.isNone:
      op.executionTurn = some(state.turn + 1)

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

proc identifyImportantColonies*(controller: AIController, state: GameState): seq[SystemId] =
  ## Identify colonies that need defense-in-depth
  ## Important = high production or abundant resources
  result = @[]
  for systemId, colony in state.colonies:
    if colony.owner == controller.houseId:
      # High production colonies (important industrial centers)
      if colony.production >= 50:
        result.add(systemId)
      # Abundant/Rich resource colonies (strategic value)
      elif colony.resources in [ResourceRating.Rich, ResourceRating.VeryRich, ResourceRating.Abundant]:
        result.add(systemId)

proc assignStrategicReserve*(controller: var AIController, fleetId: FleetId,
                              assignedSystem: Option[SystemId], radius: int = 3) =
  ## Designate a fleet as strategic reserve
  let reserve = StrategicReserve(
    fleetId: fleetId,
    assignedTo: assignedSystem,
    responseRadius: radius
  )
  controller.reserves.add(reserve)

proc getReserveForSystem*(controller: AIController, systemId: SystemId): Option[FleetId] =
  ## Get strategic reserve assigned to defend a system
  for reserve in controller.reserves:
    if reserve.assignedTo.isSome and reserve.assignedTo.get() == systemId:
      return some(reserve.fleetId)
  return none(FleetId)

proc identifyInvasionOpportunities*(controller: var AIController, state: GameState): seq[SystemId] =
  ## Identify enemy colonies that warrant coordinated invasion
  ## Criteria: valuable target, requires multiple fleets, within reach
  result = @[]

  for systemId, colony in state.colonies:
    if colony.owner == controller.houseId:
      continue

    # Estimate defense strength (ground forces + starbase + nearby fleets)
    var defenseStrength = 0
    if colony.starbases.len > 0:
      defenseStrength += 100 * colony.getOperationalStarbaseCount()  # Each starbase adds significant defense

    # Check for defending fleets
    for fleet in state.fleets.values:
      if fleet.owner == colony.owner and fleet.location == systemId:
        defenseStrength += fleet.combatStrength()

    # High-value targets (production >= 50 or rich resources)
    let isValuable = colony.production >= 50 or
                     colony.resources in [ResourceRating.Rich, ResourceRating.VeryRich]

    # Requires coordinated attack if defense > 150
    if isValuable and defenseStrength > 150:
      result.add(systemId)

proc countAvailableFleets*(controller: AIController, state: GameState): int =
  ## Count fleets not currently in operations
  result = 0
  for fleet in state.fleets.values:
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

proc planCoordinatedInvasion*(controller: var AIController, state: GameState,
                                target: SystemId, turn: int) =
  ## Plan multi-fleet invasion of a high-value target
  ## Assembles at nearby friendly system, then attacks together

  # Find nearby friendly system as assembly point
  var assemblyPoint: Option[SystemId] = none(SystemId)
  var minDist = 999

  let targetCoords = state.starMap.systems[target].coords

  for systemId, colony in state.colonies:
    if colony.owner != controller.houseId:
      continue

    let coords = state.starMap.systems[systemId].coords
    let dx = abs(coords.q - targetCoords.q)
    let dy = abs(coords.r - targetCoords.r)
    let dz = abs((coords.q + coords.r) - (targetCoords.q + targetCoords.r))
    let dist = (dx + dy + dz) div 2

    if dist < minDist and dist > 0:
      minDist = dist
      assemblyPoint = some(systemId)

  if assemblyPoint.isNone:
    return

  # Identify fleets for invasion force (need 2-3 combat fleets)
  var selectedFleets: seq[FleetId] = @[]
  for fleet in state.fleets.values:
    if fleet.owner == controller.houseId and fleet.combatStrength() > 0:
      # Skip fleets already in operations
      var inOperation = false
      for op in controller.operations:
        if fleet.id in op.requiredFleets:
          inOperation = true
          break

      if not inOperation:
        selectedFleets.add(fleet.id)
        if selectedFleets.len >= 3:
          break

  if selectedFleets.len >= 2:
    controller.planCoordinatedOperation(
      state,
      OperationType.Invasion,
      target,
      selectedFleets,
      assemblyPoint.get(),
      turn
    )

proc manageStrategicReserves*(controller: var AIController, state: GameState) =
  ## Assign fleets as strategic reserves for important colonies
  ## Defense-in-depth: keep reserves positioned near key systems

  let importantSystems = controller.identifyImportantColonies(state)

  # Assign one reserve per important system (if available)
  for systemId in importantSystems:
    if controller.getReserveForSystem(systemId).isSome:
      continue  # Already has reserve

    # Find nearby idle fleet
    let systemCoords = state.starMap.systems[systemId].coords
    var bestFleet: Option[FleetId] = none(FleetId)
    var minDist = 999

    for fleet in state.fleets.values:
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
      let fleetCoords = state.starMap.systems[fleet.location].coords
      let dx = abs(fleetCoords.q - systemCoords.q)
      let dy = abs(fleetCoords.r - systemCoords.r)
      let dz = abs((fleetCoords.q + fleetCoords.r) - (systemCoords.q + systemCoords.r))
      let dist = (dx + dy + dz) div 2

      if dist < minDist and dist <= 3:
        minDist = dist
        bestFleet = some(fleet.id)

    if bestFleet.isSome:
      controller.assignStrategicReserve(bestFleet.get(), some(systemId), 3)

proc respondToThreats*(controller: var AIController, state: GameState): seq[tuple[reserveFleet: FleetId, threatSystem: SystemId]] =
  ## Check for enemy fleets near protected systems and return reserve/threat pairs
  ## Strategic reserves should move to intercept nearby threats
  result = @[]

  for reserve in controller.reserves:
    if reserve.assignedTo.isNone:
      continue

    let protectedSystem = reserve.assignedTo.get()
    let protectedCoords = state.starMap.systems[protectedSystem].coords

    # Look for enemy fleets within response radius
    for fleet in state.fleets.values:
      if fleet.owner == controller.houseId or fleet.combatStrength() == 0:
        continue

      let fleetCoords = state.starMap.systems[fleet.location].coords
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

proc assessGarrisonNeeds*(controller: AIController, state: GameState): seq[GarrisonPlan] =
  ## Identify colonies that need marine garrisons
  result = @[]

  for systemId, colony in state.colonies:
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
    let systemCoords = state.starMap.systems[systemId].coords
    for enemySystemId, enemyColony in state.colonies:
      if enemyColony.owner == controller.houseId:
        continue
      let enemyCoords = state.starMap.systems[enemySystemId].coords
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
        systemId: systemId,
        currentMarines: currentMarines,
        targetMarines: targetMarines,
        priority: priority
      ))

proc shouldBuildMarines*(controller: AIController, state: GameState, colony: Colony): bool =
  ## Check if this colony should build marines based on garrison needs
  let plans = controller.assessGarrisonNeeds(state)

  for plan in plans:
    if plan.systemId == colony.systemId and colony.marines < plan.targetMarines:
      return true

  return false

proc ensureTransportsLoaded*(controller: var AIController, state: GameState): seq[tuple[transportId: string, needsMarines: int]] =
  ## Identify transports that need marines loaded
  ## Returns list of transports and how many marines they need
  result = @[]

  for fleet in state.fleets.values:
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

proc gatherEconomicIntelligence*(controller: var AIController, state: GameState): seq[EconomicIntelligence] =
  ## Assess enemy economic strength for targeting
  result = @[]

  let ourHouse = state.houses[controller.houseId]
  var ourProduction = 0
  for systemId, colony in state.colonies:
    if colony.owner == controller.houseId:
      ourProduction += colony.production

  for targetHouse in state.houses.keys:
    if targetHouse == controller.houseId:
      continue

    var intel = EconomicIntelligence(
      targetHouse: targetHouse,
      estimatedProduction: 0,
      highValueTargets: @[],
      economicStrength: 0.0
    )

    # Gather data from visible colonies
    for systemId, colony in state.colonies:
      if colony.owner != targetHouse:
        continue

      intel.estimatedProduction += colony.production

      # Identify high-value economic targets
      if colony.production >= 50:
        intel.highValueTargets.add(systemId)

    # Calculate relative strength
    if ourProduction > 0:
      intel.economicStrength = float(intel.estimatedProduction) / float(ourProduction)

    result.add(intel)

proc identifyEconomicTargets*(controller: var AIController, state: GameState): seq[tuple[systemId: SystemId, value: float]] =
  ## Find best targets for economic warfare (blockades, raids)
  result = @[]

  let econIntel = controller.gatherEconomicIntelligence(state)

  for intel in econIntel:
    # Target high-value colonies of economically strong enemies
    if intel.economicStrength > 0.8:  # Only target if they're competitive
      for systemId in intel.highValueTargets:
        let colony = state.colonies[systemId]
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

proc calculateMilitaryStrength(state: GameState, houseId: HouseId): int =
  ## Calculate total military strength for a house
  result = 0
  let fleets = getOwnedFleets(state, houseId)
  for fleet in fleets:
    result += getFleetStrength(fleet)

proc calculateEconomicStrength(state: GameState, houseId: HouseId): int =
  ## Calculate total economic strength for a house
  result = 0
  let house = state.houses[houseId]
  let colonies = getOwnedColonies(state, houseId)

  # Treasury value
  result += house.treasury

  # Colony production value
  for colony in colonies:
    result += colony.production * 10  # Weight production highly
    result += colony.infrastructure * 5

proc findMutualEnemies(state: GameState, houseA: HouseId, houseB: HouseId): seq[HouseId] =
  ## Find houses that both houseA and houseB consider enemies
  result = @[]
  let houseAData = state.houses[houseA]
  let houseBData = state.houses[houseB]

  for otherHouse in state.houses.keys:
    if otherHouse == houseA or otherHouse == houseB:
      continue

    let aIsEnemy = dip_types.isEnemy(houseAData.diplomaticRelations, otherHouse)
    let bIsEnemy = dip_types.isEnemy(houseBData.diplomaticRelations, otherHouse)

    if aIsEnemy and bIsEnemy:
      result.add(otherHouse)

proc estimateViolationRisk(state: GameState, targetHouse: HouseId): float =
  ## Estimate risk that target house will violate a pact (0.0-1.0)
  let targetData = state.houses[targetHouse]

  # Check violation history
  let recentViolations = dip_types.countRecentViolations(
    targetData.violationHistory,
    state.turn
  )

  # Base risk from history
  var risk = float(recentViolations) * 0.2  # +20% per recent violation

  # Check if dishonored
  if targetData.violationHistory.dishonored.active:
    risk += 0.3  # +30% if currently dishonored

  return min(risk, 0.9)  # Cap at 90% risk

proc assessDiplomaticSituation(controller: AIController, state: GameState,
                               targetHouse: HouseId): DiplomaticAssessment =
  ## Evaluate diplomatic relationship with target house
  ## Returns strategic assessment for decision making
  let myHouse = state.houses[controller.houseId]
  let theirHouse = state.houses[targetHouse]
  let p = controller.personality

  result.targetHouse = targetHouse
  result.currentState = dip_types.getDiplomaticState(
    myHouse.diplomaticRelations,
    targetHouse
  )

  # Calculate relative strengths
  let myMilitary = calculateMilitaryStrength(state, controller.houseId)
  let theirMilitary = calculateMilitaryStrength(state, targetHouse)
  result.relativeMilitaryStrength = if theirMilitary > 0:
    float(myMilitary) / float(theirMilitary)
  else:
    10.0  # They have no military

  let myEconomy = calculateEconomicStrength(state, controller.houseId)
  let theirEconomy = calculateEconomicStrength(state, targetHouse)
  result.relativeEconomicStrength = if theirEconomy > 0:
    float(myEconomy) / float(theirEconomy)
  else:
    10.0  # They have no economy

  # Find mutual enemies
  result.mutualEnemies = findMutualEnemies(state, controller.houseId, targetHouse)

  # Estimate violation risk
  result.violationRisk = estimateViolationRisk(state, targetHouse)

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
    ## 3-phase invasion assessment (Phase 1 improvement)
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
    attackerGroundForces*: int     # Marines available (NOTE: engine doesn't track loading!)
    defenderGroundForces*: int     # Enemy marines + armies + batteries

    # Overall assessment
    invasionViable*: bool          # All 3 phases passable?
    recommendInvade*: bool         # Full invasion recommended?
    recommendBlitz*: bool          # Blitz (skip ground) recommended?
    recommendBlockade*: bool       # Too strong - blockade instead?
    strategicValue*: int           # Value of target (production, resources)

proc calculateDefensiveStrength(state: GameState, systemId: SystemId): int =
  ## Calculate total defensive strength of a colony
  if systemId notin state.colonies:
    return 0

  let colony = state.colonies[systemId]
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

proc calculateFleetStrengthAtSystem(state: GameState, systemId: SystemId,
                                   houseId: HouseId): int =
  ## Calculate fleet strength for a specific house at a system
  result = 0
  for fleet in state.fleets.values:
    if fleet.owner == houseId and fleet.location == systemId:
      result += getFleetStrength(fleet)

proc estimateColonyValue(state: GameState, systemId: SystemId): int =
  ## Estimate strategic value of a colony
  if systemId notin state.colonies:
    return 0

  let colony = state.colonies[systemId]
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

proc assessCombatSituation(controller: AIController, state: GameState,
                          targetSystem: SystemId): CombatAssessment =
  ## Evaluate combat situation for attacking a target system
  ## Returns strategic assessment for attack decision

  result.targetSystem = targetSystem

  # Check if system has a colony
  if targetSystem notin state.colonies:
    result.recommendAttack = false
    return

  let targetColony = state.colonies[targetSystem]
  result.targetOwner = targetColony.owner

  # Don't attack our own colonies
  if result.targetOwner == controller.houseId:
    result.recommendAttack = false
    return

  # Check diplomatic status
  let myHouse = state.houses[controller.houseId]
  let dipState = dip_types.getDiplomaticState(
    myHouse.diplomaticRelations,
    result.targetOwner
  )
  result.violatesPact = dipState == dip_types.DiplomaticState.NonAggression

  # Calculate military strengths
  result.attackerFleetStrength = calculateFleetStrengthAtSystem(
    state, targetSystem, controller.houseId
  )
  result.defenderFleetStrength = calculateFleetStrengthAtSystem(
    state, targetSystem, result.targetOwner
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
                     calculateDefensiveStrength(state, targetSystem)

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
  result.strategicValue = estimateColonyValue(state, targetSystem)

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

proc assessInvasionViability(controller: AIController, state: GameState,
                             fleet: Fleet, targetSystem: SystemId): InvasionViability =
  ## PHASE 1 IMPROVEMENT: 3-phase invasion viability assessment
  ## Invasions require winning 3 sequential battles:
  ##   1. Space Combat - Defeat enemy fleets
  ##   2. Starbase Assault - Destroy defensive installations
  ##   3. Ground Invasion - Overcome marines, armies, ground batteries
  ##
  ## Per docs/specs/operations.md:
  ## - Invasion: Full planetary assault (all 3 phases)
  ## - Blitz: Skip ground combat, just destroy orbital defenses
  ## - Blockade: If too strong to invade, starve them economically (-60% GCO)

  # Get basic combat assessment first
  let combat = assessCombatSituation(controller, state, targetSystem)
  let targetColony = state.colonies[targetSystem]
  let p = controller.personality

  # =============================================================================
  # PHASE 1: Space Combat Assessment
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
  # PHASE 2: Starbase Assault Assessment
  # =============================================================================
  # Can we destroy defensive starbases?
  # NOTE: Starbases have both attack and defense, must be destroyed before landing

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
  # PHASE 3: Ground Combat Assessment
  # =============================================================================
  # Can we overcome ground forces (marines + armies + ground batteries)?
  #
  # ENGINE LIMITATION: Transports don't actually track loaded marines yet!
  # TODO: This will need updating when cargo system is implemented
  # For now: ASSUME transports are loaded with 1 MD (Marine Division) each

  result.defenderGroundForces = combat.groundForces + combat.groundBatteryCount

  # ARCHITECTURE FIX: Count spacelift ships (TroopTransports carry 1 MD each)
  var transportCount = 0
  for spaceLiftShip in fleet.spaceLiftShips:
    if spaceLiftShip.shipClass == ShipClass.TroopTransport:
      transportCount += 1

  result.attackerGroundForces = transportCount  # 1 MD per transport

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

proc generateFleetOrders(controller: var AIController, state: GameState, rng: var Rand): seq[FleetOrder] =
  ## Generate fleet orders based on strategic military assessment
  ## PHASE 2: Now updates intelligence when making decisions
  result = @[]
  let p = controller.personality
  let myFleets = getOwnedFleets(state, controller.houseId)

  # PHASE 2: Update intelligence for systems we have visibility on
  # (Our colonies + systems with our fleets = automatic intel)
  for systemId, colony in state.colonies:
    if colony.owner == controller.houseId:
      controller.updateIntelligence(state, systemId, state.turn, 1.0)

  for fleet in myFleets:
    # Fleets give us visibility into their current system
    controller.updateIntelligence(state, fleet.location, state.turn, 0.8)

  # PHASE 3: Update coordinated operations status
  controller.updateOperationStatus(state)
  controller.removeCompletedOperations(state.turn)

  for fleet in myFleets:
    var order: FleetOrder
    order.fleetId = fleet.id
    order.priority = 1

    # Check current location for combat situation
    let currentCombat = assessCombatSituation(
      controller, state, fleet.location
    )

    # BALANCE FIX: Priority 0 - Stay at colony to absorb unassigned squadrons
    # If at a friendly colony with unassigned squadrons, hold position so auto-assign works
    if fleet.location in state.colonies:
      let colony = state.colonies[fleet.location]
      if colony.owner == controller.houseId and colony.unassignedSquadrons.len > 0:
        # Stay at colony to pick up newly built ships
        order.orderType = FleetOrderType.Hold
        order.targetSystem = some(fleet.location)
        order.targetFleet = none(FleetId)
        result.add(order)
        continue

    # Priority 0.5: PHASE 3 - Coordinated Operations
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
        elif controller.shouldExecuteOperation(op, state.turn):
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

    # Priority 0.75: PHASE 3 - Strategic Reserve Threat Response
    # Check if this fleet is a reserve responding to a nearby threat
    let threats = controller.respondToThreats(state)
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
      # Find nearest friendly colony to retreat to
      var nearestFriendly: Option[SystemId] = none(SystemId)
      for systemId, colony in state.colonies:
        if colony.owner == controller.houseId and systemId != fleet.location:
          nearestFriendly = some(systemId)
          break

      if nearestFriendly.isSome:
        order.orderType = FleetOrderType.Move
        order.targetSystem = nearestFriendly
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

    # Priority 3: Find targets to attack based on aggression OR military focus
    # BALANCE FIX: Lowered aggression from 0.5 to 0.3 to enable more combat
    # BALANCE FIX: Added military-focused AIs always seek targets (even if low aggression)
    let militaryFocus = 1.0 - p.economicFocus
    let shouldSeekTargets = p.aggression > 0.3 or militaryFocus > 0.7

    if shouldSeekTargets:
      # Look for vulnerable enemy colonies
      var bestTarget: Option[SystemId] = none(SystemId)
      var bestOdds = 0.0

      # PHASE 5: Economic Warfare - prioritize high-value economic targets
      # if we're economically focused (lower aggression, higher economic focus)
      if p.economicFocus > 0.6 and p.aggression < 0.6:
        # Get economic targets for warfare
        let econTargets = controller.identifyEconomicTargets(state)

        # Find best economic target we can reach
        for target in econTargets:
          let combat = assessCombatSituation(controller, state, target.systemId)
          # For economic warfare, we prefer blockades over invasions
          # Target high-value economies even with moderate odds
          if combat.estimatedCombatOdds > 0.4:  # Lower threshold for economic targets
            bestTarget = some(target.systemId)
            bestOdds = combat.estimatedCombatOdds
            break  # Take first viable economic target (already sorted by value)

      # If no economic target found (or not economically focused), use standard military targeting
      if bestTarget.isNone:
        for systemId, colony in state.colonies:
          if colony.owner == controller.houseId:
            continue  # Skip our own colonies

          let combat = assessCombatSituation(controller, state, systemId)
          if combat.recommendAttack and combat.estimatedCombatOdds > bestOdds:
            bestOdds = combat.estimatedCombatOdds
            bestTarget = some(systemId)

      if bestTarget.isSome:
        # ARCHITECTURE FIX: Check if fleet has troop transports (spacelift ships)
        var hasTransports = false
        for spaceLiftShip in fleet.spaceLiftShips:
          if spaceLiftShip.shipClass == ShipClass.TroopTransport:
            hasTransports = true
            break

        # PHASE 1 IMPROVEMENT: Use 3-phase invasion viability assessment
        # Invasions give +10 prestige (highest reward!) - prioritize them
        if hasTransports:
          # Perform comprehensive 3-phase invasion assessment
          let invasion = assessInvasionViability(controller, state, fleet, bestTarget.get)

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

    # Priority 3.5: PHASE 2 - Scout Reconnaissance Missions
    # Check if this is a scout-only fleet (single squadron with scouts)
    var isScoutFleet = false
    var hasOnlyScouts = false
    if fleet.squadrons.len == 1:
      let squadron = fleet.squadrons[0]
      # Single-squadron scout fleets are ideal for spy missions (per operations.md:45)
      if squadron.flagship.shipClass == ShipClass.Scout and squadron.ships.len == 0:
        isScoutFleet = true
        hasOnlyScouts = true

    if isScoutFleet and (p.techPriority > 0.4 or p.expansionDrive > 0.5):
      # PHASE 2: Intelligence operations for scouts
      # Priority: Pre-colonization recon > Pre-invasion intel > Strategic positioning

      # A) Pre-colonization reconnaissance - scout systems before sending ETACs
      if p.expansionDrive > 0.4:
        # Find uncolonized systems that need scouting
        var needsRecon: seq[SystemId] = @[]
        for systemId, system in state.starMap.systems:
          if systemId notin state.colonies and
             controller.needsReconnaissance(systemId, state.turn):
            needsRecon.add(systemId)

        if needsRecon.len > 0:
          # Pick closest system needing recon
          var closest: Option[SystemId] = none(SystemId)
          var minDist = 999
          let fromCoords = state.starMap.systems[fleet.location].coords
          for sysId in needsRecon:
            let coords = state.starMap.systems[sysId].coords
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

      # B) Pre-invasion intelligence - scout enemy colonies before invasion
      if p.aggression > 0.4:
        # Find enemy colonies that need updated intelligence
        var needsIntel: seq[SystemId] = @[]
        for systemId, colony in state.colonies:
          if colony.owner != controller.houseId and
             controller.needsReconnaissance(systemId, state.turn):
            needsIntel.add(systemId)

        if needsIntel.len > 0:
          # Pick closest enemy colony needing intel
          var closest: Option[SystemId] = none(SystemId)
          var minDist = 999
          let fromCoords = state.starMap.systems[fleet.location].coords
          for sysId in needsIntel:
            let coords = state.starMap.systems[sysId].coords
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
      # PHASE 2: Intelligence-driven colonization
      # ETAC fleets: Colonize if at uncolonized system, otherwise move to best target
      if fleet.location notin state.colonies:
        # At uncolonized system - COLONIZE IT!
        order.orderType = FleetOrderType.Colonize
        order.targetSystem = some(fleet.location)
        order.targetFleet = none(FleetId)
        result.add(order)
        continue
      else:
        # At colonized system - seek BEST uncolonized system (using intel)
        let targetOpt = findBestColonizationTarget(controller, state, fleet.location)
        if targetOpt.isSome:
          order.orderType = FleetOrderType.Move
          order.targetSystem = targetOpt
          order.targetFleet = none(FleetId)
          result.add(order)
          continue
    elif p.expansionDrive > 0.3:
      # Non-ETAC fleets with expansion drive: Scout uncolonized systems
      let targetOpt = findNearestUncolonizedSystem(state, fleet.location)
      if targetOpt.isSome:
        order.orderType = FleetOrderType.Move
        order.targetSystem = targetOpt
        order.targetFleet = none(FleetId)
        result.add(order)
        continue

    # Priority 5: Defend home colonies (patrol)
    # Find a colony that needs defense
    var needsDefense: Option[SystemId] = none(SystemId)
    for systemId, colony in state.colonies:
      if colony.owner == controller.houseId:
        # Check if there are enemy fleets nearby (simplified: just check this colony)
        let hasEnemyFleets = calculateFleetStrengthAtSystem(
          state, systemId, colony.owner
        ) < getFleetStrength(fleet)
        if hasEnemyFleets or colony.blockaded:
          needsDefense = some(systemId)
          break

    if needsDefense.isSome:
      order.orderType = FleetOrderType.Move
      order.targetSystem = needsDefense
      order.targetFleet = none(FleetId)
    else:
      # Priority 6: Exploration - send fleets to unknown systems
      # Instead of sitting idle, explore uncolonized systems
      if p.expansionDrive > 0.2 or rng.rand(1.0) < 0.3:
        let exploreTarget = findNearestUncolonizedSystem(state, fleet.location)
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

proc generateBuildOrders(controller: AIController, state: GameState, rng: var Rand): seq[BuildOrder] =
  ## COMPREHENSIVE 4X STRATEGIC AI - Handles all asset types intelligently
  ## Ships: Combat warships, fighters, carriers, raiders, scouts, ETACs, transports
  ## Defenses: Starbases, planetary shields, ground batteries, armies, marines
  ## Facilities: Spaceports, shipyards, infrastructure
  result = @[]
  let p = controller.personality
  let house = state.houses[controller.houseId]
  let myColonies = getOwnedColonies(state, controller.houseId)

  if myColonies.len == 0:
    return  # No colonies, can't build

  # ==========================================================================
  # ASSET INVENTORY - Count existing assets
  # ==========================================================================
  var scoutCount = 0
  var raiderCount = 0
  var carrierCount = 0
  var fighterCount = 0
  var etacCount = 0
  var transportCount = 0
  var militaryCount = 0
  var capitalShipCount = 0  # BB, BC, DN, SD
  var starbaseCount = 0

  # BALANCE FIX: Count squadrons in fleets AND unassigned squadrons
  # ARCHITECTURE FIX: Count spacelift ships separately (NOT in squadrons)
  for fleet in state.fleets.values:
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
  # STRATEGIC ASSESSMENT - What does this AI need?
  # ==========================================================================

  # Assess military situation
  let myMilitaryStrength = calculateMilitaryStrength(state, controller.houseId)
  var totalEnemyStrength = 0
  var hasEnemies = false
  for otherHouse in state.houses.keys:
    if otherHouse != controller.houseId:
      let dipState = dip_types.getDiplomaticState(
        house.diplomaticRelations,
        otherHouse
      )
      if dipState == dip_types.DiplomaticState.Enemy:
        totalEnemyStrength += calculateMilitaryStrength(state, otherHouse)
        hasEnemies = true

  let militaryRatio = if totalEnemyStrength > 0:
    float(myMilitaryStrength) / float(totalEnemyStrength)
  else:
    2.0  # No declared enemies

  # Check for threatened colonies
  var threatenedColonies = 0
  var criticalThreat = false
  for colony in myColonies:
    let combat = assessCombatSituation(controller, state, colony.systemId)
    if combat.recommendRetreat or combat.recommendReinforce:
      threatenedColonies += 1
      if combat.recommendRetreat:
        criticalThreat = true

  # Strategic needs assessment (FIXED: scouts only needed initially)
  let needScouts = scoutCount < 2  # Need 2-3 scouts for exploration/ELI
  let needMoreScouts = scoutCount < 3 and p.techPriority > 0.5 and militaryCount > 5
  # PRESTIGE OPTIMIZATION: Colonization gives +5 prestige
  # Expand aggressively when uncolonized systems available
  let needETACs = (etacCount < 2 and p.expansionDrive > 0.3 and
                   findNearestUncolonizedSystem(state, myColonies[0].systemId).isSome)

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

  let needRaiders = (
    p.aggression > 0.7 and raiderCount < 2 and militaryCount > 5 and house.treasury > 200
  )

  let needCarriers = (
    fighterCount > 3 and carrierCount == 0 and house.treasury > 150
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
    # CRITICAL PRIORITY: Infrastructure for ship building
    # ------------------------------------------------------------------------
    if needsInfrastructure and (needMilitary or p.aggression > 0.4):
      # Need spaceport first, then shipyard
      if not hasSpaceport and house.treasury >= 100:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Building,
          quantity: 1,
          shipClass: none(ShipClass),
          buildingType: some("Spaceport"),
          industrialUnits: 0
        ))
        break  # Build spaceport first
      elif hasSpaceport and not hasShipyard and house.treasury >= 150:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Building,
          quantity: 1,
          shipClass: none(ShipClass),
          buildingType: some("Shipyard"),
          industrialUnits: 0
        ))
        break  # Build shipyard next

    if not hasShipyard:
      continue  # Can't build ships without shipyard

    # ------------------------------------------------------------------------
    # CRISIS RESPONSE: Critical threats get immediate defense
    # ------------------------------------------------------------------------
    if criticalThreat:
      let combat = assessCombatSituation(controller, state, colony.systemId)
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
    # PHASE 4: Marine Garrison Management
    # ------------------------------------------------------------------------
    if controller.shouldBuildMarines(state, colony):
      # This colony needs more marines for garrison
      if house.treasury >= 30:  # Cost of marines (TODO: get from config)
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
    # EARLY GAME: Initial exploration and expansion
    # ------------------------------------------------------------------------
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

    if needETACs:
      let etacCost = getShipConstructionCost(ShipClass.ETAC)
      if house.treasury >= etacCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.ETAC),
          buildingType: none(string),
          industrialUnits: 0
        ))
        break

    # ------------------------------------------------------------------------
    # MID GAME: Military buildup and defense
    # ------------------------------------------------------------------------

    # Starbases for defense (before expensive military buildup)
    if needDefenses and not hasStarbase and house.treasury >= 300:
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
    if needMilitary:
      var shipClass: ShipClass
      var shipCost: int

      # Choose ship based on treasury, aggression, and strategic needs
      if house.treasury > 150 and needRaiders:
        # Raiders for ambush tactics (high aggression + good economy)
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

    # PHASE 1 IMPROVEMENT: Proactive garrison management
    # Build marine garrisons BEFORE invasions threaten, not after
    #
    # Strategic priorities:
    # - Homeworld: 5+ marine garrison (critical)
    # - Important colonies: 3+ marines (high production, resources)
    # - Frontier colonies: 1-2 marines (minimum defense)
    # - Prepare marines for loading onto transports for invasions

    let isHomeworld = (colony.systemId == state.starMap.playerSystemIds[0])  # Assume homeworld
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

    # PHASE 1: Build extra marines for invasion preparation
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

    # Additional scouts for ELI mesh networks
    if needMoreScouts and scoutCount < 5:
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

proc generateResearchAllocation(controller: AIController, state: GameState): res_types.ResearchAllocation =
  ## Allocate research PP based on strategy
  ## Per economy.md:4.0:
  ##   - Economic Level (EL) purchased with ERP
  ##   - Science Level (SL) purchased with SRP
  ##   - Technologies (CST, WEP, etc.) purchased with TRP
  result = res_types.ResearchAllocation(
    economic: 0,
    science: 0,
    technology: initTable[TechField, int]()
  )

  let p = controller.personality
  let house = state.houses[controller.houseId]

  # Calculate available PP budget from production
  # Get house's production from all colonies
  var totalProduction = 0
  for colony in state.colonies.values:
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
      if p.aggression > 0.5:
        # Aggressive: focus on weapons
        result.technology[TechField.WeaponsTech] = techBudget div 2
        result.technology[TechField.ConstructionTech] = techBudget div 4
        result.technology[TechField.ElectronicIntelligence] = techBudget div 4
      else:
        # Peaceful: focus on infrastructure
        result.technology[TechField.ConstructionTech] = techBudget div 2
        result.technology[TechField.TerraformingTech] = techBudget div 4
        result.technology[TechField.CounterIntelligence] = techBudget div 4

    elif p.techPriority > 0.4:
      # Moderate research - focus on fundamentals (EL/SL)
      result.economic = researchBudget div 2        # 50% to EL
      result.science = researchBudget div 3         # 33% to SL

      # Remaining ~17% to one key tech
      let techBudget = researchBudget - result.economic - result.science
      if p.aggression > 0.5:
        result.technology[TechField.WeaponsTech] = techBudget
      else:
        result.technology[TechField.ConstructionTech] = techBudget
    else:
      # Minimal research - just EL for economic growth
      result.economic = researchBudget

proc generateDiplomaticActions(controller: AIController, state: GameState, rng: var Rand): seq[DiplomaticAction] =
  ## Generate diplomatic actions based on strategic assessment
  result = @[]
  let p = controller.personality
  let myHouse = state.houses[controller.houseId]

  # Priority 0: Respond to pending proposals
  # AI must respond to proposals before proposing new actions
  for proposal in state.pendingProposals:
    if proposal.target == controller.houseId and proposal.status == dip_proposals.ProposalStatus.Pending:
      # Assess the proposer
      let assessment = assessDiplomaticSituation(controller, state, proposal.proposer)

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

  # Assess all other houses
  var assessments: seq[DiplomaticAssessment] = @[]
  for otherHouseId in state.houses.keys:
    if otherHouseId == controller.houseId:
      continue
    assessments.add(assessDiplomaticSituation(controller, state, otherHouseId))

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
        if dip_types.canReinstatePact(myHouse.violationHistory, assessment.targetHouse, state.turn):
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

proc generateEspionageAction(controller: AIController, state: GameState, rng: var Rand): Option[esp_types.EspionageAttempt] =
  ## Generate espionage action based on strategy and personality
  ## Use personality weights to determine if we should use espionage
  let p = controller.personality
  let house = state.houses[controller.houseId]

  # Check if we have EBP to use espionage (need at least 5 EBP for basic actions)
  if house.espionageBudget.ebpPoints < 5:
    return none(esp_types.EspionageAttempt)

  # Use espionage based on personality rather than strategy enum
  # High risk tolerance + low aggression = espionage focus
  let espionageChance = p.riskTolerance * 0.5 + (1.0 - p.aggression) * 0.3 + p.techPriority * 0.2

  if rng.rand(1.0) > espionageChance:
    return none(esp_types.EspionageAttempt)

  # Find a target house
  var targetHouses: seq[HouseId] = @[]
  for houseId in state.houses.keys:
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

proc generateAIOrders*(controller: var AIController, state: GameState, rng: var Rand): OrderPacket =
  ## Generate complete order packet for an AI player
  ##
  ## PHASE 2/3: Controller is now `var` to support intelligence updates
  ##
  ## Context available:
  ## - controller.lastTurnReport: Previous turn's report (for AI learning)
  ## - state: Current game state
  ## - controller.personality: Strategic personality parameters
  ## - controller.intelligence: System intelligence reports (Phase 2)
  ## - controller.operations: Coordinated operations (Phase 3)
  ##
  ## Future enhancement: Parse lastTurnReport to:
  ## - React to combat losses (build replacements, retreat)
  ## - Respond to enemy fleet sightings (send reinforcements)
  ## - Adjust strategy based on economic situation
  ## - Learn from tech advances (prioritize synergistic research)
  let p = controller.personality
  let house = state.houses[controller.houseId]

  # PHASE 3: Strategic planning before generating orders
  # Update operation status (check which fleets have reached assembly points)
  controller.updateOperationStatus(state)

  # Manage strategic reserves (assign fleets to defend important colonies)
  controller.manageStrategicReserves(state)

  # Plan new coordinated operations if aggressive personality and have free fleets
  if p.aggression > 0.5 and controller.countAvailableFleets(state) >= 2:
    let opportunities = controller.identifyInvasionOpportunities(state)
    if opportunities.len > 0:
      # Plan invasion of highest-value target
      controller.planCoordinatedInvasion(state, opportunities[0], state.turn)

  result = OrderPacket(
    houseId: controller.houseId,
    turn: state.turn,
    fleetOrders: generateFleetOrders(controller, state, rng),
    buildOrders: generateBuildOrders(controller, state, rng),
    researchAllocation: generateResearchAllocation(controller, state),
    diplomaticActions: generateDiplomaticActions(controller, state, rng),
    espionageAction: generateEspionageAction(controller, state, rng),
    ebpInvestment: 0,
    cipInvestment: 0
  )

  # Set espionage budget based on personality (not strategy enum)
  # Use riskTolerance + (1-aggression) as proxy for espionage focus
  let espionageFocus = (p.riskTolerance + (1.0 - p.aggression)) / 2.0

  # Invest percentage of treasury, not absolute amounts
  # This prevents over-investment early game and scales with economy
  let ebpCost = 15  # PP per EBP (from config/espionage.toml)
  let cipCost = 15  # PP per CIP (from config/espionage.toml)

  if espionageFocus > 0.6:
    # High espionage focus - invest up to 15% of treasury
    let budget = house.treasury * 15 div 100
    result.ebpInvestment = min(budget div ebpCost, 50)
    result.cipInvestment = min(budget div (ebpCost * 2), 25)
  elif espionageFocus > 0.4:
    # Moderate espionage focus - invest up to 8% of treasury
    let budget = house.treasury * 8 div 100
    result.ebpInvestment = min(budget div ebpCost, 20)
    result.cipInvestment = min(budget div (ebpCost * 2), 10)
  else:
    # Low espionage focus - invest up to 3% of treasury
    let budget = house.treasury * 3 div 100
    result.ebpInvestment = min(budget div ebpCost, 10)
    result.cipInvestment = min(budget div (ebpCost * 2), 10)

# =============================================================================
# Export
# =============================================================================

export AIStrategy, AIPersonality, AIController
export newAIController, generateAIOrders, getStrategyPersonality
