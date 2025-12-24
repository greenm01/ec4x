## Diplomatic Proposal System
##
## Handles pending diplomatic proposals for multiplayer games
## Per docs/architecture/diplomacy_proposals.md

import std/options
import ../../types/[core, diplomacy]

export diplomacy.ProposalType, diplomacy.ProposalStatus, diplomacy.PendingProposal

proc generateProposalId*(turn: int, proposer: HouseId, target: HouseId): string =
  ## Generate unique proposal ID
  result = "PROP_T" & $turn & "_" & $proposer & "_" & $target

proc findProposal*(
    proposals: seq[PendingProposal], proposalId: string
): Option[PendingProposal] =
  ## Find pending proposal by ID
  for proposal in proposals:
    if proposal.id == proposalId:
      return some(proposal)
  return none(PendingProposal)

proc findProposalIndex*(proposals: seq[PendingProposal], proposalId: string): int =
  ## Find index of proposal by ID (-1 if not found)
  for i, proposal in proposals:
    if proposal.id == proposalId:
      return i
  return -1
