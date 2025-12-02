## Core game state representation for EC4X

import std/[tables, options, strutils]
import ../common/types/[core, planets, tech, diplomacy]
import fleet, starmap
import order_types  # Fleet order types (avoid circular dependency)
import config/[prestige_config, military_config, tech_config, game_setup_config]
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

  GameState* = object
    gameId*: string
    turn*: int
    phase*: GamePhase
    starMap*: StarMap
    houses*: Table[HouseId, House]
    colonies*: Table[SystemId, Colony]
    fleets*: Table[FleetId, Fleet]
    fleetOrders*: Table[FleetId, FleetOrder]  # Persistent fleet orders (continue until completed)
    standingOrders*: Table[FleetId, StandingOrder]  # Standing orders (execute when no explicit order)
    diplomacy*: Table[(HouseId, HouseId), DiplomaticState]
    turnDeadline*: int64          # Unix timestamp
    ongoingEffects*: seq[esp_types.OngoingEffect]  # Active espionage effects
    spyScouts*: Table[string, SpyScout]  # Active spy scouts on intelligence missions
    spyScoutOrders*: Table[string, SpyScoutOrder]  # Orders for spy scouts (parallel to fleetOrders)
    scoutLossEvents*: seq[intel_types.ScoutLossEvent]  # Scout losses for diplomatic processing (NEW)
    populationInTransit*: seq[pop_types.PopulationInTransit]  # Space Guild population transfers in progress
    pendingProposals*: seq[dip_proposals.PendingProposal]  # Pending diplomatic proposals

# Initialization

# Forward declaration
proc initializeHousesAndHomeworlds*(state: var GameState)

proc newGame*(gameId: string, playerCount: int, seed: int64 = 42): GameState =
  ## Create a new game with full setup including starmap generation
  ##
  ## This is the recommended way to create a new game. It handles:
  ## - Starmap generation and population
  ## - Game state initialization
  ## - Input validation
  ##
  ## Parameters:
  ##   - gameId: Unique identifier for this game
  ##   - playerCount: Number of players (2-12)
  ##   - seed: Random seed for map generation
  ##
  ## Example:
  ##   let game = newGame("game1", 4, seed = 12345)

  # Create and populate starmap
  var starMap = newStarMap(playerCount, seed)
  starMap.populate()

  # Create game state with populated map
  result = GameState(
    gameId: gameId,
    turn: 0,
    phase: GamePhase.Setup,
    starMap: starMap,
    houses: initTable[HouseId, House](),
    colonies: initTable[SystemId, Colony](),
    fleets: initTable[FleetId, Fleet](),
    standingOrders: initTable[FleetId, StandingOrder](),
    diplomacy: initTable[(HouseId, HouseId), DiplomaticState](),
    ongoingEffects: @[],
    spyScouts: initTable[string, SpyScout](),
    spyScoutOrders: initTable[string, SpyScoutOrder](),
    populationInTransit: @[],
    pendingProposals: @[]
  )

  # Create houses and homeworld colonies
  result.initializeHousesAndHomeworlds()

proc validateTechTree*(techTree: TechTree) =
  ## Validate that technology levels are within valid ranges
  ## Per economy.md:4.0: "ALL technology levels start at level 1, never 0"
  ##
  ## This validation is automatically called by:
  ## - initializeHouse() when creating new houses
  ## - Manual House creation should also call this or use initTechTree()
  ##
  ## Common mistake in tests: Creating House() without techTree field
  ## Fix: Always include `techTree: res_types.initTechTree()` in House constructors
  if techTree.levels.economicLevel < 1:
    raise newException(ValueError, "EL (Economics Level) cannot be less than 1. Found: " & $techTree.levels.economicLevel & ". Use initTechTree() to create valid tech tree.")
  if techTree.levels.scienceLevel < 1:
    raise newException(ValueError, "SL (Science Level) cannot be less than 1. Found: " & $techTree.levels.scienceLevel & ". Use initTechTree() to create valid tech tree.")
  if techTree.levels.economicLevel > 11:
    raise newException(ValueError, "EL (Economics Level) cannot exceed 11. Found: " & $techTree.levels.economicLevel)
  if techTree.levels.scienceLevel > 11:
    raise newException(ValueError, "SL (Science Level) cannot exceed 11. Found: " & $techTree.levels.scienceLevel)

proc newGameState*(gameId: string, playerCount: int, starMap: StarMap): GameState =
  ## Create initial game state with an existing starMap
  ##
  ## IMPORTANT: The starMap must be populated before passing to this function.
  ## Call `starMap.populate()` after creating with `newStarMap()`.
  ##
  ## Prefer using `newGame()` which handles starmap creation automatically.
  ##
  ## Example:
  ##   var starMap = newStarMap(playerCount)
  ##   starMap.populate()  # REQUIRED
  ##   let state = newGameState("game1", playerCount, starMap)

  # Validate starMap is populated
  if starMap.systems.len == 0:
    raise newException(ValueError, "StarMap must be populated before creating GameState. Call starMap.populate() first.")

  result = GameState(
    gameId: gameId,
    turn: 0,
    phase: GamePhase.Setup,
    starMap: starMap,
    houses: initTable[HouseId, House](),
    colonies: initTable[SystemId, Colony](),
    fleets: initTable[FleetId, Fleet](),
    standingOrders: initTable[FleetId, StandingOrder](),
    diplomacy: initTable[(HouseId, HouseId), DiplomaticState](),
    ongoingEffects: @[],
    spyScouts: initTable[string, SpyScout](),
    spyScoutOrders: initTable[string, SpyScoutOrder](),
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
    status: HouseStatus.Active,
    negativePrestigeTurns: 0,
    turnsWithoutOrders: 0,
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

  # Validate tech tree
  validateTechTree(result.techTree)

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
    population: homeworldCfg.population_units,  # Starting population from config
    souls: homeworldCfg.population_units * 1_000_000,  # Convert PU to souls (1 PU = 1M souls)
    populationUnits: homeworldCfg.population_units,  # PU for economic calculations
    populationTransferUnits: homeworldCfg.population_units,  # PTU for Space Guild transfers
    infrastructure: homeworldCfg.colony_level,  # Infrastructure level from config
    industrial: econ_types.IndustrialUnits(units: 0, investmentCost: econ_types.BASE_IU_COST),  # No IU at start
    planetClass: planetClass,  # Planet class from config
    resources: resources,  # Resources from config
    buildings: @[BuildingType.Shipyard],  # Start with basic shipyard
    production: 0,
    grossOutput: 0,  # Will be calculated by income engine
    taxRate: 50,  # Default 50% tax rate
    infrastructureDamage: 0.0,  # No damage at start
    underConstruction: none(ConstructionProject),
    constructionQueue: @[],  # NEW: Empty build queue
    repairQueue: @[],  # Empty repair queue
    autoRepairEnabled: false,  # Default OFF - player must enable
    unassignedSquadrons: @[],  # No unassigned squadrons
    unassignedSpaceLiftShips: @[],  # No unassigned spacelift ships
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

proc initializeHousesAndHomeworlds*(state: var GameState) =
  ## Initialize houses and their homeworld colonies
  ## Called during game setup to create starting conditions
  let playerCount = state.starMap.playerCount

  for playerIdx in 0 ..< playerCount:
    let houseName = "House" & $(playerIdx + 1)
    let houseId = "house" & $(playerIdx + 1)
    let houseColor = ["blue", "red", "green", "yellow", "purple", "orange", "cyan", "magenta", "brown", "pink", "gray", "white"][playerIdx mod 12]

    # Create and add house
    var house = initializeHouse(houseName, houseColor)
    house.id = houseId
    state.houses[houseId] = house

    # Create homeworld colony at player's designated homeworld system
    let homeworldSystemId = state.starMap.playerSystemIds[playerIdx]
    let homeworld = createHomeColony(homeworldSystemId, houseId)
    state.colonies[homeworldSystemId] = homeworld

proc createETACColony*(systemId: SystemId, owner: HouseId, planetClass: PlanetClass, resources: ResourceRating): Colony =
  ## Create a new ETAC-colonized system with 1 PTU (50k souls)
  result = Colony(
    systemId: systemId,
    owner: owner,
    population: 0,  # 50k souls = 0.05M, truncates to 0 in display
    souls: 50_000,  # Exactly 1 PTU worth of colonists
    populationUnits: 1,  # 1 PU for economic calculations (1 PTU = 1 PU)
    populationTransferUnits: 1,  # 1 PTU from ETAC colonization
    infrastructure: 0,  # No infrastructure yet
    industrial: econ_types.IndustrialUnits(units: 0, investmentCost: econ_types.BASE_IU_COST),  # No IU at start
    planetClass: planetClass,
    resources: resources,
    buildings: @[],  # No buildings yet
    production: 0,
    grossOutput: 0,  # Will be calculated by income engine
    taxRate: 50,  # Default 50% tax rate
    infrastructureDamage: 0.0,  # No damage at start
    underConstruction: none(ConstructionProject),
    constructionQueue: @[],  # NEW: Empty build queue
    repairQueue: @[],  # Empty repair queue
    autoRepairEnabled: false,  # Default OFF - player must enable
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

proc isFinalConfrontation*(state: GameState): bool =
  ## Check if only 2 houses remain (final confrontation)
  ## No dishonor penalties for inevitable war between final two houses
  let activeHouses = state.getActiveHouses()
  return activeHouses.len == 2

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

proc getShipyardDockCapacity*(colony: Colony): int =
  ## Calculate shipyard dock capacity (for ship repairs)
  result = 0
  for shipyard in colony.shipyards:
    if not shipyard.isCrippled:
      result += shipyard.docks  # Usually 10 per shipyard

proc getSpaceportDockCapacity*(colony: Colony): int =
  ## Calculate spaceport dock capacity (for smaller ship repairs)
  result = 0
  for spaceport in colony.spaceports:
    result += spaceport.docks  # Usually 5 per spaceport

proc getActiveProjectsByFacility*(colony: Colony, facilityType: econ_types.FacilityType): int =
  ## Count active projects using a specific facility type
  ## Construction projects can use any facility, repairs are facility-specific
  result = colony.getActiveConstructionProjects()  # Construction uses any docks

  # Add repairs specific to this facility type
  for repair in colony.repairQueue:
    if repair.facilityType == facilityType:
      result += 1

proc canAcceptMoreProjects*(colony: Colony): bool =
  ## Check if colony has dock capacity for more construction projects
  let capacity = colony.getConstructionDockCapacity()
  let active = colony.getTotalActiveProjects()  # Now includes repairs
  result = active < capacity

# Turn advancement

proc advanceTurn*(state: var GameState) =
  ## Advance to next strategic cycle
  state.turn += 1
