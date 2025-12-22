## Diplomatic Event Factory
## Events for diplomatic state changes
##
## DRY Principle: Single source of truth for diplomatic event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../types/[core, diplomacy, event as event_types]

# Export event_types alias for GameEvent types
export event_types

proc warDeclared*(
  declaringHouse: HouseId,
  targetHouse: HouseId
): event_types.GameEvent =
  ## Create event for war declaration
  event_types.GameEvent(
    eventType: event_types.GameEventType.WarDeclared, # Specific event type
    houseId: some(declaringHouse),
    description: &"{declaringHouse} declared war on {targetHouse}",
    systemId: none(SystemId),
    sourceHouseId: some(declaringHouse),
    targetHouseId: some(targetHouse),
    action: some("DeclareWar"), # Specific action field for case branch
    success: some(true),
    newState: some(DiplomaticState.Enemy),
    changeReason: some("War declared")
  )

proc peaceSigned*(
  house1: HouseId,
  house2: HouseId
): event_types.GameEvent =
  ## Create event for peace treaty
  event_types.GameEvent(
    eventType: event_types.GameEventType.PeaceSigned, # Specific event type
    houseId: some(house1),
    description: &"Peace treaty signed between {house1} and {house2}",
    systemId: none(SystemId),
    sourceHouseId: some(house1), # One of the signing parties
    targetHouseId: some(house2), # The other signing party
    action: some("ProposePeace"), # Specific action field for case branch
    success: some(true),
    newState: some(DiplomaticState.Neutral), # Assuming peace leads to neutral
    changeReason: some("Peace treaty signed")
  )

proc diplomaticRelationChanged*(
  sourceHouse: HouseId,
  targetHouse: HouseId,
  oldState: DiplomaticState,
  newState: DiplomaticState,
  reasonStr: string
): event_types.GameEvent =
  ## Create event for any diplomatic state change with reason
  event_types.GameEvent(
    eventType: event_types.GameEventType.DiplomaticRelationChanged,
    houseId: some(sourceHouse),
    description: &"{sourceHouse} changed diplomatic state with {targetHouse}: {oldState} → {newState} ({reasonStr})",
    systemId: none(SystemId),
    sourceHouseId: some(sourceHouse),
    targetHouseId: some(targetHouse),
    action: some("ChangeDiplomaticState"),
    success: some(true),
    oldState: some(oldState),
    newState: some(newState),
    changeReason: some(reasonStr)
  )

proc treatyProposed*(
  proposer: HouseId,
  target: HouseId,
  treatyType: string
): event_types.GameEvent =
  ## Create event for treaty proposal
  event_types.GameEvent(
    eventType: event_types.GameEventType.TreatyProposed,
    houseId: some(proposer),
    description: &"{proposer} proposed {treatyType} to {target}",
    systemId: none(SystemId),
    sourceHouseId: some(proposer),
    targetHouseId: some(target),
    action: some("ProposeTreaty"),
    proposalType: some(treatyType),
    success: some(true),
    changeReason: some("Treaty proposal submitted")
  )

proc treatyAccepted*(
  accepter: HouseId,
  proposer: HouseId,
  treatyType: string
): event_types.GameEvent =
  ## Create event for treaty acceptance
  event_types.GameEvent(
    eventType: event_types.GameEventType.TreatyAccepted,
    houseId: some(accepter),
    description: &"{accepter} accepted {treatyType} from {proposer}",
    systemId: none(SystemId),
    sourceHouseId: some(accepter),
    targetHouseId: some(proposer),
    action: some("AcceptTreaty"),
    proposalType: some(treatyType),
    success: some(true),
    changeReason: some("Treaty accepted")
  )

proc treatyBroken*(
  breaker: HouseId,
  victim: HouseId,
  treatyType: string,
  violationReason: string
): event_types.GameEvent =
  ## Create event for treaty violation/broken
  event_types.GameEvent(
    eventType: event_types.GameEventType.TreatyBroken,
    houseId: some(breaker),
    description: &"{breaker} broke {treatyType} with {victim} ({violationReason})",
    systemId: none(SystemId),
    sourceHouseId: some(breaker),
    targetHouseId: some(victim),
    action: some("BreakTreaty"),
    proposalType: some(treatyType),
    success: some(true),
    changeReason: some(violationReason)
  )

