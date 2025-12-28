## @entities/ground_unit_ops.nim
##
## Write API for creating and destroying GroundUnit entities.
## Ensures consistency between the main `GroundUnits` collection and the
## ID lists within each `Colony` object.
import std/[options, sequtils]
import ../state/[game_state as gs_helpers, id_gen, entity_manager, iterators]
import ../types/[game_state, core, ground_unit, colony]

proc createGroundUnit*(
    state: var GameState, owner: HouseId, colonyId: ColonyId, unitType: GroundUnitType
): GroundUnit =
  ## Creates a new ground unit, adds it to the entity manager, and links it to a colony.
  let unitId = state.generateGroundUnitId()
  # In a real implementation, stats would come from a config file based on unitType and tech
  let newUnit = GroundUnit(
    id: unitId,
    unitType: unitType,
    owner: owner,
    attackStrength: 5,
    defenseStrength: 5,
    state: CombatState.Undamaged,
  )

  state.groundUnits.entities.addEntity(unitId, newUnit)

  var colony = gs_helpers.colony(state, colonyId).get()
  case unitType
  of GroundUnitType.Army:
    colony.armyIds.add(unitId)
  of GroundUnitType.Marine:
    colony.marineIds.add(unitId)
  of GroundUnitType.GroundBattery:
    colony.groundBatteryIds.add(unitId)
  else:
    discard
  state.colonies.entities.updateEntity(colonyId, colony)

  return newUnit

proc destroyGroundUnit*(state: var GameState, unitId: GroundUnitId) =
  ## Destroys a ground unit, removing it from all collections.
  let unitOpt = gs_helpers.groundUnit(state, unitId)
  if unitOpt.isNone:
    return
  let unit = unitOpt.get()

  var ownerColonyId: ColonyId
  for col in state.allColonies():
    case unit.unitType
    of GroundUnitType.Army:
      if unitId in col.armyIds:
        ownerColonyId = col.id
    of GroundUnitType.Marine:
      if unitId in col.marineIds:
        ownerColonyId = col.id
    of GroundUnitType.GroundBattery:
      if unitId in col.groundBatteryIds:
        ownerColonyId = col.id
    else:
      discard
    if ownerColonyId != 0'u32:
      break

  if ownerColonyId != 0'u32:
    var colony = gs_helpers.colony(state, ownerColonyId).get()
    case unit.unitType
    of GroundUnitType.Army:
      colony.armyIds.keepIf(
        proc(id: GroundUnitId): bool =
          id != unitId
      )
    of GroundUnitType.Marine:
      colony.marineIds.keepIf(
        proc(id: GroundUnitId): bool =
          id != unitId
      )
    of GroundUnitType.GroundBattery:
      colony.groundBatteryIds.keepIf(
        proc(id: GroundUnitId): bool =
          id != unitId
      )
    else:
      discard
    state.colonies.entities.updateEntity(ownerColonyId, colony)

  state.groundUnits.entities.removeEntity(unitId)
