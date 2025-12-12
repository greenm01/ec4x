## RBA Event Subscription System
## Enables AI reactive behavior during turn resolution
##
## Architecture: Engine fires events → Fog-of-war filter → RBA subscribes
## AI updates threat assessments and priorities based on observed events

import std/[tables, options, sequtils]
import ../common/types
import ../../engine/[gamestate, resolution/types as event_types]
import ../../engine/intelligence/event_processor/visibility
import ../../common/types/core
import ./controller_types

# =============================================================================
# Event Handler Types
# =============================================================================

type
  EventHandler* = proc(
    controller: var AIController,
    state: GameState,
    event: event_types.GameEvent
  ) {.nimcall.}
    ## Handler function that processes an event and updates AI state
    ## Does NOT generate orders - only updates internal state

  EventSubscription* = object
    ## Subscription configuration for RBA event handlers
    houseId*: HouseId
    handlers*: Table[event_types.GameEventType, seq[EventHandler]]
    allEventsHandler*: Option[EventHandler]

# =============================================================================
# Subscription Builder
# =============================================================================

proc newEventSubscription*(houseId: HouseId): EventSubscription =
  ## Create a new event subscription for a house
  result = EventSubscription(
    houseId: houseId,
    handlers: initTable[event_types.GameEventType, seq[EventHandler]](),
    allEventsHandler: none(EventHandler)
  )

proc subscribe*(
  sub: var EventSubscription,
  eventType: event_types.GameEventType,
  handler: EventHandler
) =
  ## Subscribe to specific event type
  if not sub.handlers.hasKey(eventType):
    sub.handlers[eventType] = @[]
  sub.handlers[eventType].add(handler)

proc subscribeToAll*(
  sub: var EventSubscription,
  handler: EventHandler
) =
  ## Subscribe to all observable events (fog-of-war filtered)
  sub.allEventsHandler = some(handler)

# =============================================================================
# Event Delivery
# =============================================================================

proc deliverEvent*(
  sub: EventSubscription,
  controller: var AIController,
  state: GameState,
  event: event_types.GameEvent
) =
  ## Deliver a single event to subscribed handlers (fog-of-war checked)
  ##
  ## Process:
  ## 1. Check fog-of-war visibility (shouldHouseSeeEvent)
  ## 2. If visible, call type-specific handlers
  ## 3. If visible, call all-events handler
  ## 4. Handlers update AIController state (threat assessments, priorities)

  # Fog-of-war check: Can this house see this event?
  if not visibility.shouldHouseSeeEvent(state, sub.houseId, event):
    return  # Event not visible to this house

  # Call type-specific handlers
  if sub.handlers.hasKey(event.eventType):
    for handler in sub.handlers[event.eventType]:
      handler(controller, state, event)

  # Call all-events handler
  if sub.allEventsHandler.isSome:
    sub.allEventsHandler.get()(controller, state, event)

proc deliverEvents*(
  sub: EventSubscription,
  controller: var AIController,
  state: GameState,
  events: seq[event_types.GameEvent]
) =
  ## Deliver multiple events to subscribed handlers
  for event in events:
    deliverEvent(sub, controller, state, event)

# =============================================================================
# Default RBA Event Handlers
# =============================================================================

proc handleCombatEvent*(
  controller: var AIController,
  state: GameState,
  event: event_types.GameEvent
) =
  ## React to combat events (battles, bombardment, invasions)
  ## Updates threat assessments for systems where combat occurred

  # Extract system ID from event
  if event.systemId.isNone:
    return

  let systemId = event.systemId.get()

  # Update intelligence: Mark system as combat zone
  if controller.intelligence.hasKey(systemId):
    var report = controller.intelligence[systemId]
    report.lastUpdated = state.turn
    # Increase estimated fleet strength for systems with active combat
    report.estimatedFleetStrength += 20  # Combat indicates significant forces
    report.confidenceLevel = 0.9  # High confidence from direct observation
    controller.intelligence[systemId] = report

  # If this is a fleet destroyed event involving our fleets, note threat
  if event.eventType == event_types.GameEventType.FleetDestroyed:
    if event.houseId.isSome and event.houseId.get() == controller.houseId:
      # Our fleet was destroyed - update threat assessment in this system
      if controller.intelligence.hasKey(systemId):
        var report = controller.intelligence[systemId]
        report.estimatedFleetStrength += 50  # Enemy has significant strength here
        report.confidenceLevel = 1.0  # Absolute confidence from direct combat
        controller.intelligence[systemId] = report

proc handleDiplomaticEvent*(
  controller: var AIController,
  state: GameState,
  event: event_types.GameEvent
) =
  ## React to diplomatic events (war declarations, peace treaties, etc.)
  ## Updates threat assessments based on diplomatic state changes

  case event.eventType
  of event_types.GameEventType.WarDeclared:
    # Someone declared war - update threat assessments
    if event.sourceHouseId.isSome and event.targetHouseId.isSome:
      let attacker = event.sourceHouseId.get()
      let target = event.targetHouseId.get()

      # If we're the target, escalate threat assessment for attacker's systems
      if target == controller.houseId:
        for systemId, report in controller.intelligence.mpairs:
          if report.owner.isSome and report.owner.get() == attacker:
            # Increase estimated threat from attacker
            report.estimatedFleetStrength += 30
            report.lastUpdated = state.turn

      # If we're the attacker, mark our intelligence as outdated (need recon)
      if attacker == controller.houseId:
        for systemId, report in controller.intelligence.mpairs:
          if report.owner.isSome and report.owner.get() == target:
            # Mark target systems for reconnaissance
            report.lastUpdated = state.turn - 5  # Fake old intel to trigger recon

  of event_types.GameEventType.PeaceSigned:
    # Peace treaty signed - reduce threat estimates
    if event.sourceHouseId.isSome and event.targetHouseId.isSome:
      let house1 = event.sourceHouseId.get()
      let house2 = event.targetHouseId.get()

      # If we're involved in peace treaty, reduce threat estimates
      if house1 == controller.houseId or house2 == controller.houseId:
        let otherHouse = if house1 == controller.houseId: house2 else: house1
        for systemId, report in controller.intelligence.mpairs:
          if report.owner.isSome and report.owner.get() == otherHouse:
            # Reduce perceived threat from peaceful house
            report.estimatedFleetStrength = (report.estimatedFleetStrength * 70) div
                100  # 30% reduction
            report.lastUpdated = state.turn

  of event_types.GameEventType.DiplomaticRelationChanged:
    # Generic diplomatic state change - update intelligence freshness
    if event.newState.isSome and event.targetHouseId.isSome:
      let targetHouse = event.targetHouseId.get()
      # Refresh intelligence on houses we have diplomatic contact with
      for systemId, report in controller.intelligence.mpairs:
        if report.owner.isSome and report.owner.get() == targetHouse:
          report.lastUpdated = state.turn

  else:
    discard  # Other diplomatic events don't affect threat assessment

proc handleEspionageEvent*(
  controller: var AIController,
  state: GameState,
  event: event_types.GameEvent
) =
  ## React to espionage events (spy missions detected, intelligence theft, etc.)
  ## Updates counter-intelligence priorities

  case event.eventType
  of event_types.GameEventType.SpyMissionDetected:
    # Someone tried to spy on us - increase counter-intel priority
    if event.targetHouseId.isSome and event.targetHouseId.get() ==
        controller.houseId:
      # TODO: Increment counter-intelligence priority (future enhancement)
      # For now, just log that we detected espionage
      discard

  of event_types.GameEventType.IntelligenceTheftExecuted:
    # Someone stole our intelligence - our intel is compromised
    if event.targetHouseId.isSome and event.targetHouseId.get() ==
        controller.houseId:
      # TODO: Mark intelligence as compromised, consider changing strategies
      discard

  else:
    discard  # Other espionage events handled by intelligence system

proc handleColonyEvent*(
  controller: var AIController,
  state: GameState,
  event: event_types.GameEvent
) =
  ## React to colony events (captured, established, eliminated)
  ## Updates strategic priorities based on territorial changes

  if event.systemId.isNone:
    return

  let systemId = event.systemId.get()

  case event.eventType
  of event_types.GameEventType.ColonyCaptured:
    # Colony captured - update intelligence on new owner
    if event.targetHouseId.isSome:
      let newOwner = event.targetHouseId.get()
      if controller.intelligence.hasKey(systemId):
        var report = controller.intelligence[systemId]
        report.owner = some(newOwner)
        report.lastUpdated = state.turn
        report.hasColony = true
        # Update threat assessment based on who captured it
        if newOwner == controller.houseId:
          report.estimatedFleetStrength = 0  # We control it now
        else:
          report.estimatedFleetStrength += 40  # Enemy has forces here
        report.confidenceLevel = 1.0  # Absolute confidence from direct observation
        controller.intelligence[systemId] = report

  of event_types.GameEventType.ColonyEstablished:
    # New colony established - add to intelligence
    if event.houseId.isSome:
      let owner = event.houseId.get()
      var newReport = IntelligenceReport(
        systemId: systemId,
        lastUpdated: state.turn,
        hasColony: true,
        owner: some(owner),
        estimatedFleetStrength: if owner == controller.houseId: 0 else: 10,
        estimatedDefenses: 0,  # New colony has minimal defenses
        planetClass: none(PlanetClass),
        resources: none(ResourceRating),
        confidenceLevel: 1.0  # High confidence from direct observation
      )
      controller.intelligence[systemId] = newReport

  else:
    discard

proc handleFleetEvent*(
  controller: var AIController,
  state: GameState,
  event: event_types.GameEvent
) =
  ## React to fleet events (movement, encounters, merges)
  ## Updates operational awareness

  # TODO: Future enhancement - track enemy fleet movements
  # For now, fleet events primarily update intelligence database
  # which is already handled by the intelligence processor
  discard

# =============================================================================
# Default Subscription Setup
# =============================================================================

proc createDefaultRBASubscription*(houseId: HouseId): EventSubscription =
  ## Create default event subscription for RBA with standard handlers
  result = newEventSubscription(houseId)

  # Combat events - critical for threat assessment
  result.subscribe(event_types.GameEventType.Battle, handleCombatEvent)
  result.subscribe(event_types.GameEventType.BattleOccurred, handleCombatEvent)
  result.subscribe(event_types.GameEventType.FleetDestroyed, handleCombatEvent)
  result.subscribe(event_types.GameEventType.Bombardment, handleCombatEvent)
  result.subscribe(event_types.GameEventType.SystemCaptured, handleCombatEvent)

  # Diplomatic events - affects strategic priorities
  result.subscribe(event_types.GameEventType.WarDeclared, handleDiplomaticEvent)
  result.subscribe(event_types.GameEventType.PeaceSigned, handleDiplomaticEvent)
  result.subscribe(
    event_types.GameEventType.DiplomaticRelationChanged, handleDiplomaticEvent)

  # Espionage events - counter-intelligence awareness
  result.subscribe(
    event_types.GameEventType.SpyMissionDetected, handleEspionageEvent)
  result.subscribe(
    event_types.GameEventType.IntelligenceTheftExecuted, handleEspionageEvent)

  # Colony events - territorial awareness
  result.subscribe(event_types.GameEventType.ColonyCaptured, handleColonyEvent)
  result.subscribe(event_types.GameEventType.ColonyEstablished,
      handleColonyEvent)

  # Fleet events - operational awareness
  result.subscribe(event_types.GameEventType.FleetEncounter, handleFleetEvent)
  result.subscribe(event_types.GameEventType.FleetMerged, handleFleetEvent)
