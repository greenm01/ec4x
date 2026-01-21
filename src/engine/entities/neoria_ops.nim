## @entities/neoria_ops.nim
##
## Write API for creating and destroying Neoria entities (production facilities).
## Ensures consistency between the main `Neorias` collection, the `byColony` index,
## and the ID list within each `Colony` object.

import std/[options, sequtils, tables]
import ../state/[engine, id_gen]
import ../types/[game_state, core, facilities, colony, combat]
import ../globals
import ../systems/tech/effects

proc newNeoria*(
    id: NeoriaId,
    neoriaClass: NeoriaClass,
    colonyId: ColonyId,
    commissionedTurn: int32,
    baseDocks: int32,
    effectiveDocks: int32,
): Neoria =
  ## Create a new neoria value
  ## Use this when you need a Neoria value without state mutations
  ## baseDocks = base capacity from config, effectiveDocks = CST-modified capacity
  Neoria(
    id: id,
    neoriaClass: neoriaClass,
    colonyId: colonyId,
    commissionedTurn: commissionedTurn,
    state: CombatState.Nominal,
    baseDocks: baseDocks,
    effectiveDocks: effectiveDocks,
    constructionQueue: @[],
    activeConstructions: @[],
    repairQueue: @[],
    activeRepairs: @[],
  )

proc createNeoria*(
    state: GameState, colonyId: ColonyId, neoriaClass: NeoriaClass,
    ownerHouseId: HouseId = HouseId(0)
): Neoria =
  ## Creates a new neoria (production facility), adds it to the entity manager,
  ## and links it to a colony.
  ## Initializes baseDocks from config and calculates effectiveDocks using owner's CST level
  ##
  ## Parameters:
  ##   ownerHouseId: Optional house ID to look up CST level. If not provided (0),
  ##                 will look up via colony's owner. Use this when creating neorias
  ##                 during homeworld initialization before colony exists in state.
  let neoriaId = state.generateNeoriaId()

  # Determine CST level from owner house
  var cstLevel = 1.int32
  var colonyOwner = ownerHouseId

  if ownerHouseId != HouseId(0):
    # Use provided house ID directly
    let houseOpt = state.house(ownerHouseId)
    if houseOpt.isSome:
      cstLevel = houseOpt.get().techTree.levels.cst
  else:
    # Look up via colony
    let colonyOpt = state.colony(colonyId)
    if colonyOpt.isSome:
      let colony = colonyOpt.get()
      colonyOwner = colony.owner
      let houseOpt = state.house(colony.owner)
      if houseOpt.isSome:
        cstLevel = houseOpt.get().techTree.levels.cst

  # Get baseDocks from config based on neoriaClass
  let facilityClass =
    case neoriaClass
    of NeoriaClass.Spaceport:
      FacilityClass.Spaceport
    of NeoriaClass.Shipyard:
      FacilityClass.Shipyard
    of NeoriaClass.Drydock:
      FacilityClass.Drydock

  let baseDocks = gameConfig.facilities.facilities[facilityClass].docks
  let effectiveDocks = effects.calculateEffectiveDocks(baseDocks, cstLevel)

  let newNeoria =
    newNeoria(neoriaId, neoriaClass, colonyId, state.turn, baseDocks, effectiveDocks)

  state.addNeoria(neoriaId, newNeoria)
  state.neorias.byColony.mgetOrPut(colonyId, @[]).add(neoriaId)

  # Update colony's neoriaIds list if colony exists
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isSome:
    var colonyMut = colonyOpt.get()
    colonyMut.neoriaIds.add(neoriaId)
    state.updateColony(colonyId, colonyMut)

  return newNeoria

proc destroyNeoria*(state: GameState, neoriaId: NeoriaId) =
  ## Destroys a neoria, removing it from all collections.
  ## Uses O(1) lookup via neoria.colonyId (no iteration needed!)
  let neoriaOpt = state.neoria(neoriaId)
  if neoriaOpt.isNone:
    return
  let neoria = neoriaOpt.get()

  # Remove from colony's neoriaIds list (O(1) colony lookup)
  let colonyOpt = state.colony(neoria.colonyId)
  if colonyOpt.isSome:
    var colony = colonyOpt.get()
    colony.neoriaIds.keepIf(
      proc(id: NeoriaId): bool =
        id != neoriaId
    )
    state.updateColony(neoria.colonyId, colony)

  # Remove from byColony index
  if state.neorias.byColony.hasKey(neoria.colonyId):
    state.neorias.byColony[neoria.colonyId] = state.neorias.byColony[
      neoria.colonyId
    ].filterIt(it != neoriaId)

  # Remove from main collection
  state.delNeoria(neoriaId)
