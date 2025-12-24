## @initialization/fleet.nim
##
## Creates starting fleets with specified compositions, compatible with the new DoD type system.

import std/[options, tables, strutils]
import ../types/[core, game_state, fleet, squadron, ship]
import ../state/[game_state as gs_helper, id_gen, entity_manager]
import ../config/game_setup_config
import ../entities/fleet_ops

proc createStartingFleets*(
    state: var GameState,
    owner: HouseId,
    location: SystemId,
    fleetConfigs: Table[int, game_setup_config.FleetConfig],
) =
  ## Creates starting fleets and all their child entities (squadrons, ships).

  for fleetIdx in 1 .. fleetConfigs.len:
    if not fleetConfigs.hasKey(fleetIdx):
      continue

    let config = fleetConfigs[fleetIdx]

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
      let flagship = Ship(
        id: shipId,
        squadronId: squadronId,
        shipClass: shipClass,
        shipRole: ShipRole.Escort, # Will be set properly by config later
        stats: ShipStats(), # Default stats, will be populated from config
        isCrippled: false,
        name: "",
        cargo: none(ShipCargo),
      )

      # Add flagship to ship entity manager and index
      state.ships.entities.addEntity(shipId, flagship)
      state.ships.bySquadron.mgetOrPut(squadronId, @[]).add(shipId)

      # Create squadron with the flagship (manually, not via createSquadron)
      let newSquadron = Squadron(
        id: squadronId,
        flagship: flagship,
        ships: @[], # No additional ships yet
        houseId: owner,
        location: location,
        destroyed: false,
        squadronType: SquadronType.Combat, # Default, adjust as needed
      )

      # Add squadron to entity manager and indices
      state[].squadrons[].entities.addEntity(squadronId, newSquadron)
      state[].squadrons[].byFleet.mgetOrPut(newFleet.id, @[]).add(squadronId)

      # Add squadron to fleet's squadron list
      var updatedFleet = state.getFleet(newFleet.id).get()
      updatedFleet.squadrons.add(squadronId)
      state.fleets.entities.updateEntity(newFleet.id, updatedFleet)
