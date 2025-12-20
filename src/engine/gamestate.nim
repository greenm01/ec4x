## Core Game State Management for EC4X
##
## This module provides the central GameState type and game initialization functions.
## It manages all game entities (houses, colonies, fleets) and their relationships.
##
## ## Primary API Functions
##
## **Game Initialization:**
## - `newGame(gameId, playerCount, seed)` - Create a new game with automatic setup
## - `newGameState(gameId, playerCount, starMap)` - Create game with existing starmap
## - `initializeHousesAndHomeworlds(state)` - Initialize houses, colonies, and starting fleets
##
## **House Management:**
## - `initializeHouse(name, color)` - Create a new house with starting resources
## - `validateTechTree(techTree)` - Validate technology levels are within bounds
##
## **Colony Creation:**
## - `createHomeColony(systemId, owner)` - Create a starting homeworld colony
## - `createETACColony(systemId, owner, planetClass, resources)` - Create ETAC-colonized system
##
## **Game State Queries:**
## - `getHouse(state, houseId)` - Get house by ID
## - `getColony(state, systemId)` - Get colony by system ID
## - `getFleet(state, fleetId)` - Get fleet by ID
## - `activeHousesWithId(state)` - Iterator for active houses with IDs
## - `coloniesOwned(state, houseId)` - Iterator for colonies owned by house
## - `fleetsOwned(state, houseId)` - Iterator for fleets owned by house
##
## ## Configuration
##
## Game setup parameters are loaded from `game_setup/standard.toml`:
## - Starting resources (PP, prestige, tax rate)
## - Starting technology levels (EL, SL, CST, WEP, etc.)
## - Starting fleet composition (ETACs, Light Cruisers, Destroyers, Scouts)
## - Starting facilities (Spaceports, Shipyards, Starbases)
## - Starting ground forces (Armies, Marines, Ground Batteries)
## - Homeworld characteristics (planet class, population, infrastructure)
##
## See: `config/game_setup_config.nim` for configuration types
##
## ## Architecture Notes
##
## **Data-Oriented Design (DoD):**
## - All entities stored in flat `Table[Id, Entity]` structures
## - No deep nesting or pointer chasing
## - Efficient iteration and cache-friendly layout
##
## **Entity Management:**
## - Houses: Player factions with resources and technology
## - Colonies: Planetary settlements with production and infrastructure
## - Fleets: Mobile ship groups with squadrons
## - Squadrons: Ship formations within fleets
##
## **Separation of Concerns:**
## - This module: Core state and initialization
## - Resolution modules: Turn processing and game logic
## - Economy modules: Production and resource management
## - Combat modules: Battle resolution
## - Diplomacy modules: Inter-house relations

import std/[tables, options, math, algorithm, logging]
import ../common/types/[core, planets, tech, diplomacy]
import fleet, starmap, squadron
import order_types  # Fleet order types (avoid circular dependency)
import config/[military_config, economy_config]
import ../ai/rba/config  # For ActProgressionConfig
import diagnostics_data
import diplomacy/types as dip_types
import diplomacy/proposals as dip_proposals
import ./espionage/types as esp_types
import ./systems/combat/orbital
import ./systems/combat/planetary

import research/effects  # CST dock capacity calculations
import economy/types as econ_types
import population/types as pop_types
import intelligence/types as intel_types
import ./types/core # Import all new types from core.nim



# Squadron and military limits



proc getCurrentFighterCount*(colony: Colony): int =
  ## Get current number of fighter squadrons at colony
  return colony.fighterSquadrons.len

# Starbase management (assets.md:2.4.4)

proc getOperationalStarbaseCount*(colony: Colony): int =
  ## Count operational (non-crippled) starbases
  result = 0
  for starbase in colony.starbases:
    if not starbase.isCrippled:
      result += 1

proc getStarbaseGrowthBonus*(colony: Colony): float =
  ## Calculate population/IU growth bonus from starbases
  ## Per assets.md:2.4.4: Configurable % per operational starbase
  let operational = getOperationalStarbaseCount(colony)
  let bonusConfig = economy_config.globalEconomyConfig.starbase_bonuses
  let bonus = float(min(operational, bonusConfig.max_starbases_for_bonus)) *
              bonusConfig.growth_bonus_per_starbase
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
  ## Get total construction docks (uses pre-calculated effectiveDocks)
  result = 0
  for spaceport in colony.spaceports:
    result += spaceport.effectiveDocks
  for shipyard in colony.shipyards:
    if not shipyard.isCrippled:
      result += shipyard.effectiveDocks

proc getTotalRepairDocks*(colony: Colony): int =
  ## Get total repair docks from drydocks (uses pre-calculated effectiveDocks)
  result = 0
  for drydock in colony.drydocks:
    if not drydock.isCrippled:
      result += drydock.effectiveDocks

proc getShipyardDockCapacity*(colony: Colony): int =
  ## Get shipyard dock capacity (uses pre-calculated effectiveDocks)
  result = 0
  for shipyard in colony.shipyards:
    if not shipyard.isCrippled:
      result += shipyard.effectiveDocks

proc getDrydockDockCapacity*(colony: Colony): int =
  ## Get drydock dock capacity (uses pre-calculated effectiveDocks)
  result = 0
  for drydock in colony.drydocks:
    if not drydock.isCrippled:
      result += drydock.effectiveDocks

proc getSpaceportDockCapacity*(colony: Colony): int =
  ## Get spaceport dock capacity (uses pre-calculated effectiveDocks)
  result = 0
  for spaceport in colony.spaceports:
    result += spaceport.effectiveDocks

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

proc isFinalConfrontation*(state: GameState): bool =
  ## Check if only 2 houses remain (final confrontation)
  ## No dishonor penalties for inevitable war between final two houses
  let activeHouses = state.getActiveHouses()
  return activeHouses.len == 2

proc checkVictoryCondition*(state: GameState): Option[HouseId] =
  ## Check if any house has won the game
  ## Victory: last house standing (elimination)
  ## NOTE: Prestige victory removed - now handled by victory engine
  ## (src/engine/victory/) with configurable modes per game_setup/*.toml

  let activeHouses = state.getActiveHouses()

  # Last house standing (elimination victory)
  if activeHouses.len == 1:
    return some(activeHouses[0].id)

  # No victory yet
  return none(HouseId)

# Construction queue helpers

proc getConstructionDockCapacity*(colony: Colony): int =
  ## Calculate total construction dock capacity
  ## Uses pre-calculated effectiveDocks (includes CST scaling)
  result = 0
  for spaceport in colony.spaceports:
    result += spaceport.effectiveDocks
  for shipyard in colony.shipyards:
    if not shipyard.isCrippled:
      result += shipyard.effectiveDocks

proc getActiveConstructionProjects*(colony: Colony): int =
  ## Count how many projects are currently active (underConstruction + queue)
  result = colony.constructionQueue.len
  if colony.underConstruction.isSome:
    result += 1

proc getActiveRepairProjects*(colony: Colony): int =
  ## Count how many repair projects are currently active
  result = colony.repairQueue.len

proc getTotalActiveProjects*(colony: Colony): int =
  ## Count total active projects (construction + repair)
  result = colony.getActiveConstructionProjects() + colony.getActiveRepairProjects()


proc getActiveProjectsByFacility*(colony: Colony,
                                  facilityType: econ_types.FacilityType): int =
  ## Count active projects using a specific facility type
  ## With facility specialization:
  ## - Spaceports: Construction only (up to docks limit)
  ## - Shipyards: Construction only (up to docks limit)
  ## - Drydocks: Repair only (up to docks limit)
  result = 0

  case facilityType
  of econ_types.FacilityType.Spaceport:
    # Count construction projects at spaceports
    for spaceport in colony.spaceports:
      result += spaceport.activeConstructions.len
  of econ_types.FacilityType.Shipyard:
    # Count construction projects at shipyards
    for shipyard in colony.shipyards:
      result += shipyard.activeConstructions.len
  of econ_types.FacilityType.Drydock:
    # Count repair projects at drydocks
    for drydock in colony.drydocks:
      result += drydock.activeRepairs.len

proc canAcceptMoreProjects*(colony: Colony): bool =
  ## Check if colony has dock capacity for more construction projects
  let capacity = colony.getConstructionDockCapacity()
  let active = colony.getTotalActiveProjects()  # Now includes repairs
  result = active < capacity
