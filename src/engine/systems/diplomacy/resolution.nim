## Diplomatic action resolution
##
## This module handles all diplomatic action resolution including:
## - Non-Aggression Pact proposals, acceptance, rejection
## - Pact breaking with violation penalties
## - Enemy/Neutral declarations

import std/[tables, options]
import ../../types/[core, game_state, diplomacy, command, event]
import ../../state/iterators
import ../../../common/logger
import ./engine
import ./proposals
import ../../event_factory/init

proc resolveDiplomaticActions*(
    state: GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[event.GameEvent],
) =
  ## Process diplomatic actions (per gameplay.md:1.3.3 - Command Phase)
  for (houseId, house) in state.allHousesWithId():
    if houseId in orders:
      let packet = orders[houseId]

      for action in packet.diplomaticCommand:
        case action.actionType
        of DiplomaticActionType.DeclareHostile:
          logInfo("Diplomacy", "Declared Hostile",
            "declarer=", $houseId, " target=", $action.targetHouse)

          # Get old state before change
          let key = (houseId, action.targetHouse)
          let oldState =
            if key in state.diplomaticRelation:
              state.diplomaticRelation[key].state
            else:
              DiplomaticState.Neutral

          # Update diplomatic state via engine
          discard state.setHostile(houseId, action.targetHouse, state.turn)

          # Emit DiplomaticRelationChanged event (Phase 7d)
          events.add(
            diplomaticRelationChanged(
              houseId, action.targetHouse, oldState, DiplomaticState.Hostile,
              "Hostility declared",
            )
          )
        of DiplomaticActionType.DeclareEnemy:
          logInfo("Diplomacy", "Declared Enemy",
            "declarer=", $houseId, " target=", $action.targetHouse)

          # Update diplomatic state via engine
          discard state.declareWar(houseId, action.targetHouse, state.turn)

          # Emit WarDeclared event (Phase 7d)
          events.add(warDeclared(houseId, action.targetHouse))
        of DiplomaticActionType.SetNeutral:
          logInfo("Diplomacy", "Set to Neutral",
            "house=", $houseId, " target=", $action.targetHouse)

          # Update diplomatic state via engine
          discard state.setNeutral(houseId, action.targetHouse, state.turn)

          # Emit PeaceSigned event (Phase 7d)
          events.add(peaceSigned(houseId, action.targetHouse))
        
        of DiplomaticActionType.ProposeDeescalation:
          logInfo("Diplomacy", "Propose De-escalation",
            "proposer=", $houseId, " target=", $action.targetHouse)
          
          # Validate proposal type is provided
          if action.proposalType.isNone:
            logError("Diplomacy", "ProposeDeescalation missing proposalType field")
            continue
          
          let targetState = case action.proposalType.get()
            of ProposalType.DeescalateToNeutral:
              DiplomaticState.Neutral
            of ProposalType.DeescalateToHostile:
              DiplomaticState.Hostile
          
          # Get current diplomatic state
          let key = (houseId, action.targetHouse)
          if not state.diplomaticRelation.hasKey(key):
            logError("Diplomacy", "No diplomatic relation exists",
              "between=", $houseId, " and ", $action.targetHouse)
            continue
          
          let currentState = state.diplomaticRelation[key].state
          
          # Validate de-escalation is possible
          if not canProposeDeescalation(currentState, targetState):
            logError("Diplomacy", "Invalid de-escalation",
              $currentState, " -> ", $targetState)
            continue
          
          # Create proposal
          let proposal = createDeescalationProposal(
            state, houseId, action.targetHouse, targetState, state.turn
          )
          
          # Add to pending proposals
          state.pendingProposals.add(proposal)
          
          # Generate TreatyProposed event
          let proposalTypeName = case action.proposalType.get()
            of ProposalType.DeescalateToNeutral:
              "De-escalation to Neutral"
            of ProposalType.DeescalateToHostile:
              "De-escalation to Hostile"
          
          events.add(
            treatyProposed(
              houseId, action.targetHouse, proposalTypeName
            )
          )
          
          logInfo("Diplomacy", "Proposal created",
            "id=", $proposal.id, " expires=", $proposal.expiresOnTurn)
        
        of DiplomaticActionType.AcceptProposal:
          logInfo("Diplomacy", "Accept Proposal", "accepter=", $houseId)
          
          # Validate proposalId is provided
          if action.proposalId.isNone:
            logError("Diplomacy", "AcceptProposal missing proposalId field")
            continue
          
          let proposalId = action.proposalId.get()
          
          # Find proposal
          let proposalIdx = findProposalIndex(state.pendingProposals, proposalId)
          if proposalIdx == -1:
            logError("Diplomacy", "Proposal not found", "id=", $proposalId)
            continue
          
          var proposal = state.pendingProposals[proposalIdx]
          
          # Validate this house is the target
          if proposal.target != houseId:
            logError("Diplomacy", "Cannot accept proposal targeted at another house",
              "house=", $houseId, " target=", $proposal.target)
            continue
          
          # Validate proposal is still pending
          if proposal.status != ProposalStatus.Pending:
            logError("Diplomacy", "Proposal is not pending",
              "id=", $proposalId, " status=", $proposal.status)
            continue
          
          # Get current diplomatic state
          let key = (proposal.proposer, proposal.target)
          if not state.diplomaticRelation.hasKey(key):
            logError("Diplomacy", "No diplomatic relation for proposal",
              "id=", $proposalId)
            continue
          
          let oldState = state.diplomaticRelation[key].state
          
          # Determine new state from proposal type
          let newState = case proposal.proposalType
            of ProposalType.DeescalateToNeutral:
              DiplomaticState.Neutral
            of ProposalType.DeescalateToHostile:
              DiplomaticState.Hostile
          
          # Apply the de-escalation
          case newState
          of DiplomaticState.Neutral:
            discard setNeutral(
              state, proposal.proposer, proposal.target, state.turn
            )
          of DiplomaticState.Hostile:
            discard setHostile(
              state, proposal.proposer, proposal.target, state.turn
            )
          of DiplomaticState.Enemy:
            logError("Diplomacy", "Cannot de-escalate to Enemy state")
            continue
          
          # Mark proposal as accepted
          proposal.status = ProposalStatus.Accepted
          state.pendingProposals[proposalIdx] = proposal
          
          # Generate events
          let proposalTypeName = case proposal.proposalType
            of ProposalType.DeescalateToNeutral:
              "De-escalation to Neutral"
            of ProposalType.DeescalateToHostile:
              "De-escalation to Hostile"
          
          events.add(
            treatyAccepted(
              houseId, proposal.proposer, proposalTypeName
            )
          )
          
          events.add(
            diplomaticRelationChanged(
              proposal.proposer,
              proposal.target,
              oldState,
              newState,
              "De-escalation proposal accepted",
            )
          )
          
          logInfo("Diplomacy", "Proposal accepted",
            "id=", $proposalId, " ", $oldState, " -> ", $newState)
        
        of DiplomaticActionType.RejectProposal:
          logInfo("Diplomacy", "Reject Proposal", "rejecter=", $houseId)
          
          # Validate proposalId is provided
          if action.proposalId.isNone:
            logError("Diplomacy", "RejectProposal missing proposalId field")
            continue
          
          let proposalId = action.proposalId.get()
          
          # Find proposal
          let proposalIdx = findProposalIndex(state.pendingProposals, proposalId)
          if proposalIdx == -1:
            logError("Diplomacy", "Proposal not found", "id=", $proposalId)
            continue
          
          var proposal = state.pendingProposals[proposalIdx]
          
          # Validate this house is the target
          if proposal.target != houseId:
            logError("Diplomacy", "Cannot reject proposal targeted at another house",
              "house=", $houseId, " target=", $proposal.target)
            continue
          
          # Validate proposal is still pending
          if proposal.status != ProposalStatus.Pending:
            logError("Diplomacy", "Proposal is not pending",
              "id=", $proposalId, " status=", $proposal.status)
            continue
          
          # Mark proposal as rejected
          proposal.status = ProposalStatus.Rejected
          state.pendingProposals[proposalIdx] = proposal
          
          # No diplomatic state change on rejection
          # No events generated (rejection is silent)
          
          logInfo("Diplomacy", "Proposal rejected", "id=", $proposalId)

proc resolveScoutDetectionEscalations*(
    state: GameState, events: var seq[event.GameEvent]
) =
  ## Process scout loss events and trigger appropriate diplomatic escalations
  ## NOTE: After Scout System Unification, only CombatLoss and TravelIntercepted remain
  ## Neither triggers escalation, so this function currently skips all events
  ## Escalation only goes UP, never down: Neutral → Hostile → Enemy
  ##
  ## Future: If spy scout detection is re-added, implement escalation logic here

  # All current scout loss event types (TravelIntercepted, CombatLoss) are non-escalating
  # Clear events without processing
  state.scoutLossEvents = @[]
