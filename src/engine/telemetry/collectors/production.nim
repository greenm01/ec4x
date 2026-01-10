## @engine/telemetry/collectors/production.nim
##
## Collect production metrics from events and GameState.
## Covers: construction projects, repair, commissioning.

import std/options
import ../../types/[telemetry, core, game_state, event, production, colony, ship]
import ../../state/[engine, iterators]

proc collectProductionMetrics*(
    state: GameState, houseId: HouseId, prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  ## Collect production metrics from events and GameState
  result = prevMetrics # Start with previous metrics

  # Initialize counters for commissioning (event-driven)
  var shipsCommissionedThisTurn: int32 = 0
  var etacCommissionedThisTurn: int32 = 0
  var squadronsCommissionedThisTurn: int32 = 0

  # Process events from state.lastTurnEvents
  for event in state.lastTurnEvents:
    if event.houseId != some(houseId):
      continue

    case event.eventType
    of ShipCommissioned:
      shipsCommissionedThisTurn += 1
      # Detect ETAC from shipClass field
      if event.shipClass.isSome and event.shipClass.get() == ShipClass.ETAC:
        etacCommissionedThisTurn += 1
      squadronsCommissionedThisTurn += 1
    of RepairCompleted:
      # Track repairs completed (RepairCompleted event now emitted)
      discard
    of ConstructionStarted:
      # Track construction starts if needed
      discard
    else:
      discard

  result.shipsCommissionedThisTurn = shipsCommissionedThisTurn
  result.etacCommissionedThisTurn = etacCommissionedThisTurn
  result.squadronsCommissionedThisTurn = squadronsCommissionedThisTurn

  # Query GameState for current build queue
  var totalBuildQueueDepth: int32 = 0
  var etacInConstruction: int32 = 0
  var shipsUnderConstruction: int32 = 0
  var buildingsUnderConstruction: int32 = 0

  # Count construction projects from colonies (owner determines house)
  for colony in state.coloniesOwned(houseId):
    if colony.underConstruction.isSome:
      totalBuildQueueDepth += 1
      # Get the actual project to determine type
      let constructionId = colony.underConstruction.get()
      let projectOpt = state.constructionProject(constructionId)
      if projectOpt.isSome:
        let project = projectOpt.get()
        if project.projectType == BuildType.Ship:
          shipsUnderConstruction += 1
          if project.shipClass == some(ShipClass.ETAC):
            etacInConstruction += 1
        else:
          buildingsUnderConstruction += 1

    # Add queued projects
    totalBuildQueueDepth += colony.constructionQueue.len.int32
    for projectId in colony.constructionQueue:
      let projectOpt = state.constructionProject(projectId)
      if projectOpt.isSome:
        let project = projectOpt.get()
        if project.projectType == BuildType.Ship:
          shipsUnderConstruction += 1
          if project.shipClass.isSome and project.shipClass.get() == ShipClass.ETAC:
            etacInConstruction += 1
        else:
          buildingsUnderConstruction += 1

  result.totalBuildQueueDepth = totalBuildQueueDepth
  result.etacInConstruction = etacInConstruction
  result.shipsUnderConstruction = shipsUnderConstruction
  result.buildingsUnderConstruction = buildingsUnderConstruction
  
  # Note: Repair queue tracking could be added here when repair metrics are added to DiagnosticMetrics type
