## Core game state representation for EC4X

import std/[tables, options, strutils]
import ../common/[hex, system]
import ../common/types/[core, planets, tech, diplomacy]
import fleet, ship, starmap
import config/[prestige_config, military_config, tech_config]
import diplomacy/types as dip_types
import espionage/types as esp_types
import research/types as res_types

# Re-export common types
export core.HouseId, core.SystemId, core.FleetId
export planets.PlanetClass, planets.ResourceRating
export tech.TechField, tech.TechLevel
export diplomacy.DiplomaticState

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

  Colony* = object
    systemId*: SystemId
    owner*: HouseId
    population*: int              # Population in millions
    infrastructure*: int          # Infrastructure level (0-10)
    planetClass*: PlanetClass
    resources*: ResourceRating
    buildings*: seq[BuildingType]
    production*: int              # Current turn production
    underConstruction*: Option[ConstructionProject]

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

  ConstructionProject* = object
    projectType*: BuildingType
    turnsRemaining*: int
    cost*: int

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

    # Planet-Breaker tracking (assets.md:2.4.8)
    planetBreakerCount*: int  # Current PB count (max = current colony count)

  GamePhase* {.pure.} = enum
    Setup, Active, Paused, Completed

  GameState* = object
    gameId*: string
    turn*: int
    year*: int                    # Game year (starts at 2001)
    month*: int                   # Game month (1-13)
    phase*: GamePhase
    starMap*: StarMap
    houses*: Table[HouseId, House]
    colonies*: Table[SystemId, Colony]
    fleets*: Table[FleetId, Fleet]
    diplomacy*: Table[(HouseId, HouseId), DiplomaticState]
    turnDeadline*: int64          # Unix timestamp
    ongoingEffects*: seq[esp_types.OngoingEffect]  # Active espionage effects
    spyScouts*: Table[string, SpyScout]  # Active spy scouts on intelligence missions

# Initialization

proc newGameState*(gameId: string, playerCount: int, starMap: StarMap): GameState =
  ## Create initial game state with map and player houses
  result = GameState(
    gameId: gameId,
    turn: 0,
    year: 2001,
    month: 1,
    phase: GamePhase.Setup,
    starMap: starMap,
    houses: initTable[HouseId, House](),
    colonies: initTable[SystemId, Colony](),
    fleets: initTable[FleetId, Fleet](),
    diplomacy: initTable[(HouseId, HouseId), DiplomaticState](),
    ongoingEffects: @[],
    spyScouts: initTable[string, SpyScout]()
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
      energyLevel: startingTech.energy_level,
      shieldLevel: startingTech.shield_level,
      constructionTech: startingTech.construction_tech,
      weaponsTech: startingTech.weapons_tech,
      terraformingTech: startingTech.terraforming_tech,
      electronicIntelligence: startingTech.electronic_intelligence,
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
    planetBreakerCount: 0
  )

proc createHomeColony*(systemId: SystemId, owner: HouseId): Colony =
  ## Create a starting homeworld colony
  result = Colony(
    systemId: systemId,
    owner: owner,
    population: 5,  # Starting population
    infrastructure: 3,  # Starting infrastructure
    planetClass: PlanetClass.Eden,  # Homeworlds are Abundant Eden per specs
    resources: ResourceRating.Abundant,  # Abundant resources
    buildings: @[BuildingType.Shipyard],  # Start with basic shipyard
    production: 0,
    underConstruction: none(ConstructionProject),
    fighterSquadrons: @[],  # No fighters at start
    capacityViolation: CapacityViolation(
      active: false,
      violationType: "",
      turnsRemaining: 0,
      violationTurn: 0
    ),
    starbases: @[],  # No starbases at start
    spaceports: @[],  # No spaceports at start
    shipyards: @[Shipyard(
      id: $systemId & "_shipyard1",
      commissionedTurn: 1,
      docks: 10,
      isCrippled: false
    )],  # Start with one shipyard
    planetaryShieldLevel: 0,  # No shield at start
    groundBatteries: 0,  # No batteries at start
    armies: 0,  # No armies at start
    marines: 0,  # No marines at start
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
  result = 0
  for fleet in state.getHouseFleets(houseId):
    result += fleet.squadrons.len

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

# Turn advancement

proc advanceTurn*(state: var GameState) =
  ## Advance to next turn, updating year/month
  state.turn += 1
  state.month += 1

  if state.month > 13:
    state.month = 1
    state.year += 1
