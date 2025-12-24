## @entities/project_ops.nim
##
## Write API for managing ConstructionProject and RepairProject entities.
## Ensures that `byColony` and `byFacility` indexes are kept consistent
## as projects are queued, started, and completed.

import std/[options, tables, sequtils]
import ../state/[game_state as gs_helpers, id_gen, entity_manager]
import ../types/[core, game_state, production, facilities, colony]

# --- Construction Projects ---

proc queueConstructionProject*(
    state: var GameState, colonyId: ColonyId, project: var ConstructionProject
): ConstructionProject =
  ## Queues a new construction project, adding it to all relevant collections and indexes.
  let projectId = state.generateConstructionProjectId()
  project.id = projectId
  project.colonyId = colonyId

  state.constructionProjects.entities.addEntity(projectId, project)
  state.constructionProjects.byColony.mgetOrPut(colonyId, @[]).add(projectId)

  if project.facilityId.isSome and project.facilityType.isSome:
    let facilityId = project.facilityId.get()
    let facilityType = project.facilityType.get()
    state.constructionProjects.byFacility.mgetOrPut((facilityType, facilityId), @[]).add(
      projectId
    )
    case facilityType
    of FacilityType.Spaceport:
      var spaceport = gs_helpers.getSpaceport(state, SpaceportId(facilityId)).get()
      spaceport.constructionQueue.add(projectId)
      state.spaceports.entities.updateEntity(SpaceportId(facilityId), spaceport)
    of FacilityType.Shipyard:
      var shipyard = gs_helpers.getShipyard(state, ShipyardId(facilityId)).get()
      shipyard.constructionQueue.add(projectId)
      state.shipyards.entities.updateEntity(ShipyardId(facilityId), shipyard)
    else:
      discard
  else:
    var colony = gs_helpers.getColony(state, colonyId).get()
    colony.constructionQueue.add(projectId)
    state.colonies.entities.updateEntity(colonyId, colony)

  return project

proc completeConstructionProject*(
    state: var GameState, projectId: ConstructionProjectId
) =
  ## Completes a construction project, removing it from active queues and indexes.
  let projectOpt = gs_helpers.getConstructionProject(state, projectId)
  if projectOpt.isNone:
    return
  let project = projectOpt.get()

  if state.constructionProjects.byColony.contains(project.colonyId):
    state.constructionProjects.byColony[project.colonyId].keepIf(
      proc(id: ConstructionProjectId): bool =
        id != projectId
    )

  if project.facilityId.isSome and project.facilityType.isSome:
    let facilityId = project.facilityId.get()
    let facilityType = project.facilityType.get()
    let key = (facilityType, facilityId)
    if state.constructionProjects.byFacility.contains(key):
      state.constructionProjects.byFacility[key].keepIf(
        proc(id: ConstructionProjectId): bool =
          id != projectId
      )

    case facilityType
    of FacilityType.Spaceport:
      var spaceport = gs_helpers.getSpaceport(state, SpaceportId(facilityId)).get()
      spaceport.activeConstructions.keepIf(
        proc(id: ConstructionProjectId): bool =
          id != projectId
      )
      state.spaceports.entities.updateEntity(SpaceportId(facilityId), spaceport)
    of FacilityType.Shipyard:
      var shipyard = gs_helpers.getShipyard(state, ShipyardId(facilityId)).get()
      shipyard.activeConstructions.keepIf(
        proc(id: ConstructionProjectId): bool =
          id != projectId
      )
      state.shipyards.entities.updateEntity(ShipyardId(facilityId), shipyard)
    else:
      discard
  else:
    var colony = gs_helpers.getColony(state, project.colonyId).get()
    if colony.underConstruction.isSome and colony.underConstruction.get() == projectId:
      colony.underConstruction = none(ConstructionProjectId)
      state.colonies.entities.updateEntity(colony.id, colony)

  state.constructionProjects.entities.removeEntity(projectId)

# --- Repair Projects ---

proc queueRepairProject*(
    state: var GameState, colonyId: ColonyId, project: var RepairProject
): RepairProject =
  let projectId = state.generateRepairProjectId()
  project.id = projectId
  project.colonyId = colonyId

  state.repairProjects.entities.addEntity(projectId, project)
  state.repairProjects.byColony.mgetOrPut(colonyId, @[]).add(projectId)

  if project.facilityId.isSome:
    let facilityId = project.facilityId.get()
    let facilityType = project.facilityType
    state.repairProjects.byFacility.mgetOrPut((facilityType, facilityId), @[]).add(
      projectId
    )

    case facilityType
    of FacilityType.Drydock:
      var drydock = gs_helpers.getDrydock(state, DrydockId(facilityId)).get()
      drydock.repairQueue.add(projectId)
      state.drydocks.entities.updateEntity(DrydockId(facilityId), drydock)
    else:
      discard

  return project

proc completeRepairProject*(state: var GameState, projectId: RepairProjectId) =
  let projectOpt = gs_helpers.getRepairProject(state, projectId)
  if projectOpt.isNone:
    return
  let project = projectOpt.get()

  if state.repairProjects.byColony.contains(project.colonyId):
    state.repairProjects.byColony[project.colonyId].keepIf(
      proc(id: RepairProjectId): bool =
        id != projectId
    )

  if project.facilityId.isSome:
    let facilityId = project.facilityId.get()
    let facilityType = project.facilityType
    let key = (facilityType, facilityId)
    if state.repairProjects.byFacility.contains(key):
      state.repairProjects.byFacility[key].keepIf(
        proc(id: RepairProjectId): bool =
          id != projectId
      )

    case facilityType
    of FacilityType.Drydock:
      var drydock = gs_helpers.getDrydock(state, DrydockId(facilityId)).get()
      drydock.activeRepairs.keepIf(
        proc(id: RepairProjectId): bool =
          id != projectId
      )
      state.drydocks.entities.updateEntity(DrydockId(facilityId), drydock)
    else:
      discard

  state.repairProjects.entities.removeEntity(projectId)
