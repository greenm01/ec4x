## Fleet management for EC4X
##
## This module defines fleets which are collections of ships that can
## move together and engage in combat as a unit.
##
## ARCHITECTURE:
## - Fleet → Ships (all types: Combat, Scout, ETAC, TroopTransport, Fighters)
## - ETAC handle colonization
## - TroopTransport handle invasion support
## - All ships in fleets can move and fight together

import ../ship/entity as ship_entity # Ship helper functions
import ../../types/[core, fleet, ship, combat, starmap, game_state]
import ../../state/engine
import std/[strutils, options]

export FleetId, SystemId, HouseId, LaneClass, MissionState
export Ship, ShipClass # Export for fleet users
export ShipCargo, CargoClass # Export cargo types

## Fleet Business Logic
##
## This module provides pure business logic for fleet operations:
## - Query procs (combatStrength, hasIntelShips, etc.)
## - Validation procs (canAddShip, canMergeWith, etc.)
## - Analysis procs (isScoutOnly, hasCombatShips, etc.)
##
## For mutations (add/remove ships, merge, split), use entities/fleet_ops.nim

proc `$`*(state: GameState, f: Fleet): string =
  ## String representation of a fleet
  if f.ships.len == 0:
    "Empty Fleet"
  else:
    var shipClasses: seq[string] = @[]
    for shipId in f.ships:
      let ship = state.ship(shipId).get
      let status = if ship.state == CombatState.Crippled: "*" else: ""
      shipClasses.add($ship.shipClass & status)
    "Fleet[" & $f.ships.len & " ships: " & shipClasses.join(", ") & "]"

proc len*(f: Fleet): int =
  ## Get the number of ships in the fleet
  f.ships.len

proc isEmpty*(f: Fleet): bool =
  ## Check if the fleet has no ships
  f.ships.len == 0

proc hasIntelShips*(state: GameState, f: Fleet): bool =
  ## Check if fleet has any Intel ships (Scouts)
  for shipId in f.ships:
    let ship = state.ship(shipId).get
    if ship.shipClass == ShipClass.Scout:
      return true
  return false

proc hasNonIntelShips*(state: GameState, f: Fleet): bool =
  ## Check if fleet has any non-Intel ships
  for shipId in f.ships:
    let ship = state.ship(shipId).get
    if ship.shipClass != ShipClass.Scout:
      return true
  return false

proc canAddShip*(
    state: GameState, f: Fleet, ship: Ship
): tuple[canAdd: bool, reason: string] =
  ## Check if a ship can be added to this fleet
  ## RULE: Intel ships (Scouts) cannot be mixed with other ship types

  if f.ships.len == 0:
    # Empty fleet - any ship type can be added
    return (canAdd: true, reason: "")

  let isIntelShip = ship.shipClass == ShipClass.Scout
  let fleetHasIntel = state.hasIntelShips(f)
  let fleetHasNonIntel = state.hasNonIntelShips(f)

  if isIntelShip and fleetHasNonIntel:
    return (
      canAdd: false,
      reason: "Cannot add Intel ship to fleet with non-Intel ships",
    )

  if not isIntelShip and fleetHasIntel:
    return (canAdd: false, reason: "Cannot add non-Intel ship to Intel-only fleet")

  return (canAdd: true, reason: "")

proc canTraverse*(
    state: GameState, f: Fleet, laneType: LaneClass
): bool =
  ## Check if the fleet can traverse a specific type of jump lane
  ## Per operations.md:9 "Fleets containing crippled ships or Expansion/Auxiliary ships can not jump across restricted lanes"
  case laneType
  of LaneClass.Restricted:
    # Check for crippled ships
    for shipId in f.ships:
      let ship = state.ship(shipId).get
      if ship.state == CombatState.Crippled:
        return false

    # Check for Expansion/Auxiliary ships (ETAC, TroopTransport)
    for shipId in f.ships:
      let ship = state.ship(shipId).get
      if ship.shipClass in {ShipClass.ETAC, ShipClass.TroopTransport}:
        return false # Cannot cross restricted lanes with Expansion/Auxiliary ships

    return true
  else:
    # Major and Minor lanes can be traversed by any fleet
    true

proc combatStrength*(state: GameState, f: Fleet): int =
  ## Calculate the total attack strength of the fleet
  result = 0
  for shipId in f.ships:
    let ship = state.ship(shipId).get
    result += int(ship.effectiveAttackStrength())

proc isCloaked*(state: GameState, f: Fleet): bool =
  ## Check if fleet is cloaked
  ## Per assets.md:2.4.3: "Fleets that include Raiders are fully cloaked"
  ## Returns true if fleet has ANY non-crippled raiders
  if f.ships.len == 0:
    return false

  # Check if fleet has any operational raiders
  for shipId in f.ships:
    let ship = state.ship(shipId).get
    if ship.shipClass == ShipClass.Raider and ship.state != CombatState.Crippled:
      return true # Fleet is cloaked if it has ANY operational raider

  return false

proc transportCapacity*(state: GameState, f: Fleet): int =
  ## Calculate the number of operational Expansion/Auxiliary ships
  result = 0
  for shipId in f.ships:
    let ship = state.ship(shipId).get
    if ship.shipClass in {ShipClass.ETAC, ShipClass.TroopTransport}:
      if ship.state != CombatState.Crippled:
        result += 1

# NOTE: Duplicate query functions removed (now in state/fleet_queries.nim):
# - hasCombatShips, hasTransportShips, isScoutOnly
# - hasScouts, countScoutShips, hasNonScoutShips
# - canMergeWith
# Use state.func(fleet) for UFCS-style access per CLAUDE.md:8

proc combatShips*(state: GameState, f: Fleet): seq[ShipId] =
  ## Get all combat-capable ship IDs
  result = @[]
  for shipId in f.ships:
    let ship = state.ship(shipId).get
    if ship.effectiveAttackStrength() > 0:
      result.add(shipId)

proc expansionShips*(state: GameState, f: Fleet): seq[ShipId] =
  ## Get all Expansion ship IDs (ETACs for colonization)
  result = @[]
  for shipId in f.ships:
    let ship = state.ship(shipId).get
    if ship.shipClass == ShipClass.ETAC:
      result.add(shipId)

proc auxiliaryShips*(state: GameState, f: Fleet): seq[ShipId] =
  ## Get all Auxiliary ship IDs (TroopTransports for invasion)
  result = @[]
  for shipId in f.ships:
    let ship = state.ship(shipId).get
    if ship.shipClass == ShipClass.TroopTransport:
      result.add(shipId)

proc crippledShips*(state: GameState, f: Fleet): seq[ShipId] =
  ## Get all crippled ship IDs
  result = @[]
  for shipId in f.ships:
    let ship = state.ship(shipId).get
    if ship.state == CombatState.Crippled:
      result.add(shipId)

proc effectiveShips*(
    state: GameState, f: Fleet
): seq[ShipId] =
  ## Get all non-crippled ship IDs
  result = @[]
  for shipId in f.ships:
    let ship = state.ship(shipId).get
    if ship.state != CombatState.Crippled:
      result.add(shipId)

# ============================================================================
# Fleet Management Command Support (for administrative ship reorganization)
# ============================================================================

proc allShips*(state: GameState, f: Fleet): seq[Ship] =
  ## Get flat list of all ships in fleet for player UI
  ## Used by FleetManagementCommand to present ships to player
  ## Player selects ships by index in this list
  result = @[]

  # Add all ships in fleet order
  for shipId in f.ships:
    let ship = state.ship(shipId).get
    result.add(ship)

proc validateShipIndices*(
    state: GameState, f: Fleet, indices: seq[int]
): seq[int] =
  ## Validate and filter ship indices for fleet operations
  ## Player selects ships by index from allShips()
  ## Returns: Valid ship indices (filtered for bounds checking)

  result = @[]
  for idx in indices:
    if idx >= 0 and idx < f.ships.len:
      result.add(idx)
