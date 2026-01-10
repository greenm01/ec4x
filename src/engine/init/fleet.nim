## Starting Fleet Initialization
##
## Creates starting fleets with specified compositions per game setup configuration.

import std/[options, tables, strutils]
import ../types/[core, game_state, fleet, ship]
import ../types/config/game_setup
import ../state/[engine, id_gen]
import ../entities/[fleet_ops, ship_ops]
import ../utils

proc createStartingFleets*(
    state: var GameState,
    owner: HouseId,
    location: SystemId,
    fleetConfigs: seq[FleetConfig],
) =
  ## Creates starting fleets and ships directly (no squadrons).

  for config in fleetConfigs:

    # 1. Create the Fleet
    let newFleet = state.createFleet(owner, location)

    # 2. Create Ships for the Fleet
    for shipName in config.ships:
      let shipClass =
        try:
          parseEnum[ShipClass](shipName.replace("-", "").replace("_", ""))
        except:
          continue

      # Create ship ID
      let shipId = state.generateShipId()
      let shipConfig = shipConfig(shipClass)

      # Get house's current weapons tech for ship stats
      let house = state.house(owner).get()
      let weaponsTech = house.techTree.levels.wep

      # Create ship using entity ops (applies WEP correctly)
      var newShip = ship_ops.newShip(
        shipClass, weaponsTech, shipId, newFleet.id, owner
      )

      # ETACs start fully loaded with PTU at game init (capacity from config)
      if shipClass == ShipClass.ETAC:
        let ptuCapacity = shipConfig.carryLimit # PTU capacity from ship config
        newShip.cargo = some(ShipCargo(
          cargoType: CargoClass.Colonists,
          quantity: ptuCapacity,
          capacity: ptuCapacity,
        ))

      # Add ship to ship entity manager
      state.addShip(shipId, newShip)

      # Register ship indexes (byFleet, byHouse)
      state.registerShipIndexes(shipId)

      # Add ship to fleet's ship list
      var updatedFleet = state.fleet(newFleet.id).get()
      updatedFleet.ships.add(shipId)
      state.updateFleet(newFleet.id, updatedFleet)
