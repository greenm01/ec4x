## Colony Salvage System
##
## Administrative command to scrap/salvage entities at home colonies.
## Zero-turn execution: instant during Command Phase.
## Salvage value: 50% of original production cost.
##
## Supports salvaging:
## - Ships stationed at colonies (not in transit)
## - Ground Units (Army, Marine, GroundBattery, PlanetaryShield)
## - Neorias (Spaceport, Shipyard, Drydock)
## - Kastras (Starbase)
##
## Warning: Scrapping facilities with queued projects destroys those projects
## with no refund. Players must set acknowledgeQueueLoss=true to confirm.

import std/[options, strformat, sequtils]
import ../../types/[
  core, game_state, command, colony, event, ship, ground_unit,
  facilities, production
]
import ../../state/engine
import ../../entities/[ship_ops, ground_unit_ops, neoria_ops, kastra_ops]
import ../../globals
import ../../../common/logger

proc projectDesc*(p: ConstructionProject): string =
  ## Format project description from typed fields for logging
  if p.shipClass.isSome: return $p.shipClass.get()
  if p.facilityClass.isSome: return $p.facilityClass.get()
  if p.groundClass.isSome: return $p.groundClass.get()
  if p.industrialUnits > 0: return $p.industrialUnits & " IU"
  return "unknown"

# =============================================================================
# Event Factory Functions
# =============================================================================

proc entitySalvaged*(
    houseId: HouseId,
    entityType: string,
    entityId: string,
    salvageValue: int32,
    systemId: SystemId,
): event.GameEvent =
  ## Create event for entity salvaged by player command
  event.GameEvent(
    eventType: event.GameEventType.EntitySalvaged,
    houseId: some(houseId),
    systemId: some(systemId),
    description:
      &"{entityType} salvaged for {salvageValue} PP",
    details: some(&"Entity {entityId} scrapped"),
    colonyEventType: some("EntitySalvaged"),
    salvageValueColony: some(int(salvageValue)),
  )

proc constructionLost*(
    houseId: HouseId,
    projectType: string,
    ppLost: int32,
    reason: string,
    systemId: SystemId,
): event.GameEvent =
  ## Create event for construction project lost when facility scrapped
  event.GameEvent(
    eventType: event.GameEventType.ConstructionLost,
    houseId: some(houseId),
    systemId: some(systemId),
    description:
      &"Construction project lost: {projectType} ({ppLost} PP invested, no refund)",
    details: some(reason),
    colonyEventType: some("ConstructionLost"),
    lostProjectType: some(projectType),
    lostProjectPP: some(int(ppLost)),
  )

proc repairLost*(
    houseId: HouseId,
    shipClass: string,
    reason: string,
    systemId: SystemId,
): event.GameEvent =
  ## Create event for ship lost when drydock scrapped during repair
  event.GameEvent(
    eventType: event.GameEventType.ConstructionLost,
    houseId: some(houseId),
    systemId: some(systemId),
    description:
      &"Ship under repair destroyed: {shipClass} (no refund)",
    details: some(reason),
    colonyEventType: some("ConstructionLost"),
    lostProjectType: some(&"Ship Repair: {shipClass}"),
    lostProjectPP: some(0),  # Repair cost already paid, ship value lost
  )

# =============================================================================
# Queue Checking Functions
# =============================================================================

proc hasProjectsInQueue*(
    state: GameState, colonyId: ColonyId, neoriaId: NeoriaId
): bool =
  ## Check if a neoria has any construction or repair projects queued
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return false
  let colony = colonyOpt.get()

  # Check active construction
  if colony.underConstruction.isSome:
    let projectOpt = state.constructionProject(colony.underConstruction.get())
    if projectOpt.isSome and projectOpt.get().neoriaId == some(neoriaId):
      return true

  # Check construction queue
  for projectId in colony.constructionQueue:
    let projectOpt = state.constructionProject(projectId)
    if projectOpt.isSome and projectOpt.get().neoriaId == some(neoriaId):
      return true

  # Check repair queue
  for projectId in colony.repairQueue:
    let repairOpt = state.repairProject(projectId)
    if repairOpt.isSome and repairOpt.get().neoriaId == some(neoriaId):
      return true

  return false

proc getQueuedProjectsForNeoria*(
    state: GameState, colonyId: ColonyId, neoriaId: NeoriaId
): tuple[construction: seq[ConstructionProjectId], repairs: seq[RepairProjectId]] =
  ## Get all projects queued at a specific neoria
  result.construction = @[]
  result.repairs = @[]

  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return

  let colony = colonyOpt.get()

  # Check active construction
  if colony.underConstruction.isSome:
    let projectId = colony.underConstruction.get()
    let projectOpt = state.constructionProject(projectId)
    if projectOpt.isSome and projectOpt.get().neoriaId == some(neoriaId):
      result.construction.add(projectId)

  # Check construction queue
  for projectId in colony.constructionQueue:
    let projectOpt = state.constructionProject(projectId)
    if projectOpt.isSome and projectOpt.get().neoriaId == some(neoriaId):
      result.construction.add(projectId)

  # Check repair queue
  for projectId in colony.repairQueue:
    let repairOpt = state.repairProject(projectId)
    if repairOpt.isSome and repairOpt.get().neoriaId == some(neoriaId):
      result.repairs.add(projectId)

# =============================================================================
# Salvage Value Calculation
# =============================================================================

proc getSalvageMultiplier(): float32 =
  ## Get salvage value multiplier from config (default 0.5 = 50%)
  gameConfig.ships.salvage.salvageValueMultiplier

proc getShipSalvageValue*(state: GameState, shipId: ShipId): int32 =
  ## Calculate salvage value for a ship (50% of build cost)
  let shipOpt = state.ship(shipId)
  if shipOpt.isNone:
    return 0

  let ship = shipOpt.get()
  let buildCost = gameConfig.ships.ships[ship.shipClass].productionCost
  return int32(float32(buildCost) * getSalvageMultiplier())

proc getGroundUnitSalvageValue*(state: GameState, unitId: GroundUnitId): int32 =
  ## Calculate salvage value for a ground unit (50% of build cost)
  let unitOpt = state.groundUnit(unitId)
  if unitOpt.isNone:
    return 0

  let unit = unitOpt.get()
  let buildCost = gameConfig.groundUnits.units[unit.stats.unitType].productionCost
  return int32(float32(buildCost) * getSalvageMultiplier())

proc getNeoriaSalvageValue*(state: GameState, neoriaId: NeoriaId): int32 =
  ## Calculate salvage value for a neoria (50% of build cost)
  let neoriaOpt = state.neoria(neoriaId)
  if neoriaOpt.isNone:
    return 0

  let neoria = neoriaOpt.get()
  let facilityClass = case neoria.neoriaClass
    of NeoriaClass.Spaceport: FacilityClass.Spaceport
    of NeoriaClass.Shipyard: FacilityClass.Shipyard
    of NeoriaClass.Drydock: FacilityClass.Drydock

  let buildCost = gameConfig.facilities.facilities[facilityClass].buildCost
  return int32(float32(buildCost) * getSalvageMultiplier())

proc getKastraSalvageValue*(state: GameState, kastraId: KastraId): int32 =
  ## Calculate salvage value for a kastra/starbase (50% of build cost)
  let kastraOpt = state.kastra(kastraId)
  if kastraOpt.isNone:
    return 0

  let buildCost = gameConfig.facilities.facilities[FacilityClass.Starbase].buildCost
  return int32(float32(buildCost) * getSalvageMultiplier())

# =============================================================================
# Scrap Command Validation
# =============================================================================

proc validateScrapCommand*(
    state: GameState, cmd: ScrapCommand, houseId: HouseId
): ValidationResult =
  ## Validate a scrap command before execution
  ## Checks ownership, existence, and queue acknowledgment

  # Check colony exists and is owned
  let colonyOpt = state.colony(cmd.colonyId)
  if colonyOpt.isNone:
    return ValidationResult(
      valid: false,
      error: "Cannot scrap entity: colony not found."
    )

  let colony = colonyOpt.get()
  if colony.owner != houseId:
    return ValidationResult(
      valid: false,
      error: "Cannot scrap entity: you do not own this colony."
    )

  case cmd.targetType
  of ScrapTargetType.Ship:
    let shipId = ShipId(cmd.targetId)
    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      return ValidationResult(
        valid: false,
        error: "Cannot scrap ship: ship not found."
      )
    let ship = shipOpt.get()
    if ship.houseId != houseId:
      return ValidationResult(
        valid: false,
        error: "Cannot scrap ship: you do not own this ship."
      )
    # Check ship is at this colony (in a fleet at this system)
    let fleetOpt = state.fleet(ship.fleetId)
    if fleetOpt.isNone or fleetOpt.get().location != colony.systemId:
      return ValidationResult(
        valid: false,
        error: "Cannot scrap ship: ship is not at this colony."
      )

  of ScrapTargetType.GroundUnit:
    let unitId = GroundUnitId(cmd.targetId)
    let unitOpt = state.groundUnit(unitId)
    if unitOpt.isNone:
      return ValidationResult(
        valid: false,
        error: "Cannot scrap ground unit: unit not found."
      )
    let unit = unitOpt.get()
    if unit.houseId != houseId:
      return ValidationResult(
        valid: false,
        error: "Cannot scrap ground unit: you do not own this unit."
      )
    # Check unit is at this colony
    if unit.garrison.colonyId != cmd.colonyId:
      return ValidationResult(
        valid: false,
        error: "Cannot scrap ground unit: unit is not at this colony."
      )

  of ScrapTargetType.Neoria:
    let neoriaId = NeoriaId(cmd.targetId)
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isNone:
      return ValidationResult(
        valid: false,
        error: "Cannot scrap facility: facility not found."
      )
    let neoria = neoriaOpt.get()
    # Ownership verified via colony.owner == houseId above
    if neoria.colonyId != cmd.colonyId:
      return ValidationResult(
        valid: false,
        error: "Cannot scrap facility: facility is not at this colony."
      )

    # Check for queued projects
    if state.hasProjectsInQueue(cmd.colonyId, neoriaId):
      if not cmd.acknowledgeQueueLoss:
        return ValidationResult(
          valid: false,
          error: "Cannot scrap facility: construction or repair queue is not " &
                 "empty. Scrapping this facility will destroy all queued " &
                 "projects with no refund. Set acknowledgeQueueLoss=true to " &
                 "confirm, or wait for queues to complete."
        )

  of ScrapTargetType.Kastra:
    let kastraId = KastraId(cmd.targetId)
    let kastraOpt = state.kastra(kastraId)
    if kastraOpt.isNone:
      return ValidationResult(
        valid: false,
        error: "Cannot scrap starbase: starbase not found."
      )
    let kastra = kastraOpt.get()
    # Ownership verified via colony.owner == houseId above
    if kastra.colonyId != cmd.colonyId:
      return ValidationResult(
        valid: false,
        error: "Cannot scrap starbase: starbase is not at this colony."
      )

  return ValidationResult(valid: true, error: "")

# =============================================================================
# Scrap Command Execution
# =============================================================================

proc destroyQueuedProjects*(
    state: GameState,
    colonyId: ColonyId,
    neoriaId: NeoriaId,
    houseId: HouseId,
    events: var seq[GameEvent]
) =
  ## Destroy all construction and repair projects queued at a neoria
  ## Emits events for each lost project

  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return

  var colony = colonyOpt.get()
  let queued = state.getQueuedProjectsForNeoria(colonyId, neoriaId)

  # Destroy construction projects
  for projectId in queued.construction:
    let projectOpt = state.constructionProject(projectId)
    if projectOpt.isSome:
      let project = projectOpt.get()

      events.add(constructionLost(
        houseId = houseId,
        projectType = project.projectDesc,
        ppLost = project.costPaid,
        reason = "Facility scrapped with active construction queue",
        systemId = colony.systemId
      ))

      logWarn(
        "Salvage",
        &"Construction project destroyed: {project.projectDesc}",
        " ppLost=", $project.costPaid,
        " facility=", $neoriaId
      )

      # Remove from colony's construction tracking
      if colony.underConstruction == some(projectId):
        colony.underConstruction = none(ConstructionProjectId)
      colony.constructionQueue = colony.constructionQueue.filterIt(it != projectId)

      # Delete project from state
      state.delConstructionProject(projectId)

  # Destroy repair projects (and the ships being repaired!)
  for projectId in queued.repairs:
    let repairOpt = state.repairProject(projectId)
    if repairOpt.isSome:
      let repair = repairOpt.get()

      # Destroy the ship being repaired if it exists
      if repair.shipId.isSome:
        let shipId = repair.shipId.get()
        let shipOpt = state.ship(shipId)
        if shipOpt.isSome:
          let ship = shipOpt.get()

          events.add(repairLost(
            houseId = houseId,
            shipClass = $ship.shipClass,
            reason = "Drydock scrapped with ship under repair",
            systemId = colony.systemId
          ))

          logWarn(
            "Salvage",
            &"Ship under repair destroyed: {ship.shipClass}",
            " shipId=", $shipId,
            " facility=", $neoriaId
          )

          # Destroy the ship
          state.destroyShip(shipId)

      # Remove from colony's repair queue
      colony.repairQueue = colony.repairQueue.filterIt(it != projectId)

      # Delete repair project from state
      state.delRepairProject(projectId)

  # Update colony
  state.updateColony(colonyId, colony)

proc executeScrapCommand*(
    state: GameState,
    cmd: ScrapCommand,
    houseId: HouseId,
    events: var seq[GameEvent]
): bool =
  ## Execute a validated scrap command
  ## Returns true if successful

  let colonyOpt = state.colony(cmd.colonyId)
  if colonyOpt.isNone:
    return false

  let colony = colonyOpt.get()

  case cmd.targetType
  of ScrapTargetType.Ship:
    let shipId = ShipId(cmd.targetId)
    let salvageValue = state.getShipSalvageValue(shipId)
    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      return false

    let ship = shipOpt.get()
    let shipClass = $ship.shipClass

    # Credit treasury
    let houseOpt = state.house(houseId)
    if houseOpt.isSome:
      var house = houseOpt.get()
      house.treasury += salvageValue
      state.updateHouse(houseId, house)

    # Destroy ship
    state.destroyShip(shipId)

    events.add(entitySalvaged(
      houseId = houseId,
      entityType = &"Ship ({shipClass})",
      entityId = $cmd.targetId,
      salvageValue = salvageValue,
      systemId = colony.systemId
    ))

    logInfo(
      "Salvage",
      &"Ship salvaged: {shipClass}",
      " value=", $salvageValue, " PP",
      " colony=", $cmd.colonyId
    )

  of ScrapTargetType.GroundUnit:
    let unitId = GroundUnitId(cmd.targetId)
    let salvageValue = state.getGroundUnitSalvageValue(unitId)
    let unitOpt = state.groundUnit(unitId)
    if unitOpt.isNone:
      return false

    let unit = unitOpt.get()
    let unitType = $unit.stats.unitType

    # Credit treasury
    let houseOpt = state.house(houseId)
    if houseOpt.isSome:
      var house = houseOpt.get()
      house.treasury += salvageValue
      state.updateHouse(houseId, house)

    # Destroy ground unit
    state.destroyGroundUnit(unitId)

    events.add(entitySalvaged(
      houseId = houseId,
      entityType = &"Ground Unit ({unitType})",
      entityId = $cmd.targetId,
      salvageValue = salvageValue,
      systemId = colony.systemId
    ))

    logInfo(
      "Salvage",
      &"Ground unit salvaged: {unitType}",
      " value=", $salvageValue, " PP",
      " colony=", $cmd.colonyId
    )

  of ScrapTargetType.Neoria:
    let neoriaId = NeoriaId(cmd.targetId)
    let salvageValue = state.getNeoriaSalvageValue(neoriaId)
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isNone:
      return false

    let neoria = neoriaOpt.get()
    let facilityType = $neoria.neoriaClass

    # Destroy queued projects first (if any)
    state.destroyQueuedProjects(cmd.colonyId, neoriaId, houseId, events)

    # Credit treasury
    let houseOpt = state.house(houseId)
    if houseOpt.isSome:
      var house = houseOpt.get()
      house.treasury += salvageValue
      state.updateHouse(houseId, house)

    # Destroy neoria
    state.destroyNeoria(neoriaId)

    events.add(entitySalvaged(
      houseId = houseId,
      entityType = &"Facility ({facilityType})",
      entityId = $cmd.targetId,
      salvageValue = salvageValue,
      systemId = colony.systemId
    ))

    logInfo(
      "Salvage",
      &"Facility salvaged: {facilityType}",
      " value=", $salvageValue, " PP",
      " colony=", $cmd.colonyId
    )

  of ScrapTargetType.Kastra:
    let kastraId = KastraId(cmd.targetId)
    let salvageValue = state.getKastraSalvageValue(kastraId)
    let kastraOpt = state.kastra(kastraId)
    if kastraOpt.isNone:
      return false

    # Credit treasury
    let houseOpt = state.house(houseId)
    if houseOpt.isSome:
      var house = houseOpt.get()
      house.treasury += salvageValue
      state.updateHouse(houseId, house)

    # Destroy kastra
    state.destroyKastra(kastraId)

    events.add(entitySalvaged(
      houseId = houseId,
      entityType = "Starbase",
      entityId = $cmd.targetId,
      salvageValue = salvageValue,
      systemId = colony.systemId
    ))

    logInfo(
      "Salvage",
      "Starbase salvaged",
      " value=", $salvageValue, " PP",
      " colony=", $cmd.colonyId
    )

  return true

# =============================================================================
# Main Entry Point
# =============================================================================

proc resolveScrapCommands*(
    state: GameState, packet: CommandPacket, events: var seq[GameEvent]
) =
  ## Process all scrap commands in a command packet
  ## Called during Command Phase (instant execution)

  if packet.scrapCommands.len == 0:
    return

  logInfo(
    "Salvage",
    &"Processing {packet.scrapCommands.len} scrap command(s) for House {packet.houseId}"
  )

  var processed = 0
  var rejected = 0

  for cmd in packet.scrapCommands:
    # Validate command
    let validation = state.validateScrapCommand(cmd, packet.houseId)
    if not validation.valid:
      logWarn(
        "Salvage",
        &"Scrap command rejected: {validation.error}",
        " targetType=", $cmd.targetType,
        " targetId=", $cmd.targetId
      )
      rejected += 1
      continue

    # Execute command
    if state.executeScrapCommand(cmd, packet.houseId, events):
      processed += 1
    else:
      logError(
        "Salvage",
        "Scrap command execution failed",
        " targetType=", $cmd.targetType,
        " targetId=", $cmd.targetId
      )
      rejected += 1

  logInfo(
    "Salvage",
    &"Scrap commands complete: {processed} processed, {rejected} rejected"
  )
