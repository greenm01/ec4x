## Diagnostic Metrics Types Module
##
## Defines all diagnostic data structures used across collector modules.
## Separated from main diagnostics.nim for modularity and maintainability.
##
## REFACTORED: 2025-12-06 - Extracted from monolithic diagnostics.nim
## NEW FIELDS: totalSpaceports, totalShipyards, advisorReasoning

import std/tables
import ../../../engine/gamestate  # For GameState, HouseId, SystemId
import ../../../common/types/core  # For TechField, ShipClass
import ../../common/types  # For AIStrategy

type
  DiagnosticMetrics* = object
    ## Metrics collected per house, per turn
    gameId*: string        # Unique game identifier (from seed)
    turn*: int
    act*: int              # Game act/phase (1-4) for phase-based analysis
    rank*: int             # Current rank by prestige (1=winning, 4=losing)
    houseId*: HouseId
    strategy*: AIStrategy  # AI strategy/personality archetype
    totalSystemsOnMap*: int  # Total systems on the starmap (constant, same for all houses)

    # Economy (Core)
    treasuryBalance*: int
    productionPerTurn*: int
    puGrowth*: int              # Change in PU from last turn
    zeroSpendTurns*: int        # Cumulative turns with 0 treasury spending
    grossColonyOutput*: int     # GCO = sum of all colony production (before tax)
    netHouseValue*: int         # NHV = GCO � tax rate
    taxRate*: int               # Current tax rate (0-100%)
    totalIndustrialUnits*: int  # Total IU across all colonies
    totalPopulationUnits*: int  # Total PU across all colonies (economic measure)
    totalPopulationPTU*: int    # Total PTU (people measure, exponential from PU)
    populationGrowthRate*: int  # % growth rate (base 2% + tax modifiers)

    # Tech Levels (All 11 technology types)
    techCST*: int               # Construction Tech (1-10, enables Planet-Breakers at 10!)
    techWEP*: int               # Weapons Tech (1-10, +10% AS/DS per level)
    techEL*: int                # Economic Level (1-10+, +5% GCO per level)
    techSL*: int                # Science Level (1-8+, enables other tech)
    techTER*: int               # Terraforming (1-7, planet class upgrades)
    techELI*: int               # Electronic Intelligence (1-5, scout detection)
    techCLK*: int               # Cloaking (1-5, raider stealth)
    techSLD*: int               # Shield Tech (1-5, planetary shields)
    techCIC*: int               # Counter-Intelligence (1-5, anti-espionage)
    techFD*: int                # Fighter Doctrine (1-3, capacity multiplier)
    techACO*: int               # Advanced Carrier Operations (1-3, carrier capacity)

    # Research Points (Accumulated this turn)
    researchERP*: int           # Economic Research Points invested
    researchSRP*: int           # Science Research Points invested
    researchTRP*: int           # Technology Research Points invested
    researchBreakthroughs*: int # Count of breakthroughs this turn (bi-annual rolls)

    # Research Waste Tracking (Tech Level Caps)
    researchWastedERP*: int     # ERP wasted on maxed EL (EL >= 11)
    researchWastedSRP*: int     # SRP wasted on maxed SL (SL >= 8)
    turnsAtMaxEL*: int          # Consecutive turns with EL at maximum (11)
    turnsAtMaxSL*: int          # Consecutive turns with SL at maximum (8)

    # Maintenance & Prestige
    maintenanceCostTotal*: int  # Total maintenance paid this turn
    maintenanceShortfallTurns*: int  # Consecutive turns with maintenance shortfall
    prestigeCurrent*: int       # Current prestige score
    prestigeChange*: int        # Prestige gained/lost this turn
    prestigeVictoryProgress*: int  # Turns at prestige >= 1500 (victory at 3 turns)

    # Combat Performance (from combat.toml)
    combatCERAverage*: int           # Average CER in space combat (�100 for precision)
    bombardmentRoundsTotal*: int     # Total bombardment rounds executed
    groundCombatVictories*: int      # Successful invasions/blitz
    retreatsExecuted*: int           # Times fleets retreated from combat
    criticalHitsDealt*: int          # Critical hits scored (nat 9 on 1d10)
    criticalHitsReceived*: int       # Critical hits taken
    cloakedAmbushSuccess*: int       # Successful cloaked raider ambushes
    shieldsActivatedCount*: int      # Times planetary shields blocked hits

    # Diplomatic Status (4-level system: Neutral, Ally, Hostile, Enemy)
    allyStatusCount*: int            # Houses at Ally status (formal pacts)
    hostileStatusCount*: int         # Houses at Hostile status (deep space combat)
    enemyStatusCount*: int           # Houses at Enemy status (open war)
    neutralStatusCount*: int         # Houses at Neutral status (default)
    pactViolationsTotal*: int        # Cumulative pact violations (lifetime)
    dishonoredStatusActive*: bool    # Currently dishonored?
    diplomaticIsolationTurns*: int   # Turns remaining in isolation

    # Treaty Activity Metrics
    pactFormationsTotal*: int        # Cumulative pacts formed (lifetime)
    pactBreaksTotal*: int            # Cumulative pacts broken (lifetime)
    hostilityDeclarationsTotal*: int # Cumulative escalations to Hostile (lifetime)
    warDeclarationsTotal*: int       # Cumulative escalations to Enemy (lifetime)

    # Espionage Activity (from espionage.toml)
    espionageSuccessCount*: int      # Successful espionage operations
    espionageFailureCount*: int      # Failed espionage operations
    espionageDetectedCount*: int     # Times caught by counter-intel
    techTheftsSuccessful*: int       # Successful tech theft operations
    sabotageOperations*: int         # Sabotage attempts (low + high)
    assassinationAttempts*: int      # Assassination missions
    cyberAttacksLaunched*: int       # Cyber attacks on starbases
    ebpPointsSpent*: int             # EBP spent this turn
    cipPointsSpent*: int             # CIP spent this turn
    counterIntelSuccesses*: int      # Enemy espionage detected

    # Population & Colony Management (from population.toml)
    populationTransfersActive*: int  # Ongoing Space Guild transfers
    populationTransfersCompleted*: int  # Completed transfers (cumulative)
    populationTransfersLost*: int    # Transfers lost to conquest/blockade
    ptuTransferredTotal*: int        # Total PTUs moved via Guild (cumulative)
    coloniesBlockadedCount*: int     # Current colonies under blockade
    blockadeTurnsCumulative*: int    # Total colony-turns spent blockaded

    # Economic Health (from economy.toml)
    treasuryDeficit*: bool           # Treasury < maintenance cost?
    infrastructureDamageTotal*: int  # Total IU lost to bombardment/sabotage (cumulative)
    salvageValueRecovered*: int      # PP recovered from salvaging ships (cumulative)
    maintenanceCostDeficit*: int     # Shortfall amount if treasury insufficient
    taxPenaltyActive*: bool          # High tax prestige penalty active?
    avgTaxRate6Turn*: int            # Rolling 6-turn average tax rate

    # Squadron Capacity & Violations (from military.toml)
    fighterCapacityMax*: int         # Max FS allowed (sum per colony: floor(Colony_IU/fighter_capacity_iu_divisor) � FD multiplier)
    fighterCapacityUsed*: int        # Actual FS count (current)
    fighterCapacityViolation*: bool  # Over capacity?
    squadronLimitMax*: int           # Max capital squadrons allowed (floor(Total_IU/squadron_limit_iu_divisor) � 2)
    squadronLimitUsed*: int          # Actual capital squadron count
    squadronLimitViolation*: bool    # Over squadron limit?
    starbasesActual*: int            # Actual starbase facility count

    # House Status (from gameplay.toml)
    autopilotActive*: bool           # Currently in MIA Autopilot mode
    defensiveCollapseActive*: bool   # Currently in Defensive Collapse
    turnsUntilElimination*: int      # If negative prestige, turns until elimination
    missedOrderTurns*: int           # Consecutive turns without orders (MIA risk)

    # Military
    spaceCombatWins*: int
    spaceCombatLosses*: int
    spaceCombatTotal*: int
    orbitalFailures*: int       # Lost orbital phase despite winning space
    orbitalTotal*: int
    raiderAmbushSuccess*: int   # Successful Raider ambushes
    raiderAmbushAttempts*: int

    # Logistics
    capacityViolationsActive*: int    # Current active capacity violations
    fightersDisbanded*: int           # Cumulative fighters lost to capacity
    totalFighters*: int               # Current fighter count
    idleCarriers*: int                # Carriers with 0 fighters loaded
    totalCarriers*: int               # Total carrier count
    totalTransports*: int             # Total troop transport count

    # Ship Counts by Class (all 19 ship types)
    fighterShips*: int                # Fighter squadrons
    corvetteShips*: int               # CT Corvette
    frigateShips*: int                # FG Frigate
    scoutShips*: int                  # SC Scout
    raiderShips*: int                 # RR Raider
    destroyerShips*: int              # DD Destroyer
    cruiserShips*: int                # Cruiser (generic)
    lightCruiserShips*: int           # CL Light Cruiser
    heavyCruiserShips*: int           # CA Heavy Cruiser
    battlecruiserShips*: int          # BC Battle Cruiser
    battleshipShips*: int             # BB Battleship
    dreadnoughtShips*: int            # DN Dreadnought
    superDreadnoughtShips*: int       # SD Super Dreadnought
    carrierShips*: int                # CV Carrier
    superCarrierShips*: int           # CX Super Carrier
    etacShips*: int                   # ETAC-class ships
    troopTransportShips*: int         # Troop Transport
    planetBreakerShips*: int          # PB Planet-Breaker (CST 10)
    totalShips*: int                  # Sum of all 18 ship types (starbases are facilities)

    # Ground Unit Counts (all 4 ground unit types)
    planetaryShieldUnits*: int        # PS Planetary Shield (CST 5)
    groundBatteryUnits*: int          # GB Ground Batteries
    armyUnits*: int                   # AA Armies
    marineDivisionUnits*: int         # MD Space Marines

    # Facilities (NEW - Gap #10 fix)
    totalSpaceports*: int             # Spaceport count across all colonies
    totalShipyards*: int              # Shipyard count across all colonies

    # Intel / Tech
    totalInvasions*: int                # Phase F: Track total invasions (useful for strategy analysis)
    clkResearchedNoRaiders*: bool       # Has CLK but no Raiders built
    scoutCount*: int                    # Phase 2c: Current scout count for ELI mesh tracking
    spyPlanetMissions*: int             # Cumulative SpyOnPlanet missions
    hackStarbaseMissions*: int          # Cumulative HackStarbase missions
    totalEspionageMissions*: int        # All espionage missions

    # Defense
    coloniesWithoutDefense*: int  # Colonies with no fleet/starbase defense
    totalColonies*: int
    mothballedFleetsUsed*: int    # Times mothballed fleets activated
    mothballedFleetsTotal*: int   # Current mothballed fleet count

    # Orders (ENHANCED for unknown-unknowns detection)
    invalidOrders*: int           # Cumulative invalid/rejected orders
    totalOrders*: int             # Cumulative valid orders issued
    fleetOrdersSubmitted*: int    # Fleet movement orders this turn
    buildOrdersSubmitted*: int    # Construction orders this turn
    colonizeOrdersSubmitted*: int # Colonization attempts this turn

    # Build Queue (NEW - track construction pipeline)
    totalBuildQueueDepth*: int    # Sum of all colony queue depths
    etacInConstruction*: int      # ETACs currently being built
    shipsUnderConstruction*: int  # Ship squadrons in construction
    buildingsUnderConstruction*: int  # Starbases/facilities building

    # Commissioning (NEW - track ship output)
    shipsCommissionedThisTurn*: int
    etacCommissionedThisTurn*: int
    squadronsCommissionedThisTurn*: int

    # Fleet Activity (NEW - detect stuck fleets)
    fleetsMoved*: int             # Fleets that changed systems this turn
    systemsColonized*: int        # Successful colonizations this turn
    failedColonizationAttempts*: int  # Colonization orders rejected
    fleetsWithOrders*: int        # Fleets with active orders
    stuckFleets*: int             # Fleets with orders but didn't move (pathfinding fail?)

    # ETAC Specific (NEW - critical for colonization)
    totalETACs*: int              # Current ETAC count
    etacsWithoutOrders*: int      # ETACs sitting idle (not colonizing)
    etacsInTransit*: int          # ETACs moving to targets

    # Change Deltas (NEW - track turn-over-turn losses/gains)
    coloniesLost*: int            # Colonies lost this turn (conquest/rebellion)
    coloniesGained*: int          # Colonies gained this turn (colonization/conquest)
    coloniesGainedViaColonization*: int  # Colonies gained via ETAC colonization
    coloniesGainedViaConquest*: int      # Colonies gained via invasion/blitz
    shipsLost*: int               # Ships destroyed this turn (all types)
    shipsGained*: int             # Ships commissioned this turn (all types)
    fightersLost*: int            # Fighter squadrons lost this turn
    fightersGained*: int          # Fighter squadrons gained this turn

    # Bilateral Diplomatic Relations (semicolon-separated: houseId:state)
    bilateralRelations*: string   # e.g., "house-harkonnen:Hostile;house-ordos:Neutral"

    # Advisor Reasoning (NEW - Gap #9 fix)
    advisorReasoning*: string     # Structured log of advisor decision rationales

  DiagnosticSession* = object
    ## Collection of all diagnostics for a game session
    gameId*: string
    seed*: int64
    numHouses*: int
    mapSize*: int
    turnLimit*: int
    metrics*: seq[DiagnosticMetrics]  # All collected metrics

proc initDiagnosticMetrics*(turn: int, houseId: HouseId,
                           strategy: AIStrategy = AIStrategy.Balanced,
                           gameId: string = ""): DiagnosticMetrics =
  ## Initialize empty diagnostic metrics for a house at a turn
  result = DiagnosticMetrics(
    gameId: gameId,
    turn: turn,
    act: 1,  # Default to Act 1, will be calculated in collectDiagnostics
    rank: 0,  # Default to 0, will be calculated in collectDiagnostics
    houseId: houseId,
    strategy: strategy,
    totalSystemsOnMap: 0,  # Will be set in collectDiagnostics

    # Economy
    treasuryBalance: 0,
    productionPerTurn: 0,
    puGrowth: 0,
    zeroSpendTurns: 0,
    grossColonyOutput: 0,
    netHouseValue: 0,
    taxRate: 0,
    totalIndustrialUnits: 0,
    totalPopulationUnits: 0,
    totalPopulationPTU: 0,
    populationGrowthRate: 0,

    # Tech Levels
    techCST: 1, techWEP: 1, techEL: 1, techSL: 1, techTER: 1,
    techELI: 1, techCLK: 1, techSLD: 1, techCIC: 1, techFD: 1, techACO: 1,

    # Research Points
    researchERP: 0, researchSRP: 0, researchTRP: 0, researchBreakthroughs: 0,

    # Research Waste Tracking
    researchWastedERP: 0, researchWastedSRP: 0,
    turnsAtMaxEL: 0, turnsAtMaxSL: 0,

    # Maintenance & Prestige
    maintenanceCostTotal: 0, maintenanceShortfallTurns: 0,
    prestigeCurrent: 0, prestigeChange: 0, prestigeVictoryProgress: 0,

    # Combat Performance
    combatCERAverage: 0, bombardmentRoundsTotal: 0, groundCombatVictories: 0,
    retreatsExecuted: 0, criticalHitsDealt: 0, criticalHitsReceived: 0,
    cloakedAmbushSuccess: 0, shieldsActivatedCount: 0,

    # Diplomatic Status
    allyStatusCount: 0, hostileStatusCount: 0, enemyStatusCount: 0,
    neutralStatusCount: 0,
    pactViolationsTotal: 0, dishonoredStatusActive: false,
    diplomaticIsolationTurns: 0,

    # Treaty Activity Metrics
    pactFormationsTotal: 0, pactBreaksTotal: 0,
    hostilityDeclarationsTotal: 0, warDeclarationsTotal: 0,

    # Espionage Activity
    espionageSuccessCount: 0, espionageFailureCount: 0,
    espionageDetectedCount: 0,
    techTheftsSuccessful: 0, sabotageOperations: 0, assassinationAttempts: 0,
    cyberAttacksLaunched: 0, ebpPointsSpent: 0, cipPointsSpent: 0,
    counterIntelSuccesses: 0,

    # Population & Colony Management
    populationTransfersActive: 0, populationTransfersCompleted: 0,
    populationTransfersLost: 0, ptuTransferredTotal: 0,
    coloniesBlockadedCount: 0, blockadeTurnsCumulative: 0,

    # Economic Health
    treasuryDeficit: false, infrastructureDamageTotal: 0,
    salvageValueRecovered: 0, maintenanceCostDeficit: 0,
    taxPenaltyActive: false, avgTaxRate6Turn: 0,

    # Squadron Capacity & Violations
    fighterCapacityMax: 0, fighterCapacityUsed: 0, fighterCapacityViolation: false,
    squadronLimitMax: 0, squadronLimitUsed: 0, squadronLimitViolation: false,
    starbasesActual: 0,

    # House Status
    autopilotActive: false, defensiveCollapseActive: false,
    turnsUntilElimination: 0, missedOrderTurns: 0,

    # Military
    spaceCombatWins: 0,
    spaceCombatLosses: 0,
    spaceCombatTotal: 0,
    orbitalFailures: 0,
    orbitalTotal: 0,
    raiderAmbushSuccess: 0,
    raiderAmbushAttempts: 0,

    # Logistics
    capacityViolationsActive: 0,
    fightersDisbanded: 0,
    totalFighters: 0,
    idleCarriers: 0,
    totalCarriers: 0,
    totalTransports: 0,

    # Ship Counts (all 19 ship types)
    fighterShips: 0,
    corvetteShips: 0,
    frigateShips: 0,
    scoutShips: 0,
    raiderShips: 0,
    destroyerShips: 0,
    cruiserShips: 0,
    lightCruiserShips: 0,
    heavyCruiserShips: 0,
    battlecruiserShips: 0,
    battleshipShips: 0,
    dreadnoughtShips: 0,
    superDreadnoughtShips: 0,
    carrierShips: 0,
    superCarrierShips: 0,
    etacShips: 0,
    troopTransportShips: 0,
    planetBreakerShips: 0,
    totalShips: 0,

    # Ground Unit Counts (all 4 ground unit types)
    planetaryShieldUnits: 0,
    groundBatteryUnits: 0,
    armyUnits: 0,
    marineDivisionUnits: 0,

    # Facilities (NEW)
    totalSpaceports: 0,
    totalShipyards: 0,

    # Intel
    totalInvasions: 0,
    clkResearchedNoRaiders: false,
    scoutCount: 0,
    spyPlanetMissions: 0,
    hackStarbaseMissions: 0,
    totalEspionageMissions: 0,

    # Defense
    coloniesWithoutDefense: 0,
    totalColonies: 0,
    mothballedFleetsUsed: 0,
    mothballedFleetsTotal: 0,

    # Orders
    invalidOrders: 0,
    totalOrders: 0,
    fleetOrdersSubmitted: 0,
    buildOrdersSubmitted: 0,
    colonizeOrdersSubmitted: 0,

    # Build Queue
    totalBuildQueueDepth: 0,
    etacInConstruction: 0,
    shipsUnderConstruction: 0,
    buildingsUnderConstruction: 0,

    # Commissioning
    shipsCommissionedThisTurn: 0,
    etacCommissionedThisTurn: 0,
    squadronsCommissionedThisTurn: 0,

    # Fleet Activity
    fleetsMoved: 0,
    systemsColonized: 0,
    failedColonizationAttempts: 0,
    fleetsWithOrders: 0,
    stuckFleets: 0,

    # ETAC Specific
    totalETACs: 0,
    etacsWithoutOrders: 0,
    etacsInTransit: 0,

    # Change Deltas (will be calculated from prevMetrics)
    coloniesLost: 0,
    coloniesGained: 0,
    coloniesGainedViaColonization: 0,
    coloniesGainedViaConquest: 0,
    shipsLost: 0,
    shipsGained: 0,
    fightersLost: 0,
    fightersGained: 0,

    # Bilateral Diplomatic Relations
    bilateralRelations: "",

    # Advisor Reasoning (NEW)
    advisorReasoning: ""
  )
