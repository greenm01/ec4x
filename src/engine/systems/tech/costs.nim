## Research Cost Calculation
##
## Calculate RP costs and PP conversion per economy.md:4.0
##
## Cost formulas:
## - ERP: (5 + log(GHO)) PP per ERP
## - SRP: Similar scaling
## - TRP: Varies by tech field

import std/[math, tables]
import ../../types/tech
import ../../globals

export tech.ResearchAllocation

## Economic Research Points (economy.md:4.2)

proc calculateERPCost*(gho: int): float =
  ## Calculate PP cost per ERP
  ## Formula: 1 ERP = (5 + log(GHO)) PP
  result = 5.0 + log10(float(gho))

proc convertPPToERP*(pp: int32, gho: int32): int32 =
  ## Convert PP to ERP
  let costPerERP = calculateERPCost(gho.int)
  result = int32(float(pp) / costPerERP)

proc getELUpgradeCost*(currentLevel: int32): int32 =
  ## Get ERP cost to advance Economic Level
  ## Per economy.md:4.2 and config/tech.kdl
  ## Uses Table pattern for levels
  let nextLevel = currentLevel + 1
  if gameConfig.tech.el.levels.hasKey(nextLevel):
    return gameConfig.tech.el.levels[nextLevel].erpCost
  else:
    return 0 # Level not found or at max

proc getELModifier*(level: int32): float32 =
  ## Get EL economic modifier (as multiplier)
  ## Per economy.md:4.2: +5% per level, capped at 50%
  ## Returns multiplier (e.g., 1.05 for EL1, 1.50 for EL10+)
  ## Uses Table pattern for levels
  if gameConfig.tech.el.levels.hasKey(level):
    return gameConfig.tech.el.levels[level].multiplier
  elif level <= 0:
    return 1.0 # Base level (no bonus)
  else:
    # Level not in config, calculate dynamically
    # +5% per level, capped at 50%
    let bonus = min(float32(level) * 0.05, 0.50)
    return 1.0 + bonus

## Science Research Points (economy.md:4.3)

proc calculateSRPCost*(currentSL: int): float =
  ## Calculate PP cost per SRP
  ## Formula per economy.md:4.3: 1 SRP = 2 + SL(0.5) PP
  result = 2.0 + float(currentSL) * 0.5

proc convertPPToSRP*(pp: int32, currentSL: int32): int32 =
  ## Convert PP to SRP
  let costPerSRP = calculateSRPCost(currentSL.int)
  result = int32(float(pp) / costPerSRP)

proc getSLUpgradeCost*(currentLevel: int32): int32 =
  ## Get SRP cost to advance Science Level
  ## Per economy.md:4.3 and config/tech.kdl
  ## Uses Table pattern for levels
  let nextLevel = currentLevel + 1
  if gameConfig.tech.sl.levels.hasKey(nextLevel):
    let levelData = gameConfig.tech.sl.levels[nextLevel]
    # SL uses srpRequired as the cost
    return levelData.srpRequired
  else:
    return 0 # Level not found or at max

proc getSLModifier*(level: int): float =
  ## Get SL research modifier
  ## Affects TRP costs per economy.md:4.4
  ##
  ## Per the TRP formula: 1 TRP = (5 + 4(SL))/10 + log(GHO) * 0.5 PP
  ## Higher SL increases TRP cost (more advanced science infrastructure)
  ##
  ## This modifier is 5% per SL level (baseline 1.0 at SL0)
  result = 1.0 + (float(level) * 0.05)

## Technology Research Points (economy.md:4.4)

proc getTRPCost*(techField: TechField, slLevel: int, gho: int): float =
  ## Get PP cost per TRP for specific tech field
  ## Formula per economy.md:4.4: 1 TRP = (5 + 4(SL))/10 + log(GHO) * 0.5 PP
  ##
  ## Args:
  ##   techField: The technology being researched
  ##   slLevel: Current Science Level
  ##   gho: Gross House Output
  result = (5.0 + 4.0 * float(slLevel)) / 10.0 + log10(float(gho)) * 0.5

proc convertPPToTRP*(
    pp: int32, techField: TechField, slLevel: int32, gho: int32
): int32 =
  ## Convert PP to TRP for specific tech field
  let costPerTRP = getTRPCost(techField, slLevel.int, gho.int)
  result = int32(float(pp) / costPerTRP)

proc getTechUpgradeCost*(techField: TechField, currentLevel: int32): int32 =
  ## Get TRP cost to advance tech level
  ## Per economy.md:4.4-4.12 and config/tech.kdl
  ## Uses Table pattern for levels
  let nextLevel = currentLevel + 1

  # Get cost from appropriate config table
  case techField
  of TechField.ConstructionTech:
    if gameConfig.tech.cst.levels.hasKey(nextLevel):
      return gameConfig.tech.cst.levels[nextLevel].trpCost
  of TechField.WeaponsTech:
    if gameConfig.tech.wep.levels.hasKey(nextLevel):
      return gameConfig.tech.wep.levels[nextLevel].trpCost
  of TechField.TerraformingTech:
    if gameConfig.tech.ter.levels.hasKey(nextLevel):
      return gameConfig.tech.ter.levels[nextLevel].srpCost
  of TechField.ElectronicIntelligence:
    if gameConfig.tech.eli.levels.hasKey(nextLevel):
      return gameConfig.tech.eli.levels[nextLevel].srpCost
  of TechField.CloakingTech:
    if gameConfig.tech.clk.levels.hasKey(nextLevel):
      return gameConfig.tech.clk.levels[nextLevel].srpCost
  of TechField.ShieldTech:
    if gameConfig.tech.sld.levels.hasKey(nextLevel):
      return gameConfig.tech.sld.levels[nextLevel].srpCost
  of TechField.CounterIntelligence:
    if gameConfig.tech.cic.levels.hasKey(nextLevel):
      return gameConfig.tech.cic.levels[nextLevel].srpCost
  of TechField.StrategicLiftTech:
    if gameConfig.tech.stl.levels.hasKey(nextLevel):
      return gameConfig.tech.stl.levels[nextLevel].srpCost
  of TechField.FlagshipCommandTech:
    if gameConfig.tech.fc.levels.hasKey(nextLevel):
      return gameConfig.tech.fc.levels[nextLevel].trpCost
  of TechField.StrategicCommandTech:
    if gameConfig.tech.sc.levels.hasKey(nextLevel):
      return gameConfig.tech.sc.levels[nextLevel].trpCost
  of TechField.FighterDoctrine:
    if gameConfig.tech.fd.levels.hasKey(nextLevel):
      return gameConfig.tech.fd.levels[nextLevel].trpCost
  of TechField.AdvancedCarrierOps:
    if gameConfig.tech.aco.levels.hasKey(nextLevel):
      return gameConfig.tech.aco.levels[nextLevel].trpCost

  return 0 # Level not found or at max

## Research Allocation

proc allocateResearch*(
    allocation: ResearchAllocation, gho: int32, slLevel: int32
): ResearchPoints =
  ## Convert PP allocations to RP
  ##
  ## Args:
  ##   allocation: PP allocated to each category
  ##   gho: Gross House Output (for RP conversion)
  ##   slLevel: Science Level (affects TRP costs)

  result =
    ResearchPoints(economic: 0, science: 0, technology: initTable[TechField, int32]())

  # Convert economic allocation
  if allocation.economic > 0:
    result.economic = convertPPToERP(allocation.economic, gho)

  # Convert science allocation
  if allocation.science > 0:
    result.science = convertPPToSRP(allocation.science, slLevel)

  # Convert technology allocations
  for field, pp in allocation.technology:
    if pp > 0:
      result.technology[field] = convertPPToTRP(pp, field, slLevel, gho)

proc calculateTotalRPInvested*(allocation: ResearchAllocation): int =
  ## Calculate total RP invested (for breakthrough calculation)
  result = allocation.economic + allocation.science

  for pp in allocation.technology.values:
    result += pp
