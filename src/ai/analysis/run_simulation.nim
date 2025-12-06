## Run Full Balance Simulation
##
## Executes a complete game simulation with AI players
## and generates balance analysis report

import std/[json, times, strformat, random, sequtils, tables, algorithm, os, strutils, options]
import game_setup, diagnostics, balance_test_config  # Test-specific modules
import ../../ai/rba/player as ai
import ../../ai/common/types  # For AIStrategy type
import ../../engine/[gamestate, resolve, orders, fog_of_war, setup, logger]
import ../../engine/commands/zero_turn_commands
import ../../engine/victory/[engine as victory_engine, types as victory_types]
import ../../engine/config/game_setup_config  # For victory threshold from config
import ../../common/types/core
import ../../client/reports/turn_report
import ../../engine/research/types as res_types
import ../../engine/espionage/types as esp_types

proc runSimulation*(numHouses: int, maxTurns: int, strategies: seq[AIStrategy], seed: int64 = 42, mapRings: int = 3, runUntilVictory: bool = true): JsonNode =
  ## Run a full game simulation with AI players
  ## maxTurns: maximum turn limit (safety timeout, default 200)
  ## runUntilVictory: if true, run until victory achieved (default true)
  ## mapRings: number of hex rings (must be >= 1, zero not allowed)
  let victoryModeStr = if runUntilVictory: "Run until victory" else: "Fixed turns"
  echo &"Starting simulation: {numHouses} houses, max {maxTurns} turns"
  echo &"Victory mode: {victoryModeStr}"
  echo &"Strategies: {strategies}"

  var rng = initRand(seed)

  # Create balanced starting game
  echo "\nInitializing game state..."
  # mapRings must be valid (validated by caller)
  var game = createBalancedGame(numHouses, mapRings, seed)

  # Create AI controllers for each house
  # Use the strategies parameter passed to this function (for balance testing)
  # Match houses to strategies using the starMap's player order (deterministic)
  var controllers: seq[AIController] = @[]
  var houseIds: seq[HouseId] = @[]  # Keep for diagnostic collection

  # Build a position-to-house mapping first
  var positionToHouse = initTable[int, HouseId]()
  for houseId in game.houses.keys:
    for i in 0..<numHouses:
      let homeSystemId = game.starMap.playerSystemIds[i]
      if homeSystemId in game.colonies and game.colonies[homeSystemId].owner == houseId:
        positionToHouse[i] = houseId
        break

  # Assign strategies based on position (deterministic)
  for i in 0..<numHouses:
    if i in positionToHouse:
      let houseId = positionToHouse[i]
      let strategy = if i < strategies.len: strategies[i] else: AIStrategy.Balanced
      controllers.add(newAIController(houseId, strategy))
      houseIds.add(houseId)
      echo &"  {houseId}: {strategy}"

  echo &"\nGame initialized with {game.houses.len} houses"
  echo &"Star map: {game.starMap.systems.len} systems"
  echo &"Starting simulation...\n"

  # Track game progression
  var turnSnapshots = newJArray()
  var turnReports = newJArray()  # Store all turn reports for audit trail

  # Diagnostic metrics collection
  var allDiagnostics: seq[DiagnosticMetrics] = @[]
  var prevMetrics = initTable[HouseId, DiagnosticMetrics]()

  # Create output directory for turn reports and diagnostics
  # NOTE: balance_results/ is in .gitignore and cleaned by run_balance_test.py
  createDir("balance_results/simulation_reports")
  createDir("balance_results/diagnostics")

  # Victory condition setup - load from game setup config
  # Prestige threshold from config (0 = disabled)
  let setupConfig = game_setup_config.globalGameSetupConfig

  let victoryCondition = victory_types.VictoryCondition(
    prestigeThreshold: setupConfig.victory_conditions.prestige_threshold,  # 0 = disabled
    turnLimit: maxTurns,      # Safety limit to prevent infinite games
    enableDefensiveCollapse: true
  )

  logInfo(LogCategory.lcGeneral,
          &"Victory condition: Prestige threshold={victoryCondition.prestigeThreshold}, " &
          &"Max turns={maxTurns}, Run until victory={runUntilVictory}")

  # Run simulation for specified turns
  var actualTurns = 0
  for turn in 1..maxTurns:
    actualTurns = turn
    if turn mod 10 == 0:
      echo &"Turn {turn}/{maxTurns}..."

    # Store old state for turn report generation
    let oldState = game

    # Collect orders from all AI players with fog-of-war filtering
    var ordersTable = initTable[HouseId, OrderPacket]()
    for i in 0..<controllers.len:
      var controller = controllers[i]
      # Apply fog-of-war filtering - AI only sees what it should
      let filteredView = createFogOfWarView(game, controller.houseId)

      # Generate orders using RBA (returns both zero-turn commands and order packet)
      let aiSubmission = ai.generateAIOrders(controller, filteredView, rng)

      # Execute zero-turn commands first (immediate, at friendly colonies)
      for cmd in aiSubmission.zeroTurnCommands:
        let zt = submitZeroTurnCommand(game, cmd)
        if not zt.success:
          logWarn(LogCategory.lcAI,
                  &"House {controller.houseId} zero-turn command failed: {zt.error}")
          # Note: Partial success is OK (e.g., cargo capacity limits)

      # Queue order packet for normal turn resolution
      ordersTable[controller.houseId] = aiSubmission.orderPacket
      controllers[i] = controller

    # Sync AI controller fallback routes to engine (for automatic seek-home behavior)
    for i in 0..<controllers.len:
      controllers[i].syncFallbackRoutesToEngine(game)

    # Resolve turn with actual game engine
    let turnResult = resolveTurn(game, ordersTable)
    game = turnResult.newState

    # Collect diagnostic metrics after turn resolution
    for i, houseId in houseIds:
      let prevOpt = if houseId in prevMetrics: some(prevMetrics[houseId]) else: none(DiagnosticMetrics)
      # Pass orders for this house to track espionage missions
      let ordersOpt = if houseId in ordersTable: some(ordersTable[houseId]) else: none(OrderPacket)
      # Get strategy from corresponding controller
      let strategy = controllers[i].strategy
      # Use seed as game identifier
      let gameId = $seed
      let metrics = collectDiagnostics(game, houseId, strategy, prevOpt, ordersOpt, gameId, maxTurns)
      allDiagnostics.add(metrics)
      prevMetrics[houseId] = metrics

    # Generate turn reports for each house and update AI controllers
    var turnReportData = %* {
      "turn": turn,
      "reports": {}
    }

    for i, controller in controllers.mpairs:
      # Generate turn report from this house's perspective
      let report = generateTurnReport(oldState, turnResult, controller.houseId)
      let formattedReport = formatReport(report)

      # Note: lastTurnReport removed from production AIController
      # Report context not needed for balance testing

      # Save report to JSON for analysis
      let houseName = game.houses[controller.houseId].name
      turnReportData["reports"][$controller.houseId] = %* {
        "house": houseName,
        "strategy": $controller.strategy,
        "report_text": formattedReport
      }

      # Save individual turn report to file for debugging
      if turn mod 10 == 0:
        let reportPath = &"balance_results/simulation_reports/{houseName}_turn_{turn}.txt"
        writeFile(reportPath, formattedReport)

    # Store turn reports in audit trail
    turnReports.add(turnReportData)

    # Log any significant events
    if turn mod 10 == 0:
      echo &"  Events: {turnResult.events.len} game events occurred"
      if turnResult.combatReports.len > 0:
        echo &"  Battles: {turnResult.combatReports.len} combat engagements"

    # Capture snapshot every 10 turns
    if turn mod 10 == 0 or turn == 1:
      var snapshot = %* {
        "turn": turn,
        "houses": []
      }

      for houseId, house in game.houses:
        snapshot["houses"].add(%* {
          "house_id": $houseId,
          "prestige": house.prestige,
          "treasury": house.treasury,
          "tech_level": house.techTree.levels.economicLevel,
          "colonies": game.colonies.values.toSeq.filterIt(it.owner == houseId).len,
          "fleet_count": game.fleets.values.toSeq.filterIt(it.owner == houseId).len
        })

      turnSnapshots.add(snapshot)

    # Check victory conditions after turn completes
    if runUntilVictory:
      let victoryCheck = victory_engine.checkVictoryConditions(game, victoryCondition)
      if victoryCheck.victoryOccurred:
        let status = victoryCheck.status
        logInfo(LogCategory.lcGeneral,
                &"Victory achieved at turn {turn}: {status.victoryType} by {status.victor}")
        echo &"\n*** VICTORY ACHIEVED ***"
        echo &"Turn {turn}: {status.victoryType} by {status.victor}"
        echo &"Game complete!\n"
        break  # Exit loop early - game complete

  echo &"\nSimulation complete! Ran {actualTurns} turns"

  # Write diagnostic metrics to CSV
  let diagnosticFilename = &"balance_results/diagnostics/game_{seed}.csv"
  writeDiagnosticsCSV(diagnosticFilename, allDiagnostics)

  # Calculate final rankings
  var rankings = newJArray()
  var houseData: seq[tuple[id: HouseId, prestige: int]] = @[]
  for houseId, house in game.houses:
    houseData.add((houseId, house.prestige))

  houseData.sort(proc(a, b: auto): int = cmp(b.prestige, a.prestige))

  for i, data in houseData:
    rankings.add(%* {
      "rank": i + 1,
      "house_id": $data.id,
      "final_prestige": data.prestige
    })

  # Build complete report
  result = %* {
    "metadata": {
      "test_id": "full_simulation",
      "timestamp": $now(),
      "engine_version": "0.1.0",
      "test_description": "Full game simulation with AI players",
      "includes_turn_reports": true,
      "audit_trail_enabled": true
    },
    "config": {
      "test_name": "ai_simulation",
      "number_of_houses": numHouses,
      "max_turns": maxTurns,
      "actual_turns": actualTurns,
      "run_until_victory": runUntilVictory,
      "strategies": strategies.mapIt($it),
      "seed": seed
    },
    "turn_snapshots": turnSnapshots,
    "turn_reports": turnReports,
    "outcome": {
      "victor": $houseData[0].id,
      "victory_type": "prestige",
      "final_rankings": rankings
    }
  }

  echo "\nFinal Rankings:"
  for i, data in houseData:
    echo &"  {i+1}. {data.id}: {data.prestige} prestige"

when isMainModule:
  echo repeat("=", 70)
  echo "EC4X Full Game Simulation"
  echo repeat("=", 70)
  echo ""

  # Parse command line arguments with proper flags
  var maxTurns = 200  # Increased default (was 100) - safety limit for victory-based games
  var runUntilVictory = true  # Default: run until victory achieved
  var seed: int64 = 42
  var mapRings = 3  # Default: 3 rings
  var numPlayers = 4  # Default to 4 players
  var outputFile = "balance_results/full_simulation.json"
  var logLevel = "INFO"

  # Parse flags
  var i = 1
  while i <= paramCount():
    let arg = paramStr(i)

    if arg in ["--help", "-h", "help"]:
      echo "Usage: run_simulation [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --turns, -t NUMBER        Maximum turns (safety limit, default: 200)"
      echo "  --max-turns NUMBER        Alias for --turns"
      echo "  --fixed-turns             Run exactly --turns turns (disable victory check)"
      echo "  --run-until-victory       Run until victory achieved (default)"
      echo "  --seed, -s NUMBER         Random seed for map generation (default: 42)"
      echo "  --map-rings, -m NUMBER    Number of hex rings for map (default: 3)"
      echo "  --players, -p NUMBER      Number of AI players (default: 4)"
      echo "  --output, -o FILE         Output JSON file path (default: balance_results/full_simulation.json)"
      echo "  --log-level, -l LEVEL     Logging level: DEBUG, INFO, WARN, ERROR (default: INFO)"
      echo "  --help, -h                Show this help message"
      echo ""
      echo "Examples:"
      echo "  run_simulation --turns 100 --seed 88888    # Run until victory, max 100 turns"
      echo "  run_simulation --fixed-turns -t 30 -s 123  # Force 30 turns (old behavior)"
      echo "  run_simulation --max-turns 500             # Long games, safety limit 500"
      quit(0)

    elif arg in ["--turns", "-t", "--max-turns"]:
      if i >= paramCount():
        echo "Error: --turns requires a value"
        quit(1)
      inc i
      try:
        maxTurns = parseInt(paramStr(i))
      except ValueError:
        echo "Error: Invalid turns value '", paramStr(i), "' (must be integer)"
        quit(1)

    elif arg == "--fixed-turns":
      runUntilVictory = false

    elif arg == "--run-until-victory":
      runUntilVictory = true

    elif arg in ["--seed", "-s"]:
      if i >= paramCount():
        echo "Error: --seed requires a value"
        quit(1)
      inc i
      try:
        seed = parseBiggestInt(paramStr(i))
      except ValueError:
        echo "Error: Invalid seed value '", paramStr(i), "' (must be integer)"
        quit(1)

    elif arg in ["--map-rings", "-m"]:
      if i >= paramCount():
        echo "Error: --map-rings requires a value"
        quit(1)
      inc i
      try:
        mapRings = parseInt(paramStr(i))
      except ValueError:
        echo "Error: Invalid map-rings value '", paramStr(i), "' (must be integer)"
        quit(1)

    elif arg in ["--players", "-p"]:
      if i >= paramCount():
        echo "Error: --players requires a value"
        quit(1)
      inc i
      try:
        numPlayers = parseInt(paramStr(i))
      except ValueError:
        echo "Error: Invalid players value '", paramStr(i), "' (must be integer)"
        quit(1)

    elif arg in ["--output", "-o"]:
      if i >= paramCount():
        echo "Error: --output requires a value"
        quit(1)
      inc i
      outputFile = paramStr(i)

    elif arg in ["--log-level", "-l"]:
      if i >= paramCount():
        echo "Error: --log-level requires a value"
        quit(1)
      inc i
      logLevel = paramStr(i).toUpperAscii()
      if logLevel notin ["DEBUG", "INFO", "WARN", "ERROR"]:
        echo "Error: Invalid log level '", paramStr(i), "' (must be DEBUG, INFO, WARN, or ERROR)"
        quit(1)

    else:
      echo "Error: Unknown option '", arg, "'"
      echo "Use --help to see available options"
      quit(1)

    inc i

  # Validate all parameters using engine's setup validation
  let params = GameSetupParams(
    numPlayers: numPlayers,
    numTurns: maxTurns,
    mapRings: mapRings,
    seed: seed
  )

  validateGameSetupOrQuit(params, "run_simulation")

  # Load test strategies from config (enables testing without recompilation)
  let scenario = getScenario("quick_validation")
  let balanceTestStrategies = getStrategies(scenario)

  # Create strategies for the specified number of players
  # For balance testing: rotate strategies based on seed to test all combinations
  # Each game tests the same strategies but assigned to different houses
  var strategies: seq[AIStrategy] = @[]

  # Rotate strategy assignment based on seed for balance testing
  # This ensures each house gets each strategy across multiple test runs
  let rotation = int(seed mod balanceTestStrategies.len)
  for i in 0..<numPlayers:
    let strategyIndex = (i + rotation) mod balanceTestStrategies.len
    strategies.add(balanceTestStrategies[strategyIndex])

  let report = runSimulation(numPlayers, maxTurns, strategies, seed, mapRings, runUntilVictory)

  # Export report
  let outputDir = outputFile.parentDir()
  if outputDir != "":
    createDir(outputDir)
  writeFile(outputFile, report.pretty())

  echo "\n" & repeat("=", 70)
  echo "Report exported to: ", outputFile
  echo repeat("=", 70)
