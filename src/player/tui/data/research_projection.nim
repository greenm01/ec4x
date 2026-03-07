## Shared projected research gating helpers for TUI.
##
## Pool-based deposit/purchase model:
## - Players deposit PP into shared pools (ERP/SRP/TRP)
## - Players explicitly purchase tech upgrades
## - No auto-advancement

import ../../sam/tui_model
import std/tables
import ../../../engine/types/tech
import ../../../engine/systems/tech/costs
import ./tech_info

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

proc poolAccumulated*(points: ResearchPoints, pool: ResearchPoolIdx): int =
  case pool
  of ResearchPoolIdx.PoolERP: points.erp.int
  of ResearchPoolIdx.PoolSRP: points.srp.int
  of ResearchPoolIdx.PoolTRP: points.trp.int

proc currentResearchPoints*(points: ResearchPoints, item: ResearchItem): int =
  ## Return accumulated RP in the pool that funds this item.
  case item.kind
  of ResearchItemKind.EconomicLevel:
    points.erp.int
  of ResearchItemKind.ScienceLevel:
    points.srp.int
  of ResearchItemKind.Technology:
    if isSrpField(item.field):
      points.srp.int
    else:
      points.trp.int

proc researchItemPool*(item: ResearchItem): ResearchPoolIdx =
  case item.kind
  of ResearchItemKind.EconomicLevel: ResearchPoolIdx.PoolERP
  of ResearchItemKind.ScienceLevel:  ResearchPoolIdx.PoolSRP
  of ResearchItemKind.Technology:
    if isSrpField(item.field): ResearchPoolIdx.PoolSRP
    else: ResearchPoolIdx.PoolTRP

proc estimateColonyGrossOutput(
    levels: TechLevel,
    colony: ColonyInfo,
    houseTaxRate: int
): int32 =
  let pop = max(0, colony.populationUnits)
  let iu = max(0, colony.industrialUnits)

  var safeTax = houseTaxRate
  if safeTax < 0:
    safeTax = 0
  elif safeTax > 100:
    safeTax = 100

  let elMod = 1.0 + (float(levels.el) * 0.05)
  let cstLevel = max(1'i32, levels.cst)
  let cstMod = 1.0 + (float(cstLevel - 1) * 0.10)
  let prodGrowth = (50.0 - float(safeTax)) / 500.0
  let growthMod = max(0.0, 1.0 + prodGrowth)

  let output = float(pop) + float(iu) * elMod * cstMod * growthMod
  int32(max(0, int(output)))

proc projectedResearchGho*(
    levels: TechLevel,
    colonies: seq[ColonyInfo],
    fallbackProduction: int,
    houseTaxRate: int
): int32 =
  var knownGho = 0'i32
  for colony in colonies:
    knownGho += int32(max(0, colony.grossOutput))
  if knownGho > 0:
    return knownGho

  var estimatedGho = 0'i32
  for colony in colonies:
    estimatedGho += estimateColonyGrossOutput(levels, colony, houseTaxRate)
  if estimatedGho > 0:
    return estimatedGho

  int32(max(1, fallbackProduction))

proc projectedPoolRP*(
    points: ResearchPoints,
    deposits: ResearchDeposits,
    pool: ResearchPoolIdx,
    gho: int32,
    slLevel: int32
): int =
  ## Accumulated RP + conversion of staged PP deposit for a pool.
  let effectiveGho = max(1'i32, gho)
  case pool
  of ResearchPoolIdx.PoolERP:
    points.erp.int + (if deposits.erp > 0: convertPPToERP(deposits.erp, effectiveGho, slLevel).int else: 0)
  of ResearchPoolIdx.PoolSRP:
    points.srp.int + (if deposits.srp > 0: convertPPToSRP(deposits.srp, effectiveGho, slLevel).int else: 0)
  of ResearchPoolIdx.PoolTRP:
    points.trp.int + (if deposits.trp > 0: convertPPToTRP(deposits.trp, effectiveGho, slLevel).int else: 0)

proc projectedScienceLevel*(
    levels: TechLevel,
    points: ResearchPoints,
    deposits: ResearchDeposits,
    purchases: TechPurchaseSet,
    gho: int32
): int =
  ## Project SL: current + 1 if SL purchase is toggled and affordable.
  result = levels.sl.int
  if not purchases.science:
    return result
  let nextCost = slUpgradeCost(levels.sl).int
  if nextCost <= 0:
    return result
  let poolRP = projectedPoolRP(points, deposits, ResearchPoolIdx.PoolSRP, gho, levels.sl)
  if poolRP >= nextCost:
    result += 1

proc isPurchaseToggled*(purchases: TechPurchaseSet, item: ResearchItem): bool =
  case item.kind
  of ResearchItemKind.EconomicLevel: purchases.economic
  of ResearchItemKind.ScienceLevel: purchases.science
  of ResearchItemKind.Technology: item.field in purchases.technology

proc poolCap*(levels: TechLevel, pool: ResearchPoolIdx): int =
  ## Soft cap: sum of RP costs for all unresearched levels in the pool.
  for item in researchItems():
    if researchItemPool(item) != pool: continue
    let currentLevel = currentTechLevel(levels, item)
    let maxLevel = progressionMaxLevel(item)
    for lvl in currentLevel ..< maxLevel:
      result += techProgressCost(item, lvl)

proc projectedPoolBalance*(
    levels: TechLevel,
    points: ResearchPoints,
    deposits: ResearchDeposits,
    purchases: TechPurchaseSet,
    pool: ResearchPoolIdx,
    gho: int32
): int =
  ## Pool RP remaining after deducting all valid, affordable purchases.
  result = projectedPoolRP(points, deposits, pool, gho, levels.sl)
  let projSL = projectedScienceLevel(levels, points, deposits, purchases, gho)
  for item in researchItems():
    if researchItemPool(item) != pool: continue
    if not isPurchaseToggled(purchases, item): continue
    let lvl = currentTechLevel(levels, item)
    if lvl >= progressionMaxLevel(item): continue
    if projSL < techSlRequiredForLevel(item, lvl + 1): continue
    let cost = techProgressCost(item, lvl)
    if result >= cost: result -= cost

proc projectedTechLevel*(
    levels: TechLevel,
    points: ResearchPoints,
    deposits: ResearchDeposits,
    purchases: TechPurchaseSet,
    item: ResearchItem,
    gho: int32
): int =
  ## Project a research row level: current + 1 if purchase toggled and affordable.
  result = currentTechLevel(levels, item)
  let maxLevel = progressionMaxLevel(item)
  if result >= maxLevel:
    return maxLevel
  if not isPurchaseToggled(purchases, item):
    return result
  # SL gating check (use projected SL if SL purchase is also toggled)
  let projectedSL = projectedScienceLevel(levels, points, deposits, purchases, gho)
  let slRequired = techSlRequiredForLevel(item, result + 1)
  if projectedSL < slRequired:
    return result
  # Affordability: compute running balance from prior items in same pool
  let pool = researchItemPool(item)
  var balance = projectedPoolRP(points, deposits, pool, gho, levels.sl)
  for priorItem in researchItems():
    if priorItem.code == item.code: break
    if researchItemPool(priorItem) != pool: continue
    if not isPurchaseToggled(purchases, priorItem): continue
    let pLvl = currentTechLevel(levels, priorItem)
    if pLvl >= progressionMaxLevel(priorItem): continue
    if projectedSL < techSlRequiredForLevel(priorItem, pLvl + 1): continue
    let pCost = techProgressCost(priorItem, pLvl)
    if balance >= pCost: balance -= pCost
  let cost = techProgressCost(item, result)
  if balance < cost: return result   # unaffordable → no level-up shown
  result += 1

proc isBlockedProjected*(
    levels: TechLevel,
    points: ResearchPoints,
    deposits: ResearchDeposits,
    purchases: TechPurchaseSet,
    item: ResearchItem,
    gho: int32
): bool =
  ## Item is blocked if maxed or SL-gated at current projected SL.
  let currentLevel = currentTechLevel(levels, item)
  let maxLevel = progressionMaxLevel(item)
  if currentLevel >= maxLevel:
    return true
  if item.kind == ResearchItemKind.EconomicLevel or
      item.kind == ResearchItemKind.ScienceLevel:
    return false
  let projectedSL = projectedScienceLevel(levels, points, deposits, purchases, gho)
  let slRequired = techSlRequiredForLevel(item, currentLevel + 1)
  projectedSL < slRequired
