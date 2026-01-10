## Hit Application System
##
## Implements hit application rules for combat damage.
## Must cripple all before destroying any (with exceptions).
##
## Per docs/specs/07-combat.md Section 7.2.1

import std/[options]
import ../../types/[core, game_state, combat, ship]
import ../../state/engine
import ./strength

proc applyHits*(state: GameState, targetShips: seq[ShipId], hits: int32, isCriticalHit: bool = false) =
  ## Apply hits to ships following hit application rules
  ## Per docs/specs/07-combat.md Section 7.2.1 and 7.2.2
  ##
  ## **Hit Application Rules:**
  ## 1. Must cripple all undamaged ships before destroying any
  ## 2. Fighters skip Crippled state (go directly Undamaged → Destroyed)
  ## 3. Critical Hits (natural 9) bypass rule #1 - can destroy crippled ships immediately
  ## 4. Excess hits are lost
  ##
  ## **Algorithm:**
  ## - Phase 1: Cripple all undamaged ships (if enough hits)
  ## - Phase 2: Destroy crippled ships (only if no undamaged remain OR critical hit)

  var remainingHits = hits

  # Phase 1: Cripple all undamaged ships
  for shipId in targetShips:
    if remainingHits <= 0:
      break

    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      continue

    var ship = shipOpt.get()

    # Skip if not undamaged
    if ship.state != CombatState.Undamaged:
      continue

    # Calculate hits needed to cripple this ship
    let hitsNeeded = calculateShipDS(state, ship)

    if remainingHits >= hitsNeeded:
      # Fighters skip Crippled state (07-combat.md Section 7.2.1)
      if ship.shipClass == ShipClass.Fighter:
        ship.state = CombatState.Destroyed
      else:
        ship.state = CombatState.Crippled

      remainingHits -= hitsNeeded
      state.updateShip(shipId, ship)

  # Phase 2: Destroy crippled ships (only if no undamaged remain OR critical hit)
  let hasUndamaged =
    block:
      var found = false
      for shipId in targetShips:
        let shipOpt = state.ship(shipId)
        if shipOpt.isSome and shipOpt.get().state == CombatState.Undamaged:
          found = true
          break
      found

  # Critical hits bypass "cripple all first" protection
  # Can destroy crippled ships even with undamaged ships present
  if (not hasUndamaged or isCriticalHit) and remainingHits > 0:
    for shipId in targetShips:
      if remainingHits <= 0:
        break

      let shipOpt = state.ship(shipId)
      if shipOpt.isNone:
        continue

      var ship = shipOpt.get()

      # Skip if not crippled
      if ship.state != CombatState.Crippled:
        continue

      # Crippled ships have 50% DS
      let hitsNeeded = calculateShipDS(state, ship)

      if remainingHits >= hitsNeeded:
        ship.state = CombatState.Destroyed
        remainingHits -= hitsNeeded
        state.updateShip(shipId, ship)

## Design Notes:
##
## **Spec Compliance:**
## - docs/specs/07-combat.md Section 7.2.1 - Hit Application
## - docs/specs/07-combat.md Section 7.2.1 - Fighter Exception
##
## **Hit Application Order:**
## 1. Target all undamaged ships first
## 2. Apply hits based on DS (hits needed = current DS)
## 3. Only after ALL undamaged are crippled, start destroying crippled ships
## 4. Excess hits are lost (no carry-over)
##
## **Fighter Special Rule:**
## - Fighters have no Crippled state
## - Undamaged → Destroyed (instant destruction)
## - Makes fighters fragile but high-value targets
##
## **Crippled Ship DS:**
## - Crippled ships have 50% DS
## - Calculated by calculateShipDS() in strength.nim
## - Easier to finish off crippled ships
##
## **Critical Hits (Future):**
## - Critical hits may bypass cripple-all-first rule
## - Not yet implemented (Phase 6 enhancement)
##
## **Target Selection:**
## - Caller determines target ships (all ships from losing side)
## - This module only applies damage, doesn't choose targets
## - No bucket targeting or priority system
##
## **State Mutations:**
## - Only changes ship.state field
## - No damage tracking between rounds
## - State changes are immediate and permanent
