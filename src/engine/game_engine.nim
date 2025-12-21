## EC4X Game Engine
## Public API for game initialization, turn processing, and state queries

# src/
# └── engine/
#     ├── types/                 <-- THE "DATA SHAPES" (No logic here)
#     │   ├── core.nim           # EntityManager[ID, T], IdCounters, Basic IDs
#     │   ├── game_state.nim     # The main GameState object definition
#     │   ├── ship.nim           # Ship and Ships object definitions
#     │   ├── fleet.nim          # Fleet and Fleets object definitions
#     │   └── ...                # colony.nim, system.nim, etc.
#     │
#     ├── state/                 <-- THE "PLUMBING" (Generic logic)
#     │   ├── entity_manager.nim  # Generic: addEntity, removeEntity, updateEntity
#     │   ├── id_gen.nim          # Counter logic: generateShipId, etc.
#     │   ├── game_state.nim      # initGameState and global convenience procs
#     │   ├── queries.nim         # Iterators: allShips, fleetsInSystem
#     │   ├── fog_of_war.nim      # LOGIC: calculates sensor range and visibility
#     │   └── player_view_gen.nim # LOGIC: generates a PlayerView from GameState + Intel
#     │
#     └── entities/              <-- THE "RULES" (Gameplay logic)
#         ├── ship_manager.nim   # spawnShip (uses id_gen + bySquadron index)
#         ├── fleet_manager.nim  # moveFleet (updates bySystem index)
#         └── ...

import types/[game_state, command]
import turn_cycle/turn_executor
import services/persistence/[save, load]
import services/player_view/fog_of_war
import services/reporting/turn_report

export game_state.GameState
export command.CommandPacket
export turn_report.TurnReport

# Game lifecycle
proc newGame*(playerCount: int, seed: int64, config: GameConfig): GameState =
  ## Initialize a new game
  result = initializeGameState(playerCount, seed, config)

proc loadGame*(gameId: int32): GameState =
  ## Load existing game from database
  load.loadGameState(gameId)

proc saveGame*(state: GameState) =
  ## Persist game state to database
  save.saveGameState(state)

# Turn execution
proc processTurn*(state: var GameState, commands: Table[HouseId, CommandPacket]): TurnReport =
  ## Execute complete turn cycle and return results
  result = turn_executor.executeTurnCycle(state, commands)
  saveGame(state)  # Auto-save after each turn

# Player views
proc getPlayerView*(state: GameState, houseId: HouseId): PlayerView =
  ## Get fog-of-war filtered view for specific house
  fog_of_war.generatePlayerView(state, houseId)

# State queries (convenience methods)
proc getHouse*(state: GameState, houseId: HouseId): House =
  let idx = state.houses.index[houseId]
  state.houses.data[idx]

proc getFleet*(state: GameState, fleetId: FleetId): Fleet =
  let idx = state.fleets.index[fleetId]
  state.fleets.data[idx]

proc getColony*(state: GameState, colonyId: ColonyId): Colony =
  let idx = state.colonies.index[colonyId]
  state.colonies.data[idx]

# Game status
proc isGameOver*(state: GameState): bool =
  ## Check if game has ended (victory/defeat conditions)
  checkVictoryConditions(state)

proc getWinner*(state: GameState): Option[HouseId] =
  ## Get winning house if game is over
  determineWinner(state)
