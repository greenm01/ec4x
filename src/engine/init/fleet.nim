## Starting Fleet Initialization
##
## Creates starting fleets with specified compositions per game setup configuration.

import std/[options, tables, strutils]
import ../types/[core, game_state, fleet, squadron, ship]
import ../types/config/game_setup
import ../state/[engine as gs_helper, id_gen, entity_manager]
import ../entities/fleet_ops
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
      let shipConfig = getShipConfig(shipClass)

      # ETACs start fully loaded with PTU at game init (capacity from config)
      var shipCargo: Option[ShipCargo] = none(ShipCargo)
      if shipClass == ShipClass.ETAC:
        let ptuCapacity = shipConfig.carryLimit # PTU capacity from ship config
        shipCargo = some(ShipCargo(
          cargoType: CargoType.Colonists,
          quantity: ptuCapacity,
          capacity: ptuCapacity,
        ))
      # Get house's current weapons tech for ship stats
      let house = state.houses.entities.getEntity(owner).get()
      let weaponsTech = house.techTree.levels.weaponsTech

      let flagship = Ship(
        id: shipId,
        houseId: owner,
        squadronId: squadronId,
        shipClass: shipClass,
        stats: ShipStats(
          attackStrength: shipConfig.attack_strength,
          defenseStrength: shipConfig.defense_strength,
          weaponsTech: weaponsTech,
        ),
        isCrippled: false,
        cargo: shipCargo,
      )

      # Add flagship to ship entity manager and index
      state.ships.entities.addEntity(shipId, flagship)
      state.ships.bySquadron.mgetOrPut(squadronId, @[]).add(shipId)

      # Create squadron with the flagship (manually, not via createSquadron)
      let newSquadron = Squadron(
        id: squadronId,
        flagshipId: shipId,
        ships: @[], # No additional ships yet
        houseId: owner,
        location: location,
        destroyed: false,
        squadronType: SquadronType.Combat,
        embarkedFighters: @[],
      )

      # Add squadron to entity manager and indices
      state.squadrons.entities.addEntity(squadronId, newSquadron)
      state.squadrons.byFleet.mgetOrPut(newFleet.id, @[]).add(squadronId)

      # Add squadron to fleet's squadron list
      var updatedFleet = state.getFleet(newFleet.id).get()
      updatedFleet.squadrons.add(squadronId)
      state.fleets.entities.updateEntity(newFleet.id, updatedFleet)
