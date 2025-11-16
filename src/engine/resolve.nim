## Turn resolution engine - the heart of EC4X gameplay
##
## OFFLINE GAMEPLAY SYSTEM - No network dependencies
## This module is designed to work standalone for local/hotseat multiplayer
## Network transport (Nostr) wraps around this engine without modifying it

import std/[tables, algorithm, options]
import ../common/[hex, types/core]
import gamestate, orders, fleet, ship, starmap, combat, economy

type
  TurnResult* = object
    newState*: GameState
    events*: seq[GameEvent]
    combatReports*: seq[CombatReport]

  GameEvent* = object
    eventType*: GameEventType
    houseId*: HouseId
    description*: string
    systemId*: Option[SystemId]

  GameEventType* = enum
    geColonyEstablished, geSystemCaptured, geBattleOccurred,
    geTechAdvance, geFleetDestroyed, geHouseEliminated

  CombatReport* = object
    systemId*: SystemId
    attackers*: seq[HouseId]
    defenders*: seq[HouseId]
    attackerLosses*: int
    defenderLosses*: int
    victor*: Option[HouseId]

# Forward declarations for phase functions
proc resolveIncomePhase(state: var GameState, orders: Table[HouseId, OrderPacket])
proc resolveCommandPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                        events: var seq[GameEvent])
proc resolveConflictPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                         combatReports: var seq[CombatReport], events: var seq[GameEvent])
proc resolveMaintenancePhase(state: var GameState, events: var seq[GameEvent])

# Forward declarations for helper functions
proc resolveBuildOrders(state: var GameState, packet: OrderPacket, events: var seq[GameEvent])
proc resolveMovementOrder(state: var GameState, houseId: HouseId, order: FleetOrder,
                         events: var seq[GameEvent])
proc resolveColonizationOrder(state: var GameState, houseId: HouseId, order: FleetOrder,
                              events: var seq[GameEvent])
proc resolveBattle(state: var GameState, systemId: SystemId,
                  combatReports: var seq[CombatReport], events: var seq[GameEvent])
proc resolveBombardment(state: var GameState, houseId: HouseId, order: FleetOrder,
                       events: var seq[GameEvent])

## Main Turn Resolution

proc resolveTurn*(state: GameState, orders: Table[HouseId, OrderPacket]): TurnResult =
  ## Resolve a complete game turn
  ## Returns new game state and events that occurred

  result.newState = state  # Start with current state
  result.events = @[]
  result.combatReports = @[]

  echo "Resolving turn ", state.turn, " (Year ", state.year, ", Month ", state.month, ")"

  # Phase 1: Conflict Phase
  # - Resolve space battles
  # - Process bombardments
  # - Resolve invasions
  # - Damage infrastructure (shipyards, starbases, planetary improvements)
  # NOTE: Conflict happens FIRST so damaged infrastructure affects production
  resolveConflictPhase(result.newState, orders, result.combatReports, result.events)

  # Phase 2: Income Phase
  # - Collect taxes from colonies (reduced if infrastructure damaged)
  # - Calculate production (accounts for bombed facilities)
  # - Allocate research points
  resolveIncomePhase(result.newState, orders)

  # Phase 3: Command Phase
  # - Process build orders (may fail if shipyards destroyed)
  # - Execute movement orders
  # - Process colonization
  resolveCommandPhase(result.newState, orders, result.events)

  # Phase 4: Maintenance Phase
  # - Pay fleet upkeep
  # - Advance construction projects
  # - Apply repairs to damaged facilities
  # - Check victory conditions
  resolveMaintenancePhase(result.newState, result.events)

  # Advance turn counter
  result.newState.advanceTurn()

  echo "Turn ", state.turn, " resolved. New turn: ", result.newState.turn

## Phase 1: Conflict

proc resolveConflictPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                         combatReports: var seq[CombatReport], events: var seq[GameEvent]) =
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
      # Check if any are at war
      # TODO: Check diplomatic relations
      # For now, assume all non-allied fleets fight
      combatSystems.add(systemId)

  # Resolve battles in each system
  for systemId in combatSystems:
    resolveBattle(state, systemId, combatReports, events)

  # Process bombardment orders (damages infrastructure before income phase)
  for houseId in state.houses.keys:
    if houseId in orders:
      for order in orders[houseId].fleetOrders:
        if order.orderType == foBombard:
          resolveBombardment(state, houseId, order, events)

## Phase 2: Income

proc resolveIncomePhase(state: var GameState, orders: Table[HouseId, OrderPacket]) =
  ## Phase 2: Collect income and allocate resources
  ## Production is calculated AFTER conflict, so damaged infrastructure produces less
  echo "  [Income Phase]"

  for houseId, house in state.houses:
    # TODO: Call economy.calculateHouseIncome() instead of inline calculation
    var totalIncome = 0
    var totalProduction = 0

    # Collect from colonies
    for colony in state.getHouseColonies(houseId):
      # TODO: Call economy.calculateProduction() for accurate calculations
      let income = colony.population * 100  # 100 credits per million population (placeholder)
      let production = colony.population * 10 + colony.infrastructure * 50

      totalIncome += income
      totalProduction += production

    # Update treasury
    state.houses[houseId].treasury += totalIncome

    # Allocate research if orders provided
    if houseId in orders:
      let packet = orders[houseId]
      for field, points in packet.researchAllocation:
        # TODO: Call economy.applyResearch()
        discard

    echo "    ", house.name, ": +", totalIncome, " credits, ", totalProduction, " production"

## Phase 3: Command

proc resolveCommandPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                        events: var seq[GameEvent]) =
  ## Phase 3: Execute orders
  ## Build orders may fail if shipyards were destroyed in conflict phase
  echo "  [Command Phase]"

  # Process build orders first
  for houseId in state.houses.keys:
    if houseId in orders:
      resolveBuildOrders(state, orders[houseId], events)

  # Process movement orders (sorted by priority)
  var allMovementOrders: seq[(HouseId, FleetOrder)] = @[]

  for houseId in state.houses.keys:
    if houseId in orders:
      for order in orders[houseId].fleetOrders:
        if order.orderType in [foMove, foSeekHome, foPatrol]:
          allMovementOrders.add((houseId, order))

  # Sort by priority
  allMovementOrders.sort do (a, b: (HouseId, FleetOrder)) -> int:
    cmp(a[1].priority, b[1].priority)

  # Execute movement orders
  for (houseId, order) in allMovementOrders:
    resolveMovementOrder(state, houseId, order, events)

  # Process colonization orders
  for houseId in state.houses.keys:
    if houseId in orders:
      for order in orders[houseId].fleetOrders:
        if order.orderType == foColonize:
          resolveColonizationOrder(state, houseId, order, events)

proc resolveBuildOrders(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
  ## Process construction orders for a house
  # TODO: Call economy.startConstruction() for each build order
  # TODO: Validate orders against treasury and production capacity
  # TODO: Generate events for construction started/completed
  discard

proc resolveMovementOrder(state: var GameState, houseId: HouseId, order: FleetOrder,
                         events: var seq[GameEvent]) =
  ## Execute a fleet movement order
  if order.targetSystem.isNone:
    return

  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    return

  var fleet = fleetOpt.get()
  let targetId = order.targetSystem.get()

  echo "    Fleet ", order.fleetId, " moving to ", targetId

  # TODO: Call starmap.findPath() to determine route
  # TODO: Apply lane traversal rules (1-2 lanes per turn)
  # TODO: Handle multi-turn journeys (store waypoints on fleet)
  # TODO: Check for fleet encounters at destination
  # For now, just teleport (placeholder)
  fleet.location = targetId
  state.fleets[order.fleetId] = fleet

proc resolveColonizationOrder(state: var GameState, houseId: HouseId, order: FleetOrder,
                              events: var seq[GameEvent]) =
  ## Establish a new colony
  if order.targetSystem.isNone:
    return

  let targetId = order.targetSystem.get()

  # Check if system already colonized
  if targetId in state.colonies:
    echo "    System ", targetId, " already colonized"
    return

  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    return

  # Create colony (ownership tracked via colonies table)
  let colony = createHomeColony(targetId, houseId)
  state.colonies[targetId] = colony

  events.add(GameEvent(
    eventType: geColonyEstablished,
    houseId: houseId,
    description: "Established colony at system " & $targetId,
    systemId: some(targetId)
  ))

  echo "    ", state.houses[houseId].name, " colonized system ", targetId

## Phase 1: Conflict (helper functions)

proc resolveBattle(state: var GameState, systemId: SystemId,
                  combatReports: var seq[CombatReport], events: var seq[GameEvent]) =
  ## Resolve space battle in a system
  echo "    Battle at ", systemId

  # TODO: Gather all fleets at system
  # TODO: Group into attacker/defender based on system ownership
  # TODO: Build BattleContext with fleets and tech levels
  # TODO: Call combat.resolveBattle()
  # TODO: Apply results to game state (remove destroyed ships)
  # TODO: Generate combat report and events

  let report = CombatReport(
    systemId: systemId,
    attackers: @[],
    defenders: @[],
    attackerLosses: 0,
    defenderLosses: 0,
    victor: none(HouseId)
  )
  combatReports.add(report)

proc resolveBombardment(state: var GameState, houseId: HouseId, order: FleetOrder,
                       events: var seq[GameEvent]) =
  ## Process orbital bombardment order
  # TODO: Validate fleet is at target system
  # TODO: Get fleet and colony
  # TODO: Call combat.resolveBombardment()
  # TODO: Apply damage to colony
  # TODO: Generate event
  discard

## Phase 4: Maintenance

proc resolveMaintenancePhase(state: var GameState, events: var seq[GameEvent]) =
  ## Phase 4: Upkeep and cleanup
  echo "  [Maintenance Phase]"

  for houseId, house in state.houses:
    # TODO: Call economy.calculateHouseUpkeep() for accurate costs
    # Calculate fleet upkeep
    var upkeep = 0
    for fleet in state.getHouseFleets(houseId):
      # TODO: Call economy.calculateFleetUpkeep()
      for ship in fleet.ships:
        upkeep += 10  # 10 credits per ship (placeholder)

    # Deduct upkeep from treasury
    state.houses[houseId].treasury -= upkeep

    # Check if house can afford upkeep
    if state.houses[houseId].treasury < 0:
      echo "    ", house.name, " cannot afford upkeep! (", state.houses[houseId].treasury, " credits)"
      # TODO: Apply attrition (ships start to desert/break down)

    # Check for elimination
    let colonies = state.getHouseColonies(houseId)
    let fleets = state.getHouseFleets(houseId)

    if colonies.len == 0 and fleets.len == 0:
      state.houses[houseId].eliminated = true
      events.add(GameEvent(
        eventType: geHouseEliminated,
        houseId: houseId,
        description: house.name & " has been eliminated!",
        systemId: none(SystemId)
      ))
      echo "    ", house.name, " eliminated!"

  # Check victory condition
  let victorOpt = state.checkVictoryCondition()
  if victorOpt.isSome:
    let victorId = victorOpt.get()
    state.phase = GamePhase.Completed
    echo "  *** ", state.houses[victorId].name, " has won the game! ***"
