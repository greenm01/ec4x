## EC4X C API FFI Wrapper
##
## Exports Nim game engine functions as C-callable API for parallel orchestration.
## Thread safety: AI order generation is thread-safe with copied FilteredGameState.
##                Turn resolution and zero-turn commands must be sequential.

import std/[tables, strformat, options, random, sequtils, algorithm]
import std/isolation  # For GC operations in FFI
import ../engine/[gamestate, fog_of_war, resolve, orders]
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
import ../ai/common/types  # For AIStrategy
import ../common/types/core  # For HouseId types

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
  CGame = ref object
    state: GameState
    controllers: seq[AIController]
    diagnostics: seq[DiagnosticMetrics]
    rbaConfig: rba_config.RBAConfig  # Explicit config to avoid global state
    seed: int64
    numPlayers: int
    maxTurns: int

  CFilteredState = ref object
    filtered: FilteredGameState
    rbaConfig: rba_config.RBAConfig  # Config ref for AI generation

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
    rba_config.reloadRBAConfig()  # Reload into global for consistency

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
      rbaConfig: rbaConf,  # Store config explicitly
      seed: seed,
      numPlayers: num_players.int,
      maxTurns: max_turns.int
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

    let houseId = handle.controllers[house_id].houseId
    when not defined(release):
      echo "DEBUG: create_filtered_state houseId=", houseId

    let filteredState = createFogOfWarView(handle.state, houseId)

    let filterHandle = CFilteredState(
      filtered: filteredState,
      rbaConfig: handle.rbaConfig  # Pass config through
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

    # Reload global RBAConfig for this call (FFI safety)
    # Many RBA subsystems access globalRBAConfig directly, so ensure it's valid
    rba_config.reloadRBAConfig()

    # Create fresh controller for this call (avoids state corruption)
    # Use house_id to determine strategy (same pattern as game init)
    let strategyIndex = int(house_id) mod 4
    let strategy = case strategyIndex:
      of 0: AIStrategy.Balanced
      of 1: AIStrategy.Aggressive
      of 2: AIStrategy.Turtle
      else: AIStrategy.Economic

    let houseIdStr = filterHandle.filtered.viewingHouse
    when not defined(release):
      echo &"DEBUG: generate_ai_orders houseIdStr={houseIdStr}"

    # Use explicit config from handle instead of global
    var controller = newAIController(houseIdStr, strategy,
                                     filterHandle.rbaConfig)

    # Generate orders with thread-local RNG
    var rng = initRand(rng_seed)
    let submission = generateAIOrders(controller, filterHandle.filtered,
                                      rng, @[])

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
      let metrics = collectDiagnostics(
        state = handle.state,
        houseId = controller.houseId,
        strategy = controller.strategy,
        prevMetrics = none(DiagnosticMetrics),
        orders = none(OrderPacket),
        gameId = $handle.seed,
        maxTurns = handle.maxTurns
      )
      handle.diagnostics.add(metrics)

    result = 0
  except Exception as e:
    setError(&"Failed to collect diagnostics: {e.msg}")
    result = -1

proc ec4x_write_diagnostics_db(game: pointer, db_path: cstring): cint
    {.exportc, dynlib.} =
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

    # TODO: Implement database write
    # For now, just return success
    # This will need to:
    # 1. Open SQLite database
    # 2. Create tables if needed
    # 3. Insert game metadata
    # 4. Batch insert all diagnostic rows

    result = 0
  except Exception as e:
    setError(&"Failed to write diagnostics database: {e.msg}")
    result = -1

proc ec4x_write_diagnostics_csv(game: pointer, csv_path: cstring): cint
    {.exportc, dynlib.} =
  clearError()
  if game == nil:
    setError("Game handle is NULL")
    return -1
  if csv_path == nil:
    setError("CSV path is NULL")
    return -1

  try:
    let handle = cast[CGame](game)
    let path = $csv_path

    # TODO: Implement CSV write
    # This will write all collected diagnostics to CSV

    result = 0
  except Exception as e:
    setError(&"Failed to write diagnostics CSV: {e.msg}")
    result = -1
