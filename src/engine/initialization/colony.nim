## @initialization/colony.nim
##
## Initializes new Colony objects based on the new DoD type system.

import std/options
import ../types/[core, colony, starmap, production, capacity]
import ../config/[economy_config, population_config]

proc initColony*(
  colonyId: ColonyId,
  systemId: SystemId,
  owner: HouseId,
  planetClass: PlanetClass,
  resources: ResourceRating,
  startingPTU: int32
): Colony =
  ## Initialize a new colony with all required fields from the new type system.
  
  let startingIU = (startingPTU *
    economy_config.globalEconomyConfig.colonization.starting_iu_percent
  ) div 100

  result = Colony(
    id: colonyId,
    systemId: systemId,
    owner: owner,

    # Population
    population: startingPTU,
    souls: (startingPTU * population_config.soulsPerPtu()).int32,
    populationUnits: startingPTU,
    populationTransferUnits: startingPTU,

    # Infrastructure & Economy
    infrastructure: economy_config.globalEconomyConfig.colonization.
      starting_infrastructure_level.int32,
    industrial: IndustrialUnits(
      units: startingIU.int32,
      investmentCost: economy_config.globalEconomyConfig.
        industrial_investment.base_cost.int32
    ),
    production: 0,
    grossOutput: 0,
    taxRate: 50,
    infrastructureDamage: 0.0'f32,

    # Planet characteristics
    planetClass: planetClass,
    resources: resources,

    # Queues and Projects
    underConstruction: none(ConstructionProjectId),
    constructionQueue: @[],
    repairQueue: @[],
    activeTerraforming: none(TerraformProject),

    # Toggles
    autoRepairEnabled: false,
    autoLoadingEnabled: true,
    autoReloadETACs: true,

    # Military asset IDs (all empty for new colony)
    unassignedSquadronIds: @[],
    fighterSquadronIds: @[],
    groundBatteryIds: @[],
    armyIds: @[],
    marineIds: @[],
    starbaseIds: @[],
    spaceportIds: @[],
    shipyardIds: @[],
    drydockIds: @[],
    
    # Status
    capacityViolation: CapacityViolation(
      capacityType: CapacityType.FighterSquadron,
      entity: EntityIdUnion(kind: CapacityType.FighterSquadron, colonyId: colonyId),
      current: 0,
      maximum: 0,
      excess: 0,
      severity: ViolationSeverity.None,
      graceTurnsRemaining: 0,
      violationTurn: 0
    ),
    planetaryShieldLevel: 0,
    blockaded: false,
    blockadedBy: @[],
    blockadeTurns: 0
  )