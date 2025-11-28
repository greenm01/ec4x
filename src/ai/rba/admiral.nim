## Admiral Module - Strategic Fleet Rebalancing
##
## The Admiral provides tactical judgment for fleet operations:
## - Fleet utilization analysis
## - Act-specific fleet reorganization (split in Act 1, merge in Act 2+)
## - Smart defensive consolidation (no suicide attacks)
## - Opportunistic counter-attacks against vulnerable enemies
## - Probing attacks for intelligence gathering
##
## Integration: Called after logistics, before diplomatic actions in orders.nim

import std/[options, tables, sets, sequtils, strformat, algorithm]
import ../../common/system
import ../../common/types/[units, diplomacy, core]
import ../../engine/[gamestate, fog_of_war, fleet, order_types, standing_orders, logger]
import ../common/types as ai_types  # For GameAct
import ./controller_types
import ./config

# Core types for Admiral module
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

  AdmiralStrategy* {.pure.} = enum
    SplitForExploration    # Act 1: Maximize map coverage
    MergeForCombat         # Act 2+: Concentrate forces
    MaintainFormations     # Act 3+: Preserve battle groups
    ProbingAttacks         # When fleets at Rendezvous need intel
    DefensiveConsolidation # When under threat: merge weak fleets
    OpportunisticCounter   # When enemy vulnerable: organize counter-attack

# Forward declare module exports to avoid circular imports
# Note: Sub-modules will import these types directly from this file

# Now import sub-modules (they will see our type definitions)
import ./admiral/[fleet_analysis, defensive_ops, offensive_ops, staging]

proc determineStrategy(currentAct: ai_types.GameAct, personality: AIPersonality): AdmiralStrategy =
  ## Determine admiral strategy based on game act and AI personality
  case currentAct
  of ai_types.GameAct.Act1_LandGrab:
    AdmiralStrategy.SplitForExploration  # Maximize map coverage in Act 1
  of ai_types.GameAct.Act2_RisingTensions:
    AdmiralStrategy.MergeForCombat  # Consolidate forces for combat
  of ai_types.GameAct.Act3_TotalWar, ai_types.GameAct.Act4_Endgame:
    AdmiralStrategy.MaintainFormations  # Preserve battle groups in late game
  else:
    AdmiralStrategy.MaintainFormations

proc updateStandingOrdersWithAdmiralChanges*(
  controller: var AIController,
  admiralOrders: Table[FleetId, StandingOrder]
) =
  ## Update controller's standing orders with Admiral's recommendations
  ## This merges admiral defensive assignments with existing orders
  for fleetId, newOrder in admiralOrders:
    controller.standingOrders[fleetId] = newOrder

proc generateAdmiralOrders*(
  controller: var AIController,
  filtered: FilteredGameState,
  currentAct: ai_types.GameAct,
  tacticalOrders: Table[FleetId, FleetOrder]
): Table[FleetId, StandingOrder] =
  ## Generate strategic fleet reorganization orders
  ## Called after tactical/logistics, before diplomatic actions
  ##
  ## This is the main entry point for the Admiral module
  ##
  ## Returns standing order updates (not fleet orders) because Admiral
  ## manages persistent defensive posture, not one-time movements
  result = initTable[FleetId, StandingOrder]()

  # Check if Admiral is enabled in config
  if not globalRBAConfig.admiral.enabled:
    return result

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Admiral: Analyzing fleet operations")

  # Step 1: Analyze fleet utilization
  let analyses = analyzeFleetUtilization(
    filtered,
    controller.houseId,
    tacticalOrders,
    controller.standingOrders
  )

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Admiral: Analyzed {analyses.len} fleets")

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

  # Step 3: Determine act-specific strategy
  let strategy = determineStrategy(currentAct, controller.personality)

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Admiral: Strategy={strategy} for {currentAct}")

  # Step 4: Apply act-specific offensive operations
  # Note: These generate FleetOrders, not StandingOrders, so we return them separately
  var offensiveFleetOrders: seq[FleetOrder] = @[]

  case strategy
  of AdmiralStrategy.SplitForExploration:
    # Act 1: Keep fleets dispersed for exploration (no merging)
    # Defense is priority - no offensive ops in Act 1
    discard

  of AdmiralStrategy.MergeForCombat:
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

  of AdmiralStrategy.MaintainFormations:
    # Act 3+: Preserve existing battle groups, limited reorganization
    # Only counter-attack if very aggressive
    if controller.personality.aggression > 0.7:
      let counterAttackOrders = generateCounterAttackOrders(
        filtered, analyses, controller
      )
      offensiveFleetOrders.add(counterAttackOrders)

  of AdmiralStrategy.ProbingAttacks, AdmiralStrategy.DefensiveConsolidation,
     AdmiralStrategy.OpportunisticCounter:
    # Special strategies - not yet implemented
    discard

  # Note: Offensive fleet orders are returned through a separate mechanism
  # (We'd need to modify the return type or store them in controller state)
  # For now, we only return standing orders (defensive assignments)
  # TODO: Extend to return both standing orders and fleet orders

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Admiral: Generated {result.len} standing orders, " &
          &"{offensiveFleetOrders.len} offensive fleet orders")

  return result
