## Economic Prestige Effects
##
## Prestige modifiers from taxation and blockades

import std/math
import ../types/[core, prestige]
import ../globals
import ./[engine, sources, events]

proc applyTaxPrestige*(
    houseId: HouseId, colonyCount: int, taxRate: int
): PrestigeEvent =
  ## Apply prestige bonus from low tax rate
  ## Per economy.md:3.2.2
  var bonusPerColony: int32 = 0

  if taxRate >= 41:
    bonusPerColony = 0
  elif taxRate >= 31:
    bonusPerColony = 0
  elif taxRate >= 21:
    bonusPerColony = 1
  elif taxRate >= 11:
    bonusPerColony = 2
  else:
    bonusPerColony = 3

  let totalBonus = bonusPerColony * int32(colonyCount)

  return createPrestigeEvent(
    PrestigeSource.LowTaxBonus,
    totalBonus,
    $houseId & " low tax bonus (rate: " & $taxRate & "%)",
  )

proc applyHighTaxPenalty*(houseId: HouseId, taxRate: int): PrestigeEvent =
  ## Apply prestige penalty from high tax rate (exponential formula)
  ## Per economy.md:3.2.1
  let config = gameConfig.prestige.taxPenalty
  var penalty: int32 = 0

  if taxRate > config.threshold:
    let excess = float(taxRate - config.threshold)
    penalty = -int32(floor(config.baseCoefficient * pow(excess, config.exponent)))

  return createPrestigeEvent(
    PrestigeSource.HighTaxPenalty,
    penalty,
    $houseId & " high tax penalty (rate: " & $taxRate & "%)",
  )

proc applyBlockadePenalty*(houseId: HouseId, blockadedColonies: int): PrestigeEvent =
  ## Apply prestige penalty for blockaded colonies
  ## Per operations.md:6.2.6: -2 prestige per blockaded colony per turn
  let penalty =
    applyPrestigeMultiplier(getPrestigeValue(PrestigeSource.BlockadePenalty)) *
    int32(blockadedColonies)

  return createPrestigeEvent(
    PrestigeSource.BlockadePenalty,
    penalty,
    $houseId & " has " & $blockadedColonies & " blockaded colonies",
  )
