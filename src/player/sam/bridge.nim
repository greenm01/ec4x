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
    colonyId: int,
    systemId: int,
    systemName: string,
    sectorLabel: string = "",
    planetClass: int = 0,
    populationUnits: int = 0,
    industrialUnits: int = 0,
    grossOutput: int = 0,
    netValue: int = 0,
    populationGrowthPu: Option[float32] = none(float32),
    constructionDockAvailable: int = 0,
    constructionDockTotal: int = 0,
    repairDockAvailable: int = 0,
    repairDockTotal: int = 0,
    blockaded: bool = false,
    idleConstruction: bool = false,
    owner: int = 0,
): ColonyInfo =
  ## Convert colony data to SAM ColonyInfo
  ColonyInfo(
    colonyId: colonyId,
    systemId: systemId,
    systemName: systemName,
    sectorLabel: sectorLabel,
    planetClass: planetClass,
    populationUnits: populationUnits,
    industrialUnits: industrialUnits,
    grossOutput: grossOutput,
    netValue: netValue,
    populationGrowthPu: populationGrowthPu,
    constructionDockAvailable: constructionDockAvailable,
    constructionDockTotal: constructionDockTotal,
    repairDockAvailable: repairDockAvailable,
    repairDockTotal: repairDockTotal,
    blockaded: blockaded,
    idleConstruction: idleConstruction,
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
    sectorLabel: "?",
    shipCount: shipCount,
    owner: owner,
    command: 0,
    commandLabel: "Hold",
    isIdle: true,
    roe: 0,
    attackStrength: 0,
    defenseStrength: 0,
    statusLabel: "Active",
    destinationLabel: "-",
    destinationSystemId: 0,
    eta: 0,
    hasCrippled: false,
    hasCombatShips: false,
    hasSupportShips: false,
    hasScouts: false,
    hasTroopTransports: false,
    hasEtacs: false,
    isScoutOnly: false,
    seekHomeTarget: none(int),
    needsAttention: false,
  )
