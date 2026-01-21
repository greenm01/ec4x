## Combat Strength Calculation System
##
## Calculates Attack Strength (AS) and Defense Strength (DS) for ships,
## fleets, starbases (Kastras), and house combat forces.
##
## Per docs/specs/07-combat.md Section 7.2 and 7.6.3

import std/[options]
import ../../types/[core, game_state, combat, ship, facilities]
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
  ## - Nominal ships have 100% AS

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
  ## - Nominal ships have 100% DS

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

proc calculateKastraAS*(state: GameState, kastra: Kastra): int32 =
  ## Calculate Kastra's (starbase) current Attack Strength
  ## Per docs/specs/07-combat.md Section 7.6.3
  ##
  ## **Rules:**
  ## - Destroyed Kastras have 0 AS
  ## - Crippled Kastras have 50% AS
  ## - Nominal Kastras have 100% AS
  
  if kastra.state == CombatState.Destroyed:
    return 0
  
  let baseAS = kastra.stats.attackStrength
  let multiplier =
    if kastra.state == CombatState.Crippled:
      0.5
    else:
      1.0
  
  return int32(float32(baseAS) * multiplier)

proc calculateKastraDS*(state: GameState, kastra: Kastra): int32 =
  ## Calculate Kastra's (starbase) current Defense Strength
  ## Per docs/specs/07-combat.md Section 7.6.3
  ##
  ## **Rules:**
  ## - Destroyed Kastras have 0 DS
  ## - Crippled Kastras have 50% DS
  ## - Nominal Kastras have 100% DS
  
  if kastra.state == CombatState.Destroyed:
    return 0
  
  let baseDS = kastra.stats.defenseStrength
  let multiplier =
    if kastra.state == CombatState.Crippled:
      0.5
    else:
      1.0
  
  return int32(float32(baseDS) * multiplier)

proc calculateColonyKastraAS*(state: GameState, colonyId: ColonyId): int32 =
  ## Sum AS from all Kastras (starbases) at a colony
  ## Per docs/specs/07-combat.md Section 7.6.3
  ##
  ## Starbases participate directly in orbital combat, adding their AS/DS
  ## to the defender's task force.
  
  result = 0
  for kastra in state.kastrasAtColony(colonyId):
    result += calculateKastraAS(state, kastra)

proc calculateColonyKastraDS*(state: GameState, colonyId: ColonyId): int32 =
  ## Sum DS from all Kastras (starbases) at a colony
  ## Per docs/specs/07-combat.md Section 7.6.3
  
  result = 0
  for kastra in state.kastrasAtColony(colonyId):
    result += calculateKastraDS(state, kastra)

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
  ##
  ## NOTE: Does NOT include Kastra AS. For orbital combat where
  ## starbases participate, use calculateDefenderAS() instead.

  result = 0
  for fleetId in force.fleets:
    result += calculateFleetAS(state, fleetId)

proc calculateHouseDS*(state: GameState, force: HouseCombatForce): int32 =
  ## Sum DS from all fleets in house combat force
  ## This is the "task force" DS (conceptual aggregation)
  ## Per docs/specs/07-combat.md Section 7.2.2
  ##
  ## NOTE: Does NOT include Kastra DS. For orbital combat where
  ## starbases participate, use calculateDefenderDS() instead.

  result = 0
  for fleetId in force.fleets:
    result += calculateFleetDS(state, fleetId)

proc calculateDefenderAS*(
  state: GameState, force: HouseCombatForce, systemId: SystemId,
  theater: CombatTheater
): int32 =
  ## Sum AS from defender's fleets + Kastras (for orbital combat)
  ## Per docs/specs/07-combat.md Section 7.6.3
  ##
  ## Starbases participate directly in orbital combat, adding their AS
  ## to the defender's task force. They do NOT participate in space combat.
  
  result = calculateHouseAS(state, force)
  
  # Add Kastra AS for orbital combat only
  if theater == CombatTheater.Orbital:
    # Find colony in this system owned by defender
    for colony in state.coloniesOwned(force.houseId):
      if colony.systemId == systemId:
        result += calculateColonyKastraAS(state, colony.id)
        break  # Only one colony per system

proc calculateDefenderDS*(
  state: GameState, force: HouseCombatForce, systemId: SystemId,
  theater: CombatTheater
): int32 =
  ## Sum DS from defender's fleets + Kastras (for orbital combat)
  ## Per docs/specs/07-combat.md Section 7.6.3
  ##
  ## Starbases participate directly in orbital combat, adding their DS
  ## to the defender's task force. They do NOT participate in space combat.
  
  result = calculateHouseDS(state, force)
  
  # Add Kastra DS for orbital combat only
  if theater == CombatTheater.Orbital:
    # Find colony in this system owned by defender
    for colony in state.coloniesOwned(force.houseId):
      if colony.systemId == systemId:
        result += calculateColonyKastraDS(state, colony.id)
        break  # Only one colony per system

proc allShips*(state: GameState, fleets: seq[FleetId]): seq[ShipId] =
  ## Get all combat-capable ship IDs from multiple fleets
  ## Excludes screened units (auxiliary vessels, mothballed ships)
  ## Used for hit application across all ships in house combat force

  result = @[]
  for fleetId in fleets:
    let combatShips = combatShipsInFleet(state, fleetId)
    result.add(combatShips)

proc countOperationalShips*(state: GameState, fleets: seq[FleetId]): int =
  ## Count ships that can still fight (Nominal or Crippled)
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
## - docs/specs/07-combat.md Section 7.6.3 - Starbase Combat Participation
##
## **Architecture:**
## - Pure functions (no mutations)
## - Works directly with Ship and Kastra entities
## - Hierarchical calculation: Ship → Fleet → House (+ Kastras for orbital)
## - Crippled units have 50% effectiveness
## - Destroyed units have 0% effectiveness
##
## **Orbital Combat Starbase Integration:**
## - Starbases (Kastras) participate ONLY in orbital combat, not space combat
## - Use calculateDefenderAS/DS for orbital combat (includes Kastra strength)
## - Use calculateHouseAS/DS for space combat (excludes Kastras)
## - Starbases cannot retreat - fight to destruction or victory
##
## **Special Cases:**
## - Fighters: Skip Crippled state (go directly Nominal → Destroyed)
## - Carriers: Embarked fighters don't participate in fleet combat
## - Cloaked fleets: Handled by detection system (not strength calculation)
## - Starbases: Only participate in orbital combat
