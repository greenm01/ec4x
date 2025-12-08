## EC4X Core Library
##
## This is the main module for the EC4X core library, providing all the
## fundamental game mechanics and data structures for the 4X strategy game.
##
## OFFLINE-FIRST DESIGN: This library has zero network dependencies.
## It implements complete gameplay for local/hotseat multiplayer.
## Network transport (Nostr) wraps around this core without modifying it.

import common/[hex, system]
import engine/[ship, squadron, fleet, spacelift, starmap, gamestate, orders, resolve]
import engine/resolution/event_factory/init as event_factory

# Re-export all public types and procedures
# Note: types are re-exported through their respective modules (gamestate, fleet, etc.)
export hex, ship, squadron, spacelift, system, fleet, starmap
export gamestate, orders, resolve
export event_factory
# Note: Combat system available via engine/combat/ submodules when needed

# Version information
const
  ec4xVersion* = "0.1.0"
  ec4xAuthor* = "Mason Austin Green"

# Core game constants
const
  minPlayers* = 2
  maxPlayers* = 12
  defaultPlayers* = 4
  hexDirections* = 6

# Utility procedures
proc validatePlayerCount*(count: int): bool =
  ## Validate that the player count is within acceptable bounds
  count >= minPlayers and count <= maxPlayers

proc createGame*(playerCount: int = defaultPlayers): StarMap =
  ## Create a new game with the specified number of players
  if not validatePlayerCount(playerCount):
    raise newException(ValueError, "Player count must be between " & $minPlayers & " and " & $maxPlayers)

  result = starMap(playerCount)

# Game setup utilities
proc gameInfo*(): string =
  ## Get information about the EC4X game
  "EC4X v" & ec4xVersion & " by " & ec4xAuthor & "\n" &
  "Asynchronous turn-based 4X wargame\n" &
  "Players: " & $minPlayers & "-" & $maxPlayers
