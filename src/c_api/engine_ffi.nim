## EC4X C API FFI Wrapper
##
## Exports Nim game engine functions as C-callable API for parallel orchestration.
## Thread safety: AI order generation is thread-safe with copied FilteredGameState.
##                Turn resolution and zero-turn commands must be sequential.

import std/[tables, strformat, options, random, sequtils, algorithm, strutils]
import std/isolation  # For GC operations in FFI
import ../engine/state/game_state
import ../engine/[fog_of_war, resolve, orders]
import ../engine/commands/zero_turn_commands
import ../engine/config/[
  starmap_config, tech_config, prestige_config,
  game_setup_config, gameplay_config, ships_config,
  economy_config, combat_config, diplomacy_config,
  facilities_config, construction_config, military_config,
  espionage_config, population_config, standing_orders_config,
  ground_units_config
]
import ../ai/rba/[player, controller_types, orders as ai_orders, config as rba_config]
import ../ai/analysis/[game_setup, diagnostics]
import ../ai/analysis/diagnostics/csv_writer
import ../engine/persistence/[types as db_types, schema, writer]
import ../ai/common/types  # For AIStrategy
import ../common/types/core  # For HouseId types
import ../common/types/units  # For ShipClass
import db_connector/db_sqlite

# Thread-local error storage for C error handling
var lastError {.threadvar.}: string

# Library initialization for threading support
proc NimMain() {.importc.}

# Initialize Nim runtime when library loads (main thread)
proc ec4x_init_runtime(): cint {.exportc, dynlib.} =
  {.gcsafe.}:
    try:
      NimMain()
      result = 0
    except:
      result = -1

# Opaque handle wrappers
type
  FleetSnapshot = object
    turn: int
    fleetId: string
    houseId: string
    locationSystem: int
    orderType: string
    orderTarget: int
    hasArrived: int
    shipsTotal: int
    etacCount: int
    scoutCount: int
    combatShips: int
    transportCount: int
    idleTurnsCombat: int
    idleTurnsScout: int
    idleTurnsEtac: int
    idleTurnsTransport: int

  FleetIdleness = object
    ## Track idle turn count for each ship type in fleet
    idleTurnsCombat: int
    idleTurnsScout: int
    idleTurnsEtac: int
    idleTurnsTransport: int
    lastOrderType: string

  CGame = ref object
    state: GameState
    controllers: seq[AIController]
    diagnostics: seq[DiagnosticMetrics]
    fleetSnapshots: seq[FleetSnapshot]  # Fleet tracking data (collected in memory)
    fleetIdleness: Table[FleetId, FleetIdleness]  # Track idle turns per fleet
    rbaConfig: rba_config.RBAConfig  # Explicit config to avoid global state
    seed: int64
    numPlayers: int
    maxTurns: int
    mapRings: int

  CFilteredState = ref object
    filtered: FilteredGameState
    rbaConfig: rba_config.RBAConfig  # Config ref for AI generation
    gameHandle: CGame  # Game handle for accessing persistent controllers
    houseIdx: int  # Index into controllers seq

  COrders = ref object
    submission: AIOrderSubmission

# =============================================================================
# Error Handling
# =============================================================================

proc setError(msg: string) =
  lastError = msg

proc clearError() =
  lastError = ""

proc ec4x_get_last_error(): cstring {.exportc, dynlib.} =
  if lastError.len > 0:
    result = cstring(lastError)
  else:
    result = nil

# =============================================================================
# Game Lifecycle
# =============================================================================

proc ec4x_init_game(num_players: cint, seed: int64, map_rings: cint,
                    max_turns: cint): pointer {.exportc, dynlib.} =
  clearError()
  try:
    # Reload all configs in shared library context (critical for FFI)
    reloadStarmapConfig()
    reloadTechConfig()
    reloadPrestigeConfig()
    reloadGameSetupConfig()
    reloadGameplayConfig()
    reloadShipsConfig()
    reloadEconomyConfig()
    reloadCombatConfig()
    reloadDiplomacyConfig()
    reloadFacilitiesConfig()
    reloadConstructionConfig()
    reloadMilitaryConfig()
    reloadEspionageConfig()
    reloadPopulationConfig()
    reloadStandingOrdersConfig()
    reloadGroundUnitsConfig()
    # RBA config loaded per-controller (no global state) - race condition eliminated

    # Validate parameters
    if num_players < 2 or num_players > 12:
      setError("Number of players must be 2-12")
      return nil
    if map_rings < 1 or map_rings > 5:
      setError("Map rings must be 1-5")
      return nil

    # Initialize game state
    let game = createBalancedGame(num_players.int, map_rings.int, seed)

    # Load RBAConfig explicitly to avoid global state corruption in FFI
    let rbaConf = rba_config.loadRBAConfig()

    # Create AI controllers with default strategies
    # CRITICAL: Use sorted house IDs for deterministic ordering
    var controllers: seq[AIController] = @[]
    var houseIds = toSeq(game.houses.keys)
    houseIds.sort()  # Alphabetical sort for stable ordering
    for i, houseId in houseIds:
      let strategy = case i mod 4:
        of 0: AIStrategy.Balanced
        of 1: AIStrategy.Aggressive
        of 2: AIStrategy.Turtle
        else: AIStrategy.Economic
      controllers.add(newAIController(houseId, strategy, rbaConf))

    # Create game handle with explicit config
    let handle = CGame(
      state: game,
      controllers: controllers,
      diagnostics: @[],
      fleetSnapshots: @[],
      fleetIdleness: initTable[FleetId, FleetIdleness](),
      rbaConfig: rbaConf,  # Store config explicitly
      seed: seed,
      numPlayers: num_players.int,
      maxTurns: max_turns.int,
      mapRings: map_rings.int
    )

    when not defined(release):
      echo "DEBUG: Game handle created successfully"

    GC_ref(handle)  # Prevent GC from collecting this ref object
    result = cast[pointer](handle)

    when not defined(release):
      echo "DEBUG: Returning game handle pointer"
  except Exception as e:
    setError(&"Failed to initialize game: {e.msg}")
    result = nil

proc ec4x_destroy_game(game: pointer) {.exportc, dynlib.} =
  if game != nil:
    try:
      let handle = cast[CGame](game)
      GC_unref(handle)  # Release GC reference
    except:
      discard

# =============================================================================
# Fog-of-War State (for AI)
# =============================================================================

proc ec4x_create_filtered_state(game: pointer, house_id: cint): pointer
    {.exportc, dynlib.} =
  clearError()
  if game == nil:
    setError("Game handle is NULL")
    return nil

  try:
    let handle = cast[CGame](game)
    when not defined(release):
      echo &"DEBUG: create_filtered_state handle.controllers.len={handle.controllers.len}"

    if house_id < 0 or house_id >= handle.controllers.len:
      setError(&"Invalid house_id: {house_id}")
      return nil

    when not defined(release):
      echo "DEBUG: create_filtered_state house_id=", house_id
      echo "DEBUG: create_filtered_state controllers.len=", handle.controllers.len

    let houseIdx = int(house_id)  # Convert cint to int for indexing
    let houseId = handle.controllers[houseIdx].houseId
    when not defined(release):
      echo "DEBUG: create_filtered_state houseId=", houseId

    let filteredState = createFogOfWarView(handle.state, houseId)

    let filterHandle = CFilteredState(
      filtered: filteredState,
      rbaConfig: handle.rbaConfig,  # Pass config through
      gameHandle: handle,  # Store game handle for controller access
      houseIdx: houseIdx  # Store house index for controller lookup
    )
    GC_ref(filterHandle)  # Prevent GC from collecting this ref object
    result = cast[pointer](filterHandle)
  except Exception as e:
    setError(&"Failed to create filtered state: {e.msg}")
    result = nil

proc ec4x_destroy_filtered_state(state: pointer) {.exportc, dynlib.} =
  if state != nil:
    try:
      let handle = cast[CFilteredState](state)
      GC_unref(handle)  # Release GC reference
    except:
      discard

# =============================================================================
# AI Operations (Thread-Safe with Filtered State)
# =============================================================================

proc ec4x_generate_ai_orders(filtered_state: pointer, house_id: cint,
                             rng_seed: int64): pointer {.exportc, dynlib.} =
  clearError()
  if filtered_state == nil:
    setError("Filtered state handle is NULL")
    return nil

  try:
    let filterHandle = cast[CFilteredState](filtered_state)

    # REVERT: Create fresh controller each call (old working approach)
    # TODO: Implement persistent tracking via different mechanism (GameState?)
    let houseId = filterHandle.filtered.viewingHouse
    let strategyIndex = filterHandle.houseIdx mod 4
    let strategy = case strategyIndex:
      of 0: AIStrategy.Balanced
      of 1: AIStrategy.Aggressive
      of 2: AIStrategy.Turtle
      else: AIStrategy.Economic

    var controller = newAIController(houseId, strategy, filterHandle.rbaConfig)

    # Generate orders with thread-local RNG
    var rng = initRand(rng_seed)
    let submission = generateAIOrders(controller, filterHandle.filtered, rng, @[])

    let ordersHandle = COrders(submission: submission)
    GC_ref(ordersHandle)  # Prevent GC from collecting this ref object
    result = cast[pointer](ordersHandle)
  except Exception as e:
    setError(&"Failed to generate AI orders: {e.msg}")
    result = nil

proc ec4x_destroy_orders(orders: pointer) {.exportc, dynlib.} =
  if orders != nil:
    try:
      let handle = cast[COrders](orders)
      GC_unref(handle)  # Release GC reference
    except:
      discard

# =============================================================================
# Turn Resolution (NOT Thread-Safe - Sequential Only)
# =============================================================================

proc ec4x_execute_zero_turn_commands(game: pointer, orders: pointer): cint
    {.exportc, dynlib.} =
  clearError()
  if game == nil:
    setError("Game handle is NULL")
    return -1
  if orders == nil:
    setError("Orders handle is NULL")
    return -1

  try:
    var gameHandle = cast[CGame](game)
    let ordersHandle = cast[COrders](orders)

    # Execute zero-turn commands
    var events: seq[GameEvent] = @[]
    for cmd in ordersHandle.submission.zeroTurnCommands:
      let result = submitZeroTurnCommand(gameHandle.state, cmd, events)
      if not result.success:
        # Log warning but continue (don't fail entire turn)
        discard

    result = 0
  except Exception as e:
    setError(&"Failed to execute zero-turn commands: {e.msg}")
    result = -1

proc ec4x_resolve_turn(game: pointer, orders: ptr pointer,
                      num_orders: cint): cint {.exportc, dynlib.} =
  clearError()
  if game == nil:
    setError("Game handle is NULL")
    return -1
  if orders == nil:
    setError("Orders array is NULL")
    return -1

  try:
    var gameHandle = cast[CGame](game)

    # Build orders table from array of order handles
    var ordersTable = initTable[HouseId, OrderPacket]()
    let ordersArray = cast[ptr UncheckedArray[pointer]](orders)
    for i in 0..<num_orders:
      let ordersHandle = cast[COrders](ordersArray[i])
      let houseId = gameHandle.controllers[i].houseId
      ordersTable[houseId] = ordersHandle.submission.orderPacket

    # Sync fallback routes to engine
    for controller in gameHandle.controllers:
      controller.syncFallbackRoutesToEngine(gameHandle.state)

    # Resolve turn
    let turnResult = resolveTurn(gameHandle.state, ordersTable)
    gameHandle.state = turnResult.newState

    result = 0
  except Exception as e:
    setError(&"Failed to resolve turn: {e.msg}")
    result = -1

# =============================================================================
# Game State Queries
# =============================================================================

proc ec4x_get_turn(game: pointer): cint {.exportc, dynlib.} =
  if game == nil:
    return 0
  try:
    let handle = cast[CGame](game)
    result = cint(handle.state.turn)
  except:
    result = 0

proc ec4x_check_victory(game: pointer): bool {.exportc, dynlib.} =
  if game == nil:
    return false
  try:
    let handle = cast[CGame](game)
    # Check if any house is eliminated or turn limit reached
    var activeHouses = 0
    for houseId, house in handle.state.houses:
      if not house.eliminated:
        inc activeHouses

    result = (activeHouses <= 1) or (handle.state.turn >= handle.maxTurns)
  except:
    result = false

proc ec4x_get_victor(game: pointer): cint {.exportc, dynlib.} =
  if game == nil:
    return -1
  try:
    let handle = cast[CGame](game)

    # Find house with highest prestige
    var maxPrestige = 0
    var victorId = -1
    for i, controller in handle.controllers:
      let house = handle.state.houses.getOrDefault(controller.houseId)
      if not house.eliminated and house.prestige > maxPrestige:
        maxPrestige = house.prestige
        victorId = i

    result = cint(victorId)
  except:
    result = -1

# =============================================================================
# Diagnostics & Database
# =============================================================================

proc ec4x_collect_diagnostics(game: pointer, turn: cint): cint
    {.exportc, dynlib.} =
  clearError()
  if game == nil:
    setError("Game handle is NULL")
    return -1

  try:
    let handle = cast[CGame](game)

    # Collect diagnostics for all houses
    for controller in handle.controllers:
      # Find previous turn's metrics for this house (for delta calculation)
      var prevMetrics = none(DiagnosticMetrics)
      if handle.diagnostics.len > 0:
        # Find the most recent diagnostic entry for this house
        for i in countdown(handle.diagnostics.high, 0):
          if handle.diagnostics[i].houseId == controller.houseId and
             handle.diagnostics[i].turn == turn - 1:
            prevMetrics = some(handle.diagnostics[i])
            break

      let metrics = collectDiagnostics(
        state = handle.state,
        houseId = controller.houseId,
        strategy = controller.strategy,
        prevMetrics = prevMetrics,
        orders = none(OrderPacket),
        gameId = $handle.seed,
        maxTurns = handle.maxTurns
      )
      handle.diagnostics.add(metrics)

    result = 0
  except Exception as e:
    setError(&"Failed to collect diagnostics: {e.msg}")
    result = -1

proc ec4x_get_diagnostics_count(game: pointer): cint {.exportc, dynlib.} =
  ## Get the number of diagnostic records collected
  if game == nil:
    return 0

  let handle = cast[CGame](game)
  return cint(handle.diagnostics.len)

proc ec4x_get_diagnostic_field_int(game: pointer, index: cint,
                                    field_name: cstring): int64 {.exportc, dynlib.} =
  ## Get an integer field from a diagnostic record
  ## Returns 0 if field not found or invalid
  if game == nil or index < 0:
    return 0

  let handle = cast[CGame](game)
  if index >= handle.diagnostics.len:
    return 0

  # TODO: Implement field extraction by name
  # For now, stub returns 0
  return 0

proc ec4x_get_diagnostic_field_str(game: pointer, index: cint,
                                    field_name: cstring): cstring {.exportc, dynlib.} =
  ## Get a string field from a diagnostic record
  ## Returns NULL if field not found or invalid
  if game == nil or index < 0:
    return nil

  let handle = cast[CGame](game)
  if index >= handle.diagnostics.len:
    return nil

  # TODO: Implement field extraction by name
  # For now, stub returns NULL
  return nil

proc ec4x_collect_fleet_snapshots(game: pointer, turn: cint): cint
    {.exportc, dynlib.} =
  ## Collect fleet snapshots for current turn (stored in memory)
  ## Call this every turn to build up fleet tracking data
  clearError()
  if game == nil:
    setError("Game handle is NULL")
    return -1

  try:
    let handle = cast[CGame](game)

    # Collect fleet snapshots for this turn
    for fleetId, fleet in handle.state.fleets:
      # Count ship types
      var totalSquadronShips = 0
      var scoutCount = 0
      var etacCount = 0
      var transportCount = 0

      # Count all squadron ships (combat + scouts)
      for squadron in fleet.squadrons:
        totalSquadronShips += 1 + squadron.ships.len  # flagship + escorts

        # Count scouts separately
        if squadron.flagship.shipClass == ShipClass.Scout:
          scoutCount += 1
        for ship in squadron.ships:
          if ship.shipClass == ShipClass.Scout:
            scoutCount += 1

      # Count Expansion/Auxiliary squadrons (ETACs and Transports)
      var expansionShips = 0
      for squadron in fleet.squadrons:
        if squadron.squadronType == SquadronType.Expansion:
          # ETAC squadron - count flagship + escorts
          let shipCount = 1 + squadron.ships.len
          etacCount += shipCount
          expansionShips += shipCount
        elif squadron.squadronType == SquadronType.Auxiliary:
          # TroopTransport squadron - count flagship + escorts
          let shipCount = 1 + squadron.ships.len
          transportCount += shipCount
          expansionShips += shipCount

      # Combat ships = all squadron ships EXCEPT scouts and expansion/auxiliary
      let combatShips = totalSquadronShips - scoutCount - expansionShips

      # Get order info
      var orderType = "None"
      var orderTarget = 0  # 0 = no target (matches run_simulation.nim convention)
      var hasArrived = 1
      if fleetId in handle.state.fleetOrders:
        let order = handle.state.fleetOrders[fleetId]
        orderType = $order.orderType
        if order.targetSystem.isSome:
          orderTarget = int(order.targetSystem.get())
          hasArrived = if fleet.location == SystemId(orderTarget): 1 else: 0

      # Calculate idle turns per ship type
      # If fleet has no orders, all ship types in it are idle
      var idleTurnsCombat = 0
      var idleTurnsScout = 0
      var idleTurnsEtac = 0
      var idleTurnsTransport = 0

      if fleetId in handle.fleetIdleness:
        let prevState = handle.fleetIdleness[fleetId]
        if orderType == "None":
          # Fleet is idle this turn - all ship types idle
          if prevState.lastOrderType == "None":
            # Was idle last turn too - increment all
            if combatShips > 0:
              idleTurnsCombat = prevState.idleTurnsCombat + 1
            if scoutCount > 0:
              idleTurnsScout = prevState.idleTurnsScout + 1
            if etacCount > 0:
              idleTurnsEtac = prevState.idleTurnsEtac + 1
            if transportCount > 0:
              idleTurnsTransport = prevState.idleTurnsTransport + 1
          else:
            # Just became idle - first idle turn
            if combatShips > 0:
              idleTurnsCombat = 1
            if scoutCount > 0:
              idleTurnsScout = 1
            if etacCount > 0:
              idleTurnsEtac = 1
            if transportCount > 0:
              idleTurnsTransport = 1
        # else: has orders this turn, all idleTurns stay 0
      else:
        # First time seeing this fleet
        if orderType == "None":
          # New fleet with no orders - count as first idle turn
          if combatShips > 0:
            idleTurnsCombat = 1
          if scoutCount > 0:
            idleTurnsScout = 1
          if etacCount > 0:
            idleTurnsEtac = 1
          if transportCount > 0:
            idleTurnsTransport = 1

      # Update idle tracker for next turn
      handle.fleetIdleness[fleetId] = FleetIdleness(
        idleTurnsCombat: idleTurnsCombat,
        idleTurnsScout: idleTurnsScout,
        idleTurnsEtac: idleTurnsEtac,
        idleTurnsTransport: idleTurnsTransport,
        lastOrderType: orderType
      )

      # Store snapshot in memory
      handle.fleetSnapshots.add(FleetSnapshot(
        turn: turn,
        fleetId: $fleetId,
        houseId: $fleet.owner,
        locationSystem: int(fleet.location),
        orderType: orderType,
        orderTarget: orderTarget,
        hasArrived: hasArrived,
        shipsTotal: totalSquadronShips,  # All ships now in squadrons
        etacCount: etacCount,
        scoutCount: scoutCount,
        combatShips: combatShips,
        transportCount: transportCount,
        idleTurnsCombat: idleTurnsCombat,
        idleTurnsScout: idleTurnsScout,
        idleTurnsEtac: idleTurnsEtac,
        idleTurnsTransport: idleTurnsTransport
      ))

    result = 0
  except Exception as e:
    setError(&"Failed to collect fleet snapshots: {e.msg}")
    result = -1

proc ec4x_write_diagnostics_db(game: pointer, db_path: cstring): cint
    {.exportc, dynlib.} =
  ## Write all collected diagnostics and fleet snapshots to SQLite database
  ## Writes in batch at end of simulation for performance
  clearError()
  if game == nil:
    setError("Game handle is NULL")
    return -1
  if db_path == nil:
    setError("Database path is NULL")
    return -1

  try:
    let handle = cast[CGame](game)
    let path = $db_path

    # Open database and initialize schema
    let db = open(path, "", "", "")
    defer: db.close()

    if not initializeDatabase(db):
      setError("Failed to initialize database schema")
      return -1

    # Insert game metadata
    let gameId = handle.seed  # Use seed as game_id

    # Build strategies list for all players
    var strategies: seq[string] = @[]
    for i in 0..<handle.numPlayers:
      strategies.add("RBA")  # All AI players use RBA strategy

    discard insertGame(db, gameId, handle.numPlayers, handle.maxTurns,
                      handle.mapRings, strategies)

    # Write diagnostics
    for metrics in handle.diagnostics:
      insertDiagnosticRow(db, gameId, metrics)

    # Write fleet snapshots
    for snapshot in handle.fleetSnapshots:
      insertFleetSnapshot(db, gameId, snapshot.turn, snapshot.fleetId,
                         snapshot.houseId, snapshot.locationSystem,
                         snapshot.orderType, snapshot.orderTarget,
                         snapshot.hasArrived == 1, snapshot.shipsTotal,
                         snapshot.etacCount, snapshot.scoutCount,
                         snapshot.combatShips, snapshot.transportCount,
                         snapshot.idleTurnsCombat, snapshot.idleTurnsScout,
                         snapshot.idleTurnsEtac, snapshot.idleTurnsTransport)

    result = 0
  except Exception as e:
    setError(&"Failed to write diagnostics database: {e.msg}")
    result = -1

proc ec4x_write_diagnostics_csv(game: pointer, csv_path: cstring): cint
    {.exportc, dynlib.} =
  ## Write diagnostics to CSV
  clearError()
  if game == nil:
    setError("Game handle is NULL")
    return -1
  if csv_path == nil:
    setError("CSV path is NULL")
    return -1

  try:
    let handle = cast[CGame](game)
    if handle.diagnostics.len == 0:
      return 0  # No diagnostics to write

    let path = $csv_path
    writeDiagnosticsCSV(path, handle.diagnostics)
    result = 0
  except Exception as e:
    setError(&"Failed to write diagnostics CSV: {e.msg}")
    result = -1
