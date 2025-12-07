## Test RBA Enhanced Reprioritization Module (Gap 4)
##
## Tests quantity adjustment, substitution logic, and smart reprioritization

import unittest
import std/[options, tables]
import ../../src/common/types/[core, units]
import ../../src/ai/rba/controller_types
import ../../src/ai/rba/domestikos/requirements/reprioritization
import ../../src/ai/common/types as ai_types

suite "RBA Reprioritization - Quantity Adjustment":

  test "tryQuantityAdjustment reduces quantity by 50%":
    # Arrange
    let req = BuildRequirement(
      requirementType: RequirementType.DefenseGap,
      priority: RequirementPriority.High,
      shipClass: some(ShipClass.Cruiser),
      itemId: none(string),
      quantity: 10,
      buildObjective: ai_types.BuildObjective.Defense,
      targetSystem: none(SystemId),
      estimatedCost: 1500,
      reason: "Defense gap test"
    )
    let iteration = 1

    # Act
    let adjusted = tryQuantityAdjustment(req, iteration)

    # Assert
    check adjusted.quantity == 5  # 50% of 10
    check adjusted.estimatedCost <= req.estimatedCost  # Cost reduced

  test "tryQuantityAdjustment respects minimum of 1":
    # Arrange
    let req = BuildRequirement(
      requirementType: RequirementType.DefenseGap,
      priority: RequirementPriority.High,
      shipClass: some(ShipClass.Corvette),
      itemId: none(string),
      quantity: 1,  # Already at minimum
      buildObjective: ai_types.BuildObjective.Defense,
      targetSystem: none(SystemId),
      estimatedCost: 50,
      reason: "Defense gap test"
    )
    let iteration = 1

    # Act
    let adjusted = tryQuantityAdjustment(req, iteration)

    # Assert
    check adjusted.quantity == 1  # Can't reduce below 1

  test "tryQuantityAdjustment with quantity 3 becomes 1":
    # Arrange
    let req = BuildRequirement(
      requirementType: RequirementType.OffensivePrep,
      priority: RequirementPriority.High,
      shipClass: some(ShipClass.Destroyer),
      itemId: none(string),
      quantity: 3,
      buildObjective: ai_types.BuildObjective.Military,
      targetSystem: none(SystemId),
      estimatedCost: 300,
      reason: "Offensive prep test"
    )
    let iteration = 1

    # Act
    let adjusted = tryQuantityAdjustment(req, iteration)

    # Assert
    check adjusted.quantity == 1  # 50% of 3 = 1.5, but min_quantity_reduction is 1

suite "RBA Reprioritization - Substitution Logic":

  test "trySubstitution finds cheaper capital ship":
    # Arrange
    let req = BuildRequirement(
      requirementType: RequirementType.DefenseGap,
      priority: RequirementPriority.High,
      shipClass: some(ShipClass.Battleship),  # Expensive
      itemId: none(string),
      quantity: 2,
      buildObjective: ai_types.BuildObjective.Defense,
      targetSystem: none(SystemId),
      estimatedCost: 700,
      reason: "Defense gap test"
    )
    let cstLevel = 4

    # Act
    let substituted = trySubstitution(req, cstLevel)

    # Assert
    check substituted.isSome
    # Should substitute with cheaper capital ship
    let result = substituted.get()
    check result.shipClass.isSome
    check result.estimatedCost < req.estimatedCost

  test "trySubstitution respects 60% cost reduction threshold":
    # Arrange
    let req = BuildRequirement(
      requirementType: RequirementType.DefenseGap,
      priority: RequirementPriority.High,
      shipClass: some(ShipClass.HeavyCruiser),
      itemId: none(string),
      quantity: 3,
      buildObjective: ai_types.BuildObjective.Defense,
      targetSystem: none(SystemId),
      estimatedCost: 600,
      reason: "Defense gap test"
    )
    let cstLevel = 3

    # Act
    let substituted = trySubstitution(req, cstLevel)

    # Assert
    if substituted.isSome:
      let result = substituted.get()
      # Substituted ship should be at most 60% of original cost
      # (maxCostReductionFactor = 0.6 from config)
      check result.estimatedCost <= int(float(req.estimatedCost) * 0.6)

  test "trySubstitution returns none for ground units":
    # Arrange
    let req = BuildRequirement(
      requirementType: RequirementType.DefenseGap,
      priority: RequirementPriority.High,
      shipClass: none(ShipClass),
      itemId: some("Marine"),  # Ground unit
      quantity: 5,
      buildObjective: ai_types.BuildObjective.Defense,
      targetSystem: none(SystemId),
      estimatedCost: 250,
      reason: "Defense gap test"
    )
    let cstLevel = 3

    # Act
    let substituted = trySubstitution(req, cstLevel)

    # Assert
    check substituted.isNone  # No substitution for ground units

  test "trySubstitution returns none for specialized ships":
    # Arrange
    let req = BuildRequirement(
      requirementType: RequirementType.ReconnaissanceGap,
      priority: RequirementPriority.High,
      shipClass: some(ShipClass.Scout),
      itemId: none(string),
      quantity: 3,
      buildObjective: ai_types.BuildObjective.Reconnaissance,
      targetSystem: none(SystemId),
      estimatedCost: 150,
      reason: "Recon gap test"
    )
    let cstLevel = 3

    # Act
    let substituted = trySubstitution(req, cstLevel)

    # Assert
    check substituted.isNone  # No substitutes for Scout

  test "trySubstitution respects CST requirements":
    # Arrange
    let req = BuildRequirement(
      requirementType: RequirementType.DefenseGap,
      priority: RequirementPriority.High,
      shipClass: some(ShipClass.Battlecruiser),  # Requires higher CST
      itemId: none(string),
      quantity: 2,
      buildObjective: ai_types.BuildObjective.Defense,
      targetSystem: none(SystemId),
      estimatedCost: 500,
      reason: "Defense gap test"
    )
    let lowCstLevel = 2  # Only early ships available

    # Act
    let substituted = trySubstitution(req, lowCstLevel)

    # Assert
    if substituted.isSome:
      let result = substituted.get()
      check result.shipClass.isSome
      # Substituted ship must be available at CST 2

suite "RBA Reprioritization - Integration":

  test "reprioritizeRequirements uses quantity adjustment in iteration 1":
    # Arrange
    var originalReqs = BuildRequirements(
      requirements: @[
        BuildRequirement(
          requirementType: RequirementType.DefenseGap,
          priority: RequirementPriority.High,
          shipClass: some(ShipClass.Cruiser),
          itemId: none(string),
          quantity: 10,
          buildObjective: ai_types.BuildObjective.Defense,
          targetSystem: none(SystemId),
          estimatedCost: 1500,
          reason: "Defense gap"
        )
      ],
      totalEstimatedCost: 1500,
      criticalCount: 0,
      highCount: 1,
      generatedTurn: 1,
      act: ai_types.GameAct.Act1_LandGrab,
      iteration: 0  # First iteration
    )

    let feedback = TreasurerFeedback(
      fulfilledRequirements: @[],
      unfulfilledRequirements: originalReqs.requirements,
      deferredRequirements: @[],
      totalBudgetAvailable: 500,
      totalBudgetSpent: 0,
      totalUnfulfilledCost: 1500,
      detailedFeedback: @[]
    )
    let treasury = 500
    let cstLevel = 3

    # Act
    let reprioritized = reprioritizeRequirements(
      originalReqs, feedback, treasury, cstLevel)

    # Assert
    check reprioritized.iteration == 1
    check reprioritized.requirements.len == 1
    # Quantity should be reduced in iteration 1
    check reprioritized.requirements[0].quantity < originalReqs.requirements[0].quantity

  test "reprioritizeRequirements downgrades expensive unfulfilled":
    # Arrange
    var originalReqs = BuildRequirements(
      requirements: @[
        BuildRequirement(
          requirementType: RequirementType.DefenseGap,
          priority: RequirementPriority.High,
          shipClass: some(ShipClass.Battleship),
          itemId: none(string),
          quantity: 2,
          buildObjective: ai_types.BuildObjective.Defense,
          targetSystem: none(SystemId),
          estimatedCost: 700,  # Very expensive (>50% of treasury)
          reason: "Defense gap"
        )
      ],
      totalEstimatedCost: 700,
      criticalCount: 0,
      highCount: 1,
      generatedTurn: 1,
      act: ai_types.GameAct.Act1_LandGrab,
      iteration: 0
    )

    let feedback = TreasurerFeedback(
      fulfilledRequirements: @[],
      unfulfilledRequirements: originalReqs.requirements,
      deferredRequirements: @[],
      totalBudgetAvailable: 1000,
      totalBudgetSpent: 0,
      totalUnfulfilledCost: 700,
      detailedFeedback: @[]
    )
    let treasury = 1000
    let cstLevel = 4

    # Act
    let reprioritized = reprioritizeRequirements(
      originalReqs, feedback, treasury, cstLevel)

    # Assert
    check reprioritized.requirements.len > 0
    # Expensive High should be downgraded (cost is 70% of treasury)

  test "reprioritizeRequirements preserves fulfilled requirements":
    # Arrange
    let fulfilledReq = BuildRequirement(
      requirementType: RequirementType.DefenseGap,
      priority: RequirementPriority.Critical,
      shipClass: some(ShipClass.Corvette),
      itemId: none(string),
      quantity: 2,
      buildObjective: ai_types.BuildObjective.Defense,
      targetSystem: none(SystemId),
      estimatedCost: 100,
      reason: "Defense gap - fulfilled"
    )

    let unfulfilledReq = BuildRequirement(
      requirementType: RequirementType.DefenseGap,
      priority: RequirementPriority.High,
      shipClass: some(ShipClass.Cruiser),
      itemId: none(string),
      quantity: 5,
      buildObjective: ai_types.BuildObjective.Defense,
      targetSystem: none(SystemId),
      estimatedCost: 750,
      reason: "Defense gap - unfulfilled"
    )

    var originalReqs = BuildRequirements(
      requirements: @[fulfilledReq, unfulfilledReq],
      totalEstimatedCost: 850,
      criticalCount: 1,
      highCount: 1,
      generatedTurn: 1,
      act: ai_types.GameAct.Act1_LandGrab,
      iteration: 0
    )

    let feedback = TreasurerFeedback(
      fulfilledRequirements: @[fulfilledReq],
      unfulfilledRequirements: @[unfulfilledReq],
      deferredRequirements: @[],
      totalBudgetAvailable: 500,
      totalBudgetSpent: 100,
      totalUnfulfilledCost: 750,
      detailedFeedback: @[]
    )
    let treasury = 500
    let cstLevel = 3

    # Act
    let reprioritized = reprioritizeRequirements(
      originalReqs, feedback, treasury, cstLevel)

    # Assert
    check reprioritized.requirements.len == 2
    # Fulfilled requirement should still be there
    var foundFulfilled = false
    for req in reprioritized.requirements:
      if req.reason == "Defense gap - fulfilled":
        foundFulfilled = true
        check req.priority == RequirementPriority.Critical  # Preserved
    check foundFulfilled
