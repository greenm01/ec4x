## @entities/ground_unit_ops.nim
##
## Write API for creating and destroying GroundUnit entities.
## Ensures consistency between the main `GroundUnits` collection and the
## ID lists within each `Colony` object.
import std/[options, sequtils]
import ../state/[engine, id_gen, iterators]
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

  state.addGroundUnit(unitId, newUnit)

  # Access colony from state and add unit to groundUnitIds
  let colonyOpt = state.colonie(colonyId)
  if colonyOpt.isNone:
    return newUnit

  var colony = colonyOpt.get()
  colony.groundUnitIds.add(unitId)
  state.updateColony(colonyId, colony)

  return newUnit

proc destroyGroundUnit*(state: var GameState, unitId: GroundUnitId) =
  ## Destroys a ground unit, removing it from all collections.
  let unitOpt = state.groundUnit(unitId)
  if unitOpt.isNone:
    return
  let unit = unitOpt.get()

  # Use garrison.colonyId directly for O(1) lookup instead of O(n) iteration
  if unit.garrison.locationType == GroundUnitLocation.OnColony:
    let colonyOpt = state.colony(unit.garrison.colonyId)
    if colonyOpt.isSome:
      var colony = colonyOpt.get()
      colony.groundUnitIds.keepIf(
        proc(id: GroundUnitId): bool =
          id != unitId
      )
      state.updateColony(unit.garrison.colonyId, colony)

  state.delGroundUnit(unitId)
