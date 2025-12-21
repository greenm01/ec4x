## Squadron Operations for EC4X
##
## This module contains logic related to squadron management, such as adding/removing
## ships, calculating combat strength, and handling carrier operations.

import std/[sequtils, strutils, options, math, strformat]
import ../../types/military/[ship_types, squadron_types]
import ../../systems/military_assets/ship_ops # For newShip, getShipStats
import ../../../common/types/[core, units]

proc getSquadronType*(shipClass: ShipClass): SquadronType =
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

proc newSquadron*(flagship: Ship, id: SquadronId = "",
                  owner: HouseId = "", location: SystemId = 0): Squadron =
  Squadron(
    id: id,
    flagship: flagship,
    ships: @[],
    owner: owner,
    location: location,
    embarkedFighters: @[]
  )

proc `$`*(sq: Squadron): string =
  let shipCount = sq.ships.len + 1
  "Squadron " & sq.id & " [" & $shipCount & " ships, " & $sq.flagship.shipClass & " flagship]"

proc totalCommandCost*(sq: Squadron): int =
  result = 0
  for ship in sq.ships:
    result += ship.stats.commandCost

proc availableCommandCapacity*(sq: Squadron): int =
  sq.flagship.stats.commandRating - sq.totalCommandCost()

proc canAddShip*(sq: Squadron, ship: Ship): bool =
  if ship.stats.commandCost > sq.availableCommandCapacity():
    return false
  return true

proc addShip*(sq: var Squadron, ship: Ship): bool =
  if not sq.canAddShip(ship):
    return false
  sq.ships.add(ship)
  return true

proc removeShip*(sq: var Squadron, index: int): Option[Ship] =
  if index < 0 or index >= sq.ships.len:
    return none(Ship)
  let ship = sq.ships[index]
  sq.ships.delete(index)
  return some(ship)

proc allShips*(sq: Squadron): seq[Ship] =
  result = @[sq.flagship]
  result.add(sq.ships)

proc combatStrength*(sq: Squadron): int =
  result = 0
  for ship in sq.allShips():
    if ship.isCrippled:
      result += ship.stats.attackStrength div 2
    else:
      result += ship.stats.attackStrength

proc defenseStrength*(sq: Squadron): int =
  result = 0
  for ship in sq.allShips():
    result += ship.stats.defenseStrength

proc isEmpty*(sq: Squadron): bool =
  sq.ships.len == 0

proc shipCount*(sq: Squadron): int =
  sq.ships.len + 1

proc hasCombatShips*(sq: Squadron): bool =
  for ship in sq.allShips():
    if ship.stats.attackStrength > 0 and not ship.isCrippled:
      return true
  return false

proc isDestroyed*(sq: Squadron): bool =
  sq.destroyed

proc crippleShip*(sq: var Squadron, index: int): bool =
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

proc militaryShips*(sq: Squadron): seq[Ship] =
  sq.allShips().filterIt(it.shipType == ShipType.Military)

proc spaceliftShips*(sq: Squadron): seq[Ship] =
  sq.allShips().filterIt(it.shipType == ShipType.Spacelift)

proc crippledShips*(sq: Squadron): seq[Ship] =
  sq.allShips().filterIt(it.isCrippled)

proc effectiveShips*(sq: Squadron): seq[Ship] =
  sq.allShips().filterIt(not it.isCrippled)

proc scoutShips*(sq: Squadron): seq[Ship] =
  sq.allShips().filterIt(it.stats.specialCapability.startsWith("ELI"))

proc hasScouts*(sq: Squadron): bool =
  sq.scoutShips().filterIt(not it.isCrippled).len > 0

proc raiderShips*(sq: Squadron): seq[Ship] =
  sq.allShips().filterIt(it.stats.specialCapability.startsWith("CLK"))

proc isCloaked*(sq: Squadron): bool =
  let raiders = sq.raiderShips()
  if raiders.len == 0:
    return false
  for ship in raiders:
    if ship.isCrippled:
      return false
  return true

proc createSquadron*(
  shipClass: ShipClass,
  techLevel: int = 1,
  id: SquadronId = "",
  owner: HouseId = "",
  location: SystemId = 0,
  isCrippled: bool = false
): Squadron =
  let shipType = case shipClass
    of ShipClass.ETAC, ShipClass.TroopTransport:
      ShipType.Spacelift
    else:
      ShipType.Military
  let flagship = newShip(
    shipClass = shipClass,
    techLevel = techLevel,
    isCrippled = isCrippled,
    name = ""
  )
  newSquadron(flagship, id, owner, location)

proc createFleetSquadrons*(
  ships: openArray[(ShipClass, int)],
  techLevel: int = 1,
  owner: HouseId = "",
  location: SystemId = 0
): seq[Squadron] =
  result = @[]
  var counter = 0
  for (shipClass, count) in ships:
    for i in 0..<count:
      let sq = createSquadron(
        shipClass,
        techLevel,
        id = &"{owner}-sq-{counter}",
        owner,
        location
      )
      result.add(sq)
      counter += 1

proc isCarrier*(sq: Squadron): bool =
  return sq.flagship.shipClass in [ShipClass.Carrier, ShipClass.SuperCarrier]

proc getCarrierCapacity*(sq: Squadron, acoLevel: int): int =
  if not sq.isCarrier:
    return 0
  case sq.flagship.shipClass
  of ShipClass.Carrier:
    case acoLevel
    of 1: 3
    of 2: 4
    else: 5
  of ShipClass.SuperCarrier:
    case acoLevel
    of 1: 5
    of 2: 6
    else: 8
  else:
    0

proc getEmbarkedFighterCount*(sq: Squadron): int =
  return sq.embarkedFighters.len

proc hasAvailableHangarSpace*(sq: Squadron, acoLevel: int): bool =
  let capacity = sq.getCarrierCapacity(acoLevel)
  let current = sq.getEmbarkedFighterCount()
  return current < capacity

proc canLoadFighters*(sq: Squadron, acoLevel: int, count: int): bool =
  let capacity = sq.getCarrierCapacity(acoLevel)
  let current = sq.getEmbarkedFighterCount()
  return (current + count) <= capacity
