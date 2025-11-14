## Turn resolution engine - the heart of EC4X gameplay

import std/[tables, algorithm, options]
import ../common/[types, hex]
import gamestate, orders, fleet, ship, starmap

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

## Main Turn Resolution

proc resolveTurn*(state: GameState, orders: Table[HouseId, OrderPacket]): TurnResult =
  ## Resolve a complete game turn
  ## Returns new game state and events that occurred

  result.newState = state  # Start with current state
  result.events = @[]
  result.combatReports = @[]

  echo "Resolving turn ", state.turn, " (Year ", state.year, ", Month ", state.month, ")"

  # Phase 1: Income Phase
  # - Collect taxes from colonies
  # - Calculate production
  # - Allocate research points
  resolveIncomePhase(result.newState, orders)

  # Phase 2: Command Phase
  # - Process build orders
  # - Execute movement orders
  # - Process colonization
  resolveCommandPhase(result.newState, orders, result.events)

  # Phase 3: Conflict Phase
  # - Resolve space battles
  # - Process bombardments
  # - Resolve invasions
  resolveConflictPhase(result.newState, orders, result.combatReports, result.events)

  # Phase 4: Maintenance Phase
  # - Pay fleet upkeep
  # - Apply attrition
  # - Check victory conditions
  resolveMaintenancePhase(result.newState, result.events)

  # Advance turn counter
  result.newState.advanceTurn()

  echo "Turn ", state.turn, " resolved. New turn: ", result.newState.turn

## Phase 1: Income

proc resolveIncomePhase(state: var GameState, orders: Table[HouseId, OrderPacket]) =
  ## Phase 1: Collect income and allocate resources
  echo "  [Income Phase]"

  for houseId, house in state.houses:
    var totalIncome = 0
    var totalProduction = 0

    # Collect from colonies
    for colony in state.getHouseColonies(houseId):
      let income = colony.population * 100  # 100 credits per million population
      let production = colony.population * 10 + colony.infrastructure * 50

      totalIncome += income
      totalProduction += production

    # Update treasury
    state.houses[houseId].treasury += totalIncome

    # Allocate research if orders provided
    if houseId in orders:
      let packet = orders[houseId]
      for field, points in packet.researchAllocation:
        # TODO: Apply research points to tech tree
        discard

    echo "    ", house.name, ": +", totalIncome, " credits, ", totalProduction, " production"

## Phase 2: Command

proc resolveCommandPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                        events: var seq[GameEvent]) =
  ## Phase 2: Execute orders
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
  # TODO: Implement ship construction, building construction, infrastructure upgrades
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

  # TODO: Use pathfinding to determine route
  # TODO: Check lane traversal rules
  # TODO: Update fleet location
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

  # Create colony
  let colony = createHomeColony(targetId, houseId)
  state.colonies[targetId] = colony

  # Update system ownership
  if targetId in state.starMap.systems:
    var sys = state.starMap.systems[targetId]
    sys.owner = some(houseId)
    state.starMap.systems[targetId] = sys

  events.add(GameEvent(
    eventType: geColonyEstablished,
    houseId: houseId,
    description: "Established colony at " & targetId,
    systemId: some(targetId)
  ))

  echo "    ", state.houses[houseId].name, " colonized ", targetId

## Phase 3: Conflict

proc resolveConflictPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                         combatReports: var seq[CombatReport], events: var seq[GameEvent]) =
  ## Phase 3: Resolve battles
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

  # Process bombardment orders
  for houseId in state.houses.keys:
    if houseId in orders:
      for order in orders[houseId].fleetOrders:
        if order.orderType == foBombard:
          resolveBombardment(state, houseId, order, events)

proc resolveBattle(state: var GameState, systemId: SystemId,
                  combatReports: var seq[CombatReport], events: var seq[GameEvent]) =
  ## Resolve space battle in a system
  echo "    Battle at ", systemId

  # TODO: Implement combat resolution
  # - Group fleets by house
  # - Calculate combat strength
  # - Apply damage based on weapon tech
  # - Remove destroyed ships
  # - Generate combat report

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
  # TODO: Implement bombardment
  # - Check fleet is in orbit
  # - Damage colony infrastructure/population
  # - Generate event
  discard

## Phase 4: Maintenance

proc resolveMaintenancePhase(state: var GameState, events: var seq[GameEvent]) =
  ## Phase 4: Upkeep and cleanup
  echo "  [Maintenance Phase]"

  for houseId, house in state.houses:
    # Calculate fleet upkeep
    var upkeep = 0
    for fleet in state.getHouseFleets(houseId):
      for ship in fleet.ships:
        upkeep += 10  # 10 credits per ship

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
    state.phase = gpCompleted
    echo "  *** ", state.houses[victorId].name, " has won the game! ***"
