## Intelligence Event Processor
## Converts GameEvents into per-house intelligence reports
## Respects fog-of-war visibility rules
##
## Architecture: GameEvents (single source of truth) → Intelligence Reports
## DRY Principle: Single source of truth for event interpretation
## DoD Principle: Data (GameEvents) processed by behavior (converters)

import std/[tables, options]
import ../types as intel_types
import ../../resolution/types as res_types
import ../../gamestate
import ./visibility
import ./converters
import ./helpers

# Re-export sub-modules for external use
export visibility, converters, helpers

proc processEventsForIntelligence*(
    state: var GameState, events: seq[res_types.GameEvent], turn: int
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
    for houseId in state.houses.keys:
      # Check fog-of-war visibility
      if visibility.shouldHouseSeeEvent(state, houseId, event):
        # Convert event to intelligence report based on type
        case event.eventType

        # Combat events → ScoutEncounterReport
        of res_types.GameEventType.Battle, res_types.GameEventType.BattleOccurred,
            res_types.GameEventType.SystemCaptured,
            res_types.GameEventType.ColonyCaptured,
            res_types.GameEventType.InvasionRepelled,
            res_types.GameEventType.FleetDestroyed, res_types.GameEventType.Bombardment:
          let combatReport = converters.convertCombatEvent(event, houseId, turn)
          if combatReport.isSome:
            state.houses[houseId].intelligence.addScoutEncounter(combatReport.get())

        # Espionage events → EspionageActivityReport
        of res_types.GameEventType.SpyMissionSucceeded,
            res_types.GameEventType.SabotageConducted,
            res_types.GameEventType.TechTheftExecuted,
            res_types.GameEventType.AssassinationAttempted,
            res_types.GameEventType.EconomicManipulationExecuted,
            res_types.GameEventType.CyberAttackConducted,
            res_types.GameEventType.PsyopsCampaignLaunched,
            res_types.GameEventType.IntelligenceTheftExecuted,
            res_types.GameEventType.DisinformationPlanted,
            res_types.GameEventType.CounterIntelSweepExecuted,
            res_types.GameEventType.SpyMissionDetected:
          let espReport = converters.convertEspionageEvent(event, houseId, turn)
          if espReport.isSome:
            state.houses[houseId].intelligence.addEspionageActivity(espReport.get())

        # Colonization events → ScoutEncounterReport
        of res_types.GameEventType.ColonyEstablished:
          let colReport = converters.convertColonizationEvent(event, houseId, turn)
          if colReport.isSome:
            state.houses[houseId].intelligence.addScoutEncounter(colReport.get())

        # Scout detection events → ScoutEncounterReport
        of res_types.GameEventType.ScoutDetected, res_types.GameEventType.ScoutDestroyed:
          let scoutReport = converters.convertScoutDetectionEvent(event, houseId, turn)
          if scoutReport.isSome:
            state.houses[houseId].intelligence.addScoutEncounter(scoutReport.get())

        # Other event types not converted to intelligence
        # (Economic, prestige, order rejections are house-private)
        else:
          discard
