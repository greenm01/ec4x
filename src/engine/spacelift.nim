## Spacelift Command ship management for EC4X
##
## Per specification (operations.md:1036, operations.md:288):
## - Spacelift ships are "individual units" NOT squadrons
## - Travel with fleets but separate from combat squadrons
## - Screened behind task force during orbital combat
## - Participate in ground combat phase (can be destroyed by ground batteries)
##
## Architecture: Fleet → Squadrons (combat) + SpaceLiftShips (separate)

import ../common/types/[core, units]
import config/military_config

export HouseId, SystemId, ShipClass

type
  CargoType* {.pure.} = enum
    ## Type of cargo loaded on spacelift ship
    None,
    Marines,      # Marine Division (MD) - TroopTransport
    Colonists,    # Population Transfer Unit (PTU) - ETAC
    Supplies      # Generic cargo (future use)

  SpaceLiftCargo* = object
    ## Cargo loaded on spacelift ship
    cargoType*: CargoType
    quantity*: int          # Number of units loaded (0 = empty)
    capacity*: int          # Maximum capacity (CL = Carry Limit)

  SpaceLiftShip* = object
    ## Individual spacelift unit (NOT a squadron)
    ## Per operations.md:1036 "individual units within the fleet"
    id*: string             # Ship identifier
    shipClass*: ShipClass   # ETAC or TroopTransport
    owner*: HouseId
    location*: SystemId
    isCrippled*: bool
    cargo*: SpaceLiftCargo  # What's loaded (marines, colonists, supplies)

proc newSpaceLiftShip*(id: string, shipClass: ShipClass, owner: HouseId,
                       location: SystemId): SpaceLiftShip =
  ## Create a new spacelift ship
  ## Ships start empty (cargo.quantity = 0)
  ## Cargo capacity loaded from config/military.toml

  let capacity = case shipClass
    of ShipClass.TroopTransport:
      globalMilitaryConfig.spacelift_capacity.troop_transport_capacity
    of ShipClass.ETAC:
      globalMilitaryConfig.spacelift_capacity.etac_capacity
    else: 0

  result = SpaceLiftShip(
    id: id,
    shipClass: shipClass,
    owner: owner,
    location: location,
    isCrippled: false,
    cargo: SpaceLiftCargo(
      cargoType: CargoType.None,
      quantity: 0,
      capacity: capacity
    )
  )

proc isEmpty*(ship: SpaceLiftShip): bool =
  ## Check if ship has no cargo loaded
  ship.cargo.quantity == 0

proc isFull*(ship: SpaceLiftShip): bool =
  ## Check if ship is at full cargo capacity
  ship.cargo.quantity >= ship.cargo.capacity

proc canLoad*(ship: SpaceLiftShip, cargoType: CargoType): bool =
  ## Check if ship can load the specified cargo type
  if ship.isCrippled:
    return false
  if ship.isFull:
    return false
  # Can only load if empty or already carrying same cargo type
  ship.cargo.cargoType == CargoType.None or
    ship.cargo.cargoType == cargoType

proc loadCargo*(ship: var SpaceLiftShip, cargoType: CargoType, quantity: int): bool =
  ## Load cargo onto ship
  ## Returns true if successful, false if unable
  if not ship.canLoad(cargoType):
    return false

  let spaceAvailable = ship.cargo.capacity - ship.cargo.quantity
  let amountToLoad = min(quantity, spaceAvailable)

  if amountToLoad <= 0:
    return false

  ship.cargo.cargoType = cargoType
  ship.cargo.quantity += amountToLoad
  return true

proc unloadCargo*(ship: var SpaceLiftShip): tuple[cargoType: CargoType, quantity: int] =
  ## Unload all cargo from ship
  ## Returns the cargo type and quantity that was unloaded
  result = (ship.cargo.cargoType, ship.cargo.quantity)
  ship.cargo.cargoType = CargoType.None
  ship.cargo.quantity = 0

proc `$`*(ship: SpaceLiftShip): string =
  ## String representation of spacelift ship
  let status = if ship.isCrippled: "*" else: ""
  let cargoStr = if ship.isEmpty:
    "empty"
  else:
    $ship.cargo.cargoType & ":" & $ship.cargo.quantity
  $ship.shipClass & status & "[" & cargoStr & "]"
