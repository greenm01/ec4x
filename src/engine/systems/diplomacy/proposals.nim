## Diplomatic Proposal System
##
## Handles pending diplomatic proposals for multiplayer games
## Per docs/architecture/diplomacy_proposals.md

import std/options
import ../../types/[core, diplomacy, game_state]

export diplomacy.ProposalType, diplomacy.ProposalStatus, diplomacy.PendingProposal

proc findProposal*(
    proposals: seq[PendingProposal], proposalId: ProposalId
): Option[PendingProposal] =
  ## Find pending proposal by ID
  for proposal in proposals:
    if proposal.id == proposalId:
      return some(proposal)
  return none(PendingProposal)

proc findProposalIndex*(proposals: seq[PendingProposal], proposalId: ProposalId): int =
  ## Find index of proposal by ID (-1 if not found)
  for i, proposal in proposals:
    if proposal.id == proposalId:
      return i
  return -1

proc expireProposals*(proposals: var seq[PendingProposal], currentTurn: int32) =
  ## Remove all proposals that have expired
  ## Call this at the beginning of each turn
  var i = 0
  while i < proposals.len:
    if proposals[i].expiresOnTurn <= currentTurn and 
       proposals[i].status == ProposalStatus.Pending:
      # Proposal expired - remove it
      proposals.delete(i)
    else:
      i += 1

proc expiredProposals*(proposals: seq[PendingProposal], currentTurn: int32): seq[PendingProposal] =
  ## Get list of proposals that have expired this turn
  ## For event generation
  result = @[]
  for proposal in proposals:
    if proposal.expiresOnTurn == currentTurn and 
       proposal.status == ProposalStatus.Pending:
      result.add(proposal)

proc canProposeDeescalation*(
    currentState: DiplomaticState, targetState: DiplomaticState
): bool =
  ## Validate if de-escalation proposal is valid
  ## Can only de-escalate down the ladder: Enemy→Hostile→Neutral
  case currentState
  of DiplomaticState.Enemy:
    # From Enemy, can propose Hostile or Neutral
    return targetState in {DiplomaticState.Hostile, DiplomaticState.Neutral}
  of DiplomaticState.Hostile:
    # From Hostile, can only propose Neutral
    return targetState == DiplomaticState.Neutral
  of DiplomaticState.Neutral:
    # Already at lowest, cannot de-escalate further
    return false

proc createDeescalationProposal*(
    state: GameState,
    proposer: HouseId,
    target: HouseId,
    targetState: DiplomaticState,
    submittedTurn: int32,
    expirationTurns: int32 = 3
): PendingProposal =
  ## Create a de-escalation proposal
  ## Default expiration: 3 turns
  ## NOTE: Caller must increment state.idCounters.nextProposalId
  let proposalType = case targetState
    of DiplomaticState.Neutral:
      ProposalType.DeescalateToNeutral
    of DiplomaticState.Hostile:
      ProposalType.DeescalateToHostile
    of DiplomaticState.Enemy:
      # Invalid - cannot escalate via proposal
      ProposalType.DeescalateToNeutral # Fallback (should not happen)
  
  let proposalId = ProposalId(state.counters.nextProposalId)
  state.counters.nextProposalId += 1
  
  result = PendingProposal(
    id: proposalId,
    proposer: proposer,
    target: target,
    proposalType: proposalType,
    submittedTurn: submittedTurn,
    status: ProposalStatus.Pending,
    expiresOnTurn: submittedTurn + expirationTurns
  )
