## Diplomatic action resolution
##
## This module handles all diplomatic action resolution including:
## - Non-Aggression Pact proposals, acceptance, rejection
## - Pact breaking with violation penalties
## - Enemy/Neutral declarations

import std/[tables, options, logging]
import ../../types/[core, game_state, diplomacy, orders]
import ./[engine as dip_engine, proposals as dip_proposals]
import ../../config/diplomacy_config
import ../prestige/engine as prestige
import ../intelligence/diplomatic_intel
import ../intelligence/types as intel_types  # For DetectionEventType
import ../event/types as event_types  # For GameEvent
import ../event/factory/init as event_factory

proc resolveDiplomaticActions*(state: var GameState,
                                orders: Table[HouseId, OrderPacket],
                                events: var seq[event_types.GameEvent]) =
  ## Process diplomatic actions (per gameplay.md:1.3.3 - Command Phase)
  for houseId, house in state.houses.entities.data:
    if houseId in orders:
      let packet = orders[houseId]

      for action in packet.diplomaticActions:
        case action.actionType
        of DiplomaticActionType.DeclareHostile:
          info "Declared Hostile: declarer=", $houseId, " target=", $action.targetHouse

          # Get old state before change
          let key = (houseId, action.targetHouse)
          let oldState = if key in state.diplomaticRelation:
            state.diplomaticRelation[key].state
          else:
            DiplomaticState.Neutral

          # Update diplomatic state via engine
          let diplomaticEvent = dip_engine.setHostile(
            state,
            houseId,
            action.targetHouse,
            state.turn
          )

          # Emit DiplomaticRelationChanged event (Phase 7d)
          events.add(event_factory.diplomaticRelationChanged(
            houseId,
            action.targetHouse,
            oldState,
            DiplomaticState.Hostile,
            "Hostility declared"
          ))

          # Generate hostility declaration intelligence
          diplomatic_intel.generateHostilityDeclarationIntel(
            state,
            houseId,
            action.targetHouse,
            state.turn
          )

        of DiplomaticActionType.DeclareEnemy:
          info "Declared Enemy: declarer=", $houseId, " target=", $action.targetHouse

          # Update diplomatic state via engine
          let diplomaticEvent = dip_engine.declareWar(
            state,
            houseId,
            action.targetHouse,
            state.turn
          )

          # Emit WarDeclared event (Phase 7d)
          events.add(event_factory.warDeclared(houseId, action.targetHouse))

          # Generate war declaration intelligence
          diplomatic_intel.generateWarDeclarationIntel(
            state,
            houseId,
            action.targetHouse,
            state.turn
          )

        of DiplomaticActionType.SetNeutral:
          info "Set to Neutral: house=", $houseId, " target=", $action.targetHouse

          # Update diplomatic state via engine
          let diplomaticEvent = dip_engine.setNeutral(
            state,
            houseId,
            action.targetHouse,
            state.turn
          )

          # Emit PeaceSigned event (Phase 7d)
          events.add(event_factory.peaceSigned(houseId, action.targetHouse))

          # Generate peace treaty intelligence
          diplomatic_intel.generatePeaceTreatyIntel(
            state,
            houseId,
            action.targetHouse,
            state.turn
          )

proc resolveScoutDetectionEscalations*(state: var GameState,
                                        events: var seq[event_types.GameEvent]) =
  ## Process scout loss events and trigger appropriate diplomatic escalations
  ## NOTE: After Scout System Unification, only CombatLoss and TravelIntercepted remain
  ## Neither triggers escalation, so this function currently skips all events
  ## Escalation only goes UP, never down: Neutral → Hostile → Enemy

  for event in state.scoutLossEvents:
    # TravelIntercepted and CombatLoss don't trigger escalation
    # All current event types are non-escalating
    continue

    # Skip if either house is eliminated
    if event.owner notin state.houses.entities.index or
       event.detectorHouse notin state.houses.entities.index:
      continue

    let ownerIdx = state.houses.entities.index[event.owner]
    let detectorIdx = state.houses.entities.index[event.detectorHouse]
    if state.houses.entities.data[ownerIdx].isEliminated or
       state.houses.entities.data[detectorIdx].isEliminated:
      continue

    # Get current diplomatic state
    let key = (event.detectorHouse, event.owner)
    let currentState = if key in state.diplomaticRelation:
      state.diplomaticRelation[key].state
    else:
      DiplomaticState.Neutral

    # Spy scout detection triggers Hostile escalation
    # Only escalate if currently Neutral (don't downgrade Enemy)
    if currentState == DiplomaticState.Neutral:
      # Escalate to Hostile
      let diplomaticEvent = dip_engine.setHostile(
        state,
        event.detectorHouse,
        event.owner,
        state.turn
      )

      # Emit DiplomaticRelationChanged event (Phase 7d)
      events.add(event_factory.diplomaticRelationChanged(
        event.detectorHouse,
        event.owner,
        currentState,
        DiplomaticState.Hostile,
        "Spy scout detected"
      ))

      info "Spy detection escalation: detector=", $event.detectorHouse,
           " spy_owner=", $event.owner, " escalated=Neutral → Hostile",
           " reason=spy scout detected"

      # Generate diplomatic intelligence about the escalation
      diplomatic_intel.generateHostilityDeclarationIntel(
        state,
        event.detectorHouse,
        event.owner,
        state.turn
      )

  # Clear processed events
  state.scoutLossEvents = @[]
