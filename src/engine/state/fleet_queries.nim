## Fleet Query Utilities
##
## Helper functions for common fleet state queries.
## Complements @state/iterators.nim with derived properties.
##
## Architecture:
## - Pure query functions (no mutations)
## - Uses state layer iterators
## - Returns computed values based on fleet composition

import std/options
import ../types/[core, game_state, fleet, ship]
import ./iterators
import ./engine as state_engine

proc hasColonists*(state: GameState, fleet: Fleet): bool =
  ## Check if fleet has any ETAC with colonist cargo
  ## O(s) where s = ships in fleet
  ##
  ## Example:
  ##   if state.hasColonists(fleet):
  ##     # Fleet can attempt colonization
  for etac in state.etacsInFleet(fleet):
    if etac.cargo.isSome:
      let cargo = etac.cargo.get()
      if cargo.cargoType == CargoClass.Colonists and cargo.quantity > 0:
        return true
  return false

proc firstColonistCarrier*(
    state: GameState, fleet: Fleet
): Option[tuple[shipId: ShipId, ptuCount: int32]] =
  ## Find first ETAC with colonists and return its ID + PTU count
  ## O(s) where s = ships in fleet
  ##
  ## Example:
  ##   let carrierOpt = state.firstColonistCarrier(fleet)
  ##   if carrierOpt.isSome:
  ##     let (shipId, ptuCount) = carrierOpt.get()
  ##     # Use ETAC for colonization
  for (shipId, etac) in state.etacsInFleetWithId(fleet):
    if etac.cargo.isSome:
      let cargo = etac.cargo.get()
      if cargo.cargoType == CargoClass.Colonists and cargo.quantity > 0:
        return some((shipId, cargo.quantity))
  return none(tuple[shipId: ShipId, ptuCount: int32])

proc calculateFleetAS*(state: GameState, fleet: Fleet): int32 =
  ## Calculate total fleet Attack Strength for conflict resolution
  ## O(s) where s = ships in fleet
  ##
  ## Sums attack strength across all ships in fleet.
  ## Used for colonization conflict priority (Option B).
  ##
  ## Example:
  ##   let strength = state.calculateFleetAS(fleet)
  ##   # Higher strength = better chance in colonization conflicts
  result = 0
  for shipId in fleet.ships:
    let shipOpt = state_engine.ship(state, shipId)
    if shipOpt.isSome:
      result += shipOpt.get().stats.attackStrength

proc hasCombatShips*(state: GameState, fleet: Fleet): bool =
  ## Check if fleet has any combat-capable ships
  ## O(s) where s = ships in fleet
  ##
  ## Combat-capable = ships with attackStrength > 0
  ##
  ## Example:
  ##   if state.hasCombatShips(fleet):
  ##     # Fleet can engage in combat
  for shipId in fleet.ships:
    let shipOpt = state_engine.ship(state, shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if ship.stats.attackStrength > 0:
        return true
  return false

proc hasTransportShips*(state: GameState, fleet: Fleet): bool =
  ## Check if fleet has any transport ships
  ## O(s) where s = ships in fleet
  ##
  ## Transport ships = TroopTransport or ETAC
  ##
  ## Example:
  ##   if state.hasTransportShips(fleet):
  ##     # Fleet can carry cargo/troops
  for shipId in fleet.ships:
    let shipOpt = state_engine.ship(state, shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if ship.shipClass == ShipClass.TroopTransport or
          ship.shipClass == ShipClass.ETAC:
        return true
  return false

proc hasScouts*(state: GameState, fleet: Fleet): bool =
  ## Check if fleet has any scout ships
  ## O(s) where s = ships in fleet
  ##
  ## Example:
  ##   if state.hasScouts(fleet):
  ##     # Fleet has intel gathering capability
  for shipId in fleet.ships:
    let shipOpt = state_engine.ship(state, shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if ship.shipClass == ShipClass.Scout:
        return true
  return false

proc countScoutShips*(state: GameState, fleet: Fleet): int32 =
  ## Count number of scout ships in fleet
  ## O(s) where s = ships in fleet
  ##
  ## Example:
  ##   let scouts = state.countScoutShips(fleet)
  ##   if scouts >= 3:
  ##     # Sufficient scouts for deep recon
  result = 0
  for shipId in fleet.ships:
    let shipOpt = state_engine.ship(state, shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if ship.shipClass == ShipClass.Scout:
        result += 1

proc hasLoadedTransports*(state: GameState, fleet: Fleet): bool =
  ## Check if fleet has any loaded transport ships (any cargo type)
  ## O(s) where s = ships in fleet
  ##
  ## Example:
  ##   if state.hasLoadedTransports(fleet):
  ##     # Fleet is carrying cargo
  for shipId in fleet.ships:
    let shipOpt = state_engine.ship(state, shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if ship.cargo.isSome:
        let cargo = ship.cargo.get()
        if cargo.quantity > 0:
          return true
  return false

proc hasLoadedMarines*(state: GameState, fleet: Fleet): bool =
  ## Check if fleet has any transports loaded with Marines
  ## O(s) where s = ships in fleet
  ##
  ## Used for invasion command validation
  ##
  ## Example:
  ##   if state.hasLoadedMarines(fleet):
  ##     # Fleet can conduct planetary assault
  for shipId in fleet.ships:
    let shipOpt = state_engine.ship(state, shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if ship.shipClass == ShipClass.TroopTransport and ship.cargo.isSome:
        let cargo = ship.cargo.get()
        if cargo.cargoType == CargoClass.Marines and cargo.quantity > 0:
          return true
  return false

proc isScoutOnly*(state: GameState, fleet: Fleet): bool =
  ## Check if fleet contains ONLY scout ships
  ## O(s) where s = ships in fleet
  ##
  ## Used for scout mission validation (pure scout fleets only)
  ##
  ## Example:
  ##   if state.isScoutOnly(fleet):
  ##     # Fleet can perform espionage missions
  if fleet.ships.len == 0:
    return false

  for shipId in fleet.ships:
    let shipOpt = state_engine.ship(state, shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if ship.shipClass != ShipClass.Scout:
        return false
  return true

proc hasNonScoutShips*(state: GameState, fleet: Fleet): bool =
  ## Check if fleet has any non-scout ships
  ## O(s) where s = ships in fleet
  ##
  ## Used for scout mission validation (ensure pure scout fleets)
  ##
  ## Example:
  ##   if state.hasNonScoutShips(fleet):
  ##     # Fleet has combat or support ships
  for shipId in fleet.ships:
    let shipOpt = state_engine.ship(state, shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if ship.shipClass != ShipClass.Scout:
        return true
  return false

proc hasCargoType*(
    state: GameState, fleet: Fleet, cargoType: CargoClass
): bool =
  ## Check if fleet has any ships carrying specific cargo type
  ## O(s) where s = ships in fleet
  ##
  ## Example:
  ##   if state.hasCargoType(fleet, CargoClass.Colonists):
  ##     # Fleet can attempt colonization
  for shipId in fleet.ships:
    let shipOpt = state_engine.ship(state, shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if ship.cargo.isSome:
        let cargo = ship.cargo.get()
        if cargo.cargoType == cargoType and cargo.quantity > 0:
          return true
  return false

proc totalCargoOfType*(
    state: GameState, fleet: Fleet, cargoType: CargoClass
): int32 =
  ## Calculate total quantity of specific cargo type in fleet
  ## O(s) where s = ships in fleet
  ##
  ## Example:
  ##   let marines = state.totalCargoOfType(fleet, CargoClass.Marines)
  ##   echo "Fleet carrying ", marines, " marine divisions"
  result = 0
  for shipId in fleet.ships:
    let shipOpt = state_engine.ship(state, shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if ship.cargo.isSome:
        let cargo = ship.cargo.get()
        if cargo.cargoType == cargoType:
          result += cargo.quantity

proc canMergeWith*(
    state: GameState, fleet1: Fleet, fleet2: Fleet
): tuple[canMerge: bool, reason: string] =
  ## Check if two fleets can merge
  ## O(s1 + s2) where s = ships in each fleet
  ##
  ## RULE: Intel ships (Scouts) cannot be mixed with other ship types
  ## Intel fleets NEVER mix with anything (pure intelligence operations)
  ## Combat, Auxiliary, and Expansion can mix (combat escorts for transports)
  ##
  ## Example:
  ##   let mergeCheck = state.canMergeWith(fleet1, fleet2)
  ##   if mergeCheck.canMerge:
  ##     # Proceed with merge
  let f1HasIntel = state.hasScouts(fleet1)
  let f2HasIntel = state.hasScouts(fleet2)
  let f1HasNonIntel = state.hasNonScoutShips(fleet1)
  let f2HasNonIntel = state.hasNonScoutShips(fleet2)

  # Intel ships cannot mix with non-Intel ships
  if (f1HasIntel and f2HasNonIntel) or (f1HasNonIntel and f2HasIntel):
    return (false, "Intel ships cannot be mixed with other ship types")

  # Both fleets are compatible (either both Intel-only or both have no Intel)
  return (true, "")
