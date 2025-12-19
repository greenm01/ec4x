## Diplomatic Proposal System
##
## Handles pending diplomatic proposals for multiplayer games
## Per docs/architecture/diplomacy_proposals.md

import std/options
import ../../../common/types/core
import ../../types/diplomacy as dip_types

export dip_types

type
  ProposalType* {.pure.} = enum
    TradeAgreement       # Future: resource trading
    MilitaryAlliance     # Future: joint operations
    TechnologySharing    # Future: research cooperation

  ProposalStatus* {.pure.} = enum
    Pending    # Awaiting response
    Accepted   # Target accepted
    Rejected   # Target rejected
    Expired    # Timed out without response
    Withdrawn  # Proposer cancelled

  PendingProposal* = object
    id*: string              # Unique proposal ID
    proposer*: HouseId
    target*: HouseId
    proposalType*: ProposalType
    submittedTurn*: int      # When proposal was made
    expiresIn*: int          # Turns until auto-reject
    status*: ProposalStatus
    message*: string         # Optional diplomatic message

proc generateProposalId*(turn: int, proposer: HouseId, target: HouseId): string =
  ## Generate unique proposal ID
  result = "PROP_T" & $turn & "_" & proposer & "_" & target

proc findProposal*(proposals: seq[PendingProposal], proposalId: string): Option[PendingProposal] =
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
