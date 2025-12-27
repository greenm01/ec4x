## Configuration Resolution
##
## Handles defaults, fallbacks, and backward compatibility for game setup configs.
## Part of the game initialization refactoring (Phase 2).

import std/[strutils, tables]
import ../config/game_setup_config
import ../types/ship

proc parseShipClassName*(name: string): ShipClass =
  ## Parse ship class name from config string
  ## Handles various naming formats (CamelCase, snake_case, etc.)
  case name.toLower()
  of "etac":
    ShipClass.ETAC
  of "scout":
    ShipClass.Scout
  of "destroyer":
    ShipClass.Destroyer
  of "lightcruiser", "light_cruiser":
    ShipClass.LightCruiser
  of "cruiser":
    ShipClass.Cruiser
  of "heavycruiser", "heavy_cruiser":
    ShipClass.HeavyCruiser
  of "battlecruiser", "battle_cruiser":
    ShipClass.BattleCruiser
  of "battleship":
    ShipClass.Battleship
  of "dreadnought":
    ShipClass.Dreadnought
  of "superdreadnought", "super_dreadnought":
    ShipClass.SuperDreadnought
  of "carrier":
    ShipClass.Carrier
  of "supercarrier", "super_carrier":
    ShipClass.SuperCarrier
  of "raider":
    ShipClass.Raider
  of "planetbreaker", "planet_breaker":
    ShipClass.PlanetBreaker
  else:
    raise newException(ValueError, "Unknown ship class: " & name)

proc resolveFleetConfiguration*(config: GameSetupConfig): seq[seq[ShipClass]] =
  ## Resolve fleet configuration from game setup config
  ## Returns sequence of fleet compositions (each fleet is a seq[ShipClass])

  result = @[]

  # Parse each fleet from the configuration
  for fleet in config.startingFleet.fleets:
    var shipClasses: seq[ShipClass] = @[]
    for shipName in fleet.ships:
      try:
        shipClasses.add(parseShipClassName(shipName))
      except ValueError as e:
        # Skip invalid ship names with warning
        discard
    if shipClasses.len > 0:
      result.add(shipClasses)

proc getStartingTreasury*(config: GameSetupConfig): int =
  ## Get starting treasury from config
  ## Returns configured treasury value
  result = config.starting_resources.treasury
