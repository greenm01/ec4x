## Diplomatic action resolution
##
## This module handles all diplomatic action resolution including:
## - Non-Aggression Pact proposals, acceptance, rejection
## - Pact breaking with violation penalties
## - Enemy/Neutral declarations

import std/[tables, options]
import ../../common/[hex, types/core]
import ../gamestate, ../orders
import ../diplomacy/[types as dip_types, engine as dip_engine, proposals as dip_proposals]
import ../config/diplomacy_config
import ../prestige
import ../intelligence/diplomatic_intel

proc resolveDiplomaticActions*(state: var GameState, orders: Table[HouseId, OrderPacket]) =
  ## Process diplomatic actions (per gameplay.md:1.3.3 - Command Phase)
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]

      for action in packet.diplomaticActions:
        case action.actionType
        of DiplomaticActionType.ProposeNonAggressionPact:
          # Pact proposal system per docs/architecture/diplomacy_proposals.md
          # Creates pending proposal that target must accept/reject
          echo "    ", houseId, " proposed Non-Aggression Pact to ", action.targetHouse

          if action.targetHouse in state.houses and not state.houses[action.targetHouse].eliminated:
            # Check if proposer can form pacts (not isolated)
            if not dip_types.canFormPact(state.houses[houseId].violationHistory):
              echo "      Proposal blocked: proposer is diplomatically isolated"
            else:
              # Create pending proposal
              let proposal = dip_proposals.PendingProposal(
                id: dip_proposals.generateProposalId(state.turn, houseId, action.targetHouse),
                proposer: houseId,
                target: action.targetHouse,
                proposalType: dip_proposals.ProposalType.NonAggressionPact,
                submittedTurn: state.turn,
                expiresIn: 3,  # 3 turns to respond
                status: dip_proposals.ProposalStatus.Pending,
                message: action.message.get("")
              )
              state.pendingProposals.add(proposal)
              echo "      Proposal created (expires in 3 turns)"

        of DiplomaticActionType.AcceptProposal:
          # Accept pending proposal
          if action.proposalId.isNone:
            echo "    ERROR: AcceptProposal missing proposalId"
            continue

          let proposalId = action.proposalId.get()
          let proposalIndex = dip_proposals.findProposalIndex(state.pendingProposals, proposalId)

          if proposalIndex < 0:
            echo "    ERROR: Proposal ", proposalId, " not found"
            continue

          var proposal = state.pendingProposals[proposalIndex]

          if proposal.target != houseId:
            echo "    ERROR: ", houseId, " cannot accept proposal not targeted at them"
            continue

          if proposal.status != dip_proposals.ProposalStatus.Pending:
            echo "    ERROR: Proposal ", proposalId, " is not pending (status: ", proposal.status, ")"
            continue

          echo "    ", houseId, " accepted Non-Aggression Pact from ", proposal.proposer

          # Establish pact for both houses
          let eventOpt1 = dip_engine.proposePact(
            state.houses[proposal.proposer].diplomaticRelations,
            houseId,
            state.houses[proposal.proposer].violationHistory,
            state.turn
          )

          let eventOpt2 = dip_engine.proposePact(
            state.houses[houseId].diplomaticRelations,
            proposal.proposer,
            state.houses[houseId].violationHistory,
            state.turn
          )

          if eventOpt1.isSome and eventOpt2.isSome:
            proposal.status = dip_proposals.ProposalStatus.Accepted
            state.pendingProposals[proposalIndex] = proposal
            echo "      Pact established"

            # Generate intelligence reports for all houses
            diplomatic_intel.generatePactFormedIntel(
              state,
              proposal.proposer,
              houseId,
              "Non-Aggression",
              state.turn
            )
          else:
            echo "      Pact establishment failed (blocked)"

        of DiplomaticActionType.RejectProposal:
          # Reject pending proposal
          if action.proposalId.isNone:
            echo "    ERROR: RejectProposal missing proposalId"
            continue

          let proposalId = action.proposalId.get()
          let proposalIndex = dip_proposals.findProposalIndex(state.pendingProposals, proposalId)

          if proposalIndex < 0:
            echo "    ERROR: Proposal ", proposalId, " not found"
            continue

          var proposal = state.pendingProposals[proposalIndex]

          if proposal.target != houseId:
            echo "    ERROR: ", houseId, " cannot reject proposal not targeted at them"
            continue

          if proposal.status != dip_proposals.ProposalStatus.Pending:
            echo "    ERROR: Proposal ", proposalId, " is not pending (status: ", proposal.status, ")"
            continue

          echo "    ", houseId, " rejected Non-Aggression Pact from ", proposal.proposer
          proposal.status = dip_proposals.ProposalStatus.Rejected
          state.pendingProposals[proposalIndex] = proposal

        of DiplomaticActionType.WithdrawProposal:
          # Withdraw own proposal
          if action.proposalId.isNone:
            echo "    ERROR: WithdrawProposal missing proposalId"
            continue

          let proposalId = action.proposalId.get()
          let proposalIndex = dip_proposals.findProposalIndex(state.pendingProposals, proposalId)

          if proposalIndex < 0:
            echo "    ERROR: Proposal ", proposalId, " not found"
            continue

          var proposal = state.pendingProposals[proposalIndex]

          if proposal.proposer != houseId:
            echo "    ERROR: ", houseId, " cannot withdraw proposal from ", proposal.proposer
            continue

          if proposal.status != dip_proposals.ProposalStatus.Pending:
            echo "    ERROR: Proposal ", proposalId, " is not pending (status: ", proposal.status, ")"
            continue

          echo "    ", houseId, " withdrew Non-Aggression Pact proposal to ", proposal.target
          proposal.status = dip_proposals.ProposalStatus.Withdrawn
          state.pendingProposals[proposalIndex] = proposal

        of DiplomaticActionType.BreakPact:
          # Breaking a pact triggers violation penalties (diplomacy.md:8.1.2)
          echo "    ", houseId, " breaking pact with ", action.targetHouse

          # Check if there's actually a pact to break
          let currentState = dip_engine.getDiplomaticState(
            state.houses[houseId].diplomaticRelations,
            action.targetHouse
          )

          if currentState == dip_types.DiplomaticState.NonAggression:
            # Record violation
            discard dip_engine.recordViolation(
              state.houses[houseId].violationHistory,
              houseId,
              action.targetHouse,
              state.turn,
              "Broke Non-Aggression Pact"
            )

            # Apply prestige penalties
            # CRITICAL: Get house once, modify all fields, write back to persist
            var house = state.houses[houseId]

            let prestigeEvents = dip_engine.applyViolationPenalties(
              houseId,
              action.targetHouse,
              house.violationHistory,
              state.turn
            )

            for event in prestigeEvents:
              house.prestige += event.amount
              echo "      ", event.description, ": ", event.amount, " prestige"

            # Apply dishonored status (duration per config/diplomacy.toml)
            # EXCEPTION: No dishonor for final confrontation (only 2 houses left)
            if not state.isFinalConfrontation():
              let config = globalDiplomacyConfig
              house.dishonoredStatus = dip_types.DishonoredStatus(
                active: true,
                turnsRemaining: config.pact_violations.dishonored_status_turns,
                violationTurn: state.turn
              )
              echo "      Dishonored for ", config.pact_violations.dishonored_status_turns, " turns"
            else:
              echo "      Dishonor waived (final confrontation)"

            # Apply diplomatic isolation (5 turns per diplomacy.md:8.1.2)
            if not state.isFinalConfrontation():
              house.diplomaticIsolation = dip_types.DiplomaticIsolation(
                active: true,
                turnsRemaining: 5,
                violationTurn: state.turn
              )
              echo "      Isolated for 5 turns"
            else:
              echo "      Isolation waived (final confrontation)"

            # Set status to Enemy
            dip_engine.setDiplomaticState(
              house.diplomaticRelations,
              action.targetHouse,
              dip_types.DiplomaticState.Enemy,
              state.turn
            )

            # Write back modified house to persist all changes
            state.houses[houseId] = house

            # Generate intelligence reports - pact break leads to war
            diplomatic_intel.generateDiplomaticBreakIntel(
              state,
              houseId,
              action.targetHouse,
              "Non-Aggression Pact",
              state.turn
            )
            diplomatic_intel.generateWarDeclarationIntel(
              state,
              houseId,
              action.targetHouse,
              state.turn
            )
          else:
            echo "      No pact exists to break"

        of DiplomaticActionType.DeclareEnemy:
          echo "    ", houseId, " declared ", action.targetHouse, " as Enemy"
          dip_engine.setDiplomaticState(
            state.houses[houseId].diplomaticRelations,
            action.targetHouse,
            dip_types.DiplomaticState.Enemy,
            state.turn
          )

          # Generate war declaration intelligence
          diplomatic_intel.generateWarDeclarationIntel(
            state,
            houseId,
            action.targetHouse,
            state.turn
          )

        of DiplomaticActionType.SetNeutral:
          echo "    ", houseId, " set ", action.targetHouse, " to Neutral"
          dip_engine.setDiplomaticState(
            state.houses[houseId].diplomaticRelations,
            action.targetHouse,
            dip_types.DiplomaticState.Neutral,
            state.turn
          )

          # Generate peace treaty intelligence
          diplomatic_intel.generatePeaceTreatyIntel(
            state,
            houseId,
            action.targetHouse,
            state.turn
          )
