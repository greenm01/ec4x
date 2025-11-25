## Intelligence Report Types
##
## Defines intelligence data structures for spy scout missions
## Per intel.md and operations.md specifications

import std/[tables, options]
import ../../common/types/[core, tech]

type
  IntelQuality* {.pure.} = enum
    ## Quality/source of intelligence
    Visual     # Visual detection from fleet presence
    Scan       # Active sensor scan (future)
    Spy        # Espionage operation
    Perfect    # Owned/current information

  ColonyIntelReport* = object
    ## Intelligence on an enemy colony (SpyOnPlanet mission)
    ## Per intel.md:107-121
    colonyId*: SystemId
    targetOwner*: HouseId        # Owner of the colony
    gatheredTurn*: int           # When intel was gathered
    quality*: IntelQuality

    # Colony stats (what was observed)
    population*: int
    industry*: int               # IU count
    defenses*: int               # Ground unit count
    starbaseLevel*: int          # 0 if no starbase
    constructionQueue*: seq[string]  # Item IDs in construction (if successful spy)

    # Economic intelligence (Spy quality or higher)
    grossOutput*: Option[int]    # GCO (Gross Colonial Output)
    taxRevenue*: Option[int]     # NCV (Net Colonial Value) after tax

    # Orbital defenses (visible when approaching colony for orbital missions)
    unassignedSquadronCount*: int    # Combat squadrons at colony not in fleets
    reserveFleetCount*: int          # Reserve fleets at colony (visible, half AS/DS)
    mothballedFleetCount*: int       # Mothballed fleets (offline but visible)
    shipyardCount*: int              # Space-based construction facilities (NOT spaceports)

  SystemIntelReport* = object
    ## Intelligence on enemy fleets in a system (SpyOnSystem mission)
    ## Per intel.md:96-105
    systemId*: SystemId
    gatheredTurn*: int
    quality*: IntelQuality

    # Fleet information
    detectedFleets*: seq[FleetIntel]

  FleetIntel* = object
    ## Intel on a specific fleet
    fleetId*: FleetId
    owner*: HouseId
    location*: SystemId
    shipCount*: int
    # Detailed composition (only if quality = Spy or Perfect)
    squadronDetails*: Option[seq[SquadronIntel]]

  SquadronIntel* = object
    ## Detailed squadron information
    squadronId*: string
    shipClass*: string  # Ship class name
    shipCount*: int
    techLevel*: int
    hullIntegrity*: Option[int]  # % if known

  StarbaseIntelReport* = object
    ## Intelligence from hacking a starbase (HackStarbase mission)
    ## Per intel.md and operations.md:6.2.11 - "economic and R&D intelligence"
    systemId*: SystemId
    targetOwner*: HouseId
    gatheredTurn*: int
    quality*: IntelQuality

    # Economic intelligence
    treasuryBalance*: Option[int]       # PP balance
    grossIncome*: Option[int]           # Gross PP/turn
    netIncome*: Option[int]             # Net PP/turn
    taxRate*: Option[float]             # Current tax rate

    # R&D intelligence
    researchAllocations*: Option[tuple[erp: int, srp: int, trp: int]]
    currentResearch*: Option[string]    # Current tech being researched
    techLevels*: Option[TechLevel]      # Current tech levels

  EspionageActivityReport* = object
    ## Record of detected espionage activity against this house
    ## Generated when espionage attempts are detected
    turn*: int
    perpetrator*: HouseId
    action*: string           # Action type description
    targetSystem*: Option[SystemId]  # If targeted specific system
    detected*: bool           # Was the perpetrator identified?
    description*: string

  CombatPhase* {.pure.} = enum
    ## Phase of combat where encounter occurred
    Space,      # Space combat (mobile fleets)
    Orbital,    # Orbital combat (guard fleets, unassigned squadrons, starbases)
    Planetary   # Planetary invasion

  CombatOutcome* {.pure.} = enum
    ## Outcome of combat from reporter's perspective
    Victory,       # Defeated enemy
    Defeat,        # Defeated by enemy
    Retreat,       # Tactical retreat
    MutualRetreat, # Both sides retreated
    Ongoing        # Combat continues (for pre-combat reports)

  FleetOrderIntel* = object
    ## Intelligence on enemy fleet's standing orders
    orderType*: string        # Order type name (e.g., "Patrol", "GuardPlanet")
    targetSystem*: Option[SystemId]  # Target system if applicable

  SpaceLiftCargoIntel* = object
    ## Intelligence on spacelift ship cargo (troop transports, ETACs)
    shipClass*: string        # ETAC or TroopTransport
    cargoType*: string        # Marines, Colonists, Supplies, or Empty
    quantity*: int            # How many units loaded (0 = empty)
    isCrippled*: bool         # Ship damage status

  CombatFleetComposition* = object
    ## Detailed fleet composition observed in combat
    fleetId*: FleetId
    owner*: HouseId
    standingOrders*: Option[FleetOrderIntel]  # Fleet's orders (if observed)
    squadrons*: seq[SquadronIntel]  # All squadrons in fleet
    spaceLiftShips*: seq[SpaceLiftCargoIntel]  # Transport ships with cargo details
    isCloaked*: bool                # Was fleet cloaked (if detected)

  CombatEncounterReport* = object
    ## Intelligence report from combat encounter
    ## Generated automatically when fleets engage in combat
    ## Surviving ships report detailed composition and outcome
    reportId*: string         # Unique report ID
    turn*: int                # Turn when combat occurred
    systemId*: SystemId       # Where combat occurred
    phase*: CombatPhase       # Space, Orbital, or Planetary
    reportingHouse*: HouseId  # House that generated this report

    # Pre-combat intelligence (always available)
    alliedForces*: seq[CombatFleetComposition]  # Own forces in combat
    enemyForces*: seq[CombatFleetComposition]   # Enemy forces observed

    # Post-combat intelligence (only if survivors)
    outcome*: CombatOutcome      # Battle outcome
    alliedLosses*: seq[string]   # Lost squadron IDs
    enemyLosses*: seq[string]    # Observed enemy losses (ship classes)
    retreatedAllies*: seq[FleetId]   # Own fleets that retreated
    retreatedEnemies*: seq[FleetId]  # Enemy fleets that retreated (if observed)
    survived*: bool              # Did reporting fleet survive?

  ScoutEncounterType* {.pure.} = enum
    ## Type of encounter a scout observed
    FleetSighting,       # Enemy fleet observed
    ColonyDiscovered,    # New colony found
    Bombardment,         # Witnessed bombardment
    Blockade,            # Blockade established/ongoing
    Combat,              # Witnessed combat between other forces
    Construction,        # Construction activity observed
    FleetMovement,       # Fleet movement pattern detected
    DiplomaticActivity   # Diplomatic event observed (pacts, war declarations)

  SensorQuality* {.pure.} = enum
    ## Quality of sensor detection
    None,           # Not detected
    Visual,         # Basic visual detection
    Scan,           # Active sensor scan (starbase level)
    Perfect         # Perfect knowledge (own assets)

  StarbaseSurveillanceReport* = object
    ## Continuous surveillance from starbase advanced sensors
    ## Starbases monitor their sector (system + adjacent systems) automatically
    ## Only scouts and cloaked raiders can evade detection (stealth roll required)
    starbaseId*: string
    systemId*: SystemId           # Starbase location
    owner*: HouseId               # Starbase owner
    turn*: int                    # Surveillance turn

    # Detected activity in this system and adjacent systems
    detectedFleets*: seq[tuple[fleetId: FleetId, location: SystemId, owner: HouseId, shipCount: int]]
    undetectedFleets*: seq[FleetId]  # Fleets that passed stealth check (for internal tracking)

    # System activity
    transitingFleets*: seq[tuple[fleetId: FleetId, fromSystem: SystemId, toSystem: SystemId]]
    combatDetected*: seq[SystemId]    # Systems where combat occurred
    bombardmentDetected*: seq[SystemId]  # Systems under bombardment

    # Threat assessment
    significantActivity*: bool        # Major fleet movements or combat
    threatsDetected*: int            # Count of enemy fleets detected

  ScoutEncounterReport* = object
    ## Detailed report from scout reconnaissance
    ## Scouts generate these for EVERYTHING they observe
    reportId*: string
    scoutId*: string              # Which scout made the observation
    turn*: int
    systemId*: SystemId
    encounterType*: ScoutEncounterType

    # What was observed (depending on encounter type)
    observedHouses*: seq[HouseId]  # All houses involved
    fleetDetails*: seq[FleetIntel] # Detailed fleet composition
    colonyDetails*: Option[ColonyIntelReport]  # Colony details if applicable

    # Movement intelligence
    fleetMovements*: seq[tuple[fleetId: FleetId, fromSystem: Option[SystemId], toSystem: Option[SystemId]]]

    # Activity description
    description*: string          # Human-readable description
    significance*: int            # 1-10 importance rating

  FleetMovementHistory* = object
    ## Historical tracking of fleet movements
    ## Built up from multiple scout sightings
    fleetId*: FleetId
    owner*: HouseId
    sightings*: seq[tuple[turn: int, systemId: SystemId]]  # Chronological sightings
    patrolRoute*: Option[seq[SystemId]]  # Detected patrol pattern
    lastKnownLocation*: SystemId
    lastSeen*: int

  ConstructionActivityReport* = object
    ## Track construction progress at enemy colonies over time
    systemId*: SystemId
    owner*: HouseId
    observedTurns*: seq[int]      # When scouts visited

    # Construction tracking
    infrastructureHistory*: seq[tuple[turn: int, level: int]]
    shipyardCount*: int           # Current count
    spaceportCount*: int          # Current count
    starbaseCount*: int           # Current count

    # Active projects observed
    activeProjects*: seq[string]  # Item IDs being built
    completedSinceLastVisit*: seq[string]  # What was completed

  IntelligenceDatabase* = object
    ## Collection of all intelligence reports for a house
    ## Stored per-house in GameState
    colonyReports*: Table[SystemId, ColonyIntelReport]
    systemReports*: Table[SystemId, SystemIntelReport]
    starbaseReports*: Table[SystemId, StarbaseIntelReport]
    espionageActivity*: seq[EspionageActivityReport]  # Log of espionage against this house
    combatReports*: seq[CombatEncounterReport]        # Combat encounter reports (chronological)

    # Enhanced scout intelligence
    scoutEncounters*: seq[ScoutEncounterReport]       # All scout observations
    fleetMovementHistory*: Table[FleetId, FleetMovementHistory]  # Track fleet movements
    constructionActivity*: Table[SystemId, ConstructionActivityReport]  # Track construction

    # Starbase surveillance
    starbaseSurveillance*: seq[StarbaseSurveillanceReport]  # Automated starbase sensor reports

proc newIntelligenceDatabase*(): IntelligenceDatabase =
  ## Create empty intelligence database
  result.colonyReports = initTable[SystemId, ColonyIntelReport]()
  result.systemReports = initTable[SystemId, SystemIntelReport]()
  result.starbaseReports = initTable[SystemId, StarbaseIntelReport]()
  result.espionageActivity = @[]
  result.combatReports = @[]
  result.scoutEncounters = @[]
  result.fleetMovementHistory = initTable[FleetId, FleetMovementHistory]()
  result.constructionActivity = initTable[SystemId, ConstructionActivityReport]()
  result.starbaseSurveillance = @[]

proc addColonyReport*(db: var IntelligenceDatabase, report: ColonyIntelReport) =
  ## Add or update colony intelligence report
  db.colonyReports[report.colonyId] = report

proc addSystemReport*(db: var IntelligenceDatabase, report: SystemIntelReport) =
  ## Add or update system intelligence report
  db.systemReports[report.systemId] = report

proc addStarbaseReport*(db: var IntelligenceDatabase, report: StarbaseIntelReport) =
  ## Add or update starbase intelligence report
  db.starbaseReports[report.systemId] = report

proc addEspionageActivity*(db: var IntelligenceDatabase, report: EspionageActivityReport) =
  ## Add espionage activity report to log
  db.espionageActivity.add(report)

proc addCombatReport*(db: var IntelligenceDatabase, report: CombatEncounterReport) =
  ## Add combat encounter report to chronological log
  db.combatReports.add(report)

proc addScoutEncounter*(db: var IntelligenceDatabase, report: ScoutEncounterReport) =
  ## Add scout encounter report to intelligence log
  db.scoutEncounters.add(report)

proc addStarbaseSurveillance*(db: var IntelligenceDatabase, report: StarbaseSurveillanceReport) =
  ## Add starbase surveillance report
  db.starbaseSurveillance.add(report)

proc updateFleetMovementHistory*(db: var IntelligenceDatabase, fleetId: FleetId, owner: HouseId, systemId: SystemId, turn: int) =
  ## Update fleet movement tracking with new sighting
  if fleetId notin db.fleetMovementHistory:
    db.fleetMovementHistory[fleetId] = FleetMovementHistory(
      fleetId: fleetId,
      owner: owner,
      sightings: @[],
      patrolRoute: none(seq[SystemId]),
      lastKnownLocation: systemId,
      lastSeen: turn
    )

  var history = db.fleetMovementHistory[fleetId]
  history.sightings.add((turn, systemId))
  history.lastKnownLocation = systemId
  history.lastSeen = turn

  # Detect patrol patterns (if fleet visits same systems repeatedly)
  # TODO: Pattern detection algorithm

  db.fleetMovementHistory[fleetId] = history

proc updateConstructionActivity*(db: var IntelligenceDatabase, systemId: SystemId, owner: HouseId, turn: int,
                                 infrastructure: int, shipyards: int, spaceports: int, starbases: int,
                                 activeProjects: seq[string]) =
  ## Update construction activity tracking for a colony
  if systemId notin db.constructionActivity:
    db.constructionActivity[systemId] = ConstructionActivityReport(
      systemId: systemId,
      owner: owner,
      observedTurns: @[],
      infrastructureHistory: @[],
      shipyardCount: shipyards,
      spaceportCount: spaceports,
      starbaseCount: starbases,
      activeProjects: activeProjects,
      completedSinceLastVisit: @[]
    )

  var activity = db.constructionActivity[systemId]

  # Detect completed projects (were in activeProjects before, not anymore)
  var completed: seq[string] = @[]
  for oldProject in activity.activeProjects:
    if oldProject notin activeProjects:
      completed.add(oldProject)

  activity.observedTurns.add(turn)
  activity.infrastructureHistory.add((turn, infrastructure))
  activity.shipyardCount = shipyards
  activity.spaceportCount = spaceports
  activity.starbaseCount = starbases
  activity.activeProjects = activeProjects
  activity.completedSinceLastVisit = completed

  db.constructionActivity[systemId] = activity

proc getColonyIntel*(db: IntelligenceDatabase, systemId: SystemId): Option[ColonyIntelReport] =
  ## Retrieve colony intel if available
  if systemId in db.colonyReports:
    return some(db.colonyReports[systemId])
  return none(ColonyIntelReport)

proc getSystemIntel*(db: IntelligenceDatabase, systemId: SystemId): Option[SystemIntelReport] =
  ## Retrieve system intel if available
  if systemId in db.systemReports:
    return some(db.systemReports[systemId])
  return none(SystemIntelReport)

proc getStarbaseIntel*(db: IntelligenceDatabase, systemId: SystemId): Option[StarbaseIntelReport] =
  ## Retrieve starbase intel if available
  if systemId in db.starbaseReports:
    return some(db.starbaseReports[systemId])
  return none(StarbaseIntelReport)

proc getIntelStaleness*(report: ColonyIntelReport | SystemIntelReport | StarbaseIntelReport, currentTurn: int): int =
  ## Calculate how many turns old this intel is
  return currentTurn - report.gatheredTurn
