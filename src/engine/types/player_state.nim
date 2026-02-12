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
##
## Architecture Note:
## - Engine stores fog-of-war observations (what each house has seen, when)
## - Engine does NOT generate narrative reports (client responsibility)
## - Client generates human-readable reports from PlayerState deltas + GameEvents

import std/[tables, options]
import ./[core, colony, fleet, ship, diplomacy, progression, ground_unit, tech, facilities, starmap]

type
  # =============================================================================
  # Scout Detection Events
  # =============================================================================

  DetectionEventType* {.pure.} = enum
    CombatLoss
    TravelIntercepted

  ScoutLossEvent* = object
    scoutFleetId*: FleetId
    owner*: HouseId
    location*: SystemId
    detectorHouse*: HouseId
    eventType*: DetectionEventType
    turn*: int32

  # =============================================================================
  # Intel Quality and Observations (Fog-of-War Storage)
  # =============================================================================

  IntelQuality* {.pure.} = enum
    Visual # Fleet-on-fleet encounters
    Scan # View a World Fleet Command
    Perfect # Scout missions (full intel)

  ColonyObservation* = object
    ## What we observed about an enemy colony (fog-of-war data)
    ## Gathered from Scout missions
    colonyId*: ColonyId
    targetOwner*: HouseId
    gatheredTurn*: int32
    quality*: IntelQuality
    population*: int32
    infrastructure*: int32 # Infrastructure level (0-10)
    spaceportCount*: int32 # Ground-to-orbit facilities
    armyCount*: int32 # Ground armies
    marineCount*: int32 # Marine units
    groundBatteryCount*: int32 # Planetary defense batteries
    planetaryShieldLevel*: int32 # Planetary shield strength
    colonyConstructionQueue*: seq[ConstructionProjectId] # Perfect quality
    spaceportDockQueue*: seq[ConstructionProjectId] # Perfect quality
    grossOutput*: Option[int32] # Economic data (Perfect quality)
    taxRevenue*: Option[int32] # Economic data (Perfect quality)

  OrbitalObservation* = object
    ## What we observed about enemy orbital assets
    ## Gathered from approach/orbital missions
    colonyId*: ColonyId
    targetOwner*: HouseId
    gatheredTurn*: int32
    quality*: IntelQuality
    starbaseCount*: int32 # Orbital stations
    shipyardCount*: int32 # Orbital construction
    drydockCount*: int32 # Orbital repair/refit
    reserveFleetCount*: int32 # Fleets in reserve status
    mothballedFleetCount*: int32 # Fleets in mothballed status
    guardFleetIds*: seq[FleetId] # Fleets with Guard commands
    blockadeFleetIds*: seq[FleetId] # Fleets with Blockade commands
    fighterIds*: seq[ShipId] # Fighters stationed at colony

  FleetObservation* = object
    ## What we observed about an enemy fleet
    fleetId*: FleetId
    owner*: HouseId
    location*: SystemId
    shipCount*: int32
    shipIds*: seq[ShipId] # Store IDs, not details

  ShipObservation* = object
    ## What we observed about an enemy ship
    shipId*: ShipId
    shipClass*: string
    techLevel*: int32
    hullIntegrity*: Option[int32]

  SystemObservation* = object
    ## What we observed in an enemy system
    systemId*: SystemId
    gatheredTurn*: int32
    quality*: IntelQuality
    detectedFleetIds*: seq[FleetId] # Store IDs, lookup from FleetObservation

  SystemIntelPackage* = object
    ## Complete intelligence package from system surveillance
    ## Includes the system report plus detailed fleet/ship intel
    report*: SystemObservation
    fleetObservations*: seq[tuple[fleetId: FleetId, intel: FleetObservation]]
    shipObservations*: seq[tuple[shipId: ShipId, intel: ShipObservation]]

  StarbaseObservation* = object
    ## What we observed from HackStarbase missions (economic intel)
    kastraId*: KastraId # Defensive facility (Starbase)
    targetOwner*: HouseId
    gatheredTurn*: int32
    quality*: IntelQuality
    treasuryBalance*: Option[int32]
    grossIncome*: Option[int32]
    netIncome*: Option[int32]
    taxRate*: Option[float32]
    researchAllocations*: Option[tuple[erp: int32, srp: int32, trp: int32]]
    currentResearch*: Option[string]
    techLevels*: Option[TechLevel]

  IntelDatabase* = object
    ## Per-house fog-of-war storage
    ## Tracks what each house has observed about enemy assets
    houseId*: HouseId # Back-reference
    colonyObservations*: Table[ColonyId, ColonyObservation]
    orbitalObservations*: Table[ColonyId, OrbitalObservation]
    systemObservations*: Table[SystemId, SystemObservation]
    starbaseObservations*: Table[KastraId, StarbaseObservation]
    fleetObservations*: Table[FleetId, FleetObservation]
    shipObservations*: Table[ShipId, ShipObservation]

  # =============================================================================
  # Client-Facing Views (Generated per Turn, Sent to Client)
  # =============================================================================

  VisibilityLevel* {.pure.} = enum
    ## How much a house knows about a system
    None # Unexplored
    Adjacent # Knows it exists (adjacent to known system)
    Scouted # Visited by scout or fleet
    Occupied # Has fleet present
    Owned # Has colony

  VisibleSystem* = object
    ## System visibility from fog-of-war perspective
    systemId*: SystemId
    name*: string
    visibility*: VisibilityLevel
    lastScoutedTurn*: Option[int32]
    planetClass*: int32
    resourceRating*: int32
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
    # Ground assets
    estimatedArmies*: Option[int32]
    estimatedMarines*: Option[int32]
    estimatedBatteries*: Option[int32]
    estimatedShields*: Option[int32]
    # Orbital assets
    starbaseLevel*: Option[int32]
    spaceportCount*: Option[int32]
    shipyardCount*: Option[int32]
    drydockCount*: Option[int32]
    reserveFleetCount*: Option[int32]
    mothballedFleetCount*: Option[int32]

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
    homeworldSystemId*: Option[SystemId]
    treasuryBalance*: Option[int32]
    netIncome*: Option[int32]
    techLevels*: Option[TechLevel]
    researchPoints*: Option[ResearchPoints]

    # === Owned Assets (Full Entity Data) ===
    # Players get complete information about their own assets
    ownColonies*: seq[Colony]
    ownFleets*: seq[Fleet]
    ownShips*: seq[Ship]
    ownGroundUnits*: seq[GroundUnit]
    ownNeorias*: seq[Neoria]      # Production facilities
    ownKastras*: seq[Kastra]      # Defensive facilities (starbases)

    # === Visible Systems (Fog of War) ===
    visibleSystems*: Table[SystemId, VisibleSystem]

    # === Enemy Assets (Limited Intel) ===
    # Filtered based on detection and espionage
    visibleColonies*: seq[VisibleColony]
    visibleFleets*: seq[VisibleFleet]

    # === Intel Freshness (LTU) ===
    ltuSystems*: Table[SystemId, int32]
    ltuColonies*: Table[ColonyId, int32]
    ltuFleets*: Table[FleetId, int32]

    # === Public Information ===
    # Information visible to all players
    housePrestige*: Table[HouseId, int32]
    houseColonyCounts*: Table[HouseId, int32]
    houseNames*: Table[HouseId, string]
    diplomaticRelations*: Table[(HouseId, HouseId), DiplomaticState]
    eliminatedHouses*: seq[HouseId]
    actProgression*: ActProgressionState

    # === Starmap Topology (Universal Knowledge) ===
    jumpLanes*: seq[JumpLane]
