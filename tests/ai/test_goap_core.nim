## Unit tests for GOAP core modules
##
## Tests:
## - WorldStateSnapshot creation and manipulation
## - Condition checking (preconditions)
## - Effect application
## - Heuristic cost estimation

import std/[unittest, tables, options, strutils]
import ../../src/ai/rba/goap/core/[types, conditions, heuristics]
import ../../src/ai/rba/goap/state/[effects]
import ../../src/common/types/[core, tech, diplomacy, units]

# =============================================================================
# Test Fixtures
# =============================================================================

proc createTestState(): WorldStateSnapshot =
  ## Create a basic test world state
  result = WorldStateSnapshot(
    turn: 10,
    houseId: "TestHouse",
    treasury: 500,
    production: 100,
    maintenanceCost: 20,
    netIncome: 80,
    totalFleetStrength: 50,
    idleFleets: @["Fleet1", "Fleet2"],
    ownedColonies: @[SystemId(1), SystemId(2), SystemId(3)],
    vulnerableColonies: @[SystemId(2)],
    undefendedColonies: @[SystemId(3)],
    knownEnemyColonies: @[(SystemId(10), "EnemyHouse")],
    invasionOpportunities: @[SystemId(10)],
    staleIntelSystems: @[SystemId(15)],
    espionageTargets: @["EnemyHouse"],
    diplomaticRelations: initTable[HouseId, DiplomaticState](),
    techLevels: initTable[TechField, int](),
    researchProgress: initTable[TechField, int](),
    criticalTechGaps: @[]
  )

# =============================================================================
# Condition Tests
# =============================================================================

suite "GOAP Conditions":
  test "HasBudget condition - sufficient funds":
    let state = createTestState()
    let cond = hasMinBudget(200)
    check checkPrecondition(state, cond) == true

  test "HasBudget condition - insufficient funds":
    let state = createTestState()
    let cond = hasMinBudget(1000)
    check checkPrecondition(state, cond) == false

  test "ControlsSystem condition - owned system":
    let state = createTestState()
    let cond = controlsSystem(SystemId(1))
    check checkPrecondition(state, cond) == true

  test "ControlsSystem condition - unowned system":
    let state = createTestState()
    let cond = controlsSystem(SystemId(99))
    check checkPrecondition(state, cond) == false

  test "HasFleet condition - has idle fleets":
    let state = createTestState()
    let cond = createPrecondition(ConditionKind.HasFleet, initTable[string, int]())
    check checkPrecondition(state, cond) == true

  test "HasFleetStrength condition - sufficient strength":
    let state = createTestState()
    let cond = createPrecondition(ConditionKind.HasFleetStrength,
                                   {"minStrength": 30}.toTable)
    check checkPrecondition(state, cond) == true

  test "HasFleetStrength condition - insufficient strength":
    let state = createTestState()
    let cond = createPrecondition(ConditionKind.HasFleetStrength,
                                   {"minStrength": 100}.toTable)
    check checkPrecondition(state, cond) == false

  test "allPreconditionsMet - all satisfied":
    let state = createTestState()
    let preconditions = @[
      hasMinBudget(100),
      controlsSystem(SystemId(1))
    ]
    check allPreconditionsMet(state, preconditions) == true

  test "allPreconditionsMet - one fails":
    let state = createTestState()
    let preconditions = @[
      hasMinBudget(100),
      controlsSystem(SystemId(99))  # Don't own this
    ]
    check allPreconditionsMet(state, preconditions) == false

# =============================================================================
# Effect Tests
# =============================================================================

suite "GOAP Effects":
  test "ModifyTreasury effect - spend":
    var state = createTestState()
    let effect = spendTreasury(100)
    applyEffect(state, effect)
    check state.treasury == 400

  test "ModifyTreasury effect - gain":
    var state = createTestState()
    let effect = gainTreasury(100)
    applyEffect(state, effect)
    check state.treasury == 600

  test "ModifyProduction effect":
    var state = createTestState()
    let effect = createEffect(EffectKind.ModifyProduction, {"delta": 50}.toTable)
    applyEffect(state, effect)
    check state.production == 150

  test "ModifyFleetStrength effect":
    var state = createTestState()
    let effect = createEffect(EffectKind.ModifyFleetStrength, {"delta": 20}.toTable)
    applyEffect(state, effect)
    check state.totalFleetStrength == 70

  test "GainControl effect":
    var state = createTestState()
    let effect = createEffect(EffectKind.GainControl, {"systemId": 99}.toTable)
    applyEffect(state, effect)
    check SystemId(99) in state.ownedColonies

  test "LoseControl effect":
    var state = createTestState()
    let effect = createEffect(EffectKind.LoseControl, {"systemId": 1}.toTable)
    applyEffect(state, effect)
    check SystemId(1) notin state.ownedColonies

  test "ColonyDefended effect":
    var state = createTestState()
    check SystemId(3) in state.undefendedColonies
    let effect = defendColony(SystemId(3))
    applyEffect(state, effect)
    check SystemId(3) notin state.undefendedColonies

  test "AdvanceTech effect":
    var state = createTestState()
    state.techLevels[TechField.WeaponsTech] = 3
    let effect = advanceTechField(TechField.WeaponsTech)
    applyEffect(state, effect)
    check state.techLevels[TechField.WeaponsTech] == 4

  test "AddResearchProgress effect":
    var state = createTestState()
    let effect = addResearchPoints(TechField.ConstructionTech, 50)
    applyEffect(state, effect)
    check state.researchProgress[TechField.ConstructionTech] == 50

  test "applyAllEffects - multiple effects":
    var state = createTestState()
    let effects = @[
      spendTreasury(100),
      createEffect(EffectKind.ModifyProduction, {"delta": 25}.toTable),
      defendColony(SystemId(3))
    ]
    applyAllEffects(state, effects)
    check state.treasury == 400
    check state.production == 125
    check SystemId(3) notin state.undefendedColonies

# =============================================================================
# Heuristic Tests
# =============================================================================

suite "GOAP Heuristics":
  test "estimateGoalCost - DefendColony":
    let state = createTestState()
    let goal = Goal(
      goalType: GoalType.DefendColony,
      priority: 0.8,
      target: some(SystemId(2)),
      targetHouse: none(HouseId),
      requiredResources: 0,
      deadline: none(int),
      preconditions: @[],
      successCondition: nil,
      description: "Defend colony"
    )
    let cost = estimateGoalCost(state, goal)
    check cost == 100.0  # 1 cruiser minimum

  test "estimateGoalCost - InvadeColony":
    let state = createTestState()
    let goal = Goal(
      goalType: GoalType.InvadeColony,
      priority: 0.7,
      target: some(SystemId(10)),
      targetHouse: some("EnemyHouse"),
      requiredResources: 0,
      deadline: none(int),
      preconditions: @[],
      successCondition: nil,
      description: "Invade enemy colony"
    )
    let cost = estimateGoalCost(state, goal)
    check cost == 210.0  # Transport + marines + escort

  test "estimateGoalCost - TechTheft espionage":
    let state = createTestState()
    let goal = Goal(
      goalType: GoalType.StealTechnology,
      priority: 0.6,
      target: none(SystemId),
      targetHouse: some("EnemyHouse"),
      requiredResources: 0,
      deadline: none(int),
      preconditions: @[],
      successCondition: nil,
      description: "Steal tech"
    )
    let cost = estimateGoalCost(state, goal)
    check cost == 200.0  # 5 EBP * 40 PP

  test "estimateGoalCost - EstablishShipyard":
    let state = createTestState()
    let goal = Goal(
      goalType: GoalType.EstablishShipyard,
      priority: 0.5,
      target: some(SystemId(1)),
      targetHouse: none(HouseId),
      requiredResources: 0,
      deadline: none(int),
      preconditions: @[],
      successCondition: nil,
      description: "Build shipyard"
    )
    let cost = estimateGoalCost(state, goal)
    check cost == 150.0

  test "convertPriorityToWeight - Critical":
    let weight = convertPriorityToWeight(1.0)
    check weight == 1000.0

  test "convertPriorityToWeight - High":
    let weight = convertPriorityToWeight(0.7)
    check weight == 100.0

  test "convertPriorityToWeight - Medium":
    let weight = convertPriorityToWeight(0.4)
    check weight == 10.0

  test "convertPriorityToWeight - Low":
    let weight = convertPriorityToWeight(0.1)
    check weight == 1.0

  test "estimatePlanConfidence - affordable plan":
    let state = createTestState()
    let goal = Goal(
      goalType: GoalType.DefendColony,
      priority: 0.8,
      target: some(SystemId(2)),
      targetHouse: none(HouseId),
      requiredResources: 0,
      deadline: none(int),
      preconditions: @[],
      successCondition: nil,
      description: "Defend colony"
    )
    let plan = GOAPlan(
      goal: goal,
      actions: @[],
      totalCost: 200,
      estimatedTurns: 2,
      confidence: 0.0,
      dependencies: @[]
    )
    let confidence = estimatePlanConfidence(state, plan)
    check confidence > 0.5  # Should be confident with 500 PP treasury

  test "estimatePlanConfidence - unaffordable plan":
    let state = createTestState()
    let goal = Goal(
      goalType: GoalType.InvadeColony,
      priority: 0.7,
      target: some(SystemId(10)),
      targetHouse: some("EnemyHouse"),
      requiredResources: 0,
      deadline: none(int),
      preconditions: @[],
      successCondition: nil,
      description: "Invade"
    )
    let plan = GOAPlan(
      goal: goal,
      actions: @[],
      totalCost: 1000,  # More than treasury (500 PP)
      estimatedTurns: 3,
      confidence: 0.0,
      dependencies: @[]
    )
    let confidence = estimatePlanConfidence(state, plan)
    # Affordability 500/1000 = 0.5 (in 0.5-0.8 bracket) triggers 0.8 multiplier
    # Military ops (InvadeColony) get 0.7 multiplier
    # Result: 1.0 * 0.8 * 0.7 = 0.56
    check confidence <= 0.56  # Should have reduced confidence (tight budget + military risk)

  test "estimatePlanConfidence - military operation risk":
    let state = createTestState()
    let goal = Goal(
      goalType: GoalType.EliminateFleet,
      priority: 0.9,
      target: none(SystemId),
      targetHouse: some("EnemyHouse"),
      requiredResources: 0,
      deadline: none(int),
      preconditions: @[],
      successCondition: nil,
      description: "Destroy enemy fleet"
    )
    let plan = GOAPlan(
      goal: goal,
      actions: @[],
      totalCost: 200,  # Affordable
      estimatedTurns: 1,
      confidence: 0.0,
      dependencies: @[]
    )
    let confidence = estimatePlanConfidence(state, plan)
    # Military ops get 0.7 multiplier for risk
    check confidence <= 0.7

# =============================================================================
# Goal/Action Type Tests
# =============================================================================

suite "GOAP Types":
  test "Goal string representation":
    let goal = Goal(
      goalType: GoalType.DefendColony,
      priority: 0.8,
      target: some(SystemId(5)),
      targetHouse: none(HouseId),
      requiredResources: 100,
      deadline: none(int),
      preconditions: @[],
      successCondition: nil,
      description: "Defend colony at system 5"
    )
    let str = $goal
    check "DefendColony" in str
    check "5" in str

  test "Action string representation":
    let action = Action(
      actionType: ActionType.ConstructShips,
      cost: 150,
      duration: 2,
      target: some(SystemId(1)),
      targetHouse: none(HouseId),
      shipClass: some(ShipClass.Cruiser),
      quantity: 3,
      techField: none(TechField),
      preconditions: @[],
      effects: @[],
      description: "Build 3 cruisers"
    )
    let str = $action
    check "ConstructShips" in str
    check "x3" in str
    check "150 PP" in str

# =============================================================================
# Integration Tests
# =============================================================================

suite "GOAP Integration":
  test "Full goal evaluation flow":
    var state = createTestState()

    # Create a goal with preconditions
    let goal = Goal(
      goalType: GoalType.BuildFleet,
      priority: 0.7,
      target: some(SystemId(1)),
      targetHouse: none(HouseId),
      requiredResources: 300,
      deadline: none(int),
      preconditions: @[
        hasMinBudget(300),
        controlsSystem(SystemId(1))
      ],
      successCondition: nil,
      description: "Build fleet at system 1"
    )

    # Check preconditions
    check allPreconditionsMet(state, goal.preconditions) == true

    # Estimate cost
    let cost = estimateGoalCost(state, goal)
    check cost == 300.0  # Uses requiredResources

    # Apply effects (simulate building fleet)
    let effects = @[
      spendTreasury(300),
      createEffect(EffectKind.ModifyFleetStrength, {"delta": 15}.toTable)
    ]
    applyAllEffects(state, effects)

    # Verify state changes
    check state.treasury == 200
    check state.totalFleetStrength == 65

  test "Economic goal sequence":
    var state = createTestState()

    # Goal 1: Invest in infrastructure
    let effects1 = @[
      spendTreasury(50),
      createEffect(EffectKind.ModifyProduction, {"delta": 10}.toTable)
    ]
    applyAllEffects(state, effects1)
    check state.treasury == 450
    check state.production == 110

    # Goal 2: Use increased production for research
    let effects2 = @[
      addResearchPoints(TechField.WeaponsTech, 30)
    ]
    applyAllEffects(state, effects2)
    check state.researchProgress[TechField.WeaponsTech] == 30

  test "All goal types have cost estimates":
    let state = createTestState()

    # Test that all goal types are covered in heuristic
    for goalType in GoalType:
      let goal = Goal(
        goalType: goalType,
        priority: 0.5,
        target: none(SystemId),
        targetHouse: none(HouseId),
        requiredResources: 0,
        deadline: none(int),
        preconditions: @[],
        successCondition: nil,
        description: "Test goal"
      )
      let cost = estimateGoalCost(state, goal)
      # All goals should have non-negative cost estimate
      check cost >= 0.0
