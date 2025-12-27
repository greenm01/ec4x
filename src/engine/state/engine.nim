# src/engine/
# └── state/
#    ├── engine.nim      # Game State accessors
#    ├── id_gen.nim      # Counter logic
#    └── queries.nim     # Spatial/Complex Iterators (shipsInSystem, enemiesNear)

import std/[tables, options]
import ./entity_manager
import
  ../types/[
    core, game_state, fleet, ship, squadron, ground_unit, house, colony, facilities,
    production, intelligence, starmap, population,
  ]

proc getHouse*(state: GameState, id: HouseId): Option[House] =
  state.houses.entities.getEntity(id)

proc getSystem*(state: GameState, id: SystemId): Option[System] =
  state.systems.entities.getEntity(id)

proc getColony*(state: GameState, id: ColonyId): Option[Colony] =
  state.colonies.entities.getEntity(id)

proc getFleet*(state: GameState, id: FleetId): Option[Fleet] =
  state.fleets.entities.getEntity(id)

proc getShip*(state: GameState, id: ShipId): Option[Ship] =
  state.ships.entities.getEntity(id)

proc getSquadrons*(state: GameState, id: SquadronId): Option[Squadron] =
  state.squadrons.entities.getEntity(id)

proc getGroundUnit*(state: GameState, id: GroundUnitId): Option[GroundUnit] =
  state.groundUnits.entities.getEntity(id)

proc getStarbase*(state: GameState, id: StarbaseId): Option[Starbase] =
  state.starbases.entities.getEntity(id)

proc getSpaceport*(state: GameState, id: SpaceportId): Option[Spaceport] =
  state.spaceports.entities.getEntity(id)

proc getShipyard*(state: GameState, id: ShipyardId): Option[Shipyard] =
  state.shipyards.entities.getEntity(id)

proc getDrydock*(state: GameState, id: DrydockId): Option[Drydock] =
  state.drydocks.entities.getEntity(id)

proc getConstructionProject*(
    state: GameState, id: ConstructionProjectId
): Option[ConstructionProject] =
  state.constructionProjects.entities.getEntity(id)

proc getRepairProject*(state: GameState, id: RepairProjectId): Option[RepairProject] =
  state.repairProjects.entities.getEntity(id)

proc getPopulationTransfer*(
    state: GameState, id: PopulationTransferId
): Option[PopulationInTransit] =
  state.populationTransfers.entities.getEntity(id)

proc getIntel*(state: GameState, id: HouseId): Option[IntelligenceDatabase] =
  ## Direct table lookup for intelligence memory
  if state.intelligence.contains(id):
    return some(state.intelligence[id])
  return none(IntelligenceDatabase)
