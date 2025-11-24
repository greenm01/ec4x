## Run Full Balance Simulation
##
## Executes a complete game simulation with AI players
## and generates balance analysis report

import std/[json, times, strformat, random, sequtils, tables, algorithm, os, strutils, options]
import game_setup, ai_controller, diagnostics
import ../../src/engine/[gamestate, resolve, orders, fog_of_war]
import ../../src/common/types/core
import ../../src/client/reports/turn_report

proc runSimulation*(numHouses: int, numTurns: int, strategies: seq[AIStrategy], seed: int64 = 42, mapRings: int = 0): JsonNode =
  ## Run a full game simulation with AI players
  ## mapRings: number of hex rings (0 = use numHouses as default)
  echo &"Starting simulation: {numHouses} houses, {numTurns} turns"
  echo &"Strategies: {strategies}"

  var rng = initRand(seed)

  # Create balanced starting game
  echo "\nInitializing game state..."
  let rings = if mapRings > 0: mapRings else: numHouses
  var game = createBalancedGame(numHouses, rings, seed)

  # Create AI controllers for each house
  var controllers: seq[AIController] = @[]
  let houseIds = toSeq(game.houses.keys)

  for i in 0..<numHouses:
    if i < houseIds.len and i < strategies.len:
      controllers.add(newAIController(houseIds[i], strategies[i]))
      echo &"  {houseIds[i]}: {strategies[i]}"

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

  # Run simulation for specified turns
  for turn in 1..numTurns:
    if turn mod 10 == 0:
      echo &"Turn {turn}/{numTurns}..."

    # Store old state for turn report generation
    let oldState = game

    # Collect orders from all AI players with fog-of-war filtering
    var ordersTable = initTable[HouseId, OrderPacket]()
    for i in 0..<controllers.len:
      var controller = controllers[i]
      # Apply fog-of-war filtering - AI only sees what it should
      let filteredView = createFogOfWarView(game, controller.houseId)
      let orders = generateAIOrders(controller, filteredView, rng)
      ordersTable[controller.houseId] = orders
      controllers[i] = controller

    # Resolve turn with actual game engine
    let turnResult = resolveTurn(game, ordersTable)
    game = turnResult.newState

    # Collect diagnostic metrics after turn resolution
    for houseId in houseIds:
      let prevOpt = if houseId in prevMetrics: some(prevMetrics[houseId]) else: none(DiagnosticMetrics)
      # Pass orders for this house to track espionage missions
      let ordersOpt = if houseId in ordersTable: some(ordersTable[houseId]) else: none(OrderPacket)
      let metrics = collectDiagnostics(game, houseId, prevOpt, ordersOpt)
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

      # Store report in controller for AI context
      controller.lastTurnReport = formattedReport

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

  echo &"\nSimulation complete! Ran {numTurns} turns"

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
      "number_of_turns": numTurns,
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

  # Parse command line arguments: turns [seed] [mapRings] [numPlayers]
  var numTurns = 100
  var seed: int64 = 42
  var mapRings = 0  # 0 = default to player count
  var numPlayers = 4  # Default to 4 players

  if paramCount() >= 1:
    numTurns = parseInt(paramStr(1))

  if paramCount() >= 2:
    seed = parseBiggestInt(paramStr(2))

  if paramCount() >= 3:
    mapRings = parseInt(paramStr(3))

  if paramCount() >= 4:
    numPlayers = parseInt(paramStr(4))

  # Create strategies for the specified number of players
  # Cycle through strategy types
  var strategies: seq[AIStrategy] = @[]
  let strategyTypes = [AIStrategy.Aggressive, AIStrategy.Economic, AIStrategy.Balanced, AIStrategy.Turtle]
  for i in 0..<numPlayers:
    strategies.add(strategyTypes[i mod strategyTypes.len])

  let report = runSimulation(numPlayers, numTurns, strategies, seed, mapRings)

  # Export report
  import std/os
  createDir("balance_results")
  writeFile("balance_results/full_simulation.json", report.pretty())

  echo "\n" & repeat("=", 70)
  echo "Report exported to: balance_results/full_simulation.json"
  echo repeat("=", 70)
