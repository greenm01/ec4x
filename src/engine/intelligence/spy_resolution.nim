## Spy Scout Turn Resolution
## Implements spy detection and intelligence gathering from assets.md:2.4.2

import std/[tables, options]
import ../../common/types/core
import ../gamestate, ../fleet
import detection
import types as intel_types  # For DetectionEventType, ScoutLossEvent
import ../diplomacy/engine as dip_engine  # For getDiplomaticState

# =============================================================================
# Spy Scout Detection Resolution
# =============================================================================

proc resolveSpyDetection*(state: var GameState): seq[string] =
  ## Resolve detection rolls for all active spy scouts
  ## Per assets.md:2.4.2: "For every turn that a spy Scout operates in
  ## unfriendly system occupied by rival ELI, the rival will roll on
  ## the Spy Detection Table"
  ##
  ## Returns list of detection event messages

  result = @[]

  var destroyedSpies: seq[string] = @[]

  # First pass: Remove spy scouts whose owner house is eliminated
  for spyId, spy in state.spyScouts:
    if spy.owner in state.houses:
      let ownerHouse = state.houses[spy.owner]
      if ownerHouse.eliminated:
        destroyedSpies.add(spyId)
        result.add("Spy scout " & spyId & " recalled - owner house " & $spy.owner & " eliminated")
        continue

    # Check if target house is eliminated
    if spy.location in state.colonies:
      let colony = state.colonies[spy.location]
      if colony.owner in state.houses:
        let targetHouse = state.houses[colony.owner]
        if targetHouse.eliminated:
          destroyedSpies.add(spyId)
          result.add("Spy scout " & spyId & " mission ended - target house " & $colony.owner & " eliminated")
          continue

  for spyId, spy in state.spyScouts:
    if spy.detected:
      continue  # Already detected, will be removed

    let system = spy.location

    # Check detection by enemy fleets in the system
    for fleet in state.fleets.values:
      if fleet.location == system and fleet.owner != spy.owner:
        # Create ELI unit from fleet
        let detectorUnit = createELIUnit(fleet.squadrons, isStarbase = false)

        if detectorUnit.eliLevels.len > 0:
          # Attempt detection
          let detectionResult = detectSpyScout(detectorUnit, spy.eliLevel)

          if detectionResult.detected:
            # Spy scout detected and destroyed
            destroyedSpies.add(spyId)

            # Record scout loss event for diplomatic processing
            # SpyScoutDetected = caught red-handed on mission (Hostile escalation)
            let event = intel_types.ScoutLossEvent(
              scoutId: spyId,
              owner: spy.owner,
              location: spy.location,
              detectorHouse: fleet.owner,
              eventType: intel_types.DetectionEventType.SpyScoutDetected,
              turn: state.turn
            )
            state.scoutLossEvents.add(event)

            result.add("Spy scout " & spyId & " detected by " & $fleet.owner &
                      " (Roll: " & $detectionResult.roll & " > " &
                      $detectionResult.threshold & ", ELI: " &
                      $detectionResult.effectiveELI & ")")
            break  # Scout destroyed, no need to check more fleets

    # Check detection by rival spy scouts (spy-vs-spy)
    if spyId notin destroyedSpies:
      for otherSpyId, otherSpy in state.spyScouts:
        # Skip self, already detected, and friendly scouts
        if otherSpyId == spyId or otherSpy.detected or otherSpy.owner == spy.owner:
          continue

        # Only check if both scouts are in the same system
        if otherSpy.location == system:
          # Check diplomatic relations - allies don't fight each other
          let dipState = dip_engine.getDiplomaticState(
            state.houses[otherSpy.owner].diplomaticRelations,
            spy.owner
          )

          if dipState == DiplomaticState.Ally:
            # Allies share intelligence about each other's scouts but don't engage
            result.add("Spy scout " & spyId & " encountered allied spy scout " &
                      otherSpyId & " (intelligence shared)")
            continue  # No detection combat between allies
          # Spy scouts can detect each other using ELI detection
          # Each scout acts as a single-unit ELI detector
          let detectorUnit = ELIUnit(
            eliLevels: @[otherSpy.eliLevel],
            isStarbase: false
          )

          let detectionResult = detectSpyScout(detectorUnit, spy.eliLevel)

          if detectionResult.detected:
            # Spy scout detected by rival spy scout
            destroyedSpies.add(spyId)

            # Record scout loss event for diplomatic processing
            let event = intel_types.ScoutLossEvent(
              scoutId: spyId,
              owner: spy.owner,
              location: spy.location,
              detectorHouse: otherSpy.owner,
              eventType: intel_types.DetectionEventType.SpyScoutDetected,
              turn: state.turn
            )
            state.scoutLossEvents.add(event)

            result.add("Spy scout " & spyId & " detected by rival spy scout " &
                      otherSpyId & " (Roll: " & $detectionResult.roll & " > " &
                      $detectionResult.threshold & ", ELI: " &
                      $detectionResult.effectiveELI & ")")
            break  # Scout destroyed, no need to check more scouts
          # else: Detection failed - stealth stalemate, no intel report generated

    # Check detection by enemy starbases
    if spyId notin destroyedSpies:
      # Check if system has colony with starbases
      if system in state.colonies:
        let colony = state.colonies[system]

        if colony.owner != spy.owner and colony.starbases.len > 0:
          # Create ELI unit from starbase
          # Get highest ELI level from all starbases
          var starbaseELI = 0
          for starbase in colony.starbases:
            # NOTE: Starbases currently don't track ELI level
            # Per assets.md, starbases provide detection capability
            # Using ELI 2 as baseline starbase detection capability
            starbaseELI = max(starbaseELI, 2)

          if starbaseELI > 0:
            let sbUnit = ELIUnit(
              eliLevels: @[starbaseELI],
              isStarbase: true
            )

            let detectionResult = detectSpyScout(sbUnit, spy.eliLevel)

            if detectionResult.detected:
              destroyedSpies.add(spyId)

              # Record scout loss event for diplomatic processing
              # SpyScoutDetected = caught red-handed on mission (Hostile escalation)
              let event = intel_types.ScoutLossEvent(
                scoutId: spyId,
                owner: spy.owner,
                location: spy.location,
                detectorHouse: colony.owner,
                eventType: intel_types.DetectionEventType.SpyScoutDetected,
                turn: state.turn
              )
              state.scoutLossEvents.add(event)

              result.add("Spy scout " & spyId & " detected by starbase at " &
                        $system & " (Roll: " & $detectionResult.roll & " > " &
                        $detectionResult.threshold & ", ELI: " &
                        $detectionResult.effectiveELI & " +2 starbase)")

  # Remove destroyed spy scouts
  for spyId in destroyedSpies:
    state.spyScouts.del(spyId)

# =============================================================================
# Intelligence Gathering
# =============================================================================

proc gatherIntelligence*(state: GameState, spy: SpyScout): Option[string] =
  ## Gather intelligence based on spy mission type
  ## Returns intelligence report if successful
  ##
  ## NOTE: This is a legacy text-based intel system
  ## Full intel system uses generator.nim (generateSystemIntelReport, etc.)
  ## and intelligence/types.nim (IntelligenceData, ScoutEncounterReport)

  if spy.detected:
    return none(string)

  case spy.mission
  of SpyMissionType.SpyOnPlanet:
    # Gather planet intelligence
    if spy.location in state.colonies:
      let colony = state.colonies[spy.location]
      var report = "Planet Intelligence (" & $spy.location & "):\n"
      report &= "  Owner: " & $colony.owner & "\n"
      report &= "  Population: " & $colony.population & "M\n"
      report &= "  Infrastructure: " & $colony.infrastructure & "\n"
      report &= "  Ground Batteries: " & $colony.groundBatteries & "\n"
      return some(report)
    else:
      return some("No colony found at " & $spy.location)

  of SpyMissionType.HackStarbase:
    # Gather starbase/economic intelligence
    if spy.location in state.colonies:
      let colony = state.colonies[spy.location]
      if colony.starbases.len > 0:
        var report = "Starbase Intelligence (" & $spy.location & "):\n"
        report &= "  Owner: " & $colony.owner & "\n"
        report &= "  Starbases: " & $colony.starbases.len & "\n"
        # Economic/R&D intel available via generator.generateStarbaseIntelReport()
        return some(report)
      else:
        return some("No starbase found at " & $spy.location)
    else:
      return some("No colony found at " & $spy.location)

  of SpyMissionType.SpyOnSystem:
    # Gather system intelligence (fleet movements, etc.)
    var fleetCount = 0
    var totalShips = 0

    for fleet in state.fleets.values:
      if fleet.location == spy.location:
        fleetCount += 1
        totalShips += fleet.squadrons.len

    var report = "System Intelligence (" & $spy.location & "):\n"
    report &= "  Fleets present: " & $fleetCount & "\n"
    report &= "  Total squadrons: " & $totalShips & "\n"
    # Fleet composition available via generator.generateSystemIntelReport()
    return some(report)

proc resolveIntelligenceGathering*(state: GameState): Table[HouseId, seq[string]] =
  ## Gather intelligence from all active spy scouts
  ## Returns intelligence reports organized by house

  result = initTable[HouseId, seq[string]]()

  for spy in state.spyScouts.values:
    if not spy.detected:
      let intel = gatherIntelligence(state, spy)

      if intel.isSome:
        if spy.owner notin result:
          result[spy.owner] = @[]

        result[spy.owner].add(intel.get())

# =============================================================================
# Spy Scout Merging
# =============================================================================

# NOTE: Automatic spy scout merging removed - players control merging via explicit orders
# Use SpyScoutOrder.JoinSpyScout to merge spy scouts together
# Mesh network bonuses calculated from mergedScoutCount field
