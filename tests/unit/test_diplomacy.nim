## Unit Tests for Diplomacy System
##
## Tests diplomatic proposal handling and de-escalation rules.
## Per docs/specs/08-diplomacy.md

import std/[unittest, options]
import ../../src/engine/types/[core, diplomacy]
import ../../src/engine/systems/diplomacy/proposals

suite "Diplomacy: Proposal Search":
  ## Tests for findProposal and findProposalIndex

  test "findProposal returns none for empty list":
    let proposals: seq[PendingProposal] = @[]
    let result = findProposal(proposals, ProposalId(1))
    check result.isNone

  test "findProposal returns none when not found":
    let proposals = @[
      PendingProposal(
        id: ProposalId(1),
        proposer: HouseId(1),
        target: HouseId(2),
        proposalType: ProposalType.DeescalateToNeutral,
        submittedTurn: 5,
        status: ProposalStatus.Pending,
        expiresOnTurn: 8
      )
    ]
    let result = findProposal(proposals, ProposalId(999))
    check result.isNone

  test "findProposal returns proposal when found":
    let proposals = @[
      PendingProposal(
        id: ProposalId(1),
        proposer: HouseId(1),
        target: HouseId(2),
        proposalType: ProposalType.DeescalateToNeutral,
        submittedTurn: 5,
        status: ProposalStatus.Pending,
        expiresOnTurn: 8
      ),
      PendingProposal(
        id: ProposalId(2),
        proposer: HouseId(3),
        target: HouseId(4),
        proposalType: ProposalType.DeescalateToHostile,
        submittedTurn: 6,
        status: ProposalStatus.Pending,
        expiresOnTurn: 9
      )
    ]
    let result = findProposal(proposals, ProposalId(2))
    check result.isSome
    check result.get().proposer == HouseId(3)
    check result.get().target == HouseId(4)

  test "findProposalIndex returns -1 for empty list":
    let proposals: seq[PendingProposal] = @[]
    check findProposalIndex(proposals, ProposalId(1)) == -1

  test "findProposalIndex returns -1 when not found":
    let proposals = @[
      PendingProposal(id: ProposalId(1), proposer: HouseId(1), target: HouseId(2),
        proposalType: ProposalType.DeescalateToNeutral, submittedTurn: 5,
        status: ProposalStatus.Pending, expiresOnTurn: 8)
    ]
    check findProposalIndex(proposals, ProposalId(999)) == -1

  test "findProposalIndex returns correct index":
    let proposals = @[
      PendingProposal(id: ProposalId(1), proposer: HouseId(1), target: HouseId(2),
        proposalType: ProposalType.DeescalateToNeutral, submittedTurn: 5,
        status: ProposalStatus.Pending, expiresOnTurn: 8),
      PendingProposal(id: ProposalId(2), proposer: HouseId(3), target: HouseId(4),
        proposalType: ProposalType.DeescalateToHostile, submittedTurn: 6,
        status: ProposalStatus.Pending, expiresOnTurn: 9),
      PendingProposal(id: ProposalId(3), proposer: HouseId(5), target: HouseId(6),
        proposalType: ProposalType.DeescalateToNeutral, submittedTurn: 7,
        status: ProposalStatus.Pending, expiresOnTurn: 10)
    ]
    check findProposalIndex(proposals, ProposalId(1)) == 0
    check findProposalIndex(proposals, ProposalId(2)) == 1
    check findProposalIndex(proposals, ProposalId(3)) == 2

suite "Diplomacy: Proposal Expiration":
  ## Tests for expireProposals and expiredProposals

  test "expireProposals removes expired pending proposals":
    var proposals = @[
      PendingProposal(id: ProposalId(1), proposer: HouseId(1), target: HouseId(2),
        proposalType: ProposalType.DeescalateToNeutral, submittedTurn: 1,
        status: ProposalStatus.Pending, expiresOnTurn: 4),  # Expired
      PendingProposal(id: ProposalId(2), proposer: HouseId(3), target: HouseId(4),
        proposalType: ProposalType.DeescalateToHostile, submittedTurn: 3,
        status: ProposalStatus.Pending, expiresOnTurn: 6)   # Not expired
    ]
    
    expireProposals(proposals, 5)  # Turn 5
    
    check proposals.len == 1
    check proposals[0].id == ProposalId(2)

  test "expireProposals keeps already processed proposals":
    var proposals = @[
      PendingProposal(id: ProposalId(1), proposer: HouseId(1), target: HouseId(2),
        proposalType: ProposalType.DeescalateToNeutral, submittedTurn: 1,
        status: ProposalStatus.Accepted, expiresOnTurn: 4),  # Expired but accepted
      PendingProposal(id: ProposalId(2), proposer: HouseId(3), target: HouseId(4),
        proposalType: ProposalType.DeescalateToHostile, submittedTurn: 1,
        status: ProposalStatus.Rejected, expiresOnTurn: 4)   # Expired but rejected
    ]
    
    expireProposals(proposals, 5)
    
    # Both should remain since they're not Pending
    check proposals.len == 2

  test "expireProposals handles empty list":
    var proposals: seq[PendingProposal] = @[]
    expireProposals(proposals, 10)
    check proposals.len == 0

  test "expiredProposals returns proposals expiring this turn":
    let proposals = @[
      PendingProposal(id: ProposalId(1), proposer: HouseId(1), target: HouseId(2),
        proposalType: ProposalType.DeescalateToNeutral, submittedTurn: 2,
        status: ProposalStatus.Pending, expiresOnTurn: 5),  # Expires turn 5
      PendingProposal(id: ProposalId(2), proposer: HouseId(3), target: HouseId(4),
        proposalType: ProposalType.DeescalateToHostile, submittedTurn: 3,
        status: ProposalStatus.Pending, expiresOnTurn: 6),  # Expires turn 6
      PendingProposal(id: ProposalId(3), proposer: HouseId(5), target: HouseId(6),
        proposalType: ProposalType.DeescalateToNeutral, submittedTurn: 2,
        status: ProposalStatus.Pending, expiresOnTurn: 5)   # Also expires turn 5
    ]
    
    let expired = expiredProposals(proposals, 5)
    
    check expired.len == 2
    check expired[0].id == ProposalId(1)
    check expired[1].id == ProposalId(3)

  test "expiredProposals ignores non-pending":
    let proposals = @[
      PendingProposal(id: ProposalId(1), proposer: HouseId(1), target: HouseId(2),
        proposalType: ProposalType.DeescalateToNeutral, submittedTurn: 2,
        status: ProposalStatus.Accepted, expiresOnTurn: 5)  # Already accepted
    ]
    
    let expired = expiredProposals(proposals, 5)
    check expired.len == 0

suite "Diplomacy: De-escalation Validation":
  ## Tests for canProposeDeescalation

  test "Enemy can de-escalate to Hostile":
    check canProposeDeescalation(DiplomaticState.Enemy, DiplomaticState.Hostile) == true

  test "Enemy can de-escalate to Neutral":
    check canProposeDeescalation(DiplomaticState.Enemy, DiplomaticState.Neutral) == true

  test "Enemy cannot stay Enemy via proposal":
    check canProposeDeescalation(DiplomaticState.Enemy, DiplomaticState.Enemy) == false

  test "Hostile can de-escalate to Neutral":
    check canProposeDeescalation(DiplomaticState.Hostile, DiplomaticState.Neutral) == true

  test "Hostile cannot stay Hostile via proposal":
    check canProposeDeescalation(DiplomaticState.Hostile, DiplomaticState.Hostile) == false

  test "Hostile cannot escalate to Enemy via proposal":
    check canProposeDeescalation(DiplomaticState.Hostile, DiplomaticState.Enemy) == false

  test "Neutral cannot de-escalate further":
    check canProposeDeescalation(DiplomaticState.Neutral, DiplomaticState.Neutral) == false
    check canProposeDeescalation(DiplomaticState.Neutral, DiplomaticState.Hostile) == false
    check canProposeDeescalation(DiplomaticState.Neutral, DiplomaticState.Enemy) == false

suite "Diplomacy: De-escalation Ladder":
  ## Tests for proper de-escalation progression
  ## Enemy → Hostile → Neutral (one step at a time or skip)

  test "Full de-escalation path from Enemy":
    # Start as Enemy
    var currentState = DiplomaticState.Enemy
    
    # Can propose Hostile (one step down)
    check canProposeDeescalation(currentState, DiplomaticState.Hostile)
    currentState = DiplomaticState.Hostile
    
    # Can propose Neutral (one step down)
    check canProposeDeescalation(currentState, DiplomaticState.Neutral)
    currentState = DiplomaticState.Neutral
    
    # Cannot go further
    check not canProposeDeescalation(currentState, DiplomaticState.Neutral)

  test "Skip de-escalation from Enemy to Neutral":
    # Can skip Hostile and go directly to Neutral
    check canProposeDeescalation(DiplomaticState.Enemy, DiplomaticState.Neutral)

when isMainModule:
  echo "========================================"
  echo "  Diplomacy Unit Tests"
  echo "========================================"
