## Event Visibility Rules
## Determines which houses can see which events based on fog-of-war
##
## DRY Principle: Centralized visibility logic for all event types
## DoD Principle: Data (events/state) inspected by visibility rules

import std/options
import ../../types/[core, game_state, event]
import ./helpers

proc shouldHouseSeeEvent*(
    state: GameState, houseId: HouseId, event: GameEvent
): bool =
  ## Determine if a house should receive intelligence about this event
  ## Enforces fog-of-war rules to prevent AI cheating
  ##
  ## Visibility rules:
  ## - Own actions: Always visible
  ## - Diplomatic events: Public (visible to all)
  ## - Combat events: Visible if present in system (fleet/colony/starbase)
  ## - Espionage events: Only attacker sees (defender implicit)
  ## - Economic events: Private to house

  # Own events always visible
  if event.houseId.isSome and event.houseId.get == houseId:
    return true

  # Check event type for specific visibility rules
  case event.eventType

  # Public diplomatic events (visible to all)
  of GameEventType.WarDeclared, GameEventType.PeaceSigned,
      GameEventType.DiplomaticRelationChanged,
      GameEventType.TreatyProposed, GameEventType.TreatyAccepted,
      GameEventType.TreatyBroken, GameEventType.HouseEliminated:
    return true

  # Combat events - visible if participated or observed
  of GameEventType.Battle,
      GameEventType.BattleOccurred,
      GameEventType.SystemCaptured,
      GameEventType.ColonyCaptured,
      GameEventType.InvasionRepelled,
      GameEventType.FleetDestroyed,
      GameEventType.Bombardment,
      # Phase 7b: Detailed combat events
      GameEventType.CombatTheaterBegan,
      GameEventType.CombatTheaterCompleted,
      GameEventType.CombatPhaseBegan,
      GameEventType.CombatPhaseCompleted,
      GameEventType.WeaponFired,
      GameEventType.ShipDamaged,
      GameEventType.ShipDestroyed,
      GameEventType.FleetRetreat,
      GameEventType.BombardmentRoundBegan,
      GameEventType.BombardmentRoundCompleted,
      GameEventType.ShieldActivated,
      GameEventType.GroundBatteryFired,
      GameEventType.InvasionBegan,
      GameEventType.BlitzBegan,
      GameEventType.GroundCombatRound,
      GameEventType.StarbaseCombat,
      GameEventType.RaiderDetected,
      GameEventType.RaiderAmbush,
      GameEventType.FighterDeployed,
      GameEventType.FighterEngagement,
      GameEventType.CarrierDestroyed:
    if event.systemId.isNone:
      return false
    let systemId = event.systemId.get()

    # Visible if present in system (fleet, colony, or starbase surveillance)
    return hasPresenceInSystem(state, houseId, systemId)

  # Raider stealth success - only visible to raider (for diagnostics)
  # Defender doesn't know they failed to detect
  of GameEventType.RaiderStealthSuccess:
    return false # Only raider sees (filtered by houseId check above)

  # Starbase surveillance - only visible to starbase owner (for diagnostics)
  of GameEventType.StarbaseSurveillanceDetection:
    return false # Only owner sees (filtered by houseId check above)

  # Espionage events - only visible to attacker
  # (Defender awareness handled through detection events)
  of GameEventType.SpyMissionSucceeded,
      GameEventType.SabotageConducted,
      GameEventType.TechTheftExecuted,
      GameEventType.AssassinationAttempted,
      GameEventType.EconomicManipulationExecuted,
      GameEventType.CyberAttackConducted,
      GameEventType.PsyopsCampaignLaunched,
      GameEventType.IntelligenceTheftExecuted,
      GameEventType.DisinformationPlanted,
      GameEventType.CounterIntelSweepExecuted:
    return false # Only attacker sees (filtered by houseId check above)

  # Detection events - visible to both attacker and defender
  of GameEventType.SpyMissionDetected, GameEventType.ScoutDetected,
      GameEventType.ScoutDestroyed:
    # Defender (detector) sees when they caught someone
    if event.targetHouseId.isSome and event.targetHouseId.get() == houseId:
      return true
    return false # Others don't see

  # Economic/construction - private to house
  of GameEventType.ConstructionStarted,
      GameEventType.ShipCommissioned,
      GameEventType.BuildingCompleted, GameEventType.UnitRecruited,
      GameEventType.UnitDisbanded, GameEventType.FleetDisbanded,
      GameEventType.SquadronDisbanded,
      GameEventType.SquadronScrapped,
      GameEventType.PopulationTransfer,
      GameEventType.TerraformComplete:
    return false

  # Colonization events - visible if observing system
  of GameEventType.ColonyEstablished,
      # Phase 7b: Fleet encounter - visible if observing
      GameEventType.FleetEncounter:
    if event.systemId.isNone:
      return false
    let systemId = event.systemId.get()

    # Visible if have presence in system (scouts, adjacent starbases)
    return hasPresenceInSystem(state, houseId, systemId)

  # Tech/victory events - private to house
  of GameEventType.TechAdvance:
    return false

  # Prestige events - private to house
  of GameEventType.PrestigeGained, GameEventType.PrestigeLost:
    return false

  # Order events - private to house
  of GameEventType.OrderRejected,
      GameEventType.OrderIssued,
      GameEventType.OrderCompleted,
      GameEventType.OrderFailed,
      GameEventType.OrderAborted,
      GameEventType.FleetArrived,
      # Phase 7b: Standing command events
      GameEventType.StandingOrderSet,
      GameEventType.StandingOrderActivated,
      GameEventType.StandingOrderSuspended,
      # Phase 7b: Fleet reorganization events (zero-turn commands)
      GameEventType.FleetMerged,
      GameEventType.FleetDetachment,
      GameEventType.FleetTransfer,
      GameEventType.CargoLoaded,
      GameEventType.CargoUnloaded:
    return false

  # Alert events - private to house
  of GameEventType.ResourceWarning, GameEventType.ThreatDetected,
      GameEventType.AutomationCompleted:
    return false

  # Legacy intel gathering - private to house
  of GameEventType.IntelGathered:
    return false

  # Generic/categorical event types - default to private
  of GameEventType.General, GameEventType.CombatResult,
      GameEventType.Espionage, GameEventType.Diplomacy,
      GameEventType.Research, GameEventType.Economy,
      GameEventType.Colony, GameEventType.Fleet,
      GameEventType.Intelligence, GameEventType.Prestige:
    return false
