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
  result.populationTransferStatus = initTable[string, PopulationTransferStatusReport]()

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

proc addPopulationTransferStatus*(db: var IntelligenceDatabase, report: PopulationTransferStatusReport) =
  ## Add or update Space Guild population transfer status report
  ## Only for YOUR OWN house's transfers - Guild maintains client confidentiality
  db.populationTransferStatus[report.transferId] = report

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
  # Future enhancement: Analyze history.visitedSystems for recurring patterns

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
