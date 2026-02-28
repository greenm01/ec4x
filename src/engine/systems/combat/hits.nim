## Hit Application System
##
## Implements hit application rules for combat damage.
## Must cripple all before destroying any (with exceptions).
##
## Per docs/specs/07-combat.md Section 7.2.1

import std/[options, sets, algorithm, logging]
import ../../types/[core, game_state, combat, ship]
import ../../event_factory/military
import ../../state/engine
import ./strength

proc applyHits*(state: GameState, targetShips: seq[ShipId], hits: int32, systemId: SystemId, events: var seq[GameEvent], isCriticalHit: bool = false, killedByHouse: HouseId = HouseId(0)) =
  ## Apply hits to ships following hit application rules
  ## Per docs/specs/07-combat.md Section 7.2.1 and 7.2.2
  ##
  ## **Hit Application Rules:**
  ## 1. Must cripple all nominal ships before destroying any
  ## 2. Fighters skip Crippled state (go directly Nominal → Destroyed)
  ## 3. Critical Hits (natural 9) bypass rule #1 - can destroy crippled ships
  ##    that were ALREADY crippled (not ships crippled this round)
  ## 4. Excess hits are lost
  ##
  ## **Algorithm:**
  ## - Snapshot ship states BEFORE applying damage
  ## - Phase 1: Cripple all undamaged ships (if enough hits)
  ## - Phase 2: Destroy crippled ships:
  ##   - Normal hits: only if no undamaged ships at START
  ##   - Critical hits: can destroy ships that were crippled at START

  var remainingHits = hits

  # Snapshot ship states BEFORE Phase 1 modifies anything
  # This determines Phase 2 eligibility and valid targets
  var hadNominalAtStart = false
  var wasCrippledAtStart: HashSet[ShipId]
  var totalDS: int32 = 0
  
  for shipId in targetShips:
    let shipOpt = state.ship(shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      totalDS += calculateShipDS(state, ship)
      if ship.state == CombatState.Nominal:
        hadNominalAtStart = true
      elif ship.state == CombatState.Crippled:
        wasCrippledAtStart.incl(shipId)

  # Overwhelming Force (Cascading Overkill) Check
  let isCascadingOverkill = (totalDS > 0 and hits >= int32(float(totalDS) * 1.5))
  if isCascadingOverkill:
    # Bypass the cripple-first rule entirely - hits will cascade
    hadNominalAtStart = false

  # Phase 1: Cripple all undamaged ships
  for shipId in targetShips:
    if remainingHits <= 0:
      break

    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      continue

    var ship = shipOpt.get()

    # Skip if not undamaged
    if ship.state != CombatState.Nominal:
      continue

    # Calculate hits needed to cripple this ship
    let hitsNeeded = calculateShipDS(state, ship)

    if remainingHits >= hitsNeeded:
      # Fighters skip Crippled state (07-combat.md Section 7.2.1)
      if ship.shipClass == ShipClass.Fighter:
        ship.state = CombatState.Destroyed
      else:
        ship.state = CombatState.Crippled
        events.add(military.shipDamaged($ship.id, ship.houseId, hitsNeeded, "Crippled", calculateShipDS(state, ship), systemId))

      remainingHits -= hitsNeeded
      state.updateShip(shipId, ship)

  # Phase 2: Destroy crippled ships
  # Normal hits: only if no undamaged ships at START (protection rule)
  # Critical hits: can bypass protection to destroy originally-crippled ships
  #
  # Key insight: Critical hits don't allow "double damage" to ships we just
  # crippled - they only bypass protection to destroy ships that were ALREADY
  # crippled before this hit application started.
  
  if remainingHits > 0:
    # Determine which ships are valid Phase 2 targets
    let canDestroyAnyCrippled = not hadNominalAtStart
    let canDestroyOriginallyCrippled = isCriticalHit

    if canDestroyAnyCrippled or canDestroyOriginallyCrippled:
      # Prioritize targets for Phase 2 (High value first for criticals/overkill)
      var p2Targets = targetShips
      if isCriticalHit:
        p2Targets.sort(proc(a, b: ShipId): int =
          let shipA = state.ship(a).get()
          let shipB = state.ship(b).get()
          
          # Priority 1: High value classes
          let aValue = if shipA.shipClass in {ShipClass.PlanetBreaker, ShipClass.Carrier}: 2 else: 1
          let bValue = if shipB.shipClass in {ShipClass.PlanetBreaker, ShipClass.Carrier}: 2 else: 1
          if aValue != bValue: return bValue - aValue
          
          # Priority 2: Highest AS
          let aAs = calculateShipAS(state, shipA)
          let bAs = calculateShipAS(state, shipB)
          return bAs - aAs
        )

      for shipId in p2Targets:
        if remainingHits <= 0:
          break

        let shipOpt = state.ship(shipId)
        if shipOpt.isNone:
          continue

        var ship = shipOpt.get()

        # Skip if not crippled
        if ship.state != CombatState.Crippled:
          continue

        # For critical hits with undamaged ships at start:
        # Only destroy ships that were ALREADY crippled, not newly crippled
        if hadNominalAtStart and isCriticalHit:
          if shipId notin wasCrippledAtStart:
            continue  # Skip ships we just crippled in Phase 1

        # Crippled ships have 50% DS
        let hitsNeeded = calculateShipDS(state, ship)

        if remainingHits >= hitsNeeded:
          ship.state = CombatState.Destroyed
          remainingHits -= hitsNeeded
          state.updateShip(shipId, ship)
          let overkill = remainingHits
          events.add(military.shipDestroyed($ship.id, ship.houseId, killedByHouse, isCriticalHit, overkill, systemId))
          if isCriticalHit and ship.shipClass in {ShipClass.PlanetBreaker, ShipClass.Carrier, ShipClass.Battleship}:
            info "Critical Hit! High-value asset destroyed: " & $ship.shipClass

## Design Notes:
##
## **Spec Compliance:**
## - docs/specs/07-combat.md Section 7.2.1 - Hit Application
## - docs/specs/07-combat.md Section 7.2.1 - Fighter Exception
##
## **Hit Application Order:**
  ## 1. Target all nominal ships first
## 2. Apply hits based on DS (hits needed = current DS)
## 3. Only after ALL undamaged are crippled, start destroying crippled ships
## 4. Excess hits are lost (no carry-over)
##
## **Fighter Special Rule:**
## - Fighters have no Crippled state
## - Nominal → Destroyed (instant destruction)
## - Makes fighters fragile but high-value targets
##
## **Crippled Ship DS:**
## - Crippled ships have 50% DS
## - Calculated by calculateShipDS() in strength.nim
## - Easier to finish off crippled ships
##
## **Critical Hits:**
## - Critical hits (natural 9) bypass cripple-all-first rule
## - Can destroy ships that were ALREADY crippled at round start
## - Cannot "double damage" ships crippled in the same round
## - Per docs/specs/07-combat.md Section 7.2.2 Rule 2
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
