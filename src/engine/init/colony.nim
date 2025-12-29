## Homeworld Colony Initialization
##
## Creates homeworld colonies with starting facilities, ground forces,
## and infrastructure based on game setup configuration.

import std/[options, tables]
import
  ../types/[core, colony, production, capacity, facilities, ground_unit, game_state]
import ../state/[id_gen, entity_manager]
import ../systems/tech/effects
import ../globals
import ../utils

proc createHomeWorld*(
    state: var GameState, systemId: SystemId, owner: HouseId
): ColonyId =
  ## Create a starting homeworld colony per gameplay.md:1.2
  ## Loads configuration from scenarios/*.kdl
  let homeworldCfg = gameSetup.homeworld

  # Parse planet class and resources from config
  let planetClass = parsePlanetClass(homeworldCfg.planetClass)
  let resources = parseResourceRating(homeworldCfg.rawQuality)

  let colonyId = state.generateColonyId()

  var starbaseIds = newSeq[StarbaseId]()
  var spaceportIds = newSeq[SpaceportId]()
  var shipyardIds = newSeq[ShipyardId]()
  var groundBatteryIds = newSeq[GroundUnitId]()
  var armyIds = newSeq[GroundUnitId]()
  var marineIds = newSeq[GroundUnitId]()

  # Create Starbases
  for i in 0 ..< gameSetup.startingFacilities.starbases:
    let starbaseId = state.generateStarbaseId()
    let starbase = Starbase(
      id: starbaseId, colonyId: colonyId, commissionedTurn: 0, isCrippled: false
    )
    state.starbases.entities.addEntity(starbaseId, starbase)
    starbaseIds.add(starbaseId)

  # Create Spaceports
  let house = state.houses.entities.getEntity(owner).get()
  let cstLevel = house.techTree.levels.constructionTech
  let baseSpaceportDocks = gameConfig.facilities.spaceport.docks
  let effectiveSpaceportDocks =
    calculateEffectiveDocks(baseSpaceportDocks, cstLevel)
  for i in 0 ..< gameSetup.startingFacilities.spaceports:
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

  let baseShipyardDocks = gameConfig.facilities.shipyard.docks
  let effectiveShipyardDocks = calculateEffectiveDocks(baseShipyardDocks, cstLevel)
  for i in 0 ..< gameSetup.startingFacilities.shipyards:
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
  for i in 0 ..< gameSetup.startingGroundForces.groundBatteries:
    let groundUnitId = state.generateGroundUnitId()
    let gbConfig = gameConfig.groundUnits.groundBattery
    let groundBattery = GroundUnit(
      id: groundUnitId,
      houseId: owner,
      stats: GroundUnitStats(
        unitType: GroundUnitType.GroundBattery,
        attackStrength: gbConfig.attackStrength,
        defenseStrength: gbConfig.defenseStrength,
      ),
      garrison: GroundUnitGarrison(
        locationType: GroundUnitLocation.OnColony,
        colonyId: colonyId,
      ),
    )
    state.groundUnits.entities.addEntity(groundUnitId, groundBattery)
    groundBatteryIds.add(groundUnitId)

  # Create Armies
  for i in 0 ..< gameSetup.startingGroundForces.armies:
    let groundUnitId = state.generateGroundUnitId()
    let armyConfig = gameConfig.groundUnits.army
    let army = GroundUnit(
      id: groundUnitId,
      houseId: owner,
      stats: GroundUnitStats(
        unitType: GroundUnitType.Army,
        attackStrength: armyConfig.attackStrength,
        defenseStrength: armyConfig.defenseStrength,
      ),
      garrison: GroundUnitGarrison(
        locationType: GroundUnitLocation.OnColony,
        colonyId: colonyId,
      ),
    )
    state.groundUnits.entities.addEntity(groundUnitId, army)
    armyIds.add(groundUnitId)

  # Create Marines
  for i in 0 ..< gameSetup.startingGroundForces.marines:
    let groundUnitId = state.generateGroundUnitId()
    let marineConfig = gameConfig.groundUnits.marineDivision
    let marine = GroundUnit(
      id: groundUnitId,
      houseId: owner,
      stats: GroundUnitStats(
        unitType: GroundUnitType.Marine,
        attackStrength: marineConfig.attackStrength,
        defenseStrength: marineConfig.defenseStrength,
      ),
      garrison: GroundUnitGarrison(
        locationType: GroundUnitLocation.OnColony,
        colonyId: colonyId,
      ),
    )
    state.groundUnits.entities.addEntity(groundUnitId, marine)
    marineIds.add(groundUnitId)

  var newColony = Colony(
    id: colonyId,
    systemId: systemId,
    owner: owner,
    population: homeworldCfg.populationUnits,
    souls: homeworldCfg.populationUnits * 1_000_000,
    populationUnits: homeworldCfg.populationUnits,
    populationTransferUnits: homeworldCfg.populationUnits,
    infrastructure: homeworldCfg.colonyLevel,
    industrial: IndustrialUnits(
      units: homeworldCfg.industrialUnits,
      investmentCost: gameConfig.economy.industrialInvestment.baseCost,
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
    planetaryShieldLevel: gameSetup.startingGroundForces.planetaryShields,
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
