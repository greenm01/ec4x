## Domestikos Module - Strategic Fleet Rebalancing
##
## Byzantine Domestikos (δομέστικος) - Commander of Imperial Forces
##
## The Domestikos provides tactical judgment for fleet operations:
## - Fleet utilization analysis
## - Act-specific fleet reorganization (split in Act 1, merge in Act 2+)
## - Smart defensive consolidation (no suicide attacks)
## - Opportunistic counter-attacks against vulnerable enemies
## - Probing attacks for intelligence gathering
##
## Integration: Called after logistics in orders.nim

import std/[options, tables, strformat]
import ../../common/types/core
import ../../engine/[gamestate, fog_of_war, fleet, order_types, standing_orders, logger]
import ../common/types as ai_types  # For GameAct
import ./controller_types
import ./config

# Core types for Domestikos module
type
  FleetUtilization* {.pure.} = enum
    Idle           # No orders, available for rebalancing
    UnderUtilized  # 1-2 ships, could split for efficiency
    Optimal        # Well-utilized for current objective
    OverUtilized   # Too many ships for mission, could split
    Tactical       # Assigned to tactical/logistics, don't touch

  FleetAnalysis* = object
    fleetId*: FleetId
    shipCount*: int
    utilization*: FleetUtilization
    hasScouts*: bool
    hasETACs*: bool
    hasCombatShips*: bool
    location*: SystemId

  DomestikosStrategy* {.pure.} = enum
    SplitForExploration    # Act 1: Maximize map coverage
    MergeForCombat         # Act 2+: Concentrate forces
    MaintainFormations     # Act 3+: Preserve battle groups
    ProbingAttacks         # When fleets at Rendezvous need intel
    DefensiveConsolidation # When under threat: merge weak fleets
    OpportunisticCounter   # When enemy vulnerable: organize counter-attack

# Forward declare module exports to avoid circular imports
# Note: Sub-modules will import these types directly from this file

# Now import sub-modules (they will see our type definitions)
import ./domestikos/[fleet_analysis, defensive_ops, offensive_ops, staging, build_requirements, exploration_ops, fleet_management]

# Export build_requirements functions for Domestikos-Treasurer feedback loop
export build_requirements.reprioritizeRequirements
# Export fleet_management for ZeroTurnCommand operations
export fleet_management.generateFleetManagementCommands

proc determineStrategy(currentAct: ai_types.GameAct, personality: AIPersonality): DomestikosStrategy =
  ## Determine domestikos strategy based on game act and AI personality
  case currentAct
  of ai_types.GameAct.Act1_LandGrab:
    DomestikosStrategy.SplitForExploration  # Maximize map coverage in Act 1
  of ai_types.GameAct.Act2_RisingTensions:
    DomestikosStrategy.MergeForCombat  # Consolidate forces for combat
  of ai_types.GameAct.Act3_TotalWar, ai_types.GameAct.Act4_Endgame:
    DomestikosStrategy.MaintainFormations  # Preserve battle groups in late game

proc updateStandingOrdersWithDomestikosChanges*(
  controller: var AIController,
  domestikosOrders: Table[FleetId, StandingOrder]
) =
  ## Update controller's standing orders with Domestikos's recommendations
  ## This merges domestikos defensive assignments with existing orders
  for fleetId, newOrder in domestikosOrders:
    controller.standingOrders[fleetId] = newOrder

proc generateDomestikosOrders*(
  controller: var AIController,
  filtered: FilteredGameState,
  currentAct: ai_types.GameAct,
  tacticalOrders: Table[FleetId, FleetOrder],
  intelSnapshot: Option[IntelligenceSnapshot] = none(IntelligenceSnapshot)
): Table[FleetId, StandingOrder] =
  ## Generate strategic fleet reorganization orders
  ## Called after tactical/logistics, before diplomatic actions
  ##
  ## This is the main entry point for the Domestikos module
  ##
  ## Returns standing order updates (not fleet orders) because Domestikos
  ## manages persistent defensive posture, not one-time movements
  result = initTable[FleetId, StandingOrder]()

  # Check if Domestikos is enabled in config
  if not globalRBAConfig.domestikos.enabled:
    return result

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Domestikos: Analyzing fleet operations")

  # Step 1: Analyze fleet utilization
  let analyses = analyzeFleetUtilization(
    filtered,
    controller.houseId,
    tacticalOrders,
    controller.standingOrders
  )

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Domestikos: Analyzed {analyses.len} fleets")

  # Step 2: Generate defensive orders (colony protection)
  # MVP focus - fixes Unknown-Unknown #3
  let defensiveOrders = generateDefensiveOrders(
    filtered,
    analyses,
    controller
  )

  # Merge defensive orders into result
  for fleetId, order in defensiveOrders:
    result[fleetId] = order

  # Step 2.5: Generate build requirements (Phase 3)
  if globalRBAConfig.domestikos.build_requirements_enabled and intelSnapshot.isSome:
    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Domestikos: Generating build requirements")

    let buildReqs = generateBuildRequirements(
      filtered,
      analyses,
      defensiveOrders,
      controller,
      currentAct,
      intelSnapshot.get()
    )

    # Store in controller for orders.nim to use
    controller.domestikosRequirements = some(buildReqs)

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Domestikos: Generated {buildReqs.requirements.len} requirements " &
            &"(Critical={buildReqs.criticalCount}, High={buildReqs.highCount}, " &
            &"Est={buildReqs.totalEstimatedCost}PP)")
  else:
    # Phase 2 mode: No requirements generation
    controller.domestikosRequirements = none(BuildRequirements)

  # Step 3: Determine act-specific strategy
  let strategy = determineStrategy(currentAct, controller.personality)

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Domestikos: Strategy={strategy} for {currentAct}")

  # Step 4: Apply act-specific offensive operations
  # Note: These generate FleetOrders, not StandingOrders, so we return them separately
  var offensiveFleetOrders: seq[FleetOrder] = @[]

  case strategy
  of DomestikosStrategy.SplitForExploration:
    # Act 1: Exploration to build intelligence
    let explorationOrders = generateExplorationOrders(
      filtered, analyses, controller
    )
    # Add as fleet orders (one-time move commands to unexplored systems)
    offensiveFleetOrders.add(explorationOrders)

  of DomestikosStrategy.MergeForCombat:
    # Act 2: Consolidate idle fleets for combat operations
    let stagingArea = selectStagingAreaForGeneral(filtered, controller)

    let mergeOrders = generateMergeOrders(
      filtered, analyses, controller, stagingArea
    )
    offensiveFleetOrders.add(mergeOrders)

    # Probing attacks to gather intel on enemy defenses
    let probingOrders = generateProbingOrders(
      filtered, analyses, controller
    )
    offensiveFleetOrders.add(probingOrders)

    # Counter-attacks against vulnerable targets
    if controller.personality.aggression > 0.5:
      let counterAttackOrders = generateCounterAttackOrders(
        filtered, analyses, controller
      )
      offensiveFleetOrders.add(counterAttackOrders)

  of DomestikosStrategy.MaintainFormations:
    # Act 3+: Total war - active combat operations
    # Counter-attack vulnerable targets (any aggression level during war)
    if controller.personality.aggression > 0.3:
      let counterAttackOrders = generateCounterAttackOrders(
        filtered, analyses, controller
      )
      offensiveFleetOrders.add(counterAttackOrders)

    # Probe enemy defenses with scouts
    let probingOrders = generateProbingOrders(
      filtered, analyses, controller
    )
    offensiveFleetOrders.add(probingOrders)

  of DomestikosStrategy.ProbingAttacks, DomestikosStrategy.DefensiveConsolidation,
     DomestikosStrategy.OpportunisticCounter:
    # Special strategies - not yet implemented
    discard

  # Store offensive fleet orders in controller for later execution
  controller.offensiveFleetOrders = offensiveFleetOrders

  # Step 5: Generate fleet management zero-turn commands (merge/detach/transfer)
  # These execute immediately when fleets are at friendly colonies
  let fleetManagementCommands = fleet_management.generateFleetManagementCommands(
    filtered, analyses, currentAct, controller.houseId
  )

  # Store in controller for orders.nim to add to AIOrderSubmission
  controller.fleetManagementCommands = fleetManagementCommands

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Domestikos: Generated {result.len} standing orders, " &
          &"{offensiveFleetOrders.len} offensive fleet orders, " &
          &"{fleetManagementCommands.len} fleet management commands")

  return result
