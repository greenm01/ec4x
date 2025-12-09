## Diplomatic action resolution
##
## This module handles all diplomatic action resolution including:
## - Non-Aggression Pact proposals, acceptance, rejection
## - Pact breaking with violation penalties
## - Enemy/Neutral declarations

import std/[tables, options]
import ../../common/[types/core, logger]
import ../gamestate, ../orders
import ../diplomacy/[types as dip_types, engine as dip_engine, proposals as dip_proposals]
import ../config/diplomacy_config
import ../prestige
import ../intelligence/diplomatic_intel
import ../intelligence/types as intel_types  # For DetectionEventType

proc resolveDiplomaticActions*(state: var GameState, orders: Table[HouseId, OrderPacket]) =
  ## Process diplomatic actions (per gameplay.md:1.3.3 - Command Phase)
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]

      for action in packet.diplomaticActions:
        case action.actionType
        of DiplomaticActionType.ProposeAllyPact:
          # Pact proposal system per docs/architecture/diplomacy_proposals.md
          # Creates pending proposal that target must accept/reject
          logResolve("Non-Aggression Pact proposed",
                     "proposer=", $houseId, " target=", $action.targetHouse)

          if action.targetHouse in state.houses and not state.houses[action.targetHouse].eliminated:
            # Check if proposer can form pacts (not isolated)
            if not dip_types.canFormPact(state.houses[houseId].violationHistory):
              logWarn("Diplomacy", "Proposal blocked - proposer is diplomatically isolated",
                      "house=", $houseId)
            else:
              # Create pending proposal
              let proposal = dip_proposals.PendingProposal(
                id: dip_proposals.generateProposalId(state.turn, houseId, action.targetHouse),
                proposer: houseId,
                target: action.targetHouse,
                proposalType: dip_proposals.ProposalType.AllyPact,
                submittedTurn: state.turn,
                expiresIn: 3,  # 3 turns to respond
                status: dip_proposals.ProposalStatus.Pending,
                message: action.message.get("")
              )
              state.pendingProposals.add(proposal)
              logResolve("Proposal created",
                        "proposalId=", proposal.id, " expires=3 turns")

        of DiplomaticActionType.AcceptProposal:
          # Accept pending proposal
          if action.proposalId.isNone:
            logError("Diplomacy", "AcceptProposal missing proposalId",
                     "house=", $houseId)
            continue

          let proposalId = action.proposalId.get()
          let proposalIndex = dip_proposals.findProposalIndex(state.pendingProposals, proposalId)

          if proposalIndex < 0:
            logError("Diplomacy", "Proposal not found",
                     "proposalId=", proposalId, " house=", $houseId)
            continue

          var proposal = state.pendingProposals[proposalIndex]

          if proposal.target != houseId:
            logError("Diplomacy", "Cannot accept proposal not targeted at them",
                     "house=", $houseId, " target=", $proposal.target)
            continue

          if proposal.status != dip_proposals.ProposalStatus.Pending:
            logError("Diplomacy", "Proposal is not pending",
                     "proposalId=", proposalId, " status=", $proposal.status)
            continue

          logResolve("Non-Aggression Pact accepted",
                     "acceptor=", $houseId, " proposer=", $proposal.proposer)

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
            logResolve("Pact established",
                      "proposer=", $proposal.proposer, " acceptor=", $houseId)

            # Generate intelligence reports for all houses
            diplomatic_intel.generatePactFormedIntel(
              state,
              proposal.proposer,
              houseId,
              "Non-Aggression",
              state.turn
            )
          else:
            logWarn("Diplomacy", "Pact establishment failed - blocked",
                    "proposer=", $proposal.proposer, " acceptor=", $houseId)

        of DiplomaticActionType.RejectProposal:
          # Reject pending proposal
          if action.proposalId.isNone:
            logError("Diplomacy", "RejectProposal missing proposalId",
                     "house=", $houseId)
            continue

          let proposalId = action.proposalId.get()
          let proposalIndex = dip_proposals.findProposalIndex(state.pendingProposals, proposalId)

          if proposalIndex < 0:
            logError("Diplomacy", "Proposal not found",
                     "proposalId=", proposalId, " house=", $houseId)
            continue

          var proposal = state.pendingProposals[proposalIndex]

          if proposal.target != houseId:
            logError("Diplomacy", "Cannot reject proposal not targeted at them",
                     "house=", $houseId, " target=", $proposal.target)
            continue

          if proposal.status != dip_proposals.ProposalStatus.Pending:
            logError("Diplomacy", "Proposal is not pending",
                     "proposalId=", proposalId, " status=", $proposal.status)
            continue

          logResolve("Non-Aggression Pact rejected",
                     "rejector=", $houseId, " proposer=", $proposal.proposer)
          proposal.status = dip_proposals.ProposalStatus.Rejected
          state.pendingProposals[proposalIndex] = proposal

        of DiplomaticActionType.WithdrawProposal:
          # Withdraw own proposal
          if action.proposalId.isNone:
            logError("Diplomacy", "WithdrawProposal missing proposalId",
                     "house=", $houseId)
            continue

          let proposalId = action.proposalId.get()
          let proposalIndex = dip_proposals.findProposalIndex(state.pendingProposals, proposalId)

          if proposalIndex < 0:
            logError("Diplomacy", "Proposal not found",
                     "proposalId=", proposalId, " house=", $houseId)
            continue

          var proposal = state.pendingProposals[proposalIndex]

          if proposal.proposer != houseId:
            logError("Diplomacy", "Cannot withdraw proposal from another house",
                     "house=", $houseId, " proposer=", $proposal.proposer)
            continue

          if proposal.status != dip_proposals.ProposalStatus.Pending:
            logError("Diplomacy", "Proposal is not pending",
                     "proposalId=", proposalId, " status=", $proposal.status)
            continue

          logResolve("Non-Aggression Pact proposal withdrawn",
                     "withdrawer=", $houseId, " target=", $proposal.target)
          proposal.status = dip_proposals.ProposalStatus.Withdrawn
          state.pendingProposals[proposalIndex] = proposal

        of DiplomaticActionType.BreakPact:
          # Breaking a pact triggers violation penalties (diplomacy.md:8.1.2)
          logResolve("Breaking pact",
                     "breaker=", $houseId, " target=", $action.targetHouse)

          # Check if there's actually a pact to break
          let currentState = dip_engine.getDiplomaticState(
            state.houses[houseId].diplomaticRelations,
            action.targetHouse
          )

          if currentState == dip_types.DiplomaticState.Ally:
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
              applyPrestigeEvent(state, houseId, event)
              logResolve("Violation prestige penalty",
                        "event=", event.description, " prestige=", $event.amount)

            # Apply dishonored status (duration per config/diplomacy.toml)
            # EXCEPTION: No dishonor for final confrontation (only 2 houses left)
            if not state.isFinalConfrontation():
              let config = globalDiplomacyConfig
              house.dishonoredStatus = dip_types.DishonoredStatus(
                active: true,
                turnsRemaining: config.pact_violations.dishonored_status_turns,
                violationTurn: state.turn
              )
              logResolve("Dishonored status applied",
                        "house=", $houseId, " turns=", $config.pact_violations.dishonored_status_turns)
            else:
              logDebug("Diplomacy", "Dishonor waived (final confrontation)",
                       "house=", $houseId)

            # Apply diplomatic isolation (5 turns per diplomacy.md:8.1.2)
            if not state.isFinalConfrontation():
              house.diplomaticIsolation = dip_types.DiplomaticIsolation(
                active: true,
                turnsRemaining: 5,
                violationTurn: state.turn
              )
              logResolve("Diplomatic isolation applied",
                        "house=", $houseId, " turns=5")
            else:
              logDebug("Diplomacy", "Isolation waived (final confrontation)",
                       "house=", $houseId)

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
            logWarn("Diplomacy", "No pact exists to break",
                    "house=", $houseId, " target=", $action.targetHouse)

        of DiplomaticActionType.DeclareHostile:
          logResolve("Declared Hostile",
                     "declarer=", $houseId, " target=", $action.targetHouse)

          # Get mutable copy of house to modify diplomatic relations
          var house = state.houses[houseId]
          dip_engine.setDiplomaticState(
            house.diplomaticRelations,
            action.targetHouse,
            dip_types.DiplomaticState.Hostile,
            state.turn
          )
          # Write back modified house to persist changes
          state.houses[houseId] = house

          # Generate hostility declaration intelligence
          diplomatic_intel.generateHostilityDeclarationIntel(
            state,
            houseId,
            action.targetHouse,
            state.turn
          )

        of DiplomaticActionType.DeclareEnemy:
          logResolve("Declared Enemy",
                     "declarer=", $houseId, " target=", $action.targetHouse)

          # Get mutable copy of house to modify diplomatic relations
          var house = state.houses[houseId]
          dip_engine.setDiplomaticState(
            house.diplomaticRelations,
            action.targetHouse,
            dip_types.DiplomaticState.Enemy,
            state.turn
          )
          # Write back modified house to persist changes
          state.houses[houseId] = house

          # Generate war declaration intelligence
          diplomatic_intel.generateWarDeclarationIntel(
            state,
            houseId,
            action.targetHouse,
            state.turn
          )

        of DiplomaticActionType.SetNeutral:
          logResolve("Set to Neutral",
                     "house=", $houseId, " target=", $action.targetHouse)

          # Get mutable copy of house to modify diplomatic relations
          var house = state.houses[houseId]
          dip_engine.setDiplomaticState(
            house.diplomaticRelations,
            action.targetHouse,
            dip_types.DiplomaticState.Neutral,
            state.turn
          )
          # Write back modified house to persist changes
          state.houses[houseId] = house

          # Generate peace treaty intelligence
          diplomatic_intel.generatePeaceTreatyIntel(
            state,
            houseId,
            action.targetHouse,
            state.turn
          )

proc resolveScoutDetectionEscalations*(state: var GameState) =
  ## Process scout loss events and trigger appropriate diplomatic escalations
  ## Per scout mechanics revision: SpyScoutDetected → Hostile escalation
  ## Escalation only goes UP, never down: Neutral → Hostile → Enemy

  for event in state.scoutLossEvents:
    # Only process SpyScoutDetected events for escalation
    # TravelIntercepted and CombatLoss don't trigger escalation
    if event.eventType != intel_types.DetectionEventType.SpyScoutDetected:
      continue

    # Skip if either house is eliminated
    if event.owner notin state.houses or event.detectorHouse notin state.houses:
      continue
    if state.houses[event.owner].eliminated or state.houses[event.detectorHouse].eliminated:
      continue

    # Get current diplomatic state
    let currentState = dip_engine.getDiplomaticState(
      state.houses[event.detectorHouse].diplomaticRelations,
      event.owner
    )

    # Spy scout detection triggers Hostile escalation
    # Only escalate if currently Neutral (don't downgrade Enemy)
    if currentState == dip_types.DiplomaticState.Neutral:
      # Escalate to Hostile
      var detectorHouse = state.houses[event.detectorHouse]
      dip_engine.setDiplomaticState(
        detectorHouse.diplomaticRelations,
        event.owner,
        dip_types.DiplomaticState.Hostile,
        state.turn
      )
      state.houses[event.detectorHouse] = detectorHouse

      logInfo("Diplomacy", "Spy detection escalation",
             "detector=", $event.detectorHouse,
             "spy_owner=", $event.owner,
             "escalated=", "Neutral → Hostile",
             "reason=", "spy scout detected")

      # Generate diplomatic intelligence about the escalation
      diplomatic_intel.generateHostilityDeclarationIntel(
        state,
        event.detectorHouse,
        event.owner,
        state.turn
      )

  # Clear processed events
  state.scoutLossEvents = @[]
