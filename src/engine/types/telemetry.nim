## @engine/types/telemetry.nim
##
## Telemetry data types for engine observability.
## Moved from ai/analysis/diagnostics to establish telemetry as first-class engine concern.
##
## Pure event-driven architecture - collectors process GameEvent stream.
import ./core

type
  DiagnosticMetrics* = object
    ## Metrics collected per house, per turn
    gameId*: string            # Unique game identifier (from seed)
    turn*: int32
    act*: int32                # Game act/phase (1-4) for phase-based analysis
    rank*: int32               # Current rank by prestige (1=winning, 4=losing)
    houseId*: HouseId
    totalSystemsOnMap*: int32  # Total systems on the starmap (constant, same for all houses)

    # Economy (Core)
    treasuryBalance*: int32
    productionPerTurn*: int32
    puGrowth*: int32              # Change in PU from last turn
    zeroSpendTurns*: int32        # Cumulative turns with 0 treasury spending
    grossColonyOutput*: int32     # GCO = sum of all colony production (before tax)
    netHouseValue*: int32         # NHV = GCO × tax rate
    taxRate*: int32               # Current tax rate (0-100%)
    totalIndustrialUnits*: int32  # Total IU across all colonies
    totalPopulationUnits*: int32  # Total PU across all colonies (economic measure)
    totalPopulationPTU*: int32    # Total PTU (people measure, exponential from PU)
    populationGrowthRate*: int32  # % growth rate (base 2% + tax modifiers)

    # Tech Levels (All 11 technology types)
    techCST*: int32               # Construction Tech (1-10, enables Planet-Breakers at 10!)
    techWEP*: int32               # Weapons Tech (1-10, +10% AS/DS per level)
    techEL*: int32                # Economic Level (1-10+, +5% GCO per level)
    techSL*: int32                # Science Level (1-8+, enables other tech)
    techTER*: int32               # Terraforming (1-7, planet class upgrades)
    techELI*: int32               # Electronic Intelligence (1-5, scout detection)
    techCLK*: int32               # Cloaking (1-5, raider stealth)
    techSLD*: int32               # Shield Tech (1-5, planetary shields)
    techCIC*: int32               # Counter-Intelligence (1-5, anti-espionage)
    techFD*: int32                # Fighter Doctrine (1-3, capacity multiplier)
    techACO*: int32               # Advanced Carrier Operations (1-3, carrier capacity)

    # Research Points (Accumulated this turn)
    researchERP*: int32           # Economic Research Points invested
    researchSRP*: int32           # Science Research Points invested
    researchTRP*: int32           # Technology Research Points invested
    researchBreakthroughs*: int32 # Count of breakthroughs this turn (bi-annual rolls)

    # Research Waste Tracking (Tech Level Caps)
    researchWastedERP*: int32     # ERP wasted on maxed EL (EL >= 11)
    researchWastedSRP*: int32     # SRP wasted on maxed SL (SL >= 8)
    turnsAtMaxEL*: int32          # Consecutive turns with EL at maximum (11)
    turnsAtMaxSL*: int32          # Consecutive turns with SL at maximum (8)

    # Maintenance & Prestige
    maintenanceCostTotal*: int32       # Total maintenance paid this turn
    maintenanceShortfallTurns*: int32  # Consecutive turns with maintenance shortfall
    prestigeCurrent*: int32            # Current prestige score
    prestigeChange*: int32             # Prestige gained/lost this turn
    prestigeVictoryProgress*: int32    # Turns at prestige >= 1500 (victory at 3 turns)

    # Combat Performance (from combat.toml)
    combatCERAverage*: int32           # Average CER in space combat (×100 for precision)
    bombardmentRoundsTotal*: int32     # Total bombardment rounds executed
    groundCombatVictories*: int32      # Successful invasions/blitz
    retreatsExecuted*: int32           # Times fleets retreated from combat
    criticalHitsDealt*: int32          # Critical hits scored (nat 9 on 1d10)
    criticalHitsReceived*: int32       # Critical hits taken
    cloakedAmbushSuccess*: int32       # Successful cloaked raider ambushes
    shieldsActivatedCount*: int32      # Times planetary shields blocked hits

    # Diplomatic Status (4-level system: Neutral, Ally, Hostile, Enemy)
    allyStatusCount*: int32            # Houses at Ally status (formal pacts)
    hostileStatusCount*: int32         # Houses at Hostile status (deep space combat)
    enemyStatusCount*: int32           # Houses at Enemy status (open war)
    neutralStatusCount*: int32         # Houses at Neutral status (default)
    pactViolationsTotal*: int32        # Cumulative pact violations (lifetime)
    dishonoredStatusActive*: bool      # Currently dishonored?
    diplomaticIsolationTurns*: int32   # Turns remaining in isolation

    # Treaty Activity Metrics
    pactFormationsTotal*: int32        # Cumulative pacts formed (lifetime)
    pactBreaksTotal*: int32            # Cumulative pacts broken (lifetime)
    hostilityDeclarationsTotal*: int32 # Cumulative escalations to Hostile (lifetime)
    warDeclarationsTotal*: int32       # Cumulative escalations to Enemy (lifetime)

    # Espionage Activity (from espionage.toml)
    espionageSuccessCount*: int32      # Successful espionage operations
    espionageFailureCount*: int32      # Failed espionage operations
    espionageDetectedCount*: int32     # Times caught by counter-intel
    techTheftsSuccessful*: int32       # Successful tech theft operations
    sabotageOperations*: int32         # Sabotage attempts (low + high)
    assassinationAttempts*: int32      # Assassination missions
    cyberAttacksLaunched*: int32       # Cyber attacks on starbases
    ebpPointsSpent*: int32             # EBP spent this turn
    cipPointsSpent*: int32             # CIP spent this turn
    counterIntelSuccesses*: int32      # Enemy espionage detected

    # Population & Colony Management (from population.toml)
    populationTransfersActive*: int32     # Ongoing Space Guild transfers
    populationTransfersCompleted*: int32  # Completed transfers (cumulative)
    populationTransfersLost*: int32       # Transfers lost to conquest/blockade
    ptuTransferredTotal*: int32           # Total PTUs moved via Guild (cumulative)
    coloniesBlockadedCount*: int32        # Current colonies under blockade
    blockadeTurnsCumulative*: int32       # Total colony-turns spent blockaded

    # Economic Health (from economy.toml)
    treasuryDeficit*: bool             # Treasury < maintenance cost?
    infrastructureDamageTotal*: int32  # Total IU lost to bombardment/sabotage (cumulative)
    salvageValueRecovered*: int32      # PP recovered from salvaging ships (cumulative)
    maintenanceCostDeficit*: int32     # Shortfall amount if treasury insufficient
    taxPenaltyActive*: bool            # High tax prestige penalty active?
    avgTaxRate6Turn*: int32            # Rolling 6-turn average tax rate

    # Squadron Capacity & Violations (from military.toml)
    fighterCapacityMax*: int32         # Max FS allowed (sum per colony: floor(Colony_IU/fighter_capacity_iu_divisor) × FD multiplier)
    fighterCapacityUsed*: int32        # Actual FS count (current)
    fighterCapacityViolation*: bool    # Over capacity?
    squadronLimitMax*: int32           # Max capital squadrons allowed (floor(Total_IU/squadron_limit_iu_divisor) × 2)
    squadronLimitUsed*: int32          # Actual capital squadron count
    squadronLimitViolation*: bool      # Over squadron limit?
    starbasesActual*: int32            # Actual starbase facility count

    # House Status (from gameplay.toml)
    autopilotActive*: bool             # Currently in MIA Autopilot mode
    defensiveCollapseActive*: bool     # Currently in Defensive Collapse
    turnsUntilElimination*: int32      # If negative prestige, turns until elimination
    missedOrderTurns*: int32           # Consecutive turns without orders (MIA risk)

    # Military
    spaceCombatWins*: int32
    spaceCombatLosses*: int32
    spaceCombatTotal*: int32
    orbitalFailures*: int32       # Lost orbital phase despite winning space
    orbitalTotal*: int32
    raiderAmbushSuccess*: int32   # Successful Raider ambushes
    raiderAmbushAttempts*: int32
    raiderDetectedCount*: int32        # Times raiders were detected by ELI
    raiderStealthSuccessCount*: int32  # Times raiders evaded ELI detection
    eliDetectionAttempts*: int32       # Total ELI detection attempts
    avgEliRoll*: float32               # Average ELI roll value
    avgClkRoll*: float32               # Average CLK roll value
    scoutsDetected*: int32             # Enemy scouts detected (observer)
    scoutsDetectedBy*: int32           # Own scouts detected by enemy (target)

    # Logistics
    capacityViolationsActive*: int32    # Current active capacity violations
    fightersDisbanded*: int32           # Cumulative fighters lost to capacity
    totalFighters*: int32               # Current fighter count
    idleCarriers*: int32                # Carriers with 0 fighters loaded
    totalCarriers*: int32               # Total carrier count
    totalTransports*: int32             # Total troop transport count

    # Ship Counts by Class (all 19 ship types)
    fighterShips*: int32                # Fighter squadrons
    corvetteShips*: int32               # CT Corvette
    frigateShips*: int32                # FG Frigate
    scoutShips*: int32                  # SC Scout
    raiderShips*: int32                 # RR Raider
    destroyerShips*: int32              # DD Destroyer
    cruiserShips*: int32                # Cruiser (generic)
    lightCruiserShips*: int32           # CL Light Cruiser
    heavyCruiserShips*: int32           # CA Heavy Cruiser
    battlecruiserShips*: int32          # BC Battle Cruiser
    battleshipShips*: int32             # BB Battleship
    dreadnoughtShips*: int32            # DN Dreadnought
    superDreadnoughtShips*: int32       # SD Super Dreadnought
    carrierShips*: int32                # CV Carrier
    superCarrierShips*: int32           # CX Super Carrier
    etacShips*: int32                   # ETAC-class ships
    troopTransportShips*: int32         # Troop Transport
    planetBreakerShips*: int32          # PB Planet-Breaker (CST 10)
    totalShips*: int32                  # Sum of all 18 ship types (starbases are facilities)

    # Ground Unit Counts (all 4 ground unit types)
    planetaryShieldUnits*: int32        # PS Planetary Shield (CST 5)
    groundBatteryUnits*: int32          # GB Ground Batteries
    armyUnits*: int32                   # AA Armies
    marinesAtColonies*: int32           # MD Space Marines at colonies (unloaded)
    marinesOnTransports*: int32         # MD Space Marines loaded on transports
    marineDivisionUnits*: int32         # MD Space Marines (total = colonies + transports)

    # Facilities
    totalSpaceports*: int32             # Spaceport count across all colonies
    totalShipyards*: int32              # Shipyard count across all colonies
    totalDrydocks*: int32               # Drydock count across all colonies (repair-only facilities)

    # Intel / Tech
    totalInvasions*: int32                # Phase F: Track total invasions (useful for strategy analysis)
    vulnerableTargets_count*: int32       # Phase 1: Count from intelligence snapshot
    invasionOrders_generated*: int32      # Phase 1: Total invasion orders created this turn
    invasionOrders_bombard*: int32        # Phase 1: Bombardment orders created
    invasionOrders_invade*: int32         # Phase 1: Invasion orders created
    invasionOrders_blitz*: int32          # Phase 1: Blitz orders created
    invasionOrders_canceled*: int32       # Phase 1: Orders rejected/canceled
    # Phase 2: Multi-turn invasion campaign tracking
    activeCampaigns_total*: int32         # Total active campaigns this turn
    activeCampaigns_scouting*: int32      # Campaigns in Scouting phase
    activeCampaigns_bombardment*: int32   # Campaigns in Bombardment phase
    activeCampaigns_invasion*: int32      # Campaigns in Invasion phase
    campaigns_completed_success*: int32   # Campaigns completed successfully (cumulative)
    campaigns_abandoned_stalled*: int32   # Campaigns abandoned due to stall (cumulative)
    campaigns_abandoned_captured*: int32  # Campaigns abandoned - target taken by other (cumulative)
    campaigns_abandoned_timeout*: int32   # Campaigns abandoned due to timeout (cumulative)

    # Invasion attempt tracking (comprehensive - from game events)
    invasionAttemptsTotal*: int32          # InvasionBegan + BlitzBegan events
    invasionAttemptsSuccessful*: int32     # ColonyCaptured events
    invasionAttemptsFailed*: int32         # InvasionRepelled events (combat loss)
    invasionOrdersRejected*: int32         # OrderFailed for invasion/blitz
    blitzAttemptsTotal*: int32             # BlitzBegan events only
    blitzAttemptsSuccessful*: int32        # ColonyCaptured with method="Blitz"
    blitzAttemptsFailed*: int32            # InvasionRepelled from blitz
    bombardmentAttemptsTotal*: int32       # BombardmentRoundCompleted events
    bombardmentOrdersFailed*: int32        # OrderFailed for bombardment
    invasionMarinesKilled*: int32          # Marines lost in failed invasions
    invasionDefendersKilled*: int32        # Defenders killed in invasions

    clkResearchedNoRaiders*: bool       # Has CLK but no Raiders built
    scoutCount*: int32                    # Phase 2c: Current scout count for ELI mesh tracking
    spyPlanetMissions*: int32             # Cumulative SpyOnPlanet missions
    hackStarbaseMissions*: int32          # Cumulative HackStarbase missions
    totalEspionageMissions*: int32        # All espionage missions

    # Defense
    coloniesWithoutDefense*: int32  # Colonies with no fleet/starbase defense
    totalColonies*: int32
    mothballedFleetsUsed*: int32    # Times mothballed fleets activated
    mothballedFleetsTotal*: int32   # Current mothballed fleet count

    # Orders (ENHANCED for unknown-unknowns detection)
    invalidOrders*: int32           # Cumulative invalid/rejected orders
    totalOrders*: int32             # Cumulative valid orders issued
    fleetCommandsSubmitted*: int32    # Fleet movement orders this turn
    buildOrdersSubmitted*: int32    # Construction orders this turn
    colonizeOrdersSubmitted*: int32 # Colonization attempts this turn

    # Budget Allocation (Treasurer → Advisor Flow - DRY Fix Verification)
    domestikosBudgetAllocated*: int32         # PP allocated to Domestikos by Treasurer
    logotheteBudgetAllocated*: int32          # PP allocated to Logothete by Treasurer
    drungariusBudgetAllocated*: int32         # PP allocated to Drungarius by Treasurer
    eparchBudgetAllocated*: int32             # PP allocated to Eparch by Treasurer
    buildOrdersGenerated*: int32              # Build orders created by Domestikos
    ppSpentConstruction*: int32               # Actual PP spent on construction
    domestikosRequirementsTotal*: int32       # Total requirements from Domestikos
    domestikosRequirementsFulfilled*: int32   # Requirements fulfilled by Treasurer mediation
    domestikosRequirementsUnfulfilled*: int32 # Requirements not affordable
    domestikosRequirementsDeferred*: int32    # Low-priority requirements deferred

    # Build Queue (NEW - track construction pipeline)
    totalBuildQueueDepth*: int32        # Sum of all colony queue depths
    etacInConstruction*: int32          # ETACs currently being built
    shipsUnderConstruction*: int32      # Ship squadrons in construction
    buildingsUnderConstruction*: int32  # Starbases/facilities building

    # Commissioning (NEW - track ship output)
    shipsCommissionedThisTurn*: int32
    etacCommissionedThisTurn*: int32
    squadronsCommissionedThisTurn*: int32

    # Fleet Activity (NEW - detect stuck fleets)
    fleetsMoved*: int32                 # Fleets that changed systems this turn
    systemsColonized*: int32            # Successful colonizations this turn
    failedColonizationAttempts*: int32  # Colonization orders rejected
    fleetsWithOrders*: int32            # Fleets with active orders
    stuckFleets*: int32                 # Fleets with orders but didn't move (pathfinding fail?)

    # ETAC Specific (NEW - critical for colonization)
    totalETACs*: int32              # Current ETAC count
    etacsWithoutOrders*: int32      # ETACs sitting idle (not colonizing)
    etacsInTransit*: int32          # ETACs moving to targets

    # Change Deltas (NEW - track turn-over-turn losses/gains)
    coloniesLost*: int32                   # Colonies lost this turn (conquest/rebellion)
    coloniesGained*: int32                 # Colonies gained this turn (colonization/conquest)
    coloniesGainedViaColonization*: int32  # Colonies gained via ETAC colonization
    coloniesGainedViaConquest*: int32      # Colonies gained via invasion/blitz
    shipsLost*: int32                      # Ships destroyed this turn (all types)
    shipsGained*: int32                    # Ships commissioned this turn (all types)
    fightersLost*: int32                   # Fighter squadrons lost this turn
    fightersGained*: int32                 # Fighter squadrons gained this turn

    # Bilateral Diplomatic Relations (semicolon-separated: houseId:state)
    bilateralRelations*: string   # e.g., "house-harkonnen:Hostile;house-ordos:Neutral"

    # Event Counts (track event generation for balance testing)
    eventsOrderCompleted*: int32    # OrderCompleted events this turn
    eventsOrderFailed*: int32       # OrderFailed events this turn
    eventsOrderRejected*: int32     # OrderRejected events this turn
    eventsCombatTotal*: int32       # Total combat events (Battle, SystemCaptured, etc.)
    eventsBombardment*: int32       # Bombardment events this turn
    eventsColonyCaptured*: int32    # ColonyCaptured events this turn
    eventsEspionageTotal*: int32    # Total espionage events this turn
    eventsDiplomaticTotal*: int32   # Total diplomatic events this turn
    eventsResearchTotal*: int32     # Research/TechAdvance events this turn
    eventsColonyTotal*: int32       # Colony-related events this turn

    # Economic Efficiency & Health
    upkeepAsPercentageOfIncome*: float32
    gcoPerPopulationUnit*: float32
    constructionSpendingAsPercentageOfIncome*: float32

    # Military Effectiveness & Doctrine
    forceProjection*: int32
    fleetReadiness*: float32
    economicDamageEfficiency*: float32
    capitalShipRatio*: float32

    # Diplomatic Strategy
    averageWarDuration*: int32
    relationshipVolatility*: int32

    # Expansion and Empire Stability
    averageColonyDevelopment*: float32
    borderFriction*: int32

  DiagnosticSession* = object
    ## Collection of all diagnostics for a game session
    gameId*: string
    seed*: int64
    numHouses*: int32
    mapSize*: int32
    turnLimit*: int32
    metrics*: seq[DiagnosticMetrics]  # All collected metrics
