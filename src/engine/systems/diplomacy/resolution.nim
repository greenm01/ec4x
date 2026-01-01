## Diplomatic action resolution
##
## This module handles all diplomatic action resolution including:
## - Non-Aggression Pact proposals, acceptance, rejection
## - Pact breaking with violation penalties
## - Enemy/Neutral declarations

import std/[tables, logging]
import ../../types/[core, game_state, diplomacy, command, event]
import ../../state/iterators
import ./engine as dip_engine
import ../../intel/diplomatic_intel
import ../../event_factory/init as event_factory

proc resolveDiplomaticActions*(
    state: var GameState,
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
          info "Declared Hostile: declarer=", $houseId, " target=", $action.targetHouse

          # Get old state before change
          let key = (houseId, action.targetHouse)
          let oldState =
            if key in state.diplomaticRelation:
              state.diplomaticRelation[key].state
            else:
              DiplomaticState.Neutral

          # Update diplomatic state via engine
          discard dip_engine.setHostile(state, houseId, action.targetHouse, state.turn)

          # Emit DiplomaticRelationChanged event (Phase 7d)
          events.add(
            event_factory.diplomaticRelationChanged(
              houseId, action.targetHouse, oldState, DiplomaticState.Hostile,
              "Hostility declared",
            )
          )

          # Generate hostility declaration intelligence
          diplomatic_intel.generateHostilityDeclarationIntel(
            state, houseId, action.targetHouse, state.turn
          )
        of DiplomaticActionType.DeclareEnemy:
          info "Declared Enemy: declarer=", $houseId, " target=", $action.targetHouse

          # Update diplomatic state via engine
          discard dip_engine.declareWar(state, houseId, action.targetHouse, state.turn)

          # Emit WarDeclared event (Phase 7d)
          events.add(event_factory.warDeclared(houseId, action.targetHouse))

          # Generate war declaration intelligence
          diplomatic_intel.generateWarDeclarationIntel(
            state, houseId, action.targetHouse, state.turn
          )
        of DiplomaticActionType.SetNeutral:
          info "Set to Neutral: house=", $houseId, " target=", $action.targetHouse

          # Update diplomatic state via engine
          discard dip_engine.setNeutral(state, houseId, action.targetHouse, state.turn)

          # Emit PeaceSigned event (Phase 7d)
          events.add(event_factory.peaceSigned(houseId, action.targetHouse))

          # Generate peace treaty intelligence
          diplomatic_intel.generatePeaceTreatyIntel(
            state, houseId, action.targetHouse, state.turn
          )

proc resolveScoutDetectionEscalations*(
    state: var GameState, events: var seq[event.GameEvent]
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
