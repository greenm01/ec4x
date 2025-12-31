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
    production, intel, starmap, population,
  ]

proc house*(state: GameState, id: HouseId): Option[House] =
  state.houses.entities.entity(id)

proc system*(state: GameState, id: SystemId): Option[System] =
  state.systems.entities.entity(id)

proc colony*(state: GameState, id: ColonyId): Option[Colony] =
  state.colonies.entities.entity(id)

proc fleet*(state: GameState, id: FleetId): Option[Fleet] =
  state.fleets.entities.entity(id)

proc ship*(state: GameState, id: ShipId): Option[Ship] =
  state.ships.entities.entity(id)

proc squadrons*(state: GameState, id: SquadronId): Option[Squadron] =
  state.squadrons.entities.entity(id)

proc groundUnit*(state: GameState, id: GroundUnitId): Option[GroundUnit] =
  state.groundUnits.entities.entity(id)

proc starbase*(state: GameState, id: StarbaseId): Option[Starbase] =
  state.starbases.entities.entity(id)

proc spaceport*(state: GameState, id: SpaceportId): Option[Spaceport] =
  state.spaceports.entities.entity(id)

proc shipyard*(state: GameState, id: ShipyardId): Option[Shipyard] =
  state.shipyards.entities.entity(id)

proc drydock*(state: GameState, id: DrydockId): Option[Drydock] =
  state.drydocks.entities.entity(id)

proc constructionProject*(
    state: GameState, id: ConstructionProjectId
): Option[ConstructionProject] =
  state.constructionProjects.entities.entity(id)

proc repairProject*(state: GameState, id: RepairProjectId): Option[RepairProject] =
  state.repairProjects.entities.entity(id)

proc populationTransfer*(
    state: GameState, id: PopulationTransferId
): Option[PopulationInTransit] =
  state.populationTransfers.entities.entity(id)

proc intel*(state: GameState, id: HouseId): Option[IntelligenceDatabase] =
  ## Direct table lookup for intelligence memory
  if state.intelligence.contains(id):
    return some(state.intelligence[id])
  return none(IntelligenceDatabase)
