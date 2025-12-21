## Player Visibility System (Fog of War)
##
## Filters game state to create player-specific views with limited visibility.

import std/[tables, options]
import ./[core, starmap, diplomacy, progression]

type
  VisibilityLevel* {.pure.} = enum
    None, Adjacent, Scouted, Occupied, Owned

  VisibleColony* = object
    colonyId*: ColonyId
    systemId*: SystemId
    owner*: HouseId
    # Full details (if owned)
    population*: Option[int32]
    infrastructure*: Option[int32]
    planetClass*: Option[PlanetClass]
    resources*: Option[ResourceRating]
    production*: Option[int32]
    # Intel report details (if enemy)
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
    fleetId*: FleetId
    owner*: HouseId
    location*: SystemId
    # Full details (if owned)
    isOwned*: bool  # If true, lookup full Fleet from game state
    # Limited intel (if enemy)
    intelTurn*: Option[int32]
    estimatedShipCount*: Option[int32]
    detectedInSystem*: Option[SystemId]

  VisibleSystem* = object
    systemId*: SystemId
    visibility*: VisibilityLevel
    lastScoutedTurn*: Option[int32]
    coordinates*: Option[tuple[q: int32, r: int32]]
    jumpLaneIds*: seq[SystemId]

  PlayerView* = object
    ## Game state filtered for a specific house's perspective
    ## This is what the AI/player "sees" - enforces fog of war
    viewingHouse*: HouseId
    turn*: int32
    
    # Own asset IDs (lookup full details from GameState)
    ownColonyIds*: seq[ColonyId]
    ownFleetIds*: seq[FleetId]
    
    # Visible systems
    visibleSystems*: Table[SystemId, VisibleSystem]
    
    # Visible enemy assets (filtered intel)
    visibleColonies*: seq[VisibleColony]
    visibleFleets*: seq[VisibleFleet]
    
    # Public information
    housePrestige*: Table[HouseId, int32]
    houseColonyCounts*: Table[HouseId, int32]
    diplomaticRelations*: Table[(HouseId, HouseId), DiplomaticState]
    eliminatedHouses*: seq[HouseId]
    actProgression*: ActProgressionState
