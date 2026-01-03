## Squadron management for EC4X
##
## Squadrons are tactical groupings of ships under a flagship's command.
## Each flagship has a Command Rating (CR) that limits the total Command Cost (CC)
## of ships that can be assigned to the squadron.
##
## Fleet Hierarchy: Fleet → Squadron → Ship

import std/[options, math, sequtils]
import ../../types/[core, ship, squadron]
import ../../state/engine

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

proc totalCommandCost*(state: GameState, sq: Squadron): int32 =
  ## Calculate total command cost of ships in squadron (excluding flagship)
  result = 0
  for shipId in sq.ships:
    let ship = state.ship(shipId).get()
    result += ship.commandCost()

proc availableCommandCapacity*(state: GameState, sq: Squadron): int32 =
  ## Calculate remaining command capacity
  let flagship = state.ship(sq.flagshipId).get()
  flagship.commandRating() - state.totalCommandCost(sq)

proc canAddShip*(state: GameState, sq: Squadron, shipId: ShipId): bool =
  ## Check if ship can be added to squadron
  ## Ship's CC must not exceed available CR
  let ship = state.ship(shipId).get()
  if ship.commandCost() > state.availableCommandCapacity(sq):
    return false
  return true

proc allShipIds*(sq: Squadron): seq[ShipId] =
  ## Get all ship IDs including flagship
  result = @[sq.flagshipId]
  result.add(sq.ships)

proc combatStrength*(state: GameState, sq: Squadron): int32 =
  ## Calculate total attack strength of squadron
  ## Uses effectiveAttackStrength which handles crippled ships (AS halved)
  result = 0
  for shipId in sq.allShipIds():
    let ship = state.ship(shipId).get()
    result += ship.effectiveAttackStrength()

proc defenseStrength*(state: GameState, sq: Squadron): int32 =
  ## Calculate total defense strength of squadron
  result = 0
  for shipId in sq.allShipIds():
    let ship = state.ship(shipId).get()
    result += ship.effectiveDefenseStrength()

proc isEmpty*(sq: Squadron): bool =
  ## Check if squadron has only flagship (no other ships)
  sq.ships.len == 0

proc shipCount*(sq: Squadron): int32 =
  ## Total number of ships including flagship
  sq.ships.len + 1

proc hasCombatShips*(state: GameState, sq: Squadron): bool =
  ## Check if squadron has combat-capable ships
  for shipId in sq.allShipIds():
    let ship = state.ship(shipId).get()
    if ship.stats.attackStrength > 0 and not ship.isCrippled:
      return true
  return false

proc isDestroyed*(sq: Squadron): bool =
  ## Check if squadron is completely destroyed
  ## Squadron is destroyed when all ships (including flagship) are destroyed
  sq.destroyed

proc crippleShip*(state: var GameState, sq: Squadron, index: int): bool =
  ## Cripple a ship in the squadron
  ## Index -1 means flagship
  ## Returns true if ship was crippled, false if already crippled or invalid
  ## NOTE: Does not modify squadron, only updates ship entities in GameState
  if index == -1:
    let flagshipOpt = state.ship(sq.flagshipId)
    if flagshipOpt.isNone: return false
    var flagship = flagshipOpt.get()
    if flagship.isCrippled:
      return false
    flagship.isCrippled = true
    state.updateShip(sq.flagshipId, flagship)
    return true

  if index < 0 or index >= sq.ships.len:
    return false

  let shipId = sq.ships[index]
  let shipOpt = state.ship(shipId)
  if shipOpt.isNone: return false
  var ship = shipOpt.get()
  if ship.isCrippled:
    return false

  ship.isCrippled = true
  state.updateShip(shipId, ship)
  return true

## Squadron queries

proc militaryShips*(state: GameState, sq: Squadron): seq[ShipId] =
  ## Get all military ship IDs in squadron (non-transport ships)
  sq.allShipIds().filterIt(not state.ship(it).get().isTransport())

proc spaceliftShips*(state: GameState, sq: Squadron): seq[ShipId] =
  ## Get all transport ship IDs in squadron (ETAC/TroopTransport)
  sq.allShipIds().filterIt(state.ship(it).get().isTransport())

proc crippledShips*(state: GameState, sq: Squadron): seq[ShipId] =
  ## Get all crippled ship IDs in squadron
  sq.allShipIds().filterIt(state.ship(it).get().isCrippled)

proc effectiveShips*(state: GameState, sq: Squadron): seq[ShipId] =
  ## Get all non-crippled ship IDs in squadron
  sq.allShipIds().filterIt(not state.ship(it).get().isCrippled)

proc scoutShips*(state: GameState, sq: Squadron): seq[ShipId] =
  ## Get all ship IDs with scout capability (ELI tech)
  sq.allShipIds().filterIt(state.ship(it).get().isScout())

proc hasScouts*(state: GameState, sq: Squadron): bool =
  ## Check if squadron has any operational scouts

  sq.scoutShips(state).filterIt(not state.ship(it).get().isCrippled).len > 0

proc raiderShips*(state: GameState, sq: Squadron): seq[ShipId] =
  ## Get all ship IDs with cloaking capability (CLK tech)
  sq.allShipIds().filterIt(state.ship(it).get().isRaider())

proc isCloaked*(state: GameState, sq: Squadron): bool =
  ## Check if squadron has cloaking capability
  ## All ships must be raiders and none crippled
  let raiders = state.raiderShips(sq)
  if raiders.len == 0:
    return false

  # Check no crippled raiders
  for shipId in raiders:
    let ship = state.ship(shipId).get()
    if ship.isCrippled:
      return false

  return true

## Carrier Fighter Operations (assets.md:2.4.1.1)

proc isCarrier*(state: GameState, sq: Squadron): bool =
  ## Check if squadron flagship is a carrier (CV or CX)
  let flagship = state.ship(sq.flagshipId).get()
  return flagship.shipClass in [ShipClass.Carrier, ShipClass.SuperCarrier]

proc getCarrierCapacity*(state: GameState, sq: Squadron, acoLevel: int): int =
  ## Get carrier hangar capacity based on ship class and ACO tech level
  ## Per assets.md:2.4.1.1:
  ## - CV: 3 FS (base), 4 FS (ACO II), 5 FS (ACO III)
  ## - CX: 5 FS (base), 6 FS (ACO II), 8 FS (ACO III)
  ## ACO tech applies house-wide instantly

  if not state.isCarrier(sq):
    return 0

  let flagship = state.ship(sq.flagshipId).get()
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

proc hasAvailableHangarSpace*(state: GameState, sq: Squadron, acoLevel: int): bool =
  ## Check if carrier has available hangar space
  let capacity = state.getCarrierCapacity(sq, acoLevel)
  let current = sq.getEmbarkedFighterCount()
  return current < capacity

proc canLoadFighters*(state: GameState, sq: Squadron, acoLevel: int, count: int): bool =
  ## Check if carrier can load specified number of fighters
  let capacity = state.getCarrierCapacity(sq, acoLevel)
  let current = sq.getEmbarkedFighterCount()
  return (current + count) <= capacity
