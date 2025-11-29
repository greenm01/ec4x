## Turn resolution engine - the heart of EC4X gameplay
##
## OFFLINE GAMEPLAY SYSTEM - No network dependencies
## This module is designed to work standalone for local/hotseat multiplayer
## Network transport (Nostr) wraps around this engine without modifying it
##
## REFACTORED: Main orchestrator that coordinates resolution phases
## Individual phase logic has been extracted to resolution/* modules

import std/[tables, algorithm, options, random, sequtils, hashes, sets]
import ../common/types/core
import ../common/logger
import gamestate, orders, fleet, squadron, ai_special_modes, standing_orders
import espionage/[types as esp_types, engine as esp_engine]
import diplomacy/[types as dip_types]
import research/[types as res_types_research]
import commands/executor
import intelligence/espionage_intel
# Import resolution modules
import resolution/[types as res_types, fleet_orders, economy_resolution, diplomatic_resolution, combat_resolution, simultaneous, simultaneous_planetary, simultaneous_blockade, simultaneous_espionage]

# Re-export resolution types for backward compatibility
export res_types.GameEvent, res_types.GameEventType, res_types.CombatReport

type
  TurnResult* = object
    newState*: GameState
    events*: seq[res_types.GameEvent]
    combatReports*: seq[res_types.CombatReport]

# Forward declarations for phase functions
proc resolveConflictPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                         combatReports: var seq[res_types.CombatReport], events: var seq[res_types.GameEvent], rng: var Rand)
proc resolveCommandPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                        events: var seq[res_types.GameEvent], rng: var Rand)

## Main Turn Resolution

proc resolveTurn*(state: GameState, orders: Table[HouseId, OrderPacket]): TurnResult =
  ## Resolve a complete game turn
  ## Returns new game state and events that occurred

  logDebug("Resolve", "Turn resolution starting", "turn=", $state.turn)

  result.newState = state  # Start with current state
  result.events = @[]
  result.combatReports = @[]

  # Initialize RNG for this turn (use turn number as seed for reproducibility)
  # Using turn number as seed ensures deterministic replay for debugging
  var rng = initRand(state.turn)
  logRNG("RNG initialized for stochastic resolution", "turn=", $state.turn, " seed=", $state.turn)

  logResolve("Starting strategic cycle", "turn=", $state.turn)

  # Generate AI orders for special modes (Defensive Collapse & MIA Autopilot)
  # These override player/AI orders for affected houses
  var effectiveOrders = orders  # Start with submitted orders

  for houseId, house in result.newState.houses:
    case house.status
    of HouseStatus.DefensiveCollapse:
      # Generate defensive collapse AI orders
      let defensiveOrders = getDefensiveCollapseOrders(result.newState, houseId)

      # Create empty order packet (no construction, research, diplomacy)
      var collapsePacket = OrderPacket(
        houseId: houseId,
        turn: state.turn,
        fleetOrders: @[],
        buildOrders: @[],
        researchAllocation: res_types_research.initResearchAllocation(),
        diplomaticActions: @[],
        populationTransfers: @[],
        squadronManagement: @[],
        cargoManagement: @[],
        terraformOrders: @[],
        espionageAction: none(esp_types.EspionageAttempt),
        ebpInvestment: 0,
        cipInvestment: 0
      )

      # Add defensive fleet orders
      for (fleetId, order) in defensiveOrders:
        collapsePacket.fleetOrders.add(order)

      effectiveOrders[houseId] = collapsePacket
      logInfo("Resolve", "Defensive Collapse mode active", house.name, " orders=", $defensiveOrders.len)

    of HouseStatus.Autopilot:
      # Generate autopilot AI orders
      let autopilotOrders = getAutopilotOrders(result.newState, houseId)

      # Create minimal order packet (no construction, no new research, no diplomacy)
      var autopilotPacket = OrderPacket(
        houseId: houseId,
        turn: state.turn,
        fleetOrders: @[],
        buildOrders: @[],
        researchAllocation: res_types_research.initResearchAllocation(),
        diplomaticActions: @[],
        populationTransfers: @[],
        squadronManagement: @[],
        cargoManagement: @[],
        terraformOrders: @[],
        espionageAction: none(esp_types.EspionageAttempt),
        ebpInvestment: 0,
        cipInvestment: 0
      )

      # Add autopilot fleet orders
      for (fleetId, order) in autopilotOrders:
        autopilotPacket.fleetOrders.add(order)

      effectiveOrders[houseId] = autopilotPacket
      logInfo("Resolve", "Autopilot mode active", house.name, " orders=", $autopilotOrders.len)

    of HouseStatus.Active:
      # Normal play - use submitted orders
      discard

  # Phase 1: Conflict (combat, infrastructure damage, espionage)
  resolveConflictPhase(result.newState, effectiveOrders, result.combatReports, result.events, rng)

  # Phase 2: Income (resource collection)
  resolveIncomePhase(result.newState, effectiveOrders)

  # Phase 3: Command (build orders, fleet orders, diplomatic actions)
  resolveCommandPhase(result.newState, effectiveOrders, result.events, rng)

  # Phase 4: Maintenance (upkeep, effect decrements, status updates)
  resolveMaintenancePhase(result.newState, result.events, effectiveOrders)

  # Advance to next turn
  result.newState.turn += 1
  # Advance strategic cycle (handled by advanceTurn)

  return result

## Phase 1: Conflict

proc resolveConflictPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                         combatReports: var seq[res_types.CombatReport], events: var seq[res_types.GameEvent], rng: var Rand) =
  ## Phase 1: Resolve all combat and infrastructure damage
  ## This happens FIRST so damaged facilities affect production
  logInfo("Resolve", "=== Conflict Phase ===", "turn=", $state.turn)
  logRNG("Using RNG for combat resolution", "seed=", $state.turn)

  # Find all systems with hostile fleets
  var combatSystems: seq[SystemId] = @[]

  for systemId, system in state.starMap.systems:
    # Check if multiple houses have fleets here
    var housesPresent: seq[HouseId] = @[]
    var houseFleets: Table[HouseId, seq[Fleet]] = initTable[HouseId, seq[Fleet]]()

    for fleet in state.fleets.values:
      if fleet.location == systemId:
        if fleet.owner notin housesPresent:
          housesPresent.add(fleet.owner)
          houseFleets[fleet.owner] = @[]
        houseFleets[fleet.owner].add(fleet)

    if housesPresent.len > 1:
      # Check if any pairs of houses are at war AND can detect each other
      var combatDetected = false
      for i in 0..<housesPresent.len:
        for j in (i+1)..<housesPresent.len:
          let house1 = housesPresent[i]
          let house2 = housesPresent[j]

          # Check diplomatic state between these two houses
          let relation = dip_types.getDiplomaticState(
            state.houses[house1].diplomaticRelations,
            house2
          )

          # Combat occurs if houses are enemies OR neutral (no pact protection)
          # BUT: Cloaked fleets can remain hidden unless detected
          if relation == dip_types.DiplomaticState.Enemy or
             relation == dip_types.DiplomaticState.Neutral:

            # STEALTH DETECTION CHECK
            # Check if either side is cloaked and undetected
            let house1Cloaked = houseFleets[house1].anyIt(it.isCloaked())
            let house2Cloaked = houseFleets[house2].anyIt(it.isCloaked())
            let house1HasScouts = houseFleets[house1].anyIt(it.squadrons.anyIt(it.hasScouts()))
            let house2HasScouts = houseFleets[house2].anyIt(it.squadrons.anyIt(it.hasScouts()))

            # Combat only triggers if both sides can detect each other
            # If house1 is cloaked, house2 needs scouts to detect them
            # If house2 is cloaked, house1 needs scouts to detect them
            let house1Detected = not house1Cloaked or house2HasScouts
            let house2Detected = not house2Cloaked or house1HasScouts

            if house1Detected and house2Detected:
              combatDetected = true
              break
        if combatDetected:
          break

      if combatDetected:
        combatSystems.add(systemId)

  # Resolve combat in each system (operations.md:7.0)
  for systemId in combatSystems:
    resolveBattle(state, systemId, orders, combatReports, events, rng)

  # Process espionage actions (per gameplay.md:1.3.1 - resolved in Conflict Phase)
  # NOTE: Now handled by SIMULTANEOUS ESPIONAGE RESOLUTION (see Command Phase)
  # This sequential loop is deprecated and will be removed
  when false:
    for houseId in state.houses.keys:
      if houseId in orders:
        let packet = orders[houseId]

        # Process espionage action if present (max 1 per turn per diplomacy.md:8.2)
        if packet.espionageAction.isSome:
          let attempt = packet.espionageAction.get()

          # Get target's CIC level from tech tree
          let targetCICLevel = case state.houses[attempt.target].techTree.levels.counterIntelligence
            of 1: esp_types.CICLevel.CIC1
            of 2: esp_types.CICLevel.CIC2
            of 3: esp_types.CICLevel.CIC3
            of 4: esp_types.CICLevel.CIC4
            of 5: esp_types.CICLevel.CIC5
            else: esp_types.CICLevel.CIC1
          let targetCIP = if attempt.target in state.houses:
                            state.houses[attempt.target].espionageBudget.cipPoints
                          else:
                            0

          # Execute espionage action with detection roll (using turn RNG)
          let result = esp_engine.executeEspionage(
            attempt,
            targetCICLevel,
            targetCIP,
            rng
          )

          # Apply results
          if result.success:
            logInfo("Espionage", "Mission success", $attempt.attacker, " ", result.description)

            # Apply prestige changes
            for prestigeEvent in result.attackerPrestigeEvents:
              state.houses[attempt.attacker].prestige += prestigeEvent.amount
            for prestigeEvent in result.targetPrestigeEvents:
              state.houses[attempt.target].prestige += prestigeEvent.amount

            # Apply ongoing effects
            if result.effect.isSome:
              state.ongoingEffects.add(result.effect.get())

            # Apply immediate effects (SRP theft, IU damage, etc.)
            if result.srpStolen > 0:
              # Steal SRP from target
              if attempt.target in state.houses:
                state.houses[attempt.target].techTree.accumulated.science =
                  max(0, state.houses[attempt.target].techTree.accumulated.science - result.srpStolen)
                state.houses[attempt.attacker].techTree.accumulated.science += result.srpStolen
                echo "      Stole ", result.srpStolen, " SRP from ", attempt.target

          else:
            echo "    ", attempt.attacker, " espionage DETECTED by ", attempt.target
            # Apply detection prestige penalties
            for prestigeEvent in result.attackerPrestigeEvents:
              state.houses[attempt.attacker].prestige += prestigeEvent.amount

          # Generate intelligence reports for espionage operation
          espionage_intel.generateEspionageIntelligence(state, result, state.turn)

  # Process planetary combat orders (operations.md:7.5, 7.6)
  # These execute after space/orbital combat in linear progression
  # NOTE: Now handled by SIMULTANEOUS PLANETARY COMBAT RESOLUTION (see Command Phase)
  # This sequential loop is deprecated and will be removed
  when false:
    for houseId in state.houses.keys:
      if houseId in orders:
        for order in orders[houseId].fleetOrders:
          case order.orderType
          of FleetOrderType.Bombard:
            resolveBombardment(state, houseId, order, events)
          of FleetOrderType.Invade:
            resolveInvasion(state, houseId, order, events)
          of FleetOrderType.Blitz:
            resolveBlitz(state, houseId, order, events)
          else:
            discard

## Helper: Auto-balance unassigned squadrons to fleets at colony

# NOTE: Function currently unused but preserved for future implementation
# TODO: Integrate auto-balancing of unassigned squadrons to stationary fleets
when false:
  proc autoBalanceSquadronsToFleets(state: var GameState, colony: var gamestate.Colony, systemId: SystemId, orders: Table[HouseId, OrderPacket]) =
    ## Auto-assign unassigned squadrons to fleets at colony, balancing squadron count
    ## Only assigns to stationary fleets (those with Hold orders or no orders)
    if colony.unassignedSquadrons.len == 0:
      return

    # Get all fleets at this colony owned by same house
    var candidateFleets: seq[FleetId] = @[]
    for fleetId, fleet in state.fleets:
      if fleet.owner == colony.owner and fleet.location == systemId:
        # Check if fleet has stationary orders (Hold or no orders)
        var isStationary = true

        # Check if fleet has orders
        if colony.owner in orders:
          for order in orders[colony.owner].fleetOrders:
            if order.fleetId == fleetId:
              # Fleet has orders - only stationary if Hold
              if order.orderType != FleetOrderType.Hold:
                isStationary = false
              break

        if isStationary:
          candidateFleets.add(fleetId)

    if candidateFleets.len == 0:
      return

    # Calculate target squadron count per fleet (balanced distribution)
    let totalSquadrons = colony.unassignedSquadrons.len +
                          candidateFleets.mapIt(state.fleets[it].squadrons.len).foldl(a + b, 0)
    let targetPerFleet = totalSquadrons div candidateFleets.len

    # Assign squadrons to fleets to reach target count
    for fleetId in candidateFleets:
      var fleet = state.fleets[fleetId]
      while fleet.squadrons.len < targetPerFleet and colony.unassignedSquadrons.len > 0:
        let squadron = colony.unassignedSquadrons[0]
        fleet.squadrons.add(squadron)
        colony.unassignedSquadrons.delete(0)
      state.fleets[fleetId] = fleet

## Phase 3: Command

proc resolveCommandPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                        events: var seq[res_types.GameEvent], rng: var Rand) =
  ## Phase 3: Execute orders
  ## Build orders may fail if shipyards were destroyed in conflict phase
  logInfo("Resolve", "=== Command Phase ===", "turn=", $state.turn)

  # Process build orders first
  for houseId in state.houses.keys:
    if houseId in orders:
      resolveBuildOrders(state, orders[houseId], events)

  # Process Space Guild population transfers
  for houseId in state.houses.keys:
    if houseId in orders:
      resolvePopulationTransfers(state, orders[houseId], events)

  # Process diplomatic actions
  resolveDiplomaticActions(state, orders)

  # Process squadron management orders (form squadrons, transfer ships, assign to fleets)
  for houseId in state.houses.keys:
    if houseId in orders:
      resolveSquadronManagement(state, orders[houseId], events)

  # Process cargo management (manual loading/unloading)
  for houseId in state.houses.keys:
    if houseId in orders:
      resolveCargoManagement(state, orders[houseId], events)

  # Auto-load cargo at colonies (if no manual cargo order exists)
  autoLoadCargo(state, orders, events)

  # Process terraforming orders
  for houseId in state.houses.keys:
    if houseId in orders:
      resolveTerraformOrders(state, orders[houseId], events)

  # Process all fleet orders (sorted by priority)
  # PERSISTENCE: Fleet orders continue across turns until completed or overridden
  var allFleetOrders: seq[(HouseId, FleetOrder)] = @[]
  var newOrdersThisTurn = initHashSet[FleetId]()  # Track which fleets got new orders

  when not defined(release):
    logDebug("Fleet", "Fleet order processing start", "turn=", $state.turn)

  # Step 1: Collect NEW orders from this turn's OrderPackets
  # These will override any persistent orders for the same fleet
  # EXCEPT for Reserve/Mothball fleets which have locked permanent orders
  for houseId in state.houses.keys:
    if houseId in orders:
      when not defined(release):
        echo "  [NEW ORDERS - COMMAND PHASE] ", $houseId, ": ", orders[houseId].fleetOrders.len, " new orders"
      for order in orders[houseId].fleetOrders:
        # Check if this fleet has a locked permanent order (Reserve/Mothball)
        if order.fleetId in state.fleets:
          let fleet = state.fleets[order.fleetId]
          if fleet.status == FleetStatus.Reserve or fleet.status == FleetStatus.Mothballed:
            # Skip new orders for Reserve/Mothball fleets (orders are locked)
            when not defined(release):
              echo "    [LOCKED] Fleet ", order.fleetId, " has locked permanent order (status: ", fleet.status, "), ignoring new order"
            continue

        allFleetOrders.add((houseId, order))
        newOrdersThisTurn.incl(order.fleetId)
        # Store new order as persistent (will execute next turn if not completed)
        state.fleetOrders[order.fleetId] = order

  # Step 2: Add PERSISTENT orders from previous turns (not overridden this turn)
  when not defined(release):
    echo "  [PERSISTENT ORDERS] Checking ", state.fleetOrders.len, " persistent orders from previous turns"
  for fleetId, persistentOrder in state.fleetOrders:
    # Skip if this fleet got a new order this turn (new order overrides persistent)
    if fleetId in newOrdersThisTurn:
      when not defined(release):
        echo "    [OVERRIDE] Fleet ", fleetId, " persistent order overridden by new order"
      continue

    # Verify fleet still exists
    if fleetId notin state.fleets:
      when not defined(release):
        echo "    [STALE] Fleet ", fleetId, " no longer exists, dropping persistent order"
      continue

    # Add persistent order to execution queue
    let fleet = state.fleets[fleetId]
    allFleetOrders.add((fleet.owner, persistentOrder))
    when not defined(release):
      echo "    [PERSISTENT] Fleet ", fleetId, " continuing order: ", $persistentOrder.orderType

  when not defined(release):
    echo "  [TOTAL - COMMAND PHASE] ", allFleetOrders.len, " total fleet orders across all houses"

  # Sort by priority
  allFleetOrders.sort do (a, b: (HouseId, FleetOrder)) -> int:
    cmp(a[1].priority, b[1].priority)

  # CRITICAL: Enforce one order per fleet per turn
  # Track which fleets have already executed orders this turn
  var fleetsProcessed = initHashSet[FleetId]()

  # ===================================================================
  # SIMULTANEOUS COLONIZATION RESOLUTION
  # ===================================================================
  # Resolve all colonization orders simultaneously to prevent first-mover advantage
  # This must happen before the main fleet order loop
  when not defined(release):
    echo "  [SIMULTANEOUS COLONIZATION] Resolving colonization orders fairly..."

  let colonizationResults = simultaneous.resolveColonization(state, orders, rng)

  when not defined(release):
    echo "  [SIMULTANEOUS COLONIZATION] Resolved ", colonizationResults.len, " colonization attempts"
    for result in colonizationResults:
      echo "    House ", result.houseId, " Fleet ", result.fleetId, ": ", result.outcome,
           " (prestige: +", result.prestigeAwarded, ")"

  # ===================================================================
  # SIMULTANEOUS BLOCKADE RESOLUTION
  # ===================================================================
  when not defined(release):
    echo "  [SIMULTANEOUS BLOCKADE] Resolving blockade orders fairly..."

  let blockadeResults = simultaneous_blockade.resolveBlockades(state, orders, rng)

  when not defined(release):
    echo "  [SIMULTANEOUS BLOCKADE] Resolved ", blockadeResults.len, " blockade attempts"

  # ===================================================================
  # SIMULTANEOUS PLANETARY COMBAT RESOLUTION
  # ===================================================================
  when not defined(release):
    echo "  [SIMULTANEOUS PLANETARY COMBAT] Resolving planetary combat orders fairly..."

  let planetaryCombatResults = simultaneous_planetary.resolvePlanetaryCombat(state, orders, rng)

  when not defined(release):
    echo "  [SIMULTANEOUS PLANETARY COMBAT] Resolved ", planetaryCombatResults.len, " planetary combat attempts"

  # ===================================================================
  # SIMULTANEOUS ESPIONAGE RESOLUTION
  # ===================================================================
  when not defined(release):
    echo "  [SIMULTANEOUS ESPIONAGE] Resolving fleet espionage orders fairly..."

  let espionageResults = simultaneous_espionage.resolveEspionage(state, orders, rng)

  when not defined(release):
    echo "  [SIMULTANEOUS ESPIONAGE] Resolved ", espionageResults.len, " fleet espionage attempts"

  # Process OrderPacket.espionageAction (EBP-based espionage)
  when not defined(release):
    echo "  [ESPIONAGE ACTIONS] Processing EBP-based espionage actions..."

  simultaneous_espionage.processEspionageActions(state, orders, rng)

  when not defined(release):
    echo "  [ESPIONAGE ACTIONS] Completed EBP-based espionage processing"

  # ===================================================================
  # FLEET ORDER EXECUTION
  # ===================================================================
  # Execute all fleet orders through the new executor
  when not defined(release):
    var processCount = 0
  for (houseId, order) in allFleetOrders:
    # Skip if this fleet already executed an order this turn
    # ROBUSTNESS: Prevent duplicate orders for same fleet (from buggy AI or malicious input)
    when not defined(release):
      processCount += 1
      echo "    [DEDUP CHECK #", processCount, "] Fleet ", order.fleetId, " - already in set: ", (order.fleetId in fleetsProcessed), " - set size: ", fleetsProcessed.len
    if order.fleetId in fleetsProcessed:
      echo "    [SKIPPED] Fleet ", order.fleetId, " (", $order.orderType, ") - already executed an order this turn"
      continue

    fleetsProcessed.incl(order.fleetId)
    when not defined(release):
      echo "    [ADDED TO SET] Fleet ", order.fleetId, " - set size now: ", fleetsProcessed.len
    when not defined(release):
      echo "    [PROCESSING] Fleet ", order.fleetId, " order: ", $order.orderType

    # PRE-EXECUTION VALIDATION: Check if order target is still valid
    # If destination became hostile, abort mission and seek home
    var shouldAbortMission = false
    if order.targetSystem.isSome:
      let targetSystem = order.targetSystem.get()

      # Check if target system is now enemy-controlled
      if targetSystem in state.colonies:
        let colony = state.colonies[targetSystem]
        if colony.owner != houseId:
          let house = state.houses[houseId]
          if house.diplomaticRelations.isEnemy(colony.owner):
            # Target is now enemy territory - abort mission
            shouldAbortMission = true
            when not defined(release):
              echo "    [MISSION ABORT] Target system ", targetSystem, " is enemy-controlled - aborting"

    # If mission should abort, replace with Seek Home order
    var actualOrder = order
    if shouldAbortMission:
      # Find closest friendly colony for retreat
      if order.fleetId in state.fleets:
        let fleet = state.fleets[order.fleetId]
        let safeDestination = findClosestOwnedColony(state, fleet.location, houseId)

        if safeDestination.isSome:
          # Replace order with Seek Home
          actualOrder = FleetOrder(
            fleetId: order.fleetId,
            orderType: FleetOrderType.SeekHome,
            targetSystem: safeDestination,
            targetFleet: none(FleetId),
            priority: order.priority
          )
          # Update persistent order
          state.fleetOrders[order.fleetId] = actualOrder
          echo "    [MISSION ABORT] Fleet ", order.fleetId, " seeking home to system ", safeDestination.get()
        else:
          # No safe destination - assign Hold at current position
          actualOrder = FleetOrder(
            fleetId: order.fleetId,
            orderType: FleetOrderType.Hold,
            targetSystem: some(fleet.location),
            targetFleet: none(FleetId),
            priority: order.priority
          )
          state.fleetOrders[order.fleetId] = actualOrder
          echo "    [MISSION ABORT] Fleet ", order.fleetId, " has no safe destination - holding position"

    # Execute the validated order
    let result = executeFleetOrder(state, houseId, actualOrder)

    if result.success:
      echo "    [", $order.orderType, "] ", result.message
      # Add events from order execution
      for eventMsg in result.eventsGenerated:
        events.add(GameEvent(
          eventType: GameEventType.Battle,
          houseId: houseId,
          description: eventMsg,
          systemId: order.targetSystem
        ))

      # UNIVERSAL PATTERN: All fleet orders follow "Move-to-ACTION"
      # 1. Move fleet to target (if needed)
      # 2. Execute action at target
      case order.orderType
      of FleetOrderType.Move, FleetOrderType.SeekHome, FleetOrderType.Patrol:
        # Pure movement orders - just move
        resolveMovementOrder(state, houseId, order, events)

      of FleetOrderType.Colonize:
        # Check if already handled by simultaneous resolution
        if simultaneous.wasColonizationHandled(colonizationResults, houseId, order.fleetId):
          when not defined(release):
            echo "    [COLONIZE SKIP] Fleet ", order.fleetId, " already handled by simultaneous resolution"
          discard
        else:
          # Move-to-Colonize: Fleet moves to target then colonizes
          when not defined(release):
            echo "    [BEFORE COLONIZE CALL] About to call resolveColonizationOrder for fleet ", order.fleetId
          resolveColonizationOrder(state, houseId, order, events)
          when not defined(release):
            echo "    [AFTER COLONIZE CALL] resolveColonizationOrder returned for fleet ", order.fleetId

      of FleetOrderType.Bombard:
        # Check if already handled by simultaneous resolution
        if simultaneous_planetary.wasPlanetaryCombatHandled(planetaryCombatResults, houseId, order.fleetId):
          discard  # Already handled
        else:
          resolveBombardment(state, houseId, order, events)

      of FleetOrderType.Invade:
        # Check if already handled by simultaneous resolution
        if simultaneous_planetary.wasPlanetaryCombatHandled(planetaryCombatResults, houseId, order.fleetId):
          discard  # Already handled
        else:
          resolveInvasion(state, houseId, order, events)

      of FleetOrderType.Blitz:
        # Check if already handled by simultaneous resolution
        if simultaneous_planetary.wasPlanetaryCombatHandled(planetaryCombatResults, houseId, order.fleetId):
          discard  # Already handled
        else:
          resolveBlitz(state, houseId, order, events)

      of FleetOrderType.SpyPlanet, FleetOrderType.SpySystem, FleetOrderType.HackStarbase:
        # Check if already handled by simultaneous resolution
        if simultaneous_espionage.wasEspionageHandled(espionageResults, houseId, order.fleetId):
          discard  # Already handled
        else:
          # TODO: Implement individual espionage handlers
          discard

      of FleetOrderType.BlockadePlanet:
        # Check if already handled by simultaneous resolution
        if simultaneous_blockade.wasBlockadeHandled(blockadeResults, houseId, order.fleetId):
          discard  # Already handled
        else:
          # TODO: Implement individual blockade handler
          discard
      of FleetOrderType.Reserve:
        # Place fleet on reserve status
        # Per economy.md:3.9 - ships auto-join colony's single reserve fleet
        if order.fleetId in state.fleets:
          var fleet = state.fleets[order.fleetId]
          let colonySystem = fleet.location

          # Check if colony already has a reserve fleet
          var reserveFleetId: Option[FleetId] = none(FleetId)
          for fleetId, existingFleet in state.fleets:
            if existingFleet.owner == fleet.owner and
               existingFleet.location == colonySystem and
               existingFleet.status == FleetStatus.Reserve and
               fleetId != order.fleetId:
              reserveFleetId = some(fleetId)
              break

          if reserveFleetId.isSome:
            # Merge this fleet into existing reserve fleet
            let targetId = reserveFleetId.get()
            var targetFleet = state.fleets[targetId]

            # Transfer all squadrons to reserve fleet
            for squadron in fleet.squadrons:
              targetFleet.squadrons.add(squadron)

            # Transfer spacelift ships if any
            for ship in fleet.spaceLiftShips:
              targetFleet.spaceLiftShips.add(ship)

            state.fleets[targetId] = targetFleet

            # Remove the now-empty fleet
            state.fleets.del(order.fleetId)

            echo "    [Reserve] Fleet ", order.fleetId, " merged into colony reserve fleet ", targetId
          else:
            # Create new reserve fleet at this colony
            # CRITICAL: Get, modify, write back to persist
            var fleet = state.fleets[order.fleetId]
            fleet.status = FleetStatus.Reserve
            state.fleets[order.fleetId] = fleet
            echo "    [Reserve] Fleet ", order.fleetId, " is now colony reserve fleet (50% maint, half AS/DS)"

            # Assign permanent GuardPlanet order (reserve fleets can't be moved)
            let guardOrder = FleetOrder(
              fleetId: order.fleetId,
              orderType: FleetOrderType.GuardPlanet,
              targetSystem: some(colonySystem),
              targetFleet: none(FleetId),
              priority: 1
            )
            state.fleetOrders[order.fleetId] = guardOrder
            echo "    [Reserve] Assigned permanent GuardPlanet order (can't be moved)"
      of FleetOrderType.Mothball:
        # Mothball fleet
        # Per economy.md:3.9 - ships auto-join colony's single mothballed fleet
        if order.fleetId in state.fleets:
          var fleet = state.fleets[order.fleetId]
          let colonySystem = fleet.location

          # Check if colony already has a mothballed fleet
          var mothballedFleetId: Option[FleetId] = none(FleetId)
          for fleetId, existingFleet in state.fleets:
            if existingFleet.owner == fleet.owner and
               existingFleet.location == colonySystem and
               existingFleet.status == FleetStatus.Mothballed and
               fleetId != order.fleetId:
              mothballedFleetId = some(fleetId)
              break

          if mothballedFleetId.isSome:
            # Merge this fleet into existing mothballed fleet
            let targetId = mothballedFleetId.get()
            var targetFleet = state.fleets[targetId]

            # Transfer all squadrons to mothballed fleet
            for squadron in fleet.squadrons:
              targetFleet.squadrons.add(squadron)

            # Transfer spacelift ships if any
            for ship in fleet.spaceLiftShips:
              targetFleet.spaceLiftShips.add(ship)

            state.fleets[targetId] = targetFleet

            # Remove the now-empty fleet
            state.fleets.del(order.fleetId)

            echo "    [Mothball] Fleet ", order.fleetId, " merged into colony mothballed fleet ", targetId
          else:
            # Create new mothballed fleet at this colony
            # CRITICAL: Get, modify, write back to persist
            var fleet = state.fleets[order.fleetId]
            fleet.status = FleetStatus.Mothballed
            state.fleets[order.fleetId] = fleet
            echo "    [Mothball] Fleet ", order.fleetId, " is now mothballed (0% maint, no combat)"

            # Assign permanent Hold order (mothballed fleets can't be moved)
            let holdOrder = FleetOrder(
              fleetId: order.fleetId,
              orderType: FleetOrderType.Hold,
              targetSystem: some(colonySystem),
              targetFleet: none(FleetId),
              priority: 1
            )
            state.fleetOrders[order.fleetId] = holdOrder
            echo "    [Mothball] Assigned permanent Hold (00) order (can't be moved)"
      else:
        discard

      # Check if order is completed and should be cleared
      var orderCompleted = false
      case order.orderType
      of FleetOrderType.Colonize:
        # Colonize completes when colony is established at target
        if order.targetSystem.isSome:
          if order.targetSystem.get() in state.colonies:
            orderCompleted = true
      of FleetOrderType.Move, FleetOrderType.SeekHome:
        # Movement completes when fleet reaches destination
        if order.fleetId in state.fleets and order.targetSystem.isSome:
          if state.fleets[order.fleetId].location == order.targetSystem.get():
            orderCompleted = true
      of FleetOrderType.Hold:
        # Hold never completes - continues indefinitely
        # SPECIAL: Mothballed fleets have permanent Hold (can't be changed)
        discard
      of FleetOrderType.GuardPlanet, FleetOrderType.GuardStarbase:
        # Guard orders never complete - continue indefinitely
        # SPECIAL: Reserve fleets have permanent Guard (can't be changed)
        discard
      of FleetOrderType.Reserve, FleetOrderType.Mothball:
        # Status change orders complete immediately (but assign permanent follow-up order)
        orderCompleted = true
      else:
        # Other orders (Patrol, Blockade, etc.) continue indefinitely
        discard

      if orderCompleted:
        # Assign Hold order so fleet maintains position until commanded otherwise
        # Exception: Reserve/Mothball already assigned permanent orders (don't override)
        if order.orderType notin [FleetOrderType.Reserve, FleetOrderType.Mothball]:
          # Clear completed order
          state.fleetOrders.del(order.fleetId)
          # Verify fleet still exists (might have been merged or destroyed)
          if order.fleetId in state.fleets:
            let holdOrder = FleetOrder(
              fleetId: order.fleetId,
              orderType: FleetOrderType.Hold,
              targetSystem: some(state.fleets[order.fleetId].location),
              targetFleet: none(FleetId),
              priority: 1
            )
            state.fleetOrders[order.fleetId] = holdOrder
            when not defined(release):
              echo "    [ORDER COMPLETED] Fleet ", order.fleetId, " order ", $order.orderType, " completed → assigned Hold order"
        else:
          when not defined(release):
            echo "    [ORDER COMPLETED] Fleet ", order.fleetId, " order ", $order.orderType, " completed (status changed)"

    else:
      echo "    [", $order.orderType, "] FAILED: ", result.message

  when not defined(release):
    logDebug("Fleet", "Fleet order processing complete", "processed=", $processCount)

  # Execute standing orders for fleets without explicit orders
  # This happens AFTER explicit orders are processed
  # Standing orders provide persistent behaviors (patrol, auto-colonize, etc.)
  executeStandingOrders(state, state.turn)

  # =========================================================================
  # SQUADRON AUTO-BALANCING WITHIN FLEETS
  # =========================================================================
  # Optimize squadron composition within each fleet (if enabled per-fleet)
  #
  # **Purpose:**
  # Redistribute escort ships across squadrons to maximize command capacity
  # utilization and create balanced, effective battle groups.
  #
  # **When This Runs:**
  # - End of Command Phase (AFTER all fleet movements and orders complete)
  # - Only affects fleets with `autoBalanceSquadrons = true`
  # - Only processes fleets with 2+ squadrons
  #
  # **What It Does:**
  # 1. Extracts all escort ships from all squadrons (flagships never move)
  # 2. Sorts escorts by command cost (largest first for optimal bin packing)
  # 3. Redistributes escorts using greedy algorithm:
  #    - Each escort assigned to squadron with most available command capacity
  #    - Balances command capacity usage across all squadrons in fleet
  #    - Prevents underutilized and overcrowded squadrons
  #
  # **Example:**
  # Before: Squadron 1 (BB, CR=15): 5 destroyers (FULL)
  #         Squadron 2 (BB, CR=15): 0 escorts (EMPTY)
  # After:  Squadron 1 (BB, CR=15): 2-3 destroyers (BALANCED)
  #         Squadron 2 (BB, CR=15): 2-3 destroyers (BALANCED)
  #
  # **Benefits:**
  # - More efficient command capacity utilization
  # - Better distributed firepower across squadrons
  # - AI can maintain optimal fleet organization automatically
  # - Newly commissioned ships integrate seamlessly
  #
  # **Design Note:**
  # This is enabled by default (default: true) to maintain optimal fleet organization.
  # Players can disable it per-fleet to preserve specific formations
  # (e.g., dedicated scout squadrons, intentional asymmetric compositions).
  # Most fleets benefit from auto-balancing, especially AI and reinforcement fleets.
  # =========================================================================
  when not defined(release):
    echo "  [AUTO-BALANCE] Checking fleets for squadron auto-balancing..."
  var balancedCount = 0
  for fleetId, fleet in state.fleets.mpairs:
    if fleet.autoBalanceSquadrons and fleet.squadrons.len >= 2:
      when not defined(release):
        echo "    [AUTO-BALANCE] Fleet ", fleetId, " (", fleet.squadrons.len, " squadrons) - balancing..."
      fleet.balanceSquadrons()
      balancedCount += 1
  when not defined(release):
    echo "  [AUTO-BALANCE] Balanced ", balancedCount, " fleets"
