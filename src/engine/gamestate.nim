## Core game state representation for EC4X

import std/[tables, options, strutils]
import ../common/[hex, system]
import ../common/types/[core, planets, tech, diplomacy]
import fleet, ship, starmap
import config/prestige_config
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
    underConstruction: none(ConstructionProject)
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
    if house.prestige >= config.prestigeVictoryThreshold:
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
