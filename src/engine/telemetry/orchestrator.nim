## @engine/telemetry/orchestrator.nim
##
## Public API for telemetry system. Orchestrates collection from all domain
## collectors using event-driven architecture.

import ../types/[telemetry, core, game_state]
import ./collectors/[
  combat, military, fleet, facilities, colony, production, capacity,
  population, income, tech, espionage, diplomacy, house
]

proc initDiagnosticMetrics*(turn: int32, houseId: HouseId,
                           strategy: string = "Balanced",
                           gameId: string = ""): DiagnosticMetrics =
  ## Initialize empty diagnostic metrics for a house at a turn
  result = DiagnosticMetrics(
    gameId: gameId,
    turn: turn,
    act: 1'i32,  # Default to Act 1, will be calculated in collectDiagnostics
    rank: 0'i32,  # Default to 0, will be calculated in collectDiagnostics
    houseId: houseId,
    strategy: strategy,
    totalSystemsOnMap: 0'i32,  # Will be set in collectDiagnostics

    # Economy
    treasuryBalance: 0'i32,
    productionPerTurn: 0'i32,
    puGrowth: 0'i32,
    zeroSpendTurns: 0'i32,
    grossColonyOutput: 0'i32,
    netHouseValue: 0'i32,
    taxRate: 0'i32,
    totalIndustrialUnits: 0'i32,
    totalPopulationUnits: 0'i32,
    totalPopulationPTU: 0'i32,
    populationGrowthRate: 0'i32,

    # Tech Levels
    techCST: 1'i32, techWEP: 1'i32, techEL: 1'i32, techSL: 1'i32, techTER: 1'i32,
    techELI: 1'i32, techCLK: 1'i32, techSLD: 1'i32, techCIC: 1'i32, techFD: 1'i32, techACO: 1'i32,

    # Research Points
    researchERP: 0'i32, researchSRP: 0'i32, researchTRP: 0'i32, researchBreakthroughs: 0'i32,

    # Research Waste Tracking
    researchWastedERP: 0'i32, researchWastedSRP: 0'i32,
    turnsAtMaxEL: 0'i32, turnsAtMaxSL: 0'i32,

    # Maintenance & Prestige
    maintenanceCostTotal: 0'i32, maintenanceShortfallTurns: 0'i32,
    prestigeCurrent: 0'i32, prestigeChange: 0'i32, prestigeVictoryProgress: 0'i32,

    # Combat Performance
    combatCERAverage: 0'i32, bombardmentRoundsTotal: 0'i32, groundCombatVictories: 0'i32,
    retreatsExecuted: 0'i32, criticalHitsDealt: 0'i32, criticalHitsReceived: 0'i32,
    cloakedAmbushSuccess: 0'i32, shieldsActivatedCount: 0'i32,

    # Diplomatic Status
    allyStatusCount: 0'i32, hostileStatusCount: 0'i32, enemyStatusCount: 0'i32,
    neutralStatusCount: 0'i32,
    pactViolationsTotal: 0'i32, dishonoredStatusActive: false,
    diplomaticIsolationTurns: 0'i32,

    # Treaty Activity Metrics
    pactFormationsTotal: 0'i32, pactBreaksTotal: 0'i32,
    hostilityDeclarationsTotal: 0'i32, warDeclarationsTotal: 0'i32,

    # Espionage Activity
    espionageSuccessCount: 0'i32, espionageFailureCount: 0'i32,
    espionageDetectedCount: 0'i32,
    techTheftsSuccessful: 0'i32, sabotageOperations: 0'i32, assassinationAttempts: 0'i32,
    cyberAttacksLaunched: 0'i32, ebpPointsSpent: 0'i32, cipPointsSpent: 0'i32,
    counterIntelSuccesses: 0'i32,

    # Population & Colony Management
    populationTransfersActive: 0'i32, populationTransfersCompleted: 0'i32,
    populationTransfersLost: 0'i32, ptuTransferredTotal: 0'i32,
    coloniesBlockadedCount: 0'i32, blockadeTurnsCumulative: 0'i32,

    # Economic Health
    treasuryDeficit: false, infrastructureDamageTotal: 0'i32,
    salvageValueRecovered: 0'i32, maintenanceCostDeficit: 0'i32,
    taxPenaltyActive: false, avgTaxRate6Turn: 0'i32,

    # Squadron Capacity & Violations
    fighterCapacityMax: 0'i32, fighterCapacityUsed: 0'i32, fighterCapacityViolation: false,
    squadronLimitMax: 0'i32, squadronLimitUsed: 0'i32, squadronLimitViolation: false,
    starbasesActual: 0'i32,

    # House Status
    autopilotActive: false, defensiveCollapseActive: false,
    turnsUntilElimination: 0'i32, missedOrderTurns: 0'i32,

    # Military
    spaceCombatWins: 0'i32,
    spaceCombatLosses: 0'i32,
    spaceCombatTotal: 0'i32,
    orbitalFailures: 0'i32,
    orbitalTotal: 0'i32,
    raiderAmbushSuccess: 0'i32,
    raiderAmbushAttempts: 0'i32,
    raiderDetectedCount: 0'i32,
    raiderStealthSuccessCount: 0'i32,
    eliDetectionAttempts: 0'i32,
    avgEliRoll: 0'f32,
    avgClkRoll: 0'f32,
    scoutsDetected: 0'i32,
    scoutsDetectedBy: 0'i32,

    # Logistics
    capacityViolationsActive: 0'i32,
    fightersDisbanded: 0'i32,
    totalFighters: 0'i32,
    idleCarriers: 0'i32,
    totalCarriers: 0'i32,
    totalTransports: 0'i32,

    # Ship Counts (all 19 ship types)
    fighterShips: 0'i32,
    corvetteShips: 0'i32,
    frigateShips: 0'i32,
    scoutShips: 0'i32,
    raiderShips: 0'i32,
    destroyerShips: 0'i32,
    cruiserShips: 0'i32,
    lightCruiserShips: 0'i32,
    heavyCruiserShips: 0'i32,
    battlecruiserShips: 0'i32,
    battleshipShips: 0'i32,
    dreadnoughtShips: 0'i32,
    superDreadnoughtShips: 0'i32,
    carrierShips: 0'i32,
    superCarrierShips: 0'i32,
    etacShips: 0'i32,
    troopTransportShips: 0'i32,
    planetBreakerShips: 0'i32,
    totalShips: 0'i32,

    # Ground Unit Counts (all 4 ground unit types)
    planetaryShieldUnits: 0'i32,
    groundBatteryUnits: 0'i32,
    armyUnits: 0'i32,
    marinesAtColonies: 0'i32,
    marinesOnTransports: 0'i32,
    marineDivisionUnits: 0'i32,

    # Facilities
    totalSpaceports: 0'i32,
    totalShipyards: 0'i32,
    totalDrydocks: 0'i32,

    # Intel
    totalInvasions: 0'i32,
    vulnerableTargets_count: 0'i32,
    invasionOrders_generated: 0'i32,
    invasionOrders_bombard: 0'i32,
    invasionOrders_invade: 0'i32,
    invasionOrders_blitz: 0'i32,
    invasionOrders_canceled: 0'i32,
    activeCampaigns_total: 0'i32,
    activeCampaigns_scouting: 0'i32,
    activeCampaigns_bombardment: 0'i32,
    activeCampaigns_invasion: 0'i32,
    campaigns_completed_success: 0'i32,
    campaigns_abandoned_stalled: 0'i32,
    campaigns_abandoned_captured: 0'i32,
    campaigns_abandoned_timeout: 0'i32,
    invasionAttemptsTotal: 0'i32,
    invasionAttemptsSuccessful: 0'i32,
    invasionAttemptsFailed: 0'i32,
    invasionOrdersRejected: 0'i32,
    blitzAttemptsTotal: 0'i32,
    blitzAttemptsSuccessful: 0'i32,
    blitzAttemptsFailed: 0'i32,
    bombardmentAttemptsTotal: 0'i32,
    bombardmentOrdersFailed: 0'i32,
    invasionMarinesKilled: 0'i32,
    invasionDefendersKilled: 0'i32,
    clkResearchedNoRaiders: false,
    scoutCount: 0'i32,
    spyPlanetMissions: 0'i32,
    hackStarbaseMissions: 0'i32,
    totalEspionageMissions: 0'i32,

    # Defense
    coloniesWithoutDefense: 0'i32,
    totalColonies: 0'i32,
    mothballedFleetsUsed: 0'i32,
    mothballedFleetsTotal: 0'i32,

    # Orders
    invalidOrders: 0'i32,
    totalOrders: 0'i32,
    fleetOrdersSubmitted: 0'i32,
    buildOrdersSubmitted: 0'i32,
    colonizeOrdersSubmitted: 0'i32,

    # Budget Allocation
    domestikosBudgetAllocated: 0'i32,
    logotheteBudgetAllocated: 0'i32,
    drungariusBudgetAllocated: 0'i32,
    eparchBudgetAllocated: 0'i32,
    buildOrdersGenerated: 0'i32,
    ppSpentConstruction: 0'i32,
    domestikosRequirementsTotal: 0'i32,
    domestikosRequirementsFulfilled: 0'i32,
    domestikosRequirementsUnfulfilled: 0'i32,
    domestikosRequirementsDeferred: 0'i32,

    # Build Queue
    totalBuildQueueDepth: 0'i32,
    etacInConstruction: 0'i32,
    shipsUnderConstruction: 0'i32,
    buildingsUnderConstruction: 0'i32,

    # Commissioning
    shipsCommissionedThisTurn: 0'i32,
    etacCommissionedThisTurn: 0'i32,
    squadronsCommissionedThisTurn: 0'i32,

    # Fleet Activity
    fleetsMoved: 0'i32,
    systemsColonized: 0'i32,
    failedColonizationAttempts: 0'i32,
    fleetsWithOrders: 0'i32,
    stuckFleets: 0'i32,

    # ETAC Specific
    totalETACs: 0'i32,
    etacsWithoutOrders: 0'i32,
    etacsInTransit: 0'i32,

    # Change Deltas (will be calculated from prevMetrics)
    coloniesLost: 0'i32,
    coloniesGained: 0'i32,
    coloniesGainedViaColonization: 0'i32,
    coloniesGainedViaConquest: 0'i32,
    shipsLost: 0'i32,
    shipsGained: 0'i32,
    fightersLost: 0'i32,
    fightersGained: 0'i32,

    # Bilateral Diplomatic Relations
    bilateralRelations: "",

    # Advisor Reasoning
    advisorReasoning: "",

    # Event Counts
    eventsOrderCompleted: 0'i32,
    eventsOrderFailed: 0'i32,
    eventsOrderRejected: 0'i32,
    eventsCombatTotal: 0'i32,
    eventsBombardment: 0'i32,
    eventsColonyCaptured: 0'i32,
    eventsEspionageTotal: 0'i32,
    eventsDiplomaticTotal: 0'i32,
    eventsResearchTotal: 0'i32,
    eventsColonyTotal: 0'i32,

    # GOAP Metrics
    goapEnabled: false,
    goapPlansActive: 0'i32,
    goapPlansCompleted: 0'i32,
    goapGoalsExtracted: 0'i32,
    goapPlanningTimeMs: 0'f32,
    goapInvasionGoals: 0'i32,
    goapInvasionPlans: 0'i32,
    goapActionsExecuted: 0'i32,
    goapActionsFailed: 0'i32
  )
    
proc collectDiagnostics*(
  state: GameState,
  houseId: HouseId,
  strategy: string = "",
  gameId: string = "",
  act: int32 = 0'i32,
  rank: int32 = 0'i32
): DiagnosticMetrics =
  ## Collect comprehensive diagnostics for a house using all domain collectors.
  ##
  ## This is the main entry point for telemetry collection. It orchestrates
  ## all 13 domain-specific collectors in sequence.
  ##
  ## Pure event-driven architecture:
  ## - Processes events from state.lastTurnEvents
  ## - Queries GameState for snapshot metrics (counts, totals)
  ## - No TurnResolutionReport dependency
  ##
  ## Args:
  ##   state: Current game state with lastTurnEvents populated
  ##   houseId: House to collect metrics for
  ##   strategy: AI strategy name (optional)
  ##   gameId: Game identifier (optional)
  ##   act: Current act/chapter (optional)
  ##   rank: House rank/position (optional)
  ##
  ## Returns:
  ##   Complete DiagnosticMetrics for the house

  # Initialize metrics with metadata
  var metrics = initDiagnosticMetrics(state.turn, houseId, strategy, gameId)
  metrics.act = act
  metrics.rank = rank

  # Collect from each domain collector in sequence
  # Each collector processes events and queries GameState
  metrics = collectCombatMetrics(state, houseId, metrics)
  metrics = collectMilitaryMetrics(state, houseId, metrics)
  metrics = collectFleetMetrics(state, houseId, metrics)
  metrics = collectFacilitiesMetrics(state, houseId, metrics)
  metrics = collectColonyMetrics(state, houseId, metrics)
  metrics = collectProductionMetrics(state, houseId, metrics)
  metrics = collectCapacityMetrics(state, houseId, metrics)
  metrics = collectPopulationMetrics(state, houseId, metrics)
  metrics = collectIncomeMetrics(state, houseId, metrics)
  metrics = collectTechMetrics(state, houseId, metrics)
  metrics = collectEspionageMetrics(state, houseId, metrics)
  metrics = collectDiplomacyMetrics(state, houseId, metrics)
  metrics = collectHouseMetrics(state, houseId, metrics)

  return metrics
