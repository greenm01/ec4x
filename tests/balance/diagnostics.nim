## Diagnostic Metrics Collection System
##
## Tracks per-house, per-turn metrics to identify systematic AI failures
## Per Grok gap analysis: "Run diagnostics. Let the numbers tell you exactly what's missing."

import std/[tables, strformat, streams, options]
import ../../src/engine/[gamestate, fleet, squadron, orders]
import ../../src/common/types/[core, units]

type
  DiagnosticMetrics* = object
    ## Metrics collected per house, per turn
    turn*: int
    houseId*: HouseId

    # Economy
    treasuryBalance*: int
    productionPerTurn*: int
    puGrowth*: int              # Change in PU from last turn
    zeroSpendTurns*: int        # Cumulative turns with 0 treasury spending

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
    treasuryBalance: 0,
    productionPerTurn: 0,
    puGrowth: 0,
    zeroSpendTurns: 0,
    spaceCombatWins: 0,
    spaceCombatLosses: 0,
    spaceCombatTotal: 0,
    orbitalFailures: 0,
    orbitalTotal: 0,
    raiderAmbushSuccess: 0,
    raiderAmbushAttempts: 0,
    capacityViolationsActive: 0,
    fightersDisbanded: 0,
    totalFighters: 0,
    idleCarriers: 0,
    totalCarriers: 0,
    invasionFleetsWithoutELIMesh: 0,
    totalInvasions: 0,
    clkResearchedNoRaiders: false,
    scoutCount: 0,
    spyPlanetMissions: 0,
    hackStarbaseMissions: 0,
    totalEspionageMissions: 0,
    coloniesWithoutDefense: 0,
    totalColonies: 0,
    mothballedFleetsUsed: 0,
    mothballedFleetsTotal: 0,
    invalidOrders: 0,
    totalOrders: 0
  )

proc collectEconomyMetrics(state: GameState, houseId: HouseId,
                          prevMetrics: Option[DiagnosticMetrics]): DiagnosticMetrics =
  ## Collect economy-related metrics
  result = initDiagnosticMetrics(state.turn, houseId)

  let house = state.houses.getOrDefault(houseId)
  result.treasuryBalance = house.treasury

  # Calculate production from colonies
  var totalProduction = 0
  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      totalProduction += colony.production

  result.productionPerTurn = totalProduction

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

  # Phase 2c: Count scouts for ELI mesh tracking
  var scoutCount = 0
  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      for squadron in fleet.squadrons:
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

  # TODO: Track mothballed fleets
  result.mothballedFleetsUsed = 0
  result.mothballedFleetsTotal = 0

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

  # Merge all metrics
  result.treasuryBalance = econ.treasuryBalance
  result.productionPerTurn = econ.productionPerTurn
  result.puGrowth = econ.puGrowth
  result.zeroSpendTurns = econ.zeroSpendTurns

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

proc writeCSVHeader*(file: File) =
  ## Write CSV header row
  file.writeLine("turn,house,treasury,production,pu_growth,zero_spend_turns," &
                 "space_wins,space_losses,space_total,orbital_failures,orbital_total," &
                 "raider_success,raider_attempts," &
                 "capacity_violations,fighters_disbanded,total_fighters,idle_carriers,total_carriers," &
                 "invasions_no_eli,total_invasions,clk_no_raiders,scout_count," &
                 "spy_planet,hack_starbase,total_espionage," &
                 "undefended_colonies,total_colonies,mothball_used,mothball_total," &
                 "invalid_orders,total_orders")

proc writeCSVRow*(file: File, metrics: DiagnosticMetrics) =
  ## Write metrics as CSV row
  file.writeLine(&"{metrics.turn},{metrics.houseId},{metrics.treasuryBalance}," &
                 &"{metrics.productionPerTurn},{metrics.puGrowth},{metrics.zeroSpendTurns}," &
                 &"{metrics.spaceCombatWins},{metrics.spaceCombatLosses},{metrics.spaceCombatTotal}," &
                 &"{metrics.orbitalFailures},{metrics.orbitalTotal}," &
                 &"{metrics.raiderAmbushSuccess},{metrics.raiderAmbushAttempts}," &
                 &"{metrics.capacityViolationsActive},{metrics.fightersDisbanded}," &
                 &"{metrics.totalFighters},{metrics.idleCarriers},{metrics.totalCarriers}," &
                 &"{metrics.invasionFleetsWithoutELIMesh},{metrics.totalInvasions}," &
                 &"{metrics.clkResearchedNoRaiders},{metrics.scoutCount}," &
                 &"{metrics.spyPlanetMissions},{metrics.hackStarbaseMissions},{metrics.totalEspionageMissions}," &
                 &"{metrics.coloniesWithoutDefense},{metrics.totalColonies}," &
                 &"{metrics.mothballedFleetsUsed},{metrics.mothballedFleetsTotal}," &
                 &"{metrics.invalidOrders},{metrics.totalOrders}")

proc writeDiagnosticsCSV*(filename: string, metrics: seq[DiagnosticMetrics]) =
  ## Write all diagnostics to CSV file
  var file = open(filename, fmWrite)
  defer: file.close()

  writeCSVHeader(file)
  for m in metrics:
    writeCSVRow(file, m)

  echo &"Diagnostics written to {filename}"
