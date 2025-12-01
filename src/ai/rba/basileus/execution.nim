## Basileus Centralized Execution Module
##
## Central execution authority for all imperial decisions.
## Advisors recommend, Basileus (Emperor) executes.
##
## Architecture:
## - Phase 1: Advisors generate requirements
## - Phase 2: Basileus mediates competing requirements
## - Phase 3: Basileus executes approved actions (THIS MODULE)
##
## Decision Authority:
## - Zero-cost actions (diplomacy, fleet orders): Direct execution
## - PP-costing actions (research, builds): Execute after Treasurer approval

import std/[options, tables, strformat]
import ../../../common/types/[core, diplomacy]
import ../../../engine/[gamestate, fog_of_war, logger, orders]
import ../../../engine/research/types as res_types
import ../../../engine/diplomacy/proposals as dip_proposals
import ../controller_types
import ../../common/types as ai_types
import ../logothete/allocation

proc executeDiplomaticActions*(
  controller: AIController,
  filtered: FilteredGameState
): seq[DiplomaticAction] =
  ## Execute approved diplomatic requirements (zero PP cost)
  ## Basileus authority: Direct execution without Treasurer approval
  ##
  ## Converts Protostrator requirements to diplomatic actions:
  ## - DeclareWar → DeclareEnemy
  ## - ProposePact → ProposeNonAggressionPact (or future Alliance)
  ## - BreakPact → BreakPact
  ## - SeekPeace → SetNeutral
  ## - MaintainRelations → No action

  result = @[]

  if controller.protostratorRequirements.isNone:
    return result

  let reqs = controller.protostratorRequirements.get()

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Basileus executing {reqs.requirements.len} diplomatic requirements")

  for req in reqs.requirements:
    case req.requirementType
    of DiplomaticRequirementType.DeclareWar:
      result.add(DiplomaticAction(
        targetHouse: req.targetHouse,
        actionType: DiplomaticActionType.DeclareEnemy,
        proposalId: none(string),
        message: some(req.reason)
      ))
      logInfo(LogCategory.lcAI,
              &"  IMPERIAL DECREE: Declaring war on {req.targetHouse} - {req.reason}")

    of DiplomaticRequirementType.ProposePact:
      if req.proposalType.isSome:
        let propType = req.proposalType.get()
        case propType
        of dip_proposals.ProposalType.NonAggressionPact:
          result.add(DiplomaticAction(
            targetHouse: req.targetHouse,
            actionType: DiplomaticActionType.ProposeNonAggressionPact,
            proposalId: none(string),
            message: some(req.reason)
          ))
          logInfo(LogCategory.lcAI,
                  &"  Proposing NAP to {req.targetHouse}: {req.reason}")
        else:
          # Other proposal types not yet implemented in diplomacy system
          logWarn(LogCategory.lcAI,
                  &"  Proposal type {propType} not yet implemented, skipping proposal to {req.targetHouse}")

    of DiplomaticRequirementType.BreakPact:
      result.add(DiplomaticAction(
        targetHouse: req.targetHouse,
        actionType: DiplomaticActionType.BreakPact,
        proposalId: none(string),
        message: some(req.reason)
      ))
      logInfo(LogCategory.lcAI,
              &"  Breaking pact with {req.targetHouse}: {req.reason}")

    of DiplomaticRequirementType.SeekPeace:
      result.add(DiplomaticAction(
        targetHouse: req.targetHouse,
        actionType: DiplomaticActionType.SetNeutral,
        proposalId: none(string),
        message: some(req.reason)
      ))
      logInfo(LogCategory.lcAI,
              &"  Seeking peace with {req.targetHouse}: {req.reason}")

    of DiplomaticRequirementType.MaintainRelations:
      # No action needed - maintain current status
      discard

  return result

proc executeResearchAllocation*(
  controller: AIController,
  filtered: FilteredGameState,
  researchBudget: int
): res_types.ResearchAllocation =
  ## Execute approved research requirements (PP cost - after Treasurer approval)
  ## Basileus queries Treasurer for budget, then executes
  ##
  ## Uses Logothete allocation module to distribute research points

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Basileus executing research allocation " &
          &"(budget={researchBudget}PP)")

  # Use Logothete allocation module
  result = allocateResearch(
    controller,
    filtered,
    researchBudget
  )

  return result

proc executeAllImperialDecisions*(
  controller: AIController,
  filtered: FilteredGameState,
  researchBudget: int
): tuple[diplomaticActions: seq[DiplomaticAction], researchAllocation: res_types.ResearchAllocation] =
  ## Master execution function - all imperial decisions
  ## Called after Basileus mediation and Treasurer budget approval
  ##
  ## Returns all decisions for incorporation into OrderPacket
  ##
  ## Future expansion:
  ## - Fleet orders (tactical operations)
  ## - Standing orders (strategic directives)
  ## - Emergency overrides (threat > 0.8)

  result.diplomaticActions = executeDiplomaticActions(controller, filtered)
  result.researchAllocation = executeResearchAllocation(controller, filtered, researchBudget)

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Basileus issued {result.diplomaticActions.len} diplomatic actions, " &
          &"research allocation: economic={result.researchAllocation.economic}PP " &
          &"science={result.researchAllocation.science}PP")

  return result
