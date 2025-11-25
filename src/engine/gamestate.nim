## Core game state representation for EC4X

import std/[tables, options, strutils]
import ../common/[hex, system]
import ../common/types/[core, planets, tech, diplomacy]
import fleet, ship, starmap
import order_types  # Fleet order types (avoid circular dependency)
import config/[prestige_config, military_config, tech_config]
import diplomacy/types as dip_types
import diplomacy/proposals as dip_proposals
import espionage/types as esp_types
import research/types as res_types
import economy/types as econ_types
import population/types as pop_types
import intelligence/types as intel_types

# Re-export common types
export core.HouseId, core.SystemId, core.FleetId
export planets.PlanetClass, planets.ResourceRating
export tech.TechField, tech.TechLevel
export diplomacy.DiplomaticState
export fleet.SpaceLiftShip, fleet.SpaceLiftCargo, fleet.CargoType  # ARCHITECTURE FIX

type
  BuildingType* {.pure.} = enum
    Infrastructure, Shipyard, ResearchLab, DefenseGrid

  FighterSquadron* = object
    ## Colony-based fighter squadron
    id*: string                   # Unique identifier
    commissionedTurn*: int        # Turn when squadron was commissioned

  Starbase* = object
    ## Orbital fortress (assets.md:2.4.4)
    id*: string                   # Unique identifier
    commissionedTurn*: int        # Turn when built
    isCrippled*: bool             # Combat state (crippled starbases provide no bonuses)

  Spaceport* = object
    ## Ground-based launch facility (assets.md:2.3.2.1)
    id*: string                   # Unique identifier
    commissionedTurn*: int        # Turn when built
    docks*: int                   # Construction docks (5 per spaceport)

  Shipyard* = object
    ## Orbital construction facility (assets.md:2.3.2.2)
    id*: string                   # Unique identifier
    commissionedTurn*: int        # Turn when built
    docks*: int                   # Construction docks (10 per shipyard)
    isCrippled*: bool             # Combat state (crippled shipyards can't build)

  CapacityViolation* = object
    ## Tracks fighter capacity violations and grace period
    active*: bool                 # Is there an active violation
    violationType*: string        # "infrastructure" or "population"
    turnsRemaining*: int          # Grace period turns left (starts at 2)
    violationTurn*: int           # Turn when violation began

  TerraformProject* = object
    ## Active terraforming project on a colony
    startTurn*: int           # Turn when started
    turnsRemaining*: int      # Turns until completion
    targetClass*: int         # Target planet class (current + 1)
    ppCost*: int              # Total PP cost
    ppPaid*: int              # PP already invested

  Colony* = object
    systemId*: SystemId
    owner*: HouseId
    population*: int              # Population in millions (display field)
    souls*: int                   # Exact population count (for PTU transfers)
    infrastructure*: int          # Infrastructure level (0-10)
    planetClass*: PlanetClass
    resources*: ResourceRating
    buildings*: seq[BuildingType]
    production*: int              # Current turn production
    underConstruction*: Option[ConstructionProject]  # DEPRECATED: Legacy single-project field
    constructionQueue*: seq[ConstructionProject]     # NEW: Multi-project build queue
    activeTerraforming*: Option[TerraformProject]    # Active terraforming project

    # Squadrons awaiting fleet assignment (auto-commissioned from construction)
    unassignedSquadrons*: seq[Squadron]          # Combat squadrons at colony, not in any fleet
    unassignedSpaceLiftShips*: seq[SpaceLiftShip] # ARCHITECTURE FIX: Spacelift ships separate
    autoAssignFleets*: bool                       # If true, auto-balance squadrons to fleets at colony

    # Fighter squadrons (assets.md:2.4.1)
    fighterSquadrons*: seq[FighterSquadron]  # Colony-based fighters
    capacityViolation*: CapacityViolation     # Capacity violation tracking

    # Starbases (assets.md:2.4.4)
    starbases*: seq[Starbase]                 # Orbital fortresses

    # Facilities (assets.md:2.3.2)
    spaceports*: seq[Spaceport]               # Ground launch facilities
    shipyards*: seq[Shipyard]                 # Orbital construction facilities

    # Ground defenses (assets.md:2.4.7, 2.4.9)
    planetaryShieldLevel*: int                # 0=none, 1-6=SLD level
    groundBatteries*: int                     # Count of ground batteries
    armies*: int                              # Count of army divisions (AA)
    marines*: int                             # Count of marine divisions (MD)

    # Blockade status (operations.md:6.2.6)
    blockaded*: bool                          # Is colony currently under blockade
    blockadedBy*: seq[HouseId]                # Which houses are blockading (can be multiple)
    blockadeTurns*: int                       # Consecutive turns under blockade

  # Use the proper ConstructionProject from economy module
  ConstructionProject* = econ_types.ConstructionProject

  # Re-export proper TechTree from research module
  TechTree* = res_types.TechTree

  SpyMissionType* {.pure.} = enum
    ## Types of spy scout missions (operations.md:6.2.9-6.2.11)
    SpyOnPlanet     # Order 09: Gather planet intelligence
    HackStarbase    # Order 10: Infiltrate starbase network
    SpyOnSystem     # Order 11: System reconnaissance

  SpyScout* = object
    ## Independent spy scout on intelligence mission
    ## Per assets.md:2.4.2
    id*: string                   # Unique scout identifier
    owner*: HouseId               # House that deployed the scout
    location*: SystemId           # Current system location
    eliLevel*: int                # ELI tech level (1-5)
    mission*: SpyMissionType      # Type of intelligence mission
    commissionedTurn*: int        # Turn scout was deployed
    detected*: bool               # Has scout been detected and destroyed

  FallbackRoute* = object
    ## Designated safe retreat route for a region
    ## Planned retreat destinations updated by AI strategy or automatic safety checks
    region*: SystemId           # Region anchor (usually a colony)
    fallbackSystem*: SystemId   # Safe retreat destination
    lastUpdated*: int           # Turn when route was validated

  AutoRetreatPolicy* {.pure.} = enum
    ## Player setting for automatic fleet retreats
    Never,              # Never auto-retreat (player always controls)
    MissionsOnly,       # Only abort missions (ETAC, Guard, Blockade) when target lost
    ConservativeLosing, # Retreat fleets when clearly losing combat
    AggressiveSurvival  # Retreat any fleet at risk of destruction

  House* = object
    id*: HouseId
    name*: string
    color*: string                # For UI/map display
    prestige*: int                # Victory points
    treasury*: int                # Accumulated wealth
    techTree*: TechTree
    eliminated*: bool
    negativePrestigeTurns*: int  # Consecutive turns with prestige < 0 (defensive collapse)
    diplomaticRelations*: dip_types.DiplomaticRelations  # Relations with other houses
    violationHistory*: dip_types.ViolationHistory  # Track pact violations
    espionageBudget*: esp_types.EspionageBudget  # EBP/CIP points
    dishonoredStatus*: dip_types.DishonoredStatus  # Pact violation penalty
    diplomaticIsolation*: dip_types.DiplomaticIsolation  # Pact violation penalty
    taxPolicy*: econ_types.TaxPolicy  # Current tax rate and 6-turn history

    # Planet-Breaker tracking (assets.md:2.4.8)
    planetBreakerCount*: int  # Current PB count (max = current colony count)

    # Intelligence database (intel.md)
    intelligence*: intel_types.IntelligenceDatabase  # Gathered intelligence reports

    # Economic reports (for intelligence gathering)
    latestIncomeReport*: Option[econ_types.HouseIncomeReport]  # Last turn's income report

    # Safe retreat routes (automatic seek-home behavior)
    fallbackRoutes*: seq[FallbackRoute]  # Pre-planned retreat destinations
    autoRetreatPolicy*: AutoRetreatPolicy  # Player's auto-retreat preference

  GamePhase* {.pure.} = enum
    Setup, Active, Paused, Completed

  GameState* = object
    gameId*: string
    turn*: int
    phase*: GamePhase
    starMap*: StarMap
    houses*: Table[HouseId, House]
    colonies*: Table[SystemId, Colony]
    fleets*: Table[FleetId, Fleet]
    fleetOrders*: Table[FleetId, FleetOrder]  # Persistent fleet orders (continue until completed)
    diplomacy*: Table[(HouseId, HouseId), DiplomaticState]
    turnDeadline*: int64          # Unix timestamp
    ongoingEffects*: seq[esp_types.OngoingEffect]  # Active espionage effects
    spyScouts*: Table[string, SpyScout]  # Active spy scouts on intelligence missions
    populationInTransit*: seq[pop_types.PopulationInTransit]  # Space Guild population transfers in progress
    pendingProposals*: seq[dip_proposals.PendingProposal]  # Pending diplomatic proposals

# Initialization

proc newGameState*(gameId: string, playerCount: int, starMap: StarMap): GameState =
  ## Create initial game state with map and player houses
  result = GameState(
    gameId: gameId,
    turn: 0,
    phase: GamePhase.Setup,
    starMap: starMap,
    houses: initTable[HouseId, House](),
    colonies: initTable[SystemId, Colony](),
    fleets: initTable[FleetId, Fleet](),
    diplomacy: initTable[(HouseId, HouseId), DiplomaticState](),
    ongoingEffects: @[],
    spyScouts: initTable[string, SpyScout](),
    populationInTransit: @[],
    pendingProposals: @[]
  )

proc initializeHouse*(name: string, color: string): House =
  ## Create a new house with starting resources
  ## Per economy.md:4.0: "ALL technology levels start at level 1, never 0"
  let startingTech = globalTechConfig.starting_tech

  result = House(
    id: "house-" & name.toLower(),
    name: name,
    color: color,
    prestige: globalPrestigeConfig.victory.starting_prestige,
    treasury: 1000,  # Starting treasury
    techTree: res_types.initTechTree(TechLevel(
      economicLevel: startingTech.economic_level,
      scienceLevel: startingTech.science_level,
      constructionTech: startingTech.construction_tech,
      weaponsTech: startingTech.weapons_tech,
      terraformingTech: startingTech.terraforming_tech,
      electronicIntelligence: startingTech.electronic_intelligence,
      cloakingTech: startingTech.cloaking_tech,
      shieldTech: startingTech.shield_tech,
      counterIntelligence: startingTech.counter_intelligence,
      fighterDoctrine: startingTech.fighter_doctrine,
      advancedCarrierOps: startingTech.advanced_carrier_ops
    )),
    eliminated: false,
    negativePrestigeTurns: 0,
    diplomaticRelations: dip_types.initDiplomaticRelations(),
    violationHistory: dip_types.initViolationHistory(),
    espionageBudget: esp_types.initEspionageBudget(),
    dishonoredStatus: dip_types.DishonoredStatus(active: false, turnsRemaining: 0, violationTurn: 0),
    diplomaticIsolation: dip_types.DiplomaticIsolation(active: false, turnsRemaining: 0, violationTurn: 0),
    taxPolicy: econ_types.TaxPolicy(currentRate: 50, history: @[50]),  # Default 50% tax rate
    planetBreakerCount: 0,
    intelligence: intel_types.newIntelligenceDatabase(),
    latestIncomeReport: none(econ_types.HouseIncomeReport),  # No income report at game start
    fallbackRoutes: @[],  # Initialize empty, populated by AI strategy
    autoRetreatPolicy: AutoRetreatPolicy.MissionsOnly  # Default: abort missions when target lost
  )

proc createHomeColony*(systemId: SystemId, owner: HouseId): Colony =
  ## Create a starting homeworld colony
  ## ACCELERATION: Homeworld starts with 100M population to match original EC's
  ## ~100 PP/year baseline production. At 2 PP per 10M, this gives ~20 PP/turn.
  result = Colony(
    systemId: systemId,
    owner: owner,
    population: 100,  # Starting population in millions (was 5M, now 100M for EC parity)
    souls: 100_000_000,  # Exact population count: 100M souls
    infrastructure: 3,  # Starting infrastructure
    planetClass: PlanetClass.Eden,  # Homeworlds are Abundant Eden per specs
    resources: ResourceRating.Abundant,  # Abundant resources
    buildings: @[BuildingType.Shipyard],  # Start with basic shipyard
    production: 0,
    underConstruction: none(ConstructionProject),
    constructionQueue: @[],  # NEW: Empty build queue
    unassignedSquadrons: @[],  # No unassigned squadrons
    unassignedSpaceLiftShips: @[],  # No unassigned spacelift ships
    autoAssignFleets: true,  # Auto-assign by default
    fighterSquadrons: @[],  # No fighters at start
    capacityViolation: CapacityViolation(
      active: false,
      violationType: "",
      turnsRemaining: 0,
      violationTurn: 0
    ),
    starbases: @[],  # No starbases at start
    spaceports: @[],  # Configured by game setup
    shipyards: @[],  # Configured by game setup
    planetaryShieldLevel: 0,  # No shield at start
    groundBatteries: 0,  # No batteries at start
    armies: 0,  # No armies at start
    marines: 0,  # No marines at start
    blockaded: false,
    blockadedBy: @[],
    blockadeTurns: 0
  )

proc createETACColony*(systemId: SystemId, owner: HouseId, planetClass: PlanetClass, resources: ResourceRating): Colony =
  ## Create a new ETAC-colonized system with 1 PTU (50k souls)
  result = Colony(
    systemId: systemId,
    owner: owner,
    population: 0,  # 50k souls = 0.05M, truncates to 0 in display
    souls: 50_000,  # Exactly 1 PTU worth of colonists
    infrastructure: 0,  # No infrastructure yet
    planetClass: planetClass,
    resources: resources,
    buildings: @[],  # No buildings yet
    production: 0,
    underConstruction: none(ConstructionProject),
    constructionQueue: @[],  # NEW: Empty build queue
    unassignedSquadrons: @[],
    unassignedSpaceLiftShips: @[],
    autoAssignFleets: true,
    fighterSquadrons: @[],
    capacityViolation: CapacityViolation(
      active: false,
      violationType: "",
      turnsRemaining: 0,
      violationTurn: 0
    ),
    starbases: @[],
    spaceports: @[],
    shipyards: @[],  # No shipyards yet
    planetaryShieldLevel: 0,
    groundBatteries: 0,
    armies: 0,
    marines: 0,
    blockaded: false,
    blockadedBy: @[],
    blockadeTurns: 0
  )

# Game state queries

proc getHouse*(state: GameState, houseId: HouseId): Option[House] =
  ## Get house by ID
  if houseId in state.houses:
    return some(state.houses[houseId])
  return none(House)

proc getColony*(state: GameState, systemId: SystemId): Option[Colony] =
  ## Get colony by system ID
  if systemId in state.colonies:
    return some(state.colonies[systemId])
  return none(Colony)

proc getFleet*(state: GameState, fleetId: FleetId): Option[Fleet] =
  ## Get fleet by ID
  if fleetId in state.fleets:
    return some(state.fleets[fleetId])
  return none(Fleet)

proc getActiveHouses*(state: GameState): seq[House] =
  ## Get all non-eliminated houses
  result = @[]
  for house in state.houses.values:
    if not house.eliminated:
      result.add(house)

proc getHouseColonies*(state: GameState, houseId: HouseId): seq[Colony] =
  ## Get all colonies owned by a house
  result = @[]
  for colony in state.colonies.values:
    if colony.owner == houseId:
      result.add(colony)

proc getHouseFleets*(state: GameState, houseId: HouseId): seq[Fleet] =
  ## Get all fleets owned by a house
  result = @[]
  for fleet in state.fleets.values:
    if fleet.owner == houseId:
      result.add(fleet)

# Squadron and military limits

proc getHousePopulationUnits*(state: GameState, houseId: HouseId): int =
  ## Get total population units for a house across all colonies
  result = 0
  for colony in state.getHouseColonies(houseId):
    result += colony.population

proc getSquadronLimit*(state: GameState, houseId: HouseId): int =
  ## Calculate squadron limit for a house based on population
  ## Per military.toml: Squadron limit = Total PU ÷ 100 (minimum 8)
  let config = globalMilitaryConfig.squadron_limits
  let totalPU = state.getHousePopulationUnits(houseId)
  let calculatedLimit = totalPU div config.squadron_limit_pu_divisor
  return max(config.squadron_limit_minimum, calculatedLimit)

proc getHouseSquadronCount*(state: GameState, houseId: HouseId): int =
  ## Count total squadrons for a house across all fleets
  ## Scouts are exempt from squadron limits per reference.md:9.5
  result = 0
  for fleet in state.getHouseFleets(houseId):
    for squadron in fleet.squadrons:
      # Scouts don't count toward squadron limit
      if squadron.flagship.shipClass != ShipClass.Scout:
        result += 1

proc isOverSquadronLimit*(state: GameState, houseId: HouseId): bool =
  ## Check if house has exceeded squadron limit
  let current = state.getHouseSquadronCount(houseId)
  let limit = state.getSquadronLimit(houseId)
  return current > limit

# Fighter squadron capacity (assets.md:2.4.1)

proc getFighterDoctrineMultiplier*(techLevels: TechLevel): float =
  ## Get fighter doctrine multiplier from tech level
  ## Per economy.md tech tables: FD I = 1.0x, FD II = 1.5x, FD III = 2.0x
  ## CRITICAL: FD starts at level 1 (FD I), not 0! (gameplay.md:1.2)
  let fdLevel = techLevels.fighterDoctrine
  case fdLevel
  of 1:
    return 1.0  # FD I (base level, houses start here)
  of 2:
    return 1.5  # FD II
  else:
    return 2.0  # FD III+

proc getFighterPopulationCapacity*(colony: Colony, fdMultiplier: float): int =
  ## Calculate fighter capacity based on population
  ## Max FS = floor(PU / 100) × FD Multiplier
  ## Per military.toml: fighter_capacity_pu_divisor = 100
  let config = globalMilitaryConfig.fighter_mechanics
  let baseCap = colony.population div config.fighter_capacity_pu_divisor
  return int(float(baseCap) * fdMultiplier)

proc getFighterInfrastructureCapacity*(colony: Colony): int =
  ## Calculate fighter capacity based on starbases
  ## Requires 1 operational Starbase per 5 FS
  ## Per military.toml: starbase_per_fighter_squadrons = 5
  let config = globalMilitaryConfig.fighter_mechanics

  # Count operational (non-crippled) starbases
  var operationalStarbases = 0
  for starbase in colony.starbases:
    if not starbase.isCrippled:
      operationalStarbases += 1

  # Each operational starbase supports 5 fighter squadrons
  return operationalStarbases * config.starbase_per_fighter_squadrons

proc getFighterCapacity*(colony: Colony, fdMultiplier: float): int =
  ## Get effective fighter capacity (minimum of population and infrastructure limits)
  let popCap = getFighterPopulationCapacity(colony, fdMultiplier)
  let infraCap = getFighterInfrastructureCapacity(colony)
  return min(popCap, infraCap)

proc getCurrentFighterCount*(colony: Colony): int =
  ## Get current number of fighter squadrons at colony
  return colony.fighterSquadrons.len

proc isOverFighterCapacity*(colony: Colony, fdMultiplier: float): bool =
  ## Check if colony has exceeded fighter capacity
  let current = getCurrentFighterCount(colony)
  let capacity = getFighterCapacity(colony, fdMultiplier)
  return current > capacity

# Starbase management (assets.md:2.4.4)

proc getOperationalStarbaseCount*(colony: Colony): int =
  ## Count operational (non-crippled) starbases
  result = 0
  for starbase in colony.starbases:
    if not starbase.isCrippled:
      result += 1

proc getStarbaseGrowthBonus*(colony: Colony): float =
  ## Calculate population/IU growth bonus from starbases
  ## Per assets.md:2.4.4: 5% per operational starbase, max 15% (3 starbases)
  let operational = getOperationalStarbaseCount(colony)
  let bonus = float(min(operational, 3)) * 0.05  # 5% per SB, max 3
  return bonus

# Facility management (assets.md:2.3.2)

proc hasSpaceport*(colony: Colony): bool =
  ## Check if colony has at least one spaceport
  return colony.spaceports.len > 0

proc getOperationalShipyardCount*(colony: Colony): int =
  ## Count operational (non-crippled) shipyards
  result = 0
  for shipyard in colony.shipyards:
    if not shipyard.isCrippled:
      result += 1

proc hasOperationalShipyard*(colony: Colony): bool =
  ## Check if colony has at least one operational shipyard
  return getOperationalShipyardCount(colony) > 0

proc getTotalConstructionDocks*(colony: Colony): int =
  ## Calculate total construction docks from facilities
  ## Spaceports: 5 docks each
  ## Shipyards: 10 docks each (only operational ones)
  result = 0
  for spaceport in colony.spaceports:
    result += spaceport.docks
  for shipyard in colony.shipyards:
    if not shipyard.isCrippled:
      result += shipyard.docks

# Ground defense management (assets.md:2.4.7, 2.4.9)

proc hasPlanetaryShield*(colony: Colony): bool =
  ## Check if colony has an active planetary shield
  return colony.planetaryShieldLevel > 0

proc getShieldBlockChance*(shieldLevel: int): float =
  ## Get shield block chance from config
  ## TODO: Load from ground_units_config.toml
  ## Placeholder values
  case shieldLevel
  of 1: 0.30  # SLD1: 30%
  of 2: 0.40  # SLD2: 40%
  of 3: 0.50  # SLD3: 50%
  of 4: 0.60  # SLD4: 60%
  of 5: 0.70  # SLD5: 70%
  of 6: 0.80  # SLD6: 80%
  else: 0.0

proc getTotalGroundDefense*(colony: Colony): int =
  ## Calculate total ground defense strength
  ## Ground batteries + armies + marines
  return colony.groundBatteries + colony.armies + colony.marines

# Planet-Breaker management (assets.md:2.4.8)

proc getPlanetBreakerLimit*(state: GameState, houseId: HouseId): int =
  ## Get maximum Planet-Breakers allowed for house
  ## Limit = current colony count (homeworld counts)
  return state.getHouseColonies(houseId).len

proc canBuildPlanetBreaker*(state: GameState, houseId: HouseId): bool =
  ## Check if house can build another Planet-Breaker
  let current = state.houses[houseId].planetBreakerCount
  let limit = state.getPlanetBreakerLimit(houseId)
  return current < limit

# Victory condition checks

proc calculatePrestige*(state: GameState, houseId: HouseId): int =
  ## Return current prestige for a house
  ## Prestige is tracked via events and stored in House.prestige
  return state.houses[houseId].prestige

proc checkVictoryCondition*(state: GameState): Option[HouseId] =
  ## Check if any house has won the game
  ## Victory: prestige threshold (configurable) or last house standing

  let config = globalPrestigeConfig
  let activeHouses = state.getActiveHouses()

  # Last house standing
  if activeHouses.len == 1:
    return some(activeHouses[0].id)

  # Prestige victory
  for house in activeHouses:
    if house.prestige >= config.victory.prestige_victory:
      return some(house.id)

  return none(HouseId)

# Construction queue helpers

proc getConstructionDockCapacity*(colony: Colony): int =
  ## Calculate total construction dock capacity
  ## Uses actual dock counts from facilities
  result = 0
  for spaceport in colony.spaceports:
    result += spaceport.docks  # Usually 5 per spaceport
  for shipyard in colony.shipyards:
    if not shipyard.isCrippled:  # Crippled shipyards can't build
      result += shipyard.docks  # Usually 10 per shipyard

proc getActiveConstructionProjects*(colony: Colony): int =
  ## Count how many projects are currently active in the queue
  result = colony.constructionQueue.len

proc canAcceptMoreProjects*(colony: Colony): bool =
  ## Check if colony has dock capacity for more construction projects
  let capacity = colony.getConstructionDockCapacity()
  let active = colony.getActiveConstructionProjects()
  result = active < capacity

# Turn advancement

proc advanceTurn*(state: var GameState) =
  ## Advance to next strategic cycle
  state.turn += 1
