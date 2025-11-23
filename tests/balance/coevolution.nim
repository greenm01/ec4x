## Competitive Coevolution for Balance Testing
##
## Evolves 4 competing species to find exploits in:
## - Economy (growth strategies)
## - Military (combat/aggression)
## - Diplomacy (alliance manipulation)
## - Technology (tech rush strategies)
##
## Each species evolves to counter the others, creating arms race dynamics
## that expose balance issues faster than random matchups

import std/[random, algorithm, math, sequtils, sugar, strformat, tables, json, times, os, strutils]
import genetic_ai
import ai_controller
import game_setup
import ../../src/engine/[gamestate, resolve, orders]
import ../../src/common/types/core

type
  SpeciesType* {.pure.} = enum
    ## Five specialized archetypes that target different game systems
    Economic,      # Focus: Growth, expansion, infrastructure
    Military,      # Focus: Fleet power, aggression, conquest
    Diplomatic,    # Focus: Alliances, manipulation, soft power
    Technology,    # Focus: Tech rush, advanced units, force multipliers
    Espionage      # Focus: Intelligence, sabotage, covert operations

  Species* = object
    ## A population that specializes in one strategy archetype
    speciesType*: SpeciesType
    individuals*: seq[AIGenome]
    champion*: AIGenome          # Best individual (for competition)
    generation*: int
    winCount*: int               # Wins against other species
    totalGames*: int

  CoevolutionConfig* = object
    ## Config for competitive coevolution
    speciesPopSize*: int         # Individuals per species
    numGenerations*: int
    gamesPerGeneration*: int     # Games between species per generation
    mutationRate*: float
    mutationStrength*: float
    crossoverRate*: float
    elitismCount*: int

  CoevolutionState* = object
    ## Complete coevolution state
    species*: array[5, Species]
    generation*: int
    config*: CoevolutionConfig

# ============================================================================
# Species Initialization
# ============================================================================

proc initializeSpecies*(speciesType: SpeciesType, popSize: int): Species =
  ## Initialize a species with biased random genomes
  ## Each species starts with preferences toward their archetype
  result = Species(
    speciesType: speciesType,
    individuals: @[],
    generation: 0,
    winCount: 0,
    totalGames: 0
  )

  # Create biased genomes for this archetype
  for i in 0 ..< popSize:
    var genome = newRandomGenome()

    # Bias toward species archetype (70% bias + 30% random)
    case speciesType:
    of SpeciesType.Economic:
      genome.genes.economicFocus = 0.7 + rand(0.3)
      genome.genes.expansionDrive = 0.6 + rand(0.4)
      genome.genes.techPriority = 0.5 + rand(0.3)
      genome.genes.aggression = rand(0.3)
    of SpeciesType.Military:
      genome.genes.aggression = 0.7 + rand(0.3)
      genome.genes.riskTolerance = 0.6 + rand(0.4)
      genome.genes.economicFocus = rand(0.4)
      genome.genes.expansionDrive = 0.4 + rand(0.3)
    of SpeciesType.Diplomatic:
      genome.genes.diplomacyValue = 0.7 + rand(0.3)
      genome.genes.riskTolerance = rand(0.4)
      genome.genes.aggression = rand(0.3)
      genome.genes.economicFocus = 0.5 + rand(0.3)
    of SpeciesType.Technology:
      genome.genes.techPriority = 0.7 + rand(0.3)
      genome.genes.economicFocus = 0.6 + rand(0.3)
      genome.genes.aggression = rand(0.4)
      genome.genes.expansionDrive = rand(0.4)
    of SpeciesType.Espionage:
      # Espionage needs: high risk tolerance, LOW aggression, moderate tech
      # Formula: espionageFocus = (riskTolerance + (1-aggression)) / 2.0
      # Target: espionageFocus > 0.6 for heavy EBP investment
      genome.genes.riskTolerance = 0.7 + rand(0.3)   # 0.7-1.0: high risk
      genome.genes.aggression = 0.1 + rand(0.3)      # 0.1-0.4: low aggression
      genome.genes.economicFocus = 0.4 + rand(0.3)   # 0.4-0.7: moderate economy
      genome.genes.expansionDrive = 0.3 + rand(0.3)  # 0.3-0.6: low expansion
      genome.genes.diplomacyValue = 0.5 + rand(0.3)  # 0.5-0.8: moderate diplomacy
      genome.genes.techPriority = 0.6 + rand(0.3)    # 0.6-0.9: high tech (for EBP value)

    result.individuals.add(genome)

  # Set initial champion
  result.champion = result.individuals[0]

# ============================================================================
# Inter-Species Competition
# ============================================================================

proc runSpeciesCompetition(champions: seq[AIGenome], speciesTypes: seq[SpeciesType], seed: int64): Table[SpeciesType, tuple[won: bool, colonies: int, military: int]] =
  ## Run a 4-way competition between species champions
  ## Takes any 4 species (to allow 5-species rotation)
  ## Returns results for each species

  var rng = initRand(seed)
  var game = createBalancedGame(4, 4, seed)

  let houseIds = toSeq(game.houses.keys)
  var controllers: seq[AIController] = @[]

  # Map champions to species types (for result tracking)
  var genomeToSpecies: Table[int, SpeciesType]
  for i in 0 ..< min(4, champions.len):
    genomeToSpecies[champions[i].id] = speciesTypes[i]
    let controller = newAIControllerWithPersonality(houseIds[i], champions[i].genes)
    controllers.add(controller)

  # Run 100-turn game
  for turn in 1 .. 100:
    var ordersTable = initTable[HouseId, OrderPacket]()
    for controller in controllers:
      let orders = generateAIOrders(controller, game, rng)
      ordersTable[controller.houseId] = orders

    let turnResult = resolveTurn(game, ordersTable)
    game = turnResult.newState

  # Calculate winner
  var scores: seq[tuple[idx: int, score: float]] = @[]
  for i in 0 ..< 4:
    let house = game.houses[houseIds[i]]
    let colonyCount = game.colonies.values.toSeq.filterIt(it.owner == houseIds[i]).len
    let militaryScore = game.fleets.values.toSeq.filterIt(it.owner == houseIds[i]).len
    let score = house.prestige.float * 10.0 + colonyCount.float * 100.0 + militaryScore.float
    scores.add((idx: i, score: score))

  scores.sort(proc(a, b: auto): int = cmp(b.score, a.score))
  let winnerIdx = scores[0].idx

  # Build results table
  result = initTable[SpeciesType, tuple[won: bool, colonies: int, military: int]]()
  for i in 0 ..< 4:
    let house = game.houses[houseIds[i]]
    let colonyCount = game.colonies.values.toSeq.filterIt(it.owner == houseIds[i]).len
    let militaryScore = game.fleets.values.toSeq.filterIt(it.owner == houseIds[i]).len
    let speciesType = genomeToSpecies[champions[i].id]

    result[speciesType] = (
      won: i == winnerIdx,
      colonies: colonyCount,
      military: militaryScore
    )

proc evaluateSpecies(species: var Species, config: CoevolutionConfig) =
  ## Evaluate fitness of individuals within a species via internal tournaments
  echo &"  [{species.speciesType}] Evaluating {species.individuals.len} individuals..."

  # Track performance
  var performance = initTable[int, tuple[games: int, wins: int, colonies: int, military: int]]()
  for genome in species.individuals:
    performance[genome.id] = (games: 0, wins: 0, colonies: 0, military: 0)

  # Run internal species tournaments (members compete against each other)
  let internalGames = config.speciesPopSize  # Each member plays ~1 game
  for gameIdx in 0 ..< internalGames:
    # Select 4 random individuals from this species
    var gameAIs: array[4, AIGenome]
    for i in 0 ..< 4:
      gameAIs[i] = species.individuals.sample()

    # Run game
    let seed = 1000 + gameIdx + species.generation * 1000
    var rng = initRand(seed)
    var game = createBalancedGame(4, 4, seed)
    let houseIds = toSeq(game.houses.keys)

    var controllers: seq[AIController] = @[]
    for i in 0 ..< 4:
      let controller = newAIControllerWithPersonality(houseIds[i], gameAIs[i].genes)
      controllers.add(controller)

    # Simulate game
    for turn in 1 .. 100:
      var ordersTable = initTable[HouseId, OrderPacket]()
      for controller in controllers:
        let orders = generateAIOrders(controller, game, rng)
        ordersTable[controller.houseId] = orders

      let turnResult = resolveTurn(game, ordersTable)
      game = turnResult.newState

    # Score results
    var scores: seq[tuple[idx: int, score: float]] = @[]
    for i in 0 ..< 4:
      let house = game.houses[houseIds[i]]
      let colonyCount = game.colonies.values.toSeq.filterIt(it.owner == houseIds[i]).len
      let militaryScore = game.fleets.values.toSeq.filterIt(it.owner == houseIds[i]).len
      let score = house.prestige.float * 10.0 + colonyCount.float * 100.0 + militaryScore.float
      scores.add((idx: i, score: score))

    scores.sort(proc(a, b: auto): int = cmp(b.score, a.score))
    let winnerIdx = scores[0].idx

    # Update performance
    for i in 0 ..< 4:
      let house = game.houses[houseIds[i]]
      let colonyCount = game.colonies.values.toSeq.filterIt(it.owner == houseIds[i]).len
      let militaryScore = game.fleets.values.toSeq.filterIt(it.owner == houseIds[i]).len
      let p = performance[gameAIs[i].id]
      performance[gameAIs[i].id] = (
        games: p.games + 1,
        wins: p.wins + (if i == winnerIdx: 1 else: 0),
        colonies: p.colonies + colonyCount,
        military: p.military + militaryScore
      )

  # Calculate fitness
  for genome in species.individuals.mitems:
    let p = performance[genome.id]
    if p.games > 0:
      evaluateFitness(genome, p.games, p.wins, p.colonies, p.military)
    else:
      genome.fitness = 0.0

# ============================================================================
# Species Evolution
# ============================================================================

proc evolveSpecies(species: var Species, config: CoevolutionConfig) =
  ## Evolve a single species for one generation
  species.individuals.sort(proc(a, b: AIGenome): int = cmp(b.fitness, a.fitness))

  var nextGen: seq[AIGenome] = @[]

  # Elitism
  for i in 0 ..< config.elitismCount:
    if i < species.individuals.len:
      nextGen.add(species.individuals[i])

  # Breed rest of population
  while nextGen.len < config.speciesPopSize:
    if rand(1.0) < config.crossoverRate:
      let parent1 = tournamentSelect(species.individuals, 3)
      let parent2 = tournamentSelect(species.individuals, 3)
      var child = crossover(parent1, parent2)
      mutate(child, config.mutationRate, config.mutationStrength)
      nextGen.add(child)
    else:
      var child = tournamentSelect(species.individuals, 3)
      mutate(child, config.mutationRate, config.mutationStrength)
      nextGen.add(child)

  species.individuals = nextGen
  species.generation.inc

  # Update champion
  species.champion = species.individuals[0]

# ============================================================================
# Coevolution Main Loop
# ============================================================================

proc runCoevolution*(config: CoevolutionConfig) =
  ## Main coevolution loop

  echo "=" .repeat(70)
  echo "EC4X Competitive Coevolution - Balance Testing"
  echo "=" .repeat(70)
  echo ""
  echo &"Species Population:   {config.speciesPopSize} each (4 species)"
  echo &"Generations:          {config.numGenerations}"
  echo &"Games/Generation:     {config.gamesPerGeneration}"
  echo &"Mutation Rate:        {config.mutationRate * 100:.1f}%"
  echo &"Crossover Rate:       {config.crossoverRate * 100:.1f}%"
  echo ""

  # Initialize species
  var state = CoevolutionState(
    species: [
      initializeSpecies(SpeciesType.Economic, config.speciesPopSize),
      initializeSpecies(SpeciesType.Military, config.speciesPopSize),
      initializeSpecies(SpeciesType.Diplomatic, config.speciesPopSize),
      initializeSpecies(SpeciesType.Technology, config.speciesPopSize),
      initializeSpecies(SpeciesType.Espionage, config.speciesPopSize)
    ],
    generation: 0,
    config: config
  )

  echo "Initialized 5 species: Economic, Military, Diplomatic, Technology, Espionage"
  echo ""

  # Evolution log
  var evolutionLog: seq[JsonNode] = @[]

  # Create output directory
  let outputDir = "balance_results/coevolution"
  createDir(outputDir)

  # Main evolution loop
  for gen in 0 ..< config.numGenerations:
    echo &"[Generation {gen}]"
    let startTime = cpuTime()

    # 1. Evaluate each species internally
    for species in state.species.mitems:
      evaluateSpecies(species, config)

    # 2. Inter-species competition (champions fight)
    # With 5 species, rotate through different combinations of 4
    echo ""
    echo "  [Inter-Species Tournament]"
    for gameIdx in 0 ..< config.gamesPerGeneration:
      # Rotate which 4 species play (exclude one each game)
      let excludedSpecies = gameIdx mod 5
      var champions: seq[AIGenome] = @[]
      var speciesInGame: seq[SpeciesType] = @[]

      for i in 0 ..< 5:
        if i != excludedSpecies:
          champions.add(state.species[i].champion)
          speciesInGame.add(state.species[i].speciesType)

      let seed = 5000 + gen * 100 + gameIdx
      let results = runSpeciesCompetition(champions, speciesInGame, seed)

      # Update species win counts
      for speciesType, result in results:
        let idx = ord(speciesType)
        state.species[idx].totalGames.inc
        if result.won:
          state.species[idx].winCount.inc
          echo &"    Game {gameIdx + 1}: {speciesType} WON (colonies={result.colonies}, military={result.military})"

    # 3. Display generation stats
    echo ""
    echo "  [Species Performance]"
    for species in state.species:
      let winRate = if species.totalGames > 0: (species.winCount.float / species.totalGames.float * 100.0) else: 0.0
      let avgFitness = species.individuals.mapIt(it.fitness).sum / species.individuals.len.float
      echo &"    {species.speciesType}: WinRate={winRate:5.1f}% AvgFitness={avgFitness:.3f} Champion={species.champion.fitness:.3f}"

    let elapsed = cpuTime() - startTime
    echo &"  Time: {elapsed:.1f}s"
    echo ""

    # 4. Log generation
    let genLog = %*{
      "generation": gen,
      "species": state.species.mapIt(%*{
        "type": $it.speciesType,
        "winCount": it.winCount,
        "totalGames": it.totalGames,
        "champion": it.champion.toJson(),
        "avgFitness": it.individuals.mapIt(it.fitness).sum / it.individuals.len.float
      })
    }
    evolutionLog.add(genLog)

    # 5. Evolve each species
    if gen < config.numGenerations - 1:
      for species in state.species.mitems:
        evolveSpecies(species, config)
      state.generation.inc

  # Save final results
  let finalFile = outputDir / "coevolution_results.json"
  let finalResults = %*{
    "config": %*{
      "speciesPopSize": config.speciesPopSize,
      "numGenerations": config.numGenerations,
      "gamesPerGeneration": config.gamesPerGeneration
    },
    "generations": evolutionLog,
    "finalChampions": state.species.mapIt(%*{
      "species": $it.speciesType,
      "winRate": if it.totalGames > 0: (it.winCount.float / it.totalGames.float) else: 0.0,
      "champion": it.champion.toJson()
    })
  }
  writeFile(finalFile, $finalResults)

  echo "=" .repeat(70)
  echo "Coevolution Complete!"
  echo "=" .repeat(70)
  echo &"Results saved to: {finalFile}"
  echo ""
  echo "Final Species Win Rates:"
  for species in state.species:
    let winRate = if species.totalGames > 0: (species.winCount.float / species.totalGames.float * 100.0) else: 0.0
    echo &"  {species.speciesType}: {winRate:5.1f}% ({species.winCount}/{species.totalGames} wins)"

# ============================================================================
# CLI
# ============================================================================

proc defaultCoevolutionConfig*(): CoevolutionConfig =
  CoevolutionConfig(
    speciesPopSize: 10,           # 10 individuals per species (40 total)
    numGenerations: 30,           # 30 generations
    gamesPerGeneration: 5,        # 5 inter-species games per generation
    mutationRate: 0.15,
    mutationStrength: 0.1,
    crossoverRate: 0.7,
    elitismCount: 2
  )

when isMainModule:
  var config = defaultCoevolutionConfig()

  # Parse args
  for i in 1 .. paramCount():
    let arg = paramStr(i)
    if arg.startsWith("--generations="):
      config.numGenerations = parseInt(arg.split("=")[1])
    elif arg.startsWith("--population="):
      config.speciesPopSize = parseInt(arg.split("=")[1])
    elif arg.startsWith("--games="):
      config.gamesPerGeneration = parseInt(arg.split("=")[1])
    elif arg == "--help":
      echo "EC4X Competitive Coevolution"
      echo ""
      echo "Usage: coevolution [options]"
      echo ""
      echo "Options:"
      echo "  --generations=N    Generations to evolve (default: 30)"
      echo "  --population=N     Population per species (default: 10)"
      echo "  --games=N          Inter-species games per gen (default: 5)"
      quit(0)

  runCoevolution(config)
