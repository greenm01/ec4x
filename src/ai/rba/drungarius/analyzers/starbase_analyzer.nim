## Starbase Intelligence Analyzer
##
## Processes StarbaseIntelReport from engine intelligence database
## Analyzes enemy economy, research priorities, and tech levels
##
## Phase C implementation

import std/[tables, options, strutils]
import ../../../../engine/[gamestate, fog_of_war]
import ../../../../engine/intelligence/types as intel_types
import ../../../../common/types/[core, tech]
import ../../controller_types
import ../../config
import ../../shared/intelligence_types

proc calculateTechGaps(
  ownTech: Table[TechField, int],
  enemyTech: Table[TechField, int]
): Table[TechField, int] =
  ## Calculate tech level gaps (negative = we're behind)
  result = initTable[TechField, int]()

  for field in TechField:
    let ownLevel = ownTech.getOrDefault(field, 0)
    let enemyLevel = enemyTech.getOrDefault(field, 0)
    let gap = ownLevel - enemyLevel  # Positive = ahead, negative = behind
    if gap != 0:
      result[field] = gap

proc analyzeStarbaseIntelligence*(
  filtered: FilteredGameState,
  controller: AIController
): tuple[enemyEcon: Table[HouseId, EconomicAssessment], enemyTech: Table[HouseId, TechLevelEstimate]] =
  ## Analyze StarbaseIntelReport data to assess enemy economic and technological capabilities
  ## Phase C implementation

  result.enemyEcon = initTable[HouseId, EconomicAssessment]()
  result.enemyTech = initTable[HouseId, TechLevelEstimate]()

  let config = controller.rbaConfig.intelligence
  let ownHouse = filtered.ownHouse

  # Iterate through starbase intelligence reports
  for systemId, report in filtered.ownHouse.intelligence.starbaseReports:
    let targetHouse = report.targetOwner

    # Skip own starbases
    if targetHouse == controller.houseId:
      continue

    # === ECONOMIC ASSESSMENT ===
    if report.treasuryBalance.isSome or report.grossIncome.isSome:
      # Count known colonies for this house
      var knownColonies = 0
      for colSystemId, colReport in filtered.ownHouse.intelligence.colonyReports:
        if colReport.targetOwner == targetHouse:
          knownColonies += 1

      # Extract economic data
      let treasuryBalance = report.treasuryBalance.get(0)
      let grossIncome = report.grossIncome.get(0)
      let netIncome = report.netIncome.get(0)
      let taxRate = report.taxRate.get(0.0)

      # Calculate relative economic strength
      let ownIncome = filtered.ownColonies.len * 100  # Rough estimate
      let relativeStrength = if ownIncome > 0:
        netIncome.float / ownIncome.float
      else:
        1.0

      result.enemyEcon[targetHouse] = EconomicAssessment(
        houseId: targetHouse,
        knownColonyCount: knownColonies,
        estimatedTotalProduction: grossIncome,
        estimatedIncome: some(netIncome),
        estimatedTechSpending: report.researchAllocations.map(proc(alloc: tuple[erp, srp, trp: int]): int = alloc.erp + alloc.srp + alloc.trp),
        taxRate: some(taxRate),
        relativeStrength: relativeStrength,
        lastUpdated: report.gatheredTurn
      )

    # === TECH ASSESSMENT ===
    if report.techLevels.isSome:
      let enemyTechLevels = report.techLevels.get()

      # Build tech level table
      var techTable = initTable[TechField, int]()
      var confidenceTable = initTable[TechField, float]()

      # Extract tech levels from TechLevel object fields
      techTable[TechField.ConstructionTech] = enemyTechLevels.constructionTech
      techTable[TechField.WeaponsTech] = enemyTechLevels.weaponsTech
      techTable[TechField.TerraformingTech] = enemyTechLevels.terraformingTech
      techTable[TechField.ElectronicIntelligence] = enemyTechLevels.electronicIntelligence
      techTable[TechField.CloakingTech] = enemyTechLevels.cloakingTech
      techTable[TechField.ShieldTech] = enemyTechLevels.shieldTech
      techTable[TechField.CounterIntelligence] = enemyTechLevels.counterIntelligence
      techTable[TechField.FighterDoctrine] = enemyTechLevels.fighterDoctrine
      techTable[TechField.AdvancedCarrierOps] = enemyTechLevels.advancedCarrierOps

      # High confidence for all fields from starbase hack
      for field in TechField:
        confidenceTable[field] = 1.0

      # Determine current research field
      var currentResearch = none(TechField)
      if report.currentResearch.isSome:
        let researchStr = report.currentResearch.get()
        # Parse research string to TechField
        # Research strings typically match TechField enum names
        try:
          currentResearch = some(parseEnum[TechField](researchStr))
        except ValueError:
          # Unable to parse research field, leave as none
          currentResearch = none(TechField)

      result.enemyTech[targetHouse] = TechLevelEstimate(
        houseId: targetHouse,
        techLevels: techTable,
        confidence: confidenceTable,
        currentResearch: currentResearch,
        lastUpdated: report.gatheredTurn,
        source: TechIntelSource.StarbaseHack
      )

proc generateTechGapPriorities*(
  filtered: FilteredGameState,
  enemyTech: Table[HouseId, TechLevelEstimate],
  controller: AIController
): seq[ResearchPriority] =
  ## Generate research priorities based on tech gaps with enemies
  ## Phase C implementation
  result = @[]

  let config = controller.rbaConfig.intelligence

  # Extract our own tech levels from TechTree
  var ownTech = initTable[TechField, int]()
  let techLevels = filtered.ownHouse.techTree.levels
  ownTech[TechField.ConstructionTech] = techLevels.constructionTech
  ownTech[TechField.WeaponsTech] = techLevels.weaponsTech
  ownTech[TechField.TerraformingTech] = techLevels.terraformingTech
  ownTech[TechField.ElectronicIntelligence] = techLevels.electronicIntelligence
  ownTech[TechField.CloakingTech] = techLevels.cloakingTech
  ownTech[TechField.ShieldTech] = techLevels.shieldTech
  ownTech[TechField.CounterIntelligence] = techLevels.counterIntelligence
  ownTech[TechField.FighterDoctrine] = techLevels.fighterDoctrine
  ownTech[TechField.AdvancedCarrierOps] = techLevels.advancedCarrierOps

  # Analyze gaps against each known enemy
  for houseId, techEstimate in enemyTech:
    let gaps = calculateTechGaps(ownTech, techEstimate.techLevels)

    for field, gap in gaps:
      if gap < 0:  # We're behind
        let gapSize = abs(gap)

        # Determine priority based on gap size
        let priority = if gapSize >= config.tech_gap_critical_threshold:
          intelligence_types.RequirementPriority.Critical
        elif gapSize >= config.tech_gap_high_threshold:
          intelligence_types.RequirementPriority.High
        else:
          intelligence_types.RequirementPriority.Medium

        # Estimate turns to close gap (rough calculation)
        let estimatedTurns = gapSize * 5  # Simplified: 5 turns per level

        result.add(ResearchPriority(
          field: field,
          currentLevel: ownTech.getOrDefault(field, 0),
          targetLevel: techEstimate.techLevels[field],
          reason: "Enemy " & $houseId & " is " & $gapSize & " levels ahead",
          priority: priority,
          estimatedTurns: estimatedTurns
        ))
