## @entities/neoria_ops.nim
##
## Write API for creating and destroying Neoria entities (production facilities).
## Ensures consistency between the main `Neorias` collection, the `byColony` index,
## and the ID list within each `Colony` object.

import std/[options, sequtils, tables]
import ../state/[engine, id_gen]
import ../types/[game_state, core, facilities, colony]

proc createNeoria*(
    state: var GameState, colonyId: ColonyId, neoriaClass: NeoriaClass
): Neoria =
  ## Creates a new neoria (production facility), adds it to the entity manager,
  ## and links it to a colony.
  let neoriaId = state.generateNeoriaId()

  let newNeoria = Neoria(
    id: neoriaId,
    neoriaClass: neoriaClass,
    colonyId: colonyId,
    commissionedTurn: state.turn,
    isCrippled: false,
    constructionQueue: @[],
    activeConstructions: @[],
    repairQueue: @[],
    activeRepairs: @[],
  )

  state.addNeoria(neoriaId, newNeoria)
  state.neorias.byColony.mgetOrPut(colonyId, @[]).add(neoriaId)

  # Update colony's neoriaIds list
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isSome:
    var colony = colonyOpt.get()
    colony.neoriaIds.add(neoriaId)
    state.updateColony(colonyId, colony)

  return newNeoria

proc destroyNeoria*(state: var GameState, neoriaId: NeoriaId) =
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
