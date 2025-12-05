## Diplomatic Domain Actions (Protostrator)
import std/[tables, options]
import ../../core/[types, conditions]
import ../../state/effects
import ../../../../../common/types/[core, tech, units]

proc createProposeAllianceAction*(targetHouse: HouseId): Action =
  result = Action(
    actionType: ActionType.ProposeAlliance,
    cost: 0,
    duration: 1,
    target: none(SystemId),
    targetHouse: some(targetHouse),
    shipClass: none(ShipClass),
    quantity: 0,
    techField: none(TechField),
    preconditions: @[],
    effects: @[formAllianceWith(targetHouse)],
    description: "Propose alliance with " & targetHouse
  )
