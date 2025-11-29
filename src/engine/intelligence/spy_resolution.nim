## Spy Scout Turn Resolution
## Implements spy detection and intelligence gathering from assets.md:2.4.2

import std/[tables, options, sequtils]
import ../../common/types/core
import ../gamestate, ../fleet
import detection

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
            result.add("Spy scout " & spyId & " detected by " & $fleet.owner &
                      " (Roll: " & $detectionResult.roll & " > " &
                      $detectionResult.threshold & ", ELI: " &
                      $detectionResult.effectiveELI & ")")
            break  # Scout destroyed, no need to check more fleets

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
