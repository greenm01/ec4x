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
import types as res_types  # For GameEvent
import event_factory/init as event_factory

proc resolveDiplomaticActions*(state: var GameState,
                                orders: Table[HouseId, OrderPacket],
                                events: var seq[res_types.GameEvent]) =
  ## Process diplomatic actions (per gameplay.md:1.3.3 - Command Phase)
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]

      for action in packet.diplomaticActions:
        case action.actionType
        of DiplomaticActionType.DeclareHostile:
          logResolve("Declared Hostile",
                     "declarer=", $houseId, " target=", $action.targetHouse)

          # Get old state before change
          let oldState = dip_engine.getDiplomaticState(
            state.houses[houseId].diplomaticRelations,
            action.targetHouse
          )

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

          # Emit DiplomaticRelationChanged event (Phase 7d)
          events.add(event_factory.diplomaticRelationChanged(
            houseId,
            action.targetHouse,
            oldState,
            dip_types.DiplomaticState.Hostile,
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
                                        events: var seq[res_types.GameEvent]) =
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

      # Emit DiplomaticRelationChanged event (Phase 7d)
      events.add(event_factory.diplomaticRelationChanged(
        event.detectorHouse,
        event.owner,
        currentState,
        dip_types.DiplomaticState.Hostile,
        "Spy scout detected"
      ))

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
