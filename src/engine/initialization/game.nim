import std/[tables, options, math, algorithm, logging]
import ../../common/types/[core, planets, tech, diplomacy]
import ../fleet 
import ../starmap
import ../squadron
import ../order_types
import ../../../config/[military_config, economy_config]
import ../../ai/rba/config  
import ../diagnostics_data
import ../diplomacy/types as dip_types
import ../diplomacy/proposals as dip_proposals
import ../espionage/types as esp_types
import ../systems/combat/orbital
import ../systems/combat/planetary
import ../research/effects
import ../economy/types as econ_types
import ../population/types as pop_types
import ../intelligence/types as intel_types
import ../types/core # Import GameAct and ActProgressionConfig
import ./validation # For validateTechTree signature
import ../validation # For validateTechTree signature

# Game initialization functions

proc newGame*(gameId: string, playerCount: int, seed: int): GameState =
  ## Create a new game with automatic setup
  ## Uses default parameters for map size, AI personalities, etc.
  ## Returns a fully initialized GameState object

  # TODO: Implement game creation logic:
  # 1. Load game parameters from config files (e.g., game_setup/standard.toml)
  # 2. Generate starMap based on seed and parameters
  # 3. Call newGameState to create the initial state with the generated starmap
  # 4. Call initializeHousesAndHomeworlds to populate houses, colonies, fleets

  logInfo("Initialization", "Creating new game with ID ", gameId, ", players ",
          playerCount, ", seed ", seed)

  # Placeholder for now, actual implementation will use the above steps
  result = GameState(gameId: gameId, turn: 0, phase: GamePhase.Setup)

proc newGameState*(gameId: string, playerCount: int, starMap: StarMap): GameState =
  ## Create a new game state with an existing star map
  ## Used for loading games or custom map setups
  ## Requires player count to initialize house/AI configurations

  # TODO: Implement game state creation logic:
  # Initialize core GameState fields, set up initial indices,
  # but do NOT initialize houses/colonies/fleets here directly.
  # That will be handled by initializeHousesAndHomeworlds.

  logInfo("Initialization", "Creating new game state for game ID ", gameId,
          " with ", playerCount, " players.")

  result = GameState(
    gameId: gameId,
    turn: 0,
    phase: GamePhase.Setup,
    starMap: starMap,
    houses: initTable[HouseId, House](),
    fleets: initTable[FleetId, Fleet](),
    colonies: initTable[SystemId, Colony](),
    fleetsByOwner: initTable[HouseId, seq[FleetId]](),
    fleetsByLocation: initTable[SystemId, seq[FleetId]](),
    coloniesByOwner: initTable[HouseId, seq[SystemId]](),
    # ... other default initializations for a blank state
  )

proc initializeHousesAndHomeworlds*(state: var GameState) =
  ## Initialize houses, homeworlds, and starting fleets for all players
  ## Per game setup rules (e.g., docs/specs/05-gameplay.md:1.3)
  ##
  ## This function is called once after GameState creation by newGame:
  ## 1. Reads player count and homeworld settings from config
  ## 2. Creates House objects, assigns homeworlds, starting fleets, etc.
  ## 3. Populates `state.houses`, `state.fleets`, `state.colonies` indices

  logInfo("Initialization", "Initializing houses and homeworlds...")
  # TODO: Implement actual house/homeworld/fleet creation logic here.
  # This will likely involve calling initializeHouse, createHomeColony, and
  # fleet creation helpers.