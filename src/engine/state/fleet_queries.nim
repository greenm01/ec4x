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
