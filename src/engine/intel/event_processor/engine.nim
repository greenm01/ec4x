## Intelligence Event Processor
## Converts GameEvents into per-house intelligence reports
## Respects fog-of-war visibility rules
##
## Architecture: GameEvents (single source of truth) → Intelligence Reports
## DRY Principle: Single source of truth for event interpretation
## DoD Principle: Data (GameEvents) processed by behavior (converters)

import std/[tables, options]
import ../../types/[core, game_state, event, intel]
import ./[visibility, converters]

proc processEventsForIntelligence*(
    state: GameState, events: seq[GameEvent], turn: int32
) =
  ## Main entry point: Convert all events to intelligence reports
  ## Distributes to houses based on fog-of-war visibility
  ##
  ## Process:
  ## 1. For each event, check which houses can see it (fog-of-war)
  ## 2. Convert event to appropriate intelligence report type
  ## 3. Add report to each observing house's intelligence database
  ##
  ## DoD: Processes data (events) without modifying event objects

  for event in events:
    for (houseId, _) in state.allHousesWithId():
      # Check fog-of-war visibility
      if not visibility.shouldHouseSeeEvent(state, houseId, event):
        continue

      # Only process if house has intelligence database
      if not state.intelligence.contains(houseId):
        continue

      # Convert event to intelligence report based on type
      case event.eventType

      # Combat events → ScoutEncounterReport
      of GameEventType.Battle, GameEventType.BattleOccurred,
          GameEventType.SystemCaptured,
          GameEventType.ColonyCaptured,
          GameEventType.InvasionRepelled,
          GameEventType.FleetDestroyed, GameEventType.Bombardment:
        let combatReport = converters.convertCombatEvent(event, houseId, turn)
        if combatReport.isSome:
          var intel = state.intelligence[houseId]
          intel.scoutEncounters.add(combatReport.get())
          state.intelligence[houseId] = intel

      # Espionage events → EspionageActivityReport
      of GameEventType.SpyMissionSucceeded,
          GameEventType.SabotageConducted,
          GameEventType.TechTheftExecuted,
          GameEventType.AssassinationAttempted,
          GameEventType.EconomicManipulationExecuted,
          GameEventType.CyberAttackConducted,
          GameEventType.PsyopsCampaignLaunched,
          GameEventType.IntelligenceTheftExecuted,
          GameEventType.DisinformationPlanted,
          GameEventType.CounterIntelSweepExecuted,
          GameEventType.SpyMissionDetected:
        let espReport = converters.convertEspionageEvent(event, houseId, turn)
        if espReport.isSome:
          var intel = state.intelligence[houseId]
          intel.espionageActivity.add(espReport.get())
          state.intelligence[houseId] = intel

      # Colonization events → ScoutEncounterReport
      of GameEventType.ColonyEstablished:
        let colReport = converters.convertColonizationEvent(event, houseId, turn)
        if colReport.isSome:
          var intel = state.intelligence[houseId]
          intel.scoutEncounters.add(colReport.get())
          state.intelligence[houseId] = intel

      # Scout detection events → ScoutEncounterReport
      of GameEventType.ScoutDetected, GameEventType.ScoutDestroyed:
        let scoutReport = converters.convertScoutDetectionEvent(event, houseId, turn)
        if scoutReport.isSome:
          var intel = state.intelligence[houseId]
          intel.scoutEncounters.add(scoutReport.get())
          state.intelligence[houseId] = intel

      # Other event types not converted to intelligence
      # (Economic, prestige, command rejections are house-private)
      else:
        discard
