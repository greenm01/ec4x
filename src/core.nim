## EC4X Core Library
##
## This is the main module for the EC4X core library, providing all the
## fundamental game mechanics and data structures for the 4X strategy game.
##
## OFFLINE-FIRST DESIGN: This library has zero network dependencies.
## It implements complete gameplay for local/hotseat multiplayer.
## Network transport (Nostr) wraps around this core without modifying it.

import common/[hex, system]
import engine/[ship, fleet, starmap, gamestate, orders, resolve, combat, economy]

# Re-export all public types and procedures
# Note: types are re-exported through their respective modules (gamestate, fleet, etc.)
export hex, ship, system, fleet, starmap
export gamestate, orders, resolve, combat, economy

# Version information
const
  EC4X_VERSION* = "0.1.0"
  EC4X_AUTHOR* = "Mason Austin Green"

# Core game constants
const
  MIN_PLAYERS* = 2
  MAX_PLAYERS* = 12
  DEFAULT_PLAYERS* = 4
  HEX_DIRECTIONS* = 6

# Utility procedures
proc validatePlayerCount*(count: int): bool =
  ## Validate that the player count is within acceptable bounds
  count >= MIN_PLAYERS and count <= MAX_PLAYERS

proc createGame*(playerCount: int = DEFAULT_PLAYERS): StarMap =
  ## Create a new game with the specified number of players
  if not validatePlayerCount(playerCount):
    raise newException(ValueError, "Player count must be between " & $MIN_PLAYERS & " and " & $MAX_PLAYERS)

  result = starMap(playerCount)

# Game setup utilities
proc gameInfo*(): string =
  ## Get information about the EC4X game
  "EC4X v" & EC4X_VERSION & " by " & EC4X_AUTHOR & "\n" &
  "Asynchronous turn-based 4X wargame\n" &
  "Players: " & $MIN_PLAYERS & "-" & $MAX_PLAYERS
