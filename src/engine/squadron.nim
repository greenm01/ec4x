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

import std/[sequtils, strutils, options]
import ship

# Forward declarations to avoid circular dependency
type
  SquadronId* = string
  SystemId* = uint
  HouseId* = string

type
  ShipClass* = enum
    ## Detailed ship classifications
    ## Each class has different Command Cost (CC) and capabilities
    scFighter,        # Fighter Squadron - based planet-side, not fleet-based
    scScout,          # Scout (SC) - ELI capable
    scRaider,         # Raider (RR) - Cloaking capable
    scDestroyer,      # Destroyer (DD) - Fast attack ship
    scCruiser,        # Cruiser (CR) - Medium warship
    scBattlecruiser,  # Battlecruiser (BC) - Heavy flagship
    scBattleship,     # Battleship (BS) - Capital ship
    scDreadnought,    # Dreadnought (DN) - Super capital
    scCarrier,        # Carrier (CV) - Fighter transport (3 FS)
    scSuperCarrier,   # Super Carrier (CX) - Fighter transport (5 FS)
    scStarbase,       # Starbase (SB) - Orbital fortress
    scETAC,           # Environmental Transformation And Colonization
    scTroopTransport, # Troop Transport - Marines and equipment
    scGroundBattery,  # Ground Battery (GB) - Planet-based defense
    scPlanetBreaker   # Planet-Breaker (PB) - Late-game shield penetration

  ShipStats* = object
    ## Combat and operational statistics for a ship
    attackStrength*: int     # AS - offensive firepower
    defenseStrength*: int    # DS - defensive shielding
    commandCost*: int        # CC - cost to assign to squadron
    commandRating*: int      # CR - for flagships, capacity to lead
    techLevel*: int          # Minimum tech level to build
    buildCost*: int          # Production cost to construct
    upkeepCost*: int         # Per-turn maintenance cost
    specialCapability*: string  # ELI, CLK, or empty

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

  SquadronFormation* = enum
    ## Formation roles for squadrons in fleet
    sfVanguard,   # Front line, first to engage
    sfMainLine,   # Main battle line
    sfReserve,    # Held in reserve
    sfScreen,     # Screening/picket duty
    sfRearGuard   # Rear guard, last to engage

## Ship class statistics
## Based on VBAM and EC specifications

proc getShipStats*(shipClass: ShipClass, techLevel: int = 0): ShipStats =
  ## Get default stats for a ship class
  ## Stats may be modified by tech level
  ##
  ## M2: Hardcoded defaults (temporary)
  ## M3: Will load from data/ships_default.toml
  ## M3: Game-specific overrides from game_config.toml
  ##
  ## TODO M3: Replace with TOML config loading
  ## TODO M3: Implement tech level modifiers
  case shipClass
  of scFighter:
    ShipStats(
      attackStrength: 1,
      defenseStrength: 1,
      commandCost: 0,      # Fighters don't use CC (planet-based)
      commandRating: 0,
      techLevel: 0,
      buildCost: 50,
      upkeepCost: 1,
      specialCapability: ""
    )
  of scScout:
    ShipStats(
      attackStrength: 1,
      defenseStrength: 2,
      commandCost: 1,
      commandRating: 1,
      techLevel: 0,
      buildCost: 100,
      upkeepCost: 2,
      specialCapability: "ELI" & $techLevel  # ELI level = tech level
    )
  of scRaider:
    ShipStats(
      attackStrength: 4,
      defenseStrength: 2,
      commandCost: 2,
      commandRating: 2,
      techLevel: 3,        # Advanced tech required
      buildCost: 300,
      upkeepCost: 5,
      specialCapability: "CLK" & $techLevel  # CLK level = tech level
    )
  of scDestroyer:
    ShipStats(
      attackStrength: 4,
      defenseStrength: 3,
      commandCost: 2,
      commandRating: 3,
      techLevel: 0,
      buildCost: 200,
      upkeepCost: 3,
      specialCapability: ""
    )
  of scCruiser:
    ShipStats(
      attackStrength: 6,
      defenseStrength: 4,
      commandCost: 3,
      commandRating: 5,
      techLevel: 1,
      buildCost: 400,
      upkeepCost: 5,
      specialCapability: ""
    )
  of scBattlecruiser:
    ShipStats(
      attackStrength: 8,
      defenseStrength: 5,
      commandCost: 4,
      commandRating: 7,
      techLevel: 2,
      buildCost: 600,
      upkeepCost: 8,
      specialCapability: ""
    )
  of scBattleship:
    ShipStats(
      attackStrength: 10,
      defenseStrength: 6,
      commandCost: 5,
      commandRating: 9,
      techLevel: 3,
      buildCost: 1000,
      upkeepCost: 12,
      specialCapability: ""
    )
  of scDreadnought:
    ShipStats(
      attackStrength: 15,
      defenseStrength: 8,
      commandCost: 7,
      commandRating: 12,
      techLevel: 5,
      buildCost: 2000,
      upkeepCost: 20,
      specialCapability: ""
    )
  of scCarrier:
    ShipStats(
      attackStrength: 2,   # Light combat capability
      defenseStrength: 4,
      commandCost: 4,
      commandRating: 6,
      techLevel: 2,
      buildCost: 800,
      upkeepCost: 10,
      specialCapability: "CAR3"  # Carries 3 fighter squadrons
    )
  of scSuperCarrier:
    ShipStats(
      attackStrength: 3,
      defenseStrength: 5,
      commandCost: 6,
      commandRating: 8,
      techLevel: 4,
      buildCost: 1500,
      upkeepCost: 18,
      specialCapability: "CAR5"  # Carries 5 fighter squadrons
    )
  of scStarbase:
    ShipStats(
      attackStrength: 12,
      defenseStrength: 10,
      commandCost: 0,      # Starbases don't use CC (orbital)
      commandRating: 0,
      techLevel: 2,
      buildCost: 1200,
      upkeepCost: 15,
      specialCapability: "ELI+2"  # +2 ELI modifier
    )
  of scETAC:
    ShipStats(
      attackStrength: 0,
      defenseStrength: 2,
      commandCost: 2,
      commandRating: 0,
      techLevel: 0,
      buildCost: 500,
      upkeepCost: 5,
      specialCapability: "COL"  # Colonization
    )
  of scTroopTransport:
    ShipStats(
      attackStrength: 0,
      defenseStrength: 3,
      commandCost: 2,
      commandRating: 0,
      techLevel: 0,
      buildCost: 400,
      upkeepCost: 4,
      specialCapability: "TRP"  # Troop transport
    )
  of scGroundBattery:
    ShipStats(
      attackStrength: 3,
      defenseStrength: 2,
      commandCost: 0,      # Ground batteries don't use CC (planet-based)
      commandRating: 0,
      techLevel: 0,
      buildCost: 100,
      upkeepCost: 1,
      specialCapability: ""
    )
  of scPlanetBreaker:
    ShipStats(
      attackStrength: 20,
      defenseStrength: 6,
      commandCost: 8,
      commandRating: 10,
      techLevel: 7,        # Late-game tech
      buildCost: 5000,
      upkeepCost: 50,
      specialCapability: "SHP"  # Shield penetration
    )

## Ship construction

proc newEnhancedShip*(shipClass: ShipClass, techLevel: int = 0, name: string = ""): EnhancedShip =
  ## Create a new ship with stats
  let stats = getShipStats(shipClass, techLevel)
  let shipType = case shipClass
    of scETAC, scTroopTransport:
      Spacelift
    else:
      Military

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
  sq.allShips().filterIt(it.shipType == Military)

proc spaceliftShips*(sq: Squadron): seq[EnhancedShip] =
  ## Get all spacelift ships in squadron
  sq.allShips().filterIt(it.shipType == Spacelift)

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
