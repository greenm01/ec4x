## Turn resolution engine - the heart of EC4X gameplay
##
## OFFLINE GAMEPLAY SYSTEM - No network dependencies
## This module is designed to work standalone for local/hotseat multiplayer
## Network transport (Nostr) wraps around this engine without modifying it

import std/[tables, algorithm, options, random, strformat, sequtils, strutils, hashes]
import ../common/[hex, types/core, types/combat, types/tech, types/units]
import gamestate, orders, fleet, ship, starmap, squadron
import economy/[types as econ_types, engine as econ_engine, construction, maintenance]
import research/[types as res_types, advancement]
import espionage/[types as esp_types, engine as esp_engine]
import diplomacy/[types as dip_types, engine as dip_engine]
import colonization/engine as col_engine
import combat/[engine as combat_engine, types as combat_types, ground]
import config/[prestige_config, espionage_config, gameplay_config, construction_config, military_config]
import commands/executor
import blockade/engine as blockade_engine
import intelligence/detection
import prestige

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
    ColonyEstablished, SystemCaptured, BattleOccurred, Battle, Bombardment,
    TechAdvance, FleetDestroyed, HouseEliminated

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
proc resolveMovementOrder*(state: var GameState, houseId: HouseId, order: FleetOrder,
                         events: var seq[GameEvent])
proc resolveColonizationOrder(state: var GameState, houseId: HouseId, order: FleetOrder,
                              events: var seq[GameEvent])
proc resolveBattle(state: var GameState, systemId: SystemId,
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
      # Check if any are at war
      # TODO: Check diplomatic relations
      # For now, assume all non-allied fleets fight
      combatSystems.add(systemId)

  # Resolve battles in each system
  for systemId in combatSystems:
    resolveBattle(state, systemId, combatReports, events)

  # Process espionage actions (per gameplay.md:1.3.1 - resolved in Conflict Phase)
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]

      # Process espionage action if present (max 1 per turn per diplomacy.md:8.2)
      if packet.espionageAction.isSome:
        let attempt = packet.espionageAction.get()

        # Get target's CIC level from tech tree (starts at CIC1 per gameplay.md:1.2)
        let targetCICLevel = case state.houses[attempt.target].techTree.levels.counterIntelligence
          of 0: esp_types.CICLevel.CIC0
          of 1: esp_types.CICLevel.CIC1
          of 2: esp_types.CICLevel.CIC2
          of 3: esp_types.CICLevel.CIC3
          of 4: esp_types.CICLevel.CIC4
          else: esp_types.CICLevel.CIC5
        let targetCIP = if attempt.target in state.houses:
                          state.houses[attempt.target].espionageBudget.cipPoints
                        else:
                          0

        # Execute espionage action with detection roll
        var rng = initRand(state.turn + attempt.attacker.hash() + attempt.target.hash())
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
              state.houses[attempt.target].techTree.researchPoints =
                max(0, state.houses[attempt.target].techTree.researchPoints - result.srpStolen)
              state.houses[attempt.attacker].techTree.researchPoints += result.srpStolen
              echo "      Stole ", result.srpStolen, " SRP from ", attempt.target

        else:
          echo "    ", attempt.attacker, " espionage DETECTED by ", attempt.target
          # Apply detection prestige penalties
          for prestigeEvent in result.attackerPrestigeEvents:
            state.houses[attempt.attacker].prestige += prestigeEvent.amount

  # Process bombardment orders (damages infrastructure before income phase)
  for houseId in state.houses.keys:
    if houseId in orders:
      for order in orders[houseId].fleetOrders:
        if order.orderType == FleetOrderType.Bombard:
          resolveBombardment(state, houseId, order, events)

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
          echo "    Starbase at system ", effect.targetSystem.get(), " is crippled"

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

          # Check for over-investment penalty (> 5% of turn budget)
          let turnBudget = state.houses[houseId].espionageBudget.turnBudget
          if turnBudget > 0:
            let totalInvestment = ebpCost + cipCost
            let investmentPercent = (totalInvestment * 100) div turnBudget

            if investmentPercent > 5:
              let prestigePenalty = -(investmentPercent - 5)
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
          # TODO: Check for actual starbase presence in colony
          # For now, assume all colonies have detection capability
          hasStarbase = false  # Will be true when we track starbases

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
      # TODO: Generate intelligence reports based on mission type
      survivingScouts[scoutId] = scout

      case scout.mission
      of SpyMissionType.SpyOnPlanet:
        echo "    Spy scout ", scoutId, " gathering planetary intelligence at system ", scoutLocation
      of SpyMissionType.HackStarbase:
        echo "    Spy scout ", scoutId, " hacking starbase at system ", scoutLocation
      of SpyMissionType.SpyOnSystem:
        echo "    Spy scout ", scoutId, " conducting system surveillance at ", scoutLocation

  # Update spy scouts in game state (remove detected ones)
  state.spyScouts = survivingScouts

  # Convert GameState colonies to economy engine format
  var econColonies: seq[econ_types.Colony] = @[]
  for systemId, colony in state.colonies:
    # Apply blockade penalty to production
    # Per operations.md:6.2.6: "Colonies under blockade reduce their GCO by 60%"
    let blockadePenalty = blockade_engine.getBlockadePenalty(colony)
    let adjustedProduction = int(float(colony.production) * blockadePenalty)

    if colony.blockaded:
      let blockadersStr = colony.blockadedBy.join(", ")
      echo "    Colony at system ", systemId, " blockaded by [", blockadersStr,
           "]: GCO reduced from ", colony.production, " to ", adjustedProduction, " (-60%)"

    # Convert Colony to economy Colony type
    econColonies.add(econ_types.Colony(
      systemId: colony.systemId,
      owner: colony.owner,
      populationUnits: colony.population,  # Map population (millions) to PU
      populationTransferUnits: 0,  # TODO: Track PTU separately
      industrial: econ_types.IndustrialUnits(units: colony.infrastructure * 10),  # Map infrastructure to IU
      planetClass: colony.planetClass,
      resources: colony.resources,
      grossOutput: adjustedProduction,  # Apply blockade penalty
      taxRate: 50,  # TODO: Get from house tax policy
      underConstruction: none(econ_types.ConstructionProject),  # TODO: Convert construction
      infrastructureDamage: 0.0  # TODO: Track damage from combat
    ))

  # Build house tax policies (TODO: store in House)
  var houseTaxPolicies = initTable[HouseId, econ_types.TaxPolicy]()
  for houseId in state.houses.keys:
    houseTaxPolicies[houseId] = econ_types.TaxPolicy(
      currentRate: 50,  # Default
      history: @[50]
    )

  # Build house tech levels
  var houseTechLevels = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseTechLevels[houseId] = house.techTree.levels.energyLevel  # TODO: Use actual EL

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

  # Apply research prestige from tech advancements (if any occurred)
  # Note: Tech advancements are tracked separately and applied here
  # TODO: Integrate with full research system when implemented
  # For now, research prestige is embedded in advancement events

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

  # Process diplomatic actions (per gameplay.md:1.3.3 - Command Phase)
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]

      for action in packet.diplomaticActions:
        case action.actionType
        of DiplomaticActionType.ProposeNonAggressionPact:
          # TODO: Implement pact proposal system (requires acceptance/rejection)
          echo "    ", houseId, " proposed Non-Aggression Pact to ", action.targetHouse
          # For now, auto-accept pacts (AI decision making deferred)
          if action.targetHouse in state.houses and not state.houses[action.targetHouse].eliminated:
            # Proposer establishes pact on their side
            let eventOpt1 = dip_engine.proposePact(
              state.houses[houseId].diplomaticRelations,
              action.targetHouse,
              state.houses[houseId].violationHistory,
              state.turn
            )
            # Target accepts (auto-accept for now)
            let eventOpt2 = dip_engine.proposePact(
              state.houses[action.targetHouse].diplomaticRelations,
              houseId,
              state.houses[action.targetHouse].violationHistory,
              state.turn
            )
            if eventOpt1.isSome and eventOpt2.isSome:
              echo "      Pact established"
            else:
              echo "      Pact proposal failed (blocked by isolation or cooldown)"

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
          eventType: GameEventType.Battle,  # TODO: Add more specific event types
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
      updatedColony.underConstruction = some(gamestate.ConstructionProject(
        projectType: gamestate.BuildingType.Shipyard,  # Placeholder - BuildingType not aligned with construction types yet
        turnsRemaining: project.turnsRemaining,
        cost: project.costTotal
      ))
      state.colonies[order.colonySystem] = updatedColony

      echo "      Started construction at system ", order.colonySystem, ": ", projectDesc
      echo "        Cost: ", project.costTotal, " PP, Est. ", project.turnsRemaining, " turns"

      # Generate event
      events.add(GameEvent(
        eventType: GameEventType.ColonyEstablished,  # TODO: Add ConstructionStarted event type
        houseId: packet.houseId,
        description: "Started " & projectDesc & " at system " & $order.colonySystem,
        systemId: some(order.colonySystem)
      ))
    else:
      echo "      Construction start failed at system ", order.colonySystem

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

  # Get colony info from game state
  let colony = createHomeColony(targetId, houseId)

  # Use colonization engine to establish with prestige
  let result = col_engine.establishColony(
    houseId,
    targetId,
    colony.planetClass,
    colony.resources,
    50  # Starting PTU
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

proc resolveBattle(state: var GameState, systemId: SystemId,
                  combatReports: var seq[CombatReport], events: var seq[GameEvent]) =
  ## Resolve space battle in a system
  echo "    Battle at ", systemId

  # 1. Gather all fleets at this system
  var fleetsAtSystem: seq[(FleetId, Fleet)] = @[]
  for fleetId, fleet in state.fleets:
    if fleet.location == systemId:
      fleetsAtSystem.add((fleetId, fleet))

  if fleetsAtSystem.len < 2:
    # Need at least 2 fleets for combat
    return

  # 2. Determine system ownership for attacker/defender grouping
  let systemOwner = if systemId in state.colonies:
                      some(state.colonies[systemId].owner)
                    else:
                      none(HouseId)

  # 3. Group fleets by house (multiple fleets per house combine into one Task Force)
  var houseFleets: Table[HouseId, seq[Fleet]] = initTable[HouseId, seq[Fleet]]()
  for (fleetId, fleet) in fleetsAtSystem:
    if fleet.owner notin houseFleets:
      houseFleets[fleet.owner] = @[]
    houseFleets[fleet.owner].add(fleet)

  # 4. Check if there's actual conflict (need at least 2 different houses)
  if houseFleets.len < 2:
    return

  # 5. Build Task Forces for combat (Fleet now uses Squadrons!)
  var taskForces: Table[HouseId, TaskForce] = initTable[HouseId, TaskForce]()

  for houseId, fleets in houseFleets:
    # Convert all house fleets to CombatSquadrons
    var combatSquadrons: seq[CombatSquadron] = @[]

    for fleet in fleets:
      for squadron in fleet.squadrons:
        # Wrap Squadron in CombatSquadron
        let combatSq = CombatSquadron(
          squadron: squadron,
          state: if squadron.flagship.isCrippled: CombatState.Crippled else: CombatState.Undamaged,
          damageThisTurn: 0,
          crippleRound: 0,
          bucket: getTargetBucket(squadron.flagship.shipClass),
          targetWeight: 1.0
        )
        combatSquadrons.add(combatSq)

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

  # 6. Determine attacker and defender
  var attackerHouses: seq[HouseId] = @[]
  var defenderHouses: seq[HouseId] = @[]

  for houseId in taskForces.keys:
    if systemOwner.isSome and systemOwner.get() == houseId:
      defenderHouses.add(houseId)
    else:
      attackerHouses.add(houseId)

  # If no clear defender, first house is defender
  if defenderHouses.len == 0 and attackerHouses.len > 0:
    defenderHouses.add(attackerHouses[0])
    attackerHouses.delete(0)

  # 7. Create battle context and resolve
  # Collect all task forces for battle
  var allTaskForces: seq[TaskForce] = @[]
  for houseId, tf in taskForces:
    allTaskForces.add(tf)

  var battleContext = BattleContext(
    systemId: systemId,
    taskForces: allTaskForces,
    seed: 0,  # TODO: Use deterministic seed from game state
    maxRounds: 20
  )

  # Execute battle
  let outcome = combat_engine.resolveCombat(battleContext)

  # 8. Apply losses to game state
  # Collect surviving squadrons by ID
  var survivingSquadronIds: Table[SquadronId, CombatSquadron] = initTable[SquadronId, CombatSquadron]()
  for tf in outcome.survivors:
    for combatSq in tf.squadrons:
      survivingSquadronIds[combatSq.squadron.id] = combatSq

  # Update or remove fleets based on survivors
  for (fleetId, fleet) in fleetsAtSystem:
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
        location: fleet.location
      )
    else:
      # Fleet destroyed
      state.fleets.del(fleetId)

  # 9. Count losses by house
  var houseLosses: Table[HouseId, int] = initTable[HouseId, int]()
  for houseId, fleets in houseFleets:
    let totalSquadrons = fleets.mapIt(it.squadrons.len).foldl(a + b, 0)
    let survivingSquadrons = outcome.survivors.filterIt(it.house == houseId)
                                   .mapIt(it.squadrons.len).foldl(a + b, 0)
    houseLosses[houseId] = totalSquadrons - survivingSquadrons

  # 10. Generate combat report
  let victor = outcome.victor
  let attackerLosses = attackerHouses.mapIt(houseLosses.getOrDefault(it, 0)).foldl(a + b, 0)
  let defenderLosses = defenderHouses.mapIt(houseLosses.getOrDefault(it, 0)).foldl(a + b, 0)

  let report = CombatReport(
    systemId: systemId,
    attackers: attackerHouses,
    defenders: defenderHouses,
    attackerLosses: attackerLosses,
    defenderLosses: defenderLosses,
    victor: victor
  )
  combatReports.add(report)

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
  ## Process orbital bombardment order
  # NOTE: Like resolveBattle(), this requires Squadron conversion
  # Bombardment system (ground.nim:329) needs seq[CombatSquadron]
  # Current Fleet has seq[Ship] without combat stats

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
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: getTargetBucket(squadron.flagship.shipClass),
      targetWeight: 1.0
    )
    combatSquadrons.add(combatSq)

  # Get colony's planetary defense
  let colony = state.colonies[targetId]
  # TODO: Build full PlanetaryDefense from colony data
  var defense = PlanetaryDefense(
    shields: none(ShieldLevel),
    groundBatteries: @[],  # TODO: Get from colony
    groundForces: @[],  # TODO: Get from colony military units
    spaceport: false
  )

  # Conduct bombardment
  let result = conductBombardment(combatSquadrons, defense, seed = 0, maxRounds = 3)

  # Apply damage to colony
  var updatedColony = colony
  # Infrastructure damage from bombardment result
  # Note: BombardmentResult returns detailed round-by-round data
  # For now, count destroyed infrastructure units from final state
  let infrastructureLoss = 1  # TODO: Calculate from result
  updatedColony.infrastructure -= infrastructureLoss
  if updatedColony.infrastructure < 0:
    updatedColony.infrastructure = 0

  state.colonies[targetId] = updatedColony

  echo "      Bombardment at ", targetId, ": ", infrastructureLoss, " infrastructure destroyed"

  # Generate event
  events.add(GameEvent(
    eventType: GameEventType.Bombardment,
    houseId: houseId,
    description: "Bombarded system " & $targetId & ", destroyed " & $infrastructureLoss & " infrastructure",
    systemId: some(targetId)
  ))

## Phase 4: Maintenance

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
          eventType: GameEventType.ColonyEstablished,  # TODO: Add FighterCommissioned event type
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
          eventType: GameEventType.ColonyEstablished,  # TODO: Add StarbaseCommissioned event type
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
          eventType: GameEventType.ColonyEstablished,
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
          eventType: GameEventType.ColonyEstablished,
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
          eventType: GameEventType.ColonyEstablished,
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
          eventType: GameEventType.ColonyEstablished,
          houseId: colony.owner,
          description: "Planetary Shield SLD" & $colony.planetaryShieldLevel & " deployed at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

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
            eventType: GameEventType.ColonyEstablished,  # TODO: Add FighterDisbanded event type
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
