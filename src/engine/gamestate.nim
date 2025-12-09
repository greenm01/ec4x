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

import std/[tables, options, strutils, math]
import ../common/types/[core, planets, tech, diplomacy]
import fleet, starmap, squadron
import order_types  # Fleet order types (avoid circular dependency)
import config/[prestige_config, military_config, tech_config, game_setup_config]
import config/[facilities_config, prestige_multiplier, economy_config]
import diplomacy/types as dip_types
import diplomacy/proposals as dip_proposals
import espionage/types as esp_types
import research/types as res_types
import research/effects  # CST dock capacity calculations
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
    baseDocks*: int               # Base docks from config (immutable)
    effectiveDocks*: int          # Calculated: baseDocks × CST multiplier (updated on tech upgrade)
    constructionQueue*: seq[econ_types.ConstructionProject]  # Per-facility construction queue
    activeConstructions*: seq[econ_types.ConstructionProject]  # Currently building projects (up to effectiveDocks limit)

  Shipyard* = object
    ## Orbital construction facility (assets.md:2.3.2.2)
    id*: string                   # Unique identifier
    commissionedTurn*: int        # Turn when built
    baseDocks*: int               # Base docks from config (immutable)
    effectiveDocks*: int          # Calculated: baseDocks × CST multiplier (updated on tech upgrade)
    isCrippled*: bool             # Combat state (crippled shipyards can't build)
    constructionQueue*: seq[econ_types.ConstructionProject]  # Per-facility construction queue
    activeConstructions*: seq[econ_types.ConstructionProject]  # Currently building projects (up to effectiveDocks limit)

  Drydock* = object
    ## Orbital repair facility - dedicated to ship repairs only
    id*: string                   # Unique identifier
    commissionedTurn*: int        # Turn when built
    baseDocks*: int               # Base docks from config (immutable)
    effectiveDocks*: int          # Calculated: baseDocks × CST multiplier (updated on tech upgrade)
    isCrippled*: bool             # Combat state (crippled drydocks can't repair)
    repairQueue*: seq[econ_types.RepairProject]  # Per-facility repair queue
    activeRepairs*: seq[econ_types.RepairProject]  # Currently repairing (up to effectiveDocks limit)
    # NOTE: No construction queues - Drydocks are repair-only

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

    # Population (multiple representations for different systems)
    population*: int              # Population in millions (display field)
    souls*: int                   # Exact population count (for PTU transfers)
    populationUnits*: int         # PU: Economic production measure (from economy/types.nim)
    populationTransferUnits*: int # PTU: For colonization (~50k souls each, from economy/types.nim)

    # Infrastructure and production
    infrastructure*: int          # Infrastructure level (0-10)
    industrial*: econ_types.IndustrialUnits  # IU: Manufacturing capacity (from economy/types.nim)

    # Planet characteristics
    planetClass*: PlanetClass
    resources*: ResourceRating
    buildings*: seq[BuildingType]

    # Economic state (from economy/types.nim)
    production*: int              # Current turn production
    grossOutput*: int             # GCO: Cached gross colonial output for current turn
    taxRate*: int                 # 0-100 (usually house-wide, but can override per-colony)
    infrastructureDamage*: float  # 0.0-1.0, from bombardment (from economy/types.nim)

    # Construction - Dual-slot architecture (active + queue pattern)
    underConstruction*: Option[ConstructionProject]  # Active project slot: Advances each turn, DO NOT use for validation
    constructionQueue*: seq[ConstructionProject]     # Queued projects: Waiting for dock capacity, processed in parallel
    repairQueue*: seq[econ_types.RepairProject]      # Ships/starbases awaiting repair
    autoRepairEnabled*: bool                         # Enable automatic repair submission (defaults false, player-controlled)
    autoLoadingEnabled*: bool                        # Enable automatic fighter loading to carriers (defaults true, player-controlled)
    activeTerraforming*: Option[TerraformProject]    # Active terraforming project

    # Squadrons awaiting fleet assignment (auto-commissioned from construction)
    unassignedSquadrons*: seq[Squadron]          # Combat squadrons at colony, not in any fleet
    unassignedSpaceLiftShips*: seq[SpaceLiftShip] # ARCHITECTURE FIX: Spacelift ships separate
    # NOTE: Auto-assignment is ALWAYS enabled (see docs/architecture/standing-orders.md for rationale)

    # Fighter squadrons (assets.md:2.4.1)
    fighterSquadrons*: seq[FighterSquadron]  # Colony-based fighters
    capacityViolation*: CapacityViolation     # Capacity violation tracking

    # Starbases (assets.md:2.4.4)
    starbases*: seq[Starbase]                 # Orbital fortresses

    # Facilities (assets.md:2.3.2)
    spaceports*: seq[Spaceport]               # Ground launch facilities
    shipyards*: seq[Shipyard]                 # Orbital construction facilities
    drydocks*: seq[Drydock]                   # Orbital repair facilities

    # Ground defenses (assets.md:2.4.7, 2.4.9)
    planetaryShieldLevel*: int                # 0=none, 1-6=SLD level
    groundBatteries*: int                     # Count of ground batteries
    armies*: int                              # Count of army divisions (AA)
    marines*: int                             # Count of marine divisions (MD)

    # Blockade status (operations.md:6.2.6)
    blockaded*: bool                          # Is colony currently under blockade
    blockadedBy*: seq[HouseId]                # Which houses are blockading (can be multiple)
    blockadeTurns*: int                       # Consecutive turns under blockade

  # NOTE: Don't re-export ConstructionProject to avoid ambiguity
  # Modules should import economy/types directly for ConstructionProject
  # Colony.underConstruction uses econ_types.ConstructionProject directly

  # Re-export proper TechTree from research module
  TechTree* = res_types.TechTree

  SpyMissionType* {.pure.} = enum
    ## Types of spy scout missions (operations.md:6.2.9-6.2.11)
    SpyOnPlanet     # Order 09: Gather planet intelligence
    HackStarbase    # Order 10: Infiltrate starbase network
    SpyOnSystem     # Order 11: System reconnaissance

  SpyScoutState* {.pure.} = enum
    ## Operational state of spy scout
    Traveling    # En route to target
    OnMission    # Arrived at target, gathering intel
    Returning    # Mission complete, returning home (optional)
    Detected     # Detected and marked for destruction

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

    # Travel tracking (NEW)
    state*: SpyScoutState         # Current operational state
    targetSystem*: SystemId       # Final mission destination
    travelPath*: seq[SystemId]    # Planned jump lane path
    currentPathIndex*: int        # Progress through path (0-based)
    mergedScoutCount*: int        # Number of scouts merged (for mesh bonus)

  SpyScoutOrderType* {.pure.} = enum
    ## Order types for spy scout fleets
    ## Transparent to user - spy scouts behave like normal fleets
    Hold              # Stay at current location on mission
    Move              # Travel to target system
    JoinSpyScout      # Merge with another spy scout (mesh network bonus)
    JoinFleet         # Merge with normal fleet (becomes squadron, spy scout deleted)
    Rendezvous        # Meet with other spy scouts/fleets at location
    CancelMission     # Abort mission and return home

  SpyScoutOrder* = object
    ## Order for individual spy scout (parallel to FleetOrder)
    spyScoutId*: string
    orderType*: SpyScoutOrderType
    targetSystem*: Option[SystemId]
    targetSpyScout*: Option[string]      # For JoinSpyScout
    targetFleet*: Option[FleetId]        # For JoinFleet
    priority*: int

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

  HouseStatus* {.pure.} = enum
    ## Player/house operational status (gameplay.md:1.4)
    Active,              # Normal play - submitting orders
    Autopilot,           # Temporary MIA mode (3+ consecutive turns without orders)
    DefensiveCollapse    # Permanent elimination (3+ consecutive turns prestige < 0)

  House* = object
    id*: HouseId
    name*: string
    color*: string                # For UI/map display
    prestige*: int                # Victory points
    treasury*: int                # Accumulated wealth
    techTree*: TechTree
    eliminated*: bool
    status*: HouseStatus         # Operational status (Active, Autopilot, DefensiveCollapse)
    negativePrestigeTurns*: int  # Consecutive turns with prestige < 0 (defensive collapse)
    turnsWithoutOrders*: int     # Consecutive turns without submitting orders (MIA autopilot)
    diplomaticRelations*: dip_types.DiplomaticRelations  # Relations with other houses
    violationHistory*: dip_types.ViolationHistory  # Track pact violations
    espionageBudget*: esp_types.EspionageBudget  # EBP/CIP points
    dishonoredStatus*: dip_types.DishonoredStatus  # Pact violation penalty
    diplomaticIsolation*: dip_types.DiplomaticIsolation  # Pact violation penalty
    taxPolicy*: econ_types.TaxPolicy  # Current tax rate and 6-turn history
    consecutiveShortfallTurns*: int  # Consecutive turns of missed maintenance payment (economy.md:3.11)

    # Planet-Breaker tracking (assets.md:2.4.8)
    planetBreakerCount*: int  # Current PB count (max = current colony count)

    # Intelligence database (intel.md)
    intelligence*: intel_types.IntelligenceDatabase  # Gathered intelligence reports

    # Economic reports (for intelligence gathering)
    latestIncomeReport*: Option[econ_types.HouseIncomeReport]  # Last turn's income report

    # Research tracking (for diagnostics)
    lastTurnResearchERP*: int  # Economic RP earned last turn
    lastTurnResearchSRP*: int  # Science RP earned last turn
    lastTurnResearchTRP*: int  # Total Technology RP earned last turn (sum of all fields)

    # Espionage tracking (for diagnostics)
    lastTurnEspionageAttempts*: int  # Total espionage attempts last turn
    lastTurnEspionageSuccess*: int   # Successful operations
    lastTurnEspionageDetected*: int  # Detected by counter-intel
    lastTurnTechThefts*: int         # Tech theft operations
    lastTurnSabotage*: int           # Sabotage operations (low + high)
    lastTurnAssassinations*: int     # Assassination attempts
    lastTurnCyberAttacks*: int       # Cyber attacks on starbases
    lastTurnEBPSpent*: int           # EBP spent on operations
    lastTurnCIPSpent*: int           # CIP spent on counter-intel

    # Combat tracking (for diagnostics)
    lastTurnSpaceCombatWins*: int    # Space battles won
    lastTurnSpaceCombatLosses*: int  # Space battles lost
    lastTurnSpaceCombatTotal*: int   # Total space combat engagements

    # Safe retreat routes (automatic seek-home behavior)
    fallbackRoutes*: seq[FallbackRoute]  # Pre-planned retreat destinations
    autoRetreatPolicy*: AutoRetreatPolicy  # Player's auto-retreat preference

  GamePhase* {.pure.} = enum
    Setup, Active, Paused, Completed

  GracePeriodTracker* = object
    ## Tracks grace periods for capacity enforcement
    ## Per FINAL_TURN_SEQUENCE.md Income Phase Step 5
    totalSquadronsExpiry*: int  # Turn when total squadron grace expires
    fighterCapacityExpiry*: Table[SystemId, int]  # Per-colony fighter grace

  GameState* = object
    gameId*: string
    turn*: int
    phase*: GamePhase
    starMap*: StarMap
    houses*: Table[HouseId, House]
    colonies*: Table[SystemId, Colony]
    fleets*: Table[FleetId, Fleet]
    fleetOrders*: Table[FleetId, FleetOrder]  # Persistent fleet orders (continue until completed)
    queuedCombatOrders*: seq[FleetOrder]  # Combat orders queued for next turn's Conflict Phase
    standingOrders*: Table[FleetId, StandingOrder]  # Standing orders (execute when no explicit order)
    diplomacy*: Table[(HouseId, HouseId), DiplomaticState]
    turnDeadline*: int64          # Unix timestamp
    ongoingEffects*: seq[esp_types.OngoingEffect]  # Active espionage effects
    spyScouts*: Table[string, SpyScout]  # Active spy scouts on intelligence missions
    spyScoutOrders*: Table[string, SpyScoutOrder]  # Orders for spy scouts (parallel to fleetOrders)
    scoutLossEvents*: seq[intel_types.ScoutLossEvent]  # Scout losses for diplomatic processing (NEW)
    populationInTransit*: seq[pop_types.PopulationInTransit]  # Space Guild population transfers in progress
    pendingProposals*: seq[dip_proposals.PendingProposal]  # Pending diplomatic proposals
    pendingCommissions*: seq[econ_types.CompletedProject]  # Completed projects awaiting commissioning in next Command Phase
    gracePeriodTimers*: Table[HouseId, GracePeriodTracker]  # Grace period tracking for capacity enforcement

# Initialization
# NOTE: Game initialization moved to src/engine/initialization/game.nim
# Import initialization/game and use:
#   - newGame(gameId, playerCount, seed)
#   - newGameState(gameId, playerCount, starMap)

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

proc getTotalHouseIndustrialUnits*(state: GameState, houseId: HouseId): int =
  ## Get total industrial units for a house across all colonies
  ## Used for capital squadron capacity calculation per reference.md Table 10.5
  result = 0
  for colony in state.getHouseColonies(houseId):
    result += colony.industrial.units

proc getSquadronLimit*(state: GameState, houseId: HouseId): int =
  ## Calculate capital squadron limit for a house based on industrial capacity
  ## Per reference.md Table 10.5: max(8, floor(Total_House_IU ÷ 100) × 2)
  ## Changed from PU-based to IU-based formula
  let config = globalMilitaryConfig.squadron_limits
  let totalIU = state.getTotalHouseIndustrialUnits(houseId)
  # TODO load these hardocded values from config
  let calculatedLimit = int(floor(float(totalIU) / 100.0) * 2.0)
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

# Turn advancement

proc advanceTurn*(state: var GameState) =
  ## Advance to next strategic cycle
  state.turn += 1
