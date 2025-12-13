## Colony Initialization
##
## Creates homeworld and ETAC-colonized systems.
## Extracted from gamestate.nim as part of initialization refactoring.

import std/options
import ../gamestate
import ../config/[game_setup_config, facilities_config]
import ../prestige/effects as prestige_effects
import ../research/effects as research_effects
import ../../common/types/[core, planets]
import ../economy/types as econ_types

proc createHomeColony*(systemId: SystemId, owner: HouseId): Colony =
  ## Create a starting homeworld colony per gameplay.md:1.2
  ## Loads configuration from game_setup/standard.toml
  let setupConfig = game_setup_config.globalGameSetupConfig
  let homeworldCfg = setupConfig.homeworld

  # Parse planet class and resources from config
  let planetClass = game_setup_config.parsePlanetClass(homeworldCfg.planet_class)
  let resources = game_setup_config.parseResourceRating(homeworldCfg.raw_quality)

  result = Colony(
    systemId: systemId,
    owner: owner,
    population: homeworldCfg.population_units,
    souls: homeworldCfg.population_units * 1_000_000,  # Convert PU to souls
    populationUnits: homeworldCfg.population_units,
    populationTransferUnits: homeworldCfg.population_units,
    infrastructure: homeworldCfg.colony_level,
    industrial: econ_types.IndustrialUnits(
      units: homeworldCfg.industrial_units,
      investmentCost: econ_types.BASE_IU_COST
    ),
    planetClass: planetClass,
    resources: resources,
    buildings: @[BuildingType.Shipyard],  # Start with basic shipyard
    production: 0,
    grossOutput: 0,  # Will be calculated by income engine
    taxRate: 50,  # Default 50% tax rate
    infrastructureDamage: 0.0,
    underConstruction: none(ConstructionProject),
    constructionQueue: @[],
    repairQueue: @[],
    autoRepairEnabled: false,  # Default OFF - player must enable
    autoLoadingEnabled: true,  # Default ON - auto-load fighters to carriers
    autoReloadETACs: true,     # Default ON - auto-load PTUs onto ETACs
    unassignedSquadrons: @[],
    unassignedSpaceLiftShips: @[],
    fighterSquadrons: @[],
    capacityViolation: CapacityViolation(
      active: false,
      violationType: "",
      turnsRemaining: 0,
      violationTurn: 0
    ),
    starbases: block:
      # Create starbases from config
      var bases: seq[Starbase] = @[]
      for i in 1..setupConfig.starting_facilities.starbases:
        bases.add(Starbase(
          id: $systemId & "-starbase-" & $i,
          commissionedTurn: 0,
          isCrippled: false
        ))
      bases,
    spaceports: block:
      # Create spaceports from config
      var ports: seq[Spaceport] = @[]
      let baseDocks = facilities_config.globalFacilitiesConfig.spaceport.docks
      let cstLevel = 1  # Starting tech level
      let effectiveDocks = research_effects.calculateEffectiveDocks(baseDocks, cstLevel)
      for i in 1..setupConfig.starting_facilities.spaceports:
        ports.add(Spaceport(
          id: $systemId & "-spaceport-" & $i,
          commissionedTurn: 0,
          baseDocks: baseDocks,
          effectiveDocks: effectiveDocks,
          constructionQueue: @[],
          activeConstructions: @[]
        ))
      ports,
    shipyards: block:
      # Create shipyards from config
      var yards: seq[Shipyard] = @[]
      let baseDocks = facilities_config.globalFacilitiesConfig.shipyard.docks
      let cstLevel = 1  # Starting tech level
      let effectiveDocks = research_effects.calculateEffectiveDocks(baseDocks, cstLevel)
      for i in 1..setupConfig.starting_facilities.shipyards:
        yards.add(Shipyard(
          id: $systemId & "-shipyard-" & $i,
          commissionedTurn: 0,
          baseDocks: baseDocks,
          effectiveDocks: effectiveDocks,
          isCrippled: false,
          constructionQueue: @[],
          activeConstructions: @[]
        ))
      yards,
    drydocks: @[],  # No starting drydocks
    planetaryShieldLevel: 0,
    groundBatteries: setupConfig.starting_facilities.ground_batteries,
    armies: setupConfig.starting_ground_forces.armies,
    marines: setupConfig.starting_ground_forces.marines,
    blockaded: false,
    blockadedBy: @[],
    blockadeTurns: 0
  )

proc createETACColony*(systemId: SystemId, owner: HouseId,
                      planetClass: PlanetClass,
                      resources: ResourceRating): Colony =
  ## Create a new ETAC-colonized system with 1 PTU (50k souls)
  result = Colony(
    systemId: systemId,
    owner: owner,
    population: 0,  # 50k souls = 0.05M, truncates to 0 in display
    souls: 50_000,  # Exactly 1 PTU worth of colonists
    populationUnits: 1,  # 1 PU for economic calculations (1 PTU = 1 PU)
    populationTransferUnits: 1,  # 1 PTU from ETAC colonization
    infrastructure: 0,  # No infrastructure yet
    industrial: econ_types.IndustrialUnits(
      units: 0, investmentCost: econ_types.BASE_IU_COST),
    planetClass: planetClass,
    resources: resources,
    buildings: @[],  # No buildings yet
    production: 0,
    grossOutput: 0,
    taxRate: 50,  # Default 50% tax rate
    infrastructureDamage: 0.0,
    underConstruction: none(ConstructionProject),
    constructionQueue: @[],
    repairQueue: @[],
    autoRepairEnabled: false,  # Default OFF
    autoLoadingEnabled: true,  # Default ON
    autoReloadETACs: true,     # Default ON
    unassignedSquadrons: @[],
    unassignedSpaceLiftShips: @[],
    fighterSquadrons: @[],
    capacityViolation: CapacityViolation(
      active: false,
      violationType: "",
      turnsRemaining: 0,
      violationTurn: 0
    ),
    starbases: @[],
    spaceports: @[],
    shipyards: @[],
    drydocks: @[],
    planetaryShieldLevel: 0,
    groundBatteries: 0,
    armies: 0,
    marines: 0,
    blockaded: false,
    blockadedBy: @[],
    blockadeTurns: 0
  )
