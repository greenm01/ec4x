## Combat Strength Calculation System
##
## Calculates Attack Strength (AS) and Defense Strength (DS) for ships,
## fleets, and house combat forces.
##
## Per docs/specs/07-combat.md Section 7.2

import std/[options]
import ../../types/[core, game_state, combat, ship]
import ../../state/[engine, iterators]
import ./screened

proc calculateShipAS*(state: GameState, ship: Ship): int32 =
  ## Calculate ship's current Attack Strength
  ## Per docs/specs/07-combat.md Section 7.2.1
  ##
  ## **Rules:**
  ## - Screened ships have 0 AS (auxiliary vessels, mothballed ships)
  ## - Destroyed ships have 0 AS
  ## - Crippled ships have 50% AS
  ## - Undamaged ships have 100% AS

  # Screened units do not contribute AS
  if isScreenedShip(state, ship.id):
    return 0

  if ship.state == CombatState.Destroyed:
    return 0

  let baseAS = ship.stats.attackStrength
  let multiplier =
    if ship.state == CombatState.Crippled:
      0.5
    else:
      1.0

  return int32(float32(baseAS) * multiplier)

proc calculateShipDS*(state: GameState, ship: Ship): int32 =
  ## Calculate ship's current Defense Strength
  ## Per docs/specs/07-combat.md Section 7.2.1
  ##
  ## **Rules:**
  ## - Screened ships have 0 DS (not targetable in combat)
  ## - Destroyed ships have 0 DS
  ## - Crippled ships have 50% DS
  ## - Undamaged ships have 100% DS

  # Screened units do not contribute DS (not targetable)
  if isScreenedShip(state, ship.id):
    return 0

  if ship.state == CombatState.Destroyed:
    return 0

  let baseDS = ship.stats.defenseStrength
  let multiplier =
    if ship.state == CombatState.Crippled:
      0.5
    else:
      1.0

  return int32(float32(baseDS) * multiplier)

proc calculateFleetAS*(state: GameState, fleetId: FleetId): int32 =
  ## Sum AS from all ships in fleet
  ## Per docs/specs/07-combat.md Section 7.2.2

  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return 0

  result = 0
  for ship in state.shipsInFleet(fleetId):
    result += calculateShipAS(state, ship)

proc calculateFleetDS*(state: GameState, fleetId: FleetId): int32 =
  ## Sum DS from all ships in fleet
  ## Per docs/specs/07-combat.md Section 7.2.2

  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return 0

  result = 0
  for ship in state.shipsInFleet(fleetId):
    result += calculateShipDS(state, ship)

proc calculateHouseAS*(state: GameState, force: HouseCombatForce): int32 =
  ## Sum AS from all fleets in house combat force
  ## This is the "task force" AS (conceptual aggregation)
  ## Per docs/specs/07-combat.md Section 7.2.2

  result = 0
  for fleetId in force.fleets:
    result += calculateFleetAS(state, fleetId)

proc calculateHouseDS*(state: GameState, force: HouseCombatForce): int32 =
  ## Sum DS from all fleets in house combat force
  ## This is the "task force" DS (conceptual aggregation)
  ## Per docs/specs/07-combat.md Section 7.2.2

  result = 0
  for fleetId in force.fleets:
    result += calculateFleetDS(state, fleetId)

proc getAllShips*(state: GameState, fleets: seq[FleetId]): seq[ShipId] =
  ## Get all combat-capable ship IDs from multiple fleets
  ## Excludes screened units (auxiliary vessels, mothballed ships)
  ## Used for hit application across all ships in house combat force

  result = @[]
  for fleetId in fleets:
    let combatShips = getCombatShipsInFleet(state, fleetId)
    result.add(combatShips)

proc countOperationalShips*(state: GameState, fleets: seq[FleetId]): int =
  ## Count ships that can still fight (Undamaged or Crippled)
  ## Used for combat termination checks

  result = 0
  for fleetId in fleets:
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isSome:
      let fleet = fleetOpt.get()
      for shipId in fleet.ships:
        let shipOpt = state.ship(shipId)
        if shipOpt.isSome:
          let ship = shipOpt.get()
          if ship.state != CombatState.Destroyed:
            result += 1

## Design Notes:
##
## **Spec Compliance:**
## - docs/specs/07-combat.md Section 7.2.1 - Ship Combat States
## - docs/specs/07-combat.md Section 7.2.2 - Task Force Aggregation
##
## **Architecture:**
## - Pure functions (no mutations)
## - Works directly with Ship entities (no wrappers)
## - Hierarchical calculation: Ship → Fleet → House
## - Crippled ships have 50% effectiveness
## - Destroyed ships have 0% effectiveness
##
## **Special Cases:**
## - Fighters: Skip Crippled state (go directly Undamaged → Destroyed)
## - Carriers: Embarked fighters don't participate in fleet combat
## - Cloaked fleets: Handled by detection system (not strength calculation)
