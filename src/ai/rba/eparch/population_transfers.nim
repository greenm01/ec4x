## Population Transfer Opportunity Evaluation
##
## Eparch's economic analysis of Space Guild population transfers
## Generates opportunities that compete for budget through Treasurer mediation
##
## Transfer Strategy:
## - FROM: Mature core colonies (infrastructure ≥5, excess population)
## - TO: New frontier colonies (infrastructure <5, high growth potential)
## - AVOID: Transferring from threatened colonies
##
## Cost: 1 PP per PTU (economy.md Section 3.7)

import std/[strformat, algorithm, options]
import ../../../engine/[logger, fog_of_war, gamestate]
import ../../../common/types/[core, planets]
import ../../common/types as ai_types
import ../controller_types
import ../shared/intelligence_types
import ../intelligence
import ../config

type
  PopulationTransferOpportunity* = object
    ## Represents a potential population transfer for budget competition
    donorColony*: SystemId
    recipientColony*: SystemId
    ptuAmount*: int
    estimatedCost*: int  # In PP
    priority*: float  # Combined score for priority ranking
    donorScore*: float  # Donor evaluation score
    recipientScore*: float  # Recipient evaluation score
    reason*: string

proc evaluateDonorColonies*(controller: AIController,
                            colonies: seq[Colony],
                            currentAct: ai_types.GameAct):
                            seq[tuple[colony: Colony, score: float]] =
  ## Evaluate colonies as potential population donors
  ## Returns sorted list (best donors first)
  ##
  ## Criteria:
  ## - Infrastructure ≥5 (mature colony)
  ## - Population >5 (excess available)
  ## - Threat level <2.0 (safe from enemies)
  ## - Act 1 homeworld bonus (largest pop base)

  result = @[]
  let config = globalRBAConfig.eparch_population_transfers

  for colony in colonies:
    # Require mature colony
    if colony.infrastructure < 5:
      continue

    # Require excess population
    if colony.population <= 5:
      continue

    # Calculate threat level from intelligence
    var threatLevel = 0.0
    if controller.intelligenceSnapshot.isSome:
      let snap = controller.intelligenceSnapshot.get()
      for (enemySystemId, owner) in snap.knownEnemyColonies:
        if owner != controller.houseId:
          threatLevel += 0.5

    # Skip if too dangerous
    if threatLevel > 2.0:
      continue

    # Calculate donor score
    var donorScore = float(colony.infrastructure) + float(colony.population) -
      threatLevel

    # PRIORITY: Act 1 homeworld bonus
    # Homeworld has highest infrastructure (5) and population (840)
    if currentAct == ai_types.GameAct.Act1_LandGrab and
       colony.infrastructure >= 5 and colony.population > 100:
      donorScore += config.homeworld_donor_bonus_act1

    result.add((colony, donorScore))

    logInfo(LogCategory.lcAI,
      &"{controller.houseId} Donor candidate: {colony.systemId} " &
      &"(score: {donorScore:.1f})")

  # Sort by score (best first)
  result.sort(proc(a, b: auto): int =
    if a.score > b.score: -1 elif a.score < b.score: 1 else: 0)

proc evaluateRecipientColonies*(controller: AIController,
                                colonies: seq[Colony]):
                                seq[tuple[colony: Colony, score: float]] =
  ## Evaluate colonies as potential population recipients
  ## Returns sorted list (best recipients first)
  ##
  ## Criteria:
  ## - Infrastructure <5 (new colony)
  ## - High resource rating (growth potential)

  result = @[]

  for colony in colonies:
    # Require new colony
    if colony.infrastructure >= 5:
      continue

    # Resource-based scoring
    let resourceBonus = case colony.resources
      of ResourceRating.VeryRich: 3.0
      of ResourceRating.Rich: 2.0
      of ResourceRating.Abundant: 1.0
      else: 0.5

    # Frontier bonus (all recipients get small bonus)
    # TODO: Implement proper frontier detection with adjacent system checks
    let frontierBonus = 0.5

    # Calculate recipient score
    let recipientScore = resourceBonus + frontierBonus +
      (10.0 - float(colony.infrastructure))

    result.add((colony, recipientScore))

    logInfo(LogCategory.lcAI,
      &"{controller.houseId} Recipient candidate: {colony.systemId} " &
      &"(score: {recipientScore:.1f})")

  # Sort by score (best first)
  result.sort(proc(a, b: auto): int =
    if a.score > b.score: -1 elif a.score < b.score: 1 else: 0)

proc generatePopulationTransferOpportunities*(
  controller: AIController,
  filtered: FilteredGameState,
  intelSnapshot: IntelligenceSnapshot,
  currentAct: ai_types.GameAct,
  treasury: int): seq[PopulationTransferOpportunity] =
  ## Generate population transfer opportunities for Treasurer mediation
  ##
  ## Returns opportunities that will compete for budget allocation
  ## Execution happens later if requirement is fulfilled

  result = @[]
  let config = globalRBAConfig.eparch_population_transfers

  # Only generate opportunities if treasury is healthy
  if treasury < config.treasury_threshold:
    return @[]

  let myColonies = filtered.ownColonies

  # Evaluate donors and recipients
  let donors = evaluateDonorColonies(controller, myColonies, currentAct)
  let recipients = evaluateRecipientColonies(controller, myColonies)

  if donors.len == 0 or recipients.len == 0:
    return @[]

  # Calculate max transfers: 1 transfer per 2 colonies, capped by config
  let colonyCount = myColonies.len
  let scaledMaxTransfers = max(1, colonyCount div 2)
  let maxTransfers = min(
    min(donors.len, recipients.len),
    min(scaledMaxTransfers, config.max_transfers_per_turn)
  )

  # Budget allocation: 10% of treasury
  var ppBudget = treasury div 10

  # Match best donors with best recipients
  for i in 0..<maxTransfers:
    if ppBudget <= 0:
      break

    let donor = donors[i].colony
    let donorScore = donors[i].score
    let recipient = recipients[i].colony
    let recipientScore = recipients[i].score

    # PROTECTION: Don't drain donor below 50% of current population
    let minDonorPopulation = max(5, donor.population div 2)
    if donor.population - 1 < minDonorPopulation:
      continue  # Skip - would drain too much

    # Create opportunity for 1 PTU transfer (1 PP cost)
    if ppBudget >= 1:
      let combinedScore = donorScore + recipientScore
      let reason = &"Transfer PTU from {donor.systemId} (score {donorScore:.1f}) " &
                   &"to {recipient.systemId} (score {recipientScore:.1f})"

      result.add(PopulationTransferOpportunity(
        donorColony: donor.systemId,
        recipientColony: recipient.systemId,
        ptuAmount: 1,
        estimatedCost: 1,  # 1 PP per PTU
        priority: combinedScore,
        donorScore: donorScore,
        recipientScore: recipientScore,
        reason: reason
      ))

      ppBudget -= 1

      logInfo(LogCategory.lcAI,
        &"{controller.houseId} Transfer opportunity: {donor.systemId} → " &
        &"{recipient.systemId} (1 PTU, priority {combinedScore:.1f})")
