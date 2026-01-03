## Starting Fleet Initialization
##
## Creates starting fleets with specified compositions per game setup configuration.

import std/[options, tables, strutils]
import ../types/[core, game_state, fleet, squadron, ship]
import ../types/config/game_setup
import ../state/[engine, id_gen]
import ../entities/[fleet_ops, ship_ops, squadron_ops]
import ../utils

proc createStartingFleets*(
    state: var GameState,
    owner: HouseId,
    location: SystemId,
    fleetConfigs: seq[FleetConfig],
) =
  ## Creates starting fleets and all their child entities (squadrons, ships).

  for config in fleetConfigs:

    # 1. Create the Fleet
    let newFleet = fleet_ops.createFleet(state, owner, location)

    # 2. Create Squadrons and Ships for the Fleet
    for shipName in config.ships:
      let shipClass =
        try:
          parseEnum[ShipClass](shipName.replace("-", "").replace("_", ""))
        except:
          continue

      # Generate squadronId first to avoid circular dependency
      let squadronId = state.generateSquadronId()

      # Create flagship ship with the pre-generated squadronId
      let shipId = state.generateShipId()
      let shipConfig = shipConfig(shipClass)

      # Get house's current weapons tech for ship stats
      let house = state.house(owner).get()
      let weaponsTech = house.techTree.levels.wep

      # Create flagship using entity ops (applies WEP correctly)
      var flagship = ship_ops.newShip(
        shipClass, weaponsTech, shipId, squadronId, owner
      )

      # ETACs start fully loaded with PTU at game init (capacity from config)
      if shipClass == ShipClass.ETAC:
        let ptuCapacity = shipConfig.carryLimit # PTU capacity from ship config
        flagship.cargo = some(ShipCargo(
          cargoType: CargoClass.Colonists,
          quantity: ptuCapacity,
          capacity: ptuCapacity,
        ))

      # Add flagship to ship entity manager
      state.addShip(shipId, flagship)

      # Register ship indexes (bySquadron, byHouse)
      ship_ops.registerShipIndexes(state, shipId)

      # Create squadron using entity ops
      let newSquadron = squadron_ops.newSquadron(
        shipId, shipClass, squadronId, owner, location
      )

      # Add squadron to entity manager
      state.addSquadron(squadronId, newSquadron)

      # Register squadron in fleet's index
      squadron_ops.registerSquadronInFleet(state, squadronId, newFleet.id)

      # Add squadron to fleet's squadron list
      var updatedFleet = state.fleet(newFleet.id).get()
      updatedFleet.squadrons.add(squadronId)
      state.updateFleet(newFleet.id, updatedFleet)
