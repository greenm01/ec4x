## Intelligence Report Types
##
## Defines intelligence data structures for spy scout missions
import std/[tables, options]
import ./[core, tech]

type
  DetectionEventType* {.pure.} = enum
    CombatLoss, TravelIntercepted

  ScoutLossEvent* = object
    scoutFleetId*: FleetId  # Use FleetId, not string
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
    Visual, Scan, Spy, Perfect

  ColonyIntelReport* = object
    colonyId*: ColonyId  # Use ColonyId, not SystemId
    targetOwner*: HouseId
    gatheredTurn*: int32
    quality*: IntelQuality
    population*: int32
    industry*: int32
    defenses*: int32
    starbaseLevel*: int32
    constructionQueue*: seq[string]
    grossOutput*: Option[int32]
    taxRevenue*: Option[int32]
    unassignedSquadronCount*: int32
    reserveFleetCount*: int32
    mothballedFleetCount*: int32
    shipyardCount*: int32

  FleetIntel* = object
    fleetId*: FleetId
    owner*: HouseId
    location*: SystemId
    shipCount*: int32
    standingOrders*: Option[string]
    spaceLiftShipCount*: Option[int32]
    squadronIds*: seq[SquadronId]  # Store IDs, not details

  SquadronIntel* = object
    squadronId*: SquadronId  # Use typed ID
    shipClass*: string
    shipCount*: int32
    techLevel*: int32
    hullIntegrity*: Option[int32]

  SystemIntelReport* = object
    systemId*: SystemId
    gatheredTurn*: int32
    quality*: IntelQuality
    detectedFleetIds*: seq[FleetId]  # Store IDs, lookup details from FleetIntel

  StarbaseIntelReport* = object
    starbaseId*: StarbaseId  # Use typed ID
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

  CombatPhase* {.pure.} = enum
    Space, Orbital, Planetary

  CombatOutcome* {.pure.} = enum
    Victory, Defeat, Retreat, MutualRetreat, Ongoing

  FleetOrderIntel* = object
    orderType*: string
    targetSystem*: Option[SystemId]

  SpaceLiftCargoIntel* = object
    squadronId*: SquadronId  # Use typed ID
    shipClass*: string
    cargoType*: string
    quantity*: int32
    isCrippled*: bool

  CombatFleetComposition* = object
    fleetId*: FleetId
    owner*: HouseId
    standingOrders*: Option[FleetOrderIntel]
    squadronIds*: seq[SquadronId]  # Store IDs
    spaceLiftSquadronIds*: seq[SquadronId]
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
    alliedLosses*: seq[SquadronId]
    enemyLosses*: seq[string]  # Ship classes
    retreatedAllies*: seq[FleetId]
    retreatedEnemies*: seq[FleetId]
    survived*: bool

  ScoutEncounterType* {.pure.} = enum
    FleetSighting, ColonyDiscovered, Bombardment, Blockade,
    Combat, Construction, FleetMovement, DiplomaticActivity

  SensorQuality* {.pure.} = enum
    None, Visual, Scan, Perfect

  StarbaseSurveillanceReport* = object
    starbaseId*: StarbaseId
    systemId*: SystemId
    owner*: HouseId
    turn*: int32
    detectedFleets*: seq[tuple[fleetId: FleetId, location: SystemId, owner: HouseId, shipCount: int32]]
    undetectedFleets*: seq[FleetId]
    transitingFleets*: seq[tuple[fleetId: FleetId, fromSystem: SystemId, toSystem: SystemId]]
    combatDetected*: seq[SystemId]
    bombardmentDetected*: seq[SystemId]
    significantActivity*: bool
    threatsDetected*: int32

  ScoutEncounterReport* = object
    reportId*: string
    scoutFleetId*: FleetId
    turn*: int32
    systemId*: SystemId
    encounterType*: ScoutEncounterType
    observedHouses*: seq[HouseId]
    observedFleetIds*: seq[FleetId]
    colonyId*: Option[ColonyId]
    fleetMovements*: seq[tuple[fleetId: FleetId, fromSystem: Option[SystemId], toSystem: Option[SystemId]]]
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

  PopulationTransferStatus* {.pure.} = enum
    Initiated, InTransit, Delivered, Redirected, Failed

  PopulationTransferStatusReport* = object
    transferId*: PopulationTransferId
    turn*: int32
    status*: PopulationTransferStatus
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

  IntelligenceDatabase* = object
    houseId*: HouseId  # Back-reference
    colonyReports*: Table[ColonyId, ColonyIntelReport]
    systemReports*: Table[SystemId, SystemIntelReport]
    starbaseReports*: Table[StarbaseId, StarbaseIntelReport]
    espionageActivity*: seq[EspionageActivityReport]
    combatReports*: seq[CombatEncounterReport]
    scoutEncounters*: seq[ScoutEncounterReport]
    fleetMovementHistory*: Table[FleetId, FleetMovementHistory]
    constructionActivity*: Table[ColonyId, ConstructionActivityReport]
    starbaseSurveillance*: seq[StarbaseSurveillanceReport]
    populationTransferStatus*: Table[PopulationTransferId, PopulationTransferStatusReport]
