## Turn resolution engine - the heart of EC4X gameplay
##
## OFFLINE GAMEPLAY SYSTEM - No network dependencies
## This module is designed to work standalone for local/hotseat multiplayer
## Network transport (Nostr) wraps around this engine without modifying it

import std/[tables, algorithm, options]
import ../common/[hex, types/core, types/combat, types/tech, types/units]
import gamestate, orders, fleet, ship, starmap
import economy/[types as econ_types, engine as econ_engine, construction, maintenance]
import research/[types as res_types, advancement]
import config/prestige_config
# Note: Space combat via combat/engine module when needed

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
proc resolveMovementOrder*(state: var GameState, houseId: HouseId, order: FleetOrder,
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

  # Convert GameState colonies to M5 economy colonies
  var econColonies: seq[econ_types.Colony] = @[]
  for systemId, colony in state.colonies:
    # Convert old Colony to new M5 Colony
    econColonies.add(econ_types.Colony(
      systemId: colony.systemId,
      owner: colony.owner,
      populationUnits: colony.population,  # Map population (millions) to PU
      populationTransferUnits: 0,  # TODO: Track PTU separately
      industrial: econ_types.IndustrialUnits(units: colony.infrastructure * 10),  # Map infrastructure to IU
      planetClass: colony.planetClass,
      resources: colony.resources,
      grossOutput: colony.production,  # Use cached production
      taxRate: 50,  # TODO: Get from house tax policy
      underConstruction: none(econ_types.ConstructionProject),  # TODO: Convert construction
      infrastructureDamage: 0.0  # TODO: Track damage from combat
    ))

  # Build house tax policies (TODO: store in House)
  var houseTaxPolicies = initTable[HouseId, econ_types.TaxPolicy]()
  for houseId in state.houses.keys:
    houseTaxPolicies[houseId] = econ_types.TaxPolicy(
      currentRate: 50,  # Default
      history: @[50]
    )

  # Build house tech levels
  var houseTechLevels = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseTechLevels[houseId] = house.techTree.levels.energyLevel  # TODO: Use actual EL

  # Build house treasuries
  var houseTreasuries = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseTreasuries[houseId] = house.treasury

  # Call M5 economy engine
  let incomeReport = econ_engine.resolveIncomePhase(
    econColonies,
    houseTaxPolicies,
    houseTechLevels,
    houseTreasuries
  )

  # Apply results back to game state
  for houseId, houseReport in incomeReport.houseReports:
    state.houses[houseId].treasury = houseTreasuries[houseId]
    echo "    ", state.houses[houseId].name, ": +", houseReport.totalNet, " PP (Gross: ", houseReport.totalGross, ")"

    # Apply prestige events from economic activities
    for event in houseReport.prestigeEvents:
      state.houses[houseId].prestige += event.amount
      echo "      Prestige: ",
           (if event.amount > 0: "+" else: ""), event.amount,
           " (", event.description, ") -> ", state.houses[houseId].prestige

  # Apply research prestige from tech advancements (if any occurred)
  # Note: Tech advancements are tracked separately and applied here
  # TODO: Integrate with full research system when implemented
  # For now, research prestige is embedded in advancement events

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

proc resolveMovementOrder*(state: var GameState, houseId: HouseId, order: FleetOrder,
                         events: var seq[GameEvent]) =
  ## Execute a fleet movement order with pathfinding and lane traversal rules
  ## Per operations.md:6.1 - Lane traversal rules:
  ##   - Major lanes: 2 jumps per turn if all systems owned by player
  ##   - Major lanes: 1 jump per turn if jumping into unexplored/rival system
  ##   - Minor/Restricted lanes: 1 jump per turn maximum
  ##   - Crippled ships or Spacelift ships cannot cross Restricted lanes

  if order.targetSystem.isNone:
    return

  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    return

  var fleet = fleetOpt.get()
  let targetId = order.targetSystem.get()
  let startId = fleet.location

  # Already at destination
  if startId == targetId:
    echo "    Fleet ", order.fleetId, " already at destination"
    return

  echo "    Fleet ", order.fleetId, " moving from ", startId, " to ", targetId

  # Find path to destination (operations.md:6.1)
  let pathResult = state.starMap.findPath(startId, targetId, fleet)

  if not pathResult.found:
    echo "      No valid path found (blocked by restricted lanes or terrain)"
    return

  if pathResult.path.len < 2:
    echo "      Invalid path"
    return

  # Determine how many jumps the fleet can make this turn
  var jumpsAllowed = 1  # Default: 1 jump per turn

  # Check if we can do 2 major lane jumps (operations.md:6.1)
  if pathResult.path.len >= 3:
    # Check if all systems along path are owned by this house
    var allSystemsOwned = true
    for systemId in pathResult.path:
      if systemId notin state.colonies or state.colonies[systemId].owner != houseId:
        allSystemsOwned = false
        break

    # Check if next two jumps are both major lanes
    var nextTwoAreMajor = true
    if allSystemsOwned:
      for i in 0..<min(2, pathResult.path.len - 1):
        let fromSys = pathResult.path[i]
        let toSys = pathResult.path[i + 1]

        # Find lane type between these systems
        var laneIsMajor = false
        for lane in state.starMap.lanes:
          if (lane.source == fromSys and lane.destination == toSys) or
             (lane.source == toSys and lane.destination == fromSys):
            if lane.laneType == LaneType.Major:
              laneIsMajor = true
            break

        if not laneIsMajor:
          nextTwoAreMajor = false
          break

    # Apply 2-jump rule for major lanes in friendly territory
    if allSystemsOwned and nextTwoAreMajor:
      jumpsAllowed = 2

  # Execute movement (up to jumpsAllowed systems)
  let actualJumps = min(jumpsAllowed, pathResult.path.len - 1)
  let newLocation = pathResult.path[actualJumps]

  fleet.location = newLocation
  state.fleets[order.fleetId] = fleet

  echo "      Moved ", actualJumps, " jump(s) to system ", newLocation

  # Check for fleet encounters at destination
  # Find other fleets at the same location
  for otherFleetId, otherFleet in state.fleets:
    if otherFleetId != order.fleetId and otherFleet.location == newLocation:
      if otherFleet.owner != houseId:
        echo "      Encountered fleet ", otherFleetId, " (", otherFleet.owner, ") at ", newLocation
        # Combat will be resolved in conflict phase next turn
        # This just logs the encounter

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

  # Convert colonies for M5 maintenance
  var econColonies: seq[econ_types.Colony] = @[]
  for systemId, colony in state.colonies:
    econColonies.add(econ_types.Colony(
      systemId: colony.systemId,
      owner: colony.owner,
      populationUnits: colony.population,
      populationTransferUnits: 0,
      industrial: econ_types.IndustrialUnits(units: colony.infrastructure * 10),
      planetClass: colony.planetClass,
      resources: colony.resources,
      grossOutput: colony.production,
      taxRate: 50,
      underConstruction: none(econ_types.ConstructionProject),
      infrastructureDamage: 0.0
    ))

  # Build house fleet data
  var houseFleetData = initTable[HouseId, seq[(ShipClass, bool)]]()
  for houseId in state.houses.keys:
    houseFleetData[houseId] = @[]
    for fleet in state.getHouseFleets(houseId):
      for ship in fleet.ships:
        # TODO: Get actual ship class and crippled status
        houseFleetData[houseId].add((ShipClass.Cruiser, false))

  # Build house treasuries
  var houseTreasuries = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseTreasuries[houseId] = house.treasury

  # Call M5 maintenance engine
  let maintenanceReport = econ_engine.resolveMaintenancePhase(
    econColonies,
    houseFleetData,
    houseTreasuries
  )

  # Apply results back to game state
  for houseId, upkeep in maintenanceReport.houseUpkeep:
    state.houses[houseId].treasury = houseTreasuries[houseId]
    echo "    ", state.houses[houseId].name, ": -", upkeep, " PP maintenance"

  # Report completed projects
  for completed in maintenanceReport.completedProjects:
    echo "    Completed: ", completed.projectType

  # Check for elimination and defensive collapse
  let config = globalPrestigeConfig
  for houseId, house in state.houses:
    # Standard elimination: no colonies and no fleets
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
      continue

    # Defensive collapse: prestige < 0 for consecutive turns
    if house.prestige < 0:
      state.houses[houseId].negativePrestigeTurns += 1
      echo "    ", house.name, " negative prestige: ", house.prestige,
           " (", state.houses[houseId].negativePrestigeTurns, "/", config.collapseTurns, " turns)"

      if state.houses[houseId].negativePrestigeTurns >= config.collapseTurns:
        state.houses[houseId].eliminated = true
        events.add(GameEvent(
          eventType: geHouseEliminated,
          houseId: houseId,
          description: house.name & " has collapsed from negative prestige!",
          systemId: none(SystemId)
        ))
        echo "    ", house.name, " collapsed from negative prestige!"
    else:
      # Reset counter when prestige becomes positive
      state.houses[houseId].negativePrestigeTurns = 0

  # Check victory condition
  let victorOpt = state.checkVictoryCondition()
  if victorOpt.isSome:
    let victorId = victorOpt.get()
    state.phase = GamePhase.Completed
    echo "  *** ", state.houses[victorId].name, " has won the game! ***"
