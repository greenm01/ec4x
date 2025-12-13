## Game Initialization - Public API
##
## Main entry point for creating new games.
## Extracted from gamestate.nim as part of initialization refactoring.
##
## This module provides the public API for game initialization:
## - newGame(): Create complete game with starmap generation
## - newGameState(): Create game with existing starmap
## - initializeHousesAndHomeworlds(): Setup players and starting conditions

import std/[tables, strutils]
import ../gamestate
import ../starmap
import ../order_types
import ../fleet as fleet_mod
import ../config/prestige_multiplier
import ../config/population_growth_multiplier
import ../config/game_setup_config
import ../../common/types/[core, units]
import ./[house, colony, fleet as init_fleet, validation]

proc initializeHousesAndHomeworlds*(state: var GameState) =
  ## Initialize houses, their homeworld colonies, and starting fleets
  ##
  ## Called during game setup to create starting conditions per
  ## game_setup/standard.toml:
  ## - Creates houses with starting resources and technology
  ## - Creates homeworld colonies with starting infrastructure
  ## - Creates starting fleets with initial ship composition
  ##
  ## Configuration loaded from: game_setup/standard.toml
  ## See: config/game_setup_config.nim for configuration types
  ##
  ## Starting fleet composition example (from standard.toml):
  ##   - 2 colonization fleets (ETAC + Light Cruiser each)
  ##   - 2 scout fleets (Destroyer each)
  ##
  ## Used by: `newGame` during game initialization
  let playerCount = state.starMap.playerCount
  let setupConfig = game_setup_config.globalGameSetupConfig

  # Load individual fleet configurations from game_setup/fleets.toml
  let fleetConfigs = game_setup_config.loadIndividualFleetConfigs()

  for playerIdx in 0 ..< playerCount:
    # TODO Phase 4: Use house naming from config
    let houseName = "House" & $(playerIdx + 1)
    let houseId = "house" & $(playerIdx + 1)
    let houseColor = ["blue", "red", "green", "yellow", "purple", "orange",
                     "cyan", "magenta", "brown", "pink", "gray", "white"][
                       playerIdx mod 12]

    # Create and add house
    var newHouse = house.initializeHouse(houseName, houseColor)
    newHouse.id = houseId
    state.houses[houseId] = newHouse

    # Create homeworld colony at player's designated homeworld system
    let homeworldSystemId = state.starMap.playerSystemIds[playerIdx]
    let homeworld = colony.createHomeColony(homeworldSystemId, houseId)
    state.colonies[homeworldSystemId] = homeworld

    # Create starting fleets from individual fleet configurations
    let newFleets = init_fleet.createStartingFleets(houseId, homeworldSystemId, fleetConfigs)

    for newFleet in newFleets:
      state.fleets[newFleet.id] = newFleet

      # Add guard colony standing order to each fleet at homeworld
      state.standingOrders[newFleet.id] = StandingOrder(
        fleetId: newFleet.id,
        orderType: StandingOrderType.GuardColony,
        params: StandingOrderParams(
          orderType: StandingOrderType.GuardColony,
          defendTargetSystem: homeworldSystemId,  # Guard homeworld
          defendMaxRange: 0  # Stay at homeworld only
        ),
        roe: 6,  # Standard combat posture
        createdTurn: 0,
        lastActivatedTurn: 0,
        activationCount: 0,
        suspended: false,
        enabled: true,  # Enabled by default for starting fleets
        activationDelayTurns: 0,  # No delay for initial setup
        turnsUntilActivation: 0   # Active immediately
      )

proc newGame*(gameId: string, playerCount: int, seed: int64 = 42): GameState =
  ## Create a new game with full setup including starmap generation
  ##
  ## This is the recommended way to create a new game. It handles:
  ## - Starmap generation and population
  ## - Game state initialization
  ## - Input validation
  ##
  ## Parameters:
  ##   - gameId: Unique identifier for this game
  ##   - playerCount: Number of players (2-12)
  ##   - seed: Random seed for map generation
  ##
  ## Example:
  ##   let game = newGame("game1", 4, seed = 12345)

  # Create and populate starmap
  var starMap = starmap.newStarMap(playerCount, seed)
  starMap.populate()

  # Initialize the prestige multiplier
  prestige_multiplier.initializePrestigeMultiplier(starMap.systems.len, playerCount)

  # Initialize the population growth multiplier
  population_growth_multiplier.initializePopulationGrowthMultiplier(starMap.systems.len, playerCount)

  # Create game state with populated map
  result = GameState(
    gameId: gameId,
    turn: 0,
    phase: GamePhase.Setup,
    starMap: starMap,
    houses: initTable[HouseId, House](),
    colonies: initTable[SystemId, Colony](),
    fleets: initTable[FleetId, Fleet](),
    fleetOrders: initTable[FleetId, FleetOrder](),
    arrivedFleets: initTable[FleetId, SystemId](),
    standingOrders: initTable[FleetId, StandingOrder](),
    ongoingEffects: @[],
    scoutLossEvents: @[],
    populationInTransit: @[],
    pendingProposals: @[],
    pendingMilitaryCommissions: @[],
    pendingPlanetaryCommissions: @[],
    gracePeriodTimers: initTable[HouseId, GracePeriodTracker]()
  )

  # Create houses and homeworld colonies
  result.initializeHousesAndHomeworlds()

proc newGameState*(gameId: string, playerCount: int,
                  starMap: StarMap): GameState =
  ## Create initial game state with an existing starMap
  ##
  ## IMPORTANT: The starMap must be populated before passing to this function.
  ## Call `starMap.populate()` after creating with `newStarMap()`.
  ##
  ## Prefer using `newGame()` which handles starmap creation automatically.
  ##
  ## Example:
  ##   var starMap = newStarMap(playerCount)
  ##   starMap.populate()  # REQUIRED
  ##   let state = newGameState("game1", playerCount, starMap)

  # Validate starMap is populated
  if starMap.systems.len == 0:
    raise newException(ValueError,
      "StarMap must be populated before creating GameState. " &
      "Call starMap.populate() first.")

  result = GameState(
    gameId: gameId,
    turn: 0,
    phase: GamePhase.Setup,
    starMap: starMap,
    houses: initTable[HouseId, House](),
    colonies: initTable[SystemId, Colony](),
    fleets: initTable[FleetId, Fleet](),
    fleetOrders: initTable[FleetId, FleetOrder](),
    arrivedFleets: initTable[FleetId, SystemId](),
    standingOrders: initTable[FleetId, StandingOrder](),
    ongoingEffects: @[],
    scoutLossEvents: @[],
    populationInTransit: @[],
    pendingProposals: @[],
    pendingMilitaryCommissions: @[],
    pendingPlanetaryCommissions: @[],
    gracePeriodTimers: initTable[HouseId, GracePeriodTracker]()
  )

  # Create houses and homeworld colonies
  result.initializeHousesAndHomeworlds()
