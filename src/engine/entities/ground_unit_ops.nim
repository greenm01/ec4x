## @entities/ground_unit_ops.nim
##
## Write API for creating and destroying GroundUnit entities.
## Ensures consistency between the main `GroundUnits` collection and the
## ID lists within each `Colony` object.
import std/[options, sequtils]
import ../state/[id_gen, entity_manager, iterators]
import ../types/[game_state, core, ground_unit, colony, combat]

proc createGroundUnit*(
    state: var GameState, owner: HouseId, colonyId: ColonyId, unitType: GroundClass
): GroundUnit =
  ## Creates a new ground unit, adds it to the entity manager, and links it to a colony.
  let unitId = state.generateGroundUnitId()
  # In a real implementation, stats would come from a config file based on unitType and tech
  let newUnit = GroundUnit(
    id: unitId,
    houseId: owner,
    stats: GroundUnitStats(
      unitType: unitType,
      attackStrength: 5,
      defenseStrength: 5,
    ),
    state: CombatState.Undamaged,
    garrison: GroundUnitGarrison(locationType: GroundUnitLocation.OnColony, colonyId: colonyId),
  )

  state.groundUnits.entities.addEntity(unitId, newUnit)

  # Access colony from state
  let colonyOpt = state.colonies.entities.entity(colonyId)
  if colonyOpt.isNone:
    return newUnit

  var colony = colonyOpt.get()
  case unitType
  of GroundClass.Army:
    colony.armyIds.add(unitId)
  of GroundClass.Marine:
    colony.marineIds.add(unitId)
  of GroundClass.GroundBattery:
    colony.groundBatteryIds.add(unitId)
  else:
    discard
  state.colonies.entities.updateEntity(colonyId, colony)

  return newUnit

proc destroyGroundUnit*(state: var GameState, unitId: GroundUnitId) =
  ## Destroys a ground unit, removing it from all collections.
  let unitOpt = state.groundUnits.entities.entity(unitId)
  if unitOpt.isNone:
    return
  let unit = unitOpt.get()

  var ownerColonyId: ColonyId = ColonyId(0)
  for colId, col in state.colonies.entities.pairs():
    case unit.stats.unitType
    of GroundClass.Army:
      if unitId in col.armyIds:
        ownerColonyId = col.id
    of GroundClass.Marine:
      if unitId in col.marineIds:
        ownerColonyId = col.id
    of GroundClass.GroundBattery:
      if unitId in col.groundBatteryIds:
        ownerColonyId = col.id
    else:
      discard
    if ownerColonyId != ColonyId(0):
      break

  if ownerColonyId != ColonyId(0):
    let colonyOpt = state.colonies.entities.entity(ownerColonyId)
    if colonyOpt.isNone:
      return
    var colony = colonyOpt.get()
    case unit.stats.unitType
    of GroundClass.Army:
      colony.armyIds.keepIf(
        proc(id: GroundUnitId): bool =
          id != unitId
      )
    of GroundClass.Marine:
      colony.marineIds.keepIf(
        proc(id: GroundUnitId): bool =
          id != unitId
      )
    of GroundClass.GroundBattery:
      colony.groundBatteryIds.keepIf(
        proc(id: GroundUnitId): bool =
          id != unitId
      )
    else:
      discard
    state.colonies.entities.updateEntity(ownerColonyId, colony)

  state.groundUnits.entities.removeEntity(unitId)
