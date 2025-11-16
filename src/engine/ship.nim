## Ship types and fleet management for EC4X
##
## This module defines the different types of ships and their capabilities,
## including movement restrictions and combat abilities.

import ../common/types

export ShipType

type
  Ship* = object
    ## Individual ship with type and status
    shipType*: ShipType
    isCrippled*: bool

proc newShip*(shipType: ShipType, isCrippled: bool = false): Ship =
  ## Create a new ship of the specified type
  Ship(shipType: shipType, isCrippled: isCrippled)

proc `$`*(s: Ship): string =
  ## String representation of a ship
  let status = if s.isCrippled: " (crippled)" else: ""
  $s.shipType & status

proc canCrossRestrictedLane*(ship: Ship): bool =
  ## Check if a ship can traverse restricted jump lanes
  case ship.shipType
  of ShipType.Military:
    not ship.isCrippled
  of ShipType.Spacelift:
    false

proc isCombatCapable*(ship: Ship): bool =
  ## Check if a ship can engage in combat
  case ship.shipType
  of ShipType.Military:
    not ship.isCrippled
  of ShipType.Spacelift:
    false

proc canCarryTroops*(ship: Ship): bool =
  ## Check if a ship can transport ground forces
  case ship.shipType
  of ShipType.Military:
    false
  of ShipType.Spacelift:
    not ship.isCrippled

# Convenience constructors
proc militaryShip*(crippled: bool = false): Ship =
  newShip(ShipType.Military, crippled)

proc spaceliftShip*(crippled: bool = false): Ship =
  newShip(ShipType.Spacelift, crippled)
