## @entities/colony_ops.nim
##
## Write API for creating, destroying, and modifying Colony entities.
## Ensures that all secondary indexes (`bySystem`, `byOwner`) are kept consistent.
import std/[tables, sequtils, options]
import ../state/[engine, id_gen]
import ../types/[game_state, core, colony, starmap, production, capacity]
import ../globals
import ../utils

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
  ## PTU size loaded from config/economy.toml
  let colonyId = state.generateColonyId()
  let totalSouls = ptuCount * soulsPerPtu()

  let newColony = Colony(
    id: colonyId,
    systemId: systemId,
    owner: owner,
    population: totalSouls div 1_000_000,
    souls: totalSouls,
    populationUnits: ptuCount,
    populationTransferUnits: ptuCount,
    infrastructure: gameConfig.economy.colonization.startingInfrastructureLevel,
    industrial: IndustrialUnits(
      units:
        (ptuCount * gameConfig.economy.colonization.startingIuPercent) div 100,
      investmentCost: gameConfig.economy.industrialInvestment.baseCost,
    ),
    # planetClass and resources removed - stored in System, not Colony
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
    # Entity references (bucket-level tracking)
    groundUnitIds: @[],  # All ground units (batteries, armies, marines, shields)
    neoriaIds: @[],      # Production facilities (spaceport, shipyard, drydock)
    kastraIds: @[],      # Defensive facilities (starbase)
    blockaded: false,
    blockadedBy: @[],
    blockadeTurns: 0,
  )

  # Add to entity manager and update indices
  state.addColony(colonyId, newColony)
  state.colonies.bySystem[systemId] = colonyId
  if not state.colonies.byOwner.hasKey(owner):
    state.colonies.byOwner[owner] = @[]
  state.colonies.byOwner[owner].add(colonyId)

  result = colonyId

proc destroyColony*(state: var GameState, colonyId: ColonyId) =
  ## Destroys a colony, removing it from the entity manager and all indexes.
  let colonyOpt = state.colony(colonyId)
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

  state.delColony(colonyId)

proc changeColonyOwner*(state: var GameState, colonyId: ColonyId, newOwner: HouseId) =
  ## Transfers ownership of a colony, updating the `byOwner` index.
  let colonyOpt = state.colony(colonyId)
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
  state.updateColony(colonyId, colony)
