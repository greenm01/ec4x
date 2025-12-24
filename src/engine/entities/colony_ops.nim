## @entities/colony_ops.nim
##
## Write API for creating, destroying, and modifying Colony entities.
## Ensures that all secondary indexes (`bySystem`, `byOwner`) are kept consistent.
import std/[tables, sequtils, options]
import ../state/[id_gen, entity_manager, game_state as gs_helpers]
import ../types/[game_state, core, colony, starmap, production, capacity]
import ../config/[economy_config, population_config]

proc establishColony*(
    state: var GameState,
    systemId: SystemId,
    owner: HouseId,
    planetClass: PlanetClass,
    resources: ResourceRating,
    ptuCount: int32 = 3,
): ColonyId =
  ## Create a new ETAC-colonized system with specified PTU
  ## Default: 3 PTU (150k souls) for standard ETAC colonization
  ## PTU size loaded from config/population.toml
  let colonyId = state.generateColonyId()
  let totalSouls = ptuCount * population_config.soulsPerPtu().int32

  let newColony = Colony(
    id: colonyId,
    systemId: systemId,
    owner: owner,
    population: totalSouls div 1_000_000,
    souls: totalSouls,
    populationUnits: ptuCount,
    populationTransferUnits: ptuCount,
    infrastructure:
      economy_config.globalEconomyConfig.colonization.starting_infrastructure_level.int32,
    industrial: IndustrialUnits(
      units:
        (
          ptuCount *
          economy_config.globalEconomyConfig.colonization.starting_iu_percent.int32
        ) div 100,
      investmentCost:
        economy_config.globalEconomyConfig.industrial_investment.base_cost.int32,
    ),
    planetClass: planetClass,
    resources: resources,
    production: 0,
    grossOutput: 0,
    taxRate: 50, # Default 50% tax rate
    infrastructureDamage: 0.0,
    underConstruction: none(ConstructionProjectId),
    constructionQueue: @[],
    repairQueue: @[],
    autoRepairEnabled: false, # Default OFF
    autoLoadingEnabled: true, # Default ON
    autoReloadETACs: true, # Default ON
    activeTerraforming: none(TerraformProject),
    unassignedSquadronIds: @[],
    fighterSquadronIds: @[],
    capacityViolation: CapacityViolation(
      severity: ViolationSeverity.None,
      graceTurnsRemaining: 0,
      violationTurn: 0,
      capacityType: CapacityType.FighterSquadron,
      entity: EntityIdUnion(kind: CapacityType.FighterSquadron, colonyId: colonyId),
      current: 0,
      maximum: 0,
      excess: 0,
    ),
    starbaseIds: @[],
    spaceportIds: @[],
    shipyardIds: @[],
    drydockIds: @[],
    planetaryShieldLevel: 0,
    groundBatteryIds: @[],
    armyIds: @[],
    marineIds: @[],
    blockaded: false,
    blockadedBy: @[],
    blockadeTurns: 0,
  )

  # Add to entity manager and update indices
  state.colonies.entities.addEntity(colonyId, newColony)
  state.colonies.bySystem[systemId] = colonyId
  if not state.colonies.byOwner.hasKey(owner):
    state.colonies.byOwner[owner] = @[]
  state.colonies.byOwner[owner].add(colonyId)

  result = colonyId

proc destroyColony*(state: var GameState, colonyId: ColonyId) =
  ## Destroys a colony, removing it from the entity manager and all indexes.
  let colonyOpt = gs_helpers.getColony(state, colonyId)
  if colonyOpt.isNone:
    return
  let colony = colonyOpt.get()

  if state.colonies.byOwner.contains(colony.owner):
    var ownerColonies = state.colonies.byOwner[colony.owner]
    ownerColonies.keepIf(
      proc(id: ColonyId): bool =
        id != colonyId
    )
    state.colonies.byOwner[colony.owner] = ownerColonies

  if state.colonies.bySystem.contains(colony.systemId):
    state.colonies.bySystem.del(colony.systemId)

  state.colonies.entities.removeEntity(colonyId)

proc changeColonyOwner*(state: var GameState, colonyId: ColonyId, newOwner: HouseId) =
  ## Transfers ownership of a colony, updating the `byOwner` index.
  let colonyOpt = gs_helpers.getColony(state, colonyId)
  if colonyOpt.isNone:
    return
  var colony = colonyOpt.get()

  let oldOwner = colony.owner
  if oldOwner == newOwner:
    return

  if state.colonies.byOwner.contains(oldOwner):
    var oldOwnerColonies = state.colonies.byOwner[oldOwner]
    oldOwnerColonies.keepIf(
      proc(id: ColonyId): bool =
        id != colonyId
    )
    state.colonies.byOwner[oldOwner] = oldOwnerColonies

  var newOwnerColonies = state.colonies.byOwner.getOrDefault(newOwner, @[])
  newOwnerColonies.add(colonyId)
  state.colonies.byOwner[newOwner] = newOwnerColonies

  colony.owner = newOwner
  state.colonies.entities.updateEntity(colonyId, colony)
