## Campaign Classification System
##
## Classifies invasion campaigns based on intelligence quality and target
## characteristics. Implements 4-tier campaign system:
## - Speculative: No intel, proximity-based, high risk (40-60% confidence)
## - Raid: Weak target, Scan intel, quick strike (50-90% confidence)
## - Assault: Moderate target, Spy intel, planned operation (40-70% confidence)
## - Deliberate: Fortified target, Perfect intel, major campaign (30-50% confidence)
##
## Per docs/ai/operations/ec4x_strategic_ai_guide.md lines 90-108

import std/[tables, sets]
import ../../../../../common/types/core
import ../../../../../common/hex
import ../../../../../engine/[gamestate, starmap, fog_of_war]
import ../../../config
import ../../../shared/intelligence_types

# Re-export CampaignType from config
export config.CampaignType

# =============================================================================
# Proximity Assessment (Speculative Campaigns)
# =============================================================================

proc calculateHexDistance*(
  system1: SystemId,
  system2: SystemId,
  starMap: StarMap
): uint32 =
  ## Calculate hex distance between two systems
  if system1.uint notin starMap.systems or system2.uint notin starMap.systems:
    return 9999  # Infinite distance if system not found

  let coords1 = starMap.systems[system1.uint].coords
  let coords2 = starMap.systems[system2.uint].coords
  return distance(coords1, coords2)

proc isProximityTarget*(
  systemId: SystemId,
  ownedColonies: HashSet[SystemId],
  starMap: StarMap,
  maxDistance: int
): bool =
  ## Check if system is within N hexes of any owned colony
  ## Used for speculative campaign classification
  for ownedColony in ownedColonies:
    let dist = calculateHexDistance(ownedColony, systemId, starMap)
    if dist.int <= maxDistance:
      return true
  return false

proc assessSpeculativeConfidence*(
  systemId: SystemId,
  ownedColonies: HashSet[SystemId],
  starMap: StarMap,
  currentTurn: int,
  config: GOAPIntelligenceThresholdsConfig
): float =
  ## Calculate confidence for speculative campaign (no intel required)
  ## Factors:
  ## - Base confidence (config.speculative_confidence_base)
  ## - Early-game bonus (first N turns, assume weak defenses)
  ## - Proximity bonus (more adjacent owned colonies = safer)
  ## - Capped at max confidence (speculative is risky by nature)

  var confidence = config.speculative_confidence_base

  # Early-game bonus: Assume colonies are weak in first N turns
  if currentTurn <= config.speculative_early_game_turns:
    confidence += 0.2

  # Proximity bonus: More adjacent owned colonies = safer operation
  var adjacentCount = 0
  for ownedColony in ownedColonies:
    let dist = calculateHexDistance(ownedColony, systemId, starMap)
    if dist <= 2:  # Adjacent or 1 hex away
      adjacentCount += 1

  confidence += float(adjacentCount) * config.speculative_proximity_bonus

  # Cap at max confidence (speculative is risky by nature)
  return min(confidence, config.speculative_max_confidence)

# =============================================================================
# Campaign Classification
# =============================================================================

proc classifyCampaign*(
  target: InvasionOpportunity,
  ownedColonies: HashSet[SystemId],
  starMap: StarMap,
  currentTurn: int,
  config: GOAPIntelligenceThresholdsConfig
): CampaignType =
  ## Classify campaign type based on intel quality and target characteristics
  ##
  ## Priority order:
  ## 1. Speculative: Proximity-based, minimal/no intel
  ## 2. Raid: High vulnerability, low defenses, Scan+ intel
  ## 3. Assault: Moderate vulnerability/defenses, Spy+ intel
  ## 4. Deliberate: Fortified target, Perfect intel

  # Priority 1: Check for speculative opportunity (proximity-based)
  # Only if intel is minimal (Visual quality only)
  if target.intelQuality == IntelQuality.Visual:
    if isProximityTarget(
      target.systemId,
      ownedColonies,
      starMap,
      config.speculative_max_distance
    ):
      return CampaignType.Speculative

  # Priority 2: Check for raid opportunity (weak target, Scan+ intel)
  if target.vulnerability >= config.raid_vulnerability_threshold and
     target.estimatedDefenses <= config.raid_max_defense_strength:
    return CampaignType.Raid

  # Priority 3: Check for assault opportunity (moderate target, Spy+ intel)
  elif target.vulnerability >= config.assault_vulnerability_threshold and
       target.estimatedDefenses <= config.assault_max_defense_strength:
    return CampaignType.Assault

  # Priority 4: Deliberate campaign (fortified target, Perfect intel required)
  else:
    return CampaignType.Deliberate

# =============================================================================
# Intelligence Requirements Checking
# =============================================================================

proc checkIntelligenceRequirements*(
  target: InvasionOpportunity,
  currentTurn: int,
  campaignType: CampaignType,
  config: GOAPIntelligenceThresholdsConfig
): tuple[met: bool, gaps: seq[string]] =
  ## Check if target meets intel thresholds for campaign type
  ## Returns (met: true, gaps: @[]) if requirements satisfied
  ## Returns (met: false, gaps: [...]) if requirements not met

  var gaps: seq[string] = @[]

  case campaignType
  of CampaignType.Speculative:
    # No intel requirements - always met
    return (met: true, gaps: @[])

  of CampaignType.Raid:
    # Raid requires Scan+ quality and ≤10 turn age
    if target.intelQuality < IntelQuality.Scan:
      gaps.add(
        "Intel quality too low (need Scan+, have " & $target.intelQuality & ")"
      )
    let intelAge = currentTurn - target.lastIntelTurn
    if intelAge > config.raid_max_intel_age:
      gaps.add(
        "Intel too stale (" & $intelAge & " turns old, max " &
        $config.raid_max_intel_age & ")"
      )

  of CampaignType.Assault:
    # Assault requires Spy+ quality and ≤5 turn age
    if target.intelQuality < IntelQuality.Spy:
      gaps.add(
        "Intel quality too low (need Spy+, have " & $target.intelQuality & ")"
      )
    let intelAge = currentTurn - target.lastIntelTurn
    if intelAge > config.assault_max_intel_age:
      gaps.add(
        "Intel too stale (" & $intelAge & " turns old, max " &
        $config.assault_max_intel_age & ")"
      )

  of CampaignType.Deliberate:
    # Deliberate requires Perfect quality and ≤3 turn age
    if target.intelQuality < IntelQuality.Perfect:
      gaps.add(
        "Intel quality too low (need Perfect, have " & $target.intelQuality & ")"
      )
    let intelAge = currentTurn - target.lastIntelTurn
    if intelAge > config.deliberate_max_intel_age:
      gaps.add(
        "Intel too stale (" & $intelAge & " turns old, max " &
        $config.deliberate_max_intel_age & ")"
      )

  return (met: gaps.len == 0, gaps: gaps)
