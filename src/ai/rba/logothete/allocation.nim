## Logothete Research Allocation Module
##
## Byzantine Imperial Logothete - Keeper of Knowledge and Technology
##
## This module handles research budget allocation across:
## - ERP (Economic Research Points) → Economic Level
## - SRP (Science Research Points) → Science Level
## - TRP (Technology Research Points) → 9 tech fields
##
## Key Features:
## - Personality-driven allocation strategies
## - Tech cap detection and budget reallocation
## - Maxed field detection (prevents wasted RP)
## - Dynamic reallocation to available technologies

import std/[tables, strformat, sequtils, options]
import ../../../common/types/tech
import ../../../engine/[gamestate, fog_of_war, logger]
import ../../../engine/research/types as res_types
import ../../../engine/research/advancement  # For max tech level constants
import ../controller_types
import ../shared/intelligence_types  # For RequirementPriority, ResearchPriority
import ../config  # For globalRBAConfig

proc applyTechFieldAllocation(alloc: TechFieldAllocation, techBudget: int): Table[TechField, int] =
  ## Convert TechFieldAllocation percentages to actual PP amounts
  ## Returns Table with tech field allocations
  result = initTable[TechField, int]()
  result[TechField.WeaponsTech] = int(float(techBudget) * alloc.weapons_tech)
  result[TechField.ConstructionTech] = int(float(techBudget) * alloc.construction_tech)
  result[TechField.CloakingTech] = int(float(techBudget) * alloc.cloaking_tech)
  result[TechField.ElectronicIntelligence] = int(float(techBudget) * alloc.electronic_intelligence)
  result[TechField.TerraformingTech] = int(float(techBudget) * alloc.terraforming_tech)
  result[TechField.ShieldTech] = int(float(techBudget) * alloc.shield_tech)
  result[TechField.CounterIntelligence] = int(float(techBudget) * alloc.counter_intelligence)
  result[TechField.FighterDoctrine] = int(float(techBudget) * alloc.fighter_doctrine)
  result[TechField.AdvancedCarrierOps] = int(float(techBudget) * alloc.advanced_carrier_ops)

proc allocateResearch*(
  controller: AIController,
  filtered: FilteredGameState,
  researchBudget: int
): res_types.ResearchAllocation =
  ## Allocate research budget across EL/SL/TRP based on personality and tech caps
  ##
  ## Returns ResearchAllocation with:
  ## - economic: PP allocated to Economic Level
  ## - science: PP allocated to Science Level
  ## - technology: Table[TechField, int] for TRP allocations
  ##
  ## Handles:
  ## - Maxed EL/SL caps (redirects to TRP)
  ## - Maxed TRP fields (redistributes to available techs)
  ## - Personality-driven priorities

  result = res_types.ResearchAllocation(
    economic: 0,
    science: 0,
    technology: initTable[TechField, int]()
  )

  let p = controller.personality

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Logothete: Allocating {researchBudget}PP " &
           &"(techPriority={p.techPriority:.2f})")

  if researchBudget <= 0:
    return result

  # Get current tech levels to check for maxed EL/SL
  let currentEL = filtered.ownHouse.techTree.levels.economicLevel
  let currentSL = filtered.ownHouse.techTree.levels.scienceLevel

  # Check if EL/SL are at maximum levels (caps from advancement.nim)
  let elMaxed = currentEL >= maxEconomicLevel  # EL caps at 11
  let slMaxed = currentSL >= maxScienceLevel   # SL caps at 8

  # Log max level detection for diagnostics
  if elMaxed or slMaxed:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Logothete: Tech caps reached - EL={currentEL}/{maxEconomicLevel} " &
            &"(maxed={elMaxed}), SL={currentSL}/{maxScienceLevel} (maxed={slMaxed})")

  # Distribute research budget across EL/SL/TRP based on strategy
  # Configuration from config/rba.toml [logothete.allocation] and [logothete.tech_allocations]
  let cfg_thresholds = controller.rbaConfig.logothete_tech_allocations_thresholds

  if p.techPriority > cfg_thresholds.tech_priority_threshold:
    # Heavy research investment - balance across all three categories (Act 1-2 ratios)
    result.economic = int(float(researchBudget) * controller.rbaConfig.logothete_allocation.act1_economic_ratio)
    result.science = int(float(researchBudget) * controller.rbaConfig.logothete_allocation.act1_science_ratio)
    let techBudget = researchBudget - result.economic - result.science

    if p.aggression > cfg_thresholds.aggression_peaceful:
      # Aggressive: weapons + cloaking + construction + FD
      result.technology = applyTechFieldAllocation(controller.rbaConfig.logothete_tech_allocations_tech_priority_aggressive, techBudget)
    else:
      # Peaceful: infrastructure + counter-intel + terraforming
      result.technology = applyTechFieldAllocation(controller.rbaConfig.logothete_tech_allocations_tech_priority_peaceful, techBudget)
  elif p.economicFocus > cfg_thresholds.economic_focus_threshold:
    # Economic focus: prioritize EL/SL for growth + infrastructure (Act 3 balanced)
    result.economic = int(float(researchBudget) * controller.rbaConfig.logothete_allocation.act3_economic_ratio)
    result.science = int(float(researchBudget) * controller.rbaConfig.logothete_allocation.act3_science_ratio)
    let techBudget = researchBudget - result.economic - result.science
    result.technology = applyTechFieldAllocation(controller.rbaConfig.logothete_tech_allocations_economic_focus, techBudget)
  elif p.aggression > cfg_thresholds.aggression_threshold:
    # Aggressive: minimal EL/SL, heavy military tech focus (war economy)
    result.economic = int(float(researchBudget) * controller.rbaConfig.logothete_allocation.war_economic_ratio)
    result.science = int(float(researchBudget) * controller.rbaConfig.logothete_allocation.war_science_ratio)
    let techBudget = researchBudget - result.economic - result.science
    result.technology = applyTechFieldAllocation(controller.rbaConfig.logothete_tech_allocations_war_economy, techBudget)
  else:
    # Balanced strategy across all tech (default allocation)
    result.economic = int(float(researchBudget) * controller.rbaConfig.logothete_allocation.default_economic_ratio)
    result.science = int(float(researchBudget) * controller.rbaConfig.logothete_allocation.default_science_ratio)
    let techBudget = researchBudget - result.economic - result.science
    result.technology = applyTechFieldAllocation(controller.rbaConfig.logothete_tech_allocations_balanced_default, techBudget)

  # INTELLIGENCE-DRIVEN TECH GAP BOOSTING (Phase C)
  # Boost allocation to critical tech gaps identified by Drungarius
  if controller.intelligenceSnapshot.isSome:
    let intel = controller.intelligenceSnapshot.get()
    let researchIntel = intel.research
    let urgentNeeds = researchIntel.urgentResearchNeeds

    if urgentNeeds.len > 0:
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Logothete: {urgentNeeds.len} urgent tech gaps identified - adjusting allocation")

      # Boost critical and high priority gaps
      for gap in urgentNeeds:
        let field = gap.field
        let pri = gap.priority
        let reason = gap.reason

        if pri == intelligence_types.RequirementPriority.Critical:
          # Boost critical gaps by 50%
          var currentAlloc = 0
          if result.technology.hasKey(field):
            currentAlloc = result.technology[field]
          let boost = max(researchBudget div 10, 50)  # At least 10% of budget or 50PP
          result.technology[field] = currentAlloc + boost
          logInfo(LogCategory.lcAI,
                  &"  CRITICAL GAP: Boosting {field} by {boost}PP - " & reason)

        elif pri == intelligence_types.RequirementPriority.High:
          # Boost high priority gaps by 25%
          var currentAlloc = 0
          if result.technology.hasKey(field):
            currentAlloc = result.technology[field]
          let boost = max(researchBudget div 20, 25)  # At least 5% of budget or 25PP
          result.technology[field] = currentAlloc + boost
          logInfo(LogCategory.lcAI,
                  &"  HIGH PRIORITY: Boosting {field} by {boost}PP - " & reason)

  # REALLOCATION LOGIC: Redirect budget from maxed EL/SL/TRP to available techs
  # This prevents AI from wasting RP on technologies that cannot advance
  var redirectedBudget = 0

  # If EL is maxed, redirect ERP to TRP (Construction priority)
  if elMaxed and result.economic > 0:
    redirectedBudget += result.economic
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Logothete: Redirecting {result.economic}PP from maxed EL to TRP")
    result.economic = 0

  # If SL is maxed, redirect SRP to TRP (Weapons priority for aggressive, Construction otherwise)
  if slMaxed and result.science > 0:
    redirectedBudget += result.science
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Logothete: Redirecting {result.science}PP from maxed SL to TRP")
    result.science = 0

  # Check TRP field caps and redirect budget from maxed fields
  # Get current tech levels from tree
  let techLevels = filtered.ownHouse.techTree.levels

  proc getTechMax(field: TechField): int =
    ## Get maximum level for tech field (9 fields only, EL/SL handled separately)
    case field
    of TechField.ConstructionTech: maxConstructionTech
    of TechField.WeaponsTech: maxWeaponsTech
    of TechField.TerraformingTech: maxTerraformingTech
    of TechField.ElectronicIntelligence: maxElectronicIntelligence
    of TechField.CloakingTech: maxCloakingTech
    of TechField.ShieldTech: maxShieldTech
    of TechField.CounterIntelligence: maxCounterIntelligence
    of TechField.FighterDoctrine: maxFighterDoctrine
    of TechField.AdvancedCarrierOps: maxAdvancedCarrierOps

  proc getCurrentTechLevel(field: TechField): int =
    ## Get current level for tech field from tree (9 fields only, EL/SL handled separately)
    case field
    of TechField.ConstructionTech: techLevels.constructionTech
    of TechField.WeaponsTech: techLevels.weaponsTech
    of TechField.TerraformingTech: techLevels.terraformingTech
    of TechField.ElectronicIntelligence: techLevels.electronicIntelligence
    of TechField.CloakingTech: techLevels.cloakingTech
    of TechField.ShieldTech: techLevels.shieldTech
    of TechField.CounterIntelligence: techLevels.counterIntelligence
    of TechField.FighterDoctrine: techLevels.fighterDoctrine
    of TechField.AdvancedCarrierOps: techLevels.advancedCarrierOps

  # Collect budget from maxed TRP fields
  var maxedFields: seq[TechField] = @[]
  for field, amount in result.technology.pairs:
    if amount > 0 and getCurrentTechLevel(field) >= getTechMax(field):
      redirectedBudget += amount
      maxedFields.add(field)
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Logothete: Redirecting {amount}PP from maxed {field} " &
              &"(level {getCurrentTechLevel(field)}/{getTechMax(field)})")

  # Remove maxed fields from allocation
  for field in maxedFields:
    result.technology.del(field)

  # Distribute redirected budget to non-maxed TRP fields based on personality
  if redirectedBudget > 0:
    # Build list of available (non-maxed) tech fields
    var availableTechs: seq[TechField] = @[]

    # Priority order varies by personality
    if p.aggression > 0.5:
      # Aggressive: WEP > CST > CLK > ELI
      availableTechs = @[TechField.WeaponsTech, TechField.ConstructionTech,
                        TechField.CloakingTech, TechField.ElectronicIntelligence]
    else:
      # Peaceful/Economic: CST > TER > SLD > CIC
      availableTechs = @[TechField.ConstructionTech, TechField.TerraformingTech,
                        TechField.ShieldTech, TechField.CounterIntelligence]

    # Filter out maxed techs from available list
    availableTechs = availableTechs.filterIt(getCurrentTechLevel(it) < getTechMax(it))

    # Distribute redirected budget across available techs
    if availableTechs.len > 0:
      let perTech = redirectedBudget div availableTechs.len
      for tech in availableTechs:
        result.technology[tech] = result.technology.getOrDefault(tech) + perTech
        logDebug(LogCategory.lcAI,
                 &"{controller.houseId} Logothete: Allocated {perTech}PP to {tech}")
    else:
      # All techs maxed - log warning and redistribute to treasury (handled by caller)
      logWarn(LogCategory.lcAI,
              &"{controller.houseId} Logothete: All tech fields maxed! {redirectedBudget}PP research budget wasted")

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Logothete: Redirected {redirectedBudget}PP from {maxedFields.len} maxed fields")
