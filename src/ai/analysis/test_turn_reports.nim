## Test Turn Report Generation
##
## Demonstrates the client-side turn report formatter
## by generating sample reports from simulation data

import std/[json, times, strformat, random, sequtils, tables, algorithm, os, options]
import game_setup
# TODO: ai_controller module doesn't exist yet - AI logic needs to be implemented
import ../../src/engine/[gamestate, resolve, orders]
import ../../src/engine/espionage/types as esp_types
import ../../src/engine/research/types as res_types
import ../../src/common/types/[core, tech]
import ../../src/client/reports/turn_report

# Minimal AI stubs for compilation (TODO: implement properly)
type
  AIStrategy* {.pure.} = enum
    Aggressive, Economic, Balanced, Turtle, Espionage, Diplomatic, Expansionist

  AIController* = object
    houseId*: HouseId
    strategy*: AIStrategy

proc newAIController*(houseId: HouseId, strategy: AIStrategy): AIController =
  AIController(houseId: houseId, strategy: strategy)

proc generateAIOrders*(controller: AIController, state: GameState, rng: var Rand): OrderPacket =
  ## Stub AI - returns empty orders
  OrderPacket(
    houseId: controller.houseId,
    turn: state.turn,
    treasury: if state.houses.hasKey(controller.houseId): state.houses[controller.houseId].treasury else: 0,
    fleetOrders: @[],
    buildOrders: @[],
    researchAllocation: res_types.ResearchAllocation(
      economic: 0,
      science: 0,
      technology: initTable[TechField, int]()
    ),
    diplomaticActions: @[],
    populationTransfers: @[],
    terraformOrders: @[],
    espionageAction: none(esp_types.EspionageAttempt),
    ebpInvestment: 0,
    cipInvestment: 0
  )

proc testTurnReports*() =
  ## Run a short simulation and generate turn reports for each house
  echo repeat("=", 70)
  echo "EC4X Turn Report Generation Test"
  echo repeat("=", 70)
  echo ""

  var rng = initRand(42)

  # Create balanced starting game (4 houses)
  echo "Initializing game state..."
  var game = createBalancedGame(4, 4, 42)

  # Create AI controllers
  let strategies = @[
    AIStrategy.Aggressive,
    AIStrategy.Economic,
    AIStrategy.Balanced,
    AIStrategy.Turtle
  ]

  var controllers: seq[AIController] = @[]
  let houseIds = toSeq(game.houses.keys)

  for i in 0..<4:
    if i < houseIds.len and i < strategies.len:
      controllers.add(newAIController(houseIds[i], strategies[i]))
      echo &"  {houseIds[i]}: {strategies[i]}"

  echo &"\nGame initialized with {game.houses.len} houses"
  echo &"Running 20 turns with turn reports...\n"

  # Run simulation for 20 turns, generating reports
  for turn in 1..20:
    # Store old state for report generation
    let oldState = game

    # Collect orders from all AI players
    var ordersTable = initTable[HouseId, OrderPacket]()
    for controller in controllers:
      let orders = generateAIOrders(controller, game, rng)
      ordersTable[controller.houseId] = orders

    # Resolve turn with actual game engine
    let turnResult = resolveTurn(game, ordersTable)
    game = turnResult.newState

    # Generate and display turn reports for each house
    if turn mod 5 == 0:
      echo &"\n{repeat(\"=\", 70)}"
      echo &"TURN {turn} REPORTS"
      echo repeat("=", 70)

      # Show combat summary if any battles occurred
      if turnResult.combatReports.len > 0:
        echo &"\n{turnResult.combatReports.len} battle(s) occurred this turn\n"

      # Generate report for first house (as example)
      let exampleHouseId = houseIds[0]
      let houseName = game.houses[exampleHouseId].name

      echo &"\nGenerating report for {houseName} (perspective: {exampleHouseId})...\n"

      let report = generateTurnReport(oldState, turnResult, exampleHouseId)
      let formattedReport = formatReport(report)

      echo formattedReport

      # Save to file
      createDir("balance_results/turn_reports")
      let filename = &"balance_results/turn_reports/{houseName}_turn_{turn}.txt"
      writeFile(filename, formattedReport)
      echo &"Report saved to: {filename}\n"

  echo "\n" & repeat("=", 70)
  echo "Turn Report Test Complete"
  echo repeat("=", 70)

when isMainModule:
  testTurnReports()
