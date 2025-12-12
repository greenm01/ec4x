## Spy Scout Travel Resolution
## Implements jump lane travel for spy scouts per assets.md:2.4.2
##
## Spy scouts travel through jump lanes following normal movement rules:
## - Controlled major lanes: 2 jumps/turn
## - Minor/restricted lanes or rival territory: 1 jump/turn
## - Detection checks at each intermediate system

import std/[tables, options, strformat]
import ../../common/types/core
import ../gamestate, ../fleet, ../orders
import ../diplomacy/engine as dip_engine
import detection, types as intel_types
import ../resolution/[fleet_orders, types as resolution_types, event_factory/init as event_factory]

proc recordScoutLoss*(state: var GameState, scoutId: string,
                     eventType: intel_types.DetectionEventType,
                     detectorHouse: HouseId) =
  ## Record scout loss event for diplomatic processing
  if scoutId notin state.spyScouts:
    return  # Scout already removed

  let event = intel_types.ScoutLossEvent(
    scoutId: scoutId,
    owner: state.spyScouts[scoutId].owner,
    location: state.spyScouts[scoutId].location,
    detectorHouse: detectorHouse,
    eventType: eventType,
    turn: state.turn
  )

  state.scoutLossEvents.add(event)

proc checkTravelDetection(state: GameState, spyId: string,
                         systemId: SystemId): intel_types.DetectionResult =
  ## Check if traveling spy scout is detected in a system
  ## Uses same detection tables as stationary spy scouts
  ## Per assets.md detection tables in config/espionage.toml

  let spy = state.spyScouts[spyId]

  # Check detection by rival fleets
  for fleet in state.fleets.values:
    if fleet.location == systemId and fleet.owner != spy.owner:
      # Check diplomatic relations - neutral/friendly houses don't interdict
      let dipState = dip_engine.getDiplomaticState(
        state.houses[fleet.owner].diplomaticRelations,
        spy.owner
      )

      if dipState == DiplomaticState.Neutral:
        # Neutral houses allow safe passage but don't destroy scouts
        return intel_types.DetectionResult(
          detected: true,
          detectorHouse: fleet.owner,
          isAllyDetection: true,  # Flag for safe passage
          roll: 0,
          threshold: 0
        )

      let detectorUnit = createELIUnit(fleet.squadrons, isStarbase = false)
      if detectorUnit.eliLevels.len > 0:
        let detResult = detectSpyScout(detectorUnit, spy.eliLevel)
        if detResult.detected:
          return intel_types.DetectionResult(
            detected: true,
            detectorHouse: fleet.owner,
            isAllyDetection: false,
            roll: detResult.roll,
            threshold: detResult.threshold
          )

  # Check detection by starbases
  if systemId in state.colonies:
    let colony = state.colonies[systemId]
    if colony.owner != spy.owner:
      # Check diplomatic relations
      let dipState = dip_engine.getDiplomaticState(
        state.houses[colony.owner].diplomaticRelations,
        spy.owner
      )

      if dipState == DiplomaticState.Neutral:
        # Neutral detection - safe passage, no destruction
        return intel_types.DetectionResult(
          detected: true,
          detectorHouse: colony.owner,
          isAllyDetection: true,
          roll: 0,
          threshold: 0
        )

      if colony.starbases.len > 0:
        # Starbase detection with +2 bonus
        # Get highest ELI level from house
        # NOTE: ELI (Electronic Intelligence) is a specific military tech, NOT EL (Economic Level)
        let houseELI = state.houses[colony.owner].techTree.levels.electronicIntelligence
        let starbaseELI = ELIUnit(
          eliLevels: @[houseELI],
          isStarbase: true
        )

        let sbResult = detectSpyScout(starbaseELI, spy.eliLevel)
        if sbResult.detected:
          return intel_types.DetectionResult(
            detected: true,
            detectorHouse: colony.owner,
            isAllyDetection: false,
            roll: sbResult.roll,
            threshold: sbResult.threshold
          )

  return intel_types.DetectionResult(detected: false, detectorHouse: "",
                                     isAllyDetection: false, roll: 0, threshold: 0)

proc resolveSpyScoutTravel*(state: var GameState, events: var seq[resolution_types.GameEvent]): seq[string] =
  ## Move traveling spy scouts using centralized movement arbiter (DoD compliance)
  ## - Uses resolveMovementOrder() for all movement logic
  ## - Performs detection checks at intermediate systems
  ## - Emits SpyScoutTravel events (Phase 7b)
  result = @[]

  # Collect traveling spy scout IDs first (don't modify table during iteration)
  var travelingSpies: seq[string] = @[]
  for spyId, spy in state.spyScouts:
    if spy.state == SpyScoutState.Traveling:
      travelingSpies.add(spyId)

  # Process each traveling spy scout
  for spyId in travelingSpies:
    # Skip if spy scout was removed during processing (e.g., detected and destroyed)
    if spyId notin state.spyScouts:
      continue

    let spy = state.spyScouts[spyId]
    if spy.state != SpyScoutState.Traveling:
      continue

    # Check if target is still valid
    let targetSystem = spy.targetSystem
    var missionAborted = false
    var abortReason = ""

    # Check mission-specific abort conditions
    case spy.mission
    of SpyMissionType.SpyOnPlanet, SpyMissionType.SpyOnSystem:
      # Target colony lost (destroyed or uncolonized)
      if targetSystem notin state.colonies:
        missionAborted = true
        abortReason = "target colony no longer exists"
      else:
        # Target house eliminated
        let colony = state.colonies[targetSystem]
        if colony.owner in state.houses:
          if state.houses[colony.owner].eliminated:
            missionAborted = true
            abortReason = "target house eliminated"
    of SpyMissionType.HackStarbase:
      # Target starbase destroyed
      if targetSystem notin state.colonies:
        missionAborted = true
        abortReason = "target colony no longer exists"
      else:
        let colony = state.colonies[targetSystem]
        if colony.starbases.len == 0:
          missionAborted = true
          abortReason = "target starbase destroyed"
        elif colony.owner in state.houses:
          if state.houses[colony.owner].eliminated:
            missionAborted = true
            abortReason = "target house eliminated"

    if missionAborted:
      # Mission no longer viable - abort
      # Note: Events not added here due to function signature limitations
      # Scout removal is sufficient for game logic
      state.spyScouts.del(spyId)
      result.add(&"Spy scout {spyId} {spy.mission} aborted: {abortReason}")
      continue

    # Determine target for this turn's movement
    # Scout moves toward final targetSystem

    # Create movement order for spy scout
    let moveOrder = FleetOrder(
      fleetId: spyId,  # Spy scout ID used as fleet ID
      orderType: FleetOrderType.Move,
      targetSystem: some(targetSystem),
      targetFleet: none(FleetId),
      priority: 0
    )

    # Use centralized movement arbiter (DoD compliance)
    var events: seq[resolution_types.GameEvent] = @[]
    let oldLocation = spy.location

    fleet_orders.resolveMovementOrder(
      state,
      spy.owner,
      moveOrder,
      events,
      spyScoutId = some(spyId)  # Signals spy scout mode
    )

    # Check if scout still exists after movement (could be removed by house elimination)
    if spyId notin state.spyScouts:
      continue

    # Check if scout moved
    var updatedSpy = state.spyScouts[spyId]
    let newLocation = updatedSpy.location

    if newLocation != oldLocation:
      # Scout moved - perform detection check at new location
      let detectionResult = checkTravelDetection(state, spyId, newLocation)

      # Calculate travel progress
      let totalJumps = updatedSpy.travelPath.len
      let currentProgress = if totalJumps > 0:
        updatedSpy.currentPathIndex
      else:
        0

      # Emit SpyScoutTravel event (Phase 7b)
      events.add(event_factory.spyScoutTravel(
        spyId,
        updatedSpy.owner,
        oldLocation,
        newLocation,
        currentProgress,
        totalJumps,
        detectionResult.detected
      ))

      if detectionResult.detected:
        if detectionResult.isAllyDetection:
          # Ally detected scout during transit - no destruction, no escalation
          result.add("Spy scout " & spyId & " detected by ally " &
                    $detectionResult.detectorHouse & " in transit through " &
                    $newLocation & " (allowed passage)")
        else:
          # Non-ally detected scout - destroy but NO escalation for passive transit
          updatedSpy.state = SpyScoutState.Detected
          updatedSpy.detected = true
          state.spyScouts[spyId] = updatedSpy

          # Record as travel interception (NO automatic escalation for transit)
          recordScoutLoss(state, spyId, intel_types.DetectionEventType.TravelIntercepted,
                         detectionResult.detectorHouse)

          result.add("Spy scout " & spyId & " detected traveling through " &
                    $newLocation & " by " & $detectionResult.detectorHouse &
                    " (destroyed)")
          continue  # Scout destroyed, skip to next scout

      # Check if arrived at target
      if newLocation == spy.targetSystem:
        updatedSpy.state = SpyScoutState.OnMission
        state.spyScouts[spyId] = updatedSpy
        result.add("Spy scout " & spyId & " arrived at target " & $newLocation)
      else:
        # Still traveling
        result.add("Spy scout " & spyId & " traveled to system " & $newLocation & " (undetected)")
