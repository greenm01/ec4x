## Counter-Tech Module
##
## Byzantine Imperial Logothete - Counter-Technology Selection
##
## Selects research to counter specific enemy capabilities
## Based on intelligence about enemy tech levels and strengths

import std/[tables, options, algorithm, strformat]
import ../../../common/types/tech
import ../../../engine/[gamestate, logger]
import ../shared/intelligence_types
import ../../common/types as ai_types

# =============================================================================
# Counter-Tech Analysis
# =============================================================================

type
  CounterTechRecommendation* = object
    ## Recommended counter-tech vs specific enemy
    field*: TechField
    priority*: float  # 0.0-1.0 scale
    reason*: string
    enemyAdvantage*: int  # How many levels they're ahead

proc selectCounterTech*(
  enemyHouse: HouseId,
  enemyTechLevels: TechLevelEstimate,
  ourTechLevels: TechTree,
  intelSnapshot: IntelligenceSnapshot
): seq[CounterTechRecommendation] =
  ## Phase 6.2: Select counter-tech research to neutralize enemy advantages
  ## Returns prioritized recommendations (highest priority first)

  result = @[]

  # 1. Counter Superior Weapons: If enemy has better weapons, research defensive tech
  if enemyTechLevels.techLevels.hasKey(TechField.WeaponsTech):
    let enemyWeapons = enemyTechLevels.techLevels[TechField.WeaponsTech]
    let ourWeapons = ourTechLevels.levels.weaponsTech
    let gap = enemyWeapons - ourWeapons

    if gap >= 2:
      # Significant weapons gap - need defensive countermeasures
      # Option 1: Match their weapons (direct counter)
      result.add(CounterTechRecommendation(
        field: TechField.WeaponsTech,
        priority: 0.8 + (float(gap) * 0.05),  # Higher gap = higher priority
        reason: &"Match enemy weapons (they lead by {gap} levels)",
        enemyAdvantage: gap
      ))

  # 2. Counter Superior Construction: If enemy building faster/better, match CST
  if enemyTechLevels.techLevels.hasKey(TechField.ConstructionTech):
    let enemyCST = enemyTechLevels.techLevels[TechField.ConstructionTech]
    let ourCST = ourTechLevels.levels.constructionTech
    let gap = enemyCST - ourCST

    if gap >= 2:
      # CST gap = they can build units we can't
      result.add(CounterTechRecommendation(
        field: TechField.ConstructionTech,
        priority: 0.9 + (float(gap) * 0.05),  # Very high priority (gates units)
        reason: &"Match construction tech (access to advanced units)",
        enemyAdvantage: gap
      ))

  # 3. Counter Strong Economy: If enemy economically superior, consider espionage/sabotage
  if intelSnapshot.economic.enemyEconomicStrength.hasKey(enemyHouse):
    let enemyEcon = intelSnapshot.economic.enemyEconomicStrength[enemyHouse]
    if enemyEcon.relativeStrength > 1.5:  # Enemy 50% stronger economically
      # Suggest ELI (Electronic Intelligence) to disrupt their economy
      result.add(CounterTechRecommendation(
        field: TechField.ElectronicIntelligence,
        priority: 0.6,
        reason: &"Counter strong economy via ELI (they produce {enemyEcon.relativeStrength:.1f}x our output)",
        enemyAdvantage: int((enemyEcon.relativeStrength - 1.0) * 100.0)
      ))

  # 4. Counter Espionage Activity: If detecting their espionage, boost counter-intel
  if intelSnapshot.espionage.detectionRisks.hasKey(enemyHouse):
    let risk = intelSnapshot.espionage.detectionRisks[enemyHouse]
    if risk in {DetectionRiskLevel.High, DetectionRiskLevel.Critical}:
      # Heavy espionage detected - need CIC (Counter-Intelligence)
      result.add(CounterTechRecommendation(
        field: TechField.CounterIntelligence,
        priority: 0.7,
        reason: &"Counter-intelligence vs {enemyHouse} espionage (risk: {$risk})",
        enemyAdvantage: if risk == DetectionRiskLevel.Critical: 3 else: 2
      ))

  # 5. Counter Advanced Fighters: If enemy has better fighter doctrine
  if enemyTechLevels.techLevels.hasKey(TechField.FighterDoctrine):
    let enemyFD = enemyTechLevels.techLevels[TechField.FighterDoctrine]
    let ourFD = ourTechLevels.levels.fighterDoctrine
    let gap = enemyFD - ourFD

    if gap >= 2:
      # Fighter gap = they have superior fighter swarms
      result.add(CounterTechRecommendation(
        field: TechField.FighterDoctrine,
        priority: 0.7 + (float(gap) * 0.05),
        reason: &"Counter superior fighters (they lead by {gap} levels)",
        enemyAdvantage: gap
      ))

  # Sort by priority (highest first)
  result.sort(proc(a, b: CounterTechRecommendation): int =
    if a.priority > b.priority: -1
    elif a.priority < b.priority: 1
    else: 0
  )

  return result

proc recommendCounterTechAgainst*(
  enemyHouse: HouseId,
  intelSnapshot: IntelligenceSnapshot,
  ourTechLevels: TechTree
): Option[CounterTechRecommendation] =
  ## Get top counter-tech recommendation vs specific enemy
  ## Returns none if no significant counter needed

  if not intelSnapshot.research.enemyTechLevels.hasKey(enemyHouse):
    return none(CounterTechRecommendation)

  let enemyTech = intelSnapshot.research.enemyTechLevels[enemyHouse]
  let recommendations = selectCounterTech(enemyHouse, enemyTech, ourTechLevels, intelSnapshot)

  if recommendations.len > 0:
    return some(recommendations[0])  # Return top recommendation
  else:
    return none(CounterTechRecommendation)
