## Event Visibility Rules
## Determines which houses can see which events based on fog-of-war
##
## DRY Principle: Centralized visibility logic for all event types
## DoD Principle: Data (events/state) inspected by visibility rules

import std/options
import ../../../common/types/core
import ../../resolution/types as res_types
import ../../gamestate
import ./helpers

proc shouldHouseSeeEvent*(
  state: GameState,
  houseId: HouseId,
  event: res_types.GameEvent
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
  of res_types.GameEventType.WarDeclared,
     res_types.GameEventType.PeaceSigned,
     res_types.GameEventType.DiplomaticRelationChanged,
     res_types.GameEventType.TreatyProposed,
     res_types.GameEventType.TreatyAccepted,
     res_types.GameEventType.TreatyBroken,
     res_types.GameEventType.HouseEliminated:
    return true

  # Combat events - visible if participated or observed
  of res_types.GameEventType.Battle,
     res_types.GameEventType.BattleOccurred,
     res_types.GameEventType.SystemCaptured,
     res_types.GameEventType.ColonyCaptured,
     res_types.GameEventType.InvasionRepelled,
     res_types.GameEventType.FleetDestroyed,
     res_types.GameEventType.Bombardment,
     # Phase 7b: Detailed combat events
     res_types.GameEventType.CombatTheaterBegan,
     res_types.GameEventType.CombatTheaterCompleted,
     res_types.GameEventType.CombatPhaseBegan,
     res_types.GameEventType.CombatPhaseCompleted,
     res_types.GameEventType.WeaponFired,
     res_types.GameEventType.ShipDamaged,
     res_types.GameEventType.ShipDestroyed,
     res_types.GameEventType.FleetRetreat,
     res_types.GameEventType.BombardmentRoundBegan,
     res_types.GameEventType.BombardmentRoundCompleted,
     res_types.GameEventType.ShieldActivated,
     res_types.GameEventType.GroundBatteryFired,
     res_types.GameEventType.InvasionBegan,
     res_types.GameEventType.BlitzBegan,
     res_types.GameEventType.GroundCombatRound,
     res_types.GameEventType.StarbaseCombat,
     res_types.GameEventType.RaiderDetected,
     res_types.GameEventType.RaiderAmbush,
     res_types.GameEventType.EliMeshNetworkFormed,
     res_types.GameEventType.FighterDeployed,
     res_types.GameEventType.FighterEngagement,
     res_types.GameEventType.CarrierDestroyed:
    if event.systemId.isNone:
      return false
    let systemId = event.systemId.get()

    # Visible if present in system (fleet, colony, or starbase surveillance)
    return hasPresenceInSystem(state, houseId, systemId)

  # Espionage events - only visible to attacker
  # (Defender awareness handled through detection events)
  of res_types.GameEventType.SpyMissionSucceeded,
     res_types.GameEventType.SabotageConducted,
     res_types.GameEventType.TechTheftExecuted,
     res_types.GameEventType.AssassinationAttempted,
     res_types.GameEventType.EconomicManipulationExecuted,
     res_types.GameEventType.CyberAttackConducted,
     res_types.GameEventType.PsyopsCampaignLaunched,
     res_types.GameEventType.IntelligenceTheftExecuted,
     res_types.GameEventType.DisinformationPlanted,
     res_types.GameEventType.CounterIntelSweepExecuted:
    return false  # Only attacker sees (filtered by houseId check above)

  # Detection events - visible to both attacker and defender
  of res_types.GameEventType.SpyMissionDetected,
     res_types.GameEventType.ScoutDetected,
     res_types.GameEventType.ScoutDestroyed:
    # Defender (detector) sees when they caught someone
    if event.targetHouseId.isSome and event.targetHouseId.get() == houseId:
      return true
    return false  # Others don't see

  # Economic/construction - private to house
  of res_types.GameEventType.ConstructionStarted,
     res_types.GameEventType.ShipCommissioned,
     res_types.GameEventType.BuildingCompleted,
     res_types.GameEventType.UnitRecruited,
     res_types.GameEventType.UnitDisbanded,
     res_types.GameEventType.FleetDisbanded,
     res_types.GameEventType.SquadronDisbanded,
     res_types.GameEventType.SquadronScrapped,
     res_types.GameEventType.PopulationTransfer,
     res_types.GameEventType.TerraformComplete:
    return false

  # Colonization events - visible if observing system
  of res_types.GameEventType.ColonyEstablished,
     # Phase 7b: Fleet encounter - visible if observing
     res_types.GameEventType.FleetEncounter:
    if event.systemId.isNone:
      return false
    let systemId = event.systemId.get()

    # Visible if have presence in system (scouts, adjacent starbases)
    return hasPresenceInSystem(state, houseId, systemId)

  # Tech/victory events - private to house
  of res_types.GameEventType.TechAdvance:
    return false

  # Prestige events - private to house
  of res_types.GameEventType.PrestigeGained,
     res_types.GameEventType.PrestigeLost:
    return false

  # Order events - private to house
  of res_types.GameEventType.OrderRejected,
     res_types.GameEventType.OrderIssued,
     res_types.GameEventType.OrderCompleted,
     res_types.GameEventType.OrderFailed,
     res_types.GameEventType.OrderAborted,
     res_types.GameEventType.FleetArrived,
     # Phase 7b: Standing order events
     res_types.GameEventType.StandingOrderSet,
     res_types.GameEventType.StandingOrderActivated,
     res_types.GameEventType.StandingOrderSuspended,
     # Phase 7b: Fleet reorganization events (zero-turn commands)
     res_types.GameEventType.FleetMerged,
     res_types.GameEventType.FleetDetachment,
     res_types.GameEventType.FleetTransfer,
     res_types.GameEventType.CargoLoaded,
     res_types.GameEventType.CargoUnloaded:
    return false

  # Alert events - private to house
  of res_types.GameEventType.ResourceWarning,
     res_types.GameEventType.ThreatDetected,
     res_types.GameEventType.AutomationCompleted:
    return false

  # Legacy intel gathering - private to house
  of res_types.GameEventType.IntelGathered,
     # Phase 7b: Scout mesh network and spy scout operations - private
     res_types.GameEventType.ScoutMeshNetworkFormed,
     res_types.GameEventType.SpyScoutDeployed,
     res_types.GameEventType.SpyScoutTravel:
    return false

  # Generic/categorical event types - default to private
  of res_types.GameEventType.General,
     res_types.GameEventType.CombatResult,
     res_types.GameEventType.Espionage,
     res_types.GameEventType.Diplomacy,
     res_types.GameEventType.Research,
     res_types.GameEventType.Economy,
     res_types.GameEventType.Colony,
     res_types.GameEventType.Fleet,
     res_types.GameEventType.Intelligence,
     res_types.GameEventType.Prestige:
    return false
