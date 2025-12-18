## Diplomatic Domain Actions (Protostrator)
import std/[tables, options]
import ../../core/[types, conditions]
import ../../state/effects
import ../../../../../common/types/[core, tech, units]

proc createProposeAllianceAction*(targetHouse: HouseId): Action =
  ## NOTE: Alliances are not implemented in the game
  ## This action exists for API compatibility but has no effects
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
    effects: @[],  # No effects - alliances not implemented
    description: "Propose alliance with " & targetHouse
  )
