## Turn resolution engine - the heart of EC4X gameplay
##
## OFFLINE GAMEPLAY SYSTEM - No network dependencies
## This module is designed to work standalone for local/hotseat multiplayer
## Network transport (Nostr) wraps around this engine without modifying it
##
## REFACTORED: Main orchestrator that coordinates resolution phases
## Individual phase logic has been extracted to resolution/* modules

import std/[tables, algorithm, options, random, sequtils, hashes]
import ../common/[hex, types/core, types/combat]
import gamestate, orders, fleet
import espionage/[types as esp_types, engine as esp_engine]
import diplomacy/[types as dip_types]
import commands/executor
# Import resolution modules
import resolution/[types as res_types, fleet_orders, combat_resolution, economy_resolution, diplomatic_resolution]

# Re-export resolution types for backward compatibility
export res_types.GameEvent, res_types.GameEventType, res_types.CombatReport

type
  TurnResult* = object
    newState*: GameState
    events*: seq[res_types.GameEvent]
    combatReports*: seq[res_types.CombatReport]

# Forward declarations for phase functions
proc resolveConflictPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                         combatReports: var seq[res_types.CombatReport], events: var seq[res_types.GameEvent])
proc resolveCommandPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                        events: var seq[res_types.GameEvent])

## Main Turn Resolution

proc resolveTurn*(state: GameState, orders: Table[HouseId, OrderPacket]): TurnResult =
  ## Resolve a complete game turn
  ## Returns new game state and events that occurred

  result.newState = state  # Start with current state
  result.events = @[]
  result.combatReports = @[]

  # Initialize RNG for this turn (use turn number as seed for reproducibility)
  var rng = initRand(state.turn)

  echo "Resolving turn ", state.turn, " (Year ", state.year, ", Month ", state.month, ")"

  # Phase 1: Conflict (combat, infrastructure damage, espionage)
  resolveConflictPhase(result.newState, orders, result.combatReports, result.events)

  # Phase 2: Income (resource collection)
  resolveIncomePhase(result.newState, orders)

  # Phase 3: Command (build orders, fleet orders, diplomatic actions)
  resolveCommandPhase(result.newState, orders, result.events)

  # Phase 4: Maintenance (upkeep, effect decrements, status updates)
  resolveMaintenancePhase(result.newState, result.events)

  # Advance to next turn
  result.newState.turn += 1
  result.newState.month += 1
  if result.newState.month > 12:
    result.newState.month = 1
    result.newState.year += 1

  return result

## Phase 1: Conflict

proc resolveConflictPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                         combatReports: var seq[res_types.CombatReport], events: var seq[res_types.GameEvent]) =
  ## Phase 1: Resolve all combat and infrastructure damage
  ## This happens FIRST so damaged facilities affect production
  echo "  [Conflict Phase]"

  # Find all systems with hostile fleets
  var combatSystems: seq[SystemId] = @[]

  for systemId, system in state.starMap.systems:
    # Check if multiple houses have fleets here
    var housesPresent: seq[HouseId] = @[]
    for fleet in state.fleets.values:
      if fleet.location == systemId and fleet.owner notin housesPresent:
        housesPresent.add(fleet.owner)

    if housesPresent.len > 1:
      # Check if any pairs of houses are at war (Enemy status)
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
          # NonAggression pacts prevent combat
          if relation == dip_types.DiplomaticState.Enemy or
             relation == dip_types.DiplomaticState.Neutral:
            combatDetected = true
            break
        if combatDetected:
          break

      if combatDetected:
        combatSystems.add(systemId)

  # Resolve combat in each system (operations.md:7.0)
  for systemId in combatSystems:
    resolveBattle(state, systemId, orders, combatReports, events)

  # Process espionage actions (per gameplay.md:1.3.1 - resolved in Conflict Phase)
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

        # Execute espionage action with detection roll
        var rng = initRand(int64(state.turn) xor attempt.attacker.hash() xor attempt.target.hash())
        let result = esp_engine.executeEspionage(
          attempt,
          targetCICLevel,
          targetCIP,
          rng
        )

        # Apply results
        if result.success:
          echo "    ", attempt.attacker, " espionage: ", result.description

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

  # Process planetary combat orders (operations.md:7.5, 7.6)
  # These execute after space/orbital combat in linear progression
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
                        events: var seq[res_types.GameEvent]) =
  ## Phase 3: Execute orders
  ## Build orders may fail if shipyards were destroyed in conflict phase
  echo "  [Command Phase]"

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
  var allFleetOrders: seq[(HouseId, FleetOrder)] = @[]

  for houseId in state.houses.keys:
    if houseId in orders:
      for order in orders[houseId].fleetOrders:
        allFleetOrders.add((houseId, order))

  # Sort by priority
  allFleetOrders.sort do (a, b: (HouseId, FleetOrder)) -> int:
    cmp(a[1].priority, b[1].priority)

  # Execute all fleet orders through the new executor
  for (houseId, order) in allFleetOrders:
    # Check if fleet should automatically seek home due to dangerous situation
    let fleetOpt = state.getFleet(order.fleetId)
    var actualOrder = order

    if fleetOpt.isSome:
      let fleet = fleetOpt.get()
      if shouldAutoSeekHome(state, fleet, order):
        # Override order with automated Seek Home
        let safeDestination = findClosestOwnedColony(state, fleet.location, fleet.owner)
        if safeDestination.isSome:
          actualOrder = FleetOrder(
            fleetId: order.fleetId,
            orderType: FleetOrderType.SeekHome,
            targetSystem: safeDestination,
            targetFleet: none(FleetId),
            priority: order.priority
          )
          echo "    [AUTO SEEK HOME] Fleet ", order.fleetId, " aborting ", $order.orderType,
               " - destination hostile, retreating to system ", safeDestination.get()
          events.add(GameEvent(
            eventType: GameEventType.Battle,
            houseId: houseId,
            description: "Fleet " & order.fleetId & " aborted mission - automatic retreat to safe territory",
            systemId: some(fleet.location)
          ))
        else:
          echo "    [AUTO SEEK HOME] Fleet ", order.fleetId, " has no safe destination - holding position"
          # No safe destination - fleet holds in place
          actualOrder = FleetOrder(
            fleetId: order.fleetId,
            orderType: FleetOrderType.Hold,
            targetSystem: none(SystemId),
            targetFleet: none(FleetId),
            priority: order.priority
          )

    let result = executeFleetOrder(state, houseId, actualOrder)

    if result.success:
      echo "    [", $actualOrder.orderType, "] ", result.message
      # Add events from order execution
      for eventMsg in result.eventsGenerated:
        events.add(GameEvent(
          eventType: GameEventType.Battle,
          houseId: houseId,
          description: eventMsg,
          systemId: actualOrder.targetSystem
        ))

      # Some orders need additional processing after validation
      case actualOrder.orderType
      of FleetOrderType.Move, FleetOrderType.SeekHome, FleetOrderType.Patrol:
        # Executor validates, this does actual pathfinding and movement
        resolveMovementOrder(state, houseId, actualOrder, events)
      of FleetOrderType.Colonize:
        # Executor validates, this does actual colony creation
        resolveColonizationOrder(state, houseId, order, events)
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
            state.fleets[order.fleetId].status = FleetStatus.Reserve
            echo "    [Reserve] Fleet ", order.fleetId, " is now colony reserve fleet (50% maint, half AS/DS)"
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
            state.fleets[order.fleetId].status = FleetStatus.Mothballed
            echo "    [Mothball] Fleet ", order.fleetId, " is now mothballed (0% maint, no combat)"
      else:
        discard
    else:
      echo "    [", $actualOrder.orderType, "] FAILED: ", result.message
