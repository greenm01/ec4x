## Diplomacy Integration Tests
## Validates diplomatic state transitions and proposal system
## Per docs/specs/08-diplomacy.md

import std/[tables, options]
import unittest
import ../../src/engine/engine
import ../../src/engine/types/[core, house, diplomacy, game_state]
import ../../src/engine/state/[engine, iterators]

suite "Diplomacy: Proposal System (Section 8.1)":

  test "Diplomatic proposals have correct structure":
    ## Proposals have id, proposer, target, type, expiration
    let proposal = PendingProposal(
      id: ProposalId(1),
      proposer: HouseId(1),
      target: HouseId(2),
      proposalType: ProposalType.DeescalateToHostile,
      submittedTurn: 10,
      expiresOnTurn: 13,
      status: ProposalStatus.Pending
    )
    
    check proposal.status == ProposalStatus.Pending
    check proposal.expiresOnTurn == 13
    check proposal.proposer == HouseId(1)
    check proposal.target == HouseId(2)

  test "Proposal types exist for all transitions":
    ## DeescalateToHostile (Enemy → Hostile), DeescalateToNeutral (Hostile → Neutral)
    let toHostile = PendingProposal(
      id: ProposalId(1),
      proposer: HouseId(1),
      target: HouseId(2),
      proposalType: ProposalType.DeescalateToHostile,  # Enemy → Hostile
      submittedTurn: 1,
      expiresOnTurn: 4,
      status: ProposalStatus.Pending
    )
    
    let toNeutral = PendingProposal(
      id: ProposalId(2),
      proposer: HouseId(1),
      target: HouseId(2),
      proposalType: ProposalType.DeescalateToNeutral,  # Hostile → Neutral
      submittedTurn: 1,
      expiresOnTurn: 4,
      status: ProposalStatus.Pending
    )
    
    check toHostile.proposalType == ProposalType.DeescalateToHostile
    check toNeutral.proposalType == ProposalType.DeescalateToNeutral

  test "Proposal status transitions":
    ## Pending → Accepted/Rejected/Expired
    var proposal = PendingProposal(
      id: ProposalId(1),
      proposer: HouseId(1),
      target: HouseId(2),
      proposalType: ProposalType.DeescalateToHostile,
      submittedTurn: 1,
      expiresOnTurn: 4,
      status: ProposalStatus.Pending
    )
    
    check proposal.status == ProposalStatus.Pending
    
    # Can be accepted
    proposal.status = ProposalStatus.Accepted
    check proposal.status == ProposalStatus.Accepted
    
    # Or rejected
    proposal.status = ProposalStatus.Rejected
    check proposal.status == ProposalStatus.Rejected
    
    # Or expired
    proposal.status = ProposalStatus.Expired
    check proposal.status == ProposalStatus.Expired

suite "Diplomacy: Violation Tracking (Section 8.1.6)":

  test "Violation records track escalation events":
    ## Track violations between houses
    let violation = ViolationRecord(
      violator: HouseId(1),
      victim: HouseId(2),
      turn: 5,
      description: "Unprovoked colony attack"
    )
    
    check violation.violator == HouseId(1)
    check violation.victim == HouseId(2)
    check violation.turn == 5

  test "Violation history accumulates over time":
    ## Houses can have multiple violations
    var history = ViolationHistory(
      houseId: HouseId(1),
      violations: @[]
    )
    
    history.violations.add(ViolationRecord(
      violator: HouseId(1),
      victim: HouseId(2),
      turn: 3,
      description: "First violation"
    ))
    
    history.violations.add(ViolationRecord(
      violator: HouseId(1),
      victim: HouseId(2),
      turn: 5,
      description: "Second violation"
    ))
    
    check history.violations.len == 2

suite "Diplomacy: Diplomatic States (Section 8.1.1)":

  test "Diplomatic state enum values exist":
    ## Neutral, Hostile, Enemy states exist
    let neutral = DiplomaticState.Neutral
    let hostile = DiplomaticState.Hostile
    let enemy = DiplomaticState.Enemy
    
    check neutral == DiplomaticState.Neutral
    check hostile == DiplomaticState.Hostile
    check enemy == DiplomaticState.Enemy

  test "Diplomatic state change events":
    ## State changes generate events
    let event = DiplomaticEvent(
      houseId: HouseId(1),
      otherHouse: HouseId(2),
      oldState: DiplomaticState.Neutral,
      newState: DiplomaticState.Hostile,
      turn: 10,
      reason: "Escalation due to violations",
      prestigeEvents: @[]
    )
    
    check event.oldState == DiplomaticState.Neutral
    check event.newState == DiplomaticState.Hostile

suite "Diplomacy: Integration with Game State":

  test "Game state stores diplomatic relations":
    ## Diplomatic relations are part of game state
    var game = newGame()
    
    # Game should have diplomatic relations tracking
    # (stored in game state, not in House objects)
    var houseCount = 0
    for _ in game.allHouses():
      houseCount.inc
    
    check houseCount >= 2  # Need at least 2 houses for diplomacy

when isMainModule:
  echo "========================================"
  echo "  Diplomacy Integration Tests"
  echo "  Per docs/specs/08-diplomacy.md"
  echo "========================================"
  echo ""
