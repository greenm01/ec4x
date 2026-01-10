## Homeworld Colony Initialization
##
## Creates homeworld colonies with starting facilities, ground forces,
## and infrastructure based on game setup configuration.

import std/[options, tables]
import
  ../types/[core, colony, production, capacity, facilities, ground_unit, game_state]
import ../state/[engine, id_gen]
import ../entities/[neoria_ops, ground_unit_ops]
import ../globals

proc createHomeWorld*(
    state: GameState, systemId: SystemId, owner: HouseId
): ColonyId =
  ## Create a starting homeworld colony per gameplay.md:1.2
  ## Loads configuration from scenarios/*.kdl
  ##
  ## Note: Planet class and resource rating are properties of the System,
  ## not the Colony. These are set during starmap generation in starmap.nim.
  let homeworldCfg = gameSetup.homeworld

  let colonyId = state.generateColonyId()

  var groundUnitIds = newSeq[GroundUnitId]()

  # Create unified Neorias (production facilities)
  var neoriaIds = newSeq[NeoriaId]()
  for i in 0 ..< gameSetup.startingFacilities.spaceports:
    let neoria = createNeoria(state, colonyId, NeoriaClass.Spaceport)
    neoriaIds.add(neoria.id)
  for i in 0 ..< gameSetup.startingFacilities.shipyards:
    let neoria = createNeoria(state, colonyId, NeoriaClass.Shipyard)
    neoriaIds.add(neoria.id)
  for i in 0 ..< gameSetup.startingFacilities.drydocks:
    let neoria = createNeoria(state, colonyId, NeoriaClass.Drydock)
    neoriaIds.add(neoria.id)

  # Create Kastras (defensive facilities) with WEP-modified stats
  # NOTE: Original code didn't create starbases at game start
  # Keeping same behavior - kastras can be added later via production system
  var kastraIds = newSeq[KastraId]()

  # Create Ground Batteries
  for i in 0 ..< gameSetup.startingGroundForces.groundBatteries:
    let groundUnitId = state.generateGroundUnitId()
    let groundBattery = ground_unit_ops.newGroundUnit(
      groundUnitId, owner, colonyId, GroundClass.GroundBattery
    )
    state.addGroundUnit(groundUnitId, groundBattery)
    groundUnitIds.add(groundUnitId)

  # Create Armies
  for i in 0 ..< gameSetup.startingGroundForces.armies:
    let groundUnitId = state.generateGroundUnitId()
    let army = ground_unit_ops.newGroundUnit(
      groundUnitId, owner, colonyId, GroundClass.Army
    )
    state.addGroundUnit(groundUnitId, army)
    groundUnitIds.add(groundUnitId)

  # Create Marines
  for i in 0 ..< gameSetup.startingGroundForces.marines:
    let groundUnitId = state.generateGroundUnitId()
    let marine = ground_unit_ops.newGroundUnit(
      groundUnitId, owner, colonyId, GroundClass.Marine
    )
    state.addGroundUnit(groundUnitId, marine)
    groundUnitIds.add(groundUnitId)

  # Get house's current tax rate for homeworld
  let house = state.house(owner).get()

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
    production: 0,
    grossOutput: 0,
    taxRate: house.taxPolicy.currentRate,
    infrastructureDamage: 0.0,
    underConstruction: none(ConstructionProjectId),
    constructionQueue: @[],
    repairQueue: @[],
    autoRepair: false,
    autoLoadMarines: true,
    autoLoadFighters: true,
    activeTerraforming: none(TerraformProject),
    fighterIds: @[],
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
    groundUnitIds: groundUnitIds,
    neoriaIds: neoriaIds,
    kastraIds: kastraIds,
    blockaded: false,
    blockadedBy: @[],
    blockadeTurns: 0,
  )

  state.addColony(colonyId, newColony)
  state.colonies.bySystem[systemId] = colonyId
  if not state.colonies.byOwner.hasKey(owner):
    state.colonies.byOwner[owner] = @[]
  state.colonies.byOwner[owner].add(colonyId)

  result = colonyId
