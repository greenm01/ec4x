## Espionage Domain Actions (Drungarius)
import std/[tables, options]
import ../../core/[types, conditions]
import ../../state/effects
import ../../../../../common/types/[core, tech, units]

proc createTechTheftAction*(targetHouse: HouseId): Action =
  result = Action(
    actionType: ActionType.TechTheft,
    cost: 200,  # 5 EBP * 40 PP
    duration: 1,
    target: none(SystemId),
    targetHouse: some(targetHouse),
    shipClass: none(ShipClass),
    quantity: 0,
    techField: none(TechField),
    preconditions: @[hasMinBudget(200)],
    effects: @[],
    description: "Tech theft against " & targetHouse
  )
