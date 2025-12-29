## EC4X Game Engine
## Public API for game initialization, turn processing, and state queries
import types/[game_state, command]
import init/engine

export game_state.GameState
export command.CommandPacket

# Game lifecycle
proc newGame*(
  scenarioPath: string = "scenarios/standard.kdl",
  gameName: string = "",
  gameDescription: string = "",
  dataDir: string = "data"
): GameState =
  ## Initialize a new game
  ##
  ## Args:
  ##   scenarioPath: Path to scenario KDL file (default: scenarios/standard.kdl)
  ##   gameName: Human-readable game name (default: use scenarioName from config)
  ##   gameDescription: Optional game description for admin notes
  ##   dataDir: Root directory for per-game databases
  result = initGameState(scenarioPath, gameName, gameDescription, "config", dataDir)

#[
proc loadGame*(gameId: int32): GameState =
  ## Load existing game from database
  load.loadGameState(gameId)

proc saveGame*(state: GameState) =
  ## Persist game state to database
  save.saveGameState(state)

# Turn execution
proc resolveTurn*(
    state: var GameState, commands: Table[HouseId, CommandPacket]
): TurnReport =
  ## Execute complete turn cycle and return results
  result = turn_executor.executeTurnCycle(state, commands)
  saveGame(state) # Auto-save after each turn

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

]#
