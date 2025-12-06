## Diagnostics Orchestrator
##
## Coordinates all 6 advisor collectors (Byzantine Imperial Government hierarchy),
## merges their metrics, calculates Act/rank, handles change deltas, and builds
## advisor reasoning logs.
##
## REFACTORED: 2025-12-06 - Extracted from diagnostics.nim (lines 950-1250)
## NEW: Advisor reasoning log support (Gap #9 fix)

import std/[options, algorithm, strformat, tables]
import ./types
import ./domestikos_collector  # Military commander
import ./logothete_collector   # Research & technology
import ./drungarius_collector  # Intelligence & espionage
import ./eparch_collector      # Economy & infrastructure
import ./protostrator_collector  # Diplomacy
import ./basileus_collector    # House status & victory
import ../../../engine/gamestate
import ../../../engine/orders
import ../../common/types

# Forward declaration for espionage mission counting
type
  EspionageMissionCounts = object
    spyPlanet: int
    hackStarbase: int
    spySystem: int

proc countEspionageMissions(packet: OrderPacket): EspionageMissionCounts =
  ## Count fleet-based espionage missions from order packet
  result = EspionageMissionCounts()

  for fleetOrder in packet.fleetOrders:
    case fleetOrder.orderType
    of FleetOrderType.SpyPlanet:
      result.spyPlanet += 1
    of FleetOrderType.HackStarbase:
      result.hackStarbase += 1
    of FleetOrderType.SpySystem:
      result.spySystem += 1
    else:
      discard

proc buildReasoningLog(state: GameState, houseId: HouseId,
                       orders: Option[OrderPacket]): string =
  ## Build structured advisor reasoning log (Gap #9 fix)
  ##
  ## Future: Advisors should emit reasoning directly
  ## Current: Extract basic info from OrderPacket
  result = ""

  if orders.isNone:
    return ""

  let packet = orders.get()

  # Extract build orders by type
  var shipOrders = 0
  var groundOrders = 0
  var facilityOrders = 0

  for order in packet.buildOrders:
    case order.buildType
    of BuildType.Ship:
      shipOrders += 1
    of BuildType.Building:
      # Distinguish facilities vs ground units by buildingType pattern
      if order.buildingType.isSome:
        let item = order.buildingType.get()
        if item in ["Spaceport", "Shipyard"]:
          facilityOrders += 1
        else:
          groundOrders += 1
    of BuildType.Infrastructure:
      discard  # IU investment, not tracked here

  # Build basic reasoning string
  if packet.buildOrders.len > 0:
    result &= &"DOMESTIKOS: {shipOrders} ships, {groundOrders} ground, {facilityOrders} facilities; "

  if packet.fleetOrders.len > 0:
    result &= &"FLEET: {packet.fleetOrders.len} orders; "

  # Future: Add Logothete (research), Eparch (infrastructure), etc.

  # Trim trailing separator
  if result.len > 0:
    result = result[0 ..< ^2]

proc collectDiagnostics*(state: GameState, houseId: HouseId,
                        strategy: AIStrategy,
                        prevMetrics: Option[DiagnosticMetrics] = none(DiagnosticMetrics),
                        orders: Option[OrderPacket] = none(OrderPacket),
                        gameId: string = "",
                        maxTurns: int = 100): DiagnosticMetrics =
  ## Collect all diagnostic metrics for a house at current turn
  ##
  ## maxTurns: expected game length for Act calculation (default 100)
  result = initDiagnosticMetrics(state.turn, houseId, strategy, gameId)

  # Use prevMetrics or empty metrics for first turn
  let prev = if prevMetrics.isSome: prevMetrics.get() else: result

  # ================================================================
  # PHASE A: Call all 6 advisor collectors (Byzantine hierarchy)
  # ================================================================

  let domestikos = collectDomestikosMetrics(state, houseId, prev)
  let logothete = collectLogotheteMetrics(state, houseId, prev)
  let drungarius = collectDrungariusMetrics(state, houseId)
  let eparch = collectEparchMetrics(state, houseId, prev)
  let protostrator = collectProtostratorMetrics(state, houseId)
  let basileus = collectBasileusMetrics(state, houseId, prev)

  # ================================================================
  # PHASE B: Merge all advisor metrics
  # ================================================================

  # Domestikos (Military commander) - Combat + Assets + Facilities
  result.spaceCombatWins = domestikos.spaceCombatWins
  result.spaceCombatLosses = domestikos.spaceCombatLosses
  result.spaceCombatTotal = domestikos.spaceCombatTotal
  result.orbitalFailures = domestikos.orbitalFailures
  result.orbitalTotal = domestikos.orbitalTotal
  result.raiderAmbushSuccess = domestikos.raiderAmbushSuccess
  result.raiderAmbushAttempts = domestikos.raiderAmbushAttempts
  result.combatCERAverage = domestikos.combatCERAverage
  result.bombardmentRoundsTotal = domestikos.bombardmentRoundsTotal
  result.groundCombatVictories = domestikos.groundCombatVictories
  result.retreatsExecuted = domestikos.retreatsExecuted
  result.criticalHitsDealt = domestikos.criticalHitsDealt
  result.criticalHitsReceived = domestikos.criticalHitsReceived
  result.cloakedAmbushSuccess = domestikos.cloakedAmbushSuccess
  result.shieldsActivatedCount = domestikos.shieldsActivatedCount
  result.capacityViolationsActive = domestikos.capacityViolationsActive
  result.fighterCapacityMax = domestikos.fighterCapacityMax
  result.fighterCapacityUsed = domestikos.fighterCapacityUsed
  result.fighterCapacityViolation = domestikos.fighterCapacityViolation
  result.squadronLimitMax = domestikos.squadronLimitMax
  result.squadronLimitUsed = domestikos.squadronLimitUsed
  result.squadronLimitViolation = domestikos.squadronLimitViolation
  result.starbasesActual = domestikos.starbasesActual
  result.fightersDisbanded = domestikos.fightersDisbanded
  result.totalFighters = domestikos.totalFighters
  result.idleCarriers = domestikos.idleCarriers
  result.totalCarriers = domestikos.totalCarriers
  result.totalTransports = domestikos.totalTransports

  # Ship counts (all 19 types)
  result.fighterShips = domestikos.fighterShips
  result.corvetteShips = domestikos.corvetteShips
  result.frigateShips = domestikos.frigateShips
  result.scoutShips = domestikos.scoutShips
  result.raiderShips = domestikos.raiderShips
  result.destroyerShips = domestikos.destroyerShips
  result.cruiserShips = domestikos.cruiserShips
  result.lightCruiserShips = domestikos.lightCruiserShips
  result.heavyCruiserShips = domestikos.heavyCruiserShips
  result.battlecruiserShips = domestikos.battlecruiserShips
  result.battleshipShips = domestikos.battleshipShips
  result.dreadnoughtShips = domestikos.dreadnoughtShips
  result.superDreadnoughtShips = domestikos.superDreadnoughtShips
  result.carrierShips = domestikos.carrierShips
  result.superCarrierShips = domestikos.superCarrierShips
  result.etacShips = domestikos.etacShips
  result.troopTransportShips = domestikos.troopTransportShips
  result.planetBreakerShips = domestikos.planetBreakerShips
  result.totalShips = domestikos.totalShips

  # Ground units (all 4 types)
  result.planetaryShieldUnits = domestikos.planetaryShieldUnits
  result.groundBatteryUnits = domestikos.groundBatteryUnits
  result.armyUnits = domestikos.armyUnits
  result.marineDivisionUnits = domestikos.marineDivisionUnits

  # Facilities (NEW - Gap #10 fix)
  result.totalSpaceports = domestikos.totalSpaceports
  result.totalShipyards = domestikos.totalShipyards

  # Scout mesh (intelligence support)
  result.scoutCount = domestikos.scoutCount

  # Fleet activity
  result.fleetsMoved = domestikos.fleetsMoved
  result.systemsColonized = domestikos.systemsColonized
  result.failedColonizationAttempts = domestikos.failedColonizationAttempts
  result.fleetsWithOrders = domestikos.fleetsWithOrders
  result.stuckFleets = domestikos.stuckFleets
  result.totalETACs = domestikos.totalETACs
  result.etacsWithoutOrders = domestikos.etacsWithoutOrders
  result.etacsInTransit = domestikos.etacsInTransit

  # Logothete (Research & technology)
  result.techCST = logothete.techCST
  result.techWEP = logothete.techWEP
  result.techEL = logothete.techEL
  result.techSL = logothete.techSL
  result.techTER = logothete.techTER
  result.techELI = logothete.techELI
  result.techCLK = logothete.techCLK
  result.techSLD = logothete.techSLD
  result.techCIC = logothete.techCIC
  result.techFD = logothete.techFD
  result.techACO = logothete.techACO
  result.researchERP = logothete.researchERP
  result.researchSRP = logothete.researchSRP
  result.researchTRP = logothete.researchTRP
  result.researchBreakthroughs = logothete.researchBreakthroughs
  result.researchWastedERP = logothete.researchWastedERP
  result.researchWastedSRP = logothete.researchWastedSRP
  result.turnsAtMaxEL = logothete.turnsAtMaxEL
  result.turnsAtMaxSL = logothete.turnsAtMaxSL

  # Drungarius (Intelligence & espionage)
  result.clkResearchedNoRaiders = drungarius.clkResearchedNoRaiders
  result.espionageSuccessCount = drungarius.espionageSuccessCount
  result.espionageFailureCount = drungarius.espionageFailureCount
  result.espionageDetectedCount = drungarius.espionageDetectedCount
  result.techTheftsSuccessful = drungarius.techTheftsSuccessful
  result.sabotageOperations = drungarius.sabotageOperations
  result.assassinationAttempts = drungarius.assassinationAttempts
  result.cyberAttacksLaunched = drungarius.cyberAttacksLaunched
  result.ebpPointsSpent = drungarius.ebpPointsSpent
  result.cipPointsSpent = drungarius.cipPointsSpent
  result.counterIntelSuccesses = drungarius.counterIntelSuccesses
  result.totalInvasions = drungarius.totalInvasions

  # Eparch (Economy & infrastructure)
  result.treasuryBalance = eparch.treasuryBalance
  result.productionPerTurn = eparch.productionPerTurn
  result.puGrowth = eparch.puGrowth
  result.zeroSpendTurns = eparch.zeroSpendTurns
  result.grossColonyOutput = eparch.grossColonyOutput
  result.netHouseValue = eparch.netHouseValue
  result.taxRate = eparch.taxRate
  result.totalIndustrialUnits = eparch.totalIndustrialUnits
  result.totalPopulationUnits = eparch.totalPopulationUnits
  result.totalPopulationPTU = eparch.totalPopulationPTU
  result.populationGrowthRate = eparch.populationGrowthRate
  result.treasuryDeficit = eparch.treasuryDeficit
  result.infrastructureDamageTotal = eparch.infrastructureDamageTotal
  result.salvageValueRecovered = eparch.salvageValueRecovered
  result.maintenanceCostDeficit = eparch.maintenanceCostDeficit
  result.taxPenaltyActive = eparch.taxPenaltyActive
  result.avgTaxRate6Turn = eparch.avgTaxRate6Turn
  result.populationTransfersActive = eparch.populationTransfersActive
  result.populationTransfersCompleted = eparch.populationTransfersCompleted
  result.populationTransfersLost = eparch.populationTransfersLost
  result.ptuTransferredTotal = eparch.ptuTransferredTotal
  result.coloniesBlockadedCount = eparch.coloniesBlockadedCount
  result.blockadeTurnsCumulative = eparch.blockadeTurnsCumulative
  result.coloniesWithoutDefense = eparch.coloniesWithoutDefense
  result.totalColonies = eparch.totalColonies
  result.mothballedFleetsUsed = eparch.mothballedFleetsUsed
  result.mothballedFleetsTotal = eparch.mothballedFleetsTotal
  result.totalBuildQueueDepth = eparch.totalBuildQueueDepth
  result.etacInConstruction = eparch.etacInConstruction
  result.shipsUnderConstruction = eparch.shipsUnderConstruction
  result.buildingsUnderConstruction = eparch.buildingsUnderConstruction
  result.shipsCommissionedThisTurn = eparch.shipsCommissionedThisTurn
  result.etacCommissionedThisTurn = eparch.etacCommissionedThisTurn
  result.squadronsCommissionedThisTurn = eparch.squadronsCommissionedThisTurn

  # Protostrator (Diplomacy)
  result.allyStatusCount = protostrator.allyStatusCount
  result.hostileStatusCount = protostrator.hostileStatusCount
  result.enemyStatusCount = protostrator.enemyStatusCount
  result.neutralStatusCount = protostrator.neutralStatusCount
  result.pactViolationsTotal = protostrator.pactViolationsTotal
  result.dishonoredStatusActive = protostrator.dishonoredStatusActive
  result.diplomaticIsolationTurns = protostrator.diplomaticIsolationTurns
  result.pactFormationsTotal = protostrator.pactFormationsTotal
  result.pactBreaksTotal = protostrator.pactBreaksTotal
  result.hostilityDeclarationsTotal = protostrator.hostilityDeclarationsTotal
  result.warDeclarationsTotal = protostrator.warDeclarationsTotal
  result.bilateralRelations = protostrator.bilateralRelations

  # Basileus (House status & victory)
  result.prestigeCurrent = basileus.prestigeCurrent
  result.prestigeChange = basileus.prestigeChange
  result.prestigeVictoryProgress = basileus.prestigeVictoryProgress
  result.maintenanceCostTotal = basileus.maintenanceCostTotal
  result.maintenanceShortfallTurns = basileus.maintenanceShortfallTurns
  result.autopilotActive = basileus.autopilotActive
  result.defensiveCollapseActive = basileus.defensiveCollapseActive
  result.turnsUntilElimination = basileus.turnsUntilElimination
  result.missedOrderTurns = basileus.missedOrderTurns

  # ================================================================
  # PHASE C: Track espionage missions from orders (if provided)
  # ================================================================

  if orders.isSome:
    let packet = orders.get()

    # Count fleet-based espionage orders
    let fleetEspCounts = countEspionageMissions(packet)
    result.spyPlanetMissions = fleetEspCounts.spyPlanet
    result.hackStarbaseMissions = fleetEspCounts.hackStarbase

    # Count EBP-based espionage actions (OrderPacket.espionageAction)
    var ebpEspionageMissions = 0
    if packet.espionageAction.isSome:
      ebpEspionageMissions = 1  # OrderPacket contains at most 1 espionage action

    # Total includes both fleet-based and EBP-based espionage
    result.totalEspionageMissions = fleetEspCounts.spyPlanet +
                                    fleetEspCounts.hackStarbase +
                                    fleetEspCounts.spySystem +
                                    ebpEspionageMissions

    # Track orders submitted this turn
    result.fleetOrdersSubmitted = packet.fleetOrders.len
    result.buildOrdersSubmitted = packet.buildOrders.len

    # Count colonization orders
    var colonizeCount = 0
    for fleetOrder in packet.fleetOrders:
      if fleetOrder.orderType == FleetOrderType.Colonize:
        colonizeCount += 1
    result.colonizeOrdersSubmitted = colonizeCount

    # Total orders
    result.totalOrders = packet.fleetOrders.len + packet.buildOrders.len

    # TODO: Track invalid orders (need turn resolution feedback)
    result.invalidOrders = 0
  else:
    result.spyPlanetMissions = 0
    result.hackStarbaseMissions = 0
    result.totalEspionageMissions = 0
    result.fleetOrdersSubmitted = 0
    result.buildOrdersSubmitted = 0
    result.colonizeOrdersSubmitted = 0
    result.totalOrders = 0
    result.invalidOrders = 0

  # ================================================================
  # PHASE D: Calculate Act number (1-4) based on turn thresholds
  # ================================================================

  # Dynamic calculation based on expected game length: 25% per act
  # Example: 100-turn game � Act1=1-25, Act2=26-50, Act3=51-75, Act4=76-100
  let actThreshold = max(1, maxTurns div 4)
  result.act = min(4, (state.turn - 1) div actThreshold + 1)

  # ================================================================
  # PHASE E: Calculate current rank by prestige (1=best, N=worst)
  # ================================================================

  var housePrestige: seq[tuple[house: HouseId, prestige: int]] = @[]
  for otherHouseId, house in state.houses:
    housePrestige.add((otherHouseId, house.prestige))
  housePrestige.sort(proc(a, b: auto): int = cmp(b.prestige, a.prestige))

  for i, hp in housePrestige:
    if hp.house == houseId:
      result.rank = i + 1
      break

  # ================================================================
  # PHASE F: Calculate change deltas from previous turn
  # ================================================================

  if prevMetrics.isSome:
    # Colony changes
    let prevColonies = prev.totalColonies
    let currColonies = result.totalColonies
    if currColonies > prevColonies:
      result.coloniesGained = currColonies - prevColonies
      result.coloniesLost = 0
    elif currColonies < prevColonies:
      result.coloniesLost = prevColonies - currColonies
      result.coloniesGained = 0
    else:
      result.coloniesGained = 0
      result.coloniesLost = 0

    # Ship changes
    let prevShips = prev.totalShips
    let currShips = result.totalShips
    if currShips > prevShips:
      result.shipsGained = currShips - prevShips
      result.shipsLost = 0
    elif currShips < prevShips:
      result.shipsLost = prevShips - currShips
      result.shipsGained = 0
    else:
      result.shipsGained = 0
      result.shipsLost = 0

    # Fighter changes
    let prevFighters = prev.totalFighters
    let currFighters = result.totalFighters
    if currFighters > prevFighters:
      result.fightersGained = currFighters - prevFighters
      result.fightersLost = 0
    elif currFighters < prevFighters:
      result.fightersLost = prevFighters - currFighters
      result.fightersGained = 0
    else:
      result.fightersGained = 0
      result.fightersLost = 0

  # ================================================================
  # PHASE G: Build advisor reasoning log (Gap #9 fix)
  # ================================================================

  result.advisorReasoning = buildReasoningLog(state, houseId, orders)
