## Batch Training Data Generation
##
## Runs multiple game simulations and exports training data for LLM fine-tuning
## Output: JSON files with game state → AI decision mappings

import std/[json, times, strformat, random, sequtils, tables, os, parseopt, strutils]
import game_setup, ai_controller, training_data_export
import ../../src/engine/[gamestate, resolve, orders]
import ../../src/client/reports/turn_report
import ../../src/common/types/core

proc runGameForTraining*(gameId: int, numHouses: int, numTurns: int,
                         strategies: seq[AIStrategy], seed: int64): seq[TrainingExample] =
  ## Run a single game and collect training examples
  result = @[]

  echo &"[Game {gameId}] Starting: {numHouses} houses, {numTurns} turns, seed {seed}"

  var rng = initRand(seed)
  var game: GameState
  try:
    game = createBalancedGame(numHouses, numHouses, seed)
  except CatchableError as e:
    echo &"[Game {gameId}] ERROR in game setup: {e.msg}"
    echo &"[Game {gameId}] Exception: {e.name}"
    return @[]  # Return empty on setup failure

  # Create AI controllers
  var controllers: seq[AIController] = @[]
  let houseIds = toSeq(game.houses.keys)

  for i in 0..<numHouses:
    if i < houseIds.len and i < strategies.len:
      controllers.add(newAIController(houseIds[i], strategies[i]))

  # Run simulation and collect training data
  for turn in 1..numTurns:
    if turn mod 20 == 0:
      echo &"[Game {gameId}] Turn {turn}/{numTurns}... ({result.len} examples)"

    # Collect orders from all AI players
    var ordersTable = initTable[HouseId, OrderPacket]()
    for controller in controllers:
      try:
        let orders = generateAIOrders(controller, game, rng)
        ordersTable[controller.houseId] = orders

        # Create training example from this decision
        let example = createTrainingExample(turn, game, controller, orders)
        result.add(example)
      except CatchableError as e:
        echo &"[Game {gameId}] ERROR generating AI orders on turn {turn}: {e.msg}"
        return result  # Return examples collected so far

    # Resolve turn
    try:
      let turnResult = resolveTurn(game, ordersTable)
      game = turnResult.newState

      # Update AI context with turn reports (for future enhancement)
      for i, controller in controllers.mpairs:
        let report = generateTurnReport(game, turnResult, controller.houseId)
        controller.lastTurnReport = formatReport(report)
    except CatchableError as e:
      echo &"[Game {gameId}] ERROR resolving turn {turn}: {e.msg}"
      return result  # Return examples collected so far

  echo &"[Game {gameId}] Complete! Collected {result.len} training examples"

proc generateTrainingDataset*(numGames: int, gamesPerBatch: int = 10,
                              outputDir: string = "ai_training/data") =
  ## Generate complete training dataset
  echo repeat("=", 70)
  echo "EC4X Training Data Generation"
  echo repeat("=", 70)
  echo ""
  echo &"Configuration:"
  echo &"  Total games: {numGames}"
  echo &"  Batch size: {gamesPerBatch}"
  echo &"  Output dir: {outputDir}"
  echo ""

  # Create output directory
  createDir(outputDir)
  createDir(outputDir & "/batches")

  var allExamples: seq[TrainingExample] = @[]
  var gameCount = 0
  var batchNum = 1

  # Strategy configurations to test
  let strategyConfigs = @[
    @[AIStrategy.Aggressive, AIStrategy.Economic, AIStrategy.Balanced, AIStrategy.Turtle],
    @[AIStrategy.Diplomatic, AIStrategy.Espionage, AIStrategy.Balanced, AIStrategy.Economic],
    @[AIStrategy.Aggressive, AIStrategy.Aggressive, AIStrategy.Economic, AIStrategy.Diplomatic],
    @[AIStrategy.Economic, AIStrategy.Economic, AIStrategy.Balanced, AIStrategy.Balanced]
  ]

  let startTime = now()

  while gameCount < numGames:
    echo ""
    echo &"=== Batch {batchNum} ==="

    var batchExamples: seq[TrainingExample] = @[]
    let batchStart = gameCount
    let batchEnd = min(gameCount + gamesPerBatch, numGames)

    for gameId in batchStart..<batchEnd:
      # Vary game parameters
      let numHouses = 4  # Always 4 houses for now
      let numTurns = if gameId mod 3 == 0: 50 elif gameId mod 3 == 1: 100 else: 150
      let strategies = strategyConfigs[gameId mod strategyConfigs.len]
      let seed = 42 + gameId * 1000  # Deterministic but varied

      try:
        let examples = runGameForTraining(gameId + 1, numHouses, numTurns, strategies, seed)
        batchExamples.add(examples)
      except Exception as e:
        echo &"[Game {gameId + 1}] ERROR: {e.msg}"
        echo "Continuing with next game..."
      finally:
        gameCount += 1  # Always increment, even on failure

    # Save batch to file
    echo ""
    echo &"Saving batch {batchNum} ({batchExamples.len} examples)..."

    var batchJson = newJArray()
    for example in batchExamples:
      batchJson.add(exportTrainingExample(example))

    let batchPath = outputDir & &"/batches/batch_{batchNum:03d}.json"
    writeFile(batchPath, batchJson.pretty())
    echo &"  Saved: {batchPath}"

    allExamples.add(batchExamples)
    batchNum += 1

    # Progress report
    let elapsed = (now() - startTime).inSeconds
    let gamesPerSec = float(gameCount) / float(elapsed)
    let remaining = int(float(numGames - gameCount) / gamesPerSec)
    echo &"  Progress: {gameCount}/{numGames} games ({allExamples.len} examples)"
    echo &"  Speed: {gamesPerSec:.2f} games/sec"
    echo &"  Est. remaining: {remaining} seconds"

  # Save combined dataset
  echo ""
  echo "Saving combined dataset..."

  var combinedJson = %* {
    "metadata": {
      "generated": $now(),
      "num_games": gameCount,
      "num_examples": allExamples.len,
      "engine_version": "0.1.0",
      "data_version": "v1"
    },
    "examples": newJArray()
  }

  for example in allExamples:
    combinedJson["examples"].add(exportTrainingExample(example))

  let combinedPath = outputDir & "/training_data_combined.json"
  writeFile(combinedPath, combinedJson.pretty())
  echo &"  Saved: {combinedPath}"

  # Statistics
  let elapsed = (now() - startTime).inSeconds
  let fileSize = getFileSize(combinedPath)

  echo ""
  echo repeat("=", 70)
  echo "Training Data Generation Complete!"
  echo repeat("=", 70)
  echo &"  Games: {gameCount}"
  echo &"  Training examples: {allExamples.len}"
  echo &"  Time: {elapsed} seconds ({float(elapsed) / 60.0:.1f} minutes)"
  echo &"  Output: {combinedPath}"
  echo &"  Size: {fileSize div 1024 div 1024} MB"
  echo ""

when isMainModule:
  # Parse command line arguments
  import std/parseopt

  var numGames = 10  # Default: small test batch
  var batchSize = 10
  var outputDir = "ai_training/data"

  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "games", "g":
        if p.val.len > 0:
          numGames = parseInt(p.val)
      of "batch", "b":
        if p.val.len > 0:
          batchSize = parseInt(p.val)
      of "output", "o":
        if p.val.len > 0:
          outputDir = p.val
      of "help", "h":
        echo "Usage: generate_training_data [options]"
        echo ""
        echo "Options:"
        echo "  -g, --games N     Number of games to generate (default: 10)"
        echo "  -b, --batch N     Games per batch (default: 10)"
        echo "  -o, --output DIR  Output directory (default: ai_training/data)"
        echo "  -h, --help        Show this help"
        echo ""
        echo "Examples:"
        echo "  # Generate small test set"
        echo "  ./generate_training_data --games 10"
        echo ""
        echo "  # Generate full training set"
        echo "  ./generate_training_data --games 200 --batch 20"
        quit(0)
      else:
        echo &"Unknown option: {p.key}"
        quit(1)
    of cmdArgument:
      echo &"Unexpected argument: {p.key}"
      quit(1)

  # Run generation
  generateTrainingDataset(numGames, batchSize, outputDir)
