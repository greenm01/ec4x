## Research Intelligence Analyzer
##
## Extracts tech levels, gaps, and advantages from starbase intelligence
## Follows DoD: pure analysis of intelligence data, no state mutation
##
## Architecture: Analyzes engine intelligence reports → ResearchIntelligence
## Used by: intelligence_distribution.nim to populate snapshot

import std/[tables, options]
import ../../../engine/[gamestate, fog_of_war]
import ../../../engine/intelligence/types as engine_intel
import ../../../common/types/[core, tech]
import ../shared/intelligence_types
import ../controller_types

# =============================================================================
# Tech Level Extraction
# =============================================================================

proc extractEnemyTechLevels*(
  intelDb: engine_intel.IntelligenceDatabase,
  ourHouse: HouseId
): Table[HouseId, TechLevelEstimate] =
  ## Extract enemy tech levels from starbase intelligence reports
  ## Starbases provide the most reliable tech intel
  result = initTable[HouseId, TechLevelEstimate]()

  # Analyze starbase reports for tech level observations
  for systemId, report in intelDb.starbaseReports:
    if report.targetOwner == ourHouse:
      continue  # Skip our own starbases

    let enemy = report.targetOwner
    if enemy notin result:
      result[enemy] = TechLevelEstimate(
        houseId: enemy,
        economicLevel: none(int),
        militaryLevel: none(int),
        espionageLevel: none(int),
        lastUpdated: report.gatheredTurn,
        confidence: 0.0
      )

    # Starbase tech level provides military tech estimate
    # Higher starbase levels indicate advanced construction tech
    if report.starbaseLevel.isSome:
      let sbLevel = report.starbaseLevel.get()
      # Starbase level roughly correlates with CST level
      let estimatedCST = (sbLevel + 1) div 2  # SB1-2 = CST1, SB3-4 = CST2, etc.
      result[enemy].militaryLevel = some(estimatedCST)
      result[enemy].confidence = 0.7  # Moderate confidence from indirect observation

    # Update timestamp
    if report.gatheredTurn > result[enemy].lastUpdated:
      result[enemy].lastUpdated = report.gatheredTurn

# =============================================================================
# Tech Gap Analysis
# =============================================================================

proc computeTechGaps*(
  ourTech: TechLevels,
  enemyTechs: Table[HouseId, TechLevelEstimate]
): Table[HouseId, seq[TechGap]] =
  ## Compute tech gaps vs each enemy house
  ## Returns critical gaps where enemies are ahead
  result = initTable[HouseId, seq[TechGap]]()

  for enemy, enemyTech in enemyTechs:
    var gaps: seq[TechGap] = @[]

    # Economic tech gap
    if enemyTech.economicLevel.isSome:
      let theirLevel = enemyTech.economicLevel.get()
      let ourLevel = ourTech.economicLevel
      if theirLevel > ourLevel:
        let gap = theirLevel - ourLevel
        gaps.add(TechGap(
          field: TechField.Economic,
          theirLevel: theirLevel,
          ourLevel: ourLevel,
          gapSize: gap,
          urgency: if gap >= 2: RequirementPriority.Critical
                   elif gap >= 1: RequirementPriority.High
                   else: RequirementPriority.Medium
        ))

    # Military tech gap (most critical)
    if enemyTech.militaryLevel.isSome:
      let theirLevel = enemyTech.militaryLevel.get()
      let ourLevel = ourTech.militaryLevel
      if theirLevel > ourLevel:
        let gap = theirLevel - ourLevel
        gaps.add(TechGap(
          field: TechField.Military,
          theirLevel: theirLevel,
          ourLevel: ourLevel,
          gapSize: gap,
          urgency: if gap >= 2: RequirementPriority.Critical
                   elif gap >= 1: RequirementPriority.High
                   else: RequirementPriority.Medium
        ))

    # Espionage tech gap
    if enemyTech.espionageLevel.isSome:
      let theirLevel = enemyTech.espionageLevel.get()
      let ourLevel = ourTech.espionageLevel
      if theirLevel > ourLevel:
        let gap = theirLevel - ourLevel
        gaps.add(TechGap(
          field: TechField.Espionage,
          theirLevel: theirLevel,
          ourLevel: ourLevel,
          gapSize: gap,
          urgency: if gap >= 2: RequirementPriority.High
                   elif gap >= 1: RequirementPriority.Medium
                   else: RequirementPriority.Low
        ))

    if gaps.len > 0:
      result[enemy] = gaps

# =============================================================================
# Tech Advantage Analysis
# =============================================================================

proc computeTechAdvantages*(
  ourTech: TechLevels,
  enemyTechs: Table[HouseId, TechLevelEstimate]
): Table[HouseId, seq[TechAdvantage]] =
  ## Compute tech advantages vs each enemy house
  ## Returns fields where we are ahead
  result = initTable[HouseId, seq[TechAdvantage]]()

  for enemy, enemyTech in enemyTechs:
    var advantages: seq[TechAdvantage] = @[]

    # Economic advantage
    if enemyTech.economicLevel.isSome:
      let theirLevel = enemyTech.economicLevel.get()
      let ourLevel = ourTech.economicLevel
      if ourLevel > theirLevel:
        advantages.add(TechAdvantage(
          field: TechField.Economic,
          ourLevel: ourLevel,
          theirLevel: theirLevel,
          advantageSize: ourLevel - theirLevel
        ))

    # Military advantage
    if enemyTech.militaryLevel.isSome:
      let theirLevel = enemyTech.militaryLevel.get()
      let ourLevel = ourTech.militaryLevel
      if ourLevel > theirLevel:
        advantages.add(TechAdvantage(
          field: TechField.Military,
          ourLevel: ourLevel,
          theirLevel: theirLevel,
          advantageSize: ourLevel - theirLevel
        ))

    # Espionage advantage
    if enemyTech.espionageLevel.isSome:
      let theirLevel = enemyTech.espionageLevel.get()
      let ourLevel = ourTech.espionageLevel
      if ourLevel > theirLevel:
        advantages.add(TechAdvantage(
          field: TechField.Espionage,
          ourLevel: ourLevel,
          theirLevel: theirLevel,
          advantageSize: ourLevel - theirLevel
        ))

    if advantages.len > 0:
      result[enemy] = advantages

# =============================================================================
# Main Analysis Entry Point
# =============================================================================

proc analyzeResearchIntelligence*(
  filtered: FilteredGameState,
  controller: AIController
): ResearchIntelligence =
  ## Analyze research intelligence from filtered game state
  ## Extracts tech levels, gaps, and advantages
  result = ResearchIntelligence(
    enemyTechLevels: initTable[HouseId, TechLevelEstimate](),
    techGaps: @[],
    techAdvantages: @[],
    urgentResearchNeeds: @[],
    lastUpdated: filtered.turn
  )

  # Get our own tech levels
  let ourTech = filtered.ownHouse.techTree.levels

  # Extract enemy tech levels from intelligence
  # Note: This requires access to the full intelligence database
  # For now, return empty data - proper integration needs engine access
  # TODO: Pass IntelligenceDatabase to this function
  result.enemyTechLevels = initTable[HouseId, TechLevelEstimate]()

  # Compute gaps and advantages would go here
  # But we need enemy tech data first

  # Placeholder for urgent research needs
  # Would be computed from tech gaps + threat assessment
  result.urgentResearchNeeds = @[]
