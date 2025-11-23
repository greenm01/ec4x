## Genetic Algorithm for AI Personality Evolution
##
## Inspired by:
## - DEAP (Python): Clean API, tournament selection
## - OpenRA (C# RTS): Personality weight evolution for RTS bots
## - GAlib (C++): Proven genetic operators
##
## This GA evolves AIPersonality parameters to find balanced/dominant strategies

import std/[random, algorithm, math, sequtils, sugar, strformat, tables, json]
import ai_controller

# ============================================================================
# Genetic Algorithm Configuration
# ============================================================================

type
  GAConfig* = object
    ## Configuration for genetic algorithm
    populationSize*: int              # Number of AI personalities per generation
    numGenerations*: int              # How many generations to evolve
    gamesPerIndividual*: int          # Games each AI plays for fitness evaluation
    tournamentSize*: int              # Number of AIs per tournament (for selection)
    mutationRate*: float              # Probability of mutating each gene (0.0-1.0)
    mutationStrength*: float          # How much to change mutated genes (Gaussian sigma)
    crossoverRate*: float             # Probability of crossover vs cloning (0.0-1.0)
    elitismCount*: int                # Number of best individuals to preserve unchanged

  AIGenome* = object
    ## A genome encodes an AI personality's parameters
    ## This is what we're evolving via natural selection
    genes*: AIPersonality             # The personality parameters
    fitness*: float                   # Win rate from tournament games (0.0-1.0)
    id*: int                          # Unique identifier for tracking lineage

  Population* = object
    ## A generation of AI personalities
    individuals*: seq[AIGenome]
    generation*: int
    config*: GAConfig

  EvolutionStats* = object
    ## Statistics tracking evolution progress
    generation*: int
    bestFitness*: float
    avgFitness*: float
    worstFitness*: float
    diversityScore*: float            # Genetic diversity measure
    dominantStrategy*: string         # Categorize winner strategy

# ============================================================================
# Genome Creation and Mutation
# ============================================================================

var nextGenomeId = 0

proc newRandomGenome*(): AIGenome =
  ## Create a random AI genome with valid personality parameters
  ## All parameters are normalized to [0.0, 1.0] range
  nextGenomeId.inc
  result = AIGenome(
    genes: AIPersonality(
      aggression: rand(1.0),
      riskTolerance: rand(1.0),
      economicFocus: rand(1.0),
      expansionDrive: rand(1.0),
      diplomacyValue: rand(1.0),
      techPriority: rand(1.0)
    ),
    fitness: 0.0,
    id: nextGenomeId
  )

proc clampGene(value: float): float =
  ## Keep genes in valid [0.0, 1.0] range
  clamp(value, 0.0, 1.0)

proc mutate*(genome: var AIGenome, mutationRate: float, mutationStrength: float) =
  ## Mutate genome using Gaussian noise
  ## Each gene has `mutationRate` chance of being mutated
  ## Mutation adds N(0, mutationStrength) to the gene value

  template maybeMutate(gene: untyped) =
    if rand(1.0) < mutationRate:
      let noise = gauss(0.0, mutationStrength)
      gene = clampGene(gene + noise)

  maybeMutate(genome.genes.aggression)
  maybeMutate(genome.genes.riskTolerance)
  maybeMutate(genome.genes.economicFocus)
  maybeMutate(genome.genes.expansionDrive)
  maybeMutate(genome.genes.diplomacyValue)
  maybeMutate(genome.genes.techPriority)

proc crossover*(parent1, parent2: AIGenome): AIGenome =
  ## Two-point crossover: blend parent genes at random split points
  ## This is the "blend" operator from DEAP
  nextGenomeId.inc

  let alpha = rand(1.0)  # Blend factor
  result = AIGenome(
    genes: AIPersonality(
      aggression: clampGene(parent1.genes.aggression * alpha + parent2.genes.aggression * (1.0 - alpha)),
      riskTolerance: clampGene(parent1.genes.riskTolerance * alpha + parent2.genes.riskTolerance * (1.0 - alpha)),
      economicFocus: clampGene(parent1.genes.economicFocus * alpha + parent2.genes.economicFocus * (1.0 - alpha)),
      expansionDrive: clampGene(parent1.genes.expansionDrive * alpha + parent2.genes.expansionDrive * (1.0 - alpha)),
      diplomacyValue: clampGene(parent1.genes.diplomacyValue * alpha + parent2.genes.diplomacyValue * (1.0 - alpha)),
      techPriority: clampGene(parent1.genes.techPriority * alpha + parent2.genes.techPriority * (1.0 - alpha))
    ),
    fitness: 0.0,
    id: nextGenomeId
  )

# ============================================================================
# Fitness Evaluation
# ============================================================================

proc categorizeStrategy*(personality: AIPersonality): string =
  ## Categorize an AI's strategy based on its dominant traits
  ## Useful for analyzing which strategies dominate

  let traits = [
    ("Aggressive", personality.aggression),
    ("Economic", personality.economicFocus),
    ("Expansionist", personality.expansionDrive),
    ("Tech-Focused", personality.techPriority),
    ("Diplomatic", personality.diplomacyValue),
    ("Cautious", personality.riskTolerance)
  ]

  # Find highest-weighted trait
  var maxTrait = traits[0]
  for trait in traits:
    if trait[1] > maxTrait[1]:
      maxTrait = trait

  result = maxTrait[0]

proc evaluateFitness*(genome: var AIGenome, gamesPlayed: int, wins: int, colonies: int, militaryScore: int, prestige: int) =
  ## Calculate fitness based on game performance
  ## Fitness = weighted combination of:
  ## - Win rate (elimination victory or highest prestige at end)
  ## - Prestige (direct victory path - highest prestige wins)
  ## - Colony count (expansion enables prestige generation)
  ## - Military score (combat effectiveness for elimination)
  ##
  ## Victory conditions:
  ## 1. Elimination: Last house standing
  ## 2. Prestige: Highest prestige at game end
  ##
  ## Therefore prestige and win rate are equally important (40%/40%)

  let winRate = if gamesPlayed > 0: wins.float / gamesPlayed.float else: 0.0
  let avgColonies = if gamesPlayed > 0: colonies.float / gamesPlayed.float else: 0.0
  let avgMilitary = if gamesPlayed > 0: militaryScore.float / gamesPlayed.float else: 0.0
  let avgPrestige = if gamesPlayed > 0: prestige.float / gamesPlayed.float else: 0.0

  # Weighted fitness (prestige and winning are equally important)
  genome.fitness = (
    winRate * 0.40 +                   # 40% weight on winning (elimination or prestige)
    (avgPrestige / 1000.0) * 0.40 +    # 40% weight on prestige (direct victory condition)
    (avgColonies / 10.0) * 0.10 +      # 10% weight on expansion (enables prestige generation)
    (avgMilitary / 100.0) * 0.10       # 10% weight on military (enables elimination victory)
  )

# ============================================================================
# Selection Operators
# ============================================================================

proc tournamentSelect*(population: seq[AIGenome], tournamentSize: int): AIGenome =
  ## Tournament selection: randomly pick N individuals, return the best
  ## This is the standard selection method in DEAP

  var tournament: seq[AIGenome] = @[]
  for i in 0 ..< tournamentSize:
    tournament.add(population.sample())

  # Return fittest from tournament
  result = tournament.sortedByIt(-it.fitness)[0]

# ============================================================================
# Population Evolution
# ============================================================================

proc initPopulation*(config: GAConfig): Population =
  ## Create initial random population
  result = Population(
    individuals: newSeq[AIGenome](config.populationSize),
    generation: 0,
    config: config
  )

  for i in 0 ..< config.populationSize:
    result.individuals[i] = newRandomGenome()

proc evolveGeneration*(pop: var Population) =
  ## Create next generation using selection, crossover, and mutation
  ## This is the core evolution loop inspired by DEAP's algorithms.eaSimple

  # Sort by fitness (descending)
  pop.individuals.sort(proc(a, b: AIGenome): int = cmp(b.fitness, a.fitness))

  var nextGen: seq[AIGenome] = @[]

  # Elitism: preserve best individuals unchanged
  for i in 0 ..< pop.config.elitismCount:
    if i < pop.individuals.len:
      nextGen.add(pop.individuals[i])

  # Generate rest of population via selection + crossover/mutation
  while nextGen.len < pop.config.populationSize:
    if rand(1.0) < pop.config.crossoverRate:
      # Crossover: select two parents and blend
      let parent1 = tournamentSelect(pop.individuals, pop.config.tournamentSize)
      let parent2 = tournamentSelect(pop.individuals, pop.config.tournamentSize)
      var child = crossover(parent1, parent2)
      mutate(child, pop.config.mutationRate, pop.config.mutationStrength)
      nextGen.add(child)
    else:
      # Clone: select one parent and mutate
      var child = tournamentSelect(pop.individuals, pop.config.tournamentSize)
      mutate(child, pop.config.mutationRate, pop.config.mutationStrength)
      nextGen.add(child)

  pop.individuals = nextGen
  pop.generation.inc

proc calculateStats*(pop: Population): EvolutionStats =
  ## Calculate statistics for current generation
  let fitnesses = pop.individuals.mapIt(it.fitness)
  let best = pop.individuals.sortedByIt(-it.fitness)[0]

  result = EvolutionStats(
    generation: pop.generation,
    bestFitness: fitnesses.max,
    avgFitness: fitnesses.sum / fitnesses.len.float,
    worstFitness: fitnesses.min,
    diversityScore: 0.0,  # TODO: calculate genetic diversity
    dominantStrategy: categorizeStrategy(best.genes)
  )

# ============================================================================
# Serialization
# ============================================================================

proc toJson*(genome: AIGenome): JsonNode =
  ## Serialize genome to JSON for logging
  %*{
    "id": genome.id,
    "fitness": genome.fitness,
    "genes": {
      "aggression": genome.genes.aggression,
      "riskTolerance": genome.genes.riskTolerance,
      "economicFocus": genome.genes.economicFocus,
      "expansionDrive": genome.genes.expansionDrive,
      "diplomacyValue": genome.genes.diplomacyValue,
      "techPriority": genome.genes.techPriority
    },
    "strategy": categorizeStrategy(genome.genes)
  }

proc toJson*(stats: EvolutionStats): JsonNode =
  ## Serialize evolution stats to JSON
  %*{
    "generation": stats.generation,
    "bestFitness": stats.bestFitness,
    "avgFitness": stats.avgFitness,
    "worstFitness": stats.worstFitness,
    "diversityScore": stats.diversityScore,
    "dominantStrategy": stats.dominantStrategy
  }

# ============================================================================
# Default Configuration
# ============================================================================

proc defaultGAConfig*(): GAConfig =
  ## Recommended GA parameters for EC4X AI evolution
  ## Based on OpenRA bot evolution (similar RTS game)
  GAConfig(
    populationSize: 20,               # Small population for fast iteration
    numGenerations: 50,               # Evolve for 50 generations
    gamesPerIndividual: 4,            # Each AI plays 4 games per generation
    tournamentSize: 3,                # Tournament of 3 (standard for DEAP)
    mutationRate: 0.15,               # 15% chance to mutate each gene
    mutationStrength: 0.1,            # Small mutations (10% stddev)
    crossoverRate: 0.7,               # 70% crossover, 30% cloning
    elitismCount: 2                   # Keep 2 best AIs unchanged
  )
