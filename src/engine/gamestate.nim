## Core game state representation for EC4X

import std/[tables, options, strutils]
import ../common/[hex, system]
import ../common/types/[core, planets, tech, diplomacy]
import fleet, ship, starmap
import config/[prestige_config, military_config]
import diplomacy/types as dip_types
import espionage/types as esp_types

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

  ConstructionProject* = object
    projectType*: BuildingType
    turnsRemaining*: int
    cost*: int

  TechTree* = object
    levels*: TechLevel            # Tech levels for all fields
    researchPoints*: int          # Available research points

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
    ongoingEffects: @[]
  )

proc initializeHouse*(name: string, color: string): House =
  ## Create a new house with starting resources
  result = House(
    id: "house-" & name.toLower(),
    name: name,
    color: color,
    prestige: 0,
    treasury: 1000,  # Starting treasury
    techTree: TechTree(
      levels: TechLevel(
        energyLevel: 0,
        shieldLevel: 0,
        constructionTech: 0,
        weaponsTech: 0,
        terraformingTech: 0,
        electronicIntelligence: 0,
        counterIntelligence: 0
      ),
      researchPoints: 0
    ),
    eliminated: false,
    negativePrestigeTurns: 0,
    diplomaticRelations: dip_types.initDiplomaticRelations(),
    violationHistory: dip_types.initViolationHistory(),
    espionageBudget: esp_types.initEspionageBudget(),
    dishonoredStatus: dip_types.DishonoredStatus(active: false, turnsRemaining: 0, violationTurn: 0),
    diplomaticIsolation: dip_types.DiplomaticIsolation(active: false, turnsRemaining: 0, violationTurn: 0)
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
    )
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
  ## FD I = 1.0x, FD II = 1.5x, FD III = 2.0x
  ## FD tech is separate from other tech fields (placeholder: use constructionTech)
  let fdLevel = techLevels.constructionTech  # TODO: Add proper FD field
  case fdLevel
  of 0..4:
    return 1.0  # FD I
  of 5..9:
    return 1.5  # FD II
  else:
    return 2.0  # FD III

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
  var operationalStarbases = 0

  # Count operational (non-crippled) starbases
  # TODO: Need starbase tracking on colonies
  # For now, return unlimited capacity (will implement starbase tracking later)
  return 999

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
