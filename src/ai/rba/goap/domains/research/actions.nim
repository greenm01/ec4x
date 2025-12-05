## Research Domain Actions (Logothete)
import std/[tables, options]
import ../../core/[types, conditions]
import ../../state/effects
import ../../../../../common/types/[core, tech, units]

proc createAllocateResearchAction*(field: TechField, rp: int): Action =
  result = Action(
    actionType: ActionType.AllocateResearch,
    cost: rp,
    duration: 1,
    target: none(SystemId),
    targetHouse: none(HouseId),
    shipClass: none(ShipClass),
    quantity: rp,
    techField: some(field),
    preconditions: @[hasMinBudget(rp)],
    effects: @[addResearchPoints(field, rp)],
    description: "Allocate " & $rp & " RP to " & $field
  )
