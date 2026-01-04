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
import ../../entities/fleet_ops
import std/[algorithm, strutils, options]

export FleetId, SystemId, HouseId, LaneClass, FleetMissionState
export Ship, ShipClass # Export for fleet users
export ShipCargo, CargoClass # Export cargo types

## Fleet construction
##
## Note: newFleet() has been moved to entities/fleet_ops.nim
## This module provides pure business logic for fleet operations

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

proc add*(state: GameState, f: var Fleet, ship: Ship) =
  ## Add a ship to the fleet
  ## Validates that Intel ships are not mixed with other types
  let validation = state.canAddShip(f, ship)
  if not validation.canAdd:
    raise newException(
      ValueError,
      "Fleet composition violation: " & validation.reason & " (fleet: " & $f.id &
        ", ship: " & $ship.id & ")",
    )

  f.ships.add(ship.id)

proc remove*(f: var Fleet, index: int) =
  ## Remove a ship at the given index
  if index >= 0 and index < f.ships.len:
    f.ships.delete(index)

proc clear*(f: var Fleet) =
  ## Remove all ships from the fleet
  f.ships.setLen(0)

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

proc hasCombatShips*(state: GameState, f: Fleet): bool =
  ## Check if the fleet has any combat-capable ships
  for shipId in f.ships:
    let ship = state.ship(shipId).get
    if ship.effectiveAttackStrength() > 0:
      return true
  return false

proc hasTransportShips*(state: GameState, f: Fleet): bool =
  ## Check if the fleet has any operational Expansion/Auxiliary ships
  for shipId in f.ships:
    let ship = state.ship(shipId).get
    if ship.shipClass in {ShipClass.ETAC, ShipClass.TroopTransport}:
      if ship.state != CombatState.Crippled:
        return true
  return false

proc isScoutOnly*(state: GameState, f: Fleet): bool =
  ## Check if fleet contains ONLY scout ships (no combat ships)
  ## Scouts are intelligence-only units that cannot join combat operations
  if f.ships.len == 0:
    return false
  for shipId in f.ships:
    let ship = state.ship(shipId).get
    if ship.shipClass != ShipClass.Scout:
      return false
  return true

proc hasScouts*(state: GameState, f: Fleet): bool =
  ## Check if fleet contains any scout ships
  for shipId in f.ships:
    let ship = state.ship(shipId).get
    if ship.shipClass == ShipClass.Scout:
      return true
  return false

proc countScoutShips*(state: GameState, f: Fleet): int =
  ## Count number of scout ships in fleet
  ## Used for Scout-on-Scout detection formula
  result = 0
  for shipId in f.ships:
    let ship = state.ship(shipId).get
    if ship.shipClass == ShipClass.Scout:
      result += 1

proc hasNonScoutShips*(state: GameState, f: Fleet): bool =
  ## Check if fleet has any non-scout ships
  for shipId in f.ships:
    let ship = state.ship(shipId).get
    if ship.shipClass != ShipClass.Scout:
      return true
  return false

proc canMergeWith*(
    state: GameState, f1: Fleet, f2: Fleet
): tuple[canMerge: bool, reason: string] =
  ## Check if two fleets can merge (validates Intel/combat mixing)
  ## RULE: Intel ships (Scouts) cannot be mixed with other ship types
  ## Intel fleets NEVER mix with anything (pure intelligence operations)
  ## Combat, Auxiliary, and Expansion can mix (combat escorts for transports)
  ## Fighters stay at colonies and don't join fleets

  let f1HasIntel = state.hasIntelShips(f1)
  let f2HasIntel = state.hasIntelShips(f2)
  let f1HasNonIntel = state.hasNonIntelShips(f1)
  let f2HasNonIntel = state.hasNonIntelShips(f2)

  # Intel ships cannot mix with non-Intel ships
  if (f1HasIntel and f2HasNonIntel) or (f1HasNonIntel and f2HasIntel):
    return (false, "Intel ships cannot be mixed with other ship types")

  # Both fleets are compatible (either both Intel-only or both have no Intel)
  return (true, "")

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

proc merge*(f1: var Fleet, f2: Fleet) =
  ## Merge another fleet into this one
  ## Merges all ship types: Combat, Intel, Expansion, Auxiliary, Fighter
  f1.ships.add(f2.ships)

proc split*(f: var Fleet, indices: seq[int]): Fleet =
  ## Split off ships at the given indices into a new fleet
  var newShipIds: seq[ShipId] = @[]
  var toRemove: seq[int] = @[]

  for i in indices:
    if i >= 0 and i < f.ships.len:
      newShipIds.add(f.ships[i])
      toRemove.add(i)

  # Remove ships from original fleet (in reverse order to maintain indices)
  for i in toRemove.sorted(Descending):
    f.ships.delete(i)

  fleet_ops.newFleet(newShipIds)

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
