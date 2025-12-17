## Scout Build Requirements Module
##
## Part of Drungarius (Intelligence Advisor) - manages scout construction needs
## based on intelligence gaps and reconnaissance requirements.
##
## Follows Eparch/ETAC pattern: Intelligence advisor owns scout pipeline
## (identify needs → build scouts → deploy scouts)

import std/[logging, strformat, options, sequtils, tables]
import ../../../../common/types/[core, units]
import ../../../../engine/[gamestate, fog_of_war]
import ../../../../engine/economy/config_accessors
import ../../../common/types as ai_common_types
import ../../[controller_types, config]
import ../../shared/intelligence_types

proc assessScoutGaps*(
  filtered: FilteredGameState,
  controller: AIController,
  currentAct: GameAct,
  intelSnapshot: IntelligenceSnapshot
): seq[BuildRequirement] =
  ## Calculate scout needs from intelligence gaps
  ##
  ## Intelligence-driven scout requirements based on:
  ## - Stale intel systems requiring fresh reconnaissance
  ## - Enemy house coverage for strategic intelligence
  ## - Act-based scaling limits from configuration
  ##
  ## Returns build requirements for scouts to close intelligence gaps
  result = @[]

  # Count current scouts across all fleets
  var scoutCount = 0
  for fleet in filtered.ownFleets:
    scoutCount += fleet.squadrons.countIt(
      it.flagship.shipClass == ShipClass.Scout
    )

  # Intelligence-driven targeting
  let staleIntelSystems = intelSnapshot.espionage.staleIntelSystems
  let enemyHouses = intelSnapshot.military.enemyMilitaryCapability.len

  # Calculate need: 1 scout per 2 stale systems + 1 per enemy house (min 3)
  var targetScouts = max(3, staleIntelSystems.len div 2) + min(3, enemyHouses)

  # Act-based caps from config (intelligence coverage scaling)
  let actCap = case currentAct
    of Act1_LandGrab:
      controller.rbaConfig.drungarius_reconnaissance.scout_target_act1
    of Act2_RisingTensions:
      controller.rbaConfig.drungarius_reconnaissance.scout_target_act2
    of Act3_TotalWar:
      controller.rbaConfig.drungarius_reconnaissance.scout_target_act3
    of Act4_Endgame:
      controller.rbaConfig.drungarius_reconnaissance.scout_target_act4

  targetScouts = min(targetScouts, actCap)

  if scoutCount < targetScouts:
    let scoutCost = getShipConstructionCost(ShipClass.Scout)
    let needed = targetScouts - scoutCount

    # Priority based on intelligence gap severity
    let priority = if staleIntelSystems.len > 5:
      RequirementPriority.High
    elif staleIntelSystems.len > 2:
      RequirementPriority.Medium
    else:
      RequirementPriority.Low

    result.add(BuildRequirement(
      requirementType: RequirementType.ReconnaissanceGap,
      priority: priority,
      shipClass: some(ShipClass.Scout),
      quantity: needed,
      buildObjective: BuildObjective.Reconnaissance,
      estimatedCost: scoutCost * needed,
      reason: &"Intel coverage (have {scoutCount}/{targetScouts}, " &
              &"{staleIntelSystems.len} stale systems, " &
              &"{enemyHouses} enemy houses)"
    ))

    info &"{controller.houseId} Drungarius: Scout requirement - " &
         &"need {needed}x Scout ({scoutCost * needed}PP), " &
         &"priority={priority}, " &
         &"reason: {staleIntelSystems.len} stale systems, " &
         &"{enemyHouses} enemies"
