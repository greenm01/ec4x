## Turn resolution engine - the heart of EC4X gameplay
##
## OFFLINE GAMEPLAY SYSTEM - No network dependencies
## This module is designed to work standalone for local/hotseat multiplayer
## Network transport (Nostr) wraps around this engine without modifying it

import std/[tables, algorithm, options, random, strformat, sequtils, strutils, hashes, math]
import ../common/[hex, types/core, types/combat, types/tech, types/units]
import gamestate, orders, fleet, ship, starmap, squadron, spacelift
import economy/[types as econ_types, engine as econ_engine, construction, maintenance]
import research/[types as res_types, advancement, costs as res_costs, effects as res_effects]
import espionage/[types as esp_types, engine as esp_engine]
import diplomacy/[types as dip_types, engine as dip_engine, proposals as dip_proposals]
import colonization/engine as col_engine
import combat/[engine as combat_engine, types as combat_types, ground]
import population/[types as pop_types]
import config/[prestige_config, espionage_config, gameplay_config, construction_config, military_config, ground_units_config, population_config]
import commands/executor
import blockade/engine as blockade_engine
import intelligence/[detection, types as intel_types, generator as intel_gen]
import prestige

# Population config loaded from config/population.toml via population_config module
# Access via soulsPerPtu()
# No more hardcoded constants

type
  TurnResult* = object
    newState*: GameState
    events*: seq[GameEvent]
    combatReports*: seq[CombatReport]

  GameEvent* = object
    eventType*: GameEventType
    houseId*: HouseId
    description*: string
    systemId*: Option[SystemId]

  GameEventType* {.pure.} = enum
    # Colony events
    ColonyEstablished, SystemCaptured, ColonyCaptured, TerraformComplete
    # Combat events
    Battle, BattleOccurred, Bombardment, FleetDestroyed, InvasionRepelled
    # Construction events
    ConstructionStarted, ShipCommissioned, BuildingCompleted, UnitRecruited, UnitDisbanded
    # Diplomatic/Strategic events
    TechAdvance, HouseEliminated, PopulationTransfer

  CombatReport* = object
    systemId*: SystemId
    attackers*: seq[HouseId]
    defenders*: seq[HouseId]
    attackerLosses*: int
    defenderLosses*: int
    victor*: Option[HouseId]

# Forward declarations for phase functions
proc resolveIncomePhase(state: var GameState, orders: Table[HouseId, OrderPacket])
proc resolveCommandPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                        events: var seq[GameEvent])
proc resolveConflictPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                         combatReports: var seq[CombatReport], events: var seq[GameEvent])
proc resolveMaintenancePhase(state: var GameState, events: var seq[GameEvent])

# Forward declarations for helper functions
proc resolveBuildOrders(state: var GameState, packet: OrderPacket, events: var seq[GameEvent])
proc resolveSquadronManagement(state: var GameState, packet: OrderPacket, events: var seq[GameEvent])
proc resolveCargoManagement(state: var GameState, packet: OrderPacket, events: var seq[GameEvent])
proc resolveTerraformOrders(state: var GameState, packet: OrderPacket, events: var seq[GameEvent])
proc autoLoadCargo(state: var GameState, orders: Table[HouseId, OrderPacket], events: var seq[GameEvent])
proc resolvePopulationTransfers(state: var GameState, packet: OrderPacket, events: var seq[GameEvent])
proc resolvePopulationArrivals(state: var GameState, events: var seq[GameEvent])
proc resolveMovementOrder*(state: var GameState, houseId: HouseId, order: FleetOrder,
                         events: var seq[GameEvent])
proc resolveColonizationOrder(state: var GameState, houseId: HouseId, order: FleetOrder,
                              events: var seq[GameEvent])
proc resolveBattle(state: var GameState, systemId: SystemId,
                  orders: Table[HouseId, OrderPacket],
                  combatReports: var seq[CombatReport], events: var seq[GameEvent])
proc resolveBombardment(state: var GameState, houseId: HouseId, order: FleetOrder,
                       events: var seq[GameEvent])

## Main Turn Resolution

proc resolveTurn*(state: GameState, orders: Table[HouseId, OrderPacket]): TurnResult =
  ## Resolve a complete game turn
  ## Returns new game state and events that occurred

  result.newState = state  # Start with current state
  result.events = @[]
  result.combatReports = @[]

  # Initialize RNG for this turn (use turn number as seed for reproducibility)
  var rng = initRand(state.turn)

  echo "Resolving turn ", state.turn, " (Year ", state.year, ", Month ", state.month, ")"

  # Phase 1: Conflict Phase
  # - Resolve space battles
  # - Process bombardments
  # - Resolve invasions
  # - Damage infrastructure (shipyards, starbases, planetary improvements)
  # NOTE: Conflict happens FIRST so damaged infrastructure affects production
  resolveConflictPhase(result.newState, orders, result.combatReports, result.events)

  # Phase 2: Income Phase
  # - Collect taxes from colonies (reduced if infrastructure damaged)
  # - Calculate production (accounts for bombed facilities)
  # - Allocate research points
  resolveIncomePhase(result.newState, orders)

  # Phase 3: Command Phase
  # - Process build orders (may fail if shipyards destroyed)
  # - Execute movement orders
  # - Process colonization
  resolveCommandPhase(result.newState, orders, result.events)

  # Phase 4: Maintenance Phase
  # - Pay fleet upkeep
  # - Advance construction projects
  # - Apply repairs to damaged facilities
  # - Check victory conditions
  resolveMaintenancePhase(result.newState, result.events)

  # Advance turn counter
  result.newState.advanceTurn()

  echo "Turn ", state.turn, " resolved. New turn: ", result.newState.turn

## Phase 1: Conflict

proc resolveConflictPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                         combatReports: var seq[CombatReport], events: var seq[GameEvent]) =
  ## Phase 1: Resolve all combat and infrastructure damage
  ## This happens FIRST so damaged facilities affect production
  echo "  [Conflict Phase]"

  # Find all systems with hostile fleets
  var combatSystems: seq[SystemId] = @[]

  for systemId, system in state.starMap.systems:
    # Check if multiple houses have fleets here
    var housesPresent: seq[HouseId] = @[]
    for fleet in state.fleets.values:
      if fleet.location == systemId and fleet.owner notin housesPresent:
        housesPresent.add(fleet.owner)

    if housesPresent.len > 1:
      # Check if any pairs of houses are at war (Enemy status)
      var combatDetected = false
      for i in 0..<housesPresent.len:
        for j in (i+1)..<housesPresent.len:
          let house1 = housesPresent[i]
          let house2 = housesPresent[j]

          # Check diplomatic state between these two houses
          let relation = dip_types.getDiplomaticState(
            state.houses[house1].diplomaticRelations,
            house2
          )

          # Combat occurs if houses are enemies OR neutral (no pact protection)
          # NonAggression pacts prevent combat
          if relation == dip_types.DiplomaticState.Enemy or
             relation == dip_types.DiplomaticState.Neutral:
            combatDetected = true
            break
        if combatDetected:
          break

      if combatDetected:
        combatSystems.add(systemId)

  # Resolve combat in each system (operations.md:7.0)
  # Combat progresses linearly:
  # 1. Space Combat - mobile fleets not on guard duty
  # 2. Orbital Combat - guard fleets, reserve fleets, starbases
  # 3. Planetary Combat - bombardment/invasion (via orders below)
  for systemId in combatSystems:
    resolveBattle(state, systemId, orders, combatReports, events)

  # Process espionage actions (per gameplay.md:1.3.1 - resolved in Conflict Phase)
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]

      # Process espionage action if present (max 1 per turn per diplomacy.md:8.2)
      if packet.espionageAction.isSome:
        let attempt = packet.espionageAction.get()

        # Get target's CIC level from tech tree
        # CRITICAL: Tech starts at level 1 (CIC1), not 0! (gameplay.md:1.2)
        let targetCICLevel = case state.houses[attempt.target].techTree.levels.counterIntelligence
          of 1: esp_types.CICLevel.CIC1
          of 2: esp_types.CICLevel.CIC2
          of 3: esp_types.CICLevel.CIC3
          of 4: esp_types.CICLevel.CIC4
          of 5: esp_types.CICLevel.CIC5
          else: esp_types.CICLevel.CIC1  # Fallback to base level
        let targetCIP = if attempt.target in state.houses:
                          state.houses[attempt.target].espionageBudget.cipPoints
                        else:
                          0

        # Execute espionage action with detection roll
        # Use XOR instead of + to avoid overflow when combining hashes
        var rng = initRand(int64(state.turn) xor attempt.attacker.hash() xor attempt.target.hash())
        let result = esp_engine.executeEspionage(
          attempt,
          targetCICLevel,
          targetCIP,
          rng
        )

        # Apply results
        if result.success:
          echo "    ", attempt.attacker, " espionage: ", result.description

          # Apply prestige changes
          for prestigeEvent in result.attackerPrestigeEvents:
            state.houses[attempt.attacker].prestige += prestigeEvent.amount
          for prestigeEvent in result.targetPrestigeEvents:
            state.houses[attempt.target].prestige += prestigeEvent.amount

          # Apply ongoing effects
          if result.effect.isSome:
            state.ongoingEffects.add(result.effect.get())

          # Apply immediate effects (SRP theft, IU damage, etc.)
          if result.srpStolen > 0:
            # Steal SRP from target
            if attempt.target in state.houses:
              state.houses[attempt.target].techTree.accumulated.science =
                max(0, state.houses[attempt.target].techTree.accumulated.science - result.srpStolen)
              state.houses[attempt.attacker].techTree.accumulated.science += result.srpStolen
              echo "      Stole ", result.srpStolen, " SRP from ", attempt.target

        else:
          echo "    ", attempt.attacker, " espionage DETECTED by ", attempt.target
          # Apply detection prestige penalties
          for prestigeEvent in result.attackerPrestigeEvents:
            state.houses[attempt.attacker].prestige += prestigeEvent.amount

  # Process planetary combat orders (operations.md:7.5, 7.6)
  # These execute after space/orbital combat in linear progression
  for houseId in state.houses.keys:
    if houseId in orders:
      for order in orders[houseId].fleetOrders:
        case order.orderType
        of FleetOrderType.Bombard:
          resolveBombardment(state, houseId, order, events)
        of FleetOrderType.Invade:
          # TODO: Implement resolveInvasion
          discard # resolveInvasion(state, houseId, order, events)
        of FleetOrderType.Blitz:
          # TODO: Implement resolveBlitz
          discard # resolveBlitz(state, houseId, order, events)
        else:
          discard

## Helper: Auto-balance unassigned squadrons to fleets at colony

proc autoBalanceSquadronsToFleets(state: var GameState, colony: var gamestate.Colony, systemId: SystemId, orders: Table[HouseId, OrderPacket]) =
  ## Auto-assign unassigned squadrons to fleets at colony, balancing squadron count
  ## Only assigns to stationary fleets (those with Hold orders or no orders)
  if colony.unassignedSquadrons.len == 0:
    return

  # Find all stationary fleets at this system owned by colony owner
  var stationaryFleets: seq[FleetId] = @[]
  for fleetId, fleet in state.fleets:
    if fleet.location == systemId and fleet.owner == colony.owner:
      # Check if fleet has movement orders
      var hasMovementOrder = false
      if colony.owner in orders:
        for order in orders[colony.owner].fleetOrders:
          if order.fleetId == fleetId and order.orderType == FleetOrderType.Move:
            hasMovementOrder = true
            break
      if not hasMovementOrder:
        stationaryFleets.add(fleetId)

  # If no fleets exist at colony, create one
  if stationaryFleets.len == 0:
    let newFleetId = colony.owner & "_fleet_" & $systemId & "_" & $state.turn
    state.fleets[newFleetId] = Fleet(
      id: newFleetId,
      owner: colony.owner,
      location: systemId,
      squadrons: @[]
    )
    stationaryFleets.add(newFleetId)
    echo "      Created new fleet ", newFleetId, " for auto-assignment"

  # Distribute unassigned squadrons to balance fleet strength
  # Assign each squadron to the weakest fleet (by total attack strength)
  while colony.unassignedSquadrons.len > 0:
    let squadron = colony.unassignedSquadrons[0]
    colony.unassignedSquadrons.delete(0)

    # Find fleet with lowest total attack strength
    var weakestFleetId = stationaryFleets[0]
    var lowestStrength = 0
    for fleetId in stationaryFleets:
      var fleetStrength = 0
      for sq in state.fleets[fleetId].squadrons:
        fleetStrength += sq.flagship.stats.attackStrength
        for ship in sq.ships:
          fleetStrength += ship.stats.attackStrength

      if fleetId == stationaryFleets[0] or fleetStrength < lowestStrength:
        lowestStrength = fleetStrength
        weakestFleetId = fleetId

    state.fleets[weakestFleetId].squadrons.add(squadron)
    echo "      Auto-assigned squadron ", squadron.id, " to fleet ", weakestFleetId, " (strength balancing)"

## Phase 2: Income

proc resolveIncomePhase(state: var GameState, orders: Table[HouseId, OrderPacket]) =
  ## Phase 2: Collect income and allocate resources
  ## Production is calculated AFTER conflict, so damaged infrastructure produces less
  ## Also applies ongoing espionage effects (SRP/NCV/Tax reductions)
  echo "  [Income Phase]"

  # Apply blockade status to all colonies
  # Per operations.md:6.2.6: "Blockades established during the Conflict Phase
  # reduce GCO for that same turn's Income Phase calculation - there is no delay"
  blockade_engine.applyBlockades(state)

  # Apply ongoing espionage effects to houses
  var activeEffects: seq[esp_types.OngoingEffect] = @[]
  for effect in state.ongoingEffects:
    if effect.turnsRemaining > 0:
      activeEffects.add(effect)

      case effect.effectType
      of esp_types.EffectType.SRPReduction:
        echo "    ", effect.targetHouse, " affected by SRP reduction (-",
             int(effect.magnitude * 100), "%)"
      of esp_types.EffectType.NCVReduction:
        echo "    ", effect.targetHouse, " affected by NCV reduction (-",
             int(effect.magnitude * 100), "%)"
      of esp_types.EffectType.TaxReduction:
        echo "    ", effect.targetHouse, " affected by tax reduction (-",
             int(effect.magnitude * 100), "%)"
      of esp_types.EffectType.StarbaseCrippled:
        if effect.targetSystem.isSome:
          let systemId = effect.targetSystem.get()
          echo "    Starbase at system ", systemId, " is crippled"

          # Apply crippled state to starbase in colony
          if systemId in state.colonies:
            var colony = state.colonies[systemId]
            if colony.owner == effect.targetHouse:
              for starbase in colony.starbases.mitems:
                if not starbase.isCrippled:
                  starbase.isCrippled = true
                  echo "      Applied crippled state to starbase ", starbase.id
              state.colonies[systemId] = colony

  state.ongoingEffects = activeEffects

  # Process EBP/CIP purchases (diplomacy.md:8.2)
  # EBP and CIP cost 40 PP each
  # Over-investment penalty: lose 1 prestige per 1% over 5% of turn budget
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]

      if packet.ebpInvestment > 0 or packet.cipInvestment > 0:
        let ebpCost = packet.ebpInvestment * globalEspionageConfig.costs.ebp_cost_pp
        let cipCost = packet.cipInvestment * globalEspionageConfig.costs.cip_cost_pp
        let totalCost = ebpCost + cipCost

        # Deduct from treasury
        if state.houses[houseId].treasury >= totalCost:
          state.houses[houseId].treasury -= totalCost
          state.houses[houseId].espionageBudget.ebpPoints += packet.ebpInvestment
          state.houses[houseId].espionageBudget.cipPoints += packet.cipInvestment
          state.houses[houseId].espionageBudget.ebpInvested = ebpCost
          state.houses[houseId].espionageBudget.cipInvested = cipCost

          echo "    ", houseId, " purchased ", packet.ebpInvestment, " EBP, ",
               packet.cipInvestment, " CIP (", totalCost, " PP)"

          # Check for over-investment penalty (configurable threshold from espionage.toml)
          let turnBudget = state.houses[houseId].espionageBudget.turnBudget
          if turnBudget > 0:
            let totalInvestment = ebpCost + cipCost
            let investmentPercent = (totalInvestment * 100) div turnBudget
            let threshold = globalEspionageConfig.investment.threshold_percentage

            if investmentPercent > threshold:
              let prestigePenalty = -(investmentPercent - threshold) * globalEspionageConfig.investment.penalty_per_percent
              state.houses[houseId].prestige += prestigePenalty
              echo "      Over-investment penalty: ", prestigePenalty, " prestige"
        else:
          echo "    ", houseId, " insufficient funds for EBP/CIP purchase"

  # Process spy scout detection and intelligence gathering
  # Per assets.md:2.4.2: "For every turn that a spy Scout operates in unfriendly
  # system occupied by rival ELI, the rival will roll on the Spy Detection Table"
  var survivingScouts = initTable[string, SpyScout]()

  for scoutId, scout in state.spyScouts:
    if scout.detected:
      # Scout was detected in a previous turn
      continue

    var wasDetected = false
    let scoutLocation = scout.location

    # Check if system has rival ELI units (fleets with scouts or starbases)
    # Get all houses in the system (from fleets and colonies)
    var housesInSystem: seq[HouseId] = @[]

    # Check for colonies (starbases provide detection)
    if scoutLocation in state.colonies:
      let colony = state.colonies[scoutLocation]
      if colony.owner != scout.owner:
        housesInSystem.add(colony.owner)

    # Check for fleets with scouts
    for fleetId, fleet in state.fleets:
      if fleet.location == scoutLocation and fleet.owner != scout.owner:
        # Check if fleet has scouts
        for squadron in fleet.squadrons:
          if squadron.flagship.shipClass == ShipClass.Scout:
            if not housesInSystem.contains(fleet.owner):
              housesInSystem.add(fleet.owner)
            break

    # For each rival house in system, roll detection
    for rivalHouse in housesInSystem:
      # Build ELI unit from fleets
      var detectorELI: seq[int] = @[]
      var hasStarbase = false

      # Check for colony with starbase
      if scoutLocation in state.colonies:
        let colony = state.colonies[scoutLocation]
        if colony.owner == rivalHouse:
          # Check for operational starbase presence (not crippled)
          for starbase in colony.starbases:
            if not starbase.isCrippled:
              hasStarbase = true
              break

      # Collect ELI from fleets
      for fleetId, fleet in state.fleets:
        if fleet.location == scoutLocation and fleet.owner == rivalHouse:
          for squadron in fleet.squadrons:
            if squadron.flagship.shipClass == ShipClass.Scout:
              detectorELI.add(squadron.flagship.stats.techLevel)

      # Attempt detection if there are ELI units
      if detectorELI.len > 0:
        let detectorUnit = ELIUnit(
          eliLevels: detectorELI,
          isStarbase: hasStarbase
        )

        # Roll detection with turn RNG
        var rng = initRand(state.turn + scoutId.hash())
        let detectionResult = detectSpyScout(detectorUnit, scout.eliLevel, rng)

        if detectionResult.detected:
          echo "    Spy scout ", scoutId, " detected by ", rivalHouse,
               " (ELI ", detectionResult.effectiveELI, " vs ", scout.eliLevel,
               ", rolled ", detectionResult.roll, " > ", detectionResult.threshold, ")"
          wasDetected = true
          break

    if wasDetected:
      # Scout is destroyed, don't add to surviving scouts
      echo "    Spy scout ", scoutId, " destroyed"
    else:
      # Scout survives and gathers intelligence
      survivingScouts[scoutId] = scout

      # Generate intelligence reports based on mission type
      case scout.mission
      of SpyMissionType.SpyOnPlanet:
        echo "    Spy scout ", scoutId, " gathering planetary intelligence at system ", scoutLocation
        let report = intel_gen.generateColonyIntelReport(state, scout.owner, scoutLocation, intel_types.IntelQuality.Spy)
        if report.isSome:
          state.houses[scout.owner].intelligence.addColonyReport(report.get())
          echo "      Intel: Colony has ", report.get().population, " pop, ", report.get().industry, " IU, ", report.get().defenses, " ground units"

      of SpyMissionType.HackStarbase:
        echo "    Spy scout ", scoutId, " hacking starbase at system ", scoutLocation
        let report = intel_gen.generateStarbaseIntelReport(state, scout.owner, scoutLocation, intel_types.IntelQuality.Spy)
        if report.isSome:
          state.houses[scout.owner].intelligence.addStarbaseReport(report.get())
          echo "      Intel: Treasury ", report.get().treasuryBalance.get(0), " PP, Tax rate ", report.get().taxRate.get(0.0), "%"

      of SpyMissionType.SpyOnSystem:
        echo "    Spy scout ", scoutId, " conducting system surveillance at ", scoutLocation
        let report = intel_gen.generateSystemIntelReport(state, scout.owner, scoutLocation, intel_types.IntelQuality.Spy)
        if report.isSome:
          state.houses[scout.owner].intelligence.addSystemReport(report.get())
          echo "      Intel: Detected ", report.get().detectedFleets.len, " enemy fleets"

  # Update spy scouts in game state (remove detected ones)
  state.spyScouts = survivingScouts

  # Convert GameState colonies to economy engine format
  var econColonies: seq[econ_types.Colony] = @[]
  for systemId, colony in state.colonies:
    # Get owner's current tax rate
    let ownerHouse = state.houses[colony.owner]
    let currentTaxRate = ownerHouse.taxPolicy.currentRate

    # Convert Colony to economy Colony type
    # grossOutput starts at 0 and will be calculated by economy engine

    # Calculate PTU from exact souls count (1 PTU = 50k souls)
    let ptuCount = colony.souls div soulsPerPtu()

    econColonies.add(econ_types.Colony(
      systemId: colony.systemId,
      owner: colony.owner,
      populationUnits: colony.population,  # Map population (millions) to PU
      populationTransferUnits: ptuCount,  # Calculate from exact souls count
      industrial: econ_types.IndustrialUnits(units: colony.infrastructure * 10),  # Map infrastructure to IU
      planetClass: colony.planetClass,
      resources: colony.resources,
      grossOutput: 0,  # Will be calculated by economy engine
      taxRate: currentTaxRate,  # Get from house tax policy
      underConstruction: colony.underConstruction,  # Pass through construction state
      infrastructureDamage: if colony.blockaded: 0.6 else: 0.0  # Blockade = 60% infrastructure damage
    ))

  # Build house tax policies from House state
  var houseTaxPolicies = initTable[HouseId, econ_types.TaxPolicy]()
  for houseId, house in state.houses:
    houseTaxPolicies[houseId] = house.taxPolicy

  # Build house tech levels (Economic Level = economicLevel field)
  var houseTechLevels = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseTechLevels[houseId] = house.techTree.levels.economicLevel  # EL = economicLevel (confusing naming)

  # Build house treasuries
  var houseTreasuries = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseTreasuries[houseId] = house.treasury

  # Call economy engine
  let incomeReport = econ_engine.resolveIncomePhase(
    econColonies,
    houseTaxPolicies,
    houseTechLevels,
    houseTreasuries
  )

  # Apply results back to game state
  for houseId, houseReport in incomeReport.houseReports:
    state.houses[houseId].treasury = houseTreasuries[houseId]
    echo "    ", state.houses[houseId].name, ": +", houseReport.totalNet, " PP (Gross: ", houseReport.totalGross, ")"

    # Update colony production fields from income reports
    for colonyReport in houseReport.colonies:
      if colonyReport.colonyId in state.colonies:
        state.colonies[colonyReport.colonyId].production = colonyReport.grossOutput

    # Apply prestige events from economic activities
    for event in houseReport.prestigeEvents:
      state.houses[houseId].prestige += event.amount
      echo "      Prestige: ",
           (if event.amount > 0: "+" else: ""), event.amount,
           " (", event.description, ") -> ", state.houses[houseId].prestige

    # Apply blockade prestige penalties
    # Per operations.md:6.2.6: "-2 prestige per colony under blockade"
    let blockadePenalty = blockade_engine.calculateBlockadePrestigePenalty(state, houseId)
    if blockadePenalty < 0:
      let blockadedCount = blockade_engine.getBlockadedColonies(state, houseId).len
      state.houses[houseId].prestige += blockadePenalty
      echo "      Prestige: ", blockadePenalty, " (", blockadedCount,
           " colonies under blockade) -> ", state.houses[houseId].prestige

  # Process construction completion - decrement turns and complete projects
  for systemId, colony in state.colonies.mpairs:
    if colony.underConstruction.isSome:
      var project = colony.underConstruction.get()
      project.turnsRemaining -= 1

      if project.turnsRemaining <= 0:
        # Construction complete!
        echo "    Construction completed at system ", systemId, ": ", project.itemId

        case project.projectType
        of econ_types.ConstructionType.Ship:
          # Commission ship from Spaceport/Shipyard
          let shipClass = parseEnum[ShipClass](project.itemId)
          let techLevel = state.houses[colony.owner].techTree.levels.constructionTech

          # ARCHITECTURE FIX: Check if this is a spacelift ship (NOT a combat squadron)
          let isSpaceLift = shipClass in [ShipClass.ETAC, ShipClass.TroopTransport]

          if isSpaceLift:
            # Create SpaceLiftShip (individual unit, not squadron)
            let shipId = colony.owner & "_" & $shipClass & "_" & $systemId & "_" & $state.turn
            let spaceLiftShip = newSpaceLiftShip(shipId, shipClass, colony.owner, systemId)
            colony.unassignedSpaceLiftShips.add(spaceLiftShip)
            echo "      Commissioned ", shipClass, " spacelift ship at ", systemId

            # Auto-assign to fleets if enabled
            if colony.autoAssignFleets and colony.unassignedSpaceLiftShips.len > 0:
              # Find stationary fleets at this system
              for fleetId, fleet in state.fleets.mpairs:
                if fleet.location == systemId and fleet.owner == colony.owner:
                  # Transfer spacelift ship to fleet
                  fleet.spaceLiftShips.add(spaceLiftShip)
                  colony.unassignedSpaceLiftShips.setLen(colony.unassignedSpaceLiftShips.len - 1)
                  echo "      Auto-assigned ", shipClass, " to fleet ", fleetId
                  break

          else:
            # Combat ship - create squadron as normal
            let newShip = newEnhancedShip(shipClass, techLevel)

            # Intelligent tactical squadron assignment
            # Try to add escorts to existing unassigned squadrons first (battle-ready groups)
            # Capital ships always create new squadrons (they're flagships)
            var addedToSquadron = false

            let isCapitalShip = shipClass in [
              ShipClass.Battleship, ShipClass.Dreadnought, ShipClass.SuperDreadnought,
              ShipClass.Carrier, ShipClass.SuperCarrier, ShipClass.Battlecruiser,
              ShipClass.HeavyCruiser, ShipClass.Cruiser
            ]

            let isEscort = shipClass in [
              ShipClass.Scout, ShipClass.Frigate, ShipClass.Destroyer,
              ShipClass.Corvette, ShipClass.LightCruiser
            ]

            # Escorts try to join existing unassigned squadrons for balanced combat groups
            if isEscort:
              # Try to join unassigned capital ship squadrons first
              for squadron in colony.unassignedSquadrons.mitems:
                let flagshipIsCapital = squadron.flagship.shipClass in [
                  ShipClass.Battleship, ShipClass.Dreadnought, ShipClass.SuperDreadnought,
                  ShipClass.Carrier, ShipClass.SuperCarrier, ShipClass.Battlecruiser,
                  ShipClass.HeavyCruiser, ShipClass.Cruiser
                ]
                if flagshipIsCapital and squadron.canAddShip(newShip):
                  squadron.ships.add(newShip)
                  echo "      Commissioned ", shipClass, " and added to unassigned capital squadron ", squadron.id
                  addedToSquadron = true
                  break

              # If no capital squadrons, try joining escort squadrons
              if not addedToSquadron:
                for squadron in colony.unassignedSquadrons.mitems:
                  if squadron.flagship.shipClass == shipClass and squadron.canAddShip(newShip):
                    squadron.ships.add(newShip)
                    echo "      Commissioned ", shipClass, " and added to unassigned escort squadron ", squadron.id
                    addedToSquadron = true
                    break

            # Capital ships and unassigned escorts create new squadrons at colony
            if not addedToSquadron:
              let squadronId = colony.owner & "_sq_" & $systemId & "_" & $state.turn & "_" & project.itemId
              let newSquadron = newSquadron(newShip, squadronId, colony.owner, systemId)
              colony.unassignedSquadrons.add(newSquadron)
              echo "      Commissioned ", shipClass, " into new unassigned squadron at ", systemId

            # If colony has auto-assign enabled, balance unassigned squadrons to fleets
            if colony.autoAssignFleets and colony.unassignedSquadrons.len > 0:
              autoBalanceSquadronsToFleets(state, colony, systemId, orders)

        of econ_types.ConstructionType.Building:
          # Add building to colony
          if project.itemId == "Spaceport":
            let spaceportId = colony.owner & "_spaceport_" & $systemId & "_" & $state.turn
            let spaceport = Spaceport(
              id: spaceportId,
              commissionedTurn: state.turn,
              docks: 5  # 5 construction docks per spaceport
            )
            colony.spaceports.add(spaceport)
            echo "      Added Spaceport to system ", systemId

          elif project.itemId == "Shipyard":
            let shipyardId = colony.owner & "_shipyard_" & $systemId & "_" & $state.turn
            let shipyard = Shipyard(
              id: shipyardId,
              commissionedTurn: state.turn,
              docks: 10  # 10 construction docks per shipyard
            )
            colony.shipyards.add(shipyard)
            echo "      Added Shipyard to system ", systemId

          elif project.itemId == "GroundBattery":
            colony.groundBatteries += 1
            echo "      Added Ground Battery to system ", systemId

          elif project.itemId == "PlanetaryShield":
            # Set planetary shield level based on house's SLD tech
            colony.planetaryShieldLevel = state.houses[colony.owner].techTree.levels.shieldTech
            echo "      Added Planetary Shield (SLD", colony.planetaryShieldLevel, ") to system ", systemId

        of econ_types.ConstructionType.Industrial:
          # IU investment - industrial capacity was added when project started
          # Just log completion
          echo "      Industrial expansion completed at system ", systemId

        of econ_types.ConstructionType.Infrastructure:
          # Infrastructure was already added during creation
          # Just log completion
          echo "      Infrastructure expansion completed at system ", systemId

        # Clear construction slot
        colony.underConstruction = none(econ_types.ConstructionProject)
      else:
        # Still under construction
        colony.underConstruction = some(project)

  # Process research allocation
  # Per economy.md:4.0: Players allocate PP to research each turn
  # PP is converted to ERP/SRP/TRP based on current tech levels and GHO
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]
      let allocation = packet.researchAllocation

      # Calculate GHO for this house
      var gho = 0
      for colony in state.colonies.values:
        if colony.owner == houseId:
          gho += colony.production

      # Get current tech levels
      let currentSL = state.houses[houseId].techTree.levels.scienceLevel  # Science Level

      # Convert PP allocations to RP
      let earnedRP = res_costs.allocateResearch(allocation, gho, currentSL)

      # Accumulate RP
      state.houses[houseId].techTree.accumulated.economic += earnedRP.economic
      state.houses[houseId].techTree.accumulated.science += earnedRP.science

      for field, trp in earnedRP.technology:
        if field notin state.houses[houseId].techTree.accumulated.technology:
          state.houses[houseId].techTree.accumulated.technology[field] = 0
        state.houses[houseId].techTree.accumulated.technology[field] += trp

      # Log allocations
      if allocation.economic > 0:
        echo "      ", houseId, " allocated ", allocation.economic, " PP → ", earnedRP.economic, " ERP",
             " (total: ", state.houses[houseId].techTree.accumulated.economic, " ERP)"
      if allocation.science > 0:
        echo "      ", houseId, " allocated ", allocation.science, " PP → ", earnedRP.science, " SRP",
             " (total: ", state.houses[houseId].techTree.accumulated.science, " SRP)"
      for field, pp in allocation.technology:
        if pp > 0 and field in earnedRP.technology:
          let totalTRP = state.houses[houseId].techTree.accumulated.technology.getOrDefault(field, 0)
          echo "      ", houseId, " allocated ", pp, " PP → ", earnedRP.technology[field], " TRP (", field, ")",
               " (total: ", totalTRP, " TRP)"

## Phase 3: Command

proc resolveCommandPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                        events: var seq[GameEvent]) =
  ## Phase 3: Execute orders
  ## Build orders may fail if shipyards were destroyed in conflict phase
  echo "  [Command Phase]"

  # Process build orders first
  for houseId in state.houses.keys:
    if houseId in orders:
      resolveBuildOrders(state, orders[houseId], events)

  # Process Space Guild population transfers
  for houseId in state.houses.keys:
    if houseId in orders:
      resolvePopulationTransfers(state, orders[houseId], events)

  # Process diplomatic actions (per gameplay.md:1.3.3 - Command Phase)
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]

      for action in packet.diplomaticActions:
        case action.actionType
        of DiplomaticActionType.ProposeNonAggressionPact:
          # Pact proposal system per docs/architecture/diplomacy_proposals.md
          # Creates pending proposal that target must accept/reject
          echo "    ", houseId, " proposed Non-Aggression Pact to ", action.targetHouse

          if action.targetHouse in state.houses and not state.houses[action.targetHouse].eliminated:
            # Check if proposer can form pacts (not isolated)
            if not dip_types.canFormPact(state.houses[houseId].violationHistory):
              echo "      Proposal blocked: proposer is diplomatically isolated"
            else:
              # Create pending proposal
              let proposal = dip_proposals.PendingProposal(
                id: dip_proposals.generateProposalId(state.turn, houseId, action.targetHouse),
                proposer: houseId,
                target: action.targetHouse,
                proposalType: dip_proposals.ProposalType.NonAggressionPact,
                submittedTurn: state.turn,
                expiresIn: 3,  # 3 turns to respond
                status: dip_proposals.ProposalStatus.Pending,
                message: action.message.get("")
              )
              state.pendingProposals.add(proposal)
              echo "      Proposal created (expires in 3 turns)"

        of DiplomaticActionType.AcceptProposal:
          # Accept pending proposal
          if action.proposalId.isNone:
            echo "    ERROR: AcceptProposal missing proposalId"
            continue

          let proposalId = action.proposalId.get()
          let proposalIndex = dip_proposals.findProposalIndex(state.pendingProposals, proposalId)

          if proposalIndex < 0:
            echo "    ERROR: Proposal ", proposalId, " not found"
            continue

          var proposal = state.pendingProposals[proposalIndex]

          if proposal.target != houseId:
            echo "    ERROR: ", houseId, " cannot accept proposal not targeted at them"
            continue

          if proposal.status != dip_proposals.ProposalStatus.Pending:
            echo "    ERROR: Proposal ", proposalId, " is not pending (status: ", proposal.status, ")"
            continue

          echo "    ", houseId, " accepted Non-Aggression Pact from ", proposal.proposer

          # Establish pact for both houses
          let eventOpt1 = dip_engine.proposePact(
            state.houses[proposal.proposer].diplomaticRelations,
            houseId,
            state.houses[proposal.proposer].violationHistory,
            state.turn
          )

          let eventOpt2 = dip_engine.proposePact(
            state.houses[houseId].diplomaticRelations,
            proposal.proposer,
            state.houses[houseId].violationHistory,
            state.turn
          )

          if eventOpt1.isSome and eventOpt2.isSome:
            proposal.status = dip_proposals.ProposalStatus.Accepted
            state.pendingProposals[proposalIndex] = proposal
            echo "      Pact established"
          else:
            echo "      Pact establishment failed (blocked)"

        of DiplomaticActionType.RejectProposal:
          # Reject pending proposal
          if action.proposalId.isNone:
            echo "    ERROR: RejectProposal missing proposalId"
            continue

          let proposalId = action.proposalId.get()
          let proposalIndex = dip_proposals.findProposalIndex(state.pendingProposals, proposalId)

          if proposalIndex < 0:
            echo "    ERROR: Proposal ", proposalId, " not found"
            continue

          var proposal = state.pendingProposals[proposalIndex]

          if proposal.target != houseId:
            echo "    ERROR: ", houseId, " cannot reject proposal not targeted at them"
            continue

          if proposal.status != dip_proposals.ProposalStatus.Pending:
            echo "    ERROR: Proposal ", proposalId, " is not pending (status: ", proposal.status, ")"
            continue

          echo "    ", houseId, " rejected Non-Aggression Pact from ", proposal.proposer
          proposal.status = dip_proposals.ProposalStatus.Rejected
          state.pendingProposals[proposalIndex] = proposal

        of DiplomaticActionType.WithdrawProposal:
          # Withdraw own proposal
          if action.proposalId.isNone:
            echo "    ERROR: WithdrawProposal missing proposalId"
            continue

          let proposalId = action.proposalId.get()
          let proposalIndex = dip_proposals.findProposalIndex(state.pendingProposals, proposalId)

          if proposalIndex < 0:
            echo "    ERROR: Proposal ", proposalId, " not found"
            continue

          var proposal = state.pendingProposals[proposalIndex]

          if proposal.proposer != houseId:
            echo "    ERROR: ", houseId, " cannot withdraw proposal from ", proposal.proposer
            continue

          if proposal.status != dip_proposals.ProposalStatus.Pending:
            echo "    ERROR: Proposal ", proposalId, " is not pending (status: ", proposal.status, ")"
            continue

          echo "    ", houseId, " withdrew Non-Aggression Pact proposal to ", proposal.target
          proposal.status = dip_proposals.ProposalStatus.Withdrawn
          state.pendingProposals[proposalIndex] = proposal

        of DiplomaticActionType.BreakPact:
          # Breaking a pact triggers violation penalties (diplomacy.md:8.1.2)
          echo "    ", houseId, " breaking pact with ", action.targetHouse

          # Check if there's actually a pact to break
          let currentState = dip_engine.getDiplomaticState(
            state.houses[houseId].diplomaticRelations,
            action.targetHouse
          )

          if currentState == dip_types.DiplomaticState.NonAggression:
            # Record violation
            let violation = dip_engine.recordViolation(
              state.houses[houseId].violationHistory,
              houseId,
              action.targetHouse,
              state.turn,
              "Broke Non-Aggression Pact"
            )

            # Apply prestige penalties
            let prestigeEvents = dip_engine.applyViolationPenalties(
              houseId,
              action.targetHouse,
              state.houses[houseId].violationHistory,
              state.turn
            )

            for event in prestigeEvents:
              state.houses[houseId].prestige += event.amount
              echo "      ", event.description, ": ", event.amount, " prestige"

            # Apply dishonored status (3 turns per diplomacy.md:8.1.2)
            state.houses[houseId].dishonoredStatus = dip_types.DishonoredStatus(
              active: true,
              turnsRemaining: 3,
              violationTurn: state.turn
            )
            echo "      Dishonored for 3 turns"

            # Apply diplomatic isolation (5 turns per diplomacy.md:8.1.2)
            state.houses[houseId].diplomaticIsolation = dip_types.DiplomaticIsolation(
              active: true,
              turnsRemaining: 5,
              violationTurn: state.turn
            )
            echo "      Isolated for 5 turns"

            # Set status to Enemy
            dip_engine.setDiplomaticState(
              state.houses[houseId].diplomaticRelations,
              action.targetHouse,
              dip_types.DiplomaticState.Enemy,
              state.turn
            )
          else:
            echo "      No pact exists to break"

        of DiplomaticActionType.DeclareEnemy:
          echo "    ", houseId, " declared ", action.targetHouse, " as Enemy"
          dip_engine.setDiplomaticState(
            state.houses[houseId].diplomaticRelations,
            action.targetHouse,
            dip_types.DiplomaticState.Enemy,
            state.turn
          )

        of DiplomaticActionType.SetNeutral:
          echo "    ", houseId, " set ", action.targetHouse, " to Neutral"
          dip_engine.setDiplomaticState(
            state.houses[houseId].diplomaticRelations,
            action.targetHouse,
            dip_types.DiplomaticState.Neutral,
            state.turn
          )

  # Process squadron management orders (form squadrons, transfer ships, assign to fleets)
  for houseId in state.houses.keys:
    if houseId in orders:
      resolveSquadronManagement(state, orders[houseId], events)

  # Process cargo management (manual loading/unloading)
  for houseId in state.houses.keys:
    if houseId in orders:
      resolveCargoManagement(state, orders[houseId], events)

  # Auto-load cargo at colonies (if no manual cargo order exists)
  autoLoadCargo(state, orders, events)

  # Process terraforming orders
  for houseId in state.houses.keys:
    if houseId in orders:
      resolveTerraformOrders(state, orders[houseId], events)

  # Process all fleet orders (sorted by priority)
  var allFleetOrders: seq[(HouseId, FleetOrder)] = @[]

  for houseId in state.houses.keys:
    if houseId in orders:
      for order in orders[houseId].fleetOrders:
        allFleetOrders.add((houseId, order))

  # Sort by priority
  allFleetOrders.sort do (a, b: (HouseId, FleetOrder)) -> int:
    cmp(a[1].priority, b[1].priority)

  # Execute all fleet orders through the new executor
  for (houseId, order) in allFleetOrders:
    let result = executeFleetOrder(state, houseId, order)

    if result.success:
      echo "    [", $order.orderType, "] ", result.message
      # Add events from order execution
      for eventMsg in result.eventsGenerated:
        events.add(GameEvent(
          eventType: GameEventType.Battle,
          houseId: houseId,
          description: eventMsg,
          systemId: order.targetSystem
        ))

      # Some orders need additional processing after validation
      case order.orderType
      of FleetOrderType.Move, FleetOrderType.SeekHome, FleetOrderType.Patrol:
        # Executor validates, this does actual pathfinding and movement
        resolveMovementOrder(state, houseId, order, events)
      of FleetOrderType.Colonize:
        # Executor validates, this does actual colony creation
        resolveColonizationOrder(state, houseId, order, events)
      of FleetOrderType.Reserve:
        # Place fleet on reserve status
        # Per economy.md:3.9 - ships auto-join colony's single reserve fleet
        if order.fleetId in state.fleets:
          var fleet = state.fleets[order.fleetId]
          let colonySystem = fleet.location

          # Check if colony already has a reserve fleet
          var reserveFleetId: Option[FleetId] = none(FleetId)
          for fleetId, existingFleet in state.fleets:
            if existingFleet.owner == fleet.owner and
               existingFleet.location == colonySystem and
               existingFleet.status == FleetStatus.Reserve and
               fleetId != order.fleetId:
              reserveFleetId = some(fleetId)
              break

          if reserveFleetId.isSome:
            # Merge this fleet into existing reserve fleet
            let targetId = reserveFleetId.get()
            var targetFleet = state.fleets[targetId]

            # Transfer all squadrons to reserve fleet
            for squadron in fleet.squadrons:
              targetFleet.squadrons.add(squadron)

            # Transfer spacelift ships if any
            for ship in fleet.spaceLiftShips:
              targetFleet.spaceLiftShips.add(ship)

            state.fleets[targetId] = targetFleet

            # Remove the now-empty fleet
            state.fleets.del(order.fleetId)

            echo "    [Reserve] Fleet ", order.fleetId, " merged into colony reserve fleet ", targetId
          else:
            # Create new reserve fleet at this colony
            state.fleets[order.fleetId].status = FleetStatus.Reserve
            echo "    [Reserve] Fleet ", order.fleetId, " is now colony reserve fleet (50% maint, half AS/DS)"
      of FleetOrderType.Mothball:
        # Mothball fleet
        # Per economy.md:3.9 - ships auto-join colony's single mothballed fleet
        if order.fleetId in state.fleets:
          var fleet = state.fleets[order.fleetId]
          let colonySystem = fleet.location

          # Check if colony already has a mothballed fleet
          var mothballedFleetId: Option[FleetId] = none(FleetId)
          for fleetId, existingFleet in state.fleets:
            if existingFleet.owner == fleet.owner and
               existingFleet.location == colonySystem and
               existingFleet.status == FleetStatus.Mothballed and
               fleetId != order.fleetId:
              mothballedFleetId = some(fleetId)
              break

          if mothballedFleetId.isSome:
            # Merge this fleet into existing mothballed fleet
            let targetId = mothballedFleetId.get()
            var targetFleet = state.fleets[targetId]

            # Transfer all squadrons to mothballed fleet
            for squadron in fleet.squadrons:
              targetFleet.squadrons.add(squadron)

            # Transfer spacelift ships if any
            for ship in fleet.spaceLiftShips:
              targetFleet.spaceLiftShips.add(ship)

            state.fleets[targetId] = targetFleet

            # Remove the now-empty fleet
            state.fleets.del(order.fleetId)

            echo "    [Mothball] Fleet ", order.fleetId, " merged into colony mothballed fleet ", targetId
          else:
            # Create new mothballed fleet at this colony
            state.fleets[order.fleetId].status = FleetStatus.Mothballed
            echo "    [Mothball] Fleet ", order.fleetId, " is now colony mothballed fleet (0% maint, offline)"
      of FleetOrderType.Reactivate:
        # Reactivate fleet
        if order.fleetId in state.fleets:
          state.fleets[order.fleetId].status = FleetStatus.Active
          echo "    [Reactivate] Fleet ", order.fleetId, " returned to active duty"
      else:
        discard  # Fully handled by executor
    else:
      echo "    [", $order.orderType, "] FAILED: ", result.message

proc resolveBuildOrders(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
  ## Process construction orders for a house
  echo "    Processing build orders for ", state.houses[packet.houseId].name

  for order in packet.buildOrders:
    # Validate colony exists
    if order.colonySystem notin state.colonies:
      echo "      Build order failed: colony not found at system ", order.colonySystem
      continue

    # Validate colony ownership
    let colony = state.colonies[order.colonySystem]
    if colony.owner != packet.houseId:
      echo "      Build order failed: colony not owned by ", packet.houseId
      continue

    # Check if colony already has construction in progress
    if colony.underConstruction.isSome:
      echo "      Build order failed: system ", order.colonySystem, " already building something"
      continue

    # Convert gamestate.Colony to economy.Colony for construction functions
    var econColony = econ_types.Colony(
      systemId: colony.systemId,
      owner: colony.owner,
      populationUnits: colony.population,
      populationTransferUnits: 0,
      industrial: econ_types.IndustrialUnits(
        units: colony.infrastructure,  # Map infrastructure to IU
        investmentCost: 30  # Base cost
      ),
      planetClass: colony.planetClass,
      resources: colony.resources,
      underConstruction: none(econ_types.ConstructionProject)
    )

    # Create construction project based on build type
    var project: econ_types.ConstructionProject
    var projectDesc: string

    case order.buildType
    of BuildType.Infrastructure:
      # Infrastructure investment (IU expansion)
      let units = order.industrialUnits
      if units <= 0:
        echo "      Infrastructure order failed: invalid unit count ", units
        continue

      project = construction.createIndustrialProject(econColony, units)
      projectDesc = "Industrial expansion: " & $units & " IU"

    of BuildType.Ship:
      # Ship construction
      if order.shipClass.isNone:
        echo "      Ship construction failed: no ship class specified"
        continue

      let shipClass = order.shipClass.get()
      project = construction.createShipProject(shipClass)
      projectDesc = "Ship construction: " & $shipClass

    of BuildType.Building:
      # Building construction
      if order.buildingType.isNone:
        echo "      Building construction failed: no building type specified"
        continue

      let buildingType = order.buildingType.get()
      project = construction.createBuildingProject(buildingType)
      projectDesc = "Building construction: " & buildingType

    # Start construction
    if construction.startConstruction(econColony, project):
      # Convert back and update game state
      var updatedColony = colony
      updatedColony.underConstruction = some(project)
      state.colonies[order.colonySystem] = updatedColony

      echo "      Started construction at system ", order.colonySystem, ": ", projectDesc
      echo "        Cost: ", project.costTotal, " PP, Est. ", project.turnsRemaining, " turns"

      # Generate event
      events.add(GameEvent(
        eventType: GameEventType.ConstructionStarted,
        houseId: packet.houseId,
        description: "Started " & projectDesc & " at system " & $order.colonySystem,
        systemId: some(order.colonySystem)
      ))
    else:
      echo "      Construction start failed at system ", order.colonySystem

proc resolveSquadronManagement(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
  ## Process squadron management orders: form squadrons, transfer ships, assign to fleets
  for order in packet.squadronManagement:
    # Validate colony exists and is owned by house
    if order.colonySystem notin state.colonies:
      echo "    Squadron management failed: System ", order.colonySystem, " has no colony"
      continue

    var colony = state.colonies[order.colonySystem]
    if colony.owner != packet.houseId:
      echo "    Squadron management failed: ", packet.houseId, " does not own system ", order.colonySystem
      continue

    case order.action
    of SquadronManagementAction.TransferShip:
      # Transfer ship between squadrons at this colony
      if order.sourceSquadronId.isNone or order.shipIndex.isNone:
        echo "    TransferShip failed: Missing source squadron or ship index"
        continue

      if order.targetSquadronId.isNone:
        echo "    TransferShip failed: Missing target squadron"
        continue

      # Find source and target squadrons in fleets at this colony
      var sourceFleet: Option[FleetId] = none(FleetId)
      var targetFleet: Option[FleetId] = none(FleetId)
      var sourceSquadIndex: int = -1
      var targetSquadIndex: int = -1

      # Locate source squadron
      for fleetId, fleet in state.fleets:
        if fleet.location == order.colonySystem and fleet.owner == packet.houseId:
          for i, squad in fleet.squadrons:
            if squad.id == order.sourceSquadronId.get():
              sourceFleet = some(fleetId)
              sourceSquadIndex = i
              break
          if sourceFleet.isSome:
            break

      if sourceFleet.isNone:
        echo "    TransferShip failed: Source squadron ", order.sourceSquadronId.get(), " not found"
        continue

      # Locate target squadron
      for fleetId, fleet in state.fleets:
        if fleet.location == order.colonySystem and fleet.owner == packet.houseId:
          for i, squad in fleet.squadrons:
            if squad.id == order.targetSquadronId.get():
              targetFleet = some(fleetId)
              targetSquadIndex = i
              break
          if targetFleet.isSome:
            break

      if targetFleet.isNone:
        echo "    TransferShip failed: Target squadron ", order.targetSquadronId.get(), " not found"
        continue

      # Remove ship from source squadron
      let shipIndex = order.shipIndex.get()
      var sourceSquad = state.fleets[sourceFleet.get()].squadrons[sourceSquadIndex]

      if shipIndex < 0 or shipIndex >= sourceSquad.ships.len:
        echo "    TransferShip failed: Invalid ship index ", shipIndex, " (squadron has ", sourceSquad.ships.len, " ships)"
        continue

      let shipOpt = sourceSquad.removeShip(shipIndex)
      if shipOpt.isNone:
        echo "    TransferShip failed: Could not remove ship from source squadron"
        continue

      let ship = shipOpt.get()

      # Add ship to target squadron
      var targetSquad = state.fleets[targetFleet.get()].squadrons[targetSquadIndex]

      if not targetSquad.addShip(ship):
        echo "    TransferShip failed: Could not add ship to target squadron (may be full or incompatible)"
        # Put ship back in source squadron
        discard sourceSquad.addShip(ship)
        state.fleets[sourceFleet.get()].squadrons[sourceSquadIndex] = sourceSquad
        continue

      # Update both squadrons in state
      state.fleets[sourceFleet.get()].squadrons[sourceSquadIndex] = sourceSquad
      state.fleets[targetFleet.get()].squadrons[targetSquadIndex] = targetSquad

      echo "    Transferred ship from ", order.sourceSquadronId.get(), " to ", order.targetSquadronId.get()

    of SquadronManagementAction.AssignToFleet:
      # Assign existing squadron to fleet (move between fleets or create new fleet)
      if order.squadronId.isNone:
        echo "    AssignToFleet failed: No squadron ID specified"
        continue

      # Find squadron in existing fleets at this colony
      var foundSquadron: Option[Squadron] = none(Squadron)
      var sourceFleetId: Option[FleetId] = none(FleetId)

      for fleetId, fleet in state.fleets:
        if fleet.location == order.colonySystem and fleet.owner == packet.houseId:
          for i, squad in fleet.squadrons:
            if squad.id == order.squadronId.get():
              foundSquadron = some(squad)
              sourceFleetId = some(fleetId)
              break
          if foundSquadron.isSome:
            break

      if foundSquadron.isNone:
        echo "    AssignToFleet failed: Squadron ", order.squadronId.get(), " not found at system"
        continue

      let squadron = foundSquadron.get()

      # Remove squadron from source fleet
      if sourceFleetId.isSome:
        let srcFleet = state.fleets[sourceFleetId.get()]
        var newSquadrons: seq[Squadron] = @[]
        for squad in srcFleet.squadrons:
          if squad.id != order.squadronId.get():
            newSquadrons.add(squad)
        state.fleets[sourceFleetId.get()].squadrons = newSquadrons

        # If source fleet is now empty, remove it
        if newSquadrons.len == 0:
          state.fleets.del(sourceFleetId.get())
          echo "    Removed empty fleet ", sourceFleetId.get()

      # Add squadron to target fleet or create new one
      if order.targetFleetId.isSome:
        # Assign to existing fleet
        let targetId = order.targetFleetId.get()
        if targetId in state.fleets:
          state.fleets[targetId].squadrons.add(squadron)
          echo "    Assigned squadron ", squadron.id, " to fleet ", targetId
        else:
          echo "    AssignToFleet failed: Target fleet ", targetId, " does not exist"
      else:
        # Create new fleet
        let newFleetId = packet.houseId & "_fleet_" & $order.colonySystem & "_" & $state.turn
        state.fleets[newFleetId] = Fleet(
          id: newFleetId,
          owner: packet.houseId,
          location: order.colonySystem,
          squadrons: @[squadron]
        )
        echo "    Created new fleet ", newFleetId, " with squadron ", squadron.id

    # Update colony in state
    state.colonies[order.colonySystem] = colony

proc resolveCargoManagement(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
  ## Process manual cargo management orders (load/unload)
  for order in packet.cargoManagement:
    # Validate colony exists and is owned by house
    if order.colonySystem notin state.colonies:
      echo "    Cargo management failed: System ", order.colonySystem, " has no colony"
      continue

    let colony = state.colonies[order.colonySystem]
    if colony.owner != packet.houseId:
      echo "    Cargo management failed: ", packet.houseId, " does not own system ", order.colonySystem
      continue

    # Validate fleet exists and is at colony
    let fleetOpt = state.getFleet(order.fleetId)
    if fleetOpt.isNone:
      echo "    Cargo management failed: Fleet ", order.fleetId, " does not exist"
      continue

    let fleet = fleetOpt.get()
    if fleet.location != order.colonySystem:
      echo "    Cargo management failed: Fleet ", order.fleetId, " not at colony ", order.colonySystem
      continue

    case order.action
    of CargoManagementAction.LoadCargo:
      if order.cargoType.isNone:
        echo "    LoadCargo failed: No cargo type specified"
        continue

      let cargoType = order.cargoType.get()
      var requestedQty = if order.quantity.isSome: order.quantity.get() else: 0  # 0 = all available

      # Get mutable colony and fleet
      var colony = state.colonies[order.colonySystem]
      var fleet = fleetOpt.get()
      var totalLoaded = 0

      # Check colony inventory based on cargo type
      var availableUnits = case cargoType
        of CargoType.Marines: colony.marines
        of CargoType.Colonists:
          # Calculate how many complete PTUs can be loaded from exact population
          # Using souls field for accurate counting (no float rounding errors)
          # Per config/population.toml [ptu_definition] min_population_remaining = 0 (allow evacuation)
          # However, per [transfer_limits] min_source_pu_remaining = 1 (must keep 1 PU minimum)
          # This prevents total evacuation while allowing near-complete evacuation
          let minSoulsToKeep = 1_000_000  # 1 PU = 1 million souls (config/population.toml)
          if colony.souls <= minSoulsToKeep:
            0  # Cannot load any PTUs, colony at minimum viable population
          else:
            let availableSouls = colony.souls - minSoulsToKeep
            let maxPTUs = availableSouls div soulsPerPtu()
            maxPTUs
        else: 0

      if availableUnits <= 0:
        echo "    LoadCargo failed: No ", cargoType, " available at ", order.colonySystem
        continue

      # If quantity = 0, load all available
      if requestedQty == 0:
        requestedQty = availableUnits

      # Load cargo onto compatible spacelift ships
      var remainingToLoad = min(requestedQty, availableUnits)
      var modifiedShips: seq[SpaceLiftShip] = @[]

      for ship in fleet.spaceLiftShips:
        if remainingToLoad <= 0:
          modifiedShips.add(ship)
          continue

        if ship.isCrippled:
          modifiedShips.add(ship)
          continue

        # Determine ship capacity and compatible cargo type
        let shipCargoType = case ship.shipClass
          of ShipClass.TroopTransport: CargoType.Marines
          of ShipClass.ETAC: CargoType.Colonists
          else: CargoType.None

        if shipCargoType != cargoType:
          modifiedShips.add(ship)
          continue  # Ship can't carry this cargo type

        # Try to load cargo onto this ship
        var mutableShip = ship
        let loadAmount = min(remainingToLoad, mutableShip.cargo.capacity - mutableShip.cargo.quantity)
        if mutableShip.loadCargo(cargoType, loadAmount):
          totalLoaded += loadAmount
          remainingToLoad -= loadAmount
          echo "    Loaded ", loadAmount, " ", cargoType, " onto ", ship.shipClass, " ", ship.id

        modifiedShips.add(mutableShip)

      # Update colony inventory
      if totalLoaded > 0:
        case cargoType
        of CargoType.Marines:
          colony.marines -= totalLoaded
        of CargoType.Colonists:
          # Colonists come from population: 1 PTU = 50k souls
          # Use souls field for exact counting (no rounding errors)
          let soulsToLoad = totalLoaded * soulsPerPtu()
          colony.souls -= soulsToLoad
          # Update display field (population in millions)
          colony.population = colony.souls div 1_000_000
          echo "    Removed ", totalLoaded, " PTU (", soulsToLoad, " souls, ", totalLoaded.float * ptuSizeMillions(), "M) from colony"
        else:
          discard

        # Write back modified state
        fleet.spaceLiftShips = modifiedShips
        state.fleets[order.fleetId] = fleet
        state.colonies[order.colonySystem] = colony
        echo "    Successfully loaded ", totalLoaded, " ", cargoType, " at ", order.colonySystem

    of CargoManagementAction.UnloadCargo:
      # Get mutable colony and fleet
      var colony = state.colonies[order.colonySystem]
      var fleet = fleetOpt.get()
      var modifiedShips: seq[SpaceLiftShip] = @[]
      var totalUnloaded = 0
      var unloadedType = CargoType.None

      # Unload cargo from spacelift ships
      for ship in fleet.spaceLiftShips:
        var mutableShip = ship

        if mutableShip.cargo.cargoType == CargoType.None:
          modifiedShips.add(mutableShip)
          continue  # No cargo to unload

        # Unload cargo back to colony inventory
        let (cargoType, quantity) = mutableShip.unloadCargo()
        totalUnloaded += quantity
        unloadedType = cargoType

        case cargoType
        of CargoType.Marines:
          colony.marines += quantity
          echo "    Unloaded ", quantity, " Marines from ", ship.id, " to colony"
        of CargoType.Colonists:
          # Colonists are delivered to population: 1 PTU = 50k souls
          # Use souls field for exact counting (no rounding errors)
          let soulsToUnload = quantity * soulsPerPtu()
          colony.souls += soulsToUnload
          # Update display field (population in millions)
          colony.population = colony.souls div 1_000_000
          echo "    Unloaded ", quantity, " PTU (", soulsToUnload, " souls, ", quantity.float * ptuSizeMillions(), "M) from ", ship.id, " to colony"
        else:
          discard

        modifiedShips.add(mutableShip)

      # Write back modified state
      if totalUnloaded > 0:
        fleet.spaceLiftShips = modifiedShips
        state.fleets[order.fleetId] = fleet
        state.colonies[order.colonySystem] = colony
        echo "    Successfully unloaded ", totalUnloaded, " ", unloadedType, " at ", order.colonySystem

proc resolveTerraformOrders(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
  ## Process terraforming orders - initiate new terraforming projects
  ## Per economy.md Section 4.7
  for order in packet.terraformOrders:
    # Validate colony exists and is owned by house
    if order.colonySystem notin state.colonies:
      echo "    Terraforming failed: System ", order.colonySystem, " has no colony"
      continue

    var colony = state.colonies[order.colonySystem]
    if colony.owner != packet.houseId:
      echo "    Terraforming failed: ", packet.houseId, " does not own system ", order.colonySystem
      continue

    # Check if already terraforming
    if colony.activeTerraforming.isSome:
      echo "    Terraforming failed: ", order.colonySystem, " already has active terraforming project"
      continue

    # Get house tech level
    if packet.houseId notin state.houses:
      echo "    Terraforming failed: House ", packet.houseId, " not found"
      continue

    let house = state.houses[packet.houseId]
    let terLevel = house.techTree.levels.terraformingTech

    # Validate TER level requirement
    let currentClass = ord(colony.planetClass) + 1  # Convert enum to class number (1-7)
    if not res_effects.canTerraform(currentClass, terLevel):
      let targetClass = currentClass + 1
      echo "    Terraforming failed: TER level ", terLevel, " insufficient for class ", currentClass, " -> ", targetClass, " (requires TER ", targetClass, ")"
      continue

    # Calculate costs and duration
    let targetClass = currentClass + 1
    let ppCost = res_effects.getTerraformingBaseCost(currentClass)
    let turnsRequired = res_effects.getTerraformingSpeed(terLevel)

    # Check house treasury has sufficient PP
    if house.treasury < ppCost:
      echo "    Terraforming failed: Insufficient PP (need ", ppCost, ", have ", house.treasury, ")"
      continue

    # Deduct PP cost from house treasury
    state.houses[packet.houseId].treasury -= ppCost

    # Create terraforming project
    let project = TerraformProject(
      startTurn: state.turn,
      turnsRemaining: turnsRequired,
      targetClass: targetClass,
      ppCost: ppCost,
      ppPaid: ppCost
    )

    colony.activeTerraforming = some(project)
    state.colonies[order.colonySystem] = colony

    let className = case targetClass
      of 1: "Extreme"
      of 2: "Desolate"
      of 3: "Hostile"
      of 4: "Harsh"
      of 5: "Benign"
      of 6: "Lush"
      of 7: "Eden"
      else: "Unknown"

    echo "    ", house.name, " initiated terraforming of ", order.colonySystem,
         " to ", className, " (class ", targetClass, ") - Cost: ", ppCost, " PP, Duration: ", turnsRequired, " turns"

    events.add(GameEvent(
      eventType: GameEventType.TerraformComplete,
      houseId: packet.houseId,
      description: house.name & " initiated terraforming of colony " & $order.colonySystem &
                  " to " & className & " (cost: " & $ppCost & " PP, duration: " & $turnsRequired & " turns)",
      systemId: some(order.colonySystem)
    ))

proc hasVisibilityOn(state: GameState, systemId: SystemId, houseId: HouseId): bool =
  ## Check if a house has visibility on a system (fog of war)
  ## A house can see a system if:
  ## - They own a colony there
  ## - They have a fleet present
  ## - They have a spy scout present

  # Check if house owns colony in this system
  if systemId in state.colonies:
    if state.colonies[systemId].owner == houseId:
      return true

  # Check if house has any fleets in this system
  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId and fleet.location == systemId:
      return true

  # Check if house has spy scouts in this system
  for scoutId, scout in state.spyScouts:
    if scout.owner == houseId and scout.location == systemId and not scout.detected:
      return true

  return false

proc canGuildTraversePath(state: GameState, path: seq[SystemId], transferringHouse: HouseId): bool =
  ## Check if Space Guild can traverse a path for a given house
  ## Guild validates path using the house's known intel (fog of war)
  ## Returns false if:
  ## - Path crosses system the house has no visibility on (intel leak prevention)
  ## - Path crosses enemy-controlled system (blockade)
  for systemId in path:
    # Player must have visibility on this system (prevents intel leak exploit)
    if not hasVisibilityOn(state, systemId, transferringHouse):
      return false

    # If system has a colony, it must be friendly (not enemy-controlled)
    if systemId in state.colonies:
      let colony = state.colonies[systemId]
      if colony.owner != transferringHouse:
        # Enemy-controlled system - Guild cannot pass through
        return false

  return true

proc calculateTransitTime(state: GameState, sourceSystem: SystemId, destSystem: SystemId, houseId: HouseId): tuple[turns: int, jumps: int] =
  ## Calculate Space Guild transit time and jump distance
  ## Per config/population.toml: turns_per_jump = 1, minimum_turns = 1
  ## Uses pathfinding to calculate actual jump lane distance
  ## Returns (turns: -1, jumps: 0) if path crosses enemy territory (Guild cannot complete transfer)
  if sourceSystem == destSystem:
    return (turns: 1, jumps: 0)  # Minimum 1 turn even for same system, 0 jumps

  # Space Guild civilian transports can use all lanes (not restricted by fleet composition)
  # Create a dummy fleet that can traverse all lanes
  let dummyFleet = Fleet(
    id: "transit_calc",
    owner: "GUILD".HouseId,
    location: sourceSystem,
    squadrons: @[],
    spaceliftShips: @[]
  )

  # Use starmap pathfinding to get actual jump distance
  let pathResult = state.starMap.findPath(sourceSystem, destSystem, dummyFleet)

  if pathResult.found:
    # Check if path crosses enemy territory
    if not canGuildTraversePath(state, pathResult.path, houseId):
      return (turns: -1, jumps: 0)  # Cannot traverse enemy territory

    # Path length - 1 = number of jumps (e.g., [A, B, C] = 2 jumps)
    # 1 turn per jump per config/population.toml
    let jumps = pathResult.path.len - 1
    return (turns: max(1, jumps), jumps: jumps)
  else:
    # No valid path found (shouldn't happen on a connected map, but handle gracefully)
    # Fall back to hex distance as approximation
    if sourceSystem in state.starMap.systems and destSystem in state.starMap.systems:
      let source = state.starMap.systems[sourceSystem]
      let dest = state.starMap.systems[destSystem]
      let hexDist = distance(source.coords, dest.coords)
      let jumps = hexDist.int
      return (turns: max(1, jumps), jumps: jumps)
    else:
      return (turns: 1, jumps: 0)  # Ultimate fallback

proc calculateTransferCost(planetClass: PlanetClass, ptuAmount: int, jumps: int): int =
  ## Calculate Space Guild transfer cost per config/population.toml
  ## Formula: base_cost_per_ptu × ptu_amount × (1 + (jumps - 1) × 0.20)
  ## Source: docs/specs/economy.md Section 3.7, config/population.toml [transfer_costs]

  # Base cost per PTU by planet class (config/population.toml)
  let baseCostPerPTU = case planetClass
    of PlanetClass.Eden: 4
    of PlanetClass.Lush: 5
    of PlanetClass.Benign: 6
    of PlanetClass.Harsh: 8
    of PlanetClass.Hostile: 10
    of PlanetClass.Desolate: 12
    of PlanetClass.Extreme: 15

  # Distance modifier: +20% per jump beyond first (config/population.toml [transfer_modifiers])
  # First jump has no modifier, subsequent jumps add 20% each
  let distanceMultiplier = if jumps > 0:
    1.0 + (float(jumps - 1) * 0.20)
  else:
    1.0  # Same system, no distance penalty

  # Total cost = base × ptu × distance_modifier (rounded up)
  let totalCost = ceil(float(baseCostPerPTU * ptuAmount) * distanceMultiplier).int

  return totalCost

proc resolvePopulationTransfers(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
  ## Process Space Guild population transfers between colonies
  ## Source: docs/specs/economy.md Section 3.7, config/population.toml
  echo "    Processing population transfers for ", state.houses[packet.houseId].name

  for transfer in packet.populationTransfers:
    # Validate source colony exists and is owned by house
    if transfer.sourceColony notin state.colonies:
      echo "      Transfer failed: source colony ", transfer.sourceColony, " not found"
      continue

    var sourceColony = state.colonies[transfer.sourceColony]
    if sourceColony.owner != packet.houseId:
      echo "      Transfer failed: source colony ", transfer.sourceColony, " not owned by ", packet.houseId
      continue

    # Validate destination colony exists and is owned by house
    if transfer.destColony notin state.colonies:
      echo "      Transfer failed: destination colony ", transfer.destColony, " not found"
      continue

    var destColony = state.colonies[transfer.destColony]
    if destColony.owner != packet.houseId:
      echo "      Transfer failed: destination colony ", transfer.destColony, " not owned by ", packet.houseId
      continue

    # Critical validation: Destination must have ≥1 PTU (50k souls) to be a functional colony
    if destColony.souls < soulsPerPtu():
      echo "      Transfer failed: destination colony ", transfer.destColony, " has only ", destColony.souls,
           " souls (needs ≥", soulsPerPtu(), " to accept transfers)"
      continue

    # Convert PTU amount to souls for exact transfer
    let soulsToTransfer = transfer.ptuAmount * soulsPerPtu()

    # Validate source has enough souls (can transfer any amount, even fractional PTU)
    if sourceColony.souls < soulsToTransfer:
      echo "      Transfer failed: source colony ", transfer.sourceColony, " has only ", sourceColony.souls,
           " souls (needs ", soulsToTransfer, " for ", transfer.ptuAmount, " PTU)"
      continue

    # Calculate transit time and jump distance
    let (transitTime, jumps) = calculateTransitTime(state, transfer.sourceColony, transfer.destColony, packet.houseId)

    # Check if Guild can complete the transfer (path must be known and not blocked)
    if transitTime < 0:
      echo "      Transfer failed: No safe Guild route between ",
           transfer.sourceColony, " and ", transfer.destColony,
           " (requires scouted path through friendly/neutral territory)"
      continue

    let arrivalTurn = state.turn + transitTime

    # Calculate transfer cost based on destination planet class and jump distance
    # Per config/population.toml and docs/specs/economy.md Section 3.7
    let cost = calculateTransferCost(destColony.planetClass, transfer.ptuAmount, jumps)

    # Check house treasury and deduct cost
    var house = state.houses[packet.houseId]
    if house.treasury < cost:
      echo "      Transfer failed: Insufficient funds (need ", cost, " PP, have ", house.treasury, " PP)"
      continue

    # Deduct cost from treasury
    house.treasury -= cost
    state.houses[packet.houseId] = house

    # Deduct souls from source colony immediately (they've departed)
    sourceColony.souls -= soulsToTransfer
    sourceColony.population = sourceColony.souls div 1_000_000
    state.colonies[transfer.sourceColony] = sourceColony

    # Create in-transit entry
    let transferId = $packet.houseId & "_" & $transfer.sourceColony & "_" & $transfer.destColony & "_" & $state.turn
    let inTransit = pop_types.PopulationInTransit(
      id: transferId,
      houseId: packet.houseId,
      sourceSystem: transfer.sourceColony,
      destSystem: transfer.destColony,
      ptuAmount: transfer.ptuAmount,
      costPaid: cost,
      arrivalTurn: arrivalTurn
    )
    state.populationInTransit.add(inTransit)

    echo "      Space Guild transporting ", transfer.ptuAmount, " PTU (", soulsToTransfer, " souls) from ",
         transfer.sourceColony, " to ", transfer.destColony, " (arrives turn ", arrivalTurn, ", cost: ", cost, " PP)"

    events.add(GameEvent(
      eventType: GameEventType.PopulationTransfer,
      houseId: packet.houseId,
      description: "Space Guild transporting " & $transfer.ptuAmount & " PTU from " & $transfer.sourceColony & " to " & $transfer.destColony & " (ETA: turn " & $arrivalTurn & ", cost: " & $cost & " PP)",
      systemId: some(transfer.sourceColony)
    ))

proc resolvePopulationArrivals(state: var GameState, events: var seq[GameEvent]) =
  ## Process Space Guild population transfers that arrive this turn
  ## Implements risk handling per config/population.toml [transfer_risks]
  echo "  [Processing Space Guild Arrivals]"

  var arrivedTransfers: seq[int] = @[]  # Indices to remove after processing

  for idx, transfer in state.populationInTransit:
    if transfer.arrivalTurn != state.turn:
      continue  # Not arriving this turn

    let soulsToDeliver = transfer.ptuAmount * soulsPerPtu()

    # Check destination status
    if transfer.destSystem notin state.colonies:
      # Destination colony no longer exists
      echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU LOST - destination colony destroyed"
      arrivedTransfers.add(idx)
      events.add(GameEvent(
        eventType: GameEventType.PopulationTransfer,
        houseId: transfer.houseId,
        description: $transfer.ptuAmount & " PTU lost - destination " & $transfer.destSystem & " destroyed",
        systemId: some(transfer.destSystem)
      ))
      continue

    var destColony = state.colonies[transfer.destSystem]

    # Check if destination conquered (no longer owned by originating house)
    if destColony.owner != transfer.houseId:
      # dest_conquered_behavior = "lost"
      echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU LOST - destination conquered by ", destColony.owner
      arrivedTransfers.add(idx)
      events.add(GameEvent(
        eventType: GameEventType.PopulationTransfer,
        houseId: transfer.houseId,
        description: $transfer.ptuAmount & " PTU lost - destination " & $transfer.destSystem & " conquered",
        systemId: some(transfer.destSystem)
      ))
      continue

    # Check if destination blockaded
    if destColony.blockaded:
      # dest_blockaded_behavior = "return"
      # Return PTUs to source colony if it still exists and is owned
      if transfer.sourceSystem in state.colonies:
        var sourceColony = state.colonies[transfer.sourceSystem]
        if sourceColony.owner == transfer.houseId:
          sourceColony.souls += soulsToDeliver
          sourceColony.population = sourceColony.souls div 1_000_000
          state.colonies[transfer.sourceSystem] = sourceColony
          echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU RETURNED to ", transfer.sourceSystem, " - destination blockaded"
          events.add(GameEvent(
            eventType: GameEventType.PopulationTransfer,
            houseId: transfer.houseId,
            description: $transfer.ptuAmount & " PTU returned from " & $transfer.destSystem & " (blockaded) to " & $transfer.sourceSystem,
            systemId: some(transfer.sourceSystem)
          ))
        else:
          echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU LOST - destination blockaded, source conquered"
      else:
        echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU LOST - destination blockaded, source destroyed"

      arrivedTransfers.add(idx)
      continue

    # Check if destination below minimum viable (< 1 PTU)
    if destColony.souls < soulsPerPtu():
      # Destination colony collapsed below functional threshold
      # Return to source if possible
      if transfer.sourceSystem in state.colonies:
        var sourceColony = state.colonies[transfer.sourceSystem]
        if sourceColony.owner == transfer.houseId:
          sourceColony.souls += soulsToDeliver
          sourceColony.population = sourceColony.souls div 1_000_000
          state.colonies[transfer.sourceSystem] = sourceColony
          echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU RETURNED to ", transfer.sourceSystem, " - destination below minimum viable"
        else:
          echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU LOST - destination collapsed, source conquered"
      else:
        echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU LOST - destination collapsed, source destroyed"

      arrivedTransfers.add(idx)
      continue

    # Successful delivery!
    destColony.souls += soulsToDeliver
    destColony.population = destColony.souls div 1_000_000
    state.colonies[transfer.destSystem] = destColony

    echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU arrived at ", transfer.destSystem, " (", soulsToDeliver, " souls)"
    events.add(GameEvent(
      eventType: GameEventType.PopulationTransfer,
      houseId: transfer.houseId,
      description: $transfer.ptuAmount & " PTU arrived at " & $transfer.destSystem & " from " & $transfer.sourceSystem,
      systemId: some(transfer.destSystem)
    ))

    arrivedTransfers.add(idx)

  # Remove processed transfers (in reverse order to preserve indices)
  for idx in countdown(arrivedTransfers.len - 1, 0):
    state.populationInTransit.del(arrivedTransfers[idx])

proc autoLoadCargo(state: var GameState, orders: Table[HouseId, OrderPacket], events: var seq[GameEvent]) =
  ## Automatically load available marines/colonists onto empty transports at colonies
  ## Only auto-load if no manual cargo order exists for that fleet

  # Build set of fleets with manual cargo orders
  var manualCargoFleets: seq[FleetId] = @[]
  for houseId, packet in orders:
    for order in packet.cargoManagement:
      manualCargoFleets.add(order.fleetId)

  # Process each colony
  for systemId, colony in state.colonies:
    # Find fleets at this colony
    for fleetId, fleet in state.fleets:
      if fleet.location != systemId or fleet.owner != colony.owner:
        continue

      # Skip if fleet has manual cargo orders
      if fleetId in manualCargoFleets:
        continue

      # Auto-load empty transports if colony has inventory
      var colony = state.colonies[systemId]
      var fleet = state.fleets[fleetId]
      var modifiedShips: seq[SpaceLiftShip] = @[]
      var modified = false

      for ship in fleet.spaceLiftShips:
        var mutableShip = ship

        if ship.isCrippled or ship.cargo.cargoType != CargoType.None:
          modifiedShips.add(mutableShip)
          continue  # Skip crippled ships or ships already loaded

        # Determine what cargo this ship can carry
        case ship.shipClass
        of ShipClass.TroopTransport:
          # Auto-load marines if available
          if colony.marines > 0:
            let loadAmount = min(1, colony.marines)  # TroopTransport capacity = 1 MD
            if mutableShip.loadCargo(CargoType.Marines, loadAmount):
              colony.marines -= loadAmount
              modified = true
              echo "    [Auto] Loaded ", loadAmount, " Marines onto ", ship.id, " at ", systemId

        of ShipClass.ETAC:
          # Auto-load colonists if available (1 PTU commitment)
          # ETACs carry exactly 1 PTU for colonization missions
          # Per config/population.toml [transfer_limits] min_source_pu_remaining = 1
          let minSoulsToKeep = 1_000_000  # 1 PU minimum
          if colony.souls > minSoulsToKeep + soulsPerPtu():
            if mutableShip.loadCargo(CargoType.Colonists, 1):
              colony.souls -= soulsPerPtu()
              colony.population = colony.souls div 1_000_000
              modified = true
              echo "    [Auto] Loaded 1 PTU onto ", ship.id, " at ", systemId

        else:
          discard  # Other ship classes don't have spacelift capability

        modifiedShips.add(mutableShip)

      # Write back modified state if any cargo was loaded
      if modified:
        fleet.spaceLiftShips = modifiedShips
        state.fleets[fleetId] = fleet
        state.colonies[systemId] = colony

proc resolveMovementOrder*(state: var GameState, houseId: HouseId, order: FleetOrder,
                         events: var seq[GameEvent]) =
  ## Execute a fleet movement order with pathfinding and lane traversal rules
  ## Per operations.md:6.1 - Lane traversal rules:
  ##   - Major lanes: 2 jumps per turn if all systems owned by player
  ##   - Major lanes: 1 jump per turn if jumping into unexplored/rival system
  ##   - Minor/Restricted lanes: 1 jump per turn maximum
  ##   - Crippled ships or Spacelift ships cannot cross Restricted lanes

  if order.targetSystem.isNone:
    return

  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    return

  var fleet = fleetOpt.get()
  let targetId = order.targetSystem.get()
  let startId = fleet.location

  # Already at destination
  if startId == targetId:
    echo "    Fleet ", order.fleetId, " already at destination"
    return

  echo "    Fleet ", order.fleetId, " moving from ", startId, " to ", targetId

  # Find path to destination (operations.md:6.1)
  let pathResult = state.starMap.findPath(startId, targetId, fleet)

  if not pathResult.found:
    echo "      No valid path found (blocked by restricted lanes or terrain)"
    return

  if pathResult.path.len < 2:
    echo "      Invalid path"
    return

  # Determine how many jumps the fleet can make this turn
  var jumpsAllowed = 1  # Default: 1 jump per turn

  # Check if we can do 2 major lane jumps (operations.md:6.1)
  if pathResult.path.len >= 3:
    # Check if all systems along path are owned by this house
    var allSystemsOwned = true
    for systemId in pathResult.path:
      if systemId notin state.colonies or state.colonies[systemId].owner != houseId:
        allSystemsOwned = false
        break

    # Check if next two jumps are both major lanes
    var nextTwoAreMajor = true
    if allSystemsOwned:
      for i in 0..<min(2, pathResult.path.len - 1):
        let fromSys = pathResult.path[i]
        let toSys = pathResult.path[i + 1]

        # Find lane type between these systems
        var laneIsMajor = false
        for lane in state.starMap.lanes:
          if (lane.source == fromSys and lane.destination == toSys) or
             (lane.source == toSys and lane.destination == fromSys):
            if lane.laneType == LaneType.Major:
              laneIsMajor = true
            break

        if not laneIsMajor:
          nextTwoAreMajor = false
          break

    # Apply 2-jump rule for major lanes in friendly territory
    if allSystemsOwned and nextTwoAreMajor:
      jumpsAllowed = 2

  # Execute movement (up to jumpsAllowed systems)
  let actualJumps = min(jumpsAllowed, pathResult.path.len - 1)
  let newLocation = pathResult.path[actualJumps]

  fleet.location = newLocation
  state.fleets[order.fleetId] = fleet

  echo "      Moved ", actualJumps, " jump(s) to system ", newLocation

  # Check for fleet encounters at destination
  # Find other fleets at the same location
  for otherFleetId, otherFleet in state.fleets:
    if otherFleetId != order.fleetId and otherFleet.location == newLocation:
      if otherFleet.owner != houseId:
        echo "      Encountered fleet ", otherFleetId, " (", otherFleet.owner, ") at ", newLocation
        # Combat will be resolved in conflict phase next turn
        # This just logs the encounter

proc resolveColonizationOrder(state: var GameState, houseId: HouseId, order: FleetOrder,
                              events: var seq[GameEvent]) =
  ## Establish a new colony with prestige rewards
  if order.targetSystem.isNone:
    return

  let targetId = order.targetSystem.get()

  # Check if system already colonized
  if targetId in state.colonies:
    echo "    System ", targetId, " already colonized"
    return

  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    return

  # Check system exists
  if targetId notin state.starMap.systems:
    echo "    System ", targetId, " not found in starMap"
    return

  # TODO: Planet class and resources should be pre-generated or determined by system properties
  # For now, assume ETAC scouts found a benign world with abundant resources
  let planetClass = PlanetClass.Benign
  let resources = ResourceRating.Abundant

  # Create ETAC colony with 1 PTU (50k souls)
  let colony = createETACColony(targetId, houseId, planetClass, resources)

  # Use colonization engine to establish with prestige
  let result = col_engine.establishColony(
    houseId,
    targetId,
    colony.planetClass,
    colony.resources,
    1  # ETAC carries exactly 1 PTU
  )

  if result.success:
    state.colonies[targetId] = colony

    # Apply prestige award
    if result.prestigeEvent.isSome:
      let prestigeEvent = result.prestigeEvent.get()
      state.houses[houseId].prestige += prestigeEvent.amount
      echo "    ", state.houses[houseId].name, " colonized system ", targetId,
           " (+", prestigeEvent.amount, " prestige)"

    events.add(GameEvent(
      eventType: GameEventType.ColonyEstablished,
      houseId: houseId,
      description: "Established colony at system " & $targetId,
      systemId: some(targetId)
    ))

## Phase 1: Conflict (helper functions)

proc getTargetBucket(shipClass: ShipClass): TargetBucket =
  ## Determine target bucket from ship class
  case shipClass
  of ShipClass.Raider: TargetBucket.Raider
  of ShipClass.Fighter: TargetBucket.Fighter
  of ShipClass.Destroyer: TargetBucket.Destroyer
  of ShipClass.Starbase: TargetBucket.Starbase
  else: TargetBucket.Capital

proc executeCombat(
  state: var GameState,
  systemId: SystemId,
  fleetsInCombat: seq[(FleetId, Fleet)],
  systemOwner: Option[HouseId],
  includeStarbases: bool,
  includeUnassignedSquadrons: bool,
  combatPhase: string,
  preDetectedHouses: seq[HouseId] = @[]
): tuple[outcome: CombatResult, fleetsAtSystem: seq[(FleetId, Fleet)], detectedHouses: seq[HouseId]] =
  ## Helper function to execute a combat phase
  ## Returns combat outcome, fleets that participated, and newly detected cloaked houses
  ## preDetectedHouses: Houses already detected in previous combat phase

  if fleetsInCombat.len < 2:
    return (CombatResult(), @[], @[])

  echo "        ", combatPhase, " - ", fleetsInCombat.len, " fleets engaged"

  # Group fleets by house
  var houseFleets: Table[HouseId, seq[Fleet]] = initTable[HouseId, seq[Fleet]]()
  for (fleetId, fleet) in fleetsInCombat:
    if fleet.owner notin houseFleets:
      houseFleets[fleet.owner] = @[]
    houseFleets[fleet.owner].add(fleet)

  # Check if there's actual conflict (need at least 2 different houses)
  if houseFleets.len < 2:
    return (CombatResult(), @[], @[])

  # Build Task Forces for combat
  var taskForces: Table[HouseId, TaskForce] = initTable[HouseId, TaskForce]()

  for houseId, fleets in houseFleets:
    # Convert all house fleets to CombatSquadrons
    var combatSquadrons: seq[CombatSquadron] = @[]

    for fleet in fleets:
      # Mothballed ships are screened during combat and cannot fight
      if fleet.status == FleetStatus.Mothballed:
        echo "          Fleet ", fleet.id, " is mothballed - screened from combat"
        continue

      for squadron in fleet.squadrons:
        let combatSq = CombatSquadron(
          squadron: squadron,
          state: if squadron.flagship.isCrippled: CombatState.Crippled else: CombatState.Undamaged,
          fleetStatus: fleet.status,
          damageThisTurn: 0,
          crippleRound: 0,
          bucket: getTargetBucket(squadron.flagship.shipClass),
          targetWeight: 1.0
        )
        combatSquadrons.add(combatSq)

    # Add unassigned squadrons from colony if this is orbital combat
    if includeUnassignedSquadrons and systemOwner.isSome and systemOwner.get() == houseId:
      if systemId in state.colonies:
        let colony = state.colonies[systemId]
        for squadron in colony.unassignedSquadrons:
          let combatSq = CombatSquadron(
            squadron: squadron,
            state: if squadron.flagship.isCrippled: CombatState.Crippled else: CombatState.Undamaged,
            fleetStatus: FleetStatus.Active,  # Unassigned squadrons fight at full strength
            damageThisTurn: 0,
            crippleRound: 0,
            bucket: getTargetBucket(squadron.flagship.shipClass),
            targetWeight: 1.0
          )
          combatSquadrons.add(combatSq)
        if colony.unassignedSquadrons.len > 0:
          echo "          Added ", colony.unassignedSquadrons.len, " unassigned squadron(s) to orbital defense"

    # Add starbases for system owner (always included for detection)
    # Starbases are ALWAYS included in task forces for detection purposes
    # In space combat: Starbases detect but don't fight (controlled by allowStarbaseCombat flag)
    # In orbital combat: Starbases detect AND fight
    if systemOwner.isSome and systemOwner.get() == houseId:
      if systemId in state.colonies:
        let colony = state.colonies[systemId]
        for starbase in colony.starbases:
          # Convert Starbase to Squadron-like structure for combat
          # Starbases are treated as special squadrons with fixed installations
          # Create EnhancedShip from Starbase using stats from config/ships.toml
          # TODO: Load stats from config instead of hardcoding (requires GameConfig in GameState)
          let starbaseShip = EnhancedShip(
            shipClass: ShipClass.Starbase,
            shipType: ShipType.Military,
            stats: ShipStats(
              attackStrength: 45,   # From config/ships.toml [starbase]
              defenseStrength: 50,  # From config/ships.toml [starbase]
              commandCost: 0,
              commandRating: 0
            ),
            isCrippled: starbase.isCrippled,
            name: "Starbase-" & starbase.id
          )

          let starbaseSquadron = Squadron(
            id: starbase.id,
            flagship: starbaseShip,
            ships: @[],  # Starbases have no escort ships
            owner: houseId,
            location: systemId,
            embarkedFighters: @[]
          )
          let combatSq = CombatSquadron(
            squadron: starbaseSquadron,
            state: if starbase.isCrippled: CombatState.Crippled else: CombatState.Undamaged,
            fleetStatus: FleetStatus.Active,  # Always active for detection
            damageThisTurn: 0,
            crippleRound: 0,
            bucket: TargetBucket.Starbase,
            targetWeight: 1.0
          )
          combatSquadrons.add(combatSq)
        if colony.starbases.len > 0:
          let combatRole = if includeStarbases: "defense and detection" else: "detection only"
          echo "          Added ", colony.starbases.len, " starbase(s) for ", combatRole

    # Create TaskForce for this house
    taskForces[houseId] = TaskForce(
      house: houseId,
      squadrons: combatSquadrons,
      roe: 5,  # Default ROE
      isCloaked: false,
      moraleModifier: 0,
      scoutBonus: false,
      isDefendingHomeworld: false
    )

  # Collect all task forces for battle
  var allTaskForces: seq[TaskForce] = @[]
  for houseId, tf in taskForces:
    allTaskForces.add(tf)

  # Generate deterministic seed
  let deterministicSeed = hash((state.turn, systemId, combatPhase)).int64

  # Determine if ambush bonuses and starbase combat apply
  # Ambush (+4 CER) only in space combat, NOT orbital combat
  # Starbases can fight only in orbital combat, NOT space combat (but always detect)
  let allowAmbush = (combatPhase == "Space Combat")
  let allowStarbaseCombat = (combatPhase == "Orbital Combat" or includeStarbases)

  var battleContext = BattleContext(
    systemId: systemId,
    taskForces: allTaskForces,
    seed: deterministicSeed,
    maxRounds: 20,
    allowAmbush: allowAmbush,
    allowStarbaseCombat: allowStarbaseCombat,
    preDetectedHouses: preDetectedHouses
  )

  # Execute battle
  let outcome = combat_engine.resolveCombat(battleContext)

  # Track detected houses (any that were cloaked but are now detected)
  var detectedHouses: seq[HouseId] = @[]
  for tf in outcome.survivors:
    # If house had Raiders but is no longer cloaked, they were detected
    if not tf.isCloaked:
      detectedHouses.add(tf.house)

  return (outcome, fleetsInCombat, detectedHouses)

proc resolveBattle(state: var GameState, systemId: SystemId,
                  orders: Table[HouseId, OrderPacket],
                  combatReports: var seq[CombatReport], events: var seq[GameEvent]) =
  ## Resolve combat at a system with linear progression (operations.md:7.0)
  ## Phase 1: Space Combat - non-guard mobile fleets fight first
  ## Phase 2: Orbital Combat - if attackers survive, fight guard/reserve fleets + starbases
  ## Uses orders to determine which fleets are on guard duty
  echo "    Combat at ", systemId

  # 1. Determine system ownership
  let systemOwner = if systemId in state.colonies: some(state.colonies[systemId].owner) else: none(HouseId)

  # 2. Gather all fleets at this system and classify by role
  var fleetsAtSystem: seq[(FleetId, Fleet)] = @[]
  var orbitalDefenders: seq[(FleetId, Fleet)] = @[]  # Guard/Reserve/Mothballed (orbital defense only)
  var attackingFleets: seq[(FleetId, Fleet)] = @[]   # Non-owner fleets (must fight through)
  var mobileDefenders: seq[(FleetId, Fleet)] = @[]   # Owner's mobile fleets (space combat)

  for fleetId, fleet in state.fleets:
    if fleet.location == systemId:
      fleetsAtSystem.add((fleetId, fleet))

      # Classify fleet based on ownership and orders
      let isDefender = systemOwner.isSome and systemOwner.get() == fleet.owner

      if isDefender:
        # Defender fleet classification
        var isOrbitalOnly = false

        # Check for guard orders
        if fleet.owner in orders:
          for order in orders[fleet.owner].fleetOrders:
            if order.fleetId == fleetId and
               (order.orderType == FleetOrderType.GuardStarbase or
                order.orderType == FleetOrderType.GuardPlanet):
              isOrbitalOnly = true
              break

        # Reserve and mothballed fleets only defend in orbital combat
        if fleet.status == FleetStatus.Reserve or fleet.status == FleetStatus.Mothballed:
          isOrbitalOnly = true

        if isOrbitalOnly:
          orbitalDefenders.add((fleetId, fleet))
        else:
          mobileDefenders.add((fleetId, fleet))
      else:
        # All non-owner fleets are attackers (must fight through space combat first)
        attackingFleets.add((fleetId, fleet))

  if fleetsAtSystem.len < 2:
    # Need at least 2 fleets for combat
    return

  # 3. PHASE 1: Space Combat (attackers vs mobile defenders)
  # All attacking fleets must fight through mobile defending fleets first
  # Mobile defenders = owner's active fleets without guard orders
  echo "      Phase 1: Space Combat"
  var spaceCombatOutcome: CombatResult
  var spaceCombatFleets: seq[(FleetId, Fleet)] = @[]
  var spaceCombatSurvivors: seq[HouseId] = @[]  # Houses that survived space combat
  var detectedInSpace: seq[HouseId] = @[]  # Houses detected during space combat

  # Check if there are attackers and mobile defenders
  if attackingFleets.len > 0 and mobileDefenders.len > 0:
    # Space combat: attackers must fight mobile defenders
    var spaceCombatParticipants = attackingFleets & mobileDefenders
    let (outcome, fleets, detected) = executeCombat(
      state, systemId, spaceCombatParticipants, systemOwner,
      includeStarbases = false,
      includeUnassignedSquadrons = false,
      "Space Combat",
      preDetectedHouses = @[]  # No pre-detection in space combat (first phase)
    )
    spaceCombatOutcome = outcome
    spaceCombatFleets = fleets
    detectedInSpace = detected

    # Track which attacker houses survived
    for tf in outcome.survivors:
      if tf.house != systemOwner.get() and tf.house notin spaceCombatSurvivors:
        spaceCombatSurvivors.add(tf.house)

    echo "          Space combat complete - ", spaceCombatOutcome.totalRounds, " rounds"
    echo "          ", spaceCombatSurvivors.len, " attacking house(s) survived"
    if detectedInSpace.len > 0:
      echo "          ", detectedInSpace.len, " cloaked house(s) detected"
  elif attackingFleets.len > 0:
    # No mobile defenders - attackers proceed directly to orbital combat
    echo "          No space combat (no mobile defenders)"
    # All attackers advance to orbital combat
    for (fleetId, fleet) in attackingFleets:
      if fleet.owner notin spaceCombatSurvivors:
        spaceCombatSurvivors.add(fleet.owner)
  else:
    echo "          No space combat (no attackers)"

  # 4. PHASE 2: Orbital Combat (surviving attackers vs orbital defenders)
  # Only attackers who survived space combat can engage orbital defenders
  # Orbital defenders = guard fleets + reserve + starbases + unassigned squadrons
  var orbitalCombatOutcome: CombatResult
  var orbitalCombatFleets: seq[(FleetId, Fleet)] = @[]

  # Only run if there's a colony with defenders and surviving attackers
  if systemOwner.isSome and spaceCombatSurvivors.len > 0:
    # Check if there are orbital defenders
    var hasOrbitalDefenders = orbitalDefenders.len > 0
    if systemId in state.colonies:
      let colony = state.colonies[systemId]
      if colony.starbases.len > 0 or colony.unassignedSquadrons.len > 0:
        hasOrbitalDefenders = true

    if hasOrbitalDefenders:
      echo "      Phase 2: Orbital Combat"

      # Gather surviving attacker fleets
      var survivingAttackerFleets: seq[(FleetId, Fleet)] = @[]
      for (fleetId, fleet) in fleetsAtSystem:
        if fleet.owner in spaceCombatSurvivors and fleet.owner != systemOwner.get():
          survivingAttackerFleets.add((fleetId, fleet))

      if survivingAttackerFleets.len > 0:
        # Combine orbital defenders and surviving attackers
        var orbitalFleets = orbitalDefenders & survivingAttackerFleets
        let (outcome, fleets, detected) = executeCombat(
          state, systemId, orbitalFleets, systemOwner,
          includeStarbases = true,
          includeUnassignedSquadrons = true,
          "Orbital Combat",
          preDetectedHouses = detectedInSpace  # Pass detection state from space combat
        )
        orbitalCombatOutcome = outcome
        orbitalCombatFleets = fleets
        echo "          Orbital combat complete - ", orbitalCombatOutcome.totalRounds, " rounds"
        if detected.len > detectedInSpace.len:
          echo "          ", (detected.len - detectedInSpace.len), " additional house(s) detected in orbital phase"
      else:
        echo "          No surviving attacker fleets for orbital combat"
    else:
      echo "      Phase 2: No orbital combat (no orbital defenders)"
      # Attackers achieved orbital supremacy without a fight
  elif systemOwner.isSome and spaceCombatSurvivors.len == 0:
    echo "      Phase 2: No orbital combat (attackers eliminated in space combat)"
  else:
    echo "      Phase 2: No orbital combat (no colony)"

  # 5. Apply losses to game state
  # Combine outcomes from both combat phases
  var allCombatFleets = spaceCombatFleets & orbitalCombatFleets
  var combinedOutcome: CombatResult
  if spaceCombatOutcome.totalRounds > 0:
    combinedOutcome = spaceCombatOutcome
  if orbitalCombatOutcome.totalRounds > 0:
    # Merge outcomes
    combinedOutcome.totalRounds += orbitalCombatOutcome.totalRounds
    for survivor in orbitalCombatOutcome.survivors:
      combinedOutcome.survivors.add(survivor)
    for retreated in orbitalCombatOutcome.retreated:
      if retreated notin combinedOutcome.retreated:
        combinedOutcome.retreated.add(retreated)
    for eliminated in orbitalCombatOutcome.eliminated:
      if eliminated notin combinedOutcome.eliminated:
        combinedOutcome.eliminated.add(eliminated)
    if orbitalCombatOutcome.victor.isSome:
      combinedOutcome.victor = orbitalCombatOutcome.victor

  let outcome = combinedOutcome
  # Collect surviving squadrons by ID
  var survivingSquadronIds: Table[SquadronId, CombatSquadron] = initTable[SquadronId, CombatSquadron]()
  for tf in outcome.survivors:
    for combatSq in tf.squadrons:
      survivingSquadronIds[combatSq.squadron.id] = combatSq

  # Update or remove fleets based on survivors
  for (fleetId, fleet) in fleetsAtSystem:
    # Mothballed fleets didn't participate in combat - handle separately
    if fleet.status == FleetStatus.Mothballed:
      continue

    var updatedSquadrons: seq[Squadron] = @[]

    for squadron in fleet.squadrons:
      if squadron.id in survivingSquadronIds:
        # Squadron survived - update crippled status
        let survivorState = survivingSquadronIds[squadron.id]
        var updatedSquadron = squadron
        updatedSquadron.flagship.isCrippled = (survivorState.state == CombatState.Crippled)
        updatedSquadrons.add(updatedSquadron)

    # Update fleet with surviving squadrons, or remove if none survived
    if updatedSquadrons.len > 0:
      state.fleets[fleetId] = Fleet(
        squadrons: updatedSquadrons,
        id: fleet.id,
        owner: fleet.owner,
        location: fleet.location,
        status: fleet.status  # Preserve status (Active/Reserve)
      )
    else:
      # Fleet destroyed
      state.fleets.del(fleetId)

  # Check if all defenders eliminated - if so, destroy mothballed ships
  # Per economy.md:3.9 - mothballed ships are vulnerable if no Task Force defends them
  if systemOwner.isSome:
    let defendingHouse = systemOwner.get()

    # Check if defending house has any surviving active/reserve squadrons
    var defenderHasSurvivors = false
    for tf in outcome.survivors:
      if tf.house == defendingHouse and tf.squadrons.len > 0:
        defenderHasSurvivors = true
        break

    # If no defenders survived at friendly colony, destroy screened units
    # Per operations.md - mothballed ships and spacelift ships vulnerable if no orbital units defend them
    if not defenderHasSurvivors:
      var mothballedFleetsDestroyed = 0
      var mothballedSquadronsDestroyed = 0
      var spaceliftShipsDestroyed = 0

      for (fleetId, fleet) in fleetsAtSystem:
        if fleet.owner == defendingHouse:
          # Destroy mothballed ships
          if fleet.status == FleetStatus.Mothballed:
            mothballedSquadronsDestroyed += fleet.squadrons.len
            mothballedFleetsDestroyed += 1
            # Destroy the fleet by removing all squadrons
            state.fleets[fleetId] = Fleet(
              squadrons: @[],  # Empty fleet
              spaceLiftShips: @[],
              id: fleet.id,
              owner: fleet.owner,
              location: fleet.location,
              status: FleetStatus.Mothballed
            )

          # Destroy spacelift ships in any fleet (they were screened by orbital units)
          if fleet.spaceLiftShips.len > 0:
            spaceliftShipsDestroyed += fleet.spaceLiftShips.len
            # Remove spacelift ships from fleet
            var updatedFleet = state.fleets[fleetId]
            updatedFleet.spaceLiftShips = @[]
            state.fleets[fleetId] = updatedFleet

      if mothballedFleetsDestroyed > 0:
        echo "      ", mothballedSquadronsDestroyed, " mothballed squadron(s) in ",
             mothballedFleetsDestroyed, " fleet(s) destroyed - no orbital defense remains"

      if spaceliftShipsDestroyed > 0:
        echo "      ", spaceliftShipsDestroyed, " spacelift ship(s) destroyed - no orbital defense remains"

  # Update starbases at colony based on survivors
  if systemOwner.isSome and systemId in state.colonies:
    var colony = state.colonies[systemId]
    var survivingStarbases: seq[Starbase] = @[]
    for starbase in colony.starbases:
      if starbase.id in survivingSquadronIds:
        # Starbase survived - update crippled status
        let survivorState = survivingSquadronIds[starbase.id]
        var updatedStarbase = starbase
        updatedStarbase.isCrippled = (survivorState.state == CombatState.Crippled)
        survivingStarbases.add(updatedStarbase)
    colony.starbases = survivingStarbases
    state.colonies[systemId] = colony

  # Update unassigned squadrons at colony based on survivors
  if systemOwner.isSome and systemId in state.colonies:
    var colony = state.colonies[systemId]
    var survivingUnassigned: seq[Squadron] = @[]
    for squadron in colony.unassignedSquadrons:
      if squadron.id in survivingSquadronIds:
        # Squadron survived - update crippled status
        let survivorState = survivingSquadronIds[squadron.id]
        var updatedSquadron = squadron
        updatedSquadron.flagship.isCrippled = (survivorState.state == CombatState.Crippled)
        survivingUnassigned.add(updatedSquadron)
    colony.unassignedSquadrons = survivingUnassigned
    state.colonies[systemId] = colony

  # 6. Determine attacker and defender houses for reporting
  var attackerHouses: seq[HouseId] = @[]
  var defenderHouses: seq[HouseId] = @[]
  var allHouses: seq[HouseId] = @[]

  for (fleetId, fleet) in fleetsAtSystem:
    if fleet.owner notin allHouses:
      allHouses.add(fleet.owner)
      if systemOwner.isSome and systemOwner.get() == fleet.owner:
        defenderHouses.add(fleet.owner)
      else:
        attackerHouses.add(fleet.owner)

  # 7. Count losses by house
  var houseLosses: Table[HouseId, int] = initTable[HouseId, int]()
  # Count total squadrons before combat (all fleets at system)
  for houseId in allHouses:
    var totalSquadrons = 0
    for (fleetId, fleet) in fleetsAtSystem:
      if fleet.owner == houseId:
        totalSquadrons += fleet.squadrons.len

    # Add starbases and unassigned squadrons to defender's total
    if systemOwner.isSome and systemOwner.get() == houseId and systemId in state.colonies:
      let colony = state.colonies[systemId]
      totalSquadrons += colony.starbases.len
      totalSquadrons += colony.unassignedSquadrons.len

    let survivingSquadrons = outcome.survivors.filterIt(it.house == houseId)
                                   .mapIt(it.squadrons.len).foldl(a + b, 0)
    houseLosses[houseId] = totalSquadrons - survivingSquadrons

  # 8. Generate combat report
  let victor = outcome.victor
  let attackerLosses = if attackerHouses.len > 0:
                         attackerHouses.mapIt(houseLosses.getOrDefault(it, 0)).foldl(a + b, 0)
                       else: 0
  let defenderLosses = if defenderHouses.len > 0:
                         defenderHouses.mapIt(houseLosses.getOrDefault(it, 0)).foldl(a + b, 0)
                       else: 0

  let report = CombatReport(
    systemId: systemId,
    attackers: attackerHouses,
    defenders: defenderHouses,
    attackerLosses: attackerLosses,
    defenderLosses: defenderLosses,
    victor: victor
  )
  combatReports.add(report)

  # Award prestige for combat
  if victor.isSome:
    let victorHouse = victor.get()
    let victorPrestige = getPrestigeValue(PrestigeSource.CombatVictory)
    state.houses[victorHouse].prestige += victorPrestige
    echo "      ", state.houses[victorHouse].name, " victory (+", victorPrestige, " prestige)"

    # Award prestige for squadrons destroyed
    let enemyLosses = if victorHouse in attackerHouses: defenderLosses else: attackerLosses
    if enemyLosses > 0:
      let squadronPrestige = getPrestigeValue(PrestigeSource.SquadronDestroyed) * enemyLosses
      state.houses[victorHouse].prestige += squadronPrestige
      echo "      ", state.houses[victorHouse].name, " destroyed ", enemyLosses, " squadrons (+", squadronPrestige, " prestige)"

  # Generate event
  let victorName = if victor.isSome: state.houses[victor.get()].name else: "No one"
  events.add(GameEvent(
    eventType: GameEventType.Battle,
    houseId: if victor.isSome: victor.get() else: "",
    description: "Battle at " & $systemId & ". Victor: " & victorName,
    systemId: some(systemId)
  ))

  echo "      Battle complete. Victor: ", victorName

proc resolveBombardment(state: var GameState, houseId: HouseId, order: FleetOrder,
                       events: var seq[GameEvent]) =
  ## Process planetary bombardment order (operations.md:7.5)
  ## Phase 2 of planetary combat - requires orbital supremacy
  ## Attacks planetary shields, ground batteries, and infrastructure
  # NOTE: Like resolveBattle(), this requires Squadron conversion
  # Bombardment system (ground.nim:329) needs seq[CombatSquadron]

  if order.targetSystem.isNone:
    return

  let targetId = order.targetSystem.get()

  # Validate fleet exists and is at target
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    echo "      Bombardment failed: fleet not found"
    return

  let fleet = fleetOpt.get()
  if fleet.location != targetId:
    echo "      Bombardment failed: fleet not at target system"
    return

  # Validate target colony exists
  if targetId notin state.colonies:
    echo "      Bombardment failed: no colony at target"
    return

  # Fleet now uses Squadrons - convert to CombatSquadrons
  var combatSquadrons: seq[CombatSquadron] = @[]
  for squadron in fleet.squadrons:
    let combatSq = CombatSquadron(
      squadron: squadron,
      state: if squadron.flagship.isCrippled: CombatState.Crippled else: CombatState.Undamaged,
      fleetStatus: fleet.status,  # Pass fleet status for reserve AS/DS penalty
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: getTargetBucket(squadron.flagship.shipClass),
      targetWeight: 1.0
    )
    combatSquadrons.add(combatSq)

  # Get colony's planetary defense
  let colony = state.colonies[targetId]

  # Build full PlanetaryDefense from colony data
  var defense = PlanetaryDefense()

  # Shields: Convert colony shield level to ShieldLevel object
  if colony.planetaryShieldLevel > 0:
    let (rollNeeded, blockPct) = getShieldData(colony.planetaryShieldLevel)
    defense.shields = some(ShieldLevel(
      level: colony.planetaryShieldLevel,
      blockChance: float(rollNeeded) / 20.0,  # Convert d20 roll to probability
      blockPercentage: blockPct
    ))
  else:
    defense.shields = none(ShieldLevel)

  # Ground Batteries: Create GroundUnit objects from colony count
  defense.groundBatteries = @[]
  let ownerCSTLevel = state.houses[colony.owner].techTree.levels.constructionTech
  for i in 0 ..< colony.groundBatteries:
    let battery = createGroundBattery(
      id = $targetId & "_GB" & $i,
      owner = colony.owner,
      techLevel = ownerCSTLevel  # Use colony owner's actual CST level
    )
    defense.groundBatteries.add(battery)

  # Ground Forces: Create GroundUnit objects from armies and marines
  defense.groundForces = @[]
  for i in 0 ..< colony.armies:
    let army = createArmy(
      id = $targetId & "_AA" & $i,
      owner = colony.owner
    )
    defense.groundForces.add(army)

  for i in 0 ..< colony.marines:
    let marine = createMarine(
      id = $targetId & "_MD" & $i,
      owner = colony.owner
    )
    defense.groundForces.add(marine)

  # Spaceports: Check if colony has any operational spaceports
  defense.spaceport = colony.spaceports.len > 0

  # Generate deterministic seed for bombardment (turn + target system)
  let bombardmentSeed = hash((state.turn, targetId)).int64

  # Conduct bombardment
  let result = conductBombardment(combatSquadrons, defense, seed = bombardmentSeed, maxRounds = 3)

  # Apply damage to colony
  var updatedColony = colony
  # Infrastructure damage from bombardment result
  # BombardmentResult.infrastructureDamage contains excess hits after destroying all defenses
  # Colony infrastructure is stored as 0-10, but game uses Industrial Units (IU)
  # 1 infrastructure level = 10 IU (per economy mapping)
  let infrastructureLoss = result.infrastructureDamage div 10  # Convert IU damage to infrastructure levels
  updatedColony.infrastructure -= infrastructureLoss
  if updatedColony.infrastructure < 0:
    updatedColony.infrastructure = 0

  # Ships-in-dock destruction (economy.md:5.0)
  # If infrastructure is damaged, ships under construction can be destroyed
  var shipsDestroyedInDock = false
  if infrastructureLoss > 0 and updatedColony.underConstruction.isSome:
    let project = updatedColony.underConstruction.get()
    if project.projectType == econ_types.ConstructionType.Ship:
      # Ship under construction is destroyed with NO refund (per economy.md:5.0)
      # Full cost was paid upfront, funds are lost when ship is destroyed
      updatedColony.underConstruction = none(econ_types.ConstructionProject)
      shipsDestroyedInDock = true
      echo "      Ship under construction destroyed in bombardment!"

  # Note: Spaceports are NOT damaged by bombardment
  # They are only vulnerable during orbital combat (when starbases/defending fleets are destroyed)
  # Mothballed ships are vulnerable when all defending active/reserve fleets are eliminated in orbital combat

  state.colonies[targetId] = updatedColony

  echo "      Bombardment at ", targetId, ": ", infrastructureLoss, " infrastructure destroyed"

  # Generate event
  var eventDesc = "Bombarded system " & $targetId & ", destroyed " & $infrastructureLoss & " infrastructure"
  if shipsDestroyedInDock:
    eventDesc &= " (ship under construction destroyed)"

  events.add(GameEvent(
    eventType: GameEventType.Bombardment,
    houseId: houseId,
    description: eventDesc,
    systemId: some(targetId)
  ))

proc resolveInvasion(state: var GameState, houseId: HouseId, order: FleetOrder,
                    events: var seq[GameEvent]) =
  ## Process planetary invasion order (operations.md:7.6)
  ## Phase 3 of planetary combat - requires all ground batteries destroyed
  ## Marines attack ground forces to capture colony

  if order.targetSystem.isNone:
    return

  let targetId = order.targetSystem.get()

  # Validate fleet exists and is at target
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    echo "      Invasion failed: fleet not found"
    return

  let fleet = fleetOpt.get()
  if fleet.location != targetId:
    echo "      Invasion failed: fleet not at target system"
    return

  # Validate target colony exists
  if targetId notin state.colonies:
    echo "      Invasion failed: no colony at target"
    return

  let colony = state.colonies[targetId]

  # Check if colony belongs to attacker (can't invade your own colony)
  if colony.owner == houseId:
    echo "      Invasion failed: cannot invade your own colony"
    return

  # Build attacking ground forces from spacelift ships (marines only)
  var attackingForces: seq[GroundUnit] = @[]
  for ship in fleet.spaceLiftShips:
    if ship.cargo.cargoType == CargoType.Marines and ship.cargo.quantity > 0:
      for i in 0 ..< ship.cargo.quantity:
        let marine = createMarine(
          id = $houseId & "_MD_" & $targetId & "_" & $i,
          owner = houseId
        )
        attackingForces.add(marine)

  if attackingForces.len == 0:
    echo "      Invasion failed: no marines in fleet"
    return

  # Build defending ground forces
  var defendingForces: seq[GroundUnit] = @[]
  for i in 0 ..< colony.armies:
    let army = createArmy(
      id = $targetId & "_AA_" & $i,
      owner = colony.owner
    )
    defendingForces.add(army)

  for i in 0 ..< colony.marines:
    let marine = createMarine(
      id = $targetId & "_MD_" & $i,
      owner = colony.owner
    )
    defendingForces.add(marine)

  # Build planetary defense
  var defense = PlanetaryDefense()

  # Shields
  if colony.planetaryShieldLevel > 0:
    let (rollNeeded, blockPct) = getShieldData(colony.planetaryShieldLevel)
    defense.shields = some(ShieldLevel(
      level: colony.planetaryShieldLevel,
      blockChance: float(rollNeeded) / 20.0,
      blockPercentage: blockPct
    ))

  # Ground Batteries (must be destroyed for invasion to proceed)
  let ownerCSTLevel = state.houses[colony.owner].techTree.levels.constructionTech
  for i in 0 ..< colony.groundBatteries:
    let battery = createGroundBattery(
      id = $targetId & "_GB" & $i,
      owner = colony.owner,
      techLevel = ownerCSTLevel
    )
    defense.groundBatteries.add(battery)

  # Check prerequisite: all ground batteries must be destroyed
  # Per operations.md:7.6, invasion requires bombardment to destroy ground batteries first
  if defense.groundBatteries.len > 0:
    echo "      Invasion failed: ", defense.groundBatteries.len, " ground batteries still operational (bombardment required first)"
    return

  # Ground forces already added above
  defense.groundForces = defendingForces

  # Spaceport
  defense.spaceport = colony.spaceports.len > 0

  # Generate deterministic seed
  let invasionSeed = hash((state.turn, targetId, houseId)).int64

  # Conduct invasion
  let result = conductInvasion(attackingForces, defendingForces, defense, invasionSeed)

  # Apply results
  var updatedColony = colony

  if result.success:
    # Invasion succeeded - colony captured
    echo "      Invasion SUCCESS: ", houseId, " captured ", targetId, " from ", colony.owner

    # Transfer ownership
    updatedColony.owner = houseId

    # Apply infrastructure damage (50% destroyed per operations.md:7.6.2)
    updatedColony.infrastructure = updatedColony.infrastructure div 2

    # Shields and spaceports destroyed on landing (per spec)
    updatedColony.planetaryShieldLevel = 0
    updatedColony.spaceports = @[]

    # Update ground forces
    # Attacker marines that survived become garrison
    let survivingMarines = attackingForces.len - result.attackerCasualties.len
    updatedColony.marines = survivingMarines
    updatedColony.armies = 0  # Defender armies all destroyed/disbanded

    # Unload marines from spacelift ships (they've landed)
    var updatedFleet = state.fleets[order.fleetId]
    for ship in updatedFleet.spaceLiftShips.mitems:
      if ship.cargo.cargoType == CargoType.Marines:
        discard ship.unloadCargo()
    state.fleets[order.fleetId] = updatedFleet

    # Prestige changes
    let attackerPrestige = getPrestigeValue(PrestigeSource.ColonySeized)
    state.houses[houseId].prestige += attackerPrestige
    echo "      ", houseId, " gains ", attackerPrestige, " prestige for capturing colony"

    # Defender loses prestige for colony loss
    let defenderPenalty = -attackerPrestige  # Equal but opposite
    state.houses[colony.owner].prestige += defenderPenalty
    echo "      ", colony.owner, " loses ", -defenderPenalty, " prestige for losing colony"

    # Generate event
    events.add(GameEvent(
      eventType: GameEventType.SystemCaptured,
      houseId: houseId,
      description: houseId & " captured colony at " & $targetId & " from " & colony.owner,
      systemId: some(targetId)
    ))
  else:
    # Invasion failed
    echo "      Invasion FAILED: ", colony.owner, " repelled ", houseId, " invasion at ", targetId

    # Update defender ground forces
    let survivingDefenders = defendingForces.len - result.defenderCasualties.len
    # Simplified: assume casualties distributed evenly between armies and marines
    let totalDefenders = colony.armies + colony.marines
    if totalDefenders > 0:
      let armyFraction = float(colony.armies) / float(totalDefenders)
      updatedColony.armies = int(float(survivingDefenders) * armyFraction)
      updatedColony.marines = survivingDefenders - updatedColony.armies

    # Attacker marines destroyed/retreated - unload survivors from spacelift ships
    let survivingAttackers = attackingForces.len - result.attackerCasualties.len
    var updatedFleet = state.fleets[order.fleetId]
    var marinesRemaining = survivingAttackers
    for ship in updatedFleet.spaceLiftShips.mitems:
      if ship.cargo.cargoType == CargoType.Marines and ship.cargo.quantity > 0:
        let unloaded = min(ship.cargo.quantity, marinesRemaining)
        ship.cargo.quantity -= unloaded
        marinesRemaining -= unloaded
        if ship.cargo.quantity == 0:
          ship.cargo.cargoType = CargoType.None
    state.fleets[order.fleetId] = updatedFleet

    # Generate event
    events.add(GameEvent(
      eventType: GameEventType.InvasionRepelled,
      houseId: colony.owner,
      description: colony.owner & " repelled " & houseId & " invasion at " & $targetId,
      systemId: some(targetId)
    ))

  state.colonies[targetId] = updatedColony

proc resolveBlitz(state: var GameState, houseId: HouseId, order: FleetOrder,
                 events: var seq[GameEvent]) =
  ## Process planetary blitz order (operations.md:7.6.2)
  ## Fast insertion variant - seizes assets intact but marines get 0.5x AS penalty
  ## Transports vulnerable to ground batteries during insertion

  if order.targetSystem.isNone:
    return

  let targetId = order.targetSystem.get()

  # Validate fleet exists and is at target
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    echo "      Blitz failed: fleet not found"
    return

  let fleet = fleetOpt.get()
  if fleet.location != targetId:
    echo "      Blitz failed: fleet not at target system"
    return

  # Validate target colony exists
  if targetId notin state.colonies:
    echo "      Blitz failed: no colony at target"
    return

  let colony = state.colonies[targetId]

  # Check if colony belongs to attacker
  if colony.owner == houseId:
    echo "      Blitz failed: cannot blitz your own colony"
    return

  # Build attacking fleet (squadrons needed for blitz vs ground batteries)
  var attackingFleet: seq[CombatSquadron] = @[]
  for squadron in fleet.squadrons:
    let combatSq = CombatSquadron(
      squadron: squadron,
      state: if squadron.flagship.isCrippled: CombatState.Crippled else: CombatState.Undamaged,
      fleetStatus: fleet.status,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: getTargetBucket(squadron.flagship.shipClass),
      targetWeight: 1.0
    )
    attackingFleet.add(combatSq)

  # Build attacking ground forces from spacelift ships (marines only)
  var attackingForces: seq[GroundUnit] = @[]
  for ship in fleet.spaceLiftShips:
    if ship.cargo.cargoType == CargoType.Marines and ship.cargo.quantity > 0:
      for i in 0 ..< ship.cargo.quantity:
        let marine = createMarine(
          id = $houseId & "_MD_" & $targetId & "_" & $i,
          owner = houseId
        )
        attackingForces.add(marine)

  if attackingForces.len == 0:
    echo "      Blitz failed: no marines in fleet"
    return

  # Build defending ground forces
  var defendingForces: seq[GroundUnit] = @[]
  for i in 0 ..< colony.armies:
    let army = createArmy(
      id = $targetId & "_AA_" & $i,
      owner = colony.owner
    )
    defendingForces.add(army)

  for i in 0 ..< colony.marines:
    let marine = createMarine(
      id = $targetId & "_MD_" & $i,
      owner = colony.owner
    )
    defendingForces.add(marine)

  # Build planetary defense
  var defense = PlanetaryDefense()

  # Shields
  if colony.planetaryShieldLevel > 0:
    let (rollNeeded, blockPct) = getShieldData(colony.planetaryShieldLevel)
    defense.shields = some(ShieldLevel(
      level: colony.planetaryShieldLevel,
      blockChance: float(rollNeeded) / 20.0,
      blockPercentage: blockPct
    ))

  # Ground Batteries (blitz fights through them unlike invasion)
  let ownerCSTLevel = state.houses[colony.owner].techTree.levels.constructionTech
  for i in 0 ..< colony.groundBatteries:
    let battery = createGroundBattery(
      id = $targetId & "_GB" & $i,
      owner = colony.owner,
      techLevel = ownerCSTLevel
    )
    defense.groundBatteries.add(battery)

  # Ground forces
  defense.groundForces = defendingForces

  # Spaceport
  defense.spaceport = colony.spaceports.len > 0

  # Generate deterministic seed
  let blitzSeed = hash((state.turn, targetId, houseId, "blitz")).int64

  # Conduct blitz
  let result = conductBlitz(attackingFleet, attackingForces, defense, blitzSeed)

  # Apply results
  var updatedColony = colony

  if result.success:
    # Blitz succeeded - colony captured with assets intact
    echo "      Blitz SUCCESS: ", houseId, " captured ", targetId, " from ", colony.owner, " (assets seized)"

    # Transfer ownership
    updatedColony.owner = houseId

    # NO infrastructure damage on blitz (assets seized intact per operations.md:7.6.2)
    # Shields, spaceports, ground batteries all seized intact

    # Update ground forces
    let survivingMarines = attackingForces.len - result.attackerCasualties.len
    updatedColony.marines = survivingMarines
    updatedColony.armies = 0

    # Unload marines from spacelift ships
    var updatedFleet = state.fleets[order.fleetId]
    for ship in updatedFleet.spaceLiftShips.mitems:
      if ship.cargo.cargoType == CargoType.Marines:
        discard ship.unloadCargo()
    state.fleets[order.fleetId] = updatedFleet

    # Prestige changes (blitz gets same prestige as invasion)
    let attackerPrestige = getPrestigeValue(PrestigeSource.ColonySeized)
    state.houses[houseId].prestige += attackerPrestige
    echo "      ", houseId, " gains ", attackerPrestige, " prestige for blitzing colony"

    # Defender loses prestige for colony loss
    let defenderPenalty = -attackerPrestige
    state.houses[colony.owner].prestige += defenderPenalty
    echo "      ", colony.owner, " loses ", -defenderPenalty, " prestige for losing colony"

    # Generate event
    events.add(GameEvent(
      eventType: GameEventType.ColonyCaptured,
      houseId: houseId,
      description: houseId & " blitzed colony at " & $targetId & " from " & colony.owner & " (assets seized)",
      systemId: some(targetId)
    ))
  else:
    # Blitz failed
    echo "      Blitz FAILED: ", colony.owner, " repelled ", houseId, " blitz at ", targetId

    # Update defender ground forces
    let survivingDefenders = defendingForces.len - result.defenderCasualties.len
    let totalDefenders = colony.armies + colony.marines
    if totalDefenders > 0:
      let armyFraction = float(colony.armies) / float(totalDefenders)
      updatedColony.armies = int(float(survivingDefenders) * armyFraction)
      updatedColony.marines = survivingDefenders - updatedColony.armies

    # Update ground batteries (some may have been destroyed)
    # TODO: Track which batteries were destroyed in blitz result

    # Attacker marines casualties - unload survivors
    let survivingAttackers = attackingForces.len - result.attackerCasualties.len
    var updatedFleet = state.fleets[order.fleetId]
    var marinesRemaining = survivingAttackers
    for ship in updatedFleet.spaceLiftShips.mitems:
      if ship.cargo.cargoType == CargoType.Marines and ship.cargo.quantity > 0:
        let unloaded = min(ship.cargo.quantity, marinesRemaining)
        ship.cargo.quantity -= unloaded
        marinesRemaining -= unloaded
        if ship.cargo.quantity == 0:
          ship.cargo.cargoType = CargoType.None
    state.fleets[order.fleetId] = updatedFleet

    # Generate event
    events.add(GameEvent(
      eventType: GameEventType.InvasionRepelled,
      houseId: colony.owner,
      description: colony.owner & " repelled " & houseId & " blitz at " & $targetId,
      systemId: some(targetId)
    ))

  state.colonies[targetId] = updatedColony

## Phase 4: Maintenance

proc processTerraformingProjects(state: var GameState, events: var seq[GameEvent]) =
  ## Process active terraforming projects for all houses
  ## Per economy.md Section 4.7

  for colonyId, colony in state.colonies.mpairs:
    if colony.activeTerraforming.isNone:
      continue

    let houseId = colony.owner
    if houseId notin state.houses:
      continue

    let house = state.houses[houseId]
    var project = colony.activeTerraforming.get()
    project.turnsRemaining -= 1

    if project.turnsRemaining <= 0:
      # Terraforming complete!
      # Convert int class number (1-7) back to PlanetClass enum (0-6)
      colony.planetClass = PlanetClass(project.targetClass - 1)
      colony.activeTerraforming = none(TerraformProject)

      let className = case project.targetClass
        of 1: "Extreme"
        of 2: "Desolate"
        of 3: "Hostile"
        of 4: "Harsh"
        of 5: "Benign"
        of 6: "Lush"
        of 7: "Eden"
        else: "Unknown"

      echo "    ", house.name, " completed terraforming of ", colonyId,
           " to ", className, " (class ", project.targetClass, ")"

      events.add(GameEvent(
        eventType: GameEventType.TerraformComplete,
        houseId: houseId,
        description: house.name & " completed terraforming colony " & $colonyId &
                    " to " & className,
        systemId: some(colonyId)
      ))
    else:
      echo "    ", house.name, " terraforming ", colonyId,
           ": ", project.turnsRemaining, " turn(s) remaining"
      # Update project
      colony.activeTerraforming = some(project)

proc resolveMaintenancePhase(state: var GameState, events: var seq[GameEvent]) =
  ## Phase 4: Upkeep, effect decrements, and diplomatic status updates
  echo "  [Maintenance Phase]"

  # Decrement ongoing espionage effect counters
  var remainingEffects: seq[esp_types.OngoingEffect] = @[]
  for effect in state.ongoingEffects:
    var updatedEffect = effect
    updatedEffect.turnsRemaining -= 1

    if updatedEffect.turnsRemaining > 0:
      remainingEffects.add(updatedEffect)
      echo "    Effect on ", updatedEffect.targetHouse, " expires in ",
           updatedEffect.turnsRemaining, " turn(s)"
    else:
      echo "    Effect on ", updatedEffect.targetHouse, " has expired"

  state.ongoingEffects = remainingEffects

  # Expire pending diplomatic proposals
  for proposal in state.pendingProposals.mitems:
    if proposal.status == dip_proposals.ProposalStatus.Pending:
      proposal.expiresIn -= 1

      if proposal.expiresIn <= 0:
        proposal.status = dip_proposals.ProposalStatus.Expired
        echo "    Proposal ", proposal.id, " expired (", proposal.proposer, " -> ", proposal.target, ")"

  # Clean up old proposals (keep 10 turn history)
  let currentTurn = state.turn
  state.pendingProposals.keepIf(proc(p: dip_proposals.PendingProposal): bool =
    p.status == dip_proposals.ProposalStatus.Pending or
    (currentTurn - p.submittedTurn) < 10
  )

  # Process Space Guild population transfers arriving this turn
  resolvePopulationArrivals(state, events)

  # Process active terraforming projects
  processTerraformingProjects(state, events)

  # Update diplomatic status timers for all houses
  for houseId, house in state.houses.mpairs:
    # Update dishonored status
    if house.dishonoredStatus.active:
      house.dishonoredStatus.turnsRemaining -= 1
      if house.dishonoredStatus.turnsRemaining <= 0:
        house.dishonoredStatus.active = false
        echo "    ", house.name, " is no longer dishonored"

    # Update diplomatic isolation
    if house.diplomaticIsolation.active:
      house.diplomaticIsolation.turnsRemaining -= 1
      if house.diplomaticIsolation.turnsRemaining <= 0:
        house.diplomaticIsolation.active = false
        echo "    ", house.name, " is no longer diplomatically isolated"

  # Convert colonies for maintenance phase
  var econColonies: seq[econ_types.Colony] = @[]
  for systemId, colony in state.colonies:
    econColonies.add(econ_types.Colony(
      systemId: colony.systemId,
      owner: colony.owner,
      populationUnits: colony.population,
      populationTransferUnits: 0,
      industrial: econ_types.IndustrialUnits(units: colony.infrastructure * 10),
      planetClass: colony.planetClass,
      resources: colony.resources,
      grossOutput: colony.production,
      taxRate: 50,
      underConstruction: none(econ_types.ConstructionProject),
      infrastructureDamage: 0.0
    ))

  # Build house fleet data
  var houseFleetData = initTable[HouseId, seq[(ShipClass, bool)]]()
  for houseId in state.houses.keys:
    houseFleetData[houseId] = @[]
    for fleet in state.getHouseFleets(houseId):
      for squadron in fleet.squadrons:
        # Get actual ship class and crippled status from squadron
        houseFleetData[houseId].add((squadron.flagship.shipClass, squadron.flagship.isCrippled))

  # Build house treasuries
  var houseTreasuries = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseTreasuries[houseId] = house.treasury

  # Call maintenance engine
  let maintenanceReport = econ_engine.resolveMaintenancePhase(
    econColonies,
    houseFleetData,
    houseTreasuries
  )

  # Apply results back to game state
  for houseId, upkeep in maintenanceReport.houseUpkeep:
    state.houses[houseId].treasury = houseTreasuries[houseId]
    echo "    ", state.houses[houseId].name, ": -", upkeep, " PP maintenance"

  # Report and handle completed projects
  for completed in maintenanceReport.completedProjects:
    echo "    Completed: ", completed.projectType, " at system ", completed.colonyId

    # Special handling for fighter squadrons
    if completed.projectType == econ_types.ConstructionType.Building and
       completed.itemId == "FighterSquadron":
      # Commission fighter squadron at colony
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Create new fighter squadron
        let fighterSq = FighterSquadron(
          id: $completed.colonyId & "-FS-" & $(colony.fighterSquadrons.len + 1),
          commissionedTurn: state.turn
        )

        colony.fighterSquadrons.add(fighterSq)
        state.colonies[completed.colonyId] = colony

        echo "      Commissioned fighter squadron ", fighterSq.id, " at ", completed.colonyId

        # Generate event
        events.add(GameEvent(
          eventType: GameEventType.ShipCommissioned,
          houseId: colony.owner,
          description: "Fighter Squadron commissioned at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for starbases
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Starbase":
      # Commission starbase at colony
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Create new starbase
        let starbase = Starbase(
          id: $completed.colonyId & "-SB-" & $(colony.starbases.len + 1),
          commissionedTurn: state.turn,
          isCrippled: false
        )

        colony.starbases.add(starbase)
        state.colonies[completed.colonyId] = colony

        echo "      Commissioned starbase ", starbase.id, " at ", completed.colonyId
        echo "        Total operational starbases: ", getOperationalStarbaseCount(colony)
        echo "        Growth bonus: ", int(getStarbaseGrowthBonus(colony) * 100.0), "%"

        # Generate event
        events.add(GameEvent(
          eventType: GameEventType.ShipCommissioned,
          houseId: colony.owner,
          description: "Starbase commissioned at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for spaceports
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Spaceport":
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Create new spaceport (5 docks per facilities_config.toml)
        let spaceport = Spaceport(
          id: $completed.colonyId & "-SP-" & $(colony.spaceports.len + 1),
          commissionedTurn: state.turn,
          docks: 5  # From facilities_config: spaceport.docks
        )

        colony.spaceports.add(spaceport)
        state.colonies[completed.colonyId] = colony

        echo "      Commissioned spaceport ", spaceport.id, " at ", completed.colonyId
        echo "        Total construction docks: ", getTotalConstructionDocks(colony)

        events.add(GameEvent(
          eventType: GameEventType.BuildingCompleted,
          houseId: colony.owner,
          description: "Spaceport commissioned at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for shipyards
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Shipyard":
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Validate spaceport prerequisite
        if not hasSpaceport(colony):
          echo "      ERROR: Shipyard construction failed - no spaceport at ", completed.colonyId
          # This shouldn't happen if build validation worked correctly
          continue

        # Create new shipyard (10 docks per facilities_config.toml)
        let shipyard = Shipyard(
          id: $completed.colonyId & "-SY-" & $(colony.shipyards.len + 1),
          commissionedTurn: state.turn,
          docks: 10,  # From facilities_config: shipyard.docks
          isCrippled: false
        )

        colony.shipyards.add(shipyard)
        state.colonies[completed.colonyId] = colony

        echo "      Commissioned shipyard ", shipyard.id, " at ", completed.colonyId
        echo "        Total construction docks: ", getTotalConstructionDocks(colony)

        events.add(GameEvent(
          eventType: GameEventType.BuildingCompleted,
          houseId: colony.owner,
          description: "Shipyard commissioned at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for ground batteries
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "GroundBattery":
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Add ground battery (instant construction, 1 turn)
        colony.groundBatteries += 1
        state.colonies[completed.colonyId] = colony

        echo "      Deployed ground battery at ", completed.colonyId
        echo "        Total ground defenses: ", getTotalGroundDefense(colony)

        events.add(GameEvent(
          eventType: GameEventType.BuildingCompleted,
          houseId: colony.owner,
          description: "Ground battery deployed at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for planetary shields (replacement, not upgrade)
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId.startsWith("PlanetaryShield"):
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Extract shield level from itemId (e.g., "PlanetaryShield-3" -> 3)
        # For now, assume sequential upgrades
        let newLevel = colony.planetaryShieldLevel + 1
        colony.planetaryShieldLevel = min(newLevel, 6)  # Max SLD6
        state.colonies[completed.colonyId] = colony

        echo "      Deployed planetary shield SLD", colony.planetaryShieldLevel, " at ", completed.colonyId
        echo "        Block chance: ", int(getShieldBlockChance(colony.planetaryShieldLevel) * 100.0), "%"

        events.add(GameEvent(
          eventType: GameEventType.BuildingCompleted,
          houseId: colony.owner,
          description: "Planetary Shield SLD" & $colony.planetaryShieldLevel & " deployed at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for Marines (MD)
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Marine":
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Get population cost from config
        let marinePopCost = globalGroundUnitsConfig.marine_division.population_cost
        const minViablePopulation = 1_000_000  # 1 PU minimum for colony viability

        if colony.souls < marinePopCost:
          echo "      WARNING: Colony ", completed.colonyId, " lacks population to recruit Marines (",
               colony.souls, " souls < ", marinePopCost, ")"
        elif colony.souls - marinePopCost < minViablePopulation:
          echo "      WARNING: Colony ", completed.colonyId, " cannot recruit Marines - would leave colony below minimum viable size (",
               colony.souls - marinePopCost, " < ", minViablePopulation, " souls)"
        else:
          colony.marines += 1  # Add 1 Marine Division
          colony.souls -= marinePopCost  # Deduct recruited souls
          colony.population = colony.souls div 1_000_000  # Update display population
          state.colonies[completed.colonyId] = colony

          echo "      Recruited Marine Division at ", completed.colonyId
          echo "        Total Marines: ", colony.marines, " MD (", colony.souls, " souls remaining)"

          events.add(GameEvent(
            eventType: GameEventType.UnitRecruited,
            houseId: colony.owner,
            description: "Marine Division recruited at " & $completed.colonyId & " (total: " & $colony.marines & " MD)",
            systemId: some(completed.colonyId)
          ))

    # Special handling for Armies (AA)
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Army":
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Get population cost from config
        let armyPopCost = globalGroundUnitsConfig.army.population_cost
        const minViablePopulation = 1_000_000  # 1 PU minimum for colony viability

        if colony.souls < armyPopCost:
          echo "      WARNING: Colony ", completed.colonyId, " lacks population to muster Army (",
               colony.souls, " souls < ", armyPopCost, ")"
        elif colony.souls - armyPopCost < minViablePopulation:
          echo "      WARNING: Colony ", completed.colonyId, " cannot muster Army - would leave colony below minimum viable size (",
               colony.souls - armyPopCost, " < ", minViablePopulation, " souls)"
        else:
          colony.armies += 1  # Add 1 Army Division
          colony.souls -= armyPopCost  # Deduct recruited souls
          colony.population = colony.souls div 1_000_000  # Update display population
          state.colonies[completed.colonyId] = colony

          echo "      Mustered Army Division at ", completed.colonyId
          echo "        Total Armies: ", colony.armies, " AA (", colony.souls, " souls remaining)"

          events.add(GameEvent(
            eventType: GameEventType.UnitRecruited,
            houseId: colony.owner,
            description: "Army Division mustered at " & $completed.colonyId & " (total: " & $colony.armies & " AA)",
            systemId: some(completed.colonyId)
          ))

    # Handle ship construction
    elif completed.projectType == econ_types.ConstructionType.Ship:
      if completed.colonyId in state.colonies:
        let colony = state.colonies[completed.colonyId]
        let owner = colony.owner

        # Parse ship class from itemId
        try:
          let shipClass = parseEnum[ShipClass](completed.itemId)
          let techLevel = state.houses[owner].techTree.levels.weaponsTech

          # Create the ship
          let ship = newEnhancedShip(shipClass, techLevel)

          # Find squadrons at this system belonging to this house
          var assignedSquadron: SquadronId = ""
          for fleetId, fleet in state.fleets:
            if fleet.owner == owner and fleet.location == completed.colonyId:
              for squadron in fleet.squadrons:
                if canAddShip(squadron, ship):
                  # Found a squadron with capacity
                  assignedSquadron = squadron.id
                  break
              if assignedSquadron != "":
                break

          # Add ship to existing squadron or create new one
          if assignedSquadron != "":
            # Add to existing squadron
            for fleetId, fleet in state.fleets.mpairs:
              if fleet.owner == owner:
                for squadron in fleet.squadrons.mitems:
                  if squadron.id == assignedSquadron:
                    discard addShip(squadron, ship)
                    echo "      Commissioned ", shipClass, " and assigned to squadron ", squadron.id
                    break

          else:
            # Create new squadron with this ship as flagship
            let newSquadronId = $owner & "_sq_" & $state.fleets.len & "_" & $state.turn
            let newSq = newSquadron(ship, newSquadronId, owner, completed.colonyId)

            # Find or create fleet at this location
            var targetFleetId = ""
            for fleetId, fleet in state.fleets:
              if fleet.owner == owner and fleet.location == completed.colonyId:
                targetFleetId = fleetId
                break

            if targetFleetId == "":
              # Create new fleet at colony
              targetFleetId = $owner & "_fleet" & $(state.fleets.len + 1)
              state.fleets[targetFleetId] = Fleet(
                id: targetFleetId,
                owner: owner,
                location: completed.colonyId,
                squadrons: @[newSq]
              )
              echo "      Commissioned ", shipClass, " in new fleet ", targetFleetId
            else:
              # Add squadron to existing fleet
              state.fleets[targetFleetId].squadrons.add(newSq)
              echo "      Commissioned ", shipClass, " in new squadron ", newSq.id

          # Generate event
          events.add(GameEvent(
            eventType: GameEventType.ShipCommissioned,
            houseId: owner,
            description: $shipClass & " commissioned at " & $completed.colonyId,
            systemId: some(completed.colonyId)
          ))

        except ValueError:
          echo "      ERROR: Invalid ship class: ", completed.itemId

  # Check for elimination and defensive collapse
  let gameplayConfig = globalGameplayConfig
  for houseId, house in state.houses:
    # Standard elimination: no colonies and no fleets
    let colonies = state.getHouseColonies(houseId)
    let fleets = state.getHouseFleets(houseId)

    if colonies.len == 0 and fleets.len == 0:
      state.houses[houseId].eliminated = true
      events.add(GameEvent(
        eventType: GameEventType.HouseEliminated,
        houseId: houseId,
        description: house.name & " has been eliminated!",
        systemId: none(SystemId)
      ))
      echo "    ", house.name, " eliminated!"
      continue

    # Defensive collapse: prestige < threshold for consecutive turns
    if house.prestige < gameplayConfig.elimination.defensive_collapse_threshold:
      state.houses[houseId].negativePrestigeTurns += 1
      echo "    ", house.name, " at risk: prestige ", house.prestige,
           " (", state.houses[houseId].negativePrestigeTurns, "/",
           gameplayConfig.elimination.defensive_collapse_turns, " turns until elimination)"

      if state.houses[houseId].negativePrestigeTurns >= gameplayConfig.elimination.defensive_collapse_turns:
        state.houses[houseId].eliminated = true
        events.add(GameEvent(
          eventType: GameEventType.HouseEliminated,
          houseId: houseId,
          description: house.name & " has collapsed from negative prestige!",
          systemId: none(SystemId)
        ))
        echo "    ", house.name, " eliminated by defensive collapse!"
    else:
      # Reset counter when prestige recovers
      state.houses[houseId].negativePrestigeTurns = 0

  # Check squadron limits (military.toml)
  echo "  Checking squadron limits..."
  for houseId, house in state.houses:
    if house.eliminated:
      continue

    let current = state.getHouseSquadronCount(houseId)
    let limit = state.getSquadronLimit(houseId)
    let totalPU = state.getHousePopulationUnits(houseId)

    if current > limit:
      echo "    WARNING: ", house.name, " over squadron limit!"
      echo "      Current: ", current, " squadrons, Limit: ", limit, " (", totalPU, " PU)"
      # Note: In full implementation, this would trigger grace period timer
      # and eventual auto-disband per military.toml:capacity_violation_grace_period
    elif current == limit:
      echo "    ", house.name, ": At squadron limit (", current, "/", limit, ")"
    else:
      echo "    ", house.name, ": ", current, "/", limit, " squadrons (", totalPU, " PU)"

  # Check fighter squadron capacity violations (assets.md:2.4.1)
  echo "  Checking fighter squadron capacity..."
  let militaryConfig = globalMilitaryConfig.fighter_mechanics

  for systemId, colony in state.colonies.mpairs:
    let house = state.houses[colony.owner]
    if house.eliminated:
      continue

    # Get FD multiplier from house tech level
    let fdMultiplier = getFighterDoctrineMultiplier(house.techTree.levels)

    # Check current capacity
    let current = getCurrentFighterCount(colony)
    let capacity = getFighterCapacity(colony, fdMultiplier)
    let popCapacity = getFighterPopulationCapacity(colony, fdMultiplier)
    let infraCapacity = getFighterInfrastructureCapacity(colony)

    # Check if over capacity
    let isOverCapacity = current > capacity

    if isOverCapacity:
      # Determine violation type
      let violationType = if popCapacity < current:
        "population"
      elif infraCapacity < current:
        "infrastructure"
      else:
        "unknown"

      # Start or continue violation
      if not colony.capacityViolation.active:
        # New violation - start grace period
        colony.capacityViolation = CapacityViolation(
          active: true,
          violationType: violationType,
          turnsRemaining: militaryConfig.capacity_violation_grace_period,
          violationTurn: state.turn
        )
        echo "    WARNING: ", house.name, " - System ", systemId, " over fighter capacity!"
        echo "      Current: ", current, " FS, Capacity: ", capacity,
             " (Pop: ", popCapacity, ", Infra: ", infraCapacity, ")"
        echo "      Violation type: ", violationType
        echo "      Grace period: ", militaryConfig.capacity_violation_grace_period, " turns"
      else:
        # Existing violation - decrement timer
        colony.capacityViolation.turnsRemaining -= 1
        echo "    ", house.name, " - System ", systemId, " capacity violation continues"
        echo "      Current: ", current, " FS, Capacity: ", capacity
        echo "      Grace period remaining: ", colony.capacityViolation.turnsRemaining, " turn(s)"

        # Check if grace period expired
        if colony.capacityViolation.turnsRemaining <= 0:
          # Auto-disband excess fighters (oldest first)
          let excess = current - capacity
          echo "      Grace period expired! Auto-disbanding ", excess, " excess fighter squadron(s)"

          # Remove oldest squadrons first
          for i in 0..<excess:
            if colony.fighterSquadrons.len > 0:
              let disbanded = colony.fighterSquadrons[0]
              colony.fighterSquadrons.delete(0)
              echo "        Disbanded: ", disbanded.id

          # Clear violation
          colony.capacityViolation = CapacityViolation(
            active: false,
            violationType: "",
            turnsRemaining: 0,
            violationTurn: 0
          )

          # Generate event
          events.add(GameEvent(
            eventType: GameEventType.UnitDisbanded,
            houseId: colony.owner,
            description: $excess & " fighter squadrons auto-disbanded at " & $systemId & " (capacity violation)",
            systemId: some(systemId)
          ))

    elif colony.capacityViolation.active:
      # Was in violation but now resolved
      echo "    ", house.name, " - System ", systemId, " capacity violation resolved!"
      colony.capacityViolation = CapacityViolation(
        active: false,
        violationType: "",
        turnsRemaining: 0,
        violationTurn: 0
      )
    elif current > 0:
      # Normal status report
      echo "    ", house.name, " - System ", systemId, ": ", current, "/", capacity,
           " FS (Pop: ", popCapacity, ", Infra: ", infraCapacity, ")"

  # Process tech advancements on upgrade turns
  # Per economy.md:4.1: Levels purchased on turns 1 and 7 (bi-annual)
  if isUpgradeTurn(state.turn):
    echo "  Tech Advancement (Upgrade Turn)"
    for houseId, house in state.houses.mpairs:
      # Try to advance Economic Level (EL) with accumulated ERP
      let currentEL = house.techTree.levels.economicLevel
      let elAdv = attemptELAdvancement(house.techTree, currentEL)
      if elAdv.isSome:
        let adv = elAdv.get()
        echo "    ", house.name, ": EL ", adv.fromLevel, " → ", adv.toLevel,
             " (spent ", adv.cost, " ERP)"
        if adv.prestigeEvent.isSome:
          house.prestige += adv.prestigeEvent.get().amount
          echo "      +", adv.prestigeEvent.get().amount, " prestige"
        events.add(GameEvent(
          eventType: GameEventType.TechAdvance,
          houseId: houseId,
          description: &"Economic Level advanced to {adv.toLevel}",
          systemId: none(SystemId)
        ))

      # Try to advance Science Level (SL) with accumulated SRP
      let currentSL = house.techTree.levels.scienceLevel
      let slAdv = attemptSLAdvancement(house.techTree, currentSL)
      if slAdv.isSome:
        let adv = slAdv.get()
        echo "    ", house.name, ": SL ", adv.fromLevel, " → ", adv.toLevel,
             " (spent ", adv.cost, " SRP)"
        if adv.prestigeEvent.isSome:
          house.prestige += adv.prestigeEvent.get().amount
          echo "      +", adv.prestigeEvent.get().amount, " prestige"
        events.add(GameEvent(
          eventType: GameEventType.TechAdvance,
          houseId: houseId,
          description: &"Science Level advanced to {adv.toLevel}",
          systemId: none(SystemId)
        ))

      # Try to advance technology fields with accumulated TRP
      for field in [TechField.ConstructionTech, TechField.WeaponsTech,
                    TechField.TerraformingTech, TechField.ElectronicIntelligence,
                    TechField.CounterIntelligence]:
        let advancement = attemptTechAdvancement(house.techTree, field)
        if advancement.isSome:
          let adv = advancement.get()
          echo "    ", house.name, ": ", field, " ", adv.fromLevel, " → ", adv.toLevel,
               " (spent ", adv.cost, " TRP)"

          # Apply prestige if available
          if adv.prestigeEvent.isSome:
            house.prestige += adv.prestigeEvent.get().amount
            echo "      +", adv.prestigeEvent.get().amount, " prestige"

          # Generate event
          events.add(GameEvent(
            eventType: GameEventType.TechAdvance,
            houseId: houseId,
            description: &"{field} advanced to level {adv.toLevel}",
            systemId: none(SystemId)
          ))

  # Check victory condition
  let victorOpt = state.checkVictoryCondition()
  if victorOpt.isSome:
    let victorId = victorOpt.get()
    state.phase = GamePhase.Completed

    # Find victor by house id (handle case where table key != house.id)
    var victorName = "Unknown"
    for houseId, house in state.houses:
      if house.id == victorId:
        victorName = house.name
        break

    echo "  *** ", victorName, " has won the game! ***"
