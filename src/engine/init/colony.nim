## Initializes a new homeworld colony at game startup.

import std/[options, tables]
import
  ../types/[core, colony, production, capacity, facilities, ground_unit, game_state]
import ../state/[id_gen, entity_manager]
import ../config/[economy_config, facilities_config, game_setup_config]

proc createHomeWorld*(
    state: var GameState, systemId: SystemId, owner: HouseId
): ColonyId =
  ## Create a starting homeworld colony per gameplay.md:1.2
  ## Loads configuration from game_setup/standard.toml
  let setupConfig = game_setup_config.globalGameSetupConfig
  let homeworldCfg = setupConfig.homeworld

  # Parse planet class and resources from config
  let planetClass = game_setup_config.parsePlanetClass(homeworldCfg.planet_class)
  let resources = game_setup_config.parseResourceRating(homeworldCfg.raw_quality)

  let colonyId = state.generateColonyId()

  var starbaseIds = newSeq[StarbaseId]()
  var spaceportIds = newSeq[SpaceportId]()
  var shipyardIds = newSeq[ShipyardId]()
  var groundBatteryIds = newSeq[GroundUnitId]()
  var armyIds = newSeq[GroundUnitId]()
  var marineIds = newSeq[GroundUnitId]()

  # Create Starbases
  for i in 0 ..< setupConfig.starting_facilities.starbases:
    let starbaseId = state.generateStarbaseId()
    let starbase = Starbase(
      id: starbaseId, colonyId: colonyId, commissionedTurn: 0, isCrippled: false
    )
    state.starbases.entities.addEntity(starbaseId, starbase)
    starbaseIds.add(starbaseId)

  # Create Spaceports
  let baseSpaceportDocks =
    facilities_config.globalFacilitiesConfig.spaceport.docks.int32
  # TODO: Revisit research_effects for effectiveDocks. For now, use baseDocks.
  let effectiveSpaceportDocks = baseSpaceportDocks
  for i in 0 ..< setupConfig.starting_facilities.spaceports:
    let spaceportId = state.generateSpaceportId()
    let spaceport = Spaceport(
      id: spaceportId,
      colonyId: colonyId,
      commissionedTurn: 0,
      baseDocks: baseSpaceportDocks,
      effectiveDocks: effectiveSpaceportDocks,
      constructionQueue: @[],
      activeConstructions: @[],
    )
    state.spaceports.entities.addEntity(spaceportId, spaceport)
    spaceportIds.add(spaceportId)

  let baseShipyardDocks = facilities_config.globalFacilitiesConfig.shipyard.docks.int32
  # TODO: Revisit research_effects for effectiveDocks. For now, use baseDocks.
  let effectiveShipyardDocks = baseShipyardDocks
  for i in 0 ..< setupConfig.starting_facilities.shipyards:
    let shipyardId = state.generateShipyardId()
    let shipyard = Shipyard(
      id: shipyardId,
      colonyId: colonyId,
      commissionedTurn: 0,
      baseDocks: baseShipyardDocks,
      effectiveDocks: effectiveShipyardDocks,
      isCrippled: false,
      constructionQueue: @[],
      activeConstructions: @[],
    )
    state.shipyards.entities.addEntity(shipyardId, shipyard)
    shipyardIds.add(shipyardId)

  # Create Ground Batteries
  for i in 0 ..< setupConfig.starting_facilities.ground_batteries:
    let groundUnitId = state.generateGroundUnitId()
    # TODO: Load actual stats from config for ground units
    let groundBattery = GroundUnit(
      id: groundUnitId,
      unitType: GroundUnitType.GroundBattery,
      owner: owner,
      attackStrength: 1, # Placeholder
      defenseStrength: 1, # Placeholder
      state: CombatState.Undamaged,
    )
    state.groundUnits.entities.addEntity(groundUnitId, groundBattery)
    groundBatteryIds.add(groundUnitId)

  # Create Armies
  for i in 0 ..< setupConfig.starting_ground_forces.armies:
    let groundUnitId = state.generateGroundUnitId()
    let army = GroundUnit(
      id: groundUnitId,
      unitType: GroundUnitType.Army,
      owner: owner,
      attackStrength: 1, # Placeholder
      defenseStrength: 1, # Placeholder
      state: CombatState.Undamaged,
    )
    state.groundUnits.entities.addEntity(groundUnitId, army)
    armyIds.add(groundUnitId)

  # Create Marines
  for i in 0 ..< setupConfig.starting_ground_forces.marines:
    let groundUnitId = state.generateGroundUnitId()
    let marine = GroundUnit(
      id: groundUnitId,
      unitType: GroundUnitType.Marine,
      owner: owner,
      attackStrength: 1, # Placeholder
      defenseStrength: 1, # Placeholder
      state: CombatState.Undamaged,
    )
    state.groundUnits.entities.addEntity(groundUnitId, marine)
    marineIds.add(groundUnitId)

  var newColony = Colony(
    id: colonyId,
    systemId: systemId,
    owner: owner,
    population: homeworldCfg.population_units,
    souls: homeworldCfg.population_units * 1_000_000,
    populationUnits: homeworldCfg.population_units,
    populationTransferUnits: homeworldCfg.population_units,
    infrastructure: homeworldCfg.colony_level,
    industrial: IndustrialUnits(
      units: homeworldCfg.industrial_units,
      investmentCost:
        economy_config.globalEconomyConfig.industrial_investment.base_cost.int32,
    ),
    planetClass: planetClass,
    resources: resources,
    production: 0,
    grossOutput: 0,
    taxRate: 50,
    infrastructureDamage: 0.0,
    underConstruction: none(ConstructionProjectId),
    constructionQueue: @[],
    repairQueue: @[],
    autoRepairEnabled: false,
    autoLoadingEnabled: true,
    autoReloadETACs: true,
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
    planetaryShieldLevel: setupConfig.starting_facilities.planetary_shields,
    groundBatteryIds: groundBatteryIds,
    armyIds: armyIds,
    marineIds: marineIds,
    starbaseIds: starbaseIds,
    spaceportIds: spaceportIds,
    shipyardIds: shipyardIds,
    drydockIds: @[],
    blockaded: false,
    blockadedBy: @[],
    blockadeTurns: 0,
  )

  state.colonies.entities.addEntity(colonyId, newColony)
  state.colonies.bySystem[systemId] = colonyId
  if not state.colonies.byOwner.hasKey(owner):
    state.colonies.byOwner[owner] = @[]
  state.colonies.byOwner[owner].add(colonyId)

  result = colonyId
