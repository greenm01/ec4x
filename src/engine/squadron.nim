## Squadron management for EC4X
##
## Squadrons are tactical groupings of ships under a flagship's command.
## Each flagship has a Command Rating (CR) that limits the total Command Cost (CC)
## of ships that can be assigned to the squadron.
##
## Fleet Hierarchy: Fleet → Squadron → Ship

import std/[sequtils, strutils, options, math, strformat]
import ship
import ../common/types/[core, units]
import config/ships_config

export HouseId, FleetId, SystemId, SquadronId, ShipClass, ShipStats
export units.ShipType  # Use ShipType from types/units, not ship

type
  EnhancedShip* = object
    ## Enhanced ship with class and stats
    shipClass*: ShipClass
    shipType*: ShipType      # Military or Spacelift
    stats*: ShipStats
    isCrippled*: bool
    name*: string            # Optional ship name

  CarrierFighter* = object
    ## Fighter squadron embarked on carrier
    id*: string                # Fighter squadron ID
    commissionedTurn*: int     # When fighter was originally commissioned

  Squadron* = object
    ## A tactical unit of ships under flagship command
    id*: SquadronId
    flagship*: EnhancedShip
    ships*: seq[EnhancedShip]  # Ships under flagship command (excludes flagship)
    owner*: HouseId
    location*: SystemId

    # Carrier fighter operations (assets.md:2.4.1.1)
    embarkedFighters*: seq[CarrierFighter]  # Fighters aboard carriers (carrier-owned)

  SquadronFormation* {.pure.} = enum
    ## Formation roles for squadrons in fleet
    Vanguard,   # Front line, first to engage
    MainLine,   # Main battle line
    Reserve,    # Held in reserve
    Screen,     # Screening/picket duty
    RearGuard   # Rear guard, last to engage

## Ship class statistics
## Based on EC4X specifications

proc getShipStatsFromConfig(shipClass: ShipClass): ShipStats =
  ## Get base ship stats from config/ships.toml
  ## Uses globalShipsConfig loaded at module initialization

  let cfg = globalShipsConfig

  # Map ShipClass enum to config struct field
  let configStats = case shipClass
    of ShipClass.Fighter: cfg.fighter
    of ShipClass.Scout: cfg.scout
    of ShipClass.Raider: cfg.raider
    of ShipClass.Destroyer: cfg.destroyer
    of ShipClass.Cruiser: cfg.cruiser
    of ShipClass.LightCruiser: cfg.light_cruiser
    of ShipClass.HeavyCruiser: cfg.heavy_cruiser
    of ShipClass.Battlecruiser: cfg.battlecruiser
    of ShipClass.Battleship: cfg.battleship
    of ShipClass.Dreadnought: cfg.dreadnought
    of ShipClass.SuperDreadnought: cfg.super_dreadnought
    of ShipClass.Carrier: cfg.carrier
    of ShipClass.SuperCarrier: cfg.supercarrier
    of ShipClass.Starbase: cfg.starbase
    of ShipClass.ETAC: cfg.etac
    of ShipClass.TroopTransport: cfg.troop_transport
    of ShipClass.PlanetBreaker: cfg.planetbreaker

  # Convert config format to ShipStats format
  result = ShipStats(
    name: configStats.name,
    class: configStats.class,
    attackStrength: configStats.attack_strength,
    defenseStrength: configStats.defense_strength,
    commandCost: configStats.command_cost,
    commandRating: configStats.command_rating,
    techLevel: configStats.tech_level,
    buildCost: configStats.build_cost,
    upkeepCost: configStats.upkeep_cost,
    specialCapability: configStats.special_capability,
    carryLimit: if configStats.carry_limit.isSome: configStats.carry_limit.get else: 0
  )

proc getShipStats*(shipClass: ShipClass, techLevel: int = 0, configPath: string = ""): ShipStats =
  ## Get stats for a ship class from config
  ## Stats may be modified by tech level (WEP)
  ##
  ## Uses config/ships.toml loaded at module initialization
  ## configPath parameter ignored (kept for API compatibility)
  ##
  ## Per economy.md Section 4.6: "Upgrades improve the Attack Strength (AS)
  ## and Defense Strength (DS) of combat ships by 10% for each Weapons level
  ## (rounded down)."

  # Get base stats from config
  result = getShipStatsFromConfig(shipClass)

  # Apply WEP tech level modifiers (AS and DS only)
  # Base tech is WEP1 (techLevel = 1), each upgrade adds 10%
  # Formula: stat × (1.10 ^ (techLevel - 1)), rounded down
  if techLevel > 1:
    let weaponsMultiplier = pow(1.10, float(techLevel - 1))
    result.attackStrength = int(float(result.attackStrength) * weaponsMultiplier)
    result.defenseStrength = int(float(result.defenseStrength) * weaponsMultiplier)

## Ship construction

proc newEnhancedShip*(shipClass: ShipClass, techLevel: int = 0, name: string = ""): EnhancedShip =
  ## Create a new ship with stats
  let stats = getShipStats(shipClass, techLevel)
  let shipType = case shipClass
    of ShipClass.ETAC, ShipClass.TroopTransport:
      ShipType.Spacelift
    else:
      ShipType.Military

  EnhancedShip(
    shipClass: shipClass,
    shipType: shipType,
    stats: stats,
    isCrippled: false,
    name: name
  )

proc `$`*(ship: EnhancedShip): string =
  ## String representation of ship
  let status = if ship.isCrippled: " (crippled)" else: ""
  let name = if ship.name.len > 0: " \"" & ship.name & "\"" else: ""
  $ship.shipClass & name & status

## Squadron construction

proc newSquadron*(flagship: EnhancedShip, id: SquadronId = "",
                  owner: HouseId = "", location: SystemId = 0): Squadron =
  ## Create a new squadron with flagship
  Squadron(
    id: id,
    flagship: flagship,
    ships: @[],
    owner: owner,
    location: location,
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
    result += ship.stats.commandCost

proc availableCommandCapacity*(sq: Squadron): int =
  ## Calculate remaining command capacity
  sq.flagship.stats.commandRating - sq.totalCommandCost()

proc canAddShip*(sq: Squadron, ship: EnhancedShip): bool =
  ## Check if ship can be added to squadron
  ## Ship's CC must not exceed available CR
  if ship.stats.commandCost > sq.availableCommandCapacity():
    return false
  return true

proc addShip*(sq: var Squadron, ship: EnhancedShip): bool =
  ## Add ship to squadron if capacity allows
  ## Returns true on success, false if capacity exceeded
  if not sq.canAddShip(ship):
    return false
  sq.ships.add(ship)
  return true

proc removeShip*(sq: var Squadron, index: int): Option[EnhancedShip] =
  ## Remove ship at index from squadron
  ## Returns removed ship, or none if invalid index
  if index < 0 or index >= sq.ships.len:
    return none(EnhancedShip)

  let ship = sq.ships[index]
  sq.ships.delete(index)
  return some(ship)

proc allShips*(sq: Squadron): seq[EnhancedShip] =
  ## Get all ships including flagship
  result = @[sq.flagship]
  result.add(sq.ships)

proc combatStrength*(sq: Squadron): int =
  ## Calculate total attack strength of squadron
  ## Crippled ships have AS reduced by half
  result = 0
  for ship in sq.allShips():
    if ship.isCrippled:
      result += ship.stats.attackStrength div 2
    else:
      result += ship.stats.attackStrength

proc defenseStrength*(sq: Squadron): int =
  ## Calculate total defense strength of squadron
  result = 0
  for ship in sq.allShips():
    result += ship.stats.defenseStrength

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
  ## Squadron is destroyed if flagship is destroyed
  ## TODO: Implement proper destruction tracking (requires health system beyond crippled state)
  false

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

proc militaryShips*(sq: Squadron): seq[EnhancedShip] =
  ## Get all military ships in squadron
  sq.allShips().filterIt(it.shipType == ShipType.Military)

proc spaceliftShips*(sq: Squadron): seq[EnhancedShip] =
  ## Get all spacelift ships in squadron
  sq.allShips().filterIt(it.shipType == ShipType.Spacelift)

proc crippledShips*(sq: Squadron): seq[EnhancedShip] =
  ## Get all crippled ships in squadron
  sq.allShips().filterIt(it.isCrippled)

proc effectiveShips*(sq: Squadron): seq[EnhancedShip] =
  ## Get all non-crippled ships in squadron
  sq.allShips().filterIt(not it.isCrippled)

proc scoutShips*(sq: Squadron): seq[EnhancedShip] =
  ## Get all ships with ELI capability
  sq.allShips().filterIt(it.stats.specialCapability.startsWith("ELI"))

proc raiderShips*(sq: Squadron): seq[EnhancedShip] =
  ## Get all ships with cloaking capability
  sq.allShips().filterIt(it.stats.specialCapability.startsWith("CLK"))

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
  id: SquadronId = "",
  owner: HouseId = "",
  location: SystemId = 0,
  isCrippled: bool = false
): Squadron =
  ## Create a squadron with one ship (flagship only)
  ## This is the standard way to create squadrons for fleets
  let flagship = EnhancedShip(
    shipClass: shipClass,
    stats: getShipStats(shipClass, techLevel),
    isCrippled: isCrippled,
    name: ""
  )
  newSquadron(flagship, id, owner, location)

proc createFleetSquadrons*(
  ships: openArray[(ShipClass, int)],
  techLevel: int = 1,
  owner: HouseId = "",
  location: SystemId = 0
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
