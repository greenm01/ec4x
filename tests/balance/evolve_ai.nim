## Evolution Runner for EC4X AI Personalities
##
## Runs genetic algorithm to evolve AI personalities and find balance issues
## Usage: ./evolve_ai [--generations N] [--population N]

import std/[parseopt, strformat, strutils, tables, json, times, os, sequtils, sugar, algorithm, random]
import genetic_ai
import ai_controller
import game_setup
import ../../src/engine/[gamestate, resolve, orders]
import ../../src/common/types/core

# ============================================================================
# Tournament Simulation
# ============================================================================

proc runTournamentGame(genomes: array[4, AIGenome], turns: int, seed: int64): Table[int, tuple[won: bool, colonies: int, military: int]] =
  ## Run a single 4-player game with given AI genomes
  ## Returns performance stats for each genome

  var rng = initRand(seed)

  # Create balanced starting game
  var game = createBalancedGame(4, 4, seed)

  # Create AI controllers with evolved personalities
  let houseIds = toSeq(game.houses.keys)
  var controllers: seq[AIController] = @[]
  for i in 0 ..< 4:
    let controller = newAIControllerWithPersonality(houseIds[i], genomes[i].genes)
    controllers.add(controller)

  # Run simulation for N turns
  for turn in 1 .. turns:
    # Collect orders from all AI players
    var ordersTable = initTable[HouseId, OrderPacket]()
    for controller in controllers:
      let orders = generateAIOrders(controller, game, rng)
      ordersTable[controller.houseId] = orders

    # Resolve turn with actual game engine
    let turnResult = resolveTurn(game, ordersTable)
    game = turnResult.newState

  # Calculate results
  result = initTable[int, tuple[won: bool, colonies: int, military: int]]()

  # Find winner (most prestige + colony count)
  var scores: seq[tuple[id: int, score: float]] = @[]
  for i in 0 ..< 4:
    let house = game.houses[houseIds[i]]
    let colonyCount = game.colonies.values.toSeq.filterIt(it.owner == houseIds[i]).len
    # Count military fleets as proxy for military strength
    let militaryScore = game.fleets.values.toSeq.filterIt(it.owner == houseIds[i]).len
    let score = house.prestige.float * 10.0 + colonyCount.float * 100.0 + militaryScore.float
    scores.add((id: i, score: score))

  # Sort by score
  scores.sort(proc(a, b: auto): int = cmp(b.score, a.score))
  let winnerId = scores[0].id

  # Record results for each genome
  for i in 0 ..< 4:
    let house = game.houses[houseIds[i]]
    let colonyCount = game.colonies.values.toSeq.filterIt(it.owner == houseIds[i]).len
    let militaryScore = game.fleets.values.toSeq.filterIt(it.owner == houseIds[i]).len
    result[genomes[i].id] = (
      won: i == winnerId,
      colonies: colonyCount,
      military: militaryScore
    )

proc evaluatePopulation(pop: var Population) =
  ## Evaluate fitness of all individuals in population by running tournaments
  ## Each AI plays multiple games against random opponents

  echo &"[Gen {pop.generation}] Evaluating {pop.individuals.len} AI personalities..."

  # Track performance for each genome
  var performance = initTable[int, tuple[games: int, wins: int, colonies: int, military: int]]()
  for genome in pop.individuals:
    performance[genome.id] = (games: 0, wins: 0, colonies: 0, military: 0)

  # Run tournaments
  let totalGames = (pop.individuals.len * pop.config.gamesPerIndividual) div 4
  var gamesPlayed = 0

  while gamesPlayed < totalGames:
    # Randomly select 4 AIs for this game
    var gameAIs: array[4, AIGenome]
    var selectedIndices: seq[int] = @[]

    for i in 0 ..< 4:
      var idx = rand(pop.individuals.high)
      while idx in selectedIndices:
        idx = rand(pop.individuals.high)
      selectedIndices.add(idx)
      gameAIs[i] = pop.individuals[idx]

    # Run game
    echo &"  Game {gamesPlayed + 1}/{totalGames}: IDs {gameAIs[0].id},{gameAIs[1].id},{gameAIs[2].id},{gameAIs[3].id}"
    let gameSeed = 42 + gamesPlayed  # Unique seed for each game
    let results = runTournamentGame(gameAIs, 100, gameSeed)  # 100 turn games

    # Update performance tracking
    for id, result in results:
      let p = performance[id]
      performance[id] = (
        games: p.games + 1,
        wins: p.wins + (if result.won: 1 else: 0),
        colonies: p.colonies + result.colonies,
        military: p.military + result.military
      )

    gamesPlayed.inc

  # Calculate fitness for each genome
  for genome in pop.individuals.mitems:
    let p = performance[genome.id]
    evaluateFitness(genome, p.games, p.wins, p.colonies, p.military)
    let winRate = if p.games > 0: (p.wins.float / p.games.float * 100.0) else: 0.0
    echo &"    ID {genome.id:3}: Fitness={genome.fitness:.3f} WinRate={winRate:5.1f}% Strategy={categorizeStrategy(genome.genes)}"

# ============================================================================
# Evolution Loop
# ============================================================================

proc runEvolution(config: GAConfig) =
  ## Main evolution loop: initialize population and evolve for N generations

  echo "=" .repeat(70)
  echo "EC4X AI Personality Evolution"
  echo "=" .repeat(70)
  echo ""
  echo &"Population Size:      {config.populationSize}"
  echo &"Generations:          {config.numGenerations}"
  echo &"Games per AI:         {config.gamesPerIndividual}"
  echo &"Tournament Size:      {config.tournamentSize}"
  echo &"Mutation Rate:        {config.mutationRate * 100:.1f}%"
  echo &"Mutation Strength:    {config.mutationStrength}"
  echo &"Crossover Rate:       {config.crossoverRate * 100:.1f}%"
  echo &"Elitism:              {config.elitismCount} best"
  echo ""

  # Create output directory
  let outputDir = "balance_results/evolution"
  createDir(outputDir)

  # Initialize population
  var pop = initPopulation(config)
  echo &"Initialized population with {pop.individuals.len} random AI personalities"
  echo ""

  # Evolution log
  var evolutionLog: seq[JsonNode] = @[]

  # Evolution loop
  for gen in 0 ..< config.numGenerations:
    let startTime = cpuTime()

    # Evaluate fitness
    evaluatePopulation(pop)

    # Calculate and display statistics
    let stats = calculateStats(pop)
    let elapsed = cpuTime() - startTime

    echo ""
    echo &"[Gen {stats.generation}] Statistics:"
    echo &"  Best Fitness:     {stats.bestFitness:.4f}"
    echo &"  Avg Fitness:      {stats.avgFitness:.4f}"
    echo &"  Worst Fitness:    {stats.worstFitness:.4f}"
    echo &"  Dominant Strategy: {stats.dominantStrategy}"
    echo &"  Time:             {elapsed:.1f}s"
    echo ""

    # Log generation results
    let genLog = %*{
      "stats": stats.toJson(),
      "bestIndividual": pop.individuals.sortedByIt(-it.fitness)[0].toJson(),
      "top5": pop.individuals.sortedByIt(-it.fitness)[0..min(4, pop.individuals.high)].mapIt(it.toJson())
    }
    evolutionLog.add(genLog)

    # Save checkpoint every 10 generations
    if (gen + 1) mod 10 == 0:
      let checkpointFile = outputDir / &"generation_{gen + 1:03}.json"
      writeFile(checkpointFile, $(%*evolutionLog))
      echo &"[Checkpoint] Saved to {checkpointFile}"
      echo ""

    # Evolve to next generation (unless this is the last one)
    if gen < config.numGenerations - 1:
      evolveGeneration(pop)
      echo &"[Gen {pop.generation - 1}] → [Gen {pop.generation}] Evolved new generation"
      echo ""

  # Save final results
  let finalFile = outputDir / "final_results.json"
  let finalResults = %*{
    "config": %*{
      "populationSize": config.populationSize,
      "numGenerations": config.numGenerations,
      "gamesPerIndividual": config.gamesPerIndividual,
      "tournamentSize": config.tournamentSize,
      "mutationRate": config.mutationRate,
      "mutationStrength": config.mutationStrength,
      "crossoverRate": config.crossoverRate,
      "elitismCount": config.elitismCount
    },
    "generations": evolutionLog,
    "finalPopulation": pop.individuals.mapIt(it.toJson())
  }
  writeFile(finalFile, $finalResults)

  echo "=" .repeat(70)
  echo "Evolution Complete!"
  echo "=" .repeat(70)
  echo &"Results saved to: {finalFile}"
  echo ""
  echo "Top 5 AI Personalities:"
  let top5 = pop.individuals.sortedByIt(-it.fitness)[0..min(4, pop.individuals.high)]
  for i, genome in top5:
    echo &"  {i + 1}. ID {genome.id} (Fitness: {genome.fitness:.4f}, Strategy: {categorizeStrategy(genome.genes)})"
    echo &"     Aggression={genome.genes.aggression:.2f} Economic={genome.genes.economicFocus:.2f} Expansion={genome.genes.expansionDrive:.2f}"

# ============================================================================
# CLI Entry Point
# ============================================================================

when isMainModule:
  var config = defaultGAConfig()

  # Parse command line arguments
  var p = initOptParser()
  while true:
    p.next()
    case p.kind:
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key:
      of "generations", "g":
        config.numGenerations = parseInt(p.val)
      of "population", "p":
        config.populationSize = parseInt(p.val)
      of "games", "n":
        config.gamesPerIndividual = parseInt(p.val)
      of "help", "h":
        echo "EC4X AI Evolution - Genetic Algorithm for AI Balance"
        echo ""
        echo "Usage: evolve_ai [options]"
        echo ""
        echo "Options:"
        echo "  --generations N, -g N   Number of generations to evolve (default: 50)"
        echo "  --population N, -p N    Population size (default: 20)"
        echo "  --games N, -n N         Games per AI per generation (default: 4)"
        echo "  --help, -h              Show this help"
        quit(0)
    of cmdArgument:
      discard

  # Run evolution
  runEvolution(config)
