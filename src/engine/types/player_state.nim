## Player State System (Fog of War + Full Entity Data)
##
## Provides a complete, fog-of-war filtered view of the game state for a specific house.
## Unlike PlayerView (which only contained IDs), PlayerState contains full entity data
## for owned assets, enabling clients to execute zero-turn commands locally and
## allowing Claude to analyze game state directly from SQLite.
##
## Design:
## - Full entity data for owned assets (colonies, fleets, ships, etc.)
## - Filtered visibility for enemy assets (intel-based)
## - Persisted to SQLite for client retrieval
## - Used by zero-turn command system for client-side preview

import std/[tables, options]
import ./[core, colony, fleet, ship, diplomacy, progression, ground_unit]

type
  VisibilityLevel* {.pure.} = enum
    ## How much a house knows about a system
    None        # Unexplored
    Adjacent    # Knows it exists (adjacent to known system)
    Scouted     # Visited by scout or fleet
    Occupied    # Has fleet present
    Owned       # Has colony

  VisibleSystem* = object
    ## System visibility from fog-of-war perspective
    systemId*: SystemId
    visibility*: VisibilityLevel
    lastScoutedTurn*: Option[int32]
    coordinates*: Option[tuple[q: int32, r: int32]]
    jumpLaneIds*: seq[SystemId]

  VisibleColony* = object
    ## Enemy colony with limited intel
    colonyId*: ColonyId
    systemId*: SystemId
    owner*: HouseId
    # Intel report details (from spy operations)
    intelTurn*: Option[int32]
    estimatedPopulation*: Option[int32]
    estimatedIndustry*: Option[int32]
    estimatedDefenses*: Option[int32]
    starbaseLevel*: Option[int32]
    # Orbital defense intel
    unassignedSquadronCount*: Option[int32]
    reserveFleetCount*: Option[int32]
    mothballedFleetCount*: Option[int32]
    shipyardCount*: Option[int32]

  VisibleFleet* = object
    ## Enemy fleet with limited intel (detection-based)
    fleetId*: FleetId
    owner*: HouseId
    location*: SystemId
    # Limited intel (if detected)
    intelTurn*: Option[int32]
    estimatedShipCount*: Option[int32]
    detectedInSystem*: Option[SystemId]

  PlayerState* = object
    ## Complete game state view for a specific house
    ## Contains full entity data (not just IDs) for client-side operations
    viewingHouse*: HouseId
    turn*: int32

    # === Owned Assets (Full Entity Data) ===
    # Players get complete information about their own assets
    ownColonies*: seq[Colony]
    ownFleets*: seq[Fleet]
    ownShips*: seq[Ship]
    ownGroundUnits*: seq[GroundUnit]

    # === Visible Systems (Fog of War) ===
    visibleSystems*: Table[SystemId, VisibleSystem]

    # === Enemy Assets (Limited Intel) ===
    # Filtered based on detection and espionage
    visibleColonies*: seq[VisibleColony]
    visibleFleets*: seq[VisibleFleet]

    # === Public Information ===
    # Information visible to all players
    housePrestige*: Table[HouseId, int32]
    houseColonyCounts*: Table[HouseId, int32]
    diplomaticRelations*: Table[(HouseId, HouseId), DiplomaticState]
    eliminatedHouses*: seq[HouseId]
    actProgression*: ActProgressionState
