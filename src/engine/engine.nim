## EC4X Game Engine
## Public API for game initialization, turn processing, and state queries
import std/[random, tables]
import types/[core, game_state, command, player_state]
import init/game_state
import turn_cycle/engine

# Re-export core types from types/game_state (imported via init/game_state)
export GameState
export command.CommandPacket
export player_state.PlayerState

# Game lifecycle
proc newGame*(
  scenarioPath: string = "scenarios/standard-4-player.kdl",
  gameName: string = "",
  gameDescription: string = "",
  dataDir: string = "data"
): GameState =
  ## Initialize a new game
  ##
  ## Args:
  ##   scenarioPath: Path to scenario KDL file (default: scenarios/standard-4-player.kdl)
  ##   gameName: Human-readable game name (default: use scenarioName from config)
  ##   gameDescription: Optional game description for admin notes
  ##   dataDir: Root directory for per-game databases
  result = initGameState(scenarioPath, gameName, gameDescription, "config", dataDir)

# Turn execution
proc resolve*(
    state: GameState, commands: Table[HouseId, CommandPacket], rng: var Rand
): TurnResult =
  ## Execute complete turn cycle and return results
  result = resolveTurn(state, commands, rng)
  # Note: Auto-save commented out - implement when persistence layer is ready
  # saveGame(state)
