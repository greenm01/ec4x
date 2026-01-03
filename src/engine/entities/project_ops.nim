## @entities/project_ops.nim
##
## Write API for managing ConstructionProject and RepairProject entities.
## Ensures that `byColony` and `byFacility` indexes are kept consistent
## as projects are queued, started, and completed.

import std/[options, tables, sequtils]
import ../state/[engine, id_gen]
import ../types/[core, game_state, production, facilities, colony]

# --- Construction Projects ---

proc newConstructionProject*(
    id: ConstructionProjectId,
    colonyId: ColonyId,
    projectType: BuildType,
    itemId: string,
    costTotal: int32,
    costPaid: int32,
    turnsRemaining: int32,
    neoriaId: Option[NeoriaId] = none(NeoriaId),
): ConstructionProject =
  ## Create a new construction project value
  ## Use this when you need a ConstructionProject value without state mutations
  ConstructionProject(
    id: id,
    colonyId: colonyId,
    projectType: projectType,
    itemId: itemId,
    costTotal: costTotal,
    costPaid: costPaid,
    turnsRemaining: turnsRemaining,
    neoriaId: neoriaId,
  )

proc queueConstructionProject*(
    state: var GameState, colonyId: ColonyId, project: var ConstructionProject
): ConstructionProject =
  ## Queues a new construction project, adding it to all relevant collections and indexes.
  let projectId = state.generateConstructionProjectId()
  project.id = projectId
  project.colonyId = colonyId

  state.addConstructionProject(projectId, project)
  state.constructionProjects.byColony.mgetOrPut(colonyId, @[]).add(projectId)

  # NEW: Use typed NeoriaId directly - no more uint32 conversions!
  if project.neoriaId.isSome:
    let neoriaId = project.neoriaId.get()
    state.constructionProjects.byNeoria.mgetOrPut(neoriaId, @[]).add(projectId)

    var neoria = state.neoria(neoriaId).get()
    neoria.constructionQueue.add(projectId)
    state.updateNeoria(neoriaId, neoria)
  # OLD: Keep for backward compatibility during migration
  elif project.facilityId.isSome and project.facilityType.isSome:
    let facilityId = project.facilityId.get()
    let facilityType = project.facilityType.get()
    state.constructionProjects.byFacility.mgetOrPut((facilityType, facilityId), @[]).add(
      projectId
    )
    case facilityType
    of FacilityClass.Spaceport:
      var spaceport = state.spaceport(SpaceportId(facilityId)).get()
      spaceport.constructionQueue.add(projectId)
      state.updateSpaceport(SpaceportId(facilityId), spaceport)
    of FacilityClass.Shipyard:
      var shipyard = state.shipyard(ShipyardId(facilityId)).get()
      shipyard.constructionQueue.add(projectId)
      state.updateShipyard(ShipyardId(facilityId), shipyard)
    else:
      discard
  else:
    var colony = state.colony(colonyId).get()
    colony.constructionQueue.add(projectId)
    state.updateColony(colonyId, colony)

  return project

proc completeConstructionProject*(
    state: var GameState, projectId: ConstructionProjectId
) =
  ## Completes a construction project, removing it from active queues and indexes.
  let projectOpt = state.constructionProject(projectId)
  if projectOpt.isNone:
    return
  let project = projectOpt.get()

  if state.constructionProjects.byColony.contains(project.colonyId):
    state.constructionProjects.byColony[project.colonyId].keepIf(
      proc(id: ConstructionProjectId): bool =
        id != projectId
    )

  # NEW: Use typed NeoriaId directly - clean and simple!
  if project.neoriaId.isSome:
    let neoriaId = project.neoriaId.get()
    if state.constructionProjects.byNeoria.hasKey(neoriaId):
      state.constructionProjects.byNeoria[neoriaId] = state.constructionProjects.byNeoria[
        neoriaId
      ].filterIt(it != projectId)

    var neoria = state.neoria(neoriaId).get()
    neoria.activeConstructions.keepIf(
      proc(id: ConstructionProjectId): bool =
        id != projectId
    )
    state.updateNeoria(neoriaId, neoria)
  # OLD: Keep for backward compatibility during migration
  elif project.facilityId.isSome and project.facilityType.isSome:
    let facilityId = project.facilityId.get()
    let facilityType = project.facilityType.get()
    let key = (facilityType, facilityId)
    if state.constructionProjects.byFacility.contains(key):
      state.constructionProjects.byFacility[key].keepIf(
        proc(id: ConstructionProjectId): bool =
          id != projectId
      )

    case facilityType
    of FacilityClass.Spaceport:
      var spaceport = state.spaceport(SpaceportId(facilityId)).get()
      spaceport.activeConstructions.keepIf(
        proc(id: ConstructionProjectId): bool =
          id != projectId
      )
      state.updateSpaceport(SpaceportId(facilityId), spaceport)
    of FacilityClass.Shipyard:
      var shipyard = state.shipyard(ShipyardId(facilityId)).get()
      shipyard.activeConstructions.keepIf(
        proc(id: ConstructionProjectId): bool =
          id != projectId
      )
      state.updateShipyard(ShipyardId(facilityId), shipyard)
    else:
      discard
  else:
    var colony = state.colony(project.colonyId).get()
    if colony.underConstruction.isSome and colony.underConstruction.get() == projectId:
      colony.underConstruction = none(ConstructionProjectId)
      state.updateColony(colony.id, colony)

  state.delConstructionProject(projectId)

# --- Repair Projects ---

proc newRepairProject*(
    id: RepairProjectId,
    colonyId: ColonyId,
    targetType: RepairTargetType,
    facilityType: FacilityClass,
    cost: int32,
    turnsRemaining: int32,
    priority: int32 = 0,
    neoriaId: Option[NeoriaId] = none(NeoriaId),
    fleetId: Option[FleetId] = none(FleetId),
    squadronId: Option[SquadronId] = none(SquadronId),
    shipId: Option[ShipId] = none(ShipId),
    kastraId: Option[KastraId] = none(KastraId),
    shipClass: Option[ShipClass] = none(ShipClass),
): RepairProject =
  ## Create a new repair project value
  ## Use this when you need a RepairProject value without state mutations
  RepairProject(
    id: id,
    colonyId: colonyId,
    targetType: targetType,
    facilityType: facilityType,
    neoriaId: neoriaId,
    fleetId: fleetId,
    squadronId: squadronId,
    shipId: shipId,
    kastraId: kastraId,
    shipClass: shipClass,
    cost: cost,
    turnsRemaining: turnsRemaining,
    priority: priority,
  )

proc queueRepairProject*(
    state: var GameState, colonyId: ColonyId, project: var RepairProject
): RepairProject =
  let projectId = state.generateRepairProjectId()
  project.id = projectId
  project.colonyId = colonyId

  state.addRepairProject(projectId, project)
  state.repairProjects.byColony.mgetOrPut(colonyId, @[]).add(projectId)

  # NEW: Use typed NeoriaId directly - no more uint32 conversions!
  if project.neoriaId.isSome:
    let neoriaId = project.neoriaId.get()
    state.repairProjects.byNeoria.mgetOrPut(neoriaId, @[]).add(projectId)

    var neoria = state.neoria(neoriaId).get()
    neoria.repairQueue.add(projectId)
    state.updateNeoria(neoriaId, neoria)
  # OLD: Keep for backward compatibility during migration
  elif project.facilityId.isSome:
    let facilityId = project.facilityId.get()
    let facilityType = project.facilityType
    state.repairProjects.byFacility.mgetOrPut((facilityType, facilityId), @[]).add(
      projectId
    )

    case facilityType
    of FacilityClass.Drydock:
      var drydock = state.drydock(DrydockId(facilityId)).get()
      drydock.repairQueue.add(projectId)
      state.updateDrydock(DrydockId(facilityId), drydock)
    else:
      discard

  return project

proc completeRepairProject*(state: var GameState, projectId: RepairProjectId) =
  let projectOpt = state.repairProject(projectId)
  if projectOpt.isNone:
    return
  let project = projectOpt.get()

  if state.repairProjects.byColony.contains(project.colonyId):
    state.repairProjects.byColony[project.colonyId].keepIf(
      proc(id: RepairProjectId): bool =
        id != projectId
    )

  # NEW: Use typed NeoriaId directly - clean and simple!
  if project.neoriaId.isSome:
    let neoriaId = project.neoriaId.get()
    if state.repairProjects.byNeoria.hasKey(neoriaId):
      state.repairProjects.byNeoria[neoriaId] = state.repairProjects.byNeoria[
        neoriaId
      ].filterIt(it != projectId)

    var neoria = state.neoria(neoriaId).get()
    neoria.activeRepairs.keepIf(
      proc(id: RepairProjectId): bool =
        id != projectId
    )
    state.updateNeoria(neoriaId, neoria)
  # OLD: Keep for backward compatibility during migration
  elif project.facilityId.isSome:
    let facilityId = project.facilityId.get()
    let facilityType = project.facilityType
    let key = (facilityType, facilityId)
    if state.repairProjects.byFacility.contains(key):
      state.repairProjects.byFacility[key].keepIf(
        proc(id: RepairProjectId): bool =
          id != projectId
      )

    case facilityType
    of FacilityClass.Drydock:
      var drydock = state.drydock(DrydockId(facilityId)).get()
      drydock.activeRepairs.keepIf(
        proc(id: RepairProjectId): bool =
          id != projectId
      )
      state.updateDrydock(DrydockId(facilityId), drydock)
    else:
      discard

  state.delRepairProject(projectId)
