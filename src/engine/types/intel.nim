## Intelligence Report Types
##
## Defines intelligence data structures for spy scout missions
import std/[tables, options]
import ./[core, tech, combat]

type
  DetectionEventType* {.pure.} = enum
    CombatLoss
    TravelIntercepted

  ScoutLossEvent* = object
    scoutFleetId*: FleetId # Use FleetId, not string
    owner*: HouseId
    location*: SystemId
    detectorHouse*: HouseId
    eventType*: DetectionEventType
    turn*: int32

  DetectionResult* = object
    detected*: bool
    detectorHouse*: HouseId
    isAllyDetection*: bool
    roll*: int32
    threshold*: int32

  IntelQuality* {.pure.} = enum
    Visual   # Fleet-on-fleet encounters
    Scan     # View a World Fleet Command
    Spy      # Espionage events (e.g. intel theft )
    Perfect  # Scouts intel missions

  ColonyIntelReport* = object
    ## Ground/planetary intelligence + colony construction pipeline
    ## Gathered from SpyOnPlanet mission
    colonyId*: ColonyId
    targetOwner*: HouseId
    gatheredTurn*: int32
    quality*: IntelQuality
    population*: int32
    infrastructure*: int32 # Infrastructure level (0-10)
    spaceportCount*: int32 # Ground-to-orbit facilities (colony pipeline)
    armyCount*: int32 # Ground armies (colony pipeline)
    marineCount*: int32 # Marine units (colony pipeline)
    groundBatteryCount*: int32 # Planetary defense batteries (colony pipeline)
    planetaryShieldLevel*: int32 # Planetary shield strength (colony pipeline)
    colonyConstructionQueue*: seq[ConstructionProjectId] # Colony construction projects (Spy quality)
    spaceportDockQueue*: seq[ConstructionProjectId] # Ships being built at spaceport docks (Spy quality)
    grossOutput*: Option[int32] # Economic data (Spy quality)
    taxRevenue*: Option[int32] # Economic data (Spy quality)

  OrbitalIntelReport* = object
    ## Orbital/space intelligence (assets deployed in orbit)
    ## Gathered from approach/orbital missions
    ## Note: Fighters built via colony pipeline but deployed as orbital assets
    colonyId*: ColonyId
    targetOwner*: HouseId
    gatheredTurn*: int32
    quality*: IntelQuality
    starbaseCount*: int32 # Orbital stations
    shipyardCount*: int32 # Orbital construction (dock pipeline)
    drydockCount*: int32 # Orbital repair/refit (dock pipeline)
    reserveFleetCount*: int32 # Fleets in reserve status at this system
    mothballedFleetCount*: int32 # Fleets in mothballed status at this system
    guardFleetIds*: seq[FleetId] # Fleets with Guard orders for this colony
    blockadeFleetIds*: seq[FleetId] # Fleets with Blockade orders for this colony
    fighterIds*: seq[ShipId] # Fighters stationed at colony

  FleetIntel* = object
    fleetId*: FleetId
    owner*: HouseId
    location*: SystemId
    shipCount*: int32
    standingOrders*: Option[string]
    shipIds*: seq[ShipId] # Store IDs, not details

  ShipIntel* = object
    shipId*: ShipId # Use typed ID
    shipClass*: string
    techLevel*: int32
    hullIntegrity*: Option[int32]

  SystemIntelReport* = object
    systemId*: SystemId
    gatheredTurn*: int32
    quality*: IntelQuality
    detectedFleetIds*: seq[FleetId] # Store IDs, lookup details from FleetIntel

  SystemIntelPackage* = object
    ## Complete intelligence package from system surveillance
    ## Includes the system report plus detailed fleet/ship intel
    report*: SystemIntelReport
    fleetIntel*: seq[tuple[fleetId: FleetId, intel: FleetIntel]]
    shipIntel*: seq[tuple[shipId: ShipId, intel: ShipIntel]]

  StarbaseIntelReport* = object
    kastraId*: KastraId  # Defensive facility (Starbase)
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

  EspionageActivityReport* = object
    turn*: int32
    perpetrator*: HouseId
    action*: string
    targetSystem*: Option[SystemId]
    detected*: bool
    description*: string

  FleetOrderIntel* = object
    orderType*: string
    targetSystem*: Option[SystemId]

  SpaceLiftCargoIntel* = object
    shipId*: ShipId # Use typed ID
    shipClass*: string
    cargoType*: string
    quantity*: int32
    isCrippled*: bool

  CombatFleetComposition* = object
    fleetId*: FleetId
    owner*: HouseId
    standingOrders*: Option[FleetOrderIntel]
    shipIds*: seq[ShipId] # Store IDs
    isCloaked*: bool

  CombatEncounterReport* = object
    reportId*: string
    turn*: int32
    systemId*: SystemId
    phase*: CombatPhase
    reportingHouse*: HouseId
    alliedFleetIds*: seq[FleetId]
    enemyFleetIds*: seq[FleetId]
    outcome*: CombatOutcome
    alliedLosses*: seq[ShipId]
    enemyLosses*: seq[string] # Ship classes
    retreatedAllies*: seq[FleetId]
    retreatedEnemies*: seq[FleetId]
    survived*: bool

  BlockadeReport* = object
    reportId*: string
    turn*: int32
    systemId*: SystemId
    colonyId*: ColonyId
    status*: BlockadeStatus
    blockadingHouses*: seq[HouseId]
    blockadingFleetIds*: seq[FleetId]
    gcoReduction*: int32 # Actual percentage from config (e.g., 60)

  ScoutEncounterType* {.pure.} = enum
    FleetSighting
    ColonyDiscovered
    Bombardment
    Blockade
    Combat
    Construction
    FleetMovement
    DiplomaticActivity

  StarbaseSurveillanceReport* = object
    kastraId*: KastraId  # Defensive facility (Starbase)
    systemId*: SystemId
    owner*: HouseId
    turn*: int32
    detectedFleets*:
      seq[tuple[fleetId: FleetId, location: SystemId, owner: HouseId, shipCount: int32]]
    undetectedFleets*: seq[FleetId]
    transitingFleets*:
      seq[tuple[fleetId: FleetId, fromSystem: SystemId, toSystem: SystemId]]
    combatDetected*: seq[SystemId]
    bombardmentDetected*: seq[SystemId]
    significantActivity*: bool
    threatsDetected*: int32

  ScoutEncounterReport* = object
    reportId*: string
    fleetId*: FleetId
    turn*: int32
    systemId*: SystemId
    encounterType*: ScoutEncounterType
    observedHouses*: seq[HouseId]
    observedFleetIds*: seq[FleetId]
    colonyId*: Option[ColonyId]
    fleetMovements*: seq[
      tuple[fleetId: FleetId, fromSystem: Option[SystemId], toSystem: Option[SystemId]]
    ]
    description*: string
    significance*: int32

  FleetMovementHistory* = object
    fleetId*: FleetId
    owner*: HouseId
    sightings*: seq[tuple[turn: int32, systemId: SystemId]]
    patrolRoute*: Option[seq[SystemId]]
    lastKnownLocation*: SystemId
    lastSeen*: int32

  ConstructionActivityReport* = object
    colonyId*: ColonyId
    owner*: HouseId
    observedTurns*: seq[int32]
    infrastructureHistory*: seq[tuple[turn: int32, level: int32]]
    shipyardCount*: int32
    spaceportCount*: int32
    starbaseCount*: int32
    activeProjects*: seq[string]
    completedSinceLastVisit*: seq[string]

  PopulationTransferReportStatus* {.pure.} = enum
    ## Status for intel reports on population transfers
    ## (Different from population.TransferStatus which is internal state)
    Initiated
    InTransit
    Delivered
    Redirected
    Failed

  PopulationTransferStatusReport* = object
    ## Intelligence report on population transfer status
    transferId*: PopulationTransferId
    turn*: int32
    status*: PopulationTransferReportStatus
    sourceColony*: ColonyId
    intendedDestination*: ColonyId
    ptuAmount*: int32
    costPaid*: int32
    actualDestination*: Option[ColonyId]
    estimatedArrival*: Option[int32]
    redirectionReason*: Option[string]
    failureReason*: Option[string]
    travelRoute*: Option[seq[SystemId]]
    currentLocation*: Option[SystemId]

  IntelDatabase* = object
    houseId*: HouseId # Back-reference
    colonyReports*: Table[ColonyId, ColonyIntelReport]
    orbitalReports*: Table[ColonyId, OrbitalIntelReport]
    systemReports*: Table[SystemId, SystemIntelReport]
    starbaseReports*: Table[KastraId, StarbaseIntelReport]
    fleetIntel*: Table[FleetId, FleetIntel] # Detailed fleet intelligence
    shipIntel*: Table[ShipId, ShipIntel] # Detailed ship intelligence
    espionageActivity*: seq[EspionageActivityReport]
    combatReports*: seq[CombatEncounterReport]
    blockadeReports*: seq[BlockadeReport]
    scoutEncounters*: seq[ScoutEncounterReport]
    fleetMovementHistory*: Table[FleetId, FleetMovementHistory]
    constructionActivity*: Table[ColonyId, ConstructionActivityReport]
    starbaseSurveillance*: seq[StarbaseSurveillanceReport]
    populationTransferStatus*:
      Table[PopulationTransferId, PopulationTransferStatusReport]
