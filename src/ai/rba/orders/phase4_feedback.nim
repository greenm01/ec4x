## Phase 4: Multi-Advisor Feedback Loop
##
## Iteratively reprioritize unfulfilled requirements until convergence

import std/[strformat, options, strutils]
import ../../../engine/logger
import ../controller_types
import ../domestikos/requirements/reprioritization  # Gap 4 enhanced reprioritization
import ../logothete/requirements as logothete_req
import ../drungarius/requirements as drungarius_req
import ../eparch/requirements as eparch_req

proc hasUnfulfilledCriticalOrHigh*(controller: AIController): bool =
  ## Check if any advisor has unfulfilled Critical or High priority requirements
  ## Used to determine if feedback loop should continue

  # Check Domestikos (Treasurer) feedback
  if controller.treasurerFeedback.isSome:
    for req in controller.treasurerFeedback.get().unfulfilledRequirements:
      if req.priority in {RequirementPriority.Critical, RequirementPriority.High}:
        return true

  # Check Logothete (Science) feedback
  if controller.scienceFeedback.isSome:
    for req in controller.scienceFeedback.get().unfulfilledRequirements:
      if req.priority in {RequirementPriority.Critical, RequirementPriority.High}:
        return true

  # Check Drungarius feedback
  if controller.drungariusFeedback.isSome:
    for req in controller.drungariusFeedback.get().unfulfilledRequirements:
      if req.priority in {RequirementPriority.Critical, RequirementPriority.High}:
        return true

  # Check Eparch feedback
  if controller.eparchFeedback.isSome:
    for req in controller.eparchFeedback.get().unfulfilledRequirements:
      if req.priority in {RequirementPriority.Critical, RequirementPriority.High}:
        return true

  # No Critical/High unfulfilled requirements
  return false

proc reprioritizeAllAdvisors*(controller: var AIController, treasury: int, cstLevel: int) =
  ## Reprioritize unfulfilled requirements for all advisors
  ## Downgrades priorities based on cost-effectiveness
  ## Budget-aware: expensive unfulfilled requests downgraded more aggressively
  ## Gap 4 Enhanced: Includes quantity adjustment and substitution logic

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Reprioritizing unfulfilled requirements for all advisors (treasury={treasury}PP, CST={cstLevel})")

  # Reprioritize Domestikos (budget-aware with substitution)
  if controller.treasurerFeedback.isSome and controller.domestikosRequirements.isSome:
    let feedback = controller.treasurerFeedback.get()
    if feedback.unfulfilledRequirements.len > 0:
      let reprioritized = reprioritizeRequirements(
        controller.domestikosRequirements.get(),
        feedback,
        treasury,  # Budget-aware reprioritization
        cstLevel   # For substitution logic (Gap 4)
      )
      controller.domestikosRequirements = some(reprioritized)
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Domestikos: Reprioritized to {reprioritized.requirements.len} requirements")

  # Reprioritize Logothete
  if controller.scienceFeedback.isSome and controller.logotheteRequirements.isSome:
    let feedback = controller.scienceFeedback.get()
    if feedback.unfulfilledRequirements.len > 0:
      let reprioritized = logothete_req.reprioritizeResearchRequirements(
        controller.logotheteRequirements.get(),
        feedback
      )
      controller.logotheteRequirements = some(reprioritized)
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Logothete: Reprioritized to {reprioritized.requirements.len} requirements")

  # Reprioritize Drungarius
  if controller.drungariusFeedback.isSome and controller.drungariusRequirements.isSome:
    let feedback = controller.drungariusFeedback.get()
    if feedback.unfulfilledRequirements.len > 0:
      let reprioritized = drungarius_req.reprioritizeEspionageRequirements(
        controller.drungariusRequirements.get(),
        feedback
      )
      controller.drungariusRequirements = some(reprioritized)
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Drungarius: Reprioritized to {reprioritized.requirements.len} requirements")

  # Reprioritize Eparch (escalate starved requirements)
  if controller.eparchFeedback.isSome and controller.eparchRequirements.isSome:
    let feedback = controller.eparchFeedback.get()
    if feedback.unfulfilledRequirements.len > 0:
      let reprioritized = eparch_req.reprioritizeEconomicRequirements(
        controller.eparchRequirements.get(),
        feedback,
        treasury  # Budget-aware reprioritization (Gap 4)
      )
      controller.eparchRequirements = some(reprioritized)
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Eparch: Reprioritized to {reprioritized.requirements.len} requirements")

  # Note: Protostrator (diplomacy) costs 0 PP, no feedback needed

proc getUnfulfilledSummary*(controller: AIController): string =
  ## Get summary of unfulfilled requirements for logging

  var summary: seq[string] = @[]

  if controller.treasurerFeedback.isSome:
    summary.add(&"Domestikos={controller.treasurerFeedback.get().unfulfilledRequirements.len}")

  if controller.scienceFeedback.isSome:
    summary.add(&"Logothete={controller.scienceFeedback.get().unfulfilledRequirements.len}")

  if controller.drungariusFeedback.isSome:
    summary.add(&"Drungarius={controller.drungariusFeedback.get().unfulfilledRequirements.len}")

  if controller.eparchFeedback.isSome:
    summary.add(&"Eparch={controller.eparchFeedback.get().unfulfilledRequirements.len}")

  result = summary.join(", ")

proc checkGOAPReplanningNeeded*(controller: AIController): bool =
  ## Check if GOAP replanning should be triggered
  ##
  ## Phase 5 Integration: Called after Phase 4 feedback loop
  ## Returns true if significant unfulfilled requirements exist

  # TODO: GOAP integration incomplete (controller.goapEnabled field doesn't exist)
  # Stubbed out for now
  return false
  # 
  #   if controller.treasurerFeedback.isSome:
  #     totalUnfulfilled += controller.treasurerFeedback.get().unfulfilledRequirements.len
  # 
  #   if controller.scienceFeedback.isSome:
  #     totalUnfulfilled += controller.scienceFeedback.get().unfulfilledRequirements.len
  # 
  #   if controller.drungariusFeedback.isSome:
  #     totalUnfulfilled += controller.drungariusFeedback.get().unfulfilledRequirements.len
  # 
  #   if controller.eparchFeedback.isSome:
  #     totalUnfulfilled += controller.eparchFeedback.get().unfulfilledRequirements.len
  # 
  #   # Trigger replanning if >=3 unfulfilled requirements
  #   if totalUnfulfilled >= 3:
  #     logInfo(LogCategory.lcAI,
  #             &"{controller.houseId} Phase 4: {totalUnfulfilled} unfulfilled requirements - GOAP replanning needed")
  #     return true
  # 
  #   return false
