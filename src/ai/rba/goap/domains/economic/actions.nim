## Economic Domain Actions (Eparch)
import std/[tables, options]
import ../../core/[types, conditions]
import ../../state/effects
import ../../../../../common/types/[core, tech, units]

proc createTransferPopulationAction*(fromSystem: SystemId, toSystem: SystemId, ptu: int): Action =
  result = Action(
    actionType: ActionType.TransferPopulationPTU,
    cost: ptu * 10,
    duration: 1,
    target: some(toSystem),
    targetHouse: none(HouseId),
    shipClass: none(ShipClass),
    quantity: ptu,
    techField: none(TechField),
    preconditions: @[hasMinBudget(ptu * 10)],
    effects: @[],
    description: "Transfer " & $ptu & " PTU from " & $fromSystem & " to " & $toSystem
  )
