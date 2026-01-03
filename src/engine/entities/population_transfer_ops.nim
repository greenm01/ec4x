## @entities/population_transfer_ops.nim
##
## Write API for managing PopulationInTransit entities.
## Ensures consistency of the `byHouse` and `inTransit` indexes.

import std/[options, tables, sequtils]
import ../state/[engine, id_gen]
import ../types/[game_state, core, population, colony]
import ../globals

proc newPopulationInTransit*(
    id: PopulationTransferId,
    houseId: HouseId,
    sourceColonyId: ColonyId,
    destColonyId: ColonyId,
    ptuAmount: int32,
    cost: int32,
    arrivalTurn: int32,
): PopulationInTransit =
  ## Create a new population transfer value
  ## Use this when you need a PopulationInTransit value without state mutations
  PopulationInTransit(
    id: id,
    houseId: houseId,
    sourceColony: sourceColonyId,
    destColony: destColonyId,
    ptuAmount: ptuAmount,
    costPaid: cost,
    arrivalTurn: arrivalTurn,
    status: TransferStatus.InTransit,
  )

proc startTransfer*(
    state: var GameState,
    houseId: HouseId,
    sourceColonyId: ColonyId,
    destColonyId: ColonyId,
    ptuAmount: int32,
    cost: int32,
    arrivalTurn: int32,
): PopulationInTransit =
  ## Starts a new population transfer, adding it to all relevant collections and indexes.
  let transferId = state.generatePopulationTransferId()
  let newTransfer = newPopulationInTransit(
    transferId, houseId, sourceColonyId, destColonyId, ptuAmount, cost, arrivalTurn
  )

  state.addPopulationTransfer(transferId, newTransfer)
  state.populationTransfers.byHouse.mgetOrPut(houseId, @[]).add(transferId)
  state.populationTransfers.inTransit.add(transferId)

  var sourceColony = state.colony(sourceColonyId).get()
  sourceColony.population -= ptuAmount
  sourceColony.souls -= ptuAmount * gameConfig.economy.ptuDefinition.soulsPerPtu 
  state.updateColony(sourceColonyId, sourceColony)

  var house = state.house(houseId).get()
  house.treasury -= cost
  state.updateHouse(houseId, house)

  return newTransfer

proc completeTransfer*(state: var GameState, transferId: PopulationTransferId) =
  ## Completes a population transfer, removing it from active lists and indexes.
  let transferOpt = state.populationTransfer(transferId)
  if transferOpt.isNone:
    return
  let transfer = transferOpt.get()

  var destColony = state.colony(transfer.destColony).get()
  destColony.population += transfer.ptuAmount
  destColony.souls += transfer.ptuAmount * gameConfig.economy.ptuDefinition.soulsPerPtu
  state.updateColony(transfer.destColony, destColony)

  state.populationTransfers.inTransit.keepIf(
    proc(id: PopulationTransferId): bool =
      id != transferId
  )

  if state.populationTransfers.byHouse.contains(transfer.houseId):
    state.populationTransfers.byHouse[transfer.houseId].keepIf(
      proc(id: PopulationTransferId): bool =
        id != transferId
    )

  state.delPopulationTransfer(transferId)
