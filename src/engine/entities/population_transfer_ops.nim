## @entities/population_transfer_ops.nim
##
## Write API for managing PopulationInTransit entities.
## Ensures consistency of the `byHouse` and `inTransit` indexes.

import std/[options, tables, sequtils]
import ../state/[game_state as gs_helpers, id_gen, entity_manager]
import ../types/[game_state, core, population, colony]

proc startTransfer*(state: var GameState, houseId: HouseId, sourceColonyId: ColonyId, destColonyId: ColonyId, ptuAmount: int32, cost: int32, arrivalTurn: int32): PopulationInTransit =
  ## Starts a new population transfer, adding it to all relevant collections and indexes.
  let transferId = state.generatePopulationTransferId()
  let newTransfer = PopulationInTransit(
    id: transferId,
    houseId: houseId,
    sourceColony: sourceColonyId,
    destColony: destColonyId,
    ptuAmount: ptuAmount,
    costPaid: cost,
    arrivalTurn: arrivalTurn,
    status: TransferStatus.InTransit
  )

  state.populationTransfers.entities.addEntity(transferId, newTransfer)
  state.populationTransfers.byHouse.mgetOrPut(houseId, @[]).add(transferId)
  state.populationTransfers.inTransit.add(transferId)

  var sourceColony = gs_helpers.getColony(state, sourceColonyId).get()
  sourceColony.population -= ptuAmount
  sourceColony.souls -= ptuAmount * 50000 # Example
  state.colonies.entities.updateEntity(sourceColonyId, sourceColony)

  var house = gs_helpers.getHouse(state, houseId).get()
  house.treasury -= cost
  state.houses.entities.updateEntity(houseId, house)

  return newTransfer

proc completeTransfer*(state: var GameState, transferId: PopulationTransferId) =
  ## Completes a population transfer, removing it from active lists and indexes.
  let transferOpt = gs_helpers.getPopulationTransfer(state, transferId)
  if transferOpt.isNone: return
  let transfer = transferOpt.get()

  var destColony = gs_helpers.getColony(state, transfer.destColony).get()
  destColony.population += transfer.ptuAmount
  destColony.souls += transfer.ptuAmount * 50000
  state.colonies.entities.updateEntity(transfer.destColony, destColony)

  state.populationTransfers.inTransit.keepIf(proc(id: PopulationTransferId): bool = id != transferId)
  
  if state.populationTransfers.byHouse.contains(transfer.houseId):
    state.populationTransfers.byHouse[transfer.houseId].keepIf(proc(id: PopulationTransferId): bool = id != transferId)

  state.populationTransfers.entities.removeEntity(transferId)
