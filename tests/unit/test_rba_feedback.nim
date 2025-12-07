## Test RBA Rich Feedback Module (Gap 6)
##
## Tests feedback generation, substitution suggestions, and cheaper alternatives

import unittest
import std/[options, tables]
import ../../src/common/types/[core, units]
import ../../src/ai/rba/controller_types
import ../../src/ai/rba/treasurer/budget/feedback
import ../../src/ai/common/types as ai_types

suite "RBA Rich Feedback - Cheaper Alternatives":

  test "getCheaperAlternatives for capital ships":
    # Arrange
    let originalShip = ShipClass.Battleship
    let cstLevel = 4  # Battleship requires CST 4

    # Act
    let alternatives = getCheaperAlternatives(originalShip, cstLevel)

    # Assert
    check alternatives.len > 0
    # Should include cheaper capital ships: Cruiser, HeavyCruiser, etc.
    check ShipClass.Cruiser in alternatives
    check ShipClass.HeavyCruiser in alternatives
    # Should NOT include more expensive ships
    check ShipClass.Dreadnought notin alternatives
    check ShipClass.SuperDreadnought notin alternatives

  test "getCheaperAlternatives respects CST requirements":
    # Arrange
    let originalShip = ShipClass.Battleship
    let lowCstLevel = 2  # Only early ships available

    # Act
    let alternatives = getCheaperAlternatives(originalShip, lowCstLevel)

    # Assert
    # Should only include ships available at CST 2 or lower
    check ShipClass.LightCruiser in alternatives
    # Should NOT include ships requiring higher CST
    check ShipClass.HeavyCruiser notin alternatives
    check ShipClass.Battlecruiser notin alternatives

  test "getCheaperAlternatives for escorts":
    # Arrange
    let originalShip = ShipClass.Destroyer
    let cstLevel = 3

    # Act
    let alternatives = getCheaperAlternatives(originalShip, cstLevel)

    # Assert
    # Should include cheaper escorts
    check alternatives.len > 0
    check ShipClass.Corvette in alternatives
    check ShipClass.Frigate in alternatives
    # Should NOT include more expensive escorts
    check ShipClass.Destroyer notin alternatives  # Same as original

  test "getCheaperAlternatives returns empty for cheapest option":
    # Arrange
    let originalShip = ShipClass.Corvette  # Cheapest escort
    let cstLevel = 5

    # Act
    let alternatives = getCheaperAlternatives(originalShip, cstLevel)

    # Assert
    check alternatives.len == 0  # No cheaper alternatives exist

  test "getCheaperAlternatives returns empty for specialized ships":
    # Arrange
    let specializedShips = [
      ShipClass.Scout,
      ShipClass.ETAC,
      ShipClass.TroopTransport,
      ShipClass.Fighter,
      ShipClass.PlanetBreaker
    ]
    let cstLevel = 5

    # Act & Assert
    for ship in specializedShips:
      let alternatives = getCheaperAlternatives(ship, cstLevel)
      check alternatives.len == 0  # No substitutes for specialized roles

suite "RBA Rich Feedback - Requirement Feedback":

  test "generateRequirementFeedback detects insufficient budget":
    # Arrange
    let req = BuildRequirement(
      requirementType: RequirementType.DefenseGap,
      priority: RequirementPriority.High,
      shipClass: some(ShipClass.Cruiser),  # ~150 PP
      itemId: none(string),
      quantity: 2,
      buildObjective: ai_types.BuildObjective.Defense,
      targetSystem: none(SystemId),
      estimatedCost: 300,
      reason: "Defense gap test"
    )
    let budgetAvailable = 100  # Not enough for even 1 ship
    let quantityBuilt = 0
    let cstLevel = 3
    let hasCapacity = true

    # Act
    let feedback = generateRequirementFeedback(
      req, budgetAvailable, quantityBuilt, cstLevel, hasCapacity)

    # Assert
    check feedback.reason == UnfulfillmentReason.InsufficientBudget
    check feedback.budgetShortfall > 0
    check feedback.quantityBuilt == 0
    check feedback.suggestion.isSome  # Should suggest cheaper alternative

  test "generateRequirementFeedback detects partial fulfillment":
    # Arrange
    let req = BuildRequirement(
      requirementType: RequirementType.DefenseGap,
      priority: RequirementPriority.High,
      shipClass: some(ShipClass.Cruiser),
      itemId: none(string),
      quantity: 5,
      buildObjective: ai_types.BuildObjective.Defense,
      targetSystem: none(SystemId),
      estimatedCost: 750,  # 5 × 150 PP
      reason: "Defense gap test"
    )
    let budgetAvailable = 300  # Enough for 2 ships
    let quantityBuilt = 2
    let cstLevel = 3
    let hasCapacity = true

    # Act
    let feedback = generateRequirementFeedback(
      req, budgetAvailable, quantityBuilt, cstLevel, hasCapacity)

    # Assert
    check feedback.reason == UnfulfillmentReason.PartialBudget
    check feedback.quantityBuilt == 2
    check feedback.budgetShortfall > 0  # Remaining cost for 3 more ships
    check feedback.suggestion.isSome  # Should suggest completion cost

  test "generateRequirementFeedback detects capacity constraints":
    # Arrange
    let req = BuildRequirement(
      requirementType: RequirementType.DefenseGap,
      priority: RequirementPriority.High,
      shipClass: some(ShipClass.Corvette),
      itemId: none(string),
      quantity: 3,
      buildObjective: ai_types.BuildObjective.Defense,
      targetSystem: none(SystemId),
      estimatedCost: 150,
      reason: "Defense gap test"
    )
    let budgetAvailable = 500  # Plenty of budget
    let quantityBuilt = 0
    let cstLevel = 2
    let hasCapacity = false  # No dock space

    # Act
    let feedback = generateRequirementFeedback(
      req, budgetAvailable, quantityBuilt, cstLevel, hasCapacity)

    # Assert
    check feedback.reason == UnfulfillmentReason.ColonyCapacityFull
    check feedback.budgetShortfall == 0  # Budget wasn't the issue
    check feedback.quantityBuilt == 0
    check feedback.suggestion.isSome  # Should suggest building Shipyard

  test "generateRequirementFeedback detects tech unavailable":
    # Arrange
    let req = BuildRequirement(
      requirementType: RequirementType.OffensivePrep,
      priority: RequirementPriority.High,
      shipClass: some(ShipClass.Dreadnought),  # Requires CST 5
      itemId: none(string),
      quantity: 1,
      buildObjective: ai_types.BuildObjective.Military,
      targetSystem: none(SystemId),
      estimatedCost: 500,
      reason: "Offensive prep test"
    )
    let budgetAvailable = 1000  # Plenty of budget
    let quantityBuilt = 0
    let cstLevel = 3  # Too low for Dreadnought
    let hasCapacity = true

    # Act
    let feedback = generateRequirementFeedback(
      req, budgetAvailable, quantityBuilt, cstLevel, hasCapacity)

    # Assert
    check feedback.reason == UnfulfillmentReason.TechNotAvailable
    check feedback.budgetShortfall == 0
    check feedback.quantityBuilt == 0
    check feedback.suggestion.isSome  # Should suggest researching CST

suite "RBA Rich Feedback - Substitution Suggestions":

  test "generateSubstitutionSuggestion finds affordable alternative":
    # Arrange
    let req = BuildRequirement(
      requirementType: RequirementType.DefenseGap,
      priority: RequirementPriority.High,
      shipClass: some(ShipClass.Battleship),  # ~350 PP
      itemId: none(string),
      quantity: 2,
      buildObjective: ai_types.BuildObjective.Defense,
      targetSystem: none(SystemId),
      estimatedCost: 700,
      reason: "Defense gap test"
    )
    let budgetAvailable = 400  # Not enough for Battleships, but enough for Cruisers
    let cstLevel = 4

    # Act
    let suggestion = generateSubstitutionSuggestion(req, budgetAvailable, cstLevel)

    # Assert
    check suggestion.isSome
    # Suggestion should mention cheaper alternative

  test "generateSubstitutionSuggestion returns none for ground units":
    # Arrange
    let req = BuildRequirement(
      requirementType: RequirementType.DefenseGap,
      priority: RequirementPriority.High,
      shipClass: none(ShipClass),
      itemId: some("Army"),
      quantity: 5,
      buildObjective: ai_types.BuildObjective.Defense,
      targetSystem: none(SystemId),
      estimatedCost: 250,
      reason: "Defense gap test"
    )
    let budgetAvailable = 100
    let cstLevel = 3

    # Act
    let suggestion = generateSubstitutionSuggestion(req, budgetAvailable, cstLevel)

    # Assert
    check suggestion.isNone  # No substitutes for ground units yet

  test "generateSubstitutionSuggestion returns none when no alternatives exist":
    # Arrange
    let req = BuildRequirement(
      requirementType: RequirementType.ReconnaissanceGap,
      priority: RequirementPriority.High,
      shipClass: some(ShipClass.Scout),  # Specialized, no substitutes
      itemId: none(string),
      quantity: 3,
      buildObjective: ai_types.BuildObjective.Reconnaissance,
      targetSystem: none(SystemId),
      estimatedCost: 150,
      reason: "Recon gap test"
    )
    let budgetAvailable = 100
    let cstLevel = 3

    # Act
    let suggestion = generateSubstitutionSuggestion(req, budgetAvailable, cstLevel)

    # Assert
    check suggestion.isNone  # No substitutes for Scout

  test "generateSubstitutionSuggestion suggests quantity reduction when partial affordable":
    # Arrange
    let req = BuildRequirement(
      requirementType: RequirementType.DefenseGap,
      priority: RequirementPriority.High,
      shipClass: some(ShipClass.Cruiser),  # ~150 PP each
      itemId: none(string),
      quantity: 5,
      buildObjective: ai_types.BuildObjective.Defense,
      targetSystem: none(SystemId),
      estimatedCost: 750,  # 5 × 150
      reason: "Defense gap test"
    )
    let budgetAvailable = 200  # Enough for 1-2 ships with cheaper alternative
    let cstLevel = 3

    # Act
    let suggestion = generateSubstitutionSuggestion(req, budgetAvailable, cstLevel)

    # Assert
    if suggestion.isSome:
      # Should suggest either cheaper ship or reduced quantity
      check suggestion.get().len > 0
