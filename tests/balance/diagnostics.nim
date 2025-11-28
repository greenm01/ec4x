## Diagnostic Metrics Collection System
##
## Tracks per-house, per-turn metrics to identify systematic AI failures
## Per Grok gap analysis: "Run diagnostics. Let the numbers tell you exactly what's missing."

import std/[tables, strformat, streams, options]
import ../../src/engine/[gamestate, fleet, squadron, orders, logger]
import ../../src/common/types/[core, units]

type
  DiagnosticMetrics* = object
    ## Metrics collected per house, per turn
    turn*: int
    houseId*: HouseId

    # Economy (Core)
    treasuryBalance*: int
    productionPerTurn*: int
    puGrowth*: int              # Change in PU from last turn
    zeroSpendTurns*: int        # Cumulative turns with 0 treasury spending
    grossColonyOutput*: int     # GCO = sum of all colony production (before tax)
    netHouseValue*: int         # NHV = GCO × tax rate
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
    combatCERAverage*: int           # Average CER in space combat (×100 for precision)
    bombardmentRoundsTotal*: int     # Total bombardment rounds executed
    groundCombatVictories*: int      # Successful invasions/blitz
    retreatsExecuted*: int           # Times fleets retreated from combat
    criticalHitsDealt*: int          # Critical hits scored (nat 9 on 1d10)
    criticalHitsReceived*: int       # Critical hits taken
    cloakedAmbushSuccess*: int       # Successful cloaked raider ambushes
    shieldsActivatedCount*: int      # Times planetary shields blocked hits

    # Diplomatic Status (from diplomacy.toml)
    activePactsCount*: int           # Current active Non-Aggression Pacts
    pactViolationsTotal*: int        # Cumulative pact violations (lifetime)
    dishonoredStatusActive*: bool    # Currently dishonored?
    diplomaticIsolationTurns*: int   # Turns remaining in isolation
    enemyStatusCount*: int           # Houses at Enemy status
    neutralStatusCount*: int         # Houses at Neutral status

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
    fighterCapacityMax*: int         # Max FS allowed (PU/100 × FD multiplier)
    fighterCapacityUsed*: int        # Actual FS count (current)
    fighterCapacityViolation*: bool  # Over capacity?
    squadronLimitMax*: int           # Max capital squadrons allowed (PU/100)
    squadronLimitUsed*: int          # Actual capital squadron count
    squadronLimitViolation*: bool    # Over squadron limit?
    starbasesRequired*: int          # Starbases needed for current FS count (ceil(FS/5))
    starbasesActual*: int            # Actual starbase count

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
    starbaseShips*: int               # SB Starbase
    etacShips*: int                   # ETAC-class ships
    troopTransportShips*: int         # Troop Transport
    planetBreakerShips*: int          # PB Planet-Breaker (CST 10)

    # Ground Unit Counts (all 4 ground unit types)
    planetaryShieldUnits*: int        # PS Planetary Shield (CST 5)
    groundBatteryUnits*: int          # GB Ground Batteries
    armyUnits*: int                   # AA Armies
    marineDivisionUnits*: int         # MD Space Marines

    # Intel / Tech
    invasionFleetsWithoutELIMesh*: int  # Invasions without 3+ scout ELI mesh
    totalInvasions*: int
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

  DiagnosticSession* = object
    ## Collection of all diagnostics for a game session
    gameId*: string
    seed*: int64
    numHouses*: int
    mapSize*: int
    turnLimit*: int
    metrics*: seq[DiagnosticMetrics]  # All collected metrics

proc initDiagnosticMetrics*(turn: int, houseId: HouseId): DiagnosticMetrics =
  ## Initialize empty diagnostic metrics for a house at a turn
  result = DiagnosticMetrics(
    turn: turn,
    houseId: houseId,

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
    activePactsCount: 0, pactViolationsTotal: 0, dishonoredStatusActive: false,
    diplomaticIsolationTurns: 0, enemyStatusCount: 0, neutralStatusCount: 0,

    # Espionage Activity
    espionageSuccessCount: 0, espionageFailureCount: 0, espionageDetectedCount: 0,
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
    starbasesRequired: 0, starbasesActual: 0,

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

    # Intel
    invasionFleetsWithoutELIMesh: 0,
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
    totalOrders: 0
  )

proc collectEconomyMetrics(state: GameState, houseId: HouseId,
                          prevMetrics: Option[DiagnosticMetrics]): DiagnosticMetrics =
  ## Collect economy-related metrics
  result = initDiagnosticMetrics(state.turn, houseId)

  let house = state.houses.getOrDefault(houseId)
  result.treasuryBalance = house.treasury

  # Calculate comprehensive economic metrics from colonies
  var totalProduction = 0
  var totalPU = 0
  var totalPTU = 0
  var totalIU = 0
  var grossColonyOutput = 0

  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      totalProduction += colony.production
      totalPU += colony.population  # Population in millions (display field)
      totalPTU += colony.souls div 50000  # souls / 50k = PTU (approximation)
      totalIU += colony.infrastructure  # Using infrastructure as proxy for IU
      # GCO = colony output before tax (use production as proxy)
      grossColonyOutput += colony.production

  result.productionPerTurn = totalProduction
  result.totalPopulationUnits = totalPU
  result.totalPopulationPTU = totalPTU
  result.totalIndustrialUnits = totalIU
  result.grossColonyOutput = grossColonyOutput

  # Tax rate and NHV
  result.taxRate = house.taxPolicy.currentRate
  result.netHouseValue = (grossColonyOutput * house.taxPolicy.currentRate) div 100

  # Population growth rate (base 2.0% + tax modifiers from economy.md)
  # Simplified: just track base rate for now
  result.populationGrowthRate = 200  # 2.00% in basis points

  # Tech Levels (all 11 technology types)
  result.techCST = house.techTree.levels.constructionTech
  result.techWEP = house.techTree.levels.weaponsTech
  result.techEL = house.techTree.levels.economicLevel
  result.techSL = house.techTree.levels.scienceLevel
  result.techTER = house.techTree.levels.terraformingTech
  result.techELI = house.techTree.levels.electronicIntelligence
  result.techCLK = house.techTree.levels.cloakingTech
  result.techSLD = house.techTree.levels.shieldTech
  result.techCIC = house.techTree.levels.counterIntelligence
  result.techFD = house.techTree.levels.fighterDoctrine
  result.techACO = house.techTree.levels.advancedCarrierOps

  # Research Points (tracked from turn resolution)
  result.researchERP = house.lastTurnResearchERP
  result.researchSRP = house.lastTurnResearchSRP
  result.researchTRP = house.lastTurnResearchTRP
  result.researchBreakthroughs = 0  # TODO: track breakthroughs when tech advancement implemented

  # Research Waste Tracking (Tech Level Caps)
  # Track wasted RP when investing in maxed tech levels
  const maxEconomicLevel = 11
  const maxScienceLevel = 8

  # Track ERP waste if EL at max
  if result.techEL >= maxEconomicLevel and result.researchERP > 0:
    result.researchWastedERP = result.researchERP
  else:
    result.researchWastedERP = 0

  # Track SRP waste if SL at max
  if result.techSL >= maxScienceLevel and result.researchSRP > 0:
    result.researchWastedSRP = result.researchSRP
  else:
    result.researchWastedSRP = 0

  # Track consecutive turns at max levels (similar to prestigeVictoryProgress)
  if prevMetrics.isSome:
    if result.techEL >= maxEconomicLevel:
      result.turnsAtMaxEL = prevMetrics.get.turnsAtMaxEL + 1
    else:
      result.turnsAtMaxEL = 0

    if result.techSL >= maxScienceLevel:
      result.turnsAtMaxSL = prevMetrics.get.turnsAtMaxSL + 1
    else:
      result.turnsAtMaxSL = 0
  else:
    # First turn
    result.turnsAtMaxEL = if result.techEL >= maxEconomicLevel: 1 else: 0
    result.turnsAtMaxSL = if result.techSL >= maxScienceLevel: 1 else: 0

  # Maintenance & Prestige
  # TODO: track maintenance costs from turn resolution
  result.maintenanceCostTotal = 0
  result.maintenanceShortfallTurns = 0
  result.prestigeCurrent = house.prestige
  if prevMetrics.isSome:
    result.prestigeChange = house.prestige - prevMetrics.get.prestigeCurrent
  else:
    result.prestigeChange = 0

  # Victory progress: count turns at prestige >= 1500
  if prevMetrics.isSome and house.prestige >= 1500:
    result.prestigeVictoryProgress = prevMetrics.get.prestigeVictoryProgress + 1
  elif house.prestige >= 1500:
    result.prestigeVictoryProgress = 1
  else:
    result.prestigeVictoryProgress = 0

  # Calculate PU growth (change from last turn)
  if prevMetrics.isSome:
    let prev = prevMetrics.get
    result.puGrowth = totalProduction - prev.productionPerTurn

    # Track zero-spend turns
    if house.treasury == prev.treasuryBalance:
      result.zeroSpendTurns = prev.zeroSpendTurns + 1
    else:
      result.zeroSpendTurns = prev.zeroSpendTurns
  else:
    result.puGrowth = 0
    result.zeroSpendTurns = 0

  # Economic Health indicators
  # TODO: track actual maintenance cost from turn resolution
  result.treasuryDeficit = false  # Will be set by turn resolution
  result.maintenanceCostDeficit = 0

  # Tax rate analysis (6-turn rolling average)
  result.avgTaxRate6Turn = house.taxPolicy.currentRate  # TODO: calculate true 6-turn average from history
  result.taxPenaltyActive = house.taxPolicy.currentRate > 50  # Simplified: penalty if >50%

  # Squadron capacity calculations (from military.toml)
  let fdMultiplier = case house.techTree.levels.fighterDoctrine
    of 1: 1.0
    of 2: 1.5
    of 3: 2.0
    else: 1.0

  result.fighterCapacityMax = int(float(totalPU) / 100.0 * fdMultiplier)

  # Count fighters from colonies
  var totalFighters = 0
  var totalStarbases = 0
  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      totalFighters += colony.fighterSquadrons.len
      totalStarbases += colony.starbases.len

  result.fighterCapacityUsed = totalFighters
  result.fighterCapacityViolation = result.fighterCapacityUsed > result.fighterCapacityMax

  result.squadronLimitMax = max(8, totalPU div 100)  # Minimum 8, otherwise PU/100
  # TODO: Count actual capital squadrons (not all squadrons, just capitals+carriers)
  result.squadronLimitUsed = 0
  result.squadronLimitViolation = false

  result.starbasesRequired = (totalFighters + 4) div 5  # Ceiling division: (n+4)/5
  result.starbasesActual = totalStarbases

  # Blockade tracking
  var blockadedCount = 0
  var blockadeTurns = 0
  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      if colony.blockaded:
        blockadedCount += 1
        blockadeTurns += colony.blockadeTurns
  result.coloniesBlockadedCount = blockadedCount
  result.blockadeTurnsCumulative = blockadeTurns

  # Population transfers (from Space Guild transfers)
  result.populationTransfersActive = state.populationInTransit.len  # Total transfers, not just this house
  # TODO: Filter to only this house's transfers
  result.populationTransfersCompleted = 0  # TODO: track from turn resolution
  result.populationTransfersLost = 0
  result.ptuTransferredTotal = 0

proc collectDiplomaticMetrics(state: GameState, houseId: HouseId): DiagnosticMetrics =
  ## Collect diplomatic status metrics
  result = initDiagnosticMetrics(state.turn, houseId)

  let house = state.houses.getOrDefault(houseId)

  # Count diplomatic relationships
  var pactsCount = 0
  var enemyCount = 0
  var neutralCount = 0

  for otherHouseId, otherHouse in state.houses:
    if otherHouseId == houseId or otherHouse.eliminated:
      continue

    # Check diplomatic state
    let dipKey = if houseId < otherHouseId: (houseId, otherHouseId) else: (otherHouseId, houseId)
    if dipKey in state.diplomacy:
      let dipState = state.diplomacy[dipKey]
      # TODO: Check actual diplomatic state (need to understand DiplomaticState type)
      # For now, count based on relations
      neutralCount += 1

  result.activePactsCount = pactsCount
  result.enemyStatusCount = enemyCount
  result.neutralStatusCount = neutralCount

  # Violation tracking
  result.pactViolationsTotal = house.violationHistory.violations.len
  result.dishonoredStatusActive = house.dishonoredStatus.active
  result.diplomaticIsolationTurns = house.diplomaticIsolation.turnsRemaining

proc collectHouseStatusMetrics(state: GameState, houseId: HouseId): DiagnosticMetrics =
  ## Collect house operational status metrics
  result = initDiagnosticMetrics(state.turn, houseId)

  let house = state.houses.getOrDefault(houseId)

  # House status from gameplay.toml thresholds
  result.autopilotActive = house.status == HouseStatus.Autopilot
  result.defensiveCollapseActive = house.status == HouseStatus.DefensiveCollapse
  result.missedOrderTurns = house.turnsWithoutOrders

  # Elimination countdown
  if house.prestige < 0:
    result.turnsUntilElimination = 3 - house.negativePrestigeTurns
  else:
    result.turnsUntilElimination = 0

proc collectMilitaryMetrics(state: GameState, houseId: HouseId): DiagnosticMetrics =
  ## Collect military-related metrics
  result = initDiagnosticMetrics(state.turn, houseId)

  # TODO: Track combat results from turn resolution
  # For now, initialize to zero (will be updated by turn resolution tracking)
  result.spaceCombatWins = 0
  result.spaceCombatLosses = 0
  result.spaceCombatTotal = 0
  result.orbitalFailures = 0
  result.orbitalTotal = 0
  result.raiderAmbushSuccess = 0
  result.raiderAmbushAttempts = 0

  # Combat performance metrics (would be tracked during resolution)
  result.combatCERAverage = 0
  result.bombardmentRoundsTotal = 0
  result.groundCombatVictories = 0
  result.retreatsExecuted = 0
  result.criticalHitsDealt = 0
  result.criticalHitsReceived = 0
  result.cloakedAmbushSuccess = 0
  result.shieldsActivatedCount = 0

proc collectLogisticsMetrics(state: GameState, houseId: HouseId): DiagnosticMetrics =
  ## Collect logistics-related metrics
  result = initDiagnosticMetrics(state.turn, houseId)

  # Count active capacity violations
  var violationCount = 0
  var totalFighters = 0
  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      totalFighters += colony.fighterSquadrons.len
      if colony.capacityViolation.active:
        violationCount += 1

  result.capacityViolationsActive = violationCount
  result.totalFighters = totalFighters

  # Count idle carriers and total carriers
  var idleCarrierCount = 0
  var totalCarrierCount = 0

  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      for squadron in fleet.squadrons:
        if squadron.flagship.shipClass == ShipClass.Carrier:
          totalCarrierCount += 1
          # Check if carrier has fighters loaded
          if squadron.embarkedFighters.len == 0:
            idleCarrierCount += 1

  result.idleCarriers = idleCarrierCount
  result.totalCarriers = totalCarrierCount

  # Count all 19 ship classes
  var fighterShips = 0
  var corvetteShips = 0
  var frigateShips = 0
  var scoutShips = 0
  var raiderShips = 0
  var destroyerShips = 0
  var cruiserShips = 0
  var lightCruiserShips = 0
  var heavyCruiserShips = 0
  var battlecruiserShips = 0
  var battleshipShips = 0
  var dreadnoughtShips = 0
  var superDreadnoughtShips = 0
  var carrierShips = 0
  var superCarrierShips = 0
  var starbaseShips = 0
  var etacShips = 0
  var troopTransportShips = 0
  var planetBreakerShips = 0

  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      # Count squadron ships (military)
      for squadron in fleet.squadrons:
        case squadron.flagship.shipClass:
        of ShipClass.Fighter: fighterShips += 1
        of ShipClass.Corvette: corvetteShips += 1
        of ShipClass.Frigate: frigateShips += 1
        of ShipClass.Scout: scoutShips += 1
        of ShipClass.Raider: raiderShips += 1
        of ShipClass.Destroyer: destroyerShips += 1
        of ShipClass.Cruiser: cruiserShips += 1
        of ShipClass.LightCruiser: lightCruiserShips += 1
        of ShipClass.HeavyCruiser: heavyCruiserShips += 1
        of ShipClass.Battlecruiser: battlecruiserShips += 1
        of ShipClass.Battleship: battleshipShips += 1
        of ShipClass.Dreadnought: dreadnoughtShips += 1
        of ShipClass.SuperDreadnought: superDreadnoughtShips += 1
        of ShipClass.Carrier: carrierShips += 1
        of ShipClass.SuperCarrier: superCarrierShips += 1
        of ShipClass.Starbase: starbaseShips += 1
        of ShipClass.PlanetBreaker: planetBreakerShips += 1
        of ShipClass.ETAC: etacShips += 1  # Should not happen in squadrons
        of ShipClass.TroopTransport: troopTransportShips += 1  # Should not happen in squadrons

      # Count spacelift ships (ETAC and TroopTransport are here)
      for spaceLiftShip in fleet.spaceLiftShips:
        case spaceLiftShip.shipClass:
        of ShipClass.ETAC: etacShips += 1
        of ShipClass.TroopTransport: troopTransportShips += 1
        else: discard  # Spacelift shouldn't have other classes

  result.fighterShips = fighterShips
  result.corvetteShips = corvetteShips
  result.frigateShips = frigateShips
  result.scoutShips = scoutShips
  result.raiderShips = raiderShips
  result.destroyerShips = destroyerShips
  result.cruiserShips = cruiserShips
  result.lightCruiserShips = lightCruiserShips
  result.heavyCruiserShips = heavyCruiserShips
  result.battlecruiserShips = battlecruiserShips
  result.battleshipShips = battleshipShips
  result.dreadnoughtShips = dreadnoughtShips
  result.superDreadnoughtShips = superDreadnoughtShips
  result.carrierShips = carrierShips
  result.superCarrierShips = superCarrierShips
  result.starbaseShips = starbaseShips
  result.etacShips = etacShips
  result.troopTransportShips = troopTransportShips
  result.planetBreakerShips = planetBreakerShips

  # Count all 4 ground unit types (stored as int fields in Colony)
  var planetaryShieldUnits = 0
  var groundBatteryUnits = 0
  var armyUnits = 0
  var marineDivisionUnits = 0

  for colonyId, colony in state.colonies:
    if colony.owner == houseId:
      if colony.planetaryShieldLevel > 0:
        planetaryShieldUnits += 1  # Colony has shield (level 1-6)
      groundBatteryUnits += colony.groundBatteries
      armyUnits += colony.armies
      marineDivisionUnits += colony.marines

  result.planetaryShieldUnits = planetaryShieldUnits
  result.groundBatteryUnits = groundBatteryUnits
  result.armyUnits = armyUnits
  result.marineDivisionUnits = marineDivisionUnits

  # Count transports (spacelift ships: ETAC + TroopTransport, not squadrons)
  var transportCount = 0
  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      for spaceLiftShip in fleet.spaceLiftShips:
        # Count both ETAC (colonization) and TroopTransport (invasion)
        if spaceLiftShip.shipClass in [ShipClass.ETAC, ShipClass.TroopTransport]:
          transportCount += 1
      # Debug: log spacelift ship counts per fleet
      if fleet.spaceLiftShips.len > 0:
        logDebug(LogCategory.lcAI, &"Fleet {fleetId} has {fleet.spaceLiftShips.len} spacelift ships")

  result.totalTransports = transportCount
  if transportCount > 0:
    logDebug(LogCategory.lcAI, &"{houseId} has {transportCount} transports")

  # Phase 2c: Count scouts for ELI mesh tracking
  var scoutCount = 0

  # Count scouts in fleets
  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      for squadron in fleet.squadrons:
        if squadron.flagship.shipClass == ShipClass.Scout:
          scoutCount += 1
        for ship in squadron.ships:
          if ship.shipClass == ShipClass.Scout:
            scoutCount += 1

  # Count unassigned scouts at colonies (not yet assigned to fleets)
  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      for squadron in colony.unassignedSquadrons:
        if squadron.flagship.shipClass == ShipClass.Scout:
          scoutCount += 1
        for ship in squadron.ships:
          if ship.shipClass == ShipClass.Scout:
            scoutCount += 1

  result.scoutCount = scoutCount

  # TODO: Track fighters disbanded due to capacity
  result.fightersDisbanded = 0

proc collectIntelMetrics(state: GameState, houseId: HouseId): DiagnosticMetrics =
  ## Collect intelligence and tech metrics
  result = initDiagnosticMetrics(state.turn, houseId)

  let house = state.houses.getOrDefault(houseId)

  # Check if CLK researched but no Raiders built
  let hasCLK = house.techTree.levels.cloakingTech > 1
  var hasRaiders = false

  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      for squadron in fleet.squadrons:
        if squadron.flagship.shipClass == ShipClass.Raider:
          hasRaiders = true
          break

  result.clkResearchedNoRaiders = hasCLK and not hasRaiders

  # Count ELI mesh coverage on fleets
  var invasionsWithoutMesh = 0
  var totalInvasions = 0

  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      # Check if fleet has invasion capability (marines)
      var hasInvasionForce = false
      for ship in fleet.spaceLiftShips:
        if ship.cargo.cargoType == CargoType.Marines:
          hasInvasionForce = true
          break

      if hasInvasionForce:
        totalInvasions += 1

        # Count scouts in fleet
        var scoutCount = 0
        for squadron in fleet.squadrons:
          if squadron.flagship.shipClass == ShipClass.Scout:
            scoutCount += 1

        # ELI mesh requires 3+ scouts
        if scoutCount < 3:
          invasionsWithoutMesh += 1

  result.invasionFleetsWithoutELIMesh = invasionsWithoutMesh
  result.totalInvasions = totalInvasions

  # Espionage missions tracked separately (passed from orders)
  # These are set by the caller when passing order data
  result.spyPlanetMissions = 0
  result.hackStarbaseMissions = 0
  result.totalEspionageMissions = 0

proc collectDefenseMetrics(state: GameState, houseId: HouseId): DiagnosticMetrics =
  ## Collect defense-related metrics
  result = initDiagnosticMetrics(state.turn, houseId)

  # Count colonies without defense
  var undefendedColonies = 0
  var totalColonies = 0

  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      totalColonies += 1

      # Check if colony has defense (starbases or fleets in system)
      var hasDefense = colony.starbases.len > 0

      if not hasDefense:
        # Check for fleets in system
        for fleetId, fleet in state.fleets:
          if fleet.owner == houseId and fleet.location == systemId:
            hasDefense = true
            break

      if not hasDefense:
        undefendedColonies += 1

  result.coloniesWithoutDefense = undefendedColonies
  result.totalColonies = totalColonies

  # Track mothballed and reserve fleets
  var mothballedCount = 0
  var reserveCount = 0
  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      case fleet.status
      of FleetStatus.Mothballed:
        mothballedCount += 1
      of FleetStatus.Reserve:
        reserveCount += 1
      of FleetStatus.Active:
        discard

  result.mothballedFleetsTotal = mothballedCount + reserveCount  # Combined lifecycle management count
  # mothballedFleetsUsed tracks reactivations (cumulative, tracked elsewhere)
  result.mothballedFleetsUsed = 0

proc countEspionageMissions*(orders: OrderPacket): tuple[spyPlanet: int, hackStarbase: int, spySystem: int] =
  ## Count espionage-related fleet orders in an order packet
  result = (spyPlanet: 0, hackStarbase: 0, spySystem: 0)

  for order in orders.fleetOrders:
    case order.orderType
    of FleetOrderType.SpyPlanet:
      result.spyPlanet += 1
    of FleetOrderType.HackStarbase:
      result.hackStarbase += 1
    of FleetOrderType.SpySystem:
      result.spySystem += 1
    else:
      discard

proc collectDiagnostics*(state: GameState, houseId: HouseId,
                        prevMetrics: Option[DiagnosticMetrics] = none(DiagnosticMetrics),
                        orders: Option[OrderPacket] = none(OrderPacket)): DiagnosticMetrics =
  ## Collect all diagnostic metrics for a house at current turn
  result = initDiagnosticMetrics(state.turn, houseId)

  # Collect from different subsystems
  let econ = collectEconomyMetrics(state, houseId, prevMetrics)
  let mil = collectMilitaryMetrics(state, houseId)
  let log = collectLogisticsMetrics(state, houseId)
  let intel = collectIntelMetrics(state, houseId)
  let def = collectDefenseMetrics(state, houseId)
  let dip = collectDiplomaticMetrics(state, houseId)
  let status = collectHouseStatusMetrics(state, houseId)

  # Merge all metrics
  # Economy
  result.treasuryBalance = econ.treasuryBalance
  result.productionPerTurn = econ.productionPerTurn
  result.puGrowth = econ.puGrowth
  result.zeroSpendTurns = econ.zeroSpendTurns
  result.grossColonyOutput = econ.grossColonyOutput
  result.netHouseValue = econ.netHouseValue
  result.taxRate = econ.taxRate
  result.totalIndustrialUnits = econ.totalIndustrialUnits
  result.totalPopulationUnits = econ.totalPopulationUnits
  result.totalPopulationPTU = econ.totalPopulationPTU
  result.populationGrowthRate = econ.populationGrowthRate

  # Tech Levels
  result.techCST = econ.techCST
  result.techWEP = econ.techWEP
  result.techEL = econ.techEL
  result.techSL = econ.techSL
  result.techTER = econ.techTER
  result.techELI = econ.techELI
  result.techCLK = econ.techCLK
  result.techSLD = econ.techSLD
  result.techCIC = econ.techCIC
  result.techFD = econ.techFD
  result.techACO = econ.techACO

  # Research & Prestige
  result.researchERP = econ.researchERP
  result.researchSRP = econ.researchSRP
  result.researchTRP = econ.researchTRP
  result.researchBreakthroughs = econ.researchBreakthroughs
  result.researchWastedERP = econ.researchWastedERP
  result.researchWastedSRP = econ.researchWastedSRP
  result.turnsAtMaxEL = econ.turnsAtMaxEL
  result.turnsAtMaxSL = econ.turnsAtMaxSL
  result.maintenanceCostTotal = econ.maintenanceCostTotal
  result.maintenanceShortfallTurns = econ.maintenanceShortfallTurns
  result.prestigeCurrent = econ.prestigeCurrent
  result.prestigeChange = econ.prestigeChange
  result.prestigeVictoryProgress = econ.prestigeVictoryProgress

  result.spaceCombatWins = mil.spaceCombatWins
  result.spaceCombatLosses = mil.spaceCombatLosses
  result.spaceCombatTotal = mil.spaceCombatTotal
  result.orbitalFailures = mil.orbitalFailures
  result.orbitalTotal = mil.orbitalTotal
  result.raiderAmbushSuccess = mil.raiderAmbushSuccess
  result.raiderAmbushAttempts = mil.raiderAmbushAttempts

  result.capacityViolationsActive = log.capacityViolationsActive
  result.fightersDisbanded = log.fightersDisbanded
  result.totalFighters = log.totalFighters
  result.idleCarriers = log.idleCarriers
  result.totalCarriers = log.totalCarriers

  # Ship counts by class (all 19 ship types)
  result.fighterShips = log.fighterShips
  result.corvetteShips = log.corvetteShips
  result.frigateShips = log.frigateShips
  result.scoutShips = log.scoutShips
  result.raiderShips = log.raiderShips
  result.destroyerShips = log.destroyerShips
  result.cruiserShips = log.cruiserShips
  result.lightCruiserShips = log.lightCruiserShips
  result.heavyCruiserShips = log.heavyCruiserShips
  result.battlecruiserShips = log.battlecruiserShips
  result.battleshipShips = log.battleshipShips
  result.dreadnoughtShips = log.dreadnoughtShips
  result.superDreadnoughtShips = log.superDreadnoughtShips
  result.carrierShips = log.carrierShips
  result.superCarrierShips = log.superCarrierShips
  result.starbaseShips = log.starbaseShips
  result.etacShips = log.etacShips
  result.troopTransportShips = log.troopTransportShips
  result.planetBreakerShips = log.planetBreakerShips

  # Ground unit counts (all 4 ground unit types)
  result.planetaryShieldUnits = log.planetaryShieldUnits
  result.groundBatteryUnits = log.groundBatteryUnits
  result.armyUnits = log.armyUnits
  result.marineDivisionUnits = log.marineDivisionUnits

  result.invasionFleetsWithoutELIMesh = intel.invasionFleetsWithoutELIMesh
  result.totalInvasions = intel.totalInvasions
  result.clkResearchedNoRaiders = intel.clkResearchedNoRaiders
  result.scoutCount = log.scoutCount  # Phase 2c

  # Track espionage missions from orders (if provided)
  if orders.isSome:
    let espCounts = countEspionageMissions(orders.get)
    result.spyPlanetMissions = espCounts.spyPlanet
    result.hackStarbaseMissions = espCounts.hackStarbase
    result.totalEspionageMissions = espCounts.spyPlanet + espCounts.hackStarbase + espCounts.spySystem
  else:
    result.spyPlanetMissions = 0
    result.hackStarbaseMissions = 0
    result.totalEspionageMissions = 0

  # Track orders submitted this turn (ENHANCED for unknown-unknowns detection)
  if orders.isSome:
    let packet = orders.get
    result.fleetOrdersSubmitted = packet.fleetOrders.len
    result.buildOrdersSubmitted = packet.buildOrders.len

    # Count colonization orders from fleet orders
    var colonizeCount = 0
    for fleetOrder in packet.fleetOrders:
      if fleetOrder.orderType == FleetOrderType.Colonize:
        colonizeCount += 1
    result.colonizeOrdersSubmitted = colonizeCount

    # Total orders = fleet + build orders
    result.totalOrders = packet.fleetOrders.len + packet.buildOrders.len

    # TODO: Track invalid orders (need turn resolution feedback)
    result.invalidOrders = 0
  else:
    result.fleetOrdersSubmitted = 0
    result.buildOrdersSubmitted = 0
    result.colonizeOrdersSubmitted = 0
    result.totalOrders = 0
    result.invalidOrders = 0

  result.coloniesWithoutDefense = def.coloniesWithoutDefense
  result.totalColonies = def.totalColonies
  result.mothballedFleetsUsed = def.mothballedFleetsUsed
  result.mothballedFleetsTotal = def.mothballedFleetsTotal

  # Combat Performance
  result.combatCERAverage = mil.combatCERAverage
  result.bombardmentRoundsTotal = mil.bombardmentRoundsTotal
  result.groundCombatVictories = mil.groundCombatVictories
  result.retreatsExecuted = mil.retreatsExecuted
  result.criticalHitsDealt = mil.criticalHitsDealt
  result.criticalHitsReceived = mil.criticalHitsReceived
  result.cloakedAmbushSuccess = mil.cloakedAmbushSuccess
  result.shieldsActivatedCount = mil.shieldsActivatedCount

  # Diplomatic Status
  result.activePactsCount = dip.activePactsCount
  result.pactViolationsTotal = dip.pactViolationsTotal
  result.dishonoredStatusActive = dip.dishonoredStatusActive
  result.diplomaticIsolationTurns = dip.diplomaticIsolationTurns
  result.enemyStatusCount = dip.enemyStatusCount
  result.neutralStatusCount = dip.neutralStatusCount

  # Espionage Activity (TODO: track from turn resolution)
  result.espionageSuccessCount = 0
  result.espionageFailureCount = 0
  result.espionageDetectedCount = 0
  result.techTheftsSuccessful = 0
  result.sabotageOperations = 0
  result.assassinationAttempts = 0
  result.cyberAttacksLaunched = 0
  result.ebpPointsSpent = 0
  result.cipPointsSpent = 0
  result.counterIntelSuccesses = 0

  # Population & Colony Management
  result.populationTransfersActive = econ.populationTransfersActive
  result.populationTransfersCompleted = econ.populationTransfersCompleted
  result.populationTransfersLost = econ.populationTransfersLost
  result.ptuTransferredTotal = econ.ptuTransferredTotal
  result.coloniesBlockadedCount = econ.coloniesBlockadedCount
  result.blockadeTurnsCumulative = econ.blockadeTurnsCumulative

  # Economic Health
  result.treasuryDeficit = econ.treasuryDeficit
  result.infrastructureDamageTotal = econ.infrastructureDamageTotal
  result.salvageValueRecovered = econ.salvageValueRecovered
  result.maintenanceCostDeficit = econ.maintenanceCostDeficit
  result.taxPenaltyActive = econ.taxPenaltyActive
  result.avgTaxRate6Turn = econ.avgTaxRate6Turn

  # Squadron Capacity & Violations
  result.fighterCapacityMax = econ.fighterCapacityMax
  result.fighterCapacityUsed = econ.fighterCapacityUsed
  result.fighterCapacityViolation = econ.fighterCapacityViolation
  result.squadronLimitMax = econ.squadronLimitMax
  result.squadronLimitUsed = econ.squadronLimitUsed
  result.squadronLimitViolation = econ.squadronLimitViolation
  result.starbasesRequired = econ.starbasesRequired
  result.starbasesActual = econ.starbasesActual

  # House Status
  result.autopilotActive = status.autopilotActive
  result.defensiveCollapseActive = status.defensiveCollapseActive
  result.turnsUntilElimination = status.turnsUntilElimination
  result.missedOrderTurns = status.missedOrderTurns

proc writeCSVHeader*(file: File) =
  ## Write CSV header row with ALL game metrics
  file.writeLine("turn,house," &
                 # Economy (Core)
                 "treasury,production,pu_growth,zero_spend_turns," &
                 "gco,nhv,tax_rate,total_iu,total_pu,total_ptu,pop_growth_rate," &
                 # Tech Levels (11 technologies)
                 "tech_cst,tech_wep,tech_el,tech_sl,tech_ter," &
                 "tech_eli,tech_clk,tech_sld,tech_cic,tech_fd,tech_aco," &
                 # Research & Prestige
                 "research_erp,research_srp,research_trp,research_breakthroughs," &
                 "research_wasted_erp,research_wasted_srp,turns_at_max_el,turns_at_max_sl," &
                 "maintenance_cost,maintenance_shortfall_turns," &
                 "prestige,prestige_change,prestige_victory_progress," &
                 # Combat Performance
                 "combat_cer_avg,bombard_rounds,ground_victories,retreats," &
                 "crit_hits_dealt,crit_hits_received,cloaked_ambush,shields_activated," &
                 # Diplomatic Status
                 "active_pacts,pact_violations,dishonored,diplo_isolation_turns," &
                 "enemy_count,neutral_count," &
                 # Espionage Activity
                 "espionage_success,espionage_failure,espionage_detected," &
                 "tech_thefts,sabotage_ops,assassinations,cyber_attacks," &
                 "ebp_spent,cip_spent,counter_intel_success," &
                 # Population & Colony Management
                 "pop_transfers_active,pop_transfers_done,pop_transfers_lost,ptu_transferred," &
                 "blockaded_colonies,blockade_turns_total," &
                 # Economic Health
                 "treasury_deficit,infra_damage,salvage_recovered,maintenance_deficit," &
                 "tax_penalty_active,avg_tax_6turn," &
                 # Squadron Capacity & Violations
                 "fighter_cap_max,fighter_cap_used,fighter_violation," &
                 "squadron_limit_max,squadron_limit_used,squadron_violation," &
                 "starbases_required,starbases_actual," &
                 # House Status
                 "autopilot,defensive_collapse,turns_to_elimination,missed_orders," &
                 # Military
                 "space_wins,space_losses,space_total,orbital_failures,orbital_total," &
                 "raider_success,raider_attempts," &
                 # Logistics
                 "capacity_violations,fighters_disbanded,total_fighters,idle_carriers,total_carriers,total_transports," &
                 # Ship Counts (19 ship classes)
                 "fighter_ships,corvette_ships,frigate_ships,scout_ships,raider_ships," &
                 "destroyer_ships,cruiser_ships,light_cruiser_ships,heavy_cruiser_ships," &
                 "battlecruiser_ships,battleship_ships,dreadnought_ships,super_dreadnought_ships," &
                 "carrier_ships,super_carrier_ships,starbase_ships,etac_ships,troop_transport_ships,planet_breaker_ships," &
                 # Ground Units (4 types)
                 "planetary_shield_units,ground_battery_units,army_units,marine_division_units," &
                 # Intel
                 "invasions_no_eli,total_invasions,clk_no_raiders,scout_count," &
                 "spy_planet,hack_starbase,total_espionage," &
                 # Defense
                 "undefended_colonies,total_colonies,mothball_used,mothball_total," &
                 # Orders
                 "invalid_orders,total_orders")

proc writeCSVRow*(file: File, metrics: DiagnosticMetrics) =
  ## Write metrics as CSV row with ALL fields
  file.writeLine(&"{metrics.turn},{metrics.houseId}," &
                 # Economy (Core)
                 &"{metrics.treasuryBalance},{metrics.productionPerTurn},{metrics.puGrowth},{metrics.zeroSpendTurns}," &
                 &"{metrics.grossColonyOutput},{metrics.netHouseValue},{metrics.taxRate}," &
                 &"{metrics.totalIndustrialUnits},{metrics.totalPopulationUnits},{metrics.totalPopulationPTU},{metrics.populationGrowthRate}," &
                 # Tech Levels (11 technologies)
                 &"{metrics.techCST},{metrics.techWEP},{metrics.techEL},{metrics.techSL},{metrics.techTER}," &
                 &"{metrics.techELI},{metrics.techCLK},{metrics.techSLD},{metrics.techCIC},{metrics.techFD},{metrics.techACO}," &
                 # Research & Prestige
                 &"{metrics.researchERP},{metrics.researchSRP},{metrics.researchTRP},{metrics.researchBreakthroughs}," &
                 &"{metrics.researchWastedERP},{metrics.researchWastedSRP},{metrics.turnsAtMaxEL},{metrics.turnsAtMaxSL}," &
                 &"{metrics.maintenanceCostTotal},{metrics.maintenanceShortfallTurns}," &
                 &"{metrics.prestigeCurrent},{metrics.prestigeChange},{metrics.prestigeVictoryProgress}," &
                 # Combat Performance
                 &"{metrics.combatCERAverage},{metrics.bombardmentRoundsTotal},{metrics.groundCombatVictories},{metrics.retreatsExecuted}," &
                 &"{metrics.criticalHitsDealt},{metrics.criticalHitsReceived},{metrics.cloakedAmbushSuccess},{metrics.shieldsActivatedCount}," &
                 # Diplomatic Status
                 &"{metrics.activePactsCount},{metrics.pactViolationsTotal},{metrics.dishonoredStatusActive},{metrics.diplomaticIsolationTurns}," &
                 &"{metrics.enemyStatusCount},{metrics.neutralStatusCount}," &
                 # Espionage Activity
                 &"{metrics.espionageSuccessCount},{metrics.espionageFailureCount},{metrics.espionageDetectedCount}," &
                 &"{metrics.techTheftsSuccessful},{metrics.sabotageOperations},{metrics.assassinationAttempts},{metrics.cyberAttacksLaunched}," &
                 &"{metrics.ebpPointsSpent},{metrics.cipPointsSpent},{metrics.counterIntelSuccesses}," &
                 # Population & Colony Management
                 &"{metrics.populationTransfersActive},{metrics.populationTransfersCompleted},{metrics.populationTransfersLost},{metrics.ptuTransferredTotal}," &
                 &"{metrics.coloniesBlockadedCount},{metrics.blockadeTurnsCumulative}," &
                 # Economic Health
                 &"{metrics.treasuryDeficit},{metrics.infrastructureDamageTotal},{metrics.salvageValueRecovered},{metrics.maintenanceCostDeficit}," &
                 &"{metrics.taxPenaltyActive},{metrics.avgTaxRate6Turn}," &
                 # Squadron Capacity & Violations
                 &"{metrics.fighterCapacityMax},{metrics.fighterCapacityUsed},{metrics.fighterCapacityViolation}," &
                 &"{metrics.squadronLimitMax},{metrics.squadronLimitUsed},{metrics.squadronLimitViolation}," &
                 &"{metrics.starbasesRequired},{metrics.starbasesActual}," &
                 # House Status
                 &"{metrics.autopilotActive},{metrics.defensiveCollapseActive},{metrics.turnsUntilElimination},{metrics.missedOrderTurns}," &
                 # Military
                 &"{metrics.spaceCombatWins},{metrics.spaceCombatLosses},{metrics.spaceCombatTotal}," &
                 &"{metrics.orbitalFailures},{metrics.orbitalTotal}," &
                 &"{metrics.raiderAmbushSuccess},{metrics.raiderAmbushAttempts}," &
                 # Logistics
                 &"{metrics.capacityViolationsActive},{metrics.fightersDisbanded}," &
                 &"{metrics.totalFighters},{metrics.idleCarriers},{metrics.totalCarriers},{metrics.totalTransports}," &
                 # Ship Counts (19 ship classes)
                 &"{metrics.fighterShips},{metrics.corvetteShips},{metrics.frigateShips},{metrics.scoutShips},{metrics.raiderShips}," &
                 &"{metrics.destroyerShips},{metrics.cruiserShips},{metrics.lightCruiserShips},{metrics.heavyCruiserShips}," &
                 &"{metrics.battlecruiserShips},{metrics.battleshipShips},{metrics.dreadnoughtShips},{metrics.superDreadnoughtShips}," &
                 &"{metrics.carrierShips},{metrics.superCarrierShips},{metrics.starbaseShips},{metrics.etacShips},{metrics.troopTransportShips},{metrics.planetBreakerShips}," &
                 # Ground Units (4 types)
                 &"{metrics.planetaryShieldUnits},{metrics.groundBatteryUnits},{metrics.armyUnits},{metrics.marineDivisionUnits}," &
                 # Intel
                 &"{metrics.invasionFleetsWithoutELIMesh},{metrics.totalInvasions}," &
                 &"{metrics.clkResearchedNoRaiders},{metrics.scoutCount}," &
                 &"{metrics.spyPlanetMissions},{metrics.hackStarbaseMissions},{metrics.totalEspionageMissions}," &
                 # Defense
                 &"{metrics.coloniesWithoutDefense},{metrics.totalColonies}," &
                 &"{metrics.mothballedFleetsUsed},{metrics.mothballedFleetsTotal}," &
                 # Orders
                 &"{metrics.invalidOrders},{metrics.totalOrders}")

proc writeDiagnosticsCSV*(filename: string, metrics: seq[DiagnosticMetrics]) =
  ## Write all diagnostics to CSV file
  var file = open(filename, fmWrite)
  defer: file.close()

  writeCSVHeader(file)
  for m in metrics:
    writeCSVRow(file, m)

  echo &"Diagnostics written to {filename}"
