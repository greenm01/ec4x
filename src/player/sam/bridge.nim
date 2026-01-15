## SAM Bridge - Integration between SAM model and game engine
##
## This module provides the bridge between:
## - The SAM TuiModel (view layer, decoupled)
## - The engine GameState (domain layer)
##
## It handles:
## - Syncing game state to TuiModel
## - Converting game actions back to engine operations
## - Maintaining fog-of-war view consistency

import std/[options, tables]
import ./tui_model

# Forward declarations for engine types (to avoid circular imports)
# The actual integration will use these types from the engine

type
  # Placeholder for engine types - actual imports handled by calling code
  GameStateRef* = ref object
    ## Reference to engine game state (placeholder)
    turn*: int
  
  HouseIdRef* = distinct int
    ## House identifier (placeholder)

# ============================================================================
# Sync Game State to TUI Model
# ============================================================================

proc syncFromGameState*(model: var TuiModel, 
                        systems: Table[HexCoord, SystemInfo],
                        colonies: seq[ColonyInfo],
                        fleets: seq[FleetInfo],
                        turn: int,
                        houseName: string,
                        treasury: int,
                        prestige: int,
                        homeworld: Option[HexCoord],
                        maxRing: int) =
  ## Sync game state data into the TUI model
  ## This is called after game state changes (e.g., turn processing)
  model.systems = systems
  model.colonies = colonies
  model.fleets = fleets
  model.turn = turn
  model.houseName = houseName
  model.treasury = treasury
  model.prestige = prestige
  model.homeworld = homeworld
  model.maxRing = maxRing

proc updateTerminalSize*(model: var TuiModel, width, height: int) =
  ## Update terminal dimensions in model
  model.termWidth = width
  model.termHeight = height

# ============================================================================
# Convert Existing Adapters Data to SAM Model
# ============================================================================

# These procs convert from existing adapter types to SAM model types
# They can be used when integrating with the existing adapters.nim

proc toSamSystemInfo*(
  id: int,
  name: string,
  q, r: int,
  ring: int,
  planetClass: int,
  resourceRating: int,
  owner: Option[int],
  isHomeworld: bool,
  isHub: bool,
  fleetCount: int
): SystemInfo =
  ## Convert individual system data to SAM SystemInfo
  SystemInfo(
    id: id,
    name: name,
    coords: (q, r),
    ring: ring,
    planetClass: planetClass,
    resourceRating: resourceRating,
    owner: owner,
    isHomeworld: isHomeworld,
    isHub: isHub,
    fleetCount: fleetCount
  )

proc toSamColonyInfo*(
  systemId: int,
  systemName: string,
  population: int,
  production: int,
  owner: int
): ColonyInfo =
  ## Convert colony data to SAM ColonyInfo
  ColonyInfo(
    systemId: systemId,
    systemName: systemName,
    population: population,
    production: production,
    owner: owner
  )

proc toSamFleetInfo*(
  id: int,
  location: int,
  locationName: string,
  shipCount: int,
  owner: int
): FleetInfo =
  ## Convert fleet data to SAM FleetInfo
  FleetInfo(
    id: id,
    location: location,
    locationName: locationName,
    shipCount: shipCount,
    owner: owner
  )
