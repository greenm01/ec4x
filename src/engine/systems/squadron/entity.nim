## Squadron management for EC4X
##
## Squadrons are tactical groupings of ships under a flagship's command.
## Each flagship has a Command Rating (CR) that limits the total Command Cost (CC)
## of ships that can be assigned to the squadron.
##
## Fleet Hierarchy: Fleet → Squadron → Ship

import std/[options, math, sequtils]
import ../../types/[core, ship, squadron]
import ../../state/entity_manager # For getEntity()
import ../ship/entity as ship_entity # Ship helper functions

proc getSquadronType*(shipClass: ShipClass): SquadronClass =
  ## Determine squadron type from ship class
  ## Used during commissioning and migration
  case shipClass
  of ShipClass.Scout: Intel
  of ShipClass.ETAC: Expansion
  of ShipClass.TroopTransport: Auxiliary
  of ShipClass.Fighter: Fighter
  else: Combat

## Squadron construction

proc newSquadron*(
    flagshipId: ShipId,
    flagshipClass: ShipClass,
    id: SquadronId = SquadronId(0),
    owner: HouseId = HouseId(0),
    location: SystemId = SystemId(0),
): Squadron =
  ## Create a new squadron with flagship
  ## DoD: Takes ShipId reference and ship class for squadron type determination
  let squadronType = getSquadronType(flagshipClass)

  Squadron(
    id: id,
    flagshipId: flagshipId,
    ships: @[],
    houseId: owner,
    location: location,
    squadronType: squadronType,
    embarkedFighters: @[],
  )

## Squadron operations

proc totalCommandCost*(sq: Squadron, ships: Ships): int =
  ## Calculate total command cost of ships in squadron (excluding flagship)
  result = 0
  for shipId in sq.ships:
    let ship = ships.entities.getEntity(shipId).get
    result += ship.commandCost()

proc availableCommandCapacity*(sq: Squadron, ships: Ships): int =
  ## Calculate remaining command capacity
  let flagship = ships.entities.getEntity(sq.flagshipId).get
  flagship.commandRating() - sq.totalCommandCost(ships)

proc canAddShip*(sq: Squadron, shipId: ShipId, ships: Ships): bool =
  ## Check if ship can be added to squadron
  ## Ship's CC must not exceed available CR
  let ship = ships.entities.getEntity(shipId).get
  if ship.commandCost() > sq.availableCommandCapacity(ships):
    return false
  return true

proc addShip*(sq: var Squadron, shipId: ShipId, ships: Ships): bool =
  ## Add ship to squadron if capacity allows
  ## Returns true on success, false if capacity exceeded
  if not sq.canAddShip(shipId, ships):
    return false
  sq.ships.add(shipId)
  return true

proc removeShip*(sq: var Squadron, index: int): Option[ShipId] =
  ## Remove ship at index from squadron
  ## Returns removed ship ID, or none if invalid index
  if index < 0 or index >= sq.ships.len:
    return none(ShipId)

  let shipId = sq.ships[index]
  sq.ships.delete(index)
  return some(shipId)

proc allShipIds*(sq: Squadron): seq[ShipId] =
  ## Get all ship IDs including flagship
  result = @[sq.flagshipId]
  result.add(sq.ships)

proc combatStrength*(sq: Squadron, ships: Ships): int =
  ## Calculate total attack strength of squadron
  ## Uses effectiveAttackStrength which handles crippled ships (AS halved)
  result = 0
  for shipId in sq.allShipIds():
    let ship = ships.entities.getEntity(shipId).get
    result += ship.effectiveAttackStrength()

proc defenseStrength*(sq: Squadron, ships: Ships): int =
  ## Calculate total defense strength of squadron
  result = 0
  for shipId in sq.allShipIds():
    let ship = ships.entities.getEntity(shipId).get
    result += ship.effectiveDefenseStrength()

proc isEmpty*(sq: Squadron): bool =
  ## Check if squadron has only flagship (no other ships)
  sq.ships.len == 0

proc shipCount*(sq: Squadron): int =
  ## Total number of ships including flagship
  sq.ships.len + 1

proc hasCombatShips*(sq: Squadron, ships: Ships): bool =
  ## Check if squadron has combat-capable ships
  for shipId in sq.allShipIds():
    let ship = ships.entities.getEntity(shipId).get
    if ship.stats.attackStrength > 0 and not ship.isCrippled:
      return true
  return false

proc isDestroyed*(sq: Squadron): bool =
  ## Check if squadron is completely destroyed
  ## Squadron is destroyed when all ships (including flagship) are destroyed
  sq.destroyed

proc crippleShip*(sq: var Squadron, index: int, ships: var Ships): bool =
  ## Cripple a ship in the squadron
  ## Index -1 means flagship
  ## Returns true if ship was crippled, false if already crippled or invalid
  if index == -1:
    var flagship = ships.entities.getEntity(sq.flagshipId).get
    if flagship.isCrippled:
      return false
    flagship.isCrippled = true
    ships.entities.updateEntity(sq.flagshipId, flagship)
    return true

  if index < 0 or index >= sq.ships.len:
    return false

  let shipId = sq.ships[index]
  var ship = ships.entities.getEntity(shipId).get
  if ship.isCrippled:
    return false

  ship.isCrippled = true
  ships.entities.updateEntity(shipId, ship)
  return true

## Squadron queries

proc militaryShips*(sq: Squadron, ships: Ships): seq[ShipId] =
  ## Get all military ship IDs in squadron (non-transport ships)
  sq.allShipIds().filterIt(not ships.entities.getEntity(it).get.isTransport())

proc spaceliftShips*(sq: Squadron, ships: Ships): seq[ShipId] =
  ## Get all transport ship IDs in squadron (ETAC/TroopTransport)
  sq.allShipIds().filterIt(ships.entities.getEntity(it).get.isTransport())

proc crippledShips*(sq: Squadron, ships: Ships): seq[ShipId] =
  ## Get all crippled ship IDs in squadron
  sq.allShipIds().filterIt(ships.entities.getEntity(it).get.isCrippled)

proc effectiveShips*(sq: Squadron, ships: Ships): seq[ShipId] =
  ## Get all non-crippled ship IDs in squadron
  sq.allShipIds().filterIt(not ships.entities.getEntity(it).get.isCrippled)

proc scoutShips*(sq: Squadron, ships: Ships): seq[ShipId] =
  ## Get all ship IDs with scout capability (ELI tech)
  sq.allShipIds().filterIt(ships.entities.getEntity(it).get.isScout())

proc hasScouts*(sq: Squadron, ships: Ships): bool =
  ## Check if squadron has any operational scouts

  sq.scoutShips(ships).filterIt(not ships.entities.getEntity(it).get.isCrippled).len > 0

proc raiderShips*(sq: Squadron, ships: Ships): seq[ShipId] =
  ## Get all ship IDs with cloaking capability (CLK tech)
  sq.allShipIds().filterIt(ships.entities.getEntity(it).get.isRaider())

proc isCloaked*(sq: Squadron, ships: Ships): bool =
  ## Check if squadron has cloaking capability
  ## All ships must be raiders and none crippled
  let raiders = sq.raiderShips(ships)
  if raiders.len == 0:
    return false

  # Check no crippled raiders
  for shipId in raiders:
    let ship = ships.entities.getEntity(shipId).get
    if ship.isCrippled:
      return false

  return true

## Squadron Construction Helpers (for Fleet creation)
##
## TODO: These helpers need to be moved to proper initialization code
## In DoD architecture, entity creation requires access to entity managers
## Should move to entities/squadron_ops.nim or game setup module with GameState access

# proc createSquadron*(
#   shipClass: ShipClass,
#   techLevel: int = 1,
#   id: SquadronId = SquadronId(0),
#   owner: HouseId = HouseId(0),
#   location: SystemId = SystemId(0),
#   isCrippled: bool = false
# ): Squadron =
#   ## Create a squadron with one ship (flagship only)
#   ## This is the standard way to create squadrons for fleets
#   ## DEPRECATED: Doesn't work with DoD - needs entity managers
#   discard

# proc createFleetSquadrons*(
#   ships: openArray[(ShipClass, int)],
#   techLevel: int = 1,
#   owner: HouseId = HouseId(0),
#   location: SystemId = SystemId(0)
# ): seq[Squadron] =
#   ## Create multiple squadrons for a fleet
#   ## ships: seq of (ShipClass, count) tuples
#   ## Returns: seq of Squadron
#   ## DEPRECATED: Doesn't work with DoD - needs entity managers
#   discard

## Carrier Fighter Operations (assets.md:2.4.1.1)

proc isCarrier*(sq: Squadron, ships: Ships): bool =
  ## Check if squadron flagship is a carrier (CV or CX)
  let flagship = ships.entities.getEntity(sq.flagshipId).get
  return flagship.shipClass in [ShipClass.Carrier, ShipClass.SuperCarrier]

proc getCarrierCapacity*(sq: Squadron, ships: Ships, acoLevel: int): int =
  ## Get carrier hangar capacity based on ship class and ACO tech level
  ## Per assets.md:2.4.1.1:
  ## - CV: 3 FS (base), 4 FS (ACO II), 5 FS (ACO III)
  ## - CX: 5 FS (base), 6 FS (ACO II), 8 FS (ACO III)
  ## ACO tech applies house-wide instantly

  if not sq.isCarrier(ships):
    return 0

  let flagship = ships.entities.getEntity(sq.flagshipId).get
  case flagship.shipClass
  of ShipClass.Carrier:
    # Per economy.md tech tables: ACO I (starting level) = 3FS, ACO II = 4FS, ACO III = 5FS
    # CRITICAL: ACO starts at level 1 (ACO I), not 0! (gameplay.md:1.2)
    case acoLevel
    of 1:
      3
    # ACO I (base level, ships start here)
    of 2:
      4
    # ACO II
    else:
      5 # ACO III+
  of ShipClass.SuperCarrier:
    # Per economy.md tech tables: ACO I = 5FS, ACO II = 6FS, ACO III = 8FS
    case acoLevel
    of 1:
      5
    # ACO I (base level, ships start here)
    of 2:
      6
    # ACO II
    else:
      8 # ACO III+
  else:
    0

proc getEmbarkedFighterCount*(sq: Squadron): int =
  ## Get number of fighters currently embarked on carrier
  return sq.embarkedFighters.len

proc hasAvailableHangarSpace*(sq: Squadron, ships: Ships, acoLevel: int): bool =
  ## Check if carrier has available hangar space
  let capacity = sq.getCarrierCapacity(ships, acoLevel)
  let current = sq.getEmbarkedFighterCount()
  return current < capacity

proc canLoadFighters*(sq: Squadron, ships: Ships, acoLevel: int, count: int): bool =
  ## Check if carrier can load specified number of fighters
  let capacity = sq.getCarrierCapacity(ships, acoLevel)
  let current = sq.getEmbarkedFighterCount()
  return (current + count) <= capacity
