## Research Cost Calculation
##
## Calculate PP to RP conversion per ec4x_canonical_turn_cycle.md CMD6e
##
## Conversion formulas (logarithmic scaling - spec is source of truth):
## - ERP: PP * (1 + log₁₀(GHO)/3) * (1 + SL/10)
## - SRP: PP * (1 + log₁₀(GHO)/4) * (1 + SL/5)
## - TRP: PP * (1 + log₁₀(GHO)/3.5) * (1 + SL/20)
##
## Logarithmic scaling provides diminishing returns on economic scale,
## preventing runaway snowball effects while still rewarding growth.

import std/[math, tables]
import ../../types/tech
import ../../globals

export tech.ResearchAllocation

## Economic Research Points (CMD6e)

proc convertPPToERP*(pp: int32, gho: int32, slLevel: int32): int32 =
  ## Convert PP to ERP using logarithmic scaling
  ## Per ec4x_canonical_turn_cycle.md CMD6e:
  ## ERP = PP * (1 + log₁₀(GHO)/3) * (1 + SL/10)
  ##
  ## Logarithmic scaling ensures economic growth provides meaningful
  ## advantages without creating unrecoverable leads.
  let ghoModifier = if gho > 0:
    1.0 + (log10(float(gho)) / 3.0)
  else:
    1.0  # No bonus if GHO is zero
  let slModifier = 1.0 + (float(slLevel) / 10.0)
  result = int32(float(pp) * ghoModifier * slModifier)

proc elUpgradeCost*(currentLevel: int32): int32 =
  ## Get ERP cost to advance Economic Level
  ## Per economy.md:4.2 and config/tech.kdl
  ## Uses Table pattern for levels
  let nextLevel = currentLevel + 1
  if gameConfig.tech.el.levels.hasKey(nextLevel):
    return gameConfig.tech.el.levels[nextLevel].erpCost
  else:
    return 0 # Level not found or at max

proc elModifier*(level: int32): float32 =
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

## Science Research Points (CMD6e)

proc convertPPToSRP*(pp: int32, gho: int32, slLevel: int32): int32 =
  ## Convert PP to SRP using logarithmic scaling
  ## Per ec4x_canonical_turn_cycle.md CMD6e:
  ## SRP = PP * (1 + log₁₀(GHO)/4) * (1 + SL/5)
  ##
  ## Moderate GHO scaling (weaker than ERP), strong SL scaling.
  ## Science research benefits heavily from scientific infrastructure.
  let ghoModifier = if gho > 0:
    1.0 + (log10(float(gho)) / 4.0)
  else:
    1.0  # No bonus if GHO is zero
  let slModifier = 1.0 + (float(slLevel) / 5.0)
  result = int32(float(pp) * ghoModifier * slModifier)

proc slUpgradeCost*(currentLevel: int32): int32 =
  ## Get SRP cost to advance Science Level
  ## Per economy.md:4.3 and config/tech.kdl
  ## Model 2: SL advancement is SRP-only.
  ## Uses Table pattern for levels
  let nextLevel = currentLevel + 1
  if gameConfig.tech.sl.levels.hasKey(nextLevel):
    let levelData = gameConfig.tech.sl.levels[nextLevel]
    # SL uses srpRequired as the cost
    return levelData.srpRequired
  else:
    return 0 # Level not found or at max

proc slModifier*(level: int): float =
  ## Get SL research modifier
  ## Affects TRP costs per economy.md:4.4
  ##
  ## Per the TRP formula: 1 TRP = (5 + 4(SL))/10 + log(GHO) * 0.5 PP
  ## Higher SL increases TRP cost (more advanced science infrastructure)
  ##
  ## This modifier is 5% per SL level (baseline 1.0 at SL0)
  result = 1.0 + (float(level) * 0.05)

## Technology Research Points (CMD6e)

proc convertPPToTRP*(pp: int32, gho: int32, slLevel: int32): int32 =
  ## Convert PP to TRP using logarithmic scaling
  ## Per ec4x_canonical_turn_cycle.md CMD6e:
  ## TRP = PP * (1 + log₁₀(GHO)/3.5) * (1 + SL/20)
  ##
  ## Moderate GHO scaling, modest SL scaling (5% per level).
  ## Advanced research infrastructure provides some benefit to military tech.
  let ghoModifier = if gho > 0:
    1.0 + (log10(float(gho)) / 3.5)
  else:
    1.0  # No bonus if GHO is zero
  let slModifier = 1.0 + (float(slLevel) / 20.0)
  result = int32(float(pp) * ghoModifier * slModifier)

proc techUpgradeCost*(techField: TechField, currentLevel: int32): int32 =
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
  ## Convert PP allocations to RP per CMD6e (logarithmic scaling)
  ##
  ## Args:
  ##   allocation: PP allocated to each category
  ##   gho: Gross House Output (for RP conversion)
  ##   slLevel: Science Level (affects all conversion rates)

  result =
    ResearchPoints(economic: 0, science: 0, technology: initTable[TechField, int32]())

  # Convert economic allocation: ERP = PP * (1 + log₁₀(GHO)/3) * (1 + SL/10)
  if allocation.economic > 0:
    result.economic = convertPPToERP(allocation.economic, gho, slLevel)

  # Convert science allocation: SRP = PP * (1 + log₁₀(GHO)/4) * (1 + SL/5)
  if allocation.science > 0:
    result.science = convertPPToSRP(allocation.science, gho, slLevel)

  # Convert technology allocations: TRP = PP * (1 + log₁₀(GHO)/3.5) * (1 + SL/20)
  for field, pp in allocation.technology:
    if pp > 0:
      result.technology[field] = convertPPToTRP(pp, gho, slLevel)

proc calculateTotalRPInvested*(allocation: ResearchAllocation): int =
  ## Calculate total RP invested (for breakthrough calculation)
  result = allocation.economic + allocation.science

  for pp in allocation.technology.values:
    result += pp
