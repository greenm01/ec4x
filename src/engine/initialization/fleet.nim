## Fleet Initialization
##
## Creates starting fleets with specified compositions.
## Extracted from gamestate.nim as part of initialization refactoring.

import std/[options, tables, strutils]
import ../fleet
import ../squadron
import ../types/orders as order_types
import ../config/game_setup_config
import ../../common/types/[core, units]

proc createStartingFleets*(owner: HouseId, location: SystemId,
                          fleetConfigs: Table[int, game_setup_config.FleetConfig]): seq[Fleet] =
  ## Create starting fleets from individual fleet configurations
  ##
  ## Parameters:
  ##   - owner: House that owns these fleets
  ##   - location: Starting system ID (usually homeworld)
  ##   - fleetConfigs: Table of fleet configurations from game_setup/fleets.toml
  ##
  ## Returns:
  ##   Sequence of created fleets
  ##
  ## Used by: `initializeHousesAndHomeworlds` during game setup
  result = @[]

  for fleetIdx in 1..fleetConfigs.len:
    if not fleetConfigs.hasKey(fleetIdx):
      continue

    let config = fleetConfigs[fleetIdx]
    let fleetId = owner & "-fleet" & $fleetIdx

    var allSquadrons: seq[Squadron] = @[]

    # Process each ship in the configuration
    for shipName in config.ships:
      let shipClass = case shipName.toLower()
        of "etac": ShipClass.ETAC
        of "trooptransport", "troop_transport": ShipClass.TroopTransport
        of "scout": ShipClass.Scout
        of "destroyer": ShipClass.Destroyer
        of "lightcruiser", "light_cruiser": ShipClass.LightCruiser
        of "cruiser": ShipClass.Cruiser
        of "heavycruiser", "heavy_cruiser": ShipClass.HeavyCruiser
        of "battlecruiser", "battle_cruiser": ShipClass.BattleCruiser
        of "battleship": ShipClass.Battleship
        of "dreadnought": ShipClass.Dreadnought
        of "superdreadnought", "super_dreadnought": ShipClass.SuperDreadnought
        of "carrier": ShipClass.Carrier
        of "supercarrier", "super_carrier": ShipClass.SuperCarrier
        of "raider": ShipClass.Raider
        of "planetbreaker", "planet_breaker": ShipClass.PlanetBreaker
        else:
          continue  # Skip unknown ship classes

      # Check if this is a transport ship (ETAC/TroopTransport)
      if shipClass == ShipClass.ETAC or shipClass == ShipClass.TroopTransport:
        # Create squadron for ETAC/TroopTransport (single-ship squadron)
        let squadronId = owner & "-squadron" & $fleetIdx & "-" & $allSquadrons.len
        var squadron = createSquadron(
          shipClass = shipClass,
          techLevel = 1,
          id = squadronId,
          owner = owner,
          location = location,
          isCrippled = false
        )
        squadron.squadronType = getSquadronType(shipClass)  # Expansion or Auxiliary

        # Load cargo if specified (typically 1 PTU for colonization)
        if config.cargoPtu.isSome and shipClass == ShipClass.ETAC:
          let cargoQty = config.cargoPtu.get()
          squadron.flagship.cargo = some(ShipCargo(
            cargoType: CargoType.Colonists,
            quantity: cargoQty,
            capacity: squadron.flagship.stats.carryLimit
          ))

        allSquadrons.add(squadron)
      else:
        # Create combat squadron (one ship = flagship only, no escorts yet)
        let squadronId = owner & "-squadron" & $fleetIdx & "-" & $allSquadrons.len
        let squadron = createSquadron(
          shipClass = shipClass,
          techLevel = 1,  # Starting ships have base tech level
          id = squadronId,
          owner = owner,
          location = location,
          isCrippled = false
        )

        allSquadrons.add(squadron)

    # Create fleet with all squadrons (combat, expansion, auxiliary, intel)
    if allSquadrons.len > 0:
      let fleet = newFleet(
        squadrons = allSquadrons,
        id = fleetId,
        owner = owner,
        location = location
      )
      result.add(fleet)

type
  FleetConfig* = object
    ## Fleet configuration from game_setup/fleets.toml
    ships*: seq[string]
    cargoPtu*: Option[int]
