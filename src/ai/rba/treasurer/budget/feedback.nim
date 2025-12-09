## Treasurer Budget Feedback Module (Gap 6)
##
## Rich feedback generation for intelligent reprioritization.
## Tracks WHY requirements were unfulfilled and suggests alternatives.
##
## Following DoD (Data-Oriented Design): Pure functions for feedback generation.

import std/[options, strformat, sequtils, tables, algorithm]
import ../../../../common/types/[core, units]
import ../../../../engine/logger
import ../../../../engine/economy/config_accessors
import ../../controller_types
import ../../config
import ../../../common/types as ai_common_types  # From ai/rba/treasurer/budget to ai/common
import ../../domestikos/unit_priority

proc getCheaperAlternatives*(
  shipClass: ShipClass,
  cstLevel: int
): seq[ShipClass] =
  ## Get list of cheaper ships in same role category
  ## Uses ship role tables from unit_priority.nim
  ## Returns ships sorted by cost (cheapest first)

  # Get role category
  let role = case shipClass
    # Capital ships
    of ShipClass.SuperDreadnought, ShipClass.Dreadnought,
       ShipClass.Battleship, ShipClass.Battlecruiser,
       ShipClass.HeavyCruiser, ShipClass.Cruiser,
       ShipClass.LightCruiser:
      "Capital"
    # Escort ships
    of ShipClass.Destroyer, ShipClass.Frigate, ShipClass.Corvette:
      "Escort"
    # Carriers
    of ShipClass.SuperCarrier, ShipClass.Carrier:
      "Carrier"
    # Specialized
    of ShipClass.Raider, ShipClass.Scout, ShipClass.ETAC,
       ShipClass.TroopTransport, ShipClass.Fighter:
      "Specialized"
    # Strategic
    of ShipClass.PlanetBreaker:
      "Strategic"
    # Facility (not a ship, but handle gracefully)
    else:
      "Other"

  let originalCost = getShipConstructionCost(shipClass)

  # Generate candidate alternatives based on role
  var candidates: seq[ShipClass] = @[]
  case role
  of "Capital":
    candidates = @[
      ShipClass.LightCruiser, ShipClass.Cruiser,
      ShipClass.HeavyCruiser, ShipClass.Battlecruiser,
      ShipClass.Battleship, ShipClass.Dreadnought,
      ShipClass.SuperDreadnought
    ]
  of "Escort":
    candidates = @[
      ShipClass.Corvette, ShipClass.Frigate, ShipClass.Destroyer
    ]
  of "Carrier":
    candidates = @[ShipClass.Carrier, ShipClass.SuperCarrier]
  else:
    # Specialized/Strategic ships have no good substitutes
    return @[]

  # Filter: cheaper than original AND tech-available
  result = candidates.filterIt(
    getShipConstructionCost(it) < originalCost and
    getShipCSTRequirement(it) <= cstLevel
  )

  # Sort by cost (cheapest first)
  result.sort(proc (a, b: ShipClass): int =
    let costA = getShipConstructionCost(a)
    let costB = getShipConstructionCost(b)
    return cmp(costA, costB)
  )

proc generateSubstitutionSuggestion*(
  req: BuildRequirement,
  budgetAvailable: int,
  cstLevel: int
): Option[string] =
  ## Generate substitution suggestion for unfulfilled requirement
  ## Returns human-readable suggestion string

  # Only suggest for ships (ground units don't have good substitutes yet)
  if req.shipClass.isNone:
    return none(string)

  let originalShip = req.shipClass.get()
  let originalCost = getShipConstructionCost(originalShip)
  let totalCost = originalCost * req.quantity

  # Find cheaper alternatives
  let alternatives = getCheaperAlternatives(originalShip, cstLevel)

  if alternatives.len == 0:
    return none(string)

  # Check if any alternative is affordable
  for altShip in alternatives:
    let altCost = getShipConstructionCost(altShip)
    let altTotalCost = altCost * req.quantity

    if altTotalCost <= budgetAvailable:
      # Found affordable substitute
      let savings = totalCost - altTotalCost
      let savingsPct = int((1.0 - float(altCost) / float(originalCost)) * 100.0)
      return some(&"Consider {req.quantity}× {altShip} ({altCost}PP each, " &
                  &"{savingsPct}% cheaper) instead of {originalShip} " &
                  &"({originalCost}PP). Saves {savings}PP total.")

  # No affordable substitute for full quantity, suggest quantity reduction
  let cheapestAlt = alternatives[0]
  let cheapestCost = getShipConstructionCost(cheapestAlt)
  let affordableQty = budgetAvailable div cheapestCost

  if affordableQty > 0:
    return some(&"Consider {affordableQty}× {cheapestAlt} ({cheapestCost}PP " &
                &"each) instead of {req.quantity}× {originalShip}. " &
                &"Affordable within budget.")

  return none(string)

proc generateRequirementFeedback*(
  req: BuildRequirement,
  budgetAvailable: int,
  quantityBuilt: int,
  cstLevel: int,
  hasAvailableCapacity: bool
): RequirementFeedback =
  ## Generate rich feedback for unfulfilled requirement
  ## Tracks WHY requirement failed and suggests alternatives

  var feedback = RequirementFeedback(
    requirement: req,
    quantityBuilt: quantityBuilt,
    budgetShortfall: 0,
    suggestion: none(string)
  )

  # Determine unfulfillment reason
  if quantityBuilt == 0:
    # Nothing built - determine why
    let unitCost = if req.shipClass.isSome:
                     getShipConstructionCost(req.shipClass.get())
                   else:
                     # Ground unit/facility cost lookup
                     50  # Default estimate (TODO: proper cost lookup)

    if budgetAvailable < unitCost:
      # Insufficient budget for even 1 unit
      feedback.reason = UnfulfillmentReason.InsufficientBudget
      feedback.budgetShortfall = unitCost - budgetAvailable

      # Generate substitution suggestion if enabled
      if globalRBAConfig.feedback_system.suggest_cheaper_alternatives:
        feedback.suggestion = generateSubstitutionSuggestion(
          req, budgetAvailable, cstLevel)

    elif not hasAvailableCapacity:
      # No dock space available
      feedback.reason = UnfulfillmentReason.ColonyCapacityFull
      feedback.budgetShortfall = 0
      feedback.suggestion = some(
        "No available dock capacity. Build Shipyard or wait for " &
        "current construction to complete.")

    elif req.shipClass.isSome and
         getShipCSTRequirement(req.shipClass.get()) > cstLevel:
      # Tech requirement not met
      feedback.reason = UnfulfillmentReason.TechNotAvailable
      feedback.budgetShortfall = 0
      let requiredCST = getShipCSTRequirement(req.shipClass.get())
      feedback.suggestion = some(
        &"Requires CST {requiredCST} (current: {cstLevel}). " &
        &"Research Construction Tech or build cheaper ships.")

    else:
      # Budget was reserved for higher priority
      feedback.reason = UnfulfillmentReason.BudgetReserved
      feedback.budgetShortfall = 0

  else:
    # Partial fulfillment
    feedback.reason = UnfulfillmentReason.PartialBudget
    let unitCost = if req.shipClass.isSome:
                     getShipConstructionCost(req.shipClass.get())
                   else:
                     50  # Default estimate
    let remainingQty = req.quantity - quantityBuilt
    feedback.budgetShortfall = remainingQty * unitCost

    feedback.suggestion = some(
      &"Built {quantityBuilt}/{req.quantity}. Need {feedback.budgetShortfall}PP " &
      &"more to complete full order.")

  return feedback

proc generateDetailedFeedback*(
  unfulfilledRequirements: seq[BuildRequirement],
  budgetAvailable: int,
  cstLevel: int,
  partialFulfillments: Table[int, int]  # reqIndex -> quantityBuilt
): seq[RequirementFeedback] =
  ## Generate detailed feedback for all unfulfilled requirements
  ## Called by budget execution during requirement processing

  result = @[]

  for i, req in unfulfilledRequirements:
    let quantityBuilt = if partialFulfillments.hasKey(i):
                          partialFulfillments[i]
                        else:
                          0

    # Assume capacity available (executor checks this)
    let hasCapacity = true

    let feedback = generateRequirementFeedback(
      req, budgetAvailable, quantityBuilt, cstLevel, hasCapacity)

    result.add(feedback)

    # Log feedback for diagnostics
    logDebug(LogCategory.lcAI,
             &"Feedback: {req.reason} -> {feedback.reason}, " &
             &"shortfall={feedback.budgetShortfall}PP, " &
             &"built={quantityBuilt}/{req.quantity}")
