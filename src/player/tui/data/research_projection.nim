## Shared projected research gating helpers for TUI.
##
## Keeps research allocation rules consistent between:
## - Input acceptors (what can be staged)
## - Rendering (what appears blocked)

import ../../sam/tui_model
import std/tables
import ../../../engine/types/tech
import ../../../engine/systems/tech/costs
import ./tech_info

proc researchItemAllocation*(
    allocation: ResearchAllocation,
    item: ResearchItem
): int =
  case item.kind
  of ResearchItemKind.EconomicLevel:
    allocation.economic.int
  of ResearchItemKind.ScienceLevel:
    allocation.science.int
  of ResearchItemKind.Technology:
    if allocation.technology.hasKey(item.field):
      allocation.technology[item.field].int
    else:
      0

proc currentTechLevel*(levels: TechLevel, item: ResearchItem): int =
  case item.kind
  of ResearchItemKind.EconomicLevel:
    levels.el.int
  of ResearchItemKind.ScienceLevel:
    levels.sl.int
  of ResearchItemKind.Technology:
    case item.field
    of TechField.ConstructionTech:
      levels.cst.int
    of TechField.WeaponsTech:
      levels.wep.int
    of TechField.TerraformingTech:
      levels.ter.int
    of TechField.ElectronicIntelligence:
      levels.eli.int
    of TechField.CloakingTech:
      levels.clk.int
    of TechField.ShieldTech:
      levels.sld.int
    of TechField.CounterIntelligence:
      levels.cic.int
    of TechField.StrategicLiftTech:
      levels.stl.int
    of TechField.FlagshipCommandTech:
      levels.fc.int
    of TechField.StrategicCommandTech:
      levels.sc.int
    of TechField.FighterDoctrine:
      levels.fd.int
    of TechField.AdvancedCarrierOps:
      levels.aco.int

proc currentResearchPoints*(points: ResearchPoints, item: ResearchItem): int =
  case item.kind
  of ResearchItemKind.EconomicLevel:
    points.economic.int
  of ResearchItemKind.ScienceLevel:
    points.science.int
  of ResearchItemKind.Technology:
    if points.technology.hasKey(item.field):
      points.technology[item.field].int
    else:
      0

proc projectedScienceLevel*(
    levels: TechLevel,
    points: ResearchPoints,
    allocation: ResearchAllocation
): int =
  ## Project SL using staged science allocation with one-level-per-turn cap.
  result = levels.sl.int
  let nextCost = slUpgradeCost(levels.sl)
  if nextCost <= 0:
    return result

  let totalScience = points.science.int + allocation.science.int
  if totalScience >= nextCost:
    result += 1

proc maxProjectedAllocation*(
    levels: TechLevel,
    points: ResearchPoints,
    allocation: ResearchAllocation,
    item: ResearchItem
): int =
  ## Maximum allowed staged PP allocation for a row under projected SL gating.
  let currentLevel = currentTechLevel(levels, item)
  let maxLevel = progressionMaxLevel(item)
  if currentLevel >= maxLevel:
    return 0

  let projectedSL = projectedScienceLevel(levels, points, allocation)
  let slRequired = techSlRequiredForLevel(item, currentLevel + 1)
  if projectedSL < slRequired:
    return 0

  let cost = techProgressCost(item, currentLevel)
  let progress = currentResearchPoints(points, item)
  result = max(0, cost - progress)

proc isBlockedProjected*(
    levels: TechLevel,
    points: ResearchPoints,
    allocation: ResearchAllocation,
    item: ResearchItem
): bool =
  let maxAllowed = maxProjectedAllocation(levels, points, allocation, item)
  maxAllowed <= 0
