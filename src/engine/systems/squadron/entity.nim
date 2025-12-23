## Squadron management for EC4X
##
## Squadrons are tactical groupings of ships under a flagship's command.
## Each flagship has a Command Rating (CR) that limits the total Command Cost (CC)
## of ships that can be assigned to the squadron.
##
## Fleet Hierarchy: Fleet → Squadron → Ship

import std/[options, math, sequtils]
import ../../types/[core, ship, squadron]
import ../ship/entity as ship_entity  # Ship helper functions

proc getSquadronType*(shipClass: ShipClass): SquadronType =
  ## Determine squadron type from ship class
  ## Used during commissioning and migration
  case shipClass
  of ShipClass.Scout:
    Intel
  of ShipClass.ETAC:
    Expansion
  of ShipClass.TroopTransport:
    Auxiliary
  of ShipClass.Fighter:
    Fighter
  else:
    Combat

## Squadron construction

proc newSquadron*(flagship: Ship, id: SquadronId = SquadronId(0),
                  owner: HouseId = HouseId(0), location: SystemId = SystemId(0)): Squadron =
  ## Create a new squadron with flagship
  ## Squadron type is determined from flagship ship class
  let squadronType = getSquadronType(flagship.shipClass)

  Squadron(
    id: id,
    flagship: flagship,
    ships: @[],
    houseId: owner,
    location: location,
    squadronType: squadronType,
    embarkedFighters: @[]
  )

proc `$`*(sq: Squadron): string =
  ## String representation of squadron
  let shipCount = sq.ships.len + 1  # +1 for flagship
  "Squadron " & sq.id & " [" & $shipCount & " ships, " & $sq.flagship.shipClass & " flagship]"

## Squadron operations

proc totalCommandCost*(sq: Squadron): int =
  ## Calculate total command cost of ships in squadron (excluding flagship)
  result = 0
  for ship in sq.ships:
    result += ship.commandCost()

proc availableCommandCapacity*(sq: Squadron): int =
  ## Calculate remaining command capacity
  sq.flagship.commandRating() - sq.totalCommandCost()

proc canAddShip*(sq: Squadron, ship: Ship): bool =
  ## Check if ship can be added to squadron
  ## Ship's CC must not exceed available CR
  if ship.commandCost() > sq.availableCommandCapacity():
    return false
  return true

proc addShip*(sq: var Squadron, ship: Ship): bool =
  ## Add ship to squadron if capacity allows
  ## Returns true on success, false if capacity exceeded
  if not sq.canAddShip(ship):
    return false
  sq.ships.add(ship)
  return true

proc removeShip*(sq: var Squadron, index: int): Option[Ship] =
  ## Remove ship at index from squadron
  ## Returns removed ship, or none if invalid index
  if index < 0 or index >= sq.ships.len:
    return none(Ship)

  let ship = sq.ships[index]
  sq.ships.delete(index)
  return some(ship)

proc allShips*(sq: Squadron): seq[Ship] =
  ## Get all ships including flagship
  result = @[sq.flagship]
  result.add(sq.ships)

proc combatStrength*(sq: Squadron): int =
  ## Calculate total attack strength of squadron
  ## Uses effectiveAttackStrength which handles crippled ships (AS halved)
  result = 0
  for ship in sq.allShips():
    result += ship.effectiveAttackStrength()

proc defenseStrength*(sq: Squadron): int =
  ## Calculate total defense strength of squadron
  result = 0
  for ship in sq.allShips():
    result += ship.effectiveDefenseStrength()

proc isEmpty*(sq: Squadron): bool =
  ## Check if squadron has only flagship (no other ships)
  sq.ships.len == 0

proc shipCount*(sq: Squadron): int =
  ## Total number of ships including flagship
  sq.ships.len + 1

proc hasCombatShips*(sq: Squadron): bool =
  ## Check if squadron has combat-capable ships
  for ship in sq.allShips():
    if ship.stats.attackStrength > 0 and not ship.isCrippled:
      return true
  return false

proc isDestroyed*(sq: Squadron): bool =
  ## Check if squadron is completely destroyed
  ## Squadron is destroyed when all ships (including flagship) are destroyed
  sq.destroyed

proc crippleShip*(sq: var Squadron, index: int): bool =
  ## Cripple a ship in the squadron
  ## Index -1 means flagship
  ## Returns true if ship was crippled, false if already crippled or invalid
  if index == -1:
    if sq.flagship.isCrippled:
      return false
    sq.flagship.isCrippled = true
    return true

  if index < 0 or index >= sq.ships.len:
    return false

  if sq.ships[index].isCrippled:
    return false

  sq.ships[index].isCrippled = true
  return true

## Squadron queries

proc militaryShips*(sq: Squadron): seq[Ship] =
  ## Get all military ships in squadron (non-transport ships)
  sq.allShips().filterIt(not it.isTransport())

proc spaceliftShips*(sq: Squadron): seq[Ship] =
  ## Get all transport ships in squadron (ETAC/TroopTransport)
  sq.allShips().filterIt(it.isTransport())

proc crippledShips*(sq: Squadron): seq[Ship] =
  ## Get all crippled ships in squadron
  sq.allShips().filterIt(it.isCrippled)

proc effectiveShips*(sq: Squadron): seq[Ship] =
  ## Get all non-crippled ships in squadron
  sq.allShips().filterIt(not it.isCrippled)

proc scoutShips*(sq: Squadron): seq[Ship] =
  ## Get all ships with scout capability (ELI tech)
  sq.allShips().filterIt(it.isScout())

proc hasScouts*(sq: Squadron): bool =
  ## Check if squadron has any operational scouts
  sq.scoutShips().filterIt(not it.isCrippled).len > 0

proc raiderShips*(sq: Squadron): seq[Ship] =
  ## Get all ships with cloaking capability (CLK tech)
  sq.allShips().filterIt(it.isRaider())

proc isCloaked*(sq: Squadron): bool =
  ## Check if squadron has cloaking capability
  ## All ships must be raiders and none crippled
  let raiders = sq.raiderShips()
  if raiders.len == 0:
    return false

  # Check no crippled raiders
  for ship in raiders:
    if ship.isCrippled:
      return false

  return true

## Squadron Construction Helpers (for Fleet creation)

proc createSquadron*(
  shipClass: ShipClass,
  techLevel: int = 1,
  id: SquadronId = SquadronId(0),
  owner: HouseId = HouseId(0),
  location: SystemId = SystemId(0),
  isCrippled: bool = false
): Squadron =
  ## Create a squadron with one ship (flagship only)
  ## This is the standard way to create squadrons for fleets
  var flagship = ship_entity.newShip(shipClass, int32(techLevel), "", ShipId(0), SquadronId(0))
  flagship.isCrippled = isCrippled
  newSquadron(flagship, id, owner, location)

proc createFleetSquadrons*(
  ships: openArray[(ShipClass, int)],
  techLevel: int = 1,
  owner: HouseId = HouseId(0),
  location: SystemId = SystemId(0)
): seq[Squadron] =
  ## Create multiple squadrons for a fleet
  ## ships: seq of (ShipClass, count) tuples
  ## Returns: seq of Squadron
  ##
  ## Example:
  ##   let squadrons = createFleetSquadrons(
  ##     @[(ShipClass.Corvette, 3), (ShipClass.Cruiser, 2)],
  ##     techLevel = 2,
  ##     owner = "house1",
  ##     location = 100
  ##   )
  result = @[]
  var counter: uint32 = 0
  for (shipClass, count) in ships:
    for i in 0..<count:
      let sq = createSquadron(
        shipClass,
        techLevel,
        id = SquadronId(counter),
        owner,
        location
      )
      result.add(sq)
      counter += 1

## Carrier Fighter Operations (assets.md:2.4.1.1)

proc isCarrier*(sq: Squadron): bool =
  ## Check if squadron flagship is a carrier (CV or CX)
  return sq.flagship.shipClass in [ShipClass.Carrier, ShipClass.SuperCarrier]

proc getCarrierCapacity*(sq: Squadron, acoLevel: int): int =
  ## Get carrier hangar capacity based on ship class and ACO tech level
  ## Per assets.md:2.4.1.1:
  ## - CV: 3 FS (base), 4 FS (ACO II), 5 FS (ACO III)
  ## - CX: 5 FS (base), 6 FS (ACO II), 8 FS (ACO III)
  ## ACO tech applies house-wide instantly

  if not sq.isCarrier:
    return 0

  case sq.flagship.shipClass
  of ShipClass.Carrier:
    # Per economy.md tech tables: ACO I (starting level) = 3FS, ACO II = 4FS, ACO III = 5FS
    # CRITICAL: ACO starts at level 1 (ACO I), not 0! (gameplay.md:1.2)
    case acoLevel
    of 1: 3     # ACO I (base level, ships start here)
    of 2: 4     # ACO II
    else: 5     # ACO III+
  of ShipClass.SuperCarrier:
    # Per economy.md tech tables: ACO I = 5FS, ACO II = 6FS, ACO III = 8FS
    case acoLevel
    of 1: 5     # ACO I (base level, ships start here)
    of 2: 6     # ACO II
    else: 8     # ACO III+
  else:
    0

proc getEmbarkedFighterCount*(sq: Squadron): int =
  ## Get number of fighters currently embarked on carrier
  return sq.embarkedFighters.len

proc hasAvailableHangarSpace*(sq: Squadron, acoLevel: int): bool =
  ## Check if carrier has available hangar space
  let capacity = sq.getCarrierCapacity(acoLevel)
  let current = sq.getEmbarkedFighterCount()
  return current < capacity

proc canLoadFighters*(sq: Squadron, acoLevel: int, count: int): bool =
  ## Check if carrier can load specified number of fighters
  let capacity = sq.getCarrierCapacity(acoLevel)
  let current = sq.getEmbarkedFighterCount()
  return (current + count) <= capacity
