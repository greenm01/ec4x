## Squadron management for EC4X
##
## Squadrons are tactical groupings of ships under a flagship's command.
## Each flagship has a Command Rating (CR) that limits the total Command Cost (CC)
## of ships that can be assigned to the squadron.
##
## Fleet Hierarchy: Fleet → Squadron → Ship
##
## MILESTONE 2 - Squadron implementation
## M1 uses direct Fleet→Ship for simplicity

import std/[sequtils, strutils, options, parsecfg, tables, os, math]
import ship
import ../common/types/[core, units]

export HouseId, FleetId, SystemId, SquadronId, ShipClass, ShipStats
export units.ShipType  # Use ShipType from types/units, not ship

type
  EnhancedShip* = object
    ## Enhanced ship with class and stats
    ## Replaces simple Ship type for M2+
    shipClass*: ShipClass
    shipType*: ShipType      # Military or Spacelift
    stats*: ShipStats
    isCrippled*: bool
    name*: string            # Optional ship name

  Squadron* = object
    ## A tactical unit of ships under flagship command
    id*: SquadronId
    flagship*: EnhancedShip
    ships*: seq[EnhancedShip]  # Ships under flagship command (excludes flagship)
    owner*: HouseId
    location*: SystemId

  SquadronFormation* {.pure.} = enum
    ## Formation roles for squadrons in fleet
    Vanguard,   # Front line, first to engage
    MainLine,   # Main battle line
    Reserve,    # Held in reserve
    Screen,     # Screening/picket duty
    RearGuard   # Rear guard, last to engage

## Ship class statistics
## Based on EC4X specifications

var shipConfigCache: Table[ShipClass, ShipStats]
var configLoaded = false

proc shipClassToConfigKey(shipClass: ShipClass): string =
  ## Convert ShipClass enum to config file key
  case shipClass
  of ShipClass.Fighter: "fighter"
  of ShipClass.Scout: "scout"
  of ShipClass.Raider: "raider"
  of ShipClass.Destroyer: "destroyer"
  of ShipClass.Cruiser: "cruiser"
  of ShipClass.LightCruiser: "light_cruiser"
  of ShipClass.HeavyCruiser: "heavy_cruiser"
  of ShipClass.Battlecruiser: "battlecruiser"
  of ShipClass.Battleship: "battleship"
  of ShipClass.Dreadnought: "dreadnought"
  of ShipClass.SuperDreadnought: "super_dreadnought"
  of ShipClass.Carrier: "carrier"
  of ShipClass.SuperCarrier: "super_carrier"
  of ShipClass.Starbase: "starbase"
  of ShipClass.ETAC: "etac"
  of ShipClass.TroopTransport: "troop_transport"
  of ShipClass.PlanetBreaker: "planet_breaker"

proc loadShipConfig(configPath: string = "config/ships.toml") =
  ## Load ship stats from config file
  ## Caches results for subsequent calls

  if configLoaded:
    return

  if not fileExists(configPath):
    raise newException(IOError, "Ship config file not found: " & configPath)

  let config = loadConfig(configPath)
  shipConfigCache = initTable[ShipClass, ShipStats]()

  for shipClass in ShipClass:
    let key = shipClassToConfigKey(shipClass)

    let stats = ShipStats(
      attackStrength: config.getSectionValue(key, "attack_strength", "0").parseInt(),
      defenseStrength: config.getSectionValue(key, "defense_strength", "0").parseInt(),
      commandCost: config.getSectionValue(key, "command_cost", "0").parseInt(),
      commandRating: config.getSectionValue(key, "command_rating", "0").parseInt(),
      techLevel: config.getSectionValue(key, "tech_level", "0").parseInt(),
      buildCost: config.getSectionValue(key, "build_cost", "0").parseInt(),
      upkeepCost: config.getSectionValue(key, "upkeep_cost", "0").parseInt(),
      specialCapability: config.getSectionValue(key, "special_capability", "")
    )

    shipConfigCache[shipClass] = stats

  configLoaded = true

proc getShipStats*(shipClass: ShipClass, techLevel: int = 0, configPath: string = ""): ShipStats =
  ## Get stats for a ship class from config file
  ## Stats may be modified by tech level (WEP)
  ##
  ## Loads from config/ships.toml (or configPath if specified)
  ## Game-specific overrides from game_config.toml not yet implemented
  ##
  ## Per economy.md Section 4.6: "Upgrades improve the Attack Strength (AS)
  ## and Defense Strength (DS) of combat ships by 10% for each Weapons level
  ## (rounded down)."
  ##
  ## TODO M3: Support game-specific overrides

  let path = if configPath.len > 0: configPath else: "config/ships.toml"

  if not configLoaded:
    loadShipConfig(path)

  result = shipConfigCache[shipClass]

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
    location: location
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
  ## For now, just check if flagship is crippled twice (conceptually)
  ## TODO M2: Implement proper destruction tracking
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
