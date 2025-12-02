## Parallel Game Simulation
##
## Enables multi-threaded execution of game simulations for faster evolution
## Uses simple batch parallelism (divide games across cores)

import std/[cpuinfo, strformat]
import genetic_ai, game_setup, ai_controller
import ../../src/engine/[gamestate, resolve, orders]
import ../../src/common/types/core
import std/[tables, sequtils, sugar, random]

type
  GameResult* = object
    genomeIds*: array[4, int]       # Which genomes played
    winnerIdx*: int                 # Which one won (0-3)
    scores*: array[4, tuple[colonies: int, military: int, prestige: int]]

proc simulateGame*(genomes: array[4, AIGenome], seed: int64): GameResult =
  ## Run a single game simulation
  var rng = initRand(seed)
  var game = createBalancedGame(4, 4, seed)

  let houseIds = toSeq(game.houses.keys)
  var controllers: seq[AIController] = @[]

  for i in 0 ..< 4:
    let controller = newAIControllerWithPersonality(houseIds[i], genomes[i].genes)
    controllers.add(controller)

  # Run 100-turn game
  for turn in 1 .. 100:
    var ordersTable = initTable[HouseId, OrderPacket]()
    for controller in controllers:
      let orders = generateAIOrders(controller, game, rng)
      ordersTable[controller.houseId] = orders

    let turnResult = resolveTurn(game, ordersTable)
    game = turnResult.newState

  # Calculate scores
  var scores: seq[tuple[idx: int, score: float]] = @[]
  var gameScores: array[4, tuple[colonies: int, military: int, prestige: int]]

  for i in 0 ..< 4:
    let house = game.houses[houseIds[i]]
    let colonyCount = game.colonies.values.toSeq.filterIt(it.owner == houseIds[i]).len
    let militaryScore = game.fleets.values.toSeq.filterIt(it.owner == houseIds[i]).len
    let score = house.prestige.float * 10.0 + colonyCount.float * 100.0 + militaryScore.float

    gameScores[i] = (colonies: colonyCount, military: militaryScore, prestige: house.prestige)
    scores.add((idx: i, score: score))

  scores.sort(proc(a, b: auto): int = cmp(b.score, a.score))

  result = GameResult(
    genomeIds: [genomes[0].id, genomes[1].id, genomes[2].id, genomes[3].id],
    winnerIdx: scores[0].idx,
    scores: gameScores
  )

# For now, run sequentially
# TODO: Add --threads support with proper thread pool
proc runGames*(gameSetups: seq[array[4, AIGenome]], baseSeed: int64): seq[GameResult] =
  ## Run games (sequentially for now, but structure allows threading later)
  result = newSeq[GameResult](gameSetups.len)

  for i in 0 ..< gameSetups.len:
    let seed = baseSeed + i
    result[i] = simulateGame(gameSetups[i], seed)
